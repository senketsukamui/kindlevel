-- Native UI, cancellable subprocess download, normal book save and restart flow.
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
local Geom=require("ui/geometry")
local json=require("json")
local util=require("util")
local plugin="/workspace/kindlevel.koplugin"
package.path=plugin .. "/?.lua;plugins/statistics.koplugin/?.lua;" .. package.path
local function read(path) local f=assert(io.open(path,"rb"));local value=f:read("*a");f:close();return value end
local function write(path,data) util.makePath(path:match("^(.*)/[^/]+$"));local f=assert(io.open(path,"wb"));assert(f:write(data));f:close() end
local info=json.decode(read("/workspace/.cache/updater-tests/info.json"))
local target="/tmp/kindlevel-updater-ui/plugins/kindlevel.koplugin"
local archive=require("ffi/archiver").Reader:new();assert(archive:open(info.archive))
for entry in archive:iterate() do if entry.path:sub(1,19)=="kindlevel.koplugin/" then write(target .. "/" .. entry.path:sub(20),assert(archive:extractToMemory(entry.path))) end end
archive:close()
write(target .. "/custom_achievements.lua","return {} -- user extension\n")
local package=read("/workspace/.cache/updater-tests/valid.zip")
local incoming=info.incoming
local transport={fetch=function(_,url,destination)
    if destination then write(destination,package);return true end
    return json.encode{tag_name="v" .. incoming,draft=false,prerelease=false,assets={{name="kindlevel-" .. incoming .. ".zip",size=#package,
        digest="sha256:" .. require("ffi/sha2").sha256(package),browser_download_url="https://github.com/senketsukamui/kindlevel/releases/download/v" .. incoming .. "/kindlevel-" .. incoming .. ".zip"}}}
end}
local core=require("kindlevel_updater"):new{plugin_dir=target,work_dir="/tmp/kindlevel-updater-ui/work",transport=transport}
local Kindlevel=dofile(plugin .. "/main.lua");Kindlevel.path=plugin
local Native=dofile("plugins/statistics.koplugin/main.lua");Native.path="plugins/statistics.koplugin"
local Loader=require("pluginloader")
Loader.enabled_plugins={Kindlevel,Native};Loader.disabled_plugins={};Loader.loaded_plugins={}
local settings=LuaSettings:open(DataStorage:getSettingsDir() .. "/kindlevel.lua")
settings:saveSetting("library_root",target .. "/books");settings:saveSetting("auto_home",false);settings:flush()
local Manager=require("apps/filemanager/filemanager")
local Reader=require("apps/reader/readerui")
Manager:showFiles(target .. "/books")
local owner=Manager.instance.kindlevel
owner:onKindlevel("settings")
local update_hit
for _,hit in ipairs(owner.home.hits) do if hit.id=="check-updates" then update_hit=hit end end
assert(update_hit and update_hit.y+update_hit.h<owner.home:px(670),"update setting fits above the footer")
UIManager:forceRePaint();Device.screen.bb:writePNG("/workspace/dist/previews/settings-updater.png")
owner:openBook(owner.home.library.books[1])
local network=require("ui/network/manager")
network.runWhenOnline=function(_,callback) callback() end
network.afterWifiAction=function() end
local saved_file
UIManager.restartKOReader=function()
    assert(read(target .. "/kindlevel_version.lua"):find(incoming,1,true),"controller activated new files")
    assert(read(target .. "/custom_achievements.lua"):find("user extension",1,true),"custom definitions preserved")
    local cfg=require("docsettings"):open(saved_file)
    assert((cfg:readSetting("percent_finished") or 0)>0,"current book position was saved and preserved")
    local prefs=LuaSettings:open(DataStorage:getSettingsDir() .. "/kindlevel.lua")
    assert(next(prefs:readSetting("achievement_opened_books",{})) and #prefs:readSetting("achievement_session_breaks",{})>0,
        "reader achievement preferences were not overwritten by stale file-manager state")
    assert(not require("kindlevel_updater").busy,"network operation lock released")
    UIManager:quit()
    print("ALL updater UI checks passed: settings, offer, subprocesses, book/prefs preservation, activation and restart")
end
UIManager:scheduleIn(1,function()
    local reader=assert(Reader.instance)
    saved_file=reader.document.file
    UIManager:sendEvent(Event:new("Gesture",{ges="tap",pos=Geom:new{x=1000,y=1000,w=0,h=0}}))
    assert(reader.rolling.current_page>1,"real page turn before update")
    reader.kindlevel.updater=core
    reader.kindlevel:checkForUpdates()
end)
UIManager:scheduleIn(2,function()
    local confirm=UIManager:getTopmostVisibleWidget()
    assert(confirm.ok_text=="Install & restart","update confirmation shown")
    UIManager:forceRePaint();Device.screen.bb:writePNG("/workspace/dist/previews/update-offer.png")
    UIManager:close(confirm);confirm.ok_callback()
end)
UIManager:scheduleIn(15,function() error("Updater UI test timed out") end)
UIManager:run()
