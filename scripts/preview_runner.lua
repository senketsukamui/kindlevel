-- Real KOReader running with an SDL software framebuffer. The host browser
-- receives rendered PNGs and sends touch/key events through a local file queue.
require("setupkoenv")
io.stdout:setvbuf("line")
local lfs = require("libs/libkoreader-lfs")
local json = require("json")
local ipc = os.getenv("KINDLEVEL_PREVIEW_IPC") or "/preview"
local function read(path)
    local f = io.open(path, "rb")
    if not f then return end
    local data = f:read("*a"); f:close(); return data
end
local config = assert(json.decode(assert(read(ipc .. "/config.json"))))
G_defaults = require("luadefaults"):open()
local DataStorage = require("datastorage")
G_reader_settings = require("luasettings"):open(DataStorage:getDataDir() .. "/settings.reader.lua")
G_reader_settings:saveSetting("sdl_window", { width = config.width, height = config.height })
G_reader_settings:saveSetting("color_rendering", false)
G_reader_settings:saveSetting("back_to_exit", "disable")
local Device = require("device")
require("document/canvascontext"):init(Device)
require("ui/bidi").setup()
local UIManager = require("ui/uimanager")
local Event = require("ui/event")
local Geom = require("ui/geometry")
local Key = require("device/key")
local plugin = "/workspace/kindlevel.koplugin"
package.path = plugin .. "/?.lua;plugins/statistics.koplugin/?.lua;" .. package.path
local Kindlevel = dofile(plugin .. "/main.lua")
Kindlevel.path = plugin
local NativeStatistics = dofile("plugins/statistics.koplugin/main.lua")
NativeStatistics.path = "plugins/statistics.koplugin"
local PluginLoader = require("pluginloader")
PluginLoader.enabled_plugins = { Kindlevel, NativeStatistics }
PluginLoader.disabled_plugins, PluginLoader.loaded_plugins = {}, {}

local settings = require("luasettings"):open(DataStorage:getSettingsDir() .. "/kindlevel.lua")
settings:saveSetting("library_root", "/preview/books")
settings:saveSetting("auto_home", false)
settings:delSetting("return_to_home")
settings:flush()
if config.demo and not settings:has("finished_books") then
    local Stats = require("kindlevel_stats")
    local stats = Stats:new():load()
    local Goals = require("kindlevel_goals")
    local goals = Goals:new{ settings = settings, stats = stats }
    local first = os.time{ year = tonumber(os.date("%Y", stats.now)), month = 1, day = 1, hour = 0, min = 0, sec = 0 }
    for id = 1, 2 do
        local book = stats:book(id)
        if book then goals:record(book, os.date("%Y-%m-%d", math.max(first, Stats.day(stats.now, -id * 30))), "manual") end
    end
    settings:flush()
end
require("apps/filemanager/filemanager"):showFiles("/preview/books")
require("apps/filemanager/filemanager").instance.kindlevel:onKindlevel("stats")

local sequence = 0
local frame = 0
local Toasts = require("kindlevel_achievement_toast")
local function capture()
    frame = frame + 1
    UIManager:forceRePaint()
    Device.screen.bb:writePNG(ipc .. "/screen.next.png")
    assert(os.rename(ipc .. "/screen.next.png", ipc .. "/screen.png"))
    local f = assert(io.open(ipc .. "/state.next.json", "w"))
    local manager = require("apps/filemanager/filemanager").instance
    local home = manager and manager.kindlevel and manager.kindlevel.home
    f:write(json.encode{ sequence = sequence, frame = frame, width = Device.screen:getWidth(), height = Device.screen:getHeight(),
        demo = config.demo, rendered = os.time(), achievement_toast = Toasts.active and Toasts.active.achievement.id or false,
        tab = home and home.tab, stats_view = home and home.stats_view, stats_book_id = home and home.stats_book_id,
        stats_list_page = home and home.stats_list_page, recovery_mode = home and (home.stats_recovery_mode or "reading"),
        break_days = home and home:journeyThreshold() })
    f:close()
    assert(os.rename(ipc .. "/state.next.json", ipc .. "/state.json"))
end
Toasts.observer = function() UIManager:scheduleIn(0.05, capture) end

local function poll()
    local commands = {}
    for name in lfs.dir(ipc .. "/commands") do
        if name:match("%.json$") then commands[#commands + 1] = name end
    end
    table.sort(commands)
    for _, name in ipairs(commands) do
        local path = ipc .. "/commands/" .. name
        local command = json.decode(assert(read(path)))
        os.remove(path)
        sequence = command.sequence
        if command.type == "tap" or command.type == "swipe" then
            UIManager:sendEvent(Event:new("Gesture", { ges = command.type,
                pos = Geom:new{ x = command.x, y = command.y, w = 0, h = 0 }, direction = command.direction }))
        elseif command.type == "key" then
            UIManager:sendEvent(Event:new("KeyPress", Key:new(command.key, {})))
        elseif command.type == "text" then UIManager:sendEvent(Event:new("TextInput", command.text)) end
        UIManager:scheduleIn(0.15, capture)
        UIManager:scheduleIn(0.8, capture) -- Includes deferred document loading and keyboard layout.
    end
    UIManager:scheduleIn(0.1, poll)
end
UIManager:scheduleIn(0.3, capture)
UIManager:scheduleIn(0.4, poll)
UIManager:run()
