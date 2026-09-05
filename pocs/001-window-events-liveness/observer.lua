-- POC-001 disposable, read-only Hammerspoon observer.
-- Step 2B adds observation/correlation only; it never admits, removes, or acts.
local Trace = require("trace")
local Lifecycle = require("lifecycle")
local Ownership = require("ownership")
local PrivateExport = require("private_export")
local Correlation = require("correlation")

local Observer = {}
Observer.__index = Observer

local FILTER_EVENTS = {
  "windowCreated", "windowFocused", "windowDestroyed",
  "windowMinimized", "windowUnminimized",
  "windowFullscreened", "windowUnfullscreened", "windowMoved",
}
local DIRECT_APP_EVENTS = { "AXWindowCreated", "AXFocusedWindowChanged" }
local FIXTURE_BUNDLE_ID = "local.poc001.fixture"

local DIRECT_WINDOW_EVENTS = {
  "AXUIElementDestroyed", "AXWindowMiniaturized", "AXWindowDeminiaturized",
  "AXWindowMoved", "AXWindowResized",
}
local READINESS_METADATA = {
  { field = "minimized", method = "isMinimized", value_type = "boolean" },
  { field = "native_fullscreen", method = "isFullScreen", value_type = "boolean" },
  { field = "role", method = "role", value_type = "string" },
  { field = "subrole", method = "subrole", value_type = "string" },
  { field = "visibility", method = "isVisible", value_type = "boolean" },
}
local LIFECYCLE_METADATA = { READINESS_METADATA[1], READINESS_METADATA[2] }

local function monotonic_ms() return hs.timer.absoluteTime() / 1000000 end

local function protected(callable)
  local ok, value = pcall(callable)
  if ok then return true, value end
  return false, nil
end

local function safe_id(object)
  if not object or type(object.id) ~= "function" then return nil end
  local ok, value = protected(function() return object:id() end)
  return ok and value or nil
end

local function event_fact(event)
  return ({
    windowMinimized = { minimized = true },
    windowUnminimized = { minimized = false },
    windowFullscreened = { native_fullscreen = true },
    windowUnfullscreened = { native_fullscreen = false },
    AXWindowMiniaturized = { minimized = true },
    AXWindowDeminiaturized = { minimized = false },
  })[event] or {}
end

local function is_metadata_ready(metadata)
  return type(metadata.minimized) == "boolean"
    and type(metadata.native_fullscreen) == "boolean"
    and type(metadata.visibility) == "boolean"
    and type(metadata.role) == "string" and metadata.role ~= ""
    and type(metadata.subrole) == "string" and metadata.subrole ~= ""
end

function Observer.new()
  return setmetatable({ run_number = 0, running = false }, Observer)
end

function Observer:_new_run()
  self.run_number = self.run_number + 1
  self.trace = Trace.new(monotonic_ms, string.format("run-%03d", self.run_number))
  self.lifecycle, self.ownership = Lifecycle.new(), Ownership.new()
  self.app_watchers, self.window_watchers, self.window_identity_cache = {}, {}, {}
  self.window_raw_by_alias, self.ready_emitted, self.metadata_by_window = {}, {}, {}
  self.correlation = Correlation.new(function(value) return hs.hash.SHA256(value) end)
  self.destruction_candidates, self.active_target_action, self.target_binding_hotkey = {}, nil, nil
  self.space_trigger_generation, self.last_active_space, self.last_active_generation = 0, nil, nil
  self.filter, self.application_watcher, self.spaces_watcher = nil, nil, nil
  self.active_timers, self.window_effects = 0, 0
end

function Observer:_fact(fact, fields)
  fields = fields or {}; fields.fact = fact; self.trace:emit("observation_fact", fields)
end

function Observer:_app_key(application, scope)
  assert(application, "application is unavailable")
  self.trace:query("targeted_application_pid", "direct_ax.app_pid", scope or "steady")
  local ok, pid = false, nil
  if type(application.pid) == "function" then ok, pid = protected(function() return application:pid() end) end
  if not ok or pid == nil then
    self.next_anonymous_app = (self.next_anonymous_app or 0) + 1
    return "anonymous-app-" .. self.next_anonymous_app, nil
  end
  return "pid:" .. tostring(pid), pid
end

function Observer:_app_alias(application, scope)
  local key, pid = self:_app_key(application, scope)
  return key, pid, self.trace:app_alias(key)
end

function Observer:_window_alias(app_key, element, call_site, scope)
  self.trace:query("targeted_window_id", call_site, scope or "steady")
  local id = safe_id(element)
  if id == nil then self:_fact("window_identity_unavailable", { source = "direct_ax" }); return nil, nil end
  return self.trace:window_alias(app_key, tostring(id)), tostring(id)
end

function Observer:_remember_window_identity(raw_key, app, window)
  if raw_key and app and window then
    self.window_identity_cache[tostring(raw_key)] = { app = app, window = window }
    self.window_raw_by_alias[window] = tostring(raw_key)
  end
end
function Observer:_cached_window_identity(raw_key) return raw_key and self.window_identity_cache[tostring(raw_key)] or nil end
function Observer:_forget_window_identity(raw_key)
  if raw_key then
    local cached = self.window_identity_cache[tostring(raw_key)]
    if cached then self.window_raw_by_alias[cached.window] = nil end
    self.window_identity_cache[tostring(raw_key)] = nil
  end
end

local function contains(items, wanted)
  for _, item in ipairs(items or {}) do if tostring(item) == tostring(wanted) then return true end end
  return false
end

function Observer:_space_topology(event, scope)
  self.trace:targeted_check_begin("spaces_topology_snapshot", "spaces.topology_snapshot", scope, { source = "hs_spaces", raw_event = event })
  local ok, data = protected(function() return hs.spaces.data_managedDisplaySpaces() end)
  self.trace:targeted_check_end("spaces_topology_snapshot", "spaces.topology_snapshot", scope, { source = "hs_spaces", raw_event = event })
  if not ok or type(data) ~= "table" then
    self:_fact("space_topology_uncertain", { source = "hs_spaces", raw_event = event, topology_status = ok and "unavailable" or "error" })
    return nil
  end
  local types = {}
  for _, display in ipairs(data) do
    for _, space in ipairs(display.Spaces or {}) do
      local id = space.ManagedSpaceID
      if id ~= nil then types[tostring(id)] = space.type == 0 and "regular" or space.type == 4 and "fullscreen" or "unknown" end
    end
  end
  return types
end

function Observer:_emit_ready_if_complete(app, window, event)
  local lifecycle, ownership = self.lifecycle:window(window), self.ownership:window(window)
  if lifecycle and lifecycle.metadata_ready and ownership and ownership.kind == "regular" and ownership.space and not self.ready_emitted[window] then
    self.ready_emitted[window] = true
    self.trace:emit("window_ready_eligible", { source = "poc001", app = app, window = window, raw_event = event, space = ownership.space, ownership_kind = "regular", result = "non_effecting" })
  end
end

function Observer:_read_space_ownership(app, window, raw_window, event, scope, trigger, topology)
  if trigger ~= "active_space_callback_known_window_sweep" then self.space_trigger_generation = self.space_trigger_generation + 1 end
  self.trace:targeted_check_begin("spaces_window_spaces", "spaces.windowSpaces", scope, { source = "hs_spaces", app = app, window = window, raw_event = event, trigger = trigger })
  local ok, raw_spaces = protected(function() return hs.spaces.windowSpaces(tonumber(raw_window) or raw_window) end)
  self.trace:targeted_check_end("spaces_window_spaces", "spaces.windowSpaces", scope, { source = "hs_spaces", app = app, window = window, raw_event = event, trigger = trigger })
  local types = topology or self:_space_topology(event, scope)
  local memberships = {}
  if ok and type(raw_spaces) == "table" and types then
    for _, raw_space in ipairs(raw_spaces) do
      local raw_key, kind = tostring(raw_space), types[tostring(raw_space)] or "unknown"
      self.trace:targeted_check_begin("spaces_windows_for_space", "spaces.windowsForSpace", scope, { source = "hs_spaces", app = app, window = window, raw_event = event, trigger = trigger })
      local reciprocal_ok, windows = protected(function() return hs.spaces.windowsForSpace(raw_space) end)
      self.trace:targeted_check_end("spaces_windows_for_space", "spaces.windowsForSpace", scope, { source = "hs_spaces", app = app, window = window, raw_event = event, trigger = trigger })
      memberships[#memberships + 1] = { space = self.trace:space_alias(raw_key), kind = kind, reciprocal = reciprocal_ok and type(windows) == "table" and contains(windows, raw_window) or false }
    end
  end
  local outcome = self.ownership:observe(window, memberships)
  self.trace:emit("space_ownership_observed", { source = "hs_spaces", app = app, window = window, raw_event = event, trigger = trigger, space = outcome.space, ownership_kind = outcome.kind, retained_regular_space = outcome.retained_regular, retained_prior_regular = outcome.retained_regular, membership_count = outcome.membership_count, reciprocal_confirmed_count = outcome.reciprocal_confirmed_count, reason = outcome.reason, result = outcome.changed and "changed" or "duplicate" })
  if outcome.move then
    self.trace:emit("space_move_confirmed", { source = "hs_spaces", app = app, window = window, raw_event = event, trigger = trigger, from_space = outcome.move.from, to_space = outcome.move.to, result = "non_effecting" })
  elseif outcome.no_regular_move then
    self.trace:emit("no_regular_move", { source = "hs_spaces", app = app, window = window, raw_event = event, trigger = trigger, retained_prior_regular = outcome.retained_regular, reason = outcome.reason, result = "non_effecting" })
  end
  self:_emit_ready_if_complete(app, window, event)
end

function Observer:_commit_lifecycle(app, window, facts, source, event, inference)
  if not app or not window then return end
  local candidate_source = source == "window_filter" and "filter" or "direct_ax"
  local changed, record, candidate = self.lifecycle:observe_window(app, window, candidate_source, facts)
  self.trace:emit(changed and "lifecycle_fact_committed" or "lifecycle_fact_duplicate", {
    source = source, app = app, window = window, raw_event = event,
    app_hidden = record.app_hidden, candidate_source = candidate_source,
    candidate_minimized = candidate.minimized,
    candidate_native_fullscreen = candidate.native_fullscreen,
    candidate_available = candidate.available,
    result = inference or "source_fact",
  })
  local other_source = candidate_source == "filter" and "direct_ax" or "filter"
  local other = record.candidates[other_source]
  for _, condition in ipairs({ "minimized", "native_fullscreen" }) do
    if candidate[condition] ~= nil and other[condition] ~= nil and candidate[condition] ~= other[condition] then
      self:_fact("lifecycle_source_conflict", {
        source = source, app = app, window = window, raw_event = event,
        candidate_source = candidate_source, field = condition, result = "conflict",
      })
    end
  end
end

function Observer:_read_direct_metadata(app, window, element, event, scope)
  scope = scope or "steady"
  local metadata, uncertainty = {}, false
  local cached_before = self.metadata_by_window[window] or {}
  local native_fullscreen_before = cached_before.native_fullscreen
  local fields = (event == "AXWindowMoved" or event == "AXWindowResized") and LIFECYCLE_METADATA or READINESS_METADATA
  for _, spec in ipairs(fields) do
    local call_site = "direct_ax.metadata." .. spec.field
    self.trace:targeted_check_begin("targeted_window_metadata", call_site, scope, {
      source = "direct_ax_window", app = app, window = window, raw_event = event, field = spec.field,
    })
    local ok, value = false, nil
    if type(element[spec.method]) == "function" then ok, value = protected(function() return element[spec.method](element) end) end
    self.trace:targeted_check_end("targeted_window_metadata", call_site, scope, {
      source = "direct_ax_window", app = app, window = window, raw_event = event, field = spec.field,
    })
    if ok and type(value) == spec.value_type and not (spec.value_type == "string" and value == "") then
      metadata[spec.field] = value
      self.trace:emit("metadata_field_observed", { source = "direct_ax_window", app = app, window = window, raw_event = event, field = spec.field, result = "available" })
    else
      uncertainty = true
      self:_fact("metadata_uncertain", { source = "direct_ax_window", app = app, window = window, raw_event = event, field = spec.field, result = ok and "unavailable" or "method_unavailable" })
    end
  end
  local cached = cached_before
  for field, value in pairs(metadata) do cached[field] = value end
  self.metadata_by_window[window] = cached
  self:_commit_lifecycle(app, window, metadata, "direct_ax_window", event,
    (event == "AXWindowMoved" or event == "AXWindowResized") and "targeted_observed_property" or "targeted_metadata")
  if is_metadata_ready(cached) then
    local first_ready = self.lifecycle:observe_metadata_ready(app, window)
    self.trace:emit(first_ready and "metadata_ready" or "metadata_ready_duplicate", {
      source = "direct_ax_window", app = app, window = window, raw_event = event, metadata_ready = true,
      minimized = cached.minimized, native_fullscreen = cached.native_fullscreen, visibility = cached.visibility, role = cached.role, subrole = cached.subrole,
    })
    self:_emit_ready_if_complete(app, window, event)
  elseif uncertainty then
    self.trace:emit("metadata_not_ready", { source = "direct_ax_window", app = app, window = window, raw_event = event, metadata_status = "uncertain" })
  end
  return {
    native_fullscreen_before = native_fullscreen_before,
    native_fullscreen = cached.native_fullscreen,
    native_fullscreen_available = type(metadata.native_fullscreen) == "boolean",
  }
end

function Observer:_stop_window_watcher(key, reason)
  local record = self.window_watchers[key]
  if record then
    protected(function() record.watcher:stop() end)
    self:_fact("window_watcher_detached", { source = "direct_ax", app = record.app, window = record.window, watcher_kind = "window", reason = reason or "unspecified" })
  end
  self.window_watchers[key] = nil
end

function Observer:_destruction_candidate(app, window, source, event)
  if not window then return end
  local candidates = self.destruction_candidates[window] or {}
  if candidates[source] then return end
  candidates[source], self.destruction_candidates[window] = true, candidates
  local relation = "no_active_target"
  if self.active_target_action then relation = self.active_target_action.window == window and "target" or "non_target" end
  local raw_window = self.window_raw_by_alias[window]
  local correlation_alias = raw_window and self.correlation:destroy(raw_window) or nil
  self.trace:emit("destruction_candidate", { source = source, app = app, window = window, raw_event = event, target_relation = relation, correlation_alias = correlation_alias, result = "candidate_only" })
  if candidates.direct_ax and candidates.filter and not candidates.paired then
    candidates.paired = true
    self.trace:emit("destruction_paired_candidate", { source = "poc001", app = app, window = window, raw_event = event, target_relation = relation, result = "paired_candidate_only" })
  end
end

function Observer:_observe_direct_window(app_key, app_alias, element, raw_event, scope)
  local window_alias, raw_key = self:_window_alias(app_key, element, "direct_ax.window_identity", scope)
  self.trace:emit("direct_window_observed", { source = "direct_ax", app = app_alias, window = window_alias, raw_event = raw_event, result = window_alias and "identified" or "identity_unavailable" })
  self:_remember_window_identity(raw_key, app_alias, window_alias)
  if not raw_key then return end
  self:_read_direct_metadata(app_alias, window_alias, element, raw_event, scope)
  if raw_event == "bootstrap_existing_window" or raw_event == "AXWindowCreated" or raw_event == "AXFocusedWindowChanged" then
    self:_read_space_ownership(app_alias, window_alias, raw_key, raw_event, scope, raw_event == "bootstrap_existing_window" and "bootstrap" or "direct_ax_readiness")
  end
  local key = app_key .. "\0" .. raw_key
  if self.window_watchers[key] then return end
  local ok, watcher = protected(function()
    return element:newWatcher(function(_, event)
      self.trace:callback_enter("direct_ax_window", event, { app = app_alias, window = window_alias, reason = "window_watcher_callback" })
      local callback_ok = pcall(function()
        self.trace:emit("direct_window_event", { source = "direct_ax_window", app = app_alias, window = window_alias, raw_event = event })
        self:_commit_lifecycle(app_alias, window_alias, event_fact(event), "direct_ax_window", event)
        if event ~= "AXUIElementDestroyed" then
          local metadata = self:_read_direct_metadata(app_alias, window_alias, element, event, "steady")
          if event == "AXWindowMoved" then
            -- A move remains an ownership trigger regardless of lifecycle-read uncertainty.
            self:_read_space_ownership(app_alias, window_alias, raw_key, event, "steady", "direct_ax_window_move")
          elseif event == "AXWindowResized" then
            if metadata.native_fullscreen_available and metadata.native_fullscreen_before ~= metadata.native_fullscreen then
              self:_read_space_ownership(app_alias, window_alias, raw_key, event, "steady", "direct_ax_window_resize_fullscreen_changed")
            else
              -- An unavailable read is traced by metadata_uncertain.  Do not turn it
              -- into a move/liveness inference; retain prior ownership non-destructively.
              self.trace:emit("ownership_check_skipped", {
                source = "direct_ax_window", app = app_alias, window = window_alias, raw_event = event,
                reason = "resize_fullscreen_unchanged",
                fullscreen_status = metadata.native_fullscreen_available and "unchanged" or "unavailable",
                result = "non_effecting",
              })
            end
          end
        end
        if event == "AXUIElementDestroyed" then self:_destruction_candidate(app_alias, window_alias, "direct_ax", event); self:_forget_window_identity(raw_key); self:_stop_window_watcher(key, "element_destroyed") end
      end)
      if not callback_ok then self:_fact("callback_error", { source = "direct_ax_window", error_class = "runtime_error" }) end
      self.trace:callback_exit("direct_ax_window", event, { app = app_alias, window = window_alias, reason = "window_watcher_callback" })
    end)
  end)
  if not ok or not watcher then self:_fact("window_watcher_unavailable", { source = "direct_ax", app = app_alias, window = window_alias }); return end
  local started = protected(function() return watcher:start(DIRECT_WINDOW_EVENTS) end)
  if not started then
    protected(function() watcher:stop() end)
    self:_fact("window_watcher_start_failed", { source = "direct_ax", app = app_alias, window = window_alias })
    return
  end
  -- hs.uielement.watcher is userdata; keep all POC diagnostic context in this Lua record.
  self.window_watchers[key] = { watcher = watcher, app = app_alias, window = window_alias }
  self:_fact("window_watcher_attached", { source = "direct_ax", app = app_alias, window = window_alias, watcher_kind = "window", reason = "direct_window_observed" })
end

function Observer:_attach_bootstrap_windows(application, app_key, app_alias)
  self.trace:query("per_application_window_scan", "bootstrap.attach_existing_windows", "bootstrap")
  local ok, windows = false, nil
  if type(application.allWindows) == "function" then ok, windows = protected(function() return application:allWindows() end) end
  if not ok or type(windows) ~= "table" then self:_fact("bootstrap_window_scan_unavailable", { source = "bootstrap", app = app_alias }); return end
  for _, window in ipairs(windows) do self:_observe_direct_window(app_key, app_alias, window, "bootstrap_existing_window", "bootstrap") end
end

function Observer:_attach_direct_application(application, origin)
  if not application then self:_fact("application_unavailable", { source = "direct_ax", reason = origin }); return end
  local bootstrap = origin == "bootstrap"
  local app_key, pid, app_alias = self:_app_alias(application, bootstrap and "bootstrap" or "steady")
  if self.app_watchers[app_key] then if bootstrap then self:_attach_bootstrap_windows(application, app_key, app_alias) end; return end
  local ok, watcher = protected(function()
    return application:newWatcher(function(element, event)
      self.trace:callback_enter("direct_ax_application", event)
      local callback_ok = pcall(function()
        self.trace:emit("direct_application_event", { source = "direct_ax_application", app = app_alias, raw_event = event })
        self:_observe_direct_window(app_key, app_alias, element, event, "steady")
      end)
      if not callback_ok then self:_fact("callback_error", { source = "direct_ax_application", app = app_alias, error_class = "runtime_error" }) end
      self.trace:callback_exit("direct_ax_application", event)
    end)
  end)
  if not ok or not watcher then self:_fact("application_watcher_unavailable", { source = "direct_ax", app = app_alias, reason = origin })
  elseif not protected(function() return watcher:start(DIRECT_APP_EVENTS) end) then
    protected(function() watcher:stop() end)
    self:_fact("application_watcher_start_failed", { source = "direct_ax", app = app_alias, reason = origin })
  else self.app_watchers[app_key] = { watcher = watcher, pid = pid, alias = app_alias }; self:_fact("application_watcher_attached", { source = "direct_ax", app = app_alias, reason = origin, watcher_kind = "application" }) end
  if bootstrap then self:_attach_bootstrap_windows(application, app_key, app_alias) end
end

function Observer:_detach_direct_application_by_pid(pid)
  if pid == nil then return end
  local key, record = "pid:" .. tostring(pid), self.app_watchers["pid:" .. tostring(pid)]
  if record then protected(function() record.watcher:stop() end); self:_fact("application_watcher_detached", { source = "direct_ax", app = record.alias, watcher_kind = "application", reason = "application_terminated" }) end
  self.app_watchers[key] = nil
  local keys, prefix = {}, key .. "\0"
  for window_key in pairs(self.window_watchers) do if window_key:sub(1, #prefix) == prefix then keys[#keys + 1] = window_key end end
  for _, window_key in ipairs(keys) do self:_stop_window_watcher(window_key, "application_terminated") end
end

function Observer:_observe_app_hidden(app, hidden, event)
  local _, changed = self.lifecycle:observe_app_hidden(app, hidden)
  for _, change in ipairs(changed) do
    self.trace:emit("lifecycle_fact_committed", {
      source = "application_watcher", app = app, window = change.window,
      raw_event = event, app_hidden = change.record.app_hidden,
      result = "shared_app_fact",
    })
  end
  self.trace:emit(#changed == 0 and "lifecycle_fact_duplicate" or "application_lifecycle_committed", { source = "application_watcher", app = app, raw_event = event, app_hidden = hidden, count = #changed })
end

function Observer:_start_application_watcher()
  self.application_watcher = hs.application.watcher.new(function(_, event, application)
    local names = ({ [0] = "launching", "launched", "terminated", "hidden", "unhidden", "activated", "deactivated" })
    local event_name = names[event] or "unknown"
    self.trace:callback_enter("application_watcher", event_name)
    local callback_ok = pcall(function()
      local _, pid, app_alias
      if application then _, pid, app_alias = self:_app_alias(application) else app_alias = "app-unavailable"; self:_fact("application_unavailable", { source = "application_watcher", raw_event = event_name }) end
      self.trace:emit("application_event", { source = "application_watcher", app = app_alias, raw_event = event_name })
      if event == hs.application.watcher.launched then self:_attach_direct_application(application, "launch")
      elseif event == hs.application.watcher.terminated then self:_detach_direct_application_by_pid(pid); self.trace:emit("application_terminated", { source = "application_watcher", app = app_alias, raw_event = event_name })
      elseif event == hs.application.watcher.hidden then
        if app_alias ~= "app-unavailable" then self:_observe_app_hidden(app_alias, true, event_name) else self:_fact("application_lifecycle_uncertain", { source = "application_watcher", raw_event = event_name }) end
      elseif event == hs.application.watcher.unhidden then
        if app_alias ~= "app-unavailable" then self:_observe_app_hidden(app_alias, false, event_name) else self:_fact("application_lifecycle_uncertain", { source = "application_watcher", raw_event = event_name }) end
      end
    end)
    if not callback_ok then self:_fact("callback_error", { source = "application_watcher", error_class = "runtime_error" }) end
    self.trace:callback_exit("application_watcher", event_name)
  end)
  self.application_watcher:start()
  self:_fact("application_watcher_attached", { source = "application_watcher", watcher_kind = "application_lifecycle", reason = "observer_start" })
end

function Observer:_fixture_bundle_matches(application)
  if not application or type(application.bundleID) ~= "function" then return false end
  local ok, bundle_id = protected(function() return application:bundleID() end)
  return ok and bundle_id == FIXTURE_BUNDLE_ID
end

function Observer:_observe_fixture_correlation(raw_id, application, callback_window)
  if not self.correlation or self.correlation:state().armed_generation == nil then return end
  -- The exact fixture bundle merely scopes this already-delivered callback. It
  -- is not correlation evidence and is never traced or exported.
  if not self:_fixture_bundle_matches(application) then return end
  if self.correlation:state().consumed then return end
  local began = monotonic_ms()
  self.trace:query("correlation_window_element_construction", "correlation.windowElement", "steady")
  local constructed, element = protected(function() return hs.axuielement.windowElement(callback_window) end)
  self.trace:emit("correlation_window_element_constructed", { source = "window_filter", duration_ms = monotonic_ms() - began, result = constructed and element and "available" or "unavailable" })
  if not constructed or not element then
    local result = self.correlation:unresolved("window_element_unavailable")
    self.trace:emit("correlation_unresolved", { source = "window_filter", reason = result.reason, result = "unresolved" })
    return
  end
  began = monotonic_ms()
  self.trace:query("correlation_ax_identifier_read", "correlation.AXIdentifier", "steady")
  local read, raw = protected(function() return element:attributeValue("AXIdentifier") end)
  self.trace:emit("correlation_ax_identifier_read", { source = "window_filter", duration_ms = monotonic_ms() - began, result = read and "available" or "unavailable" })
  local outcome
  if not read then outcome = self.correlation:unresolved("attribute_read_error"); raw = nil
  elseif raw_id == nil then outcome = self.correlation:unresolved("window_id_unavailable")
  else outcome = self.correlation:consume(raw_id, raw) end
  raw = nil -- Do not retain a Lua reference to the raw AX identifier.
  if outcome.alias then
    self.trace:emit("correlation_observed", { source = "window_filter", correlation_alias = outcome.alias, result = "matched" })
  else
    self.trace:emit("correlation_unresolved", { source = "window_filter", reason = outcome.reason, result = "unresolved" })
  end
end

function Observer:_start_filter()
  self.filter = hs.window.filter.new(true, "poc001-window-events")
  self:_fact("filter_watcher_attached", { source = "window_filter", watcher_kind = "filter", reason = "observer_start" })
  for _, event_name in ipairs(FILTER_EVENTS) do self.filter:subscribe(event_name, function(window, _, event)
    self.trace:callback_enter("window_filter", event)
    local callback_ok = pcall(function()
      self.trace:query("targeted_window_id", "window_filter.callback_window_id", "steady")
      local raw_id = safe_id(window)
      local application_ok, application = protected(function() return window:application() end)
      local app_alias, window_alias
      if application_ok and application then local app_key; app_key, _, app_alias = self:_app_alias(application); window_alias = raw_id and self.trace:window_alias(app_key, tostring(raw_id)) or nil; self:_remember_window_identity(raw_id, app_alias, window_alias)
      else local cached = self:_cached_window_identity(raw_id); if cached then app_alias, window_alias = cached.app, cached.window else self:_fact("filter_application_unavailable", { source = "window_filter" }) end end
      if event == "windowCreated" then self:_observe_fixture_correlation(raw_id, application, window) end
      self.trace:emit("filter_window_event", { source = "window_filter", app = app_alias, window = window_alias, raw_event = event, result = window_alias and "identified" or "identity_unavailable" })
      self:_commit_lifecycle(app_alias, window_alias, event_fact(event), "window_filter", event)
      if app_alias and window_alias and raw_id and (event == "windowCreated" or event == "windowFocused" or event == "windowMoved") then
        local trigger = event == "windowMoved" and "window_filter_window_move" or "window_filter_readiness"
        self:_read_space_ownership(app_alias, window_alias, tostring(raw_id), event, "steady", trigger)
      end
      if event == "windowDestroyed" then self:_destruction_candidate(app_alias, window_alias, "filter", event); self:_forget_window_identity(raw_id) end
    end)
    if not callback_ok then self:_fact("callback_error", { source = "window_filter", error_class = "runtime_error" }) end
    self.trace:callback_exit("window_filter", event)
  end) end
end

function Observer:_start_spaces_watcher()
  local ok, watcher = protected(function()
    return hs.spaces.watcher.new(function()
      self.trace:callback_enter("spaces_watcher", "activeSpaceChanged")
      local callback_ok = pcall(function()
        self.trace:targeted_check_begin("spaces_active_space", "spaces.activeSpaceOnScreen", "steady", { source = "hs_spaces", trigger = "active_space_callback" })
        local active_ok, active = protected(function() return hs.spaces.activeSpaceOnScreen() end)
        local active_alias = active_ok and active ~= nil and self.trace:space_alias(tostring(active)) or nil
        self.trace:targeted_check_end("spaces_active_space", "spaces.activeSpaceOnScreen", "steady", { source = "hs_spaces", trigger = "active_space_callback", active_space = active_alias })
        if active_alias and self.last_active_space == active_alias and self.last_active_generation == self.space_trigger_generation then
          self.trace:emit("active_space_callback_coalesced", { source = "spaces_watcher", trigger = "active_space_callback", active_space = active_alias, active_generation = self.space_trigger_generation, result = "duplicate_active_space" })
          return
        end
        self.last_active_space, self.last_active_generation = active_alias, self.space_trigger_generation
        local before, after = self.trace:status().query_counters.steady, nil
        local count_before = 0; for _, count in pairs(before) do count_before = count_before + count end
        local topology = self:_space_topology("activeSpaceChanged", "steady")
        local known = {}
        for window, raw in pairs(self.window_raw_by_alias) do
          local cached = self:_cached_window_identity(raw)
          if cached then known[#known + 1] = { app = cached.app, window = window, raw = raw } end
        end
        table.sort(known, function(a, b) return a.window < b.window end)
        self.trace:emit("active_space_known_window_sweep_begin", { source = "spaces_watcher", trigger = "active_space_callback", sweep_scope = "known_windows_only", query_count = 0, count = #known, active_space = active_alias, active_generation = self.space_trigger_generation })
        for _, known_window in ipairs(known) do self:_read_space_ownership(known_window.app, known_window.window, known_window.raw, "activeSpaceChanged", "steady", "active_space_callback_known_window_sweep", topology) end
        after = self.trace:status().query_counters.steady
        local count_after = 0; for _, count in pairs(after) do count_after = count_after + count end
        self.trace:emit("active_space_known_window_sweep_end", { source = "spaces_watcher", trigger = "active_space_callback", sweep_scope = "known_windows_only", query_count = count_after - count_before, count = #known, active_space = active_alias, active_generation = self.space_trigger_generation, result = "callback_complete_no_timer" })
      end)
      if not callback_ok then self:_fact("callback_error", { source = "spaces_watcher", error_class = "runtime_error" }) end
      self.trace:callback_exit("spaces_watcher", "activeSpaceChanged")
    end)
  end)
  if not ok or not watcher then self:_fact("spaces_watcher_unavailable", { source = "hs_spaces" }); return end
  if not protected(function() return watcher:start() end) then
    protected(function() watcher:stop() end)
    self:_fact("spaces_watcher_start_failed", { source = "hs_spaces" })
    return
  end
  self.spaces_watcher = watcher
  self:_fact("spaces_watcher_attached", { source = "hs_spaces", watcher_kind = "spaces", reason = "observer_start" })
end

function Observer:_bootstrap_existing_apps()
  self.trace:query("all_application_scan", "bootstrap.attach_existing_apps", "bootstrap")
  local ok, applications = protected(function() return hs.application.runningApplications() end)
  if not ok or type(applications) ~= "table" then self:_fact("bootstrap_application_scan_unavailable", { source = "bootstrap" }); return end
  for _, application in ipairs(applications) do self:_attach_direct_application(application, "bootstrap") end
end

function Observer:start()
  if self.running then return false, "already_running" end
  -- Defensive transactional cleanup if an earlier failed/abandoned setup left
  -- this POC-only adapter handle behind.
  self:_delete_target_binding_hotkey("startup_reset")
  self:_new_run(); self.running = true; self.trace:lifecycle("start"); self.trace:mark("run_start", { source = "poc001" })
  local ok, startup_error = pcall(function()
    for _, source in ipairs({ "window_filter", "application_watcher", "direct_ax" }) do self.trace:mark("candidate_sources", { source = source }) end
    self.trace:mark("framework_evidence", { source = "window_filter", framework_evidence = "source_inspection_unknown" }); self.trace:mark("framework_evidence", { source = "direct_ax", framework_evidence = "source_inspection_global_cleanup_watcher" })
    self:_start_application_watcher(); self:_bootstrap_existing_apps(); self:_start_filter(); self:_start_spaces_watcher()
  end)
  if not ok then
    self:_fact("observer_start_failed", { source = "poc001", reason = "startup_error", error_class = "startup_error" })
    self:stop()
    return false, "startup_failed: " .. tostring(startup_error)
  end
  return true, self.trace:status().run_id
end

function Observer:_delete_target_binding_hotkey(reason)
  local hotkey = self.target_binding_hotkey
  self.target_binding_hotkey = nil
  if hotkey then
    protected(function() hotkey:delete() end)
    if self.trace then self:_fact("target_binding_hotkey_deleted", { source = "operator", reason = reason }) end
  end
end

function Observer:arm_fixture_correlation(generation)
  assert(self.trace, "start the POC before arming correlation")
  if not self.running then return false, "not_running" end
  local armed, reason = self.correlation:arm(generation)
  if armed then self.trace:emit("correlation_armed", { source = "operator", result = "armed" }) end
  return armed, reason
end

function Observer:stop()
  if not self.running then return false, "already_stopped" end
  self:_delete_target_binding_hotkey("observer_stop")
  if self.filter then protected(function() self.filter:unsubscribeAll() end); protected(function() self.filter:delete() end); self:_fact("filter_watcher_detached", { source = "window_filter", watcher_kind = "filter", reason = "observer_stop" }) end
  if self.application_watcher then protected(function() self.application_watcher:stop() end); self:_fact("application_watcher_detached", { source = "application_watcher", watcher_kind = "application_lifecycle", reason = "observer_stop" }) end
  if self.spaces_watcher then protected(function() self.spaces_watcher:stop() end); self:_fact("spaces_watcher_detached", { source = "hs_spaces", watcher_kind = "spaces", reason = "observer_stop" }) end
  local window_keys, app_keys = {}, {}; for key in pairs(self.window_watchers) do window_keys[#window_keys + 1] = key end; for key in pairs(self.app_watchers) do app_keys[#app_keys + 1] = key end
  for _, key in ipairs(window_keys) do self:_stop_window_watcher(key, "observer_stop") end
  for _, key in ipairs(app_keys) do local record = self.app_watchers[key]; if record then protected(function() record.watcher:stop() end); self:_fact("application_watcher_detached", { source = "direct_ax", app = record.alias, watcher_kind = "application", reason = "observer_stop" }) end; self.app_watchers[key] = nil end
  self.correlation:clear()
  self.filter, self.application_watcher, self.spaces_watcher, self.running = nil, nil, nil, false; self.trace:lifecycle("stop"); self.trace:mark("cleanup_complete", { source = "poc001", count = 0 }); return true
end

-- Read-only operator boundary for a manual action. It queries focus exactly once,
-- resolves only an already-known identity, and never probes, admits, or effects.
function Observer:begin_target_action(sample_id, action)
  assert(self.trace, "start the POC before marking")
  self.trace:set_sample(sample_id)
  self.trace:query("targeted_focused_window", "operator.begin_target_action.focused_window", "steady", { source = "operator" })
  local ok, focused = protected(function() return hs.window.focusedWindow() end)
  local raw = ok and safe_id(focused) or nil
  local cached = self:_cached_window_identity(raw)
  local ownership = cached and self.ownership:window(cached.window) or nil
  local regular = ownership and (ownership.confirmed_regular or (ownership.kind == "regular" and ownership.space)) or nil
  if not cached or not regular then
    self.trace:emit("action_target_binding_rejected", { source = "operator", action = action, action_target_status = "uncertain", reason = not cached and "target_missing" or "ownership_uncertain", result = "aborted" })
    return false, "target_uncertain"
  end
  self.active_target_action = { app = cached.app, window = cached.window, space = regular, action = action }
  self.trace:mark("action_begin", { source = "operator", action = action, app = cached.app, window = cached.window, space = regular, expected_source = regular, retained_prior_regular = regular, action_target_status = "bound" })
  return true
end

-- POC-only one-shot binding avoids an orchestrator console/hs focus change
-- selecting the session window instead of the human-selected target. Local
-- Hammerspoon 1.1.1 source verifies new(...):enable() and hotkey:delete().
function Observer:arm_target_action(sample_id, action)
  assert(self.trace, "start the POC before arming")
  if not self.running then return false, "not_running" end
  if self.target_binding_hotkey then
    self.trace:emit("action_target_binding_rejected", { source = "operator", action = action, action_target_status = "armed", reason = "already_armed", result = "aborted" })
    return false, "already_armed"
  end
  if self.active_target_action then
    self.trace:emit("action_target_binding_rejected", { source = "operator", action = action, action_target_status = "active", reason = "prior_action_active", result = "aborted" })
    return false, "prior_action_active"
  end

  self.trace:set_sample(sample_id)
  local hotkey
  local callback = function()
    -- Delete and clear the adapter handle before reading focus or recording it.
    self:_delete_target_binding_hotkey("one_shot_fired")
    local bound, reason = self:begin_target_action(sample_id, action)
    self.trace:emit("action_target_binding_hotkey_result", {
      source = "operator", action = action,
      action_target_status = bound and "bound" or "rejected",
      reason = bound and "bound" or reason,
      result = bound and "success" or "aborted",
    })
  end
  local created, created_hotkey = protected(function()
    return hs.hotkey.new({ "ctrl", "alt", "cmd" }, "b", callback)
  end)
  if not created or not created_hotkey then
    self.trace:emit("action_target_binding_rejected", { source = "operator", action = action, action_target_status = "unarmed", reason = "hotkey_create_failed", result = "aborted" })
    return false, "hotkey_create_failed"
  end
  hotkey = created_hotkey
  self.target_binding_hotkey = hotkey
  local enabled, enabled_hotkey = protected(function() return hotkey:enable() end)
  if not enabled or not enabled_hotkey then
    self:_delete_target_binding_hotkey("hotkey_enable_failed")
    self.trace:emit("action_target_binding_rejected", { source = "operator", action = action, action_target_status = "unarmed", reason = "hotkey_enable_failed", result = "aborted" })
    return false, "hotkey_enable_failed"
  end
  self.trace:emit("action_target_binding_armed", { source = "operator", action = action, action_target_status = "armed", result = "armed" })
  return true
end

function Observer:mark(sample_id, marker, action)
  assert(self.trace, "start the POC before marking")
  self.trace:set_sample(sample_id)
  local sequence = self.trace:mark(marker, { source = "operator", action = action })
  if marker == "manual_visual_complete" or marker == "native_action_completed" or marker == "sample_aborted" then self.active_target_action = nil end
  return sequence
end
function Observer:status()
  if not self.trace then return { lifecycle = "not_started", target_binding_armed = false } end
  local status = self.trace:status(); status.active_timers, status.window_effects, status.direct_application_watchers, status.direct_window_watchers, status.spaces_watcher_active, status.target_binding_armed = self.active_timers, self.window_effects, 0, 0, self.spaces_watcher ~= nil, self.target_binding_hotkey ~= nil
  for _ in pairs(self.app_watchers) do status.direct_application_watchers = status.direct_application_watchers + 1 end; for _ in pairs(self.window_watchers) do status.direct_window_watchers = status.direct_window_watchers + 1 end
  return status
end
function Observer:export(path)
  assert(self.trace, "start the POC before exporting")
  assert(not self.running and self.trace:status().lifecycle == "stopped", "stop the POC before exporting")
  return PrivateExport.write(path, Trace.encode_json(self.trace:export_table()), self.export_ops)
end
return Observer.new()
