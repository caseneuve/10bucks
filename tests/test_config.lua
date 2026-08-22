local Config = require("lib.config")

local function withTempFile(contents, callback)
  local path = os.tmpname()
  local file = assert(io.open(path, "w"))
  file:write(contents)
  file:close()

  local ok, result = pcall(callback, path)
  os.remove(path)
  if not ok then error(result, 0) end
  return result
end

local function captureError(callback)
  local ok, err = pcall(callback)
  assert(not ok, "expected callback to fail")
  return tostring(err)
end

return {
  ["configuration deep-merges action maps but replaces lists"] = function()
    local config = Config.build({
      excludedBundleIDs = { "example.bundle" },
      hotkeys = { toggleLayout = { { "cmd" }, "t" } },
    })
    assert(config.excludedBundleIDs[1] == "example.bundle")
    assert(#config.excludedBundleIDs == 1)
    assert(#config.excludedWindowTitles == 0)
    assert(config.hotkeys.toggleLayout[1][1] == "cmd")
    assert(config.hotkeys.toggleLayout[2] == "t")
    assert(config.hotkeys.reflow ~= nil)
    assert(config.hotkeys.focusPreviousWindow[2] == ";")
    assert(config.hotkeys.swapColumns[2] == "g")
    assert(config.hotkeys.chooseWorkspace[2] == "u")
    assert(config.hotkeys.chooseWindow[2] == "w")
    assert(config.hotkeys.newWorkspace == nil)
    assert(config.hotkeys.deleteWorkspace[2] == "delete")
    assert(config.hotkeys.moveFocusedToOtherColumn[2] == "o")
    assert(config.hotkeys.toggleManaged == nil)
    assert(Config.build({}).initialLayout == "stack")
    assert(Config.build({ initialLayout = "columns" }).initialLayout == "columns")
  end,

  ["empty option maps retain nested defaults"] = function()
    local config = Config.build({ bar = {}, hotkeys = {} })
    assert(config.bar.enabled == Config.defaults.bar.enabled)
    assert(config.bar.height == Config.defaults.bar.height)
    assert(config.bar.backgroundColor.alpha == Config.defaults.bar.backgroundColor.alpha)
    assert(config.hotkeys.toggleLayout[2] == "space")
    assert(config.hotkeys.reflow[2] == "r")
  end,

  ["false hotkey overrides disable one action while retaining omitted defaults"] = function()
    local config = Config.build({ hotkeys = { deleteWorkspace = false } })
    assert(config.hotkeys.deleteWorkspace == false)
    assert(config.hotkeys.chooseWindow[2] == "w")
    assert(config.hotkeys.toggleLayout[2] == "space")
  end,

  ["configuration validates title exclusion patterns and custom filters"] = function()
    local config = Config.build({
      excludedWindowTitles = { "^Picture in Picture$" },
      windowFilter = function() return false end,
    })
    assert(config.excludedWindowTitles[1] == "^Picture in Picture$")
    assert(type(config.windowFilter) == "function")
    assert(not pcall(Config.build, { excludedWindowTitles = { "[" } }))
    assert(not pcall(Config.build, { windowFilter = true }))
    assert(not pcall(Config.build, { outerGap = -1 }))
    assert(not pcall(Config.build, { columnGap = -1 }))
  end,

  ["shipped configuration example returns a complete valid table"] = function()
    local config = Config.build(Config.loadFile("10bucks.spoon/config.example.lua"))
    assert(config.initialLayout == "stack")
    assert(config.bar.rightInset == 24)
    assert(config.hotkeys.chooseWindow[2] == "w")
    assert(config.hotkeys.deleteWorkspace[2] == "delete")
  end,

  ["Lua configuration files return executable tables"] = function()
    local config = withTempFile([[local hyper = { "cmd", "alt" }
return {
  hotkeys = {
    chooseWindow = { hyper, "w" },
    deleteWorkspace = false,
  },
}
]], function(path)
      return Config.loadFile(path)
    end)
    assert(config.hotkeys.chooseWindow[1][1] == "cmd")
    assert(config.hotkeys.chooseWindow[1][2] == "alt")
    assert(config.hotkeys.chooseWindow[2] == "w")
    assert(config.hotkeys.deleteWorkspace == false)
  end,

  ["Lua configuration syntax errors preserve the file path and line"] = function()
    local message = withTempFile("return @\n", function(path)
      local message = captureError(function() Config.loadFile(path) end)
      assert(message:find(path, 1, true))
      assert(message:find(":1:", 1, true))
      return message
    end)
    assert(message ~= "")
  end,

  ["Lua configuration runtime errors preserve the file path and message"] = function()
    local message = withTempFile([[error("config exploded")
]], function(path)
      local message = captureError(function() Config.loadFile(path) end)
      assert(message:find(path, 1, true))
      assert(message:find("config exploded", 1, true))
      return message
    end)
    assert(message ~= "")
  end,

  ["Lua configuration requires a table result"] = function()
    local message = withTempFile("return \"not a table\"\n", function(path)
      local message = captureError(function() Config.loadFile(path) end)
      assert(message:find(path, 1, true))
      assert(message:find("10bucks config", 1, true))
      assert(message:find("must return a table", 1, true))
      return message
    end)
    assert(message ~= "")
  end,

  ["Lua configuration reports a missing file path"] = function()
    local path = os.tmpname()
    os.remove(path)
    local message = captureError(function() Config.loadFile(path) end)
    os.remove(path)
    assert(message:find(path, 1, true))
    assert(message:find("cannot open", 1, true))
  end,
}
