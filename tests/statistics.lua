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

local month = stats:monthData(date(10))
assert(month.days["2026-10-10"].books[1].id == 1 and #month.days["2026-10-10"].books == 2,
    "month includes each book read on an overlapping day")
assert(month.days["2026-10-10"].hours[8] == 180 and month.days["2026-10-10"].hours[9] == 60,
    "hourly histograms use original durations without page-rescaling duplicates")
local Goals = require("kindlevel_goals")
local goal_settings = LuaSettings:open("/tmp/kindlevel-year-goal-settings.lua")
local goals = Goals:new{ settings = goal_settings, stats = stats }
assert(goals:target(2026) == 24 and goals:setTarget(2026, 12), "year goal is configurable")
assert(not goals:setTarget(2026, -1) and not goals:setTarget(2026, 1.5), "invalid targets are rejected")
assert(not goals:validDate("2026-02-30") and not goals:validDate("2026-10-11"), "invalid and future finish dates are rejected")
assert(goals:record(stats:book(1), "2026-10-09", "manual"), "confirmed finish is recorded")
assert(not goals:record(stats:book(1), "2026-10-09", "manual"), "duplicate finish is idempotent")
goals:record(stats:book(1), "2026-10-10", "manual")
assert(#goals:list(2026) == 1, "rereading does not count a book twice in a year")
goals:record(stats:book(1), "2025-12-31", "manual")
assert(#goals:list(2025) == 1 and #goals:list(2026) == 1, "each year retains its own completion")
goals:record(stats:book(2), "2026-10-10", "manual")
local persisted = Goals:new{ settings = LuaSettings:open("/tmp/kindlevel-year-goal-settings.lua"), stats = stats }
goal_settings:flush()
persisted.settings = LuaSettings:open("/tmp/kindlevel-year-goal-settings.lua")
assert(#persisted:list(2026) == 2 and persisted:target(2026) == 12, "goal and confirmed finishes persist")
local DocSettings = require("docsettings")
local file = "/tmp/kindlevel-native-completion.epub"
local f = assert(io.open(file, "w")); f:close()
local sidecar = DocSettings:open(file)
sidecar:saveSetting("summary", { status = "complete", modified = "2026-10-09" })
sidecar:saveSetting("doc_props", { title = "A Quiet Beginning", authors = "Kindlevel" })
sidecar:saveSetting("partial_md5_checksum", "one")
sidecar:flush()
goals:remove(Goals.key(stats:book(1)), 2026)
goals:import{ file }
assert(#goals:list(2026) == 1, "removing a finish suppresses automatic reimport for that year")
goals:record(stats:book(1), "2026-10-08", "manual")
goals:import{ file }
assert(goals:list(2026)[2].date == "2026-10-08", "native import preserves an explicitly corrected finish date")
local fresh = Goals:new{ settings = LuaSettings:open("/tmp/kindlevel-native-import-settings.lua"), stats = stats }
assert(fresh:import{ file } and #fresh:list(2026) == 1, "KOReader Finished sidecar date is imported")

local Calendar = require("kindlevel_calendar")
local fake = { begin = Stats.date("2024-11-01"), finish = Stats.date("2024-12-01"), days = {} }
for day = 9, 28 do
    local key = string.format("2024-11-%02d", day)
    fake.days[key] = { books = {} }
    if day <= 12 then fake.days[key].books[#fake.days[key].books + 1] = { id = 1, title = "Plum Island" } end
    if day >= 13 then fake.days[key].books[#fake.days[key].books + 1] = { id = 2, title = "The Final Empire" } end
    if day == 16 then fake.days[key].books[#fake.days[key].books + 1] = { id = 1, title = "Plum Island" } end
end
local layout = Calendar.monthLayout(fake, 2)
assert(layout.weeks == 5 and layout.offset == 4 and layout.count == 30, "reference November 2024 has the correct grid")
for _, ribbon in ipairs(layout.ribbons) do
    assert(ribbon.first >= 0 and ribbon.last <= 6 and ribbon.first <= ribbon.last, "ribbons split at week edges")
end
local overlapping = {}
for _, ribbon in ipairs(layout.ribbons) do
    if ribbon.week == 2 then overlapping[ribbon.id] = ribbon.lane end
end
assert(overlapping[1] and overlapping[2] and overlapping[1] ~= overlapping[2], "overlapping titles use distinct lanes")
assert(Calendar.monthLayout({ begin = Stats.date("2021-02-01"), finish = Stats.date("2021-03-01"), days = {} }, 2).weeks == 4,
    "four-week February is supported")
assert(Calendar.monthLayout({ begin = Stats.date("2024-02-01"), finish = Stats.date("2024-03-01"), days = {} }, 2).count == 29,
    "leap February includes day 29")
assert(Calendar.monthLayout({ begin = Stats.date("2026-08-01"), finish = Stats.date("2026-09-01"), days = {} }, 1).weeks == 6,
    "six-week months are supported")

local Library = require("kindlevel_library")
local owner = { plugin_dir = "/workspace/kindlevel.koplugin", settings = LuaSettings:open("/tmp/kindlevel-ui-goals.lua"),
    getStats = function() return stats end, getGoals = function() return goals end }
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
home:onBack()
tap("book-calendar")
assert(home.stats_view == "month", "book-calendar action opens the month view")
home.stats_month = Stats.month(date(10))
render("book-calendar")
local ribbon_id
for _, hit in ipairs(home.hits) do if hit.id and hit.id:match("^month%-book%-1%-") then ribbon_id = hit.id; break end end
tap(ribbon_id)
assert(home.stats_view == "book" and home.stats_book_id == 1, "book ribbons take touch priority over their day cells")
home:onBack()
assert(home.stats_view == "month", "back restores the book calendar")
home.stats_month = Stats.date("2026-08-01")
render("book-calendar-six-weeks")
tap("year-goal")
assert(home.stats_view == "goal", "year goal header opens confirmed completions")
render("year-goal")
local recorded_without_history
owner.recordFinish = function(_, selected) recorded_without_history = selected end
home.stats_view, home.stats_book_id = "book", nil
home.stats_library_book = library.books[2]
render("book-without-statistics")
tap("record-finish")
assert(recorded_without_history == library.books[2], "a local book without statistics can still record a confirmed finish")
home:onClose()
print("ALL statistics, goals, month calendars, native query parity, read-only, and UI checks passed")
