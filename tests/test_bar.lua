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

  ["space changes reassert a bar that macOS still reports as showing"] = function()
    local shown, showCalls, behavior = false, 0, nil
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
    instance.render = function() end

    instance:refresh()
    assert(showCalls == 1)
    assert(behavior[1] == "canJoinAllSpaces")

    -- isShowing() remains true even when a window has been left on another
    -- native Space, so the watcher path must explicitly order it front again.
    instance:refresh(true)
    assert(showCalls == 2)
  end,

  ["bar periodically reasserts visibility after a Space transition"] = function()
    local shown, showCalls, periodicRefresh = false, 0, nil
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
    instance.render = function() end

    instance:start()
    assert(showCalls == 1)
    periodicRefresh()
    assert(showCalls == 2)
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
