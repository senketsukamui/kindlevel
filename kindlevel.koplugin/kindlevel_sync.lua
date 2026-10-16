local json=require("json")
local lfs=require("libs/libkoreader-lfs")
local util=require("util")
local ffiUtil=require("ffi/util")
local Sync={max_payload=8*1024*1024}
Sync.__index=Sync

local function read(path,limit)
    local size=lfs.attributes(path,"size")
    if not size then return nil end
    assert(size<=limit,"Local sync data is too large.")
    local file=assert(io.open(path,"rb"),"Cannot read sync data.")
    local value=file:read("*a");file:close();return value
end

local function write(path,value)
    util.makePath(path:match("^(.*)/[^/]+$"))
    local file=assert(io.open(path .. ".tmp","wb"),"Cannot save sync data. Check free space.")
    local ok=file:write(value)
    if not ok then file:close();error("Cannot save sync data. Check free space.") end
    local synced=ffiUtil.fsyncOpenedFile(file);file:close();assert(synced,"Cannot save sync data.")
    assert(os.rename(path .. ".tmp",path),"Cannot save sync data.")
    ffiUtil.fsyncDirectory(path:match("^(.*)/[^/]+$"))
end

function Sync:new(options)
    return setmetatable({state_path=options.state_path,pending_path=options.pending_path,cafile=options.cafile,transport=options.transport},self)
end

function Sync:state()
    local value=read(self.state_path,4096)
    local state=value and json.decode(value) or {}
    assert(type(state)=="table","Cannot read the server connection.")
    return state
end

-- Kept with the connection, rather than the per-widget preferences: ReaderUI
-- and FileManager may hold different copies of kindlevel.lua in memory.
function Sync:setAutomatic(enabled)
    local state=self:state()
    assert(state.token,"Pair this Kindle with your dashboard first.")
    state.auto_sync=enabled==true
    write(self.state_path,json.encode(state))
end

function Sync:recordAttempt(token,message)
    local state=self:state()
    if state.token~=token then return end
    state.last_attempt=os.time()
    state.last_error=message and util.fixUtf8(tostring(message):sub(1,768)) or nil
    write(self.state_path,json.encode(state))
end

function Sync:network(allow_http)
    return self.transport or require("kindlevel_sync_network"):new{cafile=self.cafile,allow_http=allow_http}
end

function Sync:pair(server,code,name,allow_http)
    local ok,result,err=pcall(function()
        local address,message=require("kindlevel_sync_network").address(server,allow_http)
        if not address then return nil,message end
        local response,failure=self:network(allow_http):request(address,"/api/v1/devices/pair",json.encode{code=code,name=name})
        if not response then return nil,failure end
        assert(type(response.token)=="string" and #response.token==43 and response.token:match("^[%w_-]+$") and type(response.device_id)=="string" and response.device_id:match("^[a-f0-9]+$") and #response.device_id==32,"The server returned invalid pairing credentials.")
        write(self.state_path,json.encode{server=address,token=response.token,device_id=response.device_id,name=name,allow_http=allow_http==true,sequence=0,auto_sync=true})
        os.remove(self.pending_path)
        return true
    end)
    if not ok then return nil,"Cannot save the server connection. Check the Kindle's storage and try again." end
    return result,err
end

function Sync:upload(owner)
    local ok,result,err=pcall(function()
        local state=self:state()
        assert(state.token and state.server,"Pair this Kindle with your dashboard first.")
        local pending=read(self.pending_path,self.max_payload)
        local passes=pending and 2 or 1
        local response
        for _=1,passes do
            if not pending then
                local payload=require("kindlevel_sync_export").snapshot(owner,(state.sequence or 0)+1)
                pending=json.encode(payload)
                assert(#pending<=self.max_payload,"Reading history is too large for this sync version.")
                write(self.pending_path,pending)
            end
            local payload=json.decode(pending)
            local message
            response,message=self:network(state.allow_http):request(state.server,"/api/v1/sync",pending,state.token)
            if not response then return nil,message end
            assert(response.accepted_sequence==payload.sequence,"The server did not confirm this reading snapshot.")
            local latest=self:state()
            assert(latest.token==state.token and latest.server==state.server,"The server connection changed during sync.")
            latest.sequence=payload.sequence;latest.last_sync=os.time();latest.last_error=nil
            write(self.state_path,json.encode(latest))
            state=latest
            assert(os.remove(self.pending_path),"Cannot clear the acknowledged snapshot. Check available storage.")
            pending=nil -- After retrying an older snapshot, also send current reading history.
        end
        return response
    end)
    if not ok then return nil,tostring(result):gsub("^.-:%d+:%s*","") end
    return result,err
end

function Sync:forget()
    os.remove(self.pending_path)
    os.remove(self.state_path)
end

return Sync
