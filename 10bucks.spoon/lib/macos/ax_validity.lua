-- One pinned native image per process/version. Build native/build.sh before load.
-- No synchronous fallback: AX queries run exclusively on the serial worker.
local M = {}
local native
function M.create()
  if not native then
    local source = debug.getinfo(1, "S").source:sub(2)
    local root = assert(source:match("^(.*)/lib/macos/ax_validity%.lua$"), "AX validity module path unavailable")
    native = assert(package.loadlib(root .. "/native/build/ax_validity.so", "luaopen_ax_validity"))()
  end
  return native.create()
end
return M
