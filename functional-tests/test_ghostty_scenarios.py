"""Scripted oracle regressions only, not native Ghostty evidence."""
import unittest
from scenarios.columns_close_recovery import AcceptanceFailure, Frame, Observation
from scenarios import ghostty_column_normalization as normalization
from scenarios import ghostty_layout_retention as retention


class Driver:
    def __init__(self, layout, defect=None):
        self.layout = layout
        self.order = ''
        self.focus = None
        self.groups = []
        self.selected = []
        self.closed = set()
        self.actions = []
        self.receipts = {}
        self.time = 0
        self.sid = 0
        self.defect = defect

    def clock(self): return self.time
    def sleep(self, duration): self.time += duration
    def preflight(self): return Frame(10, 32, 1000, 700)
    def record(self, name, o): pass

    def create_ghostty(self, alias):
        self.actions.append(('createGhostty', alias))
        self.order += alias
        self.focus = alias
        if self.layout == 'columns':
            self.groups = [['A']] if len(self.order) == 1 else [['A'], list(self.order[1:])]
            self.selected = ['A'] if len(self.order) == 1 else ['A', alias]

    def close_ghostty(self):
        self.actions.append(('closeGhostty', 'C'))
        self.order = 'AB'; self.closed.add('C'); self.focus = 'B'
        self.groups = [['A'], ['B']]; self.selected = ['A', 'B']

    def hotkey(self, command):
        self.actions.append(('hotkey', command))
        self.receipts[command] = self.receipts.get(command, 0) + 1
        if command == 'cycleLayout':
            self.layout = 'stack' if self.layout == 'columns' else 'columns'
            if self.layout == 'columns':
                if not self.groups: self.groups = [['A', 'B'], ['C']]; self.selected = ['A', 'C']
                for i, group in enumerate(self.groups):
                    if self.focus in group: self.selected[i] = self.focus
        elif command == 'focusRightGroup': self.focus = 'C'
        else:
            delta = 1 if command == 'focusNext' else -1
            if self.defect == 'reverse-navigation': delta = -delta
            self.focus = self.order[(self.order.index(self.focus) + delta) % len(self.order)]

    def observe(self):
        self.time += .001; self.sid += 1
        frames = {a: self.preflight() for a in self.order}
        if self.layout == 'columns' and len(self.groups) == 2:
            frames = {a: Frame(10 + i * 500, 32, 500, 700) for i, g in enumerate(self.groups) for a in g}
        groups = [g[:] for g in self.groups]
        selected = self.selected[:]
        focus = self.focus
        if self.closed and self.defect == 'no-normalization': groups = [['A', 'B'], []]
        if self.closed and self.defect == 'no-B-focus': focus = 'A'
        if self.defect == 'assignment-reset' and self.receipts.get('cycleLayout', 0) >= 2:
            groups = [['A', 'B'], ['C']]
        if self.defect == 'wrong-geometry' and self.layout == 'columns' and len(self.order) == 3:
            frames['B'] = self.preflight()
        layouts = {'stack': {'members': list(self.order), 'selected': self.focus}}
        if groups:
            active = next((i + 1 for i, g in enumerate(groups) if self.focus in g), 1)
            layouts['columns'] = {'groups': groups, 'selected': selected, 'active': active, 'ratio': .5}
        d = {'layout': self.layout, 'order': list(self.order), 'layouts': layouts,
             'ghosttyAXInvalid': bool(self.closed)}
        return Observation(self.sid, self.time, self.time, frames, focus,
                           frozenset(self.closed), frozenset(self.order), dict(self.receipts), d)


class Checks(unittest.TestCase):
    def execute(self, scenario, driver): run = scenario.run; run(driver, clock=driver.clock, sleep=driver.sleep)

    def test_normalization_stops_at_close(self):
        driver = Driver('stack'); self.execute(normalization, driver)
        self.assertEqual(driver.actions, [('createGhostty', 'A'), ('createGhostty', 'B'),
            ('createGhostty', 'C'), ('hotkey', 'focusPrevious'), ('hotkey', 'focusPrevious'),
            ('hotkey', 'cycleLayout'), ('hotkey', 'focusRightGroup'), ('closeGhostty', 'C')])

    def test_repeated_layout_retention_sequence(self):
        driver = Driver('columns'); self.execute(retention, driver)
        self.assertEqual(len(driver.actions), 13)
        self.assertFalse(driver.closed)
        self.assertEqual(driver.focus, 'A')

    def test_negative_oracles(self):
        for scenario, layout, defects in (
            (normalization, 'stack', ('no-normalization', 'no-B-focus', 'reverse-navigation', 'wrong-geometry')),
            (retention, 'columns', ('assignment-reset', 'reverse-navigation', 'wrong-geometry'))):
            for defect in defects:
                with self.subTest(scenario=scenario.SCENARIO_ID, defect=defect):
                    driver = Driver(layout, defect)
                    with self.assertRaises(AcceptanceFailure): self.execute(scenario, driver)
                    if driver.closed: self.assertEqual(driver.actions[-1], ('closeGhostty', 'C'))


if __name__ == '__main__': unittest.main()
