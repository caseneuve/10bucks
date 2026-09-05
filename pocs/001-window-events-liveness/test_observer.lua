local source = debug.getinfo(1, "S").source:sub(2)
local root = source:match("(.*/)pocs/") or "./"
package.path = root .. "pocs/001-window-events-liveness/?.lua;" .. package.path

local function equal(actual, expected) assert(actual == expected, string.format("expected %s, got %s", tostring(expected), tostring(actual))) end
local function fake_watcher() return { start = function(self, events) self.started, self.events = true, events; return self end, stop = function(self) self.stopped = true; return self end } end
local function fake_window(id, metadata)
  return {
    id = function() return id end,
    attributeValue = function(_, attribute) return metadata and metadata[attribute] end,
    newWatcher = function(self, callback) local watcher = fake_watcher(); watcher.callback = callback; self.watcher = watcher; return watcher end,
  }
end
local function fake_application(pid, windows)
  return {
    pid = function() return pid end,
    allWindows = function(self) self.all_windows_calls = (self.all_windows_calls or 0) + 1; return windows end,
    newWatcher = function(self, callback) local watcher = fake_watcher(); watcher.callback = callback; self.watcher = watcher; return watcher end,
  }
end
local function install_fake_hs(applications)
  local state = { filter_new_arguments = {} }
  _G.hs = {
    timer = { absoluteTime = function() state.clock = (state.clock or 0) + 1000000; return state.clock end },
    window = { filter = { new = function(allow_all, name)
      state.filter_new_arguments[#state.filter_new_arguments + 1] = { allow_all, name }
      local filter = { subscriptions = {} }
      function filter:subscribe(event, callback) self.subscriptions[event] = callback; return self end
      function filter:unsubscribeAll() self.unsubscribed = true; return self end
      function filter:delete() self.deleted = true end
      state.filter = filter; return filter
    end } },
    application = { runningApplications = function() return applications end, watcher = {
      launching = 0, launched = 1, terminated = 2, hidden = 3, unhidden = 4, activated = 5, deactivated = 6,
      new = function(callback) state.application_watcher_callback = callback; state.application_watcher = fake_watcher(); return state.application_watcher end,
    } },
  }
  return state
end
local function install_fake_spaces(state, memberships)
  memberships = memberships or {}
  _G.hs.spaces = {
    windowSpaces = function(id) return memberships[tostring(id)] or {} end,
    windowsForSpace = function(space) return memberships.reverse and memberships.reverse[tostring(space)] or {} end,
    data_managedDisplaySpaces = function() return { { Spaces = { { ManagedSpaceID = 10, type = 0 }, { ManagedSpaceID = 20, type = 0 }, { ManagedSpaceID = 30, type = 4 } } } } end,
    activeSpaceOnScreen = function() return 10 end,
    watcher = { new = function(callback) local watcher = fake_watcher(); watcher.callback = callback; state.spaces_watcher = watcher; return watcher end },
  }
end
local function complete_metadata() return { AXMinimized = false, AXFullScreen = false, AXRole = "AXWindow", AXSubrole = "AXStandardWindow", AXVisible = true } end
local function events(observer, marker) local result = {}; for _, event in ipairs(observer.trace:export_table().events) do if event.marker == marker then result[#result + 1] = event end end; return result end

return {
  ["POC-001 bootstrap attaches direct watchers and attributes metadata work to bootstrap"] = function()
    local window = fake_window(100, complete_metadata())
    local application = fake_application(41, { window })
    install_fake_hs({ application }); package.loaded.observer = nil
    local observer = require("observer").new(); assert(observer:start())
    assert(window.watcher and window.watcher.started)
    equal(application.all_windows_calls, 1)
    local begins = {}; for _, event in ipairs(events(observer, "targeted_check_begin")) do if event.query == "targeted_window_metadata" then begins[#begins + 1] = event end end
    equal(#begins, 5)
    for _, event in ipairs(begins) do equal(event.scope, "bootstrap") end
    observer:stop()
  end,
  ["POC-001 observer subscribes comparison lifecycle events and direct AX triggers"] = function()
    local window, application = fake_window(101, complete_metadata()), fake_application(42, {})
    local state = install_fake_hs({ application }); package.loaded.observer = nil
    local observer = require("observer").new(); assert(observer:start())
    for _, event in ipairs({ "windowMinimized", "windowUnminimized", "windowFullscreened", "windowUnfullscreened", "windowMoved" }) do assert(state.filter.subscriptions[event]) end
    local direct = application.watcher.events
    for _, event in ipairs({ "AXWindowCreated", "AXFocusedWindowChanged" }) do assert(table.concat(direct, ","):find(event, 1, true)) end
    application.watcher.callback(window, "AXWindowCreated")
    assert(window.watcher)
    for _, event in ipairs({ "AXWindowMiniaturized", "AXWindowDeminiaturized", "AXWindowMoved", "AXWindowResized" }) do assert(table.concat(window.watcher.events, ","):find(event, 1, true)) end
    observer:stop()
  end,
  ["POC-001 direct callbacks attribute targeted metadata queries and only mark safe ready metadata"] = function()
    local window, application = fake_window(201, complete_metadata()), fake_application(77, {})
    local state = install_fake_hs({ application }); package.loaded.observer = nil
    local observer = require("observer").new(); assert(observer:start())
    application.watcher.callback(window, "AXWindowCreated")
    local begins, ends, ready = {}, {}, events(observer, "metadata_ready")
    for _, event in ipairs(events(observer, "targeted_check_begin")) do if event.query == "targeted_window_metadata" then begins[#begins + 1] = event end end
    for _, event in ipairs(events(observer, "targeted_check_end")) do if event.query == "targeted_window_metadata" then ends[#ends + 1] = event end end
    equal(#begins, 5); equal(#ends, 5); equal(#ready, 1)
    for _, event in ipairs(begins) do equal(event.callback_sequence ~= nil, true); equal(event.query, "targeted_window_metadata") end
    local exported = require("trace").encode_json(observer.trace:export_table())
    assert(not exported:find("201", 1, true)); assert(not exported:find("77", 1, true))
    observer:stop()
  end,
  ["POC-001 direct move infers fullscreen only as a targeted observed property"] = function()
    local metadata, window = complete_metadata(), fake_window(301, complete_metadata())
    local application = fake_application(88, {}); local state = install_fake_hs({ application }); package.loaded.observer = nil
    local observer = require("observer").new(); assert(observer:start()); application.watcher.callback(window, "AXWindowCreated")
    metadata.AXFullScreen = true; window.attributeValue = function(_, attribute) return metadata[attribute] end
    window.watcher.callback(window, "AXWindowMoved")
    local commits = events(observer, "lifecycle_fact_committed"); local inferred
    for _, event in ipairs(commits) do if event.raw_event == "AXWindowMoved" then inferred = event end end
    assert(inferred); equal(inferred.candidate_source, "direct_ax"); equal(inferred.candidate_native_fullscreen, true); equal(inferred.result, "targeted_observed_property")
    observer:stop()
  end,
  ["POC-001 delayed competing filter and direct facts remain isolated and report conflict"] = function()
    local window, application = fake_window(350, complete_metadata()), fake_application(89, {})
    local state = install_fake_hs({ application }); package.loaded.observer = nil
    local observer = require("observer").new(); assert(observer:start())
    application.watcher.callback(window, "AXWindowCreated")
    window.application = function() return application end
    state.filter.subscriptions.windowMinimized(window, nil, "windowMinimized")
    local lifecycle = observer.lifecycle:window("win-001")
    equal(lifecycle.candidates.direct_ax.minimized, false)
    equal(lifecycle.candidates.filter.minimized, true)
    local conflicts = events(observer, "observation_fact")
    local found = false
    for _, event in ipairs(conflicts) do if event.fact == "lifecycle_source_conflict" and event.field == "minimized" then found = true end end
    assert(found)
    observer:stop()
  end,
  ["POC-001 app hide updates every known alias and preserves minimize fullscreen"] = function()
    local first, second = fake_window(401, complete_metadata()), fake_window(402, complete_metadata())
    local application = fake_application(99, {}); local state = install_fake_hs({ application }); package.loaded.observer = nil
    local observer = require("observer").new(); assert(observer:start()); application.watcher.callback(first, "AXWindowCreated"); application.watcher.callback(second, "AXWindowCreated")
    first.attributeValue = function(_, attr) local m = complete_metadata(); m.AXMinimized = true; return m[attr] end; first.watcher.callback(first, "AXWindowMiniaturized"); second.attributeValue = function(_, attr) local m = complete_metadata(); m.AXFullScreen = true; return m[attr] end; second.watcher.callback(second, "AXWindowMoved")
    state.application_watcher_callback(nil, hs.application.watcher.hidden, application)
    state.application_watcher_callback(nil, hs.application.watcher.unhidden, application)
    local one, two = observer.lifecycle:window("win-001"), observer.lifecycle:window("win-002")
    assert(one.candidates.direct_ax.minimized); assert(two.candidates.direct_ax.native_fullscreen)
    assert(not one.candidates.direct_ax.available); assert(not two.candidates.direct_ax.available)
    observer:stop()
  end,
  ["DISC-002 POC readiness requires safe metadata plus one confirmed regular ownership"] = function()
    local window, application = fake_window(601, complete_metadata()), fake_application(56, {})
    local state = install_fake_hs({ application }); install_fake_spaces(state, { ["601"] = { 10 }, reverse = { ["10"] = { 601 } } }); package.loaded.observer = nil
    local observer = require("observer").new(); assert(observer:start()); application.watcher.callback(window, "AXWindowCreated")
    equal(#events(observer, "window_ready_eligible"), 1)
    application.watcher.callback(window, "AXFocusedWindowChanged")
    equal(#events(observer, "window_ready_eligible"), 1)
    observer:stop()
  end,
  ["WIN-006 POC direct move query attribution confirms only a distinct regular destination"] = function()
    local window, application = fake_window(701, complete_metadata()), fake_application(57, {})
    local state = install_fake_hs({ application }); local memberships = { ["701"] = { 10 }, reverse = { ["10"] = { 701 }, ["20"] = { 701 } } }; install_fake_spaces(state, memberships); package.loaded.observer = nil
    local observer = require("observer").new(); assert(observer:start()); application.watcher.callback(window, "AXWindowCreated")
    memberships["701"] = { 20 }; window.watcher.callback(window, "AXWindowMoved")
    local moves, checks = events(observer, "space_move_confirmed"), events(observer, "targeted_check_begin")
    equal(#moves, 1); equal(moves[1].from_space, "space-001"); equal(moves[1].to_space, "space-002")
    local attributed = false; for _, event in ipairs(checks) do if event.trigger == "direct_ax_window_move" and event.query == "spaces_window_spaces" then attributed = true end end; assert(attributed)
    observer:stop()
  end,
  ["POC-001 active-Space callback performs one bounded known-window sweep and creates no timer"] = function()
    local window, application = fake_window(801, complete_metadata()), fake_application(58, {})
    local state = install_fake_hs({ application }); install_fake_spaces(state, { ["801"] = { 10 }, reverse = { ["10"] = { 801 } } }); package.loaded.observer = nil
    local observer = require("observer").new(); assert(observer:start()); application.watcher.callback(window, "AXWindowCreated")
    state.spaces_watcher.callback()
    local end_events = events(observer, "active_space_known_window_sweep_end")
    equal(#end_events, 1); equal(end_events[1].sweep_scope, "known_windows_only"); assert(end_events[1].query_count > 0); equal(observer:status().active_timers, 0)
    observer:stop(); assert(state.spaces_watcher.stopped)
  end,
  ["POC-001 cleanup removes observer-owned direct watchers"] = function()
    local window, application = fake_window(501, complete_metadata()), fake_application(55, {})
    local state = install_fake_hs({ application }); package.loaded.observer = nil
    local observer = require("observer").new(); assert(observer:start()); application.watcher.callback(window, "AXWindowCreated"); observer:stop()
    assert(state.filter.unsubscribed and state.filter.deleted); assert(state.application_watcher.stopped); assert(application.watcher.stopped); assert(window.watcher.stopped)
  end,
}
