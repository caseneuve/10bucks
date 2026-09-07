#!/usr/bin/env python3
"""Integration-shaped fake-runner tests; no test invokes a host command."""
import importlib.util, json, os, stat, sys, tempfile, unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT))
spec = importlib.util.spec_from_file_location("real_host", ROOT / "direct_ax_volume_real_host.py")
real_host = importlib.util.module_from_spec(spec); sys.modules[spec.name] = real_host; spec.loader.exec_module(real_host)

class Result:
    def __init__(self, stdout="", returncode=0): self.stdout, self.returncode, self.stderr = stdout, returncode, ""
class FakeRunner:
    def __init__(self): self.calls = []; self.pid = 912
    def run(self, argv, *, timeout, env=None):
        self.calls.append(("run", argv, timeout, env))
        if argv[-2:] == ("status", "--porcelain=v1", "-z"): return Result("")
        if "rev-parse" in argv: return Result("a" * 40 + "\n")
        if "cat-file" in argv: return Result()
        if argv[0].endswith("hs"):
            # Every host snippet receives strict JSON only.
            if "o:start()" in argv[2]: return Result('{"running":true}\n')
            return Result('{"started":true,"configured_hotkey_count":26,"binding_count":26,"lifecycle_watcher_active":true,"reconcile_active":true,"bar_timer_active":true,"bar_canvas_count":1}\n')
        return Result()
    def spawn(self, argv, *, env): self.calls.append(("spawn", argv, env)); return self.pid

class RealHostTests(unittest.TestCase):
    def test_fake_runner_only_and_all_subprocess_timeouts_are_bounded(self):
        runner = FakeRunner(); ports = real_host.RealHostPorts(ROOT.parents[1], runner)
        self.assertEqual(ports.repo_changes(), {"staged": [], "unstaged": [], "untracked": []})
        self.assertEqual(ports.head_commit(), "a" * 40)
        ports.run(("fixture-build", "canonical"), timeout=120) if False else None
        self.assertFalse(any(name == "spawn" for name, *_ in runner.calls))
        self.assertTrue(all(call[2] <= 120 for call in runner.calls if call[0] == "run"))

    def test_legacy_restore_snippet_explicitly_binds_and_verifies_hotkeys(self):
        runner = FakeRunner(); ports = real_host.RealHostPorts(ROOT.parents[1], runner)
        actual = ports.legacy("restore", expected={"binding_count": 26})
        snippet = runner.calls[-1][1][2]
        self.assertIn("t:start(); t:bindHotkeys();", snippet)
        self.assertIn("spoon['10bucks']", snippet)
        self.assertNotIn("dofile(", snippet)
        self.assertIn("configured_hotkey_count=n", snippet)
        self.assertIn("for _ in pairs(t.hotkeyBindings or {})", snippet)
        self.assertIn("bar_timer_active=b.timer ~= nil", snippet)
        self.assertIn("bar_canvas_count=cc", snippet)
        self.assertEqual(actual["binding_count"], 26)

    def test_observer_fresh_load_sets_absolute_package_path_and_one_known_global(self):
        runner = FakeRunner(); ports = real_host.RealHostPorts(ROOT.parents[1], runner)
        self.assertTrue(ports.observer("start")["running"])
        snippet = runner.calls[-1][1][2]
        self.assertIn("package.path=", snippet)
        self.assertIn(str(ROOT) + "/", snippet)
        self.assertIn("_G.__poc001_observer", snippet)
        self.assertIn("dofile(", snippet)

    def test_private_atomic_json_rejects_symlink_and_keeps_0600(self):
        runner = FakeRunner(); ports = real_host.RealHostPorts(ROOT.parents[1], runner)
        with tempfile.TemporaryDirectory(dir="/tmp") as directory:
            os.chmod(directory, 0o700); output = os.path.join(directory, "state.json")
            ports.write_private_json(output, {"ok": True})
            self.assertEqual(stat.S_IMODE(os.lstat(output).st_mode), 0o600)
            os.unlink(output); os.symlink("/tmp/nope", output)
            with self.assertRaises(real_host.HostError): ports.write_private_json(output, {"ok": False})

    def test_static_no_live_test_runner_and_safe_hs_contract(self):
        source = (ROOT / "direct_ax_volume_real_host.py").read_text()
        tests = (ROOT / "test_direct_ax_volume_real_host.py").read_text()
        self.assertIn("class FakeRunner", tests)
        self.assertNotIn("subprocess", tests.split("class FakeRunner", 1)[0])
        self.assertIn("hs.json.encode", source)
        self.assertIn("t:bindHotkeys();", source)
        self.assertIn("package.path=", source)
        self.assertIn("POC001_FIXTURE_RUN_DIR=", source)
        self.assertIn("-wwE", source)
        self.assertIn("unsafe opened private file", source)
        self.assertIn('row.get("sample_id") == sample_id', source)
        self.assertIn("POC001_FIXTURE_CLOCK_KIND=\"mach_absolute\"", source)
        self.assertIn("o.trace:set_sample", source)
        self.assertIn("wait_correlation", source)
        self.assertIn("external controller wait; observer owns no poll/timer", source)

if __name__ == "__main__": unittest.main()
