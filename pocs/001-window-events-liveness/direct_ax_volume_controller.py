#!/usr/bin/env python3
"""POC-001 direct-AX volume controller.

This is deliberately a small state machine, not a sample runner.  It exposes
only prepare, status, warm-start, and abort-cleanup.  The controller receives
all filesystem, repository, clock, command, process, legacy, and observer
operations through ports so its safety ordering is pure-testable.  A future
human-approved adapter may supply real ports; this module does not create a
fixture sample or close a fixture window.
"""
from __future__ import annotations

import argparse
import json
import re
from dataclasses import dataclass
from typing import Any, Protocol

RUN_PREFIX = "/tmp/p1d."
STATE_NAME = "controller-state.json"
EVIDENCE_NAME = "controller-evidence.json"
APPROVED_MODULES = ("trace", "lifecycle", "ownership", "private_export", "correlation", "observer")
MAX_TIMEOUT_SECONDS = 120
STARTUP_TIMEOUT_SECONDS = 30
SHA_RE = re.compile(r"^[0-9a-f]{40,64}$")
RUN_RE = re.compile(r"^/tmp/p1d\.[A-Za-z0-9]{6}$")


class ControllerError(RuntimeError):
    """A refusal or incomplete operation; callers must retain private evidence."""


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
    def process_alive(self, pid: int) -> bool: ...
    def socket_exists(self, path: str) -> bool: ...
    def wait_marker(self, trace_path: str, marker: str, *, timeout: int) -> None: ...
    def legacy(self, action: str) -> bool: ...
    def clear_modules(self, modules: tuple[str, ...]) -> None: ...
    def observer(self, action: str, **kwargs: Any) -> dict[str, Any]: ...
    def fixture_shutdown(self, run_dir: str, *, timeout: int) -> None: ...
    def terminate(self, pid: int, *, timeout: int) -> None: ...
    def wait_process(self, pid: int, *, timeout: int) -> bool: ...


@dataclass
class DirectAXVolumeController:
    ports: Ports

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

    def prepare(self, *, execute: bool, approval_file: str) -> str:
        self._require_execute(execute)
        commit = self._freeze(approval_file)
        run_dir = self.ports.make_private_run_dir(RUN_PREFIX)
        self._valid_run_dir(run_dir)
        state = {"schema": "poc001-direct-ax-controller-v1", "run_dir": run_dir, "frozen_commit": commit,
                 "phase": "prepared", "fixture_pid": None, "socket": run_dir + "/poc001-fixture.sock",
                 "legacy_stopped": False, "observer_started": False, "events": []}
        # State/evidence are opened privately by the filesystem port before any write.
        self._save(state)
        self._record(state, "prepared", environment=self.ports.environment())
        self._save(state)
        return run_dir

    def status(self, *, run_dir: str) -> dict[str, Any]:
        state = self._load(run_dir)
        pid = state.get("fixture_pid")
        # Redacted status intentionally has no private path, token, PID, or alias.
        return {"phase": state.get("phase"), "fixture_expected": isinstance(pid, int),
                "fixture_alive": isinstance(pid, int) and self.ports.process_alive(pid),
                "socket_present": self.ports.socket_exists(state["socket"]),
                "legacy_stopped": state.get("legacy_stopped") is True,
                "observer_started": state.get("observer_started") is True}

    def warm_start(self, *, run_dir: str, execute: bool, approval_file: str) -> dict[str, Any]:
        self._require_execute(execute)
        state = self._load(run_dir)
        if state.get("phase") != "prepared":
            raise ControllerError("refused: warm-start requires prepared state")
        if state.get("fixture_pid") is not None or self.ports.socket_exists(state["socket"]):
            raise ControllerError("refused: stale fixture PID or socket state")
        if self._freeze(approval_file) != state.get("frozen_commit"):
            raise ControllerError("refused: current freeze differs from prepared state")
        # Static build is deliberately before legacy stop and has an explicit bound.
        self.ports.run(("fixture-build", "canonical"), timeout=MAX_TIMEOUT_SECONDS)
        state["phase"] = "cleanup_pending" # durable recovery intent precedes any runtime mutation.
        self._record(state, "cleanup_installed")
        self._save(state)
        try:
            pid = self.ports.spawn_fixture(run_dir, clock_kind="mach_absolute", timeout=MAX_TIMEOUT_SECONDS)
            if not isinstance(pid, int) or pid <= 0:
                raise ControllerError("fixture launch failed")
            state["fixture_pid"] = pid
            self._record(state, "fixture_launched")
            self._save(state)
            self.ports.wait_marker(run_dir + "/trace.ndjson", "run_started", timeout=STARTUP_TIMEOUT_SECONDS)
            self.ports.wait_marker(run_dir + "/trace.ndjson", "socket_ready", timeout=STARTUP_TIMEOUT_SECONDS)
            if not self.ports.process_alive(pid) or not self.ports.socket_exists(state["socket"]):
                raise ControllerError("fixture startup stale or partial")
            if not self.ports.legacy("stop") or self.ports.legacy("verify_running"):
                raise ControllerError("legacy stop verification failed")
            state["legacy_stopped"] = True
            self._record(state, "legacy_stopped")
            self._save(state)
            self.ports.clear_modules(APPROVED_MODULES)
            observer = self.ports.observer("start")
            if observer.get("running") is not True:
                raise ControllerError("observer start verification failed")
            state["observer_started"] = True
            state["phase"] = "running"
            self._record(state, "running")
            self._save(state)
            return self.status(run_dir=run_dir)
        except Exception:
            self._abort(state, restoration_required=True)
            raise

    def _zero_observer(self, status: dict[str, Any]) -> bool:
        correlation = status.get("correlation", {})
        return (status.get("callbacks_open") == 0 and status.get("active_timers") == 0
                and status.get("window_effects") == 0 and correlation.get("map_count") == 0)

    def _abort(self, state: dict[str, Any], *, restoration_required: bool) -> dict[str, Any]:
        failures: list[str] = []
        try:
            self.ports.observer("abort_correlation", reason="controller_abort")
            stopped = self.ports.observer("stop_export", path=state["run_dir"] + "/observer-export.json")
            if not self._zero_observer(stopped): failures.append("observer_not_quiescent")
        except Exception:
            failures.append("observer_cleanup")
        pid = state.get("fixture_pid")
        if isinstance(pid, int):
            try: self.ports.fixture_shutdown(state["run_dir"], timeout=MAX_TIMEOUT_SECONDS)
            except Exception: failures.append("fixture_shutdown")
            if self.ports.process_alive(pid):
                try: self.ports.terminate(pid, timeout=MAX_TIMEOUT_SECONDS)
                except Exception: failures.append("fixture_terminate")
            try:
                if not self.ports.wait_process(pid, timeout=MAX_TIMEOUT_SECONDS): failures.append("fixture_wait")
            except Exception: failures.append("fixture_wait")
        if isinstance(pid, int) and self.ports.process_alive(pid): failures.append("fixture_still_alive")
        if self.ports.socket_exists(state["socket"]): failures.append("socket_present")
        try:
            if not self.ports.legacy("start") or not self.ports.legacy("verify_running"):
                failures.append("legacy_restore")
        except Exception:
            failures.append("legacy_restore")
        state["observer_started"], state["legacy_stopped"] = False, False
        state["phase"] = "indeterminate" if failures else "cleaned"
        self._record(state, "abort_cleanup", outcome=state["phase"], failures=failures)
        self._save(state)
        if failures and restoration_required:
            raise ControllerError("cleanup indeterminate: " + ",".join(failures))
        return {"phase": state["phase"], "restoration_ok": not failures}

    def abort_cleanup(self, *, run_dir: str, execute: bool, approval_file: str) -> dict[str, Any]:
        self._require_execute(execute)
        state = self._load(run_dir)
        if self._freeze(approval_file) != state.get("frozen_commit"):
            raise ControllerError("refused: current freeze differs from state")
        if state.get("phase") == "cleaned":
            return {"phase": "cleaned", "restoration_ok": True}
        return self._abort(state, restoration_required=True)

    def command(self, name: str, *, execute: bool = False, approval_file: str | None = None,
                run_dir: str | None = None) -> Any:
        """The four explicit command names used by a future approved CLI port."""
        if name == "status":
            if run_dir is None: raise ControllerError("refused: --run-dir is required")
            return self.status(run_dir=run_dir)
        if approval_file is None: raise ControllerError("refused: --approval-file is required")
        if name == "prepare": return self.prepare(execute=execute, approval_file=approval_file)
        if run_dir is None: raise ControllerError("refused: --run-dir is required")
        if name == "warm-start": return self.warm_start(run_dir=run_dir, execute=execute, approval_file=approval_file)
        if name == "abort-cleanup": return self.abort_cleanup(run_dir=run_dir, execute=execute, approval_file=approval_file)
        raise ControllerError("refused: unknown command")


def main(argv: list[str] | None = None) -> int:
    """Expose the frozen command grammar without embedding unreviewed live ports.

    The future live adapter must instantiate ``DirectAXVolumeController`` with
    reviewed ports.  This source-only entry point therefore cannot mutate the
    host, even if somebody supplies ``--execute``.
    """
    parser = argparse.ArgumentParser(description="POC-001 direct-AX controller (no bundled live adapter).")
    parser.add_argument("command", choices=("prepare", "status", "warm-start", "abort-cleanup"))
    parser.add_argument("--execute", action="store_true")
    parser.add_argument("--approval-file")
    parser.add_argument("--run-dir")
    parser.parse_args(argv)
    # Do not print paths, input content, or another sensitive value.
    raise SystemExit("refused: no live ports are bundled in the source/test controller")


if __name__ == "__main__":
    main()
