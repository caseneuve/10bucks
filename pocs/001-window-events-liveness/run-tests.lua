local source = debug.getinfo(1, "S").source:sub(2)
local root = source:match("(.*/)pocs/") or "./"
package.path = root .. "pocs/001-window-events-liveness/?.lua;" .. package.path

local trace_suite = require("test_trace")
local observer_suite = require("test_observer")
local lifecycle_suite = require("test_lifecycle")
local suites = { trace_suite, lifecycle_suite, observer_suite }
local passed, failed = 0, 0
for _, suite in ipairs(suites) do
  for name, test in pairs(suite) do
  local ok, error_message = pcall(test)
  if ok then
    passed = passed + 1
    print("PASS " .. name)
  else
    failed = failed + 1
    io.stderr:write("FAIL " .. name .. "\n  " .. tostring(error_message) .. "\n")
  end
end
end
print(string.format("%d passed; %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
