--[[
Relic: "console" look (Mike picked the light version of the sci-fi mockup, 2026-10-07).

Chamfered panels, segmented bars, corner brackets and slanted tabs, all painted straight
into the screen buffer row by row (Blitbuffer has no polygons). Sizes are in PW2 pixels
(758 x 1024) and scale with the screen width.

Fonts: DejaVu Sans Condensed (bundled in fonts/, Bitstream Vera licence, see fonts/LICENSE)
and KOReader's own Droid Sans Mono. Any font that fails to load falls back to KOReader's UI font.
]]
local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local TextWidget = require("ui/widget/textwidget")
local Screen = Device.screen

local C = {}

-- Light palette (gray levels, 0 black .. 255 white; the PW2 shows 16 steps of 17)
C.BG, C.PANEL, C.LINE, C.DIM, C.MID, C.TXT, C.EMPTY = 255, 238, 34, 153, 85, 0, 204

local function col(v) return Blitbuffer.Color8(v) end

-- Capitals that also cover accented Latin letters (string.upper only does ASCII): à..þ -> À..Þ
function C.upper(str)
    return (str:upper():gsub("\195([\160-\190])", function(c)
        if c == "\183" then return "\195" .. c end -- ÷ has no capital
        return "\195" .. string.char(c:byte() - 32)
    end))
end

-- PW2 pixels to this screen's pixels
function C.px(v) return math.floor(v * Screen:getWidth() / 758 + 0.5) end

-- Fonts -----------------------------------------------------------------------------------
local plugin_dir = (debug.getinfo(1, "S").source:match("^@(.*/)") or "./")
local FONT_FILES = {
    cond = "DejaVuSansCondensed.ttf",
    bold = "DejaVuSansCondensed-Bold.ttf",
    lcars = "Antonio-Bold.ttf",       -- LCARS theme (SIL OFL, fonts/OFL-Antonio.txt)
    lcarsr = "Antonio-Regular.ttf",
}
-- Font:getFace looks in KOReader's fonts/ folder first; reach the plugin's folder from there.
local function fontPath(file)
    local dir = plugin_dir:gsub("/$", "")
    local rel = dir:match("(plugins/[^/]+)$")
    if rel then return "../" .. rel .. "/fonts/" .. file end
    return dir .. "/fonts/" .. file
end

C.font_failed = {}

-- size in PW2 pixels (em height), like the mockup
function C.face(kind, size)
    local pt = math.max(6, math.floor(C.px(size) * 1000 / Screen:scaleBySize(1000) + 0.5))
    local f
    if kind == "mono" then f = Font:getFace("infont", pt) -- Droid Sans Mono
    elseif FONT_FILES[kind] and not C.font_failed[kind] then
        f = Font:getFace(fontPath(FONT_FILES[kind]), pt)
        if not f then C.font_failed[kind] = true end -- don't search for it again on every text
    end
    return f or Font:getFace(kind == "bold" and "tfont" or "cfont", pt)
end

-- A face by KOReader point size (like Font:getFace), from one of the plugin's fonts.
-- nil if the font file can't be loaded.
function C.pointFace(kind, pt)
    if not FONT_FILES[kind] or C.font_failed[kind] then return nil end
    local f = Font:getFace(fontPath(FONT_FILES[kind]), pt)
    if not f then C.font_failed[kind] = true end
    return f
end

function C.text(str, kind, size, gray, max_w)
    return TextWidget:new{ text = str, face = C.face(kind, size), fgcolor = col(gray or C.TXT),
        max_width = max_w, bold = false }
end

-- Shapes --------------------------------------------------------------------------------
-- inset(i, h) returns the left and right inset of row i; fill and outline are gray levels.
local function shape(bb, x, y, w, h, inset, fill, outline, t)
    t = t or 1
    local cf, co = fill and col(fill), outline and col(outline)
    for i = 0, h - 1 do
        local l, r = inset(i, h)
        local rw = w - l - r
        if rw > 0 then
            if cf then bb:paintRect(x + l, y + i, rw, 1, cf) end
            if co then
                if i < t or i >= h - t then bb:paintRect(x + l, y + i, rw, 1, co)
                else
                    -- side edges, widened where the slope moves so diagonals stay joined
                    local l2, r2 = inset(i - 1, h)
                    bb:paintRect(x + math.min(l, l2), y + i, math.abs(l - l2) + t, 1, co)
                    bb:paintRect(x + w - math.max(r, r2) - t, y + i, math.abs(r - r2) + t, 1, co)
                end
            end
        end
    end
end

-- corners = { tl, tr, br, bl } booleans; c = chamfer size in screen px
function C.chamfer(bb, x, y, w, h, c, corners, fill, outline, t)
    local tl, tr, br, bl = corners[1], corners[2], corners[3], corners[4]
    shape(bb, x, y, w, h, function(i, hh)
        local l, r = 0, 0
        if tl then l = math.max(l, c - i) end
        if bl then l = math.max(l, c - (hh - 1 - i)) end
        if tr then r = math.max(r, c - i) end
        if br then r = math.max(r, c - (hh - 1 - i)) end
        return l, r
    end, fill, outline, t)
end

-- slanted: top edge shifted right by s, bottom edge shifted left by s
function C.slant(bb, x, y, w, h, s, fill, outline)
    shape(bb, x, y, w, h, function(i, hh)
        local f = (hh > 1) and i / (hh - 1) or 0
        return math.floor(s * (1 - f) + 0.5), math.floor(s * f + 0.5)
    end, fill, outline, 1)
end

function C.brackets(bb, x, y, w, h, L, t, gray)
    local c = col(gray or C.LINE)
    for _, p in ipairs{ { x, y, 1, 1 }, { x + w - 1, y, -1, 1 }, { x, y + h - 1, 1, -1 }, { x + w - 1, y + h - 1, -1, -1 } } do
        local px, py, dx, dy = p[1], p[2], p[3], p[4]
        bb:paintRect(dx > 0 and px or px - L + 1, dy > 0 and py or py - t + 1, L, t, c)
        bb:paintRect(dx > 0 and px or px - t + 1, dy > 0 and py or py - L + 1, t, L, c)
    end
end

-- n slanted segments, the first `filled` dark
function C.segments(bb, x, y, w, h, n, filled, gap)
    local sw = (w - gap * (n - 1)) / n
    local s = math.max(1, math.floor(h * 0.3))
    for i = 0, n - 1 do
        local xx = math.floor(x + i * (sw + gap))
        C.slant(bb, xx, y, math.floor(sw), h, s, i < filled and C.LINE or C.EMPTY)
    end
end

-- Rounded rectangle; r = { tl, tr, br, bl } radii in screen px (0 = square corner).
function C.round(bb, x, y, w, h, r, fill)
    local tl, tr, br, bl = r[1] or 0, r[2] or 0, r[3] or 0, r[4] or 0
    local function cut(rad, d) -- inset of a corner of radius rad, d rows in from the edge
        if rad <= 0 or d >= rad then return 0 end
        local dy = rad - d - 0.5
        return math.floor(rad - math.sqrt(math.max(0, rad * rad - dy * dy)) + 0.5)
    end
    shape(bb, x, y, w, h, function(i, hh)
        local b = hh - 1 - i
        return math.max(cut(tl, i), cut(bl, b)), math.max(cut(tr, i), cut(br, b))
    end, fill, nil, 1)
end

function C.rect(bb, x, y, w, h, gray) bb:paintRect(x, y, w, h, col(gray)) end

-- Solid triangle centered on (cx, cy), s px tall and about 2s wide; up = apex on top.
-- (Drawn, not typed: Antonio has no arrow glyphs.)
function C.tri(bb, cx, cy, s, up, gray)
    local c = col(gray)
    local top = cy - math.floor(s / 2)
    for i = 0, s - 1 do
        local r = up and i or (s - 1 - i)
        bb:paintRect(cx - r, top + i, 2 * r + 1, 1, c)
    end
end

-- Rank insignia (Game.RANKS entry): an admiral's bar, then solid pips, then hollow pips.
-- d = pip diameter in screen px; ink and bg are gray levels. Returns the width drawn.
local function pip(bb, x, y, d, ink, bg, hollow)
    local r = math.floor(d / 2)
    C.round(bb, x, y, d, d, { r, r, r, r }, ink)
    if hollow then
        local t = math.max(2, math.floor(d / 6))
        local ir = r - t
        C.round(bb, x + t, y + t, d - 2 * t, d - 2 * t, { ir, ir, ir, ir }, bg)
    end
end

function C.insigniaWidth(rank, d)
    local gap = math.floor(d * 0.4)
    local n = (rank.pips or 0) + (rank.hollow or 0)
    local w = n * d + math.max(0, n - 1) * gap
    if rank.bar then w = w + math.floor(d * 1.8) + (n > 0 and gap or 0) end
    return w
end

function C.insignia(bb, x, y, rank, d, ink, bg)
    local gap = math.floor(d * 0.4)
    local cx = x
    if rank.bar then
        local bw, r = math.floor(d * 1.8), math.floor(d / 2)
        local t = math.max(2, math.floor(d / 6))
        C.round(bb, cx, y, bw, d, { r, r, r, r }, ink)
        C.round(bb, cx + t, y + t, bw - 2 * t, d - 2 * t, { r - t, r - t, r - t, r - t }, bg)
        C.rect(bb, cx + math.floor(bw / 4), y + math.floor(d / 2) - math.floor(t / 2), bw - 2 * math.floor(bw / 4), t, ink)
        cx = cx + bw + gap
    end
    for _ = 1, rank.pips or 0 do pip(bb, cx, y, d, ink, bg, false); cx = cx + d + gap end
    for _ = 1, rank.hollow or 0 do pip(bb, cx, y, d, ink, bg, true); cx = cx + d + gap end
    return C.insigniaWidth(rank, d)
end

-- draws a TextWidget at (x, y) vertically centred in a box of height h
function C.put(bb, tw, x, y, h)
    local sz = tw:getSize()
    tw:paintTo(bb, x, y + math.floor((h - sz.h) / 2))
    local w = sz.w
    tw:free()
    return w
end

-- Canvas: a fixed-size widget that paints with draw(self, bb, x, y) and takes taps / holds.
C.Canvas = InputContainer:extend{
    w = 0, h = 0,
    draw = nil,          -- function(self, bb, x, y)
    on_tap = nil, on_hold = nil,
}

function C.Canvas:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = self.w, h = self.h }
    self.ges_events = {}
    if self.on_tap then
        self.ges_events.Tap = { GestureRange:new{ ges = "tap", range = function() return self.dimen end } }
    end
    if self.on_hold then
        self.ges_events.Hold = { GestureRange:new{ ges = "hold", range = function() return self.dimen end } }
    end
end

function C.Canvas:getSize() return Geom:new{ w = self.w, h = self.h } end

function C.Canvas:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    if self.draw then self:draw(bb, x, y) end
end

function C.Canvas:onTap(_, ges) if self.on_tap then self.on_tap(ges, self) end return true end
function C.Canvas:onHold() if self.on_hold then self.on_hold() end return true end

return C
