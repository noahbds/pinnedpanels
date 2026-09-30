-- Settings are archived client convars (D3), each declared once with its type, range and default (§21).
-- Reads come from a typed cache that the convar change callback keeps current; writes use ConVar:SetString (G33).

local PP = PinnedPanels
PP.Settings = PP.Settings or {}
local Settings, Util = PP.Settings, PP.Util

Settings.defs = {}
Settings.order = {}
local values = {}

local function convarName(key)
	return "pinnedpanels_" .. key:gsub("%u", function(c) return "_" .. c:lower() end)
end

local function encode(def, v)
	if def.type == "bool" then return v and "1" or "0" end
	if def.type == "color" then return Util.ColorToString(v) end
	return tostring(v)
end

-- Anything invalid decodes to the default.
local function decode(def, s)
	if def.type == "bool" then
		local n = tonumber(s)
		if n == nil then return def.default end
		return n ~= 0
	elseif def.type == "int" or def.type == "key" then
		local n = tonumber(s)
		if not Util.Finite(n) then return def.default end
		n = math.Round(n)
		if def.min then n = math.max(n, def.min) end
		if def.max then n = math.min(n, def.max) end
		return n
	elseif def.type == "enum" then
		for _, v in ipairs(def.values) do
			if v == s then return s end
		end
		return def.default
	elseif def.type == "color" then
		return Util.StringToColor(s) or Color(def.default.r, def.default.g, def.default.b, def.default.a)
	end
end

local function same(def, a, b)
	if def.type == "color" then
		return a.r == b.r and a.g == b.g and a.b == b.b and a.a == b.a
	end
	return a == b
end

local function update(key, s)
	local def = Settings.defs[key]
	local value = decode(def, s)
	if same(def, value, values[key]) then return end
	values[key] = value
	hook.Run("PinnedPanelsSettingChanged", key, value)
end

-- def: { type = "bool"|"int"|"enum"|"color"|"key", default, min?, max?, values? (enum), page, section? }
function Settings.Add(key, def)
	def.key = key
	def.convar = convarName(key)
	Settings.defs[key] = def
	Settings.order[#Settings.order + 1] = key

	local min, max = def.min, def.max
	if def.type == "bool" then min, max = 0, 1 end
	local cv = CreateClientConVar(def.convar, encode(def, def.default), true, false, "", min, max)
	def.cv = cv
	values[key] = decode(def, cv:GetString())
	cvars.AddChangeCallback(def.convar, function(_, _, new) update(key, new) end, "PinnedPanels.Settings")
end

-- Colours are shared cached objects: read them, never modify them.
function Settings.Get(key)
	return values[key]
end

function Settings.Set(key, value)
	local def = Settings.defs[key]
	def.cv:SetString(encode(def, value))
	update(key, def.cv:GetString())
end

function Settings.Reset(key)
	Settings.Set(key, Settings.defs[key].default)
end

-- ── Declarations ────────────────────────────────────────────
-- Declared in the commit that first reads them (§21.1); the full list is §21.2.

Settings.Add("autoRestore", { type = "bool", default = true, page = "general", section = "behavior" })
Settings.Add("idleOpacity", { type = "int", min = 10, max = 100, default = 100, page = "general", section = "behavior" })
Settings.Add("snap", { type = "bool", default = true, page = "general", section = "snapping" })
Settings.Add("snapDistance", { type = "int", min = 0, max = 40, default = 12, page = "general", section = "snapping" })
Settings.Add("colorBg", { type = "color", default = Color(235, 238, 242, 250), page = "appearance" })
Settings.Add("colorHeader", { type = "color", default = Color(32, 35, 42, 255), page = "appearance" })
Settings.Add("colorText", { type = "color", default = Color(240, 245, 255, 255), page = "appearance" })
Settings.Add("taskbar", { type = "bool", default = true, page = "taskbar", section = "taskbar" })
Settings.Add("taskbarSide", { type = "enum", values = { "bottom", "top", "left", "right" }, default = "bottom", page = "taskbar", section = "taskbar" })
Settings.Add("taskbarSize", { type = "int", min = 20, max = 64, default = 32, page = "taskbar", section = "taskbar" })
Settings.Add("taskbarAutoHide", { type = "bool", default = false, page = "taskbar", section = "taskbar" })
Settings.Add("taskbarLabels", { type = "bool", default = true, page = "taskbar", section = "taskbar" })
Settings.Add("taskbarColorBg", { type = "color", default = Color(20, 22, 30, 220), page = "taskbar", section = "colors" })
Settings.Add("taskbarColorText", { type = "color", default = Color(220, 225, 235, 255), page = "taskbar", section = "colors" })
Settings.Add("taskbarColorAccent", { type = "color", default = Color(60, 140, 255, 255), page = "taskbar", section = "colors" })
Settings.Add("keyCursor", { type = "key", default = KEY_F4, page = "controls" })
