local source = debug.getinfo(1, "S").source:sub(2)
local root = source:match("(.*/)pocs/") or "./"
package.path = root .. "pocs/001-window-events-liveness/?.lua;" .. package.path

local Trace = require("trace")

local function equal(actual, expected)
  assert(actual == expected, string.format("expected %s, got %s", tostring(expected), tostring(actual)))
end

local function contains(value, fragment)
  assert(value:find(fragment, 1, true), string.format("expected %q to contain %q", value, fragment))
end

return {
  ["POC-001 trace assigns stable redacted aliases and never exports raw identifiers"] = function()
    local now = 100
    local trace = Trace.new(function()
      now = now + 7
      return now
    end, "run-001")

    equal(trace:app_alias("pid:123"), "app-001")
    equal(trace:app_alias("pid:123"), "app-001")
    equal(trace:window_alias("pid:123", "window:99"), "win-001")
    equal(trace:window_alias("pid:123", "window:99"), "win-001")
    trace:emit("observed", { source = "direct_ax", app = "app-001", window = "win-001", raw_event = "AXWindowCreated" })

    local exported = trace:export_table()
    equal(exported.events[1].run_id, "run-001")
    equal(exported.events[1].sequence, 1)
    equal(exported.events[1].monotonic_ms, 7)
    equal(exported.events[1].app, "app-001")
    assert(exported.aliases == nil)
    local rendered = Trace.encode_json(exported)
    assert(not rendered:find("pid:123", 1, true))
    assert(not rendered:find("window:99", 1, true))
  end,

  ["POC-001 observer trace exports independent absolute nanoseconds without raw identifiers"] = function()
    local relative, absolute = 10, 9000000000
    local trace = Trace.new(function()
      relative = relative + 7
      return relative
    end, "run-absolute", function()
      absolute = absolute + 1234567
      return absolute
    end)
    trace:emit("destruction_candidate", { raw_id = "99", raw_ax = "corr-AAAAAAAAAAAAAAAA" })
    local event = trace:export_table().events[1]
    equal(event.monotonic_ms, 7)
    equal(event.absolute_ns, 9001234567)
    assert(event.absolute_ns ~= event.monotonic_ms * 1000000)
    equal(event.raw_id, nil); equal(event.raw_ax, nil)
  end,

  ["POC-001 trace separates bootstrap global queries from steady callback queries"] = function()
    local trace = Trace.new(function() return 10 end, "run-002")
    trace:query("all_application_scan", "bootstrap.attach_existing_apps", "bootstrap")
    trace:callback_enter("application_watcher", "launched")
    trace:query("targeted_application_attach", "direct_ax.attach_app", "steady")
    trace:callback_exit("application_watcher", "launched")

    local status = trace:status()
    equal(status.query_counters.bootstrap.all_application_scan, 1)
    equal(status.query_counters.steady.targeted_application_attach, 1)
    equal(status.steady_global_queries, 0)
    equal(status.callbacks.open, 0)
  end,

  ["POC-001 trace rejects unsafe marker text and redacts unsafe fields"] = function()
    local trace = Trace.new(function() return 42 end, "run-003")
    local ok = pcall(function()
      trace:mark("action_begin", { action = "close confidential-plan.pdf" })
    end)
    assert(not ok)

    trace:emit("fact", {
      source = "direct_ax",
      title = "confidential-plan.pdf",
      url = "https://private.example",
      fact = "window_created",
    })
    local event = trace:export_table().events[1]
    equal(event.title, nil)
    equal(event.url, nil)
    equal(event.fact, "window_created")
    contains(Trace.encode_json(trace:export_table()), "window_created")
  end,

  ["POC-001 trace exports only frozen full correlation aliases"] = function()
    local trace = Trace.new(function() return 1 end, "run-005")
    local alias = "poc001-corr-sha256-83687efb86d2554f0547e44f7790efc5cc14b07af1ad8447ebb2d270cc6d7eac"
    trace:emit("correlation_observed", { correlation_alias = alias, raw_ax = "corr-AAAAAAAAAAAAAAAA" })
    local event = trace:export_table().events[1]
    equal(event.correlation_alias, alias); equal(event.raw_ax, nil)
    trace:emit("correlation_observed", { correlation_alias = "poc001-corr-sha256-not-a-digest" })
    equal(trace:export_table().events[2].correlation_alias, nil)
  end,

  ["POC-001 trace lifecycle remains idempotent in pure bookkeeping"] = function()
    local trace = Trace.new(function() return 1 end, "run-004")
    equal(trace:lifecycle("start"), true)
    equal(trace:lifecycle("start"), false)
    equal(trace:lifecycle("stop"), true)
    equal(trace:lifecycle("stop"), false)
    local status = trace:status()
    equal(status.lifecycle, "stopped")
    equal(status.lifecycle_transitions, 2)
  end,
}
