local source = debug.getinfo(1, "S").source:sub(2)
local root = source:match("(.*/)tests/") or "./"
package.path = root .. "10bucks.spoon/?.lua;" .. package.path

local tests = {
  require("tests.test_model"),
  require("tests.test_runtime"),
  require("tests.test_rules"),
  require("tests.test_stack"),
  require("tests.test_columns"),
  require("tests.test_layout_coordinator"),
  require("tests.test_generated_sequences"),
  require("tests.test_state"),
  require("tests.test_geometry"),
  require("tests.test_config"),
  require("tests.test_bindings"),
  require("tests.test_focus_history"),
  require("tests.test_window_repository"),
  require("tests.test_window_chooser"),
  require("tests.test_workspaces"),
  require("tests.test_bar"),
  require("tests.test_lifecycle"),
  (require("tests.test_engine")),
}

local passed, failed = 0, 0
for _, suite in ipairs(tests) do
  for name, test in pairs(suite) do
    local ok, err = pcall(test)
    if ok then
      passed = passed + 1
      print("PASS " .. name)
    else
      failed = failed + 1
      io.stderr:write("FAIL " .. name .. "\n  " .. tostring(err) .. "\n")
    end
  end
end

print(string.format("%d passed; %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
