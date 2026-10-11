-- Owned guest POC; controlled 200ms worker hold is cancellation evidence ONLY.
local M={rows={},costs={set={},poll={}},posts={},downs={},ups={},cancellations={},workers={},running=true,drops=0}
local function now()return hs.timer.absoluteTime()/1e9 end
local function timed(kind,fn)local t=now();local r=table.pack(fn());M.costs[kind][#M.costs[kind]+1]=(now()-t)*1000;return table.unpack(r,1,r.n)end
local function exact(window)
 local app=window and window:application()
 return M.app and app==M.app and app:path()=='/Applications/Ghostty.app'
  and app:pid()==M.pid and hs.application.applicationForPID(M.pid)==M.app
  and hs.window.focusedWindow()==window
end
local function worker(delay)
 local w=M.native.create(delay or 0);M.workers[#M.workers+1]=w;M.worker=w;return w
end
local function collect()
 local rows,dropped=timed('poll',function()return M.worker:poll()end)
 M.drops=M.drops+dropped;assert(dropped==0,'dropped')
 for _,r in ipairs(rows)do r.delivered_at=now();assert(r.token==1,'stale token');M.rows[#M.rows+1]=r end
 return rows
end
local function writeResult(cleanup)
 M.running=false
 local r={running=false,error=M.error,phase=M.phase,rows=M.rows,costs=M.costs,posts=M.posts,downs=M.downs,ups=M.ups,
 closeAt=M.closeAt,detect=M.detect,cancellations=M.cancellations,drained=M.drained,stopCost=M.stopCost,
 launchExit=M.launchExit,launchSubmitted=M.launchSubmitted,launchResolved=M.launchResolved,
 drops=M.drops,cleanup=cleanup,measurementPass=not M.error and cleanup.ok and M.detect~=nil and M.drained==true}
 local f=assert(io.open(M.root..'/poc-result.json','w'));assert(f:write(hs.json.encode(r)));assert(f:close())
end
function M.cleanupTick()
 local app=hs.application.get('com.mitchellh.ghostty')
 if M.launchSubmitted and not M.app and app then
  assert(app:path()=='/Applications/Ghostty.app','cleanup path')
  M.app=app;M.pid=app:pid();M.launchResolved=true
 end
 if M.app and not M.quitRequested then M.quitRequested=true;M.app:kill()end
 local drained=true
 for _,w in ipairs(M.workers)do if not w:status().drained then drained=false end end
 local exited=not M.launchSubmitted or (M.launchResolved==true and M.app~=nil and hs.application.applicationForPID(M.pid)==nil)
 local launchDone=not M.launchSubmitted or (M.launchExit==0 and M.launch and not M.launch:isRunning())
 local done=drained and exited and launchDone
 if done or now()-M.cleanupAt>=3 then
  if not done then M.error=M.error or 'cleanup_unresolved' end
  if M.launch and M.launch:isRunning()then M.launchForced=true;M.launch:terminate()end
  M.cleanupTimer:stop();M.cleanupTimer=nil
  writeResult({ok=done and not M.launchForced and M.bindingDeleted and M.timersStopped,
   workersDrained=drained,appExited=exited,launchNormal=launchDone,launchForced=M.launchForced==true,
   bindingDeleted=M.bindingDeleted,timersStopped=M.timersStopped,cleanupTimerStopped=true})
 end
end
function M.stop()
 if M.phase=='cleanup'or not M.running then return {running=M.running,error=M.error}end
 M.phase='cleanup';M.cleanupAt=now()
 if M.timer then M.timer:stop();M.timer=nil end
 if M.deadline then M.deadline:stop();M.deadline=nil end
 M.timersStopped=true
 for _,w in ipairs(M.workers)do w:stop()end
 if M.binding then M.binding:delete();M.binding=nil end;M.bindingDeleted=true
 M.cleanupTimer=hs.timer.doEvery(.01,function()
  local ok=pcall(M.cleanupTick)
  if not ok then
   M.error=M.error or 'cleanup_exception'
   if now()-M.cleanupAt>=3 then
    M.cleanupTimer:stop();M.cleanupTimer=nil
    writeResult({ok=false,cleanupTimerStopped=true})
   end
  end
 end)
 return {running=true,error=M.error,phase='cleanup'}
end
function M.start(root)
 M.root=root;M.started=now();M.phase='setup'
 -- Watchdog precedes module/binding/task setup; failures enter bounded cleanup.
 local ok=pcall(function()
  M.deadline=assert(hs.timer.doAfter(12,function()M.error=M.error or 'deadline';M.stop()end))
  assert(not hs.application.get('com.mitchellh.ghostty'),'owned app must be absent')
  M.native=assert(package.loadlib(root..'/ax_probe.so','luaopen_ax_probe'))()
  assert(hs.hotkey.assignable({'ctrl','alt','cmd','shift'},'y'),'key unavailable')
  M.binding=assert(hs.hotkey.bind({'ctrl','alt','cmd','shift'},'y',function()M.downs[#M.downs+1]=now()end,function()M.ups[#M.ups+1]=now()end),'binding failed')
  M.launch=assert(hs.task.new('/usr/bin/open',function(code)M.launchExit=code end,{'-na','/Applications/Ghostty.app','--args','--window-save-state=never','--initial-window=true','--command=/bin/zsh -f','--confirm-close-surface=false'}))
  M.launchSubmitted=true;assert(M.launch:start());M.phase='launch'
  M.timer=assert(hs.timer.doEvery(.01,function()
   local success=pcall(M.tick)
   if not success then M.error='poc_stage_'..M.phase;M.stop()end
  end))
 end)
 if not ok then M.error='poc_setup';M.stop()end
 return {running=M.running,error=M.error}
end
function M.tick()
 local t=now()
 if M.phase=='launch'then
  local a=hs.application.get('com.mitchellh.ghostty');local w=hs.window.focusedWindow()
  if a then assert(a:path()=='/Applications/Ghostty.app');M.app=a;M.pid=a:pid();M.launchResolved=true end
  if a and w and exact(w)and w:isStandard()then
   M.A=w;assert(exact(M.A));hs.eventtap.keyStroke({'cmd'},'n',0);M.phase='join';M.joinAt=t
  elseif t-M.started>3 then error('launch')end
 elseif M.phase=='join'then
  local w=hs.window.focusedWindow()
  if w and w~=M.A and exact(w)and w:isStandard()then
   local added={};for _,v in ipairs(M.app:allWindows())do if v:isStandard()and v~=M.A then added[#added+1]=v end end
   assert(#added==1 and added[1]==w)
   M.B=w;M.ax=hs.axuielement.windowElement(w);assert(M.ax:isValid()==true)
   worker();M.token=1
   for _=1,30 do timed('set',function()M.worker:set(M.ax,M.token)end)end
   M.phase='calibrate';M.calibrateAt=t
   hs.eventtap.event.newKeyEvent({'ctrl','alt','cmd','shift'},'y',true):post()
   hs.eventtap.event.newKeyEvent({'ctrl','alt','cmd','shift'},'y',false):post()
  elseif t-M.joinAt>3 then error('join')end
 elseif M.phase=='calibrate'then
  if #M.downs==1 and #M.ups==1 then
   M.downs={};M.ups={};M.phase='measure';M.measureAt=t;M.sent=0
  elseif t-M.calibrateAt>.5 then error('sender calibration')end
 elseif M.phase=='measure'then
  collect()
  if M.sent<100 and t-(M.lastPost or 0)>=.02 then
   M.sent=M.sent+1;M.posts[#M.posts+1]=now();M.lastPost=t
   hs.eventtap.event.newKeyEvent({'ctrl','alt','cmd','shift'},'y',true):post()
   hs.eventtap.event.newKeyEvent({'ctrl','alt','cmd','shift'},'y',false):post()
  end
  if #M.rows>=30 and #M.downs==100 and #M.ups==100 then
   assert(exact(M.B)and M.ax:isValid()==true,'exact B focus')
   M.closeAt=now();hs.eventtap.keyStroke({'ctrl'},'d',0);M.phase='detect'
  elseif t-M.measureAt>5 then error('measure')end
 elseif M.phase=='detect'then
  for _,r in ipairs(collect())do
   if r.status=='invalid'and r.sampled_at>=M.closeAt then
    assert(r.token==1 and r.sampled_at+r.query_seconds<=M.closeAt+.25
     and r.delivered_at<=M.closeAt+.25 and now()<=M.closeAt+.25,'late detection')
    M.detect=r;M.stopCost=M.worker:stop()*1000;M.phase='drain';break
   end
  end
  if now()-M.closeAt>.25 then error('detection')end
 elseif M.phase=='drain'then
  if M.worker:status().drained then
   assert(hs.axuielement.windowElement(M.A):isValid()==true)
   worker(200):set(hs.axuielement.windowElement(M.A),10);M.phase='cancelReplace'
  end
 elseif M.phase=='cancelReplace'then
  if M.worker:status().inflight then
   local t0=now();M.worker:set(nil,11);M.cancellations[#M.cancellations+1]={kind='replace',inflight=true,costMs=(now()-t0)*1000};M.cancelAt=t;M.phase='cancelWait'
  end
 elseif M.phase=='cancelWait'then
  if t-M.cancelAt>.3 and not M.worker:status().inflight then
   local rows,dropped=M.worker:poll();assert(#rows==0 and dropped==0,'stale result')
   M.cancellations[1].completed=true
   assert(hs.axuielement.windowElement(M.A):isValid()==true)
   M.worker:set(hs.axuielement.windowElement(M.A),12);M.phase='cancelStop'
  end
 elseif M.phase=='cancelStop'then
  if M.worker:status().inflight then
   M.cancellations[#M.cancellations+1]={kind='stop',inflight=true,costMs=M.worker:stop()*1000};M.phase='finalDrain'
  end
 elseif M.phase=='finalDrain'then
  if M.worker:status().drained then
   local rows,dropped=M.worker:poll();assert(#rows==0 and dropped==0)
   M.drained=true;M.stop()
  end
 end
end
return M
