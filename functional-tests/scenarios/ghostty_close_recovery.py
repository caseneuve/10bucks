"""Real Ghostty shell-exit recovery; no navigation/focus repair after Ctrl-D."""
import time

from scenarios.columns_close_recovery import Frame, sampling_gate, same_frame

SCENARIO_ID = 'ghostty-close-recovery'
INVARIANTS = ('WIN-005', 'COL-005', 'FOCUS-004', 'FOCUS-005')


def run(driver, *, clock=time.monotonic, sleep=time.sleep):
    area = driver.preflight()
    left = Frame(area.x, area.y, area.w / 2, area.h)
    right = Frame(area.x + area.w / 2, area.y, area.w / 2, area.h)
    eventually = sampling_gate(driver, scenario_id=SCENARIO_ID, clock=clock, sleep=sleep)

    def expected(order, focused, groups, selected, *, closed=(), recovered=False):
        def matches(o):
            columns = o.diagnostics.get('layouts', {}).get('columns', {})
            frames = {alias: (area if len(order) == 1 else left if alias == 'A' else right)
                      for alias in order}
            return (set(o.frames) == set(order)
                    and all(same_frame(o.frames.get(a), f) for a, f in frames.items())
                    and o.focused == focused and o.managed == frozenset(order)
                    and o.closed == frozenset(closed)
                    and o.diagnostics.get('order') == list(order)
                    and o.diagnostics.get('layout') == 'columns'
                    and columns.get('groups') == [list(g) for g in groups]
                    and columns.get('selected') == list(selected)
                    and columns.get('active') == (1 if focused == 'A' else 2)
                    and columns.get('ratio') == .5
                    and (not recovered or o.diagnostics.get('ghosttyAXInvalid') is True))
        return matches

    driver.create_ghostty('A')
    eventually('Ghostty A full width', expected('A', 'A', ('A',), ('A',)))
    driver.create_ghostty('B')
    split = expected('AB', 'B', ('A', 'B'), ('A', 'B'))
    eventually('Ghostty A left B right', split)
    eventually('Ghostty creation fresh native baseline', split)
    driver.create_ghostty('C')
    occupied = expected('ABC', 'C', ('A', 'BC'), ('A', 'C'))
    eventually('real Ghostty C right and focused', occupied)
    eventually('Ctrl-D fresh exact C focus baseline', occupied)
    driver.close_ghostty()
    eventually('Ctrl-D exact C invalid removed B focused no repair',
               expected('AB', 'B', ('A', 'B'), ('A', 'B'), closed=('C',), recovered=True))
