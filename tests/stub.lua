-- Just enough of GMod's globals to run the pure modules under plain LuaJIT (§25).
-- Stub.Reset() restores a known state before each test; Stub.* helpers drive time, keys and timers.

Stub = {}

local S

-- Plain Lua versions of the GMod extensions the modules use.
function isstring(v) return type(v) == "string" end
function istable(v) return type(v) == "table" end
function isnumber(v) return type(v) == "number" end
function isbool(v) return type(v) == "boolean" end
function isfunction(v) return type(v) == "function" end

function IsValid(v)
	return type(v) == "table" and type(v.IsValid) == "function" and v:IsValid() == true
end

function math.Clamp(v, lo, hi)
	return math.min(math.max(v, lo), hi)
end

function math.Round(v, decimals)
	local mult = 10 ^ (decimals or 0)
	return math.floor(v * mult + 0.5) / mult
end

function string.Trim(s)
	return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

KEY_NONE, KEY_A, KEY_B, KEY_ESCAPE = 0, 11, 12, 70
KEY_LSHIFT, KEY_RSHIFT, KEY_LALT, KEY_RALT = 79, 80, 81, 82
KEY_F4 = 95
NOTIFY_GENERIC, NOTIFY_ERROR = 0, 1

SERVER, CLIENT = false, true

local COLOR = {}
COLOR.__index = COLOR

function Color(r, g, b, a)
	return setmetatable({ r = r, g = g, b = b, a = a or 255 }, COLOR)
end

function IsColor(v)
	return getmetatable(v) == COLOR
end

color_white = Color(255, 255, 255)

-- Clock, screen and frames: time only moves when a test says so (G5).
function RealTime() return S.now end
function SysTime() return S.now end
function FrameNumber() return S.frame end
function ScrW() return S.sw end
function ScrH() return S.sh end

function Stub.SetScreen(w, h) S.sw, S.sh = w, h end

-- Timers: Stub.Advance runs every timer that falls due, in order.
timer = {}

function timer.Create(name, delay, reps, fn)
	S.timers[name] = { at = S.now + delay, delay = delay, reps = reps, fn = fn }
end

function timer.Remove(name) S.timers[name] = nil end
function timer.Exists(name) return S.timers[name] ~= nil end

function timer.Simple(delay, fn)
	S.anon = S.anon + 1
	timer.Create({}, delay, 1, fn)
end

function Stub.Advance(dt)
	local target = S.now + dt
	while true do
		local nextName, nextTimer
		for name, t in pairs(S.timers) do
			if t.at <= target and (not nextTimer or t.at < nextTimer.at) then nextName, nextTimer = name, t end
		end
		if not nextTimer then break end
		S.now = math.max(S.now, nextTimer.at)
		if nextTimer.reps == 1 then
			S.timers[nextName] = nil
		else
			nextTimer.reps = nextTimer.reps > 1 and nextTimer.reps - 1 or 0
			nextTimer.at = S.now + math.max(nextTimer.delay, 1e-6)
		end
		nextTimer.fn()
	end
	S.now = target
end

-- One frame: runs Think hooks and next-frame timers.
function Stub.Frame()
	S.frame = S.frame + 1
	hook.Run("Think")
	Stub.Advance(1 / 60)
end

-- Hooks, with GMod's rule that a non-string identifier is passed as the first argument (G31).
hook = {}

function hook.Add(event, id, fn)
	S.hooks[event] = S.hooks[event] or {}
	S.hooks[event][id] = fn
end

function hook.Remove(event, id)
	if S.hooks[event] then S.hooks[event][id] = nil end
end

function hook.GetTable() return S.hooks end

function hook.Run(event, ...)
	for id, fn in pairs(S.hooks[event] or {}) do
		local a, b
		if isstring(id) then
			a, b = fn(...)
		elseif IsValid(id) then
			a, b = fn(id, ...)
		else
			S.hooks[event][id] = nil
		end
		if a ~= nil then return a, b end
	end
end

concommand = {}
function concommand.Add(name, fn) S.commands[name] = fn end
function Stub.Command(name, argStr)
	return S.commands[name](nil, name, {}, argStr or "")
end

-- Convars: numeric ones clamp to min/max like the engine; changes fire cvars callbacks.
local CONVAR = {}
CONVAR.__index = CONVAR

function CONVAR:GetString() return self.value end
function CONVAR:GetInt() return math.floor(tonumber(self.value) or 0) end
function CONVAR:GetFloat() return tonumber(self.value) or 0 end
function CONVAR:GetBool() return self:GetInt() ~= 0 end
function CONVAR:GetDefault() return self.default end

function CONVAR:SetString(v)
	v = tostring(v)
	local n = tonumber(v)
	if n and self.min then n = math.max(n, self.min) end
	if n and self.max then n = math.min(n, self.max) end
	if n and (self.min or self.max) then v = tostring(n) end
	local old = self.value
	if old == v then return end
	self.value = v
	for _, fn in pairs(S.cvarCallbacks[self.name] or {}) do fn(self.name, old, v) end
end

CONVAR.SetInt = CONVAR.SetString
CONVAR.SetFloat = CONVAR.SetString
function CONVAR:SetBool(b) self:SetString(b and "1" or "0") end

function CreateClientConVar(name, default, save, userinfo, help, min, max)
	if not S.convars[name] then
		S.convars[name] = setmetatable({ name = name, value = tostring(default), default = tostring(default), min = min, max = max }, CONVAR)
	end
	return S.convars[name]
end

function GetConVar(name) return S.convars[name] end

cvars = {}
function cvars.AddChangeCallback(name, fn, id)
	S.cvarCallbacks[name] = S.cvarCallbacks[name] or {}
	S.cvarCallbacks[name][id or fn] = fn
end

-- Input state.
input = {}
function input.IsKeyDown(k) return S.keys[k] == true end
function input.IsKeyTrapping() return S.trapping end
function input.GetKeyName(k) return "KEY" .. tostring(k) end
function input.LookupKeyBinding(k) return S.binds[k] end
function Stub.Key(k, isDown) S.keys[k] = isDown or nil end

gui = {}
function gui.IsConsoleVisible() return S.console end
function gui.IsGameUIVisible() return S.gameUI end
function gui.EnableScreenClicker(on) S.clicker = on; S.clickerCalls = S.clickerCalls + 1 end
function RememberCursorPosition() end
function RestoreCursorPosition() end

system = {}
function system.HasFocus() return S.focus end

vgui = {}
function vgui.GetKeyboardFocus() return S.kbFocus end

-- Everything else a test may want to flip.
function Stub.Set(field, value) S[field] = value end
function Stub.Get(field) return S[field] end

language = {}
function language.GetPhrase(key) return S.phrases[key] or key end
function language.Add(key, value) S.phrases[key] = value end

notification = {}
function notification.AddLegacy(text, kind, seconds) S.notifications[#S.notifications + 1] = text end

function ErrorNoHalt(msg) S.errors[#S.errors + 1] = msg end
function MsgC(...) end

-- In-memory DATA folder with GMod's lowercasing (G34).
file = {}

function file.Write(name, data)
	if S.failWrites then return false end
	S.files[name:lower()] = data
	return true
end

function file.Read(name) return S.files[name:lower()] end
function file.Exists(name) return S.files[name:lower()] ~= nil end
function file.Delete(name) S.files[name:lower()] = nil end
function file.CreateDir() end
function file.Size(name) local d = S.files[name:lower()] return d and #d or -1 end

function file.Rename(from, to)
	from, to = from:lower(), to:lower()
	if S.files[from] == nil or S.files[to] ~= nil then return false end
	S.files[to], S.files[from] = S.files[from], nil
	return true
end

function Stub.Files() return S.files end

-- util: JSON with GMod's conversions (G35), Base64, and a run-length "compression" so bombs are small (G36).
util = {}

local function encodeJSON(v, out)
	local t = type(v)
	if t == "table" then
		local n = #v
		local isArray = n > 0 or next(v) == nil
		if isArray then
			for k in pairs(v) do
				if type(k) ~= "number" or k < 1 or k > n or k % 1 ~= 0 then isArray = false break end
			end
		end
		if isArray then
			out[#out + 1] = "["
			for i = 1, n do
				if i > 1 then out[#out + 1] = "," end
				encodeJSON(v[i], out)
			end
			out[#out + 1] = "]"
		else
			out[#out + 1] = "{"
			local first = true
			for k, val in pairs(v) do
				if not first then out[#out + 1] = "," end
				first = false
				encodeJSON(tostring(k), out)
				out[#out + 1] = ":"
				encodeJSON(val, out)
			end
			out[#out + 1] = "}"
		end
	elseif t == "string" then
		out[#out + 1] = '"' .. v:gsub('[%c"\\]', function(c)
			if c == "\n" then return "\\n" end
			if c == '"' or c == "\\" then return "\\" .. c end
			return string.format("\\u%04x", c:byte())
		end) .. '"'
	elseif t == "number" then
		out[#out + 1] = (v % 1 == 0 and math.abs(v) < 2 ^ 53) and string.format("%d", v) or string.format("%.14g", v)
	elseif t == "boolean" then
		out[#out + 1] = tostring(v)
	else
		out[#out + 1] = "null"
	end
end

function util.TableToJSON(t)
	local out = {}
	encodeJSON(t, out)
	return table.concat(out)
end

function util.JSONToTable(s, ignoreLimits)
	local pos, keys = 1, 0
	local function ws() pos = s:find("[^ \t\r\n]", pos) or #s + 1 end
	local value

	local function str()
		local parts = {}
		pos = pos + 1
		while true do
			local c = s:sub(pos, pos)
			if c == "" then error("unterminated string") end
			if c == '"' then pos = pos + 1 break end
			if c == "\\" then
				local e = s:sub(pos + 1, pos + 1)
				local map = { n = "\n", t = "\t", r = "\r", b = "\b", f = "\f", ['"'] = '"', ["\\"] = "\\", ["/"] = "/" }
				if e == "u" then
					parts[#parts + 1] = string.char(tonumber(s:sub(pos + 2, pos + 5), 16) % 256)
					pos = pos + 6
				elseif map[e] then
					parts[#parts + 1] = map[e]
					pos = pos + 2
				else
					error("bad escape")
				end
			else
				parts[#parts + 1] = c
				pos = pos + 1
			end
		end
		return table.concat(parts)
	end

	function value()
		ws()
		local c = s:sub(pos, pos)
		if c == "{" then
			local t = {}
			pos = pos + 1
			ws()
			if s:sub(pos, pos) == "}" then pos = pos + 1 return t end
			while true do
				ws()
				if s:sub(pos, pos) ~= '"' then error("expected key") end
				local k = str()
				ws()
				if s:sub(pos, pos) ~= ":" then error("expected colon") end
				pos = pos + 1
				local v = value()
				keys = keys + 1
				t[tonumber(k) or k] = v
				ws()
				local d = s:sub(pos, pos)
				pos = pos + 1
				if d == "}" then return t end
				if d ~= "," then error("expected comma") end
			end
		elseif c == "[" then
			local t, n = {}, 0
			pos = pos + 1
			ws()
			if s:sub(pos, pos) == "]" then pos = pos + 1 return t end
			while true do
				n = n + 1
				t[n] = value()
				keys = keys + 1
				ws()
				local d = s:sub(pos, pos)
				pos = pos + 1
				if d == "]" then return t end
				if d ~= "," then error("expected comma") end
			end
		elseif c == '"' then
			return str()
		else
			local lit = s:match("^[%w%.%-+]+", pos)
			if not lit then error("unexpected character") end
			pos = pos + #lit
			if lit == "true" then return true end
			if lit == "false" then return false end
			if lit == "null" then return nil end
			local n = tonumber(lit)
			if not n then error("bad literal") end
			return n
		end
	end

	local ok, result = pcall(function()
		local v = value()
		ws()
		if pos <= #s then error("trailing data") end
		return v
	end)
	if not ok or type(result) ~= "table" then return nil end
	if keys > 15000 and not ignoreLimits then return nil end
	return result
end

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

function util.Base64Encode(s)
	return ((s:gsub(".", function(c)
		local bits, b = "", c:byte()
		for i = 8, 1, -1 do bits = bits .. (b % 2 ^ i - b % 2 ^ (i - 1) > 0 and "1" or "0") end
		return bits
	end) .. "0000"):gsub("%d%d%d?%d?%d?%d?", function(bits)
		if #bits < 6 then return "" end
		local n = 0
		for i = 1, 6 do n = n + (bits:sub(i, i) == "1" and 2 ^ (6 - i) or 0) end
		return B64:sub(n + 1, n + 1)
	end) .. ({ "", "==", "=" })[#s % 3 + 1])
end

function util.Base64Decode(s)
	if s:find("[^%w%+/=]") then return nil end
	s = s:gsub("=", "")
	return (s:gsub(".", function(c)
		local n, bits = B64:find(c, 1, true) - 1, ""
		for i = 6, 1, -1 do bits = bits .. (n % 2 ^ i - n % 2 ^ (i - 1) > 0 and "1" or "0") end
		return bits
	end):gsub("%d%d%d?%d?%d?%d?%d?%d?", function(bits)
		if #bits ~= 8 then return "" end
		local n = 0
		for i = 1, 8 do n = n + (bits:sub(i, i) == "1" and 2 ^ (8 - i) or 0) end
		return string.char(n)
	end))
end

-- Repeats of a 1-8 byte unit (4+ times) become "\1<len><unit><count>;", so bombs and key floods stay small.
function util.Compress(s)
	local out, i = {}, 1
	while i <= #s do
		local bestP, bestK = 0, 0
		for p = 1, 8 do
			local unit, k = s:sub(i, i + p - 1), 1
			while #unit == p and s:sub(i + k * p, i + k * p + p - 1) == unit do k = k + 1 end
			if k >= 4 and k * p > bestK * bestP then bestP, bestK = p, k end
		end
		local c = s:sub(i, i)
		if bestK > 0 or c == "\1" then
			local p, k = math.max(bestP, 1), math.max(bestK, 1)
			out[#out + 1] = "\1" .. string.char(p) .. s:sub(i, i + p - 1) .. k .. ";"
			i = i + p * k
		else
			out[#out + 1] = c
			i = i + 1
		end
	end
	return "RLE" .. table.concat(out)
end

function util.Decompress(s, maxSize)
	if type(s) ~= "string" or s:sub(1, 3) ~= "RLE" then return nil end
	local out, size, i = {}, 0, 4
	while i <= #s do
		local piece
		if s:sub(i, i) == "\1" then
			local p = s:byte(i + 1)
			if not p then return nil end
			local unit = s:sub(i + 2, i + 1 + p)
			local k, stop = s:match("^(%d+);()", i + 2 + p)
			if #unit ~= p or not k then return nil end
			size = size + p * tonumber(k)
			if maxSize and size > maxSize then return nil end
			piece = unit:rep(tonumber(k))
			i = stop
		else
			piece = s:sub(i, i)
			size = size + 1
			i = i + 1
		end
		if maxSize and size > maxSize then return nil end
		out[#out + 1] = piece
	end
	return table.concat(out)
end

-- Spawn menu and control panels, filled in by the sources tests.
spawnmenu = {}
function spawnmenu.GetTools() return S.tools end
function spawnmenu.GetCreationTabs() return S.creationTabs end
function spawnmenu.ActivateTool(name) S.activated = name end
function spawnmenu.AddCreationTab() end

controlpanel = {}
function controlpanel.Get(name) return "spawnmenu panel " .. name end

function Stub.Reset()
	S = {
		now = 0, frame = 0, sw = 1920, sh = 1080, anon = 0,
		timers = {}, hooks = {}, commands = {}, convars = {}, cvarCallbacks = {},
		keys = {}, binds = {}, trapping = false, console = false, gameUI = false, focus = true, kbFocus = nil,
		clicker = false, clickerCalls = 0,
		phrases = {}, notifications = {}, errors = {}, files = {}, failWrites = false,
		tools = {}, creationTabs = {}, activated = nil,
	}
end

Stub.Reset()
