#!/usr/bin/env python3
"""TDD coverage for the POC-only controller; no port performs a live action."""
import importlib.util, json, os, shutil, subprocess, sys, tempfile, unittest
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
  self.binding_count = 26; self.fail_marker = self.fail_restore = False; self.pid = 41; self.run_count = 0
  self.fixture_token = "private-token"; self.fixture_requests = []; self.correlation_finished=False; self.waits=[]; self.interrupt_after_create=False; self.fail_map_wait=False; self.fail_normalizer=False
  self.wait_statuses={"map_ready":[False,True],"candidates_complete":[False,True]}
  self.files["/approval"] = json.dumps({"approved_commit":COMMIT}); self.private_files={"/approval"}
 def repo_changes(self): return deepcopy(self.changes)
 def head_commit(self): return self.head
 def commit_exists(self, commit): return commit == COMMIT
 def environment(self): return {"macos_build":"26A1", "architecture":"arm64", "hammerspoon_version":"1.1.1", "branch":"test", "head":COMMIT, "display":"built-in", "settings":"separate_spaces"}
 def make_private_run_dir(self, prefix):
  self.calls.append(("mkdtemp",prefix)); names=("/tmp/p1d.abc123","/tmp/p1d.def456","/tmp/p1d.ghi789","/tmp/p1d.jkl012","/tmp/p1d.mno345","/tmp/p1d.pqr678")
  path=names[self.run_count]; self.run_count+=1; self.dirs.add(path); return path
 def private_dir(self,path): return path in self.dirs
 def private_file(self,path): return path in self.private_files
 def read_text(self,path): return self.files[path]
 def write_private_json(self,path,value): self.calls.append(("write",path)); self.files[path]=json.dumps(value); self.private_files.add(path)
 def read_private_json(self,path): return json.loads(self.files[path])
 def run(self,argv,timeout):
  self.calls.append(("run",argv,timeout)); assert timeout <= 120
  if argv[0] == "normalizer" and self.fail_normalizer: raise RuntimeError("normalizer internal error")
  if argv[0] == "normalizer": self.write_private_json(argv[-1], {"validated":"row"})
  if argv[0] == "analyzer": self.write_private_json(argv[-1], {"analysis_status":"complete","outcome":"pass"})
 def spawn_fixture(self,run_dir,clock_kind,timeout): self.calls.append(("spawn",run_dir,clock_kind,timeout)); self.pid+=1; self.alive=True; self.socket=True; return self.pid
 def fixture_identity(self,pid,run_dir): return {"executable":"fixture", "run_dir":run_dir}
 def process_alive(self,pid,identity=None): return self.alive and pid == self.pid and (identity is None or identity.get("run_dir") in self.dirs)
 def socket_exists(self,path): return self.socket
 def fixture_request(self,run_dir,command,sample_id,token,timeout):
  self.fixture_requests.append((command,sample_id,token,timeout)); assert timeout <= 120
  if command == "close" and self.interrupt_after_create: raise KeyboardInterrupt()
  return {"status":"accepted","sample_id":sample_id,"fixture_token":self.fixture_token,"correlation_alias":"private-alias"}
 def wait_marker(self,path,marker,sample_id,timeout):
  self.calls.append(("marker",marker,sample_id,timeout)); assert timeout <= 120; assert sample_id == "startup" or sample_id.startswith(("warm-", "cold-"))
  if self.fail_marker: raise RuntimeError("timeout")
 def legacy(self,action,**kwargs):
  self.calls.append(("legacy",action))
  def snapshot(): return {"started":self.legacy_running,"configured_hotkey_count":26,"binding_count":self.binding_count,"lifecycle_watcher_active":self.legacy_running,"reconcile_active":self.legacy_running,"bar_timer_active":self.legacy_running,"bar_canvas_count":1 if self.legacy_running else 0}
  if action in {"capture", "inspect"}: return snapshot()
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
  if action == "arm_correlation": self.correlation_finished=False; return {"armed":True}
  if action == "wait_correlation":
   stage=kwargs["stage"]; self.waits.append(stage)
   if stage == "map_ready" and self.fail_map_wait: raise RuntimeError("map wait failed")
   observations=self.wait_statuses[stage]
   self.calls.append(("correlation_observations",stage,list(observations)))
   assert observations == [False,True]
   if stage == "map_ready": assert not any(request[0] == "close" and request[1] == kwargs["sample_id"] for request in self.fixture_requests)
   if stage == "candidates_complete": assert not self.correlation_finished
   return {"ready":True}
  if action == "correlation_ready": return {"ready":True,"map_count":1,"candidates_complete":True}
  if action == "finish_correlation": self.correlation_finished=True; return {"finished":True}
  if action == "snapshot":
   correlation={"armed":not self.correlation_finished,"candidate_source":None if self.correlation_finished else "direct_ax","map_count":0 if self.correlation_finished else 1,"candidate_sources":{"complete":False}}
   self.write_private_json(kwargs["path"], {"lifecycle":"running","callbacks":{"open":0},"active_timers":0,"window_effects":0,"correlation":correlation}); return {"lifecycle":"running","correlation":correlation}
  if action == "export_running": self.write_private_json(kwargs["path"], {"export":True}); return {"ok":True}
  if action == "abort_correlation": return {}
  if action == "stop_export": self.observer_running=False; return {"running":False,"callbacks_open":0,"active_timers":0,"window_effects":0,"direct_application_watchers":0,"direct_window_watchers":0,"target_binding_armed":False,"correlation":{"map_count":0}}
  raise AssertionError(action)
 def fixture_shutdown(self,run_dir,timeout): self.calls.append(("shutdown",timeout)); self.alive=False; self.socket=False
 def terminate(self,pid,identity,timeout): self.calls.append(("terminate",timeout)); self.alive=False
 def wait_process(self,pid,identity,timeout): self.calls.append(("wait",timeout)); return not self.alive

def prepared():
 ports=FakePorts(); machine=controller.DirectAXVolumeController(ports); run=machine.prepare(execute=True,approval_file="/approval"); return ports,machine,run

class ControllerTests(unittest.TestCase):
 def test_prepare_creates_only_private_short_run_state_and_evidence(self):
  ports,machine,run=prepared()
  self.assertEqual(run,"/tmp/p1d.abc123"); self.assertTrue(ports.private_file(run+"/controller-state.json")); self.assertTrue(ports.private_file(run+"/controller-evidence.json"))
  state=ports.read_private_json(run+"/controller-state.json"); self.assertEqual((state["phase"],state["frozen_commit"]),("prepared",COMMIT))
  self.assertFalse(any(call[0] == "spawn" for call in ports.calls))
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
  self.assertTrue(any(call[0] == "spawn" and call[-2] == "mach_absolute" and call[-1] <= 120 for call in ports.calls)); self.assertEqual((state["phase"],state["legacy_baseline"]["binding_count"]),("running",26))
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
 def test_dead_identity_matched_fixture_with_stale_socket_is_preserved_crash_residue(self):
  ports,machine,run=prepared(); machine.warm_start(run_dir=run,execute=True,approval_file="/approval")
  ports.alive=False; ports.socket=True
  with self.assertRaisesRegex(controller.ControllerError,"fixture_crash_residue"):
   machine.abort_cleanup(run_dir=run,execute=True,approval_file="/approval")
  state=ports.read_private_json(run+"/controller-state.json")
  self.assertEqual(state["phase"],"indeterminate"); self.assertTrue(ports.socket)
  self.assertNotIn(("shutdown",120),ports.calls)
  self.assertEqual(next(event for event in state["events"] if event["event"]=="fixture_crash_residue")["disposition"],"preserved")
 def test_stopped_observer_status_is_quiescent(self):
  ports,machine,run=prepared(); machine.warm_start(run_dir=run,execute=True,approval_file="/approval")
  self.assertTrue(machine._zero_observer(ports.observer("stop_export", path=run+"/observer-export.json")))
 def test_stale_state_refuses_start_and_status_is_redacted(self):
  ports,machine,run=prepared(); state=ports.read_private_json(run+"/controller-state.json"); state["phase"]="running"; state["fixture_pid"]=99; ports.write_private_json(run+"/controller-state.json",state)
  with self.assertRaisesRegex(controller.ControllerError,"requires prepared"): machine.warm_start(run_dir=run,execute=True,approval_file="/approval")
  status=machine.status(run_dir=run); self.assertNotIn("pid",status); self.assertNotIn(run,str(status))
  ports,machine,run=prepared(); ports.socket=True
  with self.assertRaisesRegex(controller.ControllerError,"stale fixture PID or socket"): machine.warm_start(run_dir=run,execute=True,approval_file="/approval")
 def test_warm_sample_requires_exact_running_generation_and_never_duplicates_a_create(self):
  ports,machine,run=prepared(); machine.warm_start(run_dir=run,execute=True,approval_file="/approval")
  with self.assertRaisesRegex(controller.ControllerError,"exact next generation"):
   machine.warm_sample(run_dir=run,generation=2,execute=True,approval_file="/approval")
  self.assertEqual(ports.fixture_requests,[])
  result=machine.warm_sample(run_dir=run,generation=1,execute=True,approval_file="/approval")
  self.assertEqual((result["next_generation"],result["samples_completed"]),(2,1))
  self.assertEqual([(item[0],item[1]) for item in ports.fixture_requests],[("create","warm-01"),("close","warm-01")])
  self.assertEqual(ports.waits,["map_ready","candidates_complete"])
  self.assertEqual(ports.fixture_requests[1][2],"private-token")
  with self.assertRaisesRegex(controller.ControllerError,"exact next generation"):
   machine.warm_sample(run_dir=run,generation=1,execute=True,approval_file="/approval")
  self.assertEqual(len(ports.fixture_requests),2)
 def test_interrupt_after_create_semantically_cleans_up_and_restores_bindings(self):
  ports,machine,run=prepared(); machine.warm_start(run_dir=run,execute=True,approval_file="/approval")
  ports.interrupt_after_create=True
  with self.assertRaises(KeyboardInterrupt): machine.warm_sample(run_dir=run,generation=1,execute=True,approval_file="/approval")
  state=ports.read_private_json(run+"/controller-state.json")
  self.assertEqual(state["phase"],"indeterminate")
  self.assertIn(("legacy","restore"),ports.calls)
  self.assertEqual(ports.binding_count,26)
  self.assertEqual([(request[0],request[1]) for request in ports.fixture_requests],[("create","warm-01"),("close","warm-01")])
 def test_map_wait_primary_failure_survives_successful_cleanup_and_binding_restore(self):
  ports,machine,run=prepared(); machine.warm_start(run_dir=run,execute=True,approval_file="/approval"); ports.fail_map_wait=True
  with self.assertRaisesRegex(RuntimeError,"map wait failed"): machine.warm_sample(run_dir=run,generation=1,execute=True,approval_file="/approval")
  state=ports.read_private_json(run+"/controller-state.json")
  self.assertEqual(state["phase"],"indeterminate"); self.assertEqual(ports.binding_count,26)
  self.assertEqual(state["last_failure"],{"stage":"wait_map_ready","reason_class":"runtime_error","cleanup_outcome":"cleaned"})
  events={event["event"]:event for event in state["events"]}
  self.assertEqual(events["warm_sample_primary_failure"]["stage"],"wait_map_ready")
  self.assertEqual(events["warm_sample_cleanup_outcome"]["cleanup_outcome"],"cleaned")
 def test_normalizer_failure_records_normalize_primary_stage(self):
  ports,machine,run=prepared(); machine.warm_start(run_dir=run,execute=True,approval_file="/approval"); ports.fail_normalizer=True
  with self.assertRaisesRegex(RuntimeError,"normalizer internal error"): machine.warm_sample(run_dir=run,generation=1,execute=True,approval_file="/approval")
  self.assertEqual(ports.read_private_json(run+"/controller-state.json")["last_failure"]["stage"],"normalize")
 def test_warm_finish_requires_30_rows_then_quiesces_and_restores_before_class_analysis(self):
  ports,machine,run=prepared(); machine.warm_start(run_dir=run,execute=True,approval_file="/approval")
  state=ports.read_private_json(run+"/controller-state.json")
  state["next_generation"],state["warm_rows"]=31,[{"validated":number} for number in range(30)]
  ports.write_private_json(run+"/controller-state.json",state)
  self.assertEqual(machine.warm_finish(run_dir=run,execute=True,approval_file="/approval")["phase"],"passed")
  names=[call[0:2] for call in ports.calls]
  self.assertIn(("observer","stop_export"),names); self.assertIn(("legacy","restore"),names)
  final=ports.read_private_json(run+"/controller-state.json")
  self.assertEqual(final["phase"],"passed")
  self.assertTrue(ports.private_file(run+"/class-final-cleanup.json"))
  ports,machine,run=prepared(); machine.warm_start(run_dir=run,execute=True,approval_file="/approval")
  with self.assertRaisesRegex(controller.ControllerError,"exactly 30"):
   machine.warm_finish(run_dir=run,execute=True,approval_file="/approval")
 def test_cold_requires_a_finalized_passing_warm_class_then_uses_five_fresh_generation_one_sessions(self):
  ports,machine,run=prepared()
  with self.assertRaisesRegex(controller.ControllerError,"finalized passing warm"):
   machine.cold_sample(run_dir=run,index=1,execute=True,approval_file="/approval")
  state=ports.read_private_json(run+"/controller-state.json"); state["phase"]="passed"; ports.write_private_json(run+"/controller-state.json",state)
  for index in range(1,6):
   result=machine.cold_sample(run_dir=run,index=index,execute=True,approval_file="/approval")
   self.assertEqual((result["next_index"],result["samples_completed"]),(index+1,index))
  self.assertEqual([(name,sample) for name,sample,*_ in ports.fixture_requests], [item for index in range(1,6) for item in (("create",f"cold-{index:02d}"),("close",f"cold-{index:02d}"))])
  arms=[call for call in ports.calls if call == ("observer","arm_correlation")]
  self.assertEqual(len(arms),5)
  cold_spawns=[call for call in ports.calls if call[0] == "spawn"]
  self.assertEqual(len({call[1] for call in cold_spawns}),5)
  state=ports.read_private_json(run+"/controller-state.json")
  self.assertEqual((state["phase"],state["cold_next_index"],len(state["cold_rows"]),len(state["cold_cleanups"])),("cold_ready",6,5,5))
  self.assertEqual([event["sample_id"] for event in state["events"] if event["event"] == "cold_sample_validated"],[f"cold-{n:02d}" for n in range(1,6)])
 def test_cold_failure_or_interrupt_cleans_once_without_retry_and_preserves_indeterminate_state(self):
  ports,machine,run=prepared(); state=ports.read_private_json(run+"/controller-state.json"); state["phase"]="passed"; ports.write_private_json(run+"/controller-state.json",state)
  ports.interrupt_after_create=True
  with self.assertRaises(KeyboardInterrupt): machine.cold_sample(run_dir=run,index=1,execute=True,approval_file="/approval")
  state=ports.read_private_json(run+"/controller-state.json")
  self.assertEqual(state["phase"],"indeterminate")
  self.assertEqual([(name,sample) for name,sample,*_ in ports.fixture_requests],[("create","cold-01"),("close","cold-01")])
  self.assertIn(("legacy","restore"),ports.calls)
 def test_cold_finish_requires_exact_ordered_clean_rows_and_runs_class_analysis(self):
  ports,machine,run=prepared(); state=ports.read_private_json(run+"/controller-state.json")
  state.update(phase="cold_ready",cold_next_index=6,cold_rows=[{"validated":n} for n in range(5)],cold_cleanups=[{"cleanup":n} for n in range(5)],legacy_baseline={"started":True,"configured_hotkey_count":26,"binding_count":26,"lifecycle_watcher_active":True,"reconcile_active":True,"bar_timer_active":True,"bar_canvas_count":1})
  ports.write_private_json(run+"/controller-state.json",state)
  self.assertEqual(machine.cold_finish(run_dir=run,execute=True,approval_file="/approval")["phase"],"cold_passed")
  self.assertTrue(ports.private_file(run+"/cold-class-final-cleanup.json"))
  ports,machine,run=prepared()
  with self.assertRaisesRegex(controller.ControllerError,"exactly five"):
   machine.cold_finish(run_dir=run,execute=True,approval_file="/approval")
 def test_shared_deadline_shrinks_each_subcall_and_recovery_gets_its_own_budget(self):
  ports=FakePorts(); now=[0.0]; machine=controller.DirectAXVolumeController(ports, clock=lambda: now[0]); run=machine.prepare(execute=True,approval_file="/approval")
  original_run, original_spawn=ports.run, ports.spawn_fixture
  def timed_run(argv, timeout):
   original_run(argv, timeout); now[0]+=80
  def timed_spawn(run_dir, clock_kind, timeout):
   value=original_spawn(run_dir, clock_kind, timeout); now[0]+=50; return value
  ports.run, ports.spawn_fixture=timed_run, timed_spawn
  with self.assertRaisesRegex(controller.ControllerError,"deadline exceeded"):
   machine.warm_start(run_dir=run,execute=True,approval_file="/approval")
  spawn=[call for call in ports.calls if call[0] == "spawn"][-1]
  self.assertLessEqual(spawn[-1],40)
  self.assertIn(("legacy","restore"),ports.calls)
  for call in ports.calls:
   if call[0] in {"run","spawn","marker","shutdown","terminate","wait"}: self.assertLessEqual(call[-1],120)
 def test_all_subprocess_boundaries_are_at_most_120_seconds(self):
  ports,machine,run=prepared(); machine.warm_start(run_dir=run,execute=True,approval_file="/approval"); machine.abort_cleanup(run_dir=run,execute=True,approval_file="/approval")
  for call in ports.calls:
   if call[0] in {"run","spawn","marker","shutdown","terminate","wait"}: self.assertLessEqual(call[-1],120)

class CLIIntegrationTests(unittest.TestCase):
 def test_cli_refusal_exits_nonzero_and_approved_prepare_leaves_clean_repo(self):
  """Exercise the executable boundary in an isolated, non-live module tree."""
  host_stub = '''\
import json, os, stat, subprocess
from pathlib import Path
class RealHostPorts:
 def __init__(self, root): self.root=Path(root); self.counter=0
 def repo_changes(self): return {"staged":[],"unstaged":[],"untracked":[]}
 def head_commit(self): return subprocess.check_output(["git","-C",str(self.root),"rev-parse","HEAD"], text=True).strip()
 def commit_exists(self, commit): return True
 def environment(self):
  head=self.head_commit()
  return {"macos_build":"test","architecture":"test","hammerspoon_version":"test","branch":"test","head":head,"display":"test","settings":"test"}
 def make_private_run_dir(self, prefix):
  for name in ("abc123", "def456"):
   path="/tmp/p1d."+name
   try: os.mkdir(path, 0o700); return path
   except FileExistsError: continue
  raise RuntimeError("test run directory collision")
 def private_dir(self, path):
  try: s=os.lstat(path); return stat.S_ISDIR(s.st_mode) and s.st_uid==os.getuid() and stat.S_IMODE(s.st_mode)==0o700
  except OSError: return False
 def private_file(self, path):
  try: s=os.lstat(path); return stat.S_ISREG(s.st_mode) and s.st_uid==os.getuid() and stat.S_IMODE(s.st_mode)==0o600
  except OSError: return False
 def read_text(self, path): return Path(path).read_text()
 def write_private_json(self, path, value):
  Path(path).write_text(json.dumps(value)); os.chmod(path, 0o600)
 def read_private_json(self, path): return json.loads(Path(path).read_text())
'''
  with tempfile.TemporaryDirectory() as temporary, tempfile.TemporaryDirectory() as private:
   repo=Path(temporary); module=repo/"pocs/001-window-events-liveness"; module.mkdir(parents=True)
   shutil.copy2(ROOT/"direct_ax_volume_controller.py", module/"direct_ax_volume_controller.py")
   (module/"direct_ax_volume_real_host.py").write_text(host_stub)
   (repo/"README").write_text("fixture\n")
   for command in (("git","init","-q"),("git","config","user.email","test@example.invalid"),("git","config","user.name","Test"),("git","add","README","pocs"),("git","commit","-qm","fixture")):
    subprocess.run(command, cwd=repo, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
   approval=Path(private)/"approval.json"; approval.write_text(json.dumps({"approved_commit":subprocess.check_output(("git","rev-parse","HEAD"),cwd=repo,text=True).strip()})); os.chmod(approval,0o600)
   refused=subprocess.run((sys.executable,str(module/"direct_ax_volume_controller.py"),"prepare"),cwd=repo,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,timeout=30)
   self.assertNotEqual(refused.returncode,0)
   prepared=subprocess.run((sys.executable,str(module/"direct_ax_volume_controller.py"),"prepare","--execute","--approval-file",str(approval)),cwd=repo,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,timeout=30)
   self.assertEqual(prepared.returncode,0, prepared.stderr)
   self.assertEqual(subprocess.check_output(("git","status","--porcelain"),cwd=repo,text=True),"")
   self.assertFalse(any(repo.rglob("__pycache__")))
   run_dir=prepared.stdout.strip()
   if run_dir.startswith("/tmp/p1d.") and Path(run_dir).is_dir(): shutil.rmtree(run_dir)

if __name__ == "__main__": unittest.main()
