-- Canary A supports only direct stack navigation and explicit reflow.
-- Before switching from stable, copy the built-in display UUID from the approved
-- switch preflight into this value. Do not commit a machine-specific UUID.
local hyper = { "cmd", "alt", "ctrl", "shift" }
return {
  builtInDisplayUUID = "REPLACE-WITH-VERIFIED-BUILT-IN-DISPLAY-UUID",
  hotkeys = {
    cycleLayout = { hyper, "space" },
    focusPreviousGroup = { hyper, "h" },
    focusNextGroup = { hyper, "l" },
    focusPrevious = { hyper, "k" },
    focusNext = { hyper, "j" },
    focusManagedPrevious = { hyper, "'" },
    moveFocusedToOtherGroup = { hyper, "o" },
    swapGroups = { hyper, "g" },
    resizeLeft = { hyper, "[" },
    resizeRight = { hyper, "]" },
    resetRatio = { hyper, "=" },
    reflow = { hyper, "r" },
  },
}
