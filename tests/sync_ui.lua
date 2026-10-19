-- Actual KOReader dialogs and subprocesses, including sync while a book is open.
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
local json=require("json")
local util=require("util")
local plugin="/workspace/kindlevel.koplugin"
package.path=plugin .. "/?.lua;plugins/statistics.koplugin/?.lua;" .. package.path
local root="/tmp/kindlevel-sync-ui/books";util.makePath(root)
local function read(path) local f=assert(io.open(path,"rb"));local v=f:read("*a");f:close();return v end
local function write(path,data) local f=assert(io.open(path,"wb"));f:write(data);f:close() end
write(root .. "/A Quiet Beginning.epub",read(plugin .. "/books/A Quiet Beginning.epub"))
local Kindlevel=dofile(plugin .. "/main.lua");Kindlevel.path=plugin
local Native=dofile("plugins/statistics.koplugin/main.lua");Native.path="plugins/statistics.koplugin"
local Loader=require("pluginloader")
Loader.enabled_plugins={Kindlevel,Native};Loader.disabled_plugins={};Loader.loaded_plugins={}
local settings=LuaSettings:open(DataStorage:getSettingsDir() .. "/kindlevel.lua")
settings:saveSetting("library_root",root);settings:saveSetting("auto_home",false);settings:flush()
local Manager=require("apps/filemanager/filemanager")
local Reader=require("apps/reader/readerui")
Manager:showFiles(root)
local owner=Manager.instance.kindlevel
local transport={request=function(_,server,path,body)
    if path=="/api/v1/devices/pair" then return {device_id=string.rep("a",32),token=string.rep("b",43)} end
    local data=json.decode(body)
    write("/tmp/kindlevel-sync-ui/payload.json",body)
    return {accepted_sequence=data.sequence,books=#data.books,activity=#data.activity,achievements=#data.achievements}
end}
local core=require("kindlevel_sync"):new{state_path="/tmp/kindlevel-sync-ui/state.json",pending_path="/tmp/kindlevel-sync-ui/pending.json",cafile=plugin .. "/assets/cacert.pem",transport=transport}
core:forget();owner.sync=core
local network=require("ui/network/manager")
network.runWhenOnline=function(_,callback) callback() end
network.afterWifiAction=function() end
owner:onKindlevel("settings")
local group_hit
for _, item in ipairs(owner.home.hits) do if item.id=="settings-connection" then group_hit=item;break end end
assert(group_hit,"settings group exists")
owner.home:onTapKindlevel(nil,{pos={x=group_hit.x+group_hit.w/2,y=group_hit.y+group_hit.h/2}})
local hit
for _,item in ipairs(owner.home.hits) do if item.id=="web-dashboard" then hit=item end end
assert(hit and hit.y+hit.h<owner.home:px(670),"dashboard settings button fits above footer")
UIManager:forceRePaint();Device.screen.bb:writePNG("/workspace/dist/previews/kindle-sync-settings.png")
owner:pairDashboard()
local dialog=UIManager:getTopmostVisibleWidget()
for i,value in ipairs{"https://books.example.com","ABCDE-FG234","Test Kindle"} do dialog.input_fields[i]:setText(value) end
UIManager:forceRePaint();Device.screen.bb:writePNG("/workspace/dist/previews/kindle-pairing.png")
UIManager:scheduleIn(0.1,function() dialog.buttons[1][2].callback() end)
UIManager:scheduleIn(1,function()
    assert(core:state().token,"pairing subprocess saved the device token")
    require("kindlevel_auto_sync"):stop()
    core:setAutomatic(false) -- This fixture exercises explicit foreground sync.
    UIManager:close(UIManager:getTopmostVisibleWidget())
    owner:openBook(owner.home.library.books[1])
end)
UIManager:scheduleIn(2,function()
    local reader=assert(Reader.instance)
    UIManager:sendEvent(require("ui/event"):new("Gesture",{ges="tap",pos=require("ui/geometry"):new{x=1000,y=1000,w=0,h=0}}))
    assert(reader.rolling.current_page>1,"page turn before sync")
    reader.kindlevel.sync=core
    reader.kindlevel:syncDashboard()
end)
UIManager:scheduleIn(3,function()
    local reader=assert(Reader.instance,"sync did not close the reader")
    assert(core:state().sequence==1 and not require("kindlevel_updater").busy,"sync acknowledged and released network lock")
    local payload=json.decode(read("/tmp/kindlevel-sync-ui/payload.json"))
    assert(#payload.books==1 and #payload.achievements==42,"actual open book and catalogue exported")
    assert(payload.books[1].progress_known and payload.books[1].progress>0 and payload.current_book==payload.books[1].id,"current book position saved before export")
    UIManager:forceRePaint();Device.screen.bb:writePNG("/workspace/dist/previews/kindle-sync-complete.png")
    reader:onClose();UIManager:quit()
    print("ALL sync UI checks passed: settings, pairing, subprocesses, open-book saving, uploads and retained reader")
end)
UIManager:scheduleIn(15,function() error("Sync UI test timed out") end)
UIManager:run()
