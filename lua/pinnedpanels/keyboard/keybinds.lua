-- ── Keyboard Navigation: Keybinds & Global Bind Dispatch ──────────────────────
local KB = PinnedPanels._KB
local IM = KB.IM

-- ── Navigation Keybinds ──────────────────────────────────────────────────────
local BINDS = {
    { id = "focus_next",       nameKey = "kb_focus_next",   default = KEY_RIGHT,    action = function()
        KB.CycleFocus(1) end },
    { id = "focus_prev",       nameKey = "kb_focus_prev",   default = KEY_LEFT,     action = function()
        KB.CycleFocus(-1) end },
    { id = "tab_next",         nameKey = "kb_tab_next",     default = KEY_RBRACKET, action = function()
        KB.SwitchTab(1) end },
    { id = "tab_prev",         nameKey = "kb_tab_prev",     default = KEY_LBRACKET, action = function()
        KB.SwitchTab(-1) end },
    { id = "enter_nav",        nameKey = "kb_enter_nav",    default = KEY_DOWN,     action = function()
        KB.EnterContentNav() end },
    { id = "equip_tool",       nameKey = "kb_equip_tool",   default = KEY_ENTER,    action = function()
        KB.EquipFocusedTool() end },
    { id = "toggle_hide",      nameKey = "kb_toggle_hide",  default = KEY_NONE,     action = function()
        KB.ToggleFocusedHidden() end },
    { id = "bring_front",      nameKey = "kb_bring_front",  default = KEY_NONE,     action = function()
        KB.BringFocusedFront() end },
    { id = "minimize_focused", nameKey = "kb_minimize",     default = KEY_NONE,     action = function()
        KB.MinimizeFocused() end },
    { id = "maximize_focused", nameKey = "kb_maximize",     default = KEY_NONE,     action = function()
        KB.MaximizeFocused() end },
    { id = "unpin_focused",    nameKey = "kb_unpin",        default = KEY_NONE,     action = function()
        KB.UnpinFocused() end },
    { id = "auto_arrange",     nameKey = "kb_auto_arrange", default = KEY_NONE,     action = function()
        if PinnedPanels.AutoArrange then PinnedPanels.AutoArrange() end end },
    {
        id = "autosize_focused",
        nameKey = "kb_autosize",
        default = KEY_NONE,
        action = function()
            if IM.Focused and IM.Focused ~= "__TASKBAR__" then PinnedPanels.AutoSizePanel(IM.Focused) end
        end
    },
    { id = "reopen_closed", nameKey = "kb_reopen", default = KEY_NONE, action = function()
        if PinnedPanels.ReopenLastClosed then PinnedPanels.ReopenLastClosed() end end },
}
-- Localized display name for a bind (falls back to the key slug).
for _, b in ipairs(BINDS) do
    b.name = PinnedPanels.L(b.nameKey)
end
PinnedPanels.Keybinds = BINDS
KB.binds = BINDS

local byId = {}
KB.byId = byId
for _, b in ipairs(BINDS) do
    byId[b.id] = b
    b.convar = "pp_key_" .. b.id
    local cv = CreateClientConVar(b.convar, tostring(b.default), true, false, "PinnedPanels: " .. b.name)
    b.key = tonumber(cv:GetString()) or b.default
    b.wasDown = false
    cvars.AddChangeCallback(b.convar, function(_, _, new) b.key = tonumber(new) or KEY_NONE end, "PinnedPanels_KeyNav")
end

-- ── Global Bind Dispatch ─────────────────────────────────────────────────────
function KB.HandleGlobalBinds(allowFire)
    local shiftHeld = input.IsKeyDown(KEY_LSHIFT) or input.IsKeyDown(KEY_RSHIFT)
    for _, b in ipairs(BINDS) do
        local k = b.key
        if k and k ~= KEY_NONE then
            local down = input.IsKeyDown(k)
            if allowFire and down and not b.wasDown then
                if b.id == "equip_tool" and shiftHeld then
                    KB.OpenContextMenuForFocused()
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
