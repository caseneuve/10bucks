local Spaces = require("lib.macos.spaces")
local function fixture()
  local timers, events, presses, now, visible = {}, {}, 0, 0, false
  local intent = { kind = "switchRegularSpace", displayId = "D", sourceId = "A", sourceType = "user",
    destinationId = "B", generation = 1, revision = 1, fullSpaceIds = { "A", "F", "B" }, regularSpaceIds = { "A", "B" } }
  local current = intent
  local hsPress
  local context = { displayId = "D", nativeSpaceId = "A", nativeSpaceType = "user", fullSpaceIds = intent.fullSpaceIds, regularSpaceIds = intent.regularSpaceIds }
  local function element(identifier, children, display)
    return { attributeValue = function(_, key) return ({ AXIdentifier = identifier, AXChildren = children, AXDisplayID = display })[key] end,
      performAction = function() presses = presses + 1; if hsPress then return hsPress() end; return {} end }
  end
  local list = element("mc.spaces.list", { element("A"), element("F"), element("B") })
  local group = element("mc", { element("mc.display", { element("mc.spaces", { list, element("mc.spaces.add") }) }, 7) })
  local dockApp, posted = {}, {}
  local hs = { eventtap = { event = { newKeyEvent = function(mods, key, down)
    assert(#mods == 0 and key == "escape")
    return { post = function(_, app)
      assert(app == dockApp); posted[#posted + 1] = down
      if not down then visible = false end
    end }
  end } }, timer = { absoluteTime = function() return now * 1e9 end, doAfter = function(delay, callback)
    local timer = { delay = delay, callback = callback, stop = function(self) self.stopped = true end }; timers[#timers + 1] = timer; return timer
  end }, application = { applicationsForBundleID = function() return { dockApp } end },
    axuielement = { applicationElement = function() return element("dock", visible and { group } or {}) end },
    screen = { allScreens = function() return { { getUUID = function() return "D" end, id = function() return 7 end } } end },
    spaces = { openMissionControl = function() visible = true end, closeMissionControl = function() error("must not close ambiguous MC") end } }
  local onReceipt
  local adapter = Spaces.new(hs, { current = function() return current end, snapshot = function() return context end,
    submit = function(event) events[#events + 1] = event; if onReceipt then onReceipt(event) end end })
  return adapter, intent, timers, events, context, function() return presses end,
    function(value) current = value end, function(value) now = value end,
    function(value) visible = value end, function(callback) hsPress = callback end, posted, function(callback) onReceipt = callback end
end
return {
  ["SPACE-003 STATE-002 CMD-006: create once then select actual identity after committed topology"] = function()
    local a,intent,timers,events,context,presses,setCurrent,setNow=fixture()
    intent.kind="createRegularSpace";intent.creating=true;intent.destinationId=nil
    local current={};for k,v in pairs(intent)do current[k]=v end;setCurrent(current)
    local inspected=0
    a.dependencies.contextChanged=function()inspected=inspected+1 end
    a:execute(intent);timers[2].callback()
    assert(presses()==1 and events[1].type=="RegularCreatePressed")
    current.phase="adding";timers[#timers].callback();assert(inspected==1 and presses()==1)
    context.regularSpaceIds={"A","B","C"};context.fullSpaceIds={"A","F","B","C"}
    local fact=a:observe(context);assert(fact.workspaceEventType=="RegularCreateTopologyObserved" and fact.destinationId==nil)
    local select={};for k,v in pairs(intent)do select[k]=v end
    select.destinationId="C";select.kind="selectCreatedRegularSpace";select.selectionFullSpaceIds=context.fullSpaceIds;select.selectionRegularSpaceIds=context.regularSpaceIds
    current={};for k,v in pairs(select)do current[k]=v end;current.phase="selecting";setCurrent(current)
    setNow(2.1);assert(a:execute(select));assert(a.operation.readinessDeadline==4.1 and a.operation.deadline==5)
    timers[#timers].callback()
    -- Faked list lacks new C: must fail without a guessed press or mutation retry.
    assert(presses()==1 and not a.operation and events[#events].type=="RegularSwitchFailed")
  end,
  ["SPACE-003 CMD-006: ambiguous add is never retried; stop and late callback cannot mutate"] = function()
    local a,intent,timers,events,_,presses,_,_,_,setPress=fixture()
    intent.kind="createRegularSpace";intent.creating=true;intent.destinationId=nil
    setPress(function()error("ambiguous add")end)
    a.dependencies.contextChanged=function()end
    a:execute(intent);timers[2].callback();assert(presses()==1 and a.operation)
    a:stop();for _,timer in ipairs(timers)do timer.callback()end
    assert(presses()==1 and #events==1 and not a.operation)
  end,
  ["FS-005: own opened fullscreen MC supplies selective rebase but dismissed reopened MC does not"] = function()
    for _, dismissed in ipairs({ false, true }) do
      local a, intent, timers, events, context, presses, setCurrent = fixture()
      intent.sourceId = "F"; intent.sourceType = "fullscreen"
      context.nativeSpaceId = "F"; context.nativeSpaceType = "fullscreen"
      a:execute(intent)
      if dismissed then a:dockBoundary() end
      context.nativeSpaceId = "A"; context.nativeSpaceType = "user"
      local observed = a:observe(context)
      if dismissed then assert(not observed.workspaceEventType and not a.operation)
      else
        assert(observed.workspaceEventType == "RegularSwitchContextRebased" and observed.sourceId == "F")
        local current = {}; for k,v in pairs(intent) do current[k] = v end
        current.pressSourceId = "A"; current.pressSourceType = "user"; setCurrent(current)
        timers[2].callback(); assert(presses() == 1 and events[1].sourceId == "F")
      end
    end
  end,
  ["CMD-005: late prior dismissal boundary releases unopened next leg not its new session"] = function()
    local a, intent, timers, events, context, presses, setCurrent = fixture()
    a:execute(intent); timers[2].callback(); context.nativeSpaceId = "B"; a:observe(context)
    assert(a.awaitingDismissal)
    local nextIntent = {}; for k,v in pairs(intent) do nextIntent[k] = v end
    nextIntent.sourceId = "B"; nextIntent.destinationId = "A"; nextIntent.generation = 2
    setCurrent(nextIntent); a:execute(nextIntent)
    local waiting = timers[#timers]; assert(waiting.delay == .05 and not a.operation.opened)
    waiting.callback(); assert(not a.operation.opened and presses() == 1)
    a:dockBoundary(); timers[#timers].callback(); assert(a.operation.opened)
    local readiness = timers[#timers]; assert(readiness.delay == .3)
    a:dockBoundary(); readiness.callback()
    assert(not a.operation and events[#events].type == "RegularSwitchFailed" and presses() == 1)
  end,
  ["CMD-006 STATE-002: pressed receipt reentry invalidation safely settles known-not-issued leg"] = function()
    for _, invalidated in ipairs({ false, true }) do
      local a, intent, timers, events, _, presses, setCurrent, _, _, _, posted, setReceipt = fixture()
      setReceipt(function(event)
        if event.type == "RegularSwitchPressed" then
          local current = {}; for k,v in pairs(intent) do current[k] = v end
          if invalidated then current.invalidated = true else current.sourceId = "changed" end
          setCurrent(current)
        end
      end)
      a:execute(intent); timers[2].callback()
      assert(presses() == 0 and #posted == 0 and not a.operation)
      assert(events[2].type == (invalidated and "RegularSwitchCancelled" or "RegularSwitchFailed"))
      timers[1].callback(); assert(#events == 2)
    end
  end,
  ["CMD-006: native AXPress cancellation reentry suppresses Escape without releasing attempted barrier"] = function()
    local a, intent, timers, events, _, presses, setCurrent, _, _, setPress, posted = fixture()
    setPress(function()
      local current = {}; for k,v in pairs(intent) do current[k] = v end
      current.invalidated = true; setCurrent(current)
      local cancel = {}; for k,v in pairs(intent) do cancel[k] = v end
      cancel.kind = "cancelRegularSwitch"; a:execute(cancel)
      return {}
    end)
    a:execute(intent); timers[2].callback()
    assert(presses() == 1 and #posted == 0 and a.operation and #events == 1)
    timers[1].callback(); assert(events[2].type == "RegularSwitchTimedOut")
  end,
  ["SPACE-004: accepted press pairs Escape targeted only to retained Dock app"] = function()
    local a, intent, timers, events, context, _, _, _, _, _, posted = fixture()
    a:execute(intent); timers[2].callback()
    assert(#posted == 2 and posted[1] == true and posted[2] == false)
    context.nativeSpaceId = "B"; assert(a:observe(context).generation == 1 and not a.operation)
  end,
  ["SPACE-004: destination alone cannot confirm while Mission Control remains visible"] = function()
    local a, intent, timers, _, context, _, _, _, visible = fixture()
    a:execute(intent); timers[2].callback(); visible(true)
    context.nativeSpaceId = "B"; assert(not a:observe(context).generation and a.operation)
    a:dockBoundary(); visible(false)
    assert(a:observe(context).generation == 1 and not a.operation)
  end,
  ["SPACE-005: fullscreen switch confirms the captured identity and type only after MC dismissal"] = function()
    local a, intent, timers, _, context, presses, _, _, visible = fixture()
    intent.destinationId = "F"
    a:execute(intent); timers[2].callback(); assert(presses() == 1)
    context.nativeSpaceId = "F"
    assert(not a:observe(context).generation and a.operation, 'wrong native type must not confirm')
    context.nativeSpaceType = "fullscreen"; visible(true)
    assert(not a:observe(context).generation and a.operation, 'visible MC must not confirm')
    a:dockBoundary(); visible(false)
    assert(a:observe(context).generation == 1 and not a.operation)
  end,
  ["CMD-006: AXPress nil false exception retain attempted barrier to native confirmation or timeout"] = function()
    for _, outcome in ipairs({ "nil", "false", "error" }) do
      local a, intent, timers, events, context, presses, _, _, _, setPress = fixture()
      setPress(function()
        assert(events[1].type == "RegularSwitchPressed")
        if outcome == "error" then error("ambiguous") end
        if outcome == "false" then return false end
      end)
      a:execute(intent); timers[2].callback()
      assert(presses() == 1 and a.operation and #events == 1)
      context.nativeSpaceId = "B"; assert(a:observe(context).generation == nil and a.operation)
      timers[1].callback(); assert(events[2].type == "RegularSwitchTimedOut")
      assert(not a.operation)
    end
  end,
  ["CMD-006: Dock boundary retires prepress callbacks but cannot drain pressed effects"] = function()
    for _, pressed in ipairs({ false, true }) do
      local a, intent, timers, events, _, presses = fixture(); a:execute(intent)
      if pressed then timers[2].callback() end
      a:dockBoundary(); timers[2].callback()
      if pressed then assert(a.operation and #events == 1 and presses() == 1)
      else assert(not a.operation and events[1].type == "RegularSwitchFailed" and presses() == 0) end
    end
  end,
  ["SPACE-004: confirmed previous leg allows bounded MC settling wait but boundary revokes it"] = function()
    local a, intent, timers, events, context, presses, setCurrent, _, visible = fixture()
    a:execute(intent); timers[2].callback(); context.nativeSpaceId = "B"; a:observe(context)
    local nextIntent = {}; for k,v in pairs(intent) do nextIntent[k] = v end
    nextIntent.sourceId = "B"; nextIntent.destinationId = "A"; nextIntent.generation = 2
    visible(true)
    setCurrent(nextIntent); assert(a:execute(nextIntent))
    assert(timers[#timers].delay == .05)
    a:dockBoundary(); assert(a.operation, "prior closing boundary must not cancel unopened leg")
    visible(false); timers[#timers].callback(); assert(timers[#timers].delay == .3)
    a:dockBoundary(); timers[#timers].callback(); assert(presses() == 1)
  end,
  ["CMD-006: MC still visible at cancel stop timeout exposes actionable cleanup uncertainty"] = function()
    local a, intent, timers = fixture(); a:execute(intent); a:stop()
    assert(a:status().cleanupUncertain and a:status().message:find("Dismiss Mission Control", 1, true))
    a, intent, timers = fixture(); a:execute(intent); timers[1].callback(); assert(a:status().cleanupUncertain)
  end,
  ["SPACE-004 STATE-002: async yield single AXPress tuple receipt and native correlated confirmation"] = function()
    local a, intent, timers, events, context, presses = fixture()
    assert(a:execute(intent)); assert(#timers == 2 and timers[1].delay == 5 and timers[2].delay == .3 and presses() == 0)
    timers[2].callback(); assert(presses() == 1 and events[1].type == "RegularSwitchPressed")
    context.nativeSpaceId = "B"
    local observed = a:observe(context)
    assert(observed.generation == 1 and observed.sourceId == "A" and not context.generation)
    timers[1].callback(); assert(#events == 1 and a.operation == nil)
  end,
  ["CMD-006: prepress cancellation acknowledges safely; stopped stale callbacks cannot press"] = function()
    local a, intent, timers, events, _, presses = fixture(); a:execute(intent)
    local cancel = {}; for k,v in pairs(intent) do cancel[k] = v end; cancel.kind = "cancelRegularSwitch"
    a:execute(cancel); assert(events[1].type == "RegularSwitchCancelled")
    timers[2].callback(); assert(presses() == 0)
    a:execute(intent); a:stop(); a:stop(); timers[#timers].callback(); assert(presses() == 0)
  end,
  ["CMD-006: postpress cancel retains barrier until actual destination or timeout without safe ack"] = function()
    for _, confirmation in ipairs({ false, true }) do
      local a, intent, timers, events, context = fixture(); a:execute(intent); timers[2].callback()
      local cancel = {}; for k,v in pairs(intent) do cancel[k] = v end; cancel.kind = "cancelRegularSwitch"
      a:execute(cancel); assert(#events == 1 and a.operation)
      assert(not a:execute(intent))
      if confirmation then context.nativeSpaceId = "B"; assert(a:observe(context).generation == nil)
      else timers[1].callback() end
      assert(events[2].type == (confirmation and "RegularSwitchFailed" or "RegularSwitchTimedOut") and not a.operation)
    end
  end,
  ["SPACE-006: prepress changed authority/order and preexisting MC never press"] = function()
    local a, intent, timers, events, context, presses = fixture(); a:execute(intent)
    context.fullSpaceIds = { "B", "F", "A" }; timers[2].callback()
    assert(presses() == 0 and events[1].type == "RegularSwitchFailed")
    local visible; a, intent, timers, events, context, presses, _, _, visible = fixture()
    visible(true); assert(not a:execute(intent)); assert(events[1].type == "RegularSwitchFailed" and presses() == 0)
  end,
  ["SPACE-006: absent list retries yield and readiness ends within two seconds"] = function()
    local a, intent, timers, events, _, presses, _, setNow, visible = fixture(); a:execute(intent)
    visible(false); timers[2].callback(); assert(timers[3].delay == .05)
    setNow(2); timers[3].callback(); assert(events[1].type == "RegularSwitchFailed" and presses() == 0)
  end,
}
