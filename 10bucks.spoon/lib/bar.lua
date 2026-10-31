-- Pure bar semantics and the one current formatter. Native canvas/timer lifetime
-- is intentionally isolated in lib/macos/bar.lua.
local Bar = {}
local HEIGHT, TOP_PADDING, RIGHT_INSET = 32, 4, 25
-- Align rendered text with the privacy indicator and icons with the text centre.
local CONTENT_OFFSET, ICON_OFFSET = 5, 3.5
local DARK = { background = { red = .08, green = .09, blue = .12, alpha = .45 }, text = { red = .9, green = .92, blue = .96, alpha = 1 } }
local LIGHT = { background = { red = .94, green = .95, blue = .97, alpha = .65 }, text = { red = .08, green = .09, blue = .12, alpha = 1 } }

local function frame(frame) return { x = frame.x, y = frame.y, w = frame.w, h = frame.h } end
-- BAR-004: this small pure reducer is composition-owned actual presentation,
-- not managed selection/history and never an admission path.
function Bar.reduceActual(actual, event)
  actual = actual or {}
  if event.type == "ActualFocusChanged" then
    if event.id == nil then return {} end
    return { id = event.id, title = type(event.title) == "string" and event.title or nil,
      applicationName = type(event.applicationName) == "string" and event.applicationName or nil,
      applicationPid = event.applicationPid, windowResource = event.resource,
      appResource = event.appResource, presentationResource = event.presentationResource,
      nativeFullscreen = event.nativeFullscreen == true }
  end
  local matchingWindow = event.presentationResource == nil and event.resource == actual.windowResource
  local matchingPresentation = event.presentationResource ~= nil and event.presentationResource == actual.presentationResource
  if event.type == "WindowTitleChanged" and actual.id == event.id and (matchingWindow or matchingPresentation) then
    return { id = actual.id, title = event.title, applicationName = actual.applicationName,
      applicationPid = actual.applicationPid, windowResource = actual.windowResource,
      appResource = actual.appResource, presentationResource = actual.presentationResource,
      nativeFullscreen = actual.nativeFullscreen == true }
  end
  if event.id == actual.id and (matchingWindow or matchingPresentation)
    and (event.type == "WindowEnteredNativeFullscreen" or event.type == "WindowExitedNativeFullscreen") then
    return { id = actual.id, title = actual.title, applicationName = actual.applicationName,
      applicationPid = actual.applicationPid, windowResource = actual.windowResource,
      appResource = actual.appResource, presentationResource = actual.presentationResource,
      nativeFullscreen = event.type == "WindowEnteredNativeFullscreen" }
  end
  if event.type == "WindowDestroyed" and actual.id == event.id and (matchingWindow or matchingPresentation) then return {} end
  if event.type == "PresentationEnded" and actual.id == event.id
    and event.presentationResource == actual.presentationResource then return {} end
  if event.type == "ApplicationTerminated" and actual.applicationPid == event.pid
    and event.resource == actual.appResource then return {} end
  return actual
end

local function title(actual)
  if actual and type(actual.title) == "string" and actual.title ~= "" then return actual.title end
  if actual and type(actual.applicationName) == "string" and actual.applicationName ~= "" then return actual.applicationName end
  return "No focused window"
end
local function truncate(text, maximum)
  local length = utf8.len(text)
  if not length or length <= maximum then return text end
  -- Preserve legacy's 90-character total: 89 Unicode characters + ellipsis.
  return text:sub(1, utf8.offset(text, maximum) - 1) .. "…"
end

-- BAR-003/BAR-004: only committed/cached primitive facts enter this projection.
function Bar.view(input)
  local context, positions, status = input.context, input.context.regularPositions or {}, input.status or {}
  return { displayId = context.displayId, frame = frame(context.barFrame), visible = context.regularSpaceId ~= nil and input.actual.nativeFullscreen ~= true,
    layout = input.layout or "stack", regularPositions = positions, activeSpaceId = context.regularSpaceId,
    actual = input.actual or {}, position = status.position, count = status.count or 0,
    timestamp = input.timestamp, dark = input.dark == true }
end

local function desktopText(view)
  local labels = {}
  for index, spaceId in ipairs(view.regularPositions) do labels[#labels + 1] = spaceId == view.activeSpaceId and "[" .. index .. "]" or tostring(index) end
  return #labels > 0 and table.concat(labels, " ") .. " · " or ""
end
local function icon(layout, color)
  local y = ICON_OFFSET + math.max(0, TOP_PADDING + math.max(0, ((HEIGHT - TOP_PADDING) - 11) / 2) - 5)
  local function outline(value) return { type = "rectangle", action = "stroke", frame = value, strokeColor = color, strokeWidth = 1.5 } end
  if layout == "columns" then return { outline({ x = 12, y = y, w = 13, h = 11 }), { type = "rectangle", action = "fill", frame = { x = 18, y = y + 1, w = 1, h = 9 }, fillColor = color } } end
  return { outline({ x = 12, y = y, w = 9, h = 8 }), outline({ x = 15, y = y + 3, w = 9, h = 8 }) }
end

-- The practical future-formatter seam: semantic view in, plain canvas
-- presentation out. No native handle, clock, or query enters this function.
function Bar.format(view)
  local palette, clockX, contentHeight = view.dark and DARK or LIGHT, math.max(0, view.frame.w - RIGHT_INSET - 168), HEIGHT - TOP_PADDING - CONTENT_OFFSET
  local elements = { { type = "rectangle", action = "fill", frame = { x = 0, y = 0, w = view.frame.w, h = HEIGHT }, fillColor = palette.background } }
  for _, item in ipairs(icon(view.layout, palette.text)) do elements[#elements + 1] = item end
  elements[#elements + 1] = { type = "text", frame = { x = 34, y = TOP_PADDING + CONTENT_OFFSET, w = math.max(0, clockX - 46), h = contentHeight },
    text = desktopText(view) .. truncate(title(view.actual), 90) .. "  (" .. (view.position or 0) .. "/" .. view.count .. ") ", textColor = palette.text, textFont = "Menlo", textSize = 13, textLineBreak = "truncateTail" }
  elements[#elements + 1] = { type = "text", frame = { x = clockX, y = TOP_PADDING + CONTENT_OFFSET, w = 168, h = contentHeight }, text = os.date("%a, %d %b, %H:%M", math.floor(view.timestamp)), textColor = palette.text, textFont = "Menlo", textSize = 13, textAlignment = "right" }
  return { displayId = view.displayId, spaceId = view.activeSpaceId, frame = frame(view.frame), visible = view.visible, elements = elements }
end
return Bar
