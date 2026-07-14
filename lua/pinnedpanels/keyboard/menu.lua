-- ── Keyboard Navigation: Context-Menu Keyboard Nav ───────────────────────────
--
-- Garry's Mod context menus are mouse-driven DMenus. To drive them by keyboard
-- we capture the items a trigger would have created, then render our own
-- keyboard-navigable replica (CreateKeyboardMenu) and dispatch the captured
-- callbacks ourselves.
local KB = PinnedPanels._KB
local IM = KB.IM
local C  = KB.C

-- ── Menu Layout Constants ────────────────────────────────────────────────────
local ROW_H          = 22
local ICON_SZ        = 16
local PAD            = 6
local FONT           = "DermaDefault"
local MIN_W          = 160
local PROBE_ATTEMPTS = 10 -- how many ancestors to probe for a right-click menu

-- ── Replica Menu Panel ───────────────────────────────────────────────────────
local function CreateKeyboardMenu(items, x, y, parentMenu)
    if not items or #items == 0 then return nil end

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

    for k in pairs(KB.NAV_KEYS) do pnl._wasDown[k] = input.IsKeyDown(k) end

    for _, it in ipairs(items) do
        if it.icon and it.icon ~= "" then
            it._mat = Material(it.icon, "smooth mips")
        end
    end

    function pnl:Paint(w, h)
        draw.RoundedBox(4, 0, 0, w, h, C and C.bgPopup or Color(40, 40, 40))
        surface.SetDrawColor(C and C.bgHeaderLine or Color(0, 0, 0, 100))
        surface.DrawOutlinedRect(0, 0, w, h, 1)

        surface.SetFont(FONT)
        for i, it in ipairs(self.Items) do
            local ry = PAD + (i - 1) * ROW_H

            if i == self.SelIndex then
                draw.RoundedBox(3, PAD - 2, ry, w - PAD * 2 + 4, ROW_H, C and C.accent or Color(50, 150, 255))
            end

            if it._mat and not it._mat:IsError() then
                surface.SetDrawColor(255, 255, 255, (it.enabled == false) and 80 or 255)
                surface.SetMaterial(it._mat)
                surface.DrawTexturedRect(PAD + 2, ry + (ROW_H - ICON_SZ) / 2, ICON_SZ, ICON_SZ)
            end

            local textColor = (it.enabled == false) and (C and C.textMuted or Color(150, 150, 150))
                or (i == self.SelIndex and (C and C.textBright or color_white) or (C and C.textLight or Color(220, 220, 220)))

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

-- ── Capture a DMenu's items without showing it ───────────────────────────────
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
                    local icon = child.m_Image and IsValid(child.m_Image) and child.m_Image:GetImage() or ""
                    local enabled = child:IsEnabled()
                    local isSubMenu = IsValid(child.SubMenu)

                    local cb = child._rawCallback
                    if not cb and isfunction(child.DoClick) then
                        local fallback = child.DoClick
                        cb = function() pcall(fallback, child) end
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

-- ── Openers ──────────────────────────────────────────────────────────────────
function KB.OpenContextMenuForFocused()
    local id = IM.Focused
    if not id or id == "__TASKBAR__" then return end
    local pin = PinnedPanels.Pins[id]
    if not pin or not IsValid(pin.frame) then return end

    local fx, fy = pin.frame:LocalToScreen(0, 0)
    local posX, posY = fx + pin.frame:GetWide() / 2, fy + 16

    local items = CaptureAndExtractMenu(function()
        local _mx, _my = gui.MouseX, gui.MouseY
        gui.MouseX = function() return posX end
        gui.MouseY = function() return posY end
        if PinnedPanels.OpenContextMenu then PinnedPanels.OpenContextMenu(id, pin.frame) end
        gui.MouseX, gui.MouseY = _mx, _my
    end)

    if #items == 0 then return end
    CloseKeyboardMenu(IM.ActiveMenu)
    IM.ActiveMenu = CreateKeyboardMenu(items, posX, posY)
end

function KB.OpenElementContextMenu(el)
    if not IsValid(el) then return end

    local ex, ey = el:LocalToScreen(0, 0)
    local ew, eh = el:GetSize()
    local posX, posY = ex + ew / 2, ey + eh / 2

    local target = el
    local items = {}
    for attempt = 1, PROBE_ATTEMPTS do
        if not IsValid(target) then break end

        local methodsToTry = {
            "OpenGenericSpawnmenuRightClickMenu", "OpenMenu", "DoRightClick", "Mouse"
        }

        for _, method in ipairs(methodsToTry) do
            items = CaptureAndExtractMenu(function()
                local _mx, _my = gui.MouseX, gui.MouseY
                gui.MouseX = function() return posX end
                gui.MouseY = function() return posY end

                if method == "Mouse" then
                    if isfunction(target.OnMousePressed) then
                        target:OnMousePressed(MOUSE_RIGHT)
                        if isfunction(target.OnMouseReleased) then target:OnMouseReleased(MOUSE_RIGHT) end
                    end
                else
                    if isfunction(target[method]) then target[method](target) end
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

-- ── Per-Frame Menu Nav ───────────────────────────────────────────────────────
function KB.HandleMenuNav()
    if not IsValid(IM.ActiveMenu) then
        IM.ActiveMenu = nil
        return
    end

    local pnl = IM.ActiveMenu
    local items = pnl.Items
    local n = #items
    if n == 0 then return end

    pnl.SelIndex = math.Clamp(pnl.SelIndex or 1, 1, n)
    local wd = pnl._wasDown

    local function CheckKey(k)
        local down = input.IsKeyDown(k)
        local pressed = down and not wd[k]
        wd[k] = down
        return pressed
    end

    local upNow    = CheckKey(KEY_UP)
    local downNow  = CheckKey(KEY_DOWN)
    local leftNow  = CheckKey(KEY_LEFT)
    local rightNow = CheckKey(KEY_RIGHT)
    local enterNow = CheckKey(KEY_ENTER)
    local backNow  = CheckKey(KEY_BACKSPACE)

    if upNow or downNow then
        local dir = upNow and -1 or 1
        local startIdx = pnl.SelIndex
        repeat
            pnl.SelIndex = (pnl.SelIndex - 1 + dir) % n + 1
        until (items[pnl.SelIndex] and items[pnl.SelIndex].enabled ~= false) or pnl.SelIndex == startIdx
        return
    end

    if enterNow or rightNow then
        local it = items[pnl.SelIndex]
        if it and it.enabled ~= false then
            if it.isSubMenu and it.subItems and #it.subItems > 0 then
                if IsValid(pnl.ActiveSubMenu) then pnl.ActiveSubMenu:Remove() end
                local cx, cy = pnl:GetPos()
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
    end

    if leftNow or backNow then
        if IsValid(pnl.ParentMenu) then
            local parent = pnl.ParentMenu
            parent.ActiveSubMenu = nil
            parent._wasDown[KEY_LEFT] = true
            parent._wasDown[KEY_BACKSPACE] = true
            IM.ActiveMenu = parent
            pnl:Remove()
        elseif backNow then
            CloseKeyboardMenu(pnl)
            IM.ActiveMenu = nil
        end
    end
end
