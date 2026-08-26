local Bar = require("lib.bar")
local Config = require("lib.config")

local screen = {
  getUUID = function() return "screen-a" end,
}

local function workspaces(activeSpace, fullscreen, label)
  return {
    activeSpace = function() return activeSpace end,
    isFullscreenSpace = function() return fullscreen end,
    label = function() return label end,
  }
end

local function bar(hs, focused, workspaces)
  return Bar.new(hs, {}, { focusedWindow = function() return focused end }, workspaces, {})
end

local function handoffHarness(menuBarHideDelay)
  local clock, over, shown = 0, false, true
  local calls = { show = 0, hide = 0, render = 0, showDuration = nil, hideDuration = nil }
  local canvas = {
    level = function(self) return self end,
    behavior = function(self) return self end,
    clickActivating = function(self) return self end,
    isShowing = function() return shown end,
    hide = function(_, duration)
      shown = false
      calls.hide = calls.hide + 1
      calls.hideDuration = duration
    end,
    show = function(_, duration)
      shown = true
      calls.show = calls.show + 1
      calls.showDuration = duration
    end,
    delete = function() end,
  }
  local workspaceScreen = {
    getUUID = function() return "screen-a" end,
    fullFrame = function() return { x = 0, y = 0, w = 1440, h = 900 } end,
  }
  local screens = { workspaceScreen }
  local instance = Bar.new({
    mouse = {
      absolutePosition = function()
        return over and { x = 100, y = 10 } or { x = 100, y = 100 }
      end,
    },
    timer = { secondsSinceEpoch = function() return clock end },
    screen = { allScreens = function() return screens end },
    canvas = {
      new = function() return canvas end,
    },
  }, {}, { focusedWindow = function() return nil end }, workspaces(),
    Config.build({ bar = { menuBarHideDelay = menuBarHideDelay } }).bar)
  instance.render = function() calls.render = calls.render + 1 end
  return {
    instance = instance,
    calls = calls,
    setPointer = function(value) over = value end,
    setTime = function(value) clock = value end,
    setScreens = function(value) screens = value end,
    isShowing = function() return shown end,
  }
end

return {
  ["bar hides on a native fullscreen Space"] = function()
    local instance = bar({}, nil, workspaces(42, true))
    assert(instance:isFullscreenSpace(screen))
  end,

  ["bar remains for an ordinary user Space"] = function()
    local instance = bar({}, nil, workspaces(42, false))
    assert(not instance:isFullscreenSpace(screen))
  end,

  ["bar displays a compact full date and time"] = function()
    local instance = bar({}, nil, workspaces())
    local timestamp = os.time({ year = 2026, month = 8, day = 22, hour = 18, min = 14, sec = 0 })
    assert(instance:clockText(timestamp) == "Sat, 22 Aug, 18:14")
  end,

  ["bar switches its rendered palette when the system appearance changes"] = function()
    local style = "Dark"
    local darkBackground, darkText = { name = "dark-background" }, { name = "dark-text" }
    local lightBackground, lightText = { name = "light-background" }, { name = "light-text" }
    local elements
    local canvas = {
      frame = function() end,
      replaceElements = function(_, value) elements = value end,
    }
    local config = Config.build({
      bar = {
        backgroundColor = darkBackground,
        textColor = darkText,
        lightBackgroundColor = lightBackground,
        lightTextColor = lightText,
      },
    }).bar
    local instance = Bar.new({
      host = { interfaceStyle = function() return style end },
    }, {}, {}, workspaces(), config)
    instance.status = function() return "stack", "Example" end

    instance:render(canvas, { x = 0, y = 0, w = 1440, h = 32 }, screen)
    assert(elements[1].fillColor.name == darkBackground.name)
    assert(elements[2].strokeColor.name == darkText.name)
    assert(elements[3].strokeColor.name == darkText.name)
    assert(elements[4].textColor.name == darkText.name)
    assert(elements[5].textColor.name == darkText.name)

    -- nil is Hammerspoon's documented result for the default (light) style.
    style = nil
    instance:render(canvas, { x = 0, y = 0, w = 1440, h = 32 }, screen)
    assert(elements[1].fillColor.name == lightBackground.name)
    assert(elements[2].strokeColor.name == lightText.name)
    assert(elements[3].strokeColor.name == lightText.name)
    assert(elements[4].textColor.name == lightText.name)
    assert(elements[5].textColor.name == lightText.name)
  end,

  ["bar status puts workspaces and focused title after the icon with stack count last"] = function()
    local focused = {
      application = function() return { name = function() return "Safari" end } end,
      title = function() return "10bucks issue" end,
    }
    local context = { screenId = "screen-a", spaceId = "space-a" }
    local engine = {
      state = {
        scope = function()
          return {
            layout = "columns",
            activeColumn = 2,
            columns = { { windows = { 1 } }, { windows = { 2, 3, 4 }, selected = 2 } },
          }
        end,
      },
    }
    local repository = {
      focusedWindow = function() return focused end,
      contextForWindow = function() return context end,
      currentContext = function() return context end,
    }
    local instance = Bar.new({}, engine, repository, workspaces(nil, false, "1 [2] 3"),
      { showWorkspaces = true, textColor = { white = 1 } })

    local layout, text = instance:status(screen)
    assert(layout == "columns")
    assert(text == "1 [2] 3 · 10bucks issue  (2/3) ")

    local columns = instance:layoutIconElements("columns", 12, 4, 28)
    assert(#columns == 2)
    assert(columns[1].action == "stroke")
    assert(columns[1].frame.x == 12 and columns[1].frame.w == 13)
    assert(columns[2].action == "fill")
    assert(columns[2].frame.x == 18)

    local stack = instance:layoutIconElements("stack", 12, 4, 28)
    assert(#stack == 2)
    assert(stack[1].frame.x == 12 and stack[1].frame.y == 7.5)
    assert(stack[2].frame.x == 15 and stack[2].frame.y == 10.5)
  end,

  ["bar leaves a compact right-side gap for macOS privacy indicators"] = function()
    local elements
    local canvas = {
      frame = function() end,
      replaceElements = function(_, value) elements = value end,
    }
    local config = Config.build({}).bar
    local instance = Bar.new({}, {}, {}, workspaces(), config)
    instance.status = function() return "stack", "1/1  ·  Example" end

    instance:render(canvas, { x = 0, y = 0, w = 1440, h = 32 }, screen)

    local clock = elements[#elements]
    assert(config.rightInset == 24)
    assert(clock.textAlignment == "right")
    assert(clock.frame.x == 1440 - config.rightInset - 168)
    assert(clock.frame.x + clock.frame.w == 1440 - config.rightInset)
  end,

  ["space changes refresh an already showing all-spaces canvas without re-showing"] = function()
    local shown, showCalls, renderCalls, behavior = false, 0, 0, nil
    local canvas = {
      level = function(self) return self end,
      behavior = function(self, value) behavior = value return self end,
      clickActivating = function(self) return self end,
      isShowing = function() return shown end,
      show = function() shown, showCalls = true, showCalls + 1 end,
    }
    local workspaceScreen = {
      getUUID = function() return "screen-a" end,
      fullFrame = function() return { x = 0, y = 0, w = 1440, h = 900 } end,
    }
    local instance = Bar.new({
      screen = { allScreens = function() return { workspaceScreen } end },
      canvas = { new = function() return canvas end },
    }, {}, { focusedWindow = function() return nil end }, workspaces(), { enabled = true, height = 32 })
    instance.render = function() renderCalls = renderCalls + 1 end

    instance:refresh()
    assert(showCalls == 1)
    assert(renderCalls == 1)
    assert(behavior[1] == "canJoinAllSpaces")

    -- A Space-change callback refreshes the content but does not reorder an
    -- all-Spaces canvas that already reports itself as showing.
    instance:refresh()
    assert(renderCalls == 2)
    assert(showCalls == 1)
  end,

  ["periodic refresh renders without re-showing a visible canvas"] = function()
    local shown, showCalls, renderCalls, periodicRefresh = false, 0, 0, nil
    local canvas = {
      level = function(self) return self end,
      behavior = function(self) return self end,
      clickActivating = function(self) return self end,
      isShowing = function() return shown end,
      show = function() shown, showCalls = true, showCalls + 1 end,
    }
    local workspaceScreen = {
      getUUID = function() return "screen-a" end,
      fullFrame = function() return { x = 0, y = 0, w = 1440, h = 900 } end,
    }
    local instance = Bar.new({
      screen = { allScreens = function() return { workspaceScreen } end },
      canvas = { new = function() return canvas end },
      timer = {
        doEvery = function(_, callback)
          periodicRefresh = callback
          return { stop = function() end }
        end,
      },
    }, {}, { focusedWindow = function() return nil end }, workspaces(), {
      enabled = true,
      height = 32,
      refreshInterval = 0.15,
    })
    instance.render = function() renderCalls = renderCalls + 1 end

    instance:start()
    assert(showCalls == 1)
    assert(renderCalls == 1)
    periodicRefresh()
    assert(renderCalls == 2)
    assert(showCalls == 1)
  end,

  ["returning from fullscreen shows a canvas that reports not showing"] = function()
    local fullscreen, shown, showCalls = true, false, 0
    local canvas = {
      level = function(self) return self end,
      behavior = function(self) return self end,
      clickActivating = function(self) return self end,
      isShowing = function() return shown end,
      hide = function() shown = false end,
      show = function() shown, showCalls = true, showCalls + 1 end,
    }
    local workspaceScreen = {
      getUUID = function() return "screen-a" end,
      fullFrame = function() return { x = 0, y = 0, w = 1440, h = 900 } end,
    }
    local workspaceState = {
      activeSpace = function() return 42 end,
      isFullscreenSpace = function() return fullscreen end,
      label = function() return nil end,
    }
    local instance = Bar.new({
      screen = { allScreens = function() return { workspaceScreen } end },
      canvas = { new = function() return canvas end },
    }, {}, { focusedWindow = function() return nil end }, workspaceState, {
      enabled = true,
      height = 32,
    })
    instance.render = function() end

    instance:refresh()
    assert(showCalls == 0)
    fullscreen = false
    instance:refresh()
    assert(showCalls == 1)
    assert(shown)
  end,

  ["new bar canvases use the native main-menu window level"] = function()
    local level
    local canvas = {
      level = function(self, value) level = value return self end,
      behavior = function(self) return self end,
      clickActivating = function(self) return self end,
      isShowing = function() return false end,
      show = function() end,
    }
    local workspaceScreen = {
      getUUID = function() return "screen-a" end,
      fullFrame = function() return { x = 0, y = 0, w = 1440, h = 900 } end,
    }
    local instance = Bar.new({
      screen = { allScreens = function() return { workspaceScreen } end },
      canvas = { new = function() return canvas end },
    }, {}, { focusedWindow = function() return nil end }, workspaces(), {
      enabled = true,
      height = 32,
    })
    instance.render = function() end

    instance:refresh()
    assert(level == "mainMenu")
  end,

  ["bar hides immediately while the pointer is over its top strip"] = function()
    local harness = handoffHarness()
    harness.setPointer(true)

    harness.instance:refresh()
    assert(not harness.isShowing())
    assert(harness.calls.hide == 1)
  end,

  ["bar stays suppressed during the hide grace period after pointer exit"] = function()
    local harness = handoffHarness(0.75)
    harness.setPointer(true)
    harness.instance:refresh()

    harness.setPointer(false)
    harness.setTime(0.5)
    harness.instance:refresh()
    assert(not harness.isShowing())
    assert(harness.calls.show == 0)
  end,

  ["re-entering the top strip extends the hide grace period"] = function()
    local harness = handoffHarness(0.75)
    harness.setPointer(true)
    harness.instance:refresh()

    harness.setPointer(false)
    harness.setTime(0.5)
    harness.instance:refresh()
    harness.setPointer(true)
    harness.setTime(0.6)
    harness.instance:refresh()
    harness.setPointer(false)
    harness.setTime(1.0)
    harness.instance:refresh()
    assert(not harness.isShowing())

    harness.setTime(1.36)
    harness.instance:refresh()
    assert(harness.isShowing())
    assert(harness.calls.show == 1)
  end,

  ["bar shows once after the hide grace period expires"] = function()
    local harness = handoffHarness(0.75)
    harness.setPointer(true)
    harness.instance:refresh()
    harness.setPointer(false)
    harness.setTime(0.76)
    harness.instance:refresh()
    harness.setTime(0.9)
    harness.instance:refresh()

    assert(harness.isShowing())
    assert(harness.calls.show == 1)
  end,

  ["default handoff delay suppresses before 0.20 seconds and shows after"] = function()
    local harness = handoffHarness()
    harness.setPointer(true)
    harness.instance:refresh()
    harness.setPointer(false)
    harness.setTime(0.19)
    harness.instance:refresh()
    assert(not harness.isShowing())

    harness.setTime(0.21)
    harness.instance:refresh()
    assert(harness.isShowing())
    assert(harness.calls.show == 1)
  end,

  ["pointer handoff fades once across repeated hovered refreshes"] = function()
    local harness = handoffHarness()
    harness.setPointer(true)
    harness.instance:refresh()
    harness.instance:refresh()

    assert(harness.calls.hide == 1)
    assert(harness.calls.hideDuration == 0.10)
  end,

  ["handoff return fades once after grace expiry"] = function()
    local harness = handoffHarness()
    harness.setPointer(true)
    harness.instance:refresh()
    harness.setPointer(false)
    harness.setTime(0.21)
    harness.instance:refresh()
    harness.setTime(0.4)
    harness.instance:refresh()

    assert(harness.calls.show == 1)
    assert(harness.calls.showDuration == 0.10)
  end,

  ["screen disappearance clears its pointer handoff state"] = function()
    local harness = handoffHarness()
    harness.setPointer(true)
    harness.instance:refresh()
    assert(next(harness.instance.handoffs) ~= nil)

    harness.setScreens({})
    harness.instance:refresh()
    assert(next(harness.instance.handoffs) == nil)
  end,

  ["stopping the bar clears pointer handoff state"] = function()
    local harness = handoffHarness()
    harness.setPointer(true)
    harness.instance:refresh()
    assert(next(harness.instance.handoffs) ~= nil)

    harness.instance:stop()
    assert(next(harness.instance.handoffs) == nil)
  end,

  ["focused native-fullscreen window is a fallback when Spaces lookup fails"] = function()
    local focused = {
      isFullScreen = function() return true end,
      screen = function() return screen end,
    }
    local instance = bar({}, focused, workspaces())
    assert(instance:isFullscreenSpace(screen))
  end,
}
