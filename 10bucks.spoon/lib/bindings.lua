-- Thin native hotkey adapter for the currently composed command registry.
local Bindings = {}

local actions = {
  cycleLayout = "CycleLayout",
  focusPreviousGroup = "FocusPreviousGroup",
  focusNextGroup = "FocusNextGroup",
  focusPrevious = "FocusPrevious",
  focusNext = "FocusNext",
  focusManagedPrevious = "FocusManagedPrevious",
  moveFocusedToOtherGroup = "MoveFocusedToOther",
  swapGroups = "SwapGroups",
  resizeLeft = { type = "ResizeRatioDelta", delta = -0.05 },
  resizeRight = { type = "ResizeRatioDelta", delta = 0.05 },
  resetRatio = "ResetRatio",
  reflow = "Reflow",
}

function Bindings.bind(hs, submit, hotkeys)
  assert(type(submit) == "function", "bindings require a command sink")
  local bindings, seen = {}, {}
  local ok, err = pcall(function()
    for name, binding in pairs(hotkeys or {}) do
      local command = actions[name]
      if not command then error("Unknown 10bucks action: " .. tostring(name), 2) end
      if binding ~= false then
        local modifiers, key = binding[1], binding[2]
        local identity = table.concat(modifiers, "+") .. ":" .. key
        if seen[identity] then error("duplicate 10bucks hotkey chord", 2) end
        seen[identity] = true
        bindings[#bindings + 1] = hs.hotkey.bind(modifiers, key, function()
          if type(command) == "table" then
            return submit({ type = command.type, delta = command.delta })
          end
          return submit({ type = command })
        end)
      end
    end
  end)
  if not ok then Bindings.delete(bindings); error(err, 0) end
  return bindings
end

function Bindings.delete(bindings)
  for _, binding in ipairs(bindings or {}) do binding:delete() end
end

return Bindings
