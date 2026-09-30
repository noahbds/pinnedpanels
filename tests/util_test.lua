local Geom, Util = PinnedPanels.Geom, PinnedPanels.Util

local function rect(x, y, w, h) return { x = x, y = y, w = w, h = h } end

return {
	["Fit shrinks an oversized rect and clamps it inside (E4)"] = function(t)
		local x, y, w, h = Geom.Fit(1800, -50, 3000, 400, 0, 0, 1920, 1080)
		t.eq(w, 1920)
		t.eq(h, 400)
		t.eq(x, 0)
		t.eq(y, 0)
		x, y = Geom.Fit(1800, 900, 300, 300, 0, 0, 1920, 1080)
		t.eq(x, 1620)
		t.eq(y, 780)
	end,

	["FreeSpot keeps the preferred spot when free"] = function(t)
		local x, y = Geom.FreeSpot(200, 200, {}, 120, 120, 0, 0, 1920, 1080)
		t.eq(x, 120)
		t.eq(y, 120)
	end,

	["FreeSpot avoids existing windows (L23)"] = function(t)
		local taken = { rect(120, 120, 280, 400) }
		local x, y = Geom.FreeSpot(280, 400, taken, 120, 120, 0, 0, 1920, 1080)
		t.ok(not Geom.Overlap(rect(x, y, 280, 400), taken[1], 20), "overlaps " .. x .. "," .. y)
	end,

	["FreeSpot falls back to the preferred spot when the screen is full"] = function(t)
		local x, y = Geom.FreeSpot(200, 200, { rect(0, 0, 1920, 1080) }, 120, 120, 0, 0, 1920, 1080)
		t.eq(x, 120)
		t.eq(y, 120)
	end,

	["SnapAxis snaps to area edges and centre"] = function(t)
		t.eq(Geom.SnapAxis(8, 200, 0, 1920, {}, "x", 12), 0)
		t.eq(Geom.SnapAxis(1715, 200, 0, 1920, {}, "x", 12), 1720)
		t.eq(Geom.SnapAxis(855, 200, 0, 1920, {}, "x", 12), 860)
		t.eq(Geom.SnapAxis(500, 200, 0, 1920, {}, "x", 12), 500)
	end,

	["SnapAxis snaps flush and adjacent to other rects"] = function(t)
		local others = { rect(400, 100, 300, 300) }
		t.eq(Geom.SnapAxis(705, 200, 0, 1920, others, "x", 12), 700, "right of")
		t.eq(Geom.SnapAxis(195, 200, 0, 1920, others, "x", 12), 200, "left of")
		t.eq(Geom.SnapAxis(395, 200, 0, 1920, others, "x", 12), 400, "left edges")
		t.eq(Geom.SnapAxis(95, 50, 0, 1080, others, "y", 12), 100, "top edges on y")
	end,

	["SnapAxis with distance 0 only snaps exact hits"] = function(t)
		t.eq(Geom.SnapAxis(1, 200, 0, 1920, {}, "x", 0), 1)
		t.eq(Geom.SnapAxis(0, 200, 0, 1920, {}, "x", 0), 0)
	end,

	["ArrayToColor clamps, rounds and defaults alpha"] = function(t)
		local c = Util.ArrayToColor({ 300, -5, 12.6 })
		t.eq(c.r, 255)
		t.eq(c.g, 0)
		t.eq(c.b, 13)
		t.eq(c.a, 255)
		t.ok(IsColor(c))
	end,

	["ArrayToColor rejects junk"] = function(t)
		t.eq(Util.ArrayToColor("red"), nil)
		t.eq(Util.ArrayToColor({ 1, 2 }), nil)
		t.eq(Util.ArrayToColor({ 0 / 0, 1, 2 }), nil)
		t.eq(Util.ArrayToColor({ math.huge, 1, 2 }), nil)
		t.eq(Util.ArrayToColor({ "x", 1, 2 }), nil)
	end,

	["colour string round-trip"] = function(t)
		local c = Util.StringToColor(Util.ColorToString(Color(1, 2, 3, 4)))
		t.eq(Util.ColorToString(c), "1 2 3 4")
		t.eq(Util.StringToColor("1 2"), nil)
		t.eq(Util.StringToColor("1 2 3 4 5"), nil)
		t.eq(Util.StringToColor(nil), nil)
		t.eq(Util.StringToColor("10 20 30").a, 255)
	end,

	["L formats and survives bad format strings (L18)"] = function(t)
		language.Add("pinnedpanels.count", "%d windows")
		language.Add("pinnedpanels.bad", "%d %d windows")
		language.Add("pinnedpanels.lines", "one\\ntwo")
		t.eq(PinnedPanels.L("count", 3), "3 windows")
		t.eq(PinnedPanels.L("bad", 3), "%d %d windows")
		t.eq(PinnedPanels.L("lines"), "one\ntwo")
		t.eq(PinnedPanels.L("missing"), "pinnedpanels.missing")
	end,

	["NextFrame skips a removed panel"] = function(t)
		local alive = { valid = true, IsValid = function(self) return self.valid end }
		local ran = 0
		Util.NextFrame(alive, function() ran = ran + 1 end)
		Util.NextFrame(nil, function() ran = ran + 10 end)
		alive.valid = false
		Stub.Frame()
		t.eq(ran, 10)
	end,
}
