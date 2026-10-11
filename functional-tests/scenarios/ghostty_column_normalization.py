"""Same-app close normalizes an emptied column without navigation repair."""
import time
from scenarios.columns_close_recovery import sampling_gate
from scenarios.ghostty_close_recovery import expected, received

SCENARIO_ID = 'ghostty-column-normalization'
INVARIANTS = ('COL-005', 'COL-007', 'LAY-003', 'WIN-005', 'FOCUS-004')


def run(driver, *, clock=time.monotonic, sleep=time.sleep):
    area = driver.preflight()
    eventually = sampling_gate(driver, scenario_id=SCENARIO_ID, clock=clock, sleep=sleep)
    for order in ('A', 'AB', 'ABC'):
        driver.create_ghostty(order[-1])
        eventually('stack create ' + order[-1], expected(area, order, order[-1], (), (), layout='stack'))
    previous = expected(area, 'ABC', 'C', (), (), layout='stack')
    for target in ('B', 'A'):
        after = expected(area, 'ABC', target, (), (), layout='stack')
        received(driver, eventually, 'focusPrevious', previous, after, 'stack previous ' + target)
        previous = after
    after = expected(area, 'ABC', 'A', ('AB', 'C'), ('A', 'C'))
    received(driver, eventually, 'cycleLayout', previous, after, 'columns preserve A')
    occupied = expected(area, 'ABC', 'C', ('AB', 'C'), ('A', 'C'))
    received(driver, eventually, 'focusRightGroup', after, occupied, 'right native C')
    eventually('Ctrl-D fresh exact C focus baseline', occupied)
    driver.close_ghostty()
    eventually('empty right normalized native B no repair',
               expected(area, 'AB', 'B', ('A', 'B'), ('A', 'B'), closed=('C',), recovered=True))
