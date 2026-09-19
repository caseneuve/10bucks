import importlib.util
import json
import os
from pathlib import Path
import stat
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("runner", ROOT / "scripts/canary-walking-stack.py")
runner = importlib.util.module_from_spec(spec); spec.loader.exec_module(runner)


class CanaryRunnerTest(unittest.TestCase):
    def approval(self, directory, commit="candidate"):
        path = Path(directory) / "approval.json"; path.write_text(json.dumps({"candidateCommit": commit})); os.chmod(path, 0o600); return path

    def test_atomic_symlink_replaces_link_instead_of_following_directory_target(self):
        with tempfile.TemporaryDirectory() as directory:
            directory = Path(directory); old, new = directory / "old", directory / "new"; old.mkdir(); new.mkdir(); link = directory / "installed"; os.symlink(old, link)
            runner.atomic_symlink(new, link)
            self.assertTrue(link.is_symlink()); self.assertEqual(os.readlink(link), str(new)); self.assertFalse((old / ".walking-stack-new").exists())

    def test_approval_requires_exact_commit_regular_owner_only_mode(self):
        with tempfile.TemporaryDirectory() as directory:
            approval = self.approval(directory); runner.require_approval(approval, "candidate")
            with self.assertRaises(RuntimeError): runner.require_approval(approval, "other")
            os.chmod(approval, 0o644)
            with self.assertRaises(RuntimeError): runner.require_approval(approval, "candidate")

    def test_stable_config_preflight_accepts_owner_owned_readable_0644(self):
        with tempfile.TemporaryDirectory() as directory:
            config = Path(directory) / "config"; config.write_text("stable"); os.chmod(config, 0o644)
            runner.require_owner_owned_nonwritable_regular(config, "config")

    def test_stable_config_preflight_rejects_group_or_other_writable_modes(self):
        with tempfile.TemporaryDirectory() as directory:
            config = Path(directory) / "config"; config.write_text("stable")
            for mode in (0o620, 0o606):
                os.chmod(config, mode)
                with self.assertRaisesRegex(RuntimeError, "no group/other write bits"):
                    runner.require_owner_owned_nonwritable_regular(config, "config")

    def test_stable_config_preflight_rejects_symlink(self):
        with tempfile.TemporaryDirectory() as directory:
            directory = Path(directory); target = directory / "target"; target.write_text("config"); os.chmod(target, 0o600)
            config = directory / "config"; os.symlink(target, config)
            with self.assertRaisesRegex(RuntimeError, "regular non-symlink"):
                runner.require_owner_owned_nonwritable_regular(config, "config")

    def test_atomic_regular_replace_never_follows_config_symlink(self):
        with tempfile.TemporaryDirectory() as directory:
            directory = Path(directory); source = directory / "source"; source.write_text("candidate"); os.chmod(source, 0o600)
            original = directory / "original"; original.write_text("stable"); os.chmod(original, 0o600)
            target = directory / "config"; target.write_text("old"); os.chmod(target, 0o600)
            runner.atomic_regular_replace(source, target, 0o600, "config")
            self.assertEqual(target.read_text(), "candidate"); self.assertEqual(stat.S_IMODE(target.stat().st_mode), 0o600)
            symlink = directory / "symlink"; os.symlink(original, symlink)
            with self.assertRaisesRegex(RuntimeError, "regular non-symlink"):
                runner.atomic_regular_replace(source, symlink, 0o600, "config")
            self.assertEqual(original.read_text(), "stable")

    def test_candidate_replacement_accepts_captured_0644_destination(self):
        with tempfile.TemporaryDirectory() as directory:
            directory = Path(directory)
            source, target = directory / "temporary", directory / "config"
            source.write_text("candidate"); os.chmod(source, 0o600)
            target.write_text("stable"); os.chmod(target, 0o644)
            runner.atomic_regular_replace(source, target, 0o600, "candidate config", destination_mode=0o644)
            self.assertEqual(target.read_text(), "candidate")
            self.assertEqual(stat.S_IMODE(target.stat().st_mode), 0o600)

    def test_atomic_regular_replace_preserves_captured_stable_mode(self):
        with tempfile.TemporaryDirectory() as directory:
            directory = Path(directory)
            source, target = directory / "backup", directory / "config"
            source.write_text("stable"); os.chmod(source, 0o600)
            target.write_text("candidate"); os.chmod(target, 0o644)
            runner.atomic_regular_replace(source, target, 0o644, "config restore")
            self.assertEqual(target.read_text(), "stable")
            self.assertEqual(stat.S_IMODE(target.stat().st_mode), 0o644)

    def test_framed_hs_response_ignores_logs_and_requires_one_marker(self):
        value = runner.parse_envelope("load log\n" + runner.MARKER + '{"ok":true,"value":{"version":"1.1.1"}}\nmore log')
        self.assertEqual(value["value"]["version"], "1.1.1")
        with self.assertRaises(RuntimeError): runner.parse_envelope("nothing")

    def test_reload_accepts_transport_exit_69_then_waits_for_health(self):
        calls = []
        class Result:
            def __init__(self, code, out="", err=""): self.returncode, self.stdout, self.stderr = code, out, err
        def fake_shell(args, **kwargs):
            calls.append(args)
            if len(calls) == 1: return Result(69, "", "connection invalidated")
            return Result(0, runner.MARKER + '{"ok":true,"value":{"version":"1.1.1"}}\n')
        with patch.object(runner, "shell", fake_shell): self.assertEqual(runner.reload_and_wait()["version"], "1.1.1")

    def test_start_failure_attempts_in_process_rollback(self):
        with tempfile.TemporaryDirectory() as directory:
            directory = Path(directory); config = directory / "config"; config.write_text("stable"); os.chmod(config, 0o600); temp = directory / "temp"; temp.write_text("canaryInstrumentation = true"); os.chmod(temp, 0o600)
            args = type("A", (), {"link":directory / "link", "config":config, "approval":self.approval(directory), "temporary_config":str(temp), "state":directory / "state"})()
            before = {"candidateCommit":"candidate", "configMode":0o600, "baseline":{}, "configSha256":runner.digest(config)}
            with patch.object(runner, "preflight", return_value=before), patch.object(runner, "stop_stable"), patch.object(runner, "reload_and_wait", side_effect=RuntimeError("candidate load failed")), patch.object(runner, "restore", return_value={} ) as restore:
                with self.assertRaisesRegex(RuntimeError, "candidate start failed"):
                    runner.start_capture(args)
                restore.assert_called_once()
            self.assertFalse(args.state.exists())
            self.assertFalse(args.state.with_suffix(".config-backup").exists())

    def test_stable_probe_uses_verified_legacy_fields_and_safe_timer_running(self):
        self.assertIn("s.lifecycle.filter", runner.STABLE_PROBE_LUA)
        self.assertIn("s.lifecycle.reconcileTimer", runner.STABLE_PROBE_LUA)
        self.assertIn("s.bar.timer", runner.STABLE_PROBE_LUA)
        self.assertIn("pcall(timer.running,timer)", runner.STABLE_PROBE_LUA)
        self.assertIn("configuredBindings", runner.STABLE_PROBE_LUA)
        self.assertIn("installedBindings", runner.STABLE_PROBE_LUA)

    def test_baseline_mismatch_is_never_restored(self):
        expected = {"hammerspoonVersion":"1.1.1","spoonVersion":"stable","started":True,"configuredBindings":26,"installedBindings":26,"lifecycleFilter":True,"reconcileTimerRunning":True,"barTimerRunning":True,"canvases":1}
        actual = dict(expected); actual["installedBindings"] = 25
        self.assertFalse(runner.equal_baseline(actual, expected))

    def test_runtime_watcher_preflight_requires_exact_installed_shapes(self):
        with patch.object(runner, "hs_query", return_value={"windowNewWatcher":"function", "axElementNewWatcher":"nil", "applicationNewWatcher":"function"}):
            self.assertEqual(runner.require_runtime_watcher_shapes()["windowNewWatcher"], "function")
        with patch.object(runner, "hs_query", return_value={"windowNewWatcher":"nil", "axElementNewWatcher":"function", "applicationNewWatcher":"function"}):
            with self.assertRaisesRegex(RuntimeError, "watcher methods"):
                runner.require_runtime_watcher_shapes()

    def test_capture_status_rejects_missing_state_or_wrong_runtime(self):
        with tempfile.TemporaryDirectory() as directory:
            directory = Path(directory); args = type("A", (), {"state":directory / "missing", "link":directory / "link"})()
            with self.assertRaisesRegex(RuntimeError, "no active candidate"):
                runner.capture_status(args)
            state = {"before":{"candidateCommit":"candidate","runtimeVersion":"1.1.1"}}
            args.state.write_text(json.dumps(state))
            with patch.object(runner, "candidate_commit", return_value="candidate"), patch.object(runner, "link_target", return_value=str(runner.SPOON)), patch.object(runner, "candidate_probe", return_value={"version":"1.1.1","spoonVersion":"wrong","started":True,"canary":{"enabled":True}}):
                with self.assertRaisesRegex(RuntimeError, "not the verified candidate"):
                    runner.capture_status(args)


if __name__ == "__main__": unittest.main()
