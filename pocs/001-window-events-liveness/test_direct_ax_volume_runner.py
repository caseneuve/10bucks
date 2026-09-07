#!/usr/bin/env python3
"""Pure tests for the retained POC-001 direct-AX volume analyzer; no live actions."""
import importlib.util
import json
import os
import pathlib
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("direct_ax_volume_runner", ROOT / "direct_ax_volume_runner.py")
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)

ALIAS = "poc001-corr-sha256-" + "a" * 64


def sample(sample_id="warm-001", correlation_ms=10.0, callback_ms=(10.0,)):
    return {
        "sample_id": sample_id,
        "source": "direct_ax",
        "fixture_alias": ALIAS,
        "observer_alias": ALIAS,
        "map_count_before_close": 1,
        "direct_constructions": 1,
        "direct_identifier_reads": 1,
        "filter_constructions": 0,
        "filter_identifier_reads": 0,
        "direct_candidates": [{"alias": ALIAS, "latency_ms": 3.0}],
        "filter_candidates": [{"alias": ALIAS, "latency_ms": 4.0}],
        "direct_correlation_ms": correlation_ms,
        "callback_durations_ms": list(callback_ms),
        "steady_global_queries": 0,
        "window_effects": 0,
        "permanent_polls": 0,
        "cleanup": {
            "observer_stopped": True, "callbacks_open": 0, "active_timers": 0,
            "window_effects": 0, "map_count": 0, "fixture_process_absent": True,
            "fixture_socket_absent": True,
        },
    }


class DirectAXVolumeRunnerTests(unittest.TestCase):
    def test_frozen_semantics_and_short_socket_template(self):
        self.assertEqual(runner.WARM_SAMPLES, 30)
        self.assertEqual(runner.COLD_SAMPLES, 5)
        self.assertEqual(runner.SOURCE, "direct_ax")
        self.assertEqual(runner.socket_path_template("abc123"), "/tmp/p1d.abc123/poc001-fixture.sock")
        self.assertLess(len(runner.socket_path_template("x" * 6)), 104)

    def test_exact_per_sample_contract_passes(self):
        result = runner.analyze_sample(sample(), "warm")
        self.assertEqual(result["sample_id"], "warm-001")
        self.assertEqual(result["direct_correlation_ms"], 10.0)
        self.assertNotIn("alias", result)

    def test_query_alias_candidate_and_cleanup_gates_fail_substantively(self):
        cases = [
            ("filter_identifier_reads", 1, "filter_identifier_reads"),
            ("map_count_before_close", 0, "map_count_before_close"),
            ("steady_global_queries", 1, "steady_global_queries"),
            ("window_effects", 1, "window_effects"),
            ("permanent_polls", 1, "permanent_polls"),
        ]
        for key, value, reason in cases:
            row = sample(); row[key] = value
            with self.subTest(reason=reason):
                with self.assertRaisesRegex(runner.SubstantiveFailure, reason):
                    runner.analyze_sample(row, "warm")
        row = sample(); row["observer_alias"] = "poc001-corr-sha256-" + "b" * 64
        with self.assertRaisesRegex(runner.SubstantiveFailure, "alias_mismatch"):
            runner.analyze_sample(row, "warm")
        row = sample(); row["direct_candidates"] = []
        with self.assertRaisesRegex(runner.SubstantiveFailure, "direct_candidate_count"):
            runner.analyze_sample(row, "warm")
        row = sample(); row["cleanup"]["fixture_socket_absent"] = False
        with self.assertRaisesRegex(runner.SubstantiveFailure, "cleanup_fixture_socket_absent"):
            runner.analyze_sample(row, "warm")

    def test_cold_bound_and_warm_aggregate_budgets_are_enforced(self):
        with self.assertRaisesRegex(runner.SubstantiveFailure, "cold_correlation_ms"):
            runner.analyze_sample(sample("cold-001", correlation_ms=3000.001), "cold")
        warm = [sample("warm-%02d" % number, correlation_ms=100.0, callback_ms=(50.0,)) for number in range(1, 31)]
        aggregate = runner.analyze_class(warm, "warm")
        self.assertEqual(aggregate["outcome"], "pass")
        warm[28] = sample("warm-29", correlation_ms=100.001)
        warm[29] = sample("warm-30", correlation_ms=100.001)
        aggregate = runner.analyze_class(warm, "warm")
        self.assertEqual(aggregate["outcome"], "substantive_failure")
        self.assertEqual(aggregate["stopped_after"], "warm-30")
        cold = [sample("cold-%02d" % number, correlation_ms=3000.0) for number in range(1, 6)]
        self.assertEqual(runner.analyze_class(cold, "cold")["outcome"], "pass")

    def test_stops_at_first_substantive_failure_and_never_relabels_analyzer_error(self):
        rows = [sample("warm-01"), sample("warm-02")]
        rows[0]["direct_identifier_reads"] = 0
        aggregate = runner.analyze_class(rows, "warm")
        self.assertEqual(aggregate["outcome"], "substantive_failure")
        self.assertEqual(aggregate["stopped_after"], "warm-01")
        self.assertEqual(aggregate["samples_examined"], 1)
        malformed = sample(); malformed.pop("cleanup")
        with self.assertRaises(runner.AnalyzerError):
            runner.analyze_sample(malformed, "warm")

    def test_sensitive_input_is_analyzer_error_not_platform_evidence(self):
        row = sample(); row["title"] = "private title"
        with self.assertRaisesRegex(runner.AnalyzerError, "sensitive_key"):
            runner.analyze_sample(row, "warm")

    def test_cli_writes_only_redacted_aggregate_and_marks_bad_input_indeterminate(self):
        with tempfile.TemporaryDirectory() as temporary:
            os.chmod(temporary, 0o700)
            input_path = pathlib.Path(temporary) / "warm.json"
            output_path = pathlib.Path(temporary) / "aggregate.json"
            input_path.write_text(json.dumps([sample("warm-%02d" % number) for number in range(1, 31)]), encoding="utf-8")
            os.chmod(input_path, 0o600)
            self.assertEqual(runner.main(["warm", str(input_path), str(output_path)]), 0)
            aggregate = json.loads(output_path.read_text(encoding="utf-8"))
            self.assertEqual(aggregate["outcome"], "pass")
            self.assertNotIn("alias", json.dumps(aggregate))
            input_path.write_text("{}", encoding="utf-8")
            os.chmod(input_path, 0o600)
            self.assertEqual(runner.main(["warm", str(input_path), str(output_path)]), 2)
            self.assertEqual(json.loads(output_path.read_text(encoding="utf-8"))["outcome"], "analyzer_error")

    def test_procedure_keeps_the_frozen_volume_and_analyzer_boundary(self):
        procedure = (ROOT / "DIRECT-AX-VOLUME.md").read_text(encoding="utf-8")
        for required in ("exactly **30 warm**", "exactly **5 cold**", "**`direct_ax`**",
                         "p95 is at most 100 ms", "p95 at most 50 ms", "at most 3,000 ms",
                         "`/tmp/p1d.XXXXXX`", "Exit 2 is never platform evidence"):
            self.assertIn(required, procedure)
        self.assertNotIn("raw token", procedure.lower())


if __name__ == "__main__":
    unittest.main()
