-- Coordinator freezes this observer/candidate and the existing independent C
-- sender. Empty guest; no fixture/FT sampler. Arm before candidate startup.
local M,s={},nil
local function now() return hs.timer.absoluteTime()/1e9 end
local function save()
 local f=assert(io.open(s.out..'.tmp','w'));f:write(hs.json.encode(s.raw));f:close();assert(os.rename(s.out..'.tmp',s.out))
end
local function wrap(o,k,fn)
 local old=assert(o[k]);local replacement=function(...) return fn(old,...) end
 s.restore[#s.restore+1]={o,k,old,replacement};o[k]=replacement
end
function M.arm(o)
 assert(not s or not s.running,'observer_busy')
 s={running=true,out=o.outputFile,root=o.sourceRoot,restore={},jobs={},raw={run=o.run,status='armed',receipts={},metadata={},jobs={},inventory={},preparation={}}}
 s.binding=hs.hotkey.bind({},'y',function() s.raw.receipts[#s.raw.receipts+1]=now() end)
 save();return M.status()
end
function M.start()
 assert(s and s.running and not s.c,'arm_before_start')
 s.raw.startRequested=now()
 local ok,err=pcall(function()
 package.path=s.root..'/10bucks.spoon/?.lua;'..package.path
 local factory=require('lib.macos.regular_discovery');local Host=require('lib.macos.window_host')
 for _,name in ipairs({'prepare','inventory'}) do
  wrap(factory,name,function(old,...)
   local at=now();local r=table.pack(old(...));local row={at=at,finished=now()}
   if name=='inventory' then row.count=type(r[1])=='table' and #r[1] or 0 end
   local dest=name=='prepare' and s.raw.preparation or s.raw.inventory;dest[#dest+1]=row
   return table.unpack(r,1,r.n)
  end)
 end
 wrap(Host,'_metadata',function(old,...)
  local at=now();local r=table.pack(old(...));s.raw.metadata[#s.raw.metadata+1]={at=at,finished=now(),accepted=r[1]~=nil}
  return table.unpack(r,1,r.n)
 end)
 wrap(factory,'create',function(old,targets,...)
  local at=now();local r=table.pack(old(targets,...));local job=r[1]
  if job then
   local row={requested=at,returned=now(),targetCount=#targets,polls={}};s.jobs[#s.jobs+1]=job;s.raw.jobs[#s.raw.jobs+1]=row
   -- Native job identity is retained, not replaced with a proxy. One method
   -- table is wrapped once; lookup below observes only our original jobs.
   if not s.methods then
    s.methods=getmetatable(job).__index
    wrap(s.methods,'poll',function(prior,self,...)
     local at=now();local values=table.pack(prior(self,...));local result=values[1]
     for i,owned in ipairs(s.jobs) do if owned==self then
      local record=s.raw.jobs[i];record.polls[#record.polls+1]={at=at,finished=now(),done=result and result.done==true}
      if result and result.done and not record.terminal then
       record.terminal={at=now(),startedAt=result.startedAt,elapsedMs=result.elapsedMs,
        overshootMs=result.overshootMs,resultCount=#(result.results or {})}
      end
     end end
     return table.unpack(values,1,values.n)
    end)
    wrap(s.methods,'cancel',function(prior,self,...)
     for i,owned in ipairs(s.jobs) do if owned==self then s.raw.jobs[i].cancelledAt=now() end end
     return prior(self,...)
    end)
   end
  end
  return table.unpack(r,1,r.n)
 end)
  s.c=dofile(s.root..'/10bucks.spoon/init.lua').new()
  s.c:configure({builtInDisplayUUID=hs.screen.allScreens()[1]:getUUID(),canaryInstrumentation=true});s.c:start()
 end)
 s.raw.startReturned=now();s.raw.status=ok and 'started' or 'failed';s.raw.error=not ok and tostring(err) or nil
 save();return M.status()
end
function M.finish()
 assert(s and s.running and not s.finishing);s.finishing=true
 local failure
 local function attempt(fn) local ok,err=pcall(fn);if not ok then failure=failure or tostring(err) end;return ok end
 s.raw.beforeStop=now();if s.c and s.c.host then s.worker=s.c.host.validityWorker end
 s.raw.stopOK=attempt(function() if s.c then s.c:stop() end end);s.raw.stopReturned=now()
 local bindingDeleted=attempt(function() s.binding:delete() end)
 local deadline=now()+5
 local function complete(drained)
  local restored=true
  for i=#s.restore,1,-1 do local r=s.restore[i]
   local same=r[1][r[2]]==r[4]
   restored=attempt(function() r[1][r[2]]=r[3] end) and same and restored
  end
  if s.timer then attempt(function() s.timer:stop() end) end
  s.raw.error=s.raw.error or failure
  s.raw.cleanup={ok=not failure and s.raw.stopOK and drained and restored and bindingDeleted,
   nativeWorkersDrained=drained,wrappersRestored=restored,bindingDeleted=bindingDeleted}
  s.running=false;save()
 end
 local function drain()
  if now()>=deadline then complete(false);return end -- before fallible native calls
  local drained=true
  local ok=attempt(function()
   for i,job in ipairs(s.jobs) do local status=job:status();s.raw.jobs[i].drainedAfterStop=status.drained==true;drained=drained and status.drained==true end
   if s.worker then drained=drained and s.worker:status().drained==true end
  end)
  if not ok or drained then complete(ok and drained) end
 end
 if not attempt(function() s.timer=hs.timer.doEvery(.01,drain) end) then complete(false) end
 return M.status()
end
function M.status() return {run=s.raw.run,running=s.running,status=s.raw.status,receipts=#s.raw.receipts} end
return M
