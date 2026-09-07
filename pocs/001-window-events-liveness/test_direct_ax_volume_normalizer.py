#!/usr/bin/env python3
"""Pure fixtures for the POC-001 private normalizer; no live orchestration."""
import importlib.util, json, os, pathlib, tempfile, unittest
ROOT = pathlib.Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("normalizer", ROOT / "direct_ax_volume_normalizer.py")
normalizer = importlib.util.module_from_spec(spec); spec.loader.exec_module(normalizer)
analyzer_spec = importlib.util.spec_from_file_location("analyzer", ROOT / "direct_ax_volume_analyzer.py")
analyzer = importlib.util.module_from_spec(analyzer_spec); analyzer_spec.loader.exec_module(analyzer)
ALIAS = "poc001-corr-sha256-" + "a" * 64

def fixture_record(sequence, event, sample, token="fixture-win-secret", **fields):
    result = {"schema":"poc001-fixture-v1","sequence":sequence,"event":event,"sample_id":sample,"fixture_token":token,"clock_kind":"mach_absolute","ticks":100 + sequence * 10,"timebase_numer":1,"timebase_denom":1}
    result.update(fields); return result

def inputs(sample="warm-02"):
    trace = [fixture_record(1,"create_requested","warm-01", "fixture-win-old", correlation_alias="poc001-corr-sha256-"+"b"*64), fixture_record(2,"native_close_completed","warm-01", "fixture-win-old", origin="ipc"), fixture_record(3,"create_requested",sample, correlation_alias=ALIAS), fixture_record(4,"native_close_completed",sample, origin="ipc")]
    events = [
      {"sample_id":sample,"marker":"correlation_armed","candidate_source":"direct_ax"},
      {"sample_id":sample,"marker":"query_attempt","query":"correlation_direct_ax_window_element_construction","scope":"steady"},
      {"sample_id":sample,"marker":"query_attempt","query":"correlation_direct_ax_identifier_read","scope":"steady"},
      {"sample_id":sample,"marker":"correlation_observed","source":"direct_ax","correlation_alias":ALIAS,"absolute_ns":150},
      {"sample_id":sample,"marker":"destruction_candidate","source":"filter","correlation_alias":ALIAS,"absolute_ns":160},
      {"sample_id":sample,"marker":"destruction_candidate","source":"direct_ax","correlation_alias":ALIAS,"absolute_ns":170},
      {"sample_id":sample,"marker":"callback_exit","duration_ms":4},
      {"sample_id":sample,"marker":"correlation_finished","correlation_armed":False,"correlation_map_count":0},
    ]
    export = {"schema":"poc-001-trace-v1","events":events,"status":{"steady_global_queries":0}}
    snapshot = {"lifecycle":"running","fixture_running":True,"callbacks":{"open":0},"active_timers":0,"window_effects":0,"correlation":{"armed":False,"map_count":0,"candidate_source":None,"candidate_sources":{"count":0,"direct_ax":False,"filter":False,"complete":False}}}
    return {"status":"accepted","sample_id":sample,"fixture_token":"fixture-win-secret","correlation_alias":ALIAS}, trace, export, snapshot

class Tests(unittest.TestCase):
 def test_derives_direct_row_from_cumulative_warm_evidence(self):
  response, trace, export, snapshot = inputs(); row = normalizer.normalize(response,trace,export,snapshot,"warm")
  self.assertEqual((row["sample_id"],row["generation"],row["direct_constructions"],row["filter_identifier_reads"]),("warm-02",2,1,0))
  self.assertEqual(row["direct_correlation_ms"],0.00002); self.assertEqual(row["direct_candidates"][0]["latency_ms"],0.00003)
  self.assertNotIn("fixture_token",json.dumps(row)); self.assertNotIn("secret",json.dumps(row))
 def test_candidate_order_is_irrelevant_but_duplicates_missing_and_wrong_sample_are_errors(self):
  response, trace, export, snapshot = inputs(); export["events"].reverse()
  self.assertEqual(normalizer.normalize(response,trace,export,snapshot,"warm")["generation"],2)
  response, trace, export, snapshot = inputs(); export["events"].append(dict(export["events"][5]))
  self.assertEqual(len(normalizer.normalize(response,trace,export,snapshot,"warm")["direct_candidates"]),2)
  response, trace, export, snapshot = inputs(); export["events"]=[e for e in export["events"] if e.get("marker") != "destruction_candidate"]
  row=normalizer.normalize(response,trace,export,snapshot,"warm"); self.assertEqual(row["direct_candidates"],[])
  with self.assertRaisesRegex(analyzer.SubstantiveFailure,"direct_candidate_count"): analyzer.analyze_sample(row,"warm")
 def test_analyzer_will_classify_missing_candidates_as_substantive_not_normalizer_platform_failure(self):
  # Candidate absence is an exact derived zero; malformed/ambiguous evidence is indeterminate.
  response, trace, export, snapshot = inputs(); export["events"].append({"sample_id":"warm-01","marker":"correlation_observed","source":"direct_ax","correlation_alias":ALIAS,"absolute_ns":1})
  self.assertEqual(normalizer.normalize(response,trace,export,snapshot,"warm")["observer_alias"],ALIAS)
 def test_private_raw_identity_or_content_is_an_indeterminate_normalizer_error(self):
  response, trace, export, snapshot = inputs(); export["events"][0]["title"]="never-export"
  with self.assertRaisesRegex(normalizer.NormalizerError,"sensitive_input"): normalizer.normalize(response,trace,export,snapshot,"warm")
  response, trace, export, snapshot = inputs(); snapshot["pid"]=123
  with self.assertRaisesRegex(normalizer.NormalizerError,"sensitive_input"): normalizer.normalize(response,trace,export,snapshot,"warm")
 def test_reset_status_modes_and_clock_contradictions_fail_closed(self):
  response, trace, export, snapshot = inputs(); snapshot["correlation"]["candidate_source"]="direct_ax"
  with self.assertRaisesRegex(normalizer.NormalizerError,"generation_not_reset"): normalizer.normalize(response,trace,export,snapshot,"warm")
  response, trace, export, snapshot = inputs(); trace[2]["clock_kind"]="mach_continuous"
  with self.assertRaisesRegex(normalizer.NormalizerError,"fixture_clock_not_absolute"): normalizer.normalize(response,trace,export,snapshot,"warm")
  response, trace, export, snapshot = inputs("cold-01"); trace=trace[2:]; snapshot["lifecycle"]="stopped"; snapshot["fixture_running"]=False
  self.assertEqual(normalizer.normalize(response,trace,export,snapshot,"cold")["generation"],1)
 def test_cli_private_modes_atomic_output_and_no_stdout_alias(self):
  response, trace, export, snapshot = inputs()
  with tempfile.TemporaryDirectory() as directory:
   os.chmod(directory,0o700); d=pathlib.Path(directory); paths=[]
   for name,data in (("response.json",response),("observer.json",export),("snapshot.json",snapshot)):
    path=d/name; path.write_text(json.dumps(data)); os.chmod(path,0o600); paths.append(path)
   trace_path=d/"trace.ndjson"; trace_path.write_text("".join(json.dumps(x)+"\n" for x in trace)); os.chmod(trace_path,0o600)
   output=d/"row.json"; self.assertEqual(normalizer.main(["warm",str(paths[0]),str(trace_path),str(paths[1]),str(paths[2]),str(output)]),0)
   self.assertEqual(os.stat(output).st_mode & 0o777,0o600); self.assertNotIn("fixture-win-secret",output.read_text())
if __name__ == "__main__": unittest.main()
