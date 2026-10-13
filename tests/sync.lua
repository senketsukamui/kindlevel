-- Real KOReader SQL adapter and durable outbox; no native statistics writes.
require("setupkoenv")
G_defaults=require("luadefaults"):open()
G_reader_settings=require("luasettings"):open("/tmp/kindlevel-sync-global.lua")
G_reader_settings:saveSetting("sdl_window",{width=1072,height=1448})
require("device")
local json=require("json")
local util=require("util")
local lfs=require("libs/libkoreader-lfs")
package.path="/workspace/kindlevel.koplugin/?.lua;" .. package.path
local Stats=require("kindlevel_stats")
local Goals=require("kindlevel_goals")
local Export=require("kindlevel_sync_export")
local Sync=require("kindlevel_sync")
local Net=require("kindlevel_sync_network")
local path="/workspace/.cache/sync-tests/statistics.sqlite3"
local now=os.time()
local stats=Stats:new{path=path,now=now}
local settings=require("luasettings"):open("/tmp/kindlevel-sync-owner.lua")
local owner={settings=settings}
function owner:getStats() return stats end
local goals=Goals:new{settings=settings,stats=stats}
function owner:getGoals() return goals end
local snapshot=Export.snapshot(owner,1)
local sums={}
for _,item in ipairs(snapshot.activity) do
    local day=sums[item.date] or {seconds=0,pages=0}
    day.seconds=day.seconds+item.seconds;day.pages=day.pages+item.pages;sums[item.date]=day
end
for date,day in pairs(stats:load().days) do assert(sums[date] and sums[date].seconds==day.seconds and sums[date].pages==day.pages,"export agrees with plugin daily metrics") end
assert(#snapshot.books==3 and #snapshot.achievements==42,"exports actual books and expandable achievements")
local encoded=json.encode(snapshot)
assert(not encoded:find("/workspace",1,true) and not encoded:find("/tmp/",1,true),"no device filesystem paths uploaded")
local stable=stats:query(function(conn) return conn:rowexec("SELECT count(*) FROM page_stat_data") end)
assert(Net.address("https://books.example.com:8443/",false)=="https://books.example.com:8443")
assert(Net.address("http://192.168.1.3:8080",true))
assert(Net.address("http://203.0.113.10",true),"public HTTP supported after explicit approval")
assert(not Net.address("http://203.0.113.10",false),"public HTTP requires approval")
for _,address in ipairs{"https://user:password@example.com","https://example.com/path","https://example.com?token=bad","http://256.1.1.1"} do assert(not Net.address(address,true),"unsafe server address rejected") end
local http=require("socket.http")
local realRequest=http.request
for _,case in ipairs{{"timeout","Connection timed out."},{"connection refused","Connection refused."},{"network is unreachable","No network route"},{"host not found","could not be resolved"}} do
    http.request=function() return nil,case[1] end
    local result,message=Net:new{allow_http=true}:request("http://192.168.1.50:8080","/api/v1/sync","{}","private-test-token")
    assert(not result and message:find(case[2],1,true) and message:find("http://192.168.1.50:8080",1,true),"diagnostic includes the address and transport cause")
    assert(not message:find("private-test-token",1,true),"credentials are not included in connection errors")
end
http.request=function() error("TLS certificate verification failed") end
local _,message=Net:new{allow_http=true}:request("http://192.168.1.50:8080","/api/v1/sync","{}")
assert(message:find("HTTPS verification or handshake failed",1,true),"network exceptions are classified")
http.request=realRequest
local folder="/tmp/kindlevel-sync-core";util.makePath(folder)
local failed=true;local firstBody;local accepted=0
local transport={request=function(_,server,path,body,secret)
    if path=="/api/v1/devices/pair" then return {device_id=string.rep("a",32),token=string.rep("b",43)} end
    assert(secret==string.rep("b",43),"device token supplied only to sync endpoint")
    local value=json.decode(body)
    if failed then firstBody=body;return nil,"offline" end
    if accepted==0 then assert(body==firstBody,"retry sends the saved snapshot unchanged") end
    accepted=accepted+1
    return {accepted_sequence=value.sequence,books=#value.books,activity=#value.activity,achievements=#value.achievements}
end}
local core=Sync:new{state_path=folder .. "/state.json",pending_path=folder .. "/pending.json",cafile="/workspace/kindlevel.koplugin/assets/cacert.pem",transport=transport}
core:forget()
assert(core:pair("https://books.example.com","ABCDE-FG234","Test Kindle",false))
assert(core:state().sequence==0)
local result,err=core:upload(owner);assert(not result and err=="offline" and lfs.attributes(core.pending_path),"failed upload keeps outbox")
failed=false
assert(core:upload(owner));assert(core:state().sequence==2 and not lfs.attributes(core.pending_path),"retry acknowledges older data and also uploads current history")
assert(core:upload(owner));assert(core:state().sequence==3,"later sync gets a new sequence")
assert(stats:query(function(conn) return conn:rowexec("SELECT count(*) FROM page_stat_data") end)==stable,"native statistics unchanged")
local saved=stats;stats=Stats:new{path="/tmp/kindlevel-nonexistent-sync.sqlite3"};goals.stats=stats
local empty=Export.snapshot(owner,3)
local emptyJSON=json.encode(empty)
assert(emptyJSON:find('"books":%[%]') and emptyJSON:find('"activity":%[%]'),"empty collections are JSON arrays")
stats=saved;goals.stats=stats
core:forget();assert(not core:state().token,"forget removes local credentials")
print("ALL sync checks passed: SQL parity, actual catalogue, addresses, durable retries, empty history, credentials and read-only data")
