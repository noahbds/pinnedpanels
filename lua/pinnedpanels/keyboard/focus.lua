-- ── Keyboard Navigation: Focus, Panel & Tab Navigation, Panel Actions ─────────
local KB = PinnedPanels._KB
local IM = KB.IM

-- ── Focus Helpers ────────────────────────────────────────────────────────────
function KB.VisibleTopLevelPins()
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

    local ts = PinnedPanels.Settings and PinnedPanels.Settings.taskbar
    if #minimized > 0 and ts and ts.enabled ~= false then
        list[#list + 1] = { id = "__TASKBAR__", title = "~Taskbar" }
    end

    return list
end

function KB.FocusedPin()
    return IM.Focused and PinnedPanels.Pins[IM.Focused] or nil
end

-- Pure check – no side effects
function PinnedPanels.IsKeyboardNavEnabled()
    if not IM.Active and not (PinnedPanels.Settings and PinnedPanels.Settings.keyboardNavOutsideCursorMode) then
        return false
    end

    for id, pin in pairs(PinnedPanels.Pins) do
        if IsValid(pin.frame) and pin.frame:IsVisible() then
            return true
        end
    end

    local minimized = PinnedPanels.GetMinimizedPanels()
    local ts = PinnedPanels.Settings and PinnedPanels.Settings.taskbar
    if IM.Active and #minimized > 0 and ts and ts.enabled ~= false then
        return true
    end

    return false
end

-- Ensures a valid focus when navigation is active
function KB.EnsureFocusValid()
    if IM.Focused == "__TASKBAR__" then return end

    local f = IM.Focused and PinnedPanels.Pins[IM.Focused]
    if f and IsValid(f.frame) and f.frame:IsVisible() then return end

    for id, pin in pairs(PinnedPanels.Pins) do
        if IsValid(pin.frame) and pin.frame:IsVisible() then
            IM.Focused = id
            return
        end
    end

    -- No visible panels, try taskbar
    if IM.Active then
        local minimized = PinnedPanels.GetMinimizedPanels()
        if #minimized > 0 and PinnedPanels.Settings.taskbar and PinnedPanels.Settings.taskbar.enabled ~= false then
            IM.Focused = "__TASKBAR__"
        end
    end
end

-- ── Panel & Tab Navigation ───────────────────────────────────────────────────
function KB.SetFocus(id, dir)
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
        if PinnedPanels.FocusTaskbar then PinnedPanels.FocusTaskbar() end
        return
    end

    if PinnedPanels.UnfocusTaskbar then PinnedPanels.UnfocusTaskbar() end
    local pin = id and PinnedPanels.Pins[id]
    if pin and IsValid(pin.frame) then pin.frame:MoveToFront() end
    if PinnedPanels.UpdatePanelStates then PinnedPanels.UpdatePanelStates() end
end

function KB.CycleFocus(dir)
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

    local list = KB.VisibleTopLevelPins()
    if #list == 0 then
        IM.Focused = nil; return
    end

    local idx = 1
    for i, e in ipairs(list) do
        if e.id == IM.Focused then
            idx = i; break
        end
    end

    idx = (idx - 1 + dir) % #list + 1
    KB.SetFocus(list[idx].id, dir)
end

function KB.SwitchTab(dir)
    local pin = KB.FocusedPin()
    if not pin or pin.kind ~= "group" or not IsValid(pin.sheet) then return end

    local items = pin.sheet:GetItems()
    if #items <= 1 then return end

    local active = pin.sheet:GetActiveTab()
    local idx = 1
    for i, item in ipairs(items) do
        if item.Tab == active then
            idx = i; break
        end
    end

    idx = (idx - 1 + dir) % #items + 1
    pin.sheet:SetActiveTab(items[idx].Tab)
end

-- ── Panel Actions ────────────────────────────────────────────────────────────
function KB.EquipFocusedTool()
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
                KB.SetFocus(id)
            else
                TB.hoverIndex = math.Clamp(sel, 1, #remaining)
            end
        end
        return
    end

    local toolClass = PinnedPanels.GetPinTool(IM.Focused)
    if not toolClass then return end
    PinnedPanels.EquipToolgun(toolClass)
    if PinnedPanels.CursorMode.Disable then PinnedPanels.CursorMode.Disable() end
end

function KB.ToggleFocusedHidden()
    local pin = KB.FocusedPin()
    if not pin or not IsValid(pin.frame) then return end
    pin.frame:SetVisible(not pin.frame:IsVisible())
    if not pin.frame:IsVisible() then KB.CycleFocus(1) end
end

function KB.BringFocusedFront()
    local pin = KB.FocusedPin()
    if pin and IsValid(pin.frame) then
        pin.frame:SetVisible(true)
        pin.frame:MoveToFront()
    end
end

function KB.MinimizeFocused()
    if IM.Focused and IM.Focused ~= "__TASKBAR__" then
        PinnedPanels.MinimizeToTaskbar(IM.Focused)
        KB.CycleFocus(1)
    end
end

function KB.MaximizeFocused()
    if IM.Focused and IM.Focused ~= "__TASKBAR__" then
        PinnedPanels.ToggleMaximizePanel(IM.Focused)
    end
end

function KB.UnpinFocused()
    if IM.Focused and IM.Focused ~= "__TASKBAR__" then
        local target = IM.Focused
        KB.CycleFocus(1)
        PinnedPanels.Unpin(target)
    end
end
