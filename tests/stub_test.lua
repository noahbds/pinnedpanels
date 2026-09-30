-- The stub's own guarantees; the storage import tests (R1) rely on the Decompress cap.

return {
	["Decompress round-trips"] = function(t)
		t.eq(util.Decompress(util.Compress("hello"), 64), "hello")
	end,

	["Decompress honours maxSize"] = function(t)
		local s = util.Compress(string.rep("x", 100))
		t.eq(util.Decompress(s, 99), nil)
		t.eq(util.Decompress(s, 100), string.rep("x", 100))
	end,

	["Decompress rejects garbage"] = function(t)
		t.eq(util.Decompress("not compressed", 64), nil)
		t.eq(util.Decompress("10:short", 64), nil)
	end,

	["clock only moves when told"] = function(t)
		t.eq(RealTime(), 0)
		Stub.Advance(0.25)
		t.eq(RealTime(), 0.25)
	end,

	["Reset restores clock and screen"] = function(t)
		Stub.SetTime(5)
		Stub.SetScreen(1280, 720)
		Stub.Reset()
		t.eq(RealTime(), 0)
		t.eq(ScrW(), 1920)
		t.eq(ScrH(), 1080)
	end,

	["Color defaults alpha and is recognised"] = function(t)
		local c = Color(1, 2, 3)
		t.eq(c.a, 255)
		t.ok(IsColor(c))
		t.ok(not IsColor({ r = 1, g = 2, b = 3, a = 255 }))
	end,
}
