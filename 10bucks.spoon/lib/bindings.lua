local Bindings = {}

local actions = {
  toggleLayout = function(engine) return engine:toggleLayout() end,
  focusPreviousColumn = function(engine) return engine:focusColumn() end,
  focusPreviousWindow = function(engine) return engine:focusPreviousWindow() end,
  focusNextColumn = function(engine) return engine:focusColumn() end,
  focusNextInStack = function(engine) return engine:focusStack(1) end,
  focusPreviousInStack = function(engine) return engine:focusStack(-1) end,
  swapColumns = function(engine) return engine:swapColumns() end,
  moveDividerLeft = function(engine) return engine:moveDivider(-1) end,
  moveDividerRight = function(engine) return engine:moveDivider(1) end,
  resetDivider = function(engine) return engine:resetDivider() end,
  moveFocusedToOtherColumn = function(engine) return engine:moveFocusedToOtherColumn() end,
  focusPreviousWorkspace = function(engine) return engine:focusPreviouslyFocusedWorkspace() end,
  focusNextWorkspace = function(engine) return engine:focusWorkspace(1) end,
  chooseWorkspace = function(engine, hs) return engine:chooseWorkspace(hs) end,
  chooseWindow = function(engine, hs) return engine:chooseWindow(hs) end,
  newWorkspace = function(engine) return engine:newWorkspace() end,
  deleteWorkspace = function(engine) return engine:deleteWorkspace() end,
  reflow = function(engine) return engine:recover() end,
  toggleManaged = function(engine) return engine:toggleManaged() end,
}

local modifierRanks = {
  cmd = 1,
  alt = 2,
  ctrl = 3,
  shift = 4,
  fn = 5,
}

local function exactArraySize(value)
  if type(value) ~= "table" then return nil end
  local count, maximum = 0, 0
  for key in pairs(value) do
    if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then return nil end
    count = count + 1
    if key > maximum then maximum = key end
  end
  if count ~= maximum then return nil end
  return count
end

local function configError(name, message)
  error("10bucks config: hotkeys." .. tostring(name) .. " " .. message, 0)
end

local function chordIdentity(modifiers, modifierCount, key)
  local ordered = {}
  for index = 1, modifierCount do ordered[index] = modifiers[index] end
  table.sort(ordered, function(left, right) return modifierRanks[left] < modifierRanks[right] end)

  local parts = { tostring(modifierCount) }
  for _, modifier in ipairs(ordered) do
    table.insert(parts, #modifier .. ":" .. modifier)
  end
  table.insert(parts, #key .. ":" .. key)
  return table.concat(parts, "|")
end

local function validateBinding(name, binding)
  if binding == false then return nil end

  if exactArraySize(binding) ~= 2 then
    configError(name, "must be false or { modifiers, key }")
  end

  local modifiers, key = binding[1], binding[2]
  local modifierCount = exactArraySize(modifiers)
  if not modifierCount then configError(name, "modifiers must be a list") end

  local seen = {}
  for index = 1, modifierCount do
    local modifier = modifiers[index]
    if type(modifier) ~= "string" then
      configError(name, "modifier must be a string")
    end
    if not modifierRanks[modifier] then
      configError(name, "unsupported modifier: " .. modifier)
    end
    if seen[modifier] then
      configError(name, "duplicate modifier: " .. modifier)
    end
    seen[modifier] = true
  end

  if type(key) ~= "string" then configError(name, "key must be a string") end
  return chordIdentity(modifiers, modifierCount, key)
end

local function actionNames(hotkeys)
  local names = {}
  for name in pairs(hotkeys) do table.insert(names, name) end
  table.sort(names, function(left, right) return tostring(left) < tostring(right) end)
  return names
end

function Bindings.bind(hs, engine, hotkeys)
  local names = actionNames(hotkeys)
  local seenChords = {}
  for _, name in ipairs(names) do
    if not actions[name] then error("Unknown 10bucks action: " .. tostring(name)) end
    local identity = validateBinding(name, hotkeys[name])
    if identity then
      local previous = seenChords[identity]
      if previous then
        error("10bucks config: duplicate hotkey chord assigned to hotkeys."
          .. previous .. " and hotkeys." .. name, 0)
      end
      seenChords[identity] = name
    end
  end

  local bindings = {}
  for _, name in ipairs(names) do
    local binding = hotkeys[name]
    if binding ~= false then
      local action = actions[name]
      local modifiers, key = binding[1], binding[2]
      table.insert(bindings, hs.hotkey.bind(modifiers, key, function() action(engine, hs) end))
    end
  end
  return bindings
end

function Bindings.delete(bindings)
  for _, binding in ipairs(bindings or {}) do binding:delete() end
end

return Bindings
