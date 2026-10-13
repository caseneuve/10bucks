"""Deterministic oracle negatives; these are NOT native platform evidence."""
from collections import Counter
from copy import deepcopy
import unittest

from scenarios.columns_close_recovery import AcceptanceFailure, Frame, Observation
from scenarios.desktop_switching import run, SWITCHES, TOPOLOGY, fullscreen
from benchmarks.desktop_switching import benchmark, nearest_rank, summarize_batches


class Driver:
    def __init__(self, defect=None):
        self.time = 0
        self.sid = 0
        self.order = ''
        self.layout = 'columns'
        self.focus = None
        self.ratio = .5
        self.stack = None
        self.active = 'D1'
        self.previous = None
        self.receipts = {}
        self.trace = []
        self.events = []
        self.scopes = {}
        self.actions = []
        self.switch_index = 0
        self.defect = defect
        self.result = None
        self.benchmark_mode = False

    def clock(self): return self.time
    def sleep(self, duration): self.time += duration
    def preflight(self): return Frame(10, 20, 1000, 700)
    def record(self, name, observation): pass
    def benchmark_record(self, result): self.result = result

    def create(self, alias):
        assert self.active == 'D1'
        self.order += alias
        self.focus = alias
        self.actions.append(('create', alias))

    def close(self, alias): raise AssertionError('no fixture close/repair in this scenario')

    def receipt(self, name):
        self.events.append({'kind': 'posted', 'name': name, 'at': self.time})
        self.time += .001
        self.receipts[name] = self.receipts.get(name, 0) + 1
        if self.defect == 'undelivered' and name == 'focusDesktop9': self.receipts[name] -= 1
        self.events.append({'kind': 'callback', 'name': name, 'at': self.time})

    def scope(self):
        columns = {'groups': [['A'], list(self.order[1:])] if len(self.order) > 1 else [list(self.order)] if self.order else [],
                   'selected': ['A', 'C'] if self.order == 'ABC' else list(self.order),
                   'active': 2 if len(self.order) > 1 else 1, 'ratio': self.ratio}
        layouts = {'columns': columns}
        if self.stack: layouts['stack'] = deepcopy(self.stack)
        return {'order': list(self.order), 'layout': self.layout, 'layouts': layouts, 'active': self.active == 'D1'}

    def switch(self, commands, target, destinations):
        old = self.active
        # Save source state without resetting hidden layout state.
        self.scopes['D1'] = self.scope()
        for name in commands: self.receipt(name)
        if self.defect == 'wrong-desktop': target = old
        for destination in destinations:
            gen = len(self.trace) + 1
            for kind in ('switchRegularSpace', 'RegularSwitchPressed', 'confirmed'):
                at = self.time + {'switchRegularSpace': 0, 'RegularSwitchPressed': .3, 'confirmed': .4}[kind]
                # First request occurs inside first callback before subsequent receipts.
                if kind == 'switchRegularSpace' and destination == destinations[0]: at -= .001 * (len(commands) - 1)
                self.trace.append({'kind': kind, 'at': at, 'source': self.active,
                                   'destination': destination, 'generation': gen})
            self.previous, self.active = self.active, destination
            self.time += .4
            self.scopes.setdefault(destination, {'order': [], 'layout': 'stack', 'layouts': {}})
        self.active = target
        if self.defect == 'early-history': self.previous = target
        if self.defect == 'unserialized' and len(destinations) == 2:
            self.trace[-3]['at'] = self.trace[-4]['at'] - .1
        if self.defect == 'late-burst' and len(commands) > 1:
            self.events[-1]['at'] = self.time + 1
        self.switch_index += 1

    def hotkey(self, command):
        self.actions.append(('key', command))
        if command == 'benignService':
            self.benchmark_mode = True; self.receipt(command); return
        if self.benchmark_mode and command in ('focusDesktop1', 'focusDesktop2'):
            target = 'D1' if command == 'focusDesktop1' else 'D2'
            self.switch((command,), target, (target,)); return
        if command.startswith('focusDesktop') or command in ('focusPreviousDesktop', 'focusNextDesktop', 'focusPreviousDesktopPosition'):
            commands, target, destinations = SWITCHES[self.switch_index]
            assert commands == (command,)
            self.switch(commands, target, destinations)
            return
        self.receipt(command)
        if command == 'resizeRight': self.ratio = .55
        elif command == 'cycleLayout':
            self.layout = 'stack' if self.layout == 'columns' else 'columns'
            self.stack = {'members': list('ABC'), 'selected': self.focus}
        elif command == 'focusPrevious': self.focus = 'B'; self.stack['selected'] = 'B'
        elif command == 'focusNext': self.focus = 'C'; self.stack['selected'] = 'C'

    def hotkey_burst(self, commands):
        self.actions.append(('burst', tuple(commands)))
        if 'benignService' in commands:
            target = 'D2' if commands[0] == 'focusDesktop2' else 'D1'
            self.switch(commands, target, (target,))
        else:
            expected, target, destinations = SWITCHES[self.switch_index]
            assert tuple(commands) == expected
            self.switch(commands, target, destinations)

    def observe(self):
        self.time += .001
        self.sid += 1
        area = self.preflight()
        frames = {a: area for a in self.order}
        if self.layout == 'columns' and len(self.order) > 1:
            frames = {a: Frame(10, 20, 1000 * self.ratio, 700) if a == 'A' else
                      Frame(10 + 1000 * self.ratio, 20, 1000 * (1 - self.ratio), 700) for a in self.order}
        native = dict(deepcopy(TOPOLOGY), active=self.active)
        scopes = deepcopy(self.scopes)
        scopes['D1'] = self.scope()
        if self.defect in ('inactive-ratio', 'inactive-order', 'inactive-selection', 'inactive-stack') and self.active != 'D1':
            d1 = scopes['D1']
            if self.defect == 'inactive-ratio': d1['layouts']['columns']['ratio'] = .5
            if self.defect == 'inactive-order': d1['order'].reverse()
            if self.defect == 'inactive-selection': d1['layouts']['columns']['selected'] = ['A', 'B']
            if self.defect == 'inactive-stack': d1['layouts']['stack']['members'].reverse()
        if self.defect == 'created-missing' and self.switch_index >= 5: native['count'] = 4
        if self.defect == 'reordered' and self.switch_index: native['order'].reverse()
        if self.defect == 'geometry' and self.switch_index and self.active == 'D1': frames['A'] = area
        diagnostics = {'nativeDesktop': native, 'workspace': {'active': self.active,
                       'history': {'current': self.active, 'previous': self.previous}},
                       'retained': scopes, 'workspaceTrace': deepcopy(self.trace), 'keyEvents': deepcopy(self.events),
                       'layout': self.layout, 'order': list(self.order), 'layouts': self.scope()['layouts']}
        focused = self.focus if self.active == 'D1' else None
        if self.defect == 'native-focus' and self.switch_index and self.active == 'D1': focused = 'A'
        return Observation(self.sid, self.time, self.time, frames, focused, frozenset(),
                           frozenset(self.order if self.active == 'D1' else ''),
                           dict(self.receipts), diagnostics)


class FullscreenDriver(Driver):
    """Oracle fixture only: place F1 between D1 and D2 to expose raw AX indexing."""
    def __init__(self, defect=None):
        super().__init__(defect)
        self.full = False
        self.fullscreen_actions = []
        self.recorded = []
        self.fullscreen_backup = None

    def record(self, name, observation): self.recorded.append((name, observation))

    def fixture_fullscreen(self, enabled):
        self.fullscreen_actions.append(enabled)
        self.full = enabled
        if enabled:
            self.fullscreen_backup = self.previous
            self.previous = 'D1'
        self.active = 'F1' if enabled else 'D1'
        if not enabled and self.defect == 'exit-wrong-desktop': self.active = 'D2'

    def hotkey(self, command):
        self.actions.append(('key', command))
        self.fullscreen_switch((command,))

    def hotkey_burst(self, commands):
        self.actions.append(('burst', tuple(commands)))
        self.fullscreen_switch(commands)

    def fullscreen_switch(self, commands):
        source = self.active
        command = commands[0]
        target = self.previous if command == 'focusPreviousDesktop' else 'D2' if command == 'focusDesktop2' else 'D1'
        for name in commands: self.receipt(name)
        if self.defect == 'raw-index' and source == 'F1': target = 'F1'
        if self.defect == 'wrong-regular-position' and command == 'focusPreviousDesktop' and source == 'D1': target = 'D3'
        if self.defect == 'undelivered-zero' and len(commands) == 2: self.receipts[command] -= 1
        gen = len(self.trace) + 1
        if source == 'F1':
            self.trace.append({'kind': 'pressContextRebased', 'at': self.time + .1, 'source': source,
                               'destination': target, 'generation': gen})
            if self.defect == 'rebase-as-confirmation': self.trace[-1]['kind'] = 'confirmed'
        for kind, delay in (('switchRegularSpace', 0), ('RegularSwitchPressed', .3), ('confirmed', .4)):
            at = self.time + delay - (.001 * (len(commands) - 1) if kind == 'switchRegularSpace' else 0)
            self.trace.append({'kind': kind, 'at': at, 'source': source,
                               'destination': target, 'generation': gen})
        self.time += .4
        self.previous, self.active = (self.fullscreen_backup if source == 'F1' else source), target
        if source == 'F1' and self.defect == 'backup-lost': self.previous = 'D1'
        if len(commands) == 2 and self.defect == 'late-zero': self.events[-1]['at'] = self.time + 1

    def observe(self):
        o = super().observe()
        d = o.diagnostics
        if self.full:
            d['nativeDesktop'] = {'active': self.active, 'order': ['D1', 'F1', 'D2', 'D3'],
                                  'types': ['user', 'fullscreen', 'user', 'user'],
                                  'regular': ['D1', 'D2', 'D3'], 'count': 4}
            if self.defect == 'unjoined': d['nativeDesktop']['order'][1] = 'unknown'
            if self.defect == 'wrong-type': d['nativeDesktop']['types'][1] = 'user'
        d['fixtureNative'] = {'A': {'fullscreen': self.full, 'spaces': ['F1' if self.full else 'D1']}} if self.order else {}
        row = d['retained']['D1']
        row['nativeFullscreen'] = ['A'] if self.full else []
        row['unavailable'] = ['A'] if self.full else []
        if self.full and self.defect == 'lost-slot': row['order'] = []
        if self.full and self.defect == 'available-full': row['unavailable'] = []
        if self.active == 'F1':
            d['workspace'] = {'history': {'current': 'D1', 'previous': 'D1'}}
            if self.defect == 'fullscreen-history': d['workspace']['history']['previous'] = 'D2'
        focused = 'A' if self.active in ('D1', 'F1') and self.order else None
        if not self.full and len(self.fullscreen_actions) == 2 and self.defect == 'exit-unmanaged-focus': focused = None
        if self.full and self.defect == 'entry-focus' and self.active == 'F1': focused = None
        frames = dict(o.frames)
        if not self.full and len(self.fullscreen_actions) == 2 and self.defect == 'exit-frame': frames['A'] = Frame(1, 1, 1, 1)
        return Observation(o.sample_id, o.sampled_at, o.observed_at, frames, focused,
                           o.closed, o.managed, o.commands_received, d)


class DesktopChecks(unittest.TestCase):
    def test_complete_sequence_and_real_burst_boundary(self):
        d = Driver()
        run(d, clock=d.clock, sleep=d.sleep)
        self.assertEqual(d.switch_index, len(SWITCHES))
        self.assertEqual(d.active, 'D1')
        self.assertEqual([a for a in d.actions if a[0] == 'create'], [('create', a) for a in 'ABC'])
        self.assertEqual([a[1] for a in d.actions if a[0] == 'burst'], [s[0] for s in SWITCHES if len(s[0]) > 1])
        self.assertLess(d.time, 55)

    def test_authority_retention_and_delivery_negatives(self):
        for defect in ('wrong-desktop', 'created-missing', 'reordered', 'undelivered', 'early-history',
                       'unserialized', 'late-burst', 'inactive-ratio', 'inactive-order',
                       'inactive-selection', 'inactive-stack', 'native-focus', 'geometry'):
            with self.subTest(defect=defect):
                d = Driver(defect)
                with self.assertRaises(AcceptanceFailure): run(d, clock=d.clock, sleep=d.sleep)

    def test_bounded_warm_and_cold_paths(self):
        for mode, count in (('warm', 10), ('cold', 1)):
            d = Driver()
            benchmark(d, mode=mode, clock=d.clock, sleep=d.sleep)
            self.assertEqual(len(d.result['samples']), count)
            self.assertEqual(d.result['lost'], 0)
            self.assertLess(d.time, 55)

    def test_complete_benchmark_aggregation_rejects_censoring(self):
        batches = []
        for mode, repeats in (('warm', 3), ('cold', 5)):
            for _ in range(repeats):
                d = Driver()
                benchmark(d, mode=mode, clock=d.clock, sleep=d.sleep)
                batches.append(d.result)
        summary = summarize_batches(batches)
        self.assertEqual(summary['warm']['count'], 30)
        self.assertEqual(summary['cold']['count'], 5)
        self.assertTrue(all(row['budgetPassed'] for row in summary.values()))
        with self.assertRaises(AcceptanceFailure): summarize_batches(batches[:-1])
        batches[0]['status'] = 'sampling'
        with self.assertRaises(AcceptanceFailure): summarize_batches(batches)

    def test_separate_fullscreen_sequence(self):
        d = FullscreenDriver()
        fullscreen(d, clock=d.clock, sleep=d.sleep)
        self.assertEqual(d.fullscreen_actions, [True, False])
        self.assertEqual(d.actions, [('create', 'A'), ('key', 'focusDesktop2'), ('key', 'focusDesktop1'),
                                     ('burst', ('focusPreviousDesktop', 'focusPreviousDesktop')),
                                     ('key', 'focusPreviousDesktop'), ('key', 'focusDesktop1')])
        self.assertEqual(sum(r['kind'] == 'RegularSwitchPressed' for r in d.trace), 5)
        self.assertLess(d.time, 55)

    def test_fullscreen_exit_focus_is_observed_not_restoration_acceptance(self):
        d = FullscreenDriver('exit-unmanaged-focus')
        fullscreen(d, clock=d.clock, sleep=d.sleep)
        name, last = d.recorded[-1]
        self.assertIn('focus observed only', name)
        self.assertIsNone(last.focused)
        self.assertNotIn('focus', [action[0] for action in d.actions])

    def test_fullscreen_native_index_and_retention_negatives(self):
        for defect in ('raw-index', 'wrong-regular-position', 'unjoined', 'wrong-type',
                       'lost-slot', 'available-full', 'exit-wrong-desktop', 'entry-focus', 'exit-frame',
                       'rebase-as-confirmation', 'fullscreen-history', 'backup-lost', 'undelivered-zero', 'late-zero'):
            with self.subTest(defect=defect):
                d = FullscreenDriver(defect)
                with self.assertRaises(AcceptanceFailure): fullscreen(d, clock=d.clock, sleep=d.sleep)

    def test_percentile_nearest_rank(self):
        self.assertEqual(nearest_rank(range(1, 31), .95), 29)


if __name__ == '__main__': unittest.main()
