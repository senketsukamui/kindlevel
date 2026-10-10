local DocSettings = require("docsettings")
local DocumentRegistry = require("document/documentregistry")
local ReadHistory = require("readhistory")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")

local Library = {}
Library.__index = Library

local MAX_BOOKS = 1000
local MAX_ENTRIES = 20000
local MAX_DEPTH = 10

local function basename(path)
    return path:match("([^/]+)$") or path
end

local function skippedDirectory(name)
    return name:sub(1, 1) == "." or name:match("%.sdr$")
        or name == "node_modules" or name == "System Volume Information"
end

function Library:new(options)
    return setmetatable({ root = options.root, books = {}, warnings = {}, inspected = {} }, self)
end

function Library:scan()
    self.books, self.warnings, self.inspected = {}, {}, {}
    local visited = 0
    local limited = false
    local function walk(path, depth)
        if limited then return end
        if depth > MAX_DEPTH then
            self.warnings.depth = true
            return
        end
        local ok, err = pcall(function()
            for name in lfs.dir(path) do
                if name ~= "." and name ~= ".." and name:sub(1, 1) ~= "." then
                    visited = visited + 1
                    if visited > MAX_ENTRIES or #self.books >= MAX_BOOKS then
                        limited = true
                        self.warnings.limit = true
                        break
                    end
                    local file = path .. "/" .. name
                    -- Do not follow symlinks: nested libraries can contain directory cycles.
                    local attr = lfs.symlinkattributes(file)
                    if attr and attr.mode == "directory" and not skippedDirectory(name) then
                        walk(file, depth + 1)
                    elseif attr and attr.mode == "file"
                        and not name:match("%.cover%.")
                        and not DocumentRegistry:isImageFile(file)
                        and DocumentRegistry:hasProvider(file) then
                        self.books[#self.books + 1] = {
                            file = file,
                            filename = name,
                            title = name:gsub("%.[^.]+$", ""):gsub("_", " "),
                            format = (name:match("%.([^.]+)$") or "BOOK"):upper(),
                            size = attr.size,
                        }
                    end
                end
            end
        end)
        if not ok then
            self.warnings.unreadable = true
            logger.warn("Kindlevel: cannot scan", path, err)
        end
    end
    local root = self.root:gsub("/+$", "")
    walk(root ~= "" and root or "/", 0)
    local recent = {}
    for _, item in ipairs(ReadHistory.hist or {}) do recent[item.file] = item.time or 0 end
    table.sort(self.books, function(a, b)
        local ar, br = recent[a.file] or 0, recent[b.file] or 0
        if ar ~= br then return ar > br end
        return a.filename:lower() < b.filename:lower()
    end)
    return self.books
end

function Library:inspect(book)
    if not book or self.inspected[book.file] then return book end
    self.inspected[book.file] = true
    local config
    if DocSettings:hasSidecarFile(book.file) then
        config = DocSettings:open(book.file)
        local props = config:readSetting("doc_props")
        if props then
            book.title = props.title or book.title
            book.author = props.authors
        end
        book.percent = tonumber(config:readSetting("percent_finished"))
        book.pages = tonumber(config:readSetting("doc_pages"))
        book.page = tonumber(config:readSetting("last_page"))
        book.started = true
    end
    -- Read metadata lazily for only the visible books, without paginating a whole EPUB.
    if not book.author then
        local doc
        local ok, err = pcall(function()
            doc = DocumentRegistry:openDocument(book.file)
            if not doc then return end
            if doc.loadDocument and not doc:loadDocument(false) then return end
            local props = doc:getProps()
            if props then
                book.title = props.title and props.title ~= "" and props.title or book.title
                book.author = props.authors
            end
        end)
        if doc then pcall(doc.close, doc) end
        if not ok then logger.warn("Kindlevel: metadata unavailable", book.file, err) end
    end
    if type(book.author) == "table" then book.author = table.concat(book.author, ", ") end
    if not book.author or book.author == "" then book.author = book.format .. " document" end
    if book.percent then book.percent = math.max(0, math.min(1, book.percent)) end
    return book
end

function Library:cover(book)
    if not book then return end
    for _, ext in ipairs{ "png", "jpg", "svg" } do
        local custom = book.file:gsub("%.[^.]+$", "") .. ".cover." .. ext
        if lfs.attributes(custom, "mode") == "file" then return { file = custom } end
    end
    local custom = DocSettings:findCustomCoverFile(book.file)
    if custom then return { file = custom } end
    local doc, image
    local ok, err = pcall(function()
        doc = DocumentRegistry:openDocument(book.file)
        if not doc then return end
        if doc.loadDocument and not doc:loadDocument(false) then return end
        image = doc:getCoverPageImage()
    end)
    if doc then pcall(doc.close, doc) end
    if not ok then logger.warn("Kindlevel: cover unavailable", book.file, err) end
    if image then return { image = image } end
end

function Library:find(file)
    for index, book in ipairs(self.books) do
        if book.file == file then return index end
    end
    return 1
end

function Library:folderLabel()
    return basename(self.root)
end

return Library
