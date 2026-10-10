local DataStorage = require("datastorage")
local Dispatcher = require("dispatcher")
local InfoMessage = require("ui/widget/infomessage")
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
end

function Kindlevel:getRoot()
    return self.settings:readSetting("library_root") or self.plugin_dir .. "/books"
end

function Kindlevel:onKindlevel()
    if self.ui.document then
        self.settings:saveSetting("return_to_home", true)
        self.settings:flush()
        -- Use KOReader's normal path so it saves the reading position and closes safely.
        self.ui:onHome()
        return true
    end
    if self.home then return true end
    local Library = require("kindlevel_library")
    local Screen = require("kindlevel_screen")
    local library = Library:new{ root = self:getRoot() }
    library:scan()
    self.home = Screen:new{
        owner = self,
        library = library,
        selected_file = self.settings:readSetting("selected_file"),
    }
    UIManager:show(self.home, "full")
    return true
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
