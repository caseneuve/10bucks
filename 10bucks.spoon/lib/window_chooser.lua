-- Derived presentation only. Membership and native resource authority stay in
-- composition's Cores/unplaced state and handle registry.
local Chooser = {}

function Chooser.reduce(rows, event)
  local nextRows = {}
  local found = false
  for _, row in ipairs(rows) do
    local matches = row.windowId == event.windowId and row.lease == event.lease
    if event.type == "RemoveApplication" and row.pid == event.pid then
      -- Authoritative application termination.
    elseif event.type == "Remove" and matches then
    elseif event.type == "Upsert" and row.windowId == event.row.windowId then
      nextRows[#nextRows + 1] = event.row; found = true
    elseif event.type == "Title" and matches then
      nextRows[#nextRows + 1] = { windowId = row.windowId, lease = row.lease,
        pid = row.pid, text = event.title, subText = row.subText }
    else nextRows[#nextRows + 1] = row end
  end
  if event.type == "Upsert" and not found then nextRows[#nextRows + 1] = event.row end
  return nextRows
end

local function better(a, b)
  if not b then return true end
  for i = 1, 3 do
    if a[i] ~= b[i] then return a[i] < b[i] end
  end
  return false
end

-- Earliest successors minimize span for each start. Advancing starts move every
-- successor monotonically; each cursor counts only newly crossed UTF-8 segments.
local function score(value, literals, literal)
  value = value:lower() -- ASCII lower only; no Unicode folding/normalization.
  if value == literal then return { 1, 0, 1 } end
  local contiguous = value:find(literal, 1, true) ~= nil
  local ends, indexes = {}, {}
  for i = 1, #literals do ends[i], indexes[i] = 0, 0 end
  local bestClass, bestGaps, bestStart
  while true do
    local start, finish = value:find(literals[1], ends[1] + 1, true)
    if not start then break end
    indexes[1] = indexes[1] + utf8.len(value, ends[1] + 1, finish)
    ends[1] = finish
    local complete = true
    for i = 2, #literals do
      if ends[i] <= ends[i - 1] then
        local _, nextEnd = value:find(literals[i], ends[i - 1] + 1, true)
        if not nextEnd then complete = false; break end
        indexes[i] = indexes[i] + utf8.len(value, ends[i] + 1, nextEnd)
        ends[i] = nextEnd
      end
    end
    -- An exhausted earliest successor cannot recover for a later start.
    if not complete then break end
    local previous = start > 1 and value:byte(start - 1) or nil
    local boundary = not previous or (previous < 128 and
      string.char(previous):match("[%s%p]") ~= nil)
    local gaps = indexes[#literals] - indexes[1] + 1 - #literals
    local class = gaps == 0 and (boundary and 2 or 3) or (boundary and 4 or 5)
    -- Ascending starts make these the earliest unbeatable alignments. An
    -- interior match cannot exit: a later boundary match may outrank it.
    if class == 2 or (class == 4 and gaps == 1 and not contiguous) then
      return { class, gaps, indexes[1] }
    end
    if not bestClass or class < bestClass or (class == bestClass and
      (gaps < bestGaps or (gaps == bestGaps and indexes[1] < bestStart))) then
      bestClass, bestGaps, bestStart = class, gaps, indexes[1]
    end
  end
  if bestClass then return { bestClass, bestGaps, bestStart } end
end

function Chooser.filter(rows, query)
  query = (query or ""):lower()
  local literals, ranked = {}, {}
  for _, code in utf8.codes(query) do literals[#literals + 1] = utf8.char(code) end
  for rank, row in ipairs(rows) do
    local quality, field = nil, 1
    if #literals > 0 then
      quality = score(row.text, literals, query)
      local application = score(row.subText, literals, query)
      if application and (not quality or not better(quality, application)) then
        quality, field = application, 2
      end
    end
    if #literals == 0 or quality then
      ranked[#ranked + 1] = { row = row, quality = quality, field = field, rank = rank }
    end
  end
  if #literals > 0 then
    table.sort(ranked, function(a, b)
      if better(a.quality, b.quality) then return true end
      if better(b.quality, a.quality) then return false end
      if a.field ~= b.field then return a.field > b.field end
      return a.rank < b.rank
    end)
  end
  local choices = {}
  for _, item in ipairs(ranked) do
    local row = item.row
    -- Do not expose cache tables or transient scores to native consumers.
    local text = row.text
    if not text:find("%S") and row.subText:find("%S") then text = "[" .. row.subText .. "]" end
    choices[#choices + 1] = { text = text, subText = row.subText,
      windowId = row.windowId, lease = row.lease }
  end
  return choices
end

return Chooser
