local Rows = require("lib.window_chooser")
local Adapter = require("lib.macos.chooser")
local function row(id, lease, title, app, pid)
  return { windowId = id, lease = lease, text = title, subText = app, pid = pid or 8 }
end
local function order(query, titles, expected, apps)
  local rows = {}
  for i, title in ipairs(titles) do rows[i] = row(i, i + 100, title, apps and apps[i] or "Utility") end
  local choices = Rows.filter(rows, query)
  assert(#choices == #expected)
  for i, id in ipairs(expected) do
    assert(choices[i].windowId == id, "unexpected relevance order at " .. i)
    assert(choices[i].lease == id + 100)
  end
end
-- Test-only exhaustive alignment oracle; no production scoring API involved.
local function oracle(value, query)
  local chars, codes = {}, {}
  for _, c in utf8.codes(value:lower()) do chars[#chars + 1] = c end
  for _, c in utf8.codes(query:lower()) do codes[#codes + 1] = c end
  local best
  local function before(a, b)
    if not b then return true end
    for i = 1, 3 do if a[i] ~= b[i] then return a[i] < b[i] end end
    return false
  end
  local function visit(index, after, start)
    for p = after + 1, #chars do
      if chars[p] == codes[index] then
        local first = start or p
        if index < #codes then visit(index + 1, p, first)
        else
          local previous = chars[first - 1]
          local boundary = not previous or (previous < 128 and utf8.char(previous):match("[%s%p]"))
          local gaps = p - first + 1 - #codes
          local class = gaps == 0 and (boundary and 2 or 3) or (boundary and 4 or 5)
          if gaps == 0 and #chars == #codes then class = 1 end
          local key = { class, gaps, first }
          if before(key, best) then best = key end
        end
      end
    end
  end
  visit(1, 0)
  return best
end
return {
  ["CHOOSE-004: exhaustive small alignments agree with public row order"] = function()
    local titles = { "" }
    local function generate(prefix, remaining)
      if remaining == 0 then return end
      for _, char in ipairs({ "a", "b", " " }) do
        local value = prefix .. char
        titles[#titles + 1] = value
        generate(value, remaining - 1)
      end
    end
    generate("", 4)
    for _, query in ipairs({ "a", "b", "aa", "ab", "ba", "aba", "aab", "a b" }) do
      local expected, apps = {}, {}
      for id, title in ipairs(titles) do
        apps[id] = titles[#titles - id + 1]
        local key, app = oracle(title, query), oracle(apps[id], query)
        local field = 1
        local appWins = app ~= nil
        if app and key then
          for i = 1, 3 do
            if app[i] ~= key[i] then appWins = app[i] < key[i]; break end
          end
        end
        if appWins then key, field = app, 2 end
        if key then expected[#expected + 1] = { id = id, key = key, field = field } end
      end
      table.sort(expected, function(a, b)
        for i = 1, 3 do if a.key[i] ~= b.key[i] then return a.key[i] < b.key[i] end end
        if a.field ~= b.field then return a.field > b.field end
        return a.id < b.id
      end)
      local ids = {}
      for i, item in ipairs(expected) do ids[i] = item.id end
      order(query, titles, ids, apps)
    end
  end,
  ["CHOOSE-004: codepoint gaps and later compact noncontiguous alignment"] = function()
    order("猫犬", { "猫--犬", "猫é犬" }, { 2, 1 })
    order("ab", { "a----b a-b", "a--b" }, { 1, 2 })
    order("ab", { "xa-b", "a----b" }, { 2, 1 })
  end,
  ["CHOOSE-003 CHOOSE-004: relevance classes compact gaps and earlier starts"] = function()
    order("in", { "i---n", "xinx", "Inbox", "in", "item notes" }, { 4, 3, 2, 1, 5 })
    order("inb", { "items needing backup", "Inbox", "x i-n-b", "x inb" }, { 2, 4, 3, 1 })
    order("ab", { "a---b", "a-b", "x a-b" }, { 2, 3, 1 })
    order("i", { "xi", "Inbox", "i" }, { 3, 2, 1 })
  end,
  ["CHOOSE-004: best later alignment and repeated characters"] = function()
    order("inb", { "i---n---b Inbox", "i-n-b" }, { 1, 2 })
    order("aab", { "a---a---b aab", "a-a-b", "ab" }, { 1, 2 })
    order("aba", { "a---b---a aba", "a-b-a" }, { 1, 2 })
  end,
  ["CHOOSE-003 CHOOSE-004: field quality then application then admission ties"] = function()
    order("in", { "Other", "Inbox", "in", "Other", "in" }, { 1, 3, 5, 4, 2 },
      { "in", "Utility", "Utility", "Inbox", "Utility" })
    order("in", { "in", "Other" }, { 1, 2 }, { "i---n", "Inbox" })
    order("in", { "in", "in", "Other" }, { 2, 3, 1 }, { "Utility", "in", "in" })
    order("ed", { "Other", "Other" }, { 1, 2 }, { "Editor", "Editor" })
    order("", { "Z", "A", "M" }, { 1, 2, 3 })
  end,
  ["CHOOSE-004: literal ordered Unicode and ASCII-only lower semantics"] = function()
    order(".[", { "x.[", ".[", ".---[", "[." }, { 2, 1, 3 })
    order("猫犬", { "猫--犬", "猫犬", "犬猫" }, { 2, 1 })
    order("A猫", { "a猫", "A---猫", "猫a" }, { 1, 2 })
    order("é", { "É", "é", "e\204\129" }, { 2 })
    order(" ", { "a b", "ab" }, { 1 })
  end,
  ["CHOOSE-003: ranked output is detached and leaves every input field intact"] = function()
    local rows = { row(1, 91, "i---n", "Utility"), row(2, 92, "Inbox", "Utility") }
    local first, second = rows[1], rows[2]
    local choices = Rows.filter(rows, "in")
    assert(choices[1].windowId == 2 and choices[1].lease == 92)
    choices[1].text, choices[1].lease, choices[1].windowId = "Changed", 0, 0
    assert(rows[1] == first and rows[2] == second)
    assert(first.text == "i---n" and first.subText == "Utility" and first.pid == 8 and first.lease == 91)
    assert(second.text == "Inbox" and second.subText == "Utility" and second.pid == 8 and second.lease == 92)
    local empty = Rows.filter(rows, nil)
    assert(empty[1].windowId == 1 and empty[2].windowId == 2 and empty[2].lease == 92)
  end,
  ["CHOOSE-003 CHOOSE-004: blank titles display the bracketed app label without changing search"] = function()
    local rows = { row(1, 11, "", "Utility"), row(2, 12, "Named", "Utility"),
      row(3, 13, "  ", "Utility"), row(4, 14, "", "") }
    local choices = Rows.filter(rows, "")
    assert(choices[1].text == "[Utility]" and choices[1].subText == "Utility")
    assert(choices[1].windowId == 1 and choices[1].lease == 11 and rows[1].text == "")
    assert(choices[2].text == "Named" and choices[3].text == "[Utility]" and choices[4].text == "")
    assert(#Rows.filter(rows, "[") == 0)
    local found = Rows.filter(rows, "Utility")
    assert(#found == 3 and found[1].windowId == 1 and found[2].windowId == 2 and found[3].windowId == 3)
    rows = Rows.reduce(rows, { type = "Title", windowId = 1, lease = 11, title = "New title" })
    assert(Rows.filter(rows, "")[1].text == "New title")
  end,
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
  ["CHOOSE-004 CMD-001: chooser rejections offer an action without exposing internal codes"] = function()
    local complete, message, reason
    local hs = { chooser = { new = function(callback)
      complete = callback; return { queryChangedCallback = function() end }
    end }, alert = { show = function(value) message = value end } }
    Adapter.new(hs, function() return {} end, function() return false, reason end)
    for _, code in ipairs({ "stale-chooser-target", "chooser-restoration-deferred", "desktop-switch-pending",
      "desktop-creation-pending", "managed-focus-failed", "unknown-internal-failure" }) do
      reason = code; complete({ windowId = 1 })
      assert(message:find("10bucks:", 1, true) and not message:find(code, 1, true))
      assert(message:find("try again", 1, true) or message:find("reopen", 1, true) or message:find("choose", 1, true))
    end
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
