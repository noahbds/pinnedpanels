-- ── Keyboard Navigation ──────────────────────────────────────────────────────
local IM = PinnedPanels.InteractMode

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
	IM.Focused = id
	local pin = id and PinnedPanels.Pins[id]
	if pin and IsValid(pin.frame) then pin.frame:MoveToFront() end
end

local function CycleFocus(dir)
	local list = VisibleTopLevelPins()
	if #list == 0 then IM.Focused = nil return end
	local idx = 0
	for i, e in ipairs(list) do
		if e.id == IM.Focused then idx = i break end
	end
	idx = idx + dir
	if idx < 1 then idx = #list elseif idx > #list then idx = 1 end
	SetFocus(list[idx].id)
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

-- ── Keybind Registry ─────────────────────────────────────────────────────────
local BINDS = {
	{ id = "focus_next",  name = "Focus Next Panel",       default = KEY_RIGHT,    action = function() CycleFocus(1) end },
	{ id = "focus_prev",  name = "Focus Previous Panel",   default = KEY_LEFT,     action = function() CycleFocus(-1) end },
	{ id = "tab_next",    name = "Next Tab (Group)",       default = KEY_RBRACKET, action = function() SwitchTab(1) end },
	{ id = "tab_prev",    name = "Previous Tab (Group)",   default = KEY_LBRACKET, action = function() SwitchTab(-1) end },
	{ id = "equip_tool",  name = "Equip Focused Tool",     default = KEY_ENTER,    action = EquipFocusedTool },
	{ id = "toggle_hide", name = "Hide / Show Focused",    default = KEY_NONE,     action = ToggleFocusedHidden },
	{ id = "bring_front", name = "Bring Focused To Front", default = KEY_NONE,     action = BringFocusedFront },
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

-- ── Poller ───────────────────────────────────────────────────────────────────
hook.Add("Think", "PinnedPanels_KeyNav", function()
	if not KeyboardNavEnabled() then return end
	if IsValid(vgui.GetKeyboardFocus()) then return end
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

local bindToButton = {
	["+attack"] = IN_ATTACK,
	["+attack2"] = IN_ATTACK2,
	["+jump"] = IN_JUMP,
	["+duck"] = IN_DUCK,
	["+forward"] = IN_FORWARD,
	["+back"] = IN_BACK,
	["+use"] = IN_USE,
	["+moveleft"] = IN_MOVELEFT,
	["+moveright"] = IN_MOVERIGHT,
	["+left"] = IN_LEFT,
	["+right"] = IN_RIGHT,
	["+reload"] = IN_RELOAD,
	["+alt1"] = IN_ALT1,
	["+alt2"] = IN_ALT2,
	["+score"] = IN_SCORE,
	["+speed"] = IN_SPEED,
	["+walk"] = IN_WALK,
	["+zoom"] = IN_ZOOM,
}

hook.Add("CreateMove", "PinnedPanels_KeyNavSuppressMove", function(cmd)
	if not KeyboardNavEnabled() then return end
	if IsValid(vgui.GetKeyboardFocus()) then return end

	local buttons = cmd:GetButtons()

	for _, b in ipairs(PinnedPanels.Keybinds) do
		local k = b.key
		if k and k ~= KEY_NONE and input.IsKeyDown(k) then
			local bindName = input.LookupKeyBinding(k)
			if bindName then
				local btn = bindToButton[bindName]
				if btn then
					buttons = bit.band(buttons, bit.bnot(btn))
				end
				
				if bindName == "+forward" or bindName == "+back" then
					cmd:SetForwardMove(0)
				elseif bindName == "+moveleft" or bindName == "+moveright" then
					cmd:SetSideMove(0)
				end
			end

			-- Arrow keys are often bound to turning or moving, ensure they are blocked
			if k == KEY_LEFT then
				buttons = bit.band(buttons, bit.bnot(IN_LEFT))
				buttons = bit.band(buttons, bit.bnot(IN_MOVELEFT))
				cmd:SetSideMove(0)
			elseif k == KEY_RIGHT then
				buttons = bit.band(buttons, bit.bnot(IN_RIGHT))
				buttons = bit.band(buttons, bit.bnot(IN_MOVERIGHT))
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

	for _, b in ipairs(PinnedPanels.Keybinds) do
		local k = b.key
		if k and k ~= KEY_NONE and input.IsKeyDown(k) then
			local bindName = input.LookupKeyBinding(k)
			if bindName and bindName == bind then
				return true
			end
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
