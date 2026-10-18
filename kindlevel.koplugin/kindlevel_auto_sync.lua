-- One coordinator shared by ReaderUI and FileManager. Uploads run in a child
-- process; UI callbacks only prepare a snapshot, poll completion and reschedule.
local UIManager=require("ui/uimanager")
local NetworkMgr=require("ui/network/manager")
local ffiUtil=require("ffi/util")
local json=require("json")
local logger=require("logger")
local Auto={interval=300,minimum_interval=60,poll_interval=0.5,timeout=240}

function Auto:owner()
    local ui=require("apps/reader/readerui").instance or require("apps/filemanager/filemanager").instance
    return ui and ui.kindlevel
end

function Auto:connected()
    -- A local dashboard needs a network address, not a successful WAN probe.
    return NetworkMgr:isWifiOn() and NetworkMgr:isConnected()
end

function Auto:state()
    local owner=self:owner()
    if not owner then return end
    local core=owner:getSync()
    local ok,state=pcall(core.state,core)
    if ok and state.token and state.auto_sync~=false then return owner,core,state end
end

function Auto:arm(delay)
    local due=os.time()+delay
    if self.timer and self.due==due then return end
    if self.timer then UIManager:unschedule(self.timer) end
    self.due=due
    self.timer=function() self.timer=nil;self.due=nil;self:run() end
    UIManager:scheduleIn(delay,self.timer)
end

function Auto:wake(reconnected)
    if self.suspended or self.job or not self:connected() then return end
    local owner,_,state=self:state()
    if not owner then return end
    local now=os.time()
    local due=self.retry_at or (state.last_sync or 0)+self.interval
    if reconnected then
        due=math.max((self.last_attempt or 0)+self.minimum_interval,(state.last_sync or 0)+self.minimum_interval)
        self.retry_at=nil
    end
    self:arm(math.max(2,due-now))
end

local function readResult(path)
    local file=io.open(path,"rb")
    if not file then return end
    local value=file:read(16385);file:close()
    if not value or #value>16384 then return end
    local ok,result=pcall(json.decode,value)
    if ok and type(result)=="table" then return result end
end

function Auto:finish(message)
    local job=self.job
    if not job then return end
    self.job=nil
    if self.poll then UIManager:unschedule(self.poll);self.poll=nil end
    os.remove(job.result_path)
    require("kindlevel_updater").busy=false
    UIManager:allowStandby()
    pcall(job.core.recordAttempt,job.core,job.token,message)
    self.failures=message and (self.failures or 0)+1 or 0
    local delay=message and ({60,300,900})[math.min(self.failures,3)] or self.interval
    self.retry_at=os.time()+delay
    -- Never log server responses or credentials. Details stay in the local menu.
    if message then logger.info("Kindlevel: automatic sync deferred") end
    self:wake()
end

function Auto:stop(suspended)
    if suspended~=nil then self.suspended=suspended end
    if self.timer then UIManager:unschedule(self.timer);self.timer=nil;self.due=nil end
    if self.poll then UIManager:unschedule(self.poll);self.poll=nil end
    local job=self.job
    if job then
        if not ffiUtil.isSubProcessDone(job.pid) then
            -- This worker only runs Lua/HTTP. Target its pid directly, including
            -- the short window before runInSubProcess sets its process group.
            require("ffi").C.kill(job.pid,9)
            ffiUtil.isSubProcessDone(job.pid,true)
        end
        self.job=nil
        os.remove(job.result_path)
        require("kindlevel_updater").busy=false
        UIManager:allowStandby()
    end
end

function Auto:run()
    if self.suspended or self.job or not self:connected() then return end
    local owner,core,state=self:state()
    if not owner then return end
    local updater=require("kindlevel_updater")
    if updater.busy or (package.loaded.kindlevel_update_activity or {}).busy then self:arm(15);return end
    self.last_attempt=os.time()
    local prepared=pcall(owner.prepareDashboardSync,owner)
    if not prepared then
        pcall(core.recordAttempt,core,state.token,"Cannot prepare reading history. Close the book and try again.")
        self.retry_at=os.time()+300;self:wake();return
    end
    local result_path=core.pending_path .. ".result"
    require("util").makePath(result_path:match("^(.*)/[^/]+$"))
    os.remove(result_path)
    updater.busy=true
    UIManager:preventStandby()
    local ok,pid=pcall(ffiUtil.runInSubProcess,function()
        local success,result,err=pcall(core.upload,core,owner)
        local message
        if not success then message="Automatic sync failed. Try Sync now for details."
        elseif not result then message=err or "Automatic sync failed. It will retry." end
        local file=io.open(result_path,"wb")
        if file then
            file:write(json.encode{ok=success and result~=nil,error=message and require("util").fixUtf8(tostring(message):sub(1,768))})
            file:close()
        end
    end)
    self.job={core=core,token=state.token,pid=ok and pid or nil,result_path=result_path,started=os.time(),owner=owner}
    if not ok or not pid then self:finish("Cannot start automatic sync. Try Sync now.");return end
    self.poll=function()
        local job=self.job
        if not job then return end
        if ffiUtil.isSubProcessDone(job.pid) then
            local result=readResult(job.result_path)
            local message
            if not result or not result.ok then message=result and result.error or "Automatic sync was interrupted. It will retry." end
            self:finish(message)
        elseif os.time()-job.started>=self.timeout then
            self:stop()
            pcall(core.recordAttempt,core,state.token,"Automatic sync timed out. It will retry.")
            self.retry_at=os.time()+300;self:wake()
        else UIManager:scheduleIn(self.poll_interval,self.poll) end
    end
    UIManager:scheduleIn(self.poll_interval,self.poll)
end

return Auto
