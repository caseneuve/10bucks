local function fakeHs(options)
  options = options or {}
  local f = { deleted = 0, frames = 0, focuses = 0, bindings = {}, scans = 0, focusedWindowQueries = 0,
    actual = { x = 99, y = 99, w = 1, h = 1 }, owners = { "space" }, members = { 9 } }
  local function watcher(callback, label)
    return { callback = callback, label = label, start = function() end,
      stop = function(self) if not self.stopped then self.stopped = true; f.deleted = f.deleted + 1 end end }
  end
  local function contextWatcher(callback)
    local watcher = watcher(callback, "space")
    f.contextWatcher = watcher
    return watcher
  end
  local function screenWatcher(callback)
    local watcher = { callback = callback, start = function() end, stop = function() end }
    f.screenWatcher = watcher
    return watcher
  end
  local function timer() return { stop = function(self) self.stopped = true end } end
  local function canvas()
    local object = { level = function(self) return self end, behavior = function(self) return self end, clickActivating = function(self) return self end,
      canvasMouseEvents = function(self) return self end, mouseCallback = function(self, callback) self.callback = callback; return self end,
      frame = function(self, value) self.currentFrame = value; return self end, replaceElements = function(self, value) self.elements = value; return self end,
      show = function(self) self.shown = true; return self end, hide = function(self) self.shown = false; return self end, delete = function(self) self.deleted = true end }
    f.canvas = object; return object
  end
  local screen = { id = function() return 1 end, getUUID = function() return "built-in" end, frame = function() return f.geometry or { x = 0, y = 0, w = 100, h = 80 } end,
    fullFrame = function() return f.geometry or { x = 0, y = 0, w = 100, h = 80 } end }
  -- Evidence-derived boundary: AX conversion provides metadata/asHSWindow only;
  -- the per-window watcher is constructed by hs.window:newWatcher(handler).
  local element = { asHSWindow = function() return f.window end,
    attributeValue = function(_, _) return false end, isAttributeSettable = function() return true end }
  local app = { isHidden = function() return false end, pid = function() return 8 end, name = function() return "App" end, bundleID = function() return "app" end,
    allWindows = function() f.scans = f.scans + 1; if options.bootstrapFails then error("bootstrap failed") end; return { f.window } end,
    newWatcher = function(_, cb) f.appWatcher = watcher(cb, "app"); return f.appWatcher end }
  f.window = { isMinimized = function() return false end, id = function() return 9 end, title = function() return "Window" end, application = function() return app end,
    role = function() return "AXWindow" end, subrole = function() return "AXStandardWindow" end,
    isFullScreen = function() return f.fullscreen end, newWatcher = function(_, cb) f.windowWatcher = watcher(cb, "window"); return f.windowWatcher end, frame = function() f.frameReads = (f.frameReads or 0) + 1; return f.actual end,
    setFrame = function(_, frame, duration) assert(duration == 0); f.frames = f.frames + 1; f.actual = frame end,
    focus = function() f.focuses = f.focuses + 1; f.presentationAtFocus = f.canvas and f.canvas.elements and f.canvas.elements[4].text end }
  local dock = { pid = function() return 81 end, bundleID = function() return 'com.apple.dock' end,
    allWindows = function() return {} end }
  local dockElement = { attributeValue = function(_, attribute)
    if attribute == 'AXChildren' then return f.mc and { f.mc } or {} end
  end }
  f.dock, f.dockElement = dock, dockElement
  local bindCount = 0
  _G.hs = { processInfo = { processID = 1 }, screen = { allScreens = function() return { screen } end },
    spaces = { activeSpaceOnScreen = function() return f.activeSpace or "space" end, spaceType = function() return "user" end,
      data_managedDisplaySpaces = function() local active = f.activeSpace or "space"; return { { ["Display Identifier"] = "built-in", ["Current Space"] = { ManagedSpaceID = active }, Spaces = f.topology or { { ManagedSpaceID = "space", type = 0 }, { ManagedSpaceID = "next-space", type = 0 } } } } end,
      windowsForSpace = function() return f.members end, windowSpaces = function() return f.owners end,
      watcher = { new = contextWatcher } },
    axuielement = { applicationElement = function(x) assert(x == dock); return dockElement end,
      observer = { notifications = { AXUIElementDestroyed = 'AXUIElementDestroyed' }, new = function(pid)
        assert(pid == 81)
        local object = { callback = function(self, callback) self.notification = callback; return self end,
          addWatcher = function(_, target, notification)
            assert(target == dockElement and notification == 'AXUIElementDestroyed'); return true
          end,
          start = function(self) self.running = true; return self end,
          stop = function(self) self.running = false; self.stopped = true end }
        f.dockObserver = object; return object
      end }, windowElement = function(x) assert(x == f.window); return element end },
    application = { applicationsForBundleID = function(bundle) assert(bundle == 'com.apple.dock'); return { dock } end,
      applicationForPID = function(pid) return pid == 8 and app or (f.apps and f.apps[pid]) end, runningApplications = function() return { app } end, watcher = { new = function(cb)
      local object = watcher(cb, 'life')
      if not f.life or f.life.stopped then f.life = object else f.dockLife = object end
      return object
    end, terminated = 3, hidden = 4, unhidden = 5, launched = 2 } },
    window = { list = function() return f.ownerRows or {} end, focusedWindow = function() f.focusedWindowQueries = f.focusedWindowQueries + 1; if f.focusedWindowError then error("focused-window read failed") end; return f.focusedWindow end },
    canvas = { new = canvas }, mouse = { absolutePosition = function() return { x = 50, y = 50 } end },
    timer = { secondsSinceEpoch = function() return 1 end, doAfter = function(_, _) return timer() end, doEvery = function(_, _) return timer() end },
    host = { interfaceStyle = function() return f.interfaceStyle end },
    distributednotifications = { new = function(callback) f.appearance = { callback = callback, start = function() end, stop = function() f.appearanceStopped = true end }; return f.appearance end },
    hotkey = { bind = function(_, _, cb) bindCount = bindCount + 1; if options.failBind == bindCount then error("bind failed") end; local h = { delete = function(self) if not self.deleted then self.deleted = true; f.deleted = f.deleted + 1 end end }; f.bindings[#f.bindings + 1] = { callback = cb, handle = h }; return h end }, }
  _G.hs.screen.watcher = { new = screenWatcher }
  return f, element
end

local function validityFake()
  return {create=function()return {set=function()end,poll=function()return {} end,stop=function()end}end}
end

local function load(f)
  package.loaded["init"] = nil
  local ten = dofile("10bucks.spoon/init.lua").new(validityFake())
  ten:configure({ builtInDisplayUUID = "built-in" })
  return ten
end

local function focus(ten, id)
  local target = ten.handleRegistry:target(id)
  return ten:_submitEvent({ type = "ActualFocusChanged", id = id, resource = target and target.lease })
end

local function loadConfiguredFile(f, config)
  package.loaded["init"] = nil
  local Config = require("lib.config")
  local original = Config.loadFile
  Config.loadFile = function(path) assert(path == "test-config.lua"); return config end
  local ten = dofile("10bucks.spoon/init.lua").new(validityFake())
  local ok, err = pcall(function() ten:configureFile("test-config.lua"):bindHotkeys():start() end)
  Config.loadFile = original
  assert(ok, err)
  return ten
end

-- Test-only native boundary: actual Context/Spaces/Runtime composition, no adapter injection.
local function workspaceSetup()
  local f = fakeHs()
  f.topology = { { ManagedSpaceID = 'space', type = 0 }, { ManagedSpaceID = 'next-space', type = 0 },
    { ManagedSpaceID = 'third-space', type = 0 } }
  f.clock, f.timers, f.presses, f.opens = 0, {}, {}, 0
  hs.timer.absoluteTime = function() return f.clock * 1e9 end
  hs.timer.doAfter = function(delay, callback)
    local timer = { delay = delay, callback = callback, due = f.clock + delay,
      stop = function(self) self.stopped = true end }
    f.timers[#f.timers + 1] = timer; return timer
  end
  local function node(identifier, children, displayId)
    return { attributeValue = function(_, name)
      if name == 'AXIdentifier' then return identifier end
      if name == 'AXChildren' then return children end
      if name == 'AXDisplayID' then return displayId end
    end }
  end
  hs.spaces.openMissionControl = function()
    f.opens = f.opens + 1
    if f.onOpen then f.onOpen() end
    local buttons = {}
    for _, item in ipairs(f.topology) do
      local id = item.ManagedSpaceID
      local button = node('button', {})
      button.performAction = function(self, action)
        assert(action == 'AXPress')
        local state = f.ten.workspace:state()
        assert(state.switch.inFlight.phase == 'pressed', 'press must follow committed phase')
        f.presses[#f.presses + 1] = id
        if f.onPress then f.onPress(id) end
        return self -- real AXPress success shape, not boolean-only mock
      end
      buttons[#buttons + 1] = button
    end
    f.mc = node('mc', { node('mc.display', { node('mc.spaces', { node('mc.spaces.list', buttons) }) }, 1) })
  end
  function f:fire(delay)
    for _, timer in ipairs(self.timers) do
      if timer.delay == delay and not timer.stopped and not timer.fired then
        self.clock = math.max(self.clock, timer.due); timer.fired = true; timer.callback(); return timer
      end
    end
    error('expected live timer ' .. tostring(delay))
  end
  function f:activate(id)
    self.activeSpace, self.members, self.focusedWindow, self.mc = id, id == 'space' and { 9 } or {}, nil, nil
    self.contextWatcher.callback()
  end
  function f:confirm(id)
    self:fire(.3)
    assert(self.presses[#self.presses] == id, 'wrong native AX index')
    -- Model actual Mission Control destruction, not only a Space watcher. The
    -- adapter's dismissal barrier must receive its independent Dock boundary.
    self.mc = nil
    self.dockObserver.notification(nil, nil, 'AXUIElementDestroyed')
    self:activate(id)
  end
  local ten = load(f):start(); f.ten = ten
  return f, ten
end

return {
  ["STATE-002 CMD-005: frame callback desktop command waits for completed outer Core flush"] = function()
    local f, ten = workspaceSetup()
    local inside, submitted, completed, opened = false, false, false, false
    local original = f.window.setFrame
    f.window.setFrame = function(window, frame, duration)
      original(window, frame, duration)
      if submitted then return end
      submitted, inside = true, true
      assert(ten.effectBatch, 'outer frame flush must retain delivery boundary')
      assert(ten:_submitCommand({ type = 'FocusRegularPosition', position = 2 }))
      assert(f.opens == 0, 'Mission Control opened inside unfinished frame callback')
      assert(ten.workspace:state().switch.inFlight.destinationId == 'next-space', 'workspace decision must commit during reentry')
      inside, completed = false, true
    end
    f.onOpen = function()
      assert(not inside and completed, 'workspace effect preceded frame callback completion')
      assert(ten.effectBatch, 'workspace flush must keep reentrant delivery boundary')
      opened = true
    end
    f.actual = { x = 7, y = 0, w = 1, h = 1 }
    assert(ten:_submitCommand({ type = 'Reflow' }))
    assert(submitted and completed and opened and f.opens == 1 and ten.effectBatch == nil)
    f:confirm('next-space'); ten:stop()
  end,
  ["STATE-002 CMD-005 FOCUS-006: native focus callback desktop command waits for completed outer Core flush"] = function()
    local f, ten = workspaceSetup(); focus(ten, 9)
    local inside, submitted, completed, opened = false, false, false, false
    f.window.focus = function()
      f.focuses = f.focuses + 1
      assert(not submitted, 'cancelled native focus must not be reissued')
      submitted, inside = true, true
      assert(ten.effectBatch, 'native focus flush lost delivery boundary')
      assert(ten:_submitCommand({ type = 'FocusRegularPosition', position = 2 }))
      assert(f.opens == 0, 'Mission Control opened inside unfinished native focus callback')
      inside, completed = false, true
    end
    f.onOpen = function() assert(not inside and completed); opened = true end
    assert(ten:_submitCommand({ type = 'FocusNext' }))
    assert(submitted and completed and opened and f.opens == 1 and f.focuses == 1 and ten.effectBatch == nil)
    assert(not ten.focusHistory:pending() and not ten.core:state().manager.focus.desiredBySpace.space.pending)
    f:confirm('next-space'); ten:stop()
  end,
  ["STATE-002 CMD-005: throwing Core flush releases guard and discards queued effects before fresh command"] = function()
    local f, ten = workspaceSetup()
    local original = f.window.setFrame
    local attempts = 0
    f.window.setFrame = function()
      attempts = attempts + 1
      assert(ten.effectBatch, 'throwing flush must initially own guard')
      assert(ten:_submitCommand({ type = 'FocusRegularPosition', position = 2 }))
      assert(f.opens == 0, 'reentrant workspace effect escaped unfinished frame flush')
      error('forced native frame flush failure')
    end
    f.actual = { x = 7, y = 0, w = 1, h = 1 }
    local ok, err = pcall(function() ten:_submitCommand({ type = 'Reflow' }) end)
    assert(not ok and tostring(err):find('forced native frame flush failure', 1, true))
    assert(attempts == 1 and ten.effectBatch == nil and f.opens == 0, 'failed flush leaked guard or queued effect')
    local failed = ten.workspace:state().switch
    assert(not failed.inFlight and not failed.desiredSpaceId and not ten.spaces.operation,
      'discarded unissued workspace effect must retire reducer barrier and desired target')
    f.window.setFrame = original
    local before = f.frames
    assert(ten:_submitCommand({ type = 'Reflow' }))
    assert(f.frames == before + 1 and f.actual.w == 100 and ten.effectBatch == nil)
    assert(f.opens == 0, 'fresh command replayed discarded workspace effect')
    assert(ten:_submitCommand({ type = 'CycleLayout' }))
    assert(ten.core:state().coordinators.space.activeLayoutId == 'columns' and ten.effectBatch == nil)
    assert(ten:_submitCommand({ type = 'FocusRegularPosition', position = 3 }))
    local fresh = ten.workspace:state().switch.inFlight
    assert(f.opens == 1 and fresh and fresh.destinationId == 'third-space' and fresh.generation == 2,
      'fresh desktop command stranded behind discarded reducer barrier')
    f:confirm('third-space')
    assert(#f.presses == 1 and not ten.workspace:state().switch.inFlight)
    ten:stop()
  end,
  ["STATE-002 CMD-005 SPACE-005: throwing Core flush preserves issued native switch ownership"] = function()
    for _, phase in ipairs({ 'requested', 'pressed' }) do
      local f, ten = workspaceSetup()
      assert(ten:_submitCommand({ type = 'FocusRegularPosition', position = 2 }))
      local native = ten.spaces.operation
      if phase == 'pressed' then f:fire(.3) end
      local before = ten.workspace:state().switch.inFlight
      assert(native and before.phase == phase)
      local original = f.window.setFrame
      f.window.setFrame = function() error('issued-operation frame flush failure') end
      f.actual = { x = 7, y = 0, w = 1, h = 1 }
      local ok, err = pcall(function() ten:_submitCommand({ type = 'Reflow' }) end)
      assert(not ok and tostring(err):find('issued-operation frame flush failure', 1, true))
      local after = ten.workspace:state().switch.inFlight
      assert(ten.effectBatch == nil and ten.spaces.operation == native,
        'unrelated flush failure discarded issued native operation')
      assert(after and after.generation == before.generation and after.sourceId == before.sourceId
        and after.sourceType == before.sourceType and after.destinationId == before.destinationId and after.phase == phase)
      assert(ten.workspace:state().switch.desiredSpaceId == 'next-space')
      for _, timer in ipairs(native.timers) do assert(not timer.stopped, 'issued operation callback retired prematurely') end
      f.window.setFrame = original
      assert(ten:_submitCommand({ type = 'FocusRegularPosition', position = 3 }))
      assert(f.opens == 1 and ten.spaces.operation == native, 'new command overlapped issued switch')
      if phase == 'requested' then f:confirm('next-space')
      else
        f.mc = nil; f.dockObserver.notification(nil, nil, 'AXUIElementDestroyed'); f:activate('next-space')
      end
      f:confirm('third-space')
      assert(#f.presses == 2 and not ten.workspace:state().switch.inFlight and not ten.spaces.operation)
      ten:stop()
    end
  end,
  ["FS-003 FOCUS-005 WIN-006: fullscreen exit to another regular scope clears unplaced record while source survives"] = function()
    local f, ten = workspaceSetup(); focus(ten, 9)
    local source, lease = ten.core, ten.handleRegistry:target(9).lease
    f.topology = { { ManagedSpaceID = 'space', type = 0 }, { ManagedSpaceID = 'full', type = 4 },
      { ManagedSpaceID = 'next-space', type = 0 }, { ManagedSpaceID = 'third-space', type = 0 } }
    hs.spaces.spaceType = function(id) return id == 'full' and 'fullscreen' or 'user' end
    -- A second retained managed lifetime makes preservation of history order observable.
    ten:_submitEvent({ type = 'WindowReady', id = 10, displayId = 'built-in', spaceId = 'third-space',
      application = { pid = 8 }, resource = 100, appResource = ten.host.appResources[8].lease },
      { id = function() return 10 end, frame = function() return f.actual end, setFrame = function() end, focus = function() end })
    focus(ten, 10); focus(ten, 9)
    f.fullscreen, f.owners = true, { 'full' }
    ten.host:_ready(f.window, 'targetedReadiness', ten.host.windowCallback)
    f:activate('full'); f.focusedWindow = f.window; ten.host:observeFocus()
    local before = ten.focusHistory:snapshot()
    assert(#before == 2 and before[1].windowId == 10 and before[2].windowId == 9 and before[2].spaceId == 'full')
    assert(ten.focusHistory:unplacedTarget(9) and ten:_targetIsManaged({ windowId = 9, spaceId = 'full' }))
    f.fullscreen, f.owners = false, { 'next-space' }; f:activate('next-space')
    ten.host:_ready(f.window, 'targetedReadiness', ten.host.windowCallback)
    assert(ten.cores.space == source and not source:state().manager.windows[9], 'cross-scope exit must retire old membership, not source Core')
    assert(not ten.focusHistory:unplacedTarget(9), 'successful regular relocation retained stale fullscreen record')
    assert(#ten.focusHistory:unplacedTargets() == 0)
    local window = ten.core:state().manager.windows[9]
    assert(window and window.placementSpaceId == 'next-space' and not window.lifecycle.nativeFullscreen)
    local after = ten.focusHistory:snapshot()
    assert(#after == #before)
    for index, entry in ipairs(before) do assert(after[index].windowId == entry.windowId, 'exit reordered managed history') end
    assert(after[1].spaceId == before[1].spaceId and after[2].spaceId == 'next-space')
    assert(ten.handleRegistry:target(9).lease == lease and ten.handleRegistry:target(9).spaceId == 'next-space')
    assert(ten:_targetIsManaged({ windowId = 9, spaceId = 'next-space' }) and not ten:_targetIsManaged({ windowId = 9, spaceId = 'full' }))
    f.windowWatcher.callback(nil, 'AXUIElementDestroyed')
    assert(not ten.handleRegistry:target(9) and not ten.focusHistory:unplacedTarget(9) and not ten.core:state().manager.windows[9])
    assert(#ten.focusHistory:snapshot() == 1 and ten.focusHistory:snapshot()[1].windowId == 10)
    ten:stop()
  end,
  ["FS-003 FS-005 SPACE-006 FOCUS-005 WIN-005: independently confirmed fullscreen survives source removal then promotes or dies"] = function()
    for _, outcome in ipairs({ 'exit', 'destroy' }) do
      local f, ten = workspaceSetup(); focus(ten, 9)
      local source, lease = ten.core, ten.handleRegistry:target(9).lease
      f.topology = { { ManagedSpaceID = 'space', type = 0 }, { ManagedSpaceID = 'full', type = 4 },
        { ManagedSpaceID = 'next-space', type = 0 }, { ManagedSpaceID = 'third-space', type = 0 } }
      f.fullscreen, f.owners = true, { 'full' }
      hs.spaces.spaceType = function(id) return id == 'full' and 'fullscreen' or 'user' end
      -- Real Host readiness joins native owner/fullscreen metadata to the retained resource.
      ten.host:_ready(f.window, 'targetedReadiness', ten.host.windowCallback)
      local full = ten.focusHistory:unplacedTarget(9)
      assert(full and full.target.spaceId == 'full' and not full.uncertain)
      assert(source:state().manager.windows[9].lifecycle.nativeFullscreen)
      assert(source:state().manager.windows[9].placementSpaceId == 'space', 'fullscreen readiness must retain saved slot')
      assert(ten.handleRegistry:target(9).lease == lease and ten.handleRegistry:target(9).spaceId == 'full',
        'independent fullscreen readiness must route retained native lease to confirmed fullscreen owner')
      -- Confirm actual native focus on F before source retirement; descriptor stays F.
      f:activate('full'); f.focusedWindow = f.window; ten.host:observeFocus()
      assert(ten:_targetIsManaged({ windowId = 9, spaceId = 'full' }), 'confirmed fullscreen focus must remain managed')
      assert(ten.handleRegistry:target(9).lease == lease and ten.handleRegistry:target(9).spaceId == 'full')
      local history = ten.focusHistory:snapshot()
      assert(#history == 1 and history[1].spaceId == 'full')
      f.topology = { { ManagedSpaceID = 'full', type = 4 }, { ManagedSpaceID = 'next-space', type = 0 },
        { ManagedSpaceID = 'third-space', type = 0 } }
      f.dockObserver.notification(nil, nil, 'AXUIElementDestroyed')
      full = ten.focusHistory:unplacedTarget(9)
      assert(not ten.cores.space and full and full.target.spaceId == 'full' and not full.uncertain)
      assert(full.window and full.window.placementSpaceId == nil, 'removed source must invalidate saved placement')
      assert(ten.handleRegistry:target(9).lease == lease and ten.host.handles[9] and ten.windows:handleForId(9) == f.window)
      assert(ten:_targetIsManaged({ windowId = 9, spaceId = 'full' }))
      history = ten.focusHistory:snapshot()
      assert(#history == 1 and history[1].windowId == 9 and history[1].spaceId == 'full', 'removal corrupted confirmed fullscreen history')
      if outcome == 'exit' then
        f.fullscreen, f.owners = false, { 'next-space' }; f:activate('next-space')
        ten.host:_ready(f.window, 'targetedReadiness', ten.host.windowCallback)
        assert(not ten.focusHistory:unplacedTarget(9) and not ten.cores.space)
        local window = ten.core:state().manager.windows[9]
        assert(window and window.placementSpaceId == 'next-space' and not window.lifecycle.nativeFullscreen)
        assert(ten.handleRegistry:target(9).lease == lease and ten.handleRegistry:target(9).spaceId == 'next-space')
        assert(ten:_targetIsManaged({ windowId = 9, spaceId = 'next-space' }))
        history = ten.focusHistory:snapshot()
        assert(#history == 1 and history[1].spaceId == 'next-space', 'promotion inserted or reordered history')
      end
      f.windowWatcher.callback(nil, 'AXUIElementDestroyed')
      assert(not ten.focusHistory:unplacedTarget(9) and not ten.handleRegistry:target(9) and #ten.focusHistory:snapshot() == 0)
      assert(not ten.cores.space and (not ten.core or not ten.core:state().manager.windows[9]))
      ten:stop()
    end
  end,
  ["SPACE-001 SPACE-004 SPACE-005 STATE-002: composed numbered and queued navigation serialize real adapter callbacks"] = function()
    for _, case in ipairs({ { delta = 1, final = 'third-space' }, { delta = -1, final = 'space' },
      { delta = 1, absolute = 1, final = 'space' } }) do
      local f, ten = workspaceSetup(); local first, host, windows = ten.core, ten.host, ten.windows
      local scans = f.scans
      assert(ten:_submitCommand({ type = 'FocusRegularPosition', position = 2 }))
      assert(ten.workspace:state().activeRegularSpaceId == 'space' and f.opens == 1 and #f.presses == 0)
      assert(ten:_submitCommand({ type = 'FocusRelativeRegular', delta = case.delta }))
      if case.absolute then assert(ten:_submitCommand({ type = 'FocusRegularPosition', position = case.absolute })) end
      assert(f.opens == 1, 'queued target must not overlap native leg')
      f:confirm('next-space')
      assert(ten.workspace:state().previousRegularSpaceId == 'space')
      f:confirm(case.final)
      assert(ten.workspace:state().activeRegularSpaceId == case.final and not ten.workspace:state().switch.inFlight)
      assert(#f.presses == 2 and ten.cores.space == first and ten.host == host and ten.windows == windows and f.scans == scans)
      local opens = f.opens
      assert(ten:_submitCommand({ type = 'FocusRegularPosition', position = 9 }))
      assert(f.opens == opens and #ten.workspace:state().regularSpaceIds == 3, 'missing desktop must not create')
      ten:stop(); assert(f.dockObserver.stopped and f.dockLife.stopped)
    end
  end,
  ["SPACE-005 LAY-001 LAY-003 COL-008 WIN-002: composed previous repeats before confirmation and retains inactive Core layouts"] = function()
    local f, ten = workspaceSetup(); focus(ten, 9)
    ten:_submitCommand({ type = 'CycleLayout' })
    ten:_submitCommand({ type = 'ResizeRatioDelta', delta = .05 })
    local first = ten.core
    local saved = first:state().coordinators.space
    assert(saved.layouts.columns.ratio == .55)
    ten:_submitCommand({ type = 'FocusRegularPosition', position = 2 }); f:confirm('next-space')
    local second = ten.core
    assert(first:state().coordinators.space.layouts.columns.ratio == .55 and ten.cores.space == first)
    ten:_submitCommand({ type = 'FocusPreviousRegular' }); ten:_submitCommand({ type = 'FocusPreviousRegular' })
    assert(ten.workspace:state().switch.desiredSpaceId == 'space' and f.opens == 2)
    f:confirm('space')
    assert(ten.core == first and ten.cores['next-space'] == second)
    local restored = first:state().coordinators.space
    assert(restored.activeLayoutId == saved.activeLayoutId and restored.layouts.columns.ratio == .55
      and restored.layouts.columns.stacks[1].members[1] == 9 and restored.layouts.stack.members[1] == 9)
    ten:_submitCommand({ type = 'FocusPreviousRegular' }); f:confirm('next-space')
    assert(#f.presses == 3 and ten.workspace:state().previousRegularSpaceId == 'space')
    ten:stop()
  end,
  ["SPACE-006 SPACE-009 FS-003 WIN-005: Dock removal retires saved placement, rejects late readiness, preserves native lease until death"] = function()
    for _, fullscreen in ipairs({ false, true }) do
      local f, ten = workspaceSetup(); focus(ten, 9)
      local first, route = ten.core, ten.handleRegistry:target(9)
      if fullscreen then
        f.fullscreen = true
        ten:_submitEvent({ type = 'WindowEnteredNativeFullscreen', id = 9, resource = route.lease })
        assert(first:state().manager.windows[9].lifecycle.nativeFullscreen)
      end
      f:activate('next-space')
      f.topology = { { ManagedSpaceID = 'next-space', type = 0 }, { ManagedSpaceID = 'third-space', type = 0 } }
      f.dockObserver.notification(nil, nil, 'AXUIElementDestroyed')
      local orphan = ten.focusHistory:unplacedTarget(9)
      assert(not ten.cores.space and orphan and orphan.uncertain and orphan.window.placementSpaceId == nil)
      assert(ten.handleRegistry:target(9).lease == route.lease and ten.host.handles[9], 'scope removal is not window death')
      local ready = { type = 'WindowReady', id = 9, title = 'late', displayId = 'built-in', spaceId = 'space',
        application = { pid = 8 }, resource = route.lease, metadata = { spaceType = 'user', nativeFullscreen = false } }
      assert(ten:_submitEvent(ready, f.window) == false and not ten.cores.space, 'late callback recreated removed Core')
      -- Definitive regular destination clears the invalid saved source, not its old slot.
      f.fullscreen, f.owners = false, { 'next-space' }
      ready.spaceId = 'next-space'
      ready.decision = { action = 'manage' }
      ready.metadata.origin, ready.metadata.createdAfterStart = 'targetedReadiness', false
      ready.metadata.role, ready.metadata.subrole = 'AXWindow', 'AXStandardWindow'
      ready.metadata.modal, ready.metadata.movable, ready.metadata.resizable, ready.metadata.selfProcess = false, true, true, false
      ready.metadata.id, ready.metadata.displayId, ready.metadata.spaceId, ready.metadata.application =
        ready.id, ready.displayId, ready.spaceId, ready.application
      assert(ten:_submitEvent(ready, f.window))
      assert(not ten.focusHistory:unplacedTarget(9) and ten.core:state().manager.windows[9].placementSpaceId == 'next-space')
      assert(not ten.core:state().manager.windows[9].lifecycle.nativeFullscreen)
      f.windowWatcher.callback(nil, 'AXUIElementDestroyed')
      assert(not ten.handleRegistry:target(9) and not ten.core:state().manager.windows[9])
      ten:stop()
    end
  end,
  ["SPACE-006 WIN-005: destruction after removed scope clears orphan without recreating Core"] = function()
    local f, ten = workspaceSetup(); local death = f.windowWatcher.callback
    f:activate('next-space')
    f.topology = { { ManagedSpaceID = 'next-space', type = 0 }, { ManagedSpaceID = 'third-space', type = 0 } }
    f.dockObserver.notification(nil, nil, 'AXUIElementDestroyed')
    assert(ten.focusHistory:unplacedTarget(9) and not ten.cores.space)
    death(nil, 'AXUIElementDestroyed')
    assert(not ten.focusHistory:unplacedTarget(9) and not ten.handleRegistry:target(9) and not ten.cores.space)
    ten:stop()
  end,
  ["FOCUS-006 CMD-005 SPACE-005: desktop command cancels local/global focus and rejects previous during switch"] = function()
    local f, ten = workspaceSetup(); focus(ten, 9)
    ten:_withEffectBatch(function()
      ten:_submitCommand({ type = 'FocusNext' })
      ten:_submitCommand({ type = 'FocusRegularPosition', position = 2 })
    end)
    assert(f.focuses == 0 and not ten.focusHistory:pending() and not ten.core:state().manager.focus.desiredBySpace.space.pending)
    local accepted, reason = ten:_submitCommand({ type = 'FocusManagedPrevious' })
    assert(not accepted and reason == 'desktop-switch-pending')
    ten:_submitCommand({ type = 'FocusNext' }) -- same-scope commands remain available
    assert(ten.core:state().manager.focus.desiredBySpace.space.pending)
    f:confirm('next-space')
    assert(not ten.cores.space:state().manager.focus.desiredBySpace.space.pending, 'departure must cancel local focus authority')
    assert(not ten.focusHistory:pending(), 'departure must cancel global pending from same-scope focus')
    ten:stop()
  end,
  ["FS-005 SPACE-001 SPACE-004: composed desktop commands work from fullscreen and skip fullscreen positions"] = function()
    local f, ten = workspaceSetup()
    f.topology = { { ManagedSpaceID = 'space', type = 0 }, { ManagedSpaceID = 'full', type = 4 },
      { ManagedSpaceID = 'next-space', type = 0 }, { ManagedSpaceID = 'third-space', type = 0 } }
    f:activate('full'); assert(ten.suspended)
    local accepted, reason = ten:_submitCommand({ type = 'FocusNext' })
    assert(not accepted and reason == 'native-fullscreen-has-no-regular-layout')
    assert(ten:_submitCommand({ type = 'FocusRegularPosition', position = 2 }))
    local op = ten.workspace:state().switch.inFlight
    assert(op.sourceId == 'full' and op.sourceType == 'fullscreen' and op.destinationId == 'next-space')
    f:confirm('next-space')
    assert(not ten.suspended and ten.core.spaceId == 'next-space' and ten.workspace:state().previousRegularSpaceId == 'space')
    ten:_submitCommand({ type = 'FocusRelativeRegular', delta = -1 }); f:confirm('space')
    assert(ten.workspace:state().activeRegularSpaceId == 'space')
    ten:stop()
  end,
  ["FOCUS-005 CMD-005: desktop command cancels already-issued global previous authority without native reversal"] = function()
    local f, ten = workspaceSetup(); focus(ten, 9)
    local other = ten:_coreForSpace('next-space')
    other:submit({ type = 'WindowReady', id = 10, displayId = 'built-in', spaceId = 'next-space', application = { pid = 8 } })
    local calls = 0
    ten.handleRegistry:remember(10, 'next-space', { id = function() return 10 end,
      focus = function() calls = calls + 1 end }, 8, 100, ten.host.appResources[8].lease)
    ten.focusHistory:observe({ windowId = 10, spaceId = 'next-space' }); focus(ten, 9)
    assert(ten:_submitCommand({ type = 'FocusManagedPrevious' }))
    assert(calls == 1 and ten.focusHistory:pending().windowId == 10)
    ten:_submitCommand({ type = 'FocusRegularPosition', position = 3 })
    assert(not ten.focusHistory:pending() and not other:state().manager.focus.desiredBySpace['next-space'].pending)
    focus(ten, 10) -- late native observation remains reality, not reissued intent
    assert(calls == 1 and not ten.focusHistory:pending())
    f:confirm('third-space'); assert(calls == 1)
    ten:stop()
  end,
  ["STATE-002 CMD-005: command reentry during native open queues desired without a second operation"] = function()
    local f, ten = workspaceSetup()
    f.onOpen = function()
      f.onOpen = nil
      assert(ten.workspace:state().switch.inFlight.destinationId == 'next-space')
      ten:_submitCommand({ type = 'FocusRelativeRegular', delta = 1 })
    end
    ten:_submitCommand({ type = 'FocusRelativeRegular', delta = 1 })
    assert(f.opens == 1 and ten.workspace:state().switch.desiredSpaceId == 'third-space')
    f:confirm('next-space'); f:confirm('third-space')
    assert(#f.presses == 2 and not ten.workspace:state().switch.inFlight)
    ten:stop()
  end,
  ["STATE-002 CMD-005: reentrant stop discards workspace effect batch and stale native timer"] = function()
    local f, ten = workspaceSetup()
    local original = f.window.setFrame
    f.window.setFrame = function(window, frame, duration) original(window, frame, duration); ten:stop() end
    f.actual = { x = 7, y = 0, w = 1, h = 1 }
    ten:_submitCommand({ type = 'FocusRegularPosition', position = 2 })
    assert(not ten.started and f.opens == 0 and not ten.workspace and not ten.spaces)
    f, ten = workspaceSetup()
    ten:_submitCommand({ type = 'FocusRegularPosition', position = 2 })
    local timer
    for _, candidate in ipairs(f.timers) do if candidate.delay == .3 then timer = candidate end end
    ten:stop(); timer.callback()
    assert(#f.presses == 0 and not ten.started and f.dockObserver.stopped)
  end,
  ["WIN-005 COL-005: native mailbox alone removes focused close and recovers occupied or emptied columns"] = function()
    for _,count in ipairs({2,3}) do
      local f = fakeHs(); local app=f.window:application(); local windows={f.window}
      local elements={}; local mailbox, token, rows
      hs.timer.doEvery=function(delay,cb)
        if delay==0.05 then mailbox=cb end
        return {stop=function()end}
      end
      f.window.isFullScreen=function()return false end
      f.window.focus=function()f.focusedWindow=f.window end
      elements[f.window]={attributeValue=function()return false end,isAttributeSettable=function()return true end,isValid=function()return nil end}
      hs.axuielement.windowElement=function(w)return elements[w]end
      local factory={create=function()return {set=function(_,_,t)token=t end,
        poll=function()return rows or {} end,stop=function()end}end}
      local ten=dofile('10bucks.spoon/init.lua').new(factory):configure({builtInDisplayUUID='built-in'}):start()
      ten.core:submit({type='CycleLayout'})
      for i=2,count do
        local w={};for k,v in pairs(f.window)do w[k]=v end
        w.id=function()return 8+i end;w.newWatcher=function()return {start=function()end,stop=function()end}end
        w.focus=function()f.focusedWindow=w end;w.setFrame=function()end
        windows[i]=w;elements[w]={attributeValue=function()return false end,isAttributeSettable=function()return true end,isValid=function()return nil end}
        f.appWatcher.callback(w,'AXWindowCreated')
        f.focusedWindow=w;ten.host:observeFocus()
      end
      local dead=windows[count]:id(); local lease=ten.host.handles[dead].lease
      assert(mailbox and ten.host.validityTarget.id==dead)
      rows={{token=token,status='invalid',error=-25202}}
      mailbox() -- no window/app callback, no reducer death injection
      local state=ten.core:state()
      assert(not state.manager.windows[dead] and not ten.host.handles[dead])
      assert(not ten.handleRegistry:target(dead) and not ten.windows:handleForId(dead))
      local columns=state.coordinators.space.layouts.columns
      assert(#columns.stacks==(count==2 and 1 or 2))
      assert(f.focusedWindow==windows[count-1], 'mailbox removal must trigger native recovery')
      for _,group in ipairs(columns.stacks)do for _,id in ipairs(group.members)do assert(id~=dead)end end
      ten:stop()
    end
  end,
  ["DISC-002 LAY-003: same-scope geometry refresh preserves pending positive creation admission"] = function()
    local f = fakeHs(); f.members = {}; f.owners = {}
    local timers = {}
    hs.timer.doAfter = function(delay, callback)
      local t = { callback = callback, stop = function(self) self.stopped = true end }
      timers[#timers + 1] = t; return t
    end
    local ten = load(f):start()
    f.appWatcher.callback(f.window, "AXWindowCreated")
    local pending = ten.host.readiness[9]; assert(pending and pending.timer)
    local timer = pending.timer
    f.geometry = { x = 0, y = 0, w = 120, h = 100 }
    f.screenWatcher.callback()
    assert(ten.host.readiness[9] == pending and pending.timer == timer, "same scope refresh cancelled creation")
    f.owners = { "space" }; timer.callback()
    assert(ten.core:state().manager.windows[9], "positive owner after geometry refresh remains unmanaged")
    ten:stop()
  end,
  ["WIN-005 FOCUS-004 STATE-002: command effects remove an invalid target when native close omitted focus and destruction callbacks"] = function()
    local f = fakeHs(); f.focusedWindow = f.window
    local ten = load(f); ten:start()
    local closed = false; local nativeFocuses = 0
    local window = {}; for key, value in pairs(f.window) do window[key] = value end
    window.id = function() return 10 end
    window.newWatcher = function() return { start = function() end, stop = function() end } end
    window.focus = function() nativeFocuses = nativeFocuses + 1; f.focusedWindow = window end
    window.frame = function() return { x = 0, y = 32, w = 100, h = 48 } end
    window.setFrame = function() end
    local original = hs.axuielement.windowElement
    hs.axuielement.windowElement = function(w)
      if w == window then return { attributeValue = function() return false end, isAttributeSettable = function() return true end,
        isValid = function() return not closed end } end
      return original(w)
    end
    f.appWatcher.callback(window, "AXWindowCreated")
    ten:_submitCommand({ type = "CycleLayout" })
    f.focusedWindow = f.window; focus(ten, 9)
    closed = true -- No native callback reaches Host.
    local before = nativeFocuses
    ten:_submitCommand({ type = "FocusRightGroup" })
    assert(not ten.core:state().manager.windows[10], "dead effect target must be removed before native focus")
    assert(nativeFocuses == before and not ten.focusHistory:pending())
    assert(#ten.core:state().coordinators.space.layouts.columns.stacks == 1 and f.actual.w == 100)
    ten:stop()
  end,
  ["STATE-008 LIFE-001 LIFE-002 BAR-005: bootstrap preserves minimized/hidden slots but excludes unavailable navigation and frames"] = function()
    for _, shape in ipairs({ "minimized", "hidden", "both" }) do
      local f = fakeHs()
      f.window.isMinimized = function() return shape ~= "hidden" end
      f.window:application().isHidden = function() return shape ~= "minimized" end
      local ten = load(f); ten:start()
      local state = ten.core:state(); local life = state.manager.windows[9].lifecycle
      assert(life.minimized == (shape ~= "hidden") and life.appHidden == (shape ~= "minimized"))
      assert(#state.manager.spaces.space.memberIds == 1 and f.frames == 0)
      assert(f.canvas.elements[4].text:find("(0/0)", 1, true))
      ten:_submitCommand({ type = "FocusNext" }); assert(f.focuses == 0)
      ten:stop()
    end
  end,
  ["FOCUS-005 CMD-001: unavailable previous target rejects before installing stranded global pending"] = function()
    local f = fakeHs(); local ten = load(f); ten:start()
    focus(ten, 9)
    local other = { frame = function() return f.actual end, setFrame = function() end }
    ten.core:submit({ type = "WindowReady", id = 10, title = "Second", displayId = "built-in", spaceId = "space", application = { pid = 8 } })
    ten.handleRegistry:remember(10, "space", other, 8, 100, ten.host.appResources[8].lease)
    focus(ten, 10)
    ten:_submitEvent({ type = "WindowMinimized", id = 9, resource = ten.handleRegistry:target(9).lease })
    local accepted, reason = ten:_submitCommand({ type = "FocusManagedPrevious" })
    assert(not accepted and reason == "previous-managed-window-unavailable" and not ten.focusHistory:pending())
    ten:stop()
  end,
  ["STATE-002 PERF-003 FOCUS-006: stale frame readback skips old geometry but preserves current focus"] = function()
    local f = fakeHs(); local ten = load(f); ten:start()
    ten.core:submit({ type = "WindowReady", id = 10, title = "Second", displayId = "built-in", spaceId = "space", application = { pid = 8 } })
    ten.handleRegistry:remember(10, "space", { frame = function() return { x = 50, y = 32, w = 50, h = 48 } end, setFrame = function() end }, 8, 100, ten.host.appResources[8].lease)
    focus(ten, 10) -- confirm admission before the deliberate mouse focus
    focus(ten, 9)
    local focusCalls = 0
    f.focusedWindow = f.window
    local target = ten.handleRegistry:resolve({ windowId = 10, spaceId = "space" })
    target.id = function() return 10 end
    target.focus = function() focusCalls = focusCalls + 1 end
    local original = f.window.frame; local injected = false
    f.window.frame = function()
      local before = original()
      if not injected then injected = true; ten:_submitCommand({ type = "ActivateLayout", layoutId = "columns" }) end
      return before
    end
    f.actual = { x = 7, y = 0, w = 1, h = 1 }
    ten:_submitCommand({ type = "FocusNext" })
    assert(ten.core:state().coordinators.space.activeLayoutId == "columns" and f.actual.w == 50)
    assert(focusCalls == 1, "stale geometry must not suppress still-current focus")
    ten:stop()
  end,
  ["STATE-002 WIN-007: unrelated title commit cannot discard explicit reflow geometry"] = function()
    local f = fakeHs(); local ten = load(f); ten:start()
    local writes = f.frames; f.actual = { x = 7, y = 0, w = 1, h = 1 }
    ten:_withEffectBatch(function()
      ten:_submitCommand({ type = "Reflow" })
      ten:_submitEvent({ type = "WindowTitleChanged", id = 9, title = "Updated", resource = ten.handleRegistry:target(9).lease })
    end)
    assert(f.frames == writes + 1 and f.actual.w == 100)
    ten:stop()
  end,
  ["FOCUS-006 CMD-005: non-focus commands preserve pending focus authority in combined batches"] = function()
    for _, command in ipairs({ { type = "Reflow" }, { type = "ActivateLayout", layoutId = "stack" } }) do
      local f = fakeHs(); local ten = load(f); ten:start(); focus(ten, 9); f.focusedWindow = f.window
      ten:_withEffectBatch(function()
        ten:_submitCommand({ type = "FocusNext" }); ten:_submitCommand(command)
      end)
      assert(f.focuses == 1 and not ten.core:state().manager.focus.desiredBySpace.space.pending)
      ten:stop()
    end
  end,
  ["FOCUS-005 CMD-005: reentrant global previous request supersedes local focus without reversal"] = function()
    local f = fakeHs(); local ten = load(f); ten:start()
    local target = { id = function() return 10 end, focus = function() f.previousFocuses = (f.previousFocuses or 0) + 1 end }
    ten.handleRegistry:remember(10, "next-space", target, 8, 100, ten.host.appResources[8].lease)
    ten:_coreForSpace("next-space"):submit({ type = "WindowReady", id = 10, title = "Other", displayId = "built-in",
      spaceId = "next-space", application = { pid = 8 }, focusAuthority = false })
    ten.focusHistory:observe({ windowId = 10, spaceId = "next-space" }); focus(ten, 9)
    f.focusedWindow = f.window
    local original = f.window.setFrame
    f.window.setFrame = function(window, frame, duration) original(window, frame, duration); ten:_submitCommand({ type = "FocusManagedPrevious" }) end
    f.actual = { x = 7, y = 0, w = 1, h = 1 }
    ten:_submitCommand({ type = "FocusNext" })
    assert(f.previousFocuses == 1 and f.focuses == 0 and ten.focusHistory:pending().windowId == 10)
    assert(not ten.core:state().manager.focus.desiredBySpace.space.pending, "suppressed source request must retire")
    focus(ten, 10) -- destination confirms global request
    assert(not ten.focusHistory:pending())
    focus(ten, 9) -- return / mouse focus on source is no longer stale
    assert(ten.core:state().coordinators.space.layouts.stack.selectedId == 9)
    ten:_submitCommand({ type = "FocusNext" })
    assert(f.focuses == 1)
    ten:stop()
  end,
  ["FOCUS-006 STATE-002: title commit in effect batch does not cancel current navigation request"] = function()
    local f = fakeHs(); local ten = load(f); ten:start(); focus(ten, 9)
    f.focusedWindow = f.window
    ten:_withEffectBatch(function()
      ten:_submitCommand({ type = "FocusNext" })
      ten:_submitEvent({ type = "WindowTitleChanged", id = 9, title = "Updated", resource = ten.handleRegistry:target(9).lease })
    end)
    assert(f.focuses == 1 and not ten.core:state().manager.focus.desiredBySpace.space.pending)
    ten:stop()
  end,
  ["FOCUS-006 CMD-001: reentrant rejected target cannot cancel valid pending frame/focus effects"] = function()
    local f = fakeHs(); local ten = load(f); ten:start(); focus(ten, 9)
    f.focusedWindow = f.window
    local original = f.window.setFrame
    f.window.setFrame = function(window, frame, duration)
      original(window, frame, duration)
      ten:_submitCommand({ type = "FocusTarget", windowId = 999 })
    end
    f.actual = { x = 7, y = 0, w = 1, h = 1 }
    ten:_submitCommand({ type = "FocusNext" })
    assert(f.focuses == 1 and not ten.core:state().manager.focus.desiredBySpace.space.pending)
    ten:stop()
  end,
  ["STATE-002 CMD-005: reentrant frame callback cannot execute superseded focus from older intent list"] = function()
    local f = fakeHs(); local ten = load(f); ten:start()
    local ready = { type = "WindowReady", id = 10, title = "Second", displayId = "built-in", spaceId = "space",
      application = { pid = 8, name = "App" } }
    ten.core:submit(ready)
    local requested = {}
    local second = { frame = function() return f.actual end, setFrame = function() end,
      focus = function() requested[#requested + 1] = 10 end, id = function() return 10 end }
    ten.handleRegistry:remember(10, "space", second, 8, 100, ten.host.appResources[8].lease)
    focus(ten, 10)
    local firstFocus = f.window.focus
    f.window.focus = function() requested[#requested + 1] = 9; firstFocus() end
    local original = f.window.setFrame; local injected = false
    f.window.setFrame = function(window, frame, duration)
      original(window, frame, duration)
      if not injected then injected = true; ten:_submitCommand({ type = "FocusNext" }) end
    end
    f.actual = { x = 7, y = 0, w = 1, h = 1 }
    ten:_submitCommand({ type = "FocusNext" }) --9;frame callback queues newer10
    assert(#requested == 1 and requested[1] == 10, "old focus must not execute after newer command was accepted")
    ten:stop()
  end,
  ["CMD-005 STATE-002: one composed batch executes only its latest committed focus intent"] = function()
    local f = fakeHs(); local ten = load(f); ten:start()
    local ready = { type = "WindowReady", id = 10, title = "Second", displayId = "built-in", spaceId = "space",
      application = { pid = 8, name = "App" } }
    ten.core:submit(ready)
    ten.handleRegistry:remember(10, "space", { frame = function() return f.actual end, setFrame = function() end }, 8, 100, ten.host.appResources[8].lease)
    focus(ten, 10)
    local requested = {}
    ten.host.execute = function(_, _, intents)
      for _, intent in ipairs(intents) do if intent.kind == "focus" then requested[#requested + 1] = intent.windowId end end
    end
    ten:_withEffectBatch(function()
      ten.core:submit({ type = "FocusNext" })
      ten.core:submit({ type = "FocusNext" })
    end)
    assert(#requested == 1 and requested[1] == 10, "superseded focus effect must never execute")
    ten:stop()
  end,
  ["COL-005 FOCUS-004: real close callback after first split expands survivor and recovers focus"] = function()
    local f = fakeHs(); f.focusedWindow = f.window
    local ten = load(f); ten:start(); ten.core:submit({ type = "CycleLayout" })
    local app = f.window:application(); local close
    local second = {}; for key, value in pairs(f.window) do second[key] = value end
    second.id = function() return 10 end
    second.newWatcher = function(_, callback) close = callback; return { start = function() end, stop = function() end } end
    second.frame = function() return { x = 50, y = 32, w = 50, h = 48 } end
    second.setFrame = function() end; second.focus = function() f.focusedWindow = second end
    local original = hs.axuielement.windowElement
    hs.axuielement.windowElement = function() return original(f.window) end
    f.appWatcher.callback(second, "AXWindowCreated")
    local state = ten.core:state(); assert(#state.coordinators.space.layouts.columns.stacks == 2)
    -- Real missed-destruction path: retain exact AX element, then invalidate it
    -- and deliver only the app focus signal after the user's close.
    local record = ten.host.handles[10]
    record.element = { isValid = function() return false end }
    f.focusedWindow = nil
    f.appWatcher.callback(nil, "AXFocusedWindowChanged")
    state = ten.core:state()
    assert(not state.manager.windows[10] and #state.coordinators.space.layouts.columns.stacks == 1)
    assert(f.actual.x == 0 and f.actual.w == 100, "survivor must project full work area")
    assert(state.manager.focus.desiredBySpace.space.targetId == 9 and f.focuses > 0)
    ten:stop()
  end,
  ["COL-005 FOCUS-004: real close callback in occupied column selects surviving underlying member"] = function()
    local f = fakeHs(); f.focusedWindow = f.window
    local ten = load(f); ten:start(); ten.core:submit({ type = "CycleLayout" })
    local closes, windows = {}, {}
    local original = hs.axuielement.windowElement
    hs.axuielement.windowElement = function() return original(f.window) end
    for _, id in ipairs({ 10, 11 }) do
      local window = {}; for key, value in pairs(f.window) do window[key] = value end
      window.id = function() return id end
      window.newWatcher = function(_, callback) closes[id] = callback; return { start = function() end, stop = function() end } end
      window.frame = function() return { x = 50, y = 32, w = 50, h = 48 } end
      window.setFrame = function() end; window.focus = function() f.focusedWindow = window end
      windows[id] = window; f.appWatcher.callback(window, "AXWindowCreated")
    end
    closes[11](nil, "AXUIElementDestroyed")
    local state = ten.core:state(); local layout = state.coordinators.space.layouts.columns
    assert(not state.manager.windows[11] and layout.stacks[2].selectedId == 10)
    assert(state.manager.focus.desiredBySpace.space.targetId == 10 and f.focusedWindow == windows[10])
    ten:stop()
  end,
  ["PERF-002 DISC-001 WIN-006: cold activation discovers unknown destination owners without global scan and warm return retains order"] = function()
    local f = fakeHs(); local ten = load(f); ten:start()
    local first = ten.core
    local app = f.window:application()
    local second = {}; for key, value in pairs(f.window) do second[key] = value end
    second.id = function() return 10 end
    second.newWatcher = function(_, callback) return { start = function() end, stop = function() end } end
    second.frame = function() return { x = 0, y = 32, w = 100, h = 48 } end
    second.setFrame = function() end
    local windowElement = hs.axuielement.windowElement
    hs.axuielement.windowElement = function(window) return windowElement(f.window) end
    app.allWindows = function() f.scans = f.scans + 1; return { f.window, second } end
    hs.application.runningApplications = function() error("activation performed global scan") end
    local scans = f.scans
    f.activeSpace, f.members, f.owners = "next-space", { 10 }, { "next-space" }
    f.ownerRows = { { kCGWindowNumber = 10, kCGWindowOwnerPID = 8 } }
    f.focusedWindow = second; f.contextWatcher.callback()
    assert(ten.core:state().manager.windows[10] and f.scans == scans + 1)
    assert(first:state().manager.windows[9], "snapshot absence is not death")
    f.activeSpace, f.members, f.owners = "space", { 9 }, { "space" }
    f.focusedWindow = f.window; f.contextWatcher.callback()
    assert(ten.core == first and f.scans == scans + 1 and first:state().manager.spaces.space.memberIds[1] == 9)
    ten:stop()
  end,
  ["PERF-002 WIN-007 BAR-004: real title and duplicate readiness paths avoid frame AX while explicit reflow corrects drift"] = function()
    local f = fakeHs(); f.focusedWindow = f.window
    local ten = load(f); ten:start()
    local reads, writes, scans = f.frameReads, f.frames, f.scans
    f.actual = { x = 7, y = 0, w = 1, h = 1 }
    f.window.title = function() return "Renamed" end
    f.windowWatcher.callback(nil, "AXTitleChanged")
    assert(ten.core:state().manager.windows[9].title == "Renamed")
    assert(f.frameReads == reads and f.frames == writes and f.scans == scans)
    f.appWatcher.callback(f.window, "AXWindowCreated")
    assert(f.frameReads == reads and f.frames == writes and f.scans == scans)
    assert(ten.core:submit({ type = "Reflow" }))
    assert(f.frameReads == reads + 1 and f.frames == writes + 1)
    -- A real navigation command remains a drift synchronization boundary.
    f.actual = { x = 7, y = 0, w = 1, h = 1 }
    reads, writes = f.frameReads, f.frames
    assert(ten.core:submit({ type = "FocusNext" }))
    assert(f.frameReads == reads + 1 and f.frames == writes + 1 and f.focuses == 1)
    ten:stop()
  end,
  ["composition bootstrap and reflow deduplicate actual frames then correct drift"] = function()
    local f = fakeHs(); local ten = load(f); ten:start()
    assert(ten.core:state().manager.windows[9] and f.frames == 1 and f.focuses == 0,
      "cold bootstrap must tile without stealing native focus")
    ten.core:submit({ type = "Reflow" }); assert(f.frames == 1 and f.focuses == 0)
    f.actual = { x = 7, y = 0, w = 100, h = 80 }; ten.core:submit({ type = "Reflow" }); assert(f.frames == 2)
    ten:stop()
  end,
  ["POC-009 FOCUS-006: no-callback unchanged focus confirms through one targeted read"] = function()
    local f = fakeHs(); local ten = load(f); ten:start()
    focus(ten, 9)
    local scans, queries = f.scans, f.focusedWindowQueries
    f.focusedWindow = f.window
    ten.core:submit({ type = "FocusNext" })
    local desired = ten.core:state().manager.focus.desiredBySpace.space
    assert(f.focuses == 1 and f.focusedWindowQueries == queries + 1 and f.scans == scans)
    assert(desired.targetId == 9 and not desired.pending)
    ten:stop()
  end,
  ["POC-009 FOCUS-006: nonmatching read awaits a later ordinary focus callback"] = function()
    local f = fakeHs(); local ten = load(f); ten:start()
    focus(ten, 9)
    local scans, queries = f.scans, f.focusedWindowQueries
    f.focusedWindow = { id = function() return 10 end }
    ten.core:submit({ type = "FocusNext" })
    assert(f.focuses == 1 and f.focusedWindowQueries == queries + 1 and f.scans == scans)
    assert(ten.core:state().manager.focus.desiredBySpace.space.pending)
    focus(ten, 9)
    assert(not ten.core:state().manager.focus.desiredBySpace.space.pending)
    ten:stop()
  end,
  ["FOCUS-001 FOCUS-006: bootstrap samples actual managed focus after readiness without requesting focus"] = function()
    local f = fakeHs(); f.focusedWindow = f.window
    local ten = load(f); ten:start()
    local state = ten.core:state().manager
    local desired = state.focus.desiredBySpace.space
    assert(state.focus.actualWindow.id == 9 and desired.targetId == 9 and not desired.pending)
    assert(#ten.focusHistory:snapshot() == 1 and ten.focusHistory:snapshot()[1].windowId == 9)
    assert(f.focuses == 0 and f.focusedWindowQueries == 1)
    ten:stop()
  end,
  ["FOCUS-001 FOCUS-006: stale AX payload normalizes the current native focus, not its payload"] = function()
    local f = fakeHs(); local ten = load(f); ten:start()
    f.focusedWindow = f.window
    local queries = f.focusedWindowQueries
    f.appWatcher.callback({ id = function() return 99 end }, "AXFocusedWindowChanged")
    assert(f.focusedWindowQueries == queries + 1)
    assert(ten.core:state().manager.focus.actualWindow.id == 9)
    ten:stop()
  end,
  ["FOCUS-001 FOCUS-003 FOCUS-006: cold Space bootstrap observes an earlier focus after independent admission"] = function()
    local f = fakeHs(); f.members = {}
    local ten = load(f); ten:start()
    f.owners, f.focusedWindow = { "next-space" }, f.window
    local beforeRaw = f.focusedWindowQueries
    f.appWatcher.callback({ id = function() return 9 end }, "AXFocusedWindowChanged") -- old host, before Space activation
    assert(f.focusedWindowQueries == beforeRaw + 1)
    assert(ten.core:state().manager.windows[9] == nil and #ten.focusHistory:snapshot() == 0 and f.focuses == 0)
    f.activeSpace, f.members = "next-space", { 9 }
    local queries, focuses = f.focusedWindowQueries, f.focuses
    f.contextWatcher.callback()
    local state = ten.core:state().manager
    local desired = state.focus.desiredBySpace["next-space"]
    assert(state.focus.actualWindow.id == 9 and desired.targetId == 9 and not desired.pending)
    assert(#ten.focusHistory:snapshot() == 1 and ten.focusHistory:snapshot()[1].windowId == 9)
    assert(f.focusedWindowQueries == queries + 1 and f.focuses == focuses)
    ten:stop()
  end,
  ["BAR-006 STATE-002: committed command feedback publishes before native focus execution"] = function()
    local f = fakeHs(); local ten = load(f); ten:start(); focus(ten, 9)
    local observed
    local handle = { id = function() return 10 end, title = function() return "B" end, application = function() return { name = function() return "B" end } end,
      focus = function() observed = f.canvas.elements[4].text end, frame = function() return { x = 0, y = 32, w = 100, h = 48 } end, setFrame = function() end }
    ten.handleRegistry:remember(10, "space", handle, 10)
    ten.core:submit({ type = "WindowReady", id = 10, title = "B", displayId = "built-in", spaceId = "space", application = { pid = 10, name = "B" } })
    assert(observed and observed:find("(2/2)", 1, true))
    ten:stop()
  end,
  ["BAR-003 BAR-004 FOCUS-001: composition publishes global actual presentation without admitting an excluded focus"] = function()
    local f = fakeHs(); local ten = load(f); ten:start()
    assert(f.canvas.elements[4].text:find("No focused window", 1, true))
    ten:_submitEvent({ type = "ActualFocusChanged", id = 99, title = "Popup", applicationName = "Popup App" })
    assert(not ten.core:state().manager.windows[99] and f.canvas.elements[4].text:find("Popup", 1, true))
    ten:_submitEvent({ type = "WindowTitleChanged", id = 99, title = "Renamed popup" })
    assert(f.canvas.elements[4].text:find("Renamed popup", 1, true))
    ten:_submitEvent({ type = "ActualFocusChanged" })
    assert(f.canvas.elements[4].text:find("No focused window", 1, true))
    ten.core:submit({ type = "FocusNext" })
    assert(f.canvas.elements[4].text:find("(1/1)", 1, true))
    f.activeSpace, f.members, f.owners = "next-space", {}, { "next-space" }; f.contextWatcher.callback()
    assert(f.canvas.elements[4].text:find("1 [2]", 1, true))
    f.interfaceStyle = "Dark"; f.appearance.callback()
    assert(f.canvas.elements[1].fillColor.red == .08)
    ten:stop()
  end,
  ["LIFE-001: real Host-to-Windows sink refusal cleans only a newly provisional conflicting route"] = function()
    local f, element = fakeHs(); local ten = load(f); ten:start()
    local stale = { frame = function() return { x = 0, y = 0, w = 1, h = 1 } end, setFrame = function() end, focus = function() end }
    local appLease = ten.host.appResources[8].lease
    ten.handleRegistry:remember(10, "space", stale, 8, 900, appLease)
    ten.core:submit({ type = "WindowReady", id = 10, title = "Retained", displayId = "built-in", spaceId = "space", application = { pid = 8, name = "App" } })
    local candidateWatcher
    local candidate = { isMinimized = function() return false end, id = function() return 10 end, title = function() return "Conflict" end, application = f.window.application,
      role = f.window.role, subrole = f.window.subrole, isFullScreen = function() return false end,
      newWatcher = function(_, callback) candidateWatcher = { callback = callback, start = function() end, stop = function(self) self.stopped = true end }; return candidateWatcher end,
      frame = stale.frame, setFrame = stale.setFrame, focus = stale.focus }
    _G.hs.axuielement.windowElement = function() return element end
    ten.host:_ready(candidate, "created", ten.host.windowCallback)
    assert(ten.core:state().manager.windows[10] and ten.handleRegistry:target(10).lease == 900)
    assert(not ten.host.handles[10] and not ten.windows:handleForId(10) and candidateWatcher.stopped,
      "explicit false cleans only the just-attached provisional resource")
    ten:stop()
  end,
  ["LIFE-001: post-commit native frame error preserves committed route until authoritative destruction"] = function()
    local f, element = fakeHs(); local ten = load(f); ten:start()
    local candidateWatcher
    local candidate = { isMinimized = function() return false end, id = function() return 10 end, title = function() return "Broken frame" end, application = f.window.application,
      role = f.window.role, subrole = f.window.subrole, isFullScreen = function() return false end,
      newWatcher = function(_, callback) candidateWatcher = { callback = callback, start = function() end, stop = function(self) self.stopped = true end }; return candidateWatcher end,
      frame = function() return { x = 9, y = 9, w = 1, h = 1 } end, setFrame = function() error("frame write failed after commit") end, focus = function() end }
    _G.hs.axuielement.windowElement = function() return element end
    assert(not pcall(function() ten.host:_ready(candidate, "created", ten.host.windowCallback) end))
    local target = ten.handleRegistry:target(10)
    assert(ten.core:state().manager.windows[10] and target and ten.host.handles[10] and ten.windows:handleForId(10) == candidate,
      "thrown post-commit effect is not readiness refusal or native death")
    candidateWatcher.callback(nil, "AXUIElementDestroyed")
    assert(not ten.core:state().manager.windows[10] and not ten.handleRegistry:target(10)
      and not ten.host.handles[10] and not ten.windows:handleForId(10))
    ten:stop()
  end,
  ["LIFE-001: regular and fullscreen readiness refuse a conflicting current route before state/history mutation"] = function()
    local f = fakeHs(); local ten = load(f); ten:start(); focus(ten, 9)
    local route, history = ten.handleRegistry:target(9), ten.focusHistory:snapshot()
    local members = #ten.core:state().manager.spaces.space.memberIds
    for _, metadata in ipairs({
      { spaceType = "user", nativeFullscreen = false },
      { spaceType = "fullscreen", nativeFullscreen = true },
    }) do
      local event = { type = "WindowReady", id = 9, title = "conflict", displayId = "built-in", spaceId = metadata.spaceType == "user" and "next-space" or 99,
        application = { pid = 8, name = "App" }, metadata = metadata, decision = { action = "manage" }, resource = route.lease + 100 }
      assert(ten:_submitEvent(event, { id = function() return 9 end }) == false)
      assert(#ten.core:state().manager.spaces.space.memberIds == members and #ten.focusHistory:snapshot() == #history)
      assert(ten.handleRegistry:target(9).lease == route.lease)
    end
    ten:stop()
  end,
  ["LIFE-001 BAR-004: conflicting same-ID focused source updates BAR only, never retained managed routing"] = function()
    local f = fakeHs(); local ten = load(f); ten:start()
    f.focusedWindow = f.window; assert(ten.host:observeFocus())
    local history = ten.focusHistory:snapshot()
    local title, conflictingWatcher = "Conflicting", nil
    local conflicting = { id = function() return 9 end, title = function() return title end, application = f.window.application,
      role = f.window.role, subrole = f.window.subrole, isFullScreen = function() return false end,
      newWatcher = function(_, callback) conflictingWatcher = { callback = callback, start = function() end, stop = function(self) self.stopped = true end }; return conflictingWatcher end }
    f.focusedWindow = conflicting; assert(ten.host:observeFocus())
    assert(ten.core:state().manager.windows[9].title == "Window" and #ten.focusHistory:snapshot() == #history,
      "rejected same-ID focus cannot select or rewrite the retained managed lifetime")
    title = "Conflict renamed"; conflictingWatcher.callback(nil, "AXTitleChanged")
    assert(f.canvas.elements[4].text:find("Conflict renamed", 1, true) and ten.core:state().manager.windows[9].title == "Window")
    ten:stop()
  end,
  ["LIFE-001 BAR-004: focused deferred release promotes without losing actual presentation authority"] = function()
    local f, element = fakeHs(); local ten = load(f); ten:start()
    f.windowWatcher.callback(nil, "AXUIElementDestroyed")
    element.attributeValue = function() return true end
    f.focusedWindow = f.window; assert(ten.host:observeFocus())
    local priorWindowLease, presentationLease = ten.actualPresentation.windowResource, ten.actualPresentation.presentationResource
    assert(priorWindowLease and presentationLease and not ten.host.handles[9], "deferred focus releases only its provisional Host record")
    element.attributeValue = function() return false end
    ten.host:_ready(f.window, "created", ten.host.windowCallback)
    local promoted = ten.handleRegistry:target(9)
    assert(promoted and promoted.lease ~= priorWindowLease and ten.actualPresentation.presentationResource == presentationLease)
    f.window.title = function() return "Promoted title" end
    f.windowWatcher.callback(nil, "AXTitleChanged")
    assert(f.canvas.elements[4].text:find("Promoted title", 1, true), "managed title carries the retained presentation authority")
    f.fullscreen = true; f.windowWatcher.callback(nil, "AXWindowResized")
    assert(ten.actualPresentation.nativeFullscreen, "managed fullscreen carries the retained presentation authority")
    ten:stop()
  end,
  ["BAR-004 LIFE-001: stable presentation token survives unavailable title attachment through release and promotion"] = function()
    for _, shape in ipairs({ "nil", "start-failed" }) do
      local f, element = fakeHs(); local ten = load(f); ten:start()
      f.windowWatcher.callback(nil, "AXUIElementDestroyed")
      element.attributeValue = function() return true end
      local original = f.window.newWatcher
      f.window.newWatcher = function(_, callback)
        if shape == "nil" then return nil end
        return { callback = callback, start = function() error("title watcher unavailable") end, stop = function(self) self.stopped = true end }
      end
      f.focusedWindow = f.window; assert(ten.host:observeFocus())
      local oldLease, presentationLease = ten.actualPresentation.windowResource, ten.actualPresentation.presentationResource
      assert(oldLease and presentationLease and not ten.host.handles[9])
      f.window.newWatcher = original; element.attributeValue = function() return false end
      ten.host:_ready(f.window, "created", ten.host.windowCallback)
      assert(ten.handleRegistry:target(9).lease ~= oldLease and ten.actualPresentation.presentationResource == presentationLease)
      f.window.title = function() return shape .. " promoted" end
      f.windowWatcher.callback(nil, "AXTitleChanged")
      assert(f.canvas.elements[4].text:find(shape .. " promoted", 1, true))
      ten:stop()
    end
  end,
  ["LIFE-001 BAR-004: independent accepted app lease clears conflicting focused source without harming managed A"] = function()
    local f = fakeHs(); local ten = load(f); ten:start()
    local appB = { pid = function() return 88 end, name = function() return "B" end, bundleID = function() return "b" end }
    local watcher
    local conflict = { id = function() return 9 end, title = function() return "B focused" end, application = function() return appB end,
      role = f.window.role, subrole = f.window.subrole, isFullScreen = function() return false end,
      newWatcher = function(_, callback) watcher = { callback = callback, start = function() end, stop = function(self) self.stopped = true end }; return watcher end }
    f.focusedWindow = conflict; assert(ten.host:observeFocus())
    local appBLease = ten.host.appResources[88].lease
    assert(ten.actualPresentation.appResource == appBLease and ten.core:state().manager.windows[9])
    f.life.callback(nil, _G.hs.application.watcher.terminated, appB)
    assert(next(ten.actualPresentation) == nil and not ten.host.appResources[88] and ten.core:state().manager.windows[9]
      and ten.handleRegistry:target(9), "B termination clears only its current actual source")
    ten:stop()
  end,
  ["LIFE-001 BAR-004: deferred same-PID presentation termination ends BAR only and preserves accepted A"] = function()
    local f = fakeHs(); local ten = load(f); ten:start()
    local appA, watcher = f.window:application(), nil
    local appB = { pid = appA.pid, name = appA.name, bundleID = appA.bundleID }
    local conflict = { id = function() return 9 end, title = function() return "Same PID B" end, application = function() return appB end,
      role = f.window.role, subrole = f.window.subrole, isFullScreen = function() return false end,
      newWatcher = function(_, callback) watcher = { callback = callback, start = function() end, stop = function(self) self.stopped = true end }; return watcher end }
    f.focusedWindow = conflict; assert(ten.host:observeFocus())
    local token = ten.actualPresentation.presentationResource
    f.life.callback(nil, _G.hs.application.watcher.terminated, appB)
    assert(watcher.stopped and next(ten.actualPresentation) == nil and ten.host.appResources[8].app == appA
      and ten.core:state().manager.windows[9] and ten.handleRegistry:target(9), "PresentationEnded must not fan out shared PID lifecycle")
    assert(token and not ten.focusHistory:pending())
    ten:stop()
  end,
  ["composition created/destroyed and availability callbacks update replacement Core only"] = function()
    local f, element = fakeHs(); local ten = load(f); ten:start()
    f.appWatcher.callback(f.window, "AXWindowCreated"); assert(ten.core:state().manager.windows[9])
    f.windowWatcher.callback(nil, "AXWindowMiniaturized"); assert(ten.core:state().manager.windows[9] and f.frames == 1)
    f.actual = { x = 5, y = 0, w = 1, h = 1 }; f.windowWatcher.callback(nil, "AXWindowDeminiaturized"); assert(f.frames == 2)
    f.life.callback(nil, _G.hs.application.watcher.hidden, f.window:application()); assert(ten.core:state().manager.windows[9])
    f.life.callback(nil, _G.hs.application.watcher.unhidden, f.window:application()); assert(ten.core:state().manager.windows[9])
    f.windowWatcher.callback(nil, "AXUIElementDestroyed"); assert(not ten.core:state().manager.windows[9] and not ten.host.handles[9])
    ten:stop()
  end,
  ["composition unknown focus never admits or scans and inactive creation defers"] = function()
    local f, element = fakeHs(); local ten = load(f); ten:start(); local scans = f.scans
    ten.windows:_window({ kind = "focus", id = 99 }, ten.windows.generation); assert(not ten.core:state().manager.windows[99] and f.scans == scans)
    f.windowWatcher.callback(nil, "AXUIElementDestroyed"); f.owners = { "other" }; f.appWatcher.callback(f.window, "AXWindowCreated"); assert(not ten.core:state().manager.windows[9])
    ten:stop()
  end,
  ["LIFE-001: post-bootstrap bind failure clears every scope route before changed-allocation retry"] = function()
    local f = fakeHs({ failBind = 2 }); local ten = load(f)
    assert(not pcall(function() ten:start() end))
    assert(not ten.started and ten.host == nil and f.deleted == 4, "expected owned host watchers and first binding rollback")
    assert(not ten.handleRegistry:target(9) and #ten.focusHistory:snapshot() == 0 and next(ten.actualPresentation) == nil,
      "failed startup must use whole-scope cleanup, not retain bootstrap state")
    local originalApps = _G.hs.application.runningApplications
    local preface = { pid = function() return 77 end, name = function() return "Preface" end, bundleID = function() return "preface" end,
      allWindows = function() return {} end, newWatcher = function(_, callback) return { start = function() end, stop = function() end } end }
    _G.hs.application.runningApplications = function() return { preface, f.window:application() } end
    _G.hs.hotkey.bind = function(_, _, cb) local h = { delete = function(self) if not self.deleted then self.deleted = true; f.deleted = f.deleted + 1 end end }; f.bindings[#f.bindings + 1] = { callback = cb, handle = h }; return h end
    ten:start(); assert(ten.started and ten.handleRegistry:target(9).lease ~= 2, "changed native allocation must not collide with a failed-start route")
    ten:stop(); _G.hs.application.runningApplications = originalApps
    f = fakeHs({ bootstrapFails = true }); ten = load(f); ten:start()
    assert(ten.started and ten.host and not ten.core:state().manager.windows[9], "one app bootstrap failure must defer rather than abort startup")
    ten:stop()
  end,
  ["configureFile then bindHotkeys then start retains canary instrumentation"] = function()
    local f = fakeHs()
    local ten = loadConfiguredFile(f, { builtInDisplayUUID = "built-in", canaryInstrumentation = true })
    local status = ten:canaryStatus()
    assert(ten.config.canaryInstrumentation == true)
    assert(status.enabled and status.started and not status.suspended and status.memberCount == 1 and status.activeTimers == 1)
    ten:stop(); assert(ten:canaryStatus().started == false)
  end,
  ["Canary A instrumentation exposes only aggregate runtime status"] = function()
    local f = fakeHs(); local ten = load(f)
    ten:configure({ builtInDisplayUUID = "built-in", canaryInstrumentation = true })
    ten:start()
    local status = ten:canaryStatus()
    assert(status.enabled and status.started and not status.suspended and status.memberCount == 1 and status.activeTimers == 1)
    assert(status.counts["event.WindowReady"] == 1 and status.counts.reducerCommitVersions == 1)
    ten:stop(); assert(ten:canaryStatus().started == false)
  end,
  ["FOCUS-001 FOCUS-005 FOCUS-006 CMD-005 COL-007: global previous confirmation routes by retained Core for every callback/activation order"] = function()
    local function crossSpaceSetup(confirmImmediately, withColumns)
      local f = fakeHs(); local ten = load(f); ten:start()
      focus(ten, 9)
      local firstCore = ten.core
      local columnHandle
      if withColumns then
        firstCore:submit({ type = "WindowReady", id = 11, title = "Column", displayId = "built-in", spaceId = "space", application = { pid = 11, name = "Column" } })
        columnHandle = { id = function() return 11 end, title = function() return "Column" end,
          application = function() return { name = function() return "Column" end } end, focus = function() end,
          frame = function() return { x = 0, y = 0, w = 100, h = 80 } end, setFrame = function() end }
        ten.handleRegistry:remember(11, "space", columnHandle, 11)
        firstCore:submit({ type = "CycleLayout" })
        focus(ten, 9)
      end
      f.activeSpace, f.members, f.owners = "next-space", {}, { "next-space" }
      f.contextWatcher.callback()
      ten.core:submit({ type = "WindowReady", id = 10, title = "Other", displayId = "built-in", spaceId = "next-space", application = { pid = 10, name = "Other" } })
      local otherFocuses = 0
      local otherHandle = { id = function() return 10 end, title = function() return "Other" end,
        application = function() return { name = function() return "Other" end } end,
        focus = function() otherFocuses = otherFocuses + 1 end,
        frame = function() return { x = 0, y = 0, w = 100, h = 80 } end, setFrame = function() end }
      ten.handleRegistry:remember(10, "next-space", otherHandle, 10)
      focus(ten, 10)
      if confirmImmediately then f.focusedWindow = f.window end
      assert(ten:_submitCommand({ type = "FocusManagedPrevious" }))
      if not confirmImmediately then
        local targetDesired = firstCore:state().manager.focus.desiredBySpace.space
        assert(targetDesired.pending and targetDesired.targetId == 9) -- committed before the native cross-Space effect
        focus(ten, 99) -- unmanaged focus preserves the managed anchor
        focus(ten, 10) -- stale managed callback cannot replace the request
        targetDesired = firstCore:state().manager.focus.desiredBySpace.space
        assert(ten.focusHistory:pending().windowId == 9 and targetDesired.pending and targetDesired.targetId == 9)
      end
      return f, ten, firstCore, function() return otherFocuses end, otherHandle, columnHandle
    end

    local cases = {
      {
        name = "POC-009 matching cross-Space read confirms pending, later callback is harmless, and mouse h/l works",
        run = function()
          local f, ten, firstCore, otherFocuses, otherHandle, columnHandle = crossSpaceSetup(true, true)
          assert(ten.focusHistory:pending() == nil and not firstCore:state().manager.focus.desiredBySpace.space.pending)
          f.appWatcher.callback(f.window, "AXFocusedWindowChanged") -- later real callback
          assert(ten.focusHistory:pending() == nil and not firstCore:state().manager.focus.desiredBySpace.space.pending)
          f.focusedWindow = otherHandle
          assert(ten:_submitCommand({ type = "FocusManagedPrevious" }))
          assert(otherFocuses() == 1 and ten.focusHistory:pending() == nil)
          f.activeSpace, f.members, f.owners = "space", { 9 }, { "space" }
          f.contextWatcher.callback()
          focus(ten, 11) -- native mouse focus
          assert(ten.core == firstCore and ten.core:state().coordinators.space.layouts.columns.activeStack == 2)
          f.focusedWindow = f.window
          ten.core:submit({ type = "FocusLeftGroup" })
          assert(not ten.core:state().manager.focus.desiredBySpace.space.pending)
          f.focusedWindow = columnHandle
          ten.core:submit({ type = "FocusRightGroup" })
          assert(not ten.core:state().manager.focus.desiredBySpace.space.pending)
          ten:stop()
        end,
      },
      {
        name = "managed focus callback before Space activation",
        run = function()
          local f, ten, firstCore, otherFocuses = crossSpaceSetup()
          -- The old host receives the target focus while its context still says
          -- next-space. Its descriptor must retain the confirmed source Space.
          f.owners, f.focusedWindow = { "space" }, f.window
          f.appWatcher.callback(f.window, "AXFocusedWindowChanged")
          assert(ten.handleRegistry:resolve({ windowId = 9, spaceId = "space" }) == f.window)
          assert(ten.focusHistory:pending() == nil)
          assert(not firstCore:state().manager.focus.desiredBySpace.space.pending)
          f.activeSpace, f.members = "space", { 9 }
          f.contextWatcher.callback()
          assert(ten.core == firstCore and not ten.core:state().manager.focus.desiredBySpace.space.pending)
          local queries = f.focusedWindowQueries
          assert(ten:_submitCommand({ type = "FocusManagedPrevious" }))
          assert(otherFocuses() == 1 and f.focusedWindowQueries == queries + 1 and ten.focusHistory:pending().windowId == 10)
          ten:stop()
        end,
      },
      {
        name = "Space activation before managed focus callback",
        run = function()
          local f, ten, firstCore, otherFocuses = crossSpaceSetup()
          f.activeSpace, f.members, f.owners = "space", { 9 }, { "space" }
          f.contextWatcher.callback()
          assert(ten.core == firstCore and ten.core:state().manager.focus.desiredBySpace.space.pending)
          f.focusedWindow = f.window
          f.appWatcher.callback(f.window, "AXFocusedWindowChanged")
          assert(ten.focusHistory:pending() == nil)
          assert(not ten.core:state().manager.focus.desiredBySpace.space.pending)
          assert(ten:_submitCommand({ type = "FocusManagedPrevious" }))
          assert(otherFocuses() == 1 and ten.focusHistory:pending().windowId == 10)
          ten:stop()
        end,
      },
      {
        name = "same-Space A to B to previous A confirmation to previous B",
        run = function()
          local f = fakeHs(); local ten = load(f); ten:start()
          focus(ten, 9)
          ten.core:submit({ type = "WindowReady", id = 10, title = "B", displayId = "built-in", spaceId = "space", application = { pid = 10, name = "B" } })
          ten.handleRegistry:remember(10, "space", { id = function() return 10 end, title = function() return "B" end,
            application = function() return { name = function() return "B" end } end, focus = function() end,
            frame = function() return { x = 0, y = 0, w = 100, h = 80 } end, setFrame = function() end }, 10)
          focus(ten, 10)
          assert(ten:_submitCommand({ type = "FocusManagedPrevious" }))
          assert(ten.core:state().manager.focus.desiredBySpace.space.targetId == 9)
          focus(ten, 9)
          assert(ten.focusHistory:pending() == nil and not ten.core:state().manager.focus.desiredBySpace.space.pending)
          assert(ten:_submitCommand({ type = "FocusManagedPrevious" }))
          assert(ten.core:state().manager.focus.desiredBySpace.space.targetId == 10)
          ten:stop()
        end,
      },
      {
        name = "mouse focus after previous confirmation enables first directional command",
        run = function()
          local f = fakeHs(); local ten = load(f); ten:start()
          focus(ten, 9)
          ten.core:submit({ type = "WindowReady", id = 10, title = "B", displayId = "built-in", spaceId = "space", application = { pid = 10, name = "B" } })
          ten.handleRegistry:remember(10, "space", { id = function() return 10 end, title = function() return "B" end,
            application = function() return { name = function() return "B" end } end, focus = function() end,
            frame = function() return { x = 0, y = 0, w = 100, h = 80 } end, setFrame = function() end }, 10)
          focus(ten, 10)
          ten.core:submit({ type = "CycleLayout" })
          assert(ten:_submitCommand({ type = "FocusManagedPrevious" }))
          focus(ten, 9)
          focus(ten, 10) -- mouse/native focus
          assert(not ten.core:state().manager.focus.desiredBySpace.space.pending)
          assert(ten.core:state().coordinators.space.layouts.columns.activeStack == 2)
          ten.core:submit({ type = "FocusLeftGroup" })
          local desired = ten.core:state().manager.focus.desiredBySpace.space
          assert(desired.pending and desired.targetId == 9)
          ten:stop()
        end,
      },
    }
    for _, case in ipairs(cases) do case.run() end
  end,
  ["FOCUS-005 destroyed global previous target is skipped without native focus or scan"] = function()
    local f = fakeHs(); local ten = load(f); ten:start()
    focus(ten, 9)
    local stale = { focus = function() error("destroyed handle focused") end }
    ten.focusHistory:observe({ windowId = 10, spaceId = "other" })
    ten.handleRegistry:remember(10, "other", stale, 10)
    local scans = f.scans
    local accepted, reason = ten:_submitCommand({ type = "FocusManagedPrevious" })
    assert(not accepted and reason == "no-previous-managed-window" and f.scans == scans)
    assert(#ten.focusHistory:snapshot() == 1)
    ten:stop()
  end,
  ["BAR-006 ENV-004: retained Space bootstrap uses changed work area on its first frame"] = function()
    local f = fakeHs(); local ten = load(f); ten:start()
    f.activeSpace, f.members, f.owners = "next-space", {}, { "next-space" }; f.contextWatcher.callback()
    f.geometry = { x = 10, y = 0, w = 200, h = 100 }; f.actual = { x = 0, y = 0, w = 1, h = 1 }
    local writes, setFrame = {}, f.window.setFrame
    f.window.setFrame = function(window, frame, duration)
      writes[#writes + 1] = frame
      setFrame(window, frame, duration)
    end
    f.activeSpace, f.members, f.owners = "space", { 9 }, { "space" }; f.contextWatcher.callback()
    assert(#writes == 1, "bootstrap must not write stale geometry then correct it")
    assert(writes[1].x == 10 and writes[1].w == 200 and writes[1].y == 32 and writes[1].h == 68)
    ten:stop()
  end,
  ["regular Spaces retain independent Core state across A-to-B-to-A activation"] = function()
    local f = fakeHs(); local ten = load(f); ten:start()
    local firstCore, oldWindowWatcher, oldSpaceWatcher = ten.core, f.windowWatcher.callback, f.contextWatcher.callback
    local firstMember = firstCore:state().manager.spaces.space.memberIds[1]
    local scans, frames = f.scans, f.frames

    f.contextWatcher.callback()
    assert(ten.core == firstCore and f.scans == scans and f.frames == frames)

    f.activeSpace, f.members, f.owners = "next-space", {}, { "space" }
    f.contextWatcher.callback()
    local secondCore = ten.core
    assert(secondCore ~= firstCore and ten.context.regularSpaceId == "next-space")
    assert(#secondCore:state().manager.spaces["next-space"].memberIds == 0)
    oldWindowWatcher(nil, "AXWindowMiniaturized")
    assert(firstCore:state().manager.windows[9] and firstCore:state().manager.windows[9].lifecycle.minimized,
      "persistent observers route inactive lifecycle state to the retained owner")

    f.activeSpace, f.members, f.owners = "space", { 9 }, { "space" }
    f.contextWatcher.callback()
    assert(ten.core == firstCore and ten.context.regularSpaceId == "space")
    assert(firstCore:state().manager.spaces.space.memberIds[1] == firstMember)
    f.windowWatcher.callback(nil, "AXWindowMiniaturized")
    assert(firstCore:state().manager.windows[9].lifecycle.minimized)
    assert(ten.cores["next-space"] == secondCore)
    ten:stop(); oldSpaceWatcher(); assert(not ten.started)
  end,
  ["LIFE-001 LIFE-002: A-B-A retains observers, avoids global discovery, and relocates only confirmed ownership"] = function()
    local f = fakeHs(); local ten = load(f); ten:start()
    local first, life, appWatcher, windowWatcher = ten.core, f.life, f.appWatcher, f.windowWatcher
    local initialScans = f.scans
    focus(ten, 9)
    f.activeSpace, f.members, f.owners = "next-space", {}, { "space" }
    f.contextWatcher.callback()
    local second = ten.core
    assert(f.life == life and f.appWatcher == appWatcher and f.windowWatcher == windowWatcher)
    assert(not life.stopped and not appWatcher.stopped and not windowWatcher.stopped and f.scans == initialScans)
    -- Creation is an authoritative owner read. It relocates from the retained
    -- source rather than synthesizing destruction/history reinsertion.
    f.owners = { "next-space" }
    appWatcher.callback(f.window, "AXWindowCreated")
    assert(not first:state().manager.windows[9] and second:state().manager.windows[9])
    local history = ten.focusHistory:snapshot()
    assert(#history == 1 and history[1].windowId == 9 and history[1].spaceId == "next-space")
    assert(ten.handleRegistry:target(9).spaceId == "next-space")
    f.activeSpace, f.members, f.owners = "space", {}, { "next-space" }
    f.contextWatcher.callback()
    assert(ten.core == first and f.life == life and f.appWatcher == appWatcher and f.windowWatcher == windowWatcher)
    assert(f.scans == initialScans, "changed regular activation must not scan all applications")
    ten:stop()
  end,
  ["LIFE-001 LIFE-002: created-away initializes its confirmed first-visit scope without inactive focus"] = function()
    local f = fakeHs(); local ten = load(f); ten:start(); local active = ten.core
    f.windowWatcher.callback(nil, "AXUIElementDestroyed")
    f.owners = { "next-space" }
    f.appWatcher.callback(f.window, "AXWindowCreated")
    local away = ten.cores["next-space"]
    assert(away and away ~= active and away:state().manager.windows[9] and ten.core == active)
    assert(not away:state().manager.focus.desiredBySpace["next-space"].pending)
    ten:stop()
  end,
  ["LIFE-002: stale batch cannot create a global pending focus request"] = function()
    local f = fakeHs(); local ten = load(f); ten:start()
    ten:_flushCoreIntents({ { core = ten.core, contextEpoch = ten.contextEpoch - 1,
      intents = { { kind = "focus", windowId = 9, spaceId = "space" } } } })
    assert(not ten.focusHistory:pending() and f.focuses == 0)
    ten:stop()
  end,
  ["STATE-002 LIFE-002: failed batched submission discards its intents before the next event"] = function()
    local f = fakeHs(); local ten = load(f); ten:start()
    local observer = ten.core.observer
    ten.core.observer = function() error("forced observer failure") end
    assert(not pcall(function()
      ten:_submitEvent({ type = "WindowReady", id = 10, title = "broken batch", displayId = "built-in", spaceId = "space",
        application = { pid = 10, name = "App" } }, { id = function() return 10 end })
    end))
    assert(ten.effectBatch == nil)
    ten.core.observer = observer
    f.windowWatcher.callback(nil, "AXWindowMiniaturized")
    f.actual = { x = 7, y = 0, w = 1, h = 1 }
    f.windowWatcher.callback(nil, "AXWindowDeminiaturized")
    assert(ten.effectBatch == nil and f.frames == 2, "next callback executes only its own recovered batch")
    ten:stop()
  end,
  ["LIFE-002 FOCUS-004: app fanout commits inactive scope without granting it focus authority"] = function()
    local f = fakeHs(); local ten = load(f); ten:start(); local first = ten.core
    focus(ten, 9)
    f.activeSpace, f.members, f.owners = "next-space", {}, { "space" }; f.contextWatcher.callback()
    local second = ten.core
    ten:_submitEvent({ type = "WindowReady", id = 10, title = "B", displayId = "built-in", spaceId = "next-space",
      application = { pid = 8, name = "App" }, resource = 100, appResource = ten.host.appResources[8].lease }, { id = function() return 10 end, frame = function() return f.actual end,
        setFrame = function() end, focus = function() end })
    f.life.callback(nil, _G.hs.application.watcher.hidden, f.window:application())
    assert(first:state().manager.windows[9].lifecycle.appHidden and second:state().manager.windows[10].lifecycle.appHidden)
    assert(not first:state().manager.focus.desiredBySpace.space.pending, "inactive cleanup cannot strand recovery focus")
    f.life.callback(nil, _G.hs.application.watcher.terminated, f.window:application())
    assert(not first:state().manager.windows[9] and not second:state().manager.windows[10])
    assert(not ten.handleRegistry:target(9) and not ten.handleRegistry:target(10))
    ten:stop()
  end,
}
