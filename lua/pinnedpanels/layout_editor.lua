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
	info:SetText("Drag boxes to reposition panels. Drag ◢ to resize. Right-click for options. Grouped panels have a highlighted border and member badge. Changes apply live.")
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

			draw.SimpleText("◢", "DermaDefault", bx + bw - 3, by + bh - 2,
				color_white, TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM)

			local maxChars = math.max(3, math.floor(bw / 6))
			local cx = bx + bw / 2
			local function fit(s)
				if #s > maxChars then return s:sub(1, maxChars - 2) .. ".." end
				return s
			end

			if box.isGroup and box.memberNames and #box.memberNames > 0 then
				local lineH = 11
				local names = box.memberNames
				local extra = (box.memberCount and box.memberCount > #names) and 1 or 0
				local blockH = 14 + (#names + extra) * lineH
				local topY = by + bh / 2 - blockH / 2

				draw.SimpleText(fit(box.label), "DermaDefaultBold", cx, topY,
					color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)

				for mi, mname in ipairs(names) do
					draw.SimpleText(fit(mname), "DermaDefault", cx, topY + 14 + (mi - 1) * lineH,
						C.groupBadgeText, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
				end
				if extra == 1 then
					draw.SimpleText("+" .. (box.memberCount - #names) .. " more", "DermaDefault",
						cx, topY + 14 + #names * lineH, C.textMuted, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
				end
			else
				draw.SimpleText(fit(box.label), "DermaDefault", cx, by + bh / 2,
					color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
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
	local function ApplyBoxToFrame(box)
		local pin = PinnedPanels.Pins[box.id]
		if pin and IsValid(pin.frame) then
			pin.frame:SetPos(math.floor(box.px), math.floor(box.py))
			pin.frame:SetSize(math.floor(box.pw), math.floor(box.ph))
		end
	end

	self.canvas.OnMousePressed = function(cv, mc)
		local mx, my = cv:CursorPos()
		local ox2, oy2 = self.canvasOX, self.canvasOY

		local function boxAt(px, py)
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

		if mc == MOUSE_RIGHT then
			local box = boxAt(mx, my)
			if box then
				local pin = PinnedPanels.Pins[box.id]
				if pin and IsValid(pin.frame) then
					PinnedPanels.OpenContextMenu(box.id, pin.frame)
				end
			end
			return
		end

		if mc ~= MOUSE_LEFT then return end

		local box, bx, by, bw, bh = boxAt(mx, my)
		if not box then return end

		if IsBoxLocked(box) then return end

		if mx >= bx + bw - 12 and my >= by + bh - 12 then
			self.resizing = box
			box.resizing = true
			box.ox = (bx + bw) - mx
			box.oy = (by + bh) - my
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
			if pin and IsValid(pin.frame) and isfunction(pin.frame.OnUserResized) then
				pin.frame.OnUserResized(pin.frame:GetSize())
			end
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

			local bx = ox2 + math.floor(box.px * self.scale)
			local by = oy2 + math.floor(box.py * self.scale)
			local nW = (mx - bx + box.ox) / self.scale
			local nH = (my - by + box.oy) / self.scale

			local lines = {}

			if math.abs((box.px + nW) - scrW) < SNAP_DIST then
				nW = scrW - box.px
				local lx = ox2 + math.floor(scrW * self.scale)
				lines[#lines + 1] = { lx, oy2, lx, oy2 + math.floor(scrH * self.scale) }
			end
			if math.abs((box.py + nH) - scrH) < SNAP_DIST then
				nH = scrH - box.py
				local ly = oy2 + math.floor(scrH * self.scale)
				lines[#lines + 1] = { ox2, ly, ox2 + math.floor(scrW * self.scale), ly }
			end

			for _, other in ipairs(self.boxes) do
				if other ~= box then
					if math.abs((box.px + nW) - (other.px + other.pw)) < SNAP_DIST then
						nW = other.px + other.pw - box.px
					elseif math.abs((box.px + nW) - other.px) < SNAP_DIST then
						nW = other.px - box.px
					end
					if math.abs((box.py + nH) - (other.py + other.ph)) < SNAP_DIST then
						nH = other.py + other.ph - box.py
					elseif math.abs((box.py + nH) - other.py) < SNAP_DIST then
						nH = other.py - box.py
					end
				end
			end

			box.pw = math.Clamp(nW, MIN_PANEL_W, scrW - box.px)
			box.ph = math.Clamp(nH, MIN_PANEL_H, scrH - box.py)
			self.snapLines = lines
			ApplyBoxToFrame(box)
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
		}
	end
end

function PinnedPanels.CreateLayoutEditor(parent)
	return EDITOR:Create(parent)
end
