-- Shared helpers: screen geometry (Geom), the colour codec, L() for translations, and Util.NextFrame,
-- the addon's only timer.Simple (§10.2). Everything here except NextFrame and L is pure.

PinnedPanels = PinnedPanels or {}
local PP = PinnedPanels
PP.Util = PP.Util or {}
PP.Geom = PP.Geom or {}
local Util, Geom = PP.Util, PP.Geom

-- ── Geometry ────────────────────────────────────────────────
-- Rects are tables with x, y, w, h (window records qualify); the area is passed as ux, uy, uw, uh.

-- The screen area windows may use: the screen minus the taskbar, unless it auto-hides (L12).
function Geom.Usable()
	local x, y, w, h = 0, 0, ScrW(), ScrH()
	local Settings = PP.Settings
	if Settings.Get("taskbar") and not Settings.Get("taskbarAutoHide") then
		local size, side = Settings.Get("taskbarSize"), Settings.Get("taskbarSide")
		if side == "top" then
			y, h = size, h - size
		elseif side == "left" then
			x, w = size, w - size
		elseif side == "right" then
			w = w - size
		else
			h = h - size
		end
	end
	return x, y, w, h
end

-- Shrinks a rect to fit the area, then moves it inside (E4).
function Geom.Fit(x, y, w, h, ux, uy, uw, uh)
	w, h = math.min(w, uw), math.min(h, uh)
	return math.Clamp(x, ux, ux + uw - w), math.Clamp(y, uy, uy + uh - h), w, h
end

function Geom.Overlap(a, b, pad)
	pad = pad or 0
	return a.x < b.x + b.w + pad and b.x < a.x + a.w + pad
		and a.y < b.y + b.h + pad and b.y < a.y + a.h + pad
end

-- Where a new w×h window can go without overlapping others (L23): the preferred spot if free,
-- else the first free spot scanning rows top-left first, else the preferred spot anyway.
local FREE_STEP, FREE_PAD = 28, 20

function Geom.FreeSpot(w, h, rects, px, py, ux, uy, uw, uh)
	local maxX, maxY = math.max(ux, ux + uw - w), math.max(uy, uy + uh - h)
	local probe = { x = math.Clamp(px, ux, maxX), y = math.Clamp(py, uy, maxY), w = w, h = h }
	local function free()
		for _, r in ipairs(rects) do
			if Geom.Overlap(probe, r, FREE_PAD) then return false end
		end
		return true
	end
	if free() then return probe.x, probe.y end
	local baseX, baseY = probe.x, probe.y
	for y = uy, maxY, FREE_STEP do
		for x = ux, maxX, FREE_STEP do
			probe.x, probe.y = x, y
			if free() then return x, y end
		end
	end
	return baseX, baseY
end

-- Snaps one axis of a rect: pos/size on axis "x" or "y", against the area's edges and centre and the
-- other rects' edges (flush and adjacent). A resized edge snaps with size 0. Returns pos unchanged
-- when nothing is within dist.
local SIZE = { x = "w", y = "h" }

function Geom.SnapAxis(pos, size, lo, span, rects, axis, dist)
	local best, bestD = pos, dist + 1
	local function try(line)
		local d = math.abs(pos - line)
		if d < bestD then best, bestD = line, d end
	end
	try(lo)
	try(lo + span - size)
	try(lo + math.floor((span - size) / 2))
	local sizeKey = SIZE[axis]
	for _, r in ipairs(rects) do
		local a, s = r[axis], r[sizeKey]
		try(a)
		try(a + s - size)
		try(a + s)
		try(a - size)
	end
	return bestD <= dist and best or pos
end

function Geom.SnapMove(x, y, w, h, rects, dist, ux, uy, uw, uh)
	return Geom.SnapAxis(x, w, ux, uw, rects, "x", dist), Geom.SnapAxis(y, h, uy, uh, rects, "y", dist)
end

-- ── Colours ─────────────────────────────────────────────────
-- Files store colours as [r, g, b, a] because JSON drops Color's metatable (G35); convars store "r g b a".

function Util.Finite(v)
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function channel(v, default)
	v = tonumber(v)
	if not Util.Finite(v) then return default end
	return math.Clamp(math.Round(v), 0, 255)
end

function Util.ArrayToColor(t)
	if not istable(t) then return nil end
	local r, g, b = channel(t[1]), channel(t[2]), channel(t[3])
	if not (r and g and b) then return nil end
	return Color(r, g, b, channel(t[4], 255))
end

function Util.ColorToArray(c)
	return { c.r, c.g, c.b, c.a }
end

function Util.StringToColor(s)
	if not isstring(s) then return nil end
	local parts = {}
	for n in s:gmatch("%S+") do parts[#parts + 1] = n end
	if #parts < 3 or #parts > 4 then return nil end
	return Util.ArrayToColor(parts)
end

function Util.ColorToString(c)
	return string.format("%d %d %d %d", c.r, c.g, c.b, c.a)
end

-- ── Text ────────────────────────────────────────────────────

-- Translated text for pinnedpanels.<key> (§23); a bad format string returns the text unformatted (L18).
function PP.L(key, ...)
	local text = language.GetPhrase("pinnedpanels." .. key):gsub("\\n", "\n")
	if select("#", ...) == 0 then return text end
	local ok, out = pcall(string.format, text, ...)
	return ok and out or text
end

-- ── Timing ──────────────────────────────────────────────────

-- Runs fn next frame, unless panel was given and is gone by then.
function Util.NextFrame(panel, fn)
	timer.Simple(0, function()
		if not panel or IsValid(panel) then fn() end
	end)
end
