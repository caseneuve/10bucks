-- 10bucks configuration
--
-- Install this file as ~/.config/10bucks/config.lua, or as
-- $XDG_CONFIG_HOME/10bucks/config.lua when XDG_CONFIG_HOME is set. This file
-- must return one Lua table. Every key is optional: omitted keys use the
-- built-in defaults shown here.

local hyper = { "cmd", "alt", "ctrl", "shift" }

return {
  -- Number of seconds used for managed-window animations. Use 0 for none.
  animationDuration = 0,

  -- "stack" overlays all managed windows; "columns" starts with two columns.
  initialLayout = "stack",
  -- Number from minimumColumnRatio through maximumColumnRatio.
  initialColumnRatio = 0.5,
  -- Non-negative gaps, in screen points.
  outerGap = 8,
  topGap = 8,
  columnGap = 8,
  -- Ratios strictly between 0 and 0.5, and strictly between 0.5 and 1.
  minimumColumnRatio = 0.2,
  maximumColumnRatio = 0.8,
  -- Positive ratio adjustment made by the resize hotkeys.
  resizeStep = 0.05,
  -- Positive number of seconds for transient status alerts.
  statusDuration = 1.2,

  bar = {
    enabled = true, -- boolean
    showWorkspaces = true, -- boolean
    height = 32, -- positive number of screen points
    topPadding = 4, -- number from 0 up to (but not including) height
    -- Non-negative space reserved at the screen's top-right edge.
    rightInset = 24,
    refreshInterval = 0.15, -- positive number of seconds
    -- Non-negative delay in seconds before the canvas returns after menu reveal.
    menuBarHideDelay = 0.20,
    -- Non-negative fade duration in seconds; no greater than menuBarHideDelay.
    menuBarFadeDuration = 0.10,
    -- Hammerspoon colour tables. The first pair is used in macOS Dark mode;
    -- the second pair is used in Light mode and updates automatically.
    backgroundColor = { red = 0.08, green = 0.09, blue = 0.12, alpha = 0.45 },
    textColor = { red = 0.9, green = 0.92, blue = 0.96, alpha = 1 },
    lightBackgroundColor = { red = 0.94, green = 0.95, blue = 0.97, alpha = 0.65 },
    lightTextColor = { red = 0.08, green = 0.09, blue = 0.12, alpha = 1 },
    font = "Menlo", -- font name string
    textSize = 13, -- positive number
  },

  -- Lists of application bundle-ID strings and Lua-pattern strings.
  -- Modal and fixed-size standard windows are excluded automatically; use
  -- these lists for any remaining exceptions.
  excludedBundleIDs = { "org.hammerspoon.Hammerspoon", "com.apple.SecurityAgent" },
  excludedWindowTitles = {
    -- "^Picture in Picture$",
    -- "^Downloads$",
  },
  -- Optional function called for an otherwise eligible standard window.
  -- Return false to leave the window unmanaged.
  -- windowFilter = function(window)
  --   return window:title() ~= "Mini Player"
  -- end,

  -- Each binding is { { modifier strings... }, key string }. Modifiers must
  -- be cmd, alt, ctrl, shift, or fn. Set a named action to false to disable it.
  -- You may omit actions to retain their defaults.
  hotkeys = {
    toggleLayout = { hyper, "space" },
    focusPreviousColumn = { hyper, "h" },
    focusPreviousWindow = { hyper, ";" },
    focusNextInStack = { hyper, "j" },
    focusPreviousInStack = { hyper, "k" },
    focusNextColumn = { hyper, "l" },
    moveDividerLeft = { hyper, "[" },
    moveDividerRight = { hyper, "]" },
    resetDivider = { hyper, "0" },
    swapColumns = { hyper, "g" },
    moveFocusedToOtherColumn = { hyper, "o" },
    focusPreviousWorkspace = { hyper, "p" },
    focusNextWorkspace = { hyper, "n" },
    chooseWorkspace = { hyper, "u" },
    chooseWindow = { hyper, "w" },
    deleteWorkspace = { hyper, "delete" },
    reflow = { hyper, "r" },
  },
}
