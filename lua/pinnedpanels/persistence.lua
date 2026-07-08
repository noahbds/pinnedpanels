-- ── Persistence: Settings & Pin Data ─────────────────────────────────────────
local SAVEF     = "pinnedpanels_save.json"
local SETTINGSF = "pinnedpanels_settings.json"

local DEFAULT_TASKBAR = {
	enabled       = true,
	position      = "bottom",
	height        = 32,
	bgColor       = Color(20, 22, 30, 220),
	textColor     = Color(220, 225, 235, 255),
	accentColor   = Color(60, 140, 255, 255),
	revealOnHover = false,     -- collapse to a thin strip until the cursor is near it
	showLabels    = true,
}

local DEFAULT_SETTINGS = {
	bg          = Color(235, 238, 242, 250),
	header      = Color(32, 35, 42, 255),
	text        = Color(240, 245, 255, 255),
	autoRestore = true,
	keyboardNavOutsideCursorMode = true,
	idleAlpha   = 1,
	groups      = {},
	taskbar     = table.Copy(DEFAULT_TASKBAR),
}

PinnedPanels.DEFAULT_TASKBAR = DEFAULT_TASKBAR

PinnedPanels.Settings = PinnedPanels.Settings or table.Copy(DEFAULT_SETTINGS)

-- ── Color Serialization ──────────────────────────────────────────────────────
local function SerializeColor(c)
	return { r = c.r, g = c.g, b = c.b, a = c.a }
end

local function DeserializeColor(t, fallback)
	if not istable(t) then return fallback end
	return Color(
		math.Clamp(tonumber(t.r) or 0, 0, 255),
		math.Clamp(tonumber(t.g) or 0, 0, 255),
		math.Clamp(tonumber(t.b) or 0, 0, 255),
		math.Clamp(tonumber(t.a) or 255, 0, 255)
	)
end

PinnedPanels._DeserializeColor = DeserializeColor

-- ── Settings Save / Load ─────────────────────────────────────────────────────
function PinnedPanels.SaveSettings()
	local groups = {}
	for _, g in ipairs(PinnedPanels.Settings.groups or {}) do
		groups[#groups + 1] = {
			name  = g.name,
			color = SerializeColor(g.color),
			ids   = g.ids,
		}
	end
	local tb = PinnedPanels.Settings.taskbar or {}
	local taskbarData = {
		enabled       = tb.enabled,
		position      = tb.position,
		height        = tb.height,
		bgColor       = tb.bgColor and SerializeColor(tb.bgColor) or nil,
		textColor     = tb.textColor and SerializeColor(tb.textColor) or nil,
		accentColor   = tb.accentColor and SerializeColor(tb.accentColor) or nil,
		revealOnHover = tb.revealOnHover,
		showLabels    = tb.showLabels,
	}

	file.Write(SETTINGSF, util.TableToJSON({
		bg          = SerializeColor(PinnedPanels.Settings.bg),
		header      = SerializeColor(PinnedPanels.Settings.header),
		text        = SerializeColor(PinnedPanels.Settings.text),
		autoRestore = PinnedPanels.Settings.autoRestore,
		keyboardNavOutsideCursorMode = PinnedPanels.Settings.keyboardNavOutsideCursorMode,
		idleAlpha   = PinnedPanels.Settings.idleAlpha,
		groups      = groups,
		taskbar     = taskbarData,
	}, true))
end

function PinnedPanels.LoadSettings()
	if not file.Exists(SETTINGSF, "DATA") then return end
	local raw = file.Read(SETTINGSF, "DATA")
	if not raw or raw == "" then return end
	local t = util.JSONToTable(raw)
	if not istable(t) then return end

	local S = PinnedPanels.Settings
	S.bg     = DeserializeColor(t.bg, DEFAULT_SETTINGS.bg)
	S.header = DeserializeColor(t.header, DEFAULT_SETTINGS.header)
	S.text   = DeserializeColor(t.text, DEFAULT_SETTINGS.text)
	if t.autoRestore ~= nil then S.autoRestore = tobool(t.autoRestore) end
	if t.keyboardNavOutsideCursorMode ~= nil then S.keyboardNavOutsideCursorMode = tobool(t.keyboardNavOutsideCursorMode) end
	S.idleAlpha = math.Clamp(tonumber(t.idleAlpha) or 1, 0.1, 1)

	local groups = {}
	if istable(t.groups) then
		for _, g in ipairs(t.groups) do
			if istable(g) and isstring(g.name) then
				groups[#groups + 1] = {
					name  = g.name,
					color = DeserializeColor(g.color, Color(255, 200, 60)),
					ids   = istable(g.ids) and g.ids or {},
				}
			end
		end
	end
	S.groups = groups

	local dtb = DEFAULT_TASKBAR
	if istable(t.taskbar) then
		local tb = t.taskbar
		local function boolOr(v, d) if v == nil then return d end return tobool(v) end
		S.taskbar = {
			enabled       = boolOr(tb.enabled, dtb.enabled),
			position      = (tb.position == "top" or tb.position == "left" or tb.position == "right") and tb.position or dtb.position,
			height        = math.Clamp(tonumber(tb.height) or dtb.height, 20, 64),
			bgColor       = DeserializeColor(tb.bgColor, dtb.bgColor),
			textColor     = DeserializeColor(tb.textColor, dtb.textColor),
			accentColor   = DeserializeColor(tb.accentColor, dtb.accentColor),
			revealOnHover = boolOr(tb.revealOnHover, dtb.revealOnHover),
			showLabels    = boolOr(tb.showLabels, dtb.showLabels),
		}
	else
		S.taskbar = table.Copy(dtb)
	end
end

PinnedPanels.LoadSettings()
hook.Run("PinnedPanels_SettingsLoaded")

-- ── Pin Data Save / Load ─────────────────────────────────────────────────────
function PinnedPanels.Save()
	local data = {}
	for id, pin in pairs(PinnedPanels.Pins) do
		if IsValid(pin.frame) then
			local x, y = pin.frame:GetPos()
			local w, h = pin.frame:GetSize()
			-- Maximize is a transient view state; persist the pre-maximize bounds.
			if pin.maximized and pin.restoreBounds then
				x, y = pin.restoreBounds.x, pin.restoreBounds.y
				w, h = pin.restoreBounds.w, pin.restoreBounds.h
			end
			local entry = {
				x = x, y = y, w = w, h = h,
				title = pin.title,
				kind  = pin.kind or "tool",
			}
			if pin.customBg then entry.customBg = SerializeColor(pin.customBg) end
			if pin.customHeader then entry.customHeader = SerializeColor(pin.customHeader) end
			if pin.customText then entry.customText = SerializeColor(pin.customText) end
			if pin.locked then entry.locked = true end
			if pin.idleAlpha then entry.idleAlpha = pin.idleAlpha end
			if pin.minimized then entry.minimized = true end
			if pin.kind == "group" and istable(pin.tabSizes) and next(pin.tabSizes) then
				entry.tabSizes = pin.tabSizes
			end
			data[id] = entry
		end
	end
	file.Write(SAVEF, util.TableToJSON(data, true))
end

function PinnedPanels.Load()
	if not file.Exists(SAVEF, "DATA") then return {} end
	local raw = file.Read(SAVEF, "DATA")
	if not raw or raw == "" then return {} end
	return util.JSONToTable(raw) or {}
end

function PinnedPanels.ClearSavedPin(id)
	local d = PinnedPanels.Load()
	d[id] = nil
	file.Write(SAVEF, util.TableToJSON(d, true))
end
