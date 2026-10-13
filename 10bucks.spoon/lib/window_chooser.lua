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

local function subsequence(value, query)
  value = value:lower()
  local position = 1
  for _, code in utf8.codes(query) do
    local start, finish = value:find(utf8.char(code), position, true)
    if not start then return false end
    position = finish + 1
  end
  return true
end

function Chooser.filter(rows, query)
  query = (query or ""):lower()
  local choices = {}
  for _, row in ipairs(rows) do
    if subsequence(row.text, query) or subsequence(row.subText, query) then
      -- Do not expose cache tables to native conversion or completion consumers.
      choices[#choices + 1] = { text = row.text, subText = row.subText,
        windowId = row.windowId, lease = row.lease }
    end
  end
  return choices
end

return Chooser
