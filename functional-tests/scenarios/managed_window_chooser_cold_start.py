"""DISC-001 ordinary regular cold-start discovery, without post-start discovery visits.

Driver readiness means the bounded startup attempt settled, not complete inventory.
Fixture A/D1 and B/D2 exist before start; unavailable startup discovery is deferred.
"""
import time
import math
from scenarios.columns_close_recovery import Frame, sampling_gate, same_frame

SCENARIO_ID = 'managed-window-chooser-cold-start'
INVARIANTS = ('DISC-001', 'CHOOSE-001', 'CHOOSE-002', 'FOCUS-005', 'FOCUS-006')


def checkpoint(*, visible, selected=False, receipt=None):
    def matches(o):
        d = o.diagnostics.get('coldStart', {})
        chooser = o.diagnostics.get('chooser', {})
        snapshot = chooser.get('nativeSnapshot', {})
        if (snapshot.get('runMatch') is not True or snapshot.get('pidMatch') is not True
                or type(snapshot.get('sequence')) is not int or snapshot['sequence'] <= 0
                or type(snapshot.get('sampled_at')) not in (int, float)
                or not math.isfinite(snapshot['sampled_at'])
                or type(snapshot.get('age')) not in (int, float)
                or not 0 <= snapshot['age'] <= .15
                or not all(math.isfinite(t) for t in (o.sampled_at, o.observed_at))
                or not snapshot['sampled_at'] <= o.sampled_at <= o.observed_at
                or o.observed_at - snapshot['sampled_at'] > .15):
            return False
        if (d.get('setupBeforeStart') is not True or d.get('startupSettled') is not True
                or d.get('setupOwners') != {'A':'D1','B':'D2'}
                or d.get('startupFocusRequests') != 0
                or d.get('postStartSpaces') != (['D1','D2'] if selected else ['D1'])
                or chooser.get('visible') is not visible or set(o.frames) != {'A','B'}
                or o.closed or d.get('exactResources') != {'A':True,'B':True}):
            return False
        status = d.get('discoveryStatus', {})
        if (status.get('pending') is not False or type(status.get('complete')) is not bool
                or type(status.get('unresolvedCount')) is not int or status['unresolvedCount'] < 0):
            return False
        # Sampled Space history is not proof against every transient visit.
        if not selected and not visible and (o.focused != 'A'
                or o.diagnostics.get('nativeDesktop', {}).get('active') != 'D1'):
            return False
        if visible:
            rows = chooser.get('rows', [])
            if (len(rows) != 2 or {row.get('alias') for row in rows} != {'A','B'}
                    or any(row.get('text') != '10bucks fixture ' + row.get('alias','')
                           or row.get('subText') != '10bucks Fixture' for row in rows)
                    or chooser.get('query') != ''):
                return False
        if selected:
            if ((not visible and o.focused != 'B') or chooser.get('pending') is not False
                    or chooser.get('completions') != [{'alias':'B','accepted':True}]
                    or o.diagnostics.get('nativeDesktop', {}).get('active') != 'D2'):
                return False
            area = d.get('workArea')
            if area is None or not same_frame(o.frames['B'], Frame(**area) if isinstance(area, dict) else area):
                return False
        if receipt and o.commands_received.get(receipt[0],0) != receipt[1]:
            return False
        return True
    return matches


def run(driver, *, clock=time.monotonic, sleep=time.sleep):
    driver.preflight()
    gate = sampling_gate(driver, scenario_id=SCENARIO_ID, clock=clock, sleep=sleep)
    before = gate('bounded startup attempt settled without focus or Space requests', checkpoint(visible=False))
    driver.hotkey('chooseWindow')
    opened = gate('first native chooser contains both pre-existing regular windows',
                  checkpoint(visible=True, receipt=('chooseWindow', before.commands_received.get('chooseWindow',0)+1)))
    # Public visible rank only: no bootstrap ordering assumption or ID callback.
    rank = next(i for i,row in enumerate(opened.diagnostics['chooser']['rows'],1) if row['alias']=='B')
    driver.hotkey('chooserCmd' + str(rank))
    selected = gate('explicit native ranked choice enters D2 and focuses exact B', checkpoint(visible=False, selected=True))
    driver.hotkey('chooseWindow')
    gate('normal D2 activation retains both confirmed cached rows',
         checkpoint(visible=True, selected=True,
                    receipt=('chooseWindow', selected.commands_received.get('chooseWindow',0)+1)))
    driver.hotkey('chooserCancel')
    gate('D2 chooser cancellation retains exact native B', checkpoint(visible=False, selected=True))
