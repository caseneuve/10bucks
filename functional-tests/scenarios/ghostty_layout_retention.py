"""Repeated same-app stack navigation preserves retained column assignment."""
import time
from scenarios.columns_close_recovery import sampling_gate
from scenarios.ghostty_close_recovery import expected, received

SCENARIO_ID = 'ghostty-layout-retention'
INVARIANTS = ('STACK-002', 'COL-002', 'LAY-003', 'FOCUS-004')


def run(driver, *, clock=time.monotonic, sleep=time.sleep):
    area = driver.preflight()
    eventually = sampling_gate(driver, scenario_id=SCENARIO_ID, clock=clock, sleep=sleep)
    for order in ('A', 'AB', 'ABC'):
        driver.create_ghostty(order[-1])
        groups = ('A',) if order == 'A' else ('A', order[1:])
        selections = ('A',) if order == 'A' else ('A', order[-1])
        eventually('columns create ' + order[-1], expected(area, order, order[-1], groups, selections))
    previous = expected(area, 'ABC', 'C', ('A', 'BC'), ('A', 'C'))
    sequence = (
        ('cycleLayout', 'C', 'stack'),
        ('focusPrevious', 'B', 'stack'), ('focusPrevious', 'A', 'stack'),
        ('focusNext', 'B', 'stack'), ('cycleLayout', 'B', 'columns'),
        ('cycleLayout', 'B', 'stack'), ('focusPrevious', 'A', 'stack'),
        ('focusPrevious', 'C', 'stack'), ('focusNext', 'A', 'stack'),
        ('cycleLayout', 'A', 'columns'),
    )
    for index, (command, focus, layout) in enumerate(sequence, 1):
        # Left selection A, retained right selection B after first reactivation.
        selected = ('A', 'B') if index >= 5 else ('A', 'C')
        after = expected(area, 'ABC', focus, ('A', 'BC'), selected, layout=layout)
        received(driver, eventually, command, previous, after, f'{index:02d} {command} native {focus}')
        previous = after
