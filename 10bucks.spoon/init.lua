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
local CanaryInstrumentation = require("lib.macos.canary_instrumentation")
local FocusHistory = require("lib.focus_history")
local HandleRegistry = require("lib.macos.handle_registry")

local Tenbucks = {}
Tenbucks.__index = Tenbucks
Tenbucks.name, Tenbucks.version = "10bucks", "Canary A"
Tenbucks.defaultHotkeys = Config.defaults.hotkeys

function Tenbucks.new()
  return setmetatable({ hotkeyBindings = {}, getenv = os.getenv,
    focusHistory = FocusHistory.new(), handleRegistry = HandleRegistry.new() }, Tenbucks):configure({})
end

function Tenbucks:_record(kind)
  if self.instrumentation then self.instrumentation:record(kind) end
end

function Tenbucks:canaryStatus()
  if not self.instrumentation then return nil end
  local result = self.instrumentation:status()
  result.started, result.suspended = self.started == true, self.suspended == true
  result.memberCount, result.version = 0, self.core and self.core:version() or 0
  if self.core then
    local state = self.core:state()
    local space = state.manager.spaces[self.core.spaceId]
    result.memberCount = space and #space.memberIds or 0
  end
  return result
end

function Tenbucks:canaryExport()
  return self.instrumentation and self.instrumentation:export() or nil
end
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
  -- A retained Core may still receive an ordering-lagged observation. Its
  -- reducer remains available, but its stopped host must not execute effects.
  if self.core then self.core.observer = function() end end
  if self.windows then self.windows:stop() end
  if self.host then self.host:stop() end
  self.host, self.windows = nil, nil
end

function Tenbucks:_stopScope()
  self:_stopHost()
  self.context, self.core, self.cores, self.suspended = nil, nil, nil, false
end

local function newCore(context)
  return Core.new({ displayId = context.displayId, regularSpaceId = context.regularSpaceId,
    workArea = context.workArea, layoutDependencies = layoutDependencies() })
end

function Tenbucks:_targetIsManaged(target)
  local core = target and self.cores and self.cores[target.spaceId]
  local window = core and core:state().manager.windows[target.windowId]
  local unplaced = target and self.focusHistory:unplacedTarget(target.windowId)
  local managed = (window and window.placementSpaceId == target.spaceId)
    or (unplaced and unplaced.target.spaceId == target.spaceId)
  return managed == true and self.handleRegistry:resolve(target) ~= nil
end

-- A managed focus callback can arrive before the host's Space watcher. Route
-- it by retained membership rather than the host that happened to receive it.
function Tenbucks:_coreForManagedWindow(windowId)
  local target = self.handleRegistry:target(windowId)
  local core = target and self.cores and self.cores[target.spaceId]
  local window = core and core:state().manager.windows[windowId]
  if window then return core, window end
end

function Tenbucks:_afterCoreEvent(event, eventCore)
  if event.type == "WindowDestroyed" then
    self.focusHistory:remove(event.id)
  elseif event.type == "ApplicationTerminated" then
    self.focusHistory:removeApplication(event.pid)
    local history = self.focusHistory:snapshot()
    for _, target in ipairs(history) do if not self:_targetIsManaged(target) then self.focusHistory:remove(target.windowId) end end
    local pending = self.focusHistory:pending()
    if pending and not self:_targetIsManaged(pending.target) then self.focusHistory:cancel() end
  elseif event.type == "ActualFocusChanged" then
    local window = eventCore and eventCore:state().manager.windows[event.id]
    local unplaced = self.focusHistory:unplacedTarget(event.id)
    local target = window and { windowId = event.id, spaceId = window.placementSpaceId }
      or (unplaced and unplaced.target)
    if target and self:_targetIsManaged(target) then self.focusHistory:observe(target) end
  end
end

function Tenbucks:_submitEvent(event, handle)
  if event.type == "WindowReady" and event.metadata.spaceType == "fullscreen" then
    if event.decision.action ~= "manage" then return true end
    local owner, window = self:_coreForManagedWindow(event.id)
    if owner then
      if not window.lifecycle.nativeFullscreen then
        local ok, err = owner:submit({ type = "WindowEnteredNativeFullscreen", id = event.id })
        if not ok then error(err, 0) end
      end
    else
      self.focusHistory:registerUnplaced(event)
      self.handleRegistry:remember(event.id, event.spaceId, handle, event.application.pid)
    end
    return true
  end
  local eventCore = self.core
  if event.type == "ActualFocusChanged" then
    local pending = self.focusHistory:pending()
    eventCore = (pending and self.cores[pending.target.spaceId]) or self:_coreForManagedWindow(event.id) or eventCore
  elseif event.id then
    eventCore = self:_coreForManagedWindow(event.id) or eventCore
  end
  if event.type == "WindowReady" and event.decision.action == "manage" then
    assert(eventCore and eventCore.spaceId == event.spaceId, "regular readiness requires its confirmed Core")
    -- Commit global relocation before Core admission can request native effects.
    -- Readiness alone never inserts/reorders an MRU entry.
    self.focusHistory:promote({ windowId = event.id, spaceId = event.spaceId })
  end
  if eventCore then
    local accepted, failure = eventCore:submit(event)
    if not accepted then error(failure, 0) end
    if event.type == "WindowReady" and event.metadata.nativeFullscreen == false then
      local window = eventCore:state().manager.windows[event.id]
      if window and window.lifecycle.nativeFullscreen then
        local ok, err = eventCore:submit({ type = "WindowExitedNativeFullscreen", id = event.id })
        if not ok then error(err, 0) end
      end
    end
  end
  self:_afterCoreEvent(event, eventCore)
  return true
end

function Tenbucks:_focusManagedPrevious()
  local target = self.focusHistory:previous(function(candidate) return self:_targetIsManaged(candidate) end)
  if not target then return false, "no-previous-managed-window" end
  self.focusHistory:request(target)
  local targetCore = self.cores[target.spaceId]
  local handle = self.handleRegistry:resolve(target)
  if not handle then self.focusHistory:cancel(); return false, "previous-managed-window-unavailable" end
  if targetCore then
    local accepted, failure = targetCore:submit({ type = "FocusTarget", windowId = target.windowId })
    if not accepted then self.focusHistory:cancel(); return false, failure end
    if targetCore == self.core and not self.suspended then return true end
  end
  -- Use the same targeted post-effect confirmation path as Core focus intents;
  -- hs.window:focus() may not emit an unchanged-focus AX callback.
  self.host:focus(handle) -- Hammerspoon hs.window:focus() performs the native Space transition.
  return true
end

function Tenbucks:_submitCommand(command)
  if command.type == "FocusManagedPrevious" then return self:_focusManagedPrevious() end
  if self.suspended or not self.core then return false, "native-fullscreen-has-no-regular-layout" end
  return self.core:submit(command)
end

function Tenbucks:_startHost(context)
  local host, adapter
  local ok, err = pcall(function()
    host = Host.new(hs, context, self.instrumentation, self.handleRegistry):start()
    local native = {
      subscribeApplications = function(callback) return host:subscribeApplications(callback) end,
      subscribeExistingWindows = function(callback) return host:subscribeExistingWindows(callback) end,
      subscribeWindow = function(handle, callback) return host:subscribeWindow(handle, callback) end,
      probeReadiness = function(id, callback) return host:probeReadiness(id, callback) end,
      managedDecision = function(id)
        local _, window = self:_coreForManagedWindow(id)
        if window then return { action = window.ruleAction } end
        local unplaced = self.focusHistory:unplacedTarget(id)
        return unplaced and unplaced.decision
      end,
      record = function(kind) self:_record(kind) end,
      recordEvent = function(eventType) if self.instrumentation then self.instrumentation:recordEvent(eventType) end end,
    }
    adapter = Windows.new({ native = native, sink = function(event)
      self:_submitEvent(event, event.id and adapter:handleForId(event.id))
    end })
    if self.core then
      self.core.observer = function(intents, version)
        if version > (self.canaryObservedVersion or 0) then
          self.canaryObservedVersion = version
          self:_record("reducerCommitVersions")
        end
        if not self.suspended then
          -- All emitted focus requests share the global confirmation gate. A
          -- newer local command must supersede an in-flight global previous.
          for _, intent in ipairs(intents) do
            if intent.kind == "focus" then
              local target = { windowId = intent.windowId, spaceId = intent.spaceId }
              local pending = self.focusHistory:pending()
              if self:_targetIsManaged(target) and (not pending or pending.target.windowId ~= target.windowId
                or pending.target.spaceId ~= target.spaceId) then self.focusHistory:request(target) end
            end
          end
          host:execute(adapter, intents)
        end
      end
    end
    adapter:start() -- bootstrap/re-synchronize only this confirmed original Space.
    for _, record in pairs(self.focusHistory:state().unplaced) do
      local handle = self.handleRegistry:resolve(record.target)
      if handle then
        local attached = pcall(adapter.retainManaged, adapter, record.target.windowId, handle, record.pid)
        if not attached then self:_record("unplacedObserverDeferrals") end
      end
    end
    -- Bootstrap readiness may precede the only focus observation; sample the
    -- current global native focus once without requesting focus.
    host:observeFocus()
    self.context, self.host, self.windows = context, host, adapter
  end)
  if not ok then
    if adapter then adapter:stop() end
    if host then host:stop() end
    error(err, 0)
  end
end

function Tenbucks:_beginContext(context)
  self.cores = {}
  if context.regularSpaceId then
    self.core = newCore(context)
    self.cores[context.regularSpaceId] = self.core
  end
  self.originContext, self.suspended = context, context.regularSpaceId == nil
  self:_startHost(context)
end

-- A confirmed regular-Space activation switches the single native host to that
-- Space's retained pure Core. A newly observed Space gets one bootstrap; a
-- returning Space reuses its existing order, selection, and layout state.
function Tenbucks:_contextChanged(context)
  if not context.regularSpaceId then
    self.suspended = true
    self.host:observeFocus()
    return
  end
  if self.context and context.regularSpaceId == self.context.regularSpaceId and not self.suspended then return end
  self:_stopHost()
  self.core = self.cores[context.regularSpaceId]
  if not self.core then
    self.core = newCore(context)
    self.cores[context.regularSpaceId] = self.core
  end
  self.suspended = false
  self:_startHost(context)
  self.core:submit({ type = "Reflow" })
  local pending = self.focusHistory:pending()
  if pending and pending.target.spaceId == context.regularSpaceId and self:_targetIsManaged(pending.target) then
    self.core:submit({ type = "FocusTarget", windowId = pending.target.windowId })
  end
end

function Tenbucks:start()
  if self.started then return self end
  self.instrumentation = self.config.canaryInstrumentation and CanaryInstrumentation.new() or nil
  self.canaryObservedVersion = 0
  if self.instrumentation then self.instrumentation:setActiveTimers(0) end
  local bindings, contextSubscription
  local ok, err = pcall(function()
    self:_beginContext(Context.snapshot(hs, self.config.builtInDisplayUUID))
    bindings = Bindings.bind(hs, function(command) return self:_submitCommand(command) end, self.config.hotkeys)
    contextSubscription = Context.watch(hs, self.config.builtInDisplayUUID, function(context)
      if self.started then self:_contextChanged(context) end
    end)
  end)
  if not ok then
    if contextSubscription then contextSubscription.detach() end
    Bindings.delete(bindings); self:_stopScope(); self.originContext = nil; self.instrumentation = nil; error(err, 0)
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
  self.canaryObservedVersion = nil
  self.focusHistory = FocusHistory.new()
  self.handleRegistry:clear()
  Bindings.delete(self.hotkeyBindings)
  self.hotkeyBindings = {}
  return self
end

function Tenbucks:bindHotkeys(mapping)
  assert(not self.started, "Stop 10bucks before changing hotkeys")
  -- Rebuild the complete validated plain config so binding changes cannot discard
  -- semantic fields supplied by configureFile (or later explicit config fields).
  local complete = Config.build(self.config)
  complete.hotkeys = mapping or complete.hotkeys
  self.config = Config.build(complete)
  return self
end

return Tenbucks.new()
