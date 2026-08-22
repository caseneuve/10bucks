local WindowRepository = require("lib.window_repository")
local Config = require("lib.config")

local function requiredWindowFilter()
  return { new = function() return {} end }
end

local function window(visible, title, bundleID)
  return {
    id = function() return 1 end,
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
