"""BUG0001 investigation, not prior-A recovery acceptance.

Each invocation uses a fresh fixture/candidate. No corrective focus after a gate.
Ordering comes from guest wrappers; sampled native outcomes remain independent.
"""
import math
import time
from scenarios.columns_close_recovery import Frame, same_frame, sampling_gate

SCENARIO_ID = 'close-recovery-investigation'
CASES = ('normal', 'excluded', 'deliberate-b', 'deliberate-c')


def ordering_valid(result, case, setup_at):
    """Strict close/control lifetimes after passed excluded-E setup; retain earlier rows."""
    rows = result.get('closeOrdering') or []
    if (not isinstance(setup_at, (int, float)) or not math.isfinite(setup_at)
            or not rows or result.get('closeOrderingDropped') != 0):
        return False
    previous = -1
    for i, row in enumerate(rows, 1):
        at = row.get('at')
        if row.get('sequence') != i or not isinstance(at, (int, float)) or not math.isfinite(at) or at < previous:
            return False
        previous = at
        if at >= setup_at and row.get('id') in ('A', 'B', 'C', 'D', 'E') and row.get('kind') in ('focus', 'ActualFocusChanged', 'destroyed', 'WindowDestroyed'):
            if row.get('exactResource') is not True or row.get('joinedLifetime') is not True:
                return False
    for alias in ('D', 'E'):
        if not any(r.get('boundary') == 'windows.normalized' and r.get('kind') == 'ActualFocusChanged'
                   and r.get('id') == alias and r.get('exactResource') is True for r in rows):
            return False
    for alias in ('DE' if case == 'normal' else 'D'):
        if not any(r.get('boundary') == 'windows.normalized' and r.get('kind') == 'WindowDestroyed'
                   and r.get('id') == alias and r['at'] >= setup_at for r in rows):
            return False
    return True


def run(driver, *, case, clock=time.monotonic, sleep=time.sleep):
    if case not in CASES:
        raise ValueError('unknown investigation case')
    area = driver.preflight()
    left = Frame(area.x, area.y, area.w / 2, area.h)
    right = Frame(area.x + area.w / 2, area.y, area.w / 2, area.h)
    eventually = sampling_gate(driver, scenario_id=SCENARIO_ID, clock=clock, sleep=sleep)

    def check(name, order, groups, focus, *, closed=(), selected=None, active=None, receipt=None):
        observed_target = object()
        def matches(o):
            nonlocal observed_target
            if focus is None and o.focused != observed_target:
                observed_target = o.focused
                return False  # Restart the same fixed stable gate on target change.
            d = o.diagnostics
            investigation = d.get('closeRecovery', {})
            layout = d.get('layouts', {}).get(d.get('layout'), {})
            expected = {a: area for a in order}
            if groups is not None:
                expected = {a: left if i == 0 else right
                            for i, group in enumerate(groups) for a in group}
            return (o.managed == frozenset(order) and d.get('order') == list(order)
                    and o.closed == frozenset(closed) and (focus is None or o.focused in focus)
                    and all(same_frame(o.frames.get(a), frame) for a, frame in expected.items())
                    and set(o.frames) == set(order) | ({'E'} if 'E' in investigation.get('liveExcluded', []) else set())
                    and (groups is None or layout.get('groups') == groups)
                    and (selected is None or layout.get('selected') == selected)
                    and (active is None or layout.get('active') == active)
                    and (receipt is None or o.commands_received.get(receipt[0], 0) == receipt[1])
                    and investigation.get('instrumented') is True
                    and investigation.get('orderingDropped') == 0
                    and all(investigation.get('exactJoins', {}).get(a) is True for a in set(order) | set(closed) | ({'E'} if 'E' in investigation.get('liveExcluded', []) else set()))
                    and investigation.get('excludedEffects') == {'frame': 0, 'focus': 0}
                    and 'E' not in investigation.get('history', [])
                    and 'E' not in investigation.get('localHistory', [])
                    and investigation.get('excludedSafety') is False
                    and investigation.get('excludedFocusRequests') == 0
                    and ('E' not in investigation.get('liveExcluded', [])
                         or same_frame(o.frames.get('E'), Frame(**investigation['excludedFrame']))))
        return eventually(name, matches)

    for alias, order in (('A', 'A'), ('B', 'AB'), ('C', 'ABC')):
        driver.create(alias)
        check('create ' + alias, order, None, {alias})
    before = check('columns receipt baseline', 'ABC', None, {'C'})
    driver.hotkey('cycleLayout')
    after = check('columns A,B | C', 'ABC', [['A', 'B'], ['C']], {'C'}, selected=['B', 'C'], active=2,
                  receipt=('cycleLayout', before.commands_received.get('cycleLayout', 0) + 1))
    before = after.commands_received.get('focusLeftGroup', 0)
    driver.hotkey('focusLeftGroup')
    after = check('left B', 'ABC', [['A', 'B'], ['C']], {'B'}, selected=['B', 'C'], active=1,
                  receipt=('focusLeftGroup', before + 1))
    before = after.commands_received.get('focusPrevious', 0)
    driver.hotkey('focusPrevious')
    check('baseline A,B | C actual A', 'ABC', [['A', 'B'], ['C']], {'A'}, selected=['A', 'C'], active=1,
          receipt=('focusPrevious', before + 1))
    driver.create('D')
    managed_d = check('managed D actual D', 'ABCD', [['A', 'B', 'D'], ['C']], {'D'}, selected=['D', 'C'], active=1)
    driver.create('E')  # Exact generic fixture title exclusion, not app-origin policy.
    excluded_e = check('excluded E preserves selection', 'ABCD', [['A', 'B', 'D'], ['C']], {'E'}, selected=['D', 'C'], active=1)
    for field in ('history', 'localHistory'):
        assert excluded_e.diagnostics['closeRecovery'][field] == managed_d.diagnostics['closeRecovery'][field]

    closed = []
    intervening = None
    final_selected = None
    if case == 'normal':
        driver.close('E'); closed.append('E')
        # Capture actual native fallback without assuming it returns to D.
        intervening = check('E closed native fallback observed', 'ABCD', [['A', 'B', 'D'], ['C']], None, closed=closed)
        expected_focus = None
    elif case.startswith('deliberate-'):
        target = case[-1].upper()
        driver.fixture_action('focus', target)  # Planned control after a passed gate.
        check('deliberate ' + target, 'ABCD', [['A', 'B', 'D'], ['C']], {target},
              selected=[target if target == 'B' else 'D', 'C'], active=1 if target == 'B' else 2)
        expected_focus = {target}
        final_selected = ['B', 'C']
    else:
        expected_focus = None
    before_close = driver.observe()
    driver.record('immediately before D close', before_close)
    if case.startswith('deliberate-'):
        columns = before_close.diagnostics['layouts']['columns']
        assert before_close.focused == target and columns['active'] == (1 if target == 'B' else 2)
        assert columns['selected'] == ([target, 'C'] if target == 'B' else ['D', 'C'])
    driver.close('D'); closed.append('D')
    final = check('D closed final native target (investigation)', 'ABC', [['A', 'B'], ['C']],
                  expected_focus, closed=closed, selected=final_selected)
    driver.investigation_record({'case': case, 'nativeFinalTarget': final.focused,
                                 'managedDSetupAt': managed_d.sampled_at,
                                 'managedDSetupSample': managed_d.sample_id,
                                 'excludedESetupAt': excluded_e.sampled_at,
                                 'sample': final.sample_id, 'priorAAcceptance': False,
                                 'postECloseTarget': intervening.focused if intervening else None,
                                 'postECloseSample': intervening.sample_id if intervening else None,
                                 'immediatelyBeforeDCloseTarget': before_close.focused,
                                 'immediatelyBeforeDCloseSample': before_close.sample_id,
                                 'immediatelyBeforeDCloseAt': before_close.sampled_at,
                                 'postECloseAt': intervening.sampled_at if intervening else None,
                                 'postECloseAck': intervening.diagnostics['closeRecovery']['lastAck'] if intervening else None,
                                 'finalColumns': final.diagnostics['layouts']['columns'],
                                 'qualification': '250ms settled checkpoints; delivered ordering is not physical causality'})
