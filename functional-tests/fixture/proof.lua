-- Guest-only, no-manager proof. Loading this file does not launch anything.
local M, s = {}, nil
local function now() return hs.timer.absoluteTime() / 1e9 end
local function exists(path) return hs.fs.attributes(path) ~= nil end
local function atomic(path, value, raw)
    local f = assert(io.open(path .. '.tmp', 'w'))
    assert(f:write(raw and value or hs.json.encode(value)))
    assert(f:close())
    assert(os.rename(path .. '.tmp', path))
end
local function absentClaims()
    return not exists(s.dir .. '/request.json') and not exists(s.dir .. '/processing.json')
end
local function record(name, flags)
    s.result.steps[#s.result.steps + 1] = {step=name, seconds=now()-s.started, flags=flags or {}}
end
local function finish()
    if s.timer then s.timer:stop(); s.timer = nil end
    if s.observer then
        local ok, stopped = pcall(function()
            s.observer:stop()
            return not s.observer:isRunning()
        end)
        s.result.cleanup.observerStopped = ok and stopped
        s.observer = nil
    else s.result.cleanup.observerStopped = true end
    s.result.cleanup.taskStopped = not s.task or not s.task:isRunning()
    s.result.cleanup.normalExit = s.exitCode == 0
    s.result.cleanup.unresolved = s.task ~= nil
        and (s.task:isRunning() or s.exitCode == nil)
    s.result.cleanup.claimsAbsent = absentClaims()
    s.result.cleanup.quitAcknowledged = s.quitAck == true
    s.result.cleanup.forced = s.forced == true
    s.result.seconds = now()-s.started
    s.result.pass = not s.result.error and s.result.cleanup.taskStopped
        and s.result.cleanup.normalExit and s.result.cleanup.claimsAbsent
        and s.result.cleanup.quitAcknowledged and s.result.cleanup.observerStopped
        and not s.result.cleanup.forced and not s.result.cleanup.unresolved
    s.running = false
    local ok = pcall(atomic, s.resultPath, s.result)
    if not ok then
        s.result.resultWriteFailed = true
        s.result.pass = false
    end
    s.a, s.b, s.axA, s.axB = nil, nil, nil, nil
end
local function fail(code)
    s.result.error = s.result.error or code -- preserve first failure, never raw AX/errors
    if s.phase ~= 'cleanup' then
        s.phase = 'cleanup'
        s.cleanupStarted = now()
    end
end
local function send(operation, alias)
    assert(not s.pending and absentClaims(), 'mailbox_busy')
    assert(alias == nil or alias == 'A' or alias == 'B', 'unsupported_alias')
    local nextSequence = s.sequence + 1
    local envelope = hs.json.encode({run=s.run, sequence=nextSequence, operation=operation})
    -- hs.json.encode accepts tables only; aliases are a closed fixture alphabet.
    envelope = envelope:sub(1, -2) .. ',"alias":' .. (alias and ('"' .. alias .. '"') or 'null') .. '}'
    atomic(s.dir .. '/request.json', envelope, true)
    s.sequence = nextSequence -- publication succeeded before sequence advances
    s.pending = {operation=operation, alias=alias, deadline=now()+3}
    record(operation, {alias=alias})
end
local function ack()
    local data = hs.json.read(s.dir .. '/ack.json')
    if not data then return nil end
    if data.run ~= s.run or data.sequence ~= s.sequence then return nil end
    local expected = s.pending and s.pending.operation or 'ready'
    if data.operation ~= expected or data.pid ~= s.pid or data.accepted ~= true then
        fail('ack_rejected_or_mismatched'); return nil
    end
    if s.pending and s.pending.alias and data.alias ~= s.pending.alias then
        fail('ack_alias_mismatch'); return nil
    end
    if not absentClaims() then fail('ack_before_claim_cleanup'); return nil end
    s.pending = nil
    return data
end
local function join(data)
    if type(data.windowNumber) ~= 'number' then return nil end
    local app = hs.application.applicationForPID(s.pid)
    if not app then return nil end
    local matched
    for _, w in ipairs(app:allWindows()) do
        if w:id() == data.windowNumber and w:application():pid() == s.pid then
            assert(not matched, 'ambiguous_join'); matched = w
        end
    end
    if not matched then return nil end
    local ax = hs.axuielement.windowElement(matched)
    assert(ax:pid() == s.pid and ax:isValid() == true, 'invalid_join')
    assert(ax:attributeValue('AXRole') == 'AXWindow'
        and ax:attributeValue('AXSubrole') == 'AXStandardWindow', 'nonstandard_window')
    assert(ax:isAttributeSettable('AXPosition') == true
        and ax:isAttributeSettable('AXSize') == true, 'not_movable_resizable')
    return matched, ax
end
local function focused(w)
    local actual = hs.window.focusedWindow()
    return actual ~= nil and actual == w and actual:application():pid() == s.pid
end
local function frameProof(alias, w)
    local f = w:frame()
    assert(f.w > 0 and f.h > 0, 'invalid_frame')
    local function matches(a, b)
        return math.abs(a.x-b.x)<=2 and math.abs(a.y-b.y)<=2
            and math.abs(a.w-b.w)<=2 and math.abs(a.h-b.h)<=2
    end
    local wrong = {x=f.x+100, y=f.y, w=f.w, h=f.h}
    assert(matches(f, f) and not matches(f, wrong), 'negative_frame_oracle_failed')
    record('native_frame', {alias=alias, frame={x=f.x,y=f.y,w=f.w,h=f.h},
        deliberatelyWrongRejected=true})
end
local function tick()
    local t = now()
    if t-s.started >= 24 and s.phase ~= 'cleanup' then fail('overall_proof_timeout') end
    if s.phase == 'cleanup' then
        -- Keep the pending sequence intact: wait for its ack before graceful quit.
        -- Drain the mailbox even after process exit; its callback may run later.
        if s.pending then
            local response = ack()
            if response and response.operation == 'quit' then s.quitAck = true end
        elseif s.task and s.task:isRunning() and not s.cleanupQuit and not s.quitAck
            and exists(s.dir) and absentClaims() then
            s.cleanupQuit = true; send('quit')
        end
        local running = s.task and s.task:isRunning()
        if running and (t-s.cleanupStarted >= 3 or t-s.started >= 29) and not s.forced then
            s.forced = true; s.task:terminate() -- ONLY this directly retained task
        end
        -- Wait for the completion callback, not merely isRunning()==false.
        -- The absolute deadline still wins, retaining the task handle if unresolved.
        if not s.task or s.exitCode ~= nil or t-s.started >= 29 then
            s.result.cleanup.unresolved = s.task ~= nil
                and (s.task:isRunning() or s.exitCode == nil)
            finish()
        end
        return
    end
    if s.exitCode ~= nil and s.phase ~= 'quit' and s.phase ~= 'exit' then
        fail('unexpected_process_exit'); return
    end
    if s.pending and t > s.pending.deadline then fail('ack_timeout'); return end
    if t > s.stepDeadline then fail('native_step_timeout'); return end
    local phase = s.phase
    if phase == 'ready' then
        if ack() then send('create', 'A'); s.phase = 'createA' end
    elseif phase == 'createA' or phase == 'createB' then
        s.createAck = s.createAck or ack()
        if s.createAck then
            local w, ax = join(s.createAck)
            if w then
                local alias = phase == 'createA' and 'A' or 'B'
                s[alias == 'A' and 'a' or 'b'] = w
                s[alias == 'A' and 'axA' or 'axB'] = ax
                record('joined', {alias=alias, standard=true, movable=true, resizable=true})
                frameProof(alias, w); s.createAck = nil
                send('focus', alias); s.phase = 'focus' .. alias
            end
        end
    elseif phase == 'focusA' or phase == 'focusB' then
        s.focusAck = s.focusAck or ack()
        local w = phase == 'focusA' and s.a or s.b
        if s.focusAck and focused(w) then
            record('native_focus', {alias=phase == 'focusA' and 'A' or 'B', confirmed=true})
            s.focusAck = nil
            if phase == 'focusA' then send('create', 'B'); s.phase = 'createB'
            else
                s.observer = hs.axuielement.observer.new(s.pid)
                s.observer:callback(function(_, element, notification)
                    if element == s.axB and notification == 'AXUIElementDestroyed' then s.destroyed = true end
                end)
                s.observer:addWatcher(s.axB, 'AXUIElementDestroyed')
                local registered = false
                for _, n in ipairs(s.observer:watching(s.axB)) do
                    if n == 'AXUIElementDestroyed' then registered = true end
                end
                assert(registered, 'destruction_registration_failed')
                s.observer:start(); assert(s.observer:isRunning(), 'observer_not_running')
                record('observer_registered', {alias='B', registered=true})
                send('close', 'B'); s.phase = 'closeB'
            end
        end
    elseif phase == 'closeB' then
        s.closeAck = s.closeAck or ack()
        local invalid = s.axB:isValid() == false
        if s.closeAck and (invalid or s.destroyed) then
            assert(s.axA:isValid() == true and s.task:isRunning(), 'survivor_or_app_not_alive')
            record('native_close', {alias='B', invalid=invalid, matchingDestruction=s.destroyed == true,
                survivorValid=true, appAlive=true})
            send('quit'); s.phase = 'quit'
        end
    elseif phase == 'quit' then
        if ack() then s.quitAck = true; s.phase = 'exit' end
    elseif phase == 'exit' then
        if s.exitCode ~= nil then
            if s.exitCode ~= 0 then fail('abnormal_exit') else finish() end
        end
    end
    if phase ~= s.phase then s.stepDeadline = t+3 end
end
function M.start(options)
    assert(not s or not s.running, 'proof_already_running')
    for _, key in ipairs({'executable','controlDir','run','resultPath'}) do
        assert(type(options[key]) == 'string' and options[key] ~= '', 'missing_option')
    end
    assert(options.executable:sub(1,1)=='/' and options.controlDir:sub(1,1)=='/'
        and options.resultPath:sub(1,1)=='/', 'absolute_paths_required')
    assert(options.run:match('^[%w_-]+$') and #options.run <= 128, 'invalid_run_nonce')
    assert(not exists(options.controlDir), 'control_directory_must_be_new')
    assert(not exists(options.resultPath), 'result_path_must_be_new')
    assert(options.resultPath:sub(1,#options.controlDir+1) ~= options.controlDir .. '/', 'result_outside_control_directory')
    s = {running=true, dir=options.controlDir, run=options.run, resultPath=options.resultPath,
        sequence=0, phase='ready', started=now(), result={steps={},cleanup={}}}
    s.stepDeadline = s.started+3
    local owner = s
    s.task = hs.task.new(options.executable, function(code)
        owner.exitCode = code -- never export stdout/stderr/private native values
    end, {'--run',options.run,'--control-dir',options.controlDir})
    if not s.task or not s.task:start() then fail('task_start_failed'); finish(); return M.status() end
    s.pid = s.task:pid()
    s.timer = hs.timer.doEvery(0.05, function()
        local ok = pcall(tick)
        if not ok then
            s.result.failedPhase = s.result.failedPhase or s.phase
            fail('controller_error')
            if now()-s.started >= 29 then
                if s.task and s.task:isRunning() then s.forced = true; s.task:terminate() end
                finish()
            end
        end
    end)
    return M.status()
end
function M.status()
    if not s then return {running=false} end
    return {running=s.running, phase=s.phase,
        ownedTaskRunning=s.task ~= nil and s.task:isRunning(),
        completionCallbackReceived=s.exitCode ~= nil,
        result=hs.fnutils.copy(s.result)}
end
function M.stop()
    if s and s.running then fail('operator_stopped')
    elseif s and s.task and s.task:isRunning() then
        s.forced = true
        s.task:terminate() -- unresolved directly-owned task remains available to operator
    end
    return M.status()
end
return M
