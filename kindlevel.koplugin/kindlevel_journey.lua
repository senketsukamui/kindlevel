-- Calendar-based journeys inferred from recorded activity, never from page totals.
local Stats = require("kindlevel_stats")
local Goals = require("kindlevel_goals")
local Journey = {}

-- A civil-day ordinal avoids 23/25-hour DST days affecting break lengths.
function Journey.ordinal(key)
    local y, m, d = key:match("^(%d+)%-(%d+)%-(%d+)$")
    y, m, d = tonumber(y), tonumber(m), tonumber(d)
    local previous = y - 1
    local result = previous * 365 + math.floor(previous / 4) - math.floor(previous / 100) + math.floor(previous / 400) + d
    local months = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }
    if y % 4 == 0 and (y % 100 ~= 0 or y % 400 == 0) then months[2] = 29 end
    for month = 1, m - 1 do result = result + months[month] end
    return result
end

function Journey.threshold(value)
    return (value == 7 or value == 14) and value or 3
end

function Journey.summarize(days, now, threshold)
    threshold = Journey.threshold(threshold)
    local result = { days = {}, episodes = {}, returns = {}, active_days = 0, seconds = 0, longest_break = 0 }
    local today, previous = os.date("%Y-%m-%d", now)
    for _, day in ipairs(days) do
        if day.date <= today and day.seconds > 0 then
            local gap = previous and Journey.ordinal(day.date) - Journey.ordinal(previous.date) - 1 or 0
            if not previous or gap >= threshold then
                if previous then
                    result.returns[#result.returns + 1] = { date = day.date, previous = previous.date, gap = gap }
                end
                result.episodes[#result.episodes + 1] = { first = day.date, last = day.date, active_days = 0, seconds = 0 }
            end
            local episode = result.episodes[#result.episodes]
            episode.last, episode.active_days, episode.seconds = day.date, episode.active_days + 1, episode.seconds + day.seconds
            result.days[#result.days + 1] = day
            result.active_days, result.seconds = result.active_days + 1, result.seconds + day.seconds
            result.longest_break = math.max(result.longest_break, gap)
            previous = day
        end
    end
    if previous then
        result.first, result.last = result.days[1].date, previous.date
        result.elapsed_days = Journey.ordinal(result.last) - Journey.ordinal(result.first) + 1
        result.idle_days = math.max(0, Journey.ordinal(today) - Journey.ordinal(result.last))
        result.inactive_days = math.max(0, result.idle_days - 1) -- Today is still in progress.
        result.on_break = result.inactive_days >= threshold
    end
    return result
end

function Journey.median(returns)
    if #returns == 0 then return nil end
    local gaps = {}
    for _, item in ipairs(returns) do gaps[#gaps + 1] = item.gap end
    table.sort(gaps)
    return (gaps[math.floor((#gaps + 1) / 2)] + gaps[math.ceil((#gaps + 1) / 2)]) / 2
end

function Journey:new(stats)
    return setmetatable({ stats = stats }, { __index = self })
end

function Journey:load()
    -- Refresh creates a new snapshot and invalidates this shared aggregate cache.
    if self.stats.journey_days then return self.stats.journey_days end
    local result, err = self.stats:query(function(conn)
        local raw = conn:rowexec("SELECT name FROM sqlite_master WHERE type='table' AND name='page_stat_data';")
        local stmt = conn:prepare(string.format([[
            SELECT id_book, strftime('%%Y-%%m-%%d', start_time, 'unixepoch', 'localtime'),
                   sum(duration), %s
            FROM %s WHERE duration > 0 AND start_time <= ?
            GROUP BY id_book, 2 ORDER BY 2, id_book;
        ]], raw and "max(CASE WHEN total_pages > 0 AND page > 0 AND page <= total_pages THEN 1.0 * page / total_pages END)" or "NULL",
            raw and "page_stat_data" or "page_stat"))
        stmt:bind(self.stats.now)
        local books, all = {}, {}
        for row in stmt:rows() do
            local id, date, seconds = tonumber(row[1]), row[2], tonumber(row[3]) or 0
            books[id] = books[id] or {}
            books[id][#books[id] + 1] = { date = date, seconds = seconds, position = tonumber(row[4]) }
            all[date] = (all[date] or 0) + seconds
        end
        stmt:close()
        local days = {}
        for date, seconds in pairs(all) do days[#days + 1] = { date = date, seconds = seconds } end
        table.sort(days, function(a, b) return a.date < b.date end)
        return { books = books, days = days }
    end)
    if result then self.stats.journey_days = result end
    return result or { books = {}, days = {} }, err
end

function Journey:book(id, threshold, goals)
    local data, err = self:load()
    local result = Journey.summarize(data.books[id] or {}, self.stats.now, threshold)
    result.error, result.finishes = err, {}
    local book = self.stats:book(id)
    if goals and book then
        local record = (goals.settings:readSetting("finished_books") or {})[Goals.key(book)]
        for _, date in pairs(record and record.dates or {}) do
            if goals:validDate(date) then result.finishes[#result.finishes + 1] = date end
        end
        table.sort(result.finishes)
    end
    return result
end

function Journey:recovery(threshold, mode)
    self.stats:load()
    local data, err = self:load()
    local result = Journey.summarize(data.days, self.stats.now, threshold)
    result.error = err
    if mode == "books" then
        result.returns = {}
        for _, book in ipairs(self.stats.books) do
            local summary = Journey.summarize(data.books[book.id] or {}, self.stats.now, threshold)
            for _, item in ipairs(summary.returns) do
                item.book_id, item.title = book.id, book.title
                result.returns[#result.returns + 1] = item
            end
        end
    end
    table.sort(result.returns, function(a, b)
        if a.date == b.date then return (a.book_id or 0) < (b.book_id or 0) end
        return a.date > b.date
    end)
    result.typical_break, result.recent_returns = Journey.median(result.returns), 0
    local start = os.date("%Y-%m-%d", Stats.day(self.stats.now, -29))
    for _, item in ipairs(result.returns) do
        if item.date >= start then result.recent_returns = result.recent_returns + 1 end
    end
    return result
end

return Journey
