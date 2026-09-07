#!/usr/bin/env python3
"""Pure POC-001 direct-AX volume analyzer; this is not a live runner.

It validates owner-private, already-normalized records. It never launches a
fixture, loads Hammerspoon, changes legacy runtime, or touches a socket.
"""
import argparse, json, math, os, re, stat, sys, tempfile
from pathlib import Path

WARM_SAMPLES, COLD_SAMPLES, SOURCE = 30, 5, "direct_ax"
WARM_P95_MS, CALLBACK_P95_MS, CALLBACK_MAX_MS = 100.0, 50.0, 100.0
COLD_MAX_MS, CANDIDATE_MAX_MS = 3000.0, 1000.0
ALIAS_RE = re.compile(r"^poc001-corr-sha256-[0-9a-f]{64}$")
SENSITIVE = frozenset({"fixture_token", "correlation_token", "raw_ax", "raw_id", "pid", "title", "path", "url", "bundle_id", "native_id", "window_id", "response"})

class AnalyzerError(ValueError): pass
class SubstantiveFailure(ValueError): pass

def socket_path_template(tag):
    if not re.fullmatch(r"[A-Za-z0-9]{6}", tag): raise AnalyzerError("invalid_run_tag")
    return f"/tmp/p1d.{tag}/poc001-fixture.sock"

def _walk(value):
    if isinstance(value, dict):
        for key, child in value.items():
            if key in SENSITIVE: raise AnalyzerError(f"sensitive_key_{key}")
            _walk(child)
    elif isinstance(value, list):
        for child in value: _walk(child)

def _required(row, key, kind=None):
    if key not in row: raise AnalyzerError(f"missing_{key}")
    value = row[key]
    if kind and (not isinstance(value, kind) or (kind in ((int, float), int) and isinstance(value, bool))):
        raise AnalyzerError(f"invalid_{key}")
    return value

def _integer(row, key):
    value = _required(row, key, int)
    if value < 0: raise AnalyzerError(f"invalid_{key}")
    return value

def _number(row, key):
    value = _required(row, key, (int, float))
    if not math.isfinite(value) or value < 0: raise AnalyzerError(f"invalid_{key}")
    return float(value)

def _alias(row, key):
    value = _required(row, key, str)
    if not ALIAS_RE.fullmatch(value): raise AnalyzerError(f"invalid_{key}")
    return value

def _exact(row, key, expected):
    value = _required(row, key, type(expected))
    if value != expected: raise SubstantiveFailure(key)

def _candidate(row, key, alias):
    candidates = _required(row, key, list)
    singular = key.removesuffix("s")
    if len(candidates) != 1: raise SubstantiveFailure(f"{singular}_count")
    candidate = candidates[0]
    if not isinstance(candidate, dict): raise AnalyzerError(f"invalid_{singular}")
    if _alias(candidate, "alias") != alias: raise SubstantiveFailure(f"{singular}_alias")
    if _number(candidate, "latency_ms") > CANDIDATE_MAX_MS: raise SubstantiveFailure(f"{singular}_latency_ms")

def _generation_reset(row):
    reset = _required(row, "generation_reset", dict)
    _exact(reset, "finish_called", True)
    _exact(reset, "map_count", 0)
    _exact(reset, "armed", False)
    # `nil` after Correlation:clear is an exact source reset, not an omitted key.
    if "candidate_source" not in reset: raise AnalyzerError("missing_candidate_source")
    if reset["candidate_source"] is not None: raise SubstantiveFailure("candidate_source_not_reset")

def _session_gate(row, sample_class):
    session = _required(row, "session_after_generation", dict)
    _exact(session, "callbacks_open", 0); _exact(session, "active_timers", 0); _exact(session, "window_effects", 0)
    if sample_class == "warm":
        _exact(session, "observer_running", True); _exact(session, "fixture_running", True)
    else:
        _exact(session, "observer_running", False); _exact(session, "fixture_running", False)

def analyze_sample(row, sample_class):
    if sample_class not in ("warm", "cold"): raise AnalyzerError("invalid_sample_class")
    if not isinstance(row, dict): raise AnalyzerError("invalid_sample")
    _walk(row)
    sample_id = _required(row, "sample_id", str)
    if not re.fullmatch(rf"{sample_class}-[0-9]{{2}}", sample_id): raise AnalyzerError("invalid_sample_id")
    generation = _integer(row, "generation")
    if generation < 1: raise AnalyzerError("invalid_generation")
    source = _required(row, "source", str)
    if source != SOURCE: raise SubstantiveFailure("source")
    fixture_alias, observer_alias = _alias(row, "fixture_alias"), _alias(row, "observer_alias")
    if fixture_alias != observer_alias: raise SubstantiveFailure("alias_mismatch")
    for key, expected in {"create_count": 1, "close_count": 1, "map_count_before_close": 1,
                          "direct_constructions": 1, "direct_identifier_reads": 1,
                          "filter_constructions": 0, "filter_identifier_reads": 0,
                          "steady_global_queries": 0, "window_effects": 0, "permanent_polls": 0}.items(): _exact(row, key, expected)
    _candidate(row, "direct_candidates", fixture_alias); _candidate(row, "filter_candidates", fixture_alias)
    correlation = _number(row, "direct_correlation_ms")
    if sample_class == "cold" and correlation > COLD_MAX_MS: raise SubstantiveFailure("cold_correlation_ms")
    durations = _required(row, "callback_durations_ms", list)
    if not durations: raise AnalyzerError("empty_callback_durations_ms")
    if any(isinstance(v, bool) or not isinstance(v, (int, float)) or not math.isfinite(v) or v < 0 for v in durations): raise AnalyzerError("invalid_callback_durations_ms")
    if max(durations) > CALLBACK_MAX_MS: raise SubstantiveFailure("callback_max_ms")
    _generation_reset(row); _session_gate(row, sample_class)
    return {"sample_id": sample_id, "generation": generation, "direct_correlation_ms": correlation, "callback_durations_ms": list(map(float, durations))}

def _class_cleanup(cleanup):
    if not isinstance(cleanup, dict): raise AnalyzerError("invalid_class_final_cleanup")
    for key, expected in {"observer_stopped": True, "callbacks_open": 0, "active_timers": 0,
                          "window_effects": 0, "map_count": 0, "fixture_process_absent": True,
                          "fixture_socket_absent": True, "legacy_restored": True}.items(): _exact(cleanup, key, expected)
    expected_bindings = _integer(cleanup, "legacy_binding_count_expected")
    actual_bindings = _integer(cleanup, "legacy_binding_count_actual")
    if expected_bindings <= 0: raise SubstantiveFailure("legacy_expected_bindings")
    if actual_bindings != expected_bindings: raise SubstantiveFailure("legacy_binding_count")
    for name in ("lifecycle_watcher", "reconcile", "bar"):
        expected = _required(cleanup, "legacy_" + name + "_expected", bool)
        actual = _required(cleanup, "legacy_" + name + "_actual", bool)
        if actual != expected: raise SubstantiveFailure("legacy_" + name)

def _p95(values):
    if not values: raise AnalyzerError("empty_metric")
    return sorted(values)[math.ceil(len(values) * .95) - 1]

def _median(values):
    if not values: raise AnalyzerError("empty_metric")
    ordered, middle = sorted(values), len(values) // 2
    return ordered[middle] if len(ordered) % 2 else (ordered[middle - 1] + ordered[middle]) / 2

def analyze_class(rows, sample_class, class_final_cleanup):
    expected = WARM_SAMPLES if sample_class == "warm" else COLD_SAMPLES
    if not isinstance(rows, list): raise AnalyzerError("invalid_samples")
    accepted, generations = [], set()
    for index, row in enumerate(rows, 1):
        try:
            result = analyze_sample(row, sample_class)
            if result["sample_id"] != f"{sample_class}-{index:02d}": raise AnalyzerError("unexpected_sample_id_order")
            if sample_class == "warm":
                if result["generation"] in generations: raise SubstantiveFailure("duplicate_generation")
                generations.add(result["generation"])
            elif result["generation"] != 1:
                raise AnalyzerError("cold_generation_not_one")
            accepted.append(result)
        except SubstantiveFailure as exc:
            return {"analysis_status":"complete", "class":sample_class, "outcome":"substantive_failure", "reason":str(exc), "stopped_after": row.get("sample_id", "unknown") if isinstance(row, dict) else "unknown", "samples_examined":len(accepted)+1, "samples_completed":len(accepted)}
    if len(accepted) != expected: raise AnalyzerError(f"wrong_{sample_class}_sample_count")
    if sample_class == "warm" and generations != set(range(1, expected + 1)): raise AnalyzerError("unexpected_generation_set")
    try:
        _class_cleanup(class_final_cleanup)
    except SubstantiveFailure as exc:
        return {"analysis_status":"complete", "class":sample_class, "outcome":"substantive_failure",
                "reason":str(exc), "stopped_after":"class_final_cleanup", "samples_examined":len(accepted),
                "samples_completed":len(accepted)}
    correlations = [v["direct_correlation_ms"] for v in accepted]
    callbacks = [d for v in accepted for d in v["callback_durations_ms"]]
    result = {"analysis_status":"complete", "class":sample_class, "outcome":"pass", "samples_completed":expected,
              "correlation_median_ms": _median(correlations), "correlation_p95_ms":_p95(correlations),
              "callback_p95_ms":_p95(callbacks), "callback_max_ms":max(callbacks)}
    if sample_class == "warm" and result["correlation_p95_ms"] > WARM_P95_MS: result.update(outcome="substantive_failure", reason="warm_correlation_p95_ms", stopped_after=accepted[-1]["sample_id"])
    elif result["callback_p95_ms"] > CALLBACK_P95_MS: result.update(outcome="substantive_failure", reason="callback_p95_ms", stopped_after=accepted[-1]["sample_id"])
    return result

def _private_dir(path):
    meta = os.lstat(path)
    if stat.S_ISLNK(meta.st_mode) or not stat.S_ISDIR(meta.st_mode) or meta.st_uid != os.getuid() or stat.S_IMODE(meta.st_mode) != 0o700: raise AnalyzerError("unsafe_private_directory")

def _read_private(path):
    meta = os.lstat(path)
    if stat.S_ISLNK(meta.st_mode) or not stat.S_ISREG(meta.st_mode) or meta.st_uid != os.getuid() or stat.S_IMODE(meta.st_mode) != 0o600: raise AnalyzerError("unsafe_input_mode")
    with path.open(encoding="utf-8") as handle: return json.load(handle)

def _atomic_output(path, result):
    _private_dir(path.parent)
    try:
        old = os.lstat(path)
        if stat.S_ISLNK(old.st_mode): raise AnalyzerError("unsafe_output_symlink")
    except FileNotFoundError: pass
    descriptor, temporary = tempfile.mkstemp(prefix=".p001-direct-ax-", dir=path.parent, text=True)
    try:
        os.fchmod(descriptor, 0o600)
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            json.dump(result, handle, sort_keys=True); handle.write("\n"); handle.flush(); os.fsync(handle.fileno())
        meta = os.lstat(temporary)
        if not stat.S_ISREG(meta.st_mode) or meta.st_uid != os.getuid() or stat.S_IMODE(meta.st_mode) != 0o600: raise AnalyzerError("unsafe_output_mode")
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary): os.unlink(temporary)

def main(argv=None):
    parser = argparse.ArgumentParser(description="Pure POC-001 analyzer; not a live runner.")
    parser.add_argument("mode", choices=("sample", "class")); parser.add_argument("sample_class", choices=("warm", "cold")); parser.add_argument("input", type=Path); parser.add_argument("output", type=Path)
    args = parser.parse_args(argv)
    try:
        _private_dir(args.input.parent); data = _read_private(args.input)
        result = analyze_sample(data, args.sample_class) if args.mode == "sample" else analyze_class(_required(data, "samples", list), args.sample_class, _required(data, "class_final_cleanup", dict))
        code = 0 if result.get("outcome", "pass") == "pass" else 1
    except (AnalyzerError, json.JSONDecodeError) as exc:
        result, code = {"analysis_status":"indeterminate", "outcome":"analyzer_error", "reason": "invalid_json" if isinstance(exc, json.JSONDecodeError) else str(exc)}, 2
    try: _atomic_output(args.output, result)
    except (AnalyzerError, OSError): sys.stderr.write("analyzer_error: output_write_error\n"); return 2
    return code
if __name__ == "__main__": sys.exit(main())
