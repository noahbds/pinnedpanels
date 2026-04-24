-- ============================================================
--  PinnedPanels / layout_editor.lua
--  Miniature screen preview with draggable panel boxes.
-- ============================================================

local SCALE   = 0.25
local MIN_BOX = 24

local COLORS = {
	Color(80,  160, 255),
	Color(80,  220, 120),
	Color(255, 170,  60),
	Color(220,  80,  80),
	Color(180,  80, 220),
	Color(80,  210, 210),
	Color(255, 120, 170),
	Color(160, 200,  80),
}
local function GetColor(i) return COLORS[((i-1) % #COLORS) + 1] end

local EDITOR = {}
EDITOR.__index = EDITOR

function EDITOR:Create(parent)
	local self = setmetatable({}, EDITOR)
	self.boxes    = {}
	self.dragging = nil
	self.canvasOX = 0
	self.canvasOY = 0

	self.root = vgui.Create("DPanel", parent)
	self.root:Dock(FILL)
	self.root.Paint = function() end

	local info = vgui.Create("DLabel", self.root)
	info:SetText("Drag the coloured boxes to reposition pinned panels on your screen in real time.")
	info:SetWrap(true)
	info:SetAutoStretchVertical(true)
	info:Dock(TOP)
	info:DockMargin(6, 4, 6, 2)
	info:SetTextColor(Color(160, 180, 220))

	local refreshBtn = vgui.Create("DButton", self.root)
	refreshBtn:SetText("Refresh")
	refreshBtn:SetIcon("icon16/arrow_refresh.png")
	refreshBtn:SetTall(22)
	refreshBtn:Dock(TOP)
	refreshBtn:DockMargin(4, 2, 4, 4)
	refreshBtn.DoClick = function() self:Rebuild() end

	self.canvas = vgui.Create("DPanel", self.root)
	self.canvas:Dock(FILL)
	self.canvas:DockMargin(4, 0, 4, 4)
	self.canvas:SetMouseInputEnabled(true)

	local scrW, scrH = ScrW(), ScrH()
	local prevW = math.floor(scrW * SCALE)
	local prevH = math.floor(scrH * SCALE)

	self.canvas.Paint = function(cv, w, h)
		-- Outer bg
		draw.RoundedBox(4, 0, 0, w, h, Color(8, 8, 16, 255))

		local ox = math.floor((w - prevW) / 2)
		local oy = math.floor((h - prevH) / 2)
		self.canvasOX = ox
		self.canvasOY = oy

		-- Screen bg
		surface.SetDrawColor(20, 20, 34)
		surface.DrawRect(ox, oy, prevW, prevH)

		-- Grid
		surface.SetDrawColor(30, 30, 50)
		local step = math.floor(100 * SCALE)
		for gx = ox, ox + prevW, step do surface.DrawLine(gx, oy, gx, oy + prevH) end
		for gy = oy, oy + prevH, step do surface.DrawLine(ox, gy, ox + prevW, gy) end

		-- Border
		surface.SetDrawColor(50, 80, 140)
		surface.DrawOutlinedRect(ox, oy, prevW, prevH, 1)

		draw.SimpleText("SCREEN  " .. scrW .. "x" .. scrH, "DermaDefault",
			ox + prevW/2, oy + 8, Color(60, 80, 130), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)

		-- Boxes
		for _, box in ipairs(self.boxes) do
			local bx = ox + math.floor(box.px * SCALE)
			local by = oy + math.floor(box.py * SCALE)
			local bw = math.max(MIN_BOX, math.floor(box.pw * SCALE))
			local bh = math.max(MIN_BOX, math.floor(box.ph * SCALE))
			local col = box.color

			draw.RoundedBox(3, bx+2, by+2, bw, bh, Color(0,0,0,100))
			draw.RoundedBox(3, bx, by, bw, bh, Color(col.r, col.g, col.b, box.dragging and 230 or 180))
			surface.SetDrawColor(col.r, col.g, col.b)
			surface.DrawOutlinedRect(bx, by, bw, bh, box.dragging and 2 or 1)

			local label = box.label
			if #label > math.floor(bw / 6) then label = label:sub(1, math.floor(bw/6) - 1) .. ".." end
			draw.SimpleText(label, "DermaDefault", bx + bw/2, by + bh/2,
				color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end
	end

	self.canvas.OnMousePressed = function(cv, mc)
		if mc ~= MOUSE_LEFT then return end
		local mx, my = cv:CursorPos()
		local ox, oy = self.canvasOX, self.canvasOY
		for i = #self.boxes, 1, -1 do
			local box = self.boxes[i]
			local bx = ox + math.floor(box.px * SCALE)
			local by = oy + math.floor(box.py * SCALE)
			local bw = math.max(MIN_BOX, math.floor(box.pw * SCALE))
			local bh = math.max(MIN_BOX, math.floor(box.ph * SCALE))
			if mx >= bx and mx <= bx+bw and my >= by and my <= by+bh then
				self.dragging = box
				box.dragging  = true
				box.ox = mx - bx
				box.oy = my - by
				break
			end
		end
	end

	self.canvas.OnMouseReleased = function()
		if self.dragging then
			self.dragging.dragging = false
			self.dragging = nil
			PinnedPanels.Save()
		end
	end

	self.canvas.OnCursorMoved = function(cv, mx, my)
		if not self.dragging then return end
		local ox, oy   = self.canvasOX, self.canvasOY
		local bw = math.max(MIN_BOX, math.floor(self.dragging.pw * SCALE))
		local bh = math.max(MIN_BOX, math.floor(self.dragging.ph * SCALE))
		local npx = math.Clamp(mx - ox - self.dragging.ox, 0, math.floor(ScrW()*SCALE) - bw)
		local npy = math.Clamp(my - oy - self.dragging.oy, 0, math.floor(ScrH()*SCALE) - bh)
		self.dragging.px = npx / SCALE
		self.dragging.py = npy / SCALE
		local pin = PinnedPanels.Pins[self.dragging.id]
		if pin and IsValid(pin.frame) then
			pin.frame:SetPos(math.floor(self.dragging.px), math.floor(self.dragging.py))
		end
	end

	-- Think panel to sync positions from real frames
	local thinkPanel = vgui.Create("DPanel", parent)
	thinkPanel:SetSize(0, 0)
	thinkPanel.Think = function()
		for _, box in ipairs(self.boxes) do
			if not box.dragging then
				local pin = PinnedPanels.Pins[box.id]
				if pin and IsValid(pin.frame) then
					local x, y = pin.frame:GetPos()
					local w, h = pin.frame:GetSize()
					box.px, box.py = x, y
					box.pw, box.ph = w, h
				end
			end
		end
	end

	self:Rebuild()
	return self
end

function EDITOR:Rebuild()
	self.boxes = {}
	local i = 0
	for id, pin in pairs(PinnedPanels.Pins) do
		if IsValid(pin.frame) then
			i = i + 1
			local x, y = pin.frame:GetPos()
			local w, h = pin.frame:GetSize()
			table.insert(self.boxes, {
				id=id, label=pin.title, color=GetColor(i),
				px=x, py=y, pw=w, ph=h, dragging=false, ox=0, oy=0,
			})
		end
	end
end

function PinnedPanels.CreateLayoutEditor(parent)
	return EDITOR:Create(parent)
end
