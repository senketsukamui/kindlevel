-- Golden-data integration checks using KOReader's own schema and SQLite library.
require("setupkoenv")
G_defaults = require("luadefaults"):open()
G_reader_settings = require("luasettings"):open("/tmp/kindlevel-stats-test-settings.lua")
G_reader_settings:saveSetting("sdl_window", { width = 1072, height = 1448 })
local Device = require("device")
require("document/canvascontext"):init(Device)
require("ui/bidi").setup()
local SQ3 = require("lua-ljsqlite3/init")
local UIManager = require("ui/uimanager")
local Blitbuffer = require("ffi/blitbuffer")
local LuaSettings = require("luasettings")
local Geom = require("ui/geometry")
package.path = "/workspace/kindlevel.koplugin/?.lua;plugins/statistics.koplugin/?.lua;" .. package.path
local Native = dofile("plugins/statistics.koplugin/main.lua")
local path = "/tmp/kindlevel-golden-statistics.sqlite3"
local conn = SQ3.open(path)
Native:createDB(conn)
conn:exec("INSERT INTO book (id,title,authors,pages,highlights,notes,md5) VALUES (1,'A Quiet Beginning','Kindlevel',20,5,2,'one');")
local book = conn:prepare("INSERT INTO book (id,title,authors,pages,highlights,notes,md5) VALUES (2,?,'Kindlevel',10,8,1,'two');")
book:bind("L'été · 東京"):step(); book:close()
local function date(day, hour, minute)
    return os.time{ year = 2026, month = 10, day = day, hour = hour or 0, min = minute or 0, sec = 0 }
end
local insert = conn:prepare("INSERT INTO page_stat_data VALUES (?,?,?,?,?);")
for _, row in ipairs{
    { 1, 1, date(9, 7), 60, 10 }, { 1, 2, date(9, 8), 60, 10 },
    { 1, 1, date(10, 7, 30), 120, 10 }, { 1, 1, date(10, 7, 32) + 20, 60, 10 },
    { 2, 2, date(10, 8), 60, 10 },
} do insert:reset():bind(unpack(row)):step() end
insert:close()
conn:close()
local Stats = require("kindlevel_stats")
local stats = Stats:new{ path = path, now = date(10, 12) }:load()
assert(not stats.error, "supported KOReader schema")
assert(stats.days["2026-10-10"].pages == 3, "page_stat rescales layout and deduplicates reread pages per day")
assert(stats.days["2026-10-10"].seconds == 240, "rereading time is retained")
assert(stats.days["2026-10-09"].pages == 4, "old-layout pages count in current book pagination")
local series, total = stats:series("7")
assert(#series == 7 and total.pages == 7 and total.seconds == 360, "seven-day totals match golden data")
assert(total.active_days == 2 and total.record == 4 and total.average == 1, "average includes days with no reading")
assert(stats:streak() == 2, "current streak spans yesterday and today")
assert(stats:book(1).pages == 4 and stats:book(1).seconds == 300, "book lifetime counts distinct pages")
assert(stats:book(1).average_seconds == 75, "per-page estimate uses KOReader's capped-duration calculation")
assert(stats:book(2).title == "L'été · 東京", "Unicode and apostrophes remain intact")
local details = stats:dayDetails("2026-10-10")
assert(#details.sessions == 2 and details.sessions[1].seconds == 180, "adjacent raw events merge without rescaling duplicates")
assert(#details.books == 2, "day view lists the books read")
local _, year = stats:series("year", 2026)
assert(year.pages == 7 and year.seconds == 360, "year totals agree with daily totals")
local other = Stats:new{ path = path, now = date(11, 12) }
assert(other:streak() == 2, "streak remains active before reading today")
other.now = date(12, 12)
assert(other:streak() == 0, "missed day ends streak")
local changed, write_error = stats:query(function(c) c:exec("UPDATE book SET title='must not write';"); return true end)
assert(changed == nil and write_error, "adapter connections reject writes")
assert(stats:refresh():book(1).title == "A Quiet Beginning", "read-only adapter leaves data unchanged")
local missing = Stats:new{ path = "/tmp/no-kindlevel-history.sqlite3" }:load()
assert(missing.error == "missing", "missing history is handled explicitly")

-- Compare our daily values with the native plugin's daily grouping query.
local native_daily = SQ3.open(path, "ro")
local result = native_daily:exec([[
 SELECT dates, count(*) AS pages, sum(sum_duration) AS durations FROM (
  SELECT strftime('%Y-%m-%d', start_time, 'unixepoch', 'localtime') AS dates,
         sum(duration) AS sum_duration FROM page_stat GROUP BY id_book,page,dates
 ) GROUP BY dates ORDER BY dates;
]])
for i, key in ipairs(result.dates) do
    assert(stats.days[key].pages == tonumber(result.pages[i]) and stats.days[key].seconds == tonumber(result.durations[i]),
        "native daily query parity")
end
native_daily:close()

local Library = require("kindlevel_library")
local owner = { plugin_dir = "/workspace/kindlevel.koplugin", settings = LuaSettings:open("/tmp/kindlevel-ui-goals.lua"),
    getStats = function() return stats end }
local library = Library:new{ root = owner.plugin_dir .. "/books" }
library:scan()
local home = require("kindlevel_screen"):new{ owner = owner, library = library, initial_tab = "stats" }
owner.home = home
home.stats_year = 2026
UIManager:show(home)
local function render(name)
    home:rebuild()
    local bb = Blitbuffer.new(home.width, home.height, Blitbuffer.TYPE_BB8)
    home:paintTo(bb, 0, 0)
    bb:writePNG("/workspace/dist/previews/" .. name .. ".png")
    bb:free()
    for _, hit in ipairs(home.hits) do
        assert(hit.x >= 0 and hit.y >= 0 and hit.x + hit.w <= home.width + 1 and hit.y + hit.h <= home.height + 1,
            "tap area stays on screen: " .. (hit.id or "anonymous"))
    end
end
local function tap(id)
    for _, hit in ipairs(home.hits) do
        if hit.id == id then
            home:onGesture{ ges = "tap", pos = Geom:new{ x = hit.x + hit.w/2, y = hit.y + hit.h/2, w = 0, h = 0 } }
            return
        end
    end
    error("Missing tap area: " .. id)
end
render("statistics")
tap("period-year")
render("statistics-year")
tap("calendar-2026-10-10")
assert(home.stats_view == "day", "calendar touch dispatch opens day view")
render("statistics-day")
tap("session-1")
assert(home.stats_view == "book" and home.stats_book_id == 1, "session touch dispatch opens book details")
render("statistics-book")
home:onBack()
assert(home.stats_view == "day", "back from a book restores the day journal")
home:onBack()
tap("period-7")
tap("metric-seconds")
assert(home.stats_metric == "seconds", "time toggle works through real gesture dispatch")
render("statistics-time")
tap("stats-books")
render("statistics-books")
home:onClose()
print("ALL statistics, native query parity, read-only, and statistics UI checks passed")
