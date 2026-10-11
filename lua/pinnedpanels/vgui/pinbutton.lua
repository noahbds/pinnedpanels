-- The pin button (X65): a button, "Pin", at the corner of the window the cursor is on, that pins it with
-- one click, the way the picker's click on a whole window does; with the wheel on it, a part of that
-- window instead, as the picker's wheel chooses one. One button for the whole screen, moved to
-- whichever window is under the cursor, and only while a cursor shows: nothing is added to the view
-- while playing. It offers what the picker offers whole (another addon's window; not a menu, a dialog,
-- a scene, or anything of ours or already pinned) and, since the spawn menu can't be pinned whole, its
-- two halves.

local PP = PinnedPanels
local Recipes, Input, Settings, T = PP.Recipes, PP.Input, PP.Settings, PP.Theme

PP.PinButton = PP.PinButton or {}
local PinButton = PP.PinButton

local HEIGHT, GAP = 28, 3     -- its width is its label's
local FONT, ICON, PAD = "DermaDefaultBold", 16, 9
-- The picker's colours for what a click would pin.
local OUTLINE, FILL = Color(60, 200, 255), Color(60, 200, 255, 30)
local LOOK = 0.1               -- seconds between two looks at what is under the cursor
local LINGER = 0.5             -- seconds the button stays once the cursor is on neither it nor its window
local MIN_W, MIN_H = 120, 60   -- smaller than this isn't a window to pin by its corner
local FRAME_BUTTONS = 104      -- a DFrame's own three buttons, when ours has to sit inside beside them
-- The parts the wheel offers: what is big enough to be a window of its own (not one button of a list),
-- no deeper and no more than this.
local PART_W, PART_H, PART_DEPTH, PART_MAX = 160, 100, 14, 24
-- A control panel puts each of its rows in one of these: the row is offered, not what holds it.
local HOLDER = { DSizeToContents = true }
local SAME = 0.9               -- a part that covers this much of the one it is in is the same to the eye
local CARD_PAD, LINE_H = 8, 16

-- ── The button ──────────────────────────────────────────────

local BUTTON = {}

function BUTTON:Init()
	self:SetText("")
	self.ppOurs = true -- never offered by the picker, nor by itself
	self.icon = T.Icon("icon16/application_add.png")
	self.label = PP.L("pinbutton.label")
	surface.SetFont(FONT)
	self:SetSize(PAD + ICON + 6 + surface.GetTextSize(self.label) + PAD, HEIGHT)
end

function BUTTON:Paint(w, h)
	local hovered = self:IsHovered()
	draw.RoundedBox(5, 0, 0, w, h, hovered and T.buttonHover or T.popupBg)
	surface.SetDrawColor(T.popupBorder)
	surface.DrawOutlinedRect(0, 0, w, h, 1)
	surface.SetMaterial(self.icon)
	surface.SetDrawColor(255, 255, 255, 255)
	surface.DrawTexturedRect(PAD, (h - ICON) / 2, ICON, ICON)
	draw.SimpleText(self.label, FONT, PAD + ICON + 6, h / 2, hovered and T.textBright or T.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
end

-- On the press, not the release: a button's own click needs the cursor to still be on it when the
-- mouse button comes up, and this one is small, at the edge of a window that is about to move.
function BUTTON:OnMousePressed(code)
	if code == MOUSE_LEFT then PinButton.Pin() end
end

-- The cursor on the button: what the wheel can choose from, as the window is now.
function BUTTON:OnCursorEntered()
	PinButton.Choose()
end

function BUTTON:OnMouseWheeled(delta)
	PinButton.Step(delta > 0 and -1 or 1)
	return true
end

vgui.Register("PinnedPanelsPinButton", BUTTON, "DButton")

-- A reload makes the button again: the one from before is this file's old code.
if IsValid(PinButton.panel) then PinButton.panel:Remove() end
PinButton.panel, PinButton.target, PinButton.root = nil, nil, nil
PinButton.parts, PinButton.names, PinButton.index, PinButton.lines = {}, {}, 1, {}

-- ── Which window ────────────────────────────────────────────

-- The panel just below a root (the world panel, or the HUD's) that p is in.
local function topOf(p)
	while IsValid(p:GetParent()) and IsValid(p:GetParent():GetParent()) do p = p:GetParent() end
	return p
end

-- What the button would pin for the panel the cursor is on: the panel to pin and the window it is (or
-- is a part of), or nothing.
local function targetUnder(hovered)
	-- On nothing, the cursor is "on" the world panel itself, which holds every window: never that
	-- (found in a test: the button sat in a corner of the screen, ready to pin the whole of it).
	if not IsValid(hovered:GetParent()) then return nil end
	local root = topOf(hovered)
	if root == g_SpawnMenu then
		for _, part in ipairs({ root.CreateMenu, root.ToolMenu }) do
			if IsValid(part) and (hovered == part or hovered:HasParent(part)) and Recipes.Pickable(part, root) then return part, root end
		end
		return nil
	elseif root == g_ContextMenu then
		-- A desktop widget's window is a child of the C menu (G47).
		local p = hovered
		while IsValid(p) and p ~= root do
			if PP.Openers.DesktopId(p) and Recipes.Pickable(p, p) then return p, p end
			p = p:GetParent()
		end
		return nil
	end
	if root:GetWide() < MIN_W or root:GetTall() < MIN_H or not root:IsMouseInputEnabled() then return nil end
	if Recipes.Refusal(root, root) then return nil end
	-- A bare stock panel that is nobody's window (an empty scroll list an addon left in a corner of the
	-- screen, invisible, was offered as "Window"): the picker's list of windows leaves those out too.
	local sig = Recipes.Signature(root)
	if not (sig.popup or sig.title or sig.class or sig.src) then return nil end
	return root, root
end

-- ── What the wheel offers ───────────────────────────────────

-- panel, then what in it could be a window of its own, outer before inner: what the picker would offer
-- somewhere in it (Recipes.Pickable), shown now, and big enough. A part that covers nearly all of the
-- one it is in stands for it only if it is a page of a tab sheet (as in the picker).
local function partsOf(panel, root)
	local out = { panel }
	local px, py = panel:LocalToScreen(0, 0)
	local pr, pb = px + panel:GetWide(), py + panel:GetTall()
	local function walk(parent, lw, lh, depth)
		if depth > PART_DEPTH then return end
		for _, kid in ipairs(parent:GetChildren()) do
			if #out >= PART_MAX then return end
			local w, h = kid:GetSize()
			if PP.Util.Drawn(kid) and w >= PART_W and h >= PART_H then
				-- Scrolled out of what shows of the window: not something to point at.
				local x, y = kid:LocalToScreen(0, 0)
				if x < pr and y < pb and x + w > px and y + h > py then
					local kw, kh = lw, lh
					-- An area, not one control (a big button, a picture to click): those are the picker's.
					if not HOLDER[kid:GetName()] and not Recipes.ControlName(kid) and Recipes.Pickable(kid, Recipes.RootFor(kid, root))
						and (w * h < lw * lh * SAME or Recipes.SheetTabName(kid)) then
						out[#out + 1] = kid
						kw, kh = w, h
					end
					walk(kid, kw, kh, depth + 1)
				end
			end
		end
	end
	walk(panel, panel:GetWide(), panel:GetTall(), 1)
	return out
end

-- What a click would pin, and the window it belongs to.
function PinButton.Picked()
	local panel = PinButton.parts[PinButton.index]
	if not IsValid(panel) then panel = PinButton.target end
	if not IsValid(panel) or not IsValid(PinButton.root) then return nil end
	if panel == PinButton.target then return panel, PinButton.root end
	return panel, Recipes.RootFor(panel, PinButton.root)
end

-- The card's lines for what a click would pin now.
local function describe()
	local panel, root = PinButton.Picked()
	local lines = {}
	PinButton.lines = lines
	if not IsValid(panel) then return end
	local sig = Recipes.Signature(panel)
	-- The window by what its pin will be called; a part by what is on it, its title or its class.
	lines[1] = PinButton.names[PinButton.index] or Recipes.PartName(panel)
	lines[2] = PP.L(panel ~= root and "picker.size_part" or "picker.size", sig.w, sig.h)
	lines[3] = PP.L(panel ~= root and "picker.click_part" or "picker.click_embed")
	-- The button offers areas; the picker points at anything. Its key, if it has one: a tip of its
	-- own, apart from the card, which is about what a click here would pin.
	local key = Settings.Get("keyPick")
	PinButton.tip = key ~= KEY_NONE and PP.L("pinbutton.picker_key", PP.Util.KeyName(key)) or PP.L("pinbutton.picker_nokey")
	local widest = 0
	-- The choices themselves, under the lines: what says there is a wheel to turn (T.DrawChoices).
	if #PinButton.names > 1 then widest = T.ChoicesSize(PinButton.names, PP.L("picker.wheel")) end
	for i, line in ipairs(lines) do
		surface.SetFont(i == 1 and "DermaDefaultBold" or "DermaDefault")
		widest = math.max(widest, (surface.GetTextSize(line)))
	end
	PinButton.cardW = widest + CARD_PAD * 2
end

function PinButton.Choose()
	local panel, root = PinButton.target, PinButton.root
	PinButton.parts = (IsValid(panel) and IsValid(root)) and partsOf(panel, root) or {}
	PinButton.index = 1
	local names = {}
	for i, part in ipairs(PinButton.parts) do
		if i > 1 then
			names[i] = Recipes.PartName(part)
		elseif part ~= root then
			names[i] = Recipes.Title({ signature = { path = Recipes.Path(root, part) } })
		else
			names[i] = Recipes.Title({ signature = Recipes.Signature(part) })
		end
	end
	PinButton.names = names
	describe()
end

function PinButton.Step(dir)
	local n = #PinButton.parts
	if n < 2 then return end
	-- Past what has gone since the list was made (a page that was closed, a part pinned meanwhile).
	for _ = 1, n do
		PinButton.index = (PinButton.index - 1 + dir) % n + 1
		local panel, root = PinButton.Picked()
		if IsValid(panel) and PinButton.parts[PinButton.index] == panel and PP.Util.Drawn(panel) and Recipes.Pickable(panel, root) then break end
	end
	describe()
end

-- ── Showing and pinning ─────────────────────────────────────

-- Just outside the window's top-right corner, so it covers nothing of the window; inside it, beside the
-- frame's own buttons, when there is no room above (a window at the top of the screen) or for a part,
-- whose surroundings aren't its own.
local function place(button, panel, root)
	local x, y = panel:LocalToScreen(0, 0)
	local w = panel:GetWide()
	local bw, bh = button:GetSize()
	local bx, by = x + w - bw, y - bh - GAP
	if by < 0 or panel ~= root then
		by = y + GAP
		bx = x + w - bw - GAP - (IsValid(panel.btnClose) and FRAME_BUTTONS or 0)
	end
	button:SetPos(math.Clamp(bx, 0, ScrW() - bw), math.Clamp(by, 0, ScrH() - bh))
end

function PinButton.Show(panel, root)
	local button = PinButton.panel
	if not IsValid(button) then
		button = vgui.Create("PinnedPanelsPinButton")
		button:MakePopup()
		button:SetKeyboardInputEnabled(false)
		PinButton.panel = button
	end
	if PinButton.target ~= panel then
		PinButton.target, PinButton.root = panel, root
		PinButton.Choose()
		-- Over the window it is for, which came to the front when it was opened or clicked.
		button:MoveToFront()
	end
	place(button, panel, root)
	button:SetVisible(true)
end

function PinButton.Hide()
	if IsValid(PinButton.panel) then PinButton.panel:SetVisible(false) end
	PinButton.target, PinButton.root = nil, nil
	PinButton.parts, PinButton.names, PinButton.index, PinButton.lines = {}, {}, 1, {}
end

-- Pins what the button is for (the window, or the part the wheel chose), as the picker's click does:
-- whole, or as the part it is, coming back the way the addon knows or was seen (Recipes.Suggest).
function PinButton.Pin()
	local panel, root = PinButton.Picked()
	PinButton.Hide()
	if not IsValid(panel) or not IsValid(root) or not Recipes.Pickable(panel, root) then return nil end
	local info = Recipes.Suggest(panel, root)
	local id = Recipes.Take(panel, root, info.mode, info.recipe)
	if id then notification.AddLegacy(PP.L("adopt.pinned", PP.Layout.Title(PP.Layout.Get(id))), NOTIFY_GENERIC, 6) end
	return id
end

-- While the cursor is on the button, what a click would pin is outlined, as the picker outlines it, with
-- a card under the button saying what it is. Drawn over everything (the window is a popup, and so is
-- whatever lies over it).
hook.Add("DrawOverlay", "PinnedPanels.PinButton", function()
	local button = PinButton.panel
	if not (IsValid(button) and button:IsVisible() and button:IsHovered()) then return end
	local panel = PinButton.Picked()
	if not IsValid(panel) then return end
	local x, y = panel:LocalToScreen(0, 0)
	local w, h = panel:GetSize()
	surface.SetDrawColor(FILL)
	surface.DrawRect(x, y, w, h)
	surface.SetDrawColor(OUTLINE)
	surface.DrawOutlinedRect(x - 2, y - 2, w + 4, h + 4, 2)

	local lines = PinButton.lines
	if #lines == 0 then return end
	local names = PinButton.names
	local header = PP.L("picker.wheel")
	local cw, ch = PinButton.cardW, CARD_PAD * 2 + #lines * LINE_H
	local listH = 0
	if #names > 1 then listH = select(2, T.ChoicesSize(names, header)) + 6 end
	ch = ch + listH
	local bx, by = button:GetPos()
	local cx = math.Clamp(bx + button:GetWide() - cw, 8, ScrW() - cw - 8)
	local cy = by + button:GetTall() + 4
	if cy + ch > ScrH() - 8 then cy = by - ch - 4 end
	draw.RoundedBox(6, cx, cy, cw, ch, T.popupBg)
	surface.SetDrawColor(OUTLINE)
	surface.DrawOutlinedRect(cx, cy, cw, ch, 1)
	for i, line in ipairs(lines) do
		local font = i == 1 and "DermaDefaultBold" or "DermaDefault"
		local tint = i == 1 and T.textBright or (i == 3 and T.textLabel or T.text)
		draw.SimpleText(line, font, cx + CARD_PAD, cy + CARD_PAD + (i - 1) * LINE_H, tint, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
	end
	if #names > 1 then T.DrawChoices(cx + CARD_PAD, cy + CARD_PAD + #lines * LINE_H + 6, cw - CARD_PAD * 2, names, PinButton.index, header) end

	-- The picker's tip, in a box of its own on the far side of the card from the button.
	local tip = PinButton.tip
	if not tip then return end
	surface.SetFont("DermaDefault")
	local tw, th = surface.GetTextSize(tip) + CARD_PAD * 2, LINE_H + 8
	local tx = math.Clamp(cx + cw - tw, 8, ScrW() - tw - 8)
	local ty = cy > by and cy + ch + 6 or cy - th - 6
	draw.RoundedBox(6, tx, ty, tw, th, T.popupBg)
	surface.SetDrawColor(T.popupBorder)
	surface.DrawOutlinedRect(tx, ty, tw, th, 1)
	draw.SimpleText(tip, "DermaDefault", tx + CARD_PAD, ty + th / 2, T.textSubtle, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
end)

-- ── Following the cursor ────────────────────────────────────
-- Ten times a second while a cursor shows: the window under it, by the game's own answer to "what is the
-- cursor on" (which knows what is in front of what). On the button itself, it stays for the window it
-- is for. Not while the picker is open or the game's menu is up.

local nextLook, seenAt, wasDown = 0, 0, false

-- Every click on a panel, told by the game: a quick one is over between two looks at the mouse.
hook.Add("VGUIMousePressed", "PinnedPanels.PinButton", function()
	wasDown = true
end)

local function menuOpen()
	for menu in pairs(PP.Desktop.menus) do
		if IsValid(menu) and menu:IsVisible() then return true end
	end
	return false
end

Input.EachFrame("pinbutton", function()
	local now = RealTime()
	if now < nextLook then return end
	nextLook = now + LOOK
	local button = PinButton.panel
	local shown = IsValid(button) and button:IsVisible()
	-- Not "a cursor shows": the button is itself a panel that shows one, and would keep itself up.
	-- A cursor that is there for something else: cursor mode, a menu, another addon's window.
	if not vgui.CursorVisible() or not Input.Interactive() then
		if shown then PinButton.Hide() end
		return
	end
	local want = Settings.Get("pinButton") and not gui.IsGameUIVisible() and not IsValid(PP.Picker.panel)
	-- A mouse button down: nothing new is looked for (the cursor may be dragging a window over others),
	-- but the button stays, with its window. It used to hide, and so blinked at every click in a menu.
	if want and input.IsMouseDown(MOUSE_LEFT) then
		wasDown = true
		local panel, root = PinButton.target, PinButton.root
		if shown and IsValid(panel) and IsValid(root) and root:IsVisible() and PP.Util.Drawn(panel) then
			seenAt = now
			place(button, panel, root)
		end
		return
	end
	-- A click on its window brought that window to the front, over the button: the button goes back
	-- over it, once no drop-down the click opened is there to be covered.
	if wasDown and not menuOpen() then
		wasDown = false
		if shown then button:MoveToFront() end
	end
	local hovered = want and vgui.GetHoveredPanel()
	local panel, root
	if IsValid(hovered) then
		if shown and hovered == button then
			panel, root = PinButton.target, PinButton.root
			-- Closed, hidden or pinned by other means while the cursor was on its way here.
			if not (IsValid(panel) and IsValid(root) and Recipes.Pickable(panel, root) and PP.Util.Drawn(panel)) then panel = nil end
		else
			panel, root = targetUnder(hovered)
			-- Something that is shown: what the cursor "is on" can be a moment old, and a window that
			-- has just closed is still a panel.
			if IsValid(panel) and not (root:IsVisible() and PP.Util.Drawn(panel)) then panel = nil end
		end
	end
	if IsValid(panel) then
		seenAt = now
		PinButton.Show(panel, root)
	elseif shown and (not want or now - seenAt > LINGER) then
		PinButton.Hide()
	end
end)

hook.Add("PinnedPanelsSettingChanged", "PinnedPanels.PinButton", function(key, value)
	if key == "pinButton" and not value then PinButton.Hide() end
end)
