"""Native acceptance scenario; no production imports or synthetic manager events.

The runner supplies the guest driver described in functional-tests/README.md.
This module is executable scenario logic, not a VM runner.
"""
from dataclasses import dataclass, field
import math
import time
from typing import Protocol


SCENARIO_ID = "columns-close-recovery"
INVARIANTS = ("COL-002", "COL-005", "COL-007", "STACK-002", "LAY-003", "WIN-005", "FOCUS-004", "FOCUS-005", "FOCUS-006")
TIMEOUT_SECONDS = 5.0
STABLE_SECONDS = 0.25
SAMPLE_SECONDS = 0.05
MAX_SAMPLE_GAP_SECONDS = 0.15
FRAME_TOLERANCE = 2.0  # macOS logical points, not backing pixels


@dataclass(frozen=True)
class Frame:
    x: float
    y: float
    w: float
    h: float


@dataclass(frozen=True)
class Observation:
    # Guest monotonic seconds; sampled_at is acquisition, observed_at is current
    # guest time when delivered. Both must be in the same clock domain.
    sample_id: int
    sampled_at: float
    observed_at: float
    # Only test-owned aliases. Frames/focus/closed come from native observation.
    frames: dict[str, Frame]
    focused: str | None
    closed: frozenset[str]
    # Secondary read-only candidate snapshot, never used to derive native frames.
    managed: frozenset[str]
    # Cumulative acknowledgements of candidate hotkey callbacks, not sent keys.
    commands_received: dict[str, int]
    diagnostics: dict = field(default_factory=dict)


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


def sampling_gate(driver, *, scenario_id=SCENARIO_ID, clock=time.monotonic, sleep=time.sleep):
    last_sample_id = -1
    last_acquired = None
    last_delivered = None

    def eventually(name, predicate):
        nonlocal last_sample_id, last_acquired, last_delivered
        deadline = clock() + TIMEOUT_SECONDS
        matching_since = None
        previous_sample = clock()
        while True:
            observation = driver.observe()
            driver.record(name, observation)
            now = clock()
            if now - previous_sample > MAX_SAMPLE_GAP_SECONDS:
                raise RuntimeError(f"{scenario_id}: {name}: native sampling gap exceeded 150ms")
            previous_sample = now
            if (observation.sample_id <= last_sample_id
                    or not math.isfinite(observation.sampled_at)
                    or not math.isfinite(observation.observed_at)
                    or observation.observed_at < observation.sampled_at
                    or observation.observed_at - observation.sampled_at > MAX_SAMPLE_GAP_SECONDS
                    or (last_acquired is not None and observation.sampled_at <= last_acquired)
                    or (last_delivered is not None and observation.observed_at < last_delivered)):
                raise RuntimeError(f"{scenario_id}: {name}: stale or replayed native sample")
            if (matching_since is not None and last_acquired is not None
                    and observation.sampled_at - last_acquired > MAX_SAMPLE_GAP_SECONDS):
                raise RuntimeError(f"{scenario_id}: {name}: native acquisition gap exceeded 150ms")
            last_sample_id = observation.sample_id
            last_acquired = observation.sampled_at
            last_delivered = observation.observed_at
            if now > deadline:
                raise AcceptanceFailure(f"{scenario_id}: {name} timed out; last={observation!r}")
            if predicate(observation):
                if matching_since is None:
                    matching_since = observation.sampled_at
                if observation.sampled_at - matching_since >= STABLE_SECONDS:
                    return observation
            else:
                matching_since = None
            sleep(SAMPLE_SECONDS)

    return eventually


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

    eventually = sampling_gate(driver, clock=clock, sleep=sleep)

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
    def paired(focused, *, stack=False):
        return lambda o: (
            same_frame(o.frames.get("A"), area if stack else left)
            and same_frame(o.frames.get("B"), area if stack else right)
            and o.focused == focused
            and o.managed == frozenset({"A", "B"})
            and not o.closed
        )

    def command_checkpoint(command, before_predicate, after_predicate, name):
        baseline = eventually(f"{name} fresh receipt baseline", before_predicate)
        before = baseline.commands_received.get(command, 0)
        driver.hotkey(command)
        eventually(name, lambda o:
                   o.commands_received.get(command, 0) == before + 1
                   and after_predicate(o))

    command_checkpoint("focusLeftGroup", paired("B"), paired("A"),
                       "focusLeftGroup received, native A focused")
    command_checkpoint("focusRightGroup", paired("A"), paired("B"),
                       "focusRightGroup received, native B focused")
    # lib/config.lua names the previous-managed-window binding
    # focusManagedPrevious (Hyper+'); focusPrevious is stack navigation (k).
    for source, target in (("B", "A"), ("A", "B")):
        command_checkpoint("focusManagedPrevious", paired(source), paired(target),
                           f"focusManagedPrevious received, native {target} focused")
    command_checkpoint("cycleLayout", paired("B"), paired("B", stack=True),
                       "cycleLayout received, stack preserves native B focus")
    command_checkpoint("focusNext", paired("B", stack=True), paired("A", stack=True),
                       "focusNext received, native A focused in stack")
    command_checkpoint("focusPrevious", paired("A", stack=True), paired("B", stack=True),
                       "focusPrevious received, native B focused in stack")
    command_checkpoint("cycleLayout", paired("B", stack=True), paired("B"),
                       "cycleLayout received, columns preserves native B focus")

    driver.close("B")
    eventually("B destroyed, A expanded and focused", recovered)

    # With one survivor both directions wrap to A. Callback acknowledgement
    # prevents an undelivered/no-op sender from falsely passing these assertions.
    for command in ("focusNext", "focusPrevious"):
        command_checkpoint(command, recovered, recovered,
                           f"{command} received, no dead target")
