local Registry = require("lib.macos.handle_registry")

return {
  ["STATE-003 PERF-002: ephemeral global handles resolve directly by managed ID and confirmed Space"] = function()
    local registry, first, second = Registry.new(), {}, {}
    registry:refresh("cold", first, 7)
    assert(registry:target("cold") == nil and registry:cached("cold").handle == first)
    registry:remember("window", "one", first, 7)
    assert(registry:resolve({ windowId = "window", spaceId = "one" }) == first)
    assert(registry:resolve({ windowId = "window", spaceId = "two" }) == nil)
    registry:remember("window", "two", second, 7)
    assert(registry:resolve({ windowId = "window", spaceId = "two" }) == second)
    local records = registry:recordsForSpace("two")
    assert(#records == 1 and records[1].handle == second and records[1].pid == 7)
    registry:forget("window", first)
    assert(registry:resolve({ windowId = "window", spaceId = "two" }) == second)
    registry:refresh("window", first, 7)
    assert(registry:resolve({ windowId = "window", spaceId = "two" }) == first)
    local target = registry:target("window")
    assert(target.windowId == "window" and target.spaceId == "two")
    local record = registry:record(target)
    assert(record.handle == first and record.pid == 7 and record.spaceId == "two")
    target.spaceId = "changed"
    assert(registry:target("window").spaceId == "two" and registry:record(target) == nil)
    registry:forget("window", second)
    assert(registry:resolve({ windowId = "window", spaceId = "two" }) == first)
    registry:forgetPid(7)
    assert(registry:resolve({ windowId = "window", spaceId = "two" }) == nil)
  end,
}
