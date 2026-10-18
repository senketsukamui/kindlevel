-- Only KOReader APIs and an injected update core; no reading-app dependencies.
-- The same controller runs inside Kindlevel and the independent recovery plugin.
local UIManager=require("ui/uimanager")
local InfoMessage=require("ui/widget/infomessage")
local UpdateUI={}
UpdateUI.__index=UpdateUI
local activity=package.loaded.kindlevel_update_activity or {}
package.loaded.kindlevel_update_activity=activity

function UpdateUI:new(options) return setmetatable(options,self) end

local function stopBackground()
    local auto=package.loaded.kindlevel_auto_sync
    if auto and auto.stop then pcall(auto.stop,auto) end
end

local function showError(text)
    UIManager:show(InfoMessage:new{text=text or "The update failed. You can retry from Kindlevel recovery."})
end

function UpdateUI:network(task,message,callback)
    stopBackground()
    local app_core=package.loaded.kindlevel_updater
    if activity.busy or app_core and app_core.busy then showError("Another network operation is running.");return end
    local network=require("ui/network/manager")
    local run=network.runWhenConnected or network.runWhenOnline
    run(network,function()
        if activity.busy or app_core and app_core.busy then return end
        activity.busy=true
        if app_core then app_core.busy=true end
        local reader=require("apps/reader/readerui").instance
        local Event=require("ui/event")
        if reader then reader:handleEvent(Event:new("ReadingPaused")) end
        require("ui/trapper"):wrap(function()
            local ok,completed,result,err=pcall(function()
                return require("ui/trapper"):dismissableRunInSubprocess(task,message)
            end)
            if reader and require("apps/reader/readerui").instance==reader then reader:handleEvent(Event:new("ReadingResumed")) end
            activity.busy=false
            if app_core then app_core.busy=false end
            network:afterWifiAction()
            if not ok then callback(nil,"The network operation failed. Try again from Kindlevel recovery.")
            elseif completed then callback(result,err)
            else callback(nil,nil,true) end
            local auto=package.loaded.kindlevel_auto_sync
            if auto and auto.wake then pcall(auto.wake,auto) end
        end)
    end)
end

function UpdateUI:check()
    local core=self.core
    self:network(function() return core:check() end,"Checking for Kindlevel updates…",function(release,err,cancelled)
        if cancelled then return end
        if not release then showError(err);return end
        if core.compare(release.version,core.installed)<0 then
            showError("Installed: " .. core.installed .. "\nLatest stable: " .. release.version .. "\n\nThis development build is newer than the stable release.");return
        end
        local reinstall=not release.newer
        UIManager:show(require("ui/widget/confirmbox"):new{
            text=string.format("%s Kindlevel?\n\nInstalled: %s\nAvailable: %s%s\n\nBuilt-in code will be replaced. Your current plugin, including local edits, is kept as a backup. Custom achievements, icons and reading data are preserved. KOReader will restart.",
                reinstall and "Reinstall" or "Update",self.installed_label or core.installed,release.version,
                release.size and string.format("\nDownload: %.0f KB",release.size/1024) or ""),
            ok_text=reinstall and "Reinstall & restart" or "Install & restart",ok_callback=function() self:install(release,reinstall) end,
        })
    end)
end

function UpdateUI:activate(action)
    stopBackground()
    local info=InfoMessage:new{text="Installing Kindlevel…",dismissable=false}
    UIManager:show(info);UIManager:forceRePaint();UIManager:preventStandby()
    local ok,result,err=pcall(function()
        local reader=require("apps/reader/readerui").instance
        if reader then reader:onClose()
        else
            local manager=require("apps/filemanager/filemanager").instance
            if manager and manager.kindlevel and manager.kindlevel.settings then manager.kindlevel.settings:flush() end
        end
        G_reader_settings:flush()
        local toasts=package.loaded.kindlevel_achievement_toast
        if toasts and toasts.clear then pcall(toasts.clear,toasts) end
        return action()
    end)
    UIManager:allowStandby();UIManager:close(info)
    if not ok or not result then self.core:cleanup();showError(ok and err or "Cannot save or install the plugin. Use Kindlevel recovery to retry.");return end
    UIManager:restartKOReader()
end

function UpdateUI:install(release,reinstall)
    self:network(function() return self.core:prepare(release,reinstall) end,"Downloading and checking Kindlevel…",function(prepared,err,cancelled)
        if cancelled then self.core:cleanup();return end
        if not prepared then self.core:cleanup();showError(err);return end
        self:activate(function() return self.core:activate(release) end)
    end)
end

function UpdateUI:restore()
    UIManager:show(require("ui/widget/confirmbox"):new{
        text="Restore the previous Kindlevel version and restart KOReader? The current plugin is kept separately. Reading history and current custom achievements are preserved.",
        ok_text="Restore & restart",ok_callback=function() self:activate(function() return self.core:restoreBackup() end) end,
    })
end

return UpdateUI
