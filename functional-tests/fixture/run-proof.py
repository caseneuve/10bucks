#!/usr/bin/env python3
"""Bounded fixture-only proof in an already-owned disposable VM, not acceptance."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time
import uuid

ROOT = Path(__file__).resolve().parents[2]


def main():
    vm = os.environ.get("TENBUCKS_VM", "")
    if not vm.startswith("10bucks-run-fixture-proof-"):
        sys.exit("Set TENBUCKS_VM to an owned 10bucks-run-fixture-proof-* disposable VM")
    nonce = uuid.uuid4().hex
    result_dir = ROOT / "vm" / "results" / vm / nonce
    snapshot = result_dir / "snapshot"
    snapshot.mkdir(parents=True)
    fixture = ROOT / "functional-tests" / "fixture"
    app = fixture / "build" / "Fixture.app"
    if not app.is_dir():
        sys.exit("Build fixture first: functional-tests/fixture/build.sh")
    shutil.copytree(app, snapshot / "Fixture.app")
    for name in ("proof.lua", "mailbox.lua", "check-api.lua", "main.swift", "Info.plist", "build.sh", "run-proof.py"):
        shutil.copy2(fixture / name, snapshot / name)
    for name in ("hs", "ssh", "common.sh"):
        shutil.copy2(ROOT / "vm" / name, snapshot / ("vm-" + name))
    manifest = {str(p.relative_to(snapshot)): hashlib.sha256(p.read_bytes()).hexdigest()
                for p in sorted(snapshot.rglob("*")) if p.is_file()}
    (result_dir / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    env = dict(os.environ, TENBUCKS_VM=vm)
    guest = f"/Volumes/My Shared Files/results/{nonce}"
    control_parent = f"/tmp/tenbucks-fixture-{nonce}"
    error = None
    proof_passed = False
    cleanup = {}

    def call(helper, argument, timeout=15):
        completed = subprocess.run([str(ROOT / "vm" / helper), argument], env=env,
                                   capture_output=True, text=True, timeout=timeout)
        if completed.returncode:
            raise RuntimeError(f"{helper} failed ({completed.returncode})")
        return completed.stdout

    try:
        api_result = call("hs", f'return hs.json.encode(dofile({json.dumps(guest + "/snapshot/check-api.lua")}))')
        api_result = json.loads(api_result.strip().splitlines()[-1])
        if api_result.get("pass") is not True:
            raise RuntimeError("real guest Hammerspoon API check failed; fixture not launched")
        (result_dir / "api-result.json").write_text(json.dumps(api_result, indent=2) + "\n")
        call("ssh", f"mkdir -m 700 {control_parent}")
        code = (
            'assert(hs.accessibilityState(), "AX required"); '
            'assert(not hs.eventtap.isSecureInputEnabled(), "Secure Input"); '
            'assert(not hs.caffeinate.sessionProperties().CGSSessionScreenIsLocked, "locked"); '
            'assert(spoon == nil or spoon["10bucks"] == nil, "manager loaded"); '
            f'fixtureProof=dofile({json.dumps(guest + "/snapshot/proof.lua")}); '
            'return hs.json.encode(fixtureProof.start({'
            f'executable={json.dumps(guest + "/snapshot/Fixture.app/Contents/MacOS/Fixture")},'
            f'controlDir={json.dumps(control_parent + "/control")},'
            f'run={json.dumps(nonce)},resultPath={json.dumps(guest + "/proof-result.json")}'
            '}))'
        )
        # Entire start+monitor budget, not 40 seconds after a slow start.
        deadline = time.monotonic() + 40
        call("hs", code)
        while time.monotonic() < deadline:
            path = result_dir / "proof-result.json"
            if path.exists():
                result = json.loads(path.read_text())
                if not result.get("pass"):
                    raise RuntimeError("fixture proof failed; inspect proof-result.json")
                proof_passed = True
                print(json.dumps(result, indent=2))
                break
            time.sleep(0.1)
        else:
            raise RuntimeError("outer proof deadline exceeded; no rerun")
    except BaseException as exc:
        error = str(exc) or type(exc).__name__
    finally:
        # Separately bounded failure cleanup; terminate only retained fixture task
        # through controller, then shut down this positively identified VM.
        cleanup_deadline = time.monotonic() + 15
        if error:
            try:
                call("hs", 'if fixtureProof then return hs.json.encode(fixtureProof.stop()) end', 3)
                cleanup["stopRequested"] = True
            except BaseException:
                cleanup["stopRequested"] = False
        try:
            # Reserve >=7s for verification even if shutdown transport hangs.
            remaining = cleanup_deadline - time.monotonic()
            r = subprocess.run([str(ROOT / "vm" / "ssh"), "sudo -n /sbin/shutdown -h now"],
                               env=env, capture_output=True, timeout=min(5, remaining))
            cleanup["shutdownCommandReturned"] = True
        except BaseException:
            cleanup["shutdownCommandReturned"] = False
        cleanup["vmStopped"] = False
        tart = os.environ.get("TART_BIN", str(Path.home() / ".tart/tool/tart.app/Contents/MacOS/tart"))
        while time.monotonic() < cleanup_deadline:
            try:
                remaining = cleanup_deadline - time.monotonic()
                if remaining <= 0:
                    break
                r = subprocess.run([tart, "get", vm, "--format", "json"],
                                   capture_output=True, text=True, timeout=min(2, remaining), check=True)
                if json.loads(r.stdout)["State"] == "stopped":
                    cleanup["vmStopped"] = True
                    break
            except BaseException:
                pass
            time.sleep(min(0.25, max(0, cleanup_deadline - time.monotonic())))
        summary = {"vm": vm, "run": nonce, "error": error, "cleanup": cleanup,
                   "proofPassed": proof_passed,
                   "pass": proof_passed and error is None and cleanup.get("vmStopped") is True}
        (result_dir / "host-result.json").write_text(json.dumps(summary, indent=2) + "\n")
        print(f"Artifacts: {result_dir}")
    return 0 if summary["pass"] else 1


if __name__ == "__main__":
    sys.exit(main())
