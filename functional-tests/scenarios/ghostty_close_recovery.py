"""Real Ghostty shell-exit recovery; no navigation/focus repair after Ctrl-D."""
import time
from scenarios.columns_close_recovery import Frame, sampling_gate, same_frame

SCENARIO_ID = 'ghostty-close-recovery'
INVARIANTS = ('WIN-005', 'COL-005', 'FOCUS-004', 'FOCUS-005')


def expected(area, order, focused, groups, selected, *, layout='columns',
             closed=(), recovered=False):
    """Independent native geometry plus exact active layout diagnostics."""
    frames = {alias: area for alias in order}
    if layout == 'columns' and len(groups) == 2:
        frames = {alias: Frame(area.x + index * area.w / 2, area.y, area.w / 2, area.h)
                  for index, group in enumerate(groups) for alias in group}
    def matches(o):
        layouts = o.diagnostics.get('layouts', {})
        columns, stack = layouts.get('columns', {}), layouts.get('stack', {})
        layout_match = (stack.get('members') == list(order) and stack.get('selected') == focused
                        if layout == 'stack' else
                        columns.get('selected') == list(selected)
                        and columns.get('active') == next(i + 1 for i, g in enumerate(groups) if focused in g))
        retained = ('columns' not in layouts if not groups else
                    columns.get('groups') == [list(g) for g in groups] and columns.get('ratio') == .5
                    and (layout != 'stack' or columns.get('selected') == list(selected)))
        return (set(o.frames) == set(order)
                and all(same_frame(o.frames.get(a), f) for a, f in frames.items())
                and o.focused == focused and o.managed == frozenset(order)
                and o.closed == frozenset(closed)
                and o.diagnostics.get('order') == list(order)
                and o.diagnostics.get('layout') == layout and layout_match and retained
                and (not recovered or o.diagnostics.get('ghosttyAXInvalid') is True))
    return matches


def received(driver, eventually, command, before, after, name):
    baseline = eventually(name + ' fresh receipt baseline', before)
    count = baseline.commands_received.get(command, 0)
    driver.hotkey(command)
    eventually(name, lambda o: o.commands_received.get(command, 0) == count + 1 and after(o))


def run(driver, *, clock=time.monotonic, sleep=time.sleep):
    area = driver.preflight()
    eventually = sampling_gate(driver, scenario_id=SCENARIO_ID, clock=clock, sleep=sleep)
    driver.create_ghostty('A')
    eventually('Ghostty A full width', expected(area, 'A', 'A', ('A',), ('A',)))
    driver.create_ghostty('B')
    split = expected(area, 'AB', 'B', ('A', 'B'), ('A', 'B'))
    eventually('Ghostty A left B right', split)
    eventually('Ghostty creation fresh native baseline', split)
    driver.create_ghostty('C')
    occupied = expected(area, 'ABC', 'C', ('A', 'BC'), ('A', 'C'))
    eventually('real Ghostty C right and focused', occupied)
    eventually('Ctrl-D fresh exact C focus baseline', occupied)
    driver.close_ghostty()
    eventually('Ctrl-D exact C invalid removed B focused no repair',
               expected(area, 'AB', 'B', ('A', 'B'), ('A', 'B'), closed=('C',), recovered=True))
