local MIN_BOX = 24
local MIN_PANEL_W = 150
local MIN_PANEL_H = 100
local SNAP_DIST = 8

local C = PinnedPanels.C

local COLORS = {
	Color(80, 160, 255), Color(80, 220, 120),
	Color(255, 170, 60), Color(220, 80, 80),
	Color(180, 80, 220), Color(80, 210, 210),
	Color(255, 120, 170), Color(160, 200, 80),
}
local function GetColor(i) return COLORS[((i - 1) % #COLORS) + 1] end

local function Fit(s, maxChars)
	if #s > maxChars then return s:sub(1, maxChars - 2) .. ".." end
	return s
end

local EDITOR = {}
EDITOR.__index = EDITOR

-- ── Locked helper ─────────────────────────────────────────────────────────────
local function IsBoxLocked(box)
	local pin = PinnedPanels.Pins[box.id]
	return pin and pin.locked
end

function EDITOR:Create(parent)
	local self = setmetatable({}, EDITOR)
	self.boxes = {}
	self.dragging = nil
	self.resizing = nil
	self.canvasOX = 0
	self.canvasOY = 0
	self.scale = 0.25
	self.snapLines = {}

	self.root = vgui.Create("DPanel", parent)
	self.root:Dock(FILL)
	self.root.Paint = function() end

	local info = vgui.Create("DLabel", self.root)
	info:SetText("Drag boxes to reposition panels. Drag any edge or corner to resize. Right-click for options. Grouped panels have a highlighted border and member badge. Changes apply live.")
	info:SetWrap(true)
	info:Dock(TOP)
	info:DockMargin(6, 6, 6, 4)
	info:SetTextColor(C.textLabel)
	info:SetAutoStretchVertical(true)

	self.canvas = vgui.Create("DPanel", self.root)
	self.canvas:Dock(FILL)
	self.canvas:DockMargin(4, 0, 4, 4)
	self.canvas:SetMouseInputEnabled(true)
	self.canvas:SetCursor("arrow")

	self.canvas.Paint = function(cv, w, h)
		local scrW, scrH = ScrW(), ScrH()
		draw.RoundedBox(4, 0, 0, w, h, C.canvasBg)

		local padding = 40
		local availW = w - padding
		local availH = h - padding
		self.scale = math.min(availW / scrW, availH / scrH)

		local prevW = math.floor(scrW * self.scale)
		local prevH = math.floor(scrH * self.scale)
		local ox = math.floor((w - prevW) / 2)
		local oy = math.floor((h - prevH) / 2)
		self.canvasOX = ox
		self.canvasOY = oy

		surface.SetDrawColor(C.canvasScreen)
		surface.DrawRect(ox, oy, prevW, prevH)
		surface.SetDrawColor(C.canvasBorder)
		surface.DrawOutlinedRect(ox, oy, prevW, prevH, 1)

		draw.SimpleText("SCREEN  " .. scrW .. "×" .. scrH, "DermaDefault",
			ox + prevW / 2, oy + 8, C.canvasLabel, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)

		for _, box in ipairs(self.boxes) do
			local bx = ox + math.floor(box.px * self.scale)
			local by = oy + math.floor(box.py * self.scale)
			local bw = math.max(MIN_BOX, math.floor(box.pw * self.scale))
			local bh = math.max(MIN_BOX, math.floor(box.ph * self.scale))
			local col = box.color
			local isInteract = box.dragging or box.resizing

			draw.RoundedBox(3, bx + 2, by + 2, bw, bh, C.boxShadow)
			surface.SetDrawColor(col.r, col.g, col.b, isInteract and 230 or 180)
			surface.DrawRect(bx, by, bw, bh)
			surface.SetDrawColor(col.r, col.g, col.b, isInteract and 255 or 200)
			surface.DrawOutlinedRect(bx, by, bw, bh, isInteract and 2 or 1)

			if box.isGroup then
				surface.SetDrawColor(C.groupBorder)
				surface.DrawOutlinedRect(bx - 2, by - 2, bw + 4, bh + 4, 1)
			end

			if not box.isGroup then
				local pin = PinnedPanels.Pins[box.id]
				if pin and pin.locked then
					draw.SimpleText("🔒", "DermaDefault", bx + 4, by + 2, C.lockIcon, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
				end
			end

			local maxChars = math.max(3, math.floor(bw / 6))
			local cx = bx + bw / 2

			if box.isGroup and box.memberNames and #box.memberNames > 0 then
				local names = box.memberNames
				local nameCount = #names
				local totalCount = box.memberCount or nameCount
				local hasExtra = totalCount > nameCount

				local lineHeight = 11
				local titleHeight = 14
				local blockHeight = titleHeight + (nameCount + (hasExtra and 1 or 0)) * lineHeight
				local topY = by + (bh - blockHeight) * 0.5

				draw.SimpleText(Fit(box.label, maxChars), "DermaDefaultBold",
					cx, topY, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)

				for i = 1, nameCount do
					draw.SimpleText(Fit(names[i], maxChars), "DermaDefault",
						cx, topY + titleHeight + (i - 1) * lineHeight,
						C.groupBadgeText, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
				end

				if hasExtra then
					draw.SimpleText(string.format("+%d more", totalCount - nameCount), "DermaDefault",
						cx, topY + titleHeight + nameCount * lineHeight,
						C.textMuted, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
				end
			else
				draw.SimpleText(Fit(box.label, maxChars), "DermaDefault",
					cx, by + bh * 0.5, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			end

			if box.cropped then
				draw.SimpleText("CROPPED", "DermaDefaultBold",
					bx + bw - 4, by + 2, C.cropLabel, TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP)
			end

			draw.SimpleText(math.floor(box.px) .. "," .. math.floor(box.py)
				.. "  " .. math.floor(box.pw) .. "×" .. math.floor(box.ph),
				"DermaDefault", bx + bw / 2, by + bh - 10,
				C.boxCoords, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)

			if box.isGroup then
				surface.SetFont("DermaDefault")
				local badge = "[ " .. (box.memberCount or 0) .. " panels ]"
				local tw = surface.GetTextSize(badge)
				draw.RoundedBox(3, bx + 2, by + 2, tw + 8, 15, C.groupBadgeBg)
				draw.SimpleText(badge, "DermaDefault", bx + 6, by + 3, C.groupBadgeText,
					TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
			end
		end

		surface.SetDrawColor(C.snapGuide)
		for _, line in ipairs(self.snapLines) do
			surface.DrawLine(line[1], line[2], line[3], line[4])
		end

		local ts = PinnedPanels.Settings.taskbar
		if ts and ts.enabled ~= false then
			local tbH = math.floor((ts.height or 32) * self.scale)
			local tbBg = ts.bgColor or C.taskbarBg
			local tbx, tby, tbw, tbh

			if ts.position == "top" then
				tbx, tby, tbw, tbh = ox, oy, prevW, tbH
			elseif ts.position == "left" then
				tbx, tby, tbw, tbh = ox, oy, tbH, prevH
			elseif ts.position == "right" then
				tbx, tby, tbw, tbh = ox + prevW - tbH, oy, tbH, prevH
			else
				tbx, tby, tbw, tbh = ox, oy + prevH - tbH, prevW, tbH
			end

			surface.SetDrawColor(tbBg.r, tbBg.g, tbBg.b, 200)
			surface.DrawRect(tbx, tby, tbw, tbh)
			surface.SetDrawColor(C.taskbarBorder)
			surface.DrawOutlinedRect(tbx, tby, tbw, tbh, 1)

			local minimized = PinnedPanels.GetMinimizedPanels()
			if #minimized > 0 then
				local entryOff = 3
				local isHoriz = (ts.position == "bottom" or ts.position == "top")
				for _, mEntry in ipairs(minimized) do
					local entryW = isHoriz and math.min(60, math.floor((tbw - 6) / #minimized)) or (tbw - 6)
					local entryH = isHoriz and (tbh - 6) or math.min(14, math.floor((tbh - 6) / #minimized))
					local ex = isHoriz and (tbx + entryOff) or (tbx + 3)
					local ey = isHoriz and (tby + 3) or (tby + entryOff)

					surface.SetDrawColor(C.taskbarEntry)
					surface.DrawRect(ex, ey, entryW, entryH)
					surface.SetDrawColor(C.taskbarBorder)
					surface.DrawOutlinedRect(ex, ey, entryW, entryH, 1)

					if isHoriz and entryW > 20 then
						local maxC = math.max(2, math.floor(entryW / 6))
						draw.SimpleText(Fit(mEntry.title, maxC), "DermaDefault",
							ex + entryW / 2, ey + entryH / 2,
							C.taskbarText, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
					end

					entryOff = entryOff + (isHoriz and entryW or entryH) + 2
				end
			end

			draw.SimpleText("TASKBAR", "DermaDefault",
				tbx + tbw / 2, tby + tbh / 2,
				Color(C.taskbarText.r, C.taskbarText.g, C.taskbarText.b, #minimized > 0 and 60 or 120),
				TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end

		if #self.boxes == 0 then
			draw.SimpleText("No pinned panels. Pin tools from the Tools tab.",
				"DermaDefault", w / 2, h / 2, C.emptyText, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end
	end

	-- ── Edge-Snap Helper ─────────────────────────────────────────────────────
	local function ComputeSnap(box, rawX, rawY, rawW, rawH, scrW, scrH)
		local snapX, snapY = rawX, rawY
		local lines = {}
		local ox, oy = self.canvasOX, self.canvasOY

		local edges = {
			{ val = rawX, ref = 0, axis = "x" },
			{ val = rawX + rawW, ref = scrW, axis = "xr" },
			{ val = rawY, ref = 0, axis = "y" },
			{ val = rawY + rawH, ref = scrH, axis = "yr" },
		}

		for _, other in ipairs(self.boxes) do
			if other ~= box then
				edges[#edges + 1] = { val = rawX, ref = other.px, axis = "x" }
				edges[#edges + 1] = { val = rawX, ref = other.px + other.pw, axis = "x" }
				edges[#edges + 1] = { val = rawX + rawW, ref = other.px, axis = "xr" }
				edges[#edges + 1] = { val = rawX + rawW, ref = other.px + other.pw, axis = "xr" }
				edges[#edges + 1] = { val = rawY, ref = other.py, axis = "y" }
				edges[#edges + 1] = { val = rawY, ref = other.py + other.ph, axis = "y" }
				edges[#edges + 1] = { val = rawY + rawH, ref = other.py, axis = "yr" }
				edges[#edges + 1] = { val = rawY + rawH, ref = other.py + other.ph, axis = "yr" }
			end
		end

		for _, e in ipairs(edges) do
			if math.abs(e.val - e.ref) < SNAP_DIST then
				local screenRef = math.floor(e.ref * self.scale)
				if e.axis == "x" then
					snapX = e.ref
					local lx = ox + screenRef
					lines[#lines + 1] = { lx, oy, lx, oy + math.floor(scrH * self.scale) }
				elseif e.axis == "xr" then
					snapX = e.ref - rawW
					local lx = ox + screenRef
					lines[#lines + 1] = { lx, oy, lx, oy + math.floor(scrH * self.scale) }
				elseif e.axis == "y" then
					snapY = e.ref
					local ly = oy + screenRef
					lines[#lines + 1] = { ox, ly, ox + math.floor(scrW * self.scale), ly }
				elseif e.axis == "yr" then
					snapY = e.ref - rawH
					local ly = oy + screenRef
					lines[#lines + 1] = { ox, ly, ox + math.floor(scrW * self.scale), ly }
				end
			end
		end

		snapX = math.Clamp(snapX, 0, scrW - rawW)
		snapY = math.Clamp(snapY, 0, scrH - rawH)

		return snapX, snapY, lines
	end

	-- ── Apply live position/size to the underlying frame ─────────────────────
	local function ApplyBoxToFrame(box, zone)
		local pin = PinnedPanels.Pins[box.id]
		if pin and IsValid(pin.frame) then
			pin.frame:SetPos(math.floor(box.px), math.floor(box.py))
			pin.frame:SetSize(math.floor(box.pw), math.floor(box.ph))
			if zone and pin.crop and isfunction(pin.frame.OnUserResized) then
				pin.frame._lastResizeZone = zone
				pin.frame.OnUserResized(pin.frame:GetSize())
			end
		end
	end

	local function BoxAt(px, py)
		local ox2, oy2 = self.canvasOX, self.canvasOY
		for i = #self.boxes, 1, -1 do
			local box = self.boxes[i]
			local bx = ox2 + math.floor(box.px * self.scale)
			local by = oy2 + math.floor(box.py * self.scale)
			local bw = math.max(MIN_BOX, math.floor(box.pw * self.scale))
			local bh = math.max(MIN_BOX, math.floor(box.ph * self.scale))
			if px >= bx and px <= bx + bw and py >= by and py <= by + bh then
				return box, bx, by, bw, bh
			end
		end
	end

	local RESIZE_MARGIN = 6
	local function ZoneAt(bx, by, bw, bh, px, py)
		local zone = {
			w = px <= bx + RESIZE_MARGIN,
			e = px >= bx + bw - RESIZE_MARGIN,
			n = py <= by + RESIZE_MARGIN,
			s = py >= by + bh - RESIZE_MARGIN,
		}
		if zone.w or zone.e or zone.n or zone.s then return zone end
	end

	self.canvas.OnMousePressed = function(cv, mc)
		local mx, my = cv:CursorPos()

		if mc == MOUSE_RIGHT then
			local box = BoxAt(mx, my)
			if box then
				local pin = PinnedPanels.Pins[box.id]
				if pin and IsValid(pin.frame) then
					PinnedPanels.OpenContextMenu(box.id, pin.frame)
				end
			end
			return
		end

		if mc ~= MOUSE_LEFT then return end

		local box, bx, by, bw, bh = BoxAt(mx, my)
		if not box then return end

		if IsBoxLocked(box) then return end

		local zone = ZoneAt(bx, by, bw, bh, mx, my)
		if zone then
			local pin = PinnedPanels.Pins[box.id]
			if pin then pin.maximized = false end
			self.resizing = box
			box.resizing = true
			box.zone = zone
			box.startPx, box.startPy = box.px, box.py
			box.startPw, box.startPh = box.pw, box.ph
			box.startMx, box.startMy = mx, my
		else
			self.dragging = box
			box.dragging = true
			box.ox = mx - bx
			box.oy = my - by
		end
		cv:MouseCapture(true)
	end

	self.canvas.OnMouseReleased = function(cv, mc)
		if self.dragging then
			self.dragging.dragging = false
			self.dragging = nil
		end
		if self.resizing then
			local box = self.resizing
			box.resizing = false
			self.resizing = nil
			local pin = PinnedPanels.Pins[box.id]
			if pin and IsValid(pin.frame) then
				pin.frame._lastResizeZone = box.zone
				if isfunction(pin.frame.OnUserResized) then
					pin.frame.OnUserResized(pin.frame:GetSize())
				end
			end
			box.zone = nil
		end
		self.snapLines = {}
		cv:MouseCapture(false)
		PinnedPanels.Save()
	end

	self.canvas.OnCursorMoved = function(cv, mx, my)
		local ox2, oy2 = self.canvasOX, self.canvasOY
		local scrW, scrH = ScrW(), ScrH()

		if self.resizing then
			local box = self.resizing
			if IsBoxLocked(box) then return end
			local zone = box.zone or {}

			local dxp = (mx - box.startMx) / self.scale
			local dyp = (my - box.startMy) / self.scale
			local left, top = box.startPx, box.startPy
			local right, bottom = left + box.startPw, top + box.startPh

			local pin = PinnedPanels.Pins[box.id]
			local minW = (pin and pin.crop) and 60 or MIN_PANEL_W
			local minH = (pin and pin.crop) and 60 or MIN_PANEL_H
			local maxW, maxH = math.huge, math.huge
			if pin and pin.crop and pin.cropBase then
				maxW = zone.w and (pin.cropBase.w - pin.crop.r) or (pin.cropBase.w - pin.crop.l)
				maxH = zone.n and (pin.cropBase.h - pin.crop.b) or (pin.cropBase.h - pin.crop.t)
			end

			local lines = {}
			local function SnapX(raw)
				local refs = { 0, scrW }
				for _, other in ipairs(self.boxes) do
					if other ~= box then
						refs[#refs + 1] = other.px
						refs[#refs + 1] = other.px + other.pw
					end
				end
				for _, r in ipairs(refs) do
					if math.abs(raw - r) < SNAP_DIST then
						local lx = ox2 + math.floor(r * self.scale)
						lines[#lines + 1] = { lx, oy2, lx, oy2 + math.floor(scrH * self.scale) }
						return r
					end
				end
				return raw
			end
			local function SnapY(raw)
				local refs = { 0, scrH }
				for _, other in ipairs(self.boxes) do
					if other ~= box then
						refs[#refs + 1] = other.py
						refs[#refs + 1] = other.py + other.ph
					end
				end
				for _, r in ipairs(refs) do
					if math.abs(raw - r) < SNAP_DIST then
						local ly = oy2 + math.floor(r * self.scale)
						lines[#lines + 1] = { ox2, ly, ox2 + math.floor(scrW * self.scale), ly }
						return r
					end
				end
				return raw
			end

			if zone.e then
				local edge = math.Clamp(SnapX(right + dxp), left + minW, math.min(scrW, left + maxW))
				box.pw = edge - left
			elseif zone.w then
				local edge = math.Clamp(SnapX(left + dxp), math.max(0, right - maxW), right - minW)
				box.px = edge
				box.pw = right - edge
			end
			if zone.s then
				local edge = math.Clamp(SnapY(bottom + dyp), top + minH, math.min(scrH, top + maxH))
				box.ph = edge - top
			elseif zone.n then
				local edge = math.Clamp(SnapY(top + dyp), math.max(0, bottom - maxH), bottom - minH)
				box.py = edge
				box.ph = bottom - edge
			end

			self.snapLines = lines
			ApplyBoxToFrame(box, zone)
		elseif self.dragging then
			local box = self.dragging
			local bw = math.max(MIN_BOX, math.floor(box.pw * self.scale))
			local bh = math.max(MIN_BOX, math.floor(box.ph * self.scale))
			local maxX = math.floor(scrW * self.scale) - bw
			local maxY = math.floor(scrH * self.scale) - bh
			local npx = math.Clamp(mx - ox2 - box.ox, 0, maxX) / self.scale
			local npy = math.Clamp(my - oy2 - box.oy, 0, maxY) / self.scale

			npx = math.Clamp(npx, 0, scrW - box.pw)
			npy = math.Clamp(npy, 0, scrH - box.ph)

			local snapX, snapY, lines = ComputeSnap(box, npx, npy, box.pw, box.ph, scrW, scrH)
			box.px = snapX
			box.py = snapY
			self.snapLines = lines
			ApplyBoxToFrame(box)
		else
			local box, bx, by, bw, bh = BoxAt(mx, my)
			if box and not IsBoxLocked(box) then
				local zone = ZoneAt(bx, by, bw, bh, mx, my)
				if zone then
					if (zone.n and zone.w) or (zone.s and zone.e) then
						cv:SetCursor("sizenwse")
					elseif (zone.n and zone.e) or (zone.s and zone.w) then
						cv:SetCursor("sizenesw")
					elseif zone.e or zone.w then
						cv:SetCursor("sizewe")
					else
						cv:SetCursor("sizens")
					end
				else
					cv:SetCursor("sizeall")
				end
			else
				cv:SetCursor("arrow")
			end
		end
	end

	-- ── Position sync think panel ────────────────────────────────────────────
	local thinkPanel = vgui.Create("DPanel", parent)
	thinkPanel:SetSize(0, 0)
	thinkPanel.NextCheck = 0

	thinkPanel.Think = function()
		if not IsValid(self.root) then
			thinkPanel:Remove()
			return
		end
		if CurTime() < thinkPanel.NextCheck then return end
		thinkPanel.NextCheck = CurTime() + 0.2

		for _, box in ipairs(self.boxes) do
			if not box.dragging and not box.resizing then
				local pin = PinnedPanels.Pins[box.id]
				if pin and IsValid(pin.frame) then
					local x, y = pin.frame:GetPos()
					local w, h = pin.frame:GetSize()
					box.px, box.py, box.pw, box.ph = x, y, w, h
					box.cropped = pin.crop ~= nil
				end
			end
		end
	end

	local stateHookName = "PinnedPanels_LayoutEditor_" .. tostring(self.root)
	hook.Add("PinnedPanels_StateChanged", stateHookName, function()
		if not IsValid(self.root) then
			hook.Remove("PinnedPanels_StateChanged", stateHookName)
			return
		end
		if not self.dragging and not self.resizing then
			self:Rebuild()
		end
	end)

	self.root.OnRemove = function()
		if IsValid(thinkPanel) then thinkPanel:Remove() end
		hook.Remove("PinnedPanels_StateChanged", stateHookName)
	end

	self:Rebuild()
	return self
end

function EDITOR:Rebuild()
	self.boxes = {}
	self.snapLines = {}

	local sorted = {}
	for id, pin in pairs(PinnedPanels.Pins) do
		if IsValid(pin.frame) and pin.frame:IsVisible() then
			sorted[#sorted + 1] = { id = id, pin = pin }
		end
	end
	table.sort(sorted, function(a, b) return a.pin.title < b.pin.title end)

	for i, entry in ipairs(sorted) do
		local frame = entry.pin.frame
		local x, y = frame:GetPos()
		local w, h = frame:GetSize()
		local isGroup = entry.pin.kind == "group"

		local gCol, memberCount, memberNames
		if isGroup and entry.pin.groupName then
			for _, g in ipairs(PinnedPanels.Settings.groups) do
				if g.name == entry.pin.groupName then
					gCol = g.color
					memberCount = #g.ids
					memberNames = {}
					for mi, pid in ipairs(g.ids) do
						if mi > 15 then break end
						local mp = PinnedPanels.Pins[pid]
						memberNames[#memberNames + 1] = mp and mp.title or pid
					end
					break
				end
			end
		end

		self.boxes[#self.boxes + 1] = {
			id = entry.id,
			label = entry.pin.title,
			color = gCol or GetColor(i),
			px = x,
			py = y,
			pw = w,
			ph = h,
			dragging = false,
			resizing = false,
			ox = 0,
			oy = 0,
			isGroup = isGroup,
			memberCount = memberCount,
			memberNames = memberNames,
			cropped = entry.pin.crop ~= nil,
		}
	end
end

function PinnedPanels.CreateLayoutEditor(parent)
	return EDITOR:Create(parent)
end
