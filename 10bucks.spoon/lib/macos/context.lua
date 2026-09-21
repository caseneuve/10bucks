local Context = {}

function Context.snapshot(hs, builtInDisplayUUID)
  assert(type(builtInDisplayUUID) == "string" and builtInDisplayUUID ~= "",
    "10bucks Canary A requires config.builtInDisplayUUID before switching runtime")
  local selected
  for _, screen in ipairs(hs.screen.allScreens()) do
    if screen:getUUID() == builtInDisplayUUID then selected = screen; break end
  end
  assert(selected, "10bucks built-in display UUID is not connected; verify config.builtInDisplayUUID before switching runtime")
  local space = assert(hs.spaces.activeSpaceOnScreen(selected), "10bucks requires an active Space")
  local spaceType = hs.spaces.spaceType(space)
  assert(spaceType == "user" or spaceType == "fullscreen", "10bucks requires a regular or native fullscreen Space")
  -- hs.geometry exposes x/y/w/h through its metatable while pairs() exposes
  -- private _x/_y/_w/_h storage. Keep only primitive geometry across the
  -- adapter boundary so downstream defensive copies preserve the work area.
  local frame = selected:frame()
  local workArea = { x = frame.x, y = frame.y, w = frame.w, h = frame.h }
  assert(type(workArea.x) == "number" and type(workArea.y) == "number"
      and type(workArea.w) == "number" and type(workArea.h) == "number",
    "10bucks built-in display frame must provide numeric x/y/w/h")
  return { displayId = builtInDisplayUUID, activeSpaceId = space, spaceType = spaceType,
    regularSpaceId = spaceType == "user" and space or nil, workArea = workArea, screen = selected }
end

-- The Space watcher owns only confirmed context changes. It deliberately does
-- not infer a new scope from a watcher payload: a fresh explicit snapshot is
-- the confirmation boundary.
function Context.watch(hs, builtInDisplayUUID, callback)
  assert(type(callback) == "function", "context watcher requires a callback")
  assert(hs.spaces.watcher and hs.spaces.watcher.new,
    "10bucks requires hs.spaces.watcher for active-Space context")
  local watcher, stopped, generation
  stopped, generation = false, 0
  local function detach()
    if stopped then return end
    stopped, generation = true, generation + 1
    if watcher and watcher.stop then pcall(watcher.stop, watcher) end
  end
  watcher = hs.spaces.watcher.new(function()
    local captured = generation
    if stopped then return end
    local ok, snapshot = pcall(Context.snapshot, hs, builtInDisplayUUID)
    if not ok or stopped or captured ~= generation then return end
    callback(snapshot, captured)
  end)
  -- Own it before start. A failed start can leave a native watcher live.
  local ok, err = pcall(watcher.start, watcher)
  if not ok then detach(); error(err, 0) end
  return { detach = detach }
end

return Context
