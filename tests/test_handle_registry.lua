local Registry = require("lib.macos.handle_registry")

return {
  ["STATE-003 PERF-002: ephemeral global handles resolve directly by managed ID and confirmed Space"] = function()
    local registry, first, second = Registry.new(), {}, {}
    registry:remember("window", "one", first, 7)
    assert(registry:resolve({ windowId = "window", spaceId = "one" }) == first)
    assert(registry:resolve({ windowId = "window", spaceId = "two" }) == nil)
    registry:remember("window", "two", second, 7)
    assert(registry:resolve({ windowId = "window", spaceId = "two" }) == second)
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
