local Instrumentation = require("lib.macos.canary_instrumentation")

return {
  ["Canary A instrumentation exports only aggregate primitive counters/timestamps"] = function()
    local ticks = 0
    local instance = Instrumentation.new(function() ticks = ticks + 1; return ticks end)
    instance:recordEvent("WindowReady")
    instance:recordEvent("WindowReady")
    instance:recordEvent("WindowDestroyed")
    instance:setActiveTimers(0)
    local status, exported = instance:status(), instance:export()
    assert(status.enabled and status.counts["event.WindowReady"] == 2 and status.counts["event.WindowDestroyed"] == 1 and status.activeTimers == 0 and status.timestampCount == 3)
    assert(exported.timestamps[1].kind == "event.WindowReady" and exported.timestamps[1].at == 1)
    assert(not pcall(instance.setActiveTimers, instance, -1))
    assert(not pcall(instance.recordEvent, instance, "Window Ready"))
  end,
}
