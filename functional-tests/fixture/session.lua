-- Fixture ownership only. Candidate, scenarios, sampling and timings belong to callers.
local Session={};Session.__index=Session
function Session.new(o)
    local self=setmetatable({dir=o.controlDir,run=o.run,sequence=0,windows={},closed={}},Session)
    self.mailbox=dofile(o.sourceRoot..'/functional-tests/fixture/mailbox.lua')
    self.task=assert(hs.task.new(o.executable,function(code) self.exitCode=code;if o.onExit then o.onExit(code) end end,
        {'--run',o.run,'--control-dir',o.controlDir}))
    if o.onOwned then o.onOwned(self) end -- retain cleanup authority before start can fail
    assert(self.task:start(),'fixture_start_failed');self.pid=self.task:pid()
    self.pending={operation='ready',sequence=0}
    return self
end
function Session:request(operation,alias)
    assert(not self.pending,'fixture_pending')
    assert(not hs.fs.attributes(self.dir..'/request.json') and not hs.fs.attributes(self.dir..'/processing.json'),'mailbox_busy')
    self.sequence=self.sequence+1
    self.mailbox.publish(self.dir,self.run,self.sequence,operation,alias)
    self.pending={operation=operation,alias=alias,sequence=self.sequence}
end
function Session:ack()
    local p=self.pending;if not p then return end
    local a=hs.json.read(self.dir..'/ack.json')
    if not a or a.run~=self.run or a.sequence~=p.sequence then return end
    assert(a.pid==self.pid and a.operation==p.operation and a.alias==p.alias and a.accepted==true,'fixture_ack_mismatch')
    assert(not hs.fs.attributes(self.dir..'/request.json') and not hs.fs.attributes(self.dir..'/processing.json'),'ack_before_cleanup')
    self.pending=nil
    if a.operation=='ready' then self.ready=true end
    if a.operation=='quit' then self.quitAcknowledged=true end
    return a
end
function Session:join(alias,number)
    local app=hs.application.applicationForPID(self.pid);if not app then return end
    local found
    for _,w in ipairs(app:allWindows()) do
        if w:id()==number and w:application()==app then assert(not found,'ambiguous_fixture_join');found=w end
    end
    if not found then return end
    local ax=hs.axuielement.windowElement(found)
    if ax:isValid()~=true or ax:pid()~=self.pid then return end
    local row={window=found,ax=ax,app=app,id=number,pid=self.pid}
    self.windows[alias]=row;return row
end
function Session:confirmClosed(alias)
    local row=assert(self.windows[alias],'fixture_not_joined')
    if row.ax:isValid()~=false then return false end
    self.closed[alias]=true;return true
end
function Session:releaseClosed(alias)
    assert(self.closed[alias] and self:confirmClosed(alias),'exact_close_required')
    self:request('resetClosedAlias',alias)
    self.windows[alias]=nil;self.closed[alias]=nil
end
function Session:quit()
    if self.ready and not self.pending and not self.quitAcknowledged and self.task:isRunning() then self:request('quit') end
end
function Session:cleanup()
    return {taskStopped=not self.task:isRunning(),normalExit=self.exitCode==0,
        callbackReceived=self.exitCode~=nil,quitAcknowledged=self.quitAcknowledged==true,
        claimsAbsent=not hs.fs.attributes(self.dir..'/request.json') and not hs.fs.attributes(self.dir..'/processing.json')}
end
return Session
