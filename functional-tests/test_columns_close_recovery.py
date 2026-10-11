"""Deterministic self-checks of the acceptance oracle, NOT native evidence."""
import unittest
from dataclasses import replace

from scenarios.columns_close_recovery import (
    AcceptanceFailure, Frame, Observation, run,
)


class ModelDriver:
    def __init__(self, defect=None):
        self.defect = defect
        self.time = 0.0
        self.stage = 0
        self.commands = {}
        self.actions = []
        self.samples = []
        self.sample_id = 0
        self.focused = None
        self.layout = "columns"
        self.previous = None
        self.last_command = None

    def clock(self):
        return self.time

    def sleep(self, duration):
        self.time += duration

    def preflight(self):
        return Frame(10, 30, 1200, 800)

    def create(self, alias):
        self.actions.append(("create", alias))
        self.stage += 1
        self.previous, self.focused = self.focused, alias

    def close(self, alias):
        self.actions.append(("close", alias))
        self.stage = 3
        self.focused = "A"

    def hotkey(self, command):
        self.actions.append(("hotkey", command))
        self.last_command = command
        if self.defect == "undelivered":
            return
        self.commands[command] = self.commands.get(command, 0) + 1
        target = self.focused
        if command == "cycleLayout":
            self.layout = "stack" if self.layout == "columns" else "columns"
        elif self.stage == 2:
            if command == "focusLeftGroup":
                target = "A"
            elif command == "focusRightGroup":
                target = "B"
            elif command == "focusManagedPrevious":
                target = self.previous
            elif command in ("focusNext", "focusPrevious"):
                target = "A" if self.focused == "B" else "B"
        if target != self.focused:
            self.previous, self.focused = self.focused, target

    def observe(self):
        self.time += 0.001  # acquisition clock advances even across checkpoints
        a = Frame(10, 30, 1200, 800)
        b = Frame(610, 30, 600, 800)
        if self.stage == 1:
            frames, focused, managed, closed = {"A": a}, "A", {"A"}, set()
        elif self.stage == 2:
            frames = {"A": Frame(10, 30, 600, 800), "B": b}
            if self.layout == "stack":
                frames = {"A": a, "B": a}
            focused, managed, closed = self.focused, {"A", "B"}, set()
        else:
            frames, focused, managed, closed = {"A": a}, "A", {"A"}, {"B"}
            if self.defect == "half-width":
                frames["A"] = Frame(10, 30, 600, 800)
            elif self.defect == "wrong-focus":
                focused = None
            elif self.defect == "dead-membership":
                managed.add("B")
            elif self.defect == "absence-not-death":
                closed.clear()
        self.sample_id += 1
        return Observation(self.sample_id, self.time, self.time, frames, focused,
                           frozenset(closed), frozenset(managed), dict(self.commands))

    def record(self, checkpoint, observation):
        self.samples.append((self.time, checkpoint, observation))


class ScenarioChecks(unittest.TestCase):
    def execute(self, driver):
        run(driver, clock=driver.clock, sleep=driver.sleep)

    def test_complete_action_sequence(self):
        driver = ModelDriver()
        self.execute(driver)
        self.assertEqual(driver.actions, [
            ("create", "A"), ("create", "B"),
            ("hotkey", "focusLeftGroup"), ("hotkey", "focusRightGroup"),
            ("hotkey", "focusManagedPrevious"), ("hotkey", "focusManagedPrevious"),
            ("hotkey", "cycleLayout"),
            ("hotkey", "focusNext"), ("hotkey", "focusPrevious"),
            ("hotkey", "cycleLayout"), ("close", "B"),
            ("hotkey", "focusNext"), ("hotkey", "focusPrevious"),
        ])
        self.assertEqual(len({s[1] for s in driver.samples}), 23)

    def test_native_and_secondary_mismatches_fail(self):
        for defect in ("half-width", "wrong-focus", "dead-membership",
                       "absence-not-death", "undelivered"):
            with self.subTest(defect=defect):
                driver = ModelDriver(defect)
                with self.assertRaises(AcceptanceFailure):
                    self.execute(driver)
                self.assertGreater(len(driver.samples), 0)
                self.assertLess(driver.time, 10)

    def test_correct_split_with_focus_on_wrong_live_member_fails(self):
        driver = ModelDriver()
        original = driver.observe
        def observation():
            sample = original()
            if driver.stage == 2:
                return replace(sample, focused="A")  # candidate members/frames correct
            return sample
        driver.observe = observation
        with self.assertRaisesRegex(AcceptanceFailure, "B right and focused"):
            self.execute(driver)
        self.assertNotIn(("close", "B"), driver.actions)

    def test_receipt_with_wrong_actual_focus_fails_each_changing_command(self):
        for command, occurrence in (("focusLeftGroup", 1), ("focusRightGroup", 1),
                                    ("focusManagedPrevious", 1),
                                    ("focusManagedPrevious", 2),
                                    ("focusNext", 1), ("focusPrevious", 1)):
            with self.subTest(command=command, occurrence=occurrence):
                driver = ModelDriver()
                original = driver.hotkey
                def hotkey(name):
                    old_focus = driver.focused
                    original(name)
                    if name == command and driver.commands[name] == occurrence:
                        driver.focused = old_focus  # receipt exists, native target unchanged
                driver.hotkey = hotkey
                with self.assertRaisesRegex(AcceptanceFailure, f"{command} received"):
                    self.execute(driver)
                self.assertEqual(driver.commands[command], occurrence)
                self.assertNotIn(("close", "B"), driver.actions)

    def test_layout_receipt_cannot_hide_lost_focus_or_wrong_geometry(self):
        for occurrence in (1, 2):
            for defect in ("focus", "geometry"):
                with self.subTest(occurrence=occurrence, defect=defect):
                    driver = ModelDriver()
                    original = driver.hotkey
                    def hotkey(name):
                        old_layout = driver.layout
                        original(name)
                        if name == "cycleLayout" and driver.commands[name] == occurrence:
                            if defect == "focus":
                                driver.focused = "A"
                            else:
                                driver.layout = old_layout
                    driver.hotkey = hotkey
                    with self.assertRaisesRegex(AcceptanceFailure, "cycleLayout received"):
                        self.execute(driver)
                    self.assertEqual(driver.commands["cycleLayout"], occurrence)
                    self.assertNotIn(("close", "B"), driver.actions)

    def test_driver_failure_is_not_reclassified(self):
        driver = ModelDriver()
        def broken_observation():
            raise RuntimeError("guest IPC unavailable")
        driver.observe = broken_observation
        with self.assertRaisesRegex(RuntimeError, "IPC unavailable"):
            self.execute(driver)

    def test_delivery_clock_cannot_regress(self):
        driver = ModelDriver()
        original = driver.observe
        def observation():
            sample = original()
            return replace(sample, observed_at=sample.sampled_at +
                           (0.14 if sample.sample_id % 2 else 0))
        driver.observe = observation
        with self.assertRaisesRegex(RuntimeError, "stale or replayed"):
            self.execute(driver)

    def test_cached_observations_cannot_establish_stability(self):
        driver = ModelDriver()
        original = driver.observe
        cached = None
        def cached_observation():
            nonlocal cached
            if cached is None:
                cached = original()
            return cached
        driver.observe = cached_observation
        with self.assertRaisesRegex(RuntimeError, "stale or replayed"):
            self.execute(driver)

    def test_sparse_observations_are_harness_failure_not_stability(self):
        driver = ModelDriver()
        original = driver.observe
        def delayed_observation():
            driver.time += 0.3
            return original()
        driver.observe = delayed_observation
        with self.assertRaisesRegex(RuntimeError, "sampling gap"):
            self.execute(driver)

    def test_transient_match_does_not_pass(self):
        driver = ModelDriver("half-width")
        original = driver.observe
        recovery_started = None
        def observation():
            nonlocal recovery_started
            if driver.stage == 3 and recovery_started is None:
                recovery_started = driver.time
            if driver.stage == 3 and driver.time - recovery_started < 0.1:
                driver.defect = None
                result = original()
                driver.defect = "half-width"
                return result
            return original()
        driver.observe = observation
        # Recovery briefly matches for <250ms, then loses its geometry.
        with self.assertRaises(AcceptanceFailure):
            self.execute(driver)
        self.assertEqual(driver.actions[-1], ("close", "B"))


if __name__ == "__main__":
    unittest.main()
