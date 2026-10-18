-- Load the distributed helper with the entire app broken, then repair over a
-- real KOReader subprocess. No app modules are on package.path or executed.
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
local util=require("util")
local lfs=require("libs/libkoreader-lfs")
local json=require("json")
local function read(path) local f=assert(io.open(path,"rb"));local value=f:read("*a");f:close();return value end
local function write(path,value) util.makePath(assert(path:match("^(.*)/[^/]+$")));local f=assert(io.open(path,"wb"));assert(f:write(value));f:close() end
local info=json.decode(read("/workspace/.cache/updater-tests/info.json"))
local parent="/tmp/kindlevel-recovery-ui/plugins"
local target=parent .. "/kindlevel.koplugin"
local helper=parent .. "/kindlevel-recovery.koplugin"
local archive=require("ffi/archiver").Reader:new();assert(archive:open(info.archive))
for entry in archive:iterate() do
    if entry.path:match("^kindlevel[%w-]*%.koplugin/") then write(parent .. "/" .. entry.path,assert(archive:extractToMemory(entry.path))) end
end
archive:close()

-- Exercise migration from an old updater: only the app folder was installed.
local bootstrap=dofile(target .. "/kindlevel_bootstrap.lua")
os.rename(helper,helper .. ".usb")
assert(bootstrap.installRecovery(target)==helper,"Wi-Fi upgrades install an independent helper")
local helperMain=read(helper .. "/main.lua")
write(target .. "/kindlevel_update_ui.lua","this is broken Lua")
assert(bootstrap.installRecovery(target)==helper and read(helper .. "/main.lua")==helperMain,"later app updates do not overwrite the recovery installation")
write(target .. "/kindlevel_app.lua","this is broken Lua too")
local fallback=dofile(target .. "/main.lua")
assert(fallback.controller,"bootstrap provides recovery when the app cannot load")

write(target .. "/main.lua","also broken")
write(target .. "/kindlevel_version.lua","error('Never execute the broken app version file')")
write(target .. "/kindlevel_updater.lua","error('Never execute the broken app updater')")
write(target .. "/custom_achievements.lua","return {} -- personal achievements")
local Loader=require("pluginloader")
Loader.enabled_plugins={};Loader.disabled_plugins={};Loader.loaded_plugins={}
Loader:_load{
    {main=target .. "/main.lua",meta=target .. "/_meta.lua",path=target,name="kindlevel",disabled=false},
    {main=helper .. "/main.lua",meta=helper .. "/_meta.lua",path=helper,name="kindlevel-recovery",disabled=false},
}
assert(#Loader.enabled_plugins==1 and Loader.enabled_plugins[1].name=="kindlevel-recovery","KOReader skips the broken app and loads recovery independently")
local Manager=require("apps/filemanager/filemanager")
Manager:showFiles(target .. "/books")
local owner=Manager.instance["kindlevel-recovery"]
assert(owner,"standalone recovery loads without Kindlevel")
local controller=owner:controller()
assert(controller.core.installed=="0.0.0","damaged app version is parsed safely, never executed")
local incoming=read("/workspace/.cache/updater-tests/valid.zip")
controller.core.transport={fetch=function(_,url,destination)
    if destination then write(destination,incoming);return true end
    return json.encode{tag_name="v" .. info.incoming,draft=false,prerelease=false,assets={{name="kindlevel-" .. info.incoming .. ".zip",size=#incoming,
        digest="sha256:" .. require("ffi/sha2").sha256(incoming),browser_download_url="https://github.com/senketsukamui/kindlevel/releases/download/v" .. info.incoming .. "/kindlevel-" .. info.incoming .. ".zip"}}}
end}
local network=require("ui/network/manager")
network.runWhenConnected=function(_,callback) callback() end
network.afterWifiAction=function() end
local finished=false
UIManager.restartKOReader=function()
    assert(read(target .. "/kindlevel_version.lua"):find(info.incoming,1,true),"recovery repaired the app")
    assert(read(controller.core.backup .. "/kindlevel_updater.lua"):find("broken app updater",1,true),"broken app files are retained in backup")
    assert(read(target .. "/custom_achievements.lua"):find("personal achievements",1,true),"personal files survive repair")
    assert(read(helper .. "/main.lua")==helperMain,"app repair leaves recovery untouched")
    assert(not package.loaded.kindlevel_version and not package.loaded.kindlevel_updater and not package.loaded.kindlevel_app,"no broken app modules were required")
    finished=true;UIManager:quit()
    print("ALL recovery UI checks passed: migration, independent loading, bootstrap fallback, damaged app/version/updater, Wi-Fi repair, backup, personal files and restart")
end
controller:check()
UIManager:scheduleIn(1,function()
    local confirm=UIManager:getTopmostVisibleWidget()
    assert(confirm.ok_text=="Install & restart","recovery offers a verified replacement")
    UIManager:forceRePaint();Device.screen.bb:writePNG("/workspace/dist/previews/recovery-update.png")
    UIManager:close(confirm);confirm.ok_callback()
end)
UIManager:scheduleIn(15,function() assert(finished,"Recovery UI test timed out") end)
UIManager:run()
