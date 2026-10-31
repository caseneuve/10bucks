-- Thin native owner for the one display overlay bar. It receives preformatted
-- presentation only; callbacks ask composition to publish a fresh cached view.
local NativeBar = {}
NativeBar.__index = NativeBar

local function sameFrame(a, b) return a and b and a.x == b.x and a.y == b.y and a.w == b.w and a.h == b.h end
local function sameElements(a, b)
  -- Local comparison of this small plain canvas presentation; it intentionally
  -- is not a shared equality framework or a formatter-schema whitelist.
  if a == b then return true end
  if type(a) ~= type(b) then return false end
  if type(a) ~= "table" then return a == b end
  local seen = {}
  for key, value in pairs(a) do seen[key] = true; if not sameElements(value, b[key]) then return false end end
  for key in pairs(b) do if not seen[key] then return false end end
  return true
end

function NativeBar.new(hs, update)
  assert(type(update) == "function", "native bar requires a composition update callback")
  return setmetatable({ hs = hs, update = update, grace = .2, interval = .05, settle = .5 }, NativeBar)
end
function NativeBar:_seconds() return self.hs.timer.secondsSinceEpoch() end
function NativeBar:_inside()
  local point, area = self.hs.mouse.absolutePosition(), self.presentation and self.presentation.frame
  return point and area and point.x >= area.x and point.x < area.x + area.w and point.y >= area.y and point.y < area.y + area.h
end
function NativeBar:_stopPointer()
  if self.pointerTimer then self.pointerTimer:stop(); self.pointerTimer = nil end
  self.leftAt = nil
end
function NativeBar:_stopParticipation()
  if self.participationDeadline then self.participationDeadline:stop(); self.participationDeadline = nil end
  self.checkedSpaceId = nil
end
-- BAR-001: a canvas can keep its canJoinAllSpaces flag and AppKit ordered-in
-- state while macOS pins it to the Spaces it was on (Verified host failure;
-- show, hide/show and same-value behavior did not repair it, a fresh canvas
-- did). Once per regular-Space arrival, after the switch settles, an occluded
-- intended-visible canvas is replaced. One-shot deadline, never a poll.
function NativeBar:_checkParticipation(spaceId)
  if self.checkedSpaceId == spaceId then return end
  self:_stopParticipation(); self.checkedSpaceId = spaceId
  self.participationDeadline = self.hs.timer.doAfter(self.settle, function()
    self.participationDeadline = nil
    local presentation = self.presentation
    if not (self.canvas and self.showing and not self.handoff and presentation and presentation.visible
      and presentation.spaceId == spaceId and self.canvas:isOccluded()) then return end
    self.canvas:delete(); self.canvas, self.frame, self.elements, self.showing = nil, nil, nil, false
    self:present(presentation)
  end)
end
function NativeBar:_handoff()
  if self.handoff or not self.canvas then return end
  self:_stopParticipation()
  self.handoff = true
  if self.showing then self.canvas:hide(); self.showing = false end
  self.pointerTimer = self.hs.timer.doEvery(self.interval, function()
    if not self.handoff then return end
    if self:_inside() then self.leftAt = nil; return end
    local now = self:_seconds(); self.leftAt = self.leftAt or now
    if now - self.leftAt >= self.grace then self:_stopPointer(); self.handoff = false; if self.presentation and self.presentation.visible then self.canvas:show(); self.showing = true; self:_checkParticipation(self.presentation.spaceId) end end
  end)
end
function NativeBar:_mouse(_, message) if message == "mouseEnter" then self:_handoff() end end
function NativeBar:_ensure()
  if self.canvas then return end
  self.canvas = self.hs.canvas.new(self.presentation.frame)
  self.canvas:level("overlay"):behavior({ "canJoinAllSpaces", "stationary", "ignoresCycle" }):clickActivating(false)
  self.canvas:canvasMouseEvents(false, false, true, false)
  self.canvas:mouseCallback(function(...) self:_mouse(...) end)
end
function NativeBar:present(presentation)
  assert(type(presentation.displayId) == "string" and presentation.displayId ~= "", "bar presentation requires display identity")
  if self.displayId then assert(self.displayId == presentation.displayId, "native bar owns one display") else self.displayId = presentation.displayId end
  if not presentation.visible then
    self:_stopPointer(); self:_stopParticipation(); self.handoff = false
    if self.canvas and self.showing then self.canvas:hide(); self.showing = false end
    self.presentation = presentation; return self
  end
  self.presentation = presentation; self:_ensure()
  if not sameFrame(self.frame, presentation.frame) then self.canvas:frame(presentation.frame); self.frame = { x = presentation.frame.x, y = presentation.frame.y, w = presentation.frame.w, h = presentation.frame.h } end
  if not sameElements(self.elements, presentation.elements) then self.canvas:replaceElements(presentation.elements); self.elements = presentation.elements end
  -- Visibility is native adapter state, not the last requested show/hide.
  -- Check only on event publication; never introduce a recovery poll.
  if self.showing and self.canvas.isShowing and not self.canvas:isShowing() then self.showing = false end
  if not self.handoff and not self.showing then
    -- Read the pointer only when about to show: unchanged publications must not
    -- query it, and an already-inside pointer hands off without a show/hide flash.
    if self:_inside() then self:_handoff() else self.canvas:show(); self.showing = true end
  end
  if self.showing and not self.handoff then self:_checkParticipation(presentation.spaceId) end
  return self
end
function NativeBar:_clock()
  self.update("clock")
end
function NativeBar:start()
  local delay = 60 - (self:_seconds() % 60)
  self.clockDeadline = self.hs.timer.doAfter(delay, function()
    self.clockDeadline = nil; self:_clock(); self.clockTimer = self.hs.timer.doEvery(60, function() self:_clock() end)
  end)
  -- The notification API is documented; this name is an unproved hypothesis
  -- pending manual theme-toggle evidence. Never poll instead.
  local ok, notification = pcall(self.hs.distributednotifications.new, function() self.update("appearance") end,
    "AppleInterfaceThemeChangedNotification")
  if not ok or not notification then self:stop(); error(notification or "appearance notification allocation failed", 0) end
  self.appearanceNotification = notification
  ok, notification = pcall(notification.start, notification)
  if not ok then self:stop(); error(notification, 0) end
  return self
end
function NativeBar:timerCount()
  local count = 0
  if self.clockDeadline then count = count + 1 end
  if self.clockTimer then count = count + 1 end
  if self.pointerTimer then count = count + 1 end
  if self.participationDeadline then count = count + 1 end
  return count
end
function NativeBar:stop()
  self:_stopPointer(); self:_stopParticipation()
  if self.clockDeadline then self.clockDeadline:stop(); self.clockDeadline = nil end
  if self.clockTimer then self.clockTimer:stop(); self.clockTimer = nil end
  if self.appearanceNotification then self.appearanceNotification:stop(); self.appearanceNotification = nil end
  if self.canvas then self.canvas:delete(); self.canvas = nil end
  self.presentation, self.elements, self.frame, self.displayId, self.showing, self.handoff = nil, nil, nil, nil, false, false
  return self
end
return NativeBar
