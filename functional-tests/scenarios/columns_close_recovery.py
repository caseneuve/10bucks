"""Native acceptance scenario; no production imports or synthetic manager events.

The runner supplies the guest driver described in functional-tests/README.md.
This module is executable scenario logic, not a VM runner.
"""
from dataclasses import dataclass
import math
import time
from typing import Protocol


SCENARIO_ID = "columns-close-recovery"
INVARIANTS = ("COL-002", "COL-005", "WIN-005", "FOCUS-004", "FOCUS-006")
TIMEOUT_SECONDS = 5.0
STABLE_SECONDS = 0.25
SAMPLE_SECONDS = 0.05
FRAME_TOLERANCE = 2.0  # macOS logical points, not backing pixels


@dataclass(frozen=True)
class Frame:
    x: float
    y: float
    w: float
    h: float


@dataclass(frozen=True)
class Observation:
    # Only test-owned aliases. Frames/focus/closed come from native observation.
    frames: dict[str, Frame]
    focused: str | None
    closed: frozenset[str]
    # Secondary read-only candidate snapshot, never used to derive native frames.
    managed: frozenset[str]
    # Cumulative acknowledgements of candidate hotkey callbacks, not sent keys.
    commands_received: dict[str, int]


class Driver(Protocol):
    def preflight(self) -> Frame:
        """Validate isolation/columns baseline; return independent native work area."""

    def create(self, alias: str) -> None:
        """Create a standard native fixture window, idempotent alias join forbidden."""

    def close(self, alias: str) -> None:
        """Normal native close of the exact owned fixture window, not an injected event."""

    def hotkey(self, command: str) -> None:
        """Send real configured guest key down/up; return is not receipt proof."""

    def observe(self) -> Observation:
        """Read native outcomes + diagnostic snapshot; must not reconcile candidate."""

    def record(self, checkpoint: str, observation: Observation) -> None:
        """Persist alias-based observations with monotonic timestamps."""


class AcceptanceFailure(AssertionError):
    pass


def same_frame(actual: Frame | None, expected: Frame) -> bool:
    return actual is not None and all(
        math.isfinite(a) and abs(a - e) <= FRAME_TOLERANCE
        for a, e in zip(
            (actual.x, actual.y, actual.w, actual.h),
            (expected.x, expected.y, expected.w, expected.h),
        )
    )


def run(driver: Driver, *, clock=time.monotonic, sleep=time.sleep) -> None:
    """Run assertions. Driver exceptions remain harness failures, not mismatches.

    Runner MUST perform cleanup in finally, including when this function raises.
    Deadlines/tolerance are fixed above; no automatic retries or weakened gates.
    """
    area = driver.preflight()
    assert all(math.isfinite(v) for v in (area.x, area.y, area.w, area.h))
    assert area.w > 0 and area.h > 0, "Invalid independent work area"
    left = Frame(area.x, area.y, area.w / 2, area.h)
    right = Frame(area.x + area.w / 2, area.y, area.w / 2, area.h)

    def eventually(name, predicate):
        deadline = clock() + TIMEOUT_SECONDS
        matching_since = None
        while True:
            observation = driver.observe()
            driver.record(name, observation)
            now = clock()
            if now > deadline:
                raise AcceptanceFailure(f"{SCENARIO_ID}: {name} timed out; last={observation!r}")
            if predicate(observation):
                if matching_since is None:
                    matching_since = now
                if now - matching_since >= STABLE_SECONDS:
                    return observation
            else:
                matching_since = None
            sleep(SAMPLE_SECONDS)

    def recovered(o):
        return (
            same_frame(o.frames.get("A"), area)
            and "B" not in o.frames
            and "B" in o.closed
            and o.focused == "A"
            and o.managed == frozenset({"A"})
        )

    driver.create("A")
    eventually("A full-width and focused", lambda o:
               same_frame(o.frames.get("A"), area)
               and o.focused == "A" and o.managed == frozenset({"A"}))
    driver.create("B")
    eventually("A left, B right and focused", lambda o:
               same_frame(o.frames.get("A"), left)
               and same_frame(o.frames.get("B"), right)
               and o.focused == "B" and o.managed == frozenset({"A", "B"}))
    driver.close("B")
    eventually("B destroyed, A expanded and focused", recovered)

    # With one survivor both directions wrap to A. Callback acknowledgement
    # prevents an undelivered/no-op sender from falsely passing these assertions.
    for command in ("focusNext", "focusPrevious"):
        before = driver.observe().commands_received.get(command, 0)
        driver.hotkey(command)
        eventually(f"{command} received, no dead target", lambda o:
                   o.commands_received.get(command, 0) == before + 1 and recovered(o))
