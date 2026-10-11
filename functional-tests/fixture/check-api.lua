-- Run in real Hammerspoon, without launching fixture/window/manager/observer.
local source = debug.getinfo(1, 'S').source:sub(2)
local Mailbox = dofile(assert(source:match('^(.*/)')) .. 'mailbox.lua')
local temporary = os.tmpname()
os.remove(temporary) -- some Lua implementations create this file
local directory = temporary .. '-tenbucks-api'
assert(hs.fs.mkdir(directory))
local checks = 0
local function check(value)
    assert(value, 'API contract check failed')
    checks = checks + 1
end
local function readRaw()
    local f = assert(io.open(directory .. '/request.json'))
    local raw = f:read('*a'); f:close()
    return raw
end
local ok, failure = pcall(function()
    Mailbox.publish(directory, 'api-check', 1, 'create', 'A')
    local decoded = hs.json.read(directory .. '/request.json')
    check(decoded.run == 'api-check' and decoded.sequence == 1
        and decoded.operation == 'create' and decoded.alias == 'A')
    Mailbox.publish(directory, 'api-check', 2, 'create', 'B')
    check(hs.json.decode(readRaw()).alias == 'B')
    Mailbox.publish(directory, 'api-check', 3, 'quit', nil)
    local raw = readRaw()
    check(raw:match('"alias"%s*:%s*null') ~= nil)
    check(hs.json.decode(raw).sequence == 3)
    check(not pcall(hs.json.encode, 'A')) -- actual installed table-only contract
    check(not pcall(Mailbox.publish, directory, 'api-check', 4, 'create', 'C'))
    check(not pcall(Mailbox.publish, directory .. '/missing', 'api-check', 4, 'create', 'A'))
    check(hs.json.read(directory .. '/request.json').sequence == 3)
    -- Verify the real overloaded task constructor without starting a process.
    local task = hs.task.new('/usr/bin/true', function() end, {})
    check(task ~= nil and not task:isRunning())
    check(type(hs.timer.absoluteTime()) == 'number')
    check(hs.fs.attributes(directory, 'mode') == 'directory')
end)
os.remove(directory .. '/request.json.tmp')
os.remove(directory .. '/request.json')
assert(hs.fs.rmdir(directory))
if not ok then error(failure, 0) end
return {pass=true, checks=checks, processesStarted=0, windowsChanged=0}
