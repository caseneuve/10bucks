local Bar = {}
Bar.__index = Bar

local function attempt(object, method, ...)
  if not object or type(object[method]) ~= "function" then return nil end
  local ok, value = pcall(object[method], object, ...)
  return ok and value or nil
end

local function truncate(text, maximum)
  text = tostring(text or "")
  if #text <= maximum then return text end
  return text:sub(1, math.max(1, maximum - 1)) .. "…"
end

local function screenId(screen)
  return tostring(screen:getUUID())
end

function Bar.new(hs, engine, repository, workspaces, config)
  assert(workspaces, "10bucks bar requires workspaces")
  return setmetatable({
    hs = hs,
    engine = engine,
    repository = repository,
    workspaces = workspaces,
    config = config,
    canvases = {},
    handoffs = {},
  }, Bar)
end

-- Draw the two layout modes directly in the canvas. This follows the
-- overlapping-window and two-pane icons without requiring a separately
-- installed icon font or relying on text baseline metrics.
function Bar:layoutIconElements(layout, x, topPadding, contentHeight)
  local color = self.config.textColor
  local size = 11
  -- Canvas text sits high within its frame; reserve five points below the
  -- smaller geometric icon so its visual center tracks the text glyphs.
  local y = math.max(0, topPadding + math.max(0, (contentHeight - size) / 2) - 5)
  local function outline(frame)
    return {
      type = "rectangle",
      action = "stroke",
      frame = frame,
      strokeColor = color,
      strokeWidth = 1.5,
    }
  end

  if layout == "columns" then
    return {
      outline({ x = x, y = y, w = 13, h = size }),
      {
        type = "rectangle",
        action = "fill",
        frame = { x = x + 6, y = y + 1, w = 1, h = size - 2 },
        fillColor = color,
      },
    }
  end

  return {
    outline({ x = x, y = y, w = 9, h = 8 }),
    outline({ x = x + 3, y = y + 3, w = 9, h = 8 }),
  }
end

-- Return the layout separately so its canvas icon can lead the workspace,
-- focused-window title, and trailing selected/total stack indicator.
function Bar:status(screen)
  local window = self.repository:focusedWindow()
  local context = self.repository:contextForWindow(window) or self.repository:currentContext()
  local layout, position = "stack", "0/0"
  if context then
    local scope = self.engine.state:scope(context)
    local column = scope.columns[scope.activeColumn]
    layout = scope.layout
    -- Retain the selected member as well as the stack total, e.g. (2/3).
    position = column.selected and string.format("%d/%d", column.selected, #column.windows) or "0/0"
  end

  local title = attempt(window, "title")
  if not title or title == "" then
    title = attempt(attempt(window, "application"), "name") or "No focused window"
  end
  local workspaceLabel = self.config.showWorkspaces and self.workspaces:label(screen)
  local workspace = workspaceLabel and (workspaceLabel .. " · ") or ""
  return layout, string.format("%s%s  (%s) ", workspace, truncate(title, 90), position)
end

function Bar:pointerOver(frame)
  if not self.hs.mouse or type(self.hs.mouse.absolutePosition) ~= "function" then return false end
  local point = self.hs.mouse.absolutePosition()
  return point and point.x >= frame.x and point.x < frame.x + frame.w
    and point.y >= frame.y and point.y < frame.y + frame.h
end

-- Hammerspoon's seconds source is fakeable in tests; os.clock is only a
-- fallback for non-Hammerspoon callers that do not provide hs.timer.
function Bar:seconds()
  local timer = self.hs and self.hs.timer
  if timer and type(timer.secondsSinceEpoch) == "function" then
    local ok, value = pcall(timer.secondsSinceEpoch)
    if ok and type(value) == "number" then return value end
  end
  return os.clock()
end

function Bar:isFullscreenSpace(screen)
  local spaceId = self.workspaces:activeSpace(screen)
  if spaceId and self.workspaces:isFullscreenSpace(spaceId) then return true end

  -- The Spaces API is private/experimental and can occasionally fail. A
  -- focused native-fullscreen window is sufficient as a conservative fallback.
  local focused = self.repository:focusedWindow()
  local focusedScreen = attempt(focused, "screen")
  return attempt(focused, "isFullScreen") == true and focusedScreen
    and screenId(focusedScreen) == screenId(screen)
end

function Bar:clockText(timestamp)
  return os.date("%a, %d %b, %H:%M", timestamp)
end

function Bar:render(canvas, frame, screen)
  local height = self.config.height
  local topPadding = self.config.topPadding
  local contentHeight = height - topPadding
  local clockWidth = 168
  local clockX = math.max(0, frame.w - self.config.rightInset - clockWidth)
  canvas:frame(frame)
  local layout, status = self:status(screen)
  local iconX, statusX = 12, 34
  local elements = {
    {
      type = "rectangle",
      action = "fill",
      frame = { x = 0, y = 0, w = frame.w, h = height },
      fillColor = self.config.backgroundColor,
    },
  }
  for _, iconElement in ipairs(self:layoutIconElements(layout, iconX, topPadding, contentHeight)) do
    table.insert(elements, iconElement)
  end
  table.insert(elements, {
    type = "text",
    frame = { x = statusX, y = topPadding, w = math.max(0, clockX - statusX - 12), h = contentHeight },
    text = status,
    textColor = self.config.textColor,
    textFont = self.config.font,
    textSize = self.config.textSize,
    textLineBreak = "truncateTail",
  })
  table.insert(elements, {
    type = "text",
    frame = { x = clockX, y = topPadding, w = clockWidth, h = contentHeight },
    text = self:clockText(),
    textColor = self.config.textColor,
    textFont = self.config.font,
    textSize = self.config.textSize,
    textAlignment = "right",
  })
  canvas:replaceElements(elements)
end

-- Refresh the canvas content and recover canvases that are actually hidden.
-- A pointer handoff temporarily suppresses the canvas while macOS retracts its
-- auto-hidden menu bar; refreshes do not reorder canvases that are already shown.
function Bar:refresh()
  if not self.config.enabled then return self end

  local present = {}
  for _, screen in ipairs(self.hs.screen.allScreens()) do
    local id = screenId(screen)
    local fullFrame = attempt(screen, "fullFrame")
    if fullFrame then
      local frame = { x = fullFrame.x, y = fullFrame.y, w = fullFrame.w, h = self.config.height }
      local canvas = self.canvases[id]
      if not canvas then
        canvas = self.hs.canvas.new(frame)
        -- Match macOS's native menu-bar window level. When the menu bar
        -- auto-reveals, macOS orders it above this same-level canvas.
        canvas:level("mainMenu")
        canvas:behavior({ "canJoinAllSpaces", "stationary", "ignoresCycle" })
        canvas:clickActivating(false)
        self.canvases[id] = canvas
      end
      self:render(canvas, frame, screen)
      local pointerOver = self:pointerOver(frame)
      local handoff = self.handoffs[id]
      if self:isFullscreenSpace(screen) then
        self.handoffs[id] = nil
        if canvas:isShowing() then canvas:hide() end
      elseif pointerOver then
        local untilTime = self:seconds() + self.config.menuBarHideDelay
        if not handoff or handoff.phase ~= "suppressing" then
          handoff = { phase = "suppressing", suppressUntil = untilTime, hideRequested = false }
          self.handoffs[id] = handoff
        else
          handoff.suppressUntil = untilTime
        end
        if not handoff.hideRequested then
          handoff.hideRequested = true
          if canvas:isShowing() then canvas:hide(self.config.menuBarFadeDuration or 0) end
        end
      elseif handoff and handoff.phase == "suppressing" and self:seconds() < handoff.suppressUntil then
        -- Keep the canvas suppressed while the native menu bar retracts.
      elseif handoff and handoff.phase == "showing" then
        if canvas:isShowing() then self.handoffs[id] = nil end
      elseif not canvas:isShowing() then
        canvas:show(self.config.menuBarFadeDuration or 0)
        self.handoffs[id] = { phase = "showing" }
      else
        self.handoffs[id] = nil
      end
      present[id] = true
    end
  end

  for id, canvas in pairs(self.canvases) do
    if not present[id] then
      canvas:delete()
      self.canvases[id] = nil
      self.handoffs[id] = nil
    end
  end
  return self
end

function Bar:start()
  if not self.config.enabled then return self end
  self:refresh()
  self.timer = self.hs.timer.doEvery(self.config.refreshInterval, function() self:refresh() end)
  return self
end

function Bar:stop()
  if self.timer then self.timer:stop() self.timer = nil end
  for id, canvas in pairs(self.canvases) do
    canvas:delete()
    self.canvases[id] = nil
    self.handoffs[id] = nil
  end
  self.handoffs = {}
  return self
end

return Bar
