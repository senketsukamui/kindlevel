require("setupkoenv")
G_defaults=require("luadefaults"):open()
G_reader_settings=require("luasettings"):open("/tmp/kindlevel-updater-reader.lua")
G_reader_settings:saveSetting("sdl_window",{width=1072,height=1448})
local Device=require("device")
require("document/canvascontext"):init(Device)
require("ui/bidi").setup()
package.path="/workspace/kindlevel.koplugin/?.lua;" .. package.path
local U=require("kindlevel_updater")
local Network=require("kindlevel_update_network")
local lfs=require("libs/libkoreader-lfs")
local util=require("util")
local json=require("json")
local fixtures="/workspace/.cache/updater-tests/"
local function read(path) local f=assert(io.open(path,"rb"));local text=f:read("*a");f:close();return text end
local function write(path,text) util.makePath(assert(path:match("^(.*)/[^/]+$")));local f=assert(io.open(path,"wb"));assert(f:write(text));f:close() end
assert(U.compare("0.10.0","0.9.9")==1 and U.compare("0.5.0","0.5.0-dev")==1,"numeric release/prerelease ordering")
assert(U.compare("0.5.0-beta.10","0.5.0-beta.2")==1,"numeric prerelease identifiers")
assert(U.compare("v0.4.0","0.4.0")==0 and not U.version("not-a-version"),"version validation")
assert(Network.allowed("https://api.github.com/repos/senketsukamui/kindlevel/releases/latest"),"GitHub HTTPS is allowed")
for _,url in ipairs{"http://github.com/a","https://github.com.evil/a","https://user:pass@github.com/a","https://github.com:444/a","file:///tmp/a"} do assert(not Network.allowed(url),"rejected network URL: " .. url) end
local function certificate(names) return {extensions=function() return {["2.5.29.17"]={dNSName=names}} end} end
assert(Network.certificateMatches(certificate{"*.github.com"},"api.github.com"),"single-label wildcard SAN")
assert(not Network.certificateMatches(certificate{"*.github.com"},"x.api.github.com"),"wildcard cannot span labels")
assert(not Network.certificateMatches(certificate{"github.com"},"api.github.com"),"hostname mismatches fail")
assert(not Network.certificateMatches(certificate{},"github.com"),"missing SAN fails closed")
local info=json.decode(read(fixtures .. "info.json"))
local current,incoming=info.current,info.incoming
local zip_name="kindlevel-" .. incoming .. ".zip"
local asset_url="https://github.com/senketsukamui/kindlevel/releases/download/v" .. incoming .. "/" .. zip_name
local package=read(fixtures .. "valid.zip")
local template={tag_name="v" .. incoming,draft=false,prerelease=false,body="Test release",assets={{name=zip_name,size=#package,
    digest="sha256:" .. require("ffi/sha2").sha256(package),browser_download_url=asset_url}}}
local serial=0
local function make(options)
    serial=serial+1
    local base="/tmp/kindlevel-update-" .. serial
    util.makePath(base .. "/plugins/kindlevel.koplugin")
    local target=base .. "/plugins/kindlevel.koplugin"
    local archive=require("ffi/archiver").Reader:new()
    assert(archive:open(info.archive))
    for entry in archive:iterate() do
        if entry.path:sub(1,19)=="kindlevel.koplugin/" then
            write(target .. "/" .. entry.path:sub(20),assert(archive:extractToMemory(entry.path)))
        end
    end
    archive:close()
    write(target .. "/custom_achievements.lua","return {} -- personal\n")
    write(target .. "/assets/my-icon.svg","personal icon")
    write(target .. "/books/A Quiet Beginning.sdr/metadata.epub.lua","return {percent_finished=0.75}")
    write(base .. "/settings/statistics.sqlite3","history stays outside plugin")
    local transport={}
    function transport:fetch(url,destination,limit)
        if options and options.failure then return nil,"expected network failure" end
        if destination then write(destination,package);return true end
        if options and options.fallback and url:find("api.github.com",1,true) then return nil,"expected rate limit" end
        if url=="https://github.com/senketsukamui/kindlevel/releases/latest" then
            return "public release page",nil,19,"https://github.com/senketsukamui/kindlevel/releases/tag/v" .. incoming
        end
        if url:sub(-7)==".sha256" then return template.assets[1].digest:sub(8) .. "  " .. zip_name .. "\n" end
        return json.encode(template)
    end
    return U:new{plugin_dir=target,work_dir=base .. "/work",transport=transport,installed=current,rename=options and options.rename},base
end
local core,base=make()
local release=assert(core:check())
assert(release.newer and release.version==incoming,"release metadata selection")
local invalid=json.decode(json.encode(template));invalid.prerelease=true
assert(not pcall(core.selectRelease,core,invalid),"prereleases are excluded")
invalid=json.decode(json.encode(template));invalid.assets[1].browser_download_url="https://github.com/other/repo/a.zip"
assert(not pcall(core.selectRelease,core,invalid),"asset must belong to this repository")
assert(core:prepare(release),"download/hash/manifest/staging")
assert(read(core.plugin_dir .. "/kindlevel_version.lua"):find(current,1,true),"staging leaves current plugin intact")
write(core.plugin_dir .. "/books/A Quiet Beginning.sdr/metadata.epub.lua","return {percent_finished=0.90}")
assert(core:activate(release),"activate staged update")
assert(read(core.plugin_dir .. "/kindlevel_version.lua"):find(incoming,1,true),"new version installed")
assert(read(core.plugin_dir .. "/custom_achievements.lua"):find("personal",1,true),"custom achievements preserved")
assert(read(core.plugin_dir .. "/assets/my-icon.svg")=="personal icon","custom icon preserved")
assert(read(core.plugin_dir .. "/books/A Quiet Beginning.sdr/metadata.epub.lua"):find("0.90",1,true),"sidecars saved after download are preserved")
assert(read(base .. "/settings/statistics.sqlite3")=="history stays outside plugin","history not modified")
assert(read(core.backup .. "/kindlevel_version.lua"):find(current,1,true),"previous plugin kept as backup")

local rollback=make{rename=function(from,to)
    if from:sub(-16)==".kindlevel-stage" then return nil,"expected activation failure" end
    return os.rename(from,to)
end}
local rr=assert(rollback:check());assert(rollback:prepare(rr))
local original_rename=rollback.rename
rollback.rename=function(from,to) if from==rollback.stage then return nil,"expected activation failure" end return os.rename(from,to) end
assert(not rollback:activate(rr),"rename failure reported")
assert(read(rollback.plugin_dir .. "/kindlevel_version.lua"):find(current,1,true),"activation failure restores old plugin")

local modified=make();local mr=assert(modified:check());assert(modified:prepare(mr))
write(modified.plugin_dir .. "/assets/achievements/book.svg","personal replacement icon")
assert(modified:activate(mr))
assert(read(modified.plugin_dir .. "/assets/achievements/book.svg")=="personal replacement icon","modified built-in asset preserved")
local edited=make();local er=assert(edited:check());assert(edited:prepare(er))
write(edited.plugin_dir .. "/kindlevel_achievement_catalog.lua","return {} -- personal edits")
assert(not edited:activate(er),"modified built-in Lua is not silently overwritten")
assert(read(edited.plugin_dir .. "/kindlevel_achievement_catalog.lua"):find("personal edits",1,true),"local Lua edits remain intact")

for _,name in ipairs{"traversal.zip","absolute.zip","symlink.zip","missing-file.zip","tampered-file.zip","wrong-version.zip","bad-manifest.zip"} do
    local candidate=make()
    local rel=assert(candidate:check())
    assert(not pcall(candidate.unpack,candidate,fixtures .. name,rel),"invalid package rejected: " .. name)
    assert(read(candidate.plugin_dir .. "/kindlevel_version.lua"):find(current,1,true),"rejected package leaves old version")
    candidate:cleanup()
end
assert(not lfs.attributes("/tmp/outside-kindlevel"),"ZIP paths did not escape staging")
local failed=make{failure=true};assert(not failed:check(),"network failures handled")
local corrupt=make();local cr=assert(corrupt:check());cr.sha256=string.rep("0",64)
assert(not corrupt:prepare(cr),"bad ZIP digest rejected")
assert(not lfs.attributes(corrupt.stage),"failed preparation cleans staging")
local fallback=make();local fr=assert(fallback:check());fr.sha256=nil
fr.checksum_url=asset_url .. ".sha256"
assert(fallback:prepare(fr),"checksum sidecar fallback")
local rate_limited=make{fallback=true};local public=assert(rate_limited:check())
assert(public.newer and public.sha256 and not public.size,"public release fallback works without the REST API")
assert(rate_limited:prepare(public),"fallback download is still hash-verified when no asset size is supplied")
rate_limited:cleanup()
print("ALL updater checks passed: versions, TLS host rules, ZIP validation, preserved data, staging and rollback")
