#!/usr/bin/env python3
"""POC-001 retained direct-AX volume analyzer.

This program performs no Hammerspoon, fixture, process, or socket action.  It
checks a private, already-collected redacted per-sample record and writes only a
redacted aggregate.  The human-gated live procedure is DIRECT-AX-VOLUME.md.
"""
import argparse
import json
import math
import os
import re
import stat
import sys
from pathlib import Path

WARM_SAMPLES = 30
COLD_SAMPLES = 5
SOURCE = "direct_ax"
WARM_CORRELATION_P95_MS = 100.0
CALLBACK_P95_MS = 50.0
CALLBACK_MAX_MS = 100.0
COLD_CORRELATION_MS = 3000.0
DESTRUCTION_CANDIDATE_MS = 1000.0
ALIAS_RE = re.compile(r"^poc001-corr-sha256-[0-9a-f]{64}$")
SENSITIVE_KEYS = frozenset({
    "fixture_token", "correlation_token", "raw_ax", "raw_id", "pid", "title",
    "path", "url", "bundle_id", "native_id", "window_id", "response",
})


class AnalyzerError(ValueError):
    """Input/schema/analyzer boundary failure; never platform evidence."""


class SubstantiveFailure(ValueError):
    """A complete, schema-valid record missed a frozen POC gate."""


def socket_path_template(run_tag):
    """Return the mandated short private socket path without creating it."""
    if not re.fullmatch(r"[A-Za-z0-9]{6}", run_tag):
        raise AnalyzerError("invalid_run_tag")
    return "/tmp/p1d.%s/poc001-fixture.sock" % run_tag


def nearest_rank_p95(values):
    if not values:
        raise AnalyzerError("empty_metric")
    return sorted(values)[math.ceil(len(values) * 0.95) - 1]


def _number(row, key, *, nonnegative=True):
    value = row.get(key)
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value):
        raise AnalyzerError("invalid_%s" % key)
    if nonnegative and value < 0:
        raise AnalyzerError("invalid_%s" % key)
    return float(value)


def _integer(row, key):
    value = _number(row, key)
    if value != int(value):
        raise AnalyzerError("invalid_%s" % key)
    return int(value)


def _walk_no_sensitive(value):
    if isinstance(value, dict):
        for key, child in value.items():
            if key in SENSITIVE_KEYS:
                raise AnalyzerError("sensitive_key_%s" % key)
            _walk_no_sensitive(child)
    elif isinstance(value, list):
        for child in value:
            _walk_no_sensitive(child)


def _alias(value, key):
    if not isinstance(value, str) or not ALIAS_RE.fullmatch(value):
        raise AnalyzerError("invalid_%s" % key)
    return value


def _require_equal(row, key, expected):
    value = row.get(key)
    # Python considers False == 0 and True == 1; reject that schema ambiguity.
    if value != expected or (isinstance(expected, int) and not isinstance(expected, bool)
                             and (isinstance(value, bool) or not isinstance(value, int))):
        raise SubstantiveFailure(key)


def _candidate_gate(row, key, alias):
    candidates = row.get(key)
    if not isinstance(candidates, list):
        raise AnalyzerError("invalid_%s" % key)
    name = key.removesuffix("s")
    if len(candidates) != 1:
        raise SubstantiveFailure("%s_count" % name)
    candidate = candidates[0]
    if not isinstance(candidate, dict):
        raise AnalyzerError("invalid_%s" % name)
    if _alias(candidate.get("alias"), "%s_alias" % name) != alias:
        raise SubstantiveFailure("%s_alias" % name)
    if _number(candidate, "latency_ms") > DESTRUCTION_CANDIDATE_MS:
        raise SubstantiveFailure("%s_latency_ms" % name)


def _cleanup_gate(row):
    cleanup = row.get("cleanup")
    if not isinstance(cleanup, dict):
        raise AnalyzerError("invalid_cleanup")
    expected = {
        "observer_stopped": True, "callbacks_open": 0, "active_timers": 0,
        "window_effects": 0, "map_count": 0, "fixture_process_absent": True,
        "fixture_socket_absent": True,
    }
    for key, value in expected.items():
        actual = cleanup.get(key)
        if actual != value or (isinstance(value, int) and not isinstance(value, bool)
                               and (isinstance(actual, bool) or not isinstance(actual, int))):
            raise SubstantiveFailure("cleanup_%s" % key)


def analyze_sample(row, sample_class):
    """Validate one private redacted sample and return no aliases/identities."""
    if sample_class not in ("warm", "cold"):
        raise AnalyzerError("invalid_sample_class")
    if not isinstance(row, dict):
        raise AnalyzerError("invalid_sample")
    _walk_no_sensitive(row)
    sample_id = row.get("sample_id")
    if not isinstance(sample_id, str) or not re.fullmatch(r"(?:warm|cold)-[0-9]{2,3}", sample_id):
        raise AnalyzerError("invalid_sample_id")
    if not sample_id.startswith(sample_class + "-"):
        raise AnalyzerError("sample_class_mismatch")
    _require_equal(row, "source", SOURCE)
    fixture_alias = _alias(row.get("fixture_alias"), "fixture_alias")
    observer_alias = _alias(row.get("observer_alias"), "observer_alias")
    if fixture_alias != observer_alias:
        raise SubstantiveFailure("alias_mismatch")
    for key, expected in {
        "map_count_before_close": 1, "direct_constructions": 1,
        "direct_identifier_reads": 1, "filter_constructions": 0,
        "filter_identifier_reads": 0, "steady_global_queries": 0,
        "window_effects": 0, "permanent_polls": 0,
    }.items():
        _require_equal(row, key, expected)
    _candidate_gate(row, "direct_candidates", fixture_alias)
    _candidate_gate(row, "filter_candidates", fixture_alias)
    correlation_ms = _number(row, "direct_correlation_ms")
    if sample_class == "cold" and correlation_ms > COLD_CORRELATION_MS:
        raise SubstantiveFailure("cold_correlation_ms")
    durations = row.get("callback_durations_ms")
    if not isinstance(durations, list) or not durations:
        raise AnalyzerError("invalid_callback_durations_ms")
    durations = [_number({"duration": value}, "duration") for value in durations]
    if max(durations) > CALLBACK_MAX_MS:
        raise SubstantiveFailure("callback_max_ms")
    _cleanup_gate(row)
    return {"sample_id": sample_id, "direct_correlation_ms": correlation_ms,
            "callback_durations_ms": durations}


def analyze_class(rows, sample_class):
    """Analyze in order and stop at the first substantive failure exactly once."""
    expected_count = WARM_SAMPLES if sample_class == "warm" else COLD_SAMPLES
    if not isinstance(rows, list):
        raise AnalyzerError("invalid_samples")
    accepted = []
    for row in rows:
        try:
            accepted.append(analyze_sample(row, sample_class))
        except SubstantiveFailure as exc:
            return {"analysis_status": "complete", "class": sample_class,
                    "outcome": "substantive_failure", "reason": str(exc),
                    "stopped_after": row.get("sample_id", "unknown") if isinstance(row, dict) else "unknown",
                    "samples_examined": len(accepted) + 1, "samples_completed": len(accepted)}
    if len(accepted) != expected_count:
        raise AnalyzerError("wrong_%s_sample_count" % sample_class)
    correlations = [row["direct_correlation_ms"] for row in accepted]
    callbacks = [duration for row in accepted for duration in row["callback_durations_ms"]]
    aggregate = {"analysis_status": "complete", "class": sample_class, "outcome": "pass",
                 "samples_completed": len(accepted), "correlation_median_ms": _median(correlations),
                 "correlation_p95_ms": nearest_rank_p95(correlations),
                 "callback_p95_ms": nearest_rank_p95(callbacks), "callback_max_ms": max(callbacks)}
    if sample_class == "warm" and aggregate["correlation_p95_ms"] > WARM_CORRELATION_P95_MS:
        aggregate.update(outcome="substantive_failure", reason="warm_correlation_p95_ms", stopped_after=accepted[-1]["sample_id"])
    elif aggregate["callback_p95_ms"] > CALLBACK_P95_MS:
        aggregate.update(outcome="substantive_failure", reason="callback_p95_ms", stopped_after=accepted[-1]["sample_id"])
    return aggregate


def _median(values):
    ordered = sorted(values)
    middle = len(ordered) // 2
    return ordered[middle] if len(ordered) % 2 else (ordered[middle - 1] + ordered[middle]) / 2


def _private_file(path):
    metadata = os.stat(path)
    if metadata.st_uid != os.getuid() or stat.S_IMODE(metadata.st_mode) != 0o600:
        raise AnalyzerError("unsafe_input_mode")


def _private_directory(path):
    metadata = os.stat(path)
    if metadata.st_uid != os.getuid() or stat.S_IMODE(metadata.st_mode) != 0o700:
        raise AnalyzerError("unsafe_private_directory")


def main(argv=None):
    parser = argparse.ArgumentParser(description="Analyze private, redacted POC-001 direct-AX volume records; no live actions.")
    parser.add_argument("sample_class", choices=("warm", "cold"))
    parser.add_argument("input", type=Path, help="owner-private JSON array of normalized redacted samples")
    parser.add_argument("output", type=Path, help="owner-private redacted aggregate output")
    args = parser.parse_args(argv)
    try:
        _private_directory(args.input.parent)
        _private_directory(args.output.parent)
        _private_file(args.input)
        with args.input.open(encoding="utf-8") as handle:
            result = analyze_class(json.load(handle), args.sample_class)
    except AnalyzerError as exc:
        # This distinct outcome cannot be reported as a platform result.
        result = {"analysis_status": "indeterminate", "outcome": "analyzer_error", "reason": str(exc)}
        code = 2
    except json.JSONDecodeError:
        result = {"analysis_status": "indeterminate", "outcome": "analyzer_error", "reason": "invalid_json"}
        code = 2
    else:
        code = 0 if result["outcome"] == "pass" else 1
    try:
        flags = os.O_WRONLY | os.O_CREAT | os.O_TRUNC
        descriptor = os.open(args.output, flags, 0o600)
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            json.dump(result, handle, sort_keys=True)
            handle.write("\n")
        os.chmod(args.output, 0o600)
        _private_file(args.output)
    except OSError:
        # Do not manufacture a platform result when the analyzer cannot retain one.
        sys.stderr.write("analyzer_error: output_write_error\n")
        return 2
    return code


if __name__ == "__main__":
    sys.exit(main())
