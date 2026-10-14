"""COL-006 real HyperO, native global focus/frames and retained-slot acceptance."""
import time
from scenarios.columns_close_recovery import Frame, sampling_gate, same_frame

SCENARIO_ID = 'column-movement'
INVARIANTS = ('COL-006', 'STATE-002', 'STATE-008', 'WIN-002', 'WIN-004', 'FOCUS-002')

# operation, alias, groups, selected, actual focus, minimized aliases
STEPS = (
    ('create', 'A', ('A',), ('A',), 'A', ''),
    ('create', 'B', ('AB',), ('B',), 'B', ''),
    ('create', 'C', ('ABC',), ('C',), 'C', ''),
    ('focusPrevious', None, ('ABC',), ('B',), 'B', ''),
    ('focusPrevious', None, ('ABC',), ('A',), 'A', ''),
    ('cycleLayout', None, ('AB', 'C'), ('A', 'C'), 'A', ''),
    ('focusRightGroup', None, ('AB', 'C'), ('A', 'C'), 'C', ''),
    ('moveFocusedToOtherGroup', None, ('CA', 'B'), ('C', 'B'), 'C', ''),
    ('focusRightGroup', None, ('CA', 'B'), ('C', 'B'), 'B', ''),
    ('moveFocusedToOtherGroup', None, ('BC', 'A'), ('B', 'A'), 'B', ''),
    ('moveFocusedToOtherGroup', None, ('C', 'AB'), ('C', 'B'), 'B', ''),
    ('focusLeftGroup', None, ('C', 'AB'), ('C', 'B'), 'C', ''),
    ('moveFocusedToOtherGroup', None, ('A', 'CB'), ('A', 'C'), 'C', ''),
    ('focusLeftGroup', None, ('A', 'CB'), ('A', 'C'), 'A', ''),
    ('moveFocusedToOtherGroup', None, ('B', 'AC'), ('B', 'A'), 'A', ''),
    ('focusPrevious', None, ('B', 'AC'), ('B', 'C'), 'C', ''),
    ('focusLeftGroup', None, ('B', 'AC'), ('B', 'C'), 'B', ''),
    ('minimize', 'A', ('B', 'AC'), ('B', 'C'), 'B', 'A'),
    ('moveFocusedToOtherGroup', None, ('B', 'AC'), ('B', 'C'), 'B', 'A'),
    # Restore may natively focus A; planned setup fixes the next command target.
    ('unminimize', 'A', ('B', 'AC'), None, None, ''),
    ('focus', 'A', ('B', 'AC'), ('B', 'A'), 'A', ''),
    ('focusLeftGroup', None, ('B', 'AC'), ('B', 'A'), 'B', ''),
    ('moveFocusedToOtherGroup', None, ('C', 'BA'), ('C', 'B'), 'B', ''),
    ('close', 'C', ('B', 'A'), ('B', 'A'), 'B', ''),
    ('moveFocusedToOtherGroup', None, ('B', 'A'), ('B', 'A'), 'B', ''),
)


def checkpoint(area, step, closed):
    operation, _, groups, selected, focus, minimized = step
    stack = operation in ('create', 'focusPrevious') and len(groups) == 1
    members = set(''.join(groups))
    left = Frame(area.x, area.y, area.w / 2, area.h)
    right = Frame(area.x + area.w / 2, area.y, area.w / 2, area.h)
    frames = {a: area if stack else (left if index == 0 else right)
              for index, group in enumerate(groups) for a in group if a not in minimized}

    def matches(o):
        d = o.diagnostics
        layout = d.get('layouts', {}).get('stack' if stack else 'columns', {})
        if (o.managed != frozenset(members) or set(o.frames) != members
                or o.closed != frozenset(closed) or d.get('layout') != ('stack' if stack else 'columns')
                or any(not same_frame(o.frames.get(a), f) for a, f in frames.items())
                or (focus is not None and o.focused != focus)):
            return False
        if stack:
            return layout.get('members') == list(groups[0]) and layout.get('selected') == selected[0]
        if layout.get('groups') != [list(g) for g in groups] or layout.get('ratio') != .5:
            return False
        if selected is not None and (layout.get('selected') != list(selected)
                or layout.get('active') != next(i + 1 for i, g in enumerate(groups) if focus in g)):
            return False
        availability = d.get('movementAvailability', {})
        return all(availability.get(a, {}).get('nativeMinimized') is (a in minimized)
                   and availability.get(a, {}).get('lifecycle', {}).get('minimized') is (a in minimized)
                   for a in members)
    return matches


def run(driver, *, clock=time.monotonic, sleep=time.sleep):
    area = driver.preflight()
    gate = sampling_gate(driver, scenario_id=SCENARIO_ID, clock=clock, sleep=sleep)
    closed = set()
    previous = lambda o: not o.managed and not o.frames and o.diagnostics.get('layout') == 'stack'
    gate('empty stack baseline', previous)
    for index, step in enumerate(STEPS, 1):
        operation, alias = step[:2]
        name = f'{index:02d} {operation} {alias or step[4]}'
        if operation == 'close':
            closed.add(alias)
        expected = checkpoint(area, step, closed.copy())
        if operation in ('create', 'close'):
            getattr(driver, operation)(alias)
        elif operation in ('minimize', 'unminimize', 'focus'):
            driver.fixture_action(operation, alias)
        else:
            count = gate(name + ' fresh receipt baseline', previous).commands_received.get(operation, 0)
            driver.hotkey(operation)
            predicate = expected
            expected = lambda o, p=predicate, op=operation, count=count: (
                o.commands_received.get(op, 0) == count + 1 and p(o))
        gate(name, expected)
        previous = expected
