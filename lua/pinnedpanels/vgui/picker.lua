-- PinnedPanelsPicker (§33.7): a full-screen overlay for pinning another addon's panel. It outlines the
-- window under the cursor, or a part of it, with a card saying what it is and what pinning would do. It
-- holds the "picker" cursor reason while open. The overlay takes the clicks, so what is under the cursor
-- is found by walking the panels, not with vgui.GetHoveredPanel().

local PP = PinnedPanels
local Recipes, Input, T = PP.Recipes, PP.Input, PP.Theme

PP.Picker = PP.Picker or {}

local REFRESH = 0.5
local CARD_W, CARD_PAD, LINE_H = 300, 10, 16
local LIST_W, ROW_H = 320, 36
local FOOTER_H = 26
local MAX_DEPTH = 40
local OUTLINE, OUTLINE_REFUSED, FILL = Color(60, 200, 255), Color(230, 80, 80), Color(60, 200, 255, 30)

local function contains(p, x, y)
	local px, py = p:LocalToScreen(0, 0)
	return x >= px and y >= py and x < px + p:GetWide() and y < py + p:GetTall()
end

local function drawn(p)
	return IsValid(p) and p:IsVisible() and p:GetAlpha() > 0 and p:GetWide() > 0 and p:GetTall() > 0
end

-- root and its deepest visible descendants under the point, top-most child first.
local function chainAt(root, x, y)
	local chain, p = { root }, root
	for _ = 1, MAX_DEPTH do
		local kids, found = p:GetChildren(), nil
		for i = #kids, 1, -1 do
			if drawn(kids[i]) and contains(kids[i], x, y) then
				found = kids[i]
				break
			end
		end
		if not found then break end
		chain[#chain + 1] = found
		p = found
	end
	return chain
end

local PICKER = {}

function PICKER:Init()
	self:SetPos(0, 0)
	self:SetSize(ScrW(), ScrH())
	self.cycle, self.depth = 1, 1
	self.chain = {}
	self.lines = {}
	self.hint = PP.L("picker.hint")
	surface.SetFont("DermaDefault")
	self.hintW = surface.GetTextSize(self.hint) + 32
	self:RefreshTops()
	self:Hit()
end

-- The windows on screen, refreshed twice a second rather than per move (G40).
function PICKER:RefreshTops()
	self.nextRefresh = RealTime() + REFRESH
	local popups, others = {}, {}
	for _, p in ipairs(Recipes.TopLevels()) do
		if p ~= self and drawn(p) then
			local list = p:IsPopup() and popups or others
			list[#list + 1] = p
		end
	end
	-- Later panels are more likely on top, and a non-popup always draws behind popups (G59).
	local tops = {}
	for i = #popups, 1, -1 do tops[#tops + 1] = popups[i] end
	for i = #others, 1, -1 do tops[#tops + 1] = others[i] end
	self.tops = tops
end

function PICKER:Think()
	if gui.IsGameUIVisible() then
		gui.HideGameUI()
		return self:Remove()
	end
	if RealTime() >= self.nextRefresh then
		self:RefreshTops()
		self:Hit()
	end
end

function PICKER:OnCursorMoved()
	self:Hit()
end

-- Works out the window under the cursor (the cycle-th of those overlapping) and the chain down to the
-- deepest part; depth picks the panel along it. Left alone while a menu is open or the list chose one.
function PICKER:Hit()
	if IsValid(self.menu) or self.fromList then return end
	local x, y = input.GetCursorPos()
	local under = {}
	for _, p in ipairs(self.tops) do
		if drawn(p) and contains(p, x, y) then under[#under + 1] = p end
	end
	self.overlaps = #under
	local root = under[(self.cycle - 1) % math.max(#under, 1) + 1]
	if root ~= self.root then self.depth = 1 end
	self.root = root
	self.chain = root and chainAt(root, x, y) or {}
	self.depth = math.Clamp(self.depth, 1, math.max(#self.chain, 1))
	self:Select(self.chain[self.depth])
end

-- The card's lines, worked out once per selection.
function PICKER:Select(panel)
	if panel == self.selected and not self.dirty then return end
	self.selected, self.dirty = panel, nil
	self.lines, self.refusal, self.info = {}, nil, nil
	if not IsValid(panel) then return end
	local root = self.root
	self.refusal = Recipes.Refusal(panel, root) or (panel ~= root and not Recipes.Native(panel) and "refuse.part")
	local sig = Recipes.Signature(panel)
	local lines = self.lines
	lines[1] = Recipes.SigTitle(sig)
	lines[2] = PP.L("picker.addon", Recipes.AddonName(Recipes.Signature(root)))
	lines[3] = sig.class and PP.L("picker.class", sig.class, sig.base or "?") or PP.L("picker.unnamed", sig.base or "?")
	lines[4] = PP.L("picker.size", sig.w, sig.h) .. (panel ~= root and "  ·  " .. PP.L("picker.part") or "")
	if self.refusal then
		lines[5] = PP.L(self.refusal)
	else
		local info = Recipes.Suggest(panel, root)
		self.info = info
		if info.mode == "native" then
			lines[5] = PP.L("picker.click_native", PP.Sources.Title(info.native))
		else
			lines[5] = PP.L("picker.click_" .. info.mode) .. "  ·  " .. Recipes.Describe(info)
		end
	end
end

function PICKER:Walk(dir)
	self.depth = math.Clamp(self.depth + dir, 1, math.max(#self.chain, 1))
	self:Select(self.chain[self.depth])
end

function PICKER:Cycle(dir)
	self.cycle = self.cycle + dir
	self.root = nil
	self:Hit()
end

-- Pins the selection; the picker closes first so its cursor reason is gone before the window is taken.
-- A desktop widget is built as our own tab instead, and its window is left alone.
function PICKER:Pin(mode, recipe)
	local panel, root, info = self.selected, self.root, self.info
	self:Remove()
	if not info or not IsValid(panel) then return end
	mode = mode or info.mode
	if mode == "native" then return PP.Desktop.PinSource(info.native) end
	local id = Recipes.Take(panel, root, mode, recipe or info.recipe)
	if id then notification.AddLegacy(PP.L("adopt.pinned", PP.Layout.Title(PP.Layout.Get(id))), NOTIFY_GENERIC, 6) end
end

-- Right-click: each way of pinning it, with how it comes back.
function PICKER:OpenMenu()
	local info = self.info
	if not info then return surface.PlaySound("buttons/button10.wav") end
	local menu = DermaMenu()
	self.menu = menu
	for _, mode in ipairs(Recipes.Modes(info)) do
		if mode == "native" then
			menu:AddOption(PP.L("picker.mode_native"), function() self:Pin("native") end):SetIcon("icon16/application_view_tile.png")
		else
			local sub, option = menu:AddSubMenu(PP.L("picker.mode_" .. mode))
			option:SetIcon(mode == info.mode and "icon16/tick.png" or "icon16/bullet_white.png")
			for _, r in ipairs(Recipes.Choices(info)) do
				sub:AddOption(Recipes.Describe({ recipe = r }), function() self:Pin(mode, r) end)
					:SetIcon(r == info.recipe and "icon16/tick.png" or "icon16/bullet_white.png")
			end
		end
	end
	menu:Open()
end

function PICKER:OnMousePressed(code)
	if code == MOUSE_LEFT then
		if self.info then self:Pin() else surface.PlaySound("buttons/button10.wav") end
	elseif code == MOUSE_RIGHT then
		self:OpenMenu()
	end
end

function PICKER:OnMouseWheeled(delta)
	self:Walk(delta > 0 and -1 or 1)
	return true
end

function PICKER:OnKeyCodePressed(code)
	if code == KEY_ESCAPE then
		self:Remove()
	elseif code == KEY_UP then
		self:Walk(-1)
	elseif code == KEY_DOWN then
		self:Walk(1)
	elseif code == KEY_LEFT then
		self:Cycle(-1)
	elseif code == KEY_RIGHT then
		self:Cycle(1)
	elseif code == KEY_TAB then
		self:ToggleList()
	elseif code == KEY_ENTER or code == KEY_PAD_ENTER then
		if self.info then self:Pin() end
	end
end

-- ── The open windows list ───────────────────────────────────
-- For windows that are hard to hover: every top-level window, hover to outline it, click to pin it.

local ROW = {}

function ROW:Init()
	self:SetText("")
	self:SetTall(ROW_H)
end

function ROW:Setup(picker, panel)
	self.picker, self.panel = picker, panel
	local sig = Recipes.Signature(panel)
	self.title = Recipes.SigTitle(sig)
	self.sub = (sig.class or sig.base or "?") .. "  ·  " .. Recipes.AddonName(sig)
end

function ROW:OnCursorEntered()
	local p = self.picker
	p.fromList = true
	p.root, p.chain, p.depth = self.panel, { self.panel }, 1
	p:Select(self.panel)
end

function ROW:OnCursorExited()
	self.picker.fromList = false
end

function ROW:DoClick()
	self.picker:Pin()
end

function ROW:DoRightClick()
	self.picker:OpenMenu()
end

function ROW:Paint(w, h)
	draw.RoundedBox(4, 0, 0, w, h, self:IsHovered() and T.paletteSelected or T.card)
	draw.SimpleText(self.title, "DermaDefaultBold", 8, 5, T.textBright, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
	draw.SimpleText(self.sub, "DermaDefault", 8, h - 5, T.textMuted, TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM)
end

vgui.Register("PinnedPanelsPickerRow", ROW, "DButton")

function PICKER:ToggleList()
	if IsValid(self.list) then
		self.list:Remove()
		self.fromList = false
		return
	end
	local list = self:Add("DScrollPanel")
	list:SetPos(ScrW() - LIST_W - 16, 16)
	list:SetSize(LIST_W, ScrH() - 32 - FOOTER_H - 16)
	list.Paint = function(_, w, h) draw.RoundedBox(6, 0, 0, w, h, T.popupBg) end
	local header = list:Add("DLabel")
	header:Dock(TOP)
	header:DockMargin(8, 6, 8, 4)
	header:SetFont("DermaDefaultBold")
	header:SetTextColor(T.textBright)
	header:SetText(PP.L("picker.open_windows"))
	for _, p in ipairs(self.tops) do
		if not Recipes.Refusal(p, p) then
			local row = list:Add("PinnedPanelsPickerRow")
			row:Dock(TOP)
			row:DockMargin(6, 0, 6, 4)
			row:Setup(self, p)
		end
	end
	self.list = list
end

-- ── Painting ────────────────────────────────────────────────

function PICKER:Paint(w, h)
	local p = self.selected
	if IsValid(p) then
		local x, y = p:LocalToScreen(0, 0)
		local color = self.refusal and OUTLINE_REFUSED or OUTLINE
		surface.SetDrawColor(FILL)
		surface.DrawRect(x, y, p:GetWide(), p:GetTall())
		surface.SetDrawColor(color)
		surface.DrawOutlinedRect(x - 2, y - 2, p:GetWide() + 4, p:GetTall() + 4, 2)

		local lines = self.lines
		local ch = CARD_PAD * 2 + #lines * LINE_H
		local mx, my = input.GetCursorPos()
		local cx = math.Clamp(mx + 18, 8, w - CARD_W - 8)
		local cy = math.Clamp(my + 18, 8, h - ch - FOOTER_H - 16)
		draw.RoundedBox(6, cx, cy, CARD_W, ch, T.popupBg)
		surface.SetDrawColor(color)
		surface.DrawOutlinedRect(cx, cy, CARD_W, ch, 1)
		for i, line in ipairs(lines) do
			local font = i == 1 and "DermaDefaultBold" or "DermaDefault"
			local tint = i == 1 and T.textBright or (i == #lines and (self.refusal and T.danger or T.accent) or T.text)
			draw.SimpleText(line, font, cx + CARD_PAD, cy + CARD_PAD + (i - 1) * LINE_H, tint, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
		end
		if (self.overlaps or 0) > 1 then
			draw.SimpleText(PP.L("picker.overlaps", self.overlaps), "DermaDefault", cx + CARD_W - CARD_PAD, cy + CARD_PAD, T.textMuted, TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP)
		end
	end
	draw.RoundedBox(6, (w - self.hintW) / 2, h - FOOTER_H - 10, self.hintW, FOOTER_H, T.popupBg)
	draw.SimpleText(self.hint, "DermaDefault", w / 2, h - FOOTER_H / 2 - 10, T.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end

function PICKER:OnRemove()
	Input.Cursor("picker", false)
	if IsValid(self.menu) then self.menu:Remove() end
	if PP.Picker.panel == self then PP.Picker.panel = nil end
end

vgui.Register("PinnedPanelsPicker", PICKER, "EditablePanel")

function PP.Picker.Open()
	if IsValid(PP.Picker.panel) then return end
	Input.Cursor("picker", true)
	local p = vgui.Create("PinnedPanelsPicker")
	p:MakePopup()
	PP.Picker.panel = p
end
