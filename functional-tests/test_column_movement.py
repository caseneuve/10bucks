"""Oracle checks only; scripted observations are not macOS acceptance."""
import copy
import unittest
from scenarios.columns_close_recovery import AcceptanceFailure, Frame, Observation
from scenarios.column_movement import STEPS, run


class Driver:
    def __init__(self, fault=None):
        self.time = 0
        self.index = 0
        self.sid = 0
        self.receipts = {}
        self.closed = set()
        self.fault = fault

    def clock(self): return self.time
    def sleep(self, duration): self.time += duration
    def preflight(self): return Frame(0, 32, 1000, 700)
    def record(self, name, observation): pass

    def action(self, op, alias=None):
        assert STEPS[self.index][:2] == (op, alias)
        self.index += 1
        if op == 'close': self.closed.add(alias)
        if alias is None:
            self.receipts[op] = self.receipts.get(op, 0) + (0 if self.fault == 'receipt' and self.index == 8 else 1)

    def create(self, alias): self.action('create', alias)
    def close(self, alias): self.action('close', alias)
    def hotkey(self, op): self.action(op)
    def fixture_action(self, op, alias): self.action(op, alias)

    def observe(self):
        self.time += .001
        self.sid += 1
        if not self.index:
            return Observation(self.sid, self.time, self.time, {}, None, frozenset(),
                               frozenset(), {}, {'layout': 'stack'})
        op, _, groups, selected, focus, minimized = STEPS[self.index - 1]
        stack = len(groups) == 1 and op in ('create', 'focusPrevious')
        frames = {a: self.preflight() if stack else Frame(i * 500, 32, 500, 700)
                  for i, group in enumerate(groups) for a in group}
        members = frozenset(''.join(groups))
        selected = selected or ('B', 'C')
        focus = focus or 'B'
        layout = {'members': list(groups[0]), 'selected': selected[0]} if stack else {
            'groups': [list(g) for g in groups], 'selected': list(selected), 'ratio': .5,
            'active': next(i + 1 for i, g in enumerate(groups) if focus in g)}
        availability = {a: {'nativeMinimized': a in minimized, 'lifecycle': {'minimized': a in minimized}}
                        for a in members}
        if self.index == 8:
            if self.fault == 'order': layout['groups'][0].reverse()
            if self.fault == 'selection': layout['selected'][0] = 'A'
            if self.fault == 'focus': focus = 'A'
            if self.fault == 'frame': frames['C'] = self.preflight()
        if self.index == 18 and self.fault == 'availability':
            availability['A']['lifecycle']['minimized'] = False
        return Observation(self.sid, self.time, self.time, frames, focus, frozenset(self.closed),
                           members, dict(self.receipts), copy.deepcopy({
                               'layout': 'stack' if stack else 'columns',
                               'layouts': {'stack' if stack else 'columns': layout},
                               'movementAvailability': availability}))


class MovementChecks(unittest.TestCase):
    def test_sequence(self):
        driver = Driver()
        run(driver, clock=driver.clock, sleep=driver.sleep)
        self.assertEqual(driver.index, len(STEPS))

    def test_native_and_retained_state_negatives(self):
        for fault in ('order', 'selection', 'focus', 'frame', 'receipt', 'availability'):
            with self.subTest(fault=fault):
                driver = Driver(fault)
                with self.assertRaises(AcceptanceFailure):
                    run(driver, clock=driver.clock, sleep=driver.sleep)
                self.assertLess(driver.index, len(STEPS))


if __name__ == '__main__': unittest.main()
