-- Concrete direct-AX host. Application callbacks deliver AX elements; only
-- element:asHSWindow() converts one to hs.window. Reverse conversion is used
-- exclusively to inspect an hs.window's AX metadata/watchers.
local Host = {}
Host.__index = Host

local function call(object, method, ...)
  if not object or type(object[method]) ~= "function" then return nil end
  local ok, value = pcall(object[method], object, ...)
  return ok and value or nil
end

local function asWindow(element)
  if not element then return nil end
  -- Verified on Hammerspoon 1.1.1 with Ghostty: application:newWatcher()
  -- delivers hs.window userdata for AXWindowCreated/AXFocusedWindowChanged.
  if type(element.id) == "function" and type(element.newWatcher) == "function" then return element end
  if type(element.asHSWindow) ~= "function" then return nil end
  local ok, window = pcall(element.asHSWindow, element)
  return ok and window or nil
end

local function moduleCall(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, value = pcall(fn, ...)
  if ok then return value end
  return nil
end

local function booleanOrNil(value)
  if type(value) == "boolean" then return value end
  return nil
end

function Host.new(hs, context, instrumentation, handleRegistry)
  return setmetatable({ hs = hs, context = context, instrumentation = instrumentation, handleRegistry = handleRegistry,
    generation = 0, started = false, owned = {}, appOwned = {}, handles = {}, frames = {} }, Host)
end

function Host:_record(kind)
  if self.instrumentation then self.instrumentation:record(kind) end
end

function Host:_detach(record)
  if not record or record.detached then return end
  record.detached = true
  if record.watcher and record.watcher.stop then pcall(record.watcher.stop, record.watcher) end
end

function Host:_own(watcher, pid)
  local record = { watcher = watcher }
  self.owned[#self.owned + 1] = record
  if pid then
    self.appOwned[pid] = self.appOwned[pid] or {}
    self.appOwned[pid][#self.appOwned[pid] + 1] = record
  end
  return { detach = function() self:_detach(record) end }
end

-- Register before start: several native watcher APIs may have allocated a live
-- observer even when start reports an error.
function Host:_startOwned(watcher, pid, events)
  local subscription = self:_own(watcher, pid)
  local ok, err = pcall(watcher.start, watcher, events)
  if not ok then subscription.detach(); error(err, 0) end
  return subscription
end

function Host:_forget(id)
  local record = self.handles[id]
  self.handles[id], self.frames[id] = nil, nil
  if self.handleRegistry then self.handleRegistry:forget(id, record and record.handle) end
end

function Host:_forgetPid(pid)
  for id, record in pairs(self.handles) do
    if record.pid == pid then self:_forget(id) end
  end
end

function Host:_remember(window, confirmedSpace)
  local id, app = call(window, "id"), call(window, "application")
  local pid = call(app, "pid")
  if id ~= nil and pid ~= nil then
    self.handles[id] = { handle = window, pid = pid }
    if self.handleRegistry then
      if confirmedSpace then self.handleRegistry:remember(id, self.context.regularSpaceId, window, pid)
      else self.handleRegistry:refresh(id, window, pid) end
    end
  end
end

function Host:_regularOwner(id)
  local spaces = self.hs.spaces
  self:_record("targetedOwnershipQueries")
  local owners = spaces and moduleCall(spaces.windowSpaces, id)
  if type(owners) ~= "table" or #owners ~= 1 or owners[1] ~= self.context.regularSpaceId then return false end
  if type(spaces.spaceType) == "function" and moduleCall(spaces.spaceType, owners[1]) ~= "user" then return false end
  return true
end

function Host:_metadata(window, origin)
  local app, id = call(window, "application"), call(window, "id")
  local pid = call(app, "pid")
  local element = self.hs.axuielement.windowElement(window)
  if id == nil or pid == nil or not element then return nil end
  local modal = moduleCall(element.attributeValue, element, "AXModal")
  local movable = moduleCall(element.isAttributeSettable, element, "AXPosition")
  local resizable = moduleCall(element.isAttributeSettable, element, "AXSize")
  return {
    id = id, application = { pid = pid, bundleID = call(app, "bundleID"), name = call(app, "name") },
    title = call(window, "title"), displayId = self.context.displayId, spaceId = self.context.regularSpaceId,
    role = call(window, "role"), subrole = call(window, "subrole"),
    modal = booleanOrNil(modal),
    movable = booleanOrNil(movable),
    resizable = booleanOrNil(resizable),
    selfProcess = pid == self.hs.processInfo.processID, origin = origin,
  }
end

function Host:_ready(window, origin, callback, membershipSet)
  local id = call(window, "id")
  if id == nil or (membershipSet and not membershipSet[id]) or (not membershipSet and not self:_regularOwner(id)) then return end
  local metadata = self:_metadata(window, origin)
  if metadata then
    self:_remember(window, true)
    callback({ kind = "ready", metadata = metadata, handle = window })
  end
end

function Host:subscribeWindow(window, callback)
  local id, generation = call(window, "id"), self.generation
  -- Verified by read-only installed-runtime query: focused hs.window.newWatcher
  -- is a function, its AX element's newWatcher is nil, and application.newWatcher
  -- is a function. Installed hs.window.filter source also calls win:newWatcher.
  -- The AX element is retained only for metadata; wrapper source is not evidence
  -- that a different userdata exposes the same method (Canary A proved it does not).
  if not id or type(window.newWatcher) ~= "function" then return { detach = function() end } end
  local knownFullscreen = call(window, "isFullScreen")
  local watcher = window:newWatcher(function(_, event)
    if not self.started or generation ~= self.generation then return end
    local kinds = { AXUIElementDestroyed = "destroyed", AXWindowMiniaturized = "minimized", AXWindowDeminiaturized = "restored", AXTitleChanged = "titleChanged" }
    if event == "AXUIElementDestroyed" then self:_forget(id); callback({ kind = "destroyed", id = id })
    elseif event == "AXWindowMiniaturized" or event == "AXWindowDeminiaturized" then
      self.frames[id] = nil; callback({ kind = kinds[event], id = id })
    elseif event == "AXWindowResized" then
      local fullscreen = call(window, "isFullScreen")
      if type(fullscreen) == "boolean" and fullscreen ~= knownFullscreen then
        knownFullscreen = fullscreen; self.frames[id] = nil; callback({ kind = fullscreen and "enteredNativeFullscreen" or "exitedNativeFullscreen", id = id })
      end
    elseif kinds[event] == "titleChanged" then callback({ kind = "titleChanged", id = id, title = call(window, "title") or "" })
    elseif kinds[event] then callback({ kind = kinds[event], id = id }) end
  end)
  return self:_startOwned(watcher, call(call(window, "application"), "pid"),
    { "AXUIElementDestroyed", "AXWindowMiniaturized", "AXWindowDeminiaturized", "AXTitleChanged", "AXWindowResized" })
end

function Host:_attachApp(app, callback)
  local pid, generation = call(app, "pid"), self.generation
  -- Read-only runtime preflight separately requires application.newWatcher on
  -- the focused app. An ordinary running/background application may still not expose an AX watcher.
  -- Its absence is uncertainty: defer it without disturbing other apps.
  local ok, watcher = pcall(app.newWatcher, app, function(element, event)
    if not self.started or generation ~= self.generation then return end
    local window = asWindow(element)
    if not window then return end
    if event == "AXWindowCreated" then self:_ready(window, "created", callback)
    elseif event == "AXFocusedWindowChanged" then
      self:_remember(window)
      callback({ kind = "focus", id = call(window, "id"), title = call(window, "title"), applicationName = call(app, "name") })
    end
  end)
  if not ok or not watcher then return nil end
  return self:_startOwned(watcher, pid, { "AXWindowCreated", "AXFocusedWindowChanged" })
end

function Host:subscribeApplications(callback)
  local generation = self.generation
  local watcher = self.hs.application.watcher.new(function(_, event, app)
    if not self.started or generation ~= self.generation or not app then return end
    local pid = call(app, "pid")
    if event == self.hs.application.watcher.launched then
      if self.windowCallback then
        -- One launch-scoped scan closes the attach-vs-first-window race. This
        -- is event-triggered and app-local: no timer, global rescan, or poll.
        self:_attachApp(app, self.windowCallback)
        local ok, windows = pcall(app.allWindows, app)
        if ok and type(windows) == "table" then
          for _, window in ipairs(windows) do
            self:_ready(window, "targetedReadiness", self.windowCallback)
          end
        end
      end
    elseif event == self.hs.application.watcher.activated then
      -- Mouse activation can occur without the application's AX focused-window
      -- callback reaching us. One app-local read immediately normalizes actual
      -- focus so the first h/l/' command acts from native reality.
      local window = call(app, "focusedWindow")
      if window and self.windowCallback then
        self:_remember(window)
        self.windowCallback({ kind = "focus", id = call(window, "id"),
          title = call(window, "title"), applicationName = call(app, "name") })
      end
    elseif event == self.hs.application.watcher.terminated then
      for _, record in ipairs(self.appOwned[pid] or {}) do self:_detach(record) end
      self.appOwned[pid] = nil; self:_forgetPid(pid)
      if self.handleRegistry then self.handleRegistry:forgetPid(pid) end
      callback({ kind = "terminated", pid = pid })
    elseif event == self.hs.application.watcher.hidden then callback({ kind = "hidden", pid = pid })
    elseif event == self.hs.application.watcher.unhidden then callback({ kind = "unhidden", pid = pid }) end
  end)
  return self:_startOwned(watcher)
end

function Host:subscribeExistingWindows(callback)
  self.windowCallback = callback
  local members = {}
  self:_record("bootstrapSpaceQueries")
  -- One relevant active-Space membership snapshot; absence only defers admission.
  for _, id in ipairs(self.hs.spaces.windowsForSpace(self.context.regularSpaceId) or {}) do members[id] = true end
  self:_record("bootstrapApplicationQueries")
  for _, app in ipairs(self.hs.application.runningApplications()) do
    self:_attachApp(app, callback)
    -- Enumeration is bootstrap-only. Failure for one app is non-destructive
    -- and must not prevent subscriptions/bootstrap for its peers.
    local ok, windows = pcall(app.allWindows, app)
    if ok and type(windows) == "table" then
      for _, window in ipairs(windows) do self:_ready(window, "bootstrap", callback, members) end
    end
  end
  return { detach = function() end }
end

function Host:probeReadiness(id, callback)
  local record = self.handles[id]
  if record and self:_regularOwner(id) then callback(self:_metadata(record.handle, "targetedReadiness"), record.handle) else callback(nil) end
  return { detach = function() end }
end

function Host:start()
  if self.started then return self end
  self.generation = self.generation + 1; self.started = true; return self
end
function Host:stop()
  if not self.started then return self end
  self.started = false; self.generation = self.generation + 1
  for _, record in ipairs(self.owned) do self:_detach(record) end
  self.owned, self.appOwned, self.handles, self.frames, self.windowCallback = {}, {}, {}, {}, nil
  return self
end

function Host:execute(adapter, intents)
  for _, intent in ipairs(intents) do
    local window = adapter:handleForId(intent.windowId)
    if not window and self.handleRegistry then
      window = self.handleRegistry:resolve({ windowId = intent.windowId, spaceId = intent.spaceId })
    end
    if window then self:_remember(window) end
    if window and intent.kind == "frame" then
      local actual = call(window, "frame")
      local previous = self.frames[intent.windowId]
      local same = actual and actual.x == intent.frame.x and actual.y == intent.frame.y and actual.w == intent.frame.w and actual.h == intent.frame.h
      self:_record("frameRequests")
      if not same and (actual or not previous or previous.x ~= intent.frame.x or previous.y ~= intent.frame.y or previous.w ~= intent.frame.w or previous.h ~= intent.frame.h) then
        window:setFrame(intent.frame, 0)
        self:_record("frameWrites")
      end
      self.frames[intent.windowId] = { x = intent.frame.x, y = intent.frame.y, w = intent.frame.w, h = intent.frame.h }
    elseif window and intent.kind == "focus" then
      self:_record("focusRequests")
      window:focus()
    end
  end
end

return Host
