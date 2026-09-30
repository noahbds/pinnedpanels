-- Small shared controls painted from theme tokens: PinnedPanelsButton, PinnedPanelsSearch, PinnedPanelsError.

local PP = PinnedPanels
local T = PP.Theme

-- ── PinnedPanelsButton ──────────────────────────────────────
-- SetOn(true) gives the green "pinned" look; SetDanger(true) the red one. SetIcon takes an icon16 path.

local BUTTON = {}

function BUTTON:Init()
	self:SetText("")
	self.label = ""
	self.on = false
end

function BUTTON:SetLabel(text) self.label = text end
function BUTTON:SetOn(on) self.on = on end
function BUTTON:SetDanger(on) self.danger = on end
function BUTTON:SetIcon(path) self.icon = path and PP.Theme.Icon(path) end

function BUTTON:Paint(w, h)
	local hovered = self:IsHovered()
	local bg, outline, text
	if self.on then
		bg, outline, text = hovered and T.buttonOnHover or T.buttonOn, T.buttonOnOutline, T.buttonOnText
	elseif self.danger then
		bg, outline, text = hovered and T.dangerHover or T.dangerBg, T.buttonOutline, T.dangerText
	else
		bg, outline, text = hovered and T.buttonHover or T.button, T.buttonOutline, T.buttonText
	end
	draw.RoundedBox(4, 0, 0, w, h, bg)
	surface.SetDrawColor(outline)
	surface.DrawOutlinedRect(0, 0, w, h, 1)
	local x = w / 2
	if self.icon then
		surface.SetFont("DermaDefault")
		local tw = self.label ~= "" and surface.GetTextSize(self.label) + 4 or 0
		local ix = math.floor((w - 16 - tw) / 2)
		surface.SetMaterial(self.icon)
		surface.SetDrawColor(255, 255, 255, 255)
		surface.DrawTexturedRect(ix, math.floor((h - 16) / 2), 16, 16)
		x = ix + 20 + (tw - 4) / 2
	end
	draw.SimpleText(self.label, "DermaDefault", x, h / 2, text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end

vgui.Register("PinnedPanelsButton", BUTTON, "DButton")

-- ── PinnedPanelsSearch ──────────────────────────────────────

local SEARCH = {}

function SEARCH:Paint(w, h)
	draw.RoundedBox(4, 0, 0, w, h, T.inputBg)
	surface.SetDrawColor(T.inputBorder)
	surface.DrawOutlinedRect(0, 0, w, h, 1)
	if self:GetText() == "" then
		draw.SimpleText(self:GetPlaceholderText() or "", "DermaDefault", 5, h / 2, T.textMuted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	end
	self:DrawTextEntryText(T.inputText, T.inputCursor, T.inputText)
end

vgui.Register("PinnedPanelsSearch", SEARCH, "DTextEntry")

-- ── PinnedPanelsError ───────────────────────────────────────
-- Shown in a tab whose content failed to build (E8), with a Retry button.

local ERROR = {}

function ERROR:Init()
	self.label = self:Add("DLabel")
	self.label:Dock(TOP)
	self.label:DockMargin(8, 8, 8, 4)
	self.label:SetWrap(true)
	self.label:SetAutoStretchVertical(true)
	self.label:SetTextColor(T.danger)
	self.label:SetText(PP.L("source.error"))

	self.retry = self:Add("PinnedPanelsButton")
	self.retry:Dock(TOP)
	self.retry:DockMargin(8, 4, 8, 8)
	self.retry:SetTall(24)
	self.retry:SetLabel(PP.L("btn.retry"))
end

function ERROR:SetRetry(fn)
	self.retry.DoClick = fn
end

function ERROR:Paint() end

vgui.Register("PinnedPanelsError", ERROR, "DPanel")

-- ── Dialogs ─────────────────────────────────────────────────
-- Small popups opened by actions. They take the keyboard only while one of their text fields has
-- focus, like windows (ppTakesKeyboard, G20), except where typing is the whole point.

PP.Dialogs = PP.Dialogs or {}
local Dialogs = PP.Dialogs

local function paintDialog(self, w, h)
	draw.RoundedBox(6, 0, 0, w, h, T.popupBg)
	draw.RoundedBoxEx(6, 0, 0, w, 24, T.popupHeader, true, true, false, false)
	surface.SetDrawColor(T.popupBorder)
	surface.DrawOutlinedRect(0, 0, w, h, 1)
end

local function dialog(title, w, h)
	local frame = vgui.Create("DFrame")
	frame:SetTitle(title)
	frame:SetSize(w, h)
	frame:Center()
	frame:SetDeleteOnClose(true)
	frame:MakePopup()
	frame.Paint = paintDialog
	return frame
end

-- A one-line text prompt (rename, new group, custom opacity); okKey names the confirm button (default OK).
function Dialogs.Text(title, prompt, default, onOk, okKey)
	Derma_StringRequest(title, prompt, default or "", onOk, function() end, PP.L(okKey or "btn.ok"), PP.L("btn.cancel"))
end

-- Captures a key with the stock DBinder (G19) and lists conflicts before applying (F26, E15, E30).
-- opts = { title, get = fn → key, set = fn(key), tag = "action:<id>" | "quick:<windowId>" }
function Dialogs.Key(opts)
	if IsValid(Dialogs.keyFrame) then Dialogs.keyFrame:Remove() end
	local frame = dialog(opts.title, 320, 150)
	Dialogs.keyFrame = frame

	local help = frame:Add("DLabel")
	help:Dock(TOP)
	help:DockMargin(8, 4, 8, 8)
	help:SetWrap(true)
	help:SetAutoStretchVertical(true)
	help:SetTextColor(T.textLabel)
	help:SetText(PP.L("bind.instr"))

	local binder = frame:Add("DBinder")
	binder:Dock(TOP)
	binder:DockMargin(8, 0, 8, 8)
	binder:SetTall(40)
	binder:SetValue(opts.get())
	binder.OnChange = function(_, key)
		if key == opts.get() then return end
		local function apply()
			opts.set(key)
			if IsValid(frame) then frame:Close() end
		end
		local conflicts = PP.Actions.Conflicts(key, opts.tag)
		if #conflicts == 0 then return apply() end
		Derma_Query(PP.L("conflict.query", string.upper(input.GetKeyName(key) or "?"), table.concat(conflicts, "\n- ")),
			PP.L("conflict.title"), PP.L("conflict.bind_anyway"), apply,
			PP.L("btn.cancel"), function() if IsValid(binder) then binder:SetValue(opts.get()) end end)
	end
	return frame
end

-- Per-window colours (F14): background, header and text, each following the settings until changed.
local COLOR_ROWS = {
	{ field = "bg", label = "color.bg", setting = "colorBg" },
	{ field = "header", label = "color.header", setting = "colorHeader" },
	{ field = "text", label = "color.text_swatch", setting = "colorText" },
}

function Dialogs.Colors(id)
	local Layout = PP.Layout
	local rec = Layout.Get(id)
	if not rec then return end
	if IsValid(Dialogs.colorFrame) then Dialogs.colorFrame:Remove() end
	local frame = dialog(PP.L("color.popup_title", Layout.Title(rec)), 320, 440)
	frame:SetKeyboardInputEnabled(false)
	frame.ppTakesKeyboard = true
	Dialogs.colorFrame = frame

	local scroll = frame:Add("DScrollPanel")
	scroll:Dock(FILL)
	scroll:DockMargin(4, 4, 4, 4)

	local function set(field, color)
		local colors = {}
		for k, v in pairs(rec.colors) do colors[k] = v end
		colors[field] = color
		Layout.SetColors(id, colors)
	end

	for _, row in ipairs(COLOR_ROWS) do
		local bar = scroll:Add("Panel")
		bar:Dock(TOP)
		bar:SetTall(24)
		bar:DockMargin(0, 0, 0, 4)

		local label = bar:Add("DLabel")
		label:Dock(FILL)
		label:SetTextColor(T.textLabel)
		label:SetText(PP.L(row.label))

		local mixer = scroll:Add("DColorMixer")
		mixer:Dock(TOP)
		mixer:SetTall(100)
		mixer:DockMargin(0, 0, 0, 8)
		mixer:SetPalette(false)
		mixer:SetAlphaBar(true)
		mixer:SetWangs(true)
		mixer:SetColor(rec.colors[row.field] or PP.Settings.Get(row.setting))
		mixer.ValueChanged = function(self, c)
			if not self.quiet then set(row.field, Color(c.r, c.g, c.b, c.a)) end
		end

		local reset = bar:Add("PinnedPanelsButton")
		reset:Dock(RIGHT)
		reset:SetWide(60)
		reset:SetLabel(PP.L("btn.reset"))
		reset.DoClick = function()
			mixer.quiet = true -- SetColor reports a change; this one isn't the player's
			mixer:SetColor(PP.Settings.Get(row.setting))
			mixer.quiet = nil
			set(row.field, nil)
		end
	end

	local all = scroll:Add("PinnedPanelsButton")
	all:Dock(TOP)
	all:SetTall(28)
	all:DockMargin(0, 4, 0, 0)
	all:SetLabel(PP.L("btn.reset_global"))
	all.DoClick = function()
		Layout.SetColors(id, {})
		frame:Close()
	end
	PP.Nav.EnterPopup(frame)
	return frame
end
