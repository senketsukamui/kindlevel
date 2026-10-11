-- Test-only owner fixture is prepared locally; no user credentials are logged.
require("setupkoenv")
G_defaults=require("luadefaults"):open()
G_reader_settings=require("luasettings"):open("/tmp/kindlevel-live-sync-global.lua")
G_reader_settings:saveSetting("sdl_window",{width=1072,height=1448})
require("device")
package.path="/workspace/kindlevel.koplugin/?.lua;" .. package.path
local json=require("json")
local f=assert(io.open("/workspace/.cache/sync-tests/live.json","rb"));local fixture=json.decode(f:read("*a"));f:close()
local stats=require("kindlevel_stats"):new{path="/workspace/.cache/sync-tests/statistics.sqlite3"}
local settings=require("luasettings"):open("/tmp/kindlevel-live-sync-owner.lua")
local goals=require("kindlevel_goals"):new{stats=stats,settings=settings}
local owner={settings=settings,getStats=function() return stats end,getGoals=function() return goals end}
local core=require("kindlevel_sync"):new{state_path="/tmp/kindlevel-live-sync/state.json",pending_path="/tmp/kindlevel-live-sync/pending.json",cafile="/workspace/kindlevel.koplugin/assets/cacert.pem"}
assert(core:pair(fixture.server,fixture.code,"KOReader integration Kindle",true))
local response,err=core:upload(owner);assert(response,err)
assert(response.books==3 and response.achievements==42 and response.activity>0,"real Go backend accepted KOReader data")
assert(core:upload(owner),"second real sync succeeds")
local state=core:state()
local output=assert(io.open("/workspace/.cache/sync-tests/result.json","wb"));output:write(json.encode{device_id=state.device_id,sequence=state.sequence,books=response.books,activity=response.activity,achievements=response.achievements});output:close()
print("Verified native KOReader-to-Go HTTP pairing and repeated statistics uploads")
