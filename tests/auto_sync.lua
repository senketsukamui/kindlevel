-- Native KOReader reader, scheduler and forked uploads; no Internet required.
require("setupkoenv")
G_defaults=require("luadefaults"):open()
local LuaSettings=require("luasettings")
local DataStorage=require("datastorage")
G_reader_settings=LuaSettings:open(DataStorage:getDataDir() .. "/settings.reader.lua")
G_reader_settings:saveSetting("sdl_window",{width=1072,height=1448})
local Device=require("device")
require("document/canvascontext"):init(Device)
require("ui/bidi").setup()
local UIManager=require("ui/uimanager")
local Event=require("ui/event")
local json=require("json")
local util=require("util")
local lfs=require("libs/libkoreader-lfs")
local ffiUtil=require("ffi/util")
local plugin="/workspace/kindlevel.koplugin"
package.path=plugin .. "/?.lua;plugins/statistics.koplugin/?.lua;" .. package.path
local folder="/tmp/kindlevel-auto-sync";local root=folder .. "/books";util.makePath(root)
local function read(path) local f=assert(io.open(path,"rb"));local v=f:read("*a");f:close();return v end
local function write(path,data) local f=assert(io.open(path,"wb"));assert(f:write(data));f:close() end
write(root .. "/A Quiet Beginning.epub",read(plugin .. "/books/A Quiet Beginning.epub"))
local Kindlevel=dofile(plugin .. "/main.lua");Kindlevel.path=plugin
local Native=dofile("plugins/statistics.koplugin/main.lua");Native.path="plugins/statistics.koplugin"
local Loader=require("pluginloader")
Loader.enabled_plugins={Kindlevel,Native};Loader.disabled_plugins={};Loader.loaded_plugins={}
local settings=LuaSettings:open(DataStorage:getSettingsDir() .. "/kindlevel.lua")
settings:saveSetting("library_root",root);settings:saveSetting("auto_home",false);settings:flush()
local network=require("ui/network/manager")
local connected=false
network.isWifiOn=function() return connected end
network.isConnected=function() return connected end
network.isOnline=function() error("automatic sync must not require WAN access") end
network.runWhenOnline=function() error("automatic sync must not prompt for Wi-Fi") end
network.afterWifiAction=function() error("automatic sync must not change Wi-Fi") end
local Auto=require("kindlevel_auto_sync")
Auto.poll_interval=0.1
local Updater=require("kindlevel_updater")
local Manager=require("apps/filemanager/filemanager")
local Reader=require("apps/reader/readerui")
local mode="fail"
local transport={request=function(_,_,path,body)
    if path=="/api/v1/devices/pair" then return {device_id=string.rep("a",32),token=string.rep("b",43)} end
    write(folder .. "/request.json",body)
    require("socket").sleep(mode=="slow" and 4 or mode=="success" and 1 or 0.2)
    if mode=="fail" then return nil,"Test server is offline." end
    local payload=json.decode(body)
    return {accepted_sequence=payload.sequence,books=#payload.books,activity=#payload.activity,achievements=#payload.achievements}
end}
local core=require("kindlevel_sync"):new{state_path=folder .. "/state.json",pending_path=folder .. "/pending.json",transport=transport}
core:forget();assert(core:pair("https://books.example.com","ABCDE-FG234","Test Kindle"))
local function waitFor(predicate,callback,remaining)
    remaining=remaining or 100
    UIManager:scheduleIn(0.1,function()
        if predicate() then callback() else
            assert(remaining>0,"automatic sync test timed out waiting for a condition")
            waitFor(predicate,callback,remaining-1)
        end
    end)
end
local function turnPage()
    local page=Reader.instance.rolling.current_page
    UIManager:sendEvent(Event:new("Gesture",{ges="tap",pos=require("ui/geometry"):new{x=1000,y=1000,w=0,h=0}}))
    assert(Reader.instance.rolling.current_page>page,"page turns work during a background upload")
end
local owner,baseline
local function fastStart()
    os.remove(folder .. "/request.json")
    Auto:stop();Auto:arm(0.1)
end
local function finish()
    assert(not Updater.busy and UIManager._prevent_standby_count==baseline,"network and standby locks released")
    owner:dashboardConnection()
    UIManager:forceRePaint()
    Device.screen.bb:writePNG("/workspace/dist/previews/kindle-auto-sync.png")
    UIManager:close(UIManager:getTopmostVisibleWidget())
    core:forget();owner:onNetworkConnected();assert(not Auto.timer,"forgotten connections do not sync")
    Reader.instance:onClose();UIManager:quit()
    print("ALL automatic sync checks passed: Wi-Fi events, quiet retries, live page turns, pending snapshots, toggle persistence, disconnect, suspend/resume, foreground priority and worker cleanup")
end
local function testSuspendAndPriority()
    mode="slow";fastStart()
    waitFor(function() return Auto.job and lfs.attributes(folder .. "/request.json") end,function()
        local pid=Auto.job.pid
        owner:onSuspend()
        assert(Auto.suspended and not Auto.job and not Auto.timer and not Updater.busy and ffiUtil.isSubProcessDone(pid),"suspend kills and reaps the worker")
        owner:onNetworkConnected();assert(not Auto.timer,"suspend suppresses connection events")
        owner:onResume();assert(Auto.timer,"resume schedules sync on an existing connection")
        Auto:stop();Updater.busy=true;Auto:run()
        assert(Auto.timer and not Auto.job,"manual network jobs take priority")
        Updater.busy=false;Auto:stop()
        -- Startup while already connected needs no new NetworkConnected event.
        Auto.retry_at=nil;core:recordAttempt(core:state().token,nil)
        Auto:wake();assert(Auto.timer,"startup with Wi-Fi already connected schedules work")
        Auto:stop();finish()
    end)
end
local function testDisableAndDisconnect()
    mode="slow";fastStart()
    waitFor(function() return Auto.job and lfs.attributes(folder .. "/request.json") end,function()
        local pid=Auto.job.pid
        -- Use the actual menu toggle, which must cancel before saving its state.
        owner:dashboardConnection()
        local dialog=UIManager:getTopmostVisibleWidget()
        assert(dialog.buttons[3][1].text=="Automatic sync: on")
        dialog.buttons[3][1].callback()
        assert(core:state().auto_sync==false and not Auto.job and not Auto.timer,"disabling is persistent and cancels the worker")
        assert(ffiUtil.isSubProcessDone(pid) and not Updater.busy,"cancelled child is reaped and network lock released")
        UIManager:close(UIManager:getTopmostVisibleWidget())
        owner:onNetworkConnected();assert(not Auto.timer,"disabled setting blocks automatic sync")
        assert(lfs.attributes(core.pending_path),"cancellation retains the durable outbox")
        core:setAutomatic(true);fastStart()
        waitFor(function() return Auto.job and lfs.attributes(folder .. "/request.json") end,function()
            pid=Auto.job.pid;connected=false;owner:onNetworkDisconnected()
            assert(not Auto.job and not Auto.timer and ffiUtil.isSubProcessDone(pid),"disconnect cancels and reaps the worker")
            connected=true;owner:onNetworkConnected();assert(Auto.timer,"reconnecting retries pending history")
            testSuspendAndPriority()
        end)
    end)
end
local function testRetry()
    assert(core:state().last_error=="Test server is offline." and lfs.attributes(core.pending_path),"failure is quiet, saved, and retryable")
    assert(Auto.due-os.time()>=58 and Auto.due-os.time()<=60,"first retry backs off one minute")
    local pending=read(core.pending_path)
    mode="success";fastStart()
    waitFor(function() return Auto.job and lfs.attributes(folder .. "/request.json") end,function()
        assert(read(folder .. "/request.json")==pending,"background retries send identical pending snapshots")
        turnPage()
        waitFor(function() return not Auto.job end,function()
            assert(core:state().sequence==2 and not core:state().last_error,"retry uploads pending and current history and clears the error")
            assert(not lfs.attributes(core.pending_path),"successful uploads clear the outbox")
            assert(Auto.due-os.time()>=298 and Auto.due-os.time()<=300,"periodic sync waits five minutes")
            local payload=json.decode(read(folder .. "/request.json"))
            assert(#payload.books==1 and payload.books[1].progress_known and #payload.achievements==42,"exports the real open reader and achievements")
            testDisableAndDisconnect()
        end)
    end)
end
Manager:showFiles(root)
Manager.instance.kindlevel.sync=core
Reader:showReader(root .. "/A Quiet Beginning.epub")
UIManager:scheduleIn(0.2,function()
    owner=assert(Reader.instance).kindlevel;owner.sync=core
    baseline=UIManager._prevent_standby_count
    owner:onNetworkConnected();assert(not Auto.timer and not Auto.job,"offline startup never enables Wi-Fi")
    connected=true
    UIManager:broadcastEvent(Event:new("NetworkConnected"))
    local timer=assert(Auto.timer,"Wi-Fi event schedules automatic sync")
    owner:onNetworkConnected();assert(Auto.timer==timer,"repeated events do not create duplicate jobs")
    fastStart()
    waitFor(function() return Auto.job~=nil end,function()
        turnPage()
        assert(UIManager:getTopmostVisibleWidget()==Reader.instance,"background upload has no modal widget")
        waitFor(function() return not Auto.job end,testRetry)
    end)
end)
UIManager:scheduleIn(35,function() error("Automatic sync test timed out") end)
UIManager:run()
