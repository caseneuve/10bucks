-- POC-001 disposable, read-only Hammerspoon observer.
-- Step 2B adds observation/correlation only; it never admits, removes, or acts.
local Trace = require("trace")
local Lifecycle = require("lifecycle")
local Ownership = require("ownership")

local Observer = {}
Observer.__index = Observer

local FILTER_EVENTS = {
  "windowCreated", "windowFocused", "windowDestroyed",
  "windowMinimized", "windowUnminimized",
  "windowFullscreened", "windowUnfullscreened", "windowMoved",
}
local DIRECT_APP_EVENTS = { "AXWindowCreated", "AXFocusedWindowChanged" }
local DIRECT_WINDOW_EVENTS = {
  "AXUIElementDestroyed", "AXWindowMiniaturized", "AXWindowDeminiaturized",
  "AXWindowMoved", "AXWindowResized",
}
local AX_METADATA = {
  { field = "minimized", attribute = "AXMinimized" },
  { field = "native_fullscreen", attribute = "AXFullScreen" },
  { field = "role", attribute = "AXRole" },
  { field = "subrole", attribute = "AXSubrole" },
  { field = "visibility", attribute = "AXVisible" },
}

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
  self.window_raw_by_alias, self.ready_emitted = {}, {}
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

function Observer:_read_space_ownership(app, window, raw_window, event, scope, trigger)
  self.trace:targeted_check_begin("spaces_window_spaces", "spaces.windowSpaces", scope, { source = "hs_spaces", app = app, window = window, raw_event = event, trigger = trigger })
  local ok, raw_spaces = protected(function() return hs.spaces.windowSpaces(tonumber(raw_window) or raw_window) end)
  self.trace:targeted_check_end("spaces_window_spaces", "spaces.windowSpaces", scope, { source = "hs_spaces", app = app, window = window, raw_event = event, trigger = trigger })
  local types = self:_space_topology(event, scope)
  local memberships = {}
  if ok and type(raw_spaces) == "table" and types then
    for _, raw_space in ipairs(raw_spaces) do
      local raw_key, kind = tostring(raw_space), types[tostring(raw_space)] or "unknown"
      self.trace:targeted_check_begin("spaces_windows_for_space", "spaces.windowsForSpace", scope, { source = "hs_spaces", app = app, window = window, raw_event = event, trigger = trigger })
      local reciprocal_ok, windows = protected(function() return hs.spaces.windowsForSpace(raw_space) end)
      self.trace:targeted_check_end("spaces_windows_for_space", "spaces.windowsForSpace", scope, { source = "hs_spaces", app = app, window = window, raw_event = event, trigger = trigger })
      memberships[#memberships + 1] = { space = self.trace:space_alias(raw_key), kind = reciprocal_ok and type(windows) == "table" and contains(windows, raw_window) and kind or "unknown" }
    end
  else
    memberships[1] = { space = self.trace:space_alias("unknown-space-" .. window), kind = "unknown" }
  end
  local outcome = self.ownership:observe(window, memberships)
  self.trace:emit("space_ownership_observed", { source = "hs_spaces", app = app, window = window, raw_event = event, trigger = trigger, space = outcome.space, ownership_kind = outcome.kind, retained_regular_space = outcome.retained_regular, result = outcome.changed and "changed" or "duplicate" })
  if outcome.move then
    self.trace:emit("space_move_confirmed", { source = "hs_spaces", app = app, window = window, raw_event = event, trigger = trigger, from_space = outcome.move.from, to_space = outcome.move.to, result = "non_effecting" })
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
  for _, spec in ipairs(AX_METADATA) do
    local call_site = "direct_ax.metadata." .. spec.field
    self.trace:targeted_check_begin("targeted_window_metadata", call_site, scope, {
      source = "direct_ax_window", app = app, window = window, raw_event = event, field = spec.field,
    })
    local ok, value = false, nil
    if type(element.attributeValue) == "function" then ok, value = protected(function() return element:attributeValue(spec.attribute) end) end
    self.trace:targeted_check_end("targeted_window_metadata", call_site, scope, {
      source = "direct_ax_window", app = app, window = window, raw_event = event, field = spec.field,
    })
    if ok and ((spec.field == "role" or spec.field == "subrole") and type(value) == "string" or type(value) == "boolean") then
      metadata[spec.field] = value
      self.trace:emit("metadata_field_observed", {
        source = "direct_ax_window", app = app, window = window, raw_event = event,
        field = spec.field, result = "available",
      })
    else
      uncertainty = true
      self:_fact("metadata_uncertain", {
        source = "direct_ax_window", app = app, window = window, raw_event = event,
        field = spec.field, result = ok and "unavailable" or "error",
      })
    end
  end
  self:_commit_lifecycle(app, window, metadata, "direct_ax_window", event,
    (event == "AXWindowMoved" or event == "AXWindowResized") and "targeted_observed_property" or "targeted_metadata")
  if is_metadata_ready(metadata) then
    local first_ready = self.lifecycle:observe_metadata_ready(app, window)
    self.trace:emit(first_ready and "metadata_ready" or "metadata_ready_duplicate", {
      source = "direct_ax_window", app = app, window = window, raw_event = event,
      metadata_ready = true, minimized = metadata.minimized,
      native_fullscreen = metadata.native_fullscreen, visibility = metadata.visibility,
      role = metadata.role, subrole = metadata.subrole,
    })
    self:_emit_ready_if_complete(app, window, event)
  elseif uncertainty then
    self.trace:emit("metadata_not_ready", { source = "direct_ax_window", app = app, window = window, raw_event = event, metadata_status = "uncertain" })
  end
end

function Observer:_stop_window_watcher(key)
  local watcher = self.window_watchers[key]
  if watcher then protected(function() watcher:stop() end) end
  self.window_watchers[key] = nil
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
      self.trace:callback_enter("direct_ax_window", event)
      local callback_ok = pcall(function()
        self.trace:emit("direct_window_event", { source = "direct_ax_window", app = app_alias, window = window_alias, raw_event = event })
        self:_commit_lifecycle(app_alias, window_alias, event_fact(event), "direct_ax_window", event)
        if event ~= "AXUIElementDestroyed" then
          self:_read_direct_metadata(app_alias, window_alias, element, event, "steady")
          if event == "AXWindowMoved" or event == "AXWindowResized" then self:_read_space_ownership(app_alias, window_alias, raw_key, event, "steady", "direct_ax_window_move") end
        end
        if event == "AXUIElementDestroyed" then self:_forget_window_identity(raw_key); self:_stop_window_watcher(key) end
      end)
      if not callback_ok then self:_fact("callback_error", { source = "direct_ax_window", error_class = "runtime_error" }) end
      self.trace:callback_exit("direct_ax_window", event)
    end)
  end)
  if not ok or not watcher then self:_fact("window_watcher_unavailable", { source = "direct_ax", app = app_alias, window = window_alias }); return end
  local started = protected(function() return watcher:start(DIRECT_WINDOW_EVENTS) end)
  if not started then self:_fact("window_watcher_start_failed", { source = "direct_ax", app = app_alias, window = window_alias }); return end
  self.window_watchers[key] = watcher
  self:_fact("window_watcher_attached", { source = "direct_ax", app = app_alias, window = window_alias, watcher_kind = "window" })
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
  elseif not protected(function() return watcher:start(DIRECT_APP_EVENTS) end) then self:_fact("application_watcher_start_failed", { source = "direct_ax", app = app_alias, reason = origin })
  else self.app_watchers[app_key] = { watcher = watcher, pid = pid, alias = app_alias }; self:_fact("application_watcher_attached", { source = "direct_ax", app = app_alias, reason = origin, watcher_kind = "application" }) end
  if bootstrap then self:_attach_bootstrap_windows(application, app_key, app_alias) end
end

function Observer:_detach_direct_application_by_pid(pid)
  if pid == nil then return end
  local key, record = "pid:" .. tostring(pid), self.app_watchers["pid:" .. tostring(pid)]
  if record then protected(function() record.watcher:stop() end) end
  self.app_watchers[key] = nil
  local keys, prefix = {}, key .. "\0"
  for window_key in pairs(self.window_watchers) do if window_key:sub(1, #prefix) == prefix then keys[#keys + 1] = window_key end end
  for _, window_key in ipairs(keys) do self:_stop_window_watcher(window_key) end
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
end

function Observer:_start_filter()
  self.filter = hs.window.filter.new(true, "poc001-window-events")
  for _, event_name in ipairs(FILTER_EVENTS) do self.filter:subscribe(event_name, function(window, _, event)
    self.trace:callback_enter("window_filter", event)
    local callback_ok = pcall(function()
      self.trace:query("targeted_window_id", "window_filter.callback_window_id", "steady")
      local raw_id = safe_id(window)
      local application_ok, application = protected(function() return window:application() end)
      local app_alias, window_alias
      if application_ok and application then local app_key; app_key, _, app_alias = self:_app_alias(application); window_alias = raw_id and self.trace:window_alias(app_key, tostring(raw_id)) or nil; self:_remember_window_identity(raw_id, app_alias, window_alias)
      else local cached = self:_cached_window_identity(raw_id); if cached then app_alias, window_alias = cached.app, cached.window else self:_fact("filter_application_unavailable", { source = "window_filter" }) end end
      self.trace:emit("filter_window_event", { source = "window_filter", app = app_alias, window = window_alias, raw_event = event, result = window_alias and "identified" or "identity_unavailable" })
      self:_commit_lifecycle(app_alias, window_alias, event_fact(event), "window_filter", event)
      if app_alias and window_alias and raw_id and (event == "windowCreated" or event == "windowFocused" or event == "windowMoved") then
        local trigger = event == "windowMoved" and "window_filter_window_move" or "window_filter_readiness"
        self:_read_space_ownership(app_alias, window_alias, tostring(raw_id), event, "steady", trigger)
      end
      if event == "windowDestroyed" then self:_forget_window_identity(raw_id) end
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
        self.trace:targeted_check_end("spaces_active_space", "spaces.activeSpaceOnScreen", "steady", { source = "hs_spaces", trigger = "active_space_callback", active_space = active_ok and self.trace:space_alias(tostring(active)) or nil })
        local known = {}
        for window, raw in pairs(self.window_raw_by_alias) do
          local cached = self:_cached_window_identity(raw)
          if cached then known[#known + 1] = { app = cached.app, window = window, raw = raw } end
        end
        table.sort(known, function(a, b) return a.window < b.window end)
        local before, after = self.trace:status().query_counters.steady, nil
        local count_before = 0; for _, count in pairs(before) do count_before = count_before + count end
        self.trace:emit("active_space_known_window_sweep_begin", { source = "spaces_watcher", trigger = "active_space_callback", sweep_scope = "known_windows_only", query_count = 0, count = #known })
        for _, known_window in ipairs(known) do self:_read_space_ownership(known_window.app, known_window.window, known_window.raw, "activeSpaceChanged", "steady", "active_space_callback_known_window_sweep") end
        after = self.trace:status().query_counters.steady
        local count_after = 0; for _, count in pairs(after) do count_after = count_after + count end
        self.trace:emit("active_space_known_window_sweep_end", { source = "spaces_watcher", trigger = "active_space_callback", sweep_scope = "known_windows_only", query_count = count_after - count_before, count = #known, result = "callback_complete_no_timer" })
      end)
      if not callback_ok then self:_fact("callback_error", { source = "spaces_watcher", error_class = "runtime_error" }) end
      self.trace:callback_exit("spaces_watcher", "activeSpaceChanged")
    end)
  end)
  if not ok or not watcher then self:_fact("spaces_watcher_unavailable", { source = "hs_spaces" }); return end
  if not protected(function() return watcher:start() end) then self:_fact("spaces_watcher_start_failed", { source = "hs_spaces" }); return end
  self.spaces_watcher = watcher
  self:_fact("spaces_watcher_attached", { source = "hs_spaces", watcher_kind = "spaces" })
end

function Observer:_bootstrap_existing_apps()
  self.trace:query("all_application_scan", "bootstrap.attach_existing_apps", "bootstrap")
  local ok, applications = protected(function() return hs.application.runningApplications() end)
  if not ok or type(applications) ~= "table" then self:_fact("bootstrap_application_scan_unavailable", { source = "bootstrap" }); return end
  for _, application in ipairs(applications) do self:_attach_direct_application(application, "bootstrap") end
end

function Observer:start()
  if self.running then return false, "already_running" end
  self:_new_run(); self.running = true; self.trace:lifecycle("start"); self.trace:mark("run_start", { source = "poc001" })
  for _, source in ipairs({ "window_filter", "application_watcher", "direct_ax" }) do self.trace:mark("candidate_sources", { source = source }) end
  self.trace:mark("framework_evidence", { source = "window_filter", framework_evidence = "source_inspection_unknown" }); self.trace:mark("framework_evidence", { source = "direct_ax", framework_evidence = "source_inspection_global_cleanup_watcher" })
  self:_start_application_watcher(); self:_bootstrap_existing_apps(); self:_start_filter(); self:_start_spaces_watcher()
  return true, self.trace:status().run_id
end

function Observer:stop()
  if not self.running then return false, "already_stopped" end
  if self.filter then protected(function() self.filter:unsubscribeAll() end); protected(function() self.filter:delete() end) end
  if self.application_watcher then protected(function() self.application_watcher:stop() end) end
  if self.spaces_watcher then protected(function() self.spaces_watcher:stop() end) end
  local window_keys, app_keys = {}, {}; for key in pairs(self.window_watchers) do window_keys[#window_keys + 1] = key end; for key in pairs(self.app_watchers) do app_keys[#app_keys + 1] = key end
  for _, key in ipairs(window_keys) do self:_stop_window_watcher(key) end
  for _, key in ipairs(app_keys) do local record = self.app_watchers[key]; if record then protected(function() record.watcher:stop() end) end; self.app_watchers[key] = nil end
  self.filter, self.application_watcher, self.spaces_watcher, self.running = nil, nil, nil, false; self.trace:lifecycle("stop"); self.trace:mark("cleanup_complete", { source = "poc001", count = 0 }); return true
end

function Observer:mark(sample_id, marker, action) assert(self.trace, "start the POC before marking"); self.trace:set_sample(sample_id); return self.trace:mark(marker, { source = "operator", action = action }) end
function Observer:status()
  if not self.trace then return { lifecycle = "not_started" } end
  local status = self.trace:status(); status.active_timers, status.window_effects, status.direct_application_watchers, status.direct_window_watchers, status.spaces_watcher_active = self.active_timers, self.window_effects, 0, 0, self.spaces_watcher ~= nil
  for _ in pairs(self.app_watchers) do status.direct_application_watchers = status.direct_application_watchers + 1 end; for _ in pairs(self.window_watchers) do status.direct_window_watchers = status.direct_window_watchers + 1 end
  return status
end
function Observer:export(path)
  assert(self.trace, "start the POC before exporting"); assert(type(path) == "string" and path:sub(1, 1) == "/", "export path must be an explicitly chosen absolute path")
  self.trace:mark("export_requested", { source = "operator" }); local file, err = io.open(path, "w"); assert(file, "cannot open export path: " .. tostring(err)); file:write(Trace.encode_json(self.trace:export_table()), "\n"); file:close(); return path
end
return Observer.new()
