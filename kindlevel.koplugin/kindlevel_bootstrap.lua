local lfs=require("libs/libkoreader-lfs")
local ffiUtil=require("ffi/util")
local Bootstrap={}

-- This sibling plugin is installed once, independently of the app directory
-- swap. Subsequent app updates never overwrite a working recovery installation.
Bootstrap.files={
    ["main.lua"]="recovery/main.lua",["_meta.lua"]="recovery/_meta.lua",
    ["updater.lua"]="kindlevel_updater.lua",["network.lua"]="kindlevel_update_network.lua",
    ["ui.lua"]="kindlevel_update_ui.lua",["cacert.pem"]="assets/cacert.pem",
    ["NOTICE.md"]="NOTICE.md",["LICENSE"]="LICENSE",
}

local function remove(path)
    local mode=lfs.symlinkattributes(path,"mode")
    if mode=="directory" then
        for name in lfs.dir(path) do if name~="." and name~=".." then remove(path .. "/" .. name) end end
        assert(lfs.rmdir(path))
    elseif mode then assert(os.remove(path)) end
end

function Bootstrap.installRecovery(root)
    local parent=assert(root:match("^(.*)/[^/]+$"))
    local target=parent .. "/kindlevel-recovery.koplugin"
    if lfs.symlinkattributes(target) then return target end
    local stage=parent .. "/.kindlevel-recovery-stage"
    remove(stage);assert(lfs.mkdir(stage))
    for destination,source in pairs(Bootstrap.files) do
        local input=assert(io.open(root .. "/" .. source,"rb"))
        local data=input:read("*a");input:close()
        if destination:sub(-4)==".lua" then assert(loadstring(data),"Recovery code is damaged.") end
        local output=assert(io.open(stage .. "/" .. destination,"wb"))
        assert(output:write(data));assert(ffiUtil.fsyncOpenedFile(output));output:close()
    end
    ffiUtil.fsyncDirectory(stage)
    assert(os.rename(stage,target));ffiUtil.fsyncDirectory(parent)
    return target
end

function Bootstrap.load(root)
    -- Source previews have no distribution manifest and must not install into
    -- the developer's repository. Packaged Wi-Fi upgrades install the helper.
    local recovery=root:match("^(.*)/[^/]+$") .. "/kindlevel-recovery.koplugin"
    if lfs.attributes(root .. "/update-manifest.json","mode")=="file" then
        local ok,err=pcall(Bootstrap.installRecovery,root)
        if not ok then require("logger").warn("Kindlevel: cannot install recovery helper",err) end
    end
    local ok,app=pcall(dofile,root .. "/kindlevel_app.lua")
    if ok and type(app)=="table" and type(app.new)=="function" then return app end
    if ok then app="The reading app did not return a plugin." end
    require("logger").warn("Kindlevel: app failed to load; opening recovery",app)
    -- On the first upgrade the helper was not in KOReader's discovery list yet.
    -- Return it here so its menu is immediately usable even if the app is bad.
    if lfs.attributes(recovery .. "/main.lua","mode")=="file" then return dofile(recovery .. "/main.lua") end
    error(app)
end

return Bootstrap
