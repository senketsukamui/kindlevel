-- Run with the official KOReader LuaJIT runtime from its working directory.
require("setupkoenv")
G_defaults = require("luadefaults"):open()
G_reader_settings = require("luasettings"):open("/tmp/kindlevel-cover-settings.lua")
local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
require("document/canvascontext"):init(Device)
local Font = require("ui/font")
local TextBoxWidget = require("ui/widget/textboxwidget")
local output = arg[1] or "/workspace/kindlevel.koplugin/books"
local factor = Device.screen:scaleBySize(1000) / 1000
local background = 247
local function text(bb, value, x, y, w, h, size, serif, gray)
    local widget = TextBoxWidget:new{
        text = value, width = w, height = h, alignment = "left", alignment_strict = true,
        face = Font:getFace(serif and "NotoSerif-Regular.ttf" or "cfont", size / factor),
        fgcolor = Blitbuffer.Color8(gray or 0), line_height = 0.15,
        bgcolor = Blitbuffer.Color8(background),
    }
    widget:paintTo(bb, x, y)
    widget:free()
end
for index, title in ipairs{ "A Quiet Beginning", "Notes on Reading", "The Long Way Home" } do
    local bb = Blitbuffer.new(600, 900, Blitbuffer.TYPE_BB8)
    background = index == 2 and 230 or 247
    bb:fill(Blitbuffer.Color8(background))
    bb:paintRect(28, 0, 2, 900, Blitbuffer.Color8(205))
    text(bb, "KINDLEVEL\nA SMALL EDITION", 62, 48, 440, 75, 17, false, 65)
    text(bb, title, 60, 150, 450, 240, 59, true)
    if index == 1 then
        bb:paintCircle(365, 660, 132, Blitbuffer.Color8(185))
        bb:paintCircle(315, 612, 100, Blitbuffer.Color8(247))
        bb:paintRect(92, 592, 2, 182, Blitbuffer.Color8(85))
        bb:paintRect(92, 773, 155, 2, Blitbuffer.Color8(85))
    elseif index == 2 then
        for i = 0, 6 do bb:paintRect(62, 465 + i * 45, 420 - (i % 3) * 57, 2, Blitbuffer.Color8(105)) end
        bb:paintRect(62, 465, 5, 272, Blitbuffer.Color8(25))
    else
        for i = 0, 4 do
            bb:paintCircle(300, 600, 145 - i * 25, Blitbuffer.Color8(70 + i * 28), 2)
        end
        bb:paintRect(297, 525, 6, 270, Blitbuffer.Color8(247))
        bb:paintRect(62, 744, 474, 2, Blitbuffer.Color8(110))
    end
    text(bb, "Original sample · 2026", 62, 823, 450, 40, 17, false, 85)
    bb:writePNG(output .. "/" .. title .. ".cover.png")
    bb:free()
    print("Rendered cover: " .. title)
end
