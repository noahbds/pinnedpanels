-- Small shared controls painted from theme tokens: PinnedPanelsButton, PinnedPanelsSearch, PinnedPanelsError.

local PP = PinnedPanels
local T = PP.Theme

-- ── PinnedPanelsButton ──────────────────────────────────────
-- SetOn(true) gives the green "pinned" look.

local BUTTON = {}

function BUTTON:Init()
	self:SetText("")
	self.label = ""
	self.on = false
end

function BUTTON:SetLabel(text) self.label = text end
function BUTTON:SetOn(on) self.on = on end

function BUTTON:Paint(w, h)
	local hovered = self:IsHovered()
	local bg, outline, text
	if self.on then
		bg, outline, text = hovered and T.buttonOnHover or T.buttonOn, T.buttonOnOutline, T.buttonOnText
	else
		bg, outline, text = hovered and T.buttonHover or T.button, T.buttonOutline, T.buttonText
	end
	draw.RoundedBox(4, 0, 0, w, h, bg)
	surface.SetDrawColor(outline)
	surface.DrawOutlinedRect(0, 0, w, h, 1)
	draw.SimpleText(self.label, "DermaDefault", w / 2, h / 2, text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end

vgui.Register("PinnedPanelsButton", BUTTON, "DButton")

-- ── PinnedPanelsSearch ──────────────────────────────────────

local SEARCH = {}

function SEARCH:Paint(w, h)
	draw.RoundedBox(4, 0, 0, w, h, T.inputBg)
	surface.SetDrawColor(T.inputBorder)
	surface.DrawOutlinedRect(0, 0, w, h, 1)
	if self:GetText() == "" then
		draw.SimpleText(self:GetPlaceholderText() or "", self:GetFont(), 5, h / 2, T.textMuted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
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
