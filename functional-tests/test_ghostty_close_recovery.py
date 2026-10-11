"""Modeled Ghostty recovery oracle checks, NOT real-app acceptance."""
import unittest
import subprocess
from pathlib import Path
from scenarios.columns_close_recovery import AcceptanceFailure, Frame, Observation
from scenarios.ghostty_close_recovery import run


class Driver:
    def __init__(self, defect=None):
        self.time = 0
        self.stage = 0
        self.sid = 0
        self.actions = []
        self.defect = defect

    def clock(self): return self.time
    def sleep(self, duration): self.time += duration
    def preflight(self): return Frame(0, 32, 1000, 700)
    def record(self, name, observation): pass
    def create(self, alias): self.actions.append(('create', alias)); self.stage += 1
    def create_ghostty(self, alias): self.actions.append(('createGhostty', alias)); self.stage += 1
    def close_ghostty(self): self.actions.append(('closeGhostty', 'C')); self.stage = 4

    def observe(self):
        self.time += .001; self.sid += 1
        order = 'A' if self.stage == 1 else 'ABC' if self.stage == 3 else 'AB'
        focus = order[-1]
        frames = {a: (self.preflight() if len(order) == 1 else
                      Frame(0 if a == 'A' else 500, 32, 500, 700)) for a in order}
        groups = [['A']] if order == 'A' else [['A'], list(order[1:])]
        closed = {'C'} if self.stage == 4 else set()
        invalid = self.stage == 4
        if self.stage == 4:
            if self.defect == 'dead-member': order = 'ABC'; groups = [['A'], ['B', 'C']]
            if self.defect == 'wrong-focus': focus = 'A'
            if self.defect == 'absence-not-invalid': invalid = False
        d = {'order': list(order), 'layout': 'columns', 'ghosttyAXInvalid': invalid,
             'layouts': {'columns': {'groups': groups, 'selected': ['A'] if order == 'A' else ['A', focus],
                                     'active': 1 if order == 'A' else 2, 'ratio': .5}}}
        return Observation(self.sid, self.time, self.time, frames, focus,
                           frozenset(closed), frozenset(order), {}, d)


class GuestLifecycleChecks(unittest.TestCase):
    def lua(self, body):
        source = Path(__file__).with_name('guest.lua').read_text()
        finalize = source.split('local function finalize()', 1)[1].split('local function cleanupTick()', 1)[0]
        prelude = '''
local present=false
local hs={application={applicationForPID=function() return present and {} or nil end},
 mouse={absolutePosition=function() end},hotkey={}}
local function claimsAbsent() return true end
local function atomic() end
local s
local function fresh()
 s={running=true,cleanup={candidateStopped=true},exitCode=0,quitAck=true,
 outputDir='/unused',trace={},task={isRunning=function() return false end}}
end
'''
        result = subprocess.run(['lua', '-'], input=prelude + '\nlocal function finalize()' + finalize + body,
                                text=True, capture_output=True, timeout=5)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_open_exit_before_app_discovery_is_unresolved(self):
        self.lua('''
fresh(); s.ghosttyLaunchSubmitted=true; s.ghosttyExit=0
finalize(); assert(not s.cleanup.ok and not s.cleanup.ghosttyExited)
-- Delayed app must first be independently discovered, then exit.
fresh(); s.ghosttyLaunchSubmitted=true; s.ghosttyExit=0
s.ghosttyApp={}; s.ghosttyPid=42; s.ghosttyLaunchResolved=true
present=true; finalize(); assert(not s.cleanup.ok)
fresh(); s.ghosttyLaunchSubmitted=true; s.ghosttyExit=0
s.ghosttyApp={}; s.ghosttyPid=42; s.ghosttyLaunchResolved=true
present=false; finalize(); assert(s.cleanup.ok)
''')

    def test_forced_nonzero_or_pending_launcher_cannot_pass(self):
        self.lua('''
for _,mode in ipairs({'forced','nonzero','pending'}) do
 fresh(); s.ghosttyLaunchSubmitted=true; s.ghosttyLaunchResolved=true
 s.ghosttyApp={}; s.ghosttyPid=42; s.ghosttyExit=0
 if mode=='forced' then s.ghosttyLaunchForced=true
 elseif mode=='nonzero' then s.ghosttyExit=1
 else s.ghosttyExit=nil end
 finalize(); assert(not s.cleanup.ok,mode)
end
''')

    def test_queued_observers_are_bound_to_session_and_owner(self):
        source = Path(__file__).with_name('guest.lua').read_text()
        callback = source.split('s.observers[pid]:callback(function(_,element,notification)', 1)[1].split('\n        end)', 1)[0]
        body = '''
local s={running=true,phase='active',axes={A={},C={}},ownerPids={A=1,C=2},destroyed={}}
local old=s
local function observer(pid)
 local owner=s
 return function(_,element,notification)
''' + callback + '''
 end
end
local first,second=observer(1),observer(2)
first(nil,old.axes.C,'AXUIElementDestroyed'); assert(not old.destroyed.C)
second(nil,old.axes.C,'AXUIElementDestroyed'); assert(old.destroyed.C)
old.destroyed={}; old.running=false
first(nil,old.axes.A,'AXUIElementDestroyed'); assert(not old.destroyed.A)
s={running=true,phase='active',axes=old.axes,ownerPids=old.ownerPids,destroyed={}}
first(nil,old.axes.A,'AXUIElementDestroyed'); second(nil,old.axes.C,'AXUIElementDestroyed')
assert(not s.destroyed.A and not s.destroyed.C and not old.destroyed.A)
'''
        result = subprocess.run(['lua','-'], input=body, text=True, capture_output=True, timeout=5)
        self.assertEqual(result.returncode, 0, result.stderr)


class Checks(unittest.TestCase):
    def test_sequence_has_no_navigation_repair(self):
        driver = Driver(); run(driver, clock=driver.clock, sleep=driver.sleep)
        self.assertEqual(driver.actions, [('createGhostty', 'A'), ('createGhostty', 'B'),
                                         ('createGhostty', 'C'), ('closeGhostty', 'C')])

    def test_recovery_requires_invalidity_membership_and_native_focus(self):
        for defect in ('dead-member', 'wrong-focus', 'absence-not-invalid'):
            with self.subTest(defect=defect):
                driver = Driver(defect)
                with self.assertRaises(AcceptanceFailure):
                    run(driver, clock=driver.clock, sleep=driver.sleep)


if __name__ == '__main__': unittest.main()
