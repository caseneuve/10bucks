-- Keyboard-first layout, focus, and existing regular-desktop commands.
-- Before switching from stable, copy the built-in display UUID from the approved
-- switch preflight into this value. Do not commit a machine-specific UUID.
local hyper = { "cmd", "alt", "ctrl", "shift" }
return {
  builtInDisplayUUID = "REPLACE-WITH-VERIFIED-BUILT-IN-DISPLAY-UUID",
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
