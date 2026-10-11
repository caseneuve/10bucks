local Registry = require("lib.macos.handle_registry")

return {
  ["STATE-003 PERF-002: ephemeral global handles resolve directly by managed ID and confirmed Space"] = function()
    local registry, first, second = Registry.new(), {}, {}
    registry:remember("window", "one", first, 7, 1, 9)
    assert(registry:resolve({ windowId = "window", spaceId = "one", lease = 1 }) == first)
    assert(registry:resolve({ windowId = "window", spaceId = "one", lease = 2 }) == nil)
    assert(not registry:remember("window", "two", second, 7, 2, 9), "conflicting current ID defers")
    registry:remember("window", "two", second, 7, 1, 9)
    assert(registry:resolve({ windowId = "window", spaceId = "two", lease = 1 }) == second)
    registry:forget("window", first)
    assert(registry:resolve({ windowId = "window", spaceId = "two" }) == second)
    registry:remember("window", "two", first, 7, 1, 9)
    assert(registry:resolve({ windowId = "window", spaceId = "two" }) == first)
    local target = registry:target("window")
    assert(target.windowId == "window" and target.spaceId == "two")
    target.spaceId = "changed"
    assert(registry:target("window").spaceId == "two")
    registry:forget("window", second)
    assert(registry:resolve({ windowId = "window", spaceId = "two" }) == first)
    registry:forgetPid(7, 8)
    assert(registry:resolve({ windowId = "window", spaceId = "two" }) == first, "other app lease cannot remove current route")
    registry:forgetPid(7, 9)
    assert(registry:resolve({ windowId = "window", spaceId = "two" }) == nil)
  end,
}
