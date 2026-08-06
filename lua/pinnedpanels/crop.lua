local C = PinnedPanels.C

-- ── Panel Cropping ───────────────────────────────────────────────────────────

local MIN_VISIBLE = 40

local function ContentRoot(pin, id)
	if not pin then return nil end
	if pin.kind == "group" then
		local mid = PinnedPanels.GetActiveGroupMemberId and PinnedPanels.GetActiveGroupMemberId(id)
		local mp = mid and PinnedPanels.Pins[mid]
		return (mp and IsValid(mp.content)) and mp.content or nil
	end
	if pin.kind == "frame" then
		return IsValid(pin.livePanel) and pin.livePanel or nil
	end
	return IsValid(pin.content) and pin.content or nil
end

-- ── Apply / Clear ────────────────────────────────────────────────────────────
local function SyncTabCrop(pin, id)
	if pin.kind ~= "group" or not pin.crop then return end
	local mid = PinnedPanels.GetActiveGroupMemberId and PinnedPanels.GetActiveGroupMemberId(id)
	if not mid then return end
	pin.tabCrops = pin.tabCrops or {}
	pin.tabCrops[mid] = table.Copy(pin.crop)
end

function PinnedPanels.ApplyCrop(id, crop)
	local pin = PinnedPanels.Pins[id]
	if not pin or not IsValid(pin.frame) or not istable(crop) then return false end

	local knownContent, knownW, knownH
	if pin.crop and IsValid(pin._cropContent) then
		knownContent = pin._cropContent
		knownW, knownH = knownContent:GetSize()
	end
	if pin.crop then PinnedPanels.ClearCrop(id, true) end

	local content = ContentRoot(pin, id)
	if not IsValid(content) then return false end

	local frame = pin.frame
	if pin.maximized then PinnedPanels.ToggleMaximizePanel(id) end

	frame:InvalidateLayout(true)
	if pin.kind == "group" and IsValid(pin.sheet) then
		pin.sheet:InvalidateLayout(true)
	end
	local host = content:GetParent()
	if IsValid(host) and host ~= frame then
		host:InvalidateLayout(true)
	end

	local fw, fh = frame:GetSize()
	local cw, ch = content:GetSize()
	if content == knownContent then cw, ch = knownW, knownH end

	local l = math.Clamp(math.Round(crop.l or 0), 0, math.max(0, cw - MIN_VISIBLE))
	local t = math.Clamp(math.Round(crop.t or 0), 0, math.max(0, ch - MIN_VISIBLE))
	local r = math.Clamp(math.Round(crop.r or 0), 0, math.max(0, cw - l - MIN_VISIBLE))
	local b = math.Clamp(math.Round(crop.b or 0), 0, math.max(0, ch - t - MIN_VISIBLE))
	if l + t + r + b == 0 then return false end

	local ml, mt2, mr, mb = content:GetDockMargin()
	local viewport = vgui.Create("DPanel", host)
	viewport:Dock(FILL)
	viewport:DockMargin(ml, mt2, mr, mb)
	viewport:SetMouseInputEnabled(false)
	viewport:SetKeyboardInputEnabled(false)
	viewport.Paint = function() end
	viewport._pp_cropViewport = true

	pin._cropRestore = { margin = { ml, mt2, mr, mb }, parent = host }
	pin._cropContent = content

	content:SetParent(viewport)
	content:Dock(NODOCK)
	content:SetMouseInputEnabled(true)
	content:SetSize(cw, ch)
	content:SetPos(-l, -t)

	pin.crop          = { l = l, t = t, r = r, b = b }
	pin.cropBase      = { w = fw, h = fh }
	pin._cropViewport = viewport

	if not pin._cropSizeHooked then
		pin._cropSizeHooked = true
		local prevResized = frame.OnUserResized
		frame.OnUserResized = function(w, h)
			if isfunction(prevResized) then prevResized(w, h) end
			local p = PinnedPanels.Pins[id]
			if not (p and p.crop and p.cropBase and IsValid(p.frame)) then return end
			local c, base = p.crop, p.cropBase
			local zone  = p.frame._lastResizeZone
			local fromW = zone and zone.w or false
			local fromN = zone and zone.n or false

			local nw, nh = w, h
			if fromW then
				nw = math.min(w, base.w - c.r)
				c.l = math.max(0, base.w - c.r - nw)
			else
				nw = math.min(w, base.w - c.l)
				c.r = math.max(0, base.w - c.l - nw)
			end
			if fromN then
				nh = math.min(h, base.h - c.b)
				c.t = math.max(0, base.h - c.b - nh)
			else
				nh = math.min(h, base.h - c.t)
				c.b = math.max(0, base.h - c.t - nh)
			end

			if nw ~= w or nh ~= h then
				local fx, fy = p.frame:GetPos()
				if fromW and nw ~= w then fx = fx + (w - nw) end
				if fromN and nh ~= h then fy = fy + (h - nh) end
				p.frame:SetSize(nw, nh)
				p.frame:SetPos(fx, fy)
			end
			if IsValid(p._cropContent) then
				p._cropContent:SetPos(-c.l, -c.t)
			end
			SyncTabCrop(p, id)
		end
	end

	frame:SetSize(fw - l - r, fh - t - b)
	frame:InvalidateLayout(true)
	SyncTabCrop(pin, id)
	PinnedPanels.Save()
	return true
end

function PinnedPanels.ClearCrop(id, keepStored)
	local pin = PinnedPanels.Pins[id]
	if not pin or not pin.crop then return end

	if not keepStored and pin.kind == "group" and pin.tabCrops then
		local mid = PinnedPanels.GetActiveGroupMemberId and PinnedPanels.GetActiveGroupMemberId(id)
		if mid then pin.tabCrops[mid] = nil end
	end

	local frame   = IsValid(pin.frame) and pin.frame or nil
	local content = IsValid(pin._cropContent) and pin._cropContent or nil
	local rest    = pin._cropRestore

	if content and IsValid(pin._cropViewport) and content:GetParent() == pin._cropViewport then
		local parent = (rest and IsValid(rest.parent)) and rest.parent or frame
		if IsValid(parent) then
			content:SetParent(parent)
			content:Dock(FILL)
			if rest and rest.margin then
				content:DockMargin(unpack(rest.margin))
			end
		end
	end
	if IsValid(pin._cropViewport) then pin._cropViewport:Remove() end

	if frame and pin.cropBase then
		frame:SetSize(pin.cropBase.w, pin.cropBase.h)
		frame:InvalidateLayout(true)
	end

	pin.crop, pin.cropBase = nil, nil
	pin._cropViewport, pin._cropRestore, pin._cropContent = nil, nil, nil
	PinnedPanels.Save()
end

-- ── Interactive Crop Editor ──────────────────────────────────────────────────
function PinnedPanels.OpenCropEditor(id)
	local pin = PinnedPanels.Pins[id]
	if not pin or not IsValid(pin.frame) then return end
	if not IsValid(ContentRoot(pin, id)) then return end
	if IsValid(pin._cropEditor) then pin._cropEditor:Remove() end

	if pin.minimized and PinnedPanels.RestoreFromTaskbar then
		PinnedPanels.RestoreFromTaskbar(id)
	end
	if not pin.frame:IsVisible() then pin.frame:SetVisible(true) end

	local IM = PinnedPanels.CursorMode
	if IM and IM.SpawnMenuOpen then
		if IM.Enable then IM.Enable() end
		if IsValid(g_SpawnMenu) then g_SpawnMenu:Close() end
		IM.SpawnMenuOpen = false
		if PinnedPanels.UpdatePanelStates then PinnedPanels.UpdatePanelStates() end
	end

	local frame = pin.frame

	local prevCrop = pin.crop and table.Copy(pin.crop) or nil
	local cx, cy, cw, ch
	if pin.crop then
		if IsValid(pin._cropViewport) and IsValid(pin._cropContent) then
			local vsx, vsy = pin._cropViewport:LocalToScreen(0, 0)
			cx, cy = frame:ScreenToLocal(vsx, vsy)
			cw, ch = pin._cropContent:GetSize()
		end
		PinnedPanels.ClearCrop(id, true)
	end
	if pin.maximized then PinnedPanels.ToggleMaximizePanel(id) end

	local wasClickThrough = pin.clickThrough or false
	if wasClickThrough then
		pin.clickThrough = false
		hook.Run("PinnedPanels_CursorModeChanged")
	end

	frame:MoveToFront()
	frame:InvalidateLayout(true)

	local content = ContentRoot(pin, id)
	if not IsValid(content) then
		if wasClickThrough then
			pin.clickThrough = true
			hook.Run("PinnedPanels_CursorModeChanged")
		end
		return
	end
	local fw, fh = frame:GetSize()
	if not cx then
		local csx, csy = content:LocalToScreen(0, 0)
		cx, cy = frame:ScreenToLocal(csx, csy)
		cw, ch = content:GetSize()
	end

	local ov = vgui.Create("DPanel", frame)
	ov:SetPos(0, 0)
	ov:SetSize(fw, fh)
	ov:SetMouseInputEnabled(true)
	ov._pp_skipNav = true
	pin._cropEditor = ov
	ov.OnRemove = function()
		if pin._cropEditor == ov then pin._cropEditor = nil end
		if wasClickThrough and PinnedPanels.Pins[id] == pin then
			pin.clickThrough = true
			hook.Run("PinnedPanels_CursorModeChanged")
		end
	end

	local function Cancel()
		ov:Remove()
		if prevCrop then PinnedPanels.ApplyCrop(id, prevCrop) end
	end

	local sel = { x = cx, y = cy, w = cw, h = ch }
	if prevCrop then
		sel.x = cx + prevCrop.l
		sel.y = cy + prevCrop.t
		sel.w = math.max(MIN_VISIBLE, cw - prevCrop.l - prevCrop.r)
		sel.h = math.max(MIN_VISIBLE, ch - prevCrop.t - prevCrop.b)
	end

	local function ClampSel()
		sel.w = math.Clamp(sel.w, MIN_VISIBLE, cw)
		sel.h = math.Clamp(sel.h, MIN_VISIBLE, ch)
		sel.x = math.Clamp(sel.x, cx, cx + cw - sel.w)
		sel.y = math.Clamp(sel.y, cy, cy + ch - sel.h)
	end
	ClampSel()

	local HANDLE = 12

	local function HitTest(mx, my)
		if mx < sel.x - HANDLE or mx > sel.x + sel.w + HANDLE
			or my < sel.y - HANDLE or my > sel.y + sel.h + HANDLE then
			return nil
		end
		local nearL = math.abs(mx - sel.x) <= HANDLE
		local nearR = math.abs(mx - (sel.x + sel.w)) <= HANDLE
		local nearT = math.abs(my - sel.y) <= HANDLE
		local nearB = math.abs(my - (sel.y + sel.h)) <= HANDLE
		if nearL and nearR then
			if mx - sel.x <= (sel.x + sel.w) - mx then nearR = false else nearL = false end
		end
		if nearT and nearB then
			if my - sel.y <= (sel.y + sel.h) - my then nearB = false else nearT = false end
		end
		if nearL or nearR or nearT or nearB then
			return { l = nearL, r = nearR, t = nearT, b = nearB }
		end
		return "move"
	end

	local function InContent(mx, my)
		return mx >= cx and mx <= cx + cw and my >= cy and my <= cy + ch
	end

	local drag, dragOffX, dragOffY = nil, 0, 0
	local anchorX, anchorY = 0, 0

	ov.OnMousePressed = function(self, mc)
		if mc == MOUSE_RIGHT then
			Cancel()
			return
		end
		if mc ~= MOUSE_LEFT then return end
		local mx, my = self:CursorPos()
		drag = HitTest(mx, my)
		if drag == "move" then
			dragOffX, dragOffY = mx - sel.x, my - sel.y
		elseif istable(drag) then
			dragOffX = (drag.l and mx - sel.x) or (drag.r and mx - (sel.x + sel.w)) or 0
			dragOffY = (drag.t and my - sel.y) or (drag.b and my - (sel.y + sel.h)) or 0
		elseif InContent(mx, my) then
			drag = "new"
			anchorX, anchorY = mx, my
			sel.x, sel.y, sel.w, sel.h = mx, my, 1, 1
		end
		if drag then self:MouseCapture(true) end
	end

	ov.OnMouseReleased = function(self)
		if drag == "new" then ClampSel() end
		drag = nil
		self:MouseCapture(false)
	end

	ov.Think = function(self)
		local mx, my = self:CursorPos()

		if not drag then
			local hit = HitTest(mx, my)
			if hit == "move" then
				self:SetCursor("sizeall")
			elseif istable(hit) then
				if (hit.l and hit.t) or (hit.r and hit.b) then
					self:SetCursor("sizenwse")
				elseif (hit.r and hit.t) or (hit.l and hit.b) then
					self:SetCursor("sizenesw")
				elseif hit.l or hit.r then
					self:SetCursor("sizewe")
				else
					self:SetCursor("sizens")
				end
			elseif InContent(mx, my) then
				self:SetCursor("crosshair")
			else
				self:SetCursor("arrow")
			end
			return
		end

		if drag == "move" then
			sel.x, sel.y = mx - dragOffX, my - dragOffY
			ClampSel()
		elseif drag == "new" then
			local bx = math.Clamp(mx, cx, cx + cw)
			local by = math.Clamp(my, cy, cy + ch)
			sel.x, sel.w = math.min(anchorX, bx), math.abs(bx - anchorX)
			sel.y, sel.h = math.min(anchorY, by), math.abs(by - anchorY)
		elseif istable(drag) then
			local ex = mx - dragOffX
			local ey = my - dragOffY
			if drag.l then
				local right = sel.x + sel.w
				sel.x = math.Clamp(ex, cx, right - MIN_VISIBLE)
				sel.w = right - sel.x
			elseif drag.r then
				sel.w = math.Clamp(ex - sel.x, MIN_VISIBLE, cx + cw - sel.x)
			end
			if drag.t then
				local bottom = sel.y + sel.h
				sel.y = math.Clamp(ey, cy, bottom - MIN_VISIBLE)
				sel.h = bottom - sel.y
			elseif drag.b then
				sel.h = math.Clamp(ey - sel.y, MIN_VISIBLE, cy + ch - sel.y)
			end
		end
	end

	ov.Paint = function(self, w, h)
		surface.SetDrawColor(0, 0, 0, 160)
		surface.DrawRect(0, 0, w, sel.y)
		surface.DrawRect(0, sel.y + sel.h, w, h - sel.y - sel.h)
		surface.DrawRect(0, sel.y, sel.x, sel.h)
		surface.DrawRect(sel.x + sel.w, sel.y, w - sel.x - sel.w, sel.h)

		surface.SetDrawColor(C.accent)
		surface.DrawOutlinedRect(sel.x, sel.y, sel.w, sel.h, 2)

		local hs = 6
		local pts = {
			{ sel.x,             sel.y },
			{ sel.x + sel.w,     sel.y },
			{ sel.x,             sel.y + sel.h },
			{ sel.x + sel.w,     sel.y + sel.h },
			{ sel.x + sel.w / 2, sel.y },
			{ sel.x + sel.w / 2, sel.y + sel.h },
			{ sel.x,             sel.y + sel.h / 2 },
			{ sel.x + sel.w,     sel.y + sel.h / 2 },
		}
		for _, p in ipairs(pts) do
			surface.DrawRect(p[1] - hs / 2, p[2] - hs / 2, hs, hs)
		end

		draw.SimpleText(PinnedPanels.L("crop_hint"),
			"DermaDefault", w / 2, 4, C.textBright, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
	end

	-- ── Toolbar ──────────────────────────────────────────────────────────────
	local btnW   = math.min(64, math.floor((fw - 24) / 3))
	local startX = math.max(4, math.floor((fw - (btnW * 3 + 12)) / 2))

	local function MakeBtn(text, slot, onClick)
		local btn = vgui.Create("DButton", ov)
		btn:SetText(text)
		btn:SetSize(btnW, 22)
		btn:SetPos(startX + (btnW + 6) * slot, fh - 30)
		btn:SetTextColor(C.textLight)
		btn.Paint = function(self, bw, bh)
			draw.RoundedBox(4, 0, 0, bw, bh, self:IsHovered() and C.btnBgHov or C.btnBg)
			surface.SetDrawColor(C.btnOutline)
			surface.DrawOutlinedRect(0, 0, bw, bh, 1)
		end
		btn.DoClick = onClick
		return btn
	end

	MakeBtn(PinnedPanels.L("btn_apply"), 0, function()
		local l = sel.x - cx
		local t = sel.y - cy
		local r = (cx + cw) - (sel.x + sel.w)
		local b = (cy + ch) - (sel.y + sel.h)
		ov:Remove()
		if l + t + r + b > 0 then
			PinnedPanels.ApplyCrop(id, { l = l, t = t, r = r, b = b })
		else
			if pin.kind == "group" and pin.tabCrops then
				local mid = PinnedPanels.GetActiveGroupMemberId and PinnedPanels.GetActiveGroupMemberId(id)
				if mid then pin.tabCrops[mid] = nil end
			end
			PinnedPanels.Save()
		end
	end)

	MakeBtn(PinnedPanels.L("crop_full"), 1, function()
		sel.x, sel.y, sel.w, sel.h = cx, cy, cw, ch
	end)

	MakeBtn(PinnedPanels.L("btn_cancel"), 2, Cancel)

	hook.Add("PinnedPanels_CursorModeChanged", ov, function(pnl)
		if not IsValid(pnl) then return end
		if not PinnedPanels.PanelsInteractive() then Cancel() end
	end)
end
