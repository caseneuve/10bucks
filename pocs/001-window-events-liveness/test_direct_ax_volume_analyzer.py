#!/usr/bin/env python3
"""Pure/static tests only; this module never starts a live POC."""
import importlib.util, json, os, pathlib, tempfile, unittest
ROOT = pathlib.Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("analyzer", ROOT / "direct_ax_volume_analyzer.py")
analyzer = importlib.util.module_from_spec(spec); spec.loader.exec_module(analyzer)
ALIAS = "poc001-corr-sha256-" + "a" * 64

def sample(sample_id="warm-01", generation=1, klass="warm"):
    return {"sample_id":sample_id, "generation":generation, "source":"direct_ax", "fixture_alias":ALIAS, "observer_alias":ALIAS,
      "create_count":1, "close_count":1, "map_count_before_close":1, "direct_constructions":1, "direct_identifier_reads":1,
      "filter_constructions":0, "filter_identifier_reads":0, "direct_candidates":[{"alias":ALIAS,"latency_ms":1}], "filter_candidates":[{"alias":ALIAS,"latency_ms":1}],
      "direct_correlation_ms":10, "callback_durations_ms":[10], "steady_global_queries":0, "window_effects":0, "permanent_polls":0,
      "generation_reset":{"finish_called":True,"map_count":0,"armed":False,"candidate_source":None},
      "session_after_generation":{"callbacks_open":0,"active_timers":0,"window_effects":0,"observer_running":klass == "warm","fixture_running":klass == "warm"}}

def final_cleanup(): return {"observer_stopped":True,"callbacks_open":0,"active_timers":0,"window_effects":0,"map_count":0,"fixture_process_absent":True,"fixture_socket_absent":True,"legacy_restarted":True}

class Tests(unittest.TestCase):
 def test_frozen_constants_and_short_socket(self):
  self.assertEqual((analyzer.WARM_SAMPLES, analyzer.COLD_SAMPLES, analyzer.SOURCE), (30,5,"direct_ax")); self.assertLess(len(analyzer.socket_path_template("abc123")),104)
 def test_warm_keeps_session_running_but_requires_finish_reset(self):
  result=analyzer.analyze_sample(sample(),"warm"); self.assertEqual(result["generation"],1)
  row=sample(); row["generation_reset"]["candidate_source"]="direct_ax"
  with self.assertRaisesRegex(analyzer.SubstantiveFailure,"candidate_source_not_reset"): analyzer.analyze_sample(row,"warm")
  row=sample(); row["session_after_generation"]["observer_running"]=False
  with self.assertRaisesRegex(analyzer.SubstantiveFailure,"observer_running"): analyzer.analyze_sample(row,"warm")
 def test_required_or_ill_typed_fields_are_indeterminate_not_platform_failures(self):
  for key in ("source","create_count","generation_reset","candidate_source"):
   row=sample()
   if key == "candidate_source": del row["generation_reset"][key]
   else: del row[key]
   with self.subTest(key=key), self.assertRaises(analyzer.AnalyzerError): analyzer.analyze_sample(row,"warm")
  row=sample(); row["source"]=False
  with self.assertRaises(analyzer.AnalyzerError): analyzer.analyze_sample(row,"warm")
 def test_exact_gates_and_cold_bound_are_substantive(self):
  row=sample(); row["filter_identifier_reads"]=1
  with self.assertRaisesRegex(analyzer.SubstantiveFailure,"filter_identifier_reads"): analyzer.analyze_sample(row,"warm")
  row=sample("cold-01",1,"cold"); row["direct_correlation_ms"]=3001
  with self.assertRaisesRegex(analyzer.SubstantiveFailure,"cold_correlation_ms"): analyzer.analyze_sample(row,"cold")
 def test_class_requires_unique_exact_generations_and_final_cleanup(self):
  warm=[sample(f"warm-{n:02d}",n) for n in range(1,31)]
  self.assertEqual(analyzer.analyze_class(warm,"warm",final_cleanup())["outcome"],"pass")
  warm[-1]["generation"]=1
  self.assertEqual(analyzer.analyze_class(warm,"warm",final_cleanup())["reason"],"duplicate_generation")
  with self.assertRaises(analyzer.AnalyzerError): analyzer.analyze_class([sample()],"warm",final_cleanup())
  bad=final_cleanup(); del bad["legacy_restarted"]
  with self.assertRaises(analyzer.AnalyzerError): analyzer.analyze_class([sample(f"warm-{n:02d}",n) for n in range(1,31)],"warm",bad)
 def test_sample_cli_and_atomic_no_follow_output(self):
  with tempfile.TemporaryDirectory() as directory:
   os.chmod(directory,0o700); d=pathlib.Path(directory); source=d/"sample.json"; output=d/"out.json"
   source.write_text(json.dumps(sample()),encoding="utf-8"); os.chmod(source,0o600)
   self.assertEqual(analyzer.main(["sample","warm",str(source),str(output)]),0); self.assertNotIn("alias",output.read_text())
   target=d/"target"; target.write_text("retain",encoding="utf-8"); output.unlink(); output.symlink_to(target)
   self.assertEqual(analyzer.main(["sample","warm",str(source),str(output)]),2); self.assertEqual(target.read_text(),"retain")
 def test_procedure_honestly_names_analyzer_and_next_live_slice(self):
  text=(ROOT/"DIRECT-AX-VOLUME.md").read_text()
  self.assertIn("not a live runner",text); self.assertIn("Executable next slice",text); self.assertIn("sample warm",text)
if __name__ == "__main__": unittest.main()
