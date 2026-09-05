local source = debug.getinfo(1, "S").source:sub(2)
local root = source:match("(.*/)pocs/") or "./"
package.path = root .. "pocs/001-window-events-liveness/?.lua;" .. package.path

local function equal(actual, expected)
  assert(actual == expected, string.format("expected %s, got %s", tostring(expected), tostring(actual)))
end

local function fake_watcher()
  return {
    started = false,
    stopped = false,
    start = function(self, events) self.started, self.events = true, events; return self end,
    stop = function(self) self.stopped = true; return self end,
  }
end

local function fake_window(id)
  return {
    id = function() return id end,
    newWatcher = function(self, callback)
      local watcher = fake_watcher()
      watcher.callback = callback
      self.watcher = watcher
      return watcher
    end,
  }
end

local function fake_application(pid, windows)
  return {
    pid = function() return pid end,
    allWindows = function(self)
      self.all_windows_calls = (self.all_windows_calls or 0) + 1
      return windows
    end,
    newWatcher = function(self, callback)
      local watcher = fake_watcher()
      watcher.callback = callback
      self.watcher = watcher
      return watcher
    end,
  }
end

local function install_fake_hs(applications)
  local state = { filter_new_arguments = {} }
  _G.hs = {
    timer = { absoluteTime = function() state.clock = (state.clock or 0) + 1000000; return state.clock end },
    window = {
      filter = {
        new = function(allow_all, name)
          state.filter_new_arguments[#state.filter_new_arguments + 1] = { allow_all, name }
          local filter = { subscriptions = {} }
          function filter:subscribe(event, callback) self.subscriptions[event] = callback; return self end
          function filter:unsubscribeAll() self.unsubscribed = true; return self end
          function filter:delete() self.deleted = true end
          state.filter = filter
          return filter
        end,
      },
    },
    application = {
      runningApplications = function() return applications end,
      watcher = {
        launched = 1, terminated = 2,
        new = function(callback)
          state.application_watcher_callback = callback
          state.application_watcher = fake_watcher()
          return state.application_watcher
        end,
      },
    },
  }
  return state
end

return {
  ["POC-001 observer uses an allow-all filter and attaches destruction watchers for bootstrap windows"] = function()
    local windows = { fake_window(101), fake_window(102) }
    local application = fake_application(42, windows)
    local state = install_fake_hs({ application })
    package.loaded.observer = nil
    local observer = require("observer").new()

    assert(observer:start())
    equal(state.filter_new_arguments[1][1], true)
    equal(application.all_windows_calls, 1)
    assert(windows[1].watcher and windows[1].watcher.started)
    assert(windows[2].watcher and windows[2].watcher.started)
    local status = observer:status()
    equal(status.direct_window_watchers, 2)
    equal(status.query_counters.bootstrap.per_application_window_scan, 1)
    equal(status.query_counters.steady.all_window_snapshot, nil)
    observer:stop()
  end,

  ["POC-001 observer termination removes its app and window watcher ownership"] = function()
    local windows = { fake_window(201), fake_window(202) }
    local application = fake_application(77, windows)
    local state = install_fake_hs({ application })
    package.loaded.observer = nil
    local observer = require("observer").new()

    assert(observer:start())
    state.application_watcher_callback(nil, hs.application.watcher.terminated, application)
    local status = observer:status()
    equal(status.direct_application_watchers, 0)
    equal(status.direct_window_watchers, 0)
    assert(application.watcher.stopped)
    assert(windows[1].watcher.stopped)
    assert(windows[2].watcher.stopped)
    observer:stop()
  end,

  ["POC-001 filter destruction keeps cached aliases when the application disappears"] = function()
    local application = fake_application(88, {})
    local state = install_fake_hs({ application })
    local window = fake_window(903)
    local current_application = application
    window.application = function() return current_application end
    package.loaded.observer = nil
    local observer = require("observer").new()

    assert(observer:start())
    state.filter.subscriptions.windowCreated(window, nil, "windowCreated")
    current_application = nil
    state.filter.subscriptions.windowDestroyed(window, nil, "windowDestroyed")

    local exported = observer.trace:export_table()
    local destruction
    for _, event in ipairs(exported.events) do
      if event.marker == "filter_window_event" and event.raw_event == "windowDestroyed" then destruction = event end
      assert(event.fact ~= "callback_error")
    end
    assert(destruction)
    equal(destruction.app, "app-001")
    equal(destruction.window, "win-001")
    local json = require("trace").encode_json(exported)
    assert(not json:find("903", 1, true))
    assert(observer.window_identity_cache["903"] == nil)
    observer:stop()
    assert(observer:start())
    assert(next(observer.window_identity_cache) == nil)
    observer:stop()
  end,
}
