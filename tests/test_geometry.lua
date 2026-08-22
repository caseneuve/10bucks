local Geometry = require("lib.geometry")

local function equal(actual, expected)
  assert(actual == expected, string.format("expected %s, got %s", tostring(expected), tostring(actual)))
end

return {
  ["stack frame applies the outer gap once"] = function()
    local frames = Geometry.frames({ x = 10, y = 20, w = 1000, h = 800 }, "stack", 0.5, 10, 0, 10)
    equal(#frames, 1)
    equal(frames[1].x, 20)
    equal(frames[1].y, 30)
    equal(frames[1].w, 980)
    equal(frames[1].h, 780)
  end,

  ["stack frame can meet a bar while retaining side and bottom gaps"] = function()
    local frames = Geometry.frames({ x = 0, y = 32, w = 1000, h = 800 }, "stack", 0.5, 8, 0, 0)
    equal(frames[1].x, 8)
    equal(frames[1].y, 32)
    equal(frames[1].w, 984)
    equal(frames[1].h, 792)
  end,

  ["column frames consume the divider without overlap"] = function()
    local frames = Geometry.frames({ x = 0, y = 0, w = 1000, h = 800 }, "columns", 0.6, 10, 20, 10)
    equal(frames[1].x, 10)
    equal(frames[1].w, 576)
    equal(frames[2].x, 606)
    equal(frames[2].w, 384)
    equal(frames[1].x + frames[1].w + 20, frames[2].x)
  end,
}
