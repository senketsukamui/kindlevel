-- Uses actual KOReader widgets, timers, input routing, and the document reader.
require("setupkoenv")
G_defaults = require("luadefaults"):open()
G_reader_settings = require("luasettings"):open("/tmp/kindlevel-achievement-test-settings.lua")
G_reader_settings:saveSetting("sdl_window", { width = 1072, height = 1448 })
G_reader_settings:saveSetting("color_rendering", false)
G_reader_settings:saveSetting("back_to_exit", "disable")
local Device = require("device")
require("document/canvascontext"):init(Device)
require("ui/bidi").setup()
local UIManager = require("ui/uimanager")
local Event = require("ui/event")
local Geom = require("ui/geometry")
local Widget = require("ui/widget/widget")
local Blitbuffer = require("ffi/blitbuffer")
local lfs = require("libs/libkoreader-lfs")
local util = require("util")
local plugin = "/workspace/kindlevel.koplugin"
package.path = plugin .. "/?.lua;plugins/statistics.koplugin/?.lua;" .. package.path
local Achievements = require("kindlevel_achievements")
local Toasts = require("kindlevel_achievement_toast")
local first = Achievements.find("first_pages")
assert(first and first.xp == 25, "preview definition exists")
assert(Achievements.progress(first, { minutes = 10 }).ratio < 1, "progress below criterion")
assert(Achievements.progress(first, { minutes = 50 }).ratio == 1, "progress is capped for display")

local taps = 0
local Background = Widget:extend{ covers_fullscreen = true, dimen = Device.screen:getSize() }
function Background:paintTo(bb) bb:fill(Blitbuffer.COLOR_WHITE) end
function Background:onGesture() taps = taps + 1; return true end
local background = Background:new{}
UIManager:show(background)
Toasts:preview(first, plugin)
local toast = Toasts.active
assert(toast.dimen.x > Device.screen:getWidth()/3 and toast.dimen.y < Device.screen:getHeight()/5, "toast is in the upper-right corner")
assert(toast.dimen.x + toast.dimen.w <= Device.screen:getWidth() and toast.dimen.y + toast.dimen.h <= Device.screen:getHeight(),
    "toast and shadow remain inside screen")
UIManager:forceRePaint()
Device.screen.bb:writePNG("/workspace/dist/previews/achievement-toast.png")
UIManager:sendEvent(Event:new("Gesture", { ges = "tap", pos = Geom:new{ x = 10, y = 700, w = 0, h = 0 } }))
assert(Toasts.active == nil and toast.closed and taps == 1, "toast dismisses without swallowing the original input")
Toasts:preview(first, plugin, 0.12)
Toasts:preview(Achievements.find("consistent_reader"), plugin, 0.12)
assert(#Toasts.pending == 1, "multiple notifications queue")
UIManager:scheduleIn(0.3, function()
    assert(Toasts.active == nil, "first toast expires automatically")
end)

-- Start a normal reader after the timed queue completes.
UIManager:scheduleIn(0.7, function()
    assert(Toasts.active == nil and #Toasts.pending == 0, "queued notifications expire and release their resources")
    UIManager:close(background)
    local fixtures = "/tmp/kindlevel-achievement-books"
    util.makePath(fixtures)
    for name in lfs.dir(plugin .. "/books") do
        local path = plugin .. "/books/" .. name
        if lfs.attributes(path, "mode") == "file" then
            local source = assert(io.open(path, "rb")); local target = assert(io.open(fixtures .. "/" .. name, "wb"))
            target:write(source:read("*a")); source:close(); target:close()
        end
    end
    local Kindlevel = dofile(plugin .. "/main.lua"); Kindlevel.path = plugin
    local Native = dofile("plugins/statistics.koplugin/main.lua"); Native.path = "plugins/statistics.koplugin"
    local PluginLoader = require("pluginloader")
    PluginLoader.enabled_plugins = { Kindlevel, Native }
    PluginLoader.disabled_plugins, PluginLoader.loaded_plugins = {}, {}
    local FileManager = require("apps/filemanager/filemanager")
    local ReaderUI = require("apps/reader/readerui")
    local settings = require("luasettings"):open(require("datastorage"):getSettingsDir() .. "/kindlevel.lua")
    settings:saveSetting("library_root", fixtures); settings:flush()
    FileManager:showFiles(fixtures)
    FileManager.instance.kindlevel:onKindlevel("achievements")
    local owner = FileManager.instance.kindlevel
    UIManager:forceRePaint()
    Device.screen.bb:writePNG("/workspace/dist/previews/achievements.png")
    owner:previewAchievementInBook()
    UIManager:scheduleIn(1.2, function()
        local reader = ReaderUI.instance
        assert(reader and reader.document and Toasts.active, "preview toast appears over a real book")
        UIManager:forceRePaint()
        Device.screen.bb:writePNG("/workspace/dist/previews/achievement-over-book.png")
        local before = reader.rolling.current_page
        UIManager:sendEvent(Event:new("Gesture", { ges = "tap", pos = Geom:new{ x = 1000, y = 1000, w = 0, h = 0 } }))
        UIManager:scheduleIn(0.2, function()
            assert(Toasts.active == nil and reader.rolling.current_page > before, "page turns normally when a toast is visible")
            assert(owner.settings:readSetting("achievement_unlocks") == nil and owner.settings:readSetting("xp") == nil,
                "preview does not save awards or XP")
            reader:onClose()
            UIManager:quit()
            print("ALL achievement POC checks passed: rendering, timers, queue, input passthrough, real reading, and no saved rewards")
        end)
    end)
end)
UIManager:scheduleIn(10, function() error("Achievement test timed out") end)
UIManager:run()
