-- Guest-only acceptance adapter. dofile returns API; start requires lead authority.
-- Host owns scenario/oracle, outer watchdog, settings/SIP/source-manifest preflight.
-- start {sourceRoot, executable, controlDir, run, outputDir, cleanSeedTerminal=false}.
-- outputDir: existing fresh private shared directory, outside new controlDir.
-- Timer atomically publishes status.json and observation.json every 50ms.
-- Host publishes action.json {sequence=1..N, operation=create/close/focusNext/
-- focusPrevious/stop, alias=A/B or omitted}. One request at a time; wait for matching
-- actionSequence + actionAccepted AND pending=false before another action.
-- accepted means submitted, never native completion. Host scenario is the oracle.
-- observation observed_at is guest publication time; do not restamp in host.
-- Initial readiness requires fixtureReady/candidateReady, columns, unknownMembers=0.
-- Overall 60s including cleanup (55s starts containment, 60s finalizes); host 100s
-- outer bound. Event-loop/AX stalls require lead's independent VM containment.
-- guest-result.json contains bounded 600-sample trace and separate cleanup diagnostics.
-- cleanSeedTerminal=true ONLY for runner-proved exclusively owned fresh clone:
-- exactly one app-local Terminal standard window/no foreign standard windows;
-- documented graceful kill(), then wait for process absence AND original AX false.
-- No baseline hiding, alias filtering, AX-close guessing or Space creation.
local M, s = {}, nil
local function now() return hs.timer.absoluteTime()/1e9 end
local function exists(p) return hs.fs.attributes(p) ~= nil end
local function copy(v)
    if type(v)~='table' then return v end
    local r={}; for k,value in pairs(v) do r[k]=copy(value) end; return r
end
local function atomic(path,value)
    local f=assert(io.open(path..'.tmp','w'))
    assert(f:write(hs.json.encode(value))); assert(f:close())
    assert(os.rename(path..'.tmp',path))
end
local function claimsAbsent()
    return not exists(s.dir..'/request.json') and not exists(s.dir..'/processing.json')
end
local function captureFailure(err)
    local allowed={'foreign_standard_baseline','unexpected_seed_baseline','seed_not_standard',
        'candidate_modules_already_loaded','initial_managed_scope_not_empty','regular_space_required',
        'unlocked_console_required','loginwindow_frontmost','loginwindow_focused','accessibility_required'}
    for _,code in ipairs(allowed) do
        if tostring(err):find(code,1,true) then return code end
    end
    return 'unexpected_startup_exception'
end
local function failure(code)
    s.error = s.error or code
    if s.phase ~= 'cleanup' then s.phase='cleanup'; s.cleanupAt=now() end
end
local function publish(op, alias)
    assert(not s.pending and claimsAbsent(), 'mailbox_busy')
    local sequence = s.sequence+1
    s.mailbox.publish(s.dir,s.run,sequence,op,alias)
    s.sequence=sequence
    s.pending={operation=op,alias=alias,deadline=now()+3}
    return {run=s.run,sequence=sequence,operation=op,alias=alias,accepted=true,submitted_at=now()}
end
local function chord(mods,key)
    local ordered=copy(mods); table.sort(ordered)
    return table.concat(ordered,'+')..':'..key
end
local function key(name)
    local binding=assert(s.chords[name], 'unknown_hotkey')
    hs.eventtap.event.newKeyEvent(binding[1],binding[2],true):post()
    hs.eventtap.event.newKeyEvent(binding[1],binding[2],false):post()
    s.keyPending={name=name,before=s.receipts[name] or 0,deadline=now()+3}
end
local function candidateSnapshot()
    local c=s.candidate and s.candidate.core
    local managed, unknown, diagnostics={},0,{}
    if c then
        local state=c:state()
        for id in pairs(state.manager.windows) do
            local alias=s.byId[id]
            if alias then managed[#managed+1]=alias else unknown=unknown+1 end
        end
        local coord=state.coordinators[c.spaceId]
        if coord then
            diagnostics.layout=coord.activeLayoutId
            local layout=coord.layouts[coord.activeLayoutId]
            diagnostics.selection=s.byId[layout.selectedId]
            diagnostics.selections={}
            for _, stack in ipairs(layout.stacks or {}) do
                diagnostics.selections[#diagnostics.selections+1]=s.byId[stack.selectedId] or 'unknown'
            end
        end
        local desired=state.manager.focus.desiredBySpace[c.spaceId]
        diagnostics.desired=desired and s.byId[desired.targetId]
        diagnostics.pending=desired and desired.pending or false
    end
    table.sort(managed)
    return managed,unknown,diagnostics
end
local function join(alias,number)
    local app=hs.application.applicationForPID(s.pid)
    if not app then return false end
    local matched
    for _, w in ipairs(app:allWindows()) do
        local owner=w:application()
        if w:id()==number and owner and owner:pid()==s.pid then
            assert(not matched,'ambiguous_join'); matched=w
        end
    end
    if not matched then return false end
    local ax=hs.axuielement.windowElement(matched)
    assert(ax:pid()==s.pid and ax:isValid()==true,'invalid_join')
    assert(ax:attributeValue('AXRole')=='AXWindow'
        and ax:attributeValue('AXSubrole')=='AXStandardWindow'
        and ax:isAttributeSettable('AXPosition')==true
        and ax:isAttributeSettable('AXSize')==true,'fixture_not_standard')
    s.windows[alias]=matched; s.axes[alias]=ax; s.byId[number]=alias
    if not s.observer then
        s.observer=hs.axuielement.observer.new(s.pid)
        s.observer:callback(function(_,element,notification)
            if notification=='AXUIElementDestroyed' then
                for a,original in pairs(s.axes) do if element==original then s.destroyed[a]=true end end
            end
        end)
    end
    s.observer:addWatcher(ax,'AXUIElementDestroyed')
    local registered=false
    for _, n in ipairs(s.observer:watching(ax)) do if n=='AXUIElementDestroyed' then registered=true end end
    assert(registered,'observer_registration_failed')
    s.observer:start(); assert(s.observer:isRunning(),'observer_not_running')
    return true
end
local function drain()
    local ack=hs.json.read(s.dir..'/ack.json')
    if not ack or ack.run~=s.run or ack.sequence~=s.sequence then return end
    local pending=s.pending
    local expected=pending and pending.operation or 'ready'
    assert(ack.pid==s.pid and ack.operation==expected and ack.accepted==true,'ack_mismatch')
    assert(not pending or not pending.alias or ack.alias==pending.alias,'ack_alias_mismatch')
    assert(claimsAbsent(),'ack_before_cleanup')
    if pending and pending.operation=='create' then
        assert(type(ack.windowNumber)=='number','missing_native_number')
        if not join(pending.alias,ack.windowNumber) then return end
    end
    s.lastAck={sequence=ack.sequence,operation=expected,alias=pending and pending.alias,processed_at=now()}
    s.pending=nil
    if expected=='ready' then s.ready=true end
    if expected=='quit' then s.quitAck=true end
end
local function sample()
    local sampledAt=now()
    local timings={} -- acquisition starts before any focus/AX/native frame reads
    local frames,closed={},{}
    local focused=hs.window.focusedWindow()
    timings.focus=now()-sampledAt
    local focusedAlias
    for alias,w in pairs(s.windows) do
        local aliasStarted=now()
        local ax=s.axes[alias]
        if s.destroyed[alias] or ax:isValid()==false then closed[#closed+1]=alias
        elseif ax:isValid()==true then
            local f=w:frame(); frames[alias]={x=f.x,y=f.y,w=f.w,h=f.h}
            local owner=focused and focused:application()
            if focused==w and owner and owner:pid()==s.pid then focusedAlias=alias end
        end
        timings[alias]=now()-aliasStarted
    end
    table.sort(closed)
    local snapshotStarted=now()
    local managed,unknown,diagnostics=candidateSnapshot()
    timings.snapshot=now()-snapshotStarted
    local bar=s.candidate and s.candidate.bar
    local barFacts={requested=bar and bar.presentation and bar.presentation.visible or false,
        showing=bar and bar.canvas and bar.canvas:isShowing() or false,
        handoff=bar and bar.handoff or false,frame=bar and copy(bar.frame)}
    s.sampleId=s.sampleId+1
    s.latest={sample_id=s.sampleId,sampled_at=sampledAt,frames=frames,closed=closed,
        focused=focusedAlias,managed=managed,commands_received=copy(s.receipts),
        unknownMembers=unknown,diagnostics=diagnostics,nativeDebug=copy(s.nativeDebug),
        timings=timings,bar=barFacts}
    s.latest.observed_at=now() -- guest publication clock; host must not restamp
    atomic(s.outputDir..'/observation.json',s.latest)
    s.trace[#s.trace+1]=copy(s.latest)
    if #s.trace>600 then table.remove(s.trace,1); s.dropped=s.dropped+1 end
end
local function finalize()
    if s.timer then s.timer:stop(); s.timer=nil end
    local observerStopped=true
    if s.observer then
        local ok,result=pcall(function() s.observer:stop(); return not s.observer:isRunning() end)
        observerStopped=ok and result
    end
    s.cleanup.observerStopped=observerStopped
    s.cleanup.timerStopped=s.timer==nil
    s.cleanup.bindWrapperRestored=hs.hotkey.bind==s.originalBind
    s.cleanup.taskStopped=not s.task or not s.task:isRunning()
    s.cleanup.normalExit=s.exitCode==0
    s.cleanup.callbackReceived=s.exitCode~=nil
    s.cleanup.claimsAbsent=claimsAbsent()
    s.cleanup.quitAcknowledged=s.quitAck==true
    s.cleanup.forced=s.forced==true
    s.cleanup.ok=s.cleanup.candidateStopped and observerStopped and s.cleanup.bindWrapperRestored
        and s.cleanup.taskStopped and s.cleanup.normalExit and s.cleanup.callbackReceived
        and s.cleanup.claimsAbsent and s.cleanup.quitAcknowledged and not s.cleanup.forced
    if not s.cleanup.ok then s.cleanup.error=s.cleanup.error or 'cleanup_incomplete' end
    s.running=false
    local result={error=s.error,cleanup=s.cleanup,trace=s.trace,dropped=s.dropped,
        workArea=s.workArea,settings=s.settings,failedOperation=s.failedOperation,baseline=s.baselineFacts}
    local ok=pcall(atomic,s.outputDir..'/guest-result.json',result)
    if not ok then s.cleanup.error='result_write_failed'; s.cleanup.ok=false end

end
local function cleanupTick()
    if not s.cleanup.candidateStopAttempted then
        s.cleanup.candidateStopAttempted=true
        s.cleanup.candidateStopped=not s.candidate or pcall(function()
            s.candidate:stop()
            assert(not s.candidate.started and #s.candidate.hotkeyBindings==0,'candidate_still_started')
        end)
        if not s.cleanup.candidateStopped then s.cleanup.error='candidate_stop_failed' end
    end
    if s.pending or not s.ready then drain() end -- even when the task already exited
    if s.task and s.task:isRunning() and not s.pending and not s.quitAck and s.ready then publish('quit') end
    if (now()-s.cleanupAt>=3 or now()-s.started>=60) and s.task and s.task:isRunning() and not s.forced then
        s.forced=true; s.task:terminate()
    end
    if not s.task or s.exitCode~=nil or now()-s.cleanupAt>=5 or now()-s.started>=60 then
        if s.task and s.task:isRunning() and not s.forced then s.forced=true; s.task:terminate() end
        finalize()
    end
end
local bootstrap
local function tick()
    if now()-s.started>=55 and s.phase~='cleanup' then failure('overall_timeout') end
    if s.phase=='baseline' then
        local exited=true
        for _,seed in ipairs(s.seeds) do
            -- Baseline isolation requires the owning setup processes to exit.
            -- AX invalidity is recorded separately, not an extra exit condition.
            seed.processExited=hs.application.applicationForPID(seed.pid)==nil
            seed.axInvalid=seed.ax:isValid()==false
            if not seed.processExited then exited=false end
        end
        s.baselineFacts.processesExited=exited
        if exited then
            s.settings.cleanedSeedTerminal=true
            bootstrap(); s.phase='ready'; s.readyDeadline=now()+3
        elseif now()>s.baselineDeadline then failure('seed_terminal_exit_timeout') end
        return
    end
    if s.phase=='cleanup' then cleanupTick(); return end
    if s.exitCode~=nil then failure('unexpected_fixture_exit'); return end
    if s.pending or not s.ready then drain() end
    if s.pending and now()>s.pending.deadline then failure('request_or_join_timeout'); return end
    if not s.ready and now()>s.readyDeadline then failure('ready_timeout'); return end
    if s.keyPending then
        local p=s.keyPending
        if (s.receipts[p.name] or 0)>p.before then
            s.keyPending=nil
            if s.phase=='columns' then
                local _,unknown,d=candidateSnapshot()
                if d.layout~='columns' or unknown~=0 then failure('columns_baseline_failed')
                else s.phase='active' end
            end
        elseif now()>p.deadline then failure('hotkey_receipt_timeout') end
    end
    if s.ready and s.phase=='ready' then s.phase='columns'; key('cycleLayout') end
    sample()
end
bootstrap=function()
    s.candidate=dofile(s.sourceRoot..'/10bucks.spoon/init.lua').new()
    s.candidate:configure({builtInDisplayUUID=s.screen:getUUID()})
    local submit=s.candidate._submitEvent
    s.nativeDebug={ready=0,normalizedReady=0,metadataMissing=0}
    s.candidate._submitEvent=function(candidate,event,...)
        if event.type=='WindowReady' then
            s.nativeDebug.normalizedReady=s.nativeDebug.normalizedReady+1
            s.nativeDebug.lastReady={action=event.decision and event.decision.action,
                reason=event.decision and event.decision.reason,
                activeSpace=event.spaceId==candidate.context.regularSpaceId,origin=event.metadata and event.metadata.origin,
                fixture=event.application and event.application.bundleID=='dev.10bucks.functional-fixture',
                role=event.metadata and event.metadata.role,subrole=event.metadata and event.metadata.subrole}
            s.nativeDebug.readyEvents=s.nativeDebug.readyEvents or {}
            s.nativeDebug.readyEvents[#s.nativeDebug.readyEvents+1]=s.nativeDebug.lastReady
        end
        local accepted=submit(candidate,event,...)
        if event.type=='WindowReady' then s.nativeDebug.lastAccepted=accepted end
        return accepted
    end
    local names={}
    for name,b in pairs(s.candidate.config.hotkeys) do
        if b~=false then names[chord(b[1],b[2])]=name; s.chords[name]=copy(b) end
    end
    hs.hotkey.bind=function(mods,k,pressed,...)
        local name=assert(names[chord(mods,k)],'unexpected_startup_binding')
        return s.originalBind(mods,k,function(...)
            s.receipts[name]=(s.receipts[name] or 0)+1
            return pressed(...)
        end,...)
    end
    local ok,err=pcall(function() s.candidate:start() end)
    hs.hotkey.bind=s.originalBind
    assert(ok,err)
    local host=s.candidate.host
    local ready=host._ready
    host._ready=function(h,...)
        s.nativeDebug.ready=s.nativeDebug.ready+1
        return ready(h,...)
    end
    local metadata=host._metadata
    host._metadata=function(h,...)
        local value=metadata(h,...)
        if not value then s.nativeDebug.metadataMissing=s.nativeDebug.metadataMissing+1
        else s.nativeDebug.lastMetadata={role=value.role,subrole=value.subrole,
            modal=value.modal,movable=value.movable,resizable=value.resizable,
            minimized=value.minimized,appHidden=value.appHidden,origin=value.origin} end
        return value
    end
    local _,unknown=candidateSnapshot()
    assert(s.candidate.context and s.candidate.context.regularSpaceId~=nil
        and not s.candidate.suspended,'regular_space_required')
    assert(s.candidate.core and unknown==0,'initial_managed_scope_not_empty')
    local owner=s
    s.task=hs.task.new(s.executable,function(code) owner.exitCode=code end,
        {'--run',s.run,'--control-dir',s.dir})
    assert(s.task and s.task:start(),'fixture_start_failed'); s.pid=s.task:pid()
end
local function baseline(clean)
    s.operation='enumerate_baseline'
    s.baselineFacts={standard=0,terminalWindows=0,foreignStandard=0,quitRequested=false}
    local count=0
    s.seeds={}
    local allowed={['com.apple.Terminal']=true,['com.apple.systempreferences']=true}
    local apps={}
    for _,app in ipairs(hs.application.runningApplications()) do
        local standard={}
        for _,w in ipairs(app:allWindows()) do
            if w:isStandard() then standard[#standard+1]=w end
        end
        if #standard>0 then
            count=count+#standard
            s.baselineFacts.standard=count
            if not allowed[app:bundleID()] then
                s.baselineFacts.foreignStandard=s.baselineFacts.foreignStandard+#standard
                error('foreign_standard_baseline')
            end
            assert(#standard==1,'unexpected_seed_baseline')
            if app:bundleID()=='com.apple.Terminal' then s.baselineFacts.terminalWindows=#standard end
            local ax=hs.axuielement.windowElement(standard[1])
            assert(ax:attributeValue('AXRole')=='AXWindow'
                and ax:attributeValue('AXSubrole')=='AXStandardWindow','seed_not_standard')
            s.seeds[#s.seeds+1]={pid=app:pid(),ax=ax}
            -- Keep handles/IDs private; only primitive exit facts are exported.
            apps[#apps+1]=app
        end
    end
    if clean and count>0 then
        s.operation='request_seed_quit'
        for _,app in ipairs(apps) do app:kill() end -- only identified owned-clone setup apps
        s.baselineFacts.quitRequested=true
        s.phase='baseline'; s.baselineDeadline=now()+3
    else
        assert(count==0,'baseline_not_empty')
        bootstrap()
    end
end
local function takeAction()
    local path=s.outputDir..'/action.json'
    if not exists(path) then return end
    local claim=s.outputDir..'/action.processing.json'
    assert(not exists(claim),'unexpected_action_claim')
    assert(os.rename(path,claim),'action_claim_failed')
    local data=hs.json.read(claim)
    assert(os.remove(claim),'action_claim_cleanup_failed') -- only this successful claim
    local ok=type(data)=='table' and type(data.sequence)=='number'
        and data.sequence==s.actionSequence+1
    if not ok then s.actionAccepted=false; s.actionError='invalid_action_sequence'; return end
    s.actionSequence=data.sequence
    local success=pcall(function()
        if data.operation=='stop' then M.stop()
        else M.command(data.operation,data.alias) end
    end)
    s.actionAccepted=success; s.actionError=not success and 'action_rejected' or nil
end
local function publishStatus()
    atomic(s.outputDir..'/status.json',M.status())
end
function M.start(o)
    assert(not s or (not s.running and (not s.task or not s.task:isRunning())),'owned_run_unresolved')
    for _,name in ipairs({'sourceRoot','executable','controlDir','run','outputDir'}) do
        assert(type(o[name])=='string' and o[name]~='','missing_option')
        if name~='run' then assert(o[name]:sub(1,1)=='/','absolute_paths_required') end
    end
    assert(o.outputDir~=o.controlDir and o.outputDir:sub(1,#o.controlDir+1)~=o.controlDir..'/',
        'output_outside_control_required')
    assert(not exists(o.controlDir),'fresh_control_required')
    assert(hs.fs.attributes(o.outputDir,'mode')=='directory','output_directory_required')
    for _,file in ipairs({'status.json','observation.json','guest-result.json','action.json','action.processing.json'}) do
        assert(not exists(o.outputDir..'/'..file),'fresh_output_required')
    end
    assert(o.run:match('^[%w_-]+$') and #o.run<=128,'invalid_nonce')
    local screens=hs.screen.allScreens(); assert(#screens==1,'sole_screen_required')
    s={running=true,phase='ready',dir=o.controlDir,run=o.run,outputDir=o.outputDir,
        sourceRoot=o.sourceRoot,executable=o.executable,screen=screens[1],started=now(),
        sequence=0,actionSequence=0,windows={},axes={},byId={},destroyed={},receipts={},chords={},
        cleanup={},trace={},dropped=0,sampleId=0,readyDeadline=now()+3,originalBind=hs.hotkey.bind}
    local native,full=s.screen:frame(),s.screen:fullFrame()
    local top=math.max(native.y,full.y+32)
    s.workArea={x=native.x,y=top,w=native.w,h=math.max(0,native.h-(top-native.y))}
    s.settings={soleScreen=true,accessibility=hs.accessibilityState(),barStrip=32,
        cleanedSeedTerminal=false} -- SIP/settings/versions are independently verified by host
    local ok,startupError=pcall(function()
        s.operation='check_session'
        local properties=hs.caffeinate.sessionProperties()
        assert(properties and properties.kCGSSessionOnConsoleKey==true
            and properties.CGSSessionScreenIsLocked~=true,'unlocked_console_required')
        local front=hs.application.frontmostApplication()
        local focused=hs.window.focusedWindow()
        local focusedApp=focused and focused:application()
        assert(front and front:bundleID()~=nil
            and front:bundleID()~='com.apple.loginwindow'
            and (not focusedApp or (focusedApp:bundleID()~=nil
                and focusedApp:bundleID()~='com.apple.loginwindow')),'loginwindow_or_unknown_frontmost')
        s.settings.unlockedConsole=true
        assert(s.settings.accessibility,'accessibility_required')
        s.operation='load_mailbox'
        s.mailbox=dofile(o.sourceRoot..'/functional-tests/fixture/mailbox.lua')
        s.operation='check_modules'
        for name in pairs(package.loaded) do assert(not name:match('^lib%.'),'candidate_modules_already_loaded') end
        baseline(o.cleanSeedTerminal==true)
    end)
    hs.hotkey.bind=s.originalBind
    if not ok then
        s.failedOperation=s.operation
        failure(captureFailure(startupError))
    end
    s.timer=hs.timer.doEvery(0.05,function()
        local success=pcall(function()
            if s.phase~='cleanup' then takeAction() end
            tick()
            publishStatus()
        end)
        hs.hotkey.bind=s.originalBind
        if not success then
            failure('guest_controller_error')
            if now()-s.cleanupAt>=5 or now()-s.started>=60 then
                if s.task and s.task:isRunning() then s.forced=true; s.task:terminate() end
                finalize(); pcall(publishStatus)
            end
        end
    end)
    publishStatus()
    return M.status()
end
function M.command(op,alias)
    assert(s and s.running and s.phase=='active' and not s.error,'controller_not_active')
    assert(not s.pending and not s.keyPending,'action_pending')
    if op=='create' or op=='close' then
        assert(alias=='A' or alias=='B','unsupported_alias')
        if op=='create' then assert(not s.windows[alias],'alias_already_used')
        else assert(s.windows[alias],'alias_not_joined') end
        return publish(op,alias)
    end
    assert(alias==nil and (op=='focusNext' or op=='focusPrevious'),'unsupported_acceptance_command')
    key(op)
    return {accepted=true,operation=op,submitted_at=now()} -- receipt is ONLY callback count
end
function M.status()
    if not s then return {running=false,observed_at=now()} end
    local observation=s.latest and copy(s.latest)
    return {running=s.running,phase=s.phase,error=s.error,observation=observation,
        observed_at=now(),actionSequence=s.actionSequence,actionAccepted=s.actionAccepted,actionError=s.actionError,
        fixtureReady=s.ready==true,candidateReady=s.phase=='active',
        layout=observation and observation.diagnostics.layout,unknownMembers=observation and observation.unknownMembers,
        lastAck=copy(s.lastAck),pending=s.pending~=nil or s.keyPending~=nil,
        workArea=copy(s.workArea),settings=copy(s.settings),cleanup=copy(s.cleanup),
        failedOperation=s.failedOperation,baseline=s.baselineFacts,
        ownedTaskRunning=s.task~=nil and s.task:isRunning(),completionCallbackReceived=s.exitCode~=nil}
end
function M.stop()
    if s and s.running and s.phase~='cleanup' then s.phase='cleanup'; s.cleanupAt=now()
    elseif s and not s.running and s.task and s.task:isRunning() then s.task:terminate() end
    return M.status()
end
return M
