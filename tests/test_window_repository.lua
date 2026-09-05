local WindowRepository = require("lib.window_repository")
local Config = require("lib.config")

local function requiredWindowFilter()
  return { new = function() return {} end }
end

local function accessibility(sizeSettable, modal)
  return {
    windowElement = function()
      return {
        attributeValue = function(_, attribute)
          assert(attribute == "AXModal")
          return modal
        end,
        isAttributeSettable = function(_, attribute)
          assert(attribute == "AXSize")
          return sizeSettable
        end,
      }
    end,
  }
end

local function crossSpaceFocusFixture(options)
  options = options or {}
  local state = { activeSpace = 10, focused = false, toggles = 0, pressed = false, pressAttempts = 0 }
  local scheduled = {}
  local timer = {
    doAfter = function(delay, callback)
      local pending = { delay = delay, callback = callback, stopped = false }
      function pending:stop() self.stopped = true end
      table.insert(scheduled, pending)
      return pending
    end,
  }
  local function runNext()
    local pending = table.remove(scheduled, 1)
    assert(pending and not pending.stopped, "expected a live scheduled callback")
    pending.callback()
    return pending.delay
  end

  local screen = { id = function() return 7 end }
  local target = {
    focus = function() state.focused = true end,
    screen = function() return screen end,
  }
  local buttons = {
    { performAction = function() error("wrong Space button") end },
    { performAction = function(_, action)
      assert(action == "AXPress")
      state.pressAttempts = state.pressAttempts + 1
      if options.transientPressFailure and state.pressAttempts == 1 then return false end
      state.pressed = true
      state.activeSpace = 20
      return true
    end },
  }
  local spacesList = { AXIdentifier = "mc.spaces.list", AXChildren = buttons }
  local spacesGroup = { AXIdentifier = "mc.spaces", AXChildren = { spacesList } }
  local display = { AXIdentifier = "mc.display", AXDisplayID = 7, AXChildren = { spacesGroup } }
  local missionControl = { AXIdentifier = "mc", AXChildren = { display } }
  local dockElement = { AXChildren = options.noMissionControlTree and {} or { missionControl } }
  local hs = {
    window = { filter = requiredWindowFilter() },
    screen = {},
    spaces = {
      MCwaitTime = 0.3,
      windowSpaces = function(candidate) assert(candidate == target) return { 20 } end,
      activeSpaceOnScreen = function(candidate) assert(candidate == screen) return state.activeSpace end,
      spacesForScreen = function(candidate) assert(candidate == screen) return { 10, 20 } end,
      toggleMissionControl = function() state.toggles = state.toggles + 1 end,
      gotoSpace = function() error("cross-Space focus must not use gotoSpace") end,
      openMissionControl = function() error("cross-Space focus must not use openMissionControl") end,
    },
    timer = timer,
    application = {
      applicationsForBundleID = function(bundleID)
        assert(bundleID == "com.apple.dock")
        return { {} }
      end,
    },
    axuielement = {
      applicationElement = function() return dockElement end,
    },
  }
  local repository = WindowRepository.new(hs, { excludedBundleIDs = {}, excludedWindowTitles = {} })
  return repository, target, state, scheduled, runNext
end

local function window(visible, title, bundleID, frame, applicationName)
  return {
    id = function() return 1 end,
    frame = function() return frame end,
    isVisible = function() return visible end,
    isFullScreen = function() return false end,
    application = function()
      return {
        bundleID = function() return bundleID or "com.example.App" end,
        name = function() return applicationName or "Example App" end,
      }
    end,
    role = function() return "AXWindow" end,
    subrole = function() return "AXStandardWindow" end,
    isStandard = function() return true end,
    title = function() return title end,
  }
end

local function fullscreenRepository(rules)
  return WindowRepository.new({
    window = { filter = requiredWindowFilter() },
    screen = {},
  }, {
    excludedBundleIDs = {},
    excludedWindowTitles = {},
    fullscreenRules = rules,
  })
end

return {
  ["built-in exclusions reject SecurityAgent standard windows"] = function()
    local securityAgent = window(true, "Untitled", "com.apple.SecurityAgent")
    local repository = WindowRepository.new({
      window = { filter = requiredWindowFilter() },
      screen = {},
    }, Config.build({}))

    assert(not repository:isEligible(securityAgent))
  end,

  ["workspace windows include minimized or hidden ordinary windows"] = function()
    local hidden = window(false)
    local repository = WindowRepository.new({
      window = {
        allWindows = function() return { hidden } end,
        visibleWindows = function() return {} end,
        filter = requiredWindowFilter(),
      },
      screen = {},
    }, { excludedBundleIDs = {}, excludedWindowTitles = {} })

    assert(not repository:isEligible(hidden))
    local windows = repository:workspaceWindows()
    assert(#windows == 1 and windows[1] == hidden)
  end,

  ["all-live window enumeration spans Spaces while excluding auxiliary and Hammerspoon windows"] = function()
    local otherSpace = window(true, "Other desktop")
    local auxiliary = {
      id = function() return 2 end,
      application = function() return { bundleID = function() return "com.example.App" end } end,
      isStandard = function() return false end,
    }
    local hammerspoon = window(true, "Hammerspoon Console")
    hammerspoon.id = function() return 3 end
    hammerspoon.application = function()
      return { bundleID = function() return "org.hammerspoon.Hammerspoon" end }
    end
    local candidates = { otherSpace, auxiliary, hammerspoon }
    local created = 0
    local pickerFilter = {
      getWindows = function(self)
        local selected = {}
        for _, candidate in ipairs(candidates) do
          if self.predicate(candidate) then table.insert(selected, candidate) end
        end
        return selected
      end,
    }
    local repository = WindowRepository.new({
      window = {
        allWindows = function() error("picker must use hs.window.filter") end,
        filter = {
          new = function(predicate)
            created = created + 1
            pickerFilter.predicate = predicate
            return pickerFilter
          end,
        },
      },
      screen = {},
    }, { excludedBundleIDs = { "org.hammerspoon.Hammerspoon" }, excludedWindowTitles = {} })

    local windows = repository:allLiveWindows()
    assert(#windows == 1 and windows[1] == otherSpace)
    assert(repository:allLiveWindows()[1] == otherSpace)
    assert(created == 1)
  end,

  ["fixed-size standard windows remain unmanaged"] = function()
    local fixedSize = window(true, "Fixed-size utility", "com.example.App")
    local repository = WindowRepository.new({
      window = { filter = requiredWindowFilter() },
      screen = {},
      axuielement = accessibility(false, false),
    }, { excludedBundleIDs = {}, excludedWindowTitles = {} })

    assert(not repository:isEligible(fixedSize))
    assert(not repository:isPickerWindow(fixedSize))
  end,

  ["modal standard windows remain unmanaged"] = function()
    local modal = window(true, "Application prompt", "com.example.App")
    local repository = WindowRepository.new({
      window = { filter = requiredWindowFilter() },
      screen = {},
      axuielement = accessibility(true, true),
    }, { excludedBundleIDs = {}, excludedWindowTitles = {} })

    assert(not repository:isEligible(modal))
    assert(not repository:isPickerWindow(modal))
  end,

  ["resizable contained TextEdit documents remain eligible"] = function()
    local larger = window(true, "Untitled 2", "com.apple.TextEdit", { x = 0, y = 0, w = 1000, h = 800 })
    local smaller = window(true, "Untitled", "com.apple.TextEdit", { x = 100, y = 100, w = 400, h = 300 })
    larger.id = function() return 1 end
    smaller.id = function() return 2 end
    local repository = WindowRepository.new({
      window = { filter = requiredWindowFilter() },
      screen = {},
      axuielement = accessibility(true, false),
    }, { excludedBundleIDs = {}, excludedWindowTitles = {} })

    assert(repository:isEligible(larger))
    assert(repository:isEligible(smaller))
    assert(repository:isPickerWindow(smaller))
  end,

  ["accessibility lookup failures do not exclude standard windows"] = function()
    local ordinary = window(true, "Document", "com.example.App")
    local repository = WindowRepository.new({
      window = { filter = requiredWindowFilter() },
      screen = {},
      axuielement = { windowElement = function() error("accessibility unavailable") end },
    }, { excludedBundleIDs = {}, excludedWindowTitles = {} })

    assert(repository:isEligible(ordinary))
    assert(repository:isPickerWindow(ordinary))
  end,

  ["eligible enumeration does not query all applications"] = function()
    local first = window(true, "First")
    local second = window(true, "Second")
    second.id = function() return 2 end
    local repository = WindowRepository.new({
      window = {
        allWindows = function() error("eligible enumeration must not query all applications") end,
        visibleWindows = function() return { first, second } end,
        filter = requiredWindowFilter(),
      },
      screen = {},
      axuielement = accessibility(true, false),
    }, { excludedBundleIDs = {}, excludedWindowTitles = {} })

    assert(#repository:eligibleWindows() == 2)
  end,

  ["onscreen ID snapshots avoid Accessibility window enumeration"] = function()
    local calls = 0
    local repository = WindowRepository.new({
      window = {
        _orderedwinids = function()
          calls = calls + 1
          return { 10, 20, 30 }
        end,
        visibleWindows = function() error("native ID snapshot must avoid Accessibility enumeration") end,
        filter = requiredWindowFilter(),
      },
      screen = {},
    }, { excludedBundleIDs = {}, excludedWindowTitles = {} })

    local ids = repository:onscreenWindowIds()
    assert(calls == 1)
    assert(ids[10] and ids[20] and ids[30])
    assert(not ids[40])
  end,

  ["onscreen ID snapshots fall back to visible windows when the native helper fails"] = function()
    local first = window(true, "First")
    local second = window(true, "Second")
    first.id = function() return 10 end
    second.id = function() return 20 end
    local repository = WindowRepository.new({
      window = {
        _orderedwinids = function() error("unavailable") end,
        visibleWindows = function() return { first, second } end,
        filter = requiredWindowFilter(),
      },
      screen = {},
    }, { excludedBundleIDs = {}, excludedWindowTitles = {} })

    local ids = repository:onscreenWindowIds()
    assert(ids[10] and ids[20])
  end,

  ["cross-Space picker excludes fixed-size tracked windows without global enumeration"] = function()
    local fixedSize = window(true, "Fixed-size utility")
    local pickerFilter = {
      getWindows = function(self)
        return self.predicate(fixedSize) and { fixedSize } or {}
      end,
    }
    local repository = WindowRepository.new({
      window = {
        allWindows = function() error("picker must not query all applications") end,
        filter = {
          new = function(predicate)
            pickerFilter.predicate = predicate
            return pickerFilter
          end,
        },
      },
      screen = {},
      axuielement = accessibility(false, false),
    }, { excludedBundleIDs = {}, excludedWindowTitles = {} })

    assert(#repository:allLiveWindows() == 0)
  end,

  ["fullscreen spawn rules OR rules while ANDing their selectors"] = function()
    local repository = fullscreenRepository({
      { bundleID = "com.example.Other", windowTitle = "^Editor" },
      {
        bundleID = "com.example.Editor",
        applicationName = "^Acme Editor$",
        windowTitle = "^Editor %-% .+$",
      },
    })
    local candidate = window(true, "Editor - notes", "com.example.Editor", nil, "Acme Editor")
    assert(repository:shouldSpawnFullscreen(candidate))

    local wrongTitle = window(true, "Editor", "com.example.Editor", nil, "Acme Editor")
    assert(not repository:shouldSpawnFullscreen(wrongTitle))
  end,

  ["fullscreen bundle selectors are exact matches"] = function()
    local repository = fullscreenRepository({ { bundleID = "com.example.App" } })
    assert(repository:shouldSpawnFullscreen(window(true, "Document", "com.example.App")))
    assert(not repository:shouldSpawnFullscreen(window(true, "Document", "com.example.App.beta")))
  end,

  ["fullscreen application names and titles use Lua patterns"] = function()
    local repository = fullscreenRepository({
      { applicationName = "^Terminal %d+$", windowTitle = "^Build %d+%%$" },
    })
    assert(repository:shouldSpawnFullscreen(window(true, "Build 100%", "com.example.Terminal", nil, "Terminal 2")))
    assert(not repository:shouldSpawnFullscreen(window(true, "Build done", "com.example.Terminal", nil, "Terminal 2")))
  end,

  ["fullscreen predicates receive matching windows after declarative selectors"] = function()
    local calls, received = 0, nil
    local candidate = window(true, "Focus", "com.example.App")
    local repository = fullscreenRepository({
      {
        bundleID = "com.example.Other",
        predicate = function() error("predicate must be short-circuited") end,
      },
      {
        windowTitle = "^Not Focus$",
        predicate = function() error("predicate must be short-circuited") end,
      },
      {
        bundleID = "com.example.App",
        predicate = function(value)
          calls = calls + 1
          received = value
          return true
        end,
      },
    })

    assert(repository:shouldSpawnFullscreen(candidate))
    assert(calls == 1 and received == candidate)
  end,

  ["fullscreen selectors do not match absent window metadata"] = function()
    local repository = fullscreenRepository({
      { bundleID = "com.example.App" },
      { applicationName = "^Example App$" },
      { windowTitle = "^Document$" },
    })
    local missingMetadata = {
      application = function() return nil end,
      title = function() return nil end,
    }

    assert(not repository:shouldSpawnFullscreen(missingMetadata))
    assert(not fullscreenRepository({}):shouldSpawnFullscreen(window(true, "Document")))
    assert(not WindowRepository.new({ window = { filter = requiredWindowFilter() }, screen = {} }, {
      excludedBundleIDs = {}, excludedWindowTitles = {},
    }):shouldSpawnFullscreen(window(true, "Document")))
  end,

  ["fullscreen requests safely report whether they were issued"] = function()
    local calls = 0
    local repository = fullscreenRepository({})
    local successful = {
      setFullScreen = function(_, enabled)
        assert(enabled == true)
        calls = calls + 1
      end,
    }
    assert(repository:requestFullscreen(successful))
    assert(calls == 1)
    assert(not repository:requestFullscreen({}))
    assert(not repository:requestFullscreen({ setFullScreen = function() error("unavailable") end }))
  end,

  ["fullscreen state queries safely preserve boolean state"] = function()
    local repository = fullscreenRepository({})
    assert(repository:isFullscreen({ isFullScreen = function() return true end }))
    assert(repository:isFullscreen({ isFullScreen = function() return false end }) == false)
    assert(repository:isFullscreen({}) == false)
    assert(repository:isFullscreen({ isFullScreen = function() error("unavailable") end }) == false)
  end,

  ["title patterns exclude matching ordinary windows"] = function()
    local pictureInPicture = window(true, "Picture in Picture")
    local repository = WindowRepository.new({ window = { filter = requiredWindowFilter() }, screen = {} }, {
      excludedBundleIDs = {},
      excludedWindowTitles = { "^Picture in Picture$" },
    })

    assert(not repository:isEligible(pictureInPicture))
  end,

  ["window filter can exclude an otherwise eligible ordinary window"] = function()
    local auxiliary = window(true, "Auxiliary")
    local repository = WindowRepository.new({ window = { filter = requiredWindowFilter() }, screen = {} }, {
      excludedBundleIDs = {},
      excludedWindowTitles = {},
      windowFilter = function(candidate) return candidate:title() ~= "Auxiliary" end,
    })

    assert(not repository:isEligible(auxiliary))
  end,

  ["same-Space focus remains immediate"] = function()
    local focused = false
    local target = {
      focus = function() focused = true end,
      screen = function() return {} end,
    }
    local repository = WindowRepository.new({
      window = { filter = requiredWindowFilter() },
      screen = {},
      spaces = {
        windowSpaces = function() return { 10 } end,
        activeSpaceOnScreen = function() return 10 end,
        gotoSpace = function() error("same-Space focus must not switch Spaces") end,
      },
      timer = { doAfter = function() error("same-Space focus must not wait") end },
    }, { excludedBundleIDs = {}, excludedWindowTitles = {} })

    assert(repository:focus(target))
    assert(focused)
  end,

  ["cross-Space focus asynchronously switches, settles, then focuses"] = function()
    local repository, target, state, scheduled, runNext = crossSpaceFocusFixture()

    assert(repository:focus(target))
    assert(not state.focused and state.toggles == 1)
    assert(#scheduled == 1 and scheduled[1].delay == 0.025)
    assert(scheduled[1].delay ~= 0.01)
    assert(runNext() == 0.025)
    assert(runNext() == 0.3)
    assert(state.pressed and not state.focused)
    assert(runNext() == 0.05)
    assert(not state.focused)
    assert(runNext() == 0.15)
    assert(state.focused and #scheduled == 0)
  end,

  ["cross-Space focus retries a transient AXPress rejection"] = function()
    local repository, target, state, scheduled, runNext = crossSpaceFocusFixture({ transientPressFailure = true })

    assert(repository:focus(target))
    assert(state.toggles == 1 and #scheduled == 1)
    assert(scheduled[1].delay == 0.025 and scheduled[1].delay ~= 0.01)
    assert(runNext() == 0.025)
    assert(runNext() == 0.3)
    assert(not state.focused and state.pressAttempts == 1 and state.toggles == 1)
    assert(runNext() == 0.025)
    assert(state.pressed and state.pressAttempts == 2)
    assert(runNext() == 0.05)
    assert(runNext() == 0.15)
    assert(state.focused and #scheduled == 0)
  end,

  ["stopping cross-Space focus closes its Mission Control session"] = function()
    local repository, target, state, scheduled, runNext = crossSpaceFocusFixture({ noMissionControlTree = true })

    assert(repository:focus(target))
    assert(state.toggles == 1 and #scheduled == 1)
    assert(scheduled[1].delay == 0.025 and scheduled[1].delay ~= 0.01)
    local stale = scheduled[1]
    repository:stop()
    assert(stale.stopped and state.toggles == 2)
    stale.callback()
    assert(not state.focused and #scheduled == 1)
  end,
}
