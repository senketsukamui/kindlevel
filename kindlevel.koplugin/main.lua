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
    end
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
        if tab then self.home.tab = tab; self.home:rebuild() end
        return true
    end
    local Library = require("kindlevel_library")
    local Screen = require("kindlevel_screen")
    local library = Library:new{ root = self:getRoot() }
    library:scan()
    self.home = Screen:new{
        owner = self,
        library = library,
        selected_file = self.settings:readSetting("selected_file"),
        initial_tab = tab or self.settings:readSetting("open_tab"),
    }
    self.settings:delSetting("open_tab")
    self.settings:flush()
    UIManager:show(self.home, "full")
    return true
end

function Kindlevel:getStats()
    if not self.stats then self.stats = require("kindlevel_stats"):new() end
    return self.stats
end

function Kindlevel:refreshStats()
    self:getStats():refresh()
    if self.home then self.home:rebuild() end
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

function Kindlevel:openBook(book)
    if not book or lfs.attributes(book.file, "mode") ~= "file" then
        UIManager:show(InfoMessage:new{ text = "This book has moved or is no longer available. Refresh your library." })
        return
    end
    self.settings:saveSetting("selected_file", book.file)
    self.settings:saveSetting("return_to_home", true)
    self.settings:flush()
    if self.home then self.home:onClose() end
    local ReaderUI = require("apps/reader/readerui")
    ReaderUI:showReader(book.file)
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
