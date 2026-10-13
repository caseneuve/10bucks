-- Rules benchmark owner. No functional sampler; native outcomes read after admission.
local M,s={},nil
local function now() return hs.timer.absoluteTime()/1e9 end
local function output(name,value)
 local f=assert(io.open(s.out..'/'..name..'.tmp','w'));f:write(hs.json.encode(value));f:close();assert(os.rename(s.out..'/'..name..'.tmp',s.out..'/'..name))
end
local function wrap(o,k,fn) local old=o[k];local replacement=fn(old);s.restore[#s.restore+1]={o,k,old,replacement};o[k]=replacement end
local function tuple(id,r,a,p) return table.concat({tostring(id),tostring(r),tostring(a),tostring(p)},":") end
local function save() output('rules-benchmark.json',s.result) end
local function empty(o,names)
 if not o then return false end
 for _,name in ipairs(names) do if type(o[name])~='table' or next(o[name]) then return false end end
 return true
end
local function cleanup()
 s.cleanupAt=s.cleanupAt or now()
 if not s.stopped then
  s.stopped=true;s.host=s.c and s.c.host;s.windows=s.c and s.c.windows
  s.worker=s.host and s.host.validityWorker
  s.stopOK=pcall(function() if s.c then s.c:stop() end end)
  s.bindingDeleted=not s.binding or pcall(function() s.binding:delete() end);s.binding=nil
 end
 if s.fixture then
  local transportOK=pcall(function() s.fixture:ack();s.fixture:quit() end)
  if not transportOK then s.cleanupFailure=true;s.error=s.error or 'cleanup_transport_exception' end
  if now()-s.cleanupAt>3 and s.fixture.task:isRunning() then
   s.forced=true;if not pcall(s.fixture.task.terminate,s.fixture.task) then s.cleanupFailure=true end
  end
 end
 local drained=true
 if s.worker then local ok,value=pcall(s.worker.status,s.worker);drained=ok and value.drained==true;if not ok then s.cleanupFailure=true end end
 if (not s.fixture or (s.fixture.exitCode~=nil and drained)) or now()-s.cleanupAt>5 then
  local facts={}
  if s.fixture then local ok,value=pcall(s.fixture.cleanup,s.fixture);if ok then facts=value else s.cleanupFailure=true end end
  local resources=empty(s.host,{'handles','appResources','managedObservers','owned','readiness'})
   and empty(s.windows,{'cache','subscriptions','probeSubscriptions','probing'})
   and not s.host.started and not s.windows.started and not s.host.validityTimer and not s.host.discoveryTimer and not s.host.validityTarget
  local restored=true
  for i=#s.restore,1,-1 do
   local r=s.restore[i];local ok,identity=pcall(function()
    local same=r[1][r[2]]==r[4];r[1][r[2]]=r[3];return same and r[1][r[2]]==r[3]
   end);restored=restored and ok and identity
  end
  s.cleanup={ok=s.stopOK and resources and drained and restored and s.bindingDeleted and facts.taskStopped
   and facts.normalExit and facts.callbackReceived and facts.quitAcknowledged and facts.claimsAbsent and not s.forced and not s.cleanupFailure,
   nativeWorkerDrained=drained,resourcesCleared=resources,wrappersRestored=restored,bindingDeleted=s.bindingDeleted}
  s.running=false;pcall(s.timer.stop,s.timer);save()
  output('guest-result.json',{error=s.error,cleanup=s.cleanup,trace=s.rows,dropped=0})
 end
end
local function tick()
 if now()-s.started>50 then s.error=s.error or 'benchmark_timeout';s.phase='cleanup' end
 if s.error then s.phase='cleanup' end
 if s.phase=='cleanup' then cleanup();return end
 local ack=s.fixture:ack()
 if s.phase=='ready' and ack then s.phase='idle' end
 if s.phase=='idle' then
  local a=hs.json.read(s.out..'/action.json')
  if a then os.remove(s.out..'/action.json');s.actionSequence=a.sequence;s.mode=a.alias;s.result.mode=s.mode;s.total=s.mode=='warm' and 22 or 2;s.index=0;s.phase='next' end
 elseif s.phase=='next' then
  s.index=s.index+1
  if s.index>s.total then s.result.status='complete';save();s.phase='done';return end
  s.focusRequests=0;s.alias=s.index%2==1 and 'A' or 'B';s.action=s.alias=='A' and 'manage' or 'exclude';s.path={frameRequests={}};s.requests=0
  s.fixture:request('create',s.alias);s.phase='created'
 elseif s.phase=='created' and ack then s.number=ack.windowNumber;s.baseline=ack.creationFrame;s.phase='observe'
 elseif s.phase=='observe' then
  local w=s.fixture:join(s.alias,s.number);if not w then return end
  local record=s.c.host.handles[w.id];local app=s.c.host.appResources[w.pid]
  if not record or not record.active or record.handle~=w.window or record.element~=w.ax
   or record.pid~=w.pid or not app or not app.active or app.app~=w.app or record.appLease~=app.lease then return end
  if tuple(w.id,record.lease,record.appLease,record.pid)~=s.path.key then return end
  local focused=hs.window.focusedWindow();local f=w.window:frame()
  local managed=s.c.core:state().manager.windows[w.id]~=nil
  if focused~=w.window or managed~=(s.action=='manage') then return end
  if managed and s.c.handleRegistry:resolve({windowId=w.id,spaceId=s.c.core.spaceId,lease=record.lease})~=w.window then return end
  local expected=s.action=='exclude' and s.baseline or s.c.context.workArea
  if not expected then error('native_expected_frame_missing') end
  for _,k in ipairs({'x','y','w','h'}) do if math.abs(f[k]-expected[k])>2 then return end end
  s.path.nativeConfirmed=now();s.path.action=s.action;s.path.effects={frame=s.requests,focus=s.focusRequests}
  s.path.posted=now();hs.eventtap.event.newKeyEvent({'cmd','alt','ctrl','shift'},'y',true):post();hs.eventtap.event.newKeyEvent({'cmd','alt','ctrl','shift'},'y',false):post();s.phase='service'
 elseif s.phase=='service' and s.path.callback then
  s.path.key=nil -- exact native tuple remains private, never serialized
  s.rows[#s.rows+1]=s.path
  local dest=s.mode=='warm' and s.index<=2 and s.result.warmup or s.result.samples;dest[#dest+1]=s.path;save()
  s.fixture:request('close',s.alias);s.phase='close'
 elseif s.phase=='close' and not s.fixture.pending then
  if s.fixture:confirmClosed(s.alias) and s.c.host.handles[s.number]==nil then s.fixture:releaseClosed(s.alias);s.phase='release' end
 elseif s.phase=='release' and ack then s.phase='next' end
end
function M.start(o)
 assert(not s or not s.running,'benchmark_already_running')
 assert(hs.accessibilityState() and #hs.screen.allScreens()==1,'benchmark_environment_required')
 for _,app in ipairs(hs.application.runningApplications()) do
  for _,w in ipairs(app:allWindows()) do assert(not w:isStandard(),'empty_benchmark_baseline_required') end
 end
 s={out=o.outputDir,started=now(),running=true,phase='ready',rows={},restore={},result={status='incomplete',samples={},warmup={},mode=nil}}
 package.path=o.sourceRoot..'/10bucks.spoon/?.lua;'..package.path
 local started, startupError=pcall(function()
 local c=dofile(o.sourceRoot..'/10bucks.spoon/init.lua').new();s.c=c
 c:configure({builtInDisplayUUID=hs.screen.allScreens()[1]:getUUID(),canaryInstrumentation=true,rules={{match={title='10bucks fixture B'},action='exclude'}}})
 local factory=require('lib.macos.ax_validity')
 wrap(factory,'prepare',function(old)return function(...) local at=now();local r=table.pack(old(...));if not s.result.imagePreparation then s.result.imagePreparation={at=at,finished=now()} end;return table.unpack(r,1,r.n) end end)
 local at=now();c:start();s.result.startup={at=at,finished=now()};assert(c:_submitCommand({type='CycleLayout'}))
 wrap(c.windows,'_ready',function(old)return function(w,obs,...)
  local prior=s.admission;local m=obs.metadata
  local key=m and tuple(m.id,obs.resource,obs.appResource,m.application.pid)
  local context=prior and prior.key==key and prior or {key=key,path=s.path,at=now()}
  s.admission=context
  local r=table.pack(pcall(old,w,obs,...));s.admission=prior
  if not r[1] then error(r[2],0) end;return table.unpack(r,2,r.n)
 end end)
 local rules=require('lib.rules')
 wrap(rules,'filter',function(old)return function(m,...)
  local ctx=s.admission;local record=c.host.handles[m.id]
  local key=record and tuple(m.id,record.lease,record.appLease,record.pid)
  if ctx and ctx.path and ctx.key==key and not ctx.path.commit then
   ctx.path.key=key;ctx.path.ready=ctx.at;ctx.path.filter=now()
  end
  return old(m,...)
 end end)
 wrap(rules,'reduce',function(old)return function(records,event)
  local r=old(records,event);local ctx=s.admission
  if event.type=='WindowReady' and r[event.id] and not records[event.id] then
   local rec=r[event.id];local key=tuple(event.id,rec.resource,rec.appResource,rec.pid)
   if ctx and ctx.path and ctx.key==key then ctx.terminal=true;ctx.path.commit=now() end
  end
  return r
 end end)
 local executing
 wrap(c.host,'execute',function(old)return function(h,adapter,intents,current,...)
  if not s.admission or not s.admission.terminal then return old(h,adapter,intents,current,...) end
  local prior=executing;executing={}
  for _,intent in ipairs(intents) do
   if intent.kind=='frame' then
    local rec=h.handles[intent.windowId]
    local key=rec and tuple(intent.windowId,rec.lease,rec.appLease,rec.pid)
    if executing.key or not rec or (intent.lease~=nil and intent.lease~=rec.lease)
     or not s.admission or key~=s.admission.key then
     s.error='ambiguous_frame_batch';executing.ambiguous=true
    else executing.key=key;executing.record=rec end
   end
  end
  local r=table.pack(pcall(old,h,adapter,intents,current,...));executing=prior
  if not r[1] then error(r[2],0) end;return table.unpack(r,2,r.n)
 end end)
 wrap(c.host,'_record',function(old)return function(h,kind,...)
  if kind=='frameQueries' and executing then executing.queried=true end
  if kind=='frameRequests' and executing then
   local ctx=s.admission
   if not executing.ambiguous and executing.queried and executing.record
    and ctx and ctx.terminal and ctx.path and executing.key==ctx.key then
    s.requests=s.requests+1;local at=now();ctx.path.frame=at
    ctx.path.frameRequests[#ctx.path.frameRequests+1]={ordinal=s.requests,at=at}
   end
  end
  return old(h,kind,...)
 end end)
 wrap(c.host,'focus',function(old)return function(h,w,...)
  local rec=h.handles[w:id()]
  if rec and s.path and tuple(w:id(),rec.lease,rec.appLease,rec.pid)==s.path.key then s.focusRequests=s.focusRequests+1 end
  return old(h,w,...)
 end end)
 s.binding=hs.hotkey.bind({'cmd','alt','ctrl','shift'},'y',function() if s.path then s.path.callback=now() end end)
 local Session=dofile(o.sourceRoot..'/functional-tests/fixture/session.lua');o.onOwned=function(owner) s.fixture=owner end;s.fixture=Session.new(o)
 end)
 if not started then s.error="benchmark_startup_exception";s.phase="cleanup" end
 s.timer=hs.timer.doEvery(.05,function() local ok=pcall(tick);if not ok then s.error='benchmark_exception';s.phase='cleanup' end;output('status.json',M.status()) end)
 return M.status()
end
function M.status() return {running=s.running,error=s.error,cleanup=s.cleanup,fixtureReady=s.fixture and s.fixture.ready,candidateReady=s.phase~='ready',layout='columns',unknownMembers=0,workArea=s.c and s.c.context and s.c.context.workArea,actionSequence=s.actionSequence,actionAccepted=true,pending=s.phase~='done' and s.phase~='idle',observed_at=now()} end
function M.stop() s.phase='cleanup';return M.status() end
return M
