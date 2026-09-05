-- POC-001 disposable, read-only Hammerspoon observer.
-- Load only from the Console after the legacy runtime is stopped; see README.md.
local Trace = require("trace")

local Observer = {}
Observer.__index = Observer

local FILTER_EVENTS = { "windowCreated", "windowFocused", "windowDestroyed" }
local DIRECT_APP_EVENTS = { "AXWindowCreated", "AXFocusedWindowChanged" }
local DIRECT_WINDOW_EVENTS = { "AXUIElementDestroyed" }

local function monotonic_ms()
  return hs.timer.absoluteTime() / 1000000
end

local function protected(callable)
  local ok, value = pcall(callable)
  if ok then return value end
  return nil
end

local function safe_id(object)
  if not object or type(object.id) ~= "function" then return nil end
  return protected(function() return object:id() end)
end

function Observer.new()
  return setmetatable({ run_number = 0, running = false }, Observer)
end

function Observer:_new_run()
  self.run_number = self.run_number + 1
  self.trace = Trace.new(monotonic_ms, string.format("run-%03d", self.run_number))
  self.app_watchers = {}
  self.window_watchers = {}
  self.window_identity_cache = {} -- raw native IDs; per-run only and never exported
  self.filter = nil
  self.application_watcher = nil
  self.active_timers = 0 -- This POC deliberately creates no timers.
  self.window_effects = 0 -- Read-only by construction.
end

function Observer:_fact(fact, fields)
  fields = fields or {}
  fields.fact = fact
  self.trace:emit("observation_fact", fields)
end

function Observer:_app_key(application, scope)
  assert(application, "application is unavailable")
  self.trace:query("targeted_application_pid", "direct_ax.app_pid", scope or "steady")
  local pid = type(application.pid) == "function" and protected(function() return application:pid() end) or nil
  if pid == nil then
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
  if id == nil then
    self:_fact("window_identity_unavailable", { source = "direct_ax" })
    return nil, nil
  end
  return self.trace:window_alias(app_key, tostring(id)), tostring(id)
end

function Observer:_remember_window_identity(raw_window_key, app_alias, window_alias)
  if raw_window_key and app_alias and window_alias then
    self.window_identity_cache[tostring(raw_window_key)] = { app = app_alias, window = window_alias }
  end
end

function Observer:_cached_window_identity(raw_window_key)
  return raw_window_key and self.window_identity_cache[tostring(raw_window_key)] or nil
end

function Observer:_forget_window_identity(raw_window_key)
  if raw_window_key then self.window_identity_cache[tostring(raw_window_key)] = nil end
end

function Observer:_stop_window_watcher(key)
  local watcher = self.window_watchers[key]
  if watcher then protected(function() watcher:stop() end) end
  self.window_watchers[key] = nil
end

function Observer:_observe_direct_window(app_key, app_alias, element, raw_event, scope)
  local window_alias, raw_window_key = self:_window_alias(app_key, element, "direct_ax.window_identity", scope)
  self.trace:emit("direct_window_observed", {
    source = "direct_ax", app = app_alias, window = window_alias,
    raw_event = raw_event, result = window_alias and "identified" or "identity_unavailable",
  })
  self:_remember_window_identity(raw_window_key, app_alias, window_alias)
  if not raw_window_key then return end

  local watcher_key = app_key .. "\0" .. raw_window_key
  if self.window_watchers[watcher_key] then return end
  local watcher = protected(function()
    return element:newWatcher(function(_, event)
      self.trace:callback_enter("direct_ax_window", event)
      local ok = pcall(function()
        local marker = event == "AXUIElementDestroyed" and "direct_window_destroyed" or "direct_window_event"
        self.trace:emit(marker, { source = "direct_ax_window", app = app_alias, window = window_alias, raw_event = event })
        if event == "AXUIElementDestroyed" then
          self:_forget_window_identity(raw_window_key)
          self:_stop_window_watcher(watcher_key)
        end
      end)
      if not ok then self:_fact("callback_error", { source = "direct_ax_window", error_class = "runtime_error" }) end
      self.trace:callback_exit("direct_ax_window", event)
    end)
  end)
  if not watcher then
    self:_fact("window_watcher_unavailable", { source = "direct_ax", app = app_alias, window = window_alias })
    return
  end
  local started = protected(function() return watcher:start(DIRECT_WINDOW_EVENTS) end)
  if not started then
    self:_fact("window_watcher_start_failed", { source = "direct_ax", app = app_alias, window = window_alias })
    return
  end
  self.window_watchers[watcher_key] = watcher
  self:_fact("window_watcher_attached", { source = "direct_ax", app = app_alias, window = window_alias, watcher_kind = "window" })
end

function Observer:_attach_bootstrap_windows(application, app_key, app_alias)
  self.trace:query("per_application_window_scan", "bootstrap.attach_existing_windows", "bootstrap")
  local windows = type(application.allWindows) == "function" and protected(function() return application:allWindows() end) or nil
  if type(windows) ~= "table" then
    self:_fact("bootstrap_window_scan_unavailable", { source = "bootstrap", app = app_alias })
    return
  end
  for _, window in ipairs(windows) do
    self:_observe_direct_window(app_key, app_alias, window, "bootstrap_existing_window", "bootstrap")
  end
end

function Observer:_attach_direct_application(application, origin)
  if not application then
    self:_fact("application_unavailable", { source = "direct_ax", reason = origin })
    return
  end
  local bootstrap = origin == "bootstrap"
  local app_key, pid, app_alias = self:_app_alias(application, bootstrap and "bootstrap" or "steady")
  if self.app_watchers[app_key] then
    if bootstrap then self:_attach_bootstrap_windows(application, app_key, app_alias) end
    return
  end
  local watcher = protected(function()
    return application:newWatcher(function(element, event)
      self.trace:callback_enter("direct_ax_application", event)
      local ok = pcall(function()
        self.trace:emit("direct_application_event", { source = "direct_ax_application", app = app_alias, raw_event = event })
        self:_observe_direct_window(app_key, app_alias, element, event)
      end)
      if not ok then self:_fact("callback_error", { source = "direct_ax_application", app = app_alias, error_class = "runtime_error" }) end
      self.trace:callback_exit("direct_ax_application", event)
    end)
  end)
  if not watcher then
    self:_fact("application_watcher_unavailable", { source = "direct_ax", app = app_alias, reason = origin })
  else
    local started = protected(function() return watcher:start(DIRECT_APP_EVENTS) end)
    if not started then
      self:_fact("application_watcher_start_failed", { source = "direct_ax", app = app_alias, reason = origin })
    else
      self.app_watchers[app_key] = { watcher = watcher, pid = pid, alias = app_alias }
      self:_fact("application_watcher_attached", { source = "direct_ax", app = app_alias, reason = origin, watcher_kind = "application" })
    end
  end
  if bootstrap then self:_attach_bootstrap_windows(application, app_key, app_alias) end
end

function Observer:_detach_direct_application_by_pid(pid)
  if pid == nil then return end
  local key = "pid:" .. tostring(pid)
  local record = self.app_watchers[key]
  if record then protected(function() record.watcher:stop() end) end
  self.app_watchers[key] = nil
  local window_keys = {}
  local prefix = key .. "\0"
  for window_key in pairs(self.window_watchers) do
    if window_key:sub(1, #prefix) == prefix then window_keys[#window_keys + 1] = window_key end
  end
  for _, window_key in ipairs(window_keys) do self:_stop_window_watcher(window_key) end
end

function Observer:_start_application_watcher()
  self.application_watcher = hs.application.watcher.new(function(_, event, application)
    local event_name = ({ [0] = "launching", "launched", "terminated", "hidden", "unhidden", "activated", "deactivated" })[event] or "unknown"
    self.trace:callback_enter("application_watcher", event_name)
    local ok = pcall(function()
      local app_key, pid, app_alias
      if application then
        app_key, pid, app_alias = self:_app_alias(application)
      else
        app_key, app_alias = "unavailable-app", "app-unavailable"
        self:_fact("application_unavailable", { source = "application_watcher", raw_event = event_name })
      end
      self.trace:emit("application_event", { source = "application_watcher", app = app_alias, raw_event = event_name })
      if event == hs.application.watcher.launched then
        self:_attach_direct_application(application, "launch")
      elseif event == hs.application.watcher.terminated then
        self:_detach_direct_application_by_pid(pid)
        self.trace:emit("application_terminated", { source = "application_watcher", app = app_alias, raw_event = event_name })
      end
    end)
    if not ok then self:_fact("callback_error", { source = "application_watcher", error_class = "runtime_error" }) end
    self.trace:callback_exit("application_watcher", event_name)
  end)
  self.application_watcher:start()
end

function Observer:_start_filter()
  self.filter = hs.window.filter.new(true, "poc001-window-events")
  for _, event_name in ipairs(FILTER_EVENTS) do
    self.filter:subscribe(event_name, function(window, _, event)
      self.trace:callback_enter("window_filter", event)
      local ok = pcall(function()
        self.trace:query("targeted_window_id", "window_filter.callback_window_id", "steady")
        local raw_id = safe_id(window)
        local application = protected(function() return window:application() end)
        local app_alias, window_alias
        if application then
          local app_key
          app_key, _, app_alias = self:_app_alias(application)
          window_alias = raw_id and self.trace:window_alias(app_key, tostring(raw_id)) or nil
          self:_remember_window_identity(raw_id, app_alias, window_alias)
        else
          local cached = self:_cached_window_identity(raw_id)
          if cached then
            app_alias, window_alias = cached.app, cached.window
          else
            self:_fact("filter_application_unavailable", { source = "window_filter" })
          end
        end
        self.trace:emit("filter_window_event", {
          source = "window_filter", app = app_alias, window = window_alias,
          raw_event = event, result = window_alias and "identified" or "identity_unavailable",
        })
        if event == "windowDestroyed" then self:_forget_window_identity(raw_id) end
      end)
      if not ok then self:_fact("callback_error", { source = "window_filter", error_class = "runtime_error" }) end
      self.trace:callback_exit("window_filter", event)
    end)
  end
end

function Observer:_bootstrap_existing_apps()
  self.trace:query("all_application_scan", "bootstrap.attach_existing_apps", "bootstrap")
  local applications = protected(function() return hs.application.runningApplications() end)
  if type(applications) ~= "table" then
    self:_fact("bootstrap_application_scan_unavailable", { source = "bootstrap" })
    return
  end
  for _, application in ipairs(applications) do self:_attach_direct_application(application, "bootstrap") end
end

function Observer:start()
  if self.running then return false, "already_running" end
  self:_new_run()
  self.running = true
  self.trace:lifecycle("start")
  self.trace:mark("run_start", { source = "poc001" })
  self.trace:mark("candidate_sources", { source = "window_filter" })
  self.trace:mark("candidate_sources", { source = "application_watcher" })
  self.trace:mark("candidate_sources", { source = "direct_ax" })
  self.trace:mark("framework_evidence", { source = "window_filter", framework_evidence = "source_inspection_unknown" })
  self.trace:mark("framework_evidence", { source = "direct_ax", framework_evidence = "source_inspection_global_cleanup_watcher" })
  self:_start_application_watcher()
  self:_bootstrap_existing_apps()
  self:_start_filter()
  return true, self.trace:status().run_id
end

function Observer:stop()
  if not self.running then return false, "already_stopped" end
  if self.filter then
    protected(function() self.filter:unsubscribeAll() end)
    protected(function() self.filter:delete() end)
  end
  if self.application_watcher then protected(function() self.application_watcher:stop() end) end
  local window_keys, application_keys = {}, {}
  for key in pairs(self.window_watchers) do window_keys[#window_keys + 1] = key end
  for key in pairs(self.app_watchers) do application_keys[#application_keys + 1] = key end
  for _, key in ipairs(window_keys) do self:_stop_window_watcher(key) end
  for _, key in ipairs(application_keys) do
    local record = self.app_watchers[key]
    if record then protected(function() record.watcher:stop() end) end
    self.app_watchers[key] = nil
  end
  self.filter, self.application_watcher = nil, nil
  self.running = false
  self.trace:lifecycle("stop")
  self.trace:mark("cleanup_complete", { source = "poc001", count = 0 })
  return true
end

function Observer:mark(sample_id, marker, action)
  assert(self.trace, "start the POC before marking")
  self.trace:set_sample(sample_id)
  return self.trace:mark(marker, { source = "operator", action = action })
end

function Observer:status()
  if not self.trace then return { lifecycle = "not_started" } end
  local status = self.trace:status()
  status.active_timers = self.active_timers
  status.window_effects = self.window_effects
  status.direct_application_watchers = 0
  status.direct_window_watchers = 0
  for _ in pairs(self.app_watchers) do status.direct_application_watchers = status.direct_application_watchers + 1 end
  for _ in pairs(self.window_watchers) do status.direct_window_watchers = status.direct_window_watchers + 1 end
  return status
end

function Observer:export(path)
  assert(self.trace, "start the POC before exporting")
  assert(type(path) == "string" and path:sub(1, 1) == "/", "export path must be an explicitly chosen absolute path")
  self.trace:mark("export_requested", { source = "operator" })
  local file, error_message = io.open(path, "w")
  assert(file, "cannot open export path: " .. tostring(error_message))
  file:write(Trace.encode_json(self.trace:export_table()))
  file:write("\n")
  file:close()
  return path
end

return Observer.new()
