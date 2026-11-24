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


def parse_ipc_response(stdout):
    """Transport logs may follow the response; accept exactly one JSON line."""
    responses = []
    for line in stdout.splitlines():
        try:
            responses.append(json.loads(line))
        except json.JSONDecodeError:
            continue
    if len(responses) != 1:
        raise ValueError('expected exactly one IPC JSON response')
    return responses[0]


def evidence_complete(result, *, configured_rules=False, managed_window_chooser=False):
    return (isinstance(result, dict) and type(result.get('dropped')) is int and result['dropped'] == 0
            and isinstance(result.get('trace'), list) and len(result['trace']) > 0
            and result.get('error') is None and result.get('cleanup', {}).get('ok') is True
            and (not configured_rules or (result.get('cleanup', {}).get('ruleResourcesCleared') is True
                and result.get('cleanup', {}).get('ruleWrappersRestored') is True))
            and (not managed_window_chooser or all(result.get('cleanup', {}).get(k) is True for k in
                 ('chooserNativeGone', 'chooserReleased', 'chooserDefaultFocusReleased', 'chooserWrapperRestored'))))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("scenario", choices=["rules-benchmark", "desktop-switching-benchmark", "desktop-creation-benchmark", "configured-rules", "managed-window-chooser", "managed-window-chooser-cold-start", "managed-window-chooser-fullscreen", "desktop-creation-race", "close-recovery-investigation", "columns-close-recovery", "column-movement", "stack-columns-membership", "ghostty-close-recovery", "ghostty-column-normalization", "ghostty-layout-retention", "desktop-switching", "desktop-creation"])
    parser.add_argument("--headed", action="store_true")
    parser.add_argument("--demo", action="store_true", help="2s pauses between actions; not a latency benchmark")
    parser.add_argument("--bar-capture", action="store_true", help="capture native bar outside/hover/return pixels for independent visual review")
    parser.add_argument("--keep-open", action="store_true", help="debug only: preserve live guest and controller after failure")
    parser.add_argument("--reuse-debug", metavar="VM", help="reuse running owned debug guest; reset HS modules, no reboot")
    parser.add_argument('--desktop-fullscreen', action='store_true',
                        help='desktop-only separate owned-fixture fullscreen indexing/retention subcase')
    previous = parser.add_mutually_exclusive_group()
    previous.add_argument('--previous-desktop-visit', action='store_true',
                          help='check previous toggling after an existing fullscreen chooser visit')
    previous.add_argument('--previous-desktop-excluded', action='store_true',
                          help='check return to the existing fullscreen Space of a rule-excluded window')
    parser.add_argument('--benchmark-mode', choices=['warm', 'cold'])
    parser.add_argument('--close-case', choices=['normal', 'excluded', 'deliberate-b', 'deliberate-c'],
                        help='required fresh-run case for close-recovery-investigation')
    args = parser.parse_args()
    if (args.previous_desktop_visit or args.previous_desktop_excluded) and (
            args.scenario != 'managed-window-chooser-fullscreen' or args.demo or args.bar_capture):
        parser.error('previous-desktop checks require managed-window-chooser-fullscreen without demo/bar capture')
    investigation = args.scenario == 'close-recovery-investigation'
    if investigation != bool(args.close_case):
        parser.error('--close-case is required only for close-recovery-investigation')
    if investigation and (args.demo or args.bar_capture or args.keep_open):
        parser.error('close investigation requires normal bounded cleanup, without demo/bar capture/keep-open')
    benchmark_name = {'rules-benchmark':'rules', 'desktop-switching-benchmark':'desktop_switching',
                      'desktop-creation-benchmark':'desktop_creation'}.get(args.scenario)
    rules_benchmark = benchmark_name == 'rules'
    desktop_benchmark = benchmark_name in ('desktop_switching', 'desktop_creation')
    if desktop_benchmark: args.scenario = benchmark_name.replace('_', '-')
    if bool(benchmark_name) != bool(args.benchmark_mode) or (rules_benchmark and (args.demo or args.bar_capture)):
        parser.error('rules-benchmark requires --benchmark-mode warm|cold, without demo/bar capture')
    if args.desktop_fullscreen and (args.scenario not in ('desktop-switching','desktop-creation') or desktop_benchmark):
        parser.error('--desktop-fullscreen requires desktop-switching without --desktop-benchmark')
    if desktop_benchmark and args.scenario not in ('desktop-switching','desktop-creation'):
        parser.error('--desktop-benchmark requires desktop-switching')
    if args.scenario in ('desktop-switching', 'configured-rules', 'managed-window-chooser', 'managed-window-chooser-cold-start') and (args.demo or args.bar_capture):
        parser.error('desktop-switching cannot combine demo/bar pauses with its watchdog')
    if args.demo and args.scenario=='stack-columns-membership':
        parser.error('--demo cannot fit the combined scenario watchdog; run without --demo')
    execution_deadline = time.monotonic() + 95
    def remaining(cap):
        left = execution_deadline - time.monotonic()
        if left <= 0:
            raise RuntimeError("runner execution deadline exceeded")
        return min(cap, left)
    tart = os.environ.get("TART_BIN", str(Path.home() / ".tart/tool/tart.app/Contents/MacOS/tart"))
    nonce = uuid.uuid4().hex
    vm = args.reuse_debug or ("10bucks-run-ft-" + nonce[:12])
    if args.reuse_debug and not vm.startswith("10bucks-run-ft-"):
        sys.exit("Only owned FT debug VMs may be reused")
    results = ROOT / "vm/results" / vm
    if args.reuse_debug:
        owner = json.loads((results / "debug-owner.json").read_text())
        if owner["vm"] != vm:
            sys.exit("debug ownership mismatch")
        results = results / ("session-" + nonce[:12])
    snapshot = results / "source"
    results.mkdir(parents=True)
    fixture = ROOT / "functional-tests/fixture"
    subprocess.run([str(fixture / "build.sh")], check=True, timeout=remaining(30), capture_output=True)
    subprocess.run([str(ROOT / '10bucks.spoon/native/build.sh')], check=True, timeout=remaining(20), capture_output=True)
    shutil.copytree(ROOT / "10bucks.spoon", snapshot / "10bucks.spoon")
    shutil.copytree(ROOT / "functional-tests", snapshot / "functional-tests",
                    ignore=shutil.ignore_patterns("build", "__pycache__"))
    shutil.copytree(fixture / "build/Fixture.app", snapshot / "Fixture.app")
    shutil.copytree(ROOT / "vm", snapshot / "vm", ignore=shutil.ignore_patterns("results"))
    manifest = {str(p.relative_to(snapshot)): hashlib.sha256(p.read_bytes()).hexdigest()
                for p in sorted(snapshot.rglob("*")) if p.is_file()}
    (results / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    sys.path.insert(0, str(snapshot / 'functional-tests'))
    scenario_file=args.scenario.replace('-', '_') + '.py'
    spec = importlib.util.spec_from_file_location("frozen_scenario", snapshot / ('functional-tests/benchmarks/' + benchmark_name + '.py' if benchmark_name else 'functional-tests/scenarios/' + scenario_file))
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    from scenarios.columns_close_recovery import Frame, Observation
    scenario = module.run if not desktop_benchmark else None
    bar_spec = importlib.util.spec_from_file_location("frozen_bar_gate", snapshot / "functional-tests/bar_capture.py")
    bar_module = importlib.util.module_from_spec(bar_spec)
    bar_spec.loader.exec_module(bar_module)
    env = dict(os.environ, TENBUCKS_VM=vm,
               TENBUCKS_VM_OWNER_ROOT=str(ROOT / "vm/results"))
    guest_results = "/Volumes/My Shared Files/results"
    if args.reuse_debug:
        guest_results += "/" + results.name
    guest_root = guest_results + "/source" if args.reuse_debug else "/Volumes/My Shared Files/10bucks"
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
            (results / 'ipc-request-failure.txt').write_text(r.stdout + '\nSTDERR:\n' + r.stderr)
            raise RuntimeError("guest Hammerspoon request failed; raw output preserved")
        try:
            return parse_ipc_response(r.stdout)
        except ValueError as exc:
            (results / 'ipc-parse-failure.txt').write_text(r.stdout + '\nSTDERR:\n' + r.stderr)
            raise RuntimeError('guest IPC JSON parse failed; raw transport output preserved') from exc

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
            expected_layout='stack' if args.scenario in ('stack-columns-membership','column-movement','ghostty-column-normalization','close-recovery-investigation') else 'columns'
            if args.scenario != 'managed-window-chooser-fullscreen' and status.get("layout") != expected_layout:
                raise RuntimeError(expected_layout + " bootstrap not confirmed")
            return Frame(**status["workArea"])

        def action(self, operation, alias=None, commands=None):
            remaining(1)
            if args.demo:
                if remaining(2) < 2:
                    raise RuntimeError("demo pause exceeds execution budget")
                time.sleep(2)
            self.action_sequence += 1
            action = {"sequence": self.action_sequence, "operation": operation, "alias": alias,
                      "commands": commands}
            with (results / 'actions.jsonl').open('a') as log:
                log.write(json.dumps(dict(action, host_submitted_at=time.monotonic())) + '\n')
            temp = results / "action.json.tmp"
            temp.write_text(json.dumps(action))
            temp.replace(results / "action.json")
            status = wait_status(lambda s: s.get("actionSequence") == self.action_sequence and not s.get("pending"), 50 if rules_benchmark else 5)
            if status.get("actionAccepted") is not True:
                raise RuntimeError("action rejected: " + str(status.get("actionError")))
            print(f"{operation} {alias or ''}", flush=True)

        def create(self, alias):
            self.action("create", alias)

        def fixture_action(self, operation, alias):
            self.action(operation, alias)

        def close(self, alias):
            self.action("close", alias)

        def create_ghostty(self, alias):
            self.action("createGhostty", alias)

        def close_ghostty(self):
            self.action("closeGhostty", "C")

        def hotkey(self, command):
            self.action(command)

        def fixture_fullscreen(self, enabled):
            self.action('enterFixtureFullscreen' if enabled else 'exitFixtureFullscreen', 'A')

        def chooser_query(self, query):
            self.action('chooserQuery', commands=[query])

        def hotkey_burst(self, commands):
            self.action('hotkeyBurst', commands=list(commands))

        def investigation_record(self, value):
            (results / 'close-investigation.json').write_text(json.dumps(value, indent=2) + '\n')

        def benchmark_record(self, value):
            (results / ('rules-benchmark-analysis.json' if rules_benchmark else 'desktop-benchmark.json')).write_text(json.dumps(value, indent=2) + '\n')

        def benchmark_result(self):
            return read('rules-benchmark.json')

        def observe(self):
            deadline = time.monotonic() + remaining(0.14)
            while time.monotonic() < deadline:
                value = read("observation.json")
                if value and value["sample_id"] > self.last_sample:
                    self.last_sample = value["sample_id"]
                    if value.get("unknownMembers", 0):
                        raise RuntimeError("unowned candidate membership")
                    return Observation(value["sample_id"], value["sampled_at"], value["observed_at"],
                        {k: Frame(**v) for k, v in (value["frames"] or {}).items()}, value.get("focused"),
                        frozenset(value["closed"]), frozenset(value["managed"]), value["commands_received"] or {},value["diagnostics"])
                time.sleep(0.005)
            raise RuntimeError("fresh native sample unavailable")

        def record(self, checkpoint, observation):
            with (results / "assertions.jsonl").open("a") as log:
                log.write(json.dumps({"checkpoint": checkpoint, "sample": observation.sample_id,
                    "focused": observation.focused, "managed": sorted(observation.managed),
                    "closed": sorted(observation.closed), "at": observation.sampled_at,
                    "diagnostics": observation.diagnostics}) + "\n")

    try:
        if args.reuse_debug:
            state = subprocess.run([tart, "get", vm, "--format", "json"], capture_output=True,
                                   text=True, check=True, timeout=remaining(5))
            if json.loads(state.stdout)["State"] != "running":
                raise RuntimeError("debug guest is not running")
            hs('assert(not ft or not ft.status().ownedTaskRunning,"fixture still running"); return hs.json.encode({ok=true})', 3)
            try:
                hs('hs.reload(); return hs.json.encode({ok=true})', 3)
            except RuntimeError:
                pass  # transport invalidation expected; readiness confirms new init
        else:
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
                process = subprocess.Popen(command, stdin=subprocess.DEVNULL, stdout=log, stderr=log,
                                           start_new_session=args.keep_open)
            (results / "debug-owner.json").write_text(json.dumps({"vm": vm,
                "tartPid": process.pid, "run": nonce, "source": str(snapshot),
                "acceptance": False}, indent=2))
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
        if args.scenario.startswith('ghostty-'):
            identity=hs('local p="/Applications/Ghostty.app/Contents/Info.plist"; local v=hs.plist.read(p); return hs.json.encode({bundle=v.CFBundleIdentifier,version=v.CFBundleShortVersionString})')
            if identity['bundle']!='com.mitchellh.ghostty' or identity['version']!='1.3.1':
                raise RuntimeError('unexpected owned Ghostty version/identity')
            identity['executableSHA256']=ssh('shasum -a 256 /Applications/Ghostty.app/Contents/MacOS/ghostty').split()[0]
            ssh('codesign --verify --deep --strict /Applications/Ghostty.app')
            assessment=ssh('spctl --assess --type execute --verbose=4 /Applications/Ghostty.app 2>&1')
            if 'accepted' not in assessment or 'Notarized Developer ID' not in assessment:
                raise RuntimeError('Ghostty signature/notarization preflight failed')
            identity['signatureVerified']=True
            identity['assessment']=assessment.strip()
            identity['argv']=['--window-save-state=never','--initial-window=true','--command=/bin/zsh -f','--confirm-close-surface=false']
            (results / 'ghostty-environment.json').write_text(json.dumps(identity,indent=2))
        (results / "environment.json").write_text(json.dumps(preflight, indent=2))
        control = f"/tmp/tenbucks-ft-{nonce}"
        ssh(f"mkdir -m 700 {control}")
        hs('ft=dofile("' + guest_root + ('/functional-tests/benchmarks/guest.lua' if rules_benchmark else '/functional-tests/benchmarks/desktop_guest.lua' if desktop_benchmark else '/functional-tests/guest.lua') + '"); return hs.json.encode(ft.start({'
           f'sourceRoot="{guest_root}", executable="{guest_root}/Fixture.app/Contents/MacOS/Fixture",'
           f'excludeFullscreenOwner={str(args.previous_desktop_excluded).lower()},'
           f'controlDir="{control}/control",run="{nonce}",outputDir="{guest_results}",initialLayout="{"stack" if args.scenario in ("stack-columns-membership","column-movement","ghostty-column-normalization","close-recovery-investigation") else "columns"}",columnMovement={str(args.scenario == "column-movement").lower()},closeRecoveryInvestigation={str(investigation).lower()},configuredRules={str(args.scenario == "configured-rules").lower()},coldStart={str(args.scenario == "managed-window-chooser-cold-start").lower()},fullscreenChooser={str(args.scenario == "managed-window-chooser-fullscreen").lower()},managedWindowChooser={str(args.scenario in ("managed-window-chooser","managed-window-chooser-cold-start","managed-window-chooser-fullscreen")).lower()},desktopSwitching={str(args.scenario in ("managed-window-chooser-fullscreen","managed-window-chooser-cold-start","managed-window-chooser","configured-rules","desktop-switching","desktop-creation","desktop-creation-race")).lower()},desktopCreation={str(args.scenario in ("desktop-creation","desktop-creation-race")).lower()},desktopFullscreen={str(args.desktop_fullscreen).lower()},ghostty={str(args.scenario.startswith("ghostty-")).lower()},ownedDisposable=true,cleanSeedTerminal={str(not bool(args.reuse_debug)).lower()}' + '}))')
        driver = Driver()
        if rules_benchmark:
            module.run(driver, mode=args.benchmark_mode)
        elif args.desktop_fullscreen:
            module.fullscreen(driver)
        elif args.previous_desktop_visit or args.previous_desktop_excluded:
            module.previous_desktop_visit(driver, excluded=args.previous_desktop_excluded)
        elif desktop_benchmark:
            module.benchmark(driver, mode=args.benchmark_mode)
        elif investigation:
            scenario(driver, case=args.close_case)
        else:
            scenario(driver)
        if args.bar_capture:
            evidence = []
            for label, operation, showing in (("outside", "pointerOutsideBar", True),
                                               ("hover", "pointerInsideBar", False),
                                               ("returned", "pointerOutsideBar", True)):
                driver.action(operation)
                baseline = read("observation.json")
                if baseline is None:
                    raise RuntimeError("bar post-action baseline unavailable")
                gate = bar_module.BarGate(baseline, showing, time.monotonic())

                def next_bar_sample():
                    deadline = time.monotonic() + remaining(0.14)
                    while time.monotonic() < deadline:
                        sample = read("observation.json")
                        if sample is not None:
                            bar_module.BarGate.validate(sample)
                            if sample["sample_id"] < gate.last["sample_id"]:
                                raise RuntimeError("bar sample ID regressed")
                            if sample["sample_id"] > gate.last["sample_id"]:
                                return sample
                        time.sleep(0.005)
                    raise RuntimeError("fresh bar sample unavailable")

                deadline = time.monotonic() + remaining(5)
                while time.monotonic() < deadline:
                    value = next_bar_sample()
                    if gate.accept(value, time.monotonic()):
                        break
                    time.sleep(0.05)
                else:
                    raise RuntimeError("bar pointer checkpoint failed: " + label)
                capture_deadline = time.monotonic() + remaining(15)
                with (results / f"bar-{label}-capture.log").open("w") as capture_log:
                    capture = subprocess.Popen([str(snapshot / "vm/capture"),
                        f"{guest_results}/bar-{label}.png"], env=env,
                        stdin=subprocess.DEVNULL, stdout=capture_log, stderr=capture_log)
                    try:
                        while capture.poll() is None:
                            if time.monotonic() > capture_deadline:
                                raise RuntimeError("bar capture deadline exceeded")
                            sample = next_bar_sample()
                            gate.accept(sample, time.monotonic())
                            if not bar_module.matches(sample, showing):
                                raise RuntimeError("bar changed during pixel capture: " + label)
                            time.sleep(0.05)
                        if capture.returncode != 0:
                            raise RuntimeError("owned guest capture failed: " + label)
                        completion = read("observation.json")
                        if completion is None:
                            raise RuntimeError("bar capture completion baseline unavailable")
                        bar_module.BarGate.validate(completion)
                        if completion["sample_id"] > gate.last["sample_id"]:
                            gate.after_capture(completion, time.monotonic())
                        elif completion["sample_id"] != gate.last["sample_id"]:
                            raise RuntimeError("bar capture completion sample regressed")
                        # Strictly newer than the baseline read AFTER process exit.
                        after = next_bar_sample()
                        gate.after_capture(after, time.monotonic())
                    finally:
                        if capture.poll() is None:
                            capture.terminate()
                            try:
                                capture.wait(timeout=0.3)
                            except subprocess.TimeoutExpired:
                                capture.kill()
                                capture.wait(timeout=0.3)
                evidence.append({"checkpoint": label, "before": value, "after": after,
                                 "image": f"bar-{label}.png"})
            (results / "bar-evidence.json").write_text(json.dumps({"captured": True,
                "pixelAcceptance": "requires independent visual review", "checkpoints": evidence}, indent=2))
        passed = True
    except BaseException as exc:
        error = str(exc) or type(exc).__name__
        print("FAIL: " + error, file=sys.stderr)
    finally:
        execution_deadline = time.monotonic() + 20
        final = None
        # Guest controller owns candidate/fixture stop before VM shutdown.
        if (process is not None or args.reuse_debug) and not (args.keep_open and error):
            if error:
                try:
                    diagnostic = hs('local out={}; for _,id in ipairs({"org.hammerspoon.Hammerspoon","com.apple.Terminal","com.apple.systempreferences"}) do local a=hs.application.get(id); local row={app=id,running=a~=nil,windows={}}; if a then for _,w in ipairs(hs.axuielement.applicationElement(a):attributeValue("AXWindows") or {}) do local item={role=w:attributeValue("AXRole"),subrole=w:attributeValue("AXSubrole"),buttons={}}; local function walk(e,d) if d>6 then return end; if e:attributeValue("AXRole")=="AXButton" then local t=e:attributeValue("AXTitle"); if t then item.buttons[#item.buttons+1]=t end end; for _,c in ipairs(e:attributeValue("AXChildren") or {}) do walk(c,d+1) end end; walk(w,0); row.windows[#row.windows+1]=item end end; out[#out+1]=row end; return hs.json.encode(out)', 3)
                    (results / "failure-ui.json").write_text(json.dumps(diagnostic, indent=2))
                except BaseException:
                    cleanup["diagnosticCaptured"] = False
            try:
                hs('if ft then ft.stop() end; return hs.json.encode({stopSubmitted=true})', 3)
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
            except BaseException as exc:
                cleanup["guestStopConfirmed"] = False
                cleanup["guestStopError"] = str(exc) or type(exc).__name__
            if args.reuse_debug:
                cleanup["debugGuestRetained"] = True
            try:
                if not args.reuse_debug:
                    ssh("sudo -n /sbin/shutdown -h now", 5)
            except BaseException:
                pass
            deadline = execution_deadline - 1
            cleanup["vmStopped"] = False
            while not args.reuse_debug and time.monotonic() < deadline:
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
                if process is not None:
                    process.wait(timeout=remaining(1))
                    cleanup["tartExited"] = True
            except (subprocess.TimeoutExpired, RuntimeError):
                cleanup["tartExited"] = process is not None and process.poll() is not None
        if process is not None and args.keep_open and error:
            cleanup["debugGuestRetained"] = True
            print(f"Debug guest kept running: TENBUCKS_VM={vm} ./vm/hs 'return hs.json.encode(ft.status())'", flush=True)
            (results / "debug-owner.json").write_text(json.dumps({"vm": vm, "tartPid": process.pid,
                "run": nonce, "source": str(snapshot), "acceptance": False}, indent=2))
        guest_result = read('guest-result.json')
        evidence_ok = evidence_complete(guest_result, configured_rules=args.scenario == 'configured-rules',
                                        managed_window_chooser=args.scenario in ('managed-window-chooser','managed-window-chooser-cold-start','managed-window-chooser-fullscreen'))
        if investigation:
            outcome_path = results / 'close-investigation.json'
            outcome = json.loads(outcome_path.read_text()) if outcome_path.exists() else {}
            evidence_ok = evidence_ok and module.ordering_valid(guest_result, args.close_case, outcome.get('excludedESetupAt')) \
                and guest_result.get('cleanup', {}).get('closeWrappersRestored') is True
            if guest_result is not None:
                (results / 'close-ordering.json').write_text(json.dumps({
                    'case': args.close_case, 'trace': guest_result.get('closeOrdering'),
                    'dropped': guest_result.get('closeOrderingDropped')}, indent=2) + '\n')
        cleanup['completeEvidence'] = evidence_ok
        success = evidence_ok and passed and error is None and not (final or {}).get("error") and (args.reuse_debug or (cleanup.get("vmStopped") and cleanup.get("tartExited"))) and cleanup.get("guest", {}).get("ok") is True
        summary = {"pass": bool(success), "scenarioPassed": passed, "error": error,
                   "cleanup": cleanup, "vm": vm, "cloneCreated": cloned, "demo": args.demo, "debugReuse": bool(args.reuse_debug),
                   "barEvidenceCaptured": bool(args.bar_capture and (results / "bar-evidence.json").exists()),
                   "investigationCase": args.close_case,
                   "acceptance": bool(success and not args.reuse_debug and not investigation)}
        (results / "host-result.json").write_text(json.dumps(summary, indent=2) + "\n")
        print(f"{'PASS' if success else 'FAIL'}; artifacts: {results}", flush=True)
    return 0 if success else 1


if __name__ == "__main__":
    sys.exit(main())
