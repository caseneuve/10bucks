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
  hotkeys = {
    cycleLayout = { hyper, "space" },
    focusLeftGroup = { hyper, "h" },
    focusRightGroup = { hyper, "l" },
    focusPrevious = { hyper, "k" },
    focusNext = { hyper, "j" },
    focusManagedPrevious = { hyper, "'" },
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
