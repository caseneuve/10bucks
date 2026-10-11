"""Deterministic self-checks of the acceptance oracle, NOT native evidence."""
import unittest

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

    def clock(self):
        return self.time

    def sleep(self, duration):
        self.time += duration

    def preflight(self):
        return Frame(10, 30, 1200, 800)

    def create(self, alias):
        self.actions.append(("create", alias))
        self.stage += 1

    def close(self, alias):
        self.actions.append(("close", alias))
        self.stage = 3

    def hotkey(self, command):
        self.actions.append(("hotkey", command))
        if self.defect != "undelivered":
            self.commands[command] = self.commands.get(command, 0) + 1

    def observe(self):
        a = Frame(10, 30, 1200, 800)
        b = Frame(610, 30, 600, 800)
        if self.stage == 1:
            frames, focused, managed, closed = {"A": a}, "A", {"A"}, set()
        elif self.stage == 2:
            frames = {"A": Frame(10, 30, 600, 800), "B": b}
            focused, managed, closed = "B", {"A", "B"}, set()
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
        return Observation(frames, focused, frozenset(closed),
                           frozenset(managed), dict(self.commands))

    def record(self, checkpoint, observation):
        self.samples.append((self.time, checkpoint, observation))


class ScenarioChecks(unittest.TestCase):
    def execute(self, driver):
        run(driver, clock=driver.clock, sleep=driver.sleep)

    def test_complete_action_sequence(self):
        driver = ModelDriver()
        self.execute(driver)
        self.assertEqual(driver.actions, [
            ("create", "A"), ("create", "B"), ("close", "B"),
            ("hotkey", "focusNext"), ("hotkey", "focusPrevious"),
        ])
        self.assertEqual(len({s[1] for s in driver.samples}), 5)

    def test_native_and_secondary_mismatches_fail(self):
        for defect in ("half-width", "wrong-focus", "dead-membership",
                       "absence-not-death", "undelivered"):
            with self.subTest(defect=defect):
                driver = ModelDriver(defect)
                with self.assertRaises(AcceptanceFailure):
                    self.execute(driver)
                self.assertGreater(len(driver.samples), 0)
                self.assertLess(driver.time, 10)

    def test_driver_failure_is_not_reclassified(self):
        driver = ModelDriver()
        def broken_observation():
            raise RuntimeError("guest IPC unavailable")
        driver.observe = broken_observation
        with self.assertRaisesRegex(RuntimeError, "IPC unavailable"):
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
        self.assertFalse(any(action[0] == "hotkey" for action in driver.actions))


if __name__ == "__main__":
    unittest.main()
