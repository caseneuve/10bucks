local source = debug.getinfo(1, "S").source:sub(2)
local root = source:match("(.*/)")
if root then package.path = root .. "?.lua;" .. root .. "?/init.lua;" .. package.path end

local Config = require("lib.config")
local Core = require("lib.core")
local Stack = require("lib.layouts.stack")
local Columns = require("lib.layouts.columns")
local Context = require("lib.macos.context")
local Host = require("lib.macos.window_host")
local Windows = require("lib.macos.windows")
local Bindings = require("lib.bindings")

local Tenbucks = {}
Tenbucks.__index = Tenbucks
Tenbucks.name, Tenbucks.version = "10bucks", "Canary A"
Tenbucks.defaultHotkeys = Config.defaults.hotkeys

function Tenbucks.new() return setmetatable({ hotkeyBindings = {}, getenv = os.getenv }, Tenbucks):configure({}) end
function Tenbucks:configure(options) assert(not self.started, "Stop 10bucks before changing configuration"); self.config = Config.build(options); return self end
function Tenbucks:configureFile(path)
  assert(not self.started, "Stop 10bucks before changing configuration")
  if path == nil then
    local xdg, home = self.getenv("XDG_CONFIG_HOME"), self.getenv("HOME")
    if xdg and xdg ~= "" then path = xdg .. "/10bucks/config.lua"
    else
      if not home or home == "" then error("10bucks config: XDG_CONFIG_HOME or HOME must be set", 0) end
      path = home .. "/.config/10bucks/config.lua"
    end
  end
  return self:configure(Config.loadFile(path))
end

local function layoutDependencies()
  return { activeLayoutId = "stack", layoutIds = { "stack", "columns" }, registry = { stack = Stack, columns = Columns },
    layoutConfigs = { columns = { minRatio = .25, maxRatio = .75, defaultRatio = .5 } } }
end

function Tenbucks:_stopHost()
  if self.windows then self.windows:stop() end
  if self.host then self.host:stop() end
  self.host, self.windows = nil, nil
end

function Tenbucks:_stopScope()
  self:_stopHost()
  self.context, self.core, self.suspended = nil, nil, false
end

function Tenbucks:_startHost(context)
  local host, adapter
  local ok, err = pcall(function()
    host = Host.new(hs, context):start()
    local native = {
      subscribeApplications = function(callback) return host:subscribeApplications(callback) end,
      subscribeExistingWindows = function(callback) return host:subscribeExistingWindows(callback) end,
      subscribeWindow = function(handle, callback) return host:subscribeWindow(handle, callback) end,
      probeReadiness = function(id, callback) return host:probeReadiness(id, callback) end,
    }
    adapter = Windows.new({ native = native, sink = function(event)
      local accepted, failure = self.core:submit(event); if not accepted then error(failure, 0) end
    end })
    self.core.observer = function(intents) host:execute(adapter, intents) end
    adapter:start() -- bootstrap/re-synchronize only this confirmed original Space.
    self.context, self.host, self.windows = context, host, adapter
  end)
  if not ok then
    if adapter then adapter:stop() end
    if host then host:stop() end
    error(err, 0)
  end
end

function Tenbucks:_beginContext(context)
  self.core = Core.new({ displayId = context.displayId, regularSpaceId = context.regularSpaceId,
    workArea = context.workArea, layoutDependencies = layoutDependencies() })
  self.originContext, self.suspended = context, false
  self:_startHost(context)
end

-- Canary A owns one original regular Space. A different confirmed Space is a
-- non-destructive suspension boundary, not permission to rebuild Core state.
function Tenbucks:_contextChanged(context)
  if not self.originContext then return end
  if context.regularSpaceId == self.originContext.regularSpaceId then
    if self.suspended then
      self.suspended = false
      self:_startHost(context)
      self.core:submit({ type = "Reflow" })
    end
    return -- duplicate same-Space observation is a no-op.
  end
  if not self.suspended then
    self:_stopHost()
    self.context, self.suspended = context, true
  end
end

function Tenbucks:start()
  if self.started then return self end
  local bindings, contextSubscription
  local ok, err = pcall(function()
    self:_beginContext(Context.snapshot(hs, self.config.builtInDisplayUUID))
    bindings = Bindings.bind(hs, function(command)
      if self.suspended then return false, "10bucks Canary A is suspended outside its original regular Space" end
      return self.core:submit(command)
    end, self.config.hotkeys)
    contextSubscription = Context.watch(hs, self.config.builtInDisplayUUID, function(context)
      if self.started then self:_contextChanged(context) end
    end)
  end)
  if not ok then
    if contextSubscription then contextSubscription.detach() end
    Bindings.delete(bindings); self:_stopScope(); self.originContext = nil; error(err, 0)
  end
  self.contextSubscription, self.hotkeyBindings, self.started = contextSubscription, bindings, true
  return self
end

function Tenbucks:stop()
  self.started = false
  if self.contextSubscription then self.contextSubscription.detach() end
  self.contextSubscription = nil
  self:_stopScope()
  self.originContext = nil
  Bindings.delete(self.hotkeyBindings)
  self.hotkeyBindings = {}
  return self
end

function Tenbucks:bindHotkeys(mapping)
  assert(not self.started, "Stop 10bucks before changing hotkeys")
  self.config = Config.build({ builtInDisplayUUID = self.config.builtInDisplayUUID, hotkeys = mapping or self.config.hotkeys })
  return self
end

return Tenbucks.new()
