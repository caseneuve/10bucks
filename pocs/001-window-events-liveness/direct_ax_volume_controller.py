#!/usr/bin/env python3
"""POC-001 direct-AX volume controller.

This is deliberately a small state machine, not a sample runner.  It exposes
only explicit warm/cold lifecycle commands and abort-cleanup. The controller receives
all filesystem, repository, clock, command, process, legacy, and observer
operations through ports so its safety ordering is pure-testable.  A future
human-approved adapter may supply real ports; this module does not create a
fixture sample or close a fixture window.
"""
from __future__ import annotations

import argparse
import json
import re
import time
from dataclasses import dataclass
from functools import wraps
from typing import Any, Callable, Protocol

RUN_PREFIX = "/tmp/p1d."
STATE_NAME = "controller-state.json"
EVIDENCE_NAME = "controller-evidence.json"
APPROVED_MODULES = ("trace", "lifecycle", "ownership", "private_export", "correlation", "observer")
LEGACY_SEMANTIC_KEYS = ("started", "configured_hotkey_count", "binding_count", "lifecycle_watcher_active", "reconcile_active", "bar_timer_active", "bar_canvas_count")
ENVIRONMENT_KEYS = ("macos_build", "architecture", "hammerspoon_version", "branch", "head", "display", "settings")
MAX_TIMEOUT_SECONDS = 120
STARTUP_TIMEOUT_SECONDS = 30
SHA_RE = re.compile(r"^[0-9a-f]{40,64}$")
RUN_RE = re.compile(r"^/tmp/p1d\.[A-Za-z0-9]{6}$")


class ControllerError(RuntimeError):
    """A refusal or incomplete operation; callers must retain private evidence."""


def bounded_command(method):
    """Give every public controller command one non-extendable 120 s budget."""
    @wraps(method)
    def wrapped(self, *args, **kwargs):
        previous = self._deadline
        self._deadline = self.clock() + MAX_TIMEOUT_SECONDS
        try:
            return method(self, *args, **kwargs)
        finally:
            self._deadline = previous
    return wrapped


class Ports(Protocol):
    # Repository values are repo-relative paths, grouped by git status class.
    def repo_changes(self) -> dict[str, list[str]]: ...
    def head_commit(self) -> str: ...
    def commit_exists(self, commit: str) -> bool: ...
    def environment(self) -> dict[str, str]: ...
    def make_private_run_dir(self, prefix: str) -> str: ...
    def private_dir(self, path: str) -> bool: ...
    def private_file(self, path: str) -> bool: ...
    def read_text(self, path: str) -> str: ...
    def write_private_json(self, path: str, value: dict[str, Any]) -> None: ...
    def read_private_json(self, path: str) -> dict[str, Any]: ...
    def run(self, argv: tuple[str, ...], *, timeout: int) -> None: ...
    def spawn_fixture(self, run_dir: str, *, clock_kind: str, timeout: int) -> int: ...
    def fixture_identity(self, pid: int, run_dir: str) -> dict[str, str]: ...
    def process_alive(self, pid: int, identity: dict[str, str] | None = None) -> bool: ...
    def socket_exists(self, path: str) -> bool: ...
    def wait_marker(self, trace_path: str, marker: str, *, sample_id: str, timeout: int) -> None: ...
    # One bounded fixture IPC request.  It returns only the private retained
    # response; the controller never prints its token or alias.
    def fixture_request(self, run_dir: str, command: str, sample_id: str, token: str | None, *, timeout: int) -> dict[str, Any]: ...
    # `restore` is one semantic action: start, rebind configured hotkeys, then
    # return an observed state for exact comparison with `capture`.
    def legacy(self, action: str, **kwargs: Any) -> dict[str, Any]: ...
    def clear_modules(self, modules: tuple[str, ...]) -> None: ...
    def observer(self, action: str, **kwargs: Any) -> dict[str, Any]: ...
    def fixture_shutdown(self, run_dir: str, *, timeout: int) -> None: ...
    def terminate(self, pid: int, identity: dict[str, str], *, timeout: int) -> None: ...
    def wait_process(self, pid: int, identity: dict[str, str], *, timeout: int) -> bool: ...


@dataclass
class DirectAXVolumeController:
    ports: Ports
    clock: Callable[[], float] = time.monotonic
    _deadline: float | None = None

    def _timeout(self, cap: float = MAX_TIMEOUT_SECONDS) -> float:
        if self._deadline is None:
            raise ControllerError("controller deadline is not installed")
        remaining = self._deadline - self.clock()
        if remaining <= 0:
            raise ControllerError("command deadline exceeded")
        return min(cap, remaining)

    def _recover(self, state: dict[str, Any]) -> None:
        """Cleanup is a separate bounded recovery command, never extra sample time."""
        previous = self._deadline
        self._deadline = self.clock() + MAX_TIMEOUT_SECONDS
        try:
            self._abort(state, restoration_required=True)
        finally:
            self._deadline = previous

    def _require_execute(self, execute: bool) -> None:
        if execute is not True:
            raise ControllerError("refused: --execute is required")

    def _preflight(self) -> None:
        changes = self.ports.repo_changes()
        for category in ("staged", "unstaged", "untracked"):
            paths = changes.get(category, [])
            if not isinstance(paths, list):
                raise ControllerError("refused: invalid repo preflight")
            for path in paths:
                if not isinstance(path, str) or path.startswith("/") or ".." in path.split("/"):
                    raise ControllerError("refused: non-repo-relative preflight path")
            if paths:
                raise ControllerError("refused: repository has " + category + " changes")

    def _approval(self, approval_file: str, commit: str) -> None:
        if not isinstance(approval_file, str) or not approval_file.startswith("/"):
            raise ControllerError("refused: approval file must be an absolute owner-private path")
        if not self.ports.private_file(approval_file):
            raise ControllerError("refused: approval file is not owner-private 0600")
        # The intentionally tiny approval format avoids accepting a broad,
        # reusable approval.  It is private and commits only to this exact head.
        try:
            approval = json.loads(self.ports.read_text(approval_file))
        except (ValueError, TypeError):
            raise ControllerError("refused: invalid approval file") from None
        if not isinstance(approval, dict) or approval.get("approved_commit") != commit:
            raise ControllerError("refused: approval does not match frozen full commit")

    def _freeze(self, approval_file: str) -> str:
        self._preflight()
        commit = self.ports.head_commit()
        if not isinstance(commit, str) or not SHA_RE.fullmatch(commit) or not self.ports.commit_exists(commit):
            raise ControllerError("refused: HEAD is not a frozen full commit")
        self._approval(approval_file, commit)
        return commit

    @staticmethod
    def _state_path(run_dir: str) -> str:
        return run_dir + "/" + STATE_NAME

    @staticmethod
    def _evidence_path(run_dir: str) -> str:
        return run_dir + "/" + EVIDENCE_NAME

    def _valid_run_dir(self, run_dir: str) -> None:
        if not RUN_RE.fullmatch(run_dir) or not self.ports.private_dir(run_dir):
            raise ControllerError("refused: run directory must be owner-private /tmp/p1d.XXXXXX")

    def _load(self, run_dir: str) -> dict[str, Any]:
        self._valid_run_dir(run_dir)
        path = self._state_path(run_dir)
        if not self.ports.private_file(path):
            raise ControllerError("refused: missing or unsafe private state")
        state = self.ports.read_private_json(path)
        if not isinstance(state, dict) or state.get("run_dir") != run_dir:
            raise ControllerError("refused: invalid state")
        return state

    def _save(self, state: dict[str, Any]) -> None:
        self.ports.write_private_json(self._state_path(state["run_dir"]), state)
        if not self.ports.private_file(self._state_path(state["run_dir"])):
            raise ControllerError("private state write failed")

    def _record(self, state: dict[str, Any], event: str, **fields: Any) -> None:
        evidence = {"schema": "poc001-direct-ax-controller-v1", "frozen_commit": state["frozen_commit"],
                    "phase": state["phase"], "events": state.get("events", []) + [{"event": event, **fields}]}
        state["events"] = evidence["events"]
        self.ports.write_private_json(self._evidence_path(state["run_dir"]), evidence)
        if not self.ports.private_file(self._evidence_path(state["run_dir"])):
            raise ControllerError("private evidence write failed")

    @bounded_command
    def prepare(self, *, execute: bool, approval_file: str) -> str:
        self._require_execute(execute)
        commit = self._freeze(approval_file)
        environment = self.ports.environment()
        if not isinstance(environment, dict) or any(not isinstance(environment.get(key), str) or not environment[key] for key in ENVIRONMENT_KEYS):
            raise ControllerError("refused: incomplete environment evidence")
        if environment["head"] != commit:
            raise ControllerError("refused: environment HEAD differs from freeze")
        run_dir = self.ports.make_private_run_dir(RUN_PREFIX)
        self._valid_run_dir(run_dir)
        state = {"schema": "poc001-direct-ax-controller-v1", "run_dir": run_dir, "frozen_commit": commit,
                 "phase": "prepared", "fixture_pid": None, "fixture_identity": None, "fixture_run_dir": None,
                 "socket": run_dir + "/poc001-fixture.sock", "legacy_stopped": False, "legacy_baseline": None,
                 "observer_started": False, "next_generation": 1, "warm_rows": [], "cold_next_index": 1,
                 "cold_rows": [], "cold_cleanups": [], "cold_session_dirs": [], "events": []}
        # State/evidence are opened privately by the filesystem port before any write.
        self._save(state)
        self._record(state, "prepared", environment=environment)
        self._save(state)
        return run_dir

    def _legacy_baseline(self) -> dict[str, Any]:
        baseline = self.ports.legacy("capture", timeout=self._timeout())
        if not isinstance(baseline, dict):
            raise ControllerError("legacy capture failed")
        for key in LEGACY_SEMANTIC_KEYS:
            if key not in baseline:
                raise ControllerError("legacy capture missing " + key)
        if (baseline["started"] is not True or isinstance(baseline["binding_count"], bool)
                or not isinstance(baseline["binding_count"], int) or baseline["binding_count"] <= 0
                or isinstance(baseline["configured_hotkey_count"], bool)
                or not isinstance(baseline["configured_hotkey_count"], int)
                or baseline["configured_hotkey_count"] != baseline["binding_count"]):
            raise ControllerError("legacy capture is not shortcut-ready")
        if any(not isinstance(baseline[key], bool) for key in ("lifecycle_watcher_active", "reconcile_active", "bar_timer_active")) or isinstance(baseline["bar_canvas_count"], bool) or not isinstance(baseline["bar_canvas_count"], int) or baseline["bar_canvas_count"] < 0:
            raise ControllerError("legacy capture has invalid lifecycle state")
        return {key: baseline[key] for key in LEGACY_SEMANTIC_KEYS}

    def _legacy_restored(self, state: dict[str, Any]) -> bool:
        baseline = state.get("legacy_baseline")
        if not isinstance(baseline, dict):
            return False
        actual = self.ports.legacy("restore", expected=baseline, timeout=self._timeout())
        if not isinstance(actual, dict):
            return False
        state["legacy_restore_observed"] = {key: actual.get(key) for key in LEGACY_SEMANTIC_KEYS}
        return all(actual.get(key) == baseline.get(key) for key in LEGACY_SEMANTIC_KEYS)

    @bounded_command
    def status(self, *, run_dir: str) -> dict[str, Any]:
        state = self._load(run_dir)
        pid = state.get("fixture_pid")
        # Redacted status intentionally has no private path, token, PID, or alias.
        return {"phase": state.get("phase"), "fixture_expected": isinstance(pid, int),
                "fixture_alive": isinstance(pid, int) and self.ports.process_alive(pid, state.get("fixture_identity")),
                "socket_present": self.ports.socket_exists(state["socket"]),
                "legacy_stopped": state.get("legacy_stopped") is True,
                "observer_started": state.get("observer_started") is True}

    @bounded_command
    def warm_start(self, *, run_dir: str, execute: bool, approval_file: str) -> dict[str, Any]:
        self._require_execute(execute)
        state = self._load(run_dir)
        if state.get("phase") != "prepared":
            raise ControllerError("refused: warm-start requires prepared state")
        if state.get("fixture_pid") is not None or state.get("fixture_identity") is not None or self.ports.socket_exists(state["socket"]):
            raise ControllerError("refused: stale fixture PID or socket state")
        if self._freeze(approval_file) != state.get("frozen_commit"):
            raise ControllerError("refused: current freeze differs from prepared state")
        # Static build is deliberately before legacy stop and has an explicit bound.
        self.ports.run(("fixture-build", "canonical"), timeout=self._timeout())
        # Capture the complete semantic restoration target before mutating
        # legacy, then durably install it before the fixture/legacy handoff.
        state["legacy_baseline"] = self._legacy_baseline()
        state["phase"] = "cleanup_pending" # durable recovery intent precedes any runtime mutation.
        self._record(state, "cleanup_installed", legacy_binding_count=state["legacy_baseline"]["binding_count"])
        self._save(state)
        try:
            pid = self.ports.spawn_fixture(run_dir, clock_kind="mach_absolute", timeout=self._timeout())
            if not isinstance(pid, int) or pid <= 0:
                raise ControllerError("fixture launch failed")
            identity = self.ports.fixture_identity(pid, run_dir)
            if not isinstance(identity, dict): raise ControllerError("fixture identity capture failed")
            state["fixture_pid"], state["fixture_identity"] = pid, identity
            self._record(state, "fixture_launched")
            self._save(state)
            self.ports.wait_marker(run_dir + "/trace.ndjson", "run_started", sample_id="startup", timeout=self._timeout(STARTUP_TIMEOUT_SECONDS))
            self.ports.wait_marker(run_dir + "/trace.ndjson", "socket_ready", sample_id="startup", timeout=self._timeout(STARTUP_TIMEOUT_SECONDS))
            if not self.ports.process_alive(pid, identity) or not self.ports.socket_exists(state["socket"]):
                raise ControllerError("fixture startup stale or partial")
            self.ports.legacy("stop", timeout=self._timeout())
            if not self._legacy_stopped(state):
                raise ControllerError("legacy stop verification failed")
            state["legacy_stopped"] = True
            self._record(state, "legacy_stopped")
            self._save(state)
            self.ports.clear_modules(APPROVED_MODULES)
            observer = self.ports.observer("start", timeout=self._timeout())
            if observer.get("running") is not True:
                raise ControllerError("observer start verification failed")
            state["observer_started"] = True
            state["phase"] = "running"
            self._record(state, "running")
            self._save(state)
            return self.status(run_dir=run_dir)
        except BaseException:
            self._recover(state)
            raise

    def _zero_observer(self, status: dict[str, Any]) -> bool:
        correlation = status.get("correlation", {})
        return (status.get("running") is False and status.get("callbacks_open") == 0
                and status.get("active_timers") == 0 and status.get("window_effects") == 0
                and status.get("direct_application_watchers") == 0
                and status.get("direct_window_watchers") == 0
                and status.get("target_binding_armed") is False
                and correlation.get("map_count") == 0)

    def _abort(self, state: dict[str, Any], *, restoration_required: bool) -> dict[str, Any]:
        failures: list[str] = []
        try:
            self.ports.observer("abort_correlation", reason="controller_abort", timeout=self._timeout())
            stopped = self.ports.observer("stop_export", timeout=self._timeout(), path=state["run_dir"] + "/observer-export.json")
            if not self._zero_observer(stopped): failures.append("observer_not_quiescent")
        except Exception:
            failures.append("observer_cleanup")
        pid, identity = state.get("fixture_pid"), state.get("fixture_identity")
        if isinstance(pid, int) and isinstance(identity, dict):
            try: self.ports.fixture_shutdown(state.get("fixture_run_dir") or state["run_dir"], timeout=self._timeout())
            except Exception: failures.append("fixture_shutdown")
            if self.ports.process_alive(pid, identity):
                try: self.ports.terminate(pid, identity, timeout=self._timeout())
                except Exception: failures.append("fixture_terminate")
            try:
                if not self.ports.wait_process(pid, identity, timeout=self._timeout()): failures.append("fixture_wait")
            except Exception: failures.append("fixture_wait")
        if isinstance(pid, int) and (not isinstance(identity, dict) or self.ports.process_alive(pid, identity)): failures.append("fixture_still_alive")
        if self.ports.socket_exists(state["socket"]): failures.append("socket_present")
        try:
            if not self._legacy_restored(state):
                failures.append("legacy_restore_semantic")
        except Exception:
            failures.append("legacy_restore_semantic")
        state["observer_started"], state["legacy_stopped"] = False, False
        state["phase"] = "indeterminate" if failures else "cleaned"
        self._record(state, "abort_cleanup", outcome=state["phase"], failures=failures)
        self._save(state)
        if failures and restoration_required:
            raise ControllerError("cleanup indeterminate: " + ",".join(failures))
        return {"phase": state["phase"], "restoration_ok": not failures}

    def _private_path(self, state: dict[str, Any], name: str) -> str:
        return state["run_dir"] + "/" + name

    def _legacy_stopped(self, state: dict[str, Any]) -> bool:
        observed = self.ports.legacy("inspect", timeout=self._timeout())
        baseline = state.get("legacy_baseline", {})
        # Stopping is semantic, not merely `started == false`: no legacy
        # binding, lifecycle watcher, reconciler, or bar may overlap the POC.
        return (isinstance(observed, dict) and observed.get("started") is False
                and observed.get("binding_count") == 0
                and observed.get("lifecycle_watcher_active") is False
                and observed.get("reconcile_active") is False
                and observed.get("bar_timer_active") is False
                and observed.get("bar_canvas_count") == 0
                and isinstance(baseline, dict))

    def _fixture_running(self, state: dict[str, Any]) -> bool:
        pid, identity = state.get("fixture_pid"), state.get("fixture_identity")
        return isinstance(pid, int) and isinstance(identity, dict) and self.ports.process_alive(pid, identity) and self.ports.socket_exists(state["socket"])

    def _snapshot(self, state: dict[str, Any], name: str, *, expected: str) -> dict[str, Any]:
        """Persist observer facts plus independently verified fixture liveness."""
        path = self._private_path(state, name)
        status = self.ports.observer("snapshot", path=path, timeout=self._timeout())
        if not isinstance(status, dict) or not self.ports.private_file(path):
            raise ControllerError("observer snapshot failed")
        # Observer never claims fixture state.  The controller supplies that one
        # fact from its identity-checked process/socket port, then atomically
        # replaces the private snapshot wrapper consumed by the normalizer.
        snapshot = self.ports.read_private_json(path)
        if not isinstance(snapshot, dict): raise ControllerError("invalid observer snapshot")
        # The adapter returns the same read-only status it exported.  Reject an
        # acknowledgement-only response or a disagreement before wrapping it.
        if status.get("lifecycle") != snapshot.get("lifecycle") or status.get("correlation") != snapshot.get("correlation"):
            raise ControllerError("observer snapshot return disagrees")
        snapshot["fixture_running"] = self._fixture_running(state)
        self.ports.write_private_json(path, snapshot)
        correlation = snapshot.get("correlation", {})
        candidates = correlation.get("candidate_sources", {}) if isinstance(correlation, dict) else {}
        if expected == "pre_close":
            valid = (snapshot.get("lifecycle") == "running" and snapshot["fixture_running"] is True
                     and correlation.get("armed") is True and correlation.get("candidate_source") == "direct_ax"
                     and correlation.get("map_count") == 1 and candidates.get("complete") is False)
        else:
            valid = (snapshot.get("lifecycle") == "running" and snapshot["fixture_running"] is True
                     and correlation.get("armed") is False and correlation.get("candidate_source") is None
                     and correlation.get("map_count") == 0 and candidates.get("complete") is False)
        if not valid: raise ControllerError("observer snapshot facts failed")
        return snapshot

    def _wait_correlation(self, state: dict[str, Any], sample_id: str, stage: str) -> None:
        result = self.ports.observer("wait_correlation", sample_id=sample_id, stage=stage, timeout=self._timeout())
        if not isinstance(result, dict) or result.get("ready") is not True:
            self._record(state, "correlation_wait_timeout", sample_id=sample_id, stage=stage)
            self._save(state)
            raise ControllerError("correlation wait failed")

    @staticmethod
    def _failure_reason_class(error: BaseException) -> str:
        if isinstance(error, KeyboardInterrupt): return "interrupt"
        if isinstance(error, ControllerError): return "controller_error"
        if isinstance(error, RuntimeError): return "runtime_error"
        return "other_error"

    def _semantic_abort(self, state: dict[str, Any], reason: str) -> None:
        # Evidence has already been written by the caller.  Never retry a
        # sample: cleanup is the only permitted response to uncertainty.
        self._record(state, "semantic_abort", reason=reason)
        self._save(state)
        self._recover(state)

    @bounded_command
    def warm_sample(self, *, run_dir: str, generation: int, execute: bool,
                    approval_file: str) -> dict[str, Any]:
        self._require_execute(execute)
        state = self._load(run_dir)
        if self._freeze(approval_file) != state.get("frozen_commit"):
            raise ControllerError("refused: current freeze differs from state")
        if state.get("phase") != "running" or state.get("observer_started") is not True:
            raise ControllerError("refused: warm-sample requires running warm session")
        if not isinstance(generation, int) or isinstance(generation, bool) or not 1 <= generation <= 30:
            raise ControllerError("refused: warm generation must be 1..30")
        if generation != state.get("next_generation"):
            raise ControllerError("refused: warm generation is not the exact next generation")
        sample_id = f"warm-{generation:02d}"
        # Persist the in-flight generation before the sole arm/create sequence.
        state["phase"] = "warm_sample_pending"
        state["active_generation"] = generation
        self._record(state, "warm_sample_started", sample_id=sample_id, generation=generation)
        self._save(state)
        stage = "arm_correlation"
        try:
            armed = self.ports.observer("arm_correlation", generation=generation, source="direct_ax", sample_id=sample_id, timeout=self._timeout())
            if not isinstance(armed, dict) or armed.get("armed") is not True:
                raise ControllerError("correlation arm failed")
            response = self.ports.fixture_request(state["run_dir"], "create", sample_id, None, timeout=self._timeout())
            if not isinstance(response, dict) or response.get("status") != "accepted":
                raise ControllerError("fixture create failed")
            response_path = self._private_path(state, f"{sample_id}-create-response.json")
            self.ports.write_private_json(response_path, response)
            if not self.ports.private_file(response_path): raise ControllerError("private create response write failed")
            stage = "wait_fixture_create_visible"
            self.ports.wait_marker(self._private_path(state, "trace.ndjson"), "fixture_create_visible_completed", sample_id=sample_id, timeout=self._timeout())
            stage = "wait_map_ready"
            self._wait_correlation(state, sample_id, "map_ready")
            stage = "snapshot_pre_close"
            self._snapshot(state, f"{sample_id}-pre-close-status.json", expected="pre_close")
            token = response.get("fixture_token")
            if not isinstance(token, str) or not token: raise ControllerError("fixture create response lacks token")
            close = self.ports.fixture_request(state["run_dir"], "close", sample_id, token, timeout=self._timeout())
            if not isinstance(close, dict) or close.get("status") != "accepted": raise ControllerError("fixture close failed")
            stage = "wait_native_close"
            self.ports.wait_marker(self._private_path(state, "trace.ndjson"), "native_close_completed", sample_id=sample_id, timeout=self._timeout())
            stage = "wait_candidates_complete"
            self._wait_correlation(state, sample_id, "candidates_complete")
            stage = "finish_correlation"
            finished = self.ports.observer("finish_correlation", sample_id=sample_id, timeout=self._timeout())
            if not isinstance(finished, dict) or finished.get("finished") is not True: raise ControllerError("correlation finish failed")
            stage = "snapshot_post_finish"
            self._snapshot(state, f"{sample_id}-post-finish-status.json", expected="post_finish")
            stage = "export_running"
            exported = self.ports.observer("export_running", timeout=self._timeout(), path=self._private_path(state, f"{sample_id}-observer-export.json"))
            if not isinstance(exported, dict) or not self.ports.private_file(self._private_path(state, f"{sample_id}-observer-export.json")):
                raise ControllerError("running observer export failed")
            row_path = self._private_path(state, f"{sample_id}-row.json")
            # The warm normalizer does not consume a stopped-session record;
            # pass the already-retained post-finish observation as its required
            # session input rather than synthesize a cleanup fact.
            stage = "normalize"
            self.ports.run(("normalizer", "warm", response_path, self._private_path(state, "trace.ndjson"), self._private_path(state, f"{sample_id}-observer-export.json"), self._private_path(state, f"{sample_id}-pre-close-status.json"), self._private_path(state, f"{sample_id}-post-finish-status.json"), self._private_path(state, f"{sample_id}-post-finish-status.json"), row_path), timeout=self._timeout())
            stage = "analyze"
            result_path = self._private_path(state, f"{sample_id}-sample-result.json")
            self.ports.run(("analyzer", "sample", "warm", row_path, result_path), timeout=self._timeout())
            result = self.ports.read_private_json(result_path)
            if result.get("analysis_status") != "complete" or result.get("outcome") != "pass":
                raise ControllerError("sample analyzer substantive failure")
            # Append only after both normalizer and analyzer have validated it.
            row = self.ports.read_private_json(row_path)
            state["warm_rows"] = state.get("warm_rows", []) + [row]
            state["next_generation"] = generation + 1
            state.pop("active_generation", None)
            state["phase"] = "running"
            self._record(state, "warm_sample_validated", sample_id=sample_id, generation=generation)
            self._save(state)
            return {"phase": "running", "next_generation": state["next_generation"], "samples_completed": len(state["warm_rows"])}
        except BaseException as error:
            substantive = isinstance(error, ControllerError) and str(error) == "sample analyzer substantive failure"
            primary = {"stage": stage, "reason_class": self._failure_reason_class(error)}
            self._record(state, "warm_sample_primary_failure", **primary)
            self._save(state)
            cleanup_outcome = "cleaned"
            try:
                self._semantic_abort(state, "warm_sample_substantive_failure" if substantive else "warm_sample_failed")
            except BaseException:
                cleanup_outcome = "indeterminate"
            # A schema-valid analyzer rejection is evidence of a failed class,
            # whereas a timeout/normalizer/harness failure is indeterminate.
            state["phase"] = "failed" if substantive else "indeterminate"
            state["last_failure"] = {**primary, "cleanup_outcome": cleanup_outcome}
            self._record(state, "warm_sample_cleanup_outcome", **primary, cleanup_outcome=cleanup_outcome)
            self._record(state, "warm_sample_terminal", outcome=state["phase"])
            self._save(state)
            # Cleanup uncertainty is separately retained; never mask the
            # primary failure that caused this sample to stop.
            raise error

    @bounded_command
    def warm_finish(self, *, run_dir: str, execute: bool, approval_file: str) -> dict[str, Any]:
        self._require_execute(execute)
        state = self._load(run_dir)
        if self._freeze(approval_file) != state.get("frozen_commit"):
            raise ControllerError("refused: current freeze differs from state")
        if state.get("phase") != "running" or state.get("next_generation") != 31 or len(state.get("warm_rows", [])) != 30:
            raise ControllerError("refused: warm-finish requires exactly 30 validated rows")
        state["phase"] = "warm_finish_pending"; self._record(state, "warm_finish_started"); self._save(state)
        try:
            stopped = self.ports.observer("stop_export", timeout=self._timeout(), path=self._private_path(state, "warm-final-observer-export.json"))
            if not self._zero_observer(stopped): raise ControllerError("observer final quiesce failed")
            pid, identity = state.get("fixture_pid"), state.get("fixture_identity")
            self.ports.fixture_shutdown(state["run_dir"], timeout=self._timeout())
            if isinstance(pid, int) and isinstance(identity, dict) and self.ports.process_alive(pid, identity):
                self.ports.terminate(pid, identity, timeout=self._timeout())
            if isinstance(pid, int) and isinstance(identity, dict) and not self.ports.wait_process(pid, identity, timeout=self._timeout()): raise ControllerError("fixture final wait failed")
            if self.ports.socket_exists(state["socket"]): raise ControllerError("fixture socket remains")
            restored = self._legacy_restored(state)
            observed = state.get("legacy_restore_observed", {})
            fixture_absent = not (isinstance(pid, int) and isinstance(identity, dict) and self.ports.process_alive(pid, identity))
            socket_absent = not self.ports.socket_exists(state["socket"])
            cleanup = self._cleanup_record(state, stopped, fixture_absent=fixture_absent,
                                           socket_absent=socket_absent, restored=restored)
            cleanup_path = self._private_path(state, "class-final-cleanup.json"); self.ports.write_private_json(cleanup_path, cleanup)
            class_path = self._private_path(state, "warm-class.json"); self.ports.write_private_json(class_path, {"samples": state["warm_rows"], "class_final_cleanup": cleanup})
            result_path = self._private_path(state, "warm-class-result.json"); self.ports.run(("analyzer", "class", "warm", class_path, result_path), timeout=self._timeout())
            result = self.ports.read_private_json(result_path)
            state["observer_started"], state["legacy_stopped"] = False, False
            state["fixture_pid"], state["fixture_identity"] = None, None
            state["phase"] = "passed" if result.get("outcome") == "pass" else "failed"
            self._record(state, "warm_finish_result", outcome=state["phase"]); self._save(state)
            return {"phase": state["phase"]}
        except BaseException:
            self._semantic_abort(state, "warm_finish_failed")
            raise

    def _cleanup_record(self, state: dict[str, Any], stopped: dict[str, Any], *, fixture_absent: bool,
                        socket_absent: bool, restored: bool) -> dict[str, Any]:
        observed = state.get("legacy_restore_observed", {})
        baseline = state["legacy_baseline"]
        # This is strictly an observation wrapper. No field claims quiescence
        # without the stop/export response, checked fixture identity, or exact
        # semantic legacy comparison that supplied it.
        return {
            "observer_stopped": stopped.get("running") is False,
            "callbacks_open": stopped.get("callbacks_open"),
            "active_timers": stopped.get("active_timers"),
            "window_effects": stopped.get("window_effects"),
            "map_count": stopped.get("correlation", {}).get("map_count"),
            "fixture_process_absent": fixture_absent,
            "fixture_socket_absent": socket_absent,
            "legacy_restored": restored,
            "legacy_binding_count_expected": baseline["binding_count"],
            "legacy_binding_count_actual": observed.get("binding_count"),
            "legacy_lifecycle_watcher_expected": baseline["lifecycle_watcher_active"],
            "legacy_lifecycle_watcher_actual": observed.get("lifecycle_watcher_active"),
            "legacy_reconcile_expected": baseline["reconcile_active"],
            "legacy_reconcile_actual": observed.get("reconcile_active"),
            "legacy_bar_expected": baseline["bar_timer_active"],
            "legacy_bar_actual": observed.get("bar_timer_active"),
        }

    def _cold_stop_and_restore(self, state: dict[str, Any], sample_id: str) -> tuple[dict[str, Any], dict[str, Any]]:
        """Stop one cold session and retain facts needed by the normalizer."""
        stopped = self.ports.observer("stop_export", timeout=self._timeout(), path=self._private_path(state, f"{sample_id}-final-observer-export.json"))
        if not self._zero_observer(stopped):
            raise ControllerError("cold observer final quiesce failed")
        pid, identity = state.get("fixture_pid"), state.get("fixture_identity")
        self.ports.fixture_shutdown(state.get("fixture_run_dir") or state["run_dir"], timeout=self._timeout())
        if isinstance(pid, int) and isinstance(identity, dict) and self.ports.process_alive(pid, identity):
            self.ports.terminate(pid, identity, timeout=self._timeout())
        if isinstance(pid, int) and isinstance(identity, dict) and not self.ports.wait_process(pid, identity, timeout=self._timeout()):
            raise ControllerError("cold fixture final wait failed")
        fixture_absent = not (isinstance(pid, int) and isinstance(identity, dict) and self.ports.process_alive(pid, identity))
        socket_absent = not self.ports.socket_exists(state["socket"])
        if not fixture_absent or not socket_absent:
            raise ControllerError("cold fixture cleanup incomplete")
        restored = self._legacy_restored(state)
        cleanup = self._cleanup_record(state, stopped, fixture_absent=fixture_absent, socket_absent=socket_absent, restored=restored)
        final_session = {"callbacks_open": stopped.get("callbacks_open"), "active_timers": stopped.get("active_timers"),
                         "window_effects": stopped.get("window_effects"), "observer_running": stopped.get("running") is True,
                         "fixture_running": not fixture_absent, "fixture_socket_present": not socket_absent}
        self.ports.write_private_json(self._private_path(state, f"{sample_id}-final-session-status.json"), final_session)
        if not self.ports.private_file(self._private_path(state, f"{sample_id}-final-session-status.json")):
            raise ControllerError("cold final session write failed")
        if not restored:
            raise ControllerError("cold legacy restore semantic failure")
        return cleanup, final_session

    @bounded_command
    def cold_sample(self, *, run_dir: str, index: int, execute: bool, approval_file: str) -> dict[str, Any]:
        self._require_execute(execute)
        state = self._load(run_dir)
        if self._freeze(approval_file) != state.get("frozen_commit"):
            raise ControllerError("refused: current freeze differs from state")
        # Cold runs are a separately gated continuation: a failed warm class is
        # not silently converted into permission to gather cold timing evidence.
        if state.get("phase") not in {"passed", "cold_ready"}:
            raise ControllerError("refused: cold-sample requires finalized passing warm class")
        if not isinstance(index, int) or isinstance(index, bool) or not 1 <= index <= 5:
            raise ControllerError("refused: cold index must be 1..5")
        if index != state.get("cold_next_index"):
            raise ControllerError("refused: cold index is not the exact next index")
        if state.get("observer_started") is True or state.get("legacy_stopped") is True or state.get("fixture_pid") is not None or state.get("fixture_identity") is not None or self.ports.socket_exists(state["socket"]):
            raise ControllerError("refused: stale cold session state")
        sample_id = f"cold-{index:02d}"
        # Capture and persist recovery intent before any fixture/legacy mutation.
        state["legacy_baseline"] = self._legacy_baseline()
        state["phase"] = "cold_sample_pending"; state["active_cold_index"] = index
        self._record(state, "cold_cleanup_installed", sample_id=sample_id, index=index,
                     legacy_binding_count=state["legacy_baseline"]["binding_count"])
        self._save(state)
        try:
            # TraceWriter rejects an existing trace. Each cold sample therefore
            # owns a new private fixture directory/socket, while the controller
            # run retains the evidence paths and aggregate state.
            fixture_run_dir = self.ports.make_private_run_dir(RUN_PREFIX)
            if not self.ports.private_dir(fixture_run_dir): raise ControllerError("cold fixture directory is unsafe")
            state["fixture_run_dir"] = fixture_run_dir
            state["socket"] = fixture_run_dir + "/poc001-fixture.sock"
            state["cold_session_dirs"] = state.get("cold_session_dirs", []) + [fixture_run_dir]
            self._record(state, "cold_fixture_session_allocated", sample_id=sample_id); self._save(state)
            self.ports.run(("fixture-build", "canonical"), timeout=self._timeout())
            pid = self.ports.spawn_fixture(fixture_run_dir, clock_kind="mach_absolute", timeout=self._timeout())
            if not isinstance(pid, int) or pid <= 0: raise ControllerError("cold fixture launch failed")
            identity = self.ports.fixture_identity(pid, fixture_run_dir)
            if not isinstance(identity, dict): raise ControllerError("cold fixture identity capture failed")
            state["fixture_pid"], state["fixture_identity"] = pid, identity
            self._record(state, "cold_fixture_launched", sample_id=sample_id); self._save(state)
            fixture_trace = fixture_run_dir + "/trace.ndjson"
            self.ports.wait_marker(fixture_trace, "run_started", sample_id="startup", timeout=self._timeout(STARTUP_TIMEOUT_SECONDS))
            self.ports.wait_marker(fixture_trace, "socket_ready", sample_id="startup", timeout=self._timeout(STARTUP_TIMEOUT_SECONDS))
            if not self._fixture_running(state): raise ControllerError("cold fixture startup stale or partial")
            self.ports.legacy("stop", timeout=self._timeout())
            if not self._legacy_stopped(state): raise ControllerError("cold legacy stop verification failed")
            state["legacy_stopped"] = True; self._record(state, "cold_legacy_stopped", sample_id=sample_id); self._save(state)
            self.ports.clear_modules(APPROVED_MODULES)
            observer = self.ports.observer("start", timeout=self._timeout())
            if not isinstance(observer, dict) or observer.get("running") is not True: raise ControllerError("cold observer start verification failed")
            state["observer_started"] = True; self._record(state, "cold_observer_started", sample_id=sample_id); self._save(state)
            # Fresh process/module session means generation is exactly one for
            # every cold sample; sample scope is installed before the one arm.
            armed = self.ports.observer("arm_correlation", generation=1, source="direct_ax", sample_id=sample_id, timeout=self._timeout())
            if not isinstance(armed, dict) or armed.get("armed") is not True: raise ControllerError("cold correlation arm failed")
            response = self.ports.fixture_request(fixture_run_dir, "create", sample_id, None, timeout=self._timeout())
            if not isinstance(response, dict) or response.get("status") != "accepted": raise ControllerError("cold fixture create failed")
            response_path = self._private_path(state, f"{sample_id}-create-response.json")
            self.ports.write_private_json(response_path, response)
            if not self.ports.private_file(response_path): raise ControllerError("cold private create response write failed")
            self.ports.wait_marker(fixture_trace, "fixture_create_visible_completed", sample_id=sample_id, timeout=self._timeout())
            self._wait_correlation(state, sample_id, "map_ready")
            self._snapshot(state, f"{sample_id}-pre-close-status.json", expected="pre_close")
            token = response.get("fixture_token")
            if not isinstance(token, str) or not token: raise ControllerError("cold fixture create response lacks token")
            close = self.ports.fixture_request(fixture_run_dir, "close", sample_id, token, timeout=self._timeout())
            if not isinstance(close, dict) or close.get("status") != "accepted": raise ControllerError("cold fixture close failed")
            self.ports.wait_marker(fixture_trace, "native_close_completed", sample_id=sample_id, timeout=self._timeout())
            self._wait_correlation(state, sample_id, "candidates_complete")
            finished = self.ports.observer("finish_correlation", sample_id=sample_id, timeout=self._timeout())
            if not isinstance(finished, dict) or finished.get("finished") is not True: raise ControllerError("cold correlation finish failed")
            self._snapshot(state, f"{sample_id}-post-finish-status.json", expected="post_finish")
            exported = self.ports.observer("export_running", timeout=self._timeout(), path=self._private_path(state, f"{sample_id}-observer-export.json"))
            if not isinstance(exported, dict) or not self.ports.private_file(self._private_path(state, f"{sample_id}-observer-export.json")):
                raise ControllerError("cold running observer export failed")
            cleanup, _ = self._cold_stop_and_restore(state, sample_id)
            cleanup_path = self._private_path(state, f"{sample_id}-cleanup.json"); self.ports.write_private_json(cleanup_path, cleanup)
            final_path = self._private_path(state, f"{sample_id}-final-session-status.json")
            row_path = self._private_path(state, f"{sample_id}-row.json")
            self.ports.run(("normalizer", "cold", response_path, fixture_trace, self._private_path(state, f"{sample_id}-observer-export.json"), self._private_path(state, f"{sample_id}-pre-close-status.json"), self._private_path(state, f"{sample_id}-post-finish-status.json"), final_path, row_path), timeout=self._timeout())
            result_path = self._private_path(state, f"{sample_id}-sample-result.json")
            self.ports.run(("analyzer", "sample", "cold", row_path, result_path), timeout=self._timeout())
            result = self.ports.read_private_json(result_path)
            if result.get("analysis_status") != "complete" or result.get("outcome") != "pass":
                raise ControllerError("cold sample analyzer substantive failure")
            row = self.ports.read_private_json(row_path)
            state["cold_rows"] = state.get("cold_rows", []) + [row]
            state["cold_cleanups"] = state.get("cold_cleanups", []) + [cleanup]
            state["cold_next_index"] = index + 1
            state.pop("active_cold_index", None); state["observer_started"] = False; state["legacy_stopped"] = False
            state["fixture_pid"], state["fixture_identity"], state["fixture_run_dir"] = None, None, None
            state["socket"] = state["run_dir"] + "/poc001-fixture.sock"; state["phase"] = "cold_ready"
            self._record(state, "cold_sample_validated", sample_id=sample_id, generation=1); self._save(state)
            return {"phase": "cold_ready", "next_index": state["cold_next_index"], "samples_completed": len(state["cold_rows"])}
        except BaseException as error:
            substantive = isinstance(error, ControllerError) and str(error) == "cold sample analyzer substantive failure"
            self._semantic_abort(state, "cold_sample_substantive_failure" if substantive else "cold_sample_failed")
            state["phase"] = "failed" if substantive else "indeterminate"
            self._record(state, "cold_sample_terminal", outcome=state["phase"]); self._save(state)
            raise error

    @bounded_command
    def cold_finish(self, *, run_dir: str, execute: bool, approval_file: str) -> dict[str, Any]:
        self._require_execute(execute)
        state = self._load(run_dir)
        if self._freeze(approval_file) != state.get("frozen_commit"):
            raise ControllerError("refused: current freeze differs from state")
        if state.get("phase") != "cold_ready" or state.get("cold_next_index") != 6 or len(state.get("cold_rows", [])) != 5 or len(state.get("cold_cleanups", [])) != 5:
            raise ControllerError("refused: cold-finish requires exactly five cleaned validated rows")
        state["phase"] = "cold_finish_pending"; self._record(state, "cold_finish_started"); self._save(state)
        try:
            # All final facts originate in the fifth completed cold cleanup;
            # re-inspect legacy now so a stale restored runtime is not claimed.
            cleanup = state["cold_cleanups"][-1]
            current = self.ports.legacy("capture", timeout=self._timeout())
            for key in LEGACY_SEMANTIC_KEYS:
                if current.get(key) != state["legacy_baseline"].get(key):
                    cleanup = dict(cleanup); cleanup["legacy_restored"] = False
            cleanup_path = self._private_path(state, "cold-class-final-cleanup.json"); self.ports.write_private_json(cleanup_path, cleanup)
            class_path = self._private_path(state, "cold-class.json"); self.ports.write_private_json(class_path, {"samples": state["cold_rows"], "class_final_cleanup": cleanup})
            result_path = self._private_path(state, "cold-class-result.json"); self.ports.run(("analyzer", "class", "cold", class_path, result_path), timeout=self._timeout())
            result = self.ports.read_private_json(result_path)
            state["phase"] = "cold_passed" if result.get("outcome") == "pass" else "failed"
            self._record(state, "cold_finish_result", outcome=state["phase"]); self._save(state)
            return {"phase": state["phase"]}
        except BaseException:
            state["phase"] = "indeterminate"; self._record(state, "cold_finish_terminal", outcome="indeterminate"); self._save(state)
            raise

    @bounded_command
    def abort_cleanup(self, *, run_dir: str, execute: bool, approval_file: str) -> dict[str, Any]:
        self._require_execute(execute)
        state = self._load(run_dir)
        if self._freeze(approval_file) != state.get("frozen_commit"):
            raise ControllerError("refused: current freeze differs from state")
        if state.get("phase") == "cleaned":
            return {"phase": "cleaned", "restoration_ok": True}
        return self._abort(state, restoration_required=True)

    def command(self, name: str, *, execute: bool = False, approval_file: str | None = None,
                run_dir: str | None = None, generation: int | None = None) -> Any:
        """The explicit, separately approved command names of the CLI port."""
        if name == "status":
            if run_dir is None: raise ControllerError("refused: --run-dir is required")
            return self.status(run_dir=run_dir)
        if approval_file is None: raise ControllerError("refused: --approval-file is required")
        if name == "prepare": return self.prepare(execute=execute, approval_file=approval_file)
        if run_dir is None: raise ControllerError("refused: --run-dir is required")
        if name == "warm-start": return self.warm_start(run_dir=run_dir, execute=execute, approval_file=approval_file)
        if name == "warm-sample":
            if generation is None: raise ControllerError("refused: --generation is required")
            return self.warm_sample(run_dir=run_dir, generation=generation, execute=execute, approval_file=approval_file)
        if name == "warm-finish": return self.warm_finish(run_dir=run_dir, execute=execute, approval_file=approval_file)
        if name == "cold-sample":
            if generation is None: raise ControllerError("refused: --index is required")
            return self.cold_sample(run_dir=run_dir, index=generation, execute=execute, approval_file=approval_file)
        if name == "cold-finish": return self.cold_finish(run_dir=run_dir, execute=execute, approval_file=approval_file)
        if name == "abort-cleanup": return self.abort_cleanup(run_dir=run_dir, execute=execute, approval_file=approval_file)
        raise ControllerError("refused: unknown command")


def main(argv: list[str] | None = None) -> int:
    """Run only the reviewed real-host adapter through the four-command grammar."""
    # This script imports the real host only after parsing.  Disable bytecode
    # writes before that dynamic import: an otherwise clean repository is a
    # hard safety precondition for every mutating command.
    __import__("sys").dont_write_bytecode = True
    parser = argparse.ArgumentParser(description="POC-001 direct-AX controller.")
    parser.add_argument("command", choices=("prepare", "status", "warm-start", "warm-sample", "warm-finish", "cold-sample", "cold-finish", "abort-cleanup"))
    parser.add_argument("--execute", action="store_true")
    parser.add_argument("--approval-file")
    parser.add_argument("--run-dir")
    parser.add_argument("--generation", type=int)
    parser.add_argument("--index", type=int)
    args = parser.parse_args(argv)
    try:
        from direct_ax_volume_real_host import RealHostPorts
        root = __import__("pathlib").Path(__file__).resolve().parents[2]
        result = DirectAXVolumeController(RealHostPorts(root)).command(
            args.command, execute=args.execute, approval_file=args.approval_file, run_dir=args.run_dir, generation=args.generation if args.generation is not None else args.index)
        # status is intentionally redacted by the controller; prepare returns
        # only its owner-private run directory as the documented normal output.
        if isinstance(result, str): print(result)
        else: print(json.dumps(result, sort_keys=True, separators=(",", ":")))
        return 0
    except KeyboardInterrupt:
        print("interrupted: cleanup attempted", file=__import__("sys").stderr)
        return 130
    except (ControllerError, RuntimeError, OSError) as error:
        # Never reflect private paths, trace content, tokens, or subprocess output.
        print("refused: " + str(error).split("/")[0], file=__import__("sys").stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
