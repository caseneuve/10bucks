local failures = {
  ["stale-chooser-target"] = "This window is no longer available. Visit it, then reopen the chooser.",
  ["chooser-restoration-deferred"] = "Unhide the application and restore the window from the Dock, then try again.",
  ["previous-managed-window-unavailable"] = "Unhide the application and restore the window from the Dock, then try again.",
  ["desktop-switch-pending"] = "Wait for the desktop switch to finish, then choose the window again.",
  ["desktop-creation-pending"] = "Wait for desktop creation to finish, then choose the window again.",
  ["managed-focus-failed"] = "Could not focus this window. Visit it, then try again.",
}

local Adapter = {}
Adapter.__index = Adapter

function Adapter.new(hs, choices, select)
  local self = setmetatable({ choices = choices }, Adapter)
  self.chooser = hs.chooser.new(function(choice)
    if choice then
      local ok, reason = select(choice)
      if not ok then hs.alert.show("10bucks: " .. (failures[reason] or "Could not focus this window. Reopen the chooser and try again.")) end
    end
  end)
  -- Installed 1.1.1 query callbacks replace native substring filtering.
  self.chooser:queryChangedCallback(function(query)
    self.chooser:choices(choices(query))
  end)
  return self
end

function Adapter:refresh()
  if self.chooser:isVisible() then self.chooser:choices(self.choices(self.chooser:query())) end
end

function Adapter:show()
  self.chooser:query("")
  self.chooser:choices(self.choices(""))
  self.chooser:show()
end

function Adapter:stop()
  if self.chooser:isVisible() then self.chooser:hide() end
  self.chooser:delete()
end

return Adapter
