local lfs=require("libs/libkoreader-lfs")
local json=require("json")
local ffiUtil=require("ffi/util")
local Updater={repository="senketsukamui/kindlevel",max_zip=16*1024*1024,max_file=8*1024*1024,max_total=64*1024*1024}
Updater.__index=Updater
local MANIFEST="update-manifest.json"

local function read(path)
    local file=assert(io.open(path,"rb"),"Cannot read update file.")
    local content=file:read("*a");file:close();return content
end
local function mkdir(path)
    if lfs.attributes(path,"mode")=="directory" then return end
    local parent=path:match("^(.*)/[^/]+$")
    if parent and parent~="" then mkdir(parent) end
    assert(lfs.mkdir(path),"Cannot create update directory. Check available storage.")
end
local function write(path,content)
    mkdir(assert(path:match("^(.*)/[^/]+$")))
    local file=assert(io.open(path,"wb"),"Cannot write update file.")
    local ok,err=file:write(content)
    if not ok then file:close();error(err or "Not enough storage.") end
    local synced,sync_err=ffiUtil.fsyncOpenedFile(file)
    file:close();assert(synced,sync_err or "Cannot save update data.")
end
local function copy(source,destination)
    mkdir(assert(destination:match("^(.*)/[^/]+$")))
    local input=assert(io.open(source,"rb"),"Cannot read a local plugin file.")
    local output=io.open(destination,"wb")
    if not output then input:close();error("Cannot preserve local plugin files. Check available storage.") end
    local ok,err=pcall(function()
        while true do
            local chunk=input:read(32768);if not chunk then break end
            assert(output:write(chunk),"Not enough storage to preserve local plugin files.")
        end
        assert(ffiUtil.fsyncOpenedFile(output),"Cannot save preserved plugin files.")
    end)
    input:close();output:close();assert(ok,err)
end
local function remove(path)
    local mode=lfs.symlinkattributes(path,"mode")
    if not mode then return end
    if mode=="directory" then
        for name in lfs.dir(path) do if name~="." and name~=".." then remove(path .. "/" .. name) end end
        assert(lfs.rmdir(path),"Cannot remove temporary update directory.")
    else assert(os.remove(path),"Cannot remove temporary update file.") end
end
local function safePath(path)
    if type(path)~="string" or path=="" or path:sub(1,1)=="/" or path:find("[\\:%c]") then return false end
    if path:find("//",1,true) then return false end
    for part in path:gmatch("[^/]+") do if part=="." or part==".." then return false end end
    return true
end
local function protected(path)
    if path=="custom_achievements.lua" or path=="kindlevel.lua" then return true end
    for part in path:gmatch("[^/]+") do if part:sub(-4)==".sdr" then return true end end
    return path:match("%.sqlite3?$")~=nil
end
local function digest(value)
    return type(value)=="string" and #value==64 and value:match("^[0-9a-fA-F]+$")~=nil
end
function Updater.shaFile(path)
    local file=assert(io.open(path,"rb"),"Cannot read update file.")
    local hash=require("ffi/sha2").sha256()
    while true do local chunk=file:read(32768);if not chunk then break end;hash(chunk) end
    file:close();return hash()
end

function Updater.version(value)
    if type(value)~="string" then return end
    local clean=value:gsub("^v","")
    local major,minor,patch,suffix=clean:match("^(%d+)%.(%d+)%.(%d+)(.*)$")
    if not major or #major>9 or #minor>9 or #patch>9 then return end
    local pre=suffix:match("^%-([%w.-]+)$")
    if suffix~="" and (not pre or pre:find("..",1,true) or pre:sub(-1)==".") then return end
    return {tonumber(major),tonumber(minor),tonumber(patch),pre=pre,text=clean}
end
function Updater.compare(a,b)
    a,b=assert(Updater.version(a)),assert(Updater.version(b))
    for index=1,3 do if a[index]~=b[index] then return a[index]>b[index] and 1 or -1 end end
    if a.pre==b.pre then return 0 end
    if not a.pre then return 1 end
    if not b.pre then return -1 end
    local aa,bb={},{}
    for part in a.pre:gmatch("[^.]+") do aa[#aa+1]=part end
    for part in b.pre:gmatch("[^.]+") do bb[#bb+1]=part end
    for index=1,math.max(#aa,#bb) do
        if not aa[index] then return -1 end
        if not bb[index] then return 1 end
        if aa[index]~=bb[index] then
            local an=aa[index]:match("^%d+$") and tonumber(aa[index])
            local bn=bb[index]:match("^%d+$") and tonumber(bb[index])
            if an and bn then return an>bn and 1 or -1 end
            if an then return -1 end
            if bn then return 1 end
            return aa[index]>bb[index] and 1 or -1
        end
    end
    return 0
end

function Updater:new(options)
    assert(options.plugin_dir:match("/kindlevel%.koplugin$"),"Unexpected plugin installation path.")
    local parent=options.plugin_dir:match("^(.*)/[^/]+$")
    return setmetatable({plugin_dir=options.plugin_dir,work_dir=options.work_dir,
        stage=parent .. "/.kindlevel-stage",backup=parent .. "/.kindlevel-backup",parent=parent,
        installed=options.installed or require("kindlevel_version"),rename=options.rename or os.rename,
        transport=options.transport or require("kindlevel_update_network"):new(options.plugin_dir .. "/assets/cacert.pem")},self)
end

function Updater:selectRelease(data)
    assert(type(data)=="table" and not data.draft and not data.prerelease,"No stable update is available.")
    local version=Updater.version(data.tag_name)
    assert(version and not version.pre,"The release has an unsupported version tag.")
    local name="kindlevel-" .. version.text .. ".zip"
    local release={version=version.text,name=name,notes=type(data.body)=="string" and data.body or ""}
    for _,asset in ipairs(data.assets or {}) do
        if asset.name==name or asset.name==name .. ".sha256" then
            assert(asset.browser_download_url=="https://github.com/" .. self.repository .. "/releases/download/" .. data.tag_name .. "/" .. asset.name,
                "The release asset URL is invalid.")
            if asset.name==name then
                assert(type(asset.size)=="number" and asset.size>0 and asset.size<=self.max_zip,"The update package is too large or empty.")
                release.url,release.size=asset.browser_download_url,asset.size
                if asset.digest then
                    local hash=asset.digest:match("^sha256:(.+)$")
                    assert(digest(hash),"The update checksum is invalid.");release.sha256=hash:lower()
                end
            else release.checksum_url=asset.browser_download_url end
        end
    end
    assert(release.url,"This release does not include an install ZIP.")
    assert(release.sha256 or release.checksum_url,"This release does not include an update checksum.")
    release.newer=Updater.compare(release.version,self.installed)>0
    return release
end

function Updater:check()
    local ok,result=pcall(function()
        local body,err=self.transport:fetch("https://api.github.com/repos/" .. self.repository .. "/releases/latest",nil,1024*1024)
        assert(body,err);return self:selectRelease(json.decode(body))
    end)
    if ok then return result end
    -- Public release redirects and checksum assets do not share the REST API limit.
    local fallback_ok,fallback=pcall(function()
        local body,err,_,final_url=self.transport:fetch("https://github.com/" .. self.repository .. "/releases/latest",nil,1024*1024)
        assert(body,err)
        local prefix="https://github.com/" .. self.repository .. "/releases/tag/"
        assert(type(final_url)=="string" and final_url:sub(1,#prefix)==prefix,"Cannot determine the latest stable release.")
        local tag=final_url:sub(#prefix+1)
        local version=Updater.version(tag)
        assert(version and not version.pre,"The latest release has an unsupported version tag.")
        local release={version=version.text,name="kindlevel-" .. version.text .. ".zip",notes="",
            newer=Updater.compare(version.text,self.installed)>0}
        release.url="https://github.com/" .. self.repository .. "/releases/download/" .. tag .. "/" .. release.name
        release.checksum_url=release.url .. ".sha256"
        if release.newer then
            local checksum,checksum_err=self.transport:fetch(release.checksum_url,nil,4096)
            assert(checksum,checksum_err)
            local hash,name=checksum:match("^([0-9a-fA-F]+)%s+%*?([^%s]+)%s*$")
            assert(digest(hash) and name==release.name,"The release checksum file is invalid.")
            release.sha256=hash:lower()
        end
        return release
    end)
    if fallback_ok then return fallback end
    return nil,tostring(fallback or result):gsub("^.-:%d+:%s*","")
end

function Updater.manifest(content,version)
    local manifest=json.decode(content)
    assert(type(manifest)=="table" and manifest.schema==1 and manifest.version==version and type(manifest.files)=="table",
        "The update manifest does not match the release.")
    local files,total={},0
    for _,file in ipairs(manifest.files) do
        assert(type(file)=="table" and safePath(file.path) and file.path:sub(-1)~="/" and not protected(file.path) and file.path~=MANIFEST,
            "The package contains a protected or unsafe filename.")
        assert(not files[file.path] and digest(file.sha256) and type(file.size)=="number" and file.size>=0 and file.size%1==0 and file.size<=Updater.max_file,
            "The package manifest has invalid file data.")
        files[file.path]=file;total=total+file.size
    end
    assert(#manifest.files>0 and #manifest.files<=2000 and total<=Updater.max_total,"The unpacked update is too large.")
    for _,name in ipairs{"main.lua","_meta.lua","kindlevel_version.lua","kindlevel_updater.lua","kindlevel_update_network.lua","assets/cacert.pem"} do
        assert(files[name] and files[name].size>0,"The update is missing a required plugin file.")
    end
    return manifest,files
end

function Updater:unpack(path,release)
    local archive=require("ffi/archiver").Reader:new()
    local ok,err=pcall(function()
        assert(archive:open(path),"Cannot open the update ZIP.")
        local entries,total,count={},0,0
        for entry in archive:iterate() do
            count=count+1
            local size=tonumber(entry.size)
            assert(count<=3000 and safePath(entry.path) and (entry.mode=="file" or entry.mode=="directory")
                and size and size>=0 and size<=self.max_file,"The ZIP contains unsafe or oversized entries.")
            assert(not entries[entry.path],"The ZIP contains duplicate filenames.")
            entries[entry.path]=entry;total=total+size
            assert(total<=self.max_total,"The unpacked ZIP is too large.")
        end
        assert(not archive.err,"The update ZIP is damaged.")
        local manifest_entry=entries["kindlevel.koplugin/" .. MANIFEST]
        assert(manifest_entry and tonumber(manifest_entry.size)<=512*1024,"This release does not support wireless installation. Use USB.")
        local manifest_text=assert(archive:extractToMemory(manifest_entry.path),"Cannot read the update manifest.")
        local manifest,files=self.manifest(manifest_text,release.version)
        local payload={}
        for name,entry in pairs(entries) do
            if name:sub(1,19)=="kindlevel.koplugin/" and entry.mode=="file" and name~=manifest_entry.path then
                local relative=name:sub(20)
                assert(files[relative],"The ZIP contains a plugin file absent from its manifest.")
                payload[#payload+1]={entry=entry,path=relative}
            end
        end
        assert(#payload==#manifest.files,"The ZIP is missing plugin files.")
        table.sort(payload,function(a,b) return a.entry.index<b.entry.index end)
        remove(self.stage);mkdir(self.stage)
        for _,item in ipairs(payload) do
            local data=assert(archive:extractToMemory(item.entry.path),"Cannot read a plugin file from the ZIP.")
            local file=files[item.path]
            assert(#data==file.size and require("ffi/sha2").sha256(data)==file.sha256:lower(),"A plugin file failed its checksum check.")
            if item.path:sub(-4)==".lua" then assert(loadstring(data),"The update contains invalid Lua code.") end
            write(self.stage .. "/" .. item.path,data)
        end
        local version_text=read(self.stage .. "/kindlevel_version.lua"):match('^%s*return%s+"([%w.+-]+)"%s*$')
        assert(version_text==release.version,"The installed version file does not match this release.")
        write(self.stage .. "/" .. MANIFEST,manifest_text)
    end)
    archive:close()
    if not ok then error(err) end
end

function Updater:prepare(release,reinstall)
    local ok,err=pcall(function()
        local comparison=Updater.compare(release.version,self.installed)
        assert(comparison>0 or reinstall==true and comparison==0,"The release is not newer than the installed version.")
        mkdir(self.work_dir)
        local hash=release.sha256
        if not hash then
            local text,fetch_err=self.transport:fetch(release.checksum_url,nil,4096)
            assert(text,fetch_err)
            local found,name=text:match("^([0-9a-fA-F]+)%s+%*?([^%s]+)%s*$")
            assert(digest(found) and name==release.name,"The release checksum file is invalid.");hash=found:lower()
        end
        local package=self.work_dir .. "/download.zip"
        local result,fetch_err=self.transport:fetch(release.url,package,self.max_zip)
        assert(result,fetch_err)
        if release.size then assert(lfs.attributes(package,"size")==release.size,"The update download is incomplete.") end
        assert(self.shaFile(package)==hash,"The update ZIP failed its checksum check.")
        self:unpack(package,release)
        os.remove(package)
    end)
    if ok then return true end
    pcall(remove,self.stage);os.remove(self.work_dir .. "/download.zip")
    return nil,tostring(err):gsub("^.-:%d+:%s*","")
end

function Updater:preserve(files)
    local old={}
    local old_path=self.plugin_dir .. "/" .. MANIFEST
    if lfs.attributes(old_path,"mode")=="file" then
        -- A damaged local manifest must not prevent a verified repair. Treat
        -- it like a legacy installation; the entire old directory is backed up.
        pcall(function()
            local content=json.decode(read(old_path))
            for _,file in ipairs(content.files or {}) do
                if safePath(file.path) and digest(file.sha256) then old[file.path]=file end
            end
        end)
    end
    local count=0
    local function visit(directory,prefix)
        for name in lfs.dir(directory) do if name~="." and name~=".." then
            local path=directory .. "/" .. name
            local relative=prefix .. name
            local mode=lfs.symlinkattributes(path,"mode")
            assert(mode=="file" or mode=="directory","The plugin contains symbolic links or special files. Update it using USB.")
            if mode=="directory" then visit(path,relative .. "/")
            elseif relative~=MANIFEST then
                count=count+1;assert(count<=10000,"Too many local plugin files to preserve.")
                local changed=old[relative] and self.shaFile(path)~=old[relative].sha256:lower()
                -- Shipped code is replaced by the verified release. Local edits
                -- remain in the full backup instead of permanently blocking OTA.
                if not files[relative] and not old[relative] or changed and relative:sub(1,7)=="assets/" then
                    copy(path,self.stage .. "/" .. relative)
                end
            end
        end end
    end
    visit(self.plugin_dir,"")
end

function Updater:activate(release)
    local moved=false
    local ok,err=pcall(function()
        local _,files=self.manifest(read(self.stage .. "/" .. MANIFEST),release.version)
        for path,file in pairs(files) do
            local full=self.stage .. "/" .. path
            assert(lfs.symlinkattributes(full,"mode")=="file" and lfs.attributes(full,"size")==file.size and self.shaFile(full)==file.sha256:lower(),
                "The staged update changed before installation.")
        end
        -- Save/close the reader before calling this: sample-book sidecars may be here.
        local exists=lfs.symlinkattributes(self.plugin_dir,"mode")=="directory"
        if exists then self:preserve(files);remove(self.backup) end
        write(self.work_dir .. "/pending.json",json.encode{version=release.version})
        if exists then
            assert(self.rename(self.plugin_dir,self.backup),"Cannot back up the installed plugin.")
            moved=true;ffiUtil.fsyncDirectory(self.parent)
        end
        assert(self.rename(self.stage,self.plugin_dir),"Cannot activate the new plugin.")
        moved=false;ffiUtil.fsyncDirectory(self.parent)
        os.remove(self.work_dir .. "/pending.json")
    end)
    if ok then return true end
    if moved then
        local restored=self.rename(self.backup,self.plugin_dir)
        if not restored then return nil,"The update could not be installed or restored. Your previous plugin is in " .. self.backup end
        ffiUtil.fsyncDirectory(self.parent)
    end
    os.remove(self.work_dir .. "/pending.json")
    return nil,tostring(err):gsub("^.-:%d+:%s*","")
end

function Updater:restoreBackup()
    local displaced
    local ok,err=pcall(function()
        assert(lfs.symlinkattributes(self.backup,"mode")=="directory","No previous plugin backup is available.")
        assert(loadstring(read(self.backup .. "/main.lua")),"The previous plugin's entry point is damaged.")
        if lfs.symlinkattributes(self.plugin_dir,"mode")=="directory" then
            local content=read(self.backup .. "/" .. MANIFEST)
            local _,files=self.manifest(content,json.decode(content).version)
            local stage=self.stage
            self.stage=self.backup
            local saved,message=pcall(self.preserve,self,files)
            self.stage=stage
            assert(saved,message)
            -- Retain the displaced installation too, including edited code.
            displaced=self.parent .. "/.kindlevel-replaced-" .. os.time()
            local suffix=0
            while lfs.symlinkattributes(displaced) do suffix=suffix+1;displaced=self.parent .. "/.kindlevel-replaced-" .. os.time() .. "-" .. suffix end
            assert(self.rename(self.plugin_dir,displaced),"Cannot keep the current plugin before restoring.")
        end
        local restored=self.rename(self.backup,self.plugin_dir)
        if not restored and displaced then self.rename(displaced,self.plugin_dir) end
        assert(restored,"Cannot restore the previous plugin.")
        ffiUtil.fsyncDirectory(self.parent)
        os.remove(self.work_dir .. "/pending.json")
    end)
    if ok then return true end
    return nil,tostring(err):gsub("^.-:%d+:%s*","")
end

function Updater:cleanup()
    pcall(remove,self.stage);os.remove(self.work_dir .. "/download.zip")
end

return Updater
