local Config = {}

Config.defaults = {
  animationDuration = 0,
  initialLayout = "stack",
  initialColumnRatio = 0.5,
  outerGap = 8,
  topGap = 8,
  columnGap = 8,
  minimumColumnRatio = 0.2,
  maximumColumnRatio = 0.8,
  resizeStep = 0.05,
  statusDuration = 1.2,
  bar = {
    enabled = true,
    showWorkspaces = true,
    height = 32,
    topPadding = 4,
    -- Preserve a compact gap for macOS's top-right privacy/status indicators.
    rightInset = 24,
    refreshInterval = 0.15,
    menuBarHideDelay = 0.20,
    menuBarFadeDuration = 0.10,
    backgroundColor = { red = 0.08, green = 0.09, blue = 0.12, alpha = 0.45 },
    textColor = { red = 0.9, green = 0.92, blue = 0.96, alpha = 1 },
    font = "Menlo",
    textSize = 13,
  },
  excludedBundleIDs = { "org.hammerspoon.Hammerspoon", "com.apple.SecurityAgent" },
  -- Lua patterns matched against the complete Accessibility window title.
  excludedWindowTitles = {},
  -- Optional final eligibility check: return false to leave an otherwise
  -- standard window unmanaged.
  windowFilter = nil,
  hotkeys = {
    toggleLayout = { { "cmd", "alt", "ctrl", "shift" }, "space" },
    focusPreviousColumn = { { "cmd", "alt", "ctrl", "shift" }, "h" },
    focusPreviousWindow = { { "cmd", "alt", "ctrl", "shift" }, ";" },
    focusNextInStack = { { "cmd", "alt", "ctrl", "shift" }, "j" },
    focusPreviousInStack = { { "cmd", "alt", "ctrl", "shift" }, "k" },
    focusNextColumn = { { "cmd", "alt", "ctrl", "shift" }, "l" },
    moveDividerLeft = { { "cmd", "alt", "ctrl", "shift" }, "[" },
    moveDividerRight = { { "cmd", "alt", "ctrl", "shift" }, "]" },
    resetDivider = { { "cmd", "alt", "ctrl", "shift" }, "0" },
    swapColumns = { { "cmd", "alt", "ctrl", "shift" }, "g" },
    moveFocusedToOtherColumn = { { "cmd", "alt", "ctrl", "shift" }, "o" },
    focusPreviousWorkspace = { { "cmd", "alt", "ctrl", "shift" }, "p" },
    focusNextWorkspace = { { "cmd", "alt", "ctrl", "shift" }, "n" },
    chooseWorkspace = { { "cmd", "alt", "ctrl", "shift" }, "u" },
    chooseWindow = { { "cmd", "alt", "ctrl", "shift" }, "w" },
    deleteWorkspace = { { "cmd", "alt", "ctrl", "shift" }, "delete" },
    reflow = { { "cmd", "alt", "ctrl", "shift" }, "r" },
  },
}

local function copy(value)
  if type(value) ~= "table" then return value end
  local result = {}
  for key, child in pairs(value) do result[key] = copy(child) end
  return result
end

local function isArray(value)
  if type(value) ~= "table" then return false end
  local count = 0
  for key in pairs(value) do
    if type(key) ~= "number" then return false end
    count = count + 1
  end
  return count == #value
end

local function mergeMap(base, override)
  local result = copy(base)
  for key, value in pairs(override or {}) do
    if type(value) == "table" and type(result[key]) == "table" then
      result[key] = mergeMap(result[key], value)
    else
      result[key] = copy(value)
    end
  end
  return result
end

local function mergeHotkeys(override)
  local result = copy(Config.defaults.hotkeys)
  for key, binding in pairs(override or {}) do
    -- Chord arrays are replacements, not index-wise merges.
    result[key] = copy(binding)
  end
  return result
end

local function merge(override)
  local result = copy(Config.defaults)
  for key, value in pairs(override or {}) do
    if key == "bar" and type(value) == "table" then
      result.bar = mergeMap(result.bar, value)
    elseif key == "hotkeys" and type(value) == "table" then
      result.hotkeys = mergeHotkeys(value)
    else
      -- Lists (bundle IDs and window titles) are intentional replacements.
      result[key] = copy(value)
    end
  end
  return result
end

local function validateStringArray(values, name)
  assert(isArray(values), name .. " must be a list of strings")
  for _, value in ipairs(values) do
    assert(type(value) == "string", name .. " must be a list of strings")
  end
end

function Config.loadFile(path)
  local chunk, loadError = loadfile(path)
  if not chunk then error(loadError, 0) end

  local ok, config = pcall(chunk)
  if not ok then error(config, 0) end
  if type(config) ~= "table" then
    error("10bucks config: " .. path .. " must return a table", 0)
  end
  return config
end

function Config.build(override)
  local config = merge(override)
  assert(config.initialLayout == "stack" or config.initialLayout == "columns",
    "initialLayout must be 'stack' or 'columns'")
  assert(config.minimumColumnRatio > 0 and config.minimumColumnRatio < 0.5,
    "minimumColumnRatio must be between 0 and 0.5")
  assert(config.maximumColumnRatio > 0.5 and config.maximumColumnRatio < 1,
    "maximumColumnRatio must be between 0.5 and 1")
  assert(config.initialColumnRatio >= config.minimumColumnRatio
    and config.initialColumnRatio <= config.maximumColumnRatio,
    "initialColumnRatio must be within the minimum and maximum column ratios")
  assert(config.resizeStep > 0, "resizeStep must be positive")
  assert(config.outerGap >= 0, "outerGap must not be negative")
  assert(config.topGap >= 0, "topGap must not be negative")
  assert(config.columnGap >= 0, "columnGap must not be negative")
  validateStringArray(config.excludedBundleIDs, "excludedBundleIDs")
  validateStringArray(config.excludedWindowTitles, "excludedWindowTitles")
  for _, pattern in ipairs(config.excludedWindowTitles) do
    assert(pcall(string.match, "", pattern), "excludedWindowTitles contains an invalid Lua pattern: " .. pattern)
  end
  assert(config.windowFilter == nil or type(config.windowFilter) == "function",
    "windowFilter must be a function or nil")
  assert(type(config.bar.enabled) == "boolean", "bar.enabled must be a boolean")
  assert(type(config.bar.showWorkspaces) == "boolean", "bar.showWorkspaces must be a boolean")
  assert(config.bar.height > 0, "bar.height must be positive")
  assert(config.bar.topPadding >= 0 and config.bar.topPadding < config.bar.height,
    "bar.topPadding must be within the bar height")
  assert(config.bar.rightInset >= 0, "bar.rightInset must not be negative")
  assert(config.bar.refreshInterval > 0, "bar.refreshInterval must be positive")
  assert(config.bar.menuBarHideDelay >= 0, "bar.menuBarHideDelay must not be negative")
  assert(config.bar.menuBarFadeDuration >= 0, "bar.menuBarFadeDuration must not be negative")
  assert(config.bar.menuBarFadeDuration <= config.bar.menuBarHideDelay,
    "bar.menuBarFadeDuration must not exceed bar.menuBarHideDelay")
  assert(config.bar.textSize > 0, "bar.textSize must be positive")
  return config
end

return Config
