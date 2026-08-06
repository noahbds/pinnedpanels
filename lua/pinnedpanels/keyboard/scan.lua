-- ── Keyboard Navigation: Interactive Element Scan (cached) ────────────────────
local KB = PinnedPanels._KB
local IM = KB.IM

-- ── Element Classification ───────────────────────────────────────────────────
local SKIP_CLASSES = {
    DLabel       = true,
    Label        = true,
    DImage       = true,
    Image        = true,
    DDivider     = true,
    Divider      = true,
    DExpandButton = true,
    DVScrollBar  = true,
    DHScrollBar  = true,
}

local COLOR_CONTAINERS = {
    DColorMixer = true, CtrlColor = true, DColorCombo = true, DColorPalette = true,
}

local CONTAINER_CLASSES = {
    ControlPanel          = true,
    DForm                 = true,
    DCollapsibleCategory  = true,
    DScrollPanel          = true,
    DPropertySheet        = true,
    DFrame                = true,
    DCategoryList         = true,
    DTree                 = true,
    DTree_Node            = true,
    DListLayout           = true,
    DIconLayout           = true,
    DTileLayout           = true,
    ContentContainer      = true,
    SpawnmenuContentPanel = true,
    DMenu                 = true,
    DMenuBar              = true,
}
for k in pairs(COLOR_CONTAINERS) do CONTAINER_CLASSES[k] = true end

local NAVIGABLE_EXACT = {
    DButton           = true,
    DImageButton      = true,
    DComboBox         = true,
    DTextEntry        = true,
    DNumSlider        = true,
    DTree_Node_Button = true,
    DRGBPicker        = true,
    DAlphaBar         = true,
    DNumberWang       = true,
}

local function IsNavigableLeaf(class)
    if NAVIGABLE_EXACT[class] then return true end
    if class:find("Slider") or class:find("CheckBox") then return true end
    if class:find("Color") and not COLOR_CONTAINERS[class] then return true end
    return false
end

-- ── Tunables ─────────────────────────────────────────────────────────────────
local SCAN_MAX_DEPTH   = 20
local MIN_ELEMENT_SIZE = 4
local NAV_CACHE_TTL    = 0.15
local MIN_CROP_VISIBLE = 8

local function CropVisible(el, ew, eh)
    local p = el:GetParent()
    while IsValid(p) do
        if p._pp_cropViewport then
            local vx, vy = p:LocalToScreen(0, 0)
            local vw, vh = p:GetSize()
            local ex, ey = el:LocalToScreen(0, 0)
            local visW = math.min(ex + ew, vx + vw) - math.max(ex, vx)
            local visH = math.min(ey + eh, vy + vh) - math.max(ey, vy)
            return visW >= MIN_CROP_VISIBLE and visH >= MIN_CROP_VISIBLE
        end
        p = p:GetParent()
    end
    return true
end

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
        if not IsValid(p) or depth > SCAN_MAX_DEPTH or p._pp_skipNav or not p:IsVisible() then return 0 end
        local class = p.ClassName or p:GetClassName()
        if SKIP_CLASSES[class] or class:find("ScrollBar") or class:find("Grip") then return 0 end

        -- HTML/DHTML panels (Panel:SetHTML) have no VBar and no navigable
        -- children; expose the panel itself so it can be focused and scrolled.
        if KB.IsHTMLPanel(p) then
            list[#list + 1] = p
            return 1
        end

        if IsNavigableLeaf(class) then
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
            if ew > MIN_ELEMENT_SIZE and eh > MIN_ELEMENT_SIZE and CropVisible(el, ew, eh) then
                result[#result + 1] = el
            end
        end
    end
    return result
end

-- ── Nav Cache ────────────────────────────────────────────────────────────────
local navCache = { frame = nil, expire = 0, list = {} }

function PinnedPanels.GetNavElements()
    local target = IsValid(IM.NavPopup) and IM.NavPopup or nil
    if not target then
        local pin = KB.FocusedPin()
        target = pin and IsValid(pin.frame) and pin.frame or nil
    end
    if not target then
        navCache.frame, navCache.list = nil, {}
        return navCache.list
    end
    if navCache.frame ~= target or CurTime() >= navCache.expire then
        navCache.frame  = target
        navCache.expire = CurTime() + NAV_CACHE_TTL
        navCache.list   = PinnedPanels.GetInteractiveElements(target)
    end
    return navCache.list
end

function KB.TopMostIndex(elems)
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
