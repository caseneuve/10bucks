local Geometry = {}

local function rect(x, y, w, h)
  return { x = x, y = y, w = math.max(0, w), h = math.max(0, h) }
end

function Geometry.frames(screenFrame, layout, ratio, outerGap, columnGap, topGap)
  local inner = rect(
    screenFrame.x + outerGap,
    screenFrame.y + topGap,
    screenFrame.w - (2 * outerGap),
    screenFrame.h - topGap - outerGap
  )

  if layout == "stack" then return { inner } end

  local divider = columnGap
  local availableWidth = math.max(0, inner.w - divider)
  local leftWidth = availableWidth * ratio
  return {
    rect(inner.x, inner.y, leftWidth, inner.h),
    rect(inner.x + leftWidth + divider, inner.y, availableWidth - leftWidth, inner.h),
  }
end

return Geometry
