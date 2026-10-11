"""Owned disposable VM runner for the first native candidate acceptance slice."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time
import uuid

ROOT = Path(__file__).resolve().parents[1]
BASE = "10bucks-functional-sip-base-20261011"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("scenario", choices=["columns-close-recovery"])
    parser.add_argument("--headed", action="store_true")
    parser.add_argument("--demo", action="store_true", help="2s pauses between actions; not a latency benchmark")
    args = parser.parse_args()
    execution_deadline = time.monotonic() + 95
    def remaining(cap):
        left = execution_deadline - time.monotonic()
        if left <= 0:
            raise RuntimeError("runner execution deadline exceeded")
        return min(cap, left)
    tart = os.environ.get("TART_BIN", str(Path.home() / ".tart/tool/tart.app/Contents/MacOS/tart"))
    nonce = uuid.uuid4().hex
    vm = "10bucks-run-ft-" + nonce[:12]
    results = ROOT / "vm/results" / vm
    snapshot = results / "source"
    results.mkdir(parents=True)
    fixture = ROOT / "functional-tests/fixture"
    subprocess.run([str(fixture / "build.sh")], check=True, timeout=remaining(30), capture_output=True)
    shutil.copytree(ROOT / "10bucks.spoon", snapshot / "10bucks.spoon")
    shutil.copytree(ROOT / "functional-tests", snapshot / "functional-tests",
                    ignore=shutil.ignore_patterns("build", "__pycache__"))
    shutil.copytree(fixture / "build/Fixture.app", snapshot / "Fixture.app")
    shutil.copytree(ROOT / "vm", snapshot / "vm", ignore=shutil.ignore_patterns("results"))
    manifest = {str(p.relative_to(snapshot)): hashlib.sha256(p.read_bytes()).hexdigest()
                for p in sorted(snapshot.rglob("*")) if p.is_file()}
    (results / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    spec = importlib.util.spec_from_file_location("frozen_scenario", snapshot / "functional-tests/scenarios/columns_close_recovery.py")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    Frame, Observation, scenario = module.Frame, module.Observation, module.run
    env = dict(os.environ, TENBUCKS_VM=vm)
    guest_root = "/Volumes/My Shared Files/10bucks"
    guest_results = "/Volumes/My Shared Files/results"
    process = None
    cloned = False
    error = None
    passed = False
    cleanup = {}

    def ssh(command, timeout=10):
        r = subprocess.run([str(snapshot / "vm/ssh"), command], env=env,
                           capture_output=True, text=True, timeout=remaining(timeout))
        if r.returncode:
            raise RuntimeError("guest SSH command failed")
        return r.stdout

    def hs(code, timeout=15):
        r = subprocess.run([str(snapshot / "vm/hs"), code], env=env,
                           capture_output=True, text=True, timeout=remaining(timeout))
        if r.returncode:
            raise RuntimeError("guest Hammerspoon request failed")
        return json.loads(r.stdout.strip().splitlines()[-1])

    def read(name):
        try:
            return json.loads((results / name).read_text())
        except (FileNotFoundError, json.JSONDecodeError):
            return None

    def wait_status(predicate, seconds=5):
        deadline = min(execution_deadline, time.monotonic() + seconds)
        while time.monotonic() < deadline:
            status = read("status.json")
            if status and status.get("error"):
                raise RuntimeError("guest controller: " + status["error"])
            if status and predicate(status):
                return status
            time.sleep(0.05)
        raise RuntimeError("guest status deadline exceeded")

    class Driver:
        action_sequence = 0
        last_sample = -1

        def preflight(self):
            status = wait_status(lambda s: s.get("candidateReady") is True and s.get("fixtureReady") is True, 10)
            if status.get("unknownMembers", 0) != 0:
                raise RuntimeError("unowned candidate membership")
            if status.get("layout") != "columns":
                raise RuntimeError("columns bootstrap not confirmed")
            return Frame(**status["workArea"])

        def action(self, operation, alias=None):
            remaining(1)
            if args.demo:
                if remaining(2) < 2:
                    raise RuntimeError("demo pause exceeds execution budget")
                time.sleep(2)
            self.action_sequence += 1
            action = {"sequence": self.action_sequence, "operation": operation, "alias": alias}
            temp = results / "action.json.tmp"
            temp.write_text(json.dumps(action))
            temp.replace(results / "action.json")
            status = wait_status(lambda s: s.get("actionSequence") == self.action_sequence and not s.get("pending"))
            if status.get("actionAccepted") is not True:
                raise RuntimeError("action rejected: " + str(status.get("actionError")))
            print(f"{operation} {alias or ''}", flush=True)

        def create(self, alias):
            self.action("create", alias)

        def close(self, alias):
            self.action("close", alias)

        def hotkey(self, command):
            self.action(command)

        def observe(self):
            deadline = time.monotonic() + remaining(0.14)
            while time.monotonic() < deadline:
                value = read("observation.json")
                if value and value["sample_id"] > self.last_sample:
                    self.last_sample = value["sample_id"]
                    if value.get("unknownMembers", 0):
                        raise RuntimeError("unowned candidate membership")
                    return Observation(value["sample_id"], value["sampled_at"], value["observed_at"],
                        {k: Frame(**v) for k, v in value["frames"].items()}, value.get("focused"),
                        frozenset(value["closed"]), frozenset(value["managed"]), value["commands_received"])
                time.sleep(0.005)
            raise RuntimeError("fresh native sample unavailable")

        def record(self, checkpoint, observation):
            with (results / "assertions.jsonl").open("a") as log:
                log.write(json.dumps({"checkpoint": checkpoint, "sample": observation.sample_id,
                    "focused": observation.focused, "managed": sorted(observation.managed),
                    "closed": sorted(observation.closed), "at": observation.sampled_at}) + "\n")

    try:
        state = subprocess.run([tart, "get", BASE, "--format", "json"], capture_output=True,
                               text=True, check=True, timeout=remaining(5))
        if json.loads(state.stdout)["State"] != "stopped":
            raise RuntimeError("base must be stopped")
        subprocess.run([tart, "clone", BASE, vm], env=dict(env, TART_NO_AUTO_PRUNE="1"),
                       check=True, timeout=remaining(30), capture_output=True)
        cloned = True
        with (results / "tart.log").open("wb") as log:
            command = [tart, "run", vm, "--no-audio", "--no-clipboard", "--no-usb-accessories",
                       f"--dir=10bucks:{snapshot}:ro", f"--dir=results:{results}"]
            if not args.headed:
                command.append("--no-graphics")
            process = subprocess.Popen(command, stdin=subprocess.DEVNULL, stdout=log, stderr=log)
        # Readiness is bounded and separate from the scenario, no actions before ready.
        deadline = min(execution_deadline - 20, time.monotonic() + 60)
        while time.monotonic() < deadline:
            try:
                sip = ssh("csrutil status", 8)
                if "status: enabled." not in sip:
                    raise RuntimeError("SIP not enabled")
                api = hs(f'return hs.json.encode(dofile("{guest_root}/functional-tests/fixture/check-api.lua"))')
                if api.get("pass") is True:
                    (results / "api-result.json").write_text(json.dumps(api))
                    break
            except (RuntimeError, subprocess.TimeoutExpired):
                time.sleep(0.2)
        else:
            raise RuntimeError("guest readiness deadline exceeded")
        settings = ssh("defaults read com.apple.dock mru-spaces; defaults read NSGlobalDomain _HIHideMenuBar")
        if settings.strip().splitlines() != ["0", "1"]:
            raise RuntimeError("required guest settings differ from configured baseline")
        preflight = hs('local session=hs.caffeinate.sessionProperties(); local front=hs.application.frontmostApplication(); return hs.json.encode({ax=hs.accessibilityState(),onConsole=session.kCGSSessionOnConsoleKey==true,locked=session.CGSSessionScreenIsLocked==true,loginwindow=front and front:bundleID()=="com.apple.loginwindow" or false,secureInput=hs.eventtap.isSecureInputEnabled(),screens=#hs.screen.allScreens(),separateSpaces=hs.spaces.screensHaveSeparateSpaces(),managerLoaded=spoon~=nil,hsVersion=hs.processInfo.version})')
        preflight["osVersion"] = ssh("sw_vers -productVersion").strip()
        preflight["osBuild"] = ssh("sw_vers -buildVersion").strip()
        preflight["sip"] = sip.strip()
        preflight["settings"] = {"mruSpaces": 0, "hideMenuBar": 1}
        if not preflight["onConsole"] or preflight["loginwindow"] or not preflight["osVersion"].startswith("26.") or preflight["hsVersion"] != "1.1.1" or not preflight["ax"] or preflight["locked"] or preflight["secureInput"] or preflight["screens"] != 1 or not preflight["separateSpaces"] or preflight["managerLoaded"]:
            raise RuntimeError("guest environment preflight failed")
        (results / "environment.json").write_text(json.dumps(preflight, indent=2))
        control = f"/tmp/tenbucks-ft-{nonce}"
        ssh(f"mkdir -m 700 {control}")
        hs('ft=dofile("' + guest_root + '/functional-tests/guest.lua"); return hs.json.encode(ft.start({'
           f'sourceRoot="{guest_root}", executable="{guest_root}/Fixture.app/Contents/MacOS/Fixture",'
           f'controlDir="{control}/control",run="{nonce}",outputDir="{guest_results}",cleanSeedTerminal=true' + '}))')
        scenario(Driver())
        passed = True
    except BaseException as exc:
        error = str(exc) or type(exc).__name__
        print("FAIL: " + error, file=sys.stderr)
    finally:
        execution_deadline = time.monotonic() + 20
        final = None
        # Guest controller owns candidate/fixture stop before VM shutdown.
        if process is not None:
            try:
                hs('if ft then return hs.json.encode(ft.stop()) end', 3)
                deadline = min(execution_deadline - 7, time.monotonic() + 5)
                final = None
                while time.monotonic() < deadline:
                    final = read("status.json")
                    if final and final.get("running") is False:
                        break
                    time.sleep(0.05)
                if not final or final.get("running") is not False:
                    raise RuntimeError("guest cleanup deadline exceeded")
                cleanup["guest"] = final.get("cleanup", {})
            except BaseException:
                cleanup["guestStopConfirmed"] = False
            try:
                ssh("sudo -n /sbin/shutdown -h now", 5)
            except BaseException:
                pass
            deadline = execution_deadline - 1
            cleanup["vmStopped"] = False
            while time.monotonic() < deadline:
                try:
                    r = subprocess.run([tart, "get", vm, "--format", "json"], capture_output=True,
                                       text=True, timeout=remaining(2), check=True)
                    if json.loads(r.stdout)["State"] == "stopped":
                        cleanup["vmStopped"] = True
                        break
                except BaseException:
                    pass
                time.sleep(0.1)
            try:
                process.wait(timeout=remaining(1))
                cleanup["tartExited"] = True
            except (subprocess.TimeoutExpired, RuntimeError):
                cleanup["tartExited"] = process.poll() is not None
        success = passed and error is None and not (final or {}).get("error") and cleanup.get("vmStopped") and cleanup.get("tartExited") and cleanup.get("guest", {}).get("ok") is True
        summary = {"pass": bool(success), "scenarioPassed": passed, "error": error,
                   "cleanup": cleanup, "vm": vm, "cloneCreated": cloned, "demo": args.demo}
        (results / "host-result.json").write_text(json.dumps(summary, indent=2) + "\n")
        print(f"{'PASS' if success else 'FAIL'}; artifacts: {results}", flush=True)
    return 0 if success else 1


if __name__ == "__main__":
    sys.exit(main())
