local Config = {}

Config.defaults = {
  builtInDisplayUUID = nil,
  hotkeys = {
    cycleLayout = { { "cmd", "alt", "ctrl", "shift" }, "space" },
    focusPreviousGroup = { { "cmd", "alt", "ctrl", "shift" }, "h" },
    focusNextGroup = { { "cmd", "alt", "ctrl", "shift" }, "l" },
    focusPrevious = { { "cmd", "alt", "ctrl", "shift" }, "k" },
    focusNext = { { "cmd", "alt", "ctrl", "shift" }, "j" },
    focusManagedPrevious = { { "cmd", "alt", "ctrl", "shift" }, "'" },
    moveFocusedToOtherGroup = { { "cmd", "alt", "ctrl", "shift" }, "o" },
    swapGroups = { { "cmd", "alt", "ctrl", "shift" }, "g" },
    resizeLeft = { { "cmd", "alt", "ctrl", "shift" }, "[" },
    resizeRight = { { "cmd", "alt", "ctrl", "shift" }, "]" },
    resetRatio = { { "cmd", "alt", "ctrl", "shift" }, "=" },
    reflow = { { "cmd", "alt", "ctrl", "shift" }, "r" },
  },
  canaryInstrumentation = false,
}

local modifiers = { cmd = true, alt = true, ctrl = true, shift = true, fn = true }
local function dense(a) for i = 1, #a do if a[i] == nil then return false end end; for k in pairs(a) do if type(k) ~= "number" or k < 1 or k % 1 ~= 0 or k > #a then return false end end; return true end
local function copy(v, seen)
  if type(v) ~= "table" then return v end
  seen = seen or {}; assert(not seen[v], "10bucks config must not contain cycles"); seen[v] = true
  local r = {}; for k, x in pairs(v) do assert(type(k) ~= "table" and type(x) ~= "function", "10bucks config must contain data only"); r[k] = copy(x, seen) end; seen[v] = nil; return r
end
local function chord(name, value)
  assert(value == false or (type(value) == "table" and dense(value) and #value == 2 and type(value[1]) == "table" and dense(value[1]) and type(value[2]) == "string"), "10bucks config: hotkeys." .. name .. " must be false or { modifiers, key }")
  if value == false then return nil end
  local seen, ordered = {}, {}
  for _, mod in ipairs(value[1]) do assert(modifiers[mod], "10bucks config: hotkeys." .. name .. " has unsupported modifier"); assert(not seen[mod], "10bucks config: hotkeys." .. name .. " repeats a modifier"); seen[mod] = true; ordered[#ordered + 1] = mod end
  table.sort(ordered); return table.concat(ordered, "+") .. ":" .. value[2]
end
function Config.build(override)
  override = override or {}; assert(type(override) == "table", "10bucks config must be a table")
  for key in pairs(override) do assert(key == "hotkeys" or key == "builtInDisplayUUID" or key == "canaryInstrumentation", "10bucks Canary A does not support config." .. tostring(key)) end
  local config = copy(Config.defaults)
  if override.builtInDisplayUUID ~= nil then config.builtInDisplayUUID = override.builtInDisplayUUID end
  if override.canaryInstrumentation ~= nil then config.canaryInstrumentation = override.canaryInstrumentation end
  assert(type(config.canaryInstrumentation) == "boolean", "config.canaryInstrumentation must be boolean")
  assert(config.builtInDisplayUUID == nil or (type(config.builtInDisplayUUID) == "string" and config.builtInDisplayUUID ~= ""), "config.builtInDisplayUUID must be a non-empty string")
  if override.hotkeys ~= nil then
    assert(type(override.hotkeys) == "table", "hotkeys must be a table")
    for name, binding in pairs(override.hotkeys) do assert(config.hotkeys[name] ~= nil, "10bucks Canary A does not support hotkeys." .. tostring(name)); config.hotkeys[name] = copy(binding) end
  end
  local used = {}; for name, binding in pairs(config.hotkeys) do local id = chord(name, binding); assert(not id or not used[id], "10bucks config: duplicate hotkey chord"); if id then used[id] = name end end
  return config
end
function Config.loadFile(path)
  local chunk, err = loadfile(path); if not chunk then error(err, 0) end
  local ok, config = pcall(chunk); if not ok then error(config, 0) end
  if type(config) ~= "table" then error("10bucks config: " .. path .. " must return a table", 0) end
  return config
end
return Config
