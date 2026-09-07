#!/usr/bin/env python3
"""Reviewed real-host ports for the POC-001 direct-AX controller.

This module performs no work when imported.  Its CLI is the only production-like
entry point and the controller still requires both --execute and a private,
exact-HEAD approval for every mutation.
"""
from __future__ import annotations

import json
import os
import re
import secrets
import signal
import stat
import string
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from typing import Any, Protocol

from direct_ax_volume_controller import APPROVED_MODULES, MAX_TIMEOUT_SECONDS


class HostError(RuntimeError): pass


class CommandRunner(Protocol):
    def run(self, argv: tuple[str, ...], *, timeout: int, env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]: ...
    def spawn(self, argv: tuple[str, ...], *, env: dict[str, str]) -> int: ...


class SubprocessRunner:
    """The sole subprocess boundary. No shell command strings are accepted."""
    def run(self, argv: tuple[str, ...], *, timeout: int, env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
        if timeout > MAX_TIMEOUT_SECONDS: raise HostError("timeout exceeds 120 seconds")
        return subprocess.run(argv, env=env, text=True, stdin=subprocess.DEVNULL,
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                              timeout=timeout, check=False)

    def spawn(self, argv: tuple[str, ...], *, env: dict[str, str]) -> int:
        return subprocess.Popen(argv, env=env, stdin=subprocess.DEVNULL,
                                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                                start_new_session=True).pid


class RealHostPorts:
    def __init__(self, repo_root: Path, runner: CommandRunner | None = None):
        self.root = repo_root.resolve()
        self.runner = runner or SubprocessRunner()
        self.fixture = self.root / "pocs/001-window-events-liveness/fixture"
        self.app = self.fixture / "build/POC001Fixture.app/Contents/MacOS/POC001Fixture"
        self.fixturectl = self.fixture / "build/POC001Fixture.app/Contents/MacOS/poc001-fixturectl"
        self.hs = "/opt/homebrew/bin/hs" if Path("/opt/homebrew/bin/hs").is_file() else "/usr/local/bin/hs"

    @staticmethod
    def _mode(path: str, wanted: int, kind: int) -> bool:
        try: meta = os.lstat(path)
        except OSError: return False
        return (not stat.S_ISLNK(meta.st_mode) and stat.S_IFMT(meta.st_mode) == kind
                and meta.st_uid == os.getuid() and stat.S_IMODE(meta.st_mode) == wanted)

    def private_dir(self, path: str) -> bool: return self._mode(path, 0o700, stat.S_IFDIR)
    def private_file(self, path: str) -> bool: return self._mode(path, 0o600, stat.S_IFREG)

    def repo_changes(self) -> dict[str, list[str]]:
        result = self.runner.run(("/usr/bin/git", "-C", str(self.root), "status", "--porcelain=v1", "-z"), timeout=30)
        if result.returncode: raise HostError("git status failed")
        output, groups = result.stdout, {"staged": [], "unstaged": [], "untracked": []}
        records = output.split("\0")
        index = 0
        while index < len(records):
            record = records[index]; index += 1
            if not record: continue
            if len(record) < 4: raise HostError("invalid git status record")
            xy, path = record[:2], record[3:]
            if xy == "??": groups["untracked"].append(path); continue
            if xy[0] != " ": groups["staged"].append(path)
            if xy[1] != " ": groups["unstaged"].append(path)
            # Renames/copies have an additional NUL pathname. Both are exact
            # preflight inputs; reject rather than silently overlooking either.
            if (xy[0] in "RC" or xy[1] in "RC") and index < len(records):
                old = records[index]; index += 1
                if old: groups["staged" if xy[0] in "RC" else "unstaged"].append(old)
        return groups

    def head_commit(self) -> str:
        result = self.runner.run(("/usr/bin/git", "-C", str(self.root), "rev-parse", "HEAD"), timeout=30)
        if result.returncode: raise HostError("cannot resolve HEAD")
        return result.stdout.strip()

    def commit_exists(self, commit: str) -> bool:
        result = self.runner.run(("/usr/bin/git", "-C", str(self.root), "cat-file", "-e", commit + "^{commit}"), timeout=30)
        return result.returncode == 0

    def environment(self) -> dict[str, str]:
        def text(argv: tuple[str, ...]) -> str:
            return self._checked(argv, 30).stdout.strip()
        # Hammerspoon provides the version/display/settings through one strict,
        # redacted JSON response; no raw defaults or display records are emitted.
        hs = self._hs("local s=hs.screen.primaryScreen(); __poc001_out({hammerspoon_version=tostring(hs.processInfo.version or ''),display=s and tostring(s:getUUID()) or '',settings=(hs.spaces and hs.spaces.screensHaveSeparateSpaces and hs.spaces.screensHaveSeparateSpaces()) and 'separate_spaces' or 'settings_unavailable'})")
        branch = text(("/usr/bin/git", "-C", str(self.root), "branch", "--show-current"))
        return {"macos_build": text(("/usr/bin/sw_vers", "-buildVersion")), "architecture": text(("/usr/bin/uname", "-m")),
                "hammerspoon_version": hs.get("hammerspoon_version", ""), "branch": branch,
                "head": self.head_commit(), "display": hs.get("display", ""), "settings": hs.get("settings", "")}

    def make_private_run_dir(self, prefix: str) -> str:
        if prefix != "/tmp/p1d.": raise HostError("invalid private run prefix")
        alphabet = string.ascii_letters + string.digits
        # tempfile.mkdtemp's platform suffix is not the controller's frozen
        # six-alphanumeric path grammar.  Create the exact path atomically;
        # collisions (including symlinks) are never followed or reused.
        old = os.umask(0o077)
        try:
            for _ in range(128):
                path = prefix + "".join(secrets.choice(alphabet) for _ in range(6))
                try:
                    os.mkdir(path, 0o700)
                except FileExistsError:
                    continue
                except OSError as error:
                    raise HostError("private run directory creation failed") from error
                meta = os.lstat(path)
                if (stat.S_ISDIR(meta.st_mode) and meta.st_uid == os.getuid()
                        and not stat.S_ISLNK(meta.st_mode)):
                    os.chmod(path, 0o700)
                    if self.private_dir(path): return path
                # Do not remove a path whose post-create identity is uncertain.
                raise HostError("private run directory verification failed")
        finally:
            os.umask(old)
        raise HostError("private run directory collision limit reached")

    def _read_nofollow(self, path: str) -> str:
        flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0)
        fd = os.open(path, flags)
        try:
            meta = os.fstat(fd)
            if not stat.S_ISREG(meta.st_mode) or meta.st_uid != os.getuid() or stat.S_IMODE(meta.st_mode) != 0o600:
                raise HostError("unsafe opened private file")
            return os.read(fd, meta.st_size + 1).decode("utf-8")
        finally: os.close(fd)

    def read_text(self, path: str) -> str: return self._read_nofollow(path)
    def read_private_json(self, path: str) -> dict[str, Any]: return json.loads(self._read_nofollow(path))

    def write_private_json(self, path: str, value: dict[str, Any]) -> None:
        parent = os.path.dirname(path)
        if not self.private_dir(parent): raise HostError("unsafe private parent")
        try:
            if os.path.lexists(path) and not self.private_file(path): raise HostError("unsafe private output")
            fd, temporary = tempfile.mkstemp(prefix=".controller-", dir=parent)
            try:
                os.fchmod(fd, 0o600)
                with os.fdopen(fd, "w", encoding="utf-8") as handle:
                    json.dump(value, handle, sort_keys=True, separators=(",", ":")); handle.write("\n")
                    handle.flush(); os.fsync(handle.fileno())
                if not self.private_file(temporary): raise HostError("unsafe temporary output")
                os.replace(temporary, path)
            finally:
                if os.path.exists(temporary): os.unlink(temporary)
        except UnboundLocalError: raise HostError("private output creation failed") from None

    def _checked(self, argv: tuple[str, ...], timeout: int, env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
        result = self.runner.run(argv, timeout=timeout, env=env)
        if result.returncode: raise HostError("command failed")
        return result

    def run(self, argv: tuple[str, ...], *, timeout: int) -> None:
        if timeout > MAX_TIMEOUT_SECONDS: raise HostError("timeout exceeds 120 seconds")
        if argv == ("fixture-build", "canonical"):
            self._checked(("/bin/sh", str(self.fixture / "scripts/build-fixture.sh")), timeout)
            if not self.app.is_file() or not self.fixturectl.is_file(): raise HostError("canonical fixture build missing")
            return
        if argv and argv[0] == "normalizer" and len(argv) == 9 and argv[1] in {"warm", "cold"}:
            self._checked((sys.executable, str(self.root / "pocs/001-window-events-liveness/direct_ax_volume_normalizer.py"), *argv[1:]), timeout)
            return
        if argv and argv[0] == "analyzer" and len(argv) == 5 and argv[1] in {"sample", "class"} and argv[2] in {"warm", "cold"}:
            # A substantive analyzer result intentionally exits 1.  The private
            # JSON result, not the return code, preserves pass/fail distinction.
            result = self.runner.run((sys.executable, str(self.root / "pocs/001-window-events-liveness/direct_ax_volume_analyzer.py"), *argv[1:]), timeout=timeout)
            if result.returncode not in (0, 1): raise HostError("analyzer command failed")
            return
        raise HostError("unapproved command")

    def spawn_fixture(self, run_dir: str, *, clock_kind: str, timeout: int) -> int:
        if clock_kind != "mach_absolute" or timeout > MAX_TIMEOUT_SECONDS or not self.app.is_file(): raise HostError("invalid fixture spawn")
        env = dict(os.environ, POC001_FIXTURE_RUN_DIR=run_dir, POC001_FIXTURE_CLOCK_KIND="mach_absolute")
        return self.runner.spawn((str(self.app),), env=env)

    def fixture_request(self, run_dir: str, command: str, sample_id: str, token: str | None, *, timeout: int) -> dict[str, Any]:
        if command not in {"create", "close", "shutdown"} or timeout > MAX_TIMEOUT_SECONDS:
            raise HostError("unapproved fixture request")
        request_id = "controller-" + command + "-" + sample_id
        argv = (str(self.fixturectl), run_dir, command, request_id, sample_id)
        if command == "close":
            if not isinstance(token, str) or not token: raise HostError("missing close token")
            argv = argv + (token,)
        result = self._checked(argv, timeout)
        try: response = json.loads(result.stdout)
        except ValueError: raise HostError("unsafe fixture response") from None
        if not isinstance(response, dict): raise HostError("unsafe fixture response")
        return response

    def fixture_identity(self, pid: int, run_dir: str) -> dict[str, str]:
        identity = {"executable": str(self.app), "run_dir": run_dir}
        if not self.process_alive(pid, identity): raise HostError("fixture identity mismatch")
        return identity

    def process_alive(self, pid: int, identity: dict[str, str] | None = None) -> bool:
        try: os.kill(pid, 0)
        except (ProcessLookupError, PermissionError): return False
        if identity is None: return True
        result = self.runner.run(("/bin/ps", "-p", str(pid), "-wwE", "-o", "command="), timeout=30)
        command = result.stdout.strip()
        return result.returncode == 0 and command.startswith(identity.get("executable", "")) and ("POC001_FIXTURE_RUN_DIR=" + identity.get("run_dir", "")) in command
    def socket_exists(self, path: str) -> bool:
        try: return stat.S_ISSOCK(os.lstat(path).st_mode)
        except OSError: return False

    def wait_marker(self, trace_path: str, marker: str, *, sample_id: str, timeout: int) -> None:
        if timeout > MAX_TIMEOUT_SECONDS: raise HostError("timeout exceeds 120 seconds")
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            try:
                text = self._read_nofollow(trace_path)
                lines = text.splitlines(keepends=True)
                for line in lines:
                    if not line.endswith("\n"): break # incomplete NDJSON is never parsed
                    row = json.loads(line)
                    if not isinstance(row, dict): raise HostError("invalid complete trace record")
                    if row.get("schema") != "poc001-fixture-v1" or row.get("sample_id") is None: raise HostError("invalid fixture trace schema")
                    if row.get("event") == marker and row.get("sample_id") == sample_id: return
            except FileNotFoundError: pass
            except json.JSONDecodeError: raise HostError("malformed complete trace record") from None
            time.sleep(0.05)
        raise HostError("marker timeout")

    _HS_ENVELOPE = "__POC001_SAFE_JSON__ "

    def _hs(self, body: str, timeout: float = 30) -> dict[str, Any]:
        # Hotkey binding may emit diagnostic lines. Accept only one final,
        # explicitly framed JSON object; diagnostics are discarded, never
        # retained or reflected to the caller.
        # `hs -c` returns Lua `print` output on stdout; direct `io.write` is
        # process-local and would silently lose the controller envelope.
        emitter = "local function __poc001_out(x) print('__POC001_SAFE_JSON__ '..hs.json.encode(x)) end; "
        # Every reviewed body must explicitly emit one envelope.  Do not rewrite
        # source text here: a textual replacement can unbalance Lua delimiters
        # and turn a harness defect into an opaque host-command failure.
        if body.count("__poc001_out(") != 1:
            raise HostError("invalid Hammerspoon envelope body")
        result = self._checked((self.hs, "-c", emitter + body), timeout)
        marked = [line[len(self._HS_ENVELOPE):] for line in result.stdout.splitlines()
                  if line.startswith(self._HS_ENVELOPE)]
        if len(marked) != 1:
            raise HostError("unsafe Hammerspoon response")
        try: value = json.loads(marked[0])
        except ValueError: raise HostError("unsafe Hammerspoon response") from None
        if not isinstance(value, dict): raise HostError("unsafe Hammerspoon response")
        return value

    def legacy(self, action: str, **kwargs: Any) -> dict[str, Any]:
        base = "local t=spoon['10bucks']; if type(t) ~= 'table' then error('missing loaded spoon') end; "
        inspect = "local l=t.lifecycle or {}; local b=t.bar or {}; local n,c=0,0; for _,v in pairs((t.config or {}).hotkeys or {}) do if v ~= false then n=n+1 end end; for _ in pairs(t.hotkeyBindings or {}) do c=c+1 end; local cc=0; for _ in pairs(b.canvases or {}) do cc=cc+1 end; return {started=t.started == true,configured_hotkey_count=n,binding_count=c,lifecycle_watcher_active=l.filter ~= nil,reconcile_active=l.reconcileTimer ~= nil,bar_timer_active=b.timer ~= nil,bar_canvas_count=cc}"
        if action in {"capture", "inspect"}: body = base + "__poc001_out((function() " + inspect + " end)())"
        elif action == "stop":  body = base + "t:stop(); __poc001_out((function() " + inspect + " end)())"
        elif action == "restore":
            # bindHotkeys is deliberately explicit and verified in the returned baseline.
            body = base + "t:start(); t:bindHotkeys(); __poc001_out((function() " + inspect + " end)())"
        else: raise HostError("unapproved legacy action")
        return self._hs(body, kwargs.get("timeout", 30))

    def clear_modules(self, modules: tuple[str, ...]) -> None:
        if modules != APPROVED_MODULES: raise HostError("unapproved modules")
        paths = ",".join(json.dumps(m) for m in modules)
        self._hs("local m={" + paths + "}; for _,n in ipairs(m) do package.loaded[n]=nil end; _G.__poc001_observer=nil; __poc001_out({ok=true})")

    def observer(self, action: str, **kwargs: Any) -> dict[str, Any]:
        observer_dir = json.dumps(str(self.root / "pocs/001-window-events-liveness") + "/")
        observer = json.dumps(str(self.root / "pocs/001-window-events-liveness/observer.lua"))
        base = "package.path=" + observer_dir + " .. '?.lua;' .. package.path; _G.__poc001_observer=_G.__poc001_observer or dofile(" + observer + "); local o=_G.__poc001_observer; "
        if action == "start": body = base + "o:start(); __poc001_out({running=o:status().lifecycle == 'running'})"
        elif action == "arm_correlation":
            # Scope arm/observed/candidate events to the exact warm sample
            # before any correlation callback can arrive.
            body = base + "o.trace:set_sample(" + json.dumps(kwargs["sample_id"]) + "); local ok=o:arm_fixture_correlation(" + str(int(kwargs["generation"])) + "," + json.dumps(kwargs["source"]) + "); __poc001_out({armed=ok})"
        elif action == "wait_correlation":
            stage, timeout = kwargs.get("stage"), kwargs.get("timeout")
            if stage not in {"map_ready", "candidates_complete"} or not isinstance(timeout, int) or timeout > MAX_TIMEOUT_SECONDS:
                raise HostError("invalid correlation wait")
            deadline = time.monotonic() + timeout
            while time.monotonic() < deadline:
                status = self._hs("local s=_G.__poc001_observer:status().correlation; __poc001_out({armed=s.armed,candidate_source=s.candidate_source,map_count=s.map_count,candidates_complete=s.candidate_sources.complete})")
                ready = (status.get("armed") is True and status.get("candidate_source") == "direct_ax" and status.get("map_count") == 1) if stage == "map_ready" else status.get("candidates_complete") is True
                if ready: return {"ready": True}
                time.sleep(0.05) # external controller wait; observer owns no poll/timer.
            return {"ready": False, "timed_out": True}
        elif action == "correlation_ready":
            body = base + "local s=o:status().correlation; __poc001_out({ready=s.armed and s.map_count == 1,candidates_complete=s.candidate_sources.complete,map_count=s.map_count})"
        elif action == "finish_correlation":
            body = base + "local ok=o:finish_fixture_correlation(); __poc001_out({finished=ok})"
        elif action == "snapshot":
            output = json.dumps(str(Path(kwargs["path"]).resolve()))
            body = base + "o:export_snapshot(" + output + "); __poc001_out(o:status())"
        elif action == "export_running":
            output = json.dumps(str(Path(kwargs["path"]).resolve()))
            body = base + "o:export_running(" + output + "); __poc001_out({ok=true})"
        elif action == "abort_correlation": body = base + "o:abort_fixture_correlation('controller_abort'); __poc001_out({ok=true})"
        elif action == "stop_export":
            export = json.dumps(str(Path(kwargs["path"]).resolve()))
            body = base + "o:stop(); o:export(" + export + "); local s=o:status(); __poc001_out({running=s.lifecycle == 'stopped',callbacks_open=s.callbacks.open,active_timers=s.active_timers,window_effects=s.window_effects,direct_application_watchers=s.direct_application_watchers,direct_window_watchers=s.direct_window_watchers,target_binding_armed=s.target_binding_armed,correlation={map_count=s.correlation.map_count}})"
        else: raise HostError("unapproved observer action")
        return self._hs(body, kwargs.get("timeout", 30))

    def fixture_shutdown(self, run_dir: str, *, timeout: int) -> None:
        if self.socket_exists(run_dir + "/poc001-fixture.sock"):
            self._checked((str(self.fixturectl), run_dir, "shutdown", "controller-abort", "controller-abort"), timeout)
    def terminate(self, pid: int, identity: dict[str, str], *, timeout: int) -> None:
        if timeout > MAX_TIMEOUT_SECONDS: raise HostError("timeout exceeds 120 seconds")
        if self.process_alive(pid, identity): os.kill(pid, signal.SIGTERM)
    def wait_process(self, pid: int, identity: dict[str, str], *, timeout: int) -> bool:
        deadline = time.monotonic() + min(timeout, MAX_TIMEOUT_SECONDS)
        while time.monotonic() < deadline:
            if not self.process_alive(pid, identity): return True
            time.sleep(0.05)
        return not self.process_alive(pid, identity)
