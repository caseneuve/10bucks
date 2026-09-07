#!/usr/bin/env python3
"""Private, pure POC-001 direct-AX evidence normalizer; never a live runner."""
import argparse, json, math, os, re, stat, sys, tempfile
from pathlib import Path

ALIAS_RE = re.compile(r"^poc001-corr-sha256-[0-9a-f]{64}$")
SENSITIVE = frozenset({"fixture_token", "correlation_token", "raw_ax", "raw_id", "pid", "title", "path", "url", "bundle_id", "native_id", "window_id"})

class NormalizerError(ValueError): pass

def _fail(reason): raise NormalizerError(reason)
def _reject_private_leak(value, permit_fixture_token=False):
    if isinstance(value, dict):
        for key, child in value.items():
            # Only fixture control/trace retain this close capability. It is
            # never an observer input, association input, or output field.
            if key in SENSITIVE and not (permit_fixture_token and key == "fixture_token"): _fail("sensitive_input")
            _reject_private_leak(child, permit_fixture_token)
    elif isinstance(value, list):
        for child in value: _reject_private_leak(child, permit_fixture_token)
def _dict(value, name):
    if not isinstance(value, dict): _fail("invalid_" + name)
    return value
def _list(value, name):
    if not isinstance(value, list): _fail("invalid_" + name)
    return value
def _string(row, key):
    value = _dict(row, "object").get(key)
    if not isinstance(value, str): _fail("invalid_" + key)
    return value
def _integer(row, key):
    value = _dict(row, "object").get(key)
    if isinstance(value, bool) or not isinstance(value, int) or value < 0: _fail("invalid_" + key)
    return value
def _bool(row, key):
    value = _dict(row, "object").get(key)
    if not isinstance(value, bool): _fail("invalid_" + key)
    return value
def _number(row, key):
    value = _dict(row, "object").get(key)
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value) or value < 0: _fail("invalid_" + key)
    return float(value)
def _alias(row, key):
    value = _string(row, key)
    if not ALIAS_RE.fullmatch(value): _fail("invalid_" + key)
    return value
def _one(values, reason):
    if len(values) != 1: _fail(reason)
    return values[0]
def _events(export):
    export = _dict(export, "observer_export")
    if export.get("schema") != "poc-001-trace-v1": _fail("invalid_observer_schema")
    events = _list(export.get("events"), "observer_events")
    for event in events: _dict(event, "observer_event")
    return events
def _fixture_records(trace):
    if not isinstance(trace, list): _fail("invalid_fixture_trace")
    records = []
    previous = 0
    for record in trace:
        _dict(record, "fixture_record")
        if record.get("schema") != "poc001-fixture-v1": _fail("invalid_fixture_schema")
        sequence = _integer(record, "sequence")
        if sequence <= previous: _fail("invalid_fixture_sequence")
        previous = sequence
        records.append(record)
    return records
def _fixture_ns(record):
    if _string(record, "clock_kind") != "mach_absolute": _fail("fixture_clock_not_absolute")
    ticks, numer, denom = _integer(record, "ticks"), _integer(record, "timebase_numer"), _integer(record, "timebase_denom")
    if numer == 0 or denom == 0: _fail("invalid_timebase")
    return (ticks // denom) * numer + ((ticks % denom) * numer) // denom
def _private_dir(path):
    meta = os.lstat(path)
    if stat.S_ISLNK(meta.st_mode) or not stat.S_ISDIR(meta.st_mode) or meta.st_uid != os.getuid() or stat.S_IMODE(meta.st_mode) != 0o700: _fail("unsafe_private_directory")
def _read_private_json(path):
    meta = os.lstat(path)
    if stat.S_ISLNK(meta.st_mode) or not stat.S_ISREG(meta.st_mode) or meta.st_uid != os.getuid() or stat.S_IMODE(meta.st_mode) != 0o600: _fail("unsafe_input_mode")
    with open(path, "r", encoding="utf-8", opener=lambda p, f: os.open(p, f | getattr(os, "O_NOFOLLOW", 0))) as handle: return json.load(handle)
def _read_private_ndjson(path):
    meta = os.lstat(path)
    if stat.S_ISLNK(meta.st_mode) or not stat.S_ISREG(meta.st_mode) or meta.st_uid != os.getuid() or stat.S_IMODE(meta.st_mode) != 0o600: _fail("unsafe_input_mode")
    with open(path, "r", encoding="utf-8", opener=lambda p, f: os.open(p, f | getattr(os, "O_NOFOLLOW", 0))) as handle:
        lines = handle.read().splitlines()
    if not lines: _fail("empty_fixture_trace")
    return [json.loads(line) for line in lines]
def _atomic_output(path, result):
    _private_dir(path.parent)
    try:
        old = os.lstat(path)
        if stat.S_ISLNK(old.st_mode) or not stat.S_ISREG(old.st_mode): _fail("unsafe_output_path")
    except FileNotFoundError: pass
    fd, temporary = tempfile.mkstemp(prefix=".p001-direct-ax-", dir=path.parent, text=True)
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            json.dump(result, handle, sort_keys=True); handle.write("\n"); handle.flush(); os.fsync(handle.fileno())
        meta = os.lstat(temporary)
        if not stat.S_ISREG(meta.st_mode) or meta.st_uid != os.getuid() or stat.S_IMODE(meta.st_mode) != 0o600: _fail("unsafe_output_mode")
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary): os.unlink(temporary)

def normalize(create_response, fixture_trace, observer_export, pre_close_snapshot, observer_snapshot, sample_class):
    """Derive one analyzer row. Inputs are retained private records, never live ports."""
    if sample_class not in ("warm", "cold"): _fail("invalid_sample_class")
    # These are owner-private retained inputs and necessarily contain the fixture
    # close capability. Redaction is enforced on the only public product below.
    _reject_private_leak(create_response, permit_fixture_token=True)
    _reject_private_leak(fixture_trace, permit_fixture_token=True)
    _reject_private_leak(observer_export)
    _reject_private_leak(pre_close_snapshot)
    _reject_private_leak(observer_snapshot)
    response = _dict(create_response, "create_response")
    if response.get("status") != "accepted": _fail("create_not_accepted")
    sample_id, fixture_alias = _string(response, "sample_id"), _alias(response, "correlation_alias")
    _string(response, "fixture_token") # validate retained control schema; never associate on it.
    if not re.fullmatch(rf"{sample_class}-[0-9]{{2}}", sample_id): _fail("invalid_sample_id")
    records = _fixture_records(fixture_trace)
    creates = [r for r in records if r.get("event") == "create_requested"]
    create = _one([r for r in creates if r.get("sample_id") == sample_id and r.get("correlation_alias") == fixture_alias], "ambiguous_fixture_create")
    create_index = creates.index(create)
    create_position = records.index(create)
    next_create_position = records.index(creates[create_index + 1]) if create_index + 1 < len(creates) else len(records)
    # Fixture control permits only one active generation.  Select its completion
    # by this bounded trace interval, never by a token/native/window identifier.
    close = _one([r for r in records[create_position + 1:next_create_position] if r.get("event") == "native_close_completed"], "ambiguous_fixture_close")
    create_ns = _fixture_ns(create)
    # The fixture has one active generation. Its position in this run is the only
    # retained generation evidence; a cold trace therefore must contain one create.
    generation = create_index + 1
    if sample_class == "cold" and generation != 1: _fail("cold_generation_not_one")
    if close.get("origin") != "ipc" or close.get("sample_id") != sample_id: _fail("invalid_close_sample")
    if records.index(close) <= records.index(create): _fail("fixture_close_order")
    close_ns = _fixture_ns(close)
    events = _events(observer_export)
    scoped = [e for e in events if e.get("sample_id") == sample_id]
    armed = _one([e for e in scoped if e.get("marker") == "correlation_armed"], "ambiguous_correlation_arm")
    if armed.get("candidate_source") != "direct_ax": _fail("invalid_candidate_source")
    observed = _one([e for e in scoped if e.get("marker") == "correlation_observed"], "ambiguous_correlation_observed")
    if observed.get("source") != "direct_ax": _fail("invalid_correlation_source")
    observer_alias = _alias(observed, "correlation_alias")
    direct_constructions = sum(e.get("query") == "correlation_direct_ax_window_element_construction" and e.get("scope") == "steady" for e in scoped)
    direct_reads = sum(e.get("query") == "correlation_direct_ax_identifier_read" and e.get("scope") == "steady" for e in scoped)
    filter_constructions = sum(e.get("query") == "correlation_window_element_construction" and e.get("scope") == "steady" for e in scoped)
    filter_reads = sum(e.get("query") == "correlation_ax_identifier_read" and e.get("scope") == "steady" for e in scoped)
    global_queries = sum(e.get("marker") == "query_attempt" and e.get("scope") == "steady" and e.get("query") in {"global_ax_enumeration", "all_window_snapshot", "all_application_scan"} for e in scoped)
    candidates = {}
    for source in ("direct_ax", "filter"):
        values = [e for e in scoped if e.get("marker") == "destruction_candidate" and e.get("source") == source]
        normalized = []
        for event in values:
            alias = _alias(event, "correlation_alias")
            absolute = _integer(event, "absolute_ns")
            if absolute < close_ns: _fail("negative_or_order_invalid_latency")
            normalized.append({"alias": alias, "latency_ms": (absolute - close_ns) / 1_000_000})
        candidates[source] = normalized
    durations = [_number(e, "duration_ms") for e in scoped if e.get("marker") == "callback_exit"]
    if not durations: _fail("empty_callback_durations_ms")
    finished = _one([e for e in scoped if e.get("marker") == "correlation_finished"], "ambiguous_correlation_finish")
    if finished.get("correlation_armed") is not False or finished.get("correlation_map_count") != 0: _fail("invalid_finish_event")
    pre_close = _dict(pre_close_snapshot, "pre_close_snapshot")
    pre_correlation = _dict(pre_close.get("correlation"), "pre_close_correlation")
    pre_sources = _dict(pre_correlation.get("candidate_sources"), "pre_close_candidate_sources")
    if (pre_correlation.get("armed") is not True or pre_correlation.get("map_count") != 1
            or pre_correlation.get("candidate_source") != "direct_ax" or pre_sources.get("direct_ax") is not False
            or pre_sources.get("filter") is not False or pre_sources.get("count") != 0 or pre_sources.get("complete") is not False): _fail("invalid_pre_close_correlation")
    snapshot = _dict(observer_snapshot, "observer_snapshot")
    correlation = _dict(snapshot.get("correlation"), "snapshot_correlation")
    candidate_sources = _dict(correlation.get("candidate_sources"), "snapshot_candidate_sources")
    if (correlation.get("armed") is not False or correlation.get("map_count") != 0 or correlation.get("candidate_source") is not None
            or candidate_sources.get("count") != 0 or candidate_sources.get("direct_ax") is not False
            or candidate_sources.get("filter") is not False or candidate_sources.get("complete") is not False): _fail("generation_not_reset")
    callbacks = _dict(snapshot.get("callbacks"), "snapshot_callbacks")
    status = _dict(observer_export.get("status"), "observer_export_status")
    # Snapshot is taken immediately after finish; export status must be internally
    # consistent about counters, but lifecycle is intentionally the snapshot fact.
    for key in ("active_timers", "window_effects"):
        _integer(snapshot, key)
    map_count_before_close = pre_correlation["map_count"]
    row = {"sample_id": sample_id, "generation": generation, "source": observed["source"], "fixture_alias": fixture_alias, "observer_alias": observer_alias,
      "create_count": sum(r.get("event") == "create_requested" and r.get("sample_id") == sample_id for r in records), "close_count": sum(r.get("event") == "native_close_completed" for r in records[create_position + 1:next_create_position]),
      "map_count_before_close": map_count_before_close, "direct_constructions": direct_constructions, "direct_identifier_reads": direct_reads, "filter_constructions": filter_constructions, "filter_identifier_reads": filter_reads,
      "direct_candidates": candidates["direct_ax"], "filter_candidates": candidates["filter"], "direct_correlation_ms": (_integer(observed, "absolute_ns") - create_ns) / 1_000_000, "callback_durations_ms": durations,
      "steady_global_queries": global_queries, "window_effects": _integer(snapshot, "window_effects"), "permanent_polls": _integer(snapshot, "active_timers"),
      "generation_reset": {"finish_called": True, "map_count": correlation["map_count"], "armed": correlation["armed"], "candidate_source": correlation["candidate_source"]},
      "session_after_generation": {"callbacks_open": _integer(callbacks, "open"), "active_timers": _integer(snapshot, "active_timers"), "window_effects": _integer(snapshot, "window_effects"), "observer_running": snapshot.get("lifecycle") == "running", "fixture_running": _bool(snapshot, "fixture_running")}}
    if row["direct_correlation_ms"] < 0: _fail("negative_or_order_invalid_correlation")
    if status.get("steady_global_queries") not in (0, global_queries): _fail("contradictory_export_global_queries")
    return row

def main(argv=None):
    parser = argparse.ArgumentParser(description="Pure POC-001 evidence normalizer; not a live runner.")
    parser.add_argument("sample_class", choices=("warm", "cold")); parser.add_argument("create_response", type=Path); parser.add_argument("fixture_trace", type=Path); parser.add_argument("observer_export", type=Path); parser.add_argument("pre_close_snapshot", type=Path); parser.add_argument("observer_snapshot", type=Path); parser.add_argument("output", type=Path)
    args = parser.parse_args(argv)
    try:
        for path in (args.create_response, args.fixture_trace, args.observer_export, args.pre_close_snapshot, args.observer_snapshot): _private_dir(path.parent)
        result = normalize(_read_private_json(args.create_response), _read_private_ndjson(args.fixture_trace), _read_private_json(args.observer_export), _read_private_json(args.pre_close_snapshot), _read_private_json(args.observer_snapshot), args.sample_class)
        code = 0
    except (NormalizerError, OSError, json.JSONDecodeError):
        result, code = {"analysis_status": "indeterminate", "outcome": "normalizer_error"}, 2
    try: _atomic_output(args.output, result)
    except (NormalizerError, OSError): sys.stderr.write("normalizer_error: output_write_error\n"); return 2
    return code
if __name__ == "__main__": sys.exit(main())
