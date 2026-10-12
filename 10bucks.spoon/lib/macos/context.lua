local Context = {}

function Context.snapshot(hs, builtInDisplayUUID)
  assert(type(builtInDisplayUUID) == "string" and builtInDisplayUUID ~= "",
    "10bucks Canary A requires config.builtInDisplayUUID before switching runtime")
  local selected
  for _, screen in ipairs(hs.screen.allScreens()) do
    if screen:getUUID() == builtInDisplayUUID then selected = screen; break end
  end
  assert(selected, "10bucks built-in display UUID is not connected; verify config.builtInDisplayUUID before switching runtime")
  -- hs.spaces.activeSpaceOnScreen/spaceType each read the complete private
  -- topology. Classify the selected display from one snapshot; the native
  -- field shape is source-verified and recorded in POC-003.
  local topology = assert(hs.spaces.data_managedDisplaySpaces(), "10bucks requires managed Space topology")
  local display
  for _, candidate in ipairs(topology) do
    if candidate["Display Identifier"] == builtInDisplayUUID then display = candidate; break end
  end
  assert(display and type(display.Spaces) == "table" and type(display["Current Space"]) == "table",
    "10bucks requires selected display Space topology")
  local space = display["Current Space"].ManagedSpaceID
  local spaceType, regularPositions, fullSpaceIds
  assert(space ~= nil, "10bucks requires an active Space")
  regularPositions, fullSpaceIds = {}, {}
  for _, item in ipairs(display.Spaces) do
    assert(item.ManagedSpaceID ~= nil and (item.type == 0 or item.type == 4), "10bucks requires complete known Space topology")
    fullSpaceIds[#fullSpaceIds + 1] = item.ManagedSpaceID
    if item.ManagedSpaceID == space then spaceType = item.type == 0 and "user" or item.type == 4 and "fullscreen" or nil end
    if item.type == 0 then regularPositions[#regularPositions + 1] = item.ManagedSpaceID end
  end
  assert(spaceType == "user" or spaceType == "fullscreen", "10bucks requires a regular or native fullscreen Space")
  -- hs.geometry exposes x/y/w/h through its metatable while pairs() exposes
  -- private _x/_y/_w/_h storage. Keep only primitive geometry across the
  -- adapter boundary so downstream defensive copies preserve the work area.
  local frame, fullFrame = selected:frame(), selected:fullFrame()
  local workArea = { x = frame.x, y = math.max(frame.y, fullFrame.y + 32), w = frame.w,
    h = math.max(0, frame.h - math.max(0, math.max(frame.y, fullFrame.y + 32) - frame.y)) }
  assert(type(workArea.x) == "number" and type(workArea.y) == "number"
      and type(workArea.w) == "number" and type(workArea.h) == "number",
    "10bucks built-in display frame must provide numeric x/y/w/h")
  assert(type(fullFrame.x) == "number" and type(fullFrame.y) == "number" and type(fullFrame.w) == "number",
    "10bucks built-in display fullFrame must provide numeric x/y/w/h")
  return { displayId = builtInDisplayUUID, regularSpaceId = spaceType == "user" and space or nil,
    workArea = workArea, barFrame = { x = fullFrame.x, y = fullFrame.y, w = fullFrame.w, h = 32 },
    regularPositions = regularPositions, regularSpaceIds = regularPositions, fullSpaceIds = fullSpaceIds,
    nativeSpaceId = space, nativeSpaceType = spaceType }
end

-- The Space watcher owns only confirmed context changes. It deliberately does
-- not infer a new scope from a watcher payload: a fresh explicit snapshot is
-- the confirmation boundary.
-- Dock destruction is a proved reconciliation trigger, not UI ownership or liveness.
function Context.watch(hs, builtInDisplayUUID, callback, onDockBoundary)
  assert(type(callback) == "function", "context watcher requires a callback")
  assert(hs.spaces.watcher and hs.spaces.watcher.new,
    "10bucks requires hs.spaces.watcher for active-Space context")
  local watcher, screenWatcher, dockObserver, appWatcher, dockPid, stopped, generation
  local boundaryError
  stopped, generation = false, 0
  local function detach()
    if stopped then return end
    stopped, generation = true, generation + 1
    if watcher and watcher.stop then pcall(watcher.stop, watcher) end
    if screenWatcher and screenWatcher.stop then pcall(screenWatcher.stop, screenWatcher) end
    if dockObserver then pcall(dockObserver.stop, dockObserver); dockObserver = nil end
    if appWatcher then pcall(appWatcher.stop, appWatcher); appWatcher = nil end
  end
  -- Own both event sources before start. A screen change updates geometry and
  -- cached positions even when the active Space ID itself is unchanged.
  local function refresh()
    local captured = generation
    if stopped then return end
    local ok, snapshot = pcall(Context.snapshot, hs, builtInDisplayUUID)
    if not ok or stopped or captured ~= generation then return end
    callback(snapshot, captured)
  end
  watcher = hs.spaces.watcher.new(refresh)
  assert(hs.screen.watcher and hs.screen.watcher.new, "10bucks requires hs.screen.watcher for bar geometry")
  screenWatcher = hs.screen.watcher.new(refresh)
  local ok, err = pcall(watcher.start, watcher)
  if not ok then detach(); error(err, 0) end
  ok, err = pcall(screenWatcher.start, screenWatcher)
  if not ok then detach(); error(err, 0) end
  if onDockBoundary then
    local function boundary()
      if stopped then return end
      local captured = generation
      local success, context = pcall(Context.snapshot, hs, builtInDisplayUUID)
      local delivered, failure = pcall(onDockBoundary, success and context or nil)
      if not delivered then boundaryError = tostring(failure) end
      if success and not stopped and captured == generation then
        delivered, failure = pcall(callback, context, captured)
        if not delivered then boundaryError = tostring(failure) end
      elseif not success then boundaryError = tostring(context) end
    end
    local function attach(app)
      if dockObserver then pcall(dockObserver.stop, dockObserver); dockObserver = nil end
      dockPid = app:pid()
      local owned
      local success, failure = pcall(function()
        owned = hs.axuielement.observer.new(dockPid)
        dockObserver = owned -- register ownership before callback/start
        owned:callback(function(_, _, notification)
          if stopped or dockObserver ~= owned then return end
          if notification == "AXUIElementDestroyed" then boundary() end
        end)
        assert(owned:addWatcher(hs.axuielement.applicationElement(app), "AXUIElementDestroyed"), "Dock boundary registration failed")
        assert(owned:start(), "Dock boundary observer start failed")
      end)
      if not success then
        if owned then pcall(owned.stop, owned) end
        dockObserver = nil; boundaryError = tostring(failure)
      else boundaryError = nil end
      return success, failure
    end
    ok, err = pcall(function()
      appWatcher = hs.application.watcher.new(function(_, event, app)
        if stopped or not app then return end
        local success, failure = pcall(function()
          if event == hs.application.watcher.terminated and app:pid() == dockPid then
            if dockObserver then pcall(dockObserver.stop, dockObserver); dockObserver = nil end
            dockPid = nil; boundary(); boundaryError = "Dock unavailable; desktop topology observation suspended."
          elseif event == hs.application.watcher.launched and app:bundleID() == "com.apple.dock" then
            attach(app); boundary()
          end
        end)
        if not success then boundaryError = tostring(failure) end
      end)
      appWatcher:start()
      local apps = hs.application.applicationsForBundleID("com.apple.dock")
      assert(apps and #apps == 1, "one Dock required for topology observation")
      local attached, failure = attach(apps[1]); assert(attached, failure)
    end)
    if not ok then detach(); error(err, 0) end
  end
  return { detach = detach, status = function() return { dockBoundaryError = boundaryError } end }
end

return Context
