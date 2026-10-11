-- JSON/file boundary shared by proof and real-Hammerspoon contract check.
local M = {}

function M.publish(directory, run, sequence, operation, alias)
    assert(alias == nil or (type(alias)=='string' and alias:match('^[A-E]$')), 'unsupported_alias')
    local request = {run=run, sequence=sequence, operation=operation, alias=alias}
    local encoded = hs.json.encode(request) -- documented input: table, not scalar
    if alias == nil then
        -- Lua nil omits the key; the fixture requires an explicit JSON null.
        encoded = encoded:sub(1, -2) .. ',"alias":null}'
    end
    local path = directory .. '/request.json'
    local temporary = path .. '.tmp'
    local file = assert(io.open(temporary, 'w'))
    local ok, failure = pcall(function()
        assert(file:write(encoded))
        assert(file:close())
        assert(os.rename(temporary, path))
    end)
    if not ok then
        pcall(function() file:close() end)
        os.remove(temporary)
        error(failure, 0)
    end
end

return M
