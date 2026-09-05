-- POC-001 fail-closed private trace export. This module has no trace or observer dependency.
local PrivateExport = {}

local function shell_quote(value)
  return "'" .. value:gsub("'", "'\\\"'\\\"'") .. "'"
end

local function split_path(path)
  local directory, name = path:match("^(.+)/([^/]+)$")
  assert(directory and directory:sub(1, 1) == "/" and name and name ~= "", "export path must name a file in an explicitly chosen absolute directory")
  return directory, name
end

local function owner_private(attributes, uid)
  return attributes and attributes.mode == "directory" and attributes.uid == uid
    and type(attributes.permissions) == "string"
    and attributes.permissions:sub(4, 9) == "------"
end

local function default_ops()
  local function command_ok(command)
    local _, status = hs.execute(command, true)
    return status == true
  end
  local function current_uid()
    local environment_uid = tonumber(os.getenv("UID"))
    if environment_uid then return environment_uid end
    local output, status = hs.execute("/usr/bin/id -u", true)
    return status == true and tonumber(output:match("%d+")) or nil
  end
  return {
    attributes = function(path) return hs.fs.attributes(path) end,
    current_uid = current_uid,
    open = io.open,
    rename = os.rename,
    remove = os.remove,
    chmod_600 = function(path)
      -- /bin/chmod is fixed; the only variable is single-quote escaped.
      return command_ok("/bin/chmod 600 " .. shell_quote(path))
    end,
  }
end

function PrivateExport.write(path, content, supplied_ops)
  assert(type(path) == "string" and path:sub(1, 1) == "/", "export path must be an explicitly chosen absolute path")
  assert(type(content) == "string", "export content must be text")
  local ops = supplied_ops or default_ops()
  local directory, name = split_path(path)
  local uid = ops.current_uid()
  assert(uid ~= nil and owner_private(ops.attributes(directory), uid), "export destination directory must already be owner-private")

  local temporary = string.format("%s/.%s.poc001-%d-%d.tmp", directory, name, os.time(), math.random(0, 0x7fffffff))
  local function cleanup() pcall(function() ops.remove(temporary) end) end
  local ok, result = pcall(function()
    local file, err = ops.open(temporary, "w")
    assert(file, "cannot create private export temporary file: " .. tostring(err))
    local write_ok, write_err = file:write(content, "\n")
    if file.close then file:close() end
    assert(write_ok ~= nil, "cannot write private export temporary file: " .. tostring(write_err))
    assert(ops.chmod_600(temporary), "cannot enforce private export mode")
    local temporary_attributes = ops.attributes(temporary)
    assert(temporary_attributes and temporary_attributes.mode == "file" and temporary_attributes.uid == uid and temporary_attributes.permissions == "rw-------", "private export mode verification failed")
    assert(ops.rename(temporary, path), "cannot atomically replace export path")
    return path
  end)
  if not ok then cleanup(); error(result, 0) end
  return result
end

return PrivateExport
