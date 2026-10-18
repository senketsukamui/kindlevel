-- Deliberately use absolute dofile paths, not the app's modules/package cache.
local root=assert(debug.getinfo(1,"S").source:match("^@(.+)/main%.lua$"))
local Core=dofile(root .. "/updater.lua")
local Network=dofile(root .. "/network.lua")
local UpdateUI=dofile(root .. "/ui.lua")
local Recovery=require("ui/widget/container/widgetcontainer"):extend{name="kindlevel-recovery",is_doc_only=false}

function Recovery:init() self.ui.menu:registerToMainMenu(self) end

function Recovery:controller()
    if not self.updates then
        local target=root:match("^(.*)/[^/]+$") .. "/kindlevel.koplugin"
        local version="0.0.0"
        local file=io.open(target .. "/kindlevel_version.lua","rb")
        if file then
            local value=file:read(256);file:close()
            local found=value and value:match('^%s*return%s+"([%w.+-]+)"%s*$')
            if Core.version(found) then version=found end
        end
        self.updates=UpdateUI:new{installed_label=version=="0.0.0" and "Unknown (repair mode)" or version,core=Core:new{plugin_dir=target,
            work_dir=require("datastorage"):getDataDir() .. "/kindlevel-updates",
            installed=version,transport=Network:new(root .. "/cacert.pem")}}
    end
    return self.updates
end

function Recovery:addToMainMenu(items)
    items.kindlevel_recovery={text="Kindlevel recovery",sorting_hint="more_tools",callback=function()
        local updates=self:controller()
        local UIManager=require("ui/uimanager")
        local dialog
        dialog=require("ui/widget/buttondialog"):new{title="Kindlevel recovery",buttons={
            {{text="Update or reinstall over Wi-Fi",callback=function() UIManager:close(dialog);updates:check() end}},
            {{text="Restore previous version (offline)",enabled=require("libs/libkoreader-lfs").attributes(updates.core.backup,"mode")=="directory",callback=function()
                UIManager:close(dialog);updates:restore()
            end}},
            {{text="Close",callback=function() UIManager:close(dialog) end}},
        }}
        UIManager:show(dialog)
    end}
end

return Recovery
