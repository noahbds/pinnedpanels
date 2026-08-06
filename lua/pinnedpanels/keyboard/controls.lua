-- ── Keyboard Navigation: Control Activation & Value Adjustment ────────────────
local KB = PinnedPanels._KB
local IM = KB.IM

-- ── Tunables ─────────────────────────────────────────────────────────────────
local COLOR_DIG_DEPTH  = 5
local OWNER_MIXER_DEPTH = 6
local HSV_MIN          = 0.05
local HUE_STEP         = 8
local SV_STEP          = 0.04
local ALPHABAR_STEP    = 0.04
local COLOR_ALPHA_STEP = 10
local SLIDER_STEPS     = 30

-- ── Colour Control Resolution ────────────────────────────────────────────────
local function ColorTarget(el)
    if not IsValid(el) then return nil end
    local cls = el.ClassName or el:GetClassName()
    if cls:find("ColorCube") then return el, cls end
    if not cls:find("Color") then return nil end

    local found, fcls
    local function dig(p, d)
        if not IsValid(p) or d > COLOR_DIG_DEPTH or found then return end
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

    if isfunction(el.GetColor) and isfunction(el.SetColor) and not isfunction(el.DoClick) then
        return el, cls
    end
    return nil
end
PinnedPanels._ColorTarget = ColorTarget

local function OwnerMixer(el)
    local p = el:GetParent()
    for _ = 1, OWNER_MIXER_DEPTH do
        if not IsValid(p) then return nil end
        if IsValid(p.HSV) and isfunction(p.GetColor) and isfunction(p.SetColor) then
            return p
        end
        p = p:GetParent()
    end
    return nil
end

-- ── HTML Panel Scrolling ─────────────────────────────────────────────────────
-- DHTML/HTML panels (Panel:SetHTML) carry no VBar, so scroll them via JS. The
-- scroll container varies: DCodeViewer overflows a ".viewport" div, while a
-- plain page scrolls the document, so target whichever actually scrolls.
local SCROLL_JS = "(function(){var v=document.querySelector('.viewport')||" ..
    "document.scrollingElement||document.documentElement||document.body;" ..
    "if(v){v.scrollTop+=(%d);v.scrollLeft+=(%d);}})();"

function KB.ScrollHTML(html, key)
    if not KB.IsHTMLPanel(html) or not isfunction(html.RunJavascript) then return end
    local w, h = html:GetSize()
    local stepV = math.max(40, math.floor(h * 0.12))
    local stepH = math.max(40, math.floor(w * 0.12))
    local dy, dx = 0, 0
    if key == KEY_DOWN then dy = stepV
    elseif key == KEY_UP then dy = -stepV
    elseif key == KEY_RIGHT then dx = stepH
    elseif key == KEY_LEFT then dx = -stepH
    else return end
    html:RunJavascript(SCROLL_JS:format(dy, dx))
end

-- ── Adjust Kind ──────────────────────────────────────────────────────────────
function KB.AdjustKind(el)
    if not IsValid(el) then return nil end
    local cls = el.ClassName or el:GetClassName()
    if KB.IsHTMLPanel(el) then return "scroll" end
    if cls == "DRGBPicker" or cls == "DAlphaBar" then return "vert" end
    if cls:find("Slider") or cls == "DComboBox" then return "1d" end
    if ColorTarget(el) then return "2d" end
    return nil
end

-- ── Adjust Value ─────────────────────────────────────────────────────────────
local function AdjustRGBPicker(el, key)
    local mixer = OwnerMixer(el)
    if not mixer then return end
    local col = mixer:GetColor()
    local h, s, v = ColorToHSV(col)
    if s < HSV_MIN then s = 1 end
    if v < HSV_MIN then v = 1 end
    local step = (key == KEY_UP or key == KEY_RIGHT) and HUE_STEP or -HUE_STEP
    local nc = HSVToColor((h + step) % 360, s, v)
    nc.a = col.a or 255
    mixer:SetColor(nc)
end

local function AdjustAlphaBar(el, key)
    local step = (key == KEY_UP or key == KEY_RIGHT) and ALPHABAR_STEP or -ALPHABAR_STEP
    local v = math.Clamp((tonumber(el:GetValue()) or 1) + step, 0, 1)
    el:SetValue(v)
    if isfunction(el.OnChange) then el:OnChange(v) end
end

local function AdjustColorCube(tgt, key)
    local col = (isfunction(tgt.GetRGB) and tgt:GetRGB()) or (isfunction(tgt.GetColor) and tgt:GetColor()) or
        Color(255, 255, 255)
    local h, s, v = ColorToHSV(col)
    if key == KEY_LEFT then
        s = math.Clamp(s + SV_STEP, 0, 1)
    elseif key == KEY_RIGHT then
        s = math.Clamp(s - SV_STEP, 0, 1)
    elseif key == KEY_UP then
        v = math.Clamp(v + SV_STEP, 0, 1)
    elseif key == KEY_DOWN then
        v = math.Clamp(v - SV_STEP, 0, 1)
    end

    local nc = HSVToColor(h, s, v)
    if isfunction(tgt.SetColor) then tgt:SetColor(nc) end
    if isfunction(tgt.OnUserChanged) then tgt:OnUserChanged(nc) end
end

local function AdjustColorMixer(tgt, key)
    local col = (isfunction(tgt.GetColor) and tgt:GetColor()) or Color(255, 255, 255)
    local h, s, v = ColorToHSV(col)
    local a = col.a or 255
    local shift = input.IsKeyDown(KEY_LSHIFT) or input.IsKeyDown(KEY_RSHIFT)

    if shift then
        if key == KEY_LEFT then
            s = math.Clamp(s + SV_STEP, 0, 1)
        elseif key == KEY_RIGHT then
            s = math.Clamp(s - SV_STEP, 0, 1)
        elseif key == KEY_UP then
            a = math.Clamp(a + COLOR_ALPHA_STEP, 0, 255)
        elseif key == KEY_DOWN then
            a = math.Clamp(a - COLOR_ALPHA_STEP, 0, 255)
        end
    else
        if key == KEY_LEFT then
            h = (h - HUE_STEP) % 360
        elseif key == KEY_RIGHT then
            h = (h + HUE_STEP) % 360
        elseif key == KEY_UP then
            v = math.Clamp(v + SV_STEP, 0, 1)
        elseif key == KEY_DOWN then
            v = math.Clamp(v - SV_STEP, 0, 1)
        end
    end

    local nc = HSVToColor(h, s, v)
    nc.a = math.Round(a)
    if isfunction(tgt.SetColor) then tgt:SetColor(nc) end
end

local AdjustHandlers = {
    slider = function(el, key, dir)
        local mn, mx = tonumber(el:GetMin()) or 0, tonumber(el:GetMax()) or 100
        local cur = tonumber(el:GetValue()) or mn
        local newVal = math.Clamp(cur + (mx - mn) / SLIDER_STEPS * dir, mn, mx)
        el:SetValue(newVal)
        if isfunction(el.OnValueChanged) then el:OnValueChanged(newVal) end
    end,
    checkbox = function(el, key)
        local v = (key == KEY_RIGHT)
        if el.SetValue then el:SetValue(v) elseif el.SetChecked then el:SetChecked(v) end
    end,
    combobox = function(el, key, dir)
        if not (isfunction(el.ChooseOptionID) and el.Choices) then return end
        local n = #el.Choices
        if n > 0 then
            local id = (el:GetSelectedID() or 1) + dir
            id = (id - 1) % n + 1
            el:ChooseOptionID(id)
        end
    end,
}

local function AdjustSimpleKind(cls)
    if cls:find("Slider") then return "slider" end
    if cls:find("CheckBox") then return "checkbox" end
    if cls == "DComboBox" then return "combobox" end
    return nil
end

function KB.AdjustValue(el, key)
    local cls = el.ClassName or el:GetClassName()
    local dir = (key == KEY_RIGHT) and 1 or -1

    if KB.IsHTMLPanel(el) then
        KB.ScrollHTML(el, key)
        return
    end

    if cls == "DRGBPicker" then
        AdjustRGBPicker(el, key)
        return
    end
    if cls == "DAlphaBar" then
        AdjustAlphaBar(el, key)
        return
    end

    local tgt, tcls = ColorTarget(el)
    if tgt then
        if tcls:find("ColorCube") then
            AdjustColorCube(tgt, key)
        else
            AdjustColorMixer(tgt, key)
        end
        return
    end

    local handler = AdjustHandlers[AdjustSimpleKind(cls)]
    if handler then handler(el, key, dir) end
end

-- ── Element Activation (Enter) ───────────────────────────────────────────────
local ActivateHandlers = {
    textentry = function(el)
        local pin = KB.FocusedPin()
        if pin and IsValid(pin.frame) then
            pin.frame:SetKeyboardInputEnabled(true)
        end
        el:SetKeyboardInputEnabled(true)
        el:RequestFocus()
        IM.NavigatingPanel = false
        IM.SelectedIndex = nil
    end,
    treenode = function(el)
        local p = el:GetParent()
        if IsValid(p) and p.InternalDoClick then
            p:InternalDoClick()
        elseif isfunction(el.DoClick) then
            el:DoClick()
        end
        IM.SelectedIndex = nil
    end,
    checkbox = function(el)
        if el.Toggle then el:Toggle() elseif el.SetValue then el:SetValue(not el:GetChecked()) end
    end,
}

local ACTIVATE_EXACT = {
    DTextEntry        = "textentry",
    DNumberWang       = "textentry",
    TextEntry         = "textentry",
    DTree_Node_Button = "treenode",
}

local function ActivateType(cls)
    if ACTIVATE_EXACT[cls] then return ACTIVATE_EXACT[cls] end
    if cls:find("CheckBox") then return "checkbox" end
    return nil
end

function KB.ActivateElement(el)
    if IM.SelectedIndex then
        IM.SelectedIndex = nil
        return
    end
    IM.SelectedIndex = IM.NavFocusIndex

    if KB.AdjustKind(el) then
        return
    end

    local cls = el.ClassName or el:GetClassName()
    local handler = ActivateHandlers[ActivateType(cls)]
    if handler then
        handler(el)
        return
    end

    if isfunction(el.DoClick) then
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
