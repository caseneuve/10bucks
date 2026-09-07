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
            if "o:start()" in argv[2]: return Result('__POC001_SAFE_JSON__ {"running":true}\n')
            return Result('__POC001_SAFE_JSON__ {"started":true,"configured_hotkey_count":26,"binding_count":26,"lifecycle_watcher_active":true,"reconcile_active":true,"bar_timer_active":true,"bar_canvas_count":1}\n')
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

    def test_hs_envelope_requires_one_explicit_emitter_and_rejects_bad_responses(self):
        runner = FakeRunner(); ports = real_host.RealHostPorts(ROOT.parents[1], runner)
        runner.run = lambda argv, *, timeout, env=None: Result('hotkey diagnostic\n__POC001_SAFE_JSON__ {"ok":true}\n')
        self.assertEqual(ports._hs("__poc001_out({ok=true})"), {"ok": True})
        with self.assertRaisesRegex(real_host.HostError, "envelope body"): ports._hs("print(hs.json.encode({ok=true}))")
        with self.assertRaisesRegex(real_host.HostError, "envelope body"): ports._hs("__poc001_out({ok=true}); __poc001_out({ok=false})")
        runner.run = lambda argv, *, timeout, env=None: Result('__POC001_SAFE_JSON__ {"ok":true}\n__POC001_SAFE_JSON__ {"ok":false}\n')
        with self.assertRaises(real_host.HostError): ports._hs("__poc001_out({ok=true})")
        runner.run = lambda argv, *, timeout, env=None: Result('__POC001_SAFE_JSON__ not-json\n')
        with self.assertRaises(real_host.HostError): ports._hs("__poc001_out({ok=true})")

    def test_every_approved_lua_body_is_balanced_and_has_one_explicit_envelope(self):
        runner = FakeRunner(); ports = real_host.RealHostPorts(ROOT.parents[1], runner)
        ports.environment()
        ports.legacy("restore", expected={"binding_count": 26})
        ports.clear_modules(real_host.APPROVED_MODULES)
        ports.observer("start")
        ports.observer("arm_correlation", sample_id="warm-01", generation=1, source="direct_ax")
        ports.observer("correlation_ready")
        ports.observer("finish_correlation")
        snippets = [call[1][2] for call in runner.calls if call[0] == "run" and call[1][0].endswith("hs")]
        self.assertGreaterEqual(len(snippets), 7)
        for snippet in snippets:
            self.assertEqual(snippet.count("__poc001_out("), 2) # injected definition + body call
            self.assertNotIn("print(hs.json.encode", snippet)
            self._assert_balanced_lua(snippet)

    @staticmethod
    def _assert_balanced_lua(source):
        pairs = {")": "(", "]": "[", "}": "{"}; stack = []; quote = None; escaped = False
        for char in source:
            if quote:
                if escaped: escaped = False
                elif char == "\\": escaped = True
                elif char == quote: quote = None
            elif char in "'\"": quote = char
            elif char in "([{": stack.append(char)
            elif char in pairs:
                if not stack or stack.pop() != pairs[char]: raise AssertionError("unbalanced Lua snippet")
        if quote or stack: raise AssertionError("unbalanced Lua snippet")

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
        self.assertIn("len(argv) == 9", source)
        self.assertIn('action in {"capture", "inspect"}', source)

if __name__ == "__main__": unittest.main()
