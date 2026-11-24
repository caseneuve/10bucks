"""TODO0004 independently admitted unplaced F; real native chooser selection.

Starts candidate on an owned pre-existing fullscreen A, not a fake readiness event.
The regular scenario separately covers retained placement and hidden/minimized rejection.
"""
import time
from scenarios.columns_close_recovery import sampling_gate
from scenarios.desktop_switching import trace_check
from scenarios.managed_window_chooser import checkpoint

SCENARIO_ID = 'managed-window-chooser-fullscreen'
INVARIANTS = ('CHOOSE-001', 'FOCUS-003', 'FOCUS-006', 'FS-002', 'FS-005', 'STATE-002')


def run(driver, *, clock=time.monotonic, sleep=time.sleep):
    driver.preflight()
    gate = sampling_gate(driver, scenario_id=SCENARIO_ID, clock=clock, sleep=sleep)
    completions = []

    def check(name, **kw):
        expected = checkpoint(['A', 'C'], completion=completions,
                              native={'A': {'fullscreen': True, 'minimized': False, 'hidden': False}}, **kw)
        return gate(name, lambda o: o.diagnostics.get('chooser', {}).get('fullscreenUnplaced') is True
                    and o.diagnostics.get('chooser', {}).get('fullscreenNoPlacement') is True
                    and all('A' not in scope.get('order', []) for scope in o.diagnostics.get('retained', {}).values())
                    and expected(o))

    gate('independent pre-existing fullscreen admission without regular slot',
         lambda o: o.focused == 'A' and o.diagnostics.get('nativeDesktop', {}).get('active') == 'F1'
         and o.diagnostics.get('chooser', {}).get('fullscreenNoPlacement') is True)
    driver.hotkey('focusDesktop1')
    gate('planned regular Space setup', lambda o: o.diagnostics.get('nativeDesktop', {}).get('active') == 'D1')
    driver.create('C')
    check('regular C setup with fullscreen A preserved', visible=False, focus='C', desktop='D1')
    for name in ('cross-Space unplaced fullscreen', 'unchanged fullscreen'):
        before = check(name + ' baseline', visible=False)
        driver.hotkey('chooseWindow')
        check(name + ' real visible cached rows', receipt=('chooseWindow', before.commands_received.get('chooseWindow', 0)+1))
        driver.hotkey('chooserEnterService')
        completions.append({'alias': 'A', 'accepted': True})
        check(name + ' exact native focus and fullscreen Space', visible=False, focus='A', desktop='F1', pending=False)
    # Benign key posted immediately after Enter measures queued main-thread service,
    # not physical input or an independently timed sender during blocking work.
    check('queued benign hotkeys received', visible=False, focus='A', desktop='F1',
          receipt=('benignService', 2))
    # Leave UI open to exercise ordinary chooser/native/observer/worker cleanup.
    driver.hotkey('chooseWindow')
    check('cleanup owns open fullscreen chooser')


def previous_desktop_visit(driver, *, excluded=False, clock=time.monotonic, sleep=time.sleep):
    """SPACE-005: visit an already existing fullscreen Space, then toggle 0 twice."""
    driver.preflight()
    case = 'excluded-owner' if excluded else 'chooser-visit'
    gate = sampling_gate(driver, scenario_id='previous-desktop-' + case, clock=clock, sleep=sleep)
    native_a = {'A': {'fullscreen': True, 'minimized': False, 'hidden': False,
                      'identityMatch': True, 'owner': 'F1'}}
    initial_topology = None

    def check(name, desktop, *, previous=None, fullscreen_return=False, **kwargs):
        expected = checkpoint(['A', 'C'], desktop=desktop, native=native_a, **kwargs)

        def matches(o):
            n = o.diagnostics.get('nativeDesktop', {})
            order, types = n.get('order', []), n.get('types', [])
            history = o.diagnostics.get('workspace', {}).get('history', {})
            if fullscreen_return:
                start = len(last.diagnostics['workspaceTrace'])
                before = last.diagnostics['instrumentation']['counts'].get('focusRequests', 0)
                after = o.diagnostics['instrumentation']['counts'].get('focusRequests', 0)
                if before != after or not trace_check(o, start, ('focusPreviousDesktop',), ('F1',), source='D1'):
                    return False
            return (expected(o) and (not excluded or
                    o.diagnostics.get('chooser', {}).get('fullscreenExcludedOwner') is True)
                    and (previous is None or history == {'current': desktop, 'previous': previous})
                    and n.get('count') == len(order) == len(types) == 4
                    and n.get('regular') == ['D1', 'D2', 'D3']
                    and set(order) == {'F1', 'D1', 'D2', 'D3'}
                    and all(t == ('fullscreen' if a == 'F1' else 'user') for a, t in zip(order, types))
                    and (initial_topology is None or order == initial_topology))

        return gate(name, matches)

    last = check('setup: exact native A already fullscreen before D2', 'F1', visible=False, focus='A')
    initial_topology = last.diagnostics['nativeDesktop']['order']

    def press(command):
        count = last.commands_received.get(command, 0) + 1
        driver.hotkey(command)
        return (command, count)

    if excluded:
        last = check('D1 after leaving existing excluded-owner F1', 'D1', visible=False,
                     previous='F1', receipt=press('focusDesktop1'))
        check('one previous returns to exact excluded-owner F1', 'F1', visible=False, focus='A',
              previous='D1', fullscreen_return=True, receipt=press('focusPreviousDesktop'))
        return

    for target, previous in (('D2', 'F1'), ('D1', 'D2')):
        last = check('native ' + target + ' while A remains fullscreen on F1', target, visible=False,
                     previous=previous, receipt=press('focusDesktop' + target[-1]))
    driver.create('C')
    last = check('regular C focused on D1 before fullscreen visit', 'D1', visible=False, focus='C')
    check('real chooser shows exact existing A as first row on D1', 'D1', receipt=press('chooseWindow'))
    driver.hotkey('chooserEnter')
    completions = [{'alias': 'A', 'accepted': True}]
    last = check('visit existing F1: native F1 and exact focus A', 'F1', visible=False, focus='A',
                 previous='D1', completion=completions, pending=False)
    last = check('one previous from F1 returns to native D1', 'D1', visible=False,
                 previous='F1', receipt=press('focusPreviousDesktop'), completion=completions, pending=False)
    check('one previous from D1 returns to existing native F1 and exact focus A', 'F1', visible=False,
          previous='D1', fullscreen_return=True, receipt=press('focusPreviousDesktop'), focus='A',
          completion=completions, pending=False)
