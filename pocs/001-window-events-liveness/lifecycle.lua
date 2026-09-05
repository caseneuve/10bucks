-- POC-001 pure lifecycle correlation. It has no Hammerspoon dependency and
-- never decides liveness, removal, or admission.
local Lifecycle = {}
Lifecycle.__index = Lifecycle

local SOURCES = { filter = true, direct_ax = true }
local CONDITIONS = { "minimized", "native_fullscreen" }

local function availability(candidate, app_hidden)
  if app_hidden == true or candidate.minimized == true or candidate.native_fullscreen == true then return false end
  if app_hidden == false and candidate.minimized == false and candidate.native_fullscreen == false then return true end
  return nil
end

local function new_record(app, app_hidden)
  return {
    app = app,
    app_hidden = app_hidden,
    candidates = {
      filter = { minimized = nil, native_fullscreen = nil, available = nil },
      direct_ax = { minimized = nil, native_fullscreen = nil, available = nil },
    },
  }
end

function Lifecycle.new()
  return setmetatable({ windows = {}, apps = {} }, Lifecycle)
end

function Lifecycle:observe_window(app, window, source, facts)
  assert(type(app) == "string" and app:match("^app%-%d+$"), "app must be a redacted alias")
  assert(type(window) == "string" and window:match("^win%-%d+$"), "window must be a redacted alias")
  assert(SOURCES[source], "source must be a candidate source")
  local record = self.windows[window]
  local changed = record == nil
  if not record then
    record = new_record(app, self.apps[app])
    self.windows[window] = record
  end
  assert(record.app == app, "a window alias cannot change applications within one run")

  local candidate = record.candidates[source]
  for _, condition in ipairs(CONDITIONS) do
    if facts[condition] ~= nil and candidate[condition] ~= facts[condition] then
      candidate[condition], changed = facts[condition], true
    end
  end
  local was_available = candidate.available
  candidate.available = availability(candidate, record.app_hidden)
  if was_available ~= candidate.available then changed = true end
  return changed, record, candidate
end

function Lifecycle:observe_app_hidden(app, hidden)
  assert(type(app) == "string" and app:match("^app%-%d+$"), "app must be a redacted alias")
  assert(type(hidden) == "boolean", "hidden must be boolean")
  local app_changed = self.apps[app] ~= hidden
  self.apps[app] = hidden
  local changed = {}
  for alias, record in pairs(self.windows) do
    if record.app == app then
      local prior = record.app_hidden
      record.app_hidden = hidden
      for _, candidate in pairs(record.candidates) do
        candidate.available = availability(candidate, hidden)
      end
      if prior ~= hidden then changed[#changed + 1] = { window = alias, record = record } end
    end
  end
  table.sort(changed, function(left, right) return left.window < right.window end)
  return app_changed, changed
end

function Lifecycle:window(window)
  local record = self.windows[window]
  if not record then return nil end
  local function copy(candidate)
    return {
      minimized = candidate.minimized,
      native_fullscreen = candidate.native_fullscreen,
      available = candidate.available,
    }
  end
  return {
    app = record.app,
    app_hidden = record.app_hidden,
    candidates = { filter = copy(record.candidates.filter), direct_ax = copy(record.candidates.direct_ax) },
  }
end

return Lifecycle
