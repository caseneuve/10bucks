local source = debug.getinfo(1, "S").source:sub(2)
local root = source:match("(.*/)pocs/") or "./"
package.path = root .. "pocs/001-window-events-liveness/?.lua;" .. package.path

local PrivateExport = require("private_export")

local function ops_for(attributes, behavior)
  behavior, attributes = behavior or {}, attributes or {}
  local files, removed = {}, {}
  local ops = {
    current_uid = function() return 501 end,
    attributes = function(path) return attributes[path] or files[path] end,
    open = function(path)
      if behavior.open_fails then return nil, "open failed" end
      local file = { content = "" }
      files[path] = file
      function file:write(...) for _, content in ipairs({ ... }) do self.content = self.content .. content end; return true end
      function file:close() self.closed = true end
      return file
    end,
    chmod_600 = function(path)
      if behavior.chmod_fails then return false end
      files[path].mode, files[path].uid, files[path].permissions = "file", 501, behavior.bad_mode and "rw-r--r--" or "rw-------"
      return true
    end,
    rename = function(from, to)
      if behavior.rename_fails then return false end
      files[to], files[from] = files[from], nil
      return true
    end,
    remove = function(path) removed[path], files[path] = true, nil; return true end,
  }
  return ops, files, removed
end

local function private_directory() return { mode = "directory", uid = 501, permissions = "rwx------" } end

return {
  ["POC-001 export rejects missing or non-private destination directories before creating a file"] = function()
    for _, attributes in ipairs({ {}, { ["/private"] = { mode = "directory", uid = 501, permissions = "rwxr-xr-x" } } }) do
      local ops, files = ops_for(attributes)
      assert(not pcall(function() PrivateExport.write("/private/trace.json", "{}", ops) end))
      assert(next(files) == nil)
    end
  end,
  ["POC-001 export removes its temporary file when chmod or mode verification fails"] = function()
    for _, behavior in ipairs({ { chmod_fails = true }, { bad_mode = true } }) do
      local ops, files, removed = ops_for({ ["/private"] = private_directory() }, behavior)
      assert(not pcall(function() PrivateExport.write("/private/trace.json", "{}", ops) end))
      assert(next(removed) ~= nil)
      assert(files["/private/trace.json"] == nil)
    end
  end,
  ["POC-001 export atomically replaces final output only after verified private temp mode"] = function()
    local ops, files = ops_for({ ["/private"] = private_directory(), ["/private/trace.json"] = { mode = "file", uid = 501, permissions = "rw-------", content = "old" } })
    local result = PrivateExport.write("/private/trace.json", "new", ops)
    assert(result == "/private/trace.json")
    assert(files["/private/trace.json"] and files["/private/trace.json"].content == "new\n")
  end,
}
