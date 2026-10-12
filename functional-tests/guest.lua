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
        'unlocked_console_required','loginwindow_frontmost','loginwindow_focused','accessibility_required',
        'three_existing_desktops_required','three_regular_desktops_required','initial_D1_required',
        'native_topology_unavailable','native_display_incomplete','native_display_unavailable'}
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
local syntheticModifiers={'cmd','alt','ctrl','shift'}
local function releaseSyntheticKeys()
    -- Guest-only controller. Empty flags + explicit modifier key-up emits the
    -- flagsChanged boundary; chord key-up alone leaves synthetic Hyper held.
    local released=true
    for key in pairs(s.syntheticKeys or {}) do
        local ok=pcall(function() hs.eventtap.event.newKeyEvent({},key,false):post() end)
        if ok then s.syntheticKeys[key]=nil else released=false end
    end
    for _,mod in ipairs(syntheticModifiers) do
        local ok=pcall(function() hs.eventtap.event.newKeyEvent({},mod,false):post() end)
        released=released and ok
    end
    return released -- submission only, not proof of observed keyboard flags
end
local function emitChord(mods,key)
    s.syntheticKeys=s.syntheticKeys or {}
    s.syntheticKeys[key]=true -- retain cleanup authority even if posting throws
    local ok,err=pcall(function()
        hs.eventtap.event.newKeyEvent(mods,key,true):post()
        hs.eventtap.event.newKeyEvent(mods,key,false):post()
        s.syntheticKeys[key]=nil
    end)
    local released=releaseSyntheticKeys()
    assert(ok,err)
    assert(released,'synthetic_key_release_failed')
end
local function postKey(name)
    local binding=assert(s.chords[name], 'unknown_hotkey')
    s.keyEvents[#s.keyEvents+1]={kind='posted',name=name,at=now()}
    emitChord(binding[1],binding[2])
end
local function keys(names)
    local expected={}
    for _,name in ipairs(names) do
        assert(s.chords[name], 'unknown_hotkey')
        expected[name]=(expected[name] or s.receipts[name] or 0)+1
    end
    s.keyPending={expected=expected,deadline=now()+3}
    -- All events posted in this callback, before yielding to the .3s AX timer.
    for _,name in ipairs(names) do postKey(name) end
end
local function key(name) keys({name}) end
local function desktopAlias(id)
    return id and (s.desktopAliases[id] or 'unknown') or nil
end
local function nativeDisplay()
    -- Independent direct native read, not Context/cache/desired/projection.
    for _,display in ipairs(assert(hs.spaces.data_managedDisplaySpaces(), 'native_topology_unavailable')) do
        if display['Display Identifier']==s.screen:getUUID() then
            assert(type(display.Spaces)=='table' and type(display['Current Space'])=='table', 'native_display_incomplete')
            return display
        end
    end
    error('native_display_unavailable')
end
local function nativeDesktop()
    local display=nativeDisplay()
    if s.desktopFullscreen and not s.fullscreenId and s.windows.A and s.windows.A:isFullScreen()==true then
        local owners=hs.spaces.windowSpaces(s.windows.A:id())
        if s.axes.A:isValid()==true and type(owners)=='table' and #owners==1 then
            for _,item in ipairs(display.Spaces) do
                if item.ManagedSpaceID==owners[1] and item.type==4 and not s.desktopAliases[owners[1]] then
                    s.fullscreenId=owners[1]; s.desktopAliases[owners[1]]='F1'
                end
            end
        end
    end
    local result={active=desktopAlias(display['Current Space'].ManagedSpaceID),order={},types={},regular={},count=#display.Spaces}
    for _,item in ipairs(display.Spaces) do
        local kind=item.type==0 and 'user' or item.type==4 and 'fullscreen' or 'unknown'
        local alias=desktopAlias(item.ManagedSpaceID)
        result.order[#result.order+1]=alias; result.types[#result.types+1]=kind
        if kind=='user' then result.regular[#result.regular+1]=alias end
    end
    return result
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
            local function aliases(ids)
                local result={}; for _,id in ipairs(ids or {}) do result[#result+1]=s.byId[id] or 'unknown' end
                return result
            end
            diagnostics.order=aliases(state.manager.spaces[c.spaceId].memberIds)
            diagnostics.layouts={}
            for name, saved in pairs(coord.layouts) do
                local row={}
                if name=='stack' then row.members=aliases(saved.members); row.selected=s.byId[saved.selectedId]
                else
                    row.groups={}; row.selected={}; row.active=saved.activeStack; row.ratio=saved.ratio
                    for _,group in ipairs(saved.stacks) do
                        row.groups[#row.groups+1]=aliases(group.members)
                        row.selected[#row.selected+1]=s.byId[group.selectedId] or 'unknown'
                    end
                end
                diagnostics.layouts[name]=row
            end
        end
        local desired=state.manager.focus.desiredBySpace[c.spaceId]
        diagnostics.desired=desired and s.byId[desired.targetId]
        diagnostics.pending=desired and desired.pending or false
    end
    if s.desktopSwitching then
        diagnostics.retained={}
        local active=s.candidate.core
        -- Read every Core, including inactive scopes; never activate/reflow to inspect.
        for id,core in pairs(s.candidate.cores or {}) do
            local state=core:state()
            local coord=state.coordinators[core.spaceId]
            local row={order={},layouts={},layout=coord and coord.activeLayoutId}
            if s.desktopFullscreen then
                row.nativeFullscreen={}; row.unavailable={}
                for wid,window in pairs(state.manager.windows) do
                    local alias=s.byId[wid] or 'unknown'
                    local life=window.lifecycle
                    if life.nativeFullscreen then row.nativeFullscreen[#row.nativeFullscreen+1]=alias end
                    if life.nativeFullscreen or life.minimized or life.appHidden then row.unavailable[#row.unavailable+1]=alias end
                end
                table.sort(row.nativeFullscreen); table.sort(row.unavailable)
            end
            local function aliases(ids)
                local result={}; for _,wid in ipairs(ids or {}) do
                    result[#result+1]=s.byId[wid] or 'unknown'
                end; return result
            end
            local scope=state.manager.spaces[core.spaceId]
            row.order=aliases(scope and scope.memberIds)
            for name,layout in pairs(coord and coord.layouts or {}) do
                if name=='stack' then row.layouts[name]={members=aliases(layout.members),selected=s.byId[layout.selectedId]}
                else
                    local saved={groups={},selected={},active=layout.activeStack,ratio=layout.ratio}
                    for _,group in ipairs(layout.stacks or {}) do
                        saved.groups[#saved.groups+1]=aliases(group.members)
                        saved.selected[#saved.selected+1]=s.byId[group.selectedId] or 'unknown'
                    end
                    row.layouts[name]=saved
                end
            end
            row.active=core==active
            diagnostics.retained[desktopAlias(id)]=row
            for wid in pairs(state.manager.windows) do
                if not s.byId[wid] and core~=active then unknown=unknown+1 end
            end
        end
        local runtime=assert(s.candidate.workspace, 'workspace_runtime_required')
        local state=runtime:state(); local op=state.switch.inFlight
        diagnostics.workspace={active=desktopAlias(state.activeRegularSpaceId),
            desired=desktopAlias(state.switch.desiredSpaceId),
            history={current=desktopAlias(state.lastConfirmedRegularSpaceId),previous=desktopAlias(state.previousRegularSpaceId)},
            inFlight=op and {source=desktopAlias(op.sourceId),destination=desktopAlias(op.destinationId),
                generation=op.generation,phase=op.phase,invalidated=op.invalidated},revision=state.revision}
        diagnostics.workspaceTrace=copy(s.workspaceTrace)
        diagnostics.keyEvents=copy(s.keyEvents)
        diagnostics.instrumentation=s.candidate.instrumentation and s.candidate.instrumentation:status() or nil
    end
    table.sort(managed)
    return managed,unknown,diagnostics
end
local function join(alias,number,pid)
    pid=pid or s.pid
    local app=hs.application.applicationForPID(pid)
    if not app then return false end
    local matched
    for _, w in ipairs(app:allWindows()) do
        local owner=w:application()
        if w:id()==number and owner and owner:pid()==pid then
            assert(not matched,'ambiguous_join'); matched=w
        end
    end
    if not matched then return false end
    local ax=hs.axuielement.windowElement(matched)
    assert(ax:pid()==pid and ax:isValid()==true,'invalid_join')
    assert(ax:attributeValue('AXRole')=='AXWindow'
        and ax:attributeValue('AXSubrole')=='AXStandardWindow'
        and ax:isAttributeSettable('AXPosition')==true
        and ax:isAttributeSettable('AXSize')==true,'fixture_not_standard')
    s.windows[alias]=matched; s.axes[alias]=ax; s.byId[number]=alias; s.ownerPids[alias]=pid
    for _, row in ipairs((s.debugById or {})[number] or {}) do row.alias=alias end
    s.observers=s.observers or {}
    if not s.observers[pid] then
        s.observers[pid]=hs.axuielement.observer.new(pid)
        local owner=s
        s.observers[pid]:callback(function(_,element,notification)
            if s~=owner or not owner.running or owner.phase=='cleanup' then return end
            if notification=='AXUIElementDestroyed' then
                for a,original in pairs(owner.axes) do
                    if owner.ownerPids[a]==pid and element==original then owner.destroyed[a]=true end
                end
            end
        end)
    end
    local observer=s.observers[pid]
    observer:addWatcher(ax,'AXUIElementDestroyed')
    local registered=false
    for _, n in ipairs(observer:watching(ax)) do if n=='AXUIElementDestroyed' then registered=true end end
    assert(registered,'observer_registration_failed')
    observer:start(); assert(observer:isRunning(),'observer_not_running')
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
            if focused==w and owner and owner:pid()==s.ownerPids[alias] then focusedAlias=alias end
        end
        timings[alias]=now()-aliasStarted
    end
    table.sort(closed)
    local snapshotStarted=now()
    -- Join F1 before aliasing workspace diagnostics from the same publication.
    local desktop=s.desktopSwitching and nativeDesktop() or nil
    local managed,unknown,diagnostics=candidateSnapshot()
    if s.desktopSwitching then diagnostics.nativeDesktop=desktop end
    if s.desktopFullscreen then
        diagnostics.fixtureNative={}
        for alias,w in pairs(s.windows) do
            local owners={}
            for _,id in ipairs(hs.spaces.windowSpaces(w:id()) or {}) do owners[#owners+1]=desktopAlias(id) end
            diagnostics.fixtureNative[alias]={fullscreen=w:isFullScreen()==true,spaces=owners}
        end
    end
    diagnostics.ghosttyAXInvalid=s.axes.C and s.ownerPids.C==s.ghosttyPid and s.axes.C:isValid()==false or false
    diagnostics.ghosttyCloseAt=s.ghosttyCloseAt
    timings.snapshot=now()-snapshotStarted
    local host=s.candidate and s.candidate.host
    diagnostics.validityTarget=host and host.validityTarget and s.byId[host.validityTarget.id]
    diagnostics.validityWorker=host and host.validityWorker and host.validityWorker:status() or nil
    diagnostics.validityMailbox=host and host.validityTimer~=nil or false
    local instrumentation=s.candidate and s.candidate.instrumentation
    diagnostics.asyncRemovalRequests=instrumentation and instrumentation:status().counts.asynchronousValidityRemovals or 0
    diagnostics.spacesAdapter=s.candidate and s.candidate.spaces and s.candidate.spaces:status() or nil
    local bar=s.candidate and s.candidate.bar
    local pointer=hs.mouse.absolutePosition()
    local barFacts={requested=bar and bar.presentation and bar.presentation.visible or false,
        showing=bar and bar.canvas and bar.canvas:isShowing() or false,
        handoff=bar and bar.handoff or false,frame=bar and copy(bar.frame),
        pointerTracking=bar and bar.pointerTimer~=nil or false,pointer={x=pointer.x,y=pointer.y}}
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
    for _,observer in pairs(s.observers or {}) do
        local ok,result=pcall(function() observer:stop(); return not observer:isRunning() end)
        observerStopped=observerStopped and ok and result
    end
    s.cleanup.observerStopped=observerStopped
    s.cleanup.nativeWorkerDrained=not s.stoppedWorker or s.stoppedWorker:status().drained==true
    s.cleanup.timerStopped=s.timer==nil
    hs.mouse.absolutePosition(s.originalPointer)
    s.cleanup.pointerRestored=true
    if s.serviceBinding then s.serviceBinding:delete(); s.serviceBinding=nil end
    if s.spaceModule then
        for name,method in pairs(s.spaceMethods) do s.spaceModule[name]=method end
        s.cleanup.spaceWrappersRestored=true
    end
    s.cleanup.bindWrapperRestored=hs.hotkey.bind==s.originalBind
    s.cleanup.taskStopped=not s.task or not s.task:isRunning()
    s.cleanup.normalExit=s.exitCode==0
    s.cleanup.callbackReceived=s.exitCode~=nil
    s.cleanup.claimsAbsent=claimsAbsent()
    s.cleanup.quitAcknowledged=s.quitAck==true
    s.cleanup.forced=s.forced==true
    s.cleanup.ghosttyLaunchSubmitted=s.ghosttyLaunchSubmitted==true
    s.cleanup.ghosttyLaunchResolved=s.ghosttyLaunchResolved==true
    s.cleanup.ghosttyLaunchForced=s.ghosttyLaunchForced==true
    s.cleanup.ghosttyLaunchExitZero=s.ghosttyExit==0
    s.cleanup.ghosttyExited=not s.ghosttyLaunchSubmitted or
        (s.ghosttyLaunchResolved==true and s.ghosttyApp~=nil
         and hs.application.applicationForPID(s.ghosttyPid)==nil)
    s.cleanup.ghosttyLaunchStopped=not s.ghosttyTask or not s.ghosttyTask:isRunning()
    s.cleanup.ghosttyNormal=not s.ghosttyLaunchSubmitted or
        (s.cleanup.ghosttyExited and s.ghosttyExit==0 and not s.ghosttyLaunchForced
         and s.cleanup.ghosttyLaunchStopped)
    local syntheticReleased=s.syntheticKeys==nil or s.cleanup.syntheticKeyReleaseSubmitted==true
    s.cleanup.ok=syntheticReleased and s.cleanup.nativeWorkerDrained and s.cleanup.ghosttyNormal and s.cleanup.candidateStopped and observerStopped and s.cleanup.bindWrapperRestored
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
    -- Release before candidate.stop() can issue its targeted Mission Control
    -- Escape; repeat on cleanup retries, including failed actions/startup.
    s.cleanup.syntheticKeyReleaseSubmitted=releaseSyntheticKeys()
    if not s.cleanup.candidateStopAttempted then
        s.cleanup.candidateStopAttempted=true
        s.stoppedWorker=s.candidate and s.candidate.host and s.candidate.host.validityWorker
        local stopped,stopError=true,nil
        if s.candidate then
            stopped,stopError=pcall(function()
                s.candidate:stop()
                assert(not s.candidate.started and #s.candidate.hotkeyBindings==0,'candidate_still_started')
            end)
        end
        s.cleanup.candidateStopped=stopped
        if not stopped then s.cleanup.error='candidate_stop_failed';s.cleanup.candidateStopError=tostring(stopError) end
    end
    if s.ghosttyTask and not s.ghosttyApp then
        local app=hs.application.get('com.mitchellh.ghostty')
        if app and app:path()=='/Applications/Ghostty.app' then
            s.ghosttyApp=app; s.ghosttyPid=app:pid(); s.ghosttyLaunchResolved=true
        end
    end
    if s.ghosttyApp and not s.ghosttyQuitRequested then
        s.ghosttyQuitRequested=true; s.ghosttyApp:kill()
    end
    s.ghosttyPending=nil
    if s.ghosttyTask and s.ghosttyTask:isRunning() and now()-s.cleanupAt>=3 then
        s.ghosttyLaunchForced=true; s.ghosttyTask:terminate()
    end
    if s.pending or not s.ready then drain() end -- even when the task already exited
    if s.task and s.task:isRunning() and not s.pending and not s.quitAck and s.ready then publish('quit') end
    if (now()-s.cleanupAt>=3 or now()-s.started>=60) and s.task and s.task:isRunning() and not s.forced then
        s.forced=true; s.task:terminate()
    end
    local ghosttyExited=not s.ghosttyLaunchSubmitted or
        (s.ghosttyLaunchResolved==true and s.ghosttyApp~=nil
         and hs.application.applicationForPID(s.ghosttyPid)==nil)
    if ((not s.task or s.exitCode~=nil) and ghosttyExited) or now()-s.cleanupAt>=5 or now()-s.started>=60 then
        if s.task and s.task:isRunning() and not s.forced then s.forced=true; s.task:terminate() end
        finalize()
    end
end
local bootstrap, baseline
local function tick()
    if now()-s.started>=55 and s.phase~='cleanup' then failure('overall_timeout') end
    if s.phase=='ghosttyBaseline' then
        if hs.application.applicationForPID(s.ghosttySeedPid)==nil then
            s.phase='ready'; s.readyDeadline=now()+3; baseline(s.cleanSeedTerminal); return
        end
        if now()>s.baselineDeadline then failure('ghostty_seed_exit_timeout') end
        return
    end
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
    if s.ghosttyPending then
        local p=s.ghosttyPending
        if p.kind=='create' then
            local app=hs.application.get('com.mitchellh.ghostty')
            if app then
                assert(app:path()=='/Applications/Ghostty.app','ghostty_path_mismatch')
                if not s.ghosttyApp then
                    s.ghosttyApp=app; s.ghosttyPid=app:pid(); s.ghosttyLaunchResolved=true
                end
                assert(app==s.ghosttyApp and app:pid()==s.ghosttyPid,'ghostty_owner_changed')
                local added,seen={},{}
                for _,w in ipairs(app:allWindows()) do
                    if w:isStandard() then
                        local known=false
                        for alias,original in pairs(s.windows) do
                            if s.ownerPids[alias]==s.ghosttyPid and w==original then known=true; seen[alias]=true end
                        end
                        if not known then added[#added+1]=w end
                    end
                end
                for alias in pairs(p.baseline) do assert(seen[alias],'ghostty_existing_resource_missing') end
                assert(#added<=1,'ghostty_ambiguous_creation')
                local focused=hs.window.focusedWindow()
                local owner=focused and focused:application()
                if #added==1 and focused==added[1] and owner==app and s.ghosttyExit==0 then
                    if join(p.alias,added[1]:id(),s.ghosttyPid) then s.ghosttyPending=nil end
                end
            end
            if s.ghosttyExit and s.ghosttyExit~=0 then failure('ghostty_launch_failed'); return end
        elseif s.axes[p.alias]:isValid()==false then s.ghosttyPending=nil end
        if s.ghosttyPending and now()>p.deadline then failure('ghostty_action_timeout'); return end
    end
    if s.pending or not s.ready then drain() end
    if s.pending and now()>s.pending.deadline then failure('request_or_join_timeout'); return end
    if not s.ready and now()>s.readyDeadline then failure('ready_timeout'); return end
    if s.keyPending then
        local p=s.keyPending
        local received=true
        for name,count in pairs(p.expected) do
            if (s.receipts[name] or 0)<count then received=false end
        end
        if received then
            s.keyPending=nil
            if s.phase=='columns' then
                local _,unknown,d=candidateSnapshot()
                if d.layout~='columns' or unknown~=0 then failure('columns_baseline_failed')
                else s.phase='active' end
            end
        elseif now()>p.deadline then failure('hotkey_receipt_timeout') end
    end
    if s.ready and s.phase=='ready' then
        if s.initialLayout=='stack' then s.phase='active'
        else s.phase='columns'; key('cycleLayout') end
    end
    sample()
end
bootstrap=function()
    s.candidate=dofile(s.sourceRoot..'/10bucks.spoon/init.lua').new()
    s.candidate:configure({builtInDisplayUUID=s.screen:getUUID(),canaryInstrumentation=true})
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
    if s.desktopSwitching then
        local Spaces=require('lib.macos.spaces')
        s.spaceMethods={}; s.spaceModule=Spaces
        local function row(kind,op)
            s.workspaceTrace[#s.workspaceTrace+1]={kind=kind,at=now(),generation=op.generation,
                source=desktopAlias(op.sourceId),destination=desktopAlias(op.destinationId)}
        end
        for _,name in ipairs({'execute','_receipt','observe'}) do s.spaceMethods[name]=Spaces[name] end
        Spaces.execute=function(adapter,intent,...)
            row(intent.kind,intent)
            return s.spaceMethods.execute(adapter,intent,...)
        end
        Spaces._receipt=function(adapter,op,kind,...)
            row(kind,op.intent)
            return s.spaceMethods._receipt(adapter,op,kind,...)
        end
        Spaces.observe=function(adapter,context,...)
            local result=s.spaceMethods.observe(adapter,context,...)
            if result.generation then row(result.workspaceEventType == 'RegularSwitchContextRebased' and 'pressContextRebased' or 'confirmed',result) end
            return result
        end
    end
    local names={}
    for name,b in pairs(s.candidate.config.hotkeys) do
        if b~=false then
            assert(not s.desktopSwitching or chord(b[1],b[2])~=chord(s.chords.benignService[1],'y'), 'benign_chord_conflict')
            names[chord(b[1],b[2])]=name; s.chords[name]=copy(b)
        end
    end
    hs.hotkey.bind=function(mods,k,pressed,...)
        local name=assert(names[chord(mods,k)],'unexpected_startup_binding')
        return s.originalBind(mods,k,function(...)
            s.receipts[name]=(s.receipts[name] or 0)+1
            s.keyEvents[#s.keyEvents+1]={kind='callback',name=name,at=now()}
            return pressed(...)
        end,...)
    end
    local ok,err=pcall(function() s.candidate:start() end)
    hs.hotkey.bind=s.originalBind
    assert(ok,err)
    local host=s.candidate.host
    local ready=host._ready
    s.debugById={}
    local activeReady
    host._ready=function(h,window,origin,...)
        s.nativeDebug.ready=s.nativeDebug.ready+1
        s.nativeDebug.readyAttempts=s.nativeDebug.readyAttempts or {}
        local id=window and window:id()
        local row={alias=s.byId[id] or 'unjoined',origin=origin,at=now()}
        s.nativeDebug.readyAttempts[#s.nativeDebug.readyAttempts+1]=row
        if id then
            s.debugById[id]=s.debugById[id] or {}
            s.debugById[id][#s.debugById[id]+1]=row
        end
        local prior=activeReady; activeReady=row
        local result=ready(h,window,origin,...)
        activeReady=prior
        return result
    end
    local owner=host._owner
    host._owner=function(h,id,...)
        local space,kind=owner(h,id,...)
        s.nativeDebug.ownerReads=(s.nativeDebug.ownerReads or 0)+1
        local row={alias=s.byId[id] or 'unjoined',known=space~=nil,
            active=space==s.candidate.context.regularSpaceId,kind=kind,at=now()}
        s.nativeDebug.ownerAttempts=s.nativeDebug.ownerAttempts or {}
        s.nativeDebug.ownerAttempts[#s.nativeDebug.ownerAttempts+1]=row
        s.debugById[id]=s.debugById[id] or {}; table.insert(s.debugById[id],row)
        if activeReady then activeReady.owner=row end
        return space,kind
    end
    for _, method in ipairs({'_acceptApp','_remember'}) do
        local original=host[method]
        host[method]=function(h,...)
            local value=original(h,...)
            if activeReady then activeReady[method]=value~=nil end
            return value
        end
    end
    local metadata=host._metadata
    host._metadata=function(h,...)
        local value=metadata(h,...)
        if activeReady then activeReady.metadata=value~=nil end
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
baseline=function(clean)
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
        else M.command(data.operation,data.alias,data.commands) end
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
        desktopSwitching=o.desktopSwitching==true,desktopFullscreen=o.desktopFullscreen==true,desktopAliases={},workspaceTrace={},keyEvents={},syntheticKeys={},
        initialLayout=o.initialLayout or 'columns',ghosttyEnabled=o.ghostty==true,ownedDisposable=o.ownedDisposable==true,cleanSeedTerminal=o.cleanSeedTerminal==true,originalPointer=copy(hs.mouse.absolutePosition()),
        sequence=0,actionSequence=0,windows={},axes={},byId={},ownerPids={},destroyed={},receipts={},chords={},
        cleanup={},trace={},dropped=0,sampleId=0,readyDeadline=now()+3,originalBind=hs.hotkey.bind}
    local native,full=s.screen:frame(),s.screen:fullFrame()
    local top=math.max(native.y,full.y+32)
    s.workArea={x=native.x,y=top,w=native.w,h=math.max(0,native.h-(top-native.y))}
    s.settings={soleScreen=true,accessibility=hs.accessibilityState(),barStrip=32,
        cleanedSeedTerminal=false} -- SIP/settings/versions are independently verified by host
    local ok,startupError=pcall(function()
        if s.desktopSwitching then
            local display=nativeDisplay()
            assert(#display.Spaces==3, 'three_existing_desktops_required')
            for i,item in ipairs(display.Spaces) do
                assert(item.type==0 and item.ManagedSpaceID~=nil, 'three_regular_desktops_required')
                s.desktopAliases[item.ManagedSpaceID]='D'..i
            end
            assert(desktopAlias(display['Current Space'].ManagedSpaceID)=='D1', 'initial_D1_required')
            s.chords.benignService={{'cmd','alt','ctrl','shift'},'y'}
            s.serviceBinding=s.originalBind(s.chords.benignService[1],'y',function()
                s.receipts.benignService=(s.receipts.benignService or 0)+1
                s.keyEvents[#s.keyEvents+1]={kind='callback',name='benignService',at=now()}
            end)
        end
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
        local ghostty=s.ghosttyEnabled and hs.application.get('com.mitchellh.ghostty')
        if ghostty then
            assert(ghostty:path()=='/Applications/Ghostty.app' and #ghostty:allWindows()==0,'ghostty_baseline_not_empty')
            assert(o.ownedDisposable==true,'ghostty_baseline_requires_owned_guest')
            s.ghosttySeedPid=ghostty:pid(); ghostty:kill()
            s.phase='ghosttyBaseline'; s.baselineDeadline=now()+3
        else baseline(o.cleanSeedTerminal==true) end
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
                s.cleanup.syntheticKeyReleaseSubmitted=releaseSyntheticKeys()
                finalize(); pcall(publishStatus)
            end
        end
    end)
    publishStatus()
    return M.status()
end
function M.command(op,alias,commands)
    assert(s and s.running and s.phase=='active' and not s.error,'controller_not_active')
    assert(not s.pending and not s.keyPending and not s.ghosttyPending,'action_pending')
    if op=='createGhostty' then
        assert(s.ghosttyEnabled and s.ownedDisposable and type(alias)=='string' and alias:match('^[A-C]$')
            and not s.windows[alias],'ghostty_alias_rejected')
        local baseline={}
        for a in pairs(s.windows) do
            assert(s.ownerPids[a]==s.ghosttyPid,'ghostty_requires_same_app_topology')
            baseline[a]=true
        end
        if not s.ghosttyTask then
            assert(alias=='A' and not hs.application.get('com.mitchellh.ghostty'),'ghostty_must_be_absent')
            s.ghosttyPending={kind='create',alias=alias,baseline=baseline,deadline=now()+3,submitted_at=now()}
            local owner=s
            s.ghosttyTask=hs.task.new('/usr/bin/open',function(code) owner.ghosttyExit=code end,
                {'-na','/Applications/Ghostty.app','--args','--window-save-state=never',
                 '--initial-window=true','--command=/bin/zsh -f','--confirm-close-surface=false'})
            assert(s.ghosttyTask,'ghostty_launch_constructor_failed')
            s.ghosttyLaunchSubmitted=true
            assert(s.ghosttyTask:start(),'ghostty_launch_start_failed')
        else
            local focused=hs.window.focusedWindow()
            local app=focused and focused:application()
            local preceding=alias=='B' and 'A' or alias=='C' and 'B'
            assert(preceding and focused==s.windows[preceding] and app==s.ghosttyApp
                and app:pid()==s.ghosttyPid and s.axes[preceding]:isValid()==true,'ghostty_new_requires_exact_focus')
            s.ghosttyPending={kind='create',alias=alias,baseline=baseline,deadline=now()+3,submitted_at=now()}
            emitChord({'cmd'},'n')
        end
        return {accepted=true,submitted_at=now()}
    end
    if op=='closeGhostty' then
        assert(alias=='C' and s.ghosttyApp and s.windows[alias],'ghostty_not_joined')
        local focused=hs.window.focusedWindow()
        local app=focused and focused:application()
        assert(focused==s.windows.C and app==s.ghosttyApp and app:pid()==s.ghosttyPid
            and s.axes.C:isValid()==true,'ghostty_close_requires_exact_focus')
        s.ghosttyCloseAt=now()
        s.ghosttyPending={kind='close',alias=alias,deadline=now()+3,submitted_at=s.ghosttyCloseAt}
        emitChord({'ctrl'},'d')
        return {accepted=true,submitted_at=s.ghosttyCloseAt}
    end
    if op=='enterFixtureFullscreen' or op=='exitFixtureFullscreen' then
        assert(s.desktopFullscreen and alias=='A' and s.windows.A and s.axes.A:isValid()==true,
            'fullscreen_requires_owned_fixture_A')
        local entering=op=='enterFixtureFullscreen'
        assert(s.windows.A:isFullScreen()==not entering,'fullscreen_transition_already_applied')
        if entering then
            assert(nativeDesktop().active=='D1' and hs.window.focusedWindow()==s.windows.A,
                'fullscreen_enter_requires_native_D1_A_focus')
        end
        -- Test setup action only, not a production fullscreen command or repair.
        s.windows.A:setFullScreen(entering)
        return {accepted=true,submitted_at=now()}
    end
    if op=='hotkeyBurst' then
        assert(s.desktopSwitching and alias==nil and type(commands)=='table'
            and (#commands==2 or #commands==3), 'invalid_hotkey_burst')
        for _,name in ipairs(commands) do
            assert(name=='benignService' or name=='focusPreviousDesktop' or name=='focusNextDesktop'
                or name=='focusPreviousDesktopPosition' or name:match('^focusDesktop[1-9]$'), 'invalid_burst_command')
        end
        keys(commands)
        return {accepted=true,submitted_at=now()}
    end
    if op=='create' or op=='close' then
        if s.desktopSwitching then assert(nativeDesktop().active=='D1','fixture_requires_D1') end
        assert(type(alias)=='string' and alias:match('^[A-E]$'),'unsupported_alias')
        if op=='create' then assert(not s.windows[alias],'alias_already_used')
        else assert(s.windows[alias],'alias_not_joined') end
        return publish(op,alias)
    end
    if op=='pointerInsideBar' or op=='pointerOutsideBar' then
        assert(alias==nil,'pointer_alias_forbidden')
        local full=s.screen:fullFrame()
        local point={x=full.x+full.w/2,y=full.y+(op=='pointerInsideBar' and 1 or 100)}
        hs.mouse.absolutePosition(point)
        hs.eventtap.event.newMouseEvent(hs.eventtap.event.types.mouseMoved,point):post()
        return {accepted=true,operation=op,submitted_at=now()}
    end
    if s.desktopSwitching and (op=='benignService' or op=='resizeLeft' or op=='resizeRight'
        or op=='focusPreviousDesktop' or op=='focusNextDesktop' or op=='focusPreviousDesktopPosition'
        or op:match('^focusDesktop[1-9]$')) then
        assert(alias==nil,'hotkey_alias_forbidden'); key(op)
        return {accepted=true,submitted_at=now()}
    end
    assert(alias==nil and (op=='focusNext' or op=='focusPrevious' or op=='focusLeftGroup'
        or op=='focusRightGroup' or op=='focusManagedPrevious' or op=='cycleLayout'),'unsupported_acceptance_command')
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
        lastAck=copy(s.lastAck),pending=s.pending~=nil or s.keyPending~=nil or s.ghosttyPending~=nil,
        ghosttyCloseAt=s.ghosttyCloseAt,
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
