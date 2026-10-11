local source = debug.getinfo(1, "S").source:sub(2)
local root = source:match("(.*/)tests/") or "./"
package.path = root .. "10bucks.spoon/?.lua;" .. package.path

local tests = {
  require("tests.test_model"), require("tests.test_runtime"), require("tests.test_workspace_switch"), require("tests.test_rules"), require("tests.test_macos_windows"), require("tests.test_window_host"), require("tests.test_context"), require("tests.test_config_replacement"), require("tests.test_canary_instrumentation"),
  require("tests.test_geometry"), require("tests.test_stack"), require("tests.test_columns"),
  require("tests.test_layout_coordinator"), require("tests.test_generated_sequences"), require("tests.test_core"),
  require("tests.test_focus_sequences"), require("tests.test_focus_history"), require("tests.test_handle_registry"),
  (require("tests.test_integration_canary_a")), (require("tests.test_composition")), (require("tests.test_fullscreen_focus")),
  (require("tests.test_bar")),
}
local passed, failed = 0, 0
for _, suite in ipairs(tests) do
  for name, test in pairs(suite) do
    local ok, err = pcall(test)
    if ok then passed = passed + 1; print("PASS " .. name)
    else failed = failed + 1; io.stderr:write("FAIL " .. name .. "\n  " .. tostring(err) .. "\n") end
  end
end
print(string.format("%d passed; %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
