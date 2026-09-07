#!/usr/bin/env python3
"""TDD coverage for the POC-only controller; no port performs a live action."""
import importlib.util, json, sys, unittest
from copy import deepcopy
from pathlib import Path

ROOT = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("controller", ROOT / "direct_ax_volume_controller.py")
controller = importlib.util.module_from_spec(spec); sys.modules[spec.name] = controller; spec.loader.exec_module(controller)
COMMIT = "a" * 40

class FakePorts:
 def __init__(self):
  self.files, self.dirs, self.calls = {}, {"/tmp/p1d.abc123"}, []
  self.changes = {"staged":[], "unstaged":[], "untracked":[]}; self.head = COMMIT
  self.alive, self.socket, self.legacy_running, self.observer_running = False, False, True, False
  self.binding_count = 26; self.fail_marker = self.fail_restore = False; self.pid = 42
  self.files["/approval"] = json.dumps({"approved_commit":COMMIT}); self.private_files={"/approval"}
 def repo_changes(self): return deepcopy(self.changes)
 def head_commit(self): return self.head
 def commit_exists(self, commit): return commit == COMMIT
 def environment(self): return {"os":"redacted", "commit":COMMIT}
 def make_private_run_dir(self, prefix): self.calls.append(("mkdtemp",prefix)); return "/tmp/p1d.abc123"
 def private_dir(self,path): return path in self.dirs
 def private_file(self,path): return path in self.private_files
 def read_text(self,path): return self.files[path]
 def write_private_json(self,path,value): self.calls.append(("write",path)); self.files[path]=json.dumps(value); self.private_files.add(path)
 def read_private_json(self,path): return json.loads(self.files[path])
 def run(self,argv,timeout): self.calls.append(("run",argv,timeout)); assert timeout <= 120
 def spawn_fixture(self,run_dir,clock_kind,timeout): self.calls.append(("spawn",clock_kind,timeout)); self.alive=True; self.socket=True; return self.pid
 def process_alive(self,pid): return self.alive and pid == self.pid
 def socket_exists(self,path): return self.socket
 def wait_marker(self,path,marker,timeout):
  self.calls.append(("marker",marker,timeout)); assert timeout <= 120
  if self.fail_marker: raise RuntimeError("timeout")
 def legacy(self,action,**kwargs):
  self.calls.append(("legacy",action))
  def snapshot(): return {"started":self.legacy_running,"configured_hotkey_count":self.binding_count,"binding_count":self.binding_count,"lifecycle_watcher_active":True,"reconcile_active":True,"bar_active":True}
  if action == "capture": return snapshot()
  if action == "stop": self.legacy_running=False; self.binding_count=0; return snapshot()
  if action == "restore":
   self.legacy_running=not self.fail_restore
   if not self.fail_restore: self.binding_count=kwargs["expected"]["binding_count"]
   return snapshot()
  raise AssertionError(action)
 def clear_modules(self,modules): self.calls.append(("clear",modules)); assert modules == controller.APPROVED_MODULES
 def observer(self,action,**kwargs):
  self.calls.append(("observer",action))
  if action == "start": self.observer_running=True; return {"running":True}
  if action == "abort_correlation": return {}
  if action == "stop_export": self.observer_running=False; return {"running":False,"callbacks_open":0,"active_timers":0,"window_effects":0,"direct_application_watchers":0,"direct_window_watchers":0,"target_binding_armed":False,"correlation":{"map_count":0}}
  raise AssertionError(action)
 def fixture_shutdown(self,run_dir,timeout): self.calls.append(("shutdown",timeout)); self.alive=False; self.socket=False
 def terminate(self,pid,timeout): self.calls.append(("terminate",timeout)); self.alive=False
 def wait_process(self,pid,timeout): self.calls.append(("wait",timeout)); return not self.alive

def prepared():
 ports=FakePorts(); machine=controller.DirectAXVolumeController(ports); run=machine.prepare(execute=True,approval_file="/approval"); return ports,machine,run

class ControllerTests(unittest.TestCase):
 def test_prepare_creates_only_private_short_run_state_and_evidence(self):
  ports,machine,run=prepared()
  self.assertEqual(run,"/tmp/p1d.abc123"); self.assertTrue(ports.private_file(run+"/controller-state.json")); self.assertTrue(ports.private_file(run+"/controller-evidence.json"))
  state=ports.read_private_json(run+"/controller-state.json"); self.assertEqual((state["phase"],state["frozen_commit"]),("prepared",COMMIT))
  self.assertNotIn(("spawn","mach_absolute",120),ports.calls)
 def test_every_mutation_requires_execute_private_approval_and_clean_relative_preflight(self):
  ports=FakePorts(); machine=controller.DirectAXVolumeController(ports)
  with self.assertRaisesRegex(controller.ControllerError,"--execute"): machine.prepare(execute=False,approval_file="/approval")
  ports.private_files.remove("/approval")
  with self.assertRaisesRegex(controller.ControllerError,"owner-private"): machine.prepare(execute=True,approval_file="/approval")
  ports.private_files.add("/approval"); ports.changes["untracked"]=["new-file"]
  with self.assertRaisesRegex(controller.ControllerError,"untracked"): machine.prepare(execute=True,approval_file="/approval")
  ports.changes["untracked"]= ["/absolute"]
  with self.assertRaisesRegex(controller.ControllerError,"repo-relative"): machine.prepare(execute=True,approval_file="/approval")
 def test_warm_start_persists_cleanup_before_stopping_legacy_and_uses_exact_fixture_mode(self):
  ports,machine,run=prepared(); result=machine.warm_start(run_dir=run,execute=True,approval_file="/approval")
  self.assertEqual(result["phase"],"running")
  names=[call[0] for call in ports.calls]; stop_index=ports.calls.index(("legacy","stop"))
  self.assertLess(names.index("spawn"), stop_index); self.assertLess(stop_index, names.index("clear"))
  state=ports.read_private_json(run+"/controller-state.json")
  self.assertIn(("spawn","mach_absolute",120),ports.calls); self.assertEqual((state["phase"],state["legacy_baseline"]["binding_count"]),("running",26))
 def test_startup_partial_failure_uses_abort_cleanup_and_preserves_indeterminate_evidence(self):
  ports,machine,run=prepared(); ports.fail_marker=True
  with self.assertRaisesRegex(RuntimeError,"timeout"): machine.warm_start(run_dir=run,execute=True,approval_file="/approval")
  self.assertEqual(ports.read_private_json(run+"/controller-state.json")["phase"],"cleaned")
  self.assertIn(("observer","abort_correlation"),ports.calls); self.assertIn(("legacy","restore"),ports.calls)
 def test_started_with_zero_bindings_is_indeterminate_not_a_restoration_success(self):
  ports,machine,run=prepared(); machine.warm_start(run_dir=run,execute=True,approval_file="/approval")
  original=ports.legacy
  def started_only(action, **kwargs):
   result=original(action, **kwargs)
   if action == "restore": ports.binding_count=0; result["binding_count"]=0
   return result
  ports.legacy=started_only
  with self.assertRaisesRegex(controller.ControllerError,"legacy_restore_semantic"):
   machine.abort_cleanup(run_dir=run,execute=True,approval_file="/approval")
  self.assertEqual(ports.read_private_json(run+"/controller-state.json")["phase"],"indeterminate")
 def test_abort_cleanup_is_idempotent_and_records_restoration_failure_as_indeterminate(self):
  ports,machine,run=prepared(); machine.warm_start(run_dir=run,execute=True,approval_file="/approval")
  self.assertEqual(machine.abort_cleanup(run_dir=run,execute=True,approval_file="/approval")["phase"],"cleaned")
  self.assertEqual(machine.abort_cleanup(run_dir=run,execute=True,approval_file="/approval")["phase"],"cleaned")
  ports,machine,run=prepared(); ports.fail_marker=True; ports.fail_restore=True
  with self.assertRaisesRegex(controller.ControllerError,"indeterminate"):
   machine.warm_start(run_dir=run,execute=True,approval_file="/approval")
  self.assertEqual(ports.read_private_json(run+"/controller-state.json")["phase"],"indeterminate")
  self.assertTrue(ports.private_file(run+"/controller-evidence.json"))
 def test_stale_state_refuses_start_and_status_is_redacted(self):
  ports,machine,run=prepared(); state=ports.read_private_json(run+"/controller-state.json"); state["phase"]="running"; state["fixture_pid"]=99; ports.write_private_json(run+"/controller-state.json",state)
  with self.assertRaisesRegex(controller.ControllerError,"requires prepared"): machine.warm_start(run_dir=run,execute=True,approval_file="/approval")
  status=machine.status(run_dir=run); self.assertNotIn("pid",status); self.assertNotIn(run,str(status))
  ports,machine,run=prepared(); ports.socket=True
  with self.assertRaisesRegex(controller.ControllerError,"stale fixture PID or socket"): machine.warm_start(run_dir=run,execute=True,approval_file="/approval")
 def test_all_subprocess_boundaries_are_at_most_120_seconds(self):
  ports,machine,run=prepared(); machine.warm_start(run_dir=run,execute=True,approval_file="/approval"); machine.abort_cleanup(run_dir=run,execute=True,approval_file="/approval")
  for call in ports.calls:
   if call[0] in {"run","spawn","marker","shutdown","terminate","wait"}: self.assertLessEqual(call[-1],120)

if __name__ == "__main__": unittest.main()
