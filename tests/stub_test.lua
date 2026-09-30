-- The stub's own guarantees that module tests rely on: bomb-proof Decompress (R1), GMod's JSON rules (G35), timers.

return {
	["Compress round-trips and shrinks runs"] = function(t)
		local s = "ab" .. string.rep("x", 1000) .. "\1cd"
		local packed = util.Compress(s)
		t.ok(#packed < 30, "packed to " .. #packed)
		t.eq(util.Decompress(packed, 2000), s)
	end,

	["Decompress stops at maxSize"] = function(t)
		local bomb = util.Compress(string.rep("x", 10 * 1024 * 1024))
		t.ok(#bomb < 20)
		t.eq(util.Decompress(bomb, 262144), nil)
	end,

	["Decompress rejects garbage"] = function(t)
		t.eq(util.Decompress("not compressed", 64), nil)
		t.eq(util.Decompress("RLE\1x12", 64), nil)
	end,

	["Base64 round-trips binary"] = function(t)
		local s = "PP2\0\1\255 hello"
		t.eq(util.Base64Decode(util.Base64Encode(s, true)), s)
		t.eq(util.Base64Encode("Man", true), "TWFu")
		t.eq(util.Base64Encode("Ma", true), "TWE=")
		t.eq(util.Base64Decode("not base64!"), nil)
	end,

	["JSON round-trips and turns numeric keys into numbers"] = function(t)
		local back = util.JSONToTable(util.TableToJSON({ a = { 1, 2, { b = "x\"y\n" } }, ["5"] = true }))
		t.eq(back.a[3].b, "x\"y\n")
		t.eq(back[5], true)
		t.eq(util.JSONToTable("{bad"), nil)
		t.eq(util.JSONToTable("[1] trailing"), nil)
	end,

	["JSON enforces the 15,000-key limit unless told not to"] = function(t)
		local parts = {}
		for i = 1, 15001 do parts[i] = "0" end
		local big = "[" .. table.concat(parts, ",") .. "]"
		t.eq(util.JSONToTable(big), nil)
		t.eq(#util.JSONToTable(big, true), 15001)
	end,

	["timers run in order when time advances"] = function(t)
		local log = {}
		timer.Create("b", 2, 1, function() log[#log + 1] = "b" end)
		timer.Simple(1, function() log[#log + 1] = "a" end)
		Stub.Advance(1.5)
		t.eq(table.concat(log), "a")
		Stub.Advance(1)
		t.eq(table.concat(log), "ab")
		t.eq(RealTime(), 2.5)
	end,
}
