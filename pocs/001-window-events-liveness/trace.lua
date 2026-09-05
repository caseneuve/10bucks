-- POC-001 pure trace/redaction bookkeeping. It deliberately has no hs dependency.
local Trace = {}
Trace.__index = Trace

local sensitive_keys = {
  title = true, url = true, path = true, text = true, value = true,
  ax_text = true, raw_ax = true, raw_id = true, pid = true,
  application_name = true, app_name = true, bundle_id = true,
}

local allowed_keys = {
  source = true, app = true, window = true, space = true, raw_event = true, marker = true,
  action = true, sample = true, query = true, call_site = true, scope = true,
  callback_sequence = true, trigger_callback_sequence = true, fact = true,
  result = true, reason = true, error_class = true, lifecycle = true,
  duration_ms = true, count = true, timer_id = true, watcher_kind = true,
  framework_evidence = true, framework_version = true, blind_spot = true,
  minimized = true, app_hidden = true, native_fullscreen = true, available = true,
  role = true, subrole = true, visibility = true, metadata_ready = true,
  metadata_status = true, field = true, query_phase = true,
  candidate_source = true, candidate_minimized = true,
  candidate_native_fullscreen = true, candidate_available = true,
  ownership_kind = true, retained_regular_space = true, from_space = true,
  to_space = true, expected_source = true, trigger = true, sweep_scope = true, query_count = true,
  topology_status = true, active_space = true, membership_count = true,
  reciprocal_confirmed_count = true, retained_prior_regular = true,
  target_relation = true, action_target_status = true, active_generation = true,
}

local function safe_token(value)
  return type(value) == "string" and value:match("^[A-Za-z0-9_.:-]+$") ~= nil
end

local function assert_safe_token(value, label)
  assert(safe_token(value), (label or "value") .. " must be a privacy-safe token")
  return value
end

local function copy_redacted(fields)
  local result = {}
  for key, value in pairs(fields or {}) do
    if allowed_keys[key] and not sensitive_keys[key] then
      if type(value) == "number" or type(value) == "boolean" then
        result[key] = value
      elseif safe_token(value) then
        result[key] = value
      end
    end
  end
  return result
end

local function deep_copy(value)
  if type(value) ~= "table" then return value end
  local result = {}
  for key, child in pairs(value) do result[key] = deep_copy(child) end
  return result
end

local function is_array(value)
  local count = 0
  for key in pairs(value) do
    if type(key) ~= "number" then return false end
    count = count + 1
  end
  return count == #value
end

local function escape_json(value)
  return value:gsub('[%z\1-\31\\"]', function(character)
    local escaped = { ['"'] = '\\"', ['\\'] = '\\\\', ['\b'] = '\\b', ['\f'] = '\\f', ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t' }
    return escaped[character] or string.format("\\u%04x", character:byte())
  end)
end

function Trace.encode_json(value)
  local kind = type(value)
  if kind == "nil" then return "null" end
  if kind == "boolean" then return value and "true" or "false" end
  if kind == "number" then return tostring(value) end
  if kind == "string" then return '"' .. escape_json(value) .. '"' end
  assert(kind == "table", "JSON value must be a plain Lua value")
  if is_array(value) then
    local parts = {}
    for index = 1, #value do parts[#parts + 1] = Trace.encode_json(value[index]) end
    return "[" .. table.concat(parts, ",") .. "]"
  end
  local keys = {}
  for key in pairs(value) do keys[#keys + 1] = key end
  table.sort(keys)
  local parts = {}
  for _, key in ipairs(keys) do
    parts[#parts + 1] = Trace.encode_json(tostring(key)) .. ":" .. Trace.encode_json(value[key])
  end
  return "{" .. table.concat(parts, ",") .. "}"
end

function Trace.new(clock, run_id)
  assert(type(clock) == "function", "clock is required")
  assert_safe_token(run_id, "run_id")
  return setmetatable({
    clock = clock,
    run_id = run_id,
    started_at_ms = clock(),
    sequence = 0,
    events = {},
    aliases = { apps = {}, windows = {}, spaces = {} }, -- never exported
    next_app = 0,
    next_window = 0,
    next_space = 0,
    current_sample = "sample-unset",
    callback_stack = {},
    counters = { bootstrap = {}, steady = {} },
    lifecycle_state = "stopped",
    lifecycle_transitions = 0,
  }, Trace)
end

function Trace:app_alias(raw_key)
  assert(raw_key ~= nil, "application identity is required")
  local alias = self.aliases.apps[raw_key]
  if not alias then
    self.next_app = self.next_app + 1
    alias = string.format("app-%03d", self.next_app)
    self.aliases.apps[raw_key] = alias
  end
  return alias
end

function Trace:space_alias(raw_space_key)
  assert(raw_space_key ~= nil, "space identity is required")
  local key = tostring(raw_space_key)
  local alias = self.aliases.spaces[key]
  if not alias then
    self.next_space = self.next_space + 1
    alias = string.format("space-%03d", self.next_space)
    self.aliases.spaces[key] = alias
  end
  return alias
end

function Trace:window_alias(raw_app_key, raw_window_key)
  assert(raw_app_key ~= nil and raw_window_key ~= nil, "window identity is required")
  local key = tostring(raw_app_key) .. "\0" .. tostring(raw_window_key)
  local alias = self.aliases.windows[key]
  if not alias then
    self.next_window = self.next_window + 1
    alias = string.format("win-%03d", self.next_window)
    self.aliases.windows[key] = alias
  end
  return alias
end

function Trace:set_sample(sample_id)
  self.current_sample = assert_safe_token(sample_id, "sample_id")
end

function Trace:emit(marker, fields)
  assert_safe_token(marker, "marker")
  self.sequence = self.sequence + 1
  local event = copy_redacted(fields)
  event.run_id = self.run_id
  event.sample_id = self.current_sample
  event.sequence = self.sequence
  event.monotonic_ms = self.clock() - self.started_at_ms
  event.marker = marker
  self.events[#self.events + 1] = event
  return event.sequence
end

function Trace:mark(marker, fields)
  if fields and fields.action ~= nil then assert_safe_token(fields.action, "action") end
  return self:emit(marker, fields)
end

function Trace:callback_enter(source, raw_event, fields)
  local callback_sequence = self:emit("callback_enter", fields)
  local callback = { source = assert_safe_token(source, "source"), raw_event = assert_safe_token(raw_event, "raw_event"), sequence = callback_sequence, began_ms = self.events[#self.events].monotonic_ms }
  self.callback_stack[#self.callback_stack + 1] = callback
  self.events[#self.events].source = callback.source
  self.events[#self.events].raw_event = callback.raw_event
  self.events[#self.events].callback_sequence = callback.sequence
  return callback.sequence
end

function Trace:callback_exit(source, raw_event, fields)
  local callback = table.remove(self.callback_stack)
  assert(callback, "callback_exit without callback_enter")
  local event_fields = fields or {}
  event_fields.source = source
  event_fields.raw_event = raw_event
  event_fields.callback_sequence = callback.sequence
  local sequence = self:emit("callback_exit", event_fields)
  self.events[#self.events].duration_ms = self.events[#self.events].monotonic_ms - callback.began_ms
  return sequence
end

function Trace:query(query, call_site, scope, fields)
  assert_safe_token(query, "query")
  assert_safe_token(call_site, "call_site")
  assert(scope == "bootstrap" or scope == "steady", "query scope must be bootstrap or steady")
  local bucket = self.counters[scope]
  bucket[query] = (bucket[query] or 0) + 1
  local event_fields = fields or {}
  event_fields.query = query
  event_fields.call_site = call_site
  event_fields.scope = scope
  local current = self.callback_stack[#self.callback_stack]
  if current then
    event_fields.callback_sequence = current.sequence
    event_fields.source = current.source
  end
  return self:emit("query_attempt", event_fields)
end

function Trace:targeted_check_begin(query, call_site, scope, fields)
  local event_fields = fields or {}
  event_fields.query_phase = "begin"
  self:query(query, call_site, scope, event_fields)
  return self:emit("targeted_check_begin", event_fields)
end

function Trace:targeted_check_end(query, call_site, scope, fields)
  local event_fields = fields or {}
  event_fields.query_phase = "end"
  event_fields.query = query
  event_fields.call_site = call_site
  event_fields.scope = scope
  local current = self.callback_stack[#self.callback_stack]
  if current then
    event_fields.callback_sequence = current.sequence
    event_fields.source = current.source
  end
  return self:emit("targeted_check_end", event_fields)
end

function Trace:lifecycle(action)
  assert(action == "start" or action == "stop", "lifecycle action must be start or stop")
  local wanted = action == "start" and "running" or "stopped"
  if self.lifecycle_state == wanted then return false end
  self.lifecycle_state = wanted
  self.lifecycle_transitions = self.lifecycle_transitions + 1
  self:emit("lifecycle_" .. action, { lifecycle = wanted })
  return true
end

function Trace:status()
  local callbacks_open = #self.callback_stack
  local steady_global = 0
  for query, count in pairs(self.counters.steady) do
    if query == "global_ax_enumeration" or query == "all_window_snapshot" or query == "all_application_scan" then
      steady_global = steady_global + count
    end
  end
  return {
    run_id = self.run_id,
    lifecycle = self.lifecycle_state,
    lifecycle_transitions = self.lifecycle_transitions,
    event_count = #self.events,
    callbacks = { open = callbacks_open },
    query_counters = deep_copy(self.counters),
    steady_global_queries = steady_global,
  }
end

function Trace:export_table()
  return { schema = "poc-001-trace-v1", events = deep_copy(self.events), status = self:status() }
end

return Trace
