-- Concrete direct-AX host. Creation callbacks can deliver hs.window wrappers
-- or AX elements; conversion and native handles stay here. Focus signals trigger
-- a current native focus read rather than treating their payload as global focus.
local Host = {}
Host.__index = Host

local function call(object, method, ...)
  if not object or type(object[method]) ~= "function" then return nil end
  local ok, value = pcall(object[method], object, ...)
  if ok then return value end
  return nil
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

function Host.new(hs, context, instrumentation, handleRegistry, nativeValidity, nativeDiscovery)
  return setmetatable({ hs = hs, context = context, instrumentation = instrumentation, handleRegistry = handleRegistry,
    nativeDiscovery = nativeDiscovery, nativeValidity = nativeValidity, validitySerial = 0, generation = 0, serial = 0, started = false, owned = {}, appResources = {}, handles = {}, managedObservers = {}, frames = {}, readiness = {} }, Host)
end

function Host:_record(kind)
  if self.instrumentation then self.instrumentation:record(kind) end
end

function Host:_detach(record)
  if not record or record.detached then return end
  record.detached = true
  self.owned[record] = nil
  if record.watcher and record.watcher.stop then pcall(record.watcher.stop, record.watcher) end
end

function Host:_own(watcher)
  local record = { watcher = watcher }
  self.owned[record] = true
  return { detach = function() self:_detach(record) end }
end

-- Register before start: several native watcher APIs may have allocated a live
-- observer even when start reports an error.
function Host:_startOwned(watcher, events)
  local generation = self.generation
  local subscription = self:_own(watcher)
  if not self.started then subscription.detach(); return subscription end
  local ok, err = pcall(watcher.start, watcher, events)
  if not ok then subscription.detach(); error(err, 0) end
  if not self.started or self.generation ~= generation then subscription.detach() end
  return subscription
end

function Host:_nextLease()
  self.serial = self.serial + 1
  return self.serial
end

function Host:_forget(id, lease)
  local record = self.handles[id]
  if not record or record.lease ~= lease then return false end
  if self.validityTarget and self.validityTarget.record == record then self:_cancelValidity() end
  record.active = false
  if record.subscription then record.subscription.detach() end
  self.handles[id], self.frames[id], self.managedObservers[id] = nil, nil, nil
  if self.handleRegistry then self.handleRegistry:forget(id, record.handle, record.lease) end
  return true
end

function Host:_forgetPid(pid, appLease)
  for id, record in pairs(self.handles) do
    if record.pid == pid and record.appLease == appLease then self:_forget(id, record.lease) end
  end
  if self.handleRegistry then self.handleRegistry:forgetPid(pid, appLease) end
end

-- App identity is accepted independently of optional AX watcher construction.
-- A current conflicting same-PID wrapper is deferred rather than replacing the
-- record. This supplies every admitted window a non-nil app lease even when
-- the application watcher is unavailable or focus is observed first.
function Host:_acceptApp(app)
  local pid = call(app, "pid")
  if pid == nil then return nil end
  local existing = self.appResources[pid]
  if existing then
    if existing.active and existing.app == app then return existing end
    return nil
  end
  local record = { pid = pid, app = app, lease = self:_nextLease(), active = true }
  self.appResources[pid] = record
  return record
end

-- Repeated wrappers are accepted only when HS equality says they name the
-- already observed resource. A different wrapper for a current native ID is
-- ambiguous: keep the old lifetime and defer rather than replacing/deleting it.
function Host:_remember(window)
  local id, app = call(window, "id"), call(window, "application")
  local pid = call(app, "pid")
  if id == nil or pid == nil then return nil end
  local appRecord = self:_acceptApp(app)
  if not appRecord then return nil end
  local existing = self.handles[id]
  if existing then
    if existing.active and existing.pid == pid and existing.handle == window then return existing end
    return nil
  end
  local record = { handle = window, element = moduleCall(self.hs.axuielement.windowElement, window),
    pid = pid, appLease = appRecord.lease, lease = self:_nextLease(), active = true }
  self.handles[id] = record
  return record
end

function Host:_owner(id)
  local spaces = self.hs.spaces
  self:_record("targetedOwnershipQueries")
  local owners = spaces and moduleCall(spaces.windowSpaces, id)
  if type(owners) ~= "table" or #owners ~= 1 then return nil end
  local kind = moduleCall(spaces.spaceType, owners[1])
  -- Persistent observation routes confirmed regular ownership to its actual
  -- retained scope, never merely to the currently active context.
  if kind == "fullscreen" or kind == "user" then return owners[1], kind end
end

function Host:_metadata(window, origin, spaceId, spaceType)
  local app, id = call(window, "application"), call(window, "id")
  local pid = call(app, "pid")
  local nativeFullscreen = booleanOrNil(call(window, "isFullScreen"))
  local minimized = booleanOrNil(call(window, "isMinimized"))
  local appHidden = booleanOrNil(call(app, "isHidden"))
  if minimized == nil or appHidden == nil then return nil end
  if (spaceType == "fullscreen" and nativeFullscreen ~= true)
    or (spaceType == "user" and nativeFullscreen == true) then return nil end
  local element = self.hs.axuielement.windowElement(window)
  if id == nil or pid == nil or not element then return nil end
  local modal = moduleCall(element.attributeValue, element, "AXModal")
  local movable = moduleCall(element.isAttributeSettable, element, "AXPosition")
  local resizable = moduleCall(element.isAttributeSettable, element, "AXSize")
  return {
    id = id, application = { pid = pid, bundleID = call(app, "bundleID"), name = call(app, "name") },
    title = call(window, "title"), displayId = self.context.displayId, spaceId = spaceId, spaceType = spaceType,
    nativeFullscreen = nativeFullscreen,
    minimized = minimized, appHidden = appHidden,
    role = call(window, "role"), subrole = call(window, "subrole"),
    modal = booleanOrNil(modal),
    movable = booleanOrNil(movable),
    resizable = booleanOrNil(resizable),
    selfProcess = pid == self.hs.processInfo.processID, origin = origin,
  }
end

function Host:_cancelReadiness(id)
  local token = self.readiness[id]
  if not token then return end
  self.readiness[id] = nil
  if token.timer then
    local timer = token.timer; token.timer = nil
    pcall(timer.stop, timer)
  end
end

function Host:_readinessAuthority(token, expected)
  local app, retained = self.appResources[token.pid], self.handles[token.id]
  return self.started and self.readiness[token.id] == token
    and self.generation == token.generation and self.context == token.context
    and app == token.appRecord and app.active and app.app == token.app
    and (not retained or (retained.active and retained.handle == token.window))
    and (not expected or (retained == expected and retained.lease == token.publishLease))
end

function Host:_readinessCurrent(token, expected)
  if not self:_readinessAuthority(token, expected) then return false end
  -- All potentially reentrant native reads precede the final pure authority
  -- check. Never use handles/app records captured before these reads.
  local id = call(token.window, "id")
  local app = call(token.window, "application")
  local valid = moduleCall(token.element and token.element.isValid, token.element)
  return id == token.id and app == token.app and valid ~= false
    and self:_readinessAuthority(token, expected)
end

-- Candidate lifetime is independent of provisional focus leases. A failed
-- focus probe may forget its handle without cancelling this creation token.
function Host:_creationReady(window, origin, callback)
  local id, app = call(window, "id"), call(window, "application")
  if id == nil then return end
  local old = self.readiness[id]
  if old and old.window == window and old.app == app then
    if origin == "created" then old.origin = "created" end
    return
  end
  self:_cancelReadiness(id)
  local record = self:_acceptApp(app)
  if not record then return end
  local token = { id = id, window = window, app = app, pid = record.pid, appRecord = record,
    generation = self.generation, context = self.context, attempts = 0, origin = origin,
    element = moduleCall(self.hs.axuielement.windowElement, window) }
  self.readiness[id] = token
  local attempt
  local function guardedAttempt()
    local ok, err = pcall(attempt)
    if not ok then
      if self.readiness[id] == token then self:_cancelReadiness(id) end
      error(err, 0)
    end
  end
  attempt = function()
    if not self:_readinessCurrent(token) then
      if self.readiness[id] == token then self:_cancelReadiness(id) end
      return
    end
    token.attempts = token.attempts + 1
    local outcome = self:_ready(window, token.origin, callback, nil, token)
    if self.readiness[id] ~= token then return end
    if not self:_readinessCurrent(token) then
      if self.readiness[id] == token then self:_cancelReadiness(id) end
      return
    end
    if outcome ~= "uncertain" or token.attempts >= 3 or not (self.hs.timer and self.hs.timer.doAfter) then
      self:_cancelReadiness(id); return
    end
    local timer, attemptNumber = nil, token.attempts
    timer = self.hs.timer.doAfter(0.1, function()
      if self.readiness[id] ~= token or token.timer ~= timer or token.attempts ~= attemptNumber then return end
      token.timer = nil
      guardedAttempt()
    end)
    if not timer then error("creation readiness timer allocation failed", 0) end
    if self.readiness[id] ~= token or not self:_readinessAuthority(token) then
      pcall(timer.stop, timer)
      if self.readiness[id] == token then self:_cancelReadiness(id) end
      return
    end
    token.timer = timer
  end
  guardedAttempt()
end

function Host:_ready(window, origin, callback, membershipSet, token)
  local id = call(window, "id")
  if id == nil or (membershipSet and not membershipSet[id]) then return "rejected" end
  if token and not self:_readinessCurrent(token) then return "rejected" end
  -- A complete discovery still enumerates a conflicting same-PID app, but it
  -- cannot reuse the retained app lifetime to admit that app's windows.
  if not self:_acceptApp(call(window, "application")) then return "rejected" end
  local spaceId, spaceType
  if membershipSet then spaceId, spaceType = self.context.regularSpaceId, "user"
  else spaceId, spaceType = self:_owner(id) end
  if not spaceId then return "uncertain" end
  if token and not self:_readinessCurrent(token) then return "rejected" end
  local metadata = self:_metadata(window, origin, spaceId, spaceType)
  if not metadata then return "uncertain" end
  if token and not self:_readinessCurrent(token) then return "rejected" end
  local record = self:_remember(window)
  if not record then return "rejected" end
  if token then
    token.publishLease = record.lease
    if not self:_readinessCurrent(token, record) then return "rejected" end
    -- No native operation between the pure authority check and publication.
  end
  -- Publication may defer; keep the same candidate identity and retry budget.
  local ok, accepted = pcall(callback, { kind = "ready", metadata = metadata, handle = window, resource = record.lease, appResource = record.appLease })
  if token and accepted ~= "uncertain" and self.readiness[id] == token then self:_cancelReadiness(id) end
  if not ok then error(accepted, 0) end
  if accepted == "excluded" then return "excluded" end
  return accepted == "uncertain" and "uncertain" or (accepted == false and "rejected" or "ready")
end

function Host:subscribeWindow(window, callback)
  local record = self:_remember(window)
  local id, generation = call(window, "id"), self.generation
  if not record or id == nil then return nil end
  if record.subscription then return record.subscription end
  if record.windowAttachment then return nil end
  -- Verified by read-only installed-runtime query: focused hs.window.newWatcher
  -- is a function, its AX element's newWatcher is nil, and application.newWatcher
  -- is a function. Installed hs.window.filter source also calls win:newWatcher.
  -- The AX element is retained only for metadata; wrapper source is not evidence
  -- that a different userdata exposes the same method (Canary A proved it does not).
  if not id or type(window.newWatcher) ~= "function" then return nil end
  local knownFullscreen = call(window, "isFullScreen")
  -- Attachment currentness is narrower than the accepted window lifetime. A
  -- watcher whose start failed may still deliver a queued callback after retry.
  local attachment = {}
  record.windowAttachment = attachment
  local ok, watcher = pcall(window.newWatcher, window, function(_, event)
    -- Aggregate raw delivery before resource guards, so acceptance can separate
    -- a missing native close signal from a stale callback rejected by us.
    if event == "AXUIElementDestroyed" then self:_record("rawWindowDestroyed") end
    if not self.started or generation ~= self.generation or not record.active or self.handles[id] ~= record
      or record.windowAttachment ~= attachment then
      if event == "AXUIElementDestroyed" then self:_record("staleWindowDestroyed") end
      return
    end
    local kinds = { AXUIElementDestroyed = "destroyed", AXWindowMiniaturized = "minimized", AXWindowDeminiaturized = "restored", AXTitleChanged = "titleChanged" }
    if event == "AXUIElementDestroyed" then
      local token = self.readiness[id]
      if token and token.window == window then self:_cancelReadiness(id) end
      -- The composition must reduce and route this authoritative fact before
      -- releaseWindow invalidates this lease and forgets its native handle.
      callback({ kind = "destroyed", id = id, resource = record.lease,
        presentationResource = self.presentationWindow == window and self.presentationLease or nil })
    elseif event == "AXWindowMiniaturized" or event == "AXWindowDeminiaturized" then
      if event == "AXWindowMiniaturized" and self.validityTarget and self.validityTarget.record == record then self:_cancelValidity() end
      self.frames[id] = nil; callback({ kind = kinds[event], id = id, resource = record.lease,
        presentationResource = self.presentationWindow == window and self.presentationLease or nil })
    elseif event == "AXWindowResized" then
      local fullscreen = call(window, "isFullScreen")
      if type(fullscreen) == "boolean" and fullscreen ~= knownFullscreen then
        if fullscreen and self.validityTarget and self.validityTarget.record == record then self:_cancelValidity() end
        knownFullscreen = fullscreen; self.frames[id] = nil; callback({ kind = fullscreen and "enteredNativeFullscreen" or "exitedNativeFullscreen", id = id, resource = record.lease,
          presentationResource = self.presentationWindow == window and self.presentationLease or nil })
      end
    elseif kinds[event] == "titleChanged" then callback({ kind = "titleChanged", id = id, title = call(window, "title") or "", resource = record.lease,
      presentationResource = self.presentationWindow == window and self.presentationLease or nil })
    elseif kinds[event] then callback({ kind = kinds[event], id = id, resource = record.lease,
      presentationResource = self.presentationWindow == window and self.presentationLease or nil }) end
  end)
  if not ok or not watcher then if record.windowAttachment == attachment then record.windowAttachment = nil end; return nil end
  local started, subscription = pcall(self._startOwned, self, watcher,
    { "AXUIElementDestroyed", "AXWindowMiniaturized", "AXWindowDeminiaturized", "AXTitleChanged", "AXWindowResized" })
  if not started then if record.windowAttachment == attachment then record.windowAttachment = nil end; error(subscription, 0) end
  if not self:current(id, record.lease, record.appLease, record.pid) or record.windowAttachment ~= attachment then subscription.detach(); return nil end
  local ownedSubscription = subscription
  subscription = { detach = function()
    if record.windowAttachment == attachment then
      record.windowAttachment = nil
      if self.managedObservers[id] and self.managedObservers[id].attachment == attachment then self.managedObservers[id] = nil end
      if record.subscription == subscription then record.subscription = nil end
    end
    ownedSubscription.detach()
  end }
  record.windowAttachment = attachment
  subscription.initialNativeFullscreen, subscription.resource = knownFullscreen, record.lease
  record.subscription = subscription
  -- A full lifecycle observer supersedes the focused-excluded title-only one.
  if self.presentationId == id and self.presentationWindow == window and self.presentationSubscription then
    self.presentationSubscription.detach()
    self.presentationSubscription = nil
  end
  self:_trackValidity()
  return subscription
end

function Host:_attachApp(app, callback)
  local generation = self.generation
  local record = self:_acceptApp(app)
  if not record then return nil end
  if record.subscription or record.appAttachment then return record end
  -- Read-only runtime preflight separately requires application.newWatcher on
  -- the focused app. An ordinary running/background application may still not expose an AX watcher.
  -- Its absence is uncertainty: defer it without disturbing other apps.
  local attachment = {}
  record.appAttachment = attachment
  local ok, watcher = pcall(app.newWatcher, app, function(element, event)
    if not self.started or generation ~= self.generation or not record.active or self.appResources[record.pid] ~= record
      or record.appAttachment ~= attachment then return end
    if event == "AXWindowCreated" then
      local window = asWindow(element)
      if window then self:_creationReady(window, "created", callback) end
    elseif event == "AXFocusedWindowChanged" then
      -- A missed close may no longer be the last presentation by the time
      -- focus signals arrive. Check only this event app's retained AX resources.
      self:_checkApplicationWindows(record.pid, record.lease)
      -- Payload is not global focus; sample independently after removal commits.
      self:observeFocus()
    end
  end)
  if not ok or not watcher then if record.appAttachment == attachment then record.appAttachment = nil end; return record end
  if not self.started or generation ~= self.generation or not record.active or self.appResources[record.pid] ~= record then pcall(watcher.stop, watcher); return nil end
  local started, subscription = pcall(self._startOwned, self, watcher, { "AXWindowCreated", "AXFocusedWindowChanged" })
  if not started then if record.appAttachment == attachment then record.appAttachment = nil end; error(subscription, 0) end
  if not self.started or generation ~= self.generation or not record.active or self.appResources[record.pid] ~= record then subscription.detach(); return nil end
  local ownedSubscription = subscription
  subscription = { detach = function()
    if record.appAttachment == attachment then
      record.appAttachment = nil
      if record.subscription == subscription then record.subscription = nil end
    end
    ownedSubscription.detach()
  end }
  record.appAttachment = attachment
  record.subscription = subscription
  return record
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
        local attached, record = pcall(self._attachApp, self, app, self.windowCallback)
        if not attached then record = self.appResources[call(app, "pid")] end
        if record then
          local ok, windows = pcall(app.allWindows, app)
          if ok and type(windows) == "table" then
            for _, window in ipairs(windows) do
              self:_creationReady(window, "targetedReadiness", self.windowCallback)
            end
          end
        end
      end
    elseif event == self.hs.application.watcher.activated then
      -- Application activation is not proof that its payload/window is globally
      -- focused; use the same global actual-focus boundary as AX callbacks.
      self:observeFocus()
    elseif event == self.hs.application.watcher.terminated then
      local record = self.appResources[pid]
      -- A deferred presentation may be a different same-PID source from the
      -- accepted app record. End only that presentation; never fan out a PID
      -- lifecycle fact to the retained app A.
      if self.presentationApp == app and not (record and record.active and record.app == app) then
        local id, presentationResource = self.presentationId, self.presentationLease
        self:_observePresentation(nil, nil, nil, nil)
        if id ~= nil and presentationResource ~= nil and self.windowCallback then
          self.windowCallback({ kind = "presentationEnded", id = id, presentationResource = presentationResource })
        end
      end
      -- The global watcher gives a PID, so require the delivered application
      -- object to equal the retained live resource. Mismatch is uncertainty;
      -- a later independent discovery may attach only after this lifetime ends.
      if record and record.active and record.app == app then
        for id, token in pairs(self.readiness) do if token.appRecord == record then self:_cancelReadiness(id) end end
        if self.presentationApp == app then self:_observePresentation(nil, nil, nil, nil) end
        callback({ kind = "terminated", pid = pid, resource = record.lease })
      end
    elseif event == self.hs.application.watcher.hidden then
      local target = self.validityTarget
      if target and target.appRecord.app == app then self:_cancelValidity() end
      local record = self.appResources[pid]
      if record and record.active and record.app == app then callback({ kind = "hidden", pid = pid, resource = record.lease }) end
    elseif event == self.hs.application.watcher.unhidden then
      local record = self.appResources[pid]
      if record and record.active and record.app == app then callback({ kind = "unhidden", pid = pid, resource = record.lease }) end
    end
  end)
  return self:_startOwned(watcher)
end

function Host:discoveryStatus()
  local s = self.startupDiscovery or { pending = false, complete = false, unresolvedCount = 0, reason = "not-started" }
  return { pending = s.pending, complete = s.complete, unresolvedCount = s.unresolvedCount, reason = s.reason }
end

function Host:_bootstrapRegular(callback)
  local factory = self.nativeDiscovery or require("lib.macos.regular_discovery")
  local generation, candidates, seen, missing = self.generation, {}, {}, {}
  self.startupDiscovery = { pending = true, complete = false, unresolvedCount = 0 }
  local topology = moduleCall(self.hs.spaces.allSpaces)
  local inventory = moduleCall(factory.inventory)
  if type(topology) ~= "table" or type(inventory) ~= "table" then
    self.startupDiscovery = { pending = false, complete = false, unresolvedCount = 0, reason = "inventory-unavailable" }
    return
  end
  local regular = {}
  for _, spaces in pairs(topology) do
    for _, space in ipairs(spaces) do
      local kind = moduleCall(self.hs.spaces.spaceType, space)
      if not kind then
        self.startupDiscovery = { pending = false, complete = false, unresolvedCount = 0, reason = "ownership-unavailable" }
        return
      end
      if kind == "user" then
        local ids = moduleCall(self.hs.spaces.windowsForSpace, space)
        if type(ids) ~= "table" then
          self.startupDiscovery = { pending = false, complete = false, unresolvedCount = 0, reason = "ownership-unavailable" }
          return
        end
        for _, id in ipairs(ids) do regular[id] = true end
      end
    end
  end
  for _, row in ipairs(inventory) do
    if regular[row.windowId] and row.pid ~= self.hs.processInfo.processID then
      candidates[row.windowId] = row
    end
  end
  self:_record("bootstrapApplicationQueries")
  for _, app in ipairs(self.hs.application.runningApplications()) do
    if not self.started or generation ~= self.generation then return end
    pcall(self._attachApp, self, app, callback)
    local ok, windows = pcall(app.allWindows, app)
    if ok and type(windows) == "table" then
      for _, window in ipairs(windows) do
        if not self.started or generation ~= self.generation then return end
        local id = call(window, "id")
        local candidate = candidates[id]
        if candidate and call(app, "pid") == candidate.pid then
          local outcome = self:_ready(window, "bootstrap", callback)
          seen[id] = outcome == "ready" or outcome == "excluded"
        end
      end
    end
  end
  local captured = {}
  for id, row in pairs(candidates) do
    if not seen[id] then
      missing[#missing + 1] = { pid = row.pid, windowId = id }
      captured[row.pid] = self.appResources[row.pid]
    end
  end
  -- Scheduling only: normal-level hints get the finite budget first. Every
  -- foreign regular candidate remains required, including higher-level rows.
  table.sort(missing, function(a, b)
    local normalA = candidates[a.windowId].layer == 0
    local normalB = candidates[b.windowId].layer == 0
    if normalA ~= normalB then return normalA end
    if a.pid ~= b.pid then return a.pid < b.pid end
    return a.windowId < b.windowId
  end)
  local function finish(count, reason)
    self.startupDiscovery = { pending = false, complete = count == 0 and not reason,
      unresolvedCount = count, reason = reason }
  end
  if #missing == 0 then finish(0); return end
  local job = moduleCall(factory.create, missing)
  if not self.started or generation ~= self.generation then
    if job then call(job, "cancel") end
    return
  end
  if not job then finish(#missing, "resolution-unavailable"); return end
  self.discoveryJob = job
  local clock = self.hs.timer and self.hs.timer.absoluteTime
    and function() return self.hs.timer.absoluteTime() / 1e9 end or os.clock
  local deadline, timer = clock() + 1, nil
  local function current()
    return self.started and generation == self.generation and self.discoveryJob == job
  end
  local function settle(count, reason)
    if not current() then return end
    if timer then pcall(timer.stop, timer); timer = nil end
    call(job, "cancel")
    if not current() then return end
    self.discoveryJob, self.startupTimer = nil, nil
    finish(count, reason)
    if count == 0 and not reason then self:observeFocus() end
  end
  local poll
  poll = function()
    if not current() then return end
    self.startupTimer, timer = nil, nil
    local ok = pcall(function()
      if clock() >= deadline then settle(#missing, "resolution-timeout"); return end
      local result = job:poll()
      if not current() then return end
      if result and result.done then
        local unresolved = #missing
        for _, row in ipairs(result.results or {}) do
          if not current() then return end
          local candidate, app = candidates[row.windowId], captured[row.pid]
          local window = candidate and candidate.pid == row.pid and not seen[row.windowId] and asWindow(row.ax)
          if not current() then return end
          if window and app and app.active and self.appResources[row.pid] == app
            and call(window, "id") == row.windowId and call(window, "application") == app.app then
            if not current() then return end
            local outcome = self:_ready(window, "bootstrap", callback)
            if outcome == "ready" or outcome == "excluded" then
              seen[row.windowId] = true; unresolved = unresolved - 1
            end
          end
        end
        settle(unresolved, unresolved > 0 and "unresolved-candidates" or nil)
      else
        timer = assert(self.hs.timer.doAfter(0.01, poll), "discovery timer unavailable")
        if current() then self.startupTimer = timer else pcall(timer.stop, timer) end
      end
    end)
    if not ok then settle(#missing, "resolution-failed") end
  end
  poll()
end

function Host:subscribeExistingWindows(callback, bootstrap, attempt)
  self.windowCallback = callback
  if bootstrap ~= false then
    self:_bootstrapRegular(callback)
    return { detach = function() end }
  end
  local members
  if self.context.regularSpaceId then
    members = {}
    self:_record("bootstrapSpaceQueries")
    -- One relevant regular-Space snapshot; absence only defers admission.
    for _, id in ipairs(self.hs.spaces.windowsForSpace(self.context.regularSpaceId) or {}) do members[id] = true end
  end
  if bootstrap == false then
    if not members then return { detach = function() end } end
    local unknown = {}
    for id in pairs(members) do
      local record = self.handles[id]
      if record and record.active then
        self:_ready(record.handle, "bootstrap", callback, members)
      else unknown[id] = true end
    end
    if next(unknown) then
      local unresolved = false
      -- WindowServer rows are discovery hints only. Missing rows never remove
      -- members or imply death; AX readiness independently confirms admission.
      self:_record("discoveryOwnerQueries")
      local rows = moduleCall(self.hs.window.list, true)
      local owners = {}
      for _, row in ipairs(type(rows) == "table" and rows or {}) do
        if unknown[row.kCGWindowNumber] and type(row.kCGWindowOwnerPID) == "number" then
          owners[row.kCGWindowOwnerPID] = true
        end
      end
      for pid in pairs(owners) do
        local app = moduleCall(self.hs.application.applicationForPID, pid)
        local record = app and self:_acceptApp(app)
        if record then
          pcall(self._attachApp, self, app, callback)
          self:_record("discoveryApplicationQueries")
          local ok, windows = pcall(app.allWindows, app)
          if ok and type(windows) == "table" then
            for _, window in ipairs(windows) do self:_ready(window, "bootstrap", callback, members) end
          end
        end
      end
      for id in pairs(unknown) do if not self.handles[id] then unresolved = true; break end end
      -- WindowServer exposure can lag the Space callback. A short, bounded
      -- retry belongs to this activation only; never a permanent discovery poll.
      attempt = attempt or 1
      if unresolved and attempt < 3 and self.hs.timer and self.hs.timer.doAfter then
        if self.discoveryTimer then self.discoveryTimer:stop() end
        local generation, context = self.generation, self.context
        local timer
        timer = self.hs.timer.doAfter(0.1, function()
          if self.discoveryTimer ~= timer then return end
          self.discoveryTimer = nil
          if self.started and generation == self.generation and self.context == context then
            self:subscribeExistingWindows(callback, false, attempt + 1)
          end
        end)
        self.discoveryTimer = timer
      end
    end
    return { detach = function() end }
  end
  self:_bootstrapRegular(callback)
  return { detach = function() end }
end

function Host:probeReadiness(id, callback)
  local record = self.handles[id]
  local spaceId, spaceType
  if record then spaceId, spaceType = self:_owner(id) end
  local metadata = spaceId and self:_metadata(record.handle, "targetedReadiness", spaceId, spaceType)
  if metadata then
    self:_remember(record.handle)
    local admitted = callback(metadata, record.handle, record.lease, record.appLease)
    -- Admission does not change MRU. Observe again only after the independent
    -- fullscreen readiness transaction, guarding against intervening focus.
    if admitted == true and spaceType == "fullscreen" then self:observeFocus(id) end
  else callback(nil, nil, record and record.lease, record and record.appLease) end
  return { detach = function() end }
end

function Host:setContext(context)
  local previous = self.context
  local sameScope = previous and previous.displayId == context.displayId
    and previous.regularSpaceId == context.regularSpaceId
    and previous.spaceType == context.spaceType
  for id, token in pairs(self.readiness) do
    if sameScope then token.context = context else self:_cancelReadiness(id) end
  end
  if self.discoveryTimer then self.discoveryTimer:stop(); self.discoveryTimer = nil end
  self.context = context
  if sameScope and self.validityTarget then self.validityTarget.context = context
  else self:_cancelValidity() end
end

-- Native lifetime authority is independent of management (WIN-001/LIFE-003).
function Host:appCurrent(pid, lease)
  local app = self.appResources[pid]
  return self.started and app and app.active and app.lease == lease
end

function Host:current(id, lease, appLease, pid)
  local record, app = self.handles[id], self.appResources[pid]
  return self.started and record and record.active and record.lease == lease
    and record.pid == pid and record.appLease == appLease and app and app.active and app.lease == appLease
end

function Host:focusedManagedLease(id, presentationLease)
  local record = self.handles[id]
  local app = record and self.appResources[record.pid]
  if record and app and self:current(id, record.lease, record.appLease, record.pid)
    and self.managedObservers[id] and self.presentationId == id
    and self.presentationLease == presentationLease and self.presentationWindow == record.handle
    and self.presentationApp == app.app then return record.lease end
end

function Host:enableManaged(id, lease)
  local record = self.handles[id]
  if record and record.lease == lease and record.active and record.subscription then
    self.managedObservers[id] = { record = record, attachment = record.windowAttachment }
    self:_trackValidity()
  end
end

function Host:releaseWindow(id, lease)
  return self:_forget(id, lease)
end

function Host:releaseApplication(pid, lease)
  local record = self.appResources[pid]
  if not record or not record.active or record.lease ~= lease then return false end
  for id, token in pairs(self.readiness) do if token.appRecord == record then self:_cancelReadiness(id) end end
  record.active = false
  if self.presentationApp == record.app then self:_observePresentation(nil, nil, nil, nil) end
  self:_forgetPid(pid, lease)
  if record.subscription then record.subscription.detach() end
  self.appResources[pid] = nil
  return true
end

function Host:start()
  if self.started then return self end
  self.generation = self.generation + 1; self.started = true; return self
end
function Host:stop()
  if not self.started then return self end
  self.started = false; self.generation = self.generation + 1
  self:_cancelValidity()
  if self.startupTimer then pcall(self.startupTimer.stop, self.startupTimer); self.startupTimer = nil end
  if self.discoveryJob then call(self.discoveryJob, "cancel"); self.discoveryJob = nil end
  self.startupDiscovery = { pending = false, complete = false, unresolvedCount = 0, reason = "stopped" }
  local worker = self.validityWorker; self.validityWorker = nil
  if worker and not pcall(worker.stop, worker) then self.validityError = "worker_stop_failed" end
  for id in pairs(self.readiness) do self:_cancelReadiness(id) end
  if self.discoveryTimer then self.discoveryTimer:stop(); self.discoveryTimer = nil end
  self:_observePresentation(nil, nil, nil, nil)
  for record in pairs(self.owned) do self:_detach(record) end
  for _, record in pairs(self.handles) do record.active = false end
  for _, record in pairs(self.appResources) do record.active = false end
  self.owned, self.appResources, self.handles, self.managedObservers, self.frames, self.windowCallback = {}, {}, {}, {}, {}, nil
  return self
end

function Host:_cancelValidity()
  self.validityTarget = nil
  local timer = self.validityTimer; self.validityTimer = nil
  if timer then
    local ok = pcall(timer.stop, timer)
    if not ok then self.validityError = "mailbox_stop_failed" end
  end
  if self.validityWorker then
    local ok = pcall(self.validityWorker.set, self.validityWorker, nil, self.validitySerial)
    if not ok then self.validityError = "worker_clear_failed" end
  end
end

function Host:_validityCurrent(target)
  local record = self.handles[target.id]
  local app = self.appResources[target.pid]
  return self.started and self.validityTarget == target and self.generation == target.generation
    and self.context == target.context and self.context.regularSpaceId == target.spaceId
    and record == target.record and record.active and record.lease == target.lease
    and record.element == target.element and record.appLease == target.appLease
    and app == target.appRecord and app.active and app.lease == target.appLease
    and self.managedObservers[target.id] and self.presentationWindow == record.handle
    and self.presentationId == target.id
end

function Host:_trackValidity()
  local id = self.presentationId
  local record = id and self.handles[id]
  local app = record and self.appResources[record.pid]
  local minimized = record and call(record.handle, "isMinimized")
  local hidden = app and call(app.app, "isHidden")
  local fullscreen = record and call(record.handle, "isFullScreen")
  if not self.started or not record or not record.active or not app or not app.active
    or not self.managedObservers[id] or self.presentationWindow ~= record.handle
    or minimized ~= false or hidden ~= false or fullscreen ~= false
    or not self.context.regularSpaceId or not record.element then self:_cancelValidity(); return end
  if self.handles[id] ~= record or self.appResources[record.pid] ~= app
    or not record.active or not app.active or self.presentationWindow ~= record.handle then return end
  if self.validityTarget and self:_validityCurrent(self.validityTarget) then return end
  self:_cancelValidity()
  self.validitySerial = self.validitySerial + 1
  local target = { id = id, pid = record.pid, record = record, appRecord = app,
    lease = record.lease, appLease = record.appLease, element = record.element,
    token = self.validitySerial, generation = self.generation, context = self.context,
    spaceId = self.context.regularSpaceId }
  self.validityTarget = target
  local ok, failure = pcall(function()
  local worker = self.validityWorker
  if not worker then
    local factory = self.nativeValidity or require("lib.macos.ax_validity")
    worker = factory.create()
    if not self:_validityCurrent(target) then worker:stop(); return end
    self.validityWorker = worker
  end
  worker:set(target.element, target.token)
  if not self:_validityCurrent(target) then
    if self.validityWorker == worker then worker:set(nil, target.token) end
    return
  end
  local timer = assert(self.hs.timer.doEvery(0.05, function()
    if not self:_validityCurrent(target) then
      if self.validityTarget == target then self:_cancelValidity() end
      return
    end
    local read, rows = pcall(worker.poll, worker) -- no AX query here
    if not read then
      if self.validityTarget == target then self.validityError = "mailbox_poll_failed"; self:_cancelValidity() end
      return
    end
    if not self:_validityCurrent(target) then return end
    for _, row in ipairs(rows) do
      if row.token == target.token and row.status == "invalid" and row.error == -25202
        and self:_validityCurrent(target) and self.windowCallback then
        self:_cancelValidity()
        self:_record("asynchronousValidityRemovals")
        self.windowCallback({ kind = "destroyed", id = target.id, resource = target.lease,
          observationOrigin = "asynchronousValidity", presentationResource = self.presentationLease })
        return
      end
    end
  end), "validity mailbox timer allocation failed")
  if not self:_validityCurrent(target) then pcall(timer.stop, timer); return end
  self.validityTimer = timer
  end)
  if not ok then
    if self.validityTarget == target then self:_cancelValidity() end
    error(failure, 0)
  end
end

function Host:_observePresentation(window, id, pid, app)
  if self.presentationWindow ~= window or self.presentationId ~= id then self:_cancelValidity() end
  -- Presentation is a focused native source, not a numerical window/PID alias.
  -- Its stable token exists even when optional title observation cannot attach.
  if self.presentationId == id and self.presentationWindow == window then return end
  self.presentationAttachment = nil
  if self.presentationSubscription then self.presentationSubscription.detach(); self.presentationSubscription = nil end
  self.presentationId, self.presentationPid, self.presentationWindow, self.presentationApp = id, pid, window, app
  self.presentationLease = id ~= nil and self:_nextLease() or nil
  if id == nil then return end
  local managed = self.managedObservers[id]
  -- A managed window has its full lifecycle title observer. A focused excluded
  -- window gets one replaceable title-only observer, independent of a deferred
  -- conflicting record with the same native ID.
  if (managed and managed.record and managed.record.active and managed.record.handle == window)
    or type(window.newWatcher) ~= "function" then return end
  local generation, lease, attachment = self.generation, self.presentationLease, {}
  local ok, watcher = pcall(window.newWatcher, window, function(_, event)
    if self.started and generation == self.generation and self.presentationLease == lease
      and self.presentationAttachment == attachment and self.presentationWindow == window
      and event == "AXTitleChanged" and self.windowCallback then
      self.windowCallback({ kind = "titleChanged", id = id, title = call(window, "title") or "", presentationResource = lease })
    end
  end)
  if not ok or not watcher then return end
  local stopped = false
  local function detach()
    if stopped then return end
    stopped = true
    if watcher.stop then pcall(watcher.stop, watcher) end
  end
  ok = pcall(watcher.start, watcher, { "AXTitleChanged" })
  if not ok then detach(); return end
  self.presentationAttachment = attachment
  self.presentationSubscription = { detach = function()
    if self.presentationAttachment == attachment then self.presentationAttachment = nil end
    detach()
  end }
end

-- POC-009 verified that unchanged native focus need not produce
-- AXFocusedWindowChanged. This is one targeted global actual-focus read, never
-- a scan or timer. An optional expected ID guards post-effect confirmation.
function Host:_checkApplicationWindows(pid, appLease)
  local records = {}
  for id, record in pairs(self.handles) do
    if record.pid == pid and record.appLease == appLease then records[#records + 1] = { id, record } end
  end
  for _, entry in ipairs(records) do self:_checkWindowValidity(entry[1], entry[2]) end
end

function Host:_checkPreviousFocus()
  local id = self.presentationId
  local record = id and self.handles[id]
  if record and record.handle == self.presentationWindow then self:_checkWindowValidity(id, record) end
end

function Host:_checkWindowValidity(id, record)
  if not self.windowCallback or not record or self.handles[id] ~= record or not record.active
    or record.checkingValidity or not self.managedObservers[id] then return end
  local element = record.element
  if not element or type(element.isValid) ~= "function" then return end
  self:_record("targetedValidityQueries")
  -- Only the API's explicit InvalidUIElement result is removal evidence.
  -- nil/errors, hidden/minimized status and snapshot absence retain uncertainty.
  local ok, valid = pcall(element.isValid, element)
  if not ok or valid ~= false then return ok and valid == true end
  record.checkingValidity = true
  local emitted, failure = pcall(self.windowCallback, { kind = "destroyed", id = id,
    resource = record.lease, presentationResource = self.presentationId == id and self.presentationWindow == record.handle and self.presentationLease or nil })
  record.checkingValidity = nil
  if not emitted then error(failure, 0) end
  return false
end

function Host:observeFocus(expectedId)
  -- A close can omit AX destruction yet leave an invalid exact AX resource.
  -- Reduce that fact before macOS fallback focus can redirect source recovery.
  if expectedId == nil and self.windowCallback then self:_checkPreviousFocus() end
  self:_record("targetedFocusQueries")
  local reader = self.hs.window and self.hs.window.focusedWindow
  if type(reader) ~= "function" then return false end
  local ok, focused = pcall(reader)
  if not ok or not self.windowCallback then return false end
  if focused == nil then
    if expectedId ~= nil then return false end
    self:_observePresentation(nil, nil, nil, nil)
    self:_cancelValidity()
    self.windowCallback({ kind = "focus" }); return true
  end
  local actualId = call(focused, "id")
  -- A non-nil object without an ID is a failed/uncertain read, not successful
  -- no-focus. Preserve presentation instead of clearing it.
  if actualId == nil then return false end
  -- An expected post-effect read only confirms its matching target; a
  -- nonmatching result is not a no-focus observation.
  if expectedId ~= nil and actualId ~= expectedId then return false end
  local app = call(focused, "application")
  local pid = call(app, "pid")
  -- App acceptance is independent from a same-ID window conflict. BAR needs
  -- the accepted app lease to clear a genuinely terminated focused source.
  local appRecord = self:_acceptApp(app)
  local record = self:_remember(focused)
  self:_observePresentation(focused, actualId, pid, app)
  self.windowCallback({ kind = "focus", id = actualId, title = call(focused, "title"),
    applicationName = call(app, "name"), applicationPid = pid, nativeFullscreen = call(focused, "isFullScreen") == true,
    resource = record and record.lease, appResource = appRecord and appRecord.lease, presentationResource = self.presentationLease })
  self:_trackValidity()
  return true
end

function Host:focus(window, lease, spaceId, fullscreen, fullscreenOwner)
  local requestedId = call(window, "id")
  if requestedId == nil then return end
  local record = self.handles[requestedId]
  if lease ~= nil and (not record or record.handle ~= window
    or not self:current(requestedId, lease, record.appLease, record.pid)) then return end
  if record and record.handle == window then
    local valid = self:_checkWindowValidity(requestedId, record)
    if not record.active or self.handles[requestedId] ~= record then return end
    if lease ~= nil then
      if valid ~= true then return end
      local owner, kind = self:_owner(requestedId)
      local nativeFullscreen = call(window, "isFullScreen")
      if not owner or nativeFullscreen ~= (fullscreen == true)
        or (fullscreen and (kind ~= "fullscreen" or (fullscreenOwner and owner ~= fullscreenOwner)))
        or (not fullscreen and (kind ~= "user" or owner ~= spaceId)) then return end
      if not self:current(requestedId, lease, record.appLease, record.pid) then return end
    end
  end
  self:_record("focusRequests")
  local ok, result = pcall(window.focus, window)
  if not ok or result == false then return end
  return self:observeFocus(requestedId)
end

function Host:execute(adapter, intents, current)
  for _, intent in ipairs(intents) do
    if not current or current(intent) then
    local record = self.handles[intent.windowId]
    if record and (intent.lease == nil or intent.lease == record.lease) then
      self:_checkWindowValidity(intent.windowId, record)
    end
    if not current or current(intent) then
    -- Composition effects are scoped to the committed target descriptor; an
    -- adapter ID cache alone cannot prove the current resource owns this Space.
    local target = { windowId = intent.windowId, spaceId = intent.spaceId, lease = intent.lease }
    local window = self.handleRegistry and self.handleRegistry:resolve(target)
    if not window and not self.handleRegistry then window = adapter:handleForId(intent.windowId) end
    if window and intent.kind == "frame" then
      -- Core emits frames only at real synchronization boundaries. Readback
      -- there is necessary to detect manual drift, even if our last write matches.
      self:_record("frameQueries")
      local actual = call(window, "frame")
      local previous = self.frames[intent.windowId]
      local same = actual and actual.x == intent.frame.x and actual.y == intent.frame.y and actual.w == intent.frame.w and actual.h == intent.frame.h
      self:_record("frameRequests")
      if not current or current(intent) then
      if not same and (actual or not previous or previous.x ~= intent.frame.x or previous.y ~= intent.frame.y or previous.w ~= intent.frame.w or previous.h ~= intent.frame.h) then
        window:setFrame(intent.frame, 0)
        self:_record("frameWrites")
      end
      self.frames[intent.windowId] = { x = intent.frame.x, y = intent.frame.y, w = intent.frame.w, h = intent.frame.h }
      end
    elseif window and intent.kind == "focus" then
      local result = self:focus(window, intent.lease, intent.spaceId, false)
      if result == nil then return false end
    end
    end
    end
  end
end

return Host
