local source = debug.getinfo(1, "S").source:sub(2)
local root = source:match("(.*/)pocs/") or "./"
package.path = root .. "pocs/001-window-events-liveness/?.lua;" .. package.path

local Correlation = require("correlation")

local function equal(actual, expected) assert(actual == expected, string.format("expected %s, got %s", tostring(expected), tostring(actual))) end
local function sha256(token)
  return ({
    ["corr-AAAAAAAAAAAAAAAA"] = "83687efb86d2554f0547e44f7790efc5cc14b07af1ad8447ebb2d270cc6d7eac",
    ["corr-7777777777777777"] = "5e5f2182c2728604b072539a13264b2ed227582defd4deaa220f8ed8cb7e178b",
  })[token]
end
local local_alias = "poc001-corr-sha256-83687efb86d2554f0547e44f7790efc5cc14b07af1ad8447ebb2d270cc6d7eac"
local remote_alias = "poc001-corr-sha256-5e5f2182c2728604b072539a13264b2ed227582defd4deaa220f8ed8cb7e178b"

local function read_file(path)
  local file = assert(io.open(path, "r"))
  local content = assert(file:read("*a"))
  file:close()
  return content
end

return {
  ["POC-001 correlation uses both frozen SHA-256 vectors and retains aliases only"] = function()
    equal(Correlation.alias("corr-AAAAAAAAAAAAAAAA", sha256), local_alias)
    equal(Correlation.alias("corr-7777777777777777", sha256), remote_alias)
    local model = Correlation.new(sha256)
    assert(model:arm(7))
    local result = model:consume("101", "corr-AAAAAAAAAAAAAAAA")
    equal(result.result, "matched"); equal(result.alias, local_alias)
    equal(model:alias_for_window("101"), local_alias)
    assert(not model:alias_for_window("102"))
  end,
  ["POC-001 correlation rejects every unresolved identifier form without retry"] = function()
    local cases = {
      { value = nil, reason = "missing" }, { value = false, reason = "non_string" },
      { value = "", reason = "malformed" }, { value = "corr-aaaaaaaaaaaaaaaa", reason = "malformed" },
      { value = "corr-AAAAAAAAAAAAAAA", reason = "malformed" }, { value = "corr-AAAAAAAAAAAAAAAAX", reason = "malformed" },
    }
    for _, case in ipairs(cases) do
      local model = Correlation.new(sha256); assert(model:arm(1))
      equal(model:consume("101", case.value).reason, case.reason)
      equal(model:consume("102", "corr-AAAAAAAAAAAAAAAA").reason, "duplicate")
    end
    local hash_error = Correlation.new(function() error("no hash") end); assert(hash_error:arm(1)); equal(hash_error:consume("101", "corr-AAAAAAAAAAAAAAAA").reason, "hash_error")
    local construction = Correlation.new(sha256); assert(construction:arm(1)); equal(construction:unresolved("window_element_unavailable").reason, "window_element_unavailable"); equal(construction:consume("101", "corr-AAAAAAAAAAAAAAAA").reason, "duplicate")
    local read = Correlation.new(sha256); assert(read:arm(1)); equal(read:unresolved("attribute_read_error").reason, "attribute_read_error")
  end,
  ["POC-001 correlation requires exact valid aliases for a fixture-observer join"] = function()
    equal(Correlation.join_aliases(local_alias, local_alias), true)
    local joined, reason = Correlation.join_aliases(local_alias, remote_alias)
    equal(joined, false); equal(reason, "alias_mismatch")
    joined, reason = Correlation.join_aliases("poc001-corr-sha256-not-a-digest", local_alias)
    equal(joined, false); equal(reason, "malformed_alias")
  end,
  ["POC-001 correlation compares fixture raw absolute ticks with observer absolute nanoseconds only"] = function()
    local latency = Correlation.close_latency({
      clock_kind = "mach_absolute", ticks = 17, timebase_numer = 10, timebase_denom = 3,
    }, { absolute_ns = 61 }, { sleep_observed = false })
    equal(latency, 5)

    for _, invalid in ipairs({
      { fixture = { clock_kind = "mach_continuous", ticks = 17, timebase_numer = 10, timebase_denom = 3 }, observer = { absolute_ns = 61 }, options = { sleep_observed = false }, reason = "fixture_clock_not_absolute" },
      { fixture = { clock_kind = "mach_absolute", ticks = 17, timebase_numer = 10, timebase_denom = 0 }, observer = { absolute_ns = 61 }, options = { sleep_observed = false }, reason = "invalid_timebase" },
      { fixture = { clock_kind = "mach_absolute", ticks = 17, timebase_numer = 10, timebase_denom = 3 }, observer = { absolute_ns = 55 }, options = { sleep_observed = false }, reason = "negative_or_order_invalid" },
      { fixture = { clock_kind = "mach_absolute", ticks = 17, timebase_numer = 10, timebase_denom = 3 }, observer = { absolute_ns = 61 }, options = { sleep_observed = true }, reason = "sleep_observed" },
      { fixture = { clock_kind = "mach_absolute", ticks = math.maxinteger, timebase_numer = 2, timebase_denom = 1 }, observer = { absolute_ns = 61 }, options = { sleep_observed = false }, reason = "conversion_overflow" },
    }) do
      local value, reason = Correlation.close_latency(invalid.fixture, invalid.observer, invalid.options)
      equal(value, nil); equal(reason, invalid.reason)
    end
  end,

  ["POC-001 correlation guide reloads only its frozen observer dependencies"] = function()
    local guide = read_file(root .. "pocs/001-window-events-liveness/LIVE-CORRELATION.md")
    assert(guide:find("hs %-c 'print%(hs%.processInfo%.version%)'"))
    assert(not guide:find("hs %-v"))
    local load_at = assert(guide:find("POC001_OBSERVER = assert%(loadfile"))
    for _, module in ipairs({ "trace", "lifecycle", "ownership", "private_export", "correlation" }) do
      local clear_at = assert(guide:find("package%.loaded%." .. module .. " = nil"))
      assert(clear_at < load_at)
    end
  end,

  ["POC-001 correlation candidates retain aliases until explicit cleanup"] = function()
    local model = Correlation.new(sha256); assert(model:arm(1)); model:consume("101", "corr-AAAAAAAAAAAAAAAA")
    equal(model:alias_for_window("101"), local_alias); equal(model:count(), 1)
    model:clear()
    assert(not model:alias_for_window("101")); equal(model:count(), 0); equal(model:state().armed_generation, nil)
  end,
}
