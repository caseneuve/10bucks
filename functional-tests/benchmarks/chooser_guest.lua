-- Separate bounded benchmark observer; no functional sampler or pixel oracle.
local M,s={},nil
local function now() return hs.timer.absoluteTime()/1e9 end
local function write()
 local f=assert(io.open(s.out..'/chooser-raw.json.tmp','w'));f:write(hs.json.encode(s.raw));f:close()
 assert(os.rename(s.out..'/chooser-raw.json.tmp',s.out..'/chooser-raw.json'))
end
local function wrap(o,k,observe)
 local old=assert(o[k]);local replacement=function(...) return observe(old,...) end
 s.restore[#s.restore+1]={o,k,old,replacement};o[k]=replacement
end
local function count(t) local n=0;for _ in pairs(t or {}) do n=n+1 end;return n end
local function counts()
 local q={};for k,v in pairs(s.queries) do q[k]=v end
 local h=s.c.host;local w=s.c.windows
 return {queries=q,resources={handles=count(h.handles),applications=count(h.appResources),
  observers=count(h.managedObservers),readiness=count(h.readiness),windows=count(w.cache),
  bindings=#s.c.hotkeyBindings,timers=s.c:canaryStatus().activeTimers}}
end
local function native() local a=s.c.windowChooser;return a and a.chooser end
local function post(key)
 local at=now();hs.eventtap.event.newKeyEvent({'cmd','alt','ctrl','shift'},key,true):post()
 hs.eventtap.event.newKeyEvent({'cmd','alt','ctrl','shift'},key,false):post()
 for _,mod in ipairs({'cmd','alt','ctrl','shift'}) do hs.eventtap.event.newKeyEvent({},mod,false):post() end
 return at
end
local function fail(reason)
 s.raw.error=s.raw.error or reason;s.raw.failedSample=s.row or s.raw.failedSample
 s.raw.status='failed';s.phase='cleanup';s.cleanupAt=s.cleanupAt or now();write()
end
local function cleanup()
 s.cleanupAt=s.cleanupAt or now()
 if not s.stopped then
  s.raw.failedSample=s.row or s.raw.failedSample;write()
  s.stopped=true;s.host=s.c and s.c.host;s.windows=s.c and s.c.windows;s.worker=s.host and s.host.validityWorker
  s.nativeBeforeStop=s.c and s.c.windowChooser and s.c.windowChooser.chooser
  s.stopOK=pcall(function() if s.c then s.c:stop() end end)
  s.bindingDeleted=not s.binding or pcall(function() s.binding:delete() end);s.binding=nil
 end
 if s.fixture then s.fixture:ack();s.fixture:quit() end
 local drained=true
 if s.worker then local ok,status=pcall(s.worker.status,s.worker);drained=ok and status.drained==true end
 if drained and (not s.fixture or s.fixture.exitCode~=nil) or now()-s.cleanupAt>5 then
  local restored=true
  for i=#s.restore,1,-1 do local r=s.restore[i];restored=restored and r[1][r[2]]==r[4];r[1][r[2]]=r[3];restored=restored and r[1][r[2]]==r[3] end
  local resources=s.host and s.windows and not s.host.started and not s.windows.started
  for _,k in ipairs({'handles','appResources','managedObservers','owned','readiness'}) do resources=resources and count(s.host and s.host[k])==0 end
  for _,k in ipairs({'cache','subscriptions','probeSubscriptions','probing'}) do resources=resources and count(s.windows and s.windows[k])==0 end
  resources=resources and not s.host.validityTimer and not s.host.discoveryTimer and not s.host.validityTarget
  local facts=s.fixture and s.fixture:cleanup() or {}
  local normal=facts.taskStopped and facts.normalExit and facts.callbackReceived and facts.quitAcknowledged and facts.claimsAbsent
  -- Never call a method on deleted chooser userdata. Visibility was observed
  -- immediately before native deletion; no corrective hide is introduced.
  local invisible=not s.nativeBeforeStop or s.invisibleBeforeDelete==true
  local focusReleased=not s.nativeBeforeStop or hs.chooser._lastFocused[s.nativeBeforeStop]==nil
  local chooserDeleted=not s.nativeBeforeStop or (s.chooserDeleted==true and invisible and focusReleased and s.c and s.c.windowChooser==nil)
  s.raw.cleanup={nativeWorkerDrained=drained,resourcesCleared=resources,wrappersRestored=restored,
   bindingDeleted=s.bindingDeleted,chooserDeleted=chooserDeleted,chooserInvisible=invisible,defaultFocusReleased=focusReleased,normalFixtureQuit=normal,
   productBindingsDeleted=s.c and #s.c.hotkeyBindings==0}
  local ok=s.stopOK and drained and resources and restored and s.bindingDeleted and chooserDeleted and normal and s.c and #s.c.hotkeyBindings==0
  s.raw.cleanup.ok=ok==true;if not ok then s.raw.status='failed';s.raw.error=s.raw.error or 'cleanup_failed' end
  s.running=false;s.timer:stop();write()
 end
end
local function tick()
 if now()-s.started>55 and s.phase~='cleanup' then fail('benchmark_timeout') end
 if s.phase=='cleanup' then cleanup();return end
 local ack=s.fixture:ack()
 if s.phase=='ready' and ack then s.index=1;s.fixture:request('create','A');s.phase='create'
 elseif s.phase=='create' and ack then s.number=ack.windowNumber;s.phase='join'
 elseif s.phase=='join' then
  local alias=({'A','B','C','D'})[s.index];local row=s.fixture:join(alias,s.number);if not row then return end
  -- Fixture readiness and manager count, not representation-specific chooser assertions.
  if s.c:canaryStatus().memberCount~=(s.index==4 and 3 or s.index) then return end
  if s.index<4 then s.index=s.index+1;s.fixture:request('create',({'A','B','C','D'})[s.index]);s.phase='create'
  else s.index=0;s.phase='next' end
 elseif s.phase=='next' then
  s.index=s.index+1
  if s.index>(s.raw.mode=='warm' and 11 or 1) then s.raw.status='complete';s.phase='cleanup';return end
  assert(not native() or not native():isVisible(),'chooser_already_visible')
  s.row={before=counts()};s.row.posted=post('w');s.phase='visible'
 elseif s.phase=='visible' and s.row.showReturned then
  local n=assert(native(),'native_chooser_missing')
  if not n:isVisible() then return end
  s.row.visible=now();s.row.nativeVisible=true
  s.row.servicePosted=post('y');s.phase='service'
 elseif s.phase=='service' and s.row.serviceReceipt then
  local r=s.row
  s.raw.failedSample=r;write() -- retain attempted sample before any validation
  assert(r.serviceReceipt-r.servicePosted<=.1,'ordinary_service_maximum')
  -- Diagnostic stop, NOT a per-sample acceptance gate replacing the fixed p95
  -- contract. Inspect this preserved exceedance before deciding any new run.
  assert(r.visible-r.posted<=.1,'invocation_visible_exceedance_inspect_before_rerun')
  assert(r.after.queries.globalAX==r.before.queries.globalAX,'global_AX_on_open')
  assert(r.after.queries.perWindowIcon==r.before.queries.perWindowIcon,'icon_on_open')
  local dest=s.raw.mode=='warm' and s.index==1 and s.raw.warmup or s.raw.samples;dest[#dest+1]=r
  native():hide();s.row=nil;s.raw.failedSample=nil;write();s.phase='next'
 end
end
function M.start(o)
 assert(not s or not s.running,'benchmark_running');assert(o.mode=='warm' or o.mode=='cold','mode_required')
 s={out=o.outputDir,started=now(),running=true,phase='ready',restore={},queries={globalAX=0,perWindowIcon=0},
  raw={run=o.run,mode=o.mode,status='incomplete',definition='native hs.chooser:isVisible true; not visible pixels',observerIntervalSeconds=.005,endpoint='first 5ms benchmark tick observing isVisible true after show returns; polling delay included',samples={},warmup={}}}
 package.path=o.sourceRoot..'/10bucks.spoon/?.lua;'..package.path
 local ok,err=pcall(function()
  assert(hs.accessibilityState() and #hs.screen.allScreens()==1,'environment_required')
  for _,app in ipairs(hs.application.runningApplications()) do for _,w in ipairs(app:allWindows()) do assert(not w:isStandard(),'empty_fixture_baseline_required') end end
  local c=dofile(o.sourceRoot..'/10bucks.spoon/init.lua').new();s.c=c
  c:configure({builtInDisplayUUID=hs.screen.allScreens()[1]:getUUID(),canaryInstrumentation=true,
   rules={{match={title='10bucks fixture D'},action='exclude'}}})
  local Adapter=require('lib.macos.chooser')
  wrap(Adapter,'show',function(old,a,...)
   if s.row then s.row.showCalled=now() end
   local r=table.pack(old(a,...)) -- show returns nil; do not manufacture a return value
   if s.row then s.row.showReturned=now() end
   return table.unpack(r,1,r.n)
  end)
  wrap(hs.getObjectMetatable('hs.chooser'),'delete',function(old,chooser,...)
   local owned=s.c and s.c.windowChooser and s.c.windowChooser.chooser==chooser
   if owned then s.invisibleBeforeDelete=chooser:isVisible()==false end
   local r=table.pack(old(chooser,...))
   if owned then s.chooserDeleted=true end
   return table.unpack(r,1,r.n)
  end)
  local at=now();c:start();s.raw.startup={at=at,finished=now()}
  -- Direct API call counters preserve arguments, returns, and production effect batches.
  for _,name in ipairs({'allWindows','visibleWindows','orderedWindows'}) do
   if hs.window[name] then wrap(hs.window,name,function(old,...) s.queries.globalAX=s.queries.globalAX+1;return old(...) end) end
  end
  wrap(hs.application,'runningApplications',function(old,...) s.queries.globalAX=s.queries.globalAX+1;return old(...) end)
  local appMethods=hs.getObjectMetatable('hs.application')
  for _,name in ipairs({'allWindows','visibleWindows'}) do
   if appMethods[name] then wrap(appMethods,name,function(old,...) s.queries.globalAX=s.queries.globalAX+1;return old(...) end) end
  end
  if appMethods.icon then wrap(appMethods,'icon',function(old,...) s.queries.perWindowIcon=s.queries.perWindowIcon+1;return old(...) end) end
  if hs.image.imageFromAppBundle then wrap(hs.image,'imageFromAppBundle',function(old,...) s.queries.perWindowIcon=s.queries.perWindowIcon+1;return old(...) end) end
  wrap(c,'_submitCommand',function(old,self,command,...)
   if command.type~='OpenWindowChooser' or not s.row then return old(self,command,...) end
   assert(not s.row.receipt,'duplicate_native_receipt');s.row.receipt=now()
   local r=table.pack(old(self,command,...));assert(r[1]==true,'chooser_command_rejected')
   assert(s.row.showReturned,'native_show_not_called');s.row.commandReturned=now();s.row.after=counts();return table.unpack(r,1,r.n)
  end)
  s.binding=hs.hotkey.bind({'cmd','alt','ctrl','shift'},'y',function() if s.row then assert(not s.row.serviceReceipt);s.row.serviceReceipt=now() end end)
  local Session=dofile(o.sourceRoot..'/functional-tests/fixture/session.lua');o.onOwned=function(f) s.fixture=f end;s.fixture=Session.new(o)
 end)
 if not ok then fail(tostring(err)) end
 s.timer=hs.timer.doEvery(.005,function()
  local success,reason=pcall(tick);if not success then fail(tostring(reason)) end
 end)
 return M.status()
end
function M.status() return {run=s.raw.run,running=s.running,phase=s.phase,error=s.raw.error} end
function M.stop() fail('operator_stop');return M.status() end
return M
