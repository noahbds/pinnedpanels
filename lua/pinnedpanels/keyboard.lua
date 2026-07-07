-- ── Keyboard Navigation ──────────────────────────────────────────────────────
local IM = PinnedPanels.CursorMode
--------------------------------------------------------------------
-- Utility functions
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

function PinnedPanels.IsKeyboardNavEnabled()
    -- Active by default whenever there is at least one visible pinned panel
    if not PinnedPanels.Pins then return false end
    for id, pin in pairs(PinnedPanels.Pins) do
        if IsValid(pin.frame) and pin.frame:IsVisible() then
            if not IM.Focused or not PinnedPanels.Pins[IM.Focused] then
                IM.Focused = id -- automatically focus the first found if none is focused
            end
            return true
        end
    end
    return false
end
local KeyboardNavEnabled = PinnedPanels.IsKeyboardNavEnabled

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
-- Cycle panels / tabs
--------------------------------------------------------------------
local function CycleFocus(dir)
    local list = VisibleTopLevelPins()
    if #list == 0 then IM.Focused = nil return end

    local idx = 1
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

--------------------------------------------------------------------
-- Other actions
--------------------------------------------------------------------
local function EquipFocusedTool()
    if not IM.Focused then return end
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

--------------------------------------------------------------------
-- Interactive elements scanner (improved)
--------------------------------------------------------------------
function PinnedPanels.GetInteractiveElements(panel)
    local list = {}
    if not IsValid(panel) then return list end

    local function Scan(p, depth)
        if not IsValid(p) then return end
        depth = depth or 0
        if depth > 15 then return end

        if not p:IsVisible() then return end

        local class = p.ClassName or p:GetClassName()

        -- Ignore non-interactive static elements
        if class == "DLabel" or class == "Label" or class == "DImage" or class == "Image" or class == "DDivider" or class == "Divider" or 
           class == "DTree_Node_Button" or class == "DExpandButton" then 
            return 
        end

        -- === VERY AGGRESSIVE TARGETING ===
        if class:find("Slider") or class:find("CheckBox") or class == "DButton" or 
           class == "DComboBox" or class == "DTextEntry" or class == "DNumSlider" or class:find("Color") or class == "DTree_Node" then
            table.insert(list, p)
            if class ~= "DTree_Node" then return end
        end

        local isContainer = (class == "ControlPanel" or class == "DForm" or class == "DCollapsibleCategory" or 
                             class == "DScrollPanel" or class == "DPanel" or class == "DPropertySheet" or 
                             class == "DFrame" or class == "DCategoryList" or class == "DTree" or 
                             class == "DTree_Node" or class == "DListLayout")

        if not isContainer then
            if isfunction(p.SetValue) and isfunction(p.GetValue) then
                table.insert(list, p)
                return
            end

            if isfunction(p.DoClick) or isfunction(p.Toggle) then
                table.insert(list, p)
                return
            end
        end

        -- Recurse everything
        for _, child in ipairs(p:GetChildren()) do
            Scan(child, depth + 1)
        end
    end

    Scan(panel)
    return list
end

--------------------------------------------------------------------
-- Debug command
--------------------------------------------------------------------
concommand.Add("pp_debug_nav", function()
    local pin = IM.Focused and PinnedPanels.Pins[IM.Focused]
    if not pin then 
        print("[pp_debug_nav] No focused pin.") 
        return 
    end
    
    local els = PinnedPanels.GetInteractiveElements(pin.frame)
    print("=== PinnedPanels Debug ===")
    print("Focused panel: " .. tostring(pin.title))
    print("Found " .. #els .. " interactive elements:")
    
    for i, el in ipairs(els) do
        local class = el.ClassName or el:GetClassName()
        local name = el.GetName and el:GetName() or "unnamed"
        print(string.format("%2d | %-20s | %s | Visible: %s", i, class, name, tostring(el:IsVisible())))
    end
end)

--------------------------------------------------------------------
-- Key repeat
--------------------------------------------------------------------
local KEY_REPEAT_INITIAL_DELAY = 0.35
local KEY_REPEAT_INTERVAL = 0.055
local keyRepeatTimers = {}

local function StartKeyRepeat(key)
    keyRepeatTimers[key] = { startTime = CurTime(), lastAction = 0, isRepeating = false }
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
    end

    if now - t.lastAction >= KEY_REPEAT_INTERVAL then
        t.lastAction = now
        return true
    end
    return false
end

--------------------------------------------------------------------
-- Binds
--------------------------------------------------------------------
local nav_keys = { [KEY_UP] = true, [KEY_DOWN] = true, [KEY_LEFT] = true, [KEY_RIGHT] = true,
                   [KEY_ENTER] = true, [KEY_ESCAPE] = true }

local BINDS = {
    { id = "focus_next",  name = "Focus Next Panel",       default = KEY_RIGHT,    action = function() CycleFocus(1) end },
    { id = "focus_prev",  name = "Focus Previous Panel",   default = KEY_LEFT,     action = function() CycleFocus(-1) end },
    { id = "tab_next",    name = "Next Tab (Group)",       default = KEY_RBRACKET, action = function() SwitchTab(1) end },
    { id = "tab_prev",    name = "Previous Tab (Group)",   default = KEY_LBRACKET, action = function() SwitchTab(-1) end },
    { id = "equip_tool",  name = "Equip Focused Tool",     default = KEY_ENTER,    action = EquipFocusedTool },
    { id = "toggle_hide", name = "Hide / Show Focused",    default = KEY_NONE,     action = ToggleFocusedHidden },
    { id = "bring_front", name = "Bring Focused To Front", default = KEY_NONE,     action = BringFocusedFront },
    { id = "enter_nav",   name = "Enter Panel Content Nav",default = KEY_DOWN,     action = function()
        local pin = FocusedPin()
        if not IM.NavigatingPanel and pin and IsValid(pin.frame) then
            IM.NavigatingPanel = true
            IM.NavFocusIndex = 1
            IM.SelectedIndex = nil
            IM.LastNavPanel = IM.Focused
            for k in pairs(keyRepeatTimers) do StopKeyRepeat(k) end
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
    cvars.AddChangeCallback(b.convar, function(_,_,new) b.key = tonumber(new) or KEY_NONE end, "PinnedPanels_KeyNav")
end

--------------------------------------------------------------------
-- Main Think hook
--------------------------------------------------------------------
local nav_keys_down = {}

hook.Add("Think", "PinnedPanels_KeyNav", function()
    if IsValid(vgui.GetKeyboardFocus()) then return end

    if not KeyboardNavEnabled() then
        IM.NavigatingPanel = false
        IM.SelectedIndex = nil
        for k in pairs(keyRepeatTimers) do StopKeyRepeat(k) end
        return
    end

    -- ==================== PANEL CONTENT NAVIGATION ====================
    if IM.NavigatingPanel then
        local pin = FocusedPin()
        if not pin or not IsValid(pin.frame) or IM.Focused ~= IM.LastNavPanel then
            IM.NavigatingPanel = false
            IM.SelectedIndex = nil
            for k in pairs(keyRepeatTimers) do StopKeyRepeat(k) end
            return
        end

        local elements = PinnedPanels.GetInteractiveElements(pin.frame)
        if #elements == 0 then
            IM.NavFocusIndex = 1
        else
            IM.NavFocusIndex = math.Clamp(IM.NavFocusIndex, 1, #elements)
        end

        local function GetFocusedElement()
            return (#elements > 0 and IM.NavFocusIndex <= #elements) and elements[IM.NavFocusIndex] or nil
        end

        -- === SAFE YELLOW HIGHLIGHT ===
        for i, el in ipairs(elements) do
            if IsValid(el) then
                if i == IM.NavFocusIndex then
                    -- Safe way to highlight
                    el:SetAlpha(255)
                    if el.SetDrawBorder then el:SetDrawBorder(true) end
                    if el.SetPaintBackground and el.SetBackgroundColor then
                        el:SetPaintBackground(true)
                        el:SetBackgroundColor(Color(255, 255, 0, 90))
                    end
                else
                    el:SetAlpha(230)
                    if el.SetBackgroundColor then
                        el:SetBackgroundColor(Color(0,0,0,0))
                    end
                end
            end
        end

        local selectedEl = IM.SelectedIndex and elements[IM.SelectedIndex] or nil
        local oldIndex = IM.NavFocusIndex

        for k in pairs(nav_keys) do
            local down = input.IsKeyDown(k)
            local wasDown = nav_keys_down[k] or false

            -- ESCAPE
            if k == KEY_ESCAPE then
                if down and not wasDown then
                    if IM.SelectedIndex then
                        IM.SelectedIndex = nil
                    else
                        IM.NavigatingPanel = false
                    end
                    for k2 in pairs(keyRepeatTimers) do StopKeyRepeat(k2) end
                end

            -- UP
            elseif k == KEY_ENTER then
                if down and not wasDown then
                    local el = GetFocusedElement()
                    if el then
                        local cls = el.ClassName or el:GetClassName()

                        if IM.SelectedIndex then
                            IM.SelectedIndex = nil
                        else
                            IM.SelectedIndex = IM.NavFocusIndex

                            if cls:find("Slider") or cls == "DComboBox" then
                                -- stay selected for arrow adjustment
                            elseif cls == "DTextEntry" then
                                el:RequestFocus()
                                IM.NavigatingPanel = false -- let user type
                            elseif cls == "DTree_Node" then
                                if el.InternalDoClick then el:InternalDoClick() end
                                IM.SelectedIndex = nil
                            elseif cls:find("CheckBox") then
                                if el.Toggle then el:Toggle() elseif el.SetValue then el:SetValue(not el:GetChecked()) end
                            elseif el.DoClick then
                                el:DoClick()
                                IM.SelectedIndex = nil
                            elseif el.Toggle then
                                el:Toggle()
                            end
                        end
                    end
                end

            elseif k == KEY_DOWN or k == KEY_UP or k == KEY_LEFT or k == KEY_RIGHT then
                if down then
                    if not wasDown then StartKeyRepeat(k) end
                    if ShouldRepeat(k) or not wasDown then
                        if IM.SelectedIndex and IsValid(selectedEl) then
                            if k == KEY_LEFT or k == KEY_RIGHT then
                                local dir = (k == KEY_RIGHT) and 1 or -1
                                local cls = selectedEl.ClassName or selectedEl:GetClassName()
                                if cls:find("Slider") then
                                    local val = selectedEl:GetValue()
                                    local min, max = selectedEl:GetMin(), selectedEl:GetMax()
                                    local step = (max - min) / 30
                                    selectedEl:SetValue(math.Clamp(val + step * dir, min, max))
                                    if selectedEl.OnValueChanged then selectedEl:OnValueChanged(selectedEl:GetValue()) end
                                elseif cls:find("CheckBox") then
                                    local newVal = (k == KEY_RIGHT)
                                    if selectedEl.SetValue then selectedEl:SetValue(newVal)
                                    elseif selectedEl.SetChecked then selectedEl:SetChecked(newVal) end
                                elseif cls == "DComboBox" then
                                    if selectedEl.ChooseOptionID and selectedEl.Choices then
                                        local numChoices = #selectedEl.Choices
                                        if numChoices > 0 then
                                            local currentId = selectedEl:GetSelectedID() or 1
                                            local newId = currentId + dir
                                            if newId < 1 then newId = numChoices end
                                            if newId > numChoices then newId = 1 end
                                            selectedEl:ChooseOptionID(newId)
                                        end
                                    end
                                end
                            else
                                -- UP/DOWN escapes selection mode
                                IM.SelectedIndex = nil
                            end
                        else
                            local focusEl = GetFocusedElement()
                            if IsValid(focusEl) then
                                local cls = focusEl.ClassName or focusEl:GetClassName()
                                local handled = false
                                
                                if cls == "DTree_Node" then
                                    if k == KEY_RIGHT and not focusEl:GetExpanded() then
                                        focusEl:SetExpanded(true)
                                        handled = true
                                    elseif k == KEY_LEFT and focusEl:GetExpanded() then
                                        focusEl:SetExpanded(false)
                                        handled = true
                                    end
                                end

                                if not handled then
                                    local cx, cy = focusEl:LocalToScreen(0, 0)
                                    local bestScore = math.huge
                                    local bestIndex = nil

                                    for i, el in ipairs(elements) do
                                        if el ~= focusEl and IsValid(el) then
                                            local ox, oy = el:LocalToScreen(0, 0)
                                            local dx = ox - cx
                                            local dy = oy - cy
                                            
                                            local valid = false
                                            local score = 0
                                            
                                            if k == KEY_LEFT and dx < -5 then
                                                valid = true
                                                score = math.abs(dx) + math.abs(dy) * 4
                                            elseif k == KEY_RIGHT and dx > 5 then
                                                valid = true
                                                score = math.abs(dx) + math.abs(dy) * 4
                                            elseif k == KEY_UP and dy < -5 then
                                                valid = true
                                                score = math.abs(dy) + math.abs(dx) * 4
                                            elseif k == KEY_DOWN and dy > 5 then
                                                valid = true
                                                score = math.abs(dy) + math.abs(dx) * 4
                                            end

                                            if valid and score < bestScore then
                                                bestScore = score
                                                bestIndex = i
                                            end
                                        end
                                    end

                                    if bestIndex then
                                        IM.NavFocusIndex = bestIndex
                                    else
                                        if k == KEY_DOWN and IM.NavFocusIndex < #elements then
                                            IM.NavFocusIndex = IM.NavFocusIndex + 1
                                        elseif k == KEY_UP then
                                            if IM.NavFocusIndex > 1 then
                                                IM.NavFocusIndex = IM.NavFocusIndex - 1
                                            else
                                                IM.NavigatingPanel = false
                                                for k2 in pairs(keyRepeatTimers) do StopKeyRepeat(k2) end
                                            end
                                        end
                                    end
                                end
                            else
                                if k == KEY_DOWN and IM.NavFocusIndex < #elements then
                                    IM.NavFocusIndex = IM.NavFocusIndex + 1
                                elseif k == KEY_UP and IM.NavFocusIndex > 1 then
                                    IM.NavFocusIndex = IM.NavFocusIndex - 1
                                end
                            end
                        end
                    end
                else
                    StopKeyRepeat(k)
                end
            end

            nav_keys_down[k] = down
        end

        if IM.NavFocusIndex ~= oldIndex then
            local focusEl = GetFocusedElement()
            if IsValid(focusEl) then
                local p = focusEl:GetParent()
                while IsValid(p) do
                    if p.GetVBar then
                        local vbar = p:GetVBar()
                        if IsValid(vbar) then
                            local _, ey = focusEl:LocalToScreen(0, 0)
                            local eh = focusEl:GetTall()
                            local _, py = p:LocalToScreen(0, 0)
                            local ph = p:GetTall()
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
        end

        return -- suppress global binds
    end

    -- ==================== GLOBAL BINDS ====================
    for _, b in ipairs(BINDS) do
        local k = b.key
        if k and k ~= KEY_NONE then
            local down = input.IsKeyDown(k)
            if down and not b.wasDown then
                b.action()
            end
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
		addKey(KEY_SPACE)
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

hook.Add("PinnedPanels_CursorModeChanged", "PinnedPanels_KeyNavFocus", function()
	if not IM.Active then return end
	local cur = FocusedPin()
	if not cur or not IsValid(cur.frame) or not cur.frame:IsVisible() then
		local list = VisibleTopLevelPins()
		IM.Focused = list[1] and list[1].id or nil
	end
end)

--------------------------------------------------------------------
-- Public API for settings
--------------------------------------------------------------------
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

print("[PinnedPanels] Keyboard navigation loaded successfully.")
