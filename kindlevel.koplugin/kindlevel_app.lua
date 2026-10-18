local DataStorage = require("datastorage")
local Dispatcher = require("dispatcher")
local InfoMessage = require("ui/widget/infomessage")
local ButtonDialog = require("ui/widget/buttondialog")
local InputDialog = require("ui/widget/inputdialog")
local LuaSettings = require("luasettings")
local PathChooser = require("ui/widget/pathchooser")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local ffiUtil = require("ffi/util")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")

local Kindlevel = WidgetContainer:extend{
    name = "kindlevel",
    is_doc_only = false,
}

function Kindlevel:init()
    self.plugin_dir = ffiUtil.realpath(self.path or "plugins/kindlevel.koplugin")
        or self.path or "plugins/kindlevel.koplugin"
    self.settings = LuaSettings:open(DataStorage:getSettingsDir() .. "/kindlevel.lua")
    self.ui.menu:registerToMainMenu(self)
    Dispatcher:registerAction("kindlevel_open", {
        category = "none", event = "Kindlevel", title = "Kindlevel", general = true,
    })
    if not self.ui.document then
        local returning = self.settings:isTrue("return_to_home")
        if returning or self.settings:isTrue("auto_home") then
            self.settings:delSetting("return_to_home")
            self.settings:flush()
            UIManager:nextTick(function()
                -- A scheduled callback must not reopen a home on a retired file manager.
                local FileManager = require("apps/filemanager/filemanager")
                if FileManager.instance == self.ui then self:onKindlevel() end
            end)
        end
        UIManager:nextTick(function()
            if require("apps/filemanager/filemanager").instance == self.ui and not require("apps/reader/readerui").instance then self:checkAchievements() end
        end)
    end
    UIManager:nextTick(function()
        if require("kindlevel_auto_sync"):owner()==self then require("kindlevel_auto_sync"):wake() end
    end)
end

function Kindlevel:addToMainMenu(items)
    items.kindlevel = {
        text = "Kindlevel",
        sorting_hint = "more_tools",
        callback = function() self:onKindlevel() end,
    }
    items.kindlevel_statistics = {
        text = "Kindlevel statistics", sorting_hint = "more_tools",
        callback = function() self:onKindlevel("stats") end,
    }
    items.kindlevel_achievements = {
        text = "Kindlevel achievements", sorting_hint = "more_tools",
        callback = function() self:onKindlevel("achievements") end,
    }
    items.kindlevel_achievement_preview = {
        text = "Preview achievement notification", sorting_hint = "more_tools",
        callback = function() self:chooseAchievementPreview() end,
    }
    items.kindlevel_updates = {
        text = "Kindlevel updates", sorting_hint = "more_tools",
        callback = function() self:checkForUpdates() end,
    }
    items.kindlevel_web = {
        text = "Kindlevel web dashboard", sorting_hint = "more_tools",
        callback = function() self:dashboardConnection() end,
    }
end

function Kindlevel:getUpdater()
    if not self.updater then self.updater=require("kindlevel_updater"):new{
        plugin_dir=self.plugin_dir,work_dir=DataStorage:getDataDir() .. "/kindlevel-updates",
    } end
    return self.updater
end

local function networkJob(task,message,callback,before)
    -- A foreground operation takes priority; the durable outbox survives.
    require("kindlevel_auto_sync"):stop()
    local updater=require("kindlevel_updater")
    if updater.busy or (package.loaded.kindlevel_update_activity or {}).busy then UIManager:show(InfoMessage:new{text="Another network operation is running."});return end
    require("ui/network/manager"):runWhenOnline(function()
        if updater.busy or (package.loaded.kindlevel_update_activity or {}).busy then return end
        updater.busy=true
        local reader=require("apps/reader/readerui").instance
        if reader then reader:handleEvent(require("ui/event"):new("ReadingPaused")) end
        if before then
            local prepared=pcall(before)
            if not prepared then
                if reader then reader:handleEvent(require("ui/event"):new("ReadingResumed")) end
                updater.busy=false;require("ui/network/manager"):afterWifiAction()
                callback(nil,"Cannot prepare reading history. Close the book and try again.")
                require("kindlevel_auto_sync"):wake()
                return
            end
        end
        require("ui/trapper"):wrap(function()
            local ok,completed,result,err=pcall(function()
                return require("ui/trapper"):dismissableRunInSubprocess(task,message)
            end)
            if reader and require("apps/reader/readerui").instance==reader then
                reader:handleEvent(require("ui/event"):new("ReadingResumed"))
            end
            updater.busy=false
            require("ui/network/manager"):afterWifiAction()
            if not ok then callback(nil,"The network operation failed. Try again.")
            elseif completed then callback(result,err)
            else callback(nil,nil,true) end
            require("kindlevel_auto_sync"):wake()
        end)
    end)
end

function Kindlevel:getUpdateUI()
    return require("kindlevel_update_ui"):new{core=self:getUpdater()}
end

function Kindlevel:checkForUpdates() self:getUpdateUI():check() end
function Kindlevel:installUpdate(release) self:getUpdateUI():install(release) end

function Kindlevel:getSync()
    if not self.sync then self.sync=require("kindlevel_sync"):new{
        state_path=DataStorage:getSettingsDir() .. "/kindlevel-sync.json",
        pending_path=DataStorage:getDataDir() .. "/kindlevel-sync/pending.json",
        cafile=self.plugin_dir .. "/assets/cacert.pem",
    } end
    return self.sync
end

function Kindlevel:dashboardConnection()
    local core=self:getSync()
    local ok,state=pcall(core.state,core)
    if not ok then UIManager:show(InfoMessage:new{text="Cannot read the server connection. Restore kindlevel-sync.json or remove it and pair again."});return end
    local dialog
    local title="Your web dashboard"
    if state.server then title=title .. "\n" .. state.server .. "\n" .. (state.last_sync and "Last synced: " .. os.date("%Y-%m-%d %H:%M",state.last_sync) or "Ready for the first sync") end
    if state.last_error then title=title .. "\nLast attempt failed · retry pending" end
    local buttons={
        {{text=state.token and "Pair another server" or "Connect to server",callback=function() UIManager:close(dialog);self:pairDashboard() end}},
        {{text="Sync now",enabled=state.token~=nil,callback=function() UIManager:close(dialog);self:syncDashboard() end}},
        {{text="Automatic sync: " .. (state.auto_sync~=false and "on" or "off"),enabled=state.token~=nil,callback=function()
            require("kindlevel_auto_sync"):stop()
            local saved=pcall(core.setAutomatic,core,state.auto_sync==false)
            UIManager:close(dialog)
            if not saved then UIManager:show(InfoMessage:new{text="Cannot save the automatic sync setting. Check free space."});return end
            require("kindlevel_auto_sync"):wake(true)
            self:dashboardConnection()
        end}},
        {{text="Forget connection",enabled=state.token~=nil,callback=function()
            UIManager:close(dialog)
            UIManager:show(require("ui/widget/confirmbox"):new{text="Forget this server connection on the Kindle? Reading history stays on both devices. Revoke the Kindle in the web dashboard to disable its old token.",ok_text="Forget",ok_callback=function()
                require("kindlevel_auto_sync"):stop()
                core:forget()
            end})
        end}},
        {{text="Close",callback=function() UIManager:close(dialog) end}},
    }
    if state.last_error then
        table.insert(buttons,#buttons,{{text="Last sync error",callback=function()
            UIManager:show(InfoMessage:new{text=state.last_error})
        end}})
    end
    dialog=ButtonDialog:new{title=title,buttons=buttons}
    UIManager:show(dialog)
end

function Kindlevel:pairDashboard()
    local core=self:getSync()
    local state=core:state()
    local dialog
    dialog=require("ui/widget/multiinputdialog"):new{title="Connect your web dashboard",fields={
        {description="Server address",text=state.server or "https://",hint="https://books.example.com"},
        {description="Pairing code from the dashboard",text="",hint="ABCDE-FG234"},
        {description="Kindle name",text=state.name or "My Kindle"},
    },buttons={{{text="Cancel",callback=function() UIManager:close(dialog) end},{text="Pair",callback=function()
        local values=dialog:getFields()
        local server=values[1]:gsub("^%s+",""):gsub("%s+$","")
        local code=values[2]:gsub("^%s+",""):gsub("%s+$","")
        local name=values[3]:gsub("^%s+",""):gsub("%s+$","")
        if code=="" or name=="" or #name>80 then UIManager:show(InfoMessage:new{text="Enter the pairing code and a Kindle name (up to 80 bytes)."});return end
        local function connect(allow_http)
            local address,err=require("kindlevel_sync_network").address(server,allow_http)
            if not address then UIManager:show(InfoMessage:new{text=err});return end
            UIManager:close(dialog)
            networkJob(function() return core:pair(address,code,name,allow_http) end,"Connecting your Kindle…",function(result,message,cancelled)
                if cancelled then return end
                if result then require("kindlevel_auto_sync"):wake(true) end
                UIManager:show(InfoMessage:new{text=result and "Kindle connected. Reading history will sync automatically while Wi-Fi is connected. You can also choose Sync now in Web dashboard." or message or "Cannot connect to the server."})
            end)
        end
        if server:sub(1,7)=="http://" then
            UIManager:show(require("ui/widget/confirmbox"):new{text="Use unencrypted HTTP for this server? The pairing code, device token and reading history will be sent without encryption.",ok_text="Allow HTTP",ok_callback=function() connect(true) end})
        else connect(false) end
    end}}}}
    UIManager:show(dialog);dialog:onShowKeyboard()
end

function Kindlevel:syncDashboard()
    local core=self:getSync()
    if not core:state().token then self:pairDashboard();return end
    networkJob(function() return core:upload(self) end,"Syncing your reading history…",function(result,err,cancelled)
        if cancelled then return end
        if result then
            local auto=require("kindlevel_auto_sync")
            auto.retry_at=nil;auto.failures=0
            UIManager:show(InfoMessage:new{text=string.format("Reading history synced.\n\n%d books · %d book-days · %d achievements\nOpen or refresh your web dashboard to see it.",result.books or 0,result.activity or 0,result.achievements or 0)})
        else UIManager:show(InfoMessage:new{text=err or "Could not sync. Your pending snapshot is kept for retry."}) end
    end,function() self:prepareDashboardSync() end)
end

function Kindlevel:prepareDashboardSync()
    local reader=require("apps/reader/readerui").instance
    if reader then reader:saveSettings() end
    self:getGoals()
    self:checkAchievements(false)
    self.settings:flush()
end

function Kindlevel:previewAchievement(id)
    local catalog = require("kindlevel_achievements")
    local achievement = catalog.find(id or "first_pages")
    if achievement then require("kindlevel_achievement_toast"):preview(achievement, self.plugin_dir) end
end

function Kindlevel:chooseAchievementPreview()
    local catalog = require("kindlevel_achievements")
    local dialog, items = nil, {}
    for _, item in ipairs(catalog.catalog) do
        items[#items + 1] = { text = item.title, callback = function()
            UIManager:close(dialog)
            UIManager:scheduleIn(0.1, function() self:previewAchievement(item.id) end)
        end }
    end
    dialog = require("ui/widget/menu"):new{ title = "Preview an achievement", item_table = items,
        close_callback = function() UIManager:close(dialog) end }
    UIManager:show(dialog)
end

function Kindlevel:previewAchievementInBook()
    local book = self.home and self.home.library.books[self.home.index]
    if not book then
        UIManager:show(InfoMessage:new{ text = "Choose a readable book in your library first." }); return
    end
    local plugin_dir = self.plugin_dir
    self:openBook(book, function()
        UIManager:scheduleIn(0.4, function()
            require("kindlevel_achievement_toast"):preview(require("kindlevel_achievements").find("first_pages"), plugin_dir)
        end)
    end)
end

function Kindlevel:getRoot()
    return self.settings:readSetting("library_root") or self.plugin_dir .. "/books"
end

function Kindlevel:onKindlevel(tab)
    if self.ui.document then
        if tab then self.settings:saveSetting("open_tab", tab) end
        self.settings:saveSetting("return_to_home", true)
        self.settings:flush()
        -- Use KOReader's normal path so it saves the reading position and closes safely.
        self.ui:onHome()
        return true
    end
    if self.home then
        self:checkAchievements()
        if tab then self.home.tab = tab; self.home:rebuild() end
        return true
    end
    local Library = require("kindlevel_library")
    local Screen = require("kindlevel_screen")
    local library = Library:new{ root = self:getRoot() }
    library:scan()
    self.goal_library = library
    self.goals_imported = false
    if self.stats then self.stats:refresh() end
    self.home = Screen:new{
        owner = self,
        library = library,
        selected_file = self.settings:readSetting("selected_file"),
        initial_tab = tab or self.settings:readSetting("open_tab"),
    }
    self.settings:delSetting("open_tab")
    self.settings:flush()
    UIManager:show(self.home, "full")
    self:checkAchievements(true, false)
    return true
end

function Kindlevel:getStats()
    if not self.stats then self.stats = require("kindlevel_stats"):new() end
    local Stats = require("kindlevel_stats")
    if not self.stats.fixed_now and Stats.day(self.stats.now) ~= Stats.day(os.time()) then self.stats:refresh() end
    return self.stats
end

function Kindlevel:refreshStats()
    self:getStats():refresh()
    self.goals_imported = false
    self:checkAchievements(true, false)
    if self.home then self.home:rebuild() end
end

function Kindlevel:getAchievementContext()
    if not self.achievement_context then self:checkAchievements(false) end
    return self.achievement_context or require("kindlevel_achievements").context(self)
end

function Kindlevel:checkAchievements(notify, refresh)
    if self._achievement_stopped then return end
    local collector = self.ui.document and self.ui.statistics
    if collector and collector.onSaveSettings then
        local ok, err = pcall(collector.onSaveSettings, collector)
        if not ok then logger.warn("Kindlevel: statistics flush failed", err) end
    end
    if refresh ~= false then self:getStats():refresh() end
    local achievements = require("kindlevel_achievements")
    local ok, fresh, context = pcall(achievements.check, self, notify ~= false)
    if not ok then logger.warn("Kindlevel: achievement check failed", fresh); return end
    self.achievement_context = context
    self._achievement_last_check = os.time()
    for _, item in ipairs(fresh) do require("kindlevel_achievement_toast"):unlock(item, self.plugin_dir) end
    -- The achievement screen reads this cache, so repainting does not re-run triggers.
    if self.home and self.home.tab == "achievements" then self.home:rebuild() end
end

function Kindlevel:scheduleAchievementCheck(force)
    if self._achievement_stopped or self._achievement_pending then return end
    if not force and self._achievement_last_check and os.time() - self._achievement_last_check < 30 then return end
    self._achievement_pending = function()
        self._achievement_pending = nil
        local reader = require("apps/reader/readerui").instance
        local manager = require("apps/filemanager/filemanager").instance
        if reader == self.ui or not reader and manager == self.ui then self:checkAchievements() end
    end
    -- Wait until all native event handlers have updated their counters.
    UIManager:scheduleIn(0.1, self._achievement_pending)
end

function Kindlevel:onReaderReady()
    if not self._achievement_reader_ready then
        self._achievement_reader_ready=true
        local props=self.ui.doc_props or {}
        local authors=props.authors
        if type(authors)=="table" then authors=table.concat(authors,", ") end
        local achievements=require("kindlevel_achievements")
        achievements.recordSessionBreak(self)
        achievements.recordOpen(self,{title=props.title or props.display_title,author=authors})
    end
    self:scheduleAchievementCheck(true)
    require("kindlevel_auto_sync"):wake()
end
function Kindlevel:onPageUpdate() self:scheduleAchievementCheck(false) end
function Kindlevel:onPosUpdate() self:scheduleAchievementCheck(false) end
function Kindlevel:onAnnotationsModified() self:scheduleAchievementCheck(true) end
function Kindlevel:onSaveSettings()
    self.goals_imported = false
    self:scheduleAchievementCheck(true)
end
function Kindlevel:onBookMetadataChanged()
    self.goals_imported = false
    self:scheduleAchievementCheck(true)
end
function Kindlevel:onResume()
    self:scheduleAchievementCheck(true)
    local auto=require("kindlevel_auto_sync")
    auto.suspended=false
    auto:wake()
end

function Kindlevel:onNetworkConnected() require("kindlevel_auto_sync"):wake(true) end
function Kindlevel:onNetworkDisconnecting() require("kindlevel_auto_sync"):stop() end
function Kindlevel:onNetworkDisconnected() require("kindlevel_auto_sync"):stop() end

function Kindlevel:onCloseWidget()
    local auto=require("kindlevel_auto_sync")
    if auto:owner()==self or auto.job and auto.job.owner==self then auto:stop() end
end

function Kindlevel:cancelAchievementCheck()
    if self._achievement_pending then UIManager:unschedule(self._achievement_pending); self._achievement_pending = nil end
end

function Kindlevel:onSuspend()
    require("kindlevel_auto_sync"):stop(true)
    if self.ui.document then require("kindlevel_achievements").recordSessionBreak(self) end
    self:cancelAchievementCheck()
    require("kindlevel_achievement_toast"):clear()
end

function Kindlevel:onCloseDocument()
    require("kindlevel_auto_sync"):stop()
    require("kindlevel_achievements").recordSessionBreak(self)
    self._achievement_stopped = true
    self:cancelAchievementCheck()
end

function Kindlevel:onReadingPaused()
    if self.ui.document then require("kindlevel_achievements").recordSessionBreak(self) end
end

function Kindlevel:getGoals()
    if not self.goals then self.goals = require("kindlevel_goals"):new{ settings = self.settings, stats = self:getStats() } end
    if not self.goals_imported then
        local files = {}
        if self.ui.document and self.ui.document.file then files[#files + 1] = self.ui.document.file end
        for _, item in ipairs(require("readhistory").hist or {}) do files[#files + 1] = item.file end
        local library = self.home and self.home.library or self.goal_library
        if library then
            for _, item in ipairs(library.books) do files[#files + 1] = item.file end
        end
        self.goals:import(files)
        self.goals_imported = true
    end
    return self.goals
end

function Kindlevel:removeFinish(key, year)
    local ConfirmBox = require("ui/widget/confirmbox")
    UIManager:show(ConfirmBox:new{
        text = "Remove this book from your " .. tostring(year) .. " goal?",
        ok_text = "Remove", ok_callback = function()
            self:getGoals():remove(key, year)
            if self.home then self.home:rebuild() end
        end,
    })
end

function Kindlevel:setYearGoal(year)
    year = year or tonumber(os.date("%Y", self:getStats().now))
    local dialog
    dialog = InputDialog:new{
        title = "Books to finish in " .. tostring(year), input_type = "number",
        input = tostring(self:getGoals():target(year)),
        description = "Books per year. Enter 0 to turn the goal off.",
        buttons = { {
            { text = "Cancel", callback = function() UIManager:close(dialog) end },
            { text = "Save", is_enter_default = true, callback = function()
                if not self:getGoals():setTarget(year, tonumber(dialog:getInputText())) then
                    UIManager:show(InfoMessage:new{ text = "Enter a whole number from 0 to 10000." }); return
                end
                UIManager:close(dialog)
                if self.home then self.home:rebuild() end
            end },
        } },
    }
    UIManager:show(dialog); dialog:onShowKeyboard()
end

function Kindlevel:recordFinish(book)
    local dialog
    dialog = InputDialog:new{
        title = "Finish date · " .. book.title,
        input = os.date("%Y-%m-%d", self:getStats().now),
        description = "YYYY-MM-DD. This book counts once toward the goal for that year.",
        buttons = { {
            { text = "Cancel", callback = function() UIManager:close(dialog) end },
            { text = "Record finish", is_enter_default = true, callback = function()
                local date = dialog:getInputText()
                if not self:getGoals():validDate(date) then
                    UIManager:show(InfoMessage:new{ text = "Enter a valid date on or before today (YYYY-MM-DD)." }); return
                end
                self:getGoals():record(book, date, "manual")
                self.settings:flush()
                UIManager:close(dialog)
                self:checkAchievements()
                if self.home then self.home:rebuild() end
            end },
        } },
    }
    UIManager:show(dialog); dialog:onShowKeyboard()
end

function Kindlevel:setDailyGoal()
    local dialog
    dialog = InputDialog:new{
        title = "Daily reading goal", input_type = "number",
        input = tostring(self.settings:readSetting("daily_minutes") or 20),
        description = "Minutes per day. Enter 0 to turn the goal off.",
        buttons = { {
            { text = "Cancel", callback = function() UIManager:close(dialog) end },
            { text = "Save", is_enter_default = true, callback = function()
                local value = tonumber(dialog:getInputText())
                if not value or value < 0 or value > 1440 or value ~= math.floor(value) then
                    UIManager:show(InfoMessage:new{ text = "Enter a whole number from 0 to 1440." })
                    return
                end
                self.settings:saveSetting("daily_minutes", value)
                self.settings:flush()
                UIManager:close(dialog)
                if self.home then self.home:rebuild() end
            end },
        } },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function Kindlevel:statisticsTools()
    local collector = self.ui.statistics
    if not collector then
        UIManager:show(InfoMessage:new{ text = "Enable KOReader's Reading statistics plugin in the plugin manager to record your reading history." })
        return
    end
    local dialog
    local function action(callback)
        return function() UIManager:close(dialog); callback() end
    end
    dialog = ButtonDialog:new{
        title = "Reading statistics", buttons = {
            { { text = collector.settings.is_enabled and "Pause recording" or "Resume recording",
                callback = action(function() collector:onToggleStatistics(); self:refreshStats() end) } },
            { { text = "KOReader calendar", callback = action(function() collector:onShowCalendarView() end) } },
            { { text = "KOReader time ranges", callback = action(function() collector:onShowTimeRange() end) } },
            { { text = "Close", callback = function() UIManager:close(dialog) end } },
        },
    }
    UIManager:show(dialog)
end

function Kindlevel:openBook(book, after_open)
    if not book or lfs.attributes(book.file, "mode") ~= "file" then
        UIManager:show(InfoMessage:new{ text = "This book has moved or is no longer available. Refresh your library." })
        return
    end
    self.settings:saveSetting("selected_file", book.file)
    self.settings:saveSetting("return_to_home", true)
    self.settings:flush()
    if self.home then self.home:onClose() end
    local ReaderUI = require("apps/reader/readerui")
    ReaderUI:showReader(book.file, nil, nil, nil, after_open)
end

function Kindlevel:chooseFolder()
    local root = self:getRoot()
    local chooser = PathChooser:new{
        path = lfs.attributes(root, "mode") == "directory" and root or "/mnt/us/documents",
        select_directory = true,
        select_file = false,
        show_files = false,
        onConfirm = function(path)
            self:setRoot(path)
        end,
    }
    UIManager:show(chooser)
end

function Kindlevel:setRoot(path)
    self.settings:saveSetting("library_root", path)
    self.settings:delSetting("selected_file")
    self.settings:flush()
    if self.home then
        self.home.library.root = path
        self.home:rescan()
    end
end

function Kindlevel:useSamples()
    self:setRoot(self.plugin_dir .. "/books")
end

function Kindlevel:toggleAutoHome()
    self.settings:saveSetting("auto_home", not self.settings:isTrue("auto_home"))
    self.settings:flush()
    if self.home then self.home:rebuild() end
end

return Kindlevel
