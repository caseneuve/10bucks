-- Startup inventory and one finite worker; no synchronous AX scan fallback.
local M, native = {}, nil
function M.prepare()
  if native then return end
  local source = debug.getinfo(1, "S").source:sub(2)
  local root = assert(source:match("^(.*)/lib/macos/regular_discovery%.lua$"))
  native = assert(package.loadlib(root .. "/native/build/regular_discovery.so", "luaopen_regular_discovery"))()
end
function M.inventory() M.prepare(); return native.inventory() end
function M.create(targets) M.prepare(); return native.create(targets) end
return M
