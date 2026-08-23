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

local function window(visible, title, bundleID, frame)
  return {
    id = function() return 1 end,
    frame = function() return frame end,
    isVisible = function() return visible end,
    isFullScreen = function() return false end,
    application = function()
      return { bundleID = function() return bundleID or "com.example.App" end }
    end,
    role = function() return "AXWindow" end,
    subrole = function() return "AXStandardWindow" end,
    isStandard = function() return true end,
    title = function() return title end,
  }
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
}
