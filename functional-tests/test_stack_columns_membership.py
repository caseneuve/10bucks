"""Scripted oracle negatives, not native evidence or a production model."""
import copy
import unittest

from scenarios.columns_close_recovery import AcceptanceFailure, Frame, Observation
from scenarios.stack_columns_membership import STEPS, run


class Driver:
    def __init__(self, defect=None):
        self.time = 0
        self.index = 0
        self.sid = 0
        self.receipts = {}
        self.closed = set()
        self.actions = []
        self.defect = defect

    def clock(self): return self.time
    def sleep(self, duration): self.time += duration
    def preflight(self): return Frame(10, 20, 1000, 700)
    def record(self, name, observation): pass

    def action(self, operation, alias):
        self.assert_action = STEPS[self.index][:2]
        assert (operation, alias) == self.assert_action
        self.actions.append((operation, alias))
        self.index += 1
        if operation == 'close': self.closed.add(alias)
        if operation not in ('create', 'close'):
            self.receipts[operation] = self.receipts.get(operation, 0) + 1

    def create(self, alias): self.action('create', alias)
    def close(self, alias): self.action('close', alias)
    def hotkey(self, operation): self.action(operation, None)

    def observe(self):
        self.time += .001
        self.sid += 1
        step = STEPS[self.index - 1] if self.index else ('', None, '', None, 'stack', '', (), None, None)
        operation, _, order, focus, layout, stack, groups, selected, active = step
        area = self.preflight()
        frames = {a: area for a in order}
        if layout == 'columns' and len(groups) == 2:
            frames = {a: Frame(10 + i * 500, 20, 500, 700)
                      for i, group in enumerate(groups) for a in group}
        diagnostics = {'layout': layout, 'order': list(order), 'layouts': {
            'stack': {'members': list(stack), 'selected': selected if layout == 'stack' else None}}}
        if groups:
            diagnostics['layouts']['columns'] = {
                'groups': [list(g) for g in groups],
                'selected': list(selected) if layout == 'columns' else
                            (['B', 'D'] if len(groups) == 2 else ['C']),
                'active': active if layout == 'columns' else (2 if len(groups) == 2 else 1),
                'ratio': .5}
        if self.defect == 'premature-columns' and self.index < 7:
            diagnostics['layouts']['columns'] = {'groups': []}
        if self.defect == 'inactive-selection' and self.index == 11:
            diagnostics['layouts']['columns']['selected'] = ['A', 'C']
        if self.defect == 'inactive-active' and self.index == 14:
            diagnostics['layouts']['columns']['active'] = 1
        closed = self.closed.copy()
        if self.defect == 'reversed-k' and self.index == 4: focus = 'A'
        if self.defect == 'reversed-j' and self.index == 6: focus = 'C'
        if self.defect == 'layout-reset' and self.index == 15:
            diagnostics['layouts']['columns']['groups'] = [['B', 'C'], ['D', 'E']]
        if self.defect == 'reorder' and self.index == 10:
            diagnostics['order'] = list(reversed(order))
        if self.defect == 'inactive-assignment' and self.index == 11:
            diagnostics['layouts']['columns']['groups'] = [['A', 'B', 'E'], ['C', 'D']]
        if self.defect == 'inactive-stack' and self.index == 9:
            diagnostics['layouts']['stack']['members'].append('D')
        if self.defect == 'stale-closed' and self.index == 14: closed.clear()
        if self.defect == 'native-focus' and self.index == 21: focus = 'E'
        if self.defect == 'geometry' and self.index == 22: frames['D'] = area
        return Observation(self.sid, self.time, self.time, frames, focus,
                           frozenset(closed), frozenset(order), dict(self.receipts),
                           copy.deepcopy(diagnostics))


class MembershipChecks(unittest.TestCase):
    def test_exact_24_actions(self):
        driver = Driver()
        run(driver, clock=driver.clock, sleep=driver.sleep)
        self.assertEqual(driver.actions, [step[:2] for step in STEPS])
        self.assertEqual(len(driver.actions), 24)
        self.assertEqual(driver.closed, {'A', 'B', 'D', 'E'})

    def test_columns_absent_before_first_activation(self):
        driver = Driver('premature-columns')
        with self.assertRaisesRegex(AcceptanceFailure, 'empty stack baseline'):
            run(driver, clock=driver.clock, sleep=driver.sleep)
        self.assertEqual(driver.actions, [])

    def test_inactive_columns_corruption_cannot_be_masked_by_activation(self):
        for defect, step in (('inactive-selection', 11), ('inactive-active', 14)):
            with self.subTest(defect=defect):
                driver = Driver(defect)
                with self.assertRaises(AcceptanceFailure):
                    run(driver, clock=driver.clock, sleep=driver.sleep)
                self.assertEqual(driver.index, step)
                self.assertLess(driver.index, 15)  # fail before reactivation repairs it

    def test_contract_negatives(self):
        for defect in ('reversed-k', 'reversed-j', 'layout-reset', 'reorder',
                       'inactive-assignment', 'inactive-stack', 'stale-closed',
                       'native-focus', 'geometry'):
            with self.subTest(defect=defect):
                driver = Driver(defect)
                with self.assertRaises(AcceptanceFailure):
                    run(driver, clock=driver.clock, sleep=driver.sleep)
                self.assertLess(driver.index, 24)


if __name__ == '__main__': unittest.main()
