local C = PinnedPanels.C

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
			surface.SetDrawColor(txtCol.r, txtCol.g, txtCol.b, 60)
			for dx = 0, 4, 2 do
				for dy = 0, 4, 2 do
					surface.DrawRect(w - 22 + dx, 10 + dy, 1, 1)
				end
			end
			surface.SetDrawColor(C.imGreenBorder)
			surface.DrawRect(w - 6, h - 6, 4, 1)
			surface.DrawRect(w - 6, h - 4, 1, 2)
		end

		if pin and pin.locked then
			surface.SetDrawColor(C.lockIcon)
			surface.DrawRect(w - 14, 9, 6, 6)
		end

		local IM = PinnedPanels.InteractMode
		local navEnabled = IM and (IM.Active or PinnedPanels.Settings.keyboardNavOutsideInteractMode)
		if pinId and navEnabled and IM.Focused == pinId then
			if IM.NavigatingPanel then
				surface.SetDrawColor(255, 50, 50, 255)
			else
				surface.SetDrawColor(C.focusRing)
			end
			surface.DrawOutlinedRect(0, 0, w, h, 2)

			if IM.NavigatingPanel and PinnedPanels.GetInteractiveElements then
				local elements = PinnedPanels.GetInteractiveElements(self)
				local el = elements[IM.NavFocusIndex]
				if IsValid(el) then
					local ex, ey = el:LocalToScreen(0, 0)
					local lx, ly = self:ScreenToLocal(ex, ey)
					local ew, eh = el:GetSize()
					
					surface.SetDrawColor(255, 255, 0, 150)
					surface.DrawOutlinedRect(lx - 2, ly - 2, ew + 4, eh + 4, 2)
					surface.SetDrawColor(255, 255, 0, 20)
					surface.DrawRect(lx, ly, ew, eh)
				end
			end
		end
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
local TITLE_HEIGHT    = 24
local CORNER_SIZE     = 16
local CLOSE_BTN_WIDTH = 30

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
	frame:ParentToHUD()
	frame:MakePopup()
	frame:SetKeyboardInputEnabled(false)

	local titleOverlay, resizeOverlay

	local function ApplyInteractState()
		local on = PinnedPanels.PanelsInteractive()
		frame:SetMouseInputEnabled(on)
		if IsValid(titleOverlay) then titleOverlay:SetMouseInputEnabled(on) end
		if IsValid(resizeOverlay) then resizeOverlay:SetMouseInputEnabled(on) end
	end

	local interactHook = "PinnedPanels_InteractFrame_" .. id .. "_" .. tostring(frame)
	hook.Add("PinnedPanels_InteractModeChanged", interactHook, function()
		if not IsValid(frame) then
			hook.Remove("PinnedPanels_InteractModeChanged", interactHook)
			return
		end
		ApplyInteractState()
	end)
	frame.OnRemove = function()
		hook.Remove("PinnedPanels_InteractModeChanged", interactHook)
	end

	frame:ShowCloseButton(true)
	frame.OnClose = function() frame:SetVisible(false) end
	frame.Paint   = PinnedPanels.GetFramePaint(title, id)

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
	titleOverlay:SetSize(fw - CLOSE_BTN_WIDTH, TITLE_HEIGHT)
	titleOverlay.Paint = function() end
	titleOverlay:SetMouseInputEnabled(false)
	titleOverlay:SetCursor("sizeall")

	resizeOverlay = vgui.Create("DPanel", frame)
	resizeOverlay:SetPos(fw - CORNER_SIZE, fh - CORNER_SIZE)
	resizeOverlay:SetSize(CORNER_SIZE, CORNER_SIZE)
	resizeOverlay.Paint = function() end
	resizeOverlay:SetMouseInputEnabled(false)
	resizeOverlay:SetCursor("sizenwse")

	ApplyInteractState()

	local function UpdateOverlayPositions()
		local fw2, fh2 = frame:GetSize()
		titleOverlay:SetSize(fw2 - CLOSE_BTN_WIDTH, TITLE_HEIGHT)
		resizeOverlay:SetPos(fw2 - CORNER_SIZE, fh2 - CORNER_SIZE)
	end

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
