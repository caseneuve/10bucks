-- Keyboard-first layout, focus, and regular-desktop commands.
-- Digits focus existing positions only. createDesktop appends one desktop and focuses it.
-- Before switching from stable, copy the built-in display UUID from the approved
-- switch preflight into this value. Do not commit a machine-specific UUID.
local hyper = { "cmd", "alt", "ctrl", "shift" }
return {
  builtInDisplayUUID = "REPLACE-WITH-VERIFIED-BUILT-IN-DISPLAY-UUID",
  -- First match wins; bundleID/title are exact, titlePrefix is literal and case-sensitive.
  -- Empty titlePrefix matches every known title; unavailable titles defer. No predicates/patterns.
  rules = {}, -- e.g. { { match = { bundleID = "com.example.App", titlePrefix = "Utility: " }, action = "exclude" } }
  -- Columns only: points on all outer sides (top below usable area) and once between columns.
  -- Finite and nonnegative; clamped to fit, allowing zero-sized frames at extremes.
  -- Ratio divides the window width remaining after gaps (two columns subtract 3 gaps).
  columnGap = 0,
  hotkeys = {
    cycleLayout = { hyper, "space" },
    focusLeftGroup = { hyper, "h" },
    focusRightGroup = { hyper, "l" },
    focusPrevious = { hyper, "k" },
    focusNext = { hyper, "j" },
    focusManagedPrevious = { hyper, "'" },
    chooseWindow = { hyper, "w" }, -- discovered managed rows; restoration/fullscreen selection deferred
    moveFocusedToOtherGroup = { hyper, "o" },
    swapGroups = { hyper, "g" },
    resizeLeft = { hyper, "[" },
    resizeRight = { hyper, "]" },
    resetRatio = { hyper, "=" },
    reflow = { hyper, "r" },
    createDesktop = { hyper, "d" }, -- configurable; false disables this binding
    focusDesktop1 = { hyper, "1" },
    focusDesktop2 = { hyper, "2" },
    focusDesktop3 = { hyper, "3" },
    focusDesktop4 = { hyper, "4" },
    focusDesktop5 = { hyper, "5" },
    focusDesktop6 = { hyper, "6" },
    focusDesktop7 = { hyper, "7" },
    focusDesktop8 = { hyper, "8" },
    focusDesktop9 = { hyper, "9" },
    focusPreviousDesktop = { hyper, "0" },
    focusNextDesktop = { hyper, "n" },
    focusPreviousDesktopPosition = { hyper, "p" },
  },
}
