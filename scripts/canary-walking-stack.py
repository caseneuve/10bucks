#!/usr/bin/env python3
"""Bounded, approval-gated Canary A capture and automatic restoration runner.

This runner never creates, closes, or focuses windows. `start-capture` swaps
only after it has stopped and verified stable. `finish` always exports the
candidate aggregate then restores and semantically verifies stable.
"""
from __future__ import annotations
import argparse, hashlib, json, os, stat, subprocess, sys, tempfile, time
from pathlib import Path
from typing import Callable

ROOT = Path(__file__).resolve().parents[1]
SPOON = ROOT / "10bucks.spoon"
DEFAULT_LINK = Path.home() / ".hammerspoon/Spoons/10bucks.spoon"
DEFAULT_CONFIG = Path.home() / ".config/10bucks/config.lua"
STATE = Path.home() / ".cache/10bucks-walking-stack-canary.json"
DEADLINE, MARKER = 120, "__10BUCKS_CANARY_JSON__:"


def shell(args, *, timeout=DEADLINE, cwd=ROOT, check=True):
    if not 0 < timeout <= DEADLINE: raise ValueError("command timeout must be in 1..120 seconds")
    return subprocess.run(args, cwd=cwd, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                          timeout=timeout, check=check)

def run(args, **kwargs): return shell(args, **kwargs).stdout.strip()
def digest(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def mode(path): return stat.S_IMODE(path.stat().st_mode)
def candidate_commit(): return run(["git", "rev-parse", "HEAD"])
def link_target(link): return os.readlink(link) if link.is_symlink() else None

def require_owner_private_regular(path, label, *, exact_mode=None):
    info = path.lstat()
    if stat.S_ISLNK(info.st_mode) or not stat.S_ISREG(info.st_mode):
        raise RuntimeError(label + " must be a regular non-symlink file")
    actual_mode = stat.S_IMODE(info.st_mode)
    if info.st_uid != os.getuid() or (actual_mode & 0o077) != 0 or (exact_mode is not None and actual_mode != exact_mode):
        required = ("mode %04o" % exact_mode) if exact_mode is not None else "owner-private mode"
        raise RuntimeError(label + " must be owned by current UID and " + required)

def atomic_regular_replace(source, target, target_mode, label):
    require_owner_private_regular(source, label + " source")
    require_owner_private_regular(target, label + " destination")
    fd, temporary = tempfile.mkstemp(prefix=target.name + ".", dir=target.parent)
    try:
        with os.fdopen(fd, "wb") as output:
            output.write(source.read_bytes())
            output.flush()
            os.fsync(output.fileno())
        os.chmod(temporary, target_mode)
        os.replace(temporary, target)
    except BaseException:
        Path(temporary).unlink(missing_ok=True)
        raise
    require_owner_private_regular(target, label + " destination")
    if mode(target) != target_mode: raise RuntimeError(label + " replacement did not preserve mode")

def parse_envelope(text):
    rows = [line[len(MARKER):] for line in text.splitlines() if line.startswith(MARKER)]
    if len(rows) != 1: raise RuntimeError("hs response did not contain exactly one framed JSON envelope")
    value = json.loads(rows[0])
    if not isinstance(value, dict): raise RuntimeError("hs envelope must be an object")
    return value

def hs_query(lua, *, check=True):
    # Logs before/after return values are deliberately ignored; only our marker is trusted.
    wrapped = "local ok,v=pcall(function() " + lua + " end); print('" + MARKER + "'..hs.json.encode({ok=ok,value=v,error=ok and nil or tostring(v)}))"
    result = shell(["hs", "-c", wrapped], check=check)
    envelope = parse_envelope(result.stdout)
    if not envelope.get("ok"): raise RuntimeError("hs query failed: " + str(envelope.get("error")))
    return envelope.get("value")

def reload_and_wait():
    # hs IPC dies during reload and commonly exits 69. That is expected only for this request.
    result = shell(["hs", "-c", "hs.reload()"], check=False)
    if result.returncode not in (0, 69):
        raise RuntimeError("reload request failed: " + (result.stderr.strip() or str(result.returncode)))
    end = time.monotonic() + DEADLINE
    last = None
    while time.monotonic() < end:
        try:
            value = hs_query("return { version=hs.processInfo.version }")
            if isinstance(value, dict) and value.get("version"): return value
        except Exception as error: last = error
        time.sleep(.25)
    raise RuntimeError("Hammerspoon did not return after reload: " + str(last))

STABLE_PROBE_LUA = """
  local s=spoon and spoon['10bucks']; local function n(t) local c=0; for _ in pairs(t or {}) do c=c+1 end; return c end
  local function running(timer) if not timer then return false end; local ok,value=pcall(timer.running,timer); return ok and value==true end
  return {hammerspoonVersion=hs.processInfo.version, spoonVersion=s and s.version or nil, started=s and s.started==true or false,
    configuredBindings=s and n(s.config and s.config.hotkeys) or 0, installedBindings=s and n(s.hotkeyBindings) or 0,
    lifecycleFilter=s and s.lifecycle and s.lifecycle.filter ~= nil or false,
    reconcileTimerRunning=s and s.lifecycle and running(s.lifecycle.reconcileTimer) or false,
    barTimerRunning=s and s.bar and running(s.bar.timer) or false,
    canvases=s and s.bar and n(s.bar.canvases) or 0}
"""
def stable_probe():
    return hs_query(STABLE_PROBE_LUA)

def candidate_probe():
    return hs_query("""
      local s=spoon and spoon['10bucks']; return {version=hs.processInfo.version, spoonVersion=s and s.version or nil,
        started=s and s.started==true or false, bindings=s and #(s.hotkeyBindings or {}) or 0,
        canary=s and s:canaryStatus() or nil}
    """)

def equal_baseline(actual, expected):
    keys = ("hammerspoonVersion", "spoonVersion", "started", "configuredBindings", "installedBindings", "lifecycleFilter", "reconcileTimerRunning", "barTimerRunning", "canvases")
    return all(actual.get(key) == expected.get(key) for key in keys)

def require_approval(path, commit):
    require_owner_private_regular(path, "approval", exact_mode=0o600)
    approval = json.loads(path.read_text())
    if approval.get("candidateCommit") != commit: raise RuntimeError("private approval does not name this exact candidate commit")

def atomic_symlink(target, link):
    link.parent.mkdir(parents=True, exist_ok=True); temporary = link.with_name(link.name + ".walking-stack-new")
    if temporary.exists() or temporary.is_symlink(): temporary.unlink()
    os.symlink(target, temporary); os.replace(temporary, link)

def save_state(value, path):
    path.parent.mkdir(parents=True, exist_ok=True); fd, temporary = tempfile.mkstemp(prefix=path.name + ".", dir=path.parent)
    try:
        with os.fdopen(fd, "w") as output: json.dump(value, output, sort_keys=True); output.write("\n")
        os.chmod(temporary, 0o600); os.replace(temporary, path)
    except BaseException: os.unlink(temporary); raise

def runtime_watcher_shapes():
    return hs_query("""
      local window=assert(hs.window.focusedWindow(), 'focus a regular window before preflight')
      local element=assert(hs.axuielement.windowElement(window), 'focused window has no AX element')
      local application=assert(window:application(), 'focused window has no application')
      return { windowNewWatcher=type(window.newWatcher), axElementNewWatcher=type(element.newWatcher), applicationNewWatcher=type(application.newWatcher) }
    """)

def require_runtime_watcher_shapes():
    actual = runtime_watcher_shapes()
    expected = {"windowNewWatcher":"function", "axElementNewWatcher":"nil", "applicationNewWatcher":"function"}
    if actual != expected:
        raise RuntimeError("installed runtime watcher methods do not match direct-AX host contract: " + json.dumps(actual, sort_keys=True))
    return actual

def preflight(link, config):
    if not SPOON.is_dir(): raise RuntimeError("candidate Spoon missing")
    require_owner_private_regular(config, "config")
    if run(["git", "status", "--porcelain"]): raise RuntimeError("candidate working tree is not clean")
    version = hs_query("return {version=hs.processInfo.version}").get("version")
    if version != "1.1.1": raise RuntimeError("unsupported Hammerspoon version: " + repr(version))
    watcher_shapes = require_runtime_watcher_shapes()
    target = link_target(link)
    if not target or not Path(target).is_dir(): raise RuntimeError("installed Spoon link target is unavailable")
    baseline = stable_probe()
    if baseline.get("configuredBindings") != 26 or baseline.get("installedBindings") != 26:
        raise RuntimeError("stable baseline must have exactly 26 configured and installed bindings")
    return {"candidateCommit": candidate_commit(), "runtimeVersion": version, "linkTarget": target,
      "stableCommit": run(["git", "-C", target, "rev-parse", "HEAD"]), "configSha256": digest(config),
      "configMode": mode(config), "baseline": baseline, "watcherShapes": watcher_shapes, "deadlineSeconds": DEADLINE}

def stop_stable():
    hs_query("local s=assert(spoon['10bucks']); s:stop(); return true")
    after = stable_probe()
    required = {"started":False,"installedBindings":0,"lifecycleFilter":False,"reconcileTimerRunning":False,"barTimerRunning":False,"canvases":0}
    if any(after.get(k) != v for k,v in required.items()): raise RuntimeError("stable did not stop cleanly: " + json.dumps(after, sort_keys=True))

def restore(state, link, config):
    before, backup = state["before"], Path(state["backup"])
    try: require_owner_private_regular(backup, "config backup")
    except OSError as error: raise RuntimeError("exact config backup unavailable: " + str(error))
    if digest(backup) != before["configSha256"] or mode(backup) != before["configMode"]: raise RuntimeError("exact config backup unavailable")
    target = Path(before["linkTarget"])
    if not target.is_dir() or run(["git", "-C", target, "rev-parse", "HEAD"]) != before["stableCommit"]: raise RuntimeError("stable target/commit changed")
    atomic_regular_replace(backup, config, before["configMode"], "config restore"); atomic_symlink(target, link); reload_and_wait()
    hs_query("local s=assert(spoon['10bucks']); s:start(); s:bindHotkeys(); return true")
    actual = stable_probe()
    if not equal_baseline(actual, before["baseline"]): raise RuntimeError("stable baseline mismatch: " + json.dumps(actual, sort_keys=True))
    if digest(config) != before["configSha256"] or mode(config) != before["configMode"] or link_target(link) != before["linkTarget"]: raise RuntimeError("restored files do not match captured state")
    return actual

def start_capture(args):
    before = preflight(args.link, args.config); require_approval(args.approval, before["candidateCommit"])
    temporary = Path(args.temporary_config)
    require_owner_private_regular(temporary, "temporary config")
    if "canaryInstrumentation = true" not in temporary.read_text(): raise RuntimeError("temporary config must explicitly enable instrumentation")
    backup = args.state.with_suffix(".config-backup"); backup.parent.mkdir(parents=True, exist_ok=True)
    fd, backup_name = tempfile.mkstemp(prefix=backup.name + ".", dir=backup.parent)
    with os.fdopen(fd, "wb") as output: output.write(args.config.read_bytes())
    os.chmod(backup_name, before["configMode"]); os.replace(backup_name, backup)
    require_owner_private_regular(backup, "config backup")
    state = {"before":before,"backup":str(backup),"startedAt":time.time()}; save_state(state,args.state)
    stopped = False
    try:
        stop_stable(); stopped = True
        atomic_regular_replace(temporary, args.config, before["configMode"], "candidate config"); atomic_symlink(SPOON,args.link); reload_and_wait()
        probe = candidate_probe(); canary = probe.get("canary") or {}
        if not (probe.get("started") and probe.get("bindings") == 3 and canary.get("enabled") and canary.get("activeTimers") == 0):
            raise RuntimeError("candidate startup verification failed: " + json.dumps(probe, sort_keys=True))
        return {"preflight":before,"status":probe}
    except Exception as primary:
        rollback_error = None
        if stopped:
            try: restore(state,args.link,args.config)
            except Exception as error: rollback_error = error
        message = "candidate start failed: " + str(primary)
        if rollback_error: message += "; automatic rollback failed: " + str(rollback_error)
        else:
            args.state.unlink(missing_ok=True); backup.unlink(missing_ok=True)
        raise RuntimeError(message)

def capture_status(args):
    if not args.state.is_file(): raise RuntimeError("no active candidate capture state")
    state=json.loads(args.state.read_text()); before=state["before"]
    if candidate_commit() != before["candidateCommit"] or link_target(args.link) != str(SPOON):
        raise RuntimeError("candidate commit or installed symlink no longer matches capture")
    probe=candidate_probe()
    if probe.get("version") != before["runtimeVersion"] or probe.get("spoonVersion") != "Canary A" or not probe.get("started") or not (probe.get("canary") or {}).get("enabled"):
        raise RuntimeError("loaded runtime is not the verified candidate")
    return probe

def finish(args):
    state=json.loads(args.state.read_text()); require_approval(args.approval,state["before"]["candidateCommit"])
    exported=None; primary=None
    try:
        exported=hs_query("local s=assert(spoon['10bucks']); return s:canaryExport()")
        hs_query("local s=assert(spoon['10bucks']); s:stop(); return true")
    except Exception as error: primary=error
    restored=restore(state,args.link,args.config)
    args.state.unlink(missing_ok=True); Path(state["backup"]).unlink(missing_ok=True)
    if primary: raise RuntimeError("candidate export/stop failed after successful restoration: "+str(primary))
    return {"export":exported,"restored":restored}

def wait_status(args):
    if not args.counter or args.delta is None or not 1 <= args.deadline_ms <= 10000:
        raise RuntimeError("wait-status requires --counter, --delta, and --deadline-ms in 1..10000")
    initial = capture_status(args); counts = (initial.get("canary") or {}).get("counts") or {}
    start = counts.get(args.counter, 0); end = time.monotonic() + args.deadline_ms / 1000
    while True:
        latest = capture_status(args); current = ((latest.get("canary") or {}).get("counts") or {}).get(args.counter, 0)
        if current - start >= args.delta: return {"initial": initial, "status": latest, "counter": args.counter, "observedDelta": current - start}
        if time.monotonic() >= end: raise RuntimeError("status counter delta did not arrive before deadline")
        time.sleep(.1)

def main(argv):
    parser=argparse.ArgumentParser(description=__doc__); parser.add_argument("command",choices=("preflight","start-capture","status","wait-status","finish","rollback")); parser.add_argument("--link",type=Path,default=DEFAULT_LINK); parser.add_argument("--config",type=Path,default=DEFAULT_CONFIG); parser.add_argument("--state",type=Path,default=STATE); parser.add_argument("--approval",type=Path); parser.add_argument("--temporary-config"); parser.add_argument("--counter"); parser.add_argument("--delta",type=int); parser.add_argument("--deadline-ms",type=int); parser.add_argument("--execute",action="store_true"); args=parser.parse_args(argv)
    try:
        if args.command=="preflight": result=preflight(args.link,args.config)
        elif args.command=="status": result=capture_status(args)
        elif args.command=="wait-status": result=wait_status(args)
        else:
            if not args.execute or not args.approval: raise RuntimeError(args.command+" requires --execute and --approval OWNER_PRIVATE_FILE")
            if args.command=="start-capture": result=start_capture(args)
            elif args.command=="finish": result=finish(args)
            else:
                state=json.loads(args.state.read_text()); require_approval(args.approval,state["before"]["candidateCommit"]); result={"restored":restore(state,args.link,args.config)}; args.state.unlink(missing_ok=True); Path(state["backup"]).unlink(missing_ok=True)
        print(json.dumps(result,sort_keys=True)); return 0
    except (RuntimeError,OSError,subprocess.SubprocessError,json.JSONDecodeError) as error: print("canary runner: "+str(error),file=sys.stderr); return 1
if __name__=="__main__": raise SystemExit(main(sys.argv[1:]))
