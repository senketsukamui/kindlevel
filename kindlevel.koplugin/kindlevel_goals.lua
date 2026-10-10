-- Completion dates live in KOReader sidecars, not in its statistics database.
-- Keep observed completions and user-entered dates in Kindlevel's own settings.
local DocSettings = require("docsettings")
local Stats = require("kindlevel_stats")
local Goals = {}
Goals.__index = Goals

function Goals.key(book)
    if not book.checksum or book.checksum == "" then
        return book.id and "id:" .. tostring(book.id) or "file:" .. tostring(book.file)
    end
    local author = book.author
    if author == "N/A" or book.format and author == book.format .. " document" then author = nil end
    local parts = { book.checksum, book.title or "", author or "" }
    local key = "book:"
    for _, part in ipairs(parts) do key = key .. tostring(#part) .. ":" .. part end
    return key
end

function Goals:new(options)
    return setmetatable({ settings = options.settings, stats = options.stats }, self)
end

function Goals:validDate(date)
    if type(date) ~= "string" then return false end
    local timestamp = Stats.date(date)
    return timestamp and os.date("%Y-%m-%d", timestamp) == date and timestamp <= Stats.day(self.stats.now)
end

function Goals:record(book, date, source)
    if not book or not self:validDate(date) then return false end
    local records = self.settings:readSetting("finished_books", {})
    local key = Goals.key(book)
    local record = records[key] or { title = book.title, author = book.author, dates = {} }
    record.dates = record.dates or {}
    local year = date:sub(1, 4)
    -- An import must not replace a date explicitly recorded by the user.
    if source == "koreader" and (record.dates[year] or record.excluded and record.excluded[year]) then return false end
    if record.dates[year] == date then return false end
    record.dates[year] = date
    if record.excluded then record.excluded[year] = nil end
    records[key] = record
    self.settings:saveSetting("finished_books", records)
    return true
end

function Goals:import(files)
    local changed, seen = false, {}
    for _, file in ipairs(files or {}) do
        if not seen[file] and DocSettings:hasSidecarFile(file) then
            local config = DocSettings:open(file)
            local summary = config:readSetting("summary") or {}
            local props = config:readSetting("doc_props") or config:readSetting("stats") or {}
            if summary.status == "complete" and self:validDate(summary.modified) then
                local book = self.stats:findBook{ file = file, title = props.title or props.display_title,
                    author = type(props.authors) == "table" and table.concat(props.authors, ", ") or props.authors }
                book = book or { file = file, title = props.title or props.display_title or file:match("([^/]+)$"),
                    author = type(props.authors) == "table" and table.concat(props.authors, ", ") or props.authors,
                    checksum = config:readSetting("partial_md5_checksum") }
                if book and self:record(book, summary.modified, "koreader") then changed = true end
            end
        end
        seen[file] = true
    end
    if changed then self.settings:flush() end
    return changed
end

function Goals:target(year)
    local targets = self.settings:readSetting("yearly_book_goals") or {}
    return targets[tostring(year)] == nil and 24 or targets[tostring(year)]
end

function Goals:setTarget(year, target)
    if type(target) ~= "number" or target < 0 or target > 10000 or target ~= math.floor(target) then return false end
    local targets = self.settings:readSetting("yearly_book_goals", {})
    targets[tostring(year)] = target
    self.settings:saveSetting("yearly_book_goals", targets)
    self.settings:flush()
    return true
end

function Goals:list(year)
    local list = {}
    for key, record in pairs(self.settings:readSetting("finished_books") or {}) do
        local date = record.dates and record.dates[tostring(year)]
        if date and self:validDate(date) then
            local book_id
            for _, book in ipairs(self.stats:load().books) do
                if Goals.key(book) == key then book_id = book.id; break end
            end
            list[#list + 1] = { title = record.title, author = record.author, date = date, key = key, book_id = book_id }
        end
    end
    table.sort(list, function(a, b) return a.date == b.date and a.title < b.title or a.date > b.date end)
    return list
end

function Goals:remove(key, year)
    local records = self.settings:readSetting("finished_books", {})
    if not records[key] or not records[key].dates[tostring(year)] then return false end
    records[key].dates[tostring(year)] = nil
    records[key].excluded = records[key].excluded or {}
    records[key].excluded[tostring(year)] = true
    self.settings:saveSetting("finished_books", records)
    self.settings:flush()
    return true
end

return Goals
