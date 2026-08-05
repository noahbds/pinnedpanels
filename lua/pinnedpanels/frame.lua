local C = PinnedPanels.C

local HDR_BTN_W = 26
local HDR_BTN_H = 18
local HDR_BTN_N = 3

-- ── Frame Paint (supports per-panel colors) ──────────────────────────────────
function PinnedPanels.GetFramePaint(title, pinId)
	local hoverHdr = Color(0, 0, 0, 255)
	return function(self, w, h)
		local pin    = pinId and PinnedPanels.Pins[pinId]
		local th     = PinnedPanels.Settings
		local inIM   = PinnedPanels.PanelsInteractive()
		local bgCol  = (pin and pin.customBg) or th.bg
		local hdrCol = (pin and pin.customHeader) or th.header
		local txtCol = (pin and pin.customText) or th.text

		if inIM then
			hoverHdr.r = math.min(hdrCol.r + 12, 255)
			hoverHdr.g = math.min(hdrCol.g + 20, 255)
			hoverHdr.b = math.min(hdrCol.b + 35, 255)
			hoverHdr.a = hdrCol.a
			hdrCol = hoverHdr
		end

		draw.RoundedBox(6, 0, 0, w, h, bgCol)
		draw.RoundedBoxEx(6, 0, 0, w, 24, hdrCol, true, true, false, false)
		local shownTitle = title
		if pin and pin.clickThrough then shownTitle = shownTitle .. "  (click-through)" end
		if pin and pin.crop then shownTitle = shownTitle .. "  (cropped)" end
		draw.SimpleText(shownTitle, "DermaDefaultBold", 10, 12, txtCol, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

		if inIM then
			surface.SetDrawColor(C.imGreenBorder)
			surface.DrawRect(w - 6, h - 6, 4, 1)
			surface.DrawRect(w - 6, h - 4, 1, 2)
		end

		if pin and pin.locked then
			surface.SetDrawColor(C.lockIcon)
			surface.DrawRect(w - HDR_BTN_W * HDR_BTN_N - 14, 9, 6, 6)
		end
	end
end

function PinnedPanels.GetFramePaintOver(pinId)
	return function(self, w, h)
		local IM = PinnedPanels.CursorMode
		if not pinId or not IM or IM.Focused ~= pinId then return end
		if not (PinnedPanels.IsKeyboardNavEnabled and PinnedPanels.IsKeyboardNavEnabled()) then return end

		surface.SetDrawColor(IM.NavigatingPanel and C.navRing or C.focusRing)
		surface.DrawOutlinedRect(0, 0, w, h, 2)

		if not IM.NavigatingPanel or not PinnedPanels.GetNavElements then return end

		local hint = PinnedPanels.L("nav_hint_panel")
		local selEl = IM.SelectedIndex and PinnedPanels.GetNavElements()[IM.SelectedIndex]
		if IsValid(selEl) then
			local sc = selEl.ClassName or selEl:GetClassName()
			local colorTgt, colorCls
			if PinnedPanels._ColorTarget then
				colorTgt, colorCls = PinnedPanels._ColorTarget(selEl)
			end
			if sc == "DRGBPicker" then
				hint = PinnedPanels.L("nav_hint_hue")
			elseif sc == "DAlphaBar" then
				hint = PinnedPanels.L("nav_hint_alpha")
			elseif colorTgt then
				if colorCls and colorCls:find("ColorCube") then
					hint = PinnedPanels.L("nav_hint_satval")
				else
					hint = PinnedPanels.L("nav_hint_huevalue")
				end
			elseif sc:find("Slider") or sc == "DComboBox" then
				hint = PinnedPanels.L("nav_hint_slider")
			end
		end
		surface.SetFont("DermaDefault")
		local tw, th = surface.GetTextSize(hint)
		local bw, bh = tw + 16, th + 6
		local bx = math.floor((w - bw) / 2)

		local screenX, screenY = self:LocalToScreen(bx, h + 4 + bh)
		if screenX < 4 then
			bx = bx + (4 - screenX)
		elseif screenX + bw > ScrW() - 4 then
			bx = bx - ((screenX + bw) - (ScrW() - 4))
		end

		local by = (screenY > ScrH() - 4) and (-bh - 4) or (h + 4)

		local oldClip = DisableClipping(true)
		draw.RoundedBox(4, bx, by, bw, bh, Color(150, 30, 30, 235))
		draw.SimpleText(hint, "DermaDefault", bx + bw / 2, by + bh / 2,
			Color(255, 225, 225), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		DisableClipping(oldClip)

		local el = PinnedPanels.GetNavElements()[IM.NavFocusIndex]
		if not IsValid(el) then return end

		local ex, ey = el:LocalToScreen(0, 0)
		local lx, ly = self:ScreenToLocal(ex, ey)
		local ew, eh = el:GetSize()
		local ringCol = (IM.SelectedIndex == IM.NavFocusIndex) and C.navSelected or C.navElement

		surface.SetDrawColor(0, 0, 0, 255)
		surface.DrawOutlinedRect(lx - 3, ly - 3, ew + 6, eh + 6, 1)

		surface.SetDrawColor(ringCol)
		surface.DrawOutlinedRect(lx - 2, ly - 2, ew + 4, eh + 4, 2)

		surface.SetDrawColor(0, 0, 0, 255)
		surface.DrawOutlinedRect(lx, ly, ew, eh, 1)

		local pulse = math.abs(math.sin(CurTime() * 6))
		surface.SetDrawColor(ringCol.r, ringCol.g, ringCol.b, 12 + 24 * pulse)
		surface.DrawRect(lx, ly, ew, eh)
	end
end

-- ── Overlap / Spawn Helpers ──────────────────────────────────────────────────
local function RectsOverlap(ax, ay, aw, ah, bx, by, bw, bh, pad)
	pad = pad or 0
	return ax < (bx + bw + pad)
		and bx < (ax + aw + pad)
		and ay < (by + bh + pad)
		and by < (ay + ah + pad)
end

local function IsSpawnOccupied(x, y, w, h, ignoreId)
	for id, pin in pairs(PinnedPanels.Pins) do
		if id ~= ignoreId and IsValid(pin.frame) and pin.frame:IsVisible() then
			local px, py = pin.frame:GetPos()
			local pw, ph = pin.frame:GetSize()
			if RectsOverlap(x, y, w, h, px, py, pw, ph, 20) then
				return true
			end
		end
	end
	return false
end

local function FindFreeSpawnPosition(w, h, preferredX, preferredY, ignoreId)
	local ux, uy, uw, uh = PinnedPanels.GetUsableBounds()
	local minX, minY = ux, uy
	local maxX = math.max(ux, ux + uw - w)
	local maxY = math.max(uy, uy + uh - h)
	local baseX = math.Clamp(preferredX or 120, minX, maxX)
	local baseY = math.Clamp(preferredY or 120, minY, maxY)

	if not IsSpawnOccupied(baseX, baseY, w, h, ignoreId) then
		return baseX, baseY
	end

	local STEP = 28
	for y = minY, maxY, STEP do
		for x = minX, maxX, STEP do
			if not IsSpawnOccupied(x, y, w, h, ignoreId) then
				return x, y
			end
		end
	end

	return baseX, baseY
end

PinnedPanels._FindFreeSpawnPosition = FindFreeSpawnPosition

-- ── Edge Snapping (drag / resize) ────────────────────────────────────────────
local function SnapActive()
	local S = PinnedPanels.Settings
	if S.snapEnabled == false then return false end
	if input.IsKeyDown(KEY_LALT) or input.IsKeyDown(KEY_RALT) then return false end
	return true
end
local function SnapLines(id, axis, w, h)
	local sw, sh = ScrW(), ScrH()
	local lines
	if axis == "x" then
		lines = { 0, sw - w, math.floor((sw - w) / 2) }
	else
		lines = { 0, sh - h, math.floor((sh - h) / 2) }
	end
	for pid, pin in pairs(PinnedPanels.Pins) do
		if pid ~= id and IsValid(pin.frame) and pin.frame:IsVisible() then
			local px, py = pin.frame:GetPos()
			local pw, ph = pin.frame:GetSize()
			if axis == "x" then
				lines[#lines + 1] = px 
				lines[#lines + 1] = px + pw - w
				lines[#lines + 1] = px + pw
				lines[#lines + 1] = px - w
			else
				lines[#lines + 1] = py
				lines[#lines + 1] = py + ph - h
				lines[#lines + 1] = py + ph
				lines[#lines + 1] = py - h
			end
		end
	end
	return lines
end

local function SnapValue(id, axis, value, w, h)
	local dist = tonumber(PinnedPanels.Settings.snapDistance) or 12
	if dist <= 0 then return value end
	local best, bestD = value, dist + 1
	for _, line in ipairs(SnapLines(id, axis, w, h)) do
		local d = math.abs(value - line)
		if d < bestD then bestD, best = d, line end
	end
	return (bestD <= dist) and best or value
end

local function SnapDragPos(id, x, y, w, h)
	if not SnapActive() then return x, y end
	return SnapValue(id, "x", x, w, h), SnapValue(id, "y", y, w, h)
end

-- ── Build Wrapper Frame ──────────────────────────────────────────────────────
local TITLE_HEIGHT = 24
local CORNER_SIZE  = 16
local EDGE_SIZE    = 5

local IsTextPanel = PinnedPanels.IsTextPanel

local function IsLocked(id)
	local pin = PinnedPanels.Pins[id]
	return pin and pin.locked
end

local function BuildWrapperFrame(title, id, fw, fh, fx, fy)
	local frame = vgui.Create("DFrame")
	frame:SetTitle("")
	frame:SetSize(fw, fh)
	frame:SetPos(fx, fy)
	frame:SetDraggable(false)
	frame:SetSizable(false)
	frame:SetDeleteOnClose(false)
	frame:ShowCloseButton(false)
	frame:ParentToHUD()
	frame:MakePopup()
	frame:SetKeyboardInputEnabled(false)

	local titleOverlay, btnMin, btnMax, btnClose
	local resizeZones = {}
	local ctGrip
	local UpdateCTGrip

	local function ApplyInteractState()
		local pin = PinnedPanels.Pins[id]
		local override = PinnedPanels.ClickThroughOverride and PinnedPanels.ClickThroughOverride() or false
		local on = PinnedPanels.PanelsInteractive() and (not (pin and pin.clickThrough) or override)
		frame:SetMouseInputEnabled(on)
		if IsValid(titleOverlay) then titleOverlay:SetMouseInputEnabled(on) end
		for _, rz in ipairs(resizeZones) do
			if IsValid(rz.panel) then rz.panel:SetMouseInputEnabled(on) end
		end
		if IsValid(btnMin)   then btnMin:SetMouseInputEnabled(on) end
		if IsValid(btnMax)   then btnMax:SetMouseInputEnabled(on) end
		if IsValid(btnClose) then btnClose:SetMouseInputEnabled(on) end
		if UpdateCTGrip then UpdateCTGrip() end
	end

	local interactHook = "PinnedPanels_InteractFrame_" .. id .. "_" .. tostring(frame)
	hook.Add("PinnedPanels_CursorModeChanged", interactHook, function()
		if not IsValid(frame) then
			hook.Remove("PinnedPanels_CursorModeChanged", interactHook)
			return
		end
		ApplyInteractState()
	end)
	frame.OnRemove = function()
		hook.Remove("PinnedPanels_CursorModeChanged", interactHook)
		if IsValid(ctGrip) then ctGrip:Remove() end
	end

	frame.OnClose = function()
		PinnedPanels.MinimizeToTaskbar(id)
	end
	frame.Paint     = PinnedPanels.GetFramePaint(title, id)
	frame.PaintOver = PinnedPanels.GetFramePaintOver(id)

	local saveDebounce = 0
	local function DebouncedSave()
		local t = CurTime()
		if t > saveDebounce + 0.2 then
			saveDebounce = t
			PinnedPanels.Save()
		end
	end

	frame.NextThink = 0
	frame.Think = function(self)
		if CurTime() < self.NextThink then return end
		self.NextThink = CurTime() + 0.1

		local x, y = self:GetPos()
		local w, h = self:GetSize()
		local nx, ny = PinnedPanels.ClampToUsable(x, y, w, h)
		if x ~= nx or y ~= ny then self:SetPos(nx, ny) end

		local hovered = vgui.GetHoveredPanel()
		local focus   = vgui.GetKeyboardFocus()
		local needsKeyboard = (IsTextPanel(hovered) and hovered:HasParent(self))
			or (IsTextPanel(focus) and focus:HasParent(self))
		if self:IsKeyboardInputEnabled() ~= needsKeyboard then
			self:SetKeyboardInputEnabled(needsKeyboard)
		end

		if UpdateCTGrip then UpdateCTGrip() end
	end

	local imDrag = false
	local imDragOffX, imDragOffY = 0, 0
	local resizing = nil
	local resizingPanel = nil
	local rsMX, rsMY, rsX, rsY, rsW, rsH = 0, 0, 0, 0, 0, 0

	titleOverlay = vgui.Create("DPanel", frame)
	titleOverlay:SetPos(0, 0)
	titleOverlay:SetSize(fw - HDR_BTN_W * HDR_BTN_N, TITLE_HEIGHT)
	titleOverlay.Paint = function() end
	titleOverlay:SetMouseInputEnabled(false)
	titleOverlay:SetCursor("sizeall")
	titleOverlay._pp_skipNav = true

	local function UpdateOverlayPositions()
		local fw2, fh2 = frame:GetSize()
		titleOverlay:SetSize(math.max(20, fw2 - HDR_BTN_W * HDR_BTN_N - 4), TITLE_HEIGHT)
		for _, rz in ipairs(resizeZones) do
			local zn, z = rz.zone, rz.panel
			if IsValid(z) then
				if zn.n and zn.w then
					z:SetPos(0, 0)
					z:SetSize(CORNER_SIZE, CORNER_SIZE)
				elseif zn.n and zn.e then
					z:SetPos(fw2 - CORNER_SIZE, 0)
					z:SetSize(CORNER_SIZE, CORNER_SIZE)
				elseif zn.s and zn.w then
					z:SetPos(0, fh2 - CORNER_SIZE)
					z:SetSize(CORNER_SIZE, CORNER_SIZE)
				elseif zn.s and zn.e then
					z:SetPos(fw2 - CORNER_SIZE, fh2 - CORNER_SIZE)
					z:SetSize(CORNER_SIZE, CORNER_SIZE)
				elseif zn.n then
					z:SetPos(CORNER_SIZE, 0)
					z:SetSize(math.max(0, fw2 - CORNER_SIZE * 2), EDGE_SIZE)
				elseif zn.s then
					z:SetPos(CORNER_SIZE, fh2 - EDGE_SIZE)
					z:SetSize(math.max(0, fw2 - CORNER_SIZE * 2), EDGE_SIZE)
				elseif zn.w then
					z:SetPos(0, CORNER_SIZE)
					z:SetSize(EDGE_SIZE, math.max(0, fh2 - CORNER_SIZE * 2))
				else
					z:SetPos(fw2 - EDGE_SIZE, CORNER_SIZE)
					z:SetSize(EDGE_SIZE, math.max(0, fh2 - CORNER_SIZE * 2))
				end
			end
		end
		if IsValid(btnMin)   then btnMin:SetPos(fw2 - HDR_BTN_W * 3 - 2, 3) end
		if IsValid(btnMax)   then btnMax:SetPos(fw2 - HDR_BTN_W * 2 - 2, 3) end
		if IsValid(btnClose) then btnClose:SetPos(fw2 - HDR_BTN_W - 2, 3) end
	end

	local function ToggleMaximize()
		PinnedPanels.ToggleMaximizePanel(id)
		UpdateOverlayPositions()
	end

	-- ── Resize zones (all edges and corners) ──────────────────────────────────
	local function StartResize(zone, pnl)
		if IsLocked(id) then return end
		local pin = PinnedPanels.Pins[id]
		if pin then pin.maximized = false end
		resizing = zone
		resizingPanel = pnl
		frame._lastResizeZone = zone
		rsMX, rsMY = gui.MouseX(), gui.MouseY()
		rsX, rsY = frame:GetPos()
		rsW, rsH = frame:GetSize()
		pnl:MouseCapture(true)
	end

	local function DoResizeThink(pnl)
		if not resizing or pnl ~= resizingPanel then return end
		if IsLocked(id) then
			resizing, resizingPanel = nil, nil
			pnl:MouseCapture(false)
			return
		end

		local mx, my = gui.MouseX(), gui.MouseY()
		local dx, dy = mx - rsMX, my - rsMY
		local ux, uy, uw, uh = PinnedPanels.GetUsableBounds()
		local x, y, w, h = rsX, rsY, rsW, rsH
		local right, bottom = rsX + rsW, rsY + rsH
		local pin = PinnedPanels.Pins[id]
		local minW = (pin and pin.crop) and 60 or 150
		local minH = (pin and pin.crop) and 60 or 100
		local maxW, maxH = math.huge, math.huge
		if pin and pin.crop and pin.cropBase then
			maxW = resizing.w and (pin.cropBase.w - pin.crop.r) or (pin.cropBase.w - pin.crop.l)
			maxH = resizing.n and (pin.cropBase.h - pin.crop.b) or (pin.cropBase.h - pin.crop.t)
		end

		if resizing.e then
			w = math.Clamp(rsW + dx, minW, math.min((ux + uw) - rsX, maxW))
			if SnapActive() then
				w = math.Clamp(SnapValue(id, "x", rsX + w, 0, h) - rsX, minW, maxW)
			end
		elseif resizing.w then
			w = math.Clamp(rsW - dx, minW, math.min(right - ux, maxW))
			if SnapActive() then
				w = math.Clamp(right - SnapValue(id, "x", right - w, 0, h), minW, maxW)
			end
		end

		if resizing.s then
			h = math.Clamp(rsH + dy, minH, math.min((uy + uh) - rsY, maxH))
			if SnapActive() then
				h = math.Clamp(SnapValue(id, "y", rsY + h, w, 0) - rsY, minH, maxH)
			end
		elseif resizing.n then
			h = math.Clamp(rsH - dy, minH, math.min(bottom - uy, maxH))
			if SnapActive() then
				h = math.Clamp(bottom - SnapValue(id, "y", bottom - h, w, 0), minH, maxH)
			end
		end

		if resizing.w then x = right - w end
		if resizing.n then y = bottom - h end

		frame:SetPos(x, y)
		frame:SetSize(w, h)

		if pin and pin.crop and isfunction(frame.OnUserResized) then
			frame.OnUserResized(w, h)
		end

		UpdateOverlayPositions()
	end

	local function EndResize(pnl)
		if not resizing or pnl ~= resizingPanel then return end
		resizing, resizingPanel = nil, nil
		pnl:MouseCapture(false)
		if isfunction(frame.OnUserResized) then
			frame.OnUserResized(frame:GetSize())
		end
		PinnedPanels.Save()
	end

	local ZONE_CURSORS = {
		n = "sizens", s = "sizens", e = "sizewe", w = "sizewe",
		nw = "sizenwse", se = "sizenwse", ne = "sizenesw", sw = "sizenesw",
	}

	for _, name in ipairs({ "nw", "ne", "sw", "se", "n", "s", "e", "w" }) do
		local zone = {
			n = name:find("n", 1, true) ~= nil,
			s = name:find("s", 1, true) ~= nil,
			e = name:find("e", 1, true) ~= nil,
			w = name:find("w", 1, true) ~= nil,
		}
		local z = vgui.Create("DPanel", frame)
		z.Paint = function() end
		z:SetCursor(ZONE_CURSORS[name])
		z:SetMouseInputEnabled(false)
		z._pp_skipNav = true
		z.OnMousePressed = function(self, mc)
			if mc == MOUSE_LEFT then
				StartResize(zone, self)
			elseif mc == MOUSE_RIGHT then
				PinnedPanels.OpenContextMenu(id, frame)
			end
		end
		z.OnMouseReleased = function(self) EndResize(self) end
		z.Think = function(self) DoResizeThink(self) end
		resizeZones[#resizeZones + 1] = { panel = z, zone = zone }
	end

	-- ── Header buttons (minimize / maximize / unpin) ──────────────────────────
	local function MakeHeaderBtn(glyph, onClick, isClose)
		local b = vgui.Create("DButton", frame)
		b:SetText("")
		b:SetSize(HDR_BTN_W, HDR_BTN_H)
		b:SetMouseInputEnabled(false)
		b._pp_skipNav = true
		b.DoClick = onClick
		b.Paint = function(self, w, h)
			local hovered = self:IsHovered()
			if hovered then
				local hc = isClose and Color(210, 60, 60, 225) or Color(255, 255, 255, 34)
				draw.RoundedBox(3, 1, 1, w - 2, h - 2, hc)
			end

			local pin  = PinnedPanels.Pins[id]
			local base = (pin and pin.customText) or PinnedPanels.Settings.text
			local col  = (isClose and hovered) and color_white or base
			surface.SetDrawColor(col.r, col.g, col.b, 235)

			local cx, cy = math.floor(w / 2), math.floor(h / 2)
			if glyph == "min" then
				surface.DrawRect(cx - 5, cy + 4, 11, 2)
			elseif glyph == "max" then
				if pin and pin.maximized then
					surface.DrawOutlinedRect(cx - 5, cy - 1, 8, 8, 1)
					surface.DrawOutlinedRect(cx - 1, cy - 5, 8, 8, 1)
				else
					surface.DrawOutlinedRect(cx - 5, cy - 5, 11, 11, 1)
				end
			else
				surface.DrawLine(cx - 4, cy - 4, cx + 4, cy + 4)
				surface.DrawLine(cx - 4, cy + 4, cx + 4, cy - 4)
			end
		end
		return b
	end

	btnMin   = MakeHeaderBtn("min",   function() PinnedPanels.MinimizeToTaskbar(id) end, false)
	btnMax   = MakeHeaderBtn("max",   ToggleMaximize, false)
	btnClose = MakeHeaderBtn("close", function() PinnedPanels.Unpin(id) end, true)

	ApplyInteractState()
	UpdateOverlayPositions()

	titleOverlay.Think = function(self)
		if not imDrag then return end
		if IsLocked(id) then
			imDrag = false
			self:MouseCapture(false)
			return
		end
		local mx, my = gui.MouseX(), gui.MouseY()
		local w, h = frame:GetSize()
		local nx, ny = PinnedPanels.ClampToUsable(mx - imDragOffX, my - imDragOffY, w, h)
		nx, ny = SnapDragPos(id, nx, ny, w, h)
		nx, ny = PinnedPanels.ClampToUsable(nx, ny, w, h)
		frame:SetPos(nx, ny)
	end

	titleOverlay.OnMousePressed = function(self, mc)
		if mc == MOUSE_LEFT then
			if IsLocked(id) then return end
			local pin = PinnedPanels.Pins[id]
			if pin and pin.maximized then ToggleMaximize() end
			imDrag = true
			imDragOffX, imDragOffY = self:CursorPos()
			self:MouseCapture(true)
		elseif mc == MOUSE_RIGHT then
			PinnedPanels.OpenContextMenu(id, frame)
		end
	end

	titleOverlay.OnMouseReleased = function(self)
		if imDrag then
			imDrag = false
			self:MouseCapture(false)
			PinnedPanels.Save()
		end
	end

	frame.OnSizeChanged = function()
		UpdateOverlayPositions()
		DebouncedSave()
	end

	-- ── Click-through header grip ─────────────────────────────────────────────
	local ctDrag, ctOffX, ctOffY = false, 0, 0

	local function EnsureCTGrip()
		if IsValid(ctGrip) then return end
		ctGrip = vgui.Create("DPanel")
		ctGrip:MakePopup()
		ctGrip:SetKeyboardInputEnabled(false)
		ctGrip:SetCursor("sizeall")
		ctGrip._pp_skipNav = true
		ctGrip.Paint = function(_, w, h)
			local pin = PinnedPanels.Pins[id]
			draw.RoundedBoxEx(6, 0, 0, w, h, Color(18, 20, 28, 230), true, true, false, false)
			surface.SetDrawColor(C.accentFrame)
			surface.DrawRect(0, h - 2, w, 2)
			draw.SimpleText(pin and pin.title or "", "DermaDefaultBold", 8, h / 2,
				C.textLight, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			draw.SimpleText(PinnedPanels.L("clickthrough_bar"), "DermaDefault", w - 8, h / 2,
				C.textMuted, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
		end
		ctGrip.OnMousePressed = function(self, mc)
			if mc == MOUSE_RIGHT then
				PinnedPanels.OpenContextMenu(id, frame)
			elseif mc == MOUSE_LEFT and not IsLocked(id) then
				ctDrag = true
				local mx, my = gui.MouseX(), gui.MouseY()
				local fx, fy = frame:GetPos()
				ctOffX, ctOffY = mx - fx, my - fy
				self:MouseCapture(true)
			end
		end
		ctGrip.OnMouseReleased = function(self)
			if ctDrag then
				ctDrag = false
				self:MouseCapture(false)
				PinnedPanels.Save()
			end
		end
		ctGrip.Think = function()
			if not ctDrag then return end
			local w, h = frame:GetSize()
			local mx, my = gui.MouseX(), gui.MouseY()
			frame:SetPos(PinnedPanels.ClampToUsable(mx - ctOffX, my - ctOffY, w, h))
		end
	end

	UpdateCTGrip = function()
		local pin  = PinnedPanels.Pins[id]
		local show = pin and pin.clickThrough and PinnedPanels.PanelsInteractive()
			and IsValid(frame) and frame:IsVisible()
			and not (PinnedPanels.ClickThroughOverride and PinnedPanels.ClickThroughOverride())
		if not show then
			if IsValid(ctGrip) then ctGrip:Remove() end
			ctGrip = nil
			ctDrag = false
			return
		end
		EnsureCTGrip()
		local fx, fy = frame:GetPos()
		ctGrip:SetSize(frame:GetWide(), TITLE_HEIGHT)
		ctGrip:SetPos(fx, fy)
		ctGrip:MoveToFront()
	end

	return frame
end

PinnedPanels._BuildWrapperFrame = BuildWrapperFrame
