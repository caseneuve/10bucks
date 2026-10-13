local Adapter = {}
Adapter.__index = Adapter

function Adapter.new(hs, choices, select)
  local self = setmetatable({ choices = choices }, Adapter)
  self.chooser = hs.chooser.new(function(choice)
    if choice then
      local ok, reason = select(choice)
      if not ok then hs.alert.show("10bucks: " .. tostring(reason)) end
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
