local C = PinnedPanels.C

-- Header button metrics (minimize / maximize / unpin)
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
		draw.SimpleText(title, "DermaDefaultBold", 10, 12, txtCol, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

		if inIM then
			-- Resize-corner hint (bottom-right); the header dots moved out for the buttons.
			surface.SetDrawColor(C.imGreenBorder)
			surface.DrawRect(w - 6, h - 6, 4, 1)
			surface.DrawRect(w - 6, h - 4, 1, 2)
		end

		if pin and pin.locked then
			-- Lock marker sits just left of the header buttons.
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

		-- Hint bar so it's obvious how to leave content-navigation mode.
		local hint = "Backspace: back    Enter: use    Arrows: move"
		surface.SetFont("DermaDefault")
		local tw, th = surface.GetTextSize(hint)
		local bw, bh = tw + 16, th + 6
		local bx = math.floor((w - bw) / 2)
		local by = h - bh - 4
		draw.RoundedBox(4, bx, by, bw, bh, Color(150, 30, 30, 235))
		draw.SimpleText(hint, "DermaDefault", w / 2, by + bh / 2,
			Color(255, 225, 225), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

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
	local sw, sh = ScrW(), ScrH()
	local maxX = math.max(0, sw - w)
	local maxY = math.max(0, sh - h)
	local baseX = math.Clamp(preferredX or 120, 0, maxX)
	local baseY = math.Clamp(preferredY or 120, 0, maxY)

	if not IsSpawnOccupied(baseX, baseY, w, h, ignoreId) then
		return baseX, baseY
	end

	local STEP = 28
	for y = 0, maxY, STEP do
		for x = 0, maxX, STEP do
			if not IsSpawnOccupied(x, y, w, h, ignoreId) then
				return x, y
			end
		end
	end

	return baseX, baseY
end

PinnedPanels._FindFreeSpawnPosition = FindFreeSpawnPosition

-- ── Build Wrapper Frame ──────────────────────────────────────────────────────
local TITLE_HEIGHT = 24
local CORNER_SIZE  = 16

local function IsTextPanel(p)
	if not IsValid(p) then return false end
	local c = p:GetClassName()
	return c == "TextEntry" or c == "DTextEntry" or c == "RichText"
end

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
	frame:ShowCloseButton(false)   -- replaced by our own header buttons
	frame:ParentToHUD()
	frame:MakePopup()
	frame:SetKeyboardInputEnabled(false)

	local titleOverlay, resizeOverlay, btnMin, btnMax, btnClose

	local function ApplyInteractState()
		local on = PinnedPanels.PanelsInteractive()
		frame:SetMouseInputEnabled(on)
		if IsValid(titleOverlay)  then titleOverlay:SetMouseInputEnabled(on) end
		if IsValid(resizeOverlay) then resizeOverlay:SetMouseInputEnabled(on) end
		if IsValid(btnMin)   then btnMin:SetMouseInputEnabled(on) end
		if IsValid(btnMax)   then btnMax:SetMouseInputEnabled(on) end
		if IsValid(btnClose) then btnClose:SetMouseInputEnabled(on) end
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
	end

	-- Fallback (e.g. if something calls Close): behave like minimize.
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
		local nx = math.Clamp(x, 0, ScrW() - w)
		local ny = math.Clamp(y, 0, ScrH() - h)
		if x ~= nx or y ~= ny then self:SetPos(nx, ny) end

		local hovered = vgui.GetHoveredPanel()
		local focus   = vgui.GetKeyboardFocus()
		local needsKeyboard = (IsTextPanel(hovered) and hovered:HasParent(self))
			or (IsTextPanel(focus) and focus:HasParent(self))
		if self:IsKeyboardInputEnabled() ~= needsKeyboard then
			self:SetKeyboardInputEnabled(needsKeyboard)
		end
	end

	local imDrag = false
	local imDragOffX, imDragOffY = 0, 0
	local imResize = false
	local imResizeSX, imResizeSY = 0, 0
	local imResizeW, imResizeH   = 0, 0

	titleOverlay = vgui.Create("DPanel", frame)
	titleOverlay:SetPos(0, 0)
	titleOverlay:SetSize(fw - HDR_BTN_W * HDR_BTN_N, TITLE_HEIGHT)
	titleOverlay.Paint = function() end
	titleOverlay:SetMouseInputEnabled(false)
	titleOverlay:SetCursor("sizeall")
	titleOverlay._pp_skipNav = true

	resizeOverlay = vgui.Create("DPanel", frame)
	resizeOverlay:SetPos(fw - CORNER_SIZE, fh - CORNER_SIZE)
	resizeOverlay:SetSize(CORNER_SIZE, CORNER_SIZE)
	resizeOverlay.Paint = function() end
	resizeOverlay:SetMouseInputEnabled(false)
	resizeOverlay:SetCursor("sizenwse")
	resizeOverlay._pp_skipNav = true

	local function UpdateOverlayPositions()
		local fw2, fh2 = frame:GetSize()
		titleOverlay:SetSize(math.max(20, fw2 - HDR_BTN_W * HDR_BTN_N - 4), TITLE_HEIGHT)
		resizeOverlay:SetPos(fw2 - CORNER_SIZE, fh2 - CORNER_SIZE)
		if IsValid(btnMin)   then btnMin:SetPos(fw2 - HDR_BTN_W * 3 - 2, 3) end
		if IsValid(btnMax)   then btnMax:SetPos(fw2 - HDR_BTN_W * 2 - 2, 3) end
		if IsValid(btnClose) then btnClose:SetPos(fw2 - HDR_BTN_W - 2, 3) end
	end

	-- Toggle "cover the whole screen" and back (shared logic in pin.lua).
	local function ToggleMaximize()
		PinnedPanels.ToggleMaximizePanel(id)
		UpdateOverlayPositions()
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
			else -- close / unpin
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
		frame:SetPos(math.Clamp(mx - imDragOffX, 0, ScrW() - w), math.Clamp(my - imDragOffY, 0, ScrH() - h))
	end

	resizeOverlay.Think = function(self)
		if not imResize then return end
		if IsLocked(id) then
			imResize = false
			self:MouseCapture(false)
			return
		end
		local fpx, fpy = frame:GetPos()
		local mx, my   = gui.MouseX(), gui.MouseY()
		local nw = math.min(math.max(150, imResizeW + mx - imResizeSX), ScrW() - fpx)
		local nh = math.min(math.max(100, imResizeH + my - imResizeSY), ScrH() - fpy)
		frame:SetSize(nw, nh)
		UpdateOverlayPositions()
	end

	titleOverlay.OnMousePressed = function(self, mc)
		if mc == MOUSE_LEFT then
			if IsLocked(id) then return end
			-- Dragging a maximized panel restores it first.
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

	resizeOverlay.OnMousePressed = function(self, mc)
		if mc == MOUSE_LEFT then
			if IsLocked(id) then return end
			local pin = PinnedPanels.Pins[id]
			if pin then pin.maximized = false end   -- manual resize leaves "maximized"
			imResize = true
			imResizeSX, imResizeSY = gui.MouseX(), gui.MouseY()
			imResizeW, imResizeH = frame:GetSize()
			self:MouseCapture(true)
		end
	end

	resizeOverlay.OnMouseReleased = function(self)
		if imResize then
			imResize = false
			self:MouseCapture(false)
			if isfunction(frame.OnUserResized) then
				frame.OnUserResized(frame:GetSize())
			end
			PinnedPanels.Save()
		end
	end

	frame.OnSizeChanged = function()
		UpdateOverlayPositions()
		DebouncedSave()
	end

	return frame
end

PinnedPanels._BuildWrapperFrame = BuildWrapperFrame
