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
local LIST_DEPTH = 3
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
	if IsValid(self.list) then self:FillList() end
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
	local root = Recipes.RootFor(panel, self.root)
	self.pickRoot = root
	self.refusal = Recipes.Refusal(panel, root)
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
		lines[5] = PP.L("picker.click_" .. info.mode) .. "  ·  " .. Recipes.Describe(info)
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
function PICKER:Pin(recipe)
	local panel, root, info = self.selected, self.pickRoot, self.info
	self:Remove()
	if not info or not IsValid(panel) then return end
	local id = Recipes.Take(panel, root, info.mode, recipe or info.recipe)
	if id then notification.AddLegacy(PP.L("adopt.pinned", PP.Layout.Title(PP.Layout.Get(id))), NOTIFY_GENERIC, 6) end
end

-- Right-click: how it comes back, then pin it with that.
function PICKER:OpenMenu()
	local info = self.info
	if not info then return surface.PlaySound("buttons/button10.wav") end
	local menu = DermaMenu()
	self.menu = menu
	for _, r in ipairs(Recipes.Choices(info)) do
		menu:AddOption(Recipes.Describe({ recipe = r }), function() self:Pin(r) end)
			:SetIcon(r == info.recipe and "icon16/tick.png" or "icon16/bullet_white.png")
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

-- root is the top-level panel it belongs to: itself, or the spawn menu or C menu for one of their parts.
function ROW:Setup(picker, panel, root)
	self.picker, self.panel, self.root = picker, panel, root
	local sig = Recipes.Signature(panel)
	self.title = Recipes.SigTitle(sig)
	self.sub = (sig.class or sig.base or "?") .. "  ·  " .. Recipes.AddonName(sig) .. "  ·  " .. sig.w .. " × " .. sig.h
end

function ROW:OnCursorEntered()
	local p = self.picker
	if not IsValid(self.panel) then return end
	p.fromList = true
	p.root, p.chain, p.depth = self.root, { self.panel }, 1
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

-- The spawn menu and the C menu can't be pinned whole, so the list names what is in them instead: the
-- first panels down that are something of their own (a class an addon or the gamemode made, or a desktop
-- widget's window).
local function addParts(out, parent, root, depth)
	for _, kid in ipairs(parent:GetChildren()) do
		if drawn(kid) and not Recipes.Refusal(kid, root) then
			if PP.Openers.DesktopId(kid) or Recipes.Signature(kid).class then
				out[#out + 1] = { panel = kid, root = root }
			elseif depth < LIST_DEPTH then
				addParts(out, kid, root, depth + 1)
			end
		end
	end
end

function PICKER:ListEntries()
	local out = {}
	for _, p in ipairs(self.tops) do
		if not drawn(p) then
			-- closed since the last look
		elseif not Recipes.Refusal(p, p) then
			-- A bare stock panel with nothing of an addon's in it (a scroll list kept for later, a holder,
			-- the game's own HUD layers) is nothing to choose by name. It can still be pinned by pointing at it.
			local sig = Recipes.Signature(p)
			if sig.popup or sig.title or sig.class or sig.src then out[#out + 1] = { panel = p, root = p } end
		elseif p == g_SpawnMenu or p == g_ContextMenu then
			addParts(out, p, p, 1)
		end
	end
	return out
end

-- The list follows what is on screen: called with every refresh of the windows, it makes its rows again
-- only when they would differ.
function PICKER:FillList()
	local entries, rows = self:ListEntries(), self.rows
	local same = #entries == #rows
	for i = 1, same and #entries or 0 do
		if rows[i].panel ~= entries[i].panel then
			same = false
			break
		end
	end
	if same then return end
	for _, row in ipairs(rows) do row:Remove() end
	-- A removed row under the cursor never says the cursor left it.
	self.fromList = false
	self.rows = {}
	for i, e in ipairs(entries) do
		local row = self.list:Add("PinnedPanelsPickerRow")
		row:Dock(TOP)
		row:DockMargin(6, 0, 6, 4)
		row:Setup(self, e.panel, e.root)
		self.rows[i] = row
	end
end

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
	self.list, self.rows = list, {}
	self:RefreshTops()
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
