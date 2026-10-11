-- Read-only live check of verified TLS against the official GitHub API.
require("setupkoenv")
G_defaults=require("luadefaults"):open()
G_reader_settings=require("luasettings"):open("/tmp/kindlevel-update-network.lua")
package.path="/workspace/kindlevel.koplugin/?.lua;" .. package.path
local U=require("kindlevel_updater")
local core=U:new{plugin_dir="/workspace/kindlevel.koplugin",work_dir="/tmp/kindlevel-live-update"}
local result,err=core:check()
assert(result,err)
assert(U.version(result.version) and result.url:find("senketsukamui/kindlevel",1,true),"official release metadata")
local checksum,checksum_err=core.transport:fetch(result.checksum_url or result.url .. ".sha256",nil,4096)
assert(checksum,checksum_err)
assert(checksum:match("^[0-9a-fA-F]+%s+kindlevel%-"),"official release checksum is accessible")
print("Verified HTTPS check passed; latest stable release: " .. result.version)
