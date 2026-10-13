local Rows = require("lib.window_chooser")
local Adapter = require("lib.macos.chooser")
local function row(id, lease, title, app, pid)
  return { windowId = id, lease = lease, text = title, subText = app, pid = pid or 8 }
end
return {
  ["CHOOSE-001 CHOOSE-003: lifecycle metadata preserves survivors and exact removal"] = function()
    local rows = Rows.reduce({}, { type = "Upsert", row = row(1, 11, "Alpha", "Editor") })
    rows = Rows.reduce(rows, { type = "Upsert", row = row(2, 12, "Beta", "Browser", 9) })
    rows = Rows.reduce(rows, { type = "Title", windowId = 1, lease = 99, title = "Wrong" })
    assert(Rows.filter(rows, "")[1].text == "Alpha")
    rows = Rows.reduce(rows, { type = "Title", windowId = 1, lease = 11, title = "Changed" })
    rows = Rows.reduce(rows, { type = "Upsert", row = row(2, 12, "Relocated", "Browser", 9) })
    local choices = Rows.filter(rows, "")
    assert(choices[1].windowId == 1 and choices[1].text == "Changed" and choices[2].windowId == 2)
    choices[1].text = "Not cached"
    assert(Rows.filter(rows, "")[1].text == "Changed")
    rows = Rows.reduce(rows, { type = "Remove", windowId = 1, lease = 99 })
    assert(#Rows.filter(rows, "") == 2)
    rows = Rows.reduce(rows, { type = "Remove", windowId = 1, lease = 11 })
    rows = Rows.reduce(rows, { type = "RemoveApplication", pid = 9 })
    assert(#Rows.filter(rows, "") == 0)
  end,
  ["CHOOSE-004: stable case-insensitive title/application subsequences and literal symbols"] = function()
    local rows = { row(1, 11, "Alpha Beta", "Editor"), row(2, 12, "A.b", "Alpha Browser") }
    assert(#Rows.filter(rows, "AB") == 2)
    assert(Rows.filter(rows, "abr")[1].windowId == 2)
    assert(Rows.filter(rows, ".")[1].windowId == 2)
    assert(#Rows.filter(rows, "baah") == 0)
    assert(#Rows.filter(rows, "") == 2)
  end,
  ["CHOOSE-002 CHOOSE-004: adapter query projection cancellation and disposal have no window queries"] = function()
    local n = { visible = false, value = "" }
    function n:queryChangedCallback(cb) self.changed = cb; return self end
    function n:choices(value) self.rows = value; return self end
    function n:query(value) if value == nil then return self.value end; self.value = value; self.changed(value); return self end
    function n:show() self.visible = true end
    function n:isVisible() return self.visible end
    function n:hide() self.visible = false end
    function n:delete() assert(not self.visible); self.deleted = true; self.complete = nil end
    local selected = 0
    local hs = { chooser = { new = function(cb) n.complete = cb; return n end }, alert = { show = function() error("unexpected rejection") end } }
    local rows = { row(1, 11, "Alpha", "Editor"), row(2, 12, "Beta", "Browser") }
    local adapter = Adapter.new(hs, function(query) return Rows.filter(rows, query) end,
      function(choice) selected = choice.windowId; return true end)
    adapter:show(); assert(#n.rows == 2)
    n:query("bt"); assert(#n.rows == 1 and n.rows[1].windowId == 2)
    n.complete(nil); assert(selected == 0)
    n.complete(n.rows[1]); assert(selected == 2)
    rows = {}; adapter:refresh(); assert(#n.rows == 0)
    adapter:stop(); assert(n.deleted and not n.visible and not n.complete)
  end,
}
