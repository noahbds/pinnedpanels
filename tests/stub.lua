-- Just enough of GMod's globals to run the pure modules under plain LuaJIT (§25).
-- Grows with the modules that need it; Stub.Reset() restores a known state before each test.

Stub = {}

local COLOR = {}
COLOR.__index = COLOR

function Color(r, g, b, a)
	return setmetatable({ r = r, g = g, b = b, a = a or 255 }, COLOR)
end

function IsColor(v)
	return getmetatable(v) == COLOR
end

-- Manual clock: UI time only moves when a test says so (G5).
local now = 0
function RealTime() return now end
function SysTime() return now end
function Stub.SetTime(t) now = t end
function Stub.Advance(dt) now = now + dt end

local screenW, screenH = 1920, 1080
function ScrW() return screenW end
function ScrH() return screenH end
function Stub.SetScreen(w, h) screenW, screenH = w, h end

-- Identity "compression" with a size prefix, so tests can build payloads that decompress past maxSize (G36).
util = {}

function util.Compress(s)
	return #s .. ":" .. s
end

function util.Decompress(s, maxSize)
	local size, body = s:match("^(%d+):(.*)$")
	size = tonumber(size)
	if not size or size ~= #body then return nil end
	if maxSize and size > maxSize then return nil end
	return body
end

function Stub.Reset()
	now = 0
	screenW, screenH = 1920, 1080
end
