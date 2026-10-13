-- Empty-window desktop benchmark observer. No fixture or FT frame/title sampler.
local M,s={},nil
local function now() return hs.timer.absoluteTime()/1e9 end
local function copy(v) if type(v)~='table' then return v end;local r={};for k,x in pairs(v) do r[k]=copy(x) end;return r end
local function output(name,v) local f=assert(io.open(s.out..'/'..name..'.tmp','w'));f:write(hs.json.encode(v));f:close();assert(os.rename(s.out..'/'..name..'.tmp',s.out..'/'..name)) end
local function alias(id) return s.aliases[id] or 'unknown' end
local function display()
 for _,d in ipairs(hs.spaces.data_managedDisplaySpaces()) do if d['Display Identifier']==s.screen:getUUID() then return d end end
 error('native_display_missing')
end
local function native()
 local d=display();local r={active=alias(d['Current Space'].ManagedSpaceID),order={},regular={},types={},count=#d.Spaces}
 for _,item in ipairs(d.Spaces) do
  local id=item.ManagedSpaceID
  if not s.aliases[id] then
   local before=s.creationBefore;assert(before and item.type==0 and #d.Spaces==#before+1,'unowned_native_addition')
   if s.c.workspace:state().switch.inFlight or d['Current Space'].ManagedSpaceID~=id then
    return {active=alias(d['Current Space'].ManagedSpaceID),order={},regular={},types={},count=#d.Spaces}
   end
   for i,prior in ipairs(before) do assert(d.Spaces[i].ManagedSpaceID==prior,'conflicting_native_topology') end
   assert(d.Spaces[#d.Spaces].ManagedSpaceID==id and d['Current Space'].ManagedSpaceID==id
    and not s.c.workspace:state().switch.inFlight,'unconfirmed_native_append')
   s.created[#s.created+1]=id;s.aliases[id]='D'..(3+#s.created);s.owned=id;s.creationBefore=nil
  end
  local a=alias(id);r.order[#r.order+1]=a;r.types[#r.types+1]=item.type==0 and 'user' or 'fullscreen'
  if item.type==0 then r.regular[#r.regular+1]=a end
 end
 return r
end
local function chord(mods,key) local m=copy(mods);table.sort(m);return table.concat(m,'+')..':'..key end
local function keys(names)
 for _,name in ipairs(names) do
  if name=='createDesktop' then
   assert(not s.creationBefore and not s.owned,'creation_already_owned')
   s.creationBefore={};for _,item in ipairs(display().Spaces) do assert(item.type==0);s.creationBefore[#s.creationBefore+1]=item.ManagedSpaceID end
  end
  local b=assert(s.chords[name]);s.events[#s.events+1]={kind='posted',name=name,at=now()}
  hs.eventtap.event.newKeyEvent(b[1],b[2],true):post();hs.eventtap.event.newKeyEvent(b[1],b[2],false):post()
 end
 for _,mod in ipairs({'cmd','alt','ctrl','shift'}) do hs.eventtap.event.newKeyEvent({},mod,false):post() end
end
local function snapshot()
 local at=now();local n=native();local state=s.c.workspace:state();local op=state.switch.inFlight
 s.sample=s.sample+1
 local row={sample_id=s.sample,sampled_at=at,frames={},closed={},managed={},commands_received=copy(s.receipts),unknownMembers=0,
  diagnostics={nativeDesktop=n,keyEvents=copy(s.events),workspaceTrace=copy(s.trace),instrumentation=s.c.instrumentation:status(),
   workspace={active=alias(state.activeRegularSpaceId),desired=state.switch.desiredSpaceId and alias(state.switch.desiredSpaceId),
    history={current=alias(state.lastConfirmedRegularSpaceId)},inFlight=op and {phase=op.phase}}}}
 row.observed_at=now();s.latest=row;s.rows[#s.rows+1]=row;output('observation.json',row)
end
local function empty(o,names)
 if not o then return false end
 for _,name in ipairs(names) do if type(o[name])~='table' or next(o[name]) then return false end end
 return true
end
local function cleanup()
 if not s.stopped then
  s.stopped=true;s.host=s.c and s.c.host;s.windows=s.c and s.c.windows;s.worker=s.host and s.host.validityWorker
  s.stopOK=pcall(function() if s.c then s.c:stop() end end)
  s.bindingDeleted=not s.binding or pcall(function() s.binding:delete() end);s.binding=nil
 end
 local drained=true
 if s.worker then local ok,value=pcall(s.worker.status,s.worker);drained=ok and value.drained==true;if not ok then s.cleanupFailure=true end end
 if drained or now()-s.cleanupAt>5 then
  local restored=true
  for _,r in ipairs(s.restore) do
   local ok,identity=pcall(function() local same=r.o[r.k]==r.wrapper;r.o[r.k]=r.old;return same and r.o[r.k]==r.old end)
   restored=restored and ok and identity
  end
  local resources=empty(s.host,{'handles','appResources','managedObservers','owned','readiness'})
   and empty(s.windows,{'cache','subscriptions','probeSubscriptions','probing'})
   and not s.host.started and not s.windows.started and not s.host.validityTimer and not s.host.discoveryTimer and not s.host.validityTarget
  s.running=false;local timerOK=pcall(s.timer.stop,s.timer)
  s.cleanup={ok=s.stopOK and drained and restored and resources and s.bindingDeleted and timerOK and not s.cleanupFailure and not s.owned and not s.creationBefore,
   nativeWorkerDrained=drained,wrappersRestored=restored,resourcesCleared=resources,bindingDeleted=s.bindingDeleted,
   ownedTestSpaceRemaining=s.owned~=nil,unconfirmedAddition=s.creationBefore~=nil,failure=s.cleanupFailure==true or not s.stopOK or not s.bindingDeleted}
  output('guest-result.json',{error=s.error,failedStage=s.failedStage,cleanup=s.cleanup,trace=s.rows,dropped=0})
 end
end
local function tick()
 if now()-s.started>55 then s.error=s.error or 'desktop_benchmark_timeout';M.stop() end
 if s.phase=='cleanup' then cleanup();return end
 s.stage='action_transport'
 local a=hs.json.read(s.out..'/action.json')
 if a then
  assert(a.sequence==s.sequence+1,'action_sequence');os.remove(s.out..'/action.json');s.sequence=a.sequence
  if a.operation=='hotkeyBurst' then keys(a.commands)
  elseif a.operation=='stop' then M.stop();return
  elseif a.operation=='removeCreatedDesktop' then
   local id=s.owned;local d=display();assert(id and d['Current Space'].ManagedSpaceID~=id,'cleanup_inactive_required')
   local before={};local found=false
   for _,item in ipairs(d.Spaces) do
    if item.ManagedSpaceID==id then assert(item.type==0);found=true else before[#before+1]=item.ManagedSpaceID end
   end
   assert(found,'owned_space_absent')
   s.stage='owned_test_environment_scan'
   local enumerated,apps=pcall(hs.application.runningApplications)
   assert(enumerated and type(apps)=='table','enumeration_unknown')
   for _,app in ipairs(apps) do
    local known,windows=pcall(app.allWindows,app)
    assert(known and type(windows)=='table','enumeration_unknown')
    for _,window in ipairs(windows) do
     local queried,ordinary=pcall(window.isStandard,window)
     assert(queried and type(ordinary)=='boolean','enumeration_unknown')
     assert(not ordinary,'owned_test_environment_has_windows')
    end
   end
   s.stage='owned_space_remove'
   assert(hs.spaces.removeSpace(id),'owned_space_cleanup_failed')
   local after=display();assert(#after.Spaces==#before,'owned_cleanup_topology_mismatch')
   for i,prior in ipairs(before) do assert(after.Spaces[i].ManagedSpaceID==prior,'owned_cleanup_order_mismatch') end
   s.owned=nil
  else keys({a.operation}) end
 end
 s.stage='native_snapshot';snapshot()
end
function M.start(o)
 assert(not s or not s.running,'benchmark_running')
 s={out=o.outputDir,started=now(),running=true,phase='active',screen=hs.screen.allScreens()[1],aliases={},created={},events={},trace={},rows={},receipts={},chords={},restore={},sequence=0,sample=0}
 local ok=pcall(function()
  assert(#hs.screen.allScreens()==1 and hs.accessibilityState(),'benchmark_environment')
  for _,app in ipairs(hs.application.runningApplications()) do for _,w in ipairs(app:allWindows()) do assert(not w:isStandard(),'empty_benchmark_required') end end
  local d=display();assert(#d.Spaces==3,'three_spaces_required')
  for i,item in ipairs(d.Spaces) do assert(item.type==0);s.aliases[item.ManagedSpaceID]='D'..i end
  assert(alias(d['Current Space'].ManagedSpaceID)=='D1')
  package.path=o.sourceRoot..'/10bucks.spoon/?.lua;'..package.path
  s.c=dofile(o.sourceRoot..'/10bucks.spoon/init.lua').new();s.c:configure({builtInDisplayUUID=s.screen:getUUID(),canaryInstrumentation=true})
  local names={};for name,b in pairs(s.c.config.hotkeys) do if b~=false then s.chords[name]=b;names[chord(b[1],b[2])]=name end end
  local bind=hs.hotkey.bind
  hs.hotkey.bind=function(mods,key,pressed,...)
   local name=assert(names[chord(mods,key)])
   return bind(mods,key,function(...) s.receipts[name]=(s.receipts[name] or 0)+1;s.events[#s.events+1]={kind='callback',name=name,at=now()};return pressed(...) end,...)
  end
  local started=pcall(s.c.start,s.c);hs.hotkey.bind=bind;assert(started,'candidate_start_failed')
  s.chords.benignService={{'cmd','alt','ctrl','shift'},'y'}
  s.binding=bind(s.chords.benignService[1],'y',function() s.receipts.benignService=(s.receipts.benignService or 0)+1;s.events[#s.events+1]={kind='callback',name='benignService',at=now()} end)
  local Spaces=require('lib.macos.spaces')
  for _,name in ipairs({'execute','_receipt','observe'}) do
   local old=Spaces[name];local wrapper
   wrapper=function(adapter,value,...)
    if name=='execute' then s.trace[#s.trace+1]={kind=value.kind,at=now(),generation=value.generation,source=alias(value.sourceId),destination=alias(value.destinationId)} end
    if name=='_receipt' then local kind=select(1,...);local i=value.intent;s.trace[#s.trace+1]={kind=kind,at=now(),generation=i.generation,source=alias(i.sourceId),destination=alias(i.destinationId)} end
    local r=table.pack(old(adapter,value,...))
    if name=='observe' and r[1].generation then local v=r[1];s.trace[#s.trace+1]={kind=v.workspaceEventType=='RegularCreateTopologyObserved' and 'createdTopology' or 'confirmed',at=now(),generation=v.generation,source=alias(v.sourceId),destination=alias(v.destinationId)} end
    return table.unpack(r,1,r.n)
   end
   Spaces[name]=wrapper;s.restore[#s.restore+1]={o=Spaces,k=name,old=old,wrapper=wrapper}
  end
 end)
 if not ok then s.error='desktop_benchmark_startup';M.stop() end
 s.timer=hs.timer.doEvery(.05,function()
  local good,err=pcall(tick)
  if not good then
   local code='desktop_benchmark_exception'
   for _,allowed in ipairs({'owned_test_environment_has_windows','enumeration_unknown','cleanup_inactive_required',
    'owned_space_absent','owned_space_cleanup_failed','owned_cleanup_topology_mismatch','owned_cleanup_order_mismatch',
    'unowned_native_addition','conflicting_native_topology','unconfirmed_native_append'}) do
    if tostring(err):find(allowed,1,true) then code=allowed;break end
   end
   s.error=s.error or code;s.failedStage=s.failedStage or s.stage;M.stop()
  end
  output('status.json',M.status())
 end)
 return M.status()
end
function M.status() return {running=s.running,error=s.error,cleanup=s.cleanup,fixtureReady=true,candidateReady=s.phase=='active',layout='columns',unknownMembers=0,workArea=s.c and s.c.context and s.c.context.workArea,actionSequence=s.sequence,actionAccepted=true,pending=false,observed_at=now()} end
function M.stop() s.phase='cleanup';s.cleanupAt=s.cleanupAt or now();return M.status() end
return M
