-- ── Keyboard Navigation ──────────────────────────────────────────────────────
local IM = PinnedPanels.InteractMode

--------------------------------------------------------------------
-- Utility: list top‑level visible pins sorted by title
--------------------------------------------------------------------
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
	return list
end

local function FocusedPin()
	return IM.Focused and PinnedPanels.Pins[IM.Focused] or nil
end

local function KeyboardNavEnabled()
	return IM.Active or PinnedPanels.Settings.keyboardNavOutsideInteractMode
end

local function SetFocus(id)
	if IM.NavigatingPanel and id ~= IM.Focused then
		IM.NavigatingPanel = false
		IM.SelectedIndex = nil
	end
	IM.Focused = id
	local pin = id and PinnedPanels.Pins[id]
	if pin and IsValid(pin.frame) then pin.frame:MoveToFront() end
end

--------------------------------------------------------------------
-- Cycle between top‑level panels
--------------------------------------------------------------------
local function CycleFocus(dir)
	local list = VisibleTopLevelPins()
	if #list == 0 then
		IM.Focused = nil
		return
	end
	local idx = 0
	for i, e in ipairs(list) do
		if e.id == IM.Focused then idx = i break end
	end
	idx = idx + dir
	if idx < 1 then idx = #list elseif idx > #list then idx = 1 end
	SetFocus(list[idx].id)
end

--------------------------------------------------------------------
-- Tab switching inside group panels
--------------------------------------------------------------------
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

--------------------------------------------------------------------
-- Other actions
--------------------------------------------------------------------
local function EquipFocusedTool()
	if not IM.Focused then return end
	local toolClass = PinnedPanels.GetPinTool(IM.Focused)
	if not toolClass then return end
	PinnedPanels.EquipToolgun(toolClass)
	PinnedPanels.InteractMode.Disable()
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

--------------------------------------------------------------------
-- Content navigation inside a focused panel
--------------------------------------------------------------------
IM.NavigatingPanel = false
IM.NavFocusIndex = 1
IM.SelectedIndex = nil    -- track which element is “selected” for editing
IM.LastNavPanel = nil

function PinnedPanels.GetInteractiveElements(panel)
	local list = {}
	if not IsValid(panel) then return list end

	local function Scan(p)
		if not IsValid(p) then return end
		local class = p:GetClassName()

		if p:IsVisible() then
			if class == "DButton" or class == "DCheckBox" or class == "DCheckBoxLabel" or
			   class == "DNumSlider" or class == "CtrlNumSlider" or
			   class == "DTextEntry" or class == "DComboBox" then
				table.insert(list, p)
				return
			end
		end

		if not p:IsVisible() then
			if class == "DPanel" or class == "EditablePanel" then return end
			if class == "Tab" then return end
		end

		if (isfunction(p.SetValue) and isfunction(p.GetValue)) or isfunction(p.DoClick) or isfunction(p.Toggle) then
			if p:IsVisible() and not p:GetChildren()[1] and class ~= "DPanel" and class ~= "EditablePanel" then
				table.insert(list, p)
				return
			end
		end

		for _, child in ipairs(p:GetChildren()) do
			Scan(child)
		end
	end

	Scan(panel)
	return list
end

concommand.Add("pp_debug_nav", function()
	local pin = IM.Focused and PinnedPanels.Pins[IM.Focused]
	if not pin then print("No focused pin.") return end
	local els = PinnedPanels.GetInteractiveElements(pin.frame)
	print("Found " .. #els .. " interactive elements in " .. tostring(pin.title))
	for i, el in ipairs(els) do
		print(i, el:GetClassName(), el:IsVisible())
	end
end)

--------------------------------------------------------------------
-- Key repeat for held keys (only used when an element is selected)
--------------------------------------------------------------------
local KEY_REPEAT_INITIAL_DELAY = 0.4
local KEY_REPEAT_INTERVAL     = 0.05
local keyRepeatTimers = {}

local function StartKeyRepeat(key)
	keyRepeatTimers[key] = {
		startTime = CurTime(),
		lastAction = 0,
		isRepeating = false,
	}
end

local function StopKeyRepeat(key)
	keyRepeatTimers[key] = nil
end

local function ShouldRepeat(key)
	local t = keyRepeatTimers[key]
	if not t then return false end
	local now = CurTime()
	if not t.isRepeating then
		if now - t.startTime >= KEY_REPEAT_INITIAL_DELAY then
			t.isRepeating = true
			t.lastAction = now
			return true
		end
		return false
	else
		if now - t.lastAction >= KEY_REPEAT_INTERVAL then
			t.lastAction = now
			return true
		end
		return false
	end
end

--------------------------------------------------------------------
-- Keybind registry
--------------------------------------------------------------------
local nav_keys = {
	[KEY_UP] = true, [KEY_DOWN] = true,
	[KEY_LEFT] = true, [KEY_RIGHT] = true,
	[KEY_ENTER] = true, [KEY_ESCAPE] = true
}
local nav_keys_down = {}

local BINDS = {
	{ id = "focus_next",  name = "Focus Next Panel",       default = KEY_RIGHT,    action = function() CycleFocus(1) end },
	{ id = "focus_prev",  name = "Focus Previous Panel",   default = KEY_LEFT,     action = function() CycleFocus(-1) end },
	{ id = "tab_next",    name = "Next Tab (Group)",       default = KEY_RBRACKET, action = function() SwitchTab(1) end },
	{ id = "tab_prev",    name = "Previous Tab (Group)",   default = KEY_LBRACKET, action = function() SwitchTab(-1) end },
	{ id = "equip_tool",  name = "Equip Focused Tool",     default = KEY_ENTER,    action = EquipFocusedTool },
	{ id = "toggle_hide", name = "Hide / Show Focused",    default = KEY_NONE,     action = ToggleFocusedHidden },
	{ id = "bring_front", name = "Bring Focused To Front", default = KEY_NONE,     action = BringFocusedFront },
	{ id = "enter_nav",   name = "Enter Panel Content Nav",default = KEY_DOWN,     action = function()
		if not IM.NavigatingPanel and FocusedPin() then
			IM.NavigatingPanel = true
			IM.NavFocusIndex = 1
			IM.SelectedIndex = nil
			IM.LastNavPanel = IM.Focused
			for k, _ in pairs(nav_keys) do
				nav_keys_down[k] = input.IsKeyDown(k)
			end
			for k in pairs(keyRepeatTimers) do
				StopKeyRepeat(k)
			end
		end
	end },
}
PinnedPanels.Keybinds = BINDS

local byId = {}
for _, b in ipairs(BINDS) do
	byId[b.id] = b
	b.convar = "pp_key_" .. b.id
	local cv = CreateClientConVar(b.convar, tostring(b.default), true, false, "PinnedPanels: " .. b.name)
	b.key = tonumber(cv:GetString()) or b.default
	b.wasDown = false
	cvars.AddChangeCallback(b.convar, function(_, _, new)
		b.key = tonumber(new) or KEY_NONE
	end, "PinnedPanels_KeyNav")
end

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

--------------------------------------------------------------------
-- Think hook – dispatches key actions
--------------------------------------------------------------------
hook.Add("Think", "PinnedPanels_KeyNav", function()
	if not KeyboardNavEnabled() then
		IM.NavigatingPanel = false
		IM.SelectedIndex = nil
		for k in pairs(keyRepeatTimers) do StopKeyRepeat(k) end
		return
	end
	if IsValid(vgui.GetKeyboardFocus()) then return end

	if IM.NavigatingPanel then
		local pin = FocusedPin()
		if not pin or not IsValid(pin.frame) then
			IM.NavigatingPanel = false
			IM.SelectedIndex = nil
			for k in pairs(keyRepeatTimers) do StopKeyRepeat(k) end
			return
		end

		if IM.Focused ~= IM.LastNavPanel then
			IM.NavFocusIndex = 1
			IM.SelectedIndex = nil
			IM.LastNavPanel = IM.Focused
			for k in pairs(keyRepeatTimers) do StopKeyRepeat(k) end
		end

		local elements = PinnedPanels.GetInteractiveElements(pin.frame)
		if #elements > 0 then
			IM.NavFocusIndex = math.Clamp(IM.NavFocusIndex, 1, #elements)
		else
			IM.NavFocusIndex = 1
			IM.SelectedIndex = nil
		end

		-- Helper: return the currently focused element (may be selected or not)
		local function GetFocusedElement()
			if #elements > 0 and IM.NavFocusIndex <= #elements then
				return elements[IM.NavFocusIndex]
			end
			return nil
		end

		local selectedEl = IM.SelectedIndex and elements[IM.SelectedIndex] or nil

		-- Process keys
		for k, _ in pairs(nav_keys) do
			local down = input.IsKeyDown(k)

			if k == KEY_ESCAPE then
				if down and not nav_keys_down[k] then
					if IM.SelectedIndex then
						IM.SelectedIndex = nil
					else
						IM.NavigatingPanel = false
					end
					for k2 in pairs(keyRepeatTimers) do StopKeyRepeat(k2) end
				end
			elseif k == KEY_UP then
				if down and not nav_keys_down[k] then
					if IM.SelectedIndex then
						IM.SelectedIndex = nil
					else
						if #elements == 0 or IM.NavFocusIndex == 1 then
							IM.NavigatingPanel = false
						else
							IM.NavFocusIndex = IM.NavFocusIndex - 1
						end
					end
					for k2 in pairs(keyRepeatTimers) do StopKeyRepeat(k2) end
				end
			elseif k == KEY_DOWN then
				if down and not nav_keys_down[k] then
					if IM.SelectedIndex then
						IM.SelectedIndex = nil
					else
						if #elements > 0 and IM.NavFocusIndex < #elements then
							IM.NavFocusIndex = IM.NavFocusIndex + 1
						end
					end
					for k2 in pairs(keyRepeatTimers) do StopKeyRepeat(k2) end
				end
			elseif k == KEY_ENTER then
				if down and not nav_keys_down[k] then
					local el = GetFocusedElement()
					if not el then continue end
					local cls = el:GetClassName()

					-- If an element is already selected, deselect it first
					if IM.SelectedIndex then
						IM.SelectedIndex = nil
						continue
					end

					-- Otherwise, decide what to do with the current focus
					if cls == "DButton" then
						if el.DoClick then el:DoClick() end
						-- Button is a one‑shot action; do not select it
					elseif cls == "DCheckBox" or cls == "DCheckBoxLabel" then
						IM.SelectedIndex = IM.NavFocusIndex
						-- First press toggles immediately
						if cls == "DCheckBoxLabel" then el:Toggle() else el:Toggle() end
					elseif cls == "DNumSlider" or cls == "CtrlNumSlider" then
						IM.SelectedIndex = IM.NavFocusIndex
					elseif cls == "DComboBox" then
						-- Open the dropdown: simulate a click on the combo button
						if el.DoClick then el:DoClick() end
						-- The dropdown menu will grab keyboard focus, so we exit our nav
						-- (but don't set SelectedIndex, it's not needed)
					elseif cls == "DTextEntry" then
						el:RequestFocus()
					end
				end
			elseif k == KEY_LEFT or k == KEY_RIGHT then
				if down then
					if not nav_keys_down[k] then
						StartKeyRepeat(k)
						-- Force an immediate action on first press (before repeat delay)
						if IM.SelectedIndex and selectedEl and IsValid(selectedEl) then
							local dir = (k == KEY_RIGHT) and 1 or -1
							local cls = selectedEl:GetClassName()
							if cls == "DNumSlider" or cls == "CtrlNumSlider" then
								local val = selectedEl:GetValue()
								local min, max = selectedEl:GetMin(), selectedEl:GetMax()
								local step = (max - min) / 20
								selectedEl:SetValue(math.Clamp(val + step * dir, min, max))
								if selectedEl.OnValueChanged then selectedEl:OnValueChanged(selectedEl:GetValue()) end
							elseif cls == "DCheckBox" or cls == "DCheckBoxLabel" then
								local chk = (k == KEY_RIGHT)
								if cls == "DCheckBoxLabel" then selectedEl:SetValue(chk) else selectedEl:SetChecked(chk) end
							end
						end
					end

					-- Repeated actions while holding
					if IM.SelectedIndex and selectedEl and IsValid(selectedEl) and ShouldRepeat(k) then
						local dir = (k == KEY_RIGHT) and 1 or -1
						local cls = selectedEl:GetClassName()
						if cls == "DNumSlider" or cls == "CtrlNumSlider" then
							local val = selectedEl:GetValue()
							local min, max = selectedEl:GetMin(), selectedEl:GetMax()
							local step = (max - min) / 20
							selectedEl:SetValue(math.Clamp(val + step * dir, min, max))
							if selectedEl.OnValueChanged then selectedEl:OnValueChanged(selectedEl:GetValue()) end
						end
					end
				else
					StopKeyRepeat(k)
				end
			end

			nav_keys_down[k] = down
		end

		return  -- don't process global keybinds while inside a panel
	end

	-- ========== Global keybinds ==========
	for _, b in ipairs(BINDS) do
		local k = b.key
		if k and k ~= KEY_NONE then
			local down = input.IsKeyDown(k)
			if down and not b.wasDown then b.action() end
			b.wasDown = down
		else
			b.wasDown = false
		end
	end
end)

--------------------------------------------------------------------
-- Movement suppression
--------------------------------------------------------------------
local bindToButton = {
	["+attack"]     = IN_ATTACK,    ["+attack2"]    = IN_ATTACK2,
	["+jump"]       = IN_JUMP,      ["+duck"]       = IN_DUCK,
	["+forward"]    = IN_FORWARD,   ["+back"]       = IN_BACK,
	["+use"]        = IN_USE,       ["+moveleft"]   = IN_MOVELEFT,
	["+moveright"]  = IN_MOVERIGHT, ["+left"]       = IN_LEFT,
	["+right"]      = IN_RIGHT,     ["+reload"]     = IN_RELOAD,
	["+alt1"]       = IN_ALT1,      ["+alt2"]       = IN_ALT2,
	["+score"]      = IN_SCORE,     ["+speed"]      = IN_SPEED,
	["+walk"]       = IN_WALK,      ["+zoom"]       = IN_ZOOM,
}

hook.Add("CreateMove", "PinnedPanels_KeyNavSuppressMove", function(cmd)
	if not KeyboardNavEnabled() then return end
	if IsValid(vgui.GetKeyboardFocus()) then return end

	local buttons = cmd:GetButtons()

	local keysToSuppress = {}
	local addKey = function(k)
		if k and k ~= KEY_NONE then keysToSuppress[k] = true end
	end

	if IM.NavigatingPanel then
		addKey(KEY_LEFT); addKey(KEY_RIGHT)
		addKey(KEY_UP); addKey(KEY_DOWN)
		addKey(KEY_ENTER); addKey(KEY_ESCAPE)
	end

	for _, b in ipairs(BINDS) do addKey(b.key) end

	for k, _ in pairs(keysToSuppress) do
		if input.IsKeyDown(k) then
			local bindName = input.LookupKeyBinding(k)
			if bindName then
				local btn = bindToButton[bindName]
				if btn then buttons = bit.band(buttons, bit.bnot(btn)) end
				if bindName == "+forward" or bindName == "+back" then cmd:SetForwardMove(0) end
				if bindName == "+moveleft" or bindName == "+moveright" then cmd:SetSideMove(0) end
			end
			if k == KEY_LEFT then
				buttons = bit.band(buttons, bit.bnot(IN_LEFT), bit.bnot(IN_MOVELEFT))
				cmd:SetSideMove(0)
			elseif k == KEY_RIGHT then
				buttons = bit.band(buttons, bit.bnot(IN_RIGHT), bit.bnot(IN_MOVERIGHT))
				cmd:SetSideMove(0)
			elseif k == KEY_UP then
				buttons = bit.band(buttons, bit.bnot(IN_FORWARD))
				cmd:SetForwardMove(0)
			elseif k == KEY_DOWN then
				buttons = bit.band(buttons, bit.bnot(IN_BACK))
				cmd:SetForwardMove(0)
			end
		end
	end

	cmd:SetButtons(buttons)
end)

hook.Add("PlayerBindPress", "PinnedPanels_KeyNavSuppressBind", function(ply, bind, pressed)
	if not KeyboardNavEnabled() then return end
	if IsValid(vgui.GetKeyboardFocus()) then return end

	if IM.NavigatingPanel then
		for k, _ in pairs(nav_keys) do
			if input.IsKeyDown(k) then
				local bound = input.LookupKeyBinding(k)
				if bound and bound == bind then return true end
			end
		end
	end

	for _, b in ipairs(BINDS) do
		local k = b.key
		if k and k ~= KEY_NONE and input.IsKeyDown(k) then
			local bound = input.LookupKeyBinding(k)
			if bound and bound == bind then return true end
		end
	end
end)

hook.Add("PinnedPanels_InteractModeChanged", "PinnedPanels_KeyNavFocus", function()
	if not IM.Active then return end
	local cur = FocusedPin()
	if not cur or not IsValid(cur.frame) or not cur.frame:IsVisible() then
		local list = VisibleTopLevelPins()
		IM.Focused = list[1] and list[1].id or nil
	end
end)