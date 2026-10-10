local DataStorage = require("datastorage")
local Dispatcher = require("dispatcher")
local InfoMessage = require("ui/widget/infomessage")
local LuaSettings = require("luasettings")
local PathChooser = require("ui/widget/pathchooser")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local ffiUtil = require("ffi/util")
local lfs = require("libs/libkoreader-lfs")

local ReadingHome = WidgetContainer:extend{
    name = "readinghome",
    is_doc_only = false,
}

function ReadingHome:init()
    self.plugin_dir = ffiUtil.realpath(self.path or "plugins/readinghome.koplugin")
        or self.path or "plugins/readinghome.koplugin"
    self.settings = LuaSettings:open(DataStorage:getSettingsDir() .. "/readinghome.lua")
    self.ui.menu:registerToMainMenu(self)
    Dispatcher:registerAction("readinghome_open", {
        category = "none", event = "ReadingHome", title = "Reading Home", general = true,
    })
    if not self.ui.document then
        local returning = self.settings:isTrue("return_to_home")
        if returning or self.settings:isTrue("auto_home") then
            self.settings:delSetting("return_to_home")
            self.settings:flush()
            UIManager:nextTick(function()
                -- A scheduled callback must not reopen a home on a retired file manager.
                local FileManager = require("apps/filemanager/filemanager")
                if FileManager.instance == self.ui then self:onReadingHome() end
            end)
        end
    end
end

function ReadingHome:addToMainMenu(items)
    items.readinghome = {
        text = "Reading Home",
        sorting_hint = "more_tools",
        callback = function() self:onReadingHome() end,
    }
end

function ReadingHome:getRoot()
    return self.settings:readSetting("library_root") or self.plugin_dir .. "/books"
end

function ReadingHome:onReadingHome()
    if self.ui.document then
        self.settings:saveSetting("return_to_home", true)
        self.settings:flush()
        -- Use KOReader's normal path so it saves the reading position and closes safely.
        self.ui:onHome()
        return true
    end
    if self.home then return true end
    local Library = require("readinghome_library")
    local Screen = require("readinghome_screen")
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

function ReadingHome:openBook(book)
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

function ReadingHome:chooseFolder()
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

function ReadingHome:setRoot(path)
    self.settings:saveSetting("library_root", path)
    self.settings:delSetting("selected_file")
    self.settings:flush()
    if self.home then
        self.home.library.root = path
        self.home:rescan()
    end
end

function ReadingHome:useSamples()
    self:setRoot(self.plugin_dir .. "/books")
end

function ReadingHome:toggleAutoHome()
    self.settings:saveSetting("auto_home", not self.settings:isTrue("auto_home"))
    self.settings:flush()
    if self.home then self.home:rebuild() end
end

return ReadingHome
