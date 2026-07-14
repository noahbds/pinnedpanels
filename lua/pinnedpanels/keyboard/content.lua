-- ── Keyboard Navigation: In-Panel Content Navigation ─────────────────────────
local KB = PinnedPanels._KB
local IM = KB.IM

local IsKeyDown = input.IsKeyDown

-- ── Tunables ─────────────────────────────────────────────────────────────────
local SCROLL_MARGIN    = 20 -- px of breathing room when scrolling an element into view
local SPATIAL_EPSILON  = 2  -- min centre delta (px) to count movement in a direction
local PERP_WEIGHT      = 4  -- how strongly off-axis distance is penalised

-- Remembers the last-focused element per panel so re-entering content nav lands
-- back where the user left off.
local navMemory = {}

-- ── Enter / Exit ─────────────────────────────────────────────────────────────
function KB.ExitContentNav()
    if IM.Focused and not IsValid(IM.NavPopup) then
        navMemory[IM.Focused] = PinnedPanels.GetNavElements()[IM.NavFocusIndex]
    end
    IM.NavPopup = nil
    IM.NavigatingPanel = false
    IM.SelectedIndex = nil
    KB.StopAllRepeats()
    KB.navKeyDown = {}
    if PinnedPanels.UpdatePanelStates then PinnedPanels.UpdatePanelStates() end
end

function PinnedPanels.SetNavPopup(frame)
    if IsValid(frame) then
        IM.NavPopup        = frame
        IM.NavigatingPanel = true
        IM.NavFocusIndex   = KB.TopMostIndex(PinnedPanels.GetNavElements())
        IM.SelectedIndex   = nil
        KB.ResetNavKeyState()
    elseif IM.NavPopup ~= nil then
        KB.ExitContentNav()
    end
end

function KB.EnterContentNav()
    local pin = KB.FocusedPin()
    if IM.NavigatingPanel or not pin or not IsValid(pin.frame) then return end
    IM.NavigatingPanel = true

    local elems = PinnedPanels.GetNavElements()
    local idx
    local mem = navMemory[IM.Focused]
    if IsValid(mem) then
        for i, el in ipairs(elems) do
            if el == mem then
                idx = i; break
            end
        end
    end
    IM.NavFocusIndex = idx or KB.TopMostIndex(elems)

    IM.SelectedIndex = nil
    IM.LastNavPanel = IM.Focused
    KB.ResetNavKeyState()
    if PinnedPanels.UpdatePanelStates then PinnedPanels.UpdatePanelStates() end
end

-- ── Scrolling & Geometry ─────────────────────────────────────────────────────
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
                    vbar:SetScroll(vbar:GetScroll() + (ey - py) - SCROLL_MARGIN)
                elseif ey + eh > py + ph then
                    vbar:SetScroll(vbar:GetScroll() + (ey + eh - (py + ph)) + SCROLL_MARGIN)
                end
            end
        end
        p = p:GetParent()
    end
end

local function ElementRect(el)
    local x, y = el:LocalToScreen(0, 0)
    local w, h = el:GetSize()
    return x, y, w, h, x + w / 2, y + h / 2
end

-- ── Spatial Move ─────────────────────────────────────────────────────────────
-- Picks the best neighbouring element in the pressed direction. Elements whose
-- perpendicular span overlaps the focused element are preferred; otherwise the
-- nearest off-axis candidate wins (vertical moves only). Rects are read live so
-- navigation stays correct while panels scroll or animate.
local function SpatialMove(elements, focusEl, key)
    local cls = focusEl.ClassName or focusEl:GetClassName()
    if cls == "DTree_Node_Button" then
        local p = focusEl:GetParent()
        if IsValid(p) and (p.ClassName == "DTree_Node" or p:GetClassName() == "DTree_Node") then
            if key == KEY_RIGHT and not p:GetExpanded() then
                p:SetExpanded(true)
                return
            end
            if key == KEY_LEFT and p:GetExpanded() then
                p:SetExpanded(false)
                return
            end
        end
    end

    local fx, fy, fw, fh, fcx, fcy = ElementRect(focusEl)
    local horiz                    = (key == KEY_LEFT or key == KEY_RIGHT)

    local bestOver, bestOverIdx    = math.huge, nil
    local bestAny, bestAnyIdx      = math.huge, nil

    for i, el in ipairs(elements) do
        if el ~= focusEl and IsValid(el) then
            local ex, ey, ew, eh, ecx, ecy = ElementRect(el)
            local dx, dy = ecx - fcx, ecy - fcy

            local valid = false
            if key == KEY_LEFT then
                valid = dx < -SPATIAL_EPSILON
            elseif key == KEY_RIGHT then
                valid = dx > SPATIAL_EPSILON
            elseif key == KEY_UP then
                valid = dy < -SPATIAL_EPSILON
            else
                valid = dy > SPATIAL_EPSILON
            end

            if valid then
                local overlap = horiz and (ey < fy + fh) and (fy < ey + eh) or (ex < fx + fw) and (fx < ex + ew)
                local score = horiz and (math.abs(dx) + math.abs(dy) * PERP_WEIGHT) or
                    (math.abs(dy) + math.abs(dx) * PERP_WEIGHT)

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
        KB.ExitContentNav()
    end
end

-- ── Per-Frame Content Nav ────────────────────────────────────────────────────
function KB.HandleContentNav()
    if not IsValid(IM.NavPopup) then
        local pin = KB.FocusedPin()
        if not pin or not IsValid(pin.frame) or IM.Focused ~= IM.LastNavPanel then
            KB.ExitContentNav()
            return
        end
    end

    local elements = PinnedPanels.GetNavElements()
    IM.NavFocusIndex = (#elements == 0) and 1 or math.Clamp(IM.NavFocusIndex or 1, 1, #elements)

    local focusedEl = (#elements > 0 and IM.NavFocusIndex <= #elements) and elements[IM.NavFocusIndex] or nil
    local selectedEl = IM.SelectedIndex and elements[IM.SelectedIndex] or nil
    local oldIndex = IM.NavFocusIndex

    for key in pairs(KB.NAV_KEYS) do
        local down = IsKeyDown(key)
        local wasDown = KB.navKeyDown[key] or false

        if key == KEY_BACKSPACE then
            if down and not wasDown then
                if IM.SelectedIndex then IM.SelectedIndex = nil else KB.ExitContentNav() end
            end
        elseif key == KEY_ENTER then
            if down and not wasDown then
                local shiftHeld = IsKeyDown(KEY_LSHIFT) or IsKeyDown(KEY_RSHIFT)
                if shiftHeld and focusedEl then
                    KB.OpenElementContextMenu(focusedEl)
                elseif focusedEl then
                    KB.ActivateElement(focusedEl)
                end
            end
        elseif down then
            if not wasDown then KB.StartRepeat(key) end
            if not wasDown or KB.ShouldRepeat(key) then
                if IM.SelectedIndex and IsValid(selectedEl) then
                    local kind = KB.AdjustKind(selectedEl)
                    local consume = (kind == "2d" or kind == "vert") or
                        (kind == "1d" and (key == KEY_LEFT or key == KEY_RIGHT))
                    if consume then KB.AdjustValue(selectedEl, key) else IM.SelectedIndex = nil end
                else
                    if IsValid(focusedEl) then
                        SpatialMove(elements, focusedEl, key)
                    elseif key == KEY_DOWN and IM.NavFocusIndex < #elements then
                        IM.NavFocusIndex = IM.NavFocusIndex + 1
                    elseif key == KEY_UP and IM.NavFocusIndex > 1 then
                        IM.NavFocusIndex = IM.NavFocusIndex - 1
                    end
                end
            end
        else
            KB.StopRepeat(key)
        end

        KB.navKeyDown[key] = down
    end

    if IM.NavFocusIndex ~= oldIndex and focusedEl then ScrollIntoView(focusedEl) end
end
