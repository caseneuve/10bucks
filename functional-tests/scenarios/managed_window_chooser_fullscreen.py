"""TODO0004 independently admitted unplaced F; real native chooser selection.

Starts candidate on an owned pre-existing fullscreen A, not a fake readiness event.
The regular scenario separately covers retained placement and hidden/minimized rejection.
"""
import time
from scenarios.columns_close_recovery import sampling_gate
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
