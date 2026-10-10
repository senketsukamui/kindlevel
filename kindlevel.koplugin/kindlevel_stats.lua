-- Reads KOReader Reading Statistics' existing database without changing it.
-- The daily grouping and use of page_stat follow KOReader's statistics plugin
-- (AGPL-3.0): https://github.com/koreader/koreader/tree/master/plugins/statistics.koplugin
-- page_stat rescales recorded pages after font/layout changes; raw rows are
-- used only for session intervals, where rescaling would duplicate events.
local DataStorage = require("datastorage")
local DocSettings = require("docsettings")
local SQ3 = require("lua-ljsqlite3/init")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")

local Stats = {}
Stats.__index = Stats

function Stats.day(timestamp, delta)
    local date = os.date("*t", timestamp or os.time())
    return os.time{ year = date.year, month = date.month, day = date.day + (delta or 0), hour = 0, min = 0, sec = 0 }
end

function Stats.date(key)
    local y, m, d = key:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
    if not y then return end
    return os.time{ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 0, min = 0, sec = 0 }
end

function Stats.month(timestamp, delta)
    local date = os.date("*t", timestamp or os.time())
    return os.time{ year = date.year, month = date.month + (delta or 0), day = 1, hour = 0, min = 0, sec = 0 }
end

function Stats.minutes(seconds)
    return math.floor((seconds or 0) / 60)
end

function Stats.duration(seconds)
    seconds = math.max(0, tonumber(seconds) or 0)
    if seconds > 0 and seconds < 60 then return "<1 min" end
    local minutes = math.floor(seconds / 60)
    if minutes < 60 then return tostring(minutes) .. " min" end
    return string.format("%d h %02d", math.floor(minutes / 60), minutes % 60)
end

function Stats.number(value)
    local text = tostring(math.floor((tonumber(value) or 0) + 0.5))
    while true do
        local changed, count = text:gsub("^(%-?%d+)(%d%d%d)", "%1 %2")
        text = changed
        if count == 0 then return text end
    end
end

function Stats:new(options)
    options = options or {}
    return setmetatable({
        path = options.path or DataStorage:getSettingsDir() .. "/statistics.sqlite3",
        now = options.now or os.time(), fixed_now = options.now ~= nil,
        days = {}, books = {}, loaded = false, months = {},
    }, self)
end

-- Keep all queries in one short read transaction, and always release the handle.
function Stats:query(callback)
    if lfs.attributes(self.path, "mode") ~= "file" then return nil, "missing" end
    local conn
    local ok, result = pcall(function()
        conn = SQ3.open(self.path, "ro")
        conn:set_busy_timeout(250)
        conn:exec("BEGIN;")
        local value = callback(conn)
        conn:exec("COMMIT;")
        return value
    end)
    if conn then pcall(conn.close, conn) end
    if not ok then
        logger.warn("Kindlevel: statistics read failed", result)
        return nil, "unavailable"
    end
    return result
end

local function rows(conn, sql, ...)
    local stmt = conn:prepare(sql)
    stmt:bind(...)
    local result = {}
    for row in stmt:rows() do result[#result + 1] = row end
    stmt:close()
    return result
end

function Stats:refresh()
    if not self.fixed_now then self.now = os.time() end
    self.loaded = false
    self.days, self.books = {}, {}
    self.months = {}
    return self:load()
end

function Stats:load()
    if self.loaded then return self end
    self.loaded = true
    local result, err = self:query(function(conn)
        local daily = rows(conn, [[
            SELECT day, count(*), sum(seconds) FROM (
                SELECT strftime('%Y-%m-%d', start_time, 'unixepoch', 'localtime') AS day,
                       id_book, page, sum(duration) AS seconds
                FROM page_stat WHERE duration > 0 GROUP BY day, id_book, page
            ) GROUP BY day ORDER BY day;
        ]])
        local options = G_reader_settings:readSetting("statistics") or {}
        local max_sec = math.max(1, tonumber(options.max_sec) or 120)
        local books = rows(conn, [[
            WITH per_page AS (
                SELECT id_book, page, sum(duration) AS seconds FROM page_stat
                WHERE duration > 0 GROUP BY id_book, page
            ), totals AS (
                SELECT id_book, count(*) AS pages, sum(seconds) AS seconds,
                       sum(min(seconds, ?)) AS capped FROM per_page GROUP BY id_book
            ), dates AS (
                SELECT id_book, min(start_time) AS first, max(start_time) AS last,
                       count(DISTINCT strftime('%Y-%m-%d', start_time, 'unixepoch', 'localtime')) AS days
                FROM page_stat WHERE duration > 0 GROUP BY id_book
            )
            SELECT b.id, b.title, b.authors, b.pages, b.highlights, b.notes, b.md5,
                   coalesce(t.pages, 0), coalesce(t.seconds, 0), d.first, d.last, coalesce(d.days, 0), coalesce(t.capped, 0)
            FROM book b LEFT JOIN totals t ON t.id_book = b.id LEFT JOIN dates d ON d.id_book = b.id
            ORDER BY d.last DESC;
        ]], max_sec)
        return { daily = daily, books = books }
    end)
    self.error = err
    if not result then return self end
    for _, row in ipairs(result.daily) do
        self.days[row[1]] = { date = row[1], pages = tonumber(row[2]) or 0, seconds = tonumber(row[3]) or 0 }
    end
    for _, row in ipairs(result.books) do
        self.books[#self.books + 1] = {
            id = tonumber(row[1]), title = row[2] or "Untitled", author = row[3] or "",
            total_pages = tonumber(row[4]) or 0, highlights = tonumber(row[5]) or 0,
            notes = tonumber(row[6]) or 0, checksum = row[7], pages = tonumber(row[8]) or 0,
            seconds = tonumber(row[9]) or 0, first = tonumber(row[10]), last = tonumber(row[11]),
            active_days = tonumber(row[12]) or 0,
            average_seconds = (tonumber(row[13]) or 0) / math.max(1, tonumber(row[8]) or 0),
        }
    end
    return self
end

function Stats:series(period, year, book_id)
    self:load()
    local today = Stats.day(self.now)
    local finish = Stats.day(today, 1)
    local begin
    if period == "year" then
        year = year or tonumber(os.date("%Y", self.now))
        begin = os.time{ year = year, month = 1, day = 1, hour = 0, min = 0, sec = 0 }
        finish = os.time{ year = year + 1, month = 1, day = 1, hour = 0, min = 0, sec = 0 }
    elseif period == "all" then
        begin = today
        for key in pairs(self.days) do begin = math.min(begin, Stats.date(key)) end
    else begin = Stats.day(today, -(tonumber(period) or 30) + 1) end
    local source = self.days
    if book_id then
        source = {}
        local result = self:query(function(conn)
            return rows(conn, [[
                SELECT day, count(*), sum(seconds) FROM (
                    SELECT strftime('%Y-%m-%d', start_time, 'unixepoch', 'localtime') AS day,
                           page, sum(duration) AS seconds FROM page_stat
                    WHERE id_book = ? AND start_time >= ? AND start_time < ? AND duration > 0
                    GROUP BY day, page
                ) GROUP BY day ORDER BY day;
            ]], book_id, begin, finish)
        end)
        for _, row in ipairs(result or {}) do
            source[row[1]] = { pages = tonumber(row[2]) or 0, seconds = tonumber(row[3]) or 0 }
        end
    end
    local series, totals = {}, { pages = 0, seconds = 0, active_days = 0, record = 0 }
    local timestamp = begin
    while timestamp < finish do
        local key = os.date("%Y-%m-%d", timestamp)
        local day = source[key] or {}
        local item = { date = key, timestamp = timestamp, pages = day.pages or 0, seconds = day.seconds or 0,
            future = timestamp > today }
        series[#series + 1] = item
        if not item.future then
            totals.pages = totals.pages + item.pages
            totals.seconds = totals.seconds + item.seconds
            if item.seconds > 0 then totals.active_days = totals.active_days + 1 end
            totals.record = math.max(totals.record, item.pages)
        end
        timestamp = Stats.day(timestamp, 1) -- Calendar arithmetic also handles DST days.
    end
    local elapsed_days = 0
    for _, item in ipairs(series) do if not item.future then elapsed_days = elapsed_days + 1 end end
    totals.average = totals.pages / math.max(1, elapsed_days)
    totals.elapsed_days = elapsed_days
    return series, totals
end

function Stats:streak()
    self:load()
    local today = Stats.day(self.now)
    local key = os.date("%Y-%m-%d", today)
    if not self.days[key] then today = Stats.day(today, -1) end
    local streak = 0
    while true do
        local day = self.days[os.date("%Y-%m-%d", today)]
        if not day or day.seconds <= 0 then return streak end
        streak = streak + 1
        today = Stats.day(today, -1)
    end
end

function Stats:book(id)
    self:load()
    for _, book in ipairs(self.books) do if book.id == id then return book end end
end

function Stats:findBook(book)
    self:load()
    local checksum
    if book.file and DocSettings:hasSidecarFile(book.file) then
        checksum = DocSettings:open(book.file):readSetting("partial_md5_checksum")
    end
    local candidates = {}
    for _, item in ipairs(self.books) do
        if checksum and item.checksum == checksum and item.title == book.title then return item end
        if item.title == book.title and (item.author == book.author or item.author == "N/A") then
            candidates[#candidates + 1] = item
        end
    end
    if #candidates == 1 then return candidates[1] end
end

function Stats:dayDetails(key)
    self:load()
    local begin = Stats.date(key)
    if not begin then return { sessions = {}, books = {} } end
    local finish = Stats.day(begin, 1)
    local result, err = self:query(function(conn)
        -- page_stat_data is the original event table; older databases used page_stat.
        local raw = conn:rowexec("SELECT name FROM sqlite_master WHERE type='table' AND name='page_stat_data';")
        return {
            activity = rows(conn, string.format([[
                SELECT p.start_time, p.duration, p.id_book, b.title FROM %s p
                JOIN book b ON b.id = p.id_book
                WHERE p.start_time >= ? AND p.start_time < ? AND p.duration > 0
                ORDER BY p.start_time, p.id_book;
            ]], raw and "page_stat_data" or "page_stat"), begin, finish),
            books = rows(conn, [[
                SELECT b.id, b.title, count(DISTINCT p.page), sum(p.duration)
                FROM page_stat p JOIN book b ON b.id = p.id_book
                WHERE p.start_time >= ? AND p.start_time < ? AND p.duration > 0
                GROUP BY b.id ORDER BY sum(p.duration) DESC;
            ]], begin, finish),
        }
    end)
    local details = { sessions = {}, books = {}, error = err, date = key }
    local options = G_reader_settings:readSetting("statistics") or {}
    local gap = math.max(30, tonumber(options.min_sec) or 5)
    for _, row in ipairs(result and result.activity or {}) do
        local start, duration, id = tonumber(row[1]), tonumber(row[2]), tonumber(row[3])
        local last = details.sessions[#details.sessions]
        if last and last.book_id == id and start <= last.finish + gap then
            last.finish = math.max(last.finish, start + duration)
            last.seconds = last.seconds + duration
        else details.sessions[#details.sessions + 1] = {
            start = start, finish = start + duration, seconds = duration, book_id = id, title = row[4],
        } end
    end
    for _, row in ipairs(result and result.books or {}) do
        details.books[#details.books + 1] = { id = tonumber(row[1]), title = row[2], pages = tonumber(row[3]), seconds = tonumber(row[4]) }
    end
    return details
end

function Stats:monthData(timestamp)
    self:load()
    local begin = Stats.month(timestamp)
    local finish = Stats.month(begin, 1)
    local key = os.date("%Y-%m", begin)
    if self.months[key] then return self.months[key] end
    local result, err = self:query(function(conn)
        local raw = conn:rowexec("SELECT name FROM sqlite_master WHERE type='table' AND name='page_stat_data';")
        return {
            books = rows(conn, [[
                SELECT strftime('%Y-%m-%d', p.start_time, 'unixepoch', 'localtime'),
                       b.id, b.title, count(DISTINCT p.page), sum(p.duration)
                FROM page_stat p JOIN book b ON b.id=p.id_book
                WHERE p.start_time >= ? AND p.start_time < ? AND p.duration > 0
                GROUP BY 1,b.id ORDER BY 1,b.title;
            ]], begin, finish),
            activity = rows(conn, string.format([[
                SELECT start_time,duration FROM %s
                WHERE start_time >= ? AND start_time < ? AND duration > 0 ORDER BY start_time;
            ]], raw and "page_stat_data" or "page_stat"), begin, finish),
        }
    end)
    local data = { days = {}, begin = begin, finish = finish, error = err }
    local current = begin
    while current < finish do
        local date = os.date("%Y-%m-%d", current)
        data.days[date] = { date = date, timestamp = current, books = {}, hours = {} }
        current = Stats.day(current, 1)
    end
    for _, row in ipairs(result and result.books or {}) do
        local day = data.days[row[1]]
        if day then day.books[#day.books + 1] = {
            id = tonumber(row[2]), title = row[3], pages = tonumber(row[4]), seconds = tonumber(row[5]),
        } end
    end
    for _, row in ipairs(result and result.activity or {}) do
        local start, seconds = tonumber(row[1]), tonumber(row[2])
        while seconds > 0 and start < finish do
            local date = os.date("*t", start)
            local length = math.min(seconds, 3600 - date.min * 60 - date.sec)
            local day = data.days[os.date("%Y-%m-%d", start)]
            if day then day.hours[date.hour + 1] = (day.hours[date.hour + 1] or 0) + length end
            start, seconds = start + length, seconds - length
        end
    end
    self.months[key] = data
    return data
end

return Stats
