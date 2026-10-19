-- Pocket Ledger's shared UI fonts. Register only bundled faces; reader settings stay untouched.
local Font = require("ui/font")
local FontList = require("fontlist")
local lfs = require("libs/libkoreader-lfs")
local Theme = { ink = 34, muted = 85, line = 180, surface = 238 }
local registered = {}
function Theme.register(path)
    if registered[path] then return end
    local list = FontList:getFontList()
    for _, name in ipairs{ "IBMPlexSans-Regular.ttf", "IBMPlexSans-Medium.ttf", "IBMPlexSans-SemiBold.ttf", "IBMPlexMono-Regular.ttf" } do
        local file = path .. "/assets/fonts/" .. name
        if lfs.attributes(file, "mode") == "file" then
            local found = false
            for _, value in ipairs(list) do if value == file then found = true; break end end
            if not found then list[#list + 1] = file end
        end
    end
    registered[path] = true
end
function Theme.face(path, size, options)
    Theme.register(path)
    options = options or {}
    local name = options.mono and "IBMPlexMono-Regular.ttf"
        or (options.bold or options.serif) and "IBMPlexSans-SemiBold.ttf" or "IBMPlexSans-Regular.ttf"
    return Font:getFace(path .. "/assets/fonts/" .. name, size) or Font:getFace("cfont", size)
end
return Theme
