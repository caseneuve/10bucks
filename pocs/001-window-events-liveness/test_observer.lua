local source = debug.getinfo(1, "S").source:sub(2)
local root = source:match("(.*/)pocs/") or "./"
package.path = root .. "pocs/001-window-events-liveness/?.lua;" .. package.path

local function equal(actual, expected) assert(actual == expected, string.format("expected %s, got %s", tostring(expected), tostring(actual))) end
local function fake_watcher() return { start = function(self, events) self.started, self.events = true, events; return self end, stop = function(self) self.stopped = true; return self end } end
local function userdata_like_watcher()
  local watcher, state = {}, {}
  watcher.start = function(_, events) state.started, state.events = true, events; return watcher end
  watcher.stop = function() state.stopped = true; return watcher end
  return setmetatable(watcher, { __newindex = function() error("userdata does not allow arbitrary fields") end }), state
end
local function fake_window(id, metadata)
  local window = {
    id = function() return id end,
    newWatcher = function(self, callback) local watcher = fake_watcher(); watcher.callback = callback; self.watcher = watcher; return watcher end,
  }
  window.isMinimized = function() return metadata and metadata.minimized end
  window.isFullScreen = function() return metadata and metadata.native_fullscreen end
  window.role = function() return metadata and metadata.role end
  window.subrole = function() return metadata and metadata.subrole end
  window.isVisible = function() return metadata and metadata.visibility end
  return window
end
local function fake_application(pid, windows, bundle_id)
  return {
    pid = function() return pid end,
    bundleID = function() return bundle_id end,
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
local function install_fake_hotkey(state)
  state.hotkeys = {}
  _G.hs.hotkey = {
    new = function(modifiers, key, callback)
      local hotkey, hotkey_state = {}, { modifiers = modifiers, key = key, callback = callback }
      hotkey.enable = function()
        hotkey_state.enabled = true
        return hotkey
      end
      hotkey.delete = function()
        hotkey_state.deleted = true
        return hotkey
      end
      local userdata_like = setmetatable(hotkey, { __newindex = function() error("userdata does not allow arbitrary fields") end })
      hotkey_state.hotkey = userdata_like
      state.hotkeys[#state.hotkeys + 1] = hotkey_state
      return userdata_like
    end,
  }
end
local function install_fake_spaces(state, memberships)
  memberships = memberships or {}
  _G.hs.spaces = {
    windowSpaces = function(id) return memberships[tostring(id)] or {} end,
    windowsForSpace = function(space) return memberships.reverse and memberships.reverse[tostring(space)] or {} end,
    data_managedDisplaySpaces = function() state.topology_calls = (state.topology_calls or 0) + 1; return { { Spaces = { { ManagedSpaceID = 10, type = 0 }, { ManagedSpaceID = 20, type = 0 }, { ManagedSpaceID = 30, type = 4 } } } } end,
    activeSpaceOnScreen = function() state.active_space_calls = (state.active_space_calls or 0) + 1; return memberships.active or 10 end,
    watcher = { new = function(callback) local watcher = fake_watcher(); watcher.callback = callback; state.spaces_watcher = watcher; return watcher end },
  }
end
local function complete_metadata() return { minimized = false, native_fullscreen = false, role = "AXWindow", subrole = "AXStandardWindow", visibility = true } end
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
    metadata.native_fullscreen = true; window.isFullScreen = function() return metadata.native_fullscreen end
    window.watcher.callback(window, "AXWindowMoved")
    local commits = events(observer, "lifecycle_fact_committed"); local inferred
    for _, event in ipairs(commits) do if event.raw_event == "AXWindowMoved" then inferred = event end end
    assert(inferred); equal(inferred.candidate_source, "direct_ax"); equal(inferred.candidate_native_fullscreen, true); equal(inferred.result, "targeted_observed_property")
    observer:stop()
  end,
  ["PERF-002 POC repeated same-fullscreen resize skips Space ownership"] = function()
    local metadata, window = complete_metadata(), fake_window(302, complete_metadata())
    local application = fake_application(881, {}); local state = install_fake_hs({ application })
    install_fake_spaces(state, { ["302"] = { 10 }, reverse = { ["10"] = { 302 } } }); package.loaded.observer = nil
    local observer = require("observer").new(); assert(observer:start()); application.watcher.callback(window, "AXWindowCreated")
    window.isFullScreen = function() return metadata.native_fullscreen end
    window.watcher.callback(window, "AXWindowResized"); window.watcher.callback(window, "AXWindowResized")
    local checks, skipped = events(observer, "targeted_check_begin"), events(observer, "ownership_check_skipped")
    local resize_checks = 0; for _, event in ipairs(checks) do if event.trigger == "direct_ax_window_resize_fullscreen_changed" then resize_checks = resize_checks + 1 end end
    equal(resize_checks, 0); equal(#skipped, 2)
    for _, event in ipairs(skipped) do equal(event.reason, "resize_fullscreen_unchanged"); equal(event.fullscreen_status, "unchanged") end
    observer:stop()
  end,
  ["FS-002 POC resize fullscreen transitions each probe Space ownership"] = function()
    local metadata, window = complete_metadata(), fake_window(303, complete_metadata())
    local application = fake_application(882, {}); local state = install_fake_hs({ application })
    install_fake_spaces(state, { ["303"] = { 10 }, reverse = { ["10"] = { 303 } } }); package.loaded.observer = nil
    local observer = require("observer").new(); assert(observer:start()); application.watcher.callback(window, "AXWindowCreated")
    window.isFullScreen = function() return metadata.native_fullscreen end
    metadata.native_fullscreen = true; window.watcher.callback(window, "AXWindowResized")
    metadata.native_fullscreen = false; window.watcher.callback(window, "AXWindowResized")
    local checks, resize_checks = events(observer, "targeted_check_begin"), 0
    for _, event in ipairs(checks) do if event.query == "spaces_window_spaces" and event.trigger == "direct_ax_window_resize_fullscreen_changed" then resize_checks = resize_checks + 1 end end
    equal(resize_checks, 2); observer:stop()
  end,
  ["WIN-006 POC moved always probes ownership despite fullscreen-read uncertainty"] = function()
    local window = fake_window(304, complete_metadata())
    local application = fake_application(883, {}); local state = install_fake_hs({ application })
    install_fake_spaces(state, { ["304"] = { 10 }, reverse = { ["10"] = { 304 } } }); package.loaded.observer = nil
    local observer = require("observer").new(); assert(observer:start()); application.watcher.callback(window, "AXWindowCreated")
    window.isFullScreen = nil; window.watcher.callback(window, "AXWindowMoved")
    local checks, uncertain, moved = events(observer, "targeted_check_begin"), events(observer, "observation_fact"), 0
    for _, event in ipairs(checks) do if event.query == "spaces_window_spaces" and event.trigger == "direct_ax_window_move" then moved = moved + 1 end end
    equal(moved, 1); local found = false; for _, event in ipairs(uncertain) do if event.fact == "metadata_uncertain" and event.field == "native_fullscreen" then found = true end end; assert(found)
    observer:stop()
  end,
  ["STATE-005 POC unavailable resize records uncertainty and retains ownership non-destructively"] = function()
    local window = fake_window(305, complete_metadata())
    local application = fake_application(884, {}); local state = install_fake_hs({ application })
    install_fake_spaces(state, { ["305"] = { 10 }, reverse = { ["10"] = { 305 } } }); package.loaded.observer = nil
    local observer = require("observer").new(); assert(observer:start()); application.watcher.callback(window, "AXWindowCreated")
    window.isFullScreen = nil; window.watcher.callback(window, "AXWindowResized")
    local ownership = observer.ownership:window("win-001")
    equal(ownership.confirmed_regular, "space-001")
    local skipped = events(observer, "ownership_check_skipped"); equal(#skipped, 1); equal(skipped[1].reason, "resize_fullscreen_unchanged"); equal(skipped[1].fullscreen_status, "unavailable")
    local resize_checks = 0; for _, event in ipairs(events(observer, "targeted_check_begin")) do if event.trigger == "direct_ax_window_resize_fullscreen_changed" then resize_checks = resize_checks + 1 end end; equal(resize_checks, 0)
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
    local first_metadata, second_metadata = complete_metadata(), complete_metadata(); first_metadata.minimized = true; second_metadata.native_fullscreen = true
    first.isMinimized = function() return first_metadata.minimized end; first.watcher.callback(first, "AXWindowMiniaturized")
    second.isFullScreen = function() return second_metadata.native_fullscreen end; second.watcher.callback(second, "AXWindowMoved")
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
  ["POC-001 active-Space sweep reuses one topology snapshot across known windows and creates no timer"] = function()
    local first, second = fake_window(801, complete_metadata()), fake_window(802, complete_metadata())
    local application = fake_application(58, {})
    local state = install_fake_hs({ application }); install_fake_spaces(state, { ["801"] = { 10 }, ["802"] = { 10 }, reverse = { ["10"] = { 801, 802 } } }); package.loaded.observer = nil
    local observer = require("observer").new(); assert(observer:start()); application.watcher.callback(first, "AXWindowCreated"); application.watcher.callback(second, "AXWindowCreated")
    local topology_before = state.topology_calls; state.spaces_watcher.callback()
    local end_events = events(observer, "active_space_known_window_sweep_end")
    equal(#end_events, 1); equal(end_events[1].sweep_scope, "known_windows_only"); equal(end_events[1].count, 2); assert(end_events[1].query_count > 0); equal(state.topology_calls - topology_before, 1); equal(observer:status().active_timers, 0)
    observer:stop(); assert(state.spaces_watcher.stopped)
  end,
  ["POC-001 duplicate active-Space callback is coalesced without another sweep"] = function()
    local window, application = fake_window(803, complete_metadata()), fake_application(63, {})
    local state = install_fake_hs({ application }); install_fake_spaces(state, { ["803"] = { 10 }, reverse = { ["10"] = { 803 } } }); package.loaded.observer = nil
    local observer = require("observer").new(); assert(observer:start()); application.watcher.callback(window, "AXWindowCreated")
    state.spaces_watcher.callback(); local after_first = state.topology_calls; state.spaces_watcher.callback()
    equal(#events(observer, "active_space_known_window_sweep_end"), 1); local coalesced = events(observer, "active_space_callback_coalesced")
    equal(#coalesced, 1); equal(coalesced[1].result, "duplicate_active_space"); equal(state.topology_calls, after_first)
    observer:stop()
  end,
  ["POC-001 Ctrl-Option-Command-B one-shot target-binding hotkey deletes before binding the actual focused cached window"] = function()
    local window, application = fake_window(8041, complete_metadata()), fake_application(641, {})
    local state = install_fake_hs({ application }); install_fake_hotkey(state)
    install_fake_spaces(state, { ["8041"] = { 10 }, reverse = { ["10"] = { 8041 } } })
    hs.window.focusedWindow = function()
      assert(state.hotkeys[1].deleted, "one-shot hotkey must delete before focus is read")
      state.focused_calls = (state.focused_calls or 0) + 1
      return window
    end
    package.loaded.observer = nil
    local observer = require("observer").new(); assert(observer:start())
    application.watcher.callback(window, "AXWindowCreated")
    assert(observer:arm_target_action("move-sample", "manual_move_regular_space"))
    equal(observer:status().target_binding_armed, true)
    equal(state.hotkeys[1].key, "b"); equal(table.concat(state.hotkeys[1].modifiers, ","), "ctrl,alt,cmd")
    state.hotkeys[1].callback()
    equal(state.focused_calls, 1); assert(state.hotkeys[1].deleted); equal(observer:status().target_binding_armed, false)
    local action = events(observer, "action_begin")[1]
    equal(action.window, "win-001"); equal(action.space, "space-001"); equal(action.expected_source, "space-001")
    equal(events(observer, "action_target_binding_hotkey_result")[1].result, "success")
    equal(observer:status().window_effects, 0)
    observer:stop()
  end,
  ["POC-001 target binding rejects while armed or active and rearms only after completion"] = function()
    local known, unknown = fake_window(8042, complete_metadata()), fake_window(8043, complete_metadata())
    local application = fake_application(642, {})
    local state = install_fake_hs({ application }); install_fake_hotkey(state)
    install_fake_spaces(state, { ["8042"] = { 10 }, reverse = { ["10"] = { 8042 } } })
    hs.window.focusedWindow = function() return known end
    package.loaded.observer = nil
    local observer = require("observer").new(); assert(observer:start())
    application.watcher.callback(known, "AXWindowCreated")
    assert(observer:arm_target_action("move-sample", "close_temporary"))
    local armed, reason = observer:arm_target_action("move-sample", "close_temporary")
    equal(armed, false); equal(reason, "already_armed"); equal(#state.hotkeys, 1)
    state.hotkeys[1].callback()
    equal(observer:status().target_binding_armed, false); equal(#events(observer, "action_begin"), 1)
    local active, active_reason = observer:arm_target_action("move-sample", "close_temporary")
    equal(active, false); equal(active_reason, "prior_action_active"); equal(#state.hotkeys, 1)
    observer:mark("move-sample", "manual_visual_complete", "close_temporary")
    assert(observer:arm_target_action("move-sample", "close_temporary")); equal(#state.hotkeys, 2)
    hs.window.focusedWindow = function() return unknown end
    state.hotkeys[2].callback()
    equal(#events(observer, "action_begin"), 1)
    equal(events(observer, "action_target_binding_hotkey_result")[2].result, "aborted")
    equal(observer:status().window_effects, 0)
    observer:stop()
  end,
  ["POC-001 target-binding hotkey is deleted on stop and defensive failed-start cleanup"] = function()
    local state = install_fake_hs({}); install_fake_hotkey(state); install_fake_spaces(state)
    package.loaded.observer = nil
    local observer = require("observer").new(); assert(observer:start())
    assert(observer:arm_target_action("move-sample", "manual_move_regular_space"))
    observer:stop(); assert(state.hotkeys[1].deleted); equal(observer:status().target_binding_armed, false)

    local stale_state = {}
    local stale = { delete = function() stale_state.deleted = true end }
    observer.target_binding_hotkey = setmetatable(stale, { __newindex = function() error("userdata does not allow arbitrary fields") end })
    observer._start_spaces_watcher = function() error("forced startup failure") end
    local started = observer:start()
    equal(started, false); assert(stale_state.deleted); equal(observer:status().target_binding_armed, false)
  end,
  ["FOCUS-003 POC target binding queries focused once, uses cached identity, and never admits or effects"] = function()
    local window, application = fake_window(804, complete_metadata()), fake_application(64, {})
    local state = install_fake_hs({ application }); install_fake_spaces(state, { ["804"] = { 10 }, reverse = { ["10"] = { 804 } } }); hs.window.focusedWindow = function() state.focused_calls = (state.focused_calls or 0) + 1; return window end; package.loaded.observer = nil
    local observer = require("observer").new(); assert(observer:start()); application.watcher.callback(window, "AXWindowCreated")
    local facts_before = #events(observer, "window_ready_eligible"); assert(observer:begin_target_action("move-sample", "manual_move_regular_space"))
    equal(state.focused_calls, 1); equal(#events(observer, "action_begin"), 1); equal(events(observer, "action_begin")[1].window, "win-001"); equal(events(observer, "action_begin")[1].space, "space-001"); equal(#events(observer, "window_ready_eligible"), facts_before); equal(observer:status().window_effects, 0)
    observer:mark("move-sample", "sample_aborted", "operator_abort"); observer:stop()
  end,
  ["FOCUS-003 POC uncertain target binding rejects without admission or effects"] = function()
    local window, application = fake_window(805, complete_metadata()), fake_application(65, {})
    local state = install_fake_hs({ application }); install_fake_spaces(state); hs.window.focusedWindow = function() state.focused_calls = (state.focused_calls or 0) + 1; return window end; package.loaded.observer = nil
    local observer = require("observer").new(); assert(observer:start())
    local ok, reason = observer:begin_target_action("move-sample", "manual_move_regular_space")
    equal(ok, false); equal(reason, "target_uncertain"); equal(state.focused_calls, 1); equal(#events(observer, "action_begin"), 0); equal(#events(observer, "action_target_binding_rejected"), 1); equal(#events(observer, "window_ready_eligible"), 0); equal(observer:status().window_effects, 0)
    observer:stop()
  end,
  ["STATE-005 POC destruction candidates and paired diagnostic classify target versus non-target without confirmation"] = function()
    local first, second = fake_window(806, complete_metadata()), fake_window(807, complete_metadata())
    local application = fake_application(66, {}); local state = install_fake_hs({ application }); install_fake_spaces(state, { ["806"] = { 10 }, ["807"] = { 10 }, reverse = { ["10"] = { 806, 807 } } }); hs.window.focusedWindow = function() return first end; package.loaded.observer = nil
    local observer = require("observer").new(); assert(observer:start()); application.watcher.callback(first, "AXWindowCreated"); application.watcher.callback(second, "AXWindowCreated"); first.application = function() return application end; second.application = function() return application end
    assert(observer:begin_target_action("move-sample", "manual_move_regular_space")); second.watcher.callback(second, "AXUIElementDestroyed")
    first.watcher.callback(first, "AXUIElementDestroyed"); state.filter.subscriptions.windowDestroyed(first, nil, "windowDestroyed")
    local candidates, paired = events(observer, "destruction_candidate"), events(observer, "destruction_paired_candidate")
    equal(candidates[1].target_relation, "non_target"); equal(candidates[2].target_relation, "target"); equal(paired[1].target_relation, "target"); equal(#events(observer, "destruction_confirmed"), 0); observer:stop()
  end,
  ["DISC-002 POC metadata uses callback public methods without attributeValue and retains readiness across lifecycle-only reads"] = function()
    local metadata, window = complete_metadata(), fake_window(901, complete_metadata())
    local application = fake_application(59, {}); local state = install_fake_hs({ application }); package.loaded.observer = nil
    local observer = require("observer").new(); assert(observer:start()); application.watcher.callback(window, "AXWindowCreated")
    assert(window.attributeValue == nil); equal(#events(observer, "metadata_ready"), 1)
    metadata.native_fullscreen = true; window.isFullScreen = function() return metadata.native_fullscreen end
    window.watcher.callback(window, "AXWindowMoved")
    local move_fields = {}; for _, event in ipairs(events(observer, "metadata_field_observed")) do if event.raw_event == "AXWindowMoved" then move_fields[#move_fields + 1] = event.field end end
    equal(#move_fields, 2); assert(table.concat(move_fields, ","):find("native_fullscreen", 1, true))
    equal(#events(observer, "metadata_ready"), 1)
    observer:stop()
  end,
  ["POC-001 unavailable callback methods leave metadata uncertain without clearing cached readiness"] = function()
    local window, application = fake_window(902, complete_metadata()), fake_application(60, {})
    local state = install_fake_hs({ application }); package.loaded.observer = nil
    local observer = require("observer").new(); assert(observer:start()); application.watcher.callback(window, "AXWindowCreated")
    window.isMinimized = nil; window.watcher.callback(window, "AXWindowMoved")
    local uncertain = events(observer, "observation_fact"); local found = false
    for _, event in ipairs(uncertain) do if event.fact == "metadata_uncertain" and event.field == "minimized" then found = true end end
    assert(found); equal(#events(observer, "metadata_ready"), 1); observer:stop()
  end,
  ["POC-001 pairs direct and filter destruction candidates in either callback order without confirmation"] = function()
    local window, application = fake_window(903, complete_metadata()), fake_application(61, {})
    local state = install_fake_hs({ application }); package.loaded.observer = nil
    local observer = require("observer").new(); assert(observer:start()); application.watcher.callback(window, "AXWindowCreated"); window.application = function() return application end
    window.watcher.callback(window, "AXUIElementDestroyed"); state.filter.subscriptions.windowDestroyed(window, nil, "windowDestroyed")
    local paired = events(observer, "destruction_paired_candidate")
    equal(#paired, 1); equal(paired[1].target_relation, "no_active_target"); equal(#events(observer, "destruction_confirmed"), 0)
    local attached, detached = events(observer, "observation_fact"), false
    for _, event in ipairs(attached) do if event.fact == "window_watcher_detached" and event.reason == "element_destroyed" then detached = true end end
    assert(detached); observer:stop()
  end,
  ["POC-001 pairs filter then direct destruction candidates and callback context carries aliases"] = function()
    local window, application = fake_window(904, complete_metadata()), fake_application(62, {})
    local state = install_fake_hs({ application }); package.loaded.observer = nil
    local observer = require("observer").new(); assert(observer:start()); application.watcher.callback(window, "AXWindowCreated"); window.application = function() return application end
    state.filter.subscriptions.windowDestroyed(window, nil, "windowDestroyed"); window.watcher.callback(window, "AXUIElementDestroyed")
    equal(#events(observer, "destruction_paired_candidate"), 1)
    local enter, exit; for _, event in ipairs(events(observer, "callback_enter")) do if event.source == "direct_ax_window" and event.raw_event == "AXUIElementDestroyed" then enter = event end end
    for _, event in ipairs(events(observer, "callback_exit")) do if event.source == "direct_ax_window" and event.raw_event == "AXUIElementDestroyed" then exit = event end end
    assert(enter and enter.app == "app-001" and enter.window == "win-001")
    assert(exit and exit.app == "app-001" and exit.window == "win-001")
    observer:stop()
  end,
  ["POC-001 userdata-like direct watchers retain context in a Lua record and clean up"] = function()
    local watcher, watcher_state = userdata_like_watcher()
    local window = fake_window(502, complete_metadata())
    window.newWatcher = function() return watcher end
    local application = fake_application(65, { window })
    install_fake_hs({ application }); package.loaded.observer = nil
    local observer = require("observer").new()
    assert(observer:start())
    local record
    for _, candidate in pairs(observer.window_watchers) do record = candidate end
    assert(record and record.watcher == watcher)
    equal(record.app, "app-001"); equal(record.window, "win-001")
    equal(observer:status().direct_window_watchers, 1)
    observer:stop()
    assert(watcher_state.started and watcher_state.stopped)
    local detached = false
    for _, event in ipairs(events(observer, "observation_fact")) do
      if event.fact == "window_watcher_detached" then
        detached = event.app == "app-001" and event.window == "win-001" and event.reason == "observer_stop"
      end
    end
    assert(detached); equal(observer:status().direct_window_watchers, 0)
  end,
  ["POC-001 failed startup transaction cleans every already-created observer watcher"] = function()
    local window = fake_window(503, complete_metadata())
    local application = fake_application(66, { window })
    local state = install_fake_hs({ application }); install_fake_spaces(state)
    package.loaded.observer = nil
    local observer = require("observer").new()
    observer._start_spaces_watcher = function() error("forced final startup stage failure") end
    local started, startup_error = observer:start()
    equal(started, false); assert(startup_error:find("startup_failed:", 1, true))
    equal(observer:status().lifecycle, "stopped")
    equal(observer:status().direct_application_watchers, 0); equal(observer:status().direct_window_watchers, 0)
    assert(state.filter.unsubscribed and state.filter.deleted); assert(state.application_watcher.stopped)
    assert(application.watcher.stopped); assert(window.watcher.stopped)
    local failed = false
    for _, event in ipairs(events(observer, "observation_fact")) do
      if event.fact == "observer_start_failed" and event.reason == "startup_error" then failed = true end
    end
    assert(failed)
  end,
  ["POC-001 fixture correlation performs exactly one scoped construction and AXIdentifier read"] = function()
    local window = fake_window(990, complete_metadata())
    local application = fake_application(90, {}, "local.poc001.fixture")
    window.application = function() return application end
    local state = install_fake_hs({}); package.loaded.observer = nil
    local reads, constructions = 0, 0
    hs.hash = { SHA256 = function(raw)
      equal(raw, "corr-AAAAAAAAAAAAAAAA")
      return "83687efb86d2554f0547e44f7790efc5cc14b07af1ad8447ebb2d270cc6d7eac"
    end }
    hs.axuielement = { windowElement = function(callback_window)
      equal(callback_window, window); constructions = constructions + 1
      return { attributeValue = function(_, name) equal(name, "AXIdentifier"); reads = reads + 1; return "corr-AAAAAAAAAAAAAAAA" end }
    end }
    local observer = require("observer").new(); assert(observer:start()); assert(observer:arm_fixture_correlation(1))
    state.filter.subscriptions.windowCreated(window, nil, "windowCreated")
    state.filter.subscriptions.windowCreated(window, nil, "windowCreated")
    equal(constructions, 1); equal(reads, 1)
    equal(observer:status().query_counters.steady.correlation_window_element_construction, 1)
    equal(observer:status().query_counters.steady.correlation_ax_identifier_read, 1)
    local matched = events(observer, "correlation_observed"); equal(#matched, 1)
    equal(matched[1].correlation_alias, "poc001-corr-sha256-83687efb86d2554f0547e44f7790efc5cc14b07af1ad8447ebb2d270cc6d7eac")
    local rendered = require("trace").encode_json(observer.trace:export_table())
    assert(not rendered:find("corr-AAAAAAAAAAAAAAAA", 1, true)); assert(not rendered:find("990", 1, true))
    observer:stop()
  end,
  ["POC-001 fixture correlation scopes by exact bundle and clears aliases on destruction stop and failed startup"] = function()
    local window = fake_window(991, complete_metadata())
    local foreign = fake_application(91, {}, "not.the.fixture")
    window.application = function() return foreign end
    local state = install_fake_hs({}); package.loaded.observer = nil
    local constructions = 0
    hs.hash = { SHA256 = function() return "83687efb86d2554f0547e44f7790efc5cc14b07af1ad8447ebb2d270cc6d7eac" end }
    hs.axuielement = { windowElement = function() constructions = constructions + 1; error("must not construct") end }
    local observer = require("observer").new(); assert(observer:start()); assert(observer:arm_fixture_correlation(1))
    state.filter.subscriptions.windowCreated(window, nil, "windowCreated"); equal(constructions, 0)
    foreign.bundleID = function() return "local.poc001.fixture" end
    hs.axuielement.windowElement = function() constructions = constructions + 1; return { attributeValue = function() return "corr-AAAAAAAAAAAAAAAA" end } end
    state.filter.subscriptions.windowCreated(window, nil, "windowCreated")
    state.filter.subscriptions.windowDestroyed(window, nil, "windowDestroyed")
    local destroyed = events(observer, "destruction_candidate"); equal(destroyed[#destroyed].correlation_alias, "poc001-corr-sha256-83687efb86d2554f0547e44f7790efc5cc14b07af1ad8447ebb2d270cc6d7eac")
    assert(not observer.correlation:alias_for_window("991")); observer:stop(); assert(not observer.correlation:alias_for_window("991"))
  end,
  ["POC-001 fixture correlation unresolved callbacks consume the generation without prohibited fallback reads"] = function()
    local window = fake_window(992, complete_metadata())
    local application = fake_application(92, {}, "local.poc001.fixture")
    window.application = function() return application end
    local state = install_fake_hs({}); package.loaded.observer = nil
    local reads = 0
    hs.hash = { SHA256 = function() error("must not hash malformed token") end }
    hs.axuielement = { windowElement = function() return { attributeValue = function() reads = reads + 1; return "bad" end } end }
    local observer = require("observer").new(); assert(observer:start()); assert(observer:arm_fixture_correlation(1))
    state.filter.subscriptions.windowCreated(window, nil, "windowCreated"); state.filter.subscriptions.windowCreated(window, nil, "windowCreated")
    equal(reads, 1); equal(events(observer, "correlation_unresolved")[1].reason, "malformed")
    assert(observer:arm_fixture_correlation(2)); hs.axuielement.windowElement = function() error("construction fails") end
    state.filter.subscriptions.windowCreated(window, nil, "windowCreated")
    assert(observer:arm_fixture_correlation(3)); hs.axuielement.windowElement = function() return { attributeValue = function() error("read fails") end } end
    state.filter.subscriptions.windowCreated(window, nil, "windowCreated")
    local unresolved = events(observer, "correlation_unresolved")
    equal(unresolved[2].reason, "window_element_unavailable"); equal(unresolved[3].reason, "attribute_read_error")
    local source_text = assert(io.open(root .. "pocs/001-window-events-liveness/observer.lua")):read("*a")
    local correlation_source = assert(source_text:match("function Observer:_observe_fixture_correlation.-\nend\n\nfunction Observer:_start_filter"))
    for _, prohibited in ipairs({ "attributeNames", "allAttributeValues", "hs.window.find", "children", "timer", "runningApplications", "focusedWindow" }) do assert(not correlation_source:find(prohibited, 1, true), prohibited .. " is prohibited in correlation observer") end
    observer:stop()
  end,
  ["POC-001 cleanup removes observer-owned direct watchers"] = function()
    local window, application = fake_window(501, complete_metadata()), fake_application(55, {})
    local state = install_fake_hs({ application }); package.loaded.observer = nil
    local observer = require("observer").new(); assert(observer:start()); application.watcher.callback(window, "AXWindowCreated"); observer:stop()
    assert(state.filter.unsubscribed and state.filter.deleted); assert(state.application_watcher.stopped); assert(application.watcher.stopped); assert(window.watcher.stopped)
  end,
}
