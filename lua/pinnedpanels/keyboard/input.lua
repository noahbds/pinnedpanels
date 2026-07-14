-- ── Keyboard Navigation: Think Loop, Input Suppression & Cursor Handoff ───────
local KB = PinnedPanels._KB
local IM = KB.IM

local IsKeyDown = input.IsKeyDown
local NAV_KEYS  = KB.NAV_KEYS
local BINDS     = KB.binds

-- Idle timeouts (seconds).
local TASKBAR_IDLE     = 5 -- drop taskbar focus after this long with no input
local NAV_OPACITY_IDLE = 2 -- fade the nav-activity opacity boost after this long

-- ── Main Think Loop / Taskbar Handoff ────────────────────────────────────────
hook.Add("Think", "PinnedPanels_KeyNav", function()
    if IsValid(vgui.GetKeyboardFocus()) then return end

    local anyNavDown = false
    for k in pairs(NAV_KEYS) do
        if IsKeyDown(k) then
            anyNavDown = true
            break
        end
    end
    if not anyNavDown then
        for _, b in ipairs(BINDS) do
            if b.key and b.key ~= KEY_NONE and IsKeyDown(b.key) then
                anyNavDown = true
                break
            end
        end
    end

    if anyNavDown then
        IM.LastNavActivity = CurTime()
        if not IM._navOpacityActive then
            IM._navOpacityActive = true
            if PinnedPanels.UpdatePanelStates then PinnedPanels.UpdatePanelStates() end
        end
    end

    if IM._navOpacityActive and CurTime() - (IM.LastNavActivity or 0) > NAV_OPACITY_IDLE then
        IM._navOpacityActive = false
        if PinnedPanels.UpdatePanelStates then PinnedPanels.UpdatePanelStates() end
    end

    if IM.ActiveMenu then
        KB.HandleMenuNav()
        return
    end

    if not PinnedPanels.IsKeyboardNavEnabled() then
        if IM.NavigatingPanel then KB.ExitContentNav() end
        if PinnedPanels.UnfocusTaskbar then PinnedPanels.UnfocusTaskbar() end
        KB.StopAllRepeats()
        return
    end

    KB.EnsureFocusValid()

    if IM.Focused == "__TASKBAR__" then
        local TB = PinnedPanels.Taskbar
        if TB and not TB.kbFocused and PinnedPanels.FocusTaskbar then
            PinnedPanels.FocusTaskbar()
        end

        if IsKeyDown(KEY_LEFT) or IsKeyDown(KEY_RIGHT)
            or IsKeyDown(KEY_UP) or IsKeyDown(KEY_DOWN) or IsKeyDown(KEY_ENTER) then
            IM._taskbarLastInput = CurTime()
        end

        local idle = IM._taskbarLastInput and (CurTime() - IM._taskbarLastInput > TASKBAR_IDLE)
        if IsKeyDown(KEY_BACKSPACE) or (idle and not PinnedPanels.PanelsInteractive()) then
            if PinnedPanels.UnfocusTaskbar then PinnedPanels.UnfocusTaskbar() end
            return
        end

        KB.HandleGlobalBinds(true)
    elseif IM.NavigatingPanel then
        if PinnedPanels.UnfocusTaskbar then PinnedPanels.UnfocusTaskbar() end
        KB.HandleContentNav()
        KB.HandleGlobalBinds(false)
    else
        if PinnedPanels.UnfocusTaskbar then PinnedPanels.UnfocusTaskbar() end
        KB.HandleGlobalBinds(true)
    end
end)

-- ── Input Suppression ────────────────────────────────────────────────────────
-- Maps a movement bind name to its IN_* button bit, so held nav keys that are
-- also bound to movement don't leak into the player's usercmd.
local bindToButton = {
    ["+attack"]    = IN_ATTACK,
    ["+attack2"]   = IN_ATTACK2,
    ["+jump"]      = IN_JUMP,
    ["+duck"]      = IN_DUCK,
    ["+forward"]   = IN_FORWARD,
    ["+back"]      = IN_BACK,
    ["+use"]       = IN_USE,
    ["+moveleft"]  = IN_MOVELEFT,
    ["+moveright"] = IN_MOVERIGHT,
    ["+left"]      = IN_LEFT,
    ["+right"]     = IN_RIGHT,
    ["+reload"]    = IN_RELOAD,
    ["+speed"]     = IN_SPEED,
    ["+walk"]      = IN_WALK,
}

local function IsCapturedKey(k)
    if not k or k == KEY_NONE then return false end
    if IM.ActiveMenu and (k == KEY_UP or k == KEY_DOWN or k == KEY_ENTER or k == KEY_BACKSPACE or k == KEY_LEFT or k == KEY_RIGHT) then return true end
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
        if not IsCapturedKey(k) or not IsKeyDown(k) then return end
        local bind = input.LookupKeyBinding(k)
        if bind then
            local btn = bindToButton[bind]
            if btn then buttons = bit.band(buttons, bit.bnot(btn)) end
            if bind == "+forward" or bind == "+back" then cmd:SetForwardMove(0) end
            if bind == "+moveleft" or bind == "+moveright" then cmd:SetSideMove(0) end
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

    for _, b in ipairs(BINDS) do suppress(b.key) end
    if IM.NavigatingPanel then for k in pairs(NAV_KEYS) do suppress(k) end end

    cmd:SetButtons(buttons)
end)

hook.Add("PlayerBindPress", "PinnedPanels_KeyNavSuppressBind", function(ply, bind, pressed, code)
    if not PinnedPanels.IsKeyboardNavEnabled() or IsValid(vgui.GetKeyboardFocus()) then return end
    if code and IsCapturedKey(code) then return true end
end)

-- ── Cursor Mode Handoff ──────────────────────────────────────────────────────
local _prevInteractive = false
hook.Add("PinnedPanels_CursorModeChanged", "PinnedPanels_KeyNavFocus", function(interactive)
    if _prevInteractive and not interactive and IM.NavigatingPanel then
        KB.ExitContentNav()
    end
    _prevInteractive = interactive

    if not IM.Active then return end
    local cur = KB.FocusedPin()
    if not cur or not IsValid(cur.frame) or not cur.frame:IsVisible() then
        local list = KB.VisibleTopLevelPins()
        IM.Focused = list[1] and list[1].id or nil
    end
end)
