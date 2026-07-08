-- ── Keyboard Navigation ──────────────────────────────────────────────────────
local IM = PinnedPanels.CursorMode

-- ── Focus Helpers ────────────────────────────────────────────────────────────
local function GetTaskbarEntries()
	return PinnedPanels.GetMinimizedPanels and PinnedPanels.GetMinimizedPanels() or {}
end

local function VisibleTopLevelPins()
	local list = {}
	for id, pin in pairs(PinnedPanels.Pins) do
		if IsValid(pin.frame) and pin.frame:IsVisible() then
			if pin.kind == "group" or not PinnedPanels.GetGroupForPanel(id) then
				list[#list + 1] = { id = id, title = pin.title }
			end
		end
	end
	table.sort(list, function(a, b) return a.title < b.title end)

	-- Append taskbar as virtual entry if it has minimized panels
	local minimized = GetTaskbarEntries()
	local ts = PinnedPanels.Settings.taskbar
	if #minimized > 0 and ts and ts.enabled ~= false then
		list[#list + 1] = { id = "__TASKBAR__", title = "~Taskbar" }
	end

	return list
end

local function FocusedPin()
	return IM.Focused and PinnedPanels.Pins[IM.Focused] or nil
end

function PinnedPanels.IsKeyboardNavEnabled()
	if not IM.Active and not (PinnedPanels.Settings and PinnedPanels.Settings.keyboardNavOutsideCursorMode) then
		return false
	end

	for id, pin in pairs(PinnedPanels.Pins) do
		if IsValid(pin.frame) and pin.frame:IsVisible() then
			local f = FocusedPin()
			if not f or not IsValid(f.frame) or not f.frame:IsVisible() then
				if IM.Focused ~= "__TASKBAR__" then
					IM.Focused = id
				end
			end
			return true
		end
	end

	-- With only minimized panels (no visible ones), the taskbar is keyboard-navigable
	-- but ONLY in cursor mode, so during plain gameplay arrow keys stay free for
	-- movement and the bar doesn't get pinned on screen. We never auto-focus it.
	local minimized = GetTaskbarEntries()
	local ts = PinnedPanels.Settings.taskbar
	if IM.Active and #minimized > 0 and ts and ts.enabled ~= false then
		return true
	end

	return false
end
local NavEnabled = PinnedPanels.IsKeyboardNavEnabled

-- ── Panel & Tab Navigation ───────────────────────────────────────────────────
local function SetFocus(id, dir)
	if IM.NavigatingPanel and id ~= IM.Focused then
		IM.NavigatingPanel = false
		IM.SelectedIndex = nil
	end
	IM.Focused = id

	if id == "__TASKBAR__" then
		local TB = PinnedPanels.Taskbar
		local entries = GetTaskbarEntries()
		if TB then
			if #entries == 0 then
				TB.hoverIndex = nil
			else
				TB.hoverIndex = (dir and dir < 0) and #entries or 1
			end
		end
		IM._taskbarLastInput = CurTime()
		if PinnedPanels.FocusTaskbar then PinnedPanels.FocusTaskbar() end
		return
	end

	if PinnedPanels.UnfocusTaskbar then PinnedPanels.UnfocusTaskbar() end
	local pin = id and PinnedPanels.Pins[id]
	if pin and IsValid(pin.frame) then pin.frame:MoveToFront() end
end

local function CycleFocus(dir)
	-- While the taskbar is focused, step through its entries before leaving it.
	if IM.Focused == "__TASKBAR__" then
		local TB = PinnedPanels.Taskbar
		local entries = GetTaskbarEntries()
		if TB and #entries > 0 then
			local ni = (TB.hoverIndex or 1) + dir
			if ni >= 1 and ni <= #entries then
				TB.hoverIndex = ni
				return
			end
			-- stepped past an end: fall through to move to an adjacent panel
		end
	end

	local list = VisibleTopLevelPins()
	if #list == 0 then IM.Focused = nil return end
	local idx = 1
	for i, e in ipairs(list) do
		if e.id == IM.Focused then idx = i break end
	end
	idx = idx + dir
	if idx < 1 then idx = #list elseif idx > #list then idx = 1 end
	SetFocus(list[idx].id, dir)
end

local function SwitchTab(dir)
	local pin = FocusedPin()
	if not pin or pin.kind ~= "group" or not IsValid(pin.sheet) then return end
	local items = pin.sheet:GetItems()
	if #items <= 1 then return end
	local active = pin.sheet:GetActiveTab()
	local idx = 1
	for i, item in ipairs(items) do
		if item.Tab == active then idx = i break end
	end
	idx = idx + dir
	if idx < 1 then idx = #items elseif idx > #items then idx = 1 end
	pin.sheet:SetActiveTab(items[idx].Tab)
end

-- ── Panel Actions ────────────────────────────────────────────────────────────
local function EquipFocusedTool()
	if not IM.Focused then return end

	-- On the taskbar, "equip/enter" restores the selected minimized panel.
	if IM.Focused == "__TASKBAR__" then
		local TB = PinnedPanels.Taskbar
		local entries = GetTaskbarEntries()
		local sel = TB and TB.hoverIndex
		if sel and entries[sel] then
			local id = entries[sel].id
			PinnedPanels.RestoreFromTaskbar(id)
			local remaining = GetTaskbarEntries()
			if #remaining == 0 then
				SetFocus(id)                        -- follow the panel we just restored
			else
				TB.hoverIndex = math.Clamp(sel, 1, #remaining)
			end
		end
		return
	end

	local toolClass = PinnedPanels.GetPinTool(IM.Focused)
	if not toolClass then return end
	PinnedPanels.EquipToolgun(toolClass)
	PinnedPanels.CursorMode.Disable()
end

local function ToggleFocusedHidden()
	local pin = FocusedPin()
	if not pin or not IsValid(pin.frame) then return end
	pin.frame:SetVisible(not pin.frame:IsVisible())
	if not pin.frame:IsVisible() then CycleFocus(1) end
end

local function BringFocusedFront()
	local pin = FocusedPin()
	if pin and IsValid(pin.frame) then
		pin.frame:SetVisible(true)
		pin.frame:MoveToFront()
	end
end

-- Header-button actions available from the keyboard for the focused panel.
local function MinimizeFocused()
	if IM.Focused and IM.Focused ~= "__TASKBAR__" then
		PinnedPanels.MinimizeToTaskbar(IM.Focused)
		CycleFocus(1)   -- move focus off the panel we just hid
	end
end

local function MaximizeFocused()
	if IM.Focused and IM.Focused ~= "__TASKBAR__" and PinnedPanels.ToggleMaximizePanel then
		PinnedPanels.ToggleMaximizePanel(IM.Focused)
	end
end

local function UnpinFocused()
	if IM.Focused and IM.Focused ~= "__TASKBAR__" then
		local target = IM.Focused
		CycleFocus(1)   -- pick a neighbour first so focus survives removal
		PinnedPanels.Unpin(target)
	end
end

-- ── Interactive Element Scan (cached) ────────────────────────────────────────
local SKIP_CLASSES = {
	DLabel = true, Label = true, DImage = true, Image = true,
	DDivider = true, Divider = true, DExpandButton = true,
	DVScrollBar = true, DHScrollBar = true,
}

local CONTAINER_CLASSES = {
	ControlPanel = true, DForm = true, DCollapsibleCategory = true, DScrollPanel = true,
	DPropertySheet = true, DFrame = true, DCategoryList = true, DTree = true,
	DTree_Node = true, DListLayout = true, DIconLayout = true, DTileLayout = true,
	ContentContainer = true, SpawnmenuContentPanel = true, DMenu = true, DMenuBar = true,
}

local BASE_OMP = (vgui.GetControlTable and vgui.GetControlTable("DPanel") or {}).OnMousePressed

local function HasCustomInteraction(p)
	if not p:IsMouseInputEnabled() then return false end
	if isfunction(p.DoClick) or isfunction(p.Toggle) then return true end
	if isfunction(p.SetValue) and isfunction(p.GetValue) then return true end
	local omp = p.OnMousePressed
	return isfunction(omp) and omp ~= BASE_OMP
end

function PinnedPanels.GetInteractiveElements(panel)
	local list = {}
	if not IsValid(panel) then return list end

	local function scan(p, depth)
		if not IsValid(p) or depth > 20 or p._pp_skipNav or not p:IsVisible() then return 0 end
		local class = p.ClassName or p:GetClassName()
		-- Scrollbars/grips are drag-only, not click targets — skip them and their parts.
		if SKIP_CLASSES[class] or class:find("ScrollBar") or class:find("Grip") then return 0 end

		if class:find("Slider") or class:find("CheckBox") or class == "DButton"
			or class == "DImageButton" or class == "DComboBox" or class == "DTextEntry"
			or class == "DNumSlider" or class:find("Color") or class == "DTree_Node_Button" then
			list[#list + 1] = p
			return 1
		end

		local isCustom = not CONTAINER_CLASSES[class] and HasCustomInteraction(p)

		local interactiveChildren = 0
		for _, child in ipairs(p:GetChildren()) do
			interactiveChildren = interactiveChildren + scan(child, depth + 1)
		end

		if isCustom and interactiveChildren == 0 then
			list[#list + 1] = p
			return 1
		end

		return interactiveChildren
	end

	scan(panel, 0)

	-- Drop degenerate (zero/near-zero size) controls that make useless stops.
	-- (We keep scrolled-off elements so navigation can still scroll into them.)
	local result = {}
	for _, el in ipairs(list) do
		if IsValid(el) then
			local ew, eh = el:GetSize()
			if ew > 4 and eh > 4 then
				result[#result + 1] = el
			end
		end
	end
	return result
end

local navCache = { frame = nil, expire = 0, list = {} }

function PinnedPanels.GetNavElements()
	local pin = FocusedPin()
	if not pin or not IsValid(pin.frame) then
		navCache.frame, navCache.list = nil, {}
		return navCache.list
	end
	if navCache.frame ~= pin.frame or CurTime() >= navCache.expire then
		navCache.frame  = pin.frame
		navCache.expire = CurTime() + 0.15
		navCache.list   = PinnedPanels.GetInteractiveElements(pin.frame)
	end
	return navCache.list
end
local GetNavElements = PinnedPanels.GetNavElements

-- ── Key Repeat ───────────────────────────────────────────────────────────────
local KEY_REPEAT_DELAY    = 0.35
local KEY_REPEAT_INTERVAL = 0.055
local keyRepeat = {}

local function StartRepeat(key) keyRepeat[key] = { start = CurTime(), last = 0, repeating = false } end
local function StopRepeat(key) keyRepeat[key] = nil end
local function StopAllRepeats() for k in pairs(keyRepeat) do keyRepeat[k] = nil end end

local function ShouldRepeat(key)
	local t = keyRepeat[key]
	if not t then return false end
	local now = CurTime()
	if not t.repeating then
		if now - t.start >= KEY_REPEAT_DELAY then
			t.repeating, t.last = true, now
			return true
		end
		return false
	end
	if now - t.last >= KEY_REPEAT_INTERVAL then
		t.last = now
		return true
	end
	return false
end

-- ── Keybinds ─────────────────────────────────────────────────────────────────
local NAV_KEYS = { [KEY_UP] = true, [KEY_DOWN] = true, [KEY_LEFT] = true, [KEY_RIGHT] = true,
                   [KEY_ENTER] = true, [KEY_ESCAPE] = true, [KEY_BACKSPACE] = true,
                   [KEY_LSHIFT] = true, [KEY_RSHIFT] = true }
local navKeyDown = {}

local function ExitContentNav()
	IM.NavigatingPanel = false
	IM.SelectedIndex = nil
	StopAllRepeats()
	for k in pairs(navKeyDown) do navKeyDown[k] = false end
end

PinnedPanels.ExitContentNav = ExitContentNav

-- Leaving cursor mode always drops the intense content-nav ("red glow") mode,
-- giving the cursor-mode key a guaranteed way out of it. Only act on the actual
-- on→off transition (this hook also fires on unrelated state changes).
local _prevInteractive = false
hook.Add("PinnedPanels_CursorModeChanged", "PinnedPanels_ExitNavOnCursorOff", function(interactive)
	if _prevInteractive and not interactive and IM.NavigatingPanel then
		ExitContentNav()
	end
	_prevInteractive = interactive
end)

local function EnterContentNav()
	local pin = FocusedPin()
	if IM.NavigatingPanel or not pin or not IsValid(pin.frame) then return end
	IM.NavigatingPanel = true
	IM.NavFocusIndex = 1
	IM.SelectedIndex = nil
	IM.LastNavPanel = IM.Focused
	StopAllRepeats()
	for k in pairs(NAV_KEYS) do
		navKeyDown[k] = input.IsKeyDown(k)
		if navKeyDown[k] then StartRepeat(k) end
	end
end

-- ── Context-Menu Keyboard Navigation ───────────────────────────────────────

local C = PinnedPanels.C

-- Build a custom keyboard-navigable menu panel from a list of extracted
-- options. This replaces GMod's DMenu entirely so we get full control over
-- highlighting, navigation and activation without needing cursor focus.
--
-- Each entry in `items`: { text=, icon=, callback=, enabled= }
local function CreateKeyboardMenu(items, x, y)
	if #items == 0 then return nil end

	local ROW_H   = 22
	local ICON_SZ = 16
	local PAD     = 6
	local FONT    = "DermaDefault"
	local MIN_W   = 160

	-- Measure required width.
	surface.SetFont(FONT)
	local maxW = MIN_W
	for _, it in ipairs(items) do
		local tw = select(1, surface.GetTextSize(it.text or ""))
		maxW = math.max(maxW, tw + ICON_SZ + PAD * 4 + 8)
	end

	local panelW = maxW + PAD * 2
	local panelH = #items * ROW_H + PAD * 2

	-- Clamp to screen.
	local sw, sh = ScrW(), ScrH()
	x = math.Clamp(x, 0, sw - panelW)
	y = math.Clamp(y, 0, sh - panelH)

	local pnl = vgui.Create("DPanel")
	pnl:SetPos(x, y)
	pnl:SetSize(panelW, panelH)
	pnl:SetDrawOnTop(true)
	pnl:MakePopup()
	pnl:SetKeyboardInputEnabled(false)
	pnl:SetMouseInputEnabled(false)
	pnl.Items     = items
	pnl.SelIndex  = 1
	pnl._wasDown  = {
		[KEY_UP]        = input.IsKeyDown(KEY_UP),
		[KEY_DOWN]      = input.IsKeyDown(KEY_DOWN),
		[KEY_ENTER]     = input.IsKeyDown(KEY_ENTER),
		[KEY_ESCAPE]    = input.IsKeyDown(KEY_ESCAPE),
		[KEY_BACKSPACE] = input.IsKeyDown(KEY_BACKSPACE),
	}

	-- Preload icon materials.
	for _, it in ipairs(items) do
		if it.icon and it.icon ~= "" then
			it._mat = Material(it.icon, "smooth mips")
		end
	end

	function pnl:Paint(w, h)
		-- Background
		draw.RoundedBox(4, 0, 0, w, h, C.bgPopup)
		surface.SetDrawColor(C.bgHeaderLine)
		surface.DrawOutlinedRect(0, 0, w, h, 1)

		surface.SetFont(FONT)
		for i, it in ipairs(self.Items) do
			local ry = PAD + (i - 1) * ROW_H

			-- Highlight
			if i == self.SelIndex then
				draw.RoundedBox(3, PAD - 2, ry, w - PAD * 2 + 4, ROW_H, C.accent)
			end

			-- Icon
			if it._mat and not it._mat:IsError() then
				surface.SetDrawColor(255, 255, 255, (it.enabled == false) and 80 or 255)
				surface.SetMaterial(it._mat)
				surface.DrawTexturedRect(PAD + 2, ry + (ROW_H - ICON_SZ) / 2, ICON_SZ, ICON_SZ)
			end

			-- Text
			local textColor = (it.enabled == false) and C.textMuted
				or (i == self.SelIndex and C.textBright or C.textLight)
			draw.SimpleText(it.text or "", FONT, PAD + ICON_SZ + PAD + 4, ry + ROW_H / 2,
				textColor, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		end
	end

	return pnl
end

-- Snapshot existing DMenus, call triggerFn (which is expected to open a
-- DermaMenu), then find the newly created DMenu, extract its options,
-- remove it, and return the extracted items.
local function CaptureAndExtractMenu(triggerFn)
	local captured = nil
	
	-- Intercept DermaMenu and vgui.Create directly to reliably catch the menu.
	local _origDermaMenu = DermaMenu
	local _origCreate = vgui.Create

	DermaMenu = function(bDeleteSelf, parent)
		local m = _origDermaMenu(bDeleteSelf, parent)
		if not IsValid(captured) then captured = m end
		return m
	end

	vgui.Create = function(class, parent, name)
		local m = _origCreate(class, parent, name)
		if (class == "DMenu" or class == "DermaMenu") and not IsValid(captured) then
			captured = m
		end
		return m
	end

	-- Call the function that opens the menu.
	local ok, err = pcall(triggerFn)

	-- Restore globals immediately.
	DermaMenu = _origDermaMenu
	vgui.Create = _origCreate

	if not ok then
		ErrorNoHalt("[PinnedPanels] Context menu trigger error: " .. tostring(err) .. "\n")
	end

	if not IsValid(captured) then return {} end

	-- Extract options from the captured DMenu.
	-- The DMenu internal hierarchy varies across GMod versions, so we
	-- recursively walk ALL descendants to find DMenuOption panels.
	local items = {}
	local function walk(parent)
		for _, child in ipairs(parent:GetChildren()) do
			if IsValid(child) then
				local cls = child.ClassName or child:GetClassName()
				if cls == "DMenuOption" or cls == "DMenuOptionCVar" then
					local text = child:GetText() or ""
					local icon = ""
					if child.m_Image and IsValid(child.m_Image) then
						icon = child.m_Image:GetImage() or ""
					end
					local enabled = child:IsEnabled()
					local cb = child.DoClick
					if text ~= "" then
						items[#items + 1] = {
							text     = text,
							icon     = icon,
							callback = cb,
							enabled  = enabled,
						}
					end
				end
				walk(child)
			end
		end
	end
	walk(captured)

	-- Kill the real DMenu immediately so it never shows on screen.
	-- Also close any other derma menus and undo the cursor activation
	-- that DMenu:MakePopup() causes.
	captured:Remove()
	if CloseDermaMenus then CloseDermaMenus() end
	gui.EnableScreenClicker(PinnedPanels.CursorMode.Active or false)

	return items
end

local function ShowKeyboardMenu(items, x, y)
	if not items or #items == 0 then return end
	if IsValid(IM.ActiveMenu) then IM.ActiveMenu:Remove() end
	IM.ActiveMenu = CreateKeyboardMenu(items, x, y)
end

-- Open the pin's context menu for the focused pin (blue glow / Shift+Enter
-- from panel level), build a keyboard-navigable version of it.
local function OpenContextMenuForFocused()
	local id = IM.Focused
	if not id or id == "__TASKBAR__" then return end
	local pin = PinnedPanels.Pins[id]
	if not pin or not IsValid(pin.frame) then return end

	local fx, fy = pin.frame:LocalToScreen(0, 0)
	local fw = pin.frame:GetWide()
	local posX, posY = fx + fw / 2, fy + 16

	local items = CaptureAndExtractMenu(function()
		local _mx, _my = gui.MouseX, gui.MouseY
		gui.MouseX = function() return posX end
		gui.MouseY = function() return posY end
		PinnedPanels.OpenContextMenu(id, pin.frame)
		gui.MouseX, gui.MouseY = _mx, _my
	end)

	ShowKeyboardMenu(items, posX, posY)
end

-- Open the element's own context menu (red glow / Shift+Enter from content
-- nav), e.g. SpawnIcon's "Copy to clipboard / Spawn using toolgun" menu.
-- The nav system may pick a child panel (like a Label inside ContentIcon),
-- so we walk up the parent chain until we find a panel whose right-click
-- actually creates a DMenu.
local function OpenElementContextMenu(el)
	if not IsValid(el) then return end

	local ex, ey = el:LocalToScreen(0, 0)
	local ew, eh = el:GetSize()
	local posX, posY = ex + ew / 2, ey + eh / 2

	-- Try the element itself, then walk up to parents (max 10 levels).
	local target = el
	local items = {}
	for attempt = 1, 10 do
		if not IsValid(target) then break end

		-- The methods that might trigger a context menu on this panel.
		local methodsToTry = {
			"OpenGenericSpawnmenuRightClickMenu",
			"OpenMenu",
			"DoRightClick",
			"Mouse" -- Special case for OnMousePressed/Released
		}

		for _, method in ipairs(methodsToTry) do
			items = CaptureAndExtractMenu(function()
				local _mx, _my = gui.MouseX, gui.MouseY
				gui.MouseX = function() return posX end
				gui.MouseY = function() return posY end

				if method == "Mouse" then
					if isfunction(target.OnMousePressed) then
						target:OnMousePressed(MOUSE_RIGHT)
						if isfunction(target.OnMouseReleased) then
							target:OnMouseReleased(MOUSE_RIGHT)
						end
					end
				else
					if isfunction(target[method]) then
						target[method](target)
					end
				end

				gui.MouseX, gui.MouseY = _mx, _my
			end)

			if #items > 0 then break end
		end

		if #items > 0 then break end

		target = target:GetParent()
	end

	ShowKeyboardMenu(items, posX, posY)
end

-- Keyboard handler that drives our custom PP_KeyboardMenu.
local function HandleMenuNav()
	if not IsValid(IM.ActiveMenu) then
		IM.ActiveMenu = nil
		return
	end

	local pnl   = IM.ActiveMenu
	local items = pnl.Items
	local n     = #items
	if n == 0 then return end
	pnl.SelIndex = math.Clamp(pnl.SelIndex or 1, 1, n)

	local upNow    = input.IsKeyDown(KEY_UP)
	local downNow  = input.IsKeyDown(KEY_DOWN)
	local enterNow = input.IsKeyDown(KEY_ENTER)
	local escNow   = input.IsKeyDown(KEY_ESCAPE) or input.IsKeyDown(KEY_BACKSPACE)
	local wd       = pnl._wasDown

	local function step(dir)
		local tried = 0
		repeat
			pnl.SelIndex = pnl.SelIndex + dir
			if pnl.SelIndex < 1 then pnl.SelIndex = n
			elseif pnl.SelIndex > n then pnl.SelIndex = 1 end
			tried = tried + 1
		until (items[pnl.SelIndex] and items[pnl.SelIndex].enabled ~= false) or tried >= n
	end

	if upNow and not wd[KEY_UP] then
		step(-1)
	elseif downNow and not wd[KEY_DOWN] then
		step(1)
	elseif enterNow and not wd[KEY_ENTER] then
		local it = items[pnl.SelIndex]
		if it and it.enabled ~= false and isfunction(it.callback) then
			it.callback()
		end
		pnl:Remove()
		IM.ActiveMenu = nil
		return
	elseif escNow and not wd[KEY_ESCAPE] and not wd[KEY_BACKSPACE] then
		pnl:Remove()
		IM.ActiveMenu = nil
		return
	end

	wd[KEY_UP]        = upNow
	wd[KEY_DOWN]      = downNow
	wd[KEY_ENTER]     = enterNow
	wd[KEY_ESCAPE]    = escNow
	wd[KEY_BACKSPACE] = input.IsKeyDown(KEY_BACKSPACE)
end

local BINDS = {
	{ id = "focus_next",  name = "Focus Next Panel",        default = KEY_RIGHT,    action = function() CycleFocus(1) end },
	{ id = "focus_prev",  name = "Focus Previous Panel",    default = KEY_LEFT,     action = function() CycleFocus(-1) end },
	{ id = "tab_next",    name = "Next Tab (Group)",        default = KEY_RBRACKET, action = function() SwitchTab(1) end },
	{ id = "tab_prev",    name = "Previous Tab (Group)",    default = KEY_LBRACKET, action = function() SwitchTab(-1) end },
	{ id = "enter_nav",   name = "Enter Panel Content Nav", default = KEY_DOWN,     action = EnterContentNav },
	{ id = "equip_tool",  name = "Equip Focused Tool",      default = KEY_ENTER,    action = EquipFocusedTool },
	{ id = "toggle_hide", name = "Hide / Show Focused",     default = KEY_NONE,     action = ToggleFocusedHidden },
	{ id = "bring_front", name = "Bring Focused To Front",  default = KEY_NONE,     action = BringFocusedFront },
	{ id = "minimize_focused", name = "Minimize Focused (Taskbar)",  default = KEY_NONE, action = MinimizeFocused },
	{ id = "maximize_focused", name = "Maximize Focused (Fill Screen)", default = KEY_NONE, action = MaximizeFocused },
	{ id = "unpin_focused",    name = "Unpin Focused",              default = KEY_NONE, action = UnpinFocused },
}
PinnedPanels.Keybinds = BINDS

local byId = {}
for _, b in ipairs(BINDS) do
	byId[b.id] = b
	b.convar = "pp_key_" .. b.id
	local cv = CreateClientConVar(b.convar, tostring(b.default), true, false, "PinnedPanels: " .. b.name)
	b.key = tonumber(cv:GetString()) or b.default
	b.wasDown = false
	cvars.AddChangeCallback(b.convar, function(_, _, new) b.key = tonumber(new) or KEY_NONE end, "PinnedPanels_KeyNav")
end

-- ── Content Navigation ───────────────────────────────────────────────────────
local function ScrollIntoView(el)
	if not IsValid(el) then return end
	local p = el:GetParent()
	while IsValid(p) do
		if p.GetVBar then
			local vbar = p:GetVBar()
			if IsValid(vbar) then
				local _, ey = el:LocalToScreen(0, 0)
				local _, py = p:LocalToScreen(0, 0)
				local eh, ph = el:GetTall(), p:GetTall()
				if ey < py then
					vbar:SetScroll(vbar:GetScroll() + (ey - py) - 20)
				elseif ey + eh > py + ph then
					vbar:SetScroll(vbar:GetScroll() + (ey + eh - (py + ph)) + 20)
				end
			end
		end
		p = p:GetParent()
	end
end

local function AdjustValue(el, key)
	local cls = el.ClassName or el:GetClassName()
	local dir = (key == KEY_RIGHT) and 1 or -1
	if cls:find("Slider") then
		local mn, mx = el:GetMin(), el:GetMax()
		el:SetValue(math.Clamp(el:GetValue() + (mx - mn) / 30 * dir, mn, mx))
		if el.OnValueChanged then el:OnValueChanged(el:GetValue()) end
	elseif cls:find("CheckBox") then
		local v = (key == KEY_RIGHT)
		if el.SetValue then el:SetValue(v) elseif el.SetChecked then el:SetChecked(v) end
	elseif cls == "DComboBox" and el.ChooseOptionID and el.Choices then
		local n = #el.Choices
		if n > 0 then
			local id = (el:GetSelectedID() or 1) + dir
			if id < 1 then id = n elseif id > n then id = 1 end
			el:ChooseOptionID(id)
		end
	end
end

local function ActivateElement(el)
	if IM.SelectedIndex then IM.SelectedIndex = nil return end
	local cls = el.ClassName or el:GetClassName()
	IM.SelectedIndex = IM.NavFocusIndex

	local keepSelected = false

	if cls:find("Slider") or cls == "DComboBox" then
		keepSelected = true
	elseif cls == "DTextEntry" then
		-- The wrapper frame keeps keyboard input off by default; enable it first so
		-- the text entry can actually receive focus and typed characters.
		local pin = FocusedPin()
		if pin and IsValid(pin.frame) then
			pin.frame:SetKeyboardInputEnabled(true)
		end
		el:SetKeyboardInputEnabled(true)
		el:RequestFocus()
		IM.NavigatingPanel = false
	elseif cls == "DTree_Node_Button" then
		local p = el:GetParent()
		if IsValid(p) and p.InternalDoClick then p:InternalDoClick()
		elseif isfunction(el.DoClick) then el:DoClick() end
	elseif cls:find("CheckBox") then
		if el.Toggle then el:Toggle() elseif el.SetValue then el:SetValue(not el:GetChecked()) end
	elseif isfunction(el.DoClick) then
		el:DoClick()
	elseif isfunction(el.Toggle) then
		el:Toggle()
	elseif isfunction(el.OnMousePressed) then
		el:OnMousePressed(MOUSE_LEFT)
		if isfunction(el.OnMouseReleased) then el:OnMouseReleased(MOUSE_LEFT) end
	end

	if not keepSelected then
		IM.SelectedIndex = nil
	end
end

local function SpatialMove(elements, focusEl, key)
	local cls = focusEl.ClassName or focusEl:GetClassName()
	if cls == "DTree_Node_Button" then
		local p = focusEl:GetParent()
		if IsValid(p) and (p.ClassName == "DTree_Node" or p:GetClassName() == "DTree_Node") then
			if key == KEY_RIGHT and not p:GetExpanded() then p:SetExpanded(true) return end
			if key == KEY_LEFT and p:GetExpanded() then p:SetExpanded(false) return end
		end
	end

	local cx, cy = focusEl:LocalToScreen(0, 0)
	local best, bestIdx = math.huge, nil
	for i, el in ipairs(elements) do
		if el ~= focusEl and IsValid(el) then
			local ox, oy = el:LocalToScreen(0, 0)
			local dx, dy = ox - cx, oy - cy
			local valid, score = false, 0
			if key == KEY_LEFT and dx < -5 then valid, score = true, math.abs(dx) + math.abs(dy) * 4
			elseif key == KEY_RIGHT and dx > 5 then valid, score = true, math.abs(dx) + math.abs(dy) * 4
			elseif key == KEY_UP and dy < -5 then valid, score = true, math.abs(dy) + math.abs(dx) * 4
			elseif key == KEY_DOWN and dy > 5 then valid, score = true, math.abs(dy) + math.abs(dx) * 4 end
			if valid and score < best then best, bestIdx = score, i end
		end
	end

	if bestIdx then
		IM.NavFocusIndex = bestIdx
	elseif key == KEY_DOWN and IM.NavFocusIndex < #elements then
		IM.NavFocusIndex = IM.NavFocusIndex + 1
	elseif key == KEY_UP then
		if IM.NavFocusIndex > 1 then
			IM.NavFocusIndex = IM.NavFocusIndex - 1
		else
			ExitContentNav()
		end
	end
end

local function HandleContentNav()
	local pin = FocusedPin()
	if not pin or not IsValid(pin.frame) or IM.Focused ~= IM.LastNavPanel then
		ExitContentNav()
		return
	end

	local elements = GetNavElements()
	IM.NavFocusIndex = (#elements == 0) and 1 or math.Clamp(IM.NavFocusIndex or 1, 1, #elements)

	local function focusedEl()
		return (#elements > 0 and IM.NavFocusIndex <= #elements) and elements[IM.NavFocusIndex] or nil
	end

	local selectedEl = IM.SelectedIndex and elements[IM.SelectedIndex] or nil
	local oldIndex = IM.NavFocusIndex

	for key in pairs(NAV_KEYS) do
		local down = input.IsKeyDown(key)
		local wasDown = navKeyDown[key] or false

		if key == KEY_ESCAPE or key == KEY_BACKSPACE then
			-- Backspace is the reliable exit (Esc also opens the game menu).
			if down and not wasDown then
				if IM.SelectedIndex then IM.SelectedIndex = nil else ExitContentNav() end
			end
		elseif key == KEY_ENTER then
			if down and not wasDown then
				local shiftHeld = input.IsKeyDown(KEY_LSHIFT) or input.IsKeyDown(KEY_RSHIFT)
				if shiftHeld then
					-- Shift+Enter in content-nav: right-click the highlighted element
					-- to open *its* context menu (e.g. spawnicon → Copy / Spawn…).
					local el = focusedEl()
					if el then OpenElementContextMenu(el) end
				else
					local el = focusedEl()
					if el then ActivateElement(el) end
				end
			end
		elseif down then
			if not wasDown then StartRepeat(key) end
			if not wasDown or ShouldRepeat(key) then
				if IM.SelectedIndex and IsValid(selectedEl) then
					if key == KEY_LEFT or key == KEY_RIGHT then
						AdjustValue(selectedEl, key)
					else
						IM.SelectedIndex = nil
					end
				else
					local fe = focusedEl()
					if IsValid(fe) then
						SpatialMove(elements, fe, key)
					elseif key == KEY_DOWN and IM.NavFocusIndex < #elements then
						IM.NavFocusIndex = IM.NavFocusIndex + 1
					elseif key == KEY_UP and IM.NavFocusIndex > 1 then
						IM.NavFocusIndex = IM.NavFocusIndex - 1
					end
				end
			end
		else
			StopRepeat(key)
		end

		navKeyDown[key] = down
	end

	if IM.NavFocusIndex ~= oldIndex then
		ScrollIntoView(focusedEl())
	end
end

-- ── Global Binds ─────────────────────────────────────────────────────────────
local function HandleGlobalBinds(allowFire)
	local shiftHeld = input.IsKeyDown(KEY_LSHIFT) or input.IsKeyDown(KEY_RSHIFT)
	for _, b in ipairs(BINDS) do
		local k = b.key
		if k and k ~= KEY_NONE then
			local down = input.IsKeyDown(k)
			if allowFire and down and not b.wasDown then
				-- Shift+Enter on the equip_tool bind → open context menu instead.
				if b.id == "equip_tool" and shiftHeld then
					OpenContextMenuForFocused()
				else
					b.action()
				end
			end
			b.wasDown = down
		else
			b.wasDown = false
		end
	end
end

-- ── Taskbar Keyboard Nav Handoff ───────────────────────────────────────────────

hook.Add("Think", "PinnedPanels_KeyNav", function()
	if IsValid(vgui.GetKeyboardFocus()) then return end

	-- If a context menu is open via keyboard, handle it exclusively.
	if IM.ActiveMenu then
		HandleMenuNav()
		return
	end

	if not NavEnabled() then
		if IM.NavigatingPanel then ExitContentNav() end
		if PinnedPanels.UnfocusTaskbar then PinnedPanels.UnfocusTaskbar() end
		return
	end

	if IM.Focused == "__TASKBAR__" then
		-- Taskbar participates in the normal bind system (CycleFocus / EquipFocusedTool are taskbar-aware).
		local TB = PinnedPanels.Taskbar
		if TB and not TB.kbFocused and PinnedPanels.FocusTaskbar then
			PinnedPanels.FocusTaskbar()
		end

		-- Keep the bar up only while actively used; release it on Escape, or after
		-- a few idle seconds when not in cursor mode, so it doesn't stay stuck.
		if input.IsKeyDown(KEY_LEFT) or input.IsKeyDown(KEY_RIGHT)
			or input.IsKeyDown(KEY_UP) or input.IsKeyDown(KEY_DOWN) or input.IsKeyDown(KEY_ENTER) then
			IM._taskbarLastInput = CurTime()
		end
		local idle = IM._taskbarLastInput and (CurTime() - IM._taskbarLastInput > 5)
		if input.IsKeyDown(KEY_ESCAPE) or (idle and not PinnedPanels.PanelsInteractive()) then
			if PinnedPanels.UnfocusTaskbar then PinnedPanels.UnfocusTaskbar() end
			return
		end

		HandleGlobalBinds(true)
	elseif IM.NavigatingPanel then
		if PinnedPanels.UnfocusTaskbar then PinnedPanels.UnfocusTaskbar() end
		HandleContentNav()
		HandleGlobalBinds(false)
	else
		if PinnedPanels.UnfocusTaskbar then PinnedPanels.UnfocusTaskbar() end
		HandleGlobalBinds(true)
	end
end)

-- ── Input Suppression ────────────────────────────────────────────────────────
local bindToButton = {
	["+attack"]  = IN_ATTACK,   ["+attack2"]   = IN_ATTACK2,
	["+jump"]    = IN_JUMP,     ["+duck"]      = IN_DUCK,
	["+forward"] = IN_FORWARD,  ["+back"]      = IN_BACK,
	["+use"]     = IN_USE,      ["+moveleft"]  = IN_MOVELEFT,
	["+moveright"] = IN_MOVERIGHT, ["+left"]   = IN_LEFT,
	["+right"]   = IN_RIGHT,    ["+reload"]    = IN_RELOAD,
	["+speed"]   = IN_SPEED,    ["+walk"]      = IN_WALK,
}

local function IsCapturedKey(k)
	if not k or k == KEY_NONE then return false end
	if IM.ActiveMenu and (k == KEY_UP or k == KEY_DOWN or k == KEY_ENTER or k == KEY_ESCAPE or k == KEY_BACKSPACE) then return true end
	if IM.NavigatingPanel and NAV_KEYS[k] then return true end
	for _, b in ipairs(BINDS) do
		if b.key == k then return true end
	end
	return false
end

hook.Add("CreateMove", "PinnedPanels_KeyNavSuppressMove", function(cmd)
	if not NavEnabled() or IsValid(vgui.GetKeyboardFocus()) then return end

	local buttons = cmd:GetButtons()
	local function suppress(k)
		if not IsCapturedKey(k) or not input.IsKeyDown(k) then return end
		local bind = input.LookupKeyBinding(k)
		if bind then
			local btn = bindToButton[bind]
			if btn then buttons = bit.band(buttons, bit.bnot(btn)) end
			if bind == "+forward" or bind == "+back" then cmd:SetForwardMove(0) end
			if bind == "+moveleft" or bind == "+moveright" then cmd:SetSideMove(0) end
		end
		if k == KEY_LEFT then buttons = bit.band(buttons, bit.bnot(IN_LEFT), bit.bnot(IN_MOVELEFT)) cmd:SetSideMove(0)
		elseif k == KEY_RIGHT then buttons = bit.band(buttons, bit.bnot(IN_RIGHT), bit.bnot(IN_MOVERIGHT)) cmd:SetSideMove(0)
		elseif k == KEY_UP then buttons = bit.band(buttons, bit.bnot(IN_FORWARD)) cmd:SetForwardMove(0)
		elseif k == KEY_DOWN then buttons = bit.band(buttons, bit.bnot(IN_BACK)) cmd:SetForwardMove(0) end
	end

	for _, b in ipairs(BINDS) do suppress(b.key) end
	if IM.NavigatingPanel then for k in pairs(NAV_KEYS) do suppress(k) end end

	cmd:SetButtons(buttons)
end)

hook.Add("PlayerBindPress", "PinnedPanels_KeyNavSuppressBind", function(ply, bind, pressed, code)
	if not NavEnabled() or IsValid(vgui.GetKeyboardFocus()) then return end
	if code and IsCapturedKey(code) then return true end
end)

hook.Add("PinnedPanels_CursorModeChanged", "PinnedPanels_KeyNavFocus", function()
	if not IM.Active then return end
	local cur = FocusedPin()
	if not cur or not IsValid(cur.frame) or not cur.frame:IsVisible() then
		local list = VisibleTopLevelPins()
		IM.Focused = list[1] and list[1].id or nil
	end
end)

-- ── Public API ───────────────────────────────────────────────────────────────
function PinnedPanels.GetBind(id)
	local b = byId[id]
	return b and b.key or KEY_NONE
end

function PinnedPanels.SetBind(id, keycode)
	local b = byId[id]
	if not b then return end
	b.key = keycode or KEY_NONE
	RunConsoleCommand(b.convar, tostring(b.key))
end

function PinnedPanels.ResetBind(id)
	local b = byId[id]
	if not b then return end
	b.key = b.default
	RunConsoleCommand(b.convar, tostring(b.default))
end

function PinnedPanels.ResetAllBinds()
	for _, b in ipairs(BINDS) do
		b.key = b.default
		RunConsoleCommand(b.convar, tostring(b.default))
	end
end

-- Diagnostic: list what the keyboard nav treats as clickable in the focused panel.
concommand.Add("pp_navdump", function()
	local els = PinnedPanels.GetNavElements and PinnedPanels.GetNavElements() or {}
	print(string.format("[PinnedPanels] %d nav element(s) in focused panel:", #els))
	for i, el in ipairs(els) do
		if IsValid(el) then
			local w, h = el:GetSize()
			print(string.format("  %2d: %-24s %dx%d", i, el:GetClassName(), w, h))
		end
	end
end, nil, "List the keyboard-nav targets of the focused pinned panel")
