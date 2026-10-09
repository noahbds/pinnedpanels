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

-- Where a new w×h window goes (L23): the preferred spot if nothing is there, else the spot that covers
-- the least of the other windows, scanning rows top-left first. A minimized window's place counts
-- too, for less: it is where that window comes back. Landing on another window's corner costs as much
-- as covering it whole, so when there is no room left windows still step off each other and every
-- title bar can be reached. (Records qualify as rects, which is how a minimized one is told.)
local FREE_STEP, FREE_PAD = 28, 20
local AWAY_WEIGHT, SAME_CORNER, CROWDED = 0.3, 24, 30

function Geom.FreeSpot(w, h, rects, px, py, ux, uy, uw, uh)
	local maxX, maxY = math.max(ux, ux + uw - w), math.max(uy, uy + uh - h)
	-- The rects once, padded, as plain numbers: the scan below asks about a few thousand spots, and
	-- with sixty windows open that is a few hundred thousand comparisons.
	local n, x1, y1, x2, y2, weight, cx, cy = #rects, {}, {}, {}, {}, {}, {}, {}
	for i, r in ipairs(rects) do
		x1[i], y1[i], x2[i], y2[i] = r.x - FREE_PAD, r.y - FREE_PAD, r.x + r.w + FREE_PAD, r.y + r.h + FREE_PAD
		weight[i], cx[i], cy[i] = r.state == "minimized" and AWAY_WEIGHT or 1, r.x, r.y
	end
	local whole = w * h
	-- What a window at x, y would cover, given up as soon as it passes limit.
	local function cost(x, y, limit)
		local c, xr, yb = 0, x + w, y + h
		for i = 1, n do
			if x < x2[i] and xr > x1[i] and y < y2[i] and yb > y1[i] then
				local ox = (xr < x2[i] and xr or x2[i]) - (x > x1[i] and x or x1[i])
				local oy = (yb < y2[i] and yb or y2[i]) - (y > y1[i] and y or y1[i])
				c = c + ox * oy * weight[i]
				local dx, dy = x - cx[i], y - cy[i]
				if dx < SAME_CORNER and dx > -SAME_CORNER and dy < SAME_CORNER and dy > -SAME_CORNER then c = c + whole end
				if c >= limit then return c end
			end
		end
		return c
	end
	local bx, by = math.Clamp(px, ux, maxX), math.Clamp(py, uy, maxY)
	local best = cost(bx, by, math.huge)
	if best == 0 then return bx, by end
	-- A crowded desktop is searched in wider steps: no spot is free there, and which of two covered
	-- ones is taken matters less than not making the player wait for it.
	local step = n > CROWDED and FREE_STEP * 2 or FREE_STEP
	for y = uy, maxY, step do
		for x = ux, maxX, step do
			local c = cost(x, y, best)
			if c < best then
				best, bx, by = c, x, y
				if c == 0 then return x, y end
			end
		end
	end
	return bx, by
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

-- Palette matching (v1): a substring scores its position; letters in order score behind any substring.
-- Lower is better; nil means no match. needle must be lower case.
function Util.Fuzzy(hay, needle)
	hay = hay:lower()
	local at = hay:find(needle, 1, true)
	if at then return at end
	local from = 1
	for i = 1, #needle do
		local found = hay:find(needle:sub(i, i), from, true)
		if not found then return nil end
		from = found + 1
	end
	return 500 + #hay
end

-- ── Replacing a global ──────────────────────────────────────

-- The addon's only way to replace a field of a global table (R5): tbl[key] is replacement while fn runs
-- and the original comes back on every path. fn's errors are printed and contained (G38). Returns ok.
function Util.WithOverride(tbl, key, replacement, fn)
	local original = tbl[key]
	tbl[key] = replacement
	local ok, err = xpcall(fn, debug.traceback)
	tbl[key] = original
	if not ok then ErrorNoHalt("[Pinned Panels] " .. tostring(err) .. "\n") end
	return ok
end

-- The timed form, only for Record mode (R14): tbl[key] is replacement until the returned function is
-- called. That restores the original only if our replacement is still installed (another addon may have
-- wrapped it since, §33.17) and returns whether it did; the replacement must then pass calls through.
function Util.BeginOverride(tbl, key, replacement)
	local original = tbl[key]
	tbl[key] = replacement
	return function()
		if tbl[key] ~= replacement then return false end
		tbl[key] = original
		return true
	end
end

-- ── Text ────────────────────────────────────────────────────

-- Titles sort as they read: "Émetteur" with the E's, not after Z. The accented Latin letters of the
-- languages the addon is translated into, folded to their plain ones.
local FOLD = {}
for plain, accented in pairs({
	a = "àáâãäåÀÁÂÃÄÅ", c = "çÇ", e = "èéêëÈÉÊË", i = "ìíîïÌÍÎÏ", n = "ñÑ", o = "òóôõöøÒÓÔÕÖØ", u = "ùúûüÙÚÛÜ", y = "ýÿÝ",
}) do
	for char in accented:gmatch(utf8.charpattern) do FOLD[char] = plain end
end
-- One whole character at a time (utf8.charpattern), so a letter of several bytes is looked up as one.
function Util.SortKey(title)
	return (title:gsub(utf8.charpattern, FOLD)):lower()
end

-- ── Timing ──────────────────────────────────────────────────

-- Runs fn next frame, unless panel was given and is gone by then.
function Util.NextFrame(panel, fn)
	timer.Simple(0, function()
		if not panel or IsValid(panel) then fn() end
	end)
end
