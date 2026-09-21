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
  local spaceType, regularPositions
  assert(space ~= nil, "10bucks requires an active Space")
  regularPositions = {}
  for _, item in ipairs(display.Spaces) do
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
    regularPositions = regularPositions }
end

-- The Space watcher owns only confirmed context changes. It deliberately does
-- not infer a new scope from a watcher payload: a fresh explicit snapshot is
-- the confirmation boundary.
function Context.watch(hs, builtInDisplayUUID, callback)
  assert(type(callback) == "function", "context watcher requires a callback")
  assert(hs.spaces.watcher and hs.spaces.watcher.new,
    "10bucks requires hs.spaces.watcher for active-Space context")
  local watcher, screenWatcher, stopped, generation
  stopped, generation = false, 0
  local function detach()
    if stopped then return end
    stopped, generation = true, generation + 1
    if watcher and watcher.stop then pcall(watcher.stop, watcher) end
    if screenWatcher and screenWatcher.stop then pcall(screenWatcher.stop, screenWatcher) end
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
  return { detach = detach }
end

return Context
