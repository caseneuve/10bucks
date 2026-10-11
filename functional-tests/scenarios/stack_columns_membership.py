"""Combined retained-layout/native membership acceptance; no production projector."""
import math
import time

from scenarios.columns_close_recovery import Frame, sampling_gate, same_frame

SCENARIO_ID = 'stack-columns-membership'
INVARIANTS = ('STACK-002', 'COL-002', 'COL-005', 'COL-007', 'LAY-003', 'WIN-005', 'FOCUS-004')

# Exact action contract. Inactive stack selection is deliberately unspecified.
# Retained columns selection/active group remains known through steps 10–14.
# operation, argument, live order, native focus, layout, stack members,
# columns groups, active selections (stack alias OR columns tuple), active group
STEPS = (
    ('create', 'A', 'A', 'A', 'stack', 'A', (), 'A', None),
    ('create', 'B', 'AB', 'B', 'stack', 'AB', (), 'B', None),
    ('create', 'C', 'ABC', 'C', 'stack', 'ABC', (), 'C', None),
    ('focusPrevious', None, 'ABC', 'B', 'stack', 'ABC', (), 'B', None),
    ('focusPrevious', None, 'ABC', 'A', 'stack', 'ABC', (), 'A', None),
    ('focusNext', None, 'ABC', 'B', 'stack', 'ABC', (), 'B', None),
    ('cycleLayout', None, 'ABC', 'B', 'columns', 'ABC', ('AB', 'C'), ('B', 'C'), 1),
    ('focusRightGroup', None, 'ABC', 'C', 'columns', 'ABC', ('AB', 'C'), ('B', 'C'), 2),
    ('create', 'D', 'ABCD', 'D', 'columns', 'ABC', ('AB', 'CD'), ('B', 'D'), 2),
    ('cycleLayout', None, 'ABCD', 'D', 'stack', 'ABCD', ('AB', 'CD'), 'D', None),
    ('create', 'E', 'ABCDE', 'E', 'stack', 'ABCDE', ('AB', 'CD'), 'E', None),
    ('focusNext', None, 'ABCDE', 'A', 'stack', 'ABCDE', ('AB', 'CD'), 'A', None),
    ('focusPrevious', None, 'ABCDE', 'E', 'stack', 'ABCDE', ('AB', 'CD'), 'E', None),
    ('close', 'A', 'BCDE', 'E', 'stack', 'BCDE', ('B', 'CD'), 'E', None),
    ('cycleLayout', None, 'BCDE', 'E', 'columns', 'BCDE', ('B', 'CDE'), ('B', 'E'), 2),
    ('focusNext', None, 'BCDE', 'C', 'columns', 'BCDE', ('B', 'CDE'), ('B', 'C'), 2),
    ('focusPrevious', None, 'BCDE', 'E', 'columns', 'BCDE', ('B', 'CDE'), ('B', 'E'), 2),
    ('focusPrevious', None, 'BCDE', 'D', 'columns', 'BCDE', ('B', 'CDE'), ('B', 'D'), 2),
    ('focusNext', None, 'BCDE', 'E', 'columns', 'BCDE', ('B', 'CDE'), ('B', 'E'), 2),
    ('focusLeftGroup', None, 'BCDE', 'B', 'columns', 'BCDE', ('B', 'CDE'), ('B', 'E'), 1),
    ('close', 'B', 'CDE', 'D', 'columns', 'CDE', ('CD', 'E'), ('D', 'E'), 1),
    ('close', 'E', 'CD', 'D', 'columns', 'CD', ('C', 'D'), ('C', 'D'), 2),
    ('close', 'D', 'C', 'C', 'columns', 'C', ('C',), ('C',), 1),
    ('cycleLayout', None, 'C', 'C', 'stack', 'C', ('C',), 'C', None),
)


def checkpoint(area, step, closed):
    _, _, order, focus, layout, stack, groups, selected, active = step
    left = Frame(area.x, area.y, area.w / 2, area.h)
    right = Frame(area.x + area.w / 2, area.y, area.w / 2, area.h)
    frames = {alias: area for alias in order}
    if layout == 'columns' and len(groups) == 2:
        frames = {alias: (left if index == 0 else right)
                  for index, group in enumerate(groups) for alias in group}

    def matches(o):
        d = o.diagnostics
        layouts = d.get('layouts', {})
        s, c = layouts.get('stack', {}), layouts.get('columns', {})
        columns_match = (
            'columns' not in layouts if not groups else
            c.get('groups') == [list(group) for group in groups]
            and c.get('ratio') == 0.5
            and (layout != 'stack' or len(groups) != 2 or
                 c.get('selected') == ['B', 'D'] and c.get('active') == 2)
        )
        return (set(o.frames) == set(order)
                and all(same_frame(o.frames.get(alias), frame) for alias, frame in frames.items())
                and o.focused == focus and o.managed == frozenset(order)
                and o.closed == frozenset(closed)
                and d.get('layout') == layout and d.get('order') == list(order)
                and s.get('members') == list(stack)
                and columns_match
                and (s.get('selected') == selected if layout == 'stack' else
                     c.get('selected') == list(selected) and c.get('active') == active
                     and c.get('ratio') == 0.5))
    return matches


def run(driver, *, clock=time.monotonic, sleep=time.sleep):
    area = driver.preflight()
    assert all(math.isfinite(v) for v in (area.x, area.y, area.w, area.h))
    assert area.w > 0 and area.h > 0
    eventually = sampling_gate(driver, scenario_id=SCENARIO_ID, clock=clock, sleep=sleep)
    closed = set()
    initial = ('', None, '', None, 'stack', '', (), None, None)
    previous = checkpoint(area, initial, closed)
    eventually('empty stack baseline', previous)
    for index, step in enumerate(STEPS, 1):
        operation, alias = step[:2]
        name = f'{index:02d} {operation} {alias or step[3]}'
        if operation == 'close':
            closed.add(alias)
        expected = checkpoint(area, step, closed.copy())
        if operation in ('create', 'close'):
            getattr(driver, operation)(alias)
            eventually(name, expected)
        else:
            baseline = eventually(name + ' fresh receipt baseline', previous)
            count = baseline.commands_received.get(operation, 0)
            driver.hotkey(operation)
            eventually(name, lambda o, expected=expected, operation=operation, count=count:
                       o.commands_received.get(operation, 0) == count + 1 and expected(o))
        previous = expected
