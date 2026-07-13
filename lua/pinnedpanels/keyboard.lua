-- ── Keyboard Navigation ──────────────────────────────────────────────────────
local IM = PinnedPanels.CursorMode

-- ── Focus Helpers ────────────────────────────────────────────────────────────
local function VisibleTopLevelPins()
	local list = {}
	local minimized = PinnedPanels.GetMinimizedPanels()

	for id, pin in pairs(PinnedPanels.Pins) do
		if IsValid(pin.frame) and pin.frame:IsVisible() then
			if pin.kind == "group" or not PinnedPanels.GetGroupForPanel(id) then
				list[#list + 1] = { id = id, title = pin.title }
			end
		end
	end
	table.sort(list, function(a, b) return a.title < b.title end)

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
			local f = IM.Focused and PinnedPanels.Pins[IM.Focused]
			if not f or not IsValid(f.frame) or not f.frame:IsVisible() then
				if IM.Focused ~= "__TASKBAR__" then
					IM.Focused = id
				end
			end
			return true
		end
	end

	local minimized = PinnedPanels.GetMinimizedPanels()
	local ts = PinnedPanels.Settings.taskbar
	if IM.Active and #minimized > 0 and ts and ts.enabled ~= false then
		return true
	end

	return false
end

-- ── Panel & Tab Navigation ───────────────────────────────────────────────────
local function SetFocus(id, dir)
	if IM.NavigatingPanel and id ~= IM.Focused then
		IM.NavigatingPanel = false
		IM.SelectedIndex = nil
	end
	IM.Focused = id

	if id == "__TASKBAR__" then
		local TB = PinnedPanels.Taskbar
		local entries = PinnedPanels.GetMinimizedPanels()
		if TB then
			if #entries == 0 then
				TB.hoverIndex = nil
			else
				TB.hoverIndex = (dir and dir < 0) and #entries or 1
			end
		end
		IM._taskbarLastInput = CurTime()
		PinnedPanels.FocusTaskbar()
		return
	end

	PinnedPanels.UnfocusTaskbar()
	local pin = id and PinnedPanels.Pins[id]
	if pin and IsValid(pin.frame) then pin.frame:MoveToFront() end
	PinnedPanels.UpdatePanelStates()
end

local function CycleFocus(dir)
	if IM.Focused == "__TASKBAR__" then
		local TB = PinnedPanels.Taskbar
		local entries = PinnedPanels.GetMinimizedPanels()
		if TB and #entries > 0 then
			local ni = (TB.hoverIndex or 1) + dir
			if ni >= 1 and ni <= #entries then
				TB.hoverIndex = ni
				return
			end
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

	if IM.Focused == "__TASKBAR__" then
		local TB = PinnedPanels.Taskbar
		local entries = PinnedPanels.GetMinimizedPanels()
		local sel = TB and TB.hoverIndex
		if sel and entries[sel] then
			local id = entries[sel].id
			PinnedPanels.RestoreFromTaskbar(id)
			local remaining = PinnedPanels.GetMinimizedPanels()
			if #remaining == 0 then
				SetFocus(id)
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

local function MinimizeFocused()
	if IM.Focused and IM.Focused ~= "__TASKBAR__" then
		PinnedPanels.MinimizeToTaskbar(IM.Focused)
		CycleFocus(1)
	end
end

local function MaximizeFocused()
	if IM.Focused and IM.Focused ~= "__TASKBAR__" then
		PinnedPanels.ToggleMaximizePanel(IM.Focused)
	end
end

local function UnpinFocused()
	if IM.Focused and IM.Focused ~= "__TASKBAR__" then
		local target = IM.Focused
		CycleFocus(1)
		PinnedPanels.Unpin(target)
	end
end

-- ── Colour Control Resolution ────────────────────────────────────────────────
local function ColorTarget(el)
	if not IsValid(el) then return nil end
	local cls = el.ClassName or el:GetClassName()
	if cls:find("ColorCube") then return el, cls end
	if not cls:find("Color") then return nil end

	local found, fcls
	local function dig(p, d)
		if not IsValid(p) or d > 5 or found then return end
		for _, c in ipairs(p:GetChildren()) do
			if IsValid(c) then
				local ccls = c.ClassName or c:GetClassName()
				if ccls == "DColorMixer" or ccls:find("ColorCube") then
					found, fcls = c, ccls
					return
				end
				dig(c, d + 1)
			end
		end
	end
	dig(el, 0)
	if IsValid(found) then return found, fcls end

	-- a clickable colour thing (palette swatch, swatch-button…) is a
	-- button to press, not a value to adjust
	if isfunction(el.GetColor) and isfunction(el.SetColor)
		and not isfunction(el.DoClick) then
		return el, cls
	end
	return nil
end
PinnedPanels._ColorTarget = ColorTarget

-- ── Interactive Element Scan (cached) ────────────────────────────────────────
local SKIP_CLASSES = {
	DLabel = true, Label = true, DImage = true, Image = true,
	DDivider = true, Divider = true, DExpandButton = true,
	DVScrollBar = true, DHScrollBar = true,
}

local COLOR_CONTAINERS = {
	DColorMixer = true, CtrlColor = true, DColorCombo = true, DColorPalette = true,
}

local CONTAINER_CLASSES = {
	ControlPanel = true, DForm = true, DCollapsibleCategory = true, DScrollPanel = true,
	DPropertySheet = true, DFrame = true, DCategoryList = true, DTree = true,
	DTree_Node = true, DListLayout = true, DIconLayout = true, DTileLayout = true,
	ContentContainer = true, SpawnmenuContentPanel = true, DMenu = true, DMenuBar = true,
}
for k in pairs(COLOR_CONTAINERS) do CONTAINER_CLASSES[k] = true end

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
		if SKIP_CLASSES[class] or class:find("ScrollBar") or class:find("Grip") then return 0 end

		if class:find("Slider") or class:find("CheckBox") or class == "DButton"
			or class == "DImageButton" or class == "DComboBox" or class == "DTextEntry"
			or class == "DNumSlider" or class == "DTree_Node_Button"
			or class == "DRGBPicker" or class == "DAlphaBar" or class == "DNumberWang"
			or (class:find("Color") and not COLOR_CONTAINERS[class]) then
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
	-- a nav popup (e.g. the colour changer) takes precedence over the pin
	local target = IsValid(IM.NavPopup) and IM.NavPopup or nil
	if not target then
		local pin = FocusedPin()
		target = pin and IsValid(pin.frame) and pin.frame or nil
	end
	if not target then
		navCache.frame, navCache.list = nil, {}
		return navCache.list
	end
	if navCache.frame ~= target or CurTime() >= navCache.expire then
		navCache.frame  = target
		navCache.expire = CurTime() + 0.15
		navCache.list   = PinnedPanels.GetInteractiveElements(target)
	end
	return navCache.list
end
local GetNavElements = PinnedPanels.GetNavElements

local function TopMostIndex(elems)
	local bestIdx, bestY, bestX = 1, math.huge, math.huge
	for i, el in ipairs(elems) do
		if IsValid(el) then
			local x, y = el:LocalToScreen(0, 0)
			if y < bestY - 2 or (math.abs(y - bestY) <= 2 and x < bestX) then
				bestIdx, bestY, bestX = i, y, x
			end
		end
	end
	return bestIdx
end

-- ── Key Repeat ───────────────────────────────────────────────────────────────
local KEY_REPEAT_DELAY    = 0.35
local KEY_REPEAT_INTERVAL = 0.055
local keyRepeat = {}

local function StartRepeat(key) keyRepeat[key] = { start = CurTime(), last = 0, repeating = false } end
local function StopRepeat(key) keyRepeat[key] = nil end
local function StopAllRepeats() keyRepeat = {} end

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
-- ESC is deliberately NOT captured anywhere in nav — it must stay free to open
-- the game pause menu. BACKSPACE is the "back / exit" key instead.
local NAV_KEYS = { [KEY_UP] = true, [KEY_DOWN] = true, [KEY_LEFT] = true, [KEY_RIGHT] = true,
                   [KEY_ENTER] = true, [KEY_BACKSPACE] = true }
local navKeyDown = {}
local navMemory = {}

local function ResetNavKeyState()
	StopAllRepeats()
	navKeyDown = {}
	for k in pairs(NAV_KEYS) do
		if input.IsKeyDown(k) then
			navKeyDown[k] = true
			StartRepeat(k)
		end
	end
end

local function ExitContentNav()
	if IM.Focused and not IsValid(IM.NavPopup) then
		navMemory[IM.Focused] = GetNavElements()[IM.NavFocusIndex]
	end
	IM.NavPopup = nil
	IM.NavigatingPanel = false
	IM.SelectedIndex = nil
	StopAllRepeats()
	navKeyDown = {}
	PinnedPanels.UpdatePanelStates()
end

function PinnedPanels.SetNavPopup(frame)
	if IsValid(frame) then
		IM.NavPopup        = frame
		IM.NavigatingPanel = true
		IM.NavFocusIndex   = TopMostIndex(GetNavElements())
		IM.SelectedIndex   = nil
		ResetNavKeyState()
	elseif IM.NavPopup ~= nil then
		ExitContentNav()
	end
end

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

	local elems = GetNavElements()
	local idx
	local mem = navMemory[IM.Focused]
	if IsValid(mem) then
		for i, el in ipairs(elems) do
			if el == mem then idx = i break end
		end
	end
	IM.NavFocusIndex = idx or TopMostIndex(elems)

	IM.SelectedIndex = nil
	IM.LastNavPanel = IM.Focused
	ResetNavKeyState()
	PinnedPanels.UpdatePanelStates()
end

-- ── Context-Menu Keyboard Navigation ───────────────────────────────────────
local C = PinnedPanels.C

local function CreateKeyboardMenu(items, x, y, parentMenu)
	if not items or #items == 0 then return nil end

	local ROW_H   = 22
	local ICON_SZ = 16
	local PAD     = 6
	local FONT    = "DermaDefault"
	local MIN_W   = 160

	surface.SetFont(FONT)
	local maxW = MIN_W
	for _, it in ipairs(items) do
		local tw = select(1, surface.GetTextSize(it.text or ""))
		maxW = math.max(maxW, tw + ICON_SZ + PAD * 4 + 16)
	end

	local panelW = maxW + PAD * 2
	local panelH = #items * ROW_H + PAD * 2

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
	pnl.Items      = items
	pnl.SelIndex   = 1
	pnl.ParentMenu = parentMenu
	pnl._wasDown   = {}
	for k in pairs(NAV_KEYS) do pnl._wasDown[k] = input.IsKeyDown(k) end

	for _, it in ipairs(items) do
		if it.icon and it.icon ~= "" then
			it._mat = Material(it.icon, "smooth mips")
		end
	end

	function pnl:Paint(w, h)
		draw.RoundedBox(4, 0, 0, w, h, C.bgPopup)
		surface.SetDrawColor(C.bgHeaderLine)
		surface.DrawOutlinedRect(0, 0, w, h, 1)

		surface.SetFont(FONT)
		for i, it in ipairs(self.Items) do
			local ry = PAD + (i - 1) * ROW_H

			if i == self.SelIndex then
				draw.RoundedBox(3, PAD - 2, ry, w - PAD * 2 + 4, ROW_H, C.accent)
			end

			if it._mat and not it._mat:IsError() then
				surface.SetDrawColor(255, 255, 255, (it.enabled == false) and 80 or 255)
				surface.SetMaterial(it._mat)
				surface.DrawTexturedRect(PAD + 2, ry + (ROW_H - ICON_SZ) / 2, ICON_SZ, ICON_SZ)
			end

			local textColor = (it.enabled == false) and C.textMuted
				or (i == self.SelIndex and C.textBright or C.textLight)
			draw.SimpleText(it.text or "", FONT, PAD + ICON_SZ + PAD + 4, ry + ROW_H / 2,
				textColor, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

			if it.isSubMenu then
				surface.SetDrawColor(textColor)
				local ax = w - PAD - 6
				local ay = ry + ROW_H / 2
				draw.NoTexture()
				surface.DrawPoly({
					{ x = ax - 4, y = ay - 4 },
					{ x = ax + 2, y = ay },
					{ x = ax - 4, y = ay + 4 },
				})
			end
		end
	end

	return pnl
end

local function CaptureAndExtractMenu(triggerFn)
	local captured = nil

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
			local origAddOption = m.AddOption
			if isfunction(origAddOption) then
				m.AddOption = function(self, text, func)
					local opt = origAddOption(self, text, func)
					if IsValid(opt) then opt._rawCallback = func end
					return opt
				end
			end
			local origAddCVar = m.AddCVar
			if isfunction(origAddCVar) then
				m.AddCVar = function(self, text, cv, on, off, func)
					local opt = origAddCVar(self, text, cv, on, off, func)
					if IsValid(opt) then
						opt._rawCallback = function()
							RunConsoleCommand(cv, tostring(on))
							if func then func() end
						end
					end
					return opt
				end
			end
		end
		return m
	end

	local ok, err = pcall(triggerFn)

	DermaMenu = _origDermaMenu
	vgui.Create = _origCreate

	if not ok then
		ErrorNoHalt("[PinnedPanels] Context menu trigger error: " .. tostring(err) .. "\n")
	end

	if not IsValid(captured) then return {} end

	local items = {}
	local function walk(parent, outList)
		local children = parent.GetCanvas and parent:GetCanvas():GetChildren() or parent:GetChildren()
		for _, child in ipairs(children) do
			if IsValid(child) then
				local cls = child.ClassName or child:GetClassName()
				if cls == "DMenuOption" or cls == "DMenuOptionCVar" then
					local text = child:GetText() or ""
					local icon = ""
					if child.m_Image and IsValid(child.m_Image) then
						icon = child.m_Image:GetImage() or ""
					end
					local enabled = child:IsEnabled()
					
					local isSubMenu = IsValid(child.SubMenu)

					local cb = child._rawCallback
					if not cb and isfunction(child.DoClick) then
						local fallback = child.DoClick
						cb = function()
							pcall(fallback, { GetDisabled = function() return false end, Toggle = function() end })
						end
					end

					if text ~= "" then
						local item = {
							text      = text,
							icon      = icon,
							callback  = cb,
							enabled   = enabled,
							isSubMenu = isSubMenu,
						}
						outList[#outList + 1] = item

						if isSubMenu and IsValid(child.SubMenu) then
							item.subItems = {}
							walk(child.SubMenu, item.subItems)
						end
					end
				elseif cls == "DMenu" or cls == "DermaMenu" then
					walk(child, outList)
				end
			end
		end
	end
	walk(captured, items)

	captured:Remove()
	if CloseDermaMenus then CloseDermaMenus() end
	gui.EnableScreenClicker(PinnedPanels.CursorMode.Active or false)

	return items
end

local function CloseKeyboardMenu(pnl)
	if not IsValid(pnl) then return end
	local root = pnl
	while IsValid(root.ParentMenu) do root = root.ParentMenu end
	local curr = root
	while IsValid(curr) do
		local nxt = curr.ActiveSubMenu
		curr:Remove()
		curr = nxt
	end
end

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

	if #items == 0 then return end

	CloseKeyboardMenu(IM.ActiveMenu)
	IM.ActiveMenu = CreateKeyboardMenu(items, posX, posY)
end

local function OpenElementContextMenu(el)
	if not IsValid(el) then return end

	local ex, ey = el:LocalToScreen(0, 0)
	local ew, eh = el:GetSize()
	local posX, posY = ex + ew / 2, ey + eh / 2

	local target = el
	local items = {}
	for attempt = 1, 10 do
		if not IsValid(target) then break end

		local methodsToTry = {
			"OpenGenericSpawnmenuRightClickMenu",
			"OpenMenu",
			"DoRightClick",
			"Mouse"
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

	if #items == 0 then return end

	CloseKeyboardMenu(IM.ActiveMenu)
	IM.ActiveMenu = CreateKeyboardMenu(items, posX, posY)
end

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
	local leftNow  = input.IsKeyDown(KEY_LEFT)
	local rightNow = input.IsKeyDown(KEY_RIGHT)
	local enterNow = input.IsKeyDown(KEY_ENTER)
	local backNow  = input.IsKeyDown(KEY_BACKSPACE) -- back out of / close the menu (not ESC)
	local wd       = pnl._wasDown

	if upNow and not wd[KEY_UP] then
		pnl.SelIndex = (pnl.SelIndex > 1) and (pnl.SelIndex - 1) or n
		local tried = 0
		while items[pnl.SelIndex] and items[pnl.SelIndex].enabled == false and tried < n do
			pnl.SelIndex = (pnl.SelIndex > 1) and (pnl.SelIndex - 1) or n
			tried = tried + 1
		end
	elseif downNow and not wd[KEY_DOWN] then
		pnl.SelIndex = (pnl.SelIndex < n) and (pnl.SelIndex + 1) or 1
		local tried = 0
		while items[pnl.SelIndex] and items[pnl.SelIndex].enabled == false and tried < n do
			pnl.SelIndex = (pnl.SelIndex < n) and (pnl.SelIndex + 1) or 1
			tried = tried + 1
		end
	elseif (enterNow and not wd[KEY_ENTER]) or (rightNow and not wd[KEY_RIGHT]) then
		local it = items[pnl.SelIndex]
		if it and it.enabled ~= false then
			if it.isSubMenu and it.subItems and #it.subItems > 0 then
				if IsValid(pnl.ActiveSubMenu) then pnl.ActiveSubMenu:Remove() end
				local cx, cy = pnl:GetPos()
				local ROW_H, PAD = 22, 6
				local rx = cx + pnl:GetWide()
				local ry = cy + PAD + (pnl.SelIndex - 1) * ROW_H
				pnl.ActiveSubMenu = CreateKeyboardMenu(it.subItems, rx, ry, pnl)
				if IsValid(pnl.ActiveSubMenu) then
					IM.ActiveMenu = pnl.ActiveSubMenu
					IM.ActiveMenu._wasDown[KEY_ENTER] = true
					IM.ActiveMenu._wasDown[KEY_RIGHT] = true
				end
			elseif enterNow and isfunction(it.callback) then
				it.callback()
				CloseKeyboardMenu(pnl)
				IM.ActiveMenu = nil
			end
		end
		return
	elseif (leftNow and not wd[KEY_LEFT]) or (backNow and not wd[KEY_BACKSPACE]) then
		if IsValid(pnl.ParentMenu) then
			local parent = pnl.ParentMenu
			parent.ActiveSubMenu = nil
			parent._wasDown[KEY_LEFT] = true
			parent._wasDown[KEY_BACKSPACE] = true
			IM.ActiveMenu = parent
			pnl:Remove()
			return
		elseif backNow then
			CloseKeyboardMenu(pnl)
			IM.ActiveMenu = nil
			return
		end
	end

	wd[KEY_UP]        = upNow
	wd[KEY_DOWN]      = downNow
	wd[KEY_LEFT]      = leftNow
	wd[KEY_RIGHT]     = rightNow
	wd[KEY_ENTER]     = enterNow
	wd[KEY_BACKSPACE] = backNow
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
	{ id = "auto_arrange",     name = "Auto-Arrange Panels",        default = KEY_NONE, action = function() if PinnedPanels.AutoArrange then PinnedPanels.AutoArrange() end end },
	{ id = "autosize_focused", name = "Auto-Size Focused",          default = KEY_NONE, action = function()
		if IM.Focused and IM.Focused ~= "__TASKBAR__" then PinnedPanels.AutoSizePanel(IM.Focused) end
	end },
	{ id = "reopen_closed",    name = "Reopen Last Closed",         default = KEY_NONE, action = function() if PinnedPanels.ReopenLastClosed then PinnedPanels.ReopenLastClosed() end end },
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

local function OwnerMixer(el)
	local p = el:GetParent()
	for _ = 1, 6 do
		if not IsValid(p) then return nil end
		if IsValid(p.HSV) and isfunction(p.GetColor) and isfunction(p.SetColor) then
			return p
		end
		p = p:GetParent()
	end
	return nil
end

local function AdjustKind(el)
	if not IsValid(el) then return nil end
	local cls = el.ClassName or el:GetClassName()
	if cls == "DRGBPicker" or cls == "DAlphaBar" then return "vert" end
	if ColorTarget(el) then return "2d" end
	if cls:find("Slider") or cls == "DComboBox" then return "1d" end
	return nil
end

local function AdjustValue(el, key)
	local cls = el.ClassName or el:GetClassName()
	local dir = (key == KEY_RIGHT) and 1 or -1

	if cls == "DRGBPicker" then
		-- hue strip: step the owning mixer's hue. On a grey colour a hue
		-- change is invisible, so give it saturation first (clicking the
		-- strip with the mouse yields a fully saturated colour too).
		local mixer = OwnerMixer(el)
		if mixer then
			local col = mixer:GetColor()
			local h, s, v = ColorToHSV(col)
			if s < 0.05 then s = 1 end
			if v < 0.05 then v = 1 end
			local step = (key == KEY_UP or key == KEY_RIGHT) and 8 or -8
			local nc = HSVToColor((h + step) % 360, s, v)
			nc.a = col.a or 255
			mixer:SetColor(nc)
		end
		return
	end

	if cls == "DAlphaBar" then
		-- SetValue alone doesn't notify; fire OnChange like the mouse does
		local step = (key == KEY_UP or key == KEY_RIGHT) and 0.04 or -0.04
		local v = math.Clamp((el:GetValue() or 1) + step, 0, 1)
		el:SetValue(v)
		el:OnChange(v)
		return
	end

	local tgt, tcls = ColorTarget(el)
	if tgt then
		if tcls:find("ColorCube") then
			-- Cube controls saturation (X) and value (Y); hue stays fixed.
			local col = (isfunction(tgt.GetRGB) and tgt:GetRGB())
				or (isfunction(tgt.GetColor) and tgt:GetColor()) or color_white
			local h, s, v = ColorToHSV(col)
			if key == KEY_LEFT      then s = math.Clamp(s - 0.04, 0, 1)
			elseif key == KEY_RIGHT then s = math.Clamp(s + 0.04, 0, 1)
			elseif key == KEY_UP    then v = math.Clamp(v + 0.04, 0, 1)
			elseif key == KEY_DOWN  then v = math.Clamp(v - 0.04, 0, 1) end
			local nc = HSVToColor(h, s, v)
			if isfunction(tgt.SetColor) then tgt:SetColor(nc) end
			if isfunction(tgt.OnUserChanged) then tgt:OnUserChanged(nc) end
		else
			-- Full mixer: Arrows = Hue / Value, Shift+Arrows = Saturation / Alpha.
			-- SetColor fires the mixer's ValueChanged, which pushes the convars.
			local col = (isfunction(tgt.GetColor) and tgt:GetColor()) or color_white
			local h, s, v = ColorToHSV(col)
			local a = col.a or 255
			local shift = input.IsKeyDown(KEY_LSHIFT) or input.IsKeyDown(KEY_RSHIFT)
			if shift then
				if key == KEY_LEFT      then s = math.Clamp(s - 0.04, 0, 1)
				elseif key == KEY_RIGHT then s = math.Clamp(s + 0.04, 0, 1)
				elseif key == KEY_UP    then a = math.Clamp(a + 10, 0, 255)
				elseif key == KEY_DOWN  then a = math.Clamp(a - 10, 0, 255) end
			else
				if key == KEY_LEFT      then h = (h - 8) % 360
				elseif key == KEY_RIGHT then h = (h + 8) % 360
				elseif key == KEY_UP    then v = math.Clamp(v + 0.04, 0, 1)
				elseif key == KEY_DOWN  then v = math.Clamp(v - 0.04, 0, 1) end
			end
			local nc = HSVToColor(h, s, v)
			nc.a = math.Round(a)
			if isfunction(tgt.SetColor) then tgt:SetColor(nc) end
		end
		return
	end

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
	if AdjustKind(el) then
		-- enter adjust mode; arrows tweak the value in place
		return
	elseif cls == "DTextEntry" or cls == "DNumberWang" or el:GetClassName() == "TextEntry" then
		local pin = FocusedPin()
		if pin and IsValid(pin.frame) then
			pin.frame:SetKeyboardInputEnabled(true)
		end
		el:SetKeyboardInputEnabled(true)
		el:RequestFocus()
		IM.NavigatingPanel = false
		IM.SelectedIndex = nil
	elseif cls == "DTree_Node_Button" then
		local p = el:GetParent()
		if IsValid(p) and p.InternalDoClick then p:InternalDoClick()
		elseif isfunction(el.DoClick) then el:DoClick() end
		IM.SelectedIndex = nil
	elseif cls:find("CheckBox") then
		if el.Toggle then el:Toggle() elseif el.SetValue then el:SetValue(not el:GetChecked()) end
	elseif isfunction(el.DoClick) then
		el:DoClick()
		IM.SelectedIndex = nil
	elseif isfunction(el.Toggle) then
		el:Toggle()
		IM.SelectedIndex = nil
	elseif isfunction(el.OnMousePressed) then
		el:OnMousePressed(MOUSE_LEFT)
		if isfunction(el.OnMouseReleased) then el:OnMouseReleased(MOUSE_LEFT) end
		IM.SelectedIndex = nil
	end
end

local function ElementRect(el)
	local x, y = el:LocalToScreen(0, 0)
	local w, h = el:GetSize()
	return x, y, w, h, x + w / 2, y + h / 2
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

	local fx, fy, fw, fh, fcx, fcy = ElementRect(focusEl)
	local horiz = (key == KEY_LEFT or key == KEY_RIGHT)

	-- overlapping candidates (same row / column) beat non-overlapping ones
	local bestOver, bestOverIdx = math.huge, nil
	local bestAny,  bestAnyIdx  = math.huge, nil

	for i, el in ipairs(elements) do
		if el ~= focusEl and IsValid(el) then
			local ex, ey, ew, eh, ecx, ecy = ElementRect(el)
			local dx, dy = ecx - fcx, ecy - fcy

			local valid
			if key == KEY_LEFT then      valid = dx < -2
			elseif key == KEY_RIGHT then valid = dx > 2
			elseif key == KEY_UP then    valid = dy < -2
			else                         valid = dy > 2 end

			if valid then
				local overlap
				if horiz then
					overlap = (ey < fy + fh) and (fy < ey + eh)
				else
					overlap = (ex < fx + fw) and (fx < ex + ew)
				end
				local score = horiz and (math.abs(dx) + math.abs(dy) * 4)
					or (math.abs(dy) + math.abs(dx) * 4)
				if overlap then
					if score < bestOver then bestOver, bestOverIdx = score, i end
				elseif score < bestAny then
					bestAny, bestAnyIdx = score, i
				end
			end
		end
	end

	local idx = bestOverIdx or ((not horiz) and bestAnyIdx or nil)
	if idx then
		IM.NavFocusIndex = idx
	elseif key == KEY_UP then
		-- moving up from the top-most element leaves content nav
		ExitContentNav()
	end
end

local function HandleContentNav()
	-- popup nav (colour changer…) has no owning pin to validate against
	if not IsValid(IM.NavPopup) then
		local pin = FocusedPin()
		if not pin or not IsValid(pin.frame) or IM.Focused ~= IM.LastNavPanel then
			ExitContentNav()
			return
		end
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

		if key == KEY_BACKSPACE then
			if down and not wasDown then
				if IM.SelectedIndex then IM.SelectedIndex = nil else ExitContentNav() end
			end
		elseif key == KEY_ENTER then
			if down and not wasDown then
				local shiftHeld = input.IsKeyDown(KEY_LSHIFT) or input.IsKeyDown(KEY_RSHIFT)
				if shiftHeld then
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
					local kind = AdjustKind(selectedEl)
					local consume = (kind == "2d" or kind == "vert")
						or (kind == "1d" and (key == KEY_LEFT or key == KEY_RIGHT))
					if consume then
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
		local fe = focusedEl()
		if fe then ScrollIntoView(fe) end
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

	local anyNavDown = false
	for k in pairs(NAV_KEYS) do
		if input.IsKeyDown(k) then anyNavDown = true break end
	end
	if not anyNavDown then
		for _, b in ipairs(BINDS) do
			if b.key and b.key ~= KEY_NONE and input.IsKeyDown(b.key) then anyNavDown = true break end
		end
	end

	if anyNavDown then
		IM.LastNavActivity = CurTime()
		if not IM._navOpacityActive then
			IM._navOpacityActive = true
			if PinnedPanels.UpdatePanelStates then PinnedPanels.UpdatePanelStates() end
		end
	end

	if IM._navOpacityActive and CurTime() - (IM.LastNavActivity or 0) > 2 then
		IM._navOpacityActive = false
		if PinnedPanels.UpdatePanelStates then PinnedPanels.UpdatePanelStates() end
	end

	if IM.ActiveMenu then
		HandleMenuNav()
		return
	end

	if not PinnedPanels.IsKeyboardNavEnabled() then
		if IM.NavigatingPanel then ExitContentNav() end
		if PinnedPanels.UnfocusTaskbar then PinnedPanels.UnfocusTaskbar() end
		return
	end

	if IM.Focused == "__TASKBAR__" then
		local TB = PinnedPanels.Taskbar
		if TB and not TB.kbFocused and PinnedPanels.FocusTaskbar then
			PinnedPanels.FocusTaskbar()
		end

		if input.IsKeyDown(KEY_LEFT) or input.IsKeyDown(KEY_RIGHT)
			or input.IsKeyDown(KEY_UP) or input.IsKeyDown(KEY_DOWN) or input.IsKeyDown(KEY_ENTER) then
			IM._taskbarLastInput = CurTime()
		end
		local idle = IM._taskbarLastInput and (CurTime() - IM._taskbarLastInput > 5)
		if input.IsKeyDown(KEY_BACKSPACE) or (idle and not PinnedPanels.PanelsInteractive()) then
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
	if IM.ActiveMenu and (k == KEY_UP or k == KEY_DOWN or k == KEY_ENTER or k == KEY_BACKSPACE) then return true end
	if IM.NavigatingPanel and NAV_KEYS[k] then return true end
	for _, b in ipairs(BINDS) do
		if b.key == k then return true end
	end
	return false
end

hook.Add("CreateMove", "PinnedPanels_KeyNavSuppressMove", function(cmd)
	if not PinnedPanels.IsKeyboardNavEnabled() or IsValid(vgui.GetKeyboardFocus()) then return end

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
	if not PinnedPanels.IsKeyboardNavEnabled() or IsValid(vgui.GetKeyboardFocus()) then return end
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