-- Integration checks run against official KOReader, not mocked widgets or renderers.
require("setupkoenv")
G_defaults = require("luadefaults"):open()
G_reader_settings = require("luasettings"):open("/tmp/readinghome-smoke-settings.lua")
G_reader_settings:saveSetting("sdl_window", { width = tonumber(os.getenv("TEST_WIDTH")) or 1072, height = tonumber(os.getenv("TEST_HEIGHT")) or 1448 })
G_reader_settings:saveSetting("color_rendering", false)
G_reader_settings:saveSetting("back_to_exit", "disable")
local Device = require("device")
require("document/canvascontext"):init(Device)
require("ui/bidi").setup()
local UIManager = require("ui/uimanager")
local Blitbuffer = require("ffi/blitbuffer")
local LuaSettings = require("luasettings")
local lfs = require("libs/libkoreader-lfs")
local util = require("util")
local root = "/workspace"
local plugin = root .. "/readinghome.koplugin"
package.path = plugin .. "/?.lua;" .. package.path
local Library = require("readinghome_library")
local Home = require("readinghome_screen")
require("readhistory").hist = {}

local function expect(condition, message)
    assert(condition, message)
    print("PASS: " .. message)
end

local output = root .. "/dist/previews"
local fixtures = "/tmp/readinghome-books"
util.makePath(fixtures)
for name in lfs.dir(plugin .. "/books") do
    local path = plugin .. "/books/" .. name
    if lfs.attributes(path, "mode") == "file" then
        local input = assert(io.open(path, "rb"))
        local target = assert(io.open(fixtures .. "/" .. name, "wb"))
        target:write(input:read("*a"))
        input:close()
        target:close()
    end
end
local library = Library:new{ root = fixtures }
library:scan()
expect(#library.books == 3, "scanner finds the two EPUBs and TXT, excluding adjacent cover images")
library:inspect(library.books[1])
expect(library.books[1].title == "A Quiet Beginning", "EPUB metadata loads through KOReader")
expect(library.books[1].author == "Reading Home", "EPUB author is extracted")
expect(library.books[1].percent == nil, "unopened books have no invented reading progress")

local owner = {
    plugin_dir = plugin,
    settings = LuaSettings:open("/tmp/readinghome-owner-settings.lua"),
    chooseFolder = function() end,
    useSamples = function() end,
    toggleAutoHome = function() end,
}
local opened
owner.openBook = function(_, book) opened = book.file end
local home = Home:new{ owner = owner, library = library }
owner.home = home
UIManager:show(home)

local function render(name)
    local bb = Blitbuffer.new(home.width, home.height, Blitbuffer.TYPE_BB8)
    home:paintTo(bb, 0, 0)
    bb:writePNG(output .. "/" .. name .. ".png")
    bb:free()
    for _, hit in ipairs(home.hits) do
        expect(hit.x >= 0 and hit.y >= 0 and hit.x + hit.w <= home.width + 1 and hit.y + hit.h <= home.height + 1,
            "tap area stays on screen: " .. (hit.id or "anonymous"))
    end
end

local function tap(id)
    for _, hit in ipairs(home.hits) do
        if hit.id == id then
            home:onTapReadingHome(nil, { pos = { x = hit.x + hit.w / 2, y = hit.y + hit.h / 2 } })
            return
        end
    end
    error("Missing tap area: " .. id)
end

render("reading")
home:onSwipeReadingHome(nil, { direction = "west" })
expect(home.index == 2, "swipe advances the cover carousel")
render("carousel")
tap("start-reading")
expect(opened == library.books[2].file, "reading button opens the selected file")
tap("tab-library")
render("library")
tap("book-3")
expect(home.tab == "read" and home.index == 3, "library selection returns to the correct carousel book")
render("text-book")
tap("tab-settings")
render("settings")
home:onBack()
expect(home.tab == "read", "back leaves settings for reading")
home:onClose()
expect(owner.home == nil and home.closed, "closing releases home and rendering resources")

-- Verify empty libraries and failed directory reads remain usable.
local empty = Library:new{ root = "/tmp/does-not-exist" }
empty:scan()
expect(#empty.books == 0 and empty.warnings.unreadable, "missing folder produces an empty library instead of crashing")
home = Home:new{ owner = owner, library = empty }
owner.home = home
UIManager:show(home)
render("empty-library")
home:onClose()

-- Exercise the real file manager/plugin loader/reader lifecycle.
local PluginLoader = require("pluginloader")
local ReadingHome = dofile(plugin .. "/main.lua")
ReadingHome.path = plugin
PluginLoader.enabled_plugins = { ReadingHome }
PluginLoader.disabled_plugins = {}
PluginLoader.loaded_plugins = {}
local FileManager = require("apps/filemanager/filemanager")
local ReaderUI = require("apps/reader/readerui")
local DataStorage = require("datastorage")
local plugin_settings = LuaSettings:open(DataStorage:getSettingsDir() .. "/readinghome.lua")
plugin_settings:saveSetting("library_root", fixtures)
plugin_settings:saveSetting("auto_home", false)
plugin_settings:delSetting("return_to_home")
plugin_settings:flush()
FileManager:showFiles(fixtures)
local fm = FileManager.instance
expect(fm.readinghome ~= nil, "KOReader loads the plugin and registers it in file manager")
fm.readinghome:onReadingHome()
expect(fm.readinghome.home ~= nil, "plugin menu opens the custom home")
local selected = fm.readinghome.home.library.books[1]
fm.readinghome:openBook(selected)

-- Drive KOReader's event loop until its document-loading coroutine is ready.
UIManager:scheduleIn(1, function()
    local reader = ReaderUI.instance
    expect(reader and reader.document, "custom home opens EPUB in the real KOReader reader")
    expect(reader.readinghome ~= nil, "plugin also registers in the reader")
    expect(reader.document:getPageCount() > 1, "sample EPUB paginates successfully")
    reader.rolling:onGotoPage(2)
    reader.readinghome:onReadingHome()
    UIManager:scheduleIn(0.5, function()
        local back = FileManager.instance
        expect(ReaderUI.instance == nil, "return action saves and closes the reader")
        expect(back and back.readinghome.home, "return action restores custom home without a core patch")
        local returned_home = back.readinghome.home
        local book = returned_home.library.books[returned_home.index]
        expect(book.percent and book.percent > 0, "saved KOReader progress is shown on the home")
        home = returned_home
        render("resumed-reading")
        back.readinghome:openBook(book)
        UIManager:scheduleIn(0.5, function()
            local resumed = ReaderUI.instance
            expect(resumed and resumed.rolling.current_page >= 2, "reopening resumes the saved reading position")
            resumed:onClose()
            FileManager:showFiles(fixtures)
            UIManager:scheduleIn(0.3, function()
                local next_fm = FileManager.instance
                if not next_fm.readinghome.home then next_fm.readinghome:onReadingHome() end
                local books = next_fm.readinghome.home.library.books
                local text_book
                for _, candidate in ipairs(books) do
                    if candidate.format == "TXT" then text_book = candidate end
                end
                expect(text_book ~= nil, "plain-text sample remains available alongside EPUBs")
                next_fm.readinghome:openBook(text_book)
                UIManager:scheduleIn(0.5, function()
                    local text_reader = ReaderUI.instance
                    expect(text_reader and text_reader.document.file == text_book.file,
                        "plain text opens successfully in the real reader")
                    text_reader:onClose()
                    UIManager:quit()
                    print("ALL KOReader integration checks passed")
                end)
            end)
        end)
    end)
end)
UIManager:scheduleIn(15, function() error("KOReader smoke test timed out") end)
UIManager:run()
