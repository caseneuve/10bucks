local source = debug.getinfo(1, "S").source:sub(2)
local root = source:match("(.*/)")
if root then package.path = root .. "?.lua;" .. root .. "?/init.lua;" .. package.path end

local Config = require("lib.config")
local Rules = require("lib.rules")
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
local Coordinator = require("lib.layouts.coordinator")
local Model = require("lib.model")
local Bar = require("lib.bar")
local NativeBar = require("lib.macos.bar")
local Runtime = require("lib.runtime")
local WorkspaceSwitch = require("lib.workspace_switch")
local Spaces = require("lib.macos.spaces")
local WindowChooser = require("lib.window_chooser")
local NativeChooser = require("lib.macos.chooser")

local Tenbucks = {}
Tenbucks.__index = Tenbucks
Tenbucks.name, Tenbucks.version = "10bucks", "Canary A"
Tenbucks.defaultHotkeys = Config.defaults.hotkeys

function Tenbucks.new(nativeValidity, nativeDiscovery)
  return setmetatable({ nativeValidity = nativeValidity, nativeDiscovery = nativeDiscovery, hotkeyBindings = {}, getenv = os.getenv,
    focusHistory = FocusHistory.new(), chooserRows = {}, actualPresentation = {}, handleRegistry = HandleRegistry.new() }, Tenbucks):configure({})
end

function Tenbucks:_record(kind)
  if self.instrumentation then self.instrumentation:record(kind) end
end

function Tenbucks:canaryStatus()
  if not self.instrumentation then return nil end
  local result = self.instrumentation:status()
  result.started, result.suspended = self.started == true, self.suspended == true
  result.activeTimers = self.bar and self.bar:timerCount() or 0
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

local function layoutDependencies(config)
  return { activeLayoutId = "stack", layoutIds = { "stack", "columns" }, registry = { stack = Stack, columns = Columns },
    layoutConfigs = { stack = { columnGap = config.columnGap },
      columns = { minRatio = .30, maxRatio = .70, defaultRatio = .5, columnGap = config.columnGap } } }
end

function Tenbucks:_publishBar()
  if not self.bar or not self.context then return end
  local status, layout = { position = nil, count = 0 }, "stack"
  if self.core and not self.suspended then
    local state = self.core:state()
    local coordinator = state.coordinators[self.core.spaceId]
    local available = {}; for id, window in pairs(state.manager.windows) do available[id] = Model.isAvailable(window) end
    status = Coordinator.status(coordinator, available, { displayId = self.core.displayId, spaceId = self.core.spaceId,
      availableMembers = available }, self.core.dependencies)
    layout = coordinator.activeLayoutId
  end
  self.bar:present(Bar.format(Bar.view({ context = self.context, status = status, layout = layout,
    actual = self.actualPresentation, timestamp = hs.timer.secondsSinceEpoch(), dark = self.darkAppearance })))
end

function Tenbucks:_stopObservers()
  if self.windows then self.windows:stop() end
  if self.host then self.host:stop() end
  self.host, self.windows, self.effectBatch = nil, nil, nil
end

function Tenbucks:_stopScope()
  self:_stopObservers()
  self.context, self.core, self.cores, self.suspended = nil, nil, nil, false
end

local function newCore(context, config)
  return Core.new({ displayId = context.displayId, regularSpaceId = context.regularSpaceId,
    workArea = context.workArea, layoutDependencies = layoutDependencies(config) })
end

function Tenbucks:_observeCoreIntents(core, intents, version)
  if version > (self.canaryObservedVersion or 0) then
    self.canaryObservedVersion = version
    self:_record("reducerCommitVersions")
  end
  local entry = { core = core, intents = intents, version = version, contextEpoch = self.contextEpoch }
  if self.effectBatch then self.effectBatch[#self.effectBatch + 1] = entry
  else self:_flushCoreIntents({ entry }) end
end

function Tenbucks:_entryCanExecute(entry)
  return entry.contextEpoch == self.contextEpoch and entry.core == self.core
    and not self.suspended and self.host and self.windows
end

function Tenbucks:_scopedIntents(intents, core)
  local scoped = {}
  for _, intent in ipairs(intents) do
    local desired = core and core:state().manager.focus.desiredBySpace[core.spaceId]
    local current = intent.kind ~= "focus" or (desired and desired.pending
      and desired.targetId == intent.windowId and desired.generation == intent.generation)
    local window = core and core:state().manager.windows[intent.windowId]
    -- Fullscreen global requests use the direct exact-handle effect below;
    -- saved regular Core intents must not issue a second effect behind it.
    if current and not (intent.kind == "focus" and window and window.lifecycle.nativeFullscreen) then
    local copy = {}; for key, value in pairs(intent) do copy[key] = value end
    if copy.kind == "frame" or copy.kind == "focus" then
      local target = self.handleRegistry:target(copy.windowId)
      if target and target.spaceId == copy.spaceId then copy.lease = target.lease end
    end
    scoped[#scoped + 1] = copy
    end
  end
  return scoped
end

function Tenbucks:_flushCoreIntents(entries)
  -- Core reducers, global focus confirmation, and route updates all commit
  -- before the first native request. Stale/inactive batches own neither.
  for _, entry in ipairs(entries) do
    if self:_entryCanExecute(entry) then
      for _, intent in ipairs(self:_scopedIntents(entry.intents, entry.core)) do
        if intent.kind == "focus" then
          local target = { windowId = intent.windowId, spaceId = intent.spaceId }
          local pending = self.focusHistory:pending()
          if self:_targetIsManaged(target) and (not pending or pending.windowId ~= target.windowId or pending.spaceId ~= target.spaceId) then
            self:_stopManagedFocusTimer()
            self.focusHistory:request(target)
          end
        end
      end
    end
  end
  local success = true
  for _, entry in ipairs(entries) do
    if self:_entryCanExecute(entry) then
      self:_publishBar()
      local executed = self.host:execute(self.windows, self:_scopedIntents(entry.intents, entry.core), function(intent)
        if not self:_entryCanExecute(entry) then return false end
        if intent.kind == "focus" then
          local desired = entry.core:state().manager.focus.desiredBySpace[entry.core.spaceId]
          local pending = self.focusHistory:pending()
          return desired.pending and desired.targetId == intent.windowId and desired.generation == intent.generation
            and pending and pending.windowId == intent.windowId and pending.spaceId == intent.spaceId
        end
        return intent.kind ~= "frame" or entry.core:frameIsCurrent(intent)
      end)
      if executed == false then self:_cancelManagedFocus(); success = false end
    end
  end
  return success
end

function Tenbucks:_withEffectBatch(work)
  local parent, batch = self.effectBatch, {}
  self.effectBatch = batch
  local ok, first, second = pcall(work)
  self.effectBatch = parent
  if not ok then error(first, 0) end
  if parent then
    for _, entry in ipairs(batch) do parent[#parent + 1] = entry end
  else
    self.effectBatch = batch
    local focusFailed = false
    local flushed, flushError = pcall(function()
    while #batch > 0 do
    local pending = batch; batch = {}; self.effectBatch = batch
    local cores, workspace = {}, {}
    for _, entry in ipairs(pending) do
      if entry.workspace then workspace[#workspace + 1] = entry else cores[#cores + 1] = entry end
    end
    if self:_flushCoreIntents(cores) == false then focusFailed = true end
    for _, entry in ipairs(workspace) do
      for _, intent in ipairs(entry.intents) do
        if self.spaces and self.workspace then
          if intent.kind == "resnapshotRegularTopology" then
            self:_contextChanged(Context.snapshot(hs, self.config.builtInDisplayUUID))
          elseif intent.kind ~= "RegularSpaceRemoved" then
            local op = self.workspace:state().switch.inFlight
            if intent.kind == "cancelRegularSwitch" or (op and not op.invalidated and op.generation == intent.generation) then
              self.spaces:execute(intent)
            end
          end
        end
      end
    end
    end
    end)
    self.effectBatch = nil
    if not flushed then
      local op = self.workspace and self.workspace:state().switch.inFlight
      if op and self.spaces and not self.spaces.operation then
        self.workspace:submit({ type = "RegularSwitchFailed", generation = op.generation,
          sourceId = op.sourceId, sourceType = op.sourceType, destinationId = op.destinationId })
      end
      error(flushError, 0)
    end
    if focusFailed and first == true then return false, "managed-focus-failed" end
  end
  return first, second
end

function Tenbucks:_submitCore(core, event)
  event.focusAuthority = core == self.core and not self.suspended
  local accepted, failure = core:submit(event)
  if not accepted then error(failure, 0) end
end

function Tenbucks:_coreForSpace(spaceId)
  local core = self.cores and self.cores[spaceId]
  if core then return core end
  if not self.context or not spaceId then return nil end
  if self.workspace then
    local present = false
    for _, id in ipairs(self.workspace:state().regularSpaceIds) do if id == spaceId then present = true end end
    if not present then return nil end
  end
  local context = { displayId = self.context.displayId, regularSpaceId = spaceId, workArea = self.context.workArea }
  core = newCore(context, self.config)
  self.cores[spaceId] = core
  core.observer = function(intents, version) self:_observeCoreIntents(core, intents, version) end
  return core
end

function Tenbucks:_targetIsManaged(target)
  local core = target and self.cores and self.cores[target.spaceId]
  local window = core and core:state().manager.windows[target.windowId]
  local unplaced = target and self.focusHistory:unplacedTarget(target.windowId)
  local managed = (window and window.placementSpaceId == target.spaceId)
    or (unplaced and unplaced.target.spaceId == target.spaceId)
  return managed == true and not (unplaced and unplaced.uncertain) and self.handleRegistry:resolve(target) ~= nil
end

-- A managed focus callback can arrive before the host's Space watcher. Route
-- it by retained membership rather than the host that happened to receive it.
function Tenbucks:_coreForManagedWindow(windowId, lease)
  local target = self.handleRegistry:target(windowId, lease)
  local core = target and self.cores and self.cores[target.spaceId]
  local window = core and core:state().manager.windows[windowId]
  if window then return core, window, target end
  if target then
    for _, retained in pairs(self.cores or {}) do
      local member = retained:state().manager.windows[windowId]
      if member and member.lifecycle.nativeFullscreen then
        return retained, member, { windowId = windowId, spaceId = retained.spaceId, lease = target.lease }
      end
    end
  end
end

function Tenbucks:_updateChooser(event)
  self.chooserRows = WindowChooser.reduce(self.chooserRows, event)
  if self.windowChooser then self.windowChooser:refresh() end
end

function Tenbucks:_cacheReady(event)
  local route = self.handleRegistry:target(event.id, event.resource)
  if route and (type(route.lease) == "number" or type(route.lease) == "string") and self:_targetIsManaged(route) then
    self:_updateChooser({ type = "Upsert", row = { windowId = event.id, lease = route.lease,
      pid = event.application.pid, text = event.title or "", subText = event.application.name or "" } })
  end
end

function Tenbucks:_afterCoreEvent(event, eventCore)
  if event.type == "WindowDestroyed" then
    self.focusHistory:remove(event.id)
    if not self.focusHistory:pending() then self:_stopManagedFocusTimer() end
  elseif event.type == "ActualFocusChanged" then
    local window = eventCore and eventCore:state().manager.windows[event.id]
    local unplaced = self.focusHistory:unplacedTarget(event.id)
    local target = (unplaced and not unplaced.uncertain and unplaced.target)
      or (window and { windowId = event.id, spaceId = window.placementSpaceId })
    if target and self:_targetIsManaged(target) then
      self.focusHistory:observe(target)
      if not self.focusHistory:pending() then self:_stopManagedFocusTimer() end
    end
  end
end

function Tenbucks:_submitEvent(event, handle)
  return self:_withEffectBatch(function() return self:_deliverEvent(event, handle) end)
end

function Tenbucks:_deliverEvent(event, handle)
  -- A stale lifecycle callback cannot route or mutate actual presentation by
  -- an ID alone after its window resource lease ended. Current global focus is
  -- a separate native read and remains presentation-authoritative.
  if event.id and event.resource and event.type ~= "WindowReady" and event.type ~= "ActualFocusChanged"
    and not self.handleRegistry:matches(event.id, event.resource) then
    -- Excluded lifetime events retire observation decisions, never enter Core.
    self:_publishBar(); return true
  end
  self.actualPresentation = Bar.reduceActual(self.actualPresentation, event)
  if event.type == "ActualFocusChanged" and event.id == nil then self:_publishBar(); return true end
  if event.type == "PresentationEnded" then self:_publishBar(); return true end
  -- A title-only presentation observer has no managed window resource. It can
  -- update BAR actual presentation but cannot alias an equal numeric ID into a
  -- retained Core.
  if event.type == "WindowTitleChanged" and event.presentationResource ~= nil and event.resource == nil then
    self:_publishBar(); return true
  end
  if event.type == "ActualFocusChanged" and event.id ~= nil then
    -- A focused conflicting wrapper may share a native ID with a retained
    -- route. BAR may show the current native read, but managed selection/MRU
    -- require that route's exact accepted resource.
    local routed = self.handleRegistry:target(event.id)
    if routed and routed.lease ~= event.resource then self:_publishBar(); return true end
  end

  if event.type == "ApplicationHidden" or event.type == "ApplicationUnhidden" or event.type == "ApplicationTerminated" then
    if event.type ~= "ApplicationTerminated" then self.focusHistory:observeLifecycle(event) end
    if event.type ~= "ApplicationUnhidden" then
      local pending = self.focusHistory:pending()
      if pending and pending.restoreLease then
        local _, window = self:_coreForManagedWindow(pending.windowId, pending.restoreLease)
        if window and window.application.pid == event.pid then self:_cancelManagedFocus() end
      end
    end
    self:_withEffectBatch(function()
      local removed = {}
      for _, core in pairs(self.cores or {}) do
        if event.type == "ApplicationTerminated" then
          for id, window in pairs(core:state().manager.windows) do if window.application.pid == event.pid then removed[#removed + 1] = id end end
        end
        self:_submitCore(core, event)
      end
      if event.type == "ApplicationTerminated" then
        for _, id in ipairs(removed) do self.focusHistory:remove(id) end
        self.focusHistory:removeApplication(event.pid)
        self.handleRegistry:forgetPid(event.pid, event.resource)
        self:_updateChooser({ type = "RemoveApplication", pid = event.pid })
      end
    end)
    self:_publishBar()
    return true
  end

  if event.type == "WindowMinimized" or event.type == "WindowRestored"
    then
    self.focusHistory:observeLifecycle(event)
  end
  local readyAction = event.decision and event.decision.action or "manage"
  local function readyRouteAllowed()
    local prior = self.handleRegistry:target(event.id)
    if prior and prior.lease ~= event.resource then return false end
    return handle == nil or self.handleRegistry:canRemember(event.id, event.resource)
  end
  local function rememberReady()
    if handle ~= nil and not self.handleRegistry:remember(event.id, event.spaceId, handle, event.application.pid, event.resource, event.appResource) then
      error("current WindowReady route was refused after preflight", 0)
    end
  end
  if event.type == "WindowReady" and event.metadata and event.metadata.spaceType == "fullscreen" then
    if readyAction ~= "manage" then return true end
    if not readyRouteAllowed() then return false end
    local owner, window = self:_coreForManagedWindow(event.id, event.resource)
    self.focusHistory:registerUnplaced(event)
    if owner then
      if not window.lifecycle.nativeFullscreen then self:_submitCore(owner, { type = "WindowEnteredNativeFullscreen", id = event.id }) end
    end
    rememberReady()
    self:_cacheReady(event)
    self:_publishBar(); return true
  end

  if event.type == "WindowReady" and readyAction == "manage" then
    if not readyRouteAllowed() or not self:_coreForSpace(event.spaceId) then return false end
    self:_withEffectBatch(function()
      local prior, _, target = self:_coreForManagedWindow(event.id, event.resource)
      local destination = self:_coreForSpace(event.spaceId)
      if prior and target.spaceId ~= event.spaceId then
        self:_submitCore(prior, { type = "WindowRelocated", id = event.id })
        self.focusHistory:relocate({ windowId = event.id, spaceId = event.spaceId })
        self.focusHistory:promote({ windowId = event.id, spaceId = event.spaceId })
      elseif self.focusHistory:unplacedTarget(event.id) then
        self.focusHistory:promote({ windowId = event.id, spaceId = event.spaceId })
      end
      if not destination then return end
      self:_submitCore(destination, event)
      local window = destination:state().manager.windows[event.id]
      if window and window.lifecycle.nativeFullscreen and event.metadata and event.metadata.nativeFullscreen == false then
        self:_submitCore(destination, { type = "WindowExitedNativeFullscreen", id = event.id })
      end
      rememberReady()
      self:_cacheReady(event)
    end)
    self:_publishBar(); return true
  end

  local eventCore = nil
  if event.type == "ActualFocusChanged" then
    local pending = self.focusHistory:pending()
    if pending and (pending.restoreLease or pending.windowId ~= event.id) then self:_publishBar(); return true end
    eventCore = self:_coreForManagedWindow(event.id, event.resource) or self.core
  elseif event.id then
    eventCore = self:_coreForManagedWindow(event.id, event.resource)
  end
  if event.type == "WindowDestroyed" then
    self:_withEffectBatch(function()
      if eventCore then self:_submitCore(eventCore, event) end
      self:_afterCoreEvent(event, eventCore)
      self.handleRegistry:forget(event.id, nil, event.resource)
      self:_updateChooser({ type = "Remove", windowId = event.id, lease = event.resource })
    end)
  else
    if eventCore then self:_submitCore(eventCore, event) end
    self:_afterCoreEvent(event, eventCore)
    if event.type == "WindowRestored" then self:_focusRestoredTarget(event) end
    if event.type == "WindowTitleChanged" and self.handleRegistry:matches(event.id, event.resource) then
      self:_updateChooser({ type = "Title", windowId = event.id, lease = event.resource, title = event.title })
    end
  end
  self:_publishBar()
  return true
end

function Tenbucks:_focusManagedPrevious()
  local target = self.focusHistory:previous(function(candidate) return self:_targetIsManaged(candidate) end)
  if not target then return false, "no-previous-managed-window" end
  return self:_focusManagedTarget(target)
end

function Tenbucks:_stopManagedFocusTimer()
  if self.managedFocusTimer then self.managedFocusTimer:stop(); self.managedFocusTimer = nil end
  if self.host then self.host:cancelRestore() end
end

function Tenbucks:_cancelManagedFocus()
  self:_stopManagedFocusTimer()
  self.focusHistory:cancel()
  for _, core in pairs(self.cores or {}) do
    self:_submitCore(core, { type = "FocusRequestCancelled", spaceId = core.spaceId })
  end
end

function Tenbucks:_focusRestoredTarget(event)
  local pending, timer = self.focusHistory:pending(), self.managedFocusTimer
  if not timer or not pending or pending.windowId ~= event.id or not pending.restoreLease
    or pending.restoreLease ~= event.resource then return end
  local target = self.handleRegistry:target(event.id, event.resource)
  local handle = target and target.spaceId == pending.spaceId and self:_targetIsManaged(target)
    and self.handleRegistry:resolve(target)
  local function authorized() return self.managedFocusTimer == timer and self:_targetIsManaged(target) end
  -- The lifecycle fact already committed. Only actual focus can now settle history.
  self.focusHistory:request(pending)
  local ok, requested
  if handle then ok, requested = pcall(self.host.focus, self.host, handle, event.resource, pending.spaceId, false, nil, authorized) end
  if (not ok or requested == nil) and self.managedFocusTimer == timer then
    self:_cancelManagedFocus()
    if hs.alert then hs.alert.show("10bucks: Could not focus the restored window. Try selecting it again.") end
  end
end

function Tenbucks:_focusManagedTarget(target)
  if not self.host or not self:_targetIsManaged(target) then return false, "stale-chooser-target" end
  local targetCore, window = self:_coreForManagedWindow(target.windowId, target.lease)
  local unplaced = self.focusHistory:unplacedTarget(target.windowId)
  if (window and window.lifecycle.appHidden) or (unplaced and unplaced.appHidden) then
    return false, "managed-window-hidden"
  end
  local restoring = window and window.lifecycle.minimized
  if (unplaced and unplaced.minimized) or (restoring and window.lifecycle.nativeFullscreen) then
    return false, "chooser-restoration-deferred"
  end
  if restoring then
    if self.workspace and self.workspace:state().switch.inFlight then return false, "desktop-switch-pending" end
    local exact = self.handleRegistry:target(target.windowId, target.lease)
    if not exact or exact.spaceId ~= target.spaceId then return false, "stale-chooser-target" end
    target = exact
    local pending = self.focusHistory:pending()
    if pending and pending.windowId == target.windowId and pending.spaceId == target.spaceId
      and pending.restoreLease == target.lease then return true end
  end
  -- A global target supersedes local requests in other scopes. Retire their
  -- reducer authority, not just the old native effect, before requesting focus.
  for _, core in pairs(self.cores or {}) do
    if core ~= targetCore or restoring then
      local accepted, failure = core:submit({ type = "FocusRequestCancelled", spaceId = core.spaceId })
      if not accepted then return false, failure end
    end
  end
  self:_stopManagedFocusTimer()
  self.focusHistory:request(target, restoring and target.lease or nil)
  local timer
  timer = hs.timer.doAfter(5, function()
    if self.managedFocusTimer ~= timer then return end
    self.managedFocusTimer = nil
    local pending = self.focusHistory:pending()
    if not self.started or not pending or pending.windowId ~= target.windowId or pending.spaceId ~= target.spaceId then return end
    self:_withEffectBatch(function() self:_cancelManagedFocus() end)
    self.host:observeFocus() -- reconcile actual state, never retry the effect
    if hs.alert then hs.alert.show("10bucks: Window focus was not confirmed. Visit the window and try again.") end
  end)
  self.managedFocusTimer = timer
  local handle = self.handleRegistry:resolve(target)
  if not handle then self:_cancelManagedFocus(); return false, "stale-chooser-target" end
  if restoring then
    local function authorized() return self.managedFocusTimer == timer and self:_targetIsManaged(target) end
    if self.host:unminimize(handle, target.lease, target.spaceId, authorized) then return true end
    if self.managedFocusTimer == timer then self:_cancelManagedFocus() end
    return false, "managed-restore-failed"
  end
  if targetCore then
    local accepted, failure = targetCore:submit({ type = "FocusTarget", windowId = target.windowId })
    if not accepted then self:_cancelManagedFocus(); return false, failure end
    if targetCore == self.core and not self.suspended and target.spaceId == targetCore.spaceId
      and not window.lifecycle.nativeFullscreen then return true end
  end
  -- Use the same targeted post-effect confirmation path as Core focus intents;
  -- hs.window:focus() may not emit an unchanged-focus AX callback.
  if not self:_targetIsManaged(target) then self:_cancelManagedFocus(); return false, "stale-chooser-target" end
  local ok, requested = pcall(self.host.focus, self.host, handle, target.lease, target.spaceId,
    (window and window.lifecycle.nativeFullscreen) or unplaced ~= nil,
    unplaced and unplaced.target.spaceId) -- Native focus may change Spaces.
  if not ok or requested == nil or not self:_targetIsManaged(target) then
    self:_cancelManagedFocus(); return false, "managed-focus-failed"
  end
  return true
end

function Tenbucks:_chooseWindow(choice)
  if not self.started or (type(choice.lease) ~= "number" and type(choice.lease) ~= "string") then
    return false, "stale-chooser-target"
  end
  local target = self.handleRegistry:target(choice.windowId, choice.lease)
  if not target or not self:_targetIsManaged(target) then return false, "stale-chooser-target" end
  local core, window = self:_coreForManagedWindow(target.windowId, target.lease)
  local unplaced = self.focusHistory:unplacedTarget(target.windowId)
  if not window and not unplaced then return false, "stale-chooser-target" end
  local operation = self.workspace and self.workspace:state().switch.inFlight
  if operation then
    if not operation.creating then return false, "desktop-switch-pending" end
    if core ~= self.core or self.suspended or not window or window.lifecycle.nativeFullscreen then
      return false, "desktop-creation-pending"
    end
  end
  return self:_withEffectBatch(function() return self:_focusManagedTarget(target) end)
end

function Tenbucks:_submitCommand(command)
  if command.type == "OpenWindowChooser" then
    if not self.started then return false, "not-started" end
    if not self.windowChooser then
      self.windowChooser = NativeChooser.new(hs, function(query) return WindowChooser.filter(self.chooserRows, query) end,
        function(choice) return self:_chooseWindow(choice) end)
    end
    self.windowChooser:show(); return true
  end
  local operation = self.workspace and self.workspace:state().switch.inFlight
  if operation and operation.creating and (command.type == "CreateRegularDesktop" or command.type == "FocusRegularPosition"
    or command.type == "FocusRelativeRegular" or command.type == "FocusPreviousDesktop") then
    return false, "desktop-creation-pending"
  end
  if command.type == "CreateRegularDesktop" and operation then return false, "desktop-switch-pending" end
  if command.type == "FocusRegularPosition" or command.type == "FocusRelativeRegular" or command.type == "FocusPreviousDesktop" or command.type == "CreateRegularDesktop" then
    return self:_withEffectBatch(function()
      self:_cancelManagedFocus()
      self:_contextChanged(Context.snapshot(hs, self.config.builtInDisplayUUID))
      return self.workspace:submit(command)
    end)
  end
  if command.type == "FocusManagedPrevious" then
    if operation then
      if not operation.creating then return false, "desktop-switch-pending" end
      local target = self.focusHistory:previous(function(candidate) return self:_targetIsManaged(candidate) end)
      local targetCore = target and self.cores[target.spaceId]
      local window = targetCore and targetCore:state().manager.windows[target.windowId]
      if not target or targetCore ~= self.core or self.suspended or not window or window.lifecycle.nativeFullscreen then
        return false, "desktop-creation-pending"
      end
    end
    return self:_withEffectBatch(function() return self:_focusManagedPrevious() end)
  end
  if self.suspended or not self.core then return false, "native-fullscreen-has-no-regular-layout" end
  if command.type == "MoveFocusedToOther" then
    local actual = self.actualPresentation or {}
    local lease = self.host and self.host:focusedManagedLease(actual.id, actual.presentationResource)
    local owner, window
    if lease then owner, window = self:_coreForManagedWindow(actual.id, lease) end
    if owner ~= self.core or not window or not Model.isAvailable(window) then return false, "actual-focus-is-not-managed" end
    command = { type = command.type, memberId = window.id }
  end
  return self:_withEffectBatch(function() return self.core:submit(command) end)
end

function Tenbucks:_startHost(context)
  -- Context and Core exist before bootstrap can synchronously publish facts.
  self.context = context
  local host, adapter
  local records = {} -- Host-scoped primitive state; Rules.reduce is its only writer.
  local ok, err = pcall(function()
    host = Host.new(hs, context, self.instrumentation, self.handleRegistry, self.nativeValidity, self.nativeDiscovery):start()
    local native = {
      subscribeApplications = function(callback) return host:subscribeApplications(callback) end,
      subscribeExistingWindows = function(callback, bootstrap) return host:subscribeExistingWindows(callback, bootstrap) end,
      subscribeWindow = function(handle, callback) return host:subscribeWindow(handle, callback) end,
      probeReadiness = function(id, callback) return host:probeReadiness(id, callback) end,
      releaseWindow = function(id, lease) return host:releaseWindow(id, lease) end,
      releaseApplication = function(pid, lease) return host:releaseApplication(pid, lease) end,
      decide = function(event)
        local prior = Rules.action(records, event.id, event.resource, event.appResource, event.application.pid)
        if records[event.id] and not prior then return { action = "defer", reason = "conflicting-resource" } end
        event.decision = prior and { action = prior } or Rules.filter(event.metadata, self.config.rules, event.decision)
        records = Rules.reduce(records, event)
        return event.decision
      end,
      current = function(...) return host:current(...) end,
      appCurrent = function(...) return host:appCurrent(...) end,
      committed = function(event)
        local route = self.handleRegistry:target(event.id, event.resource)
        return route ~= nil and self:_targetIsManaged(route)
      end,
      enableManaged = function(...) return host:enableManaged(...) end,
      record = function(kind) self:_record(kind) end,
      recordEvent = function(eventType) if self.instrumentation then self.instrumentation:recordEvent(eventType) end end,
    }
    adapter = Windows.new({ native = native,
      withTransaction = function(work) return self:_withEffectBatch(work) end,
      sink = function(event)
      if (event.type == "ApplicationHidden" or event.type == "ApplicationUnhidden" or event.type == "ApplicationTerminated")
        and not host:appCurrent(event.pid, event.resource) then return false end
      local observed = event.id and records[event.id]
      local authorized = observed and observed.resource == event.resource
      records = Rules.reduce(records, event)
      if event.type == "WindowReady" and event.decision.action == "exclude" then return true end
      if authorized and observed.action == "exclude" then
        self.actualPresentation = Bar.reduceActual(self.actualPresentation, event)
        self:_publishBar(); return true
      end
      return self:_submitEvent(event, event.id and adapter:handleForId(event.id))
    end })
    self.host, self.windows = host, adapter
    for _, core in pairs(self.cores or {}) do
      local observedCore = core
      observedCore.observer = function(intents, version) self:_observeCoreIntents(observedCore, intents, version) end
    end
    adapter:start() -- one runtime-lifetime observer set; initial full discovery.
    -- Bootstrap readiness may precede the only focus observation; sample once
    -- without requesting focus.
    if host.started and adapter.started then host:observeFocus() end
  end)
  if not ok then
    if adapter then adapter:stop() end
    if host then host:stop() end
    self.host, self.windows = nil, nil
    error(err, 0)
  end
end

function Tenbucks:_workspaceFact(context)
  self.workspaceRevision = (self.workspaceRevision or 0) + 1
  local fact = { type = context.workspaceEventType or "RegularTopologyObserved", displayId = context.displayId, revision = self.workspaceRevision,
    nativeSpaceId = context.nativeSpaceId, nativeSpaceType = context.nativeSpaceType,
    regularSpaceIds = context.regularSpaceIds or context.regularPositions, fullSpaceIds = context.fullSpaceIds }
  for _, key in ipairs({ "generation", "sourceId", "sourceType", "destinationId" }) do fact[key] = context[key] end
  return fact
end

function Tenbucks:_retireSpace(spaceId)
  local core = self.cores and self.cores[spaceId]
  if not core then return end
  local windows = {}
  for _, window in pairs(core:state().manager.windows) do windows[#windows + 1] = window end
  self.focusHistory:invalidateSpace(spaceId, windows)
  self:_submitCore(core, { type = "FocusRequestCancelled", spaceId = spaceId })
  self.cores[spaceId] = nil
  if self.core == core then self.core = nil end
end

function Tenbucks:_beginContext(context)
  self.cores = {}
  self.workspaceRevision = 0
  self.workspace = Runtime.new({ initialState = WorkspaceSwitch.initial(self:_workspaceFact(context)),
    reduce = WorkspaceSwitch.reduce, validate = WorkspaceSwitch.validate, deriveIntents = WorkspaceSwitch.deriveIntents,
    observeIntents = function(intents)
      for _, intent in ipairs(intents) do if intent.kind == "RegularSpaceRemoved" then self:_retireSpace(intent.spaceId) end end
      local entry = { workspace = true, intents = intents }
      if self.effectBatch then self.effectBatch[#self.effectBatch + 1] = entry end
    end })
  self.spaces = Spaces.new(hs, { current = function() return self.workspace and self.workspace:state().switch.inFlight end,
    snapshot = function() return Context.snapshot(hs, self.config.builtInDisplayUUID) end,
    contextChanged = function(context) return self:_contextChanged(context) end,
    submit = function(event)
      if self.workspace then self:_withEffectBatch(function() assert(self.workspace:submit(event)) end) end
    end })
  if context.regularSpaceId then
    self.core = newCore(context, self.config)
    self.cores[context.regularSpaceId] = self.core
  end
  self.contextEpoch = (self.contextEpoch or 0) + 1
  self.originContext, self.suspended = context, context.regularSpaceId == nil
  self:_startHost(context)
end

-- A confirmed regular-Space activation switches the single native host to that
-- Space's retained pure Core. A newly observed Space gets one bootstrap; a
-- returning Space reuses its existing order, selection, and layout state.
function Tenbucks:_contextChanged(context)
  return self:_withEffectBatch(function()
    if self.spaces then context = self.spaces:observe(context) end
    if self.workspace then assert(self.workspace:submit(self:_workspaceFact(context))) end
    local previous = self.context and self.context.regularSpaceId
    if previous and previous ~= context.regularSpaceId then
      local pending = self.focusHistory:pending()
      local requestedWindow
      if pending then local _; _, requestedWindow = self:_coreForManagedWindow(pending.windowId) end
      if pending and pending.spaceId == previous and not (requestedWindow and requestedWindow.lifecycle.nativeFullscreen) then
        self:_stopManagedFocusTimer()
        self.focusHistory:cancel()
      end
      local old = self.cores[previous]
      if old then self:_submitCore(old, { type = "FocusRequestCancelled", spaceId = previous }) end
    end
    self:_applyContext(context)
  end)
end

function Tenbucks:_applyContext(context)
  if not self.context or self.context.regularSpaceId ~= context.regularSpaceId then
    self.contextEpoch = (self.contextEpoch or 0) + 1
  end
  if not context.regularSpaceId then
    self.context, self.suspended = context, true
    if self.host then self.host:setContext(context); self.host:observeFocus() end
    self:_publishBar()
    return
  end
  if self.context and context.regularSpaceId == self.context.regularSpaceId and not self.suspended then
    self.context = context
    if self.host then self.host:setContext(context) end
    if self.core then
      self.core:setWorkArea(context.workArea)
      self.core:submit({ type = "Reflow" })
    end
    self:_publishBar()
    return
  end
  self.context = context
  self.core = self:_coreForSpace(context.regularSpaceId)
  self.suspended = false
  -- Geometry commits before discovery can derive any active frames.
  self.core:setWorkArea(context.workArea)
  self.host:setContext(context)
  -- Retained handles plus relevant WindowServer owner hints replace global
  -- application enumeration on ordinary activation. Unknown readiness defers.
  self.windows:discover()
  self.host:observeFocus()
  self.core:submit({ type = "Reflow" })
  self:_publishBar()
  local pending = self.focusHistory:pending()
  if pending and pending.spaceId == context.regularSpaceId and self:_targetIsManaged(pending) then
    self.core:submit({ type = "FocusTarget", windowId = pending.windowId })
  end
end

function Tenbucks:start()
  if self.started then return self end
  self.instrumentation = self.config.canaryInstrumentation and CanaryInstrumentation.new() or nil
  self.canaryObservedVersion = 0
  if self.instrumentation then self.instrumentation:setActiveTimers(0) end
  local bindings, contextSubscription
  self.starting = true
  local ok, err = pcall(function()
    -- Prepare the required image before any native observation or bindings;
    -- injected worker factories may omit this optional preparation operation.
    local validity = self.nativeValidity or require("lib.macos.ax_validity")
    if validity.prepare then validity.prepare() end
    local discovery = self.nativeDiscovery or require("lib.macos.regular_discovery")
    if discovery.prepare then discovery.prepare() end
    if not self.starting then return end
    local style = hs.host and hs.host.interfaceStyle and hs.host.interfaceStyle() or nil
    self.darkAppearance = style == "Dark" -- appearance-change notification remains Hypothesis; no polling.
    self.bar = NativeBar.new(hs, function(kind)
      if kind == "appearance" then
        local current = hs.host and hs.host.interfaceStyle and hs.host.interfaceStyle() or nil
        self.darkAppearance = current == "Dark" -- Hypothesis pending manual theme-toggle evidence.
      end
      self:_publishBar()
    end):start()
    self:_beginContext(Context.snapshot(hs, self.config.builtInDisplayUUID))
    if not self.starting then return end
    self:_publishBar()
    bindings = Bindings.bind(hs, function(command) return self:_submitCommand(command) end, self.config.hotkeys)
    if not self.starting then Bindings.delete(bindings); return end
    contextSubscription = Context.watch(hs, self.config.builtInDisplayUUID, function(context)
      if self.started then self:_contextChanged(context) end
    end, function(context)
      if self.spaces then self.spaces:dockBoundary(context) end
    end)
  end)
  if not ok then
    if contextSubscription then contextSubscription.detach() end
    -- Use the ordinary whole-scope stop path: bootstrap may already have
    -- committed routes/history/presentation before a later binding failure.
    Bindings.delete(bindings)
    self:stop()
    error(err, 0)
  end
  if not self.starting then
    if contextSubscription then contextSubscription.detach() end
    Bindings.delete(bindings)
    self:stop(); return self
  end
  self.starting = nil
  self.contextSubscription, self.hotkeyBindings, self.started = contextSubscription, bindings, true
  return self
end

function Tenbucks:stop()
  self.started, self.starting = false, nil
  if self.managedFocusTimer then self.managedFocusTimer:stop(); self.managedFocusTimer = nil end
  if self.contextSubscription then self.contextSubscription.detach() end
  self.contextSubscription = nil
  if self.workspace then self.workspace:submit({ type = "WorkspaceSwitchStopped" }) end
  if self.spaces then self.spaces:stop() end
  self.spaces, self.workspace, self.effectBatch = nil, nil, nil
  self:_stopScope()
  if self.bar then self.bar:stop(); self.bar = nil end
  self.originContext = nil
  self.canaryObservedVersion = nil
  if self.windowChooser then self.windowChooser:stop(); self.windowChooser = nil end
  self.chooserRows = {}
  self.focusHistory = FocusHistory.new()
  self.actualPresentation = {}
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
