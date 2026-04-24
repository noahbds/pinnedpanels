local MIN_BOX = 24

local COLORS = {
	Color(80, 160, 255), Color(80, 220, 120),
	Color(255, 170, 60), Color(220, 80, 80),
	Color(180, 80, 220), Color(80, 210, 210),
	Color(255, 120, 170), Color(160, 200, 80),
}
local function GetColor(i) return COLORS[((i - 1) % #COLORS) + 1] end

local EDITOR = {}
EDITOR.__index = EDITOR

function EDITOR:Create(parent)
	local self    = setmetatable({}, EDITOR)
	self.boxes    = {}
	self.dragging = nil
	self.resizing = nil
	self.canvasOX = 0
	self.canvasOY = 0
	self.scale    = 0.25

	self.root     = vgui.Create("DPanel", parent)
	self.root:Dock(FILL)
	self.root.Paint = function() end

	local info = vgui.Create("DLabel", self.root)
	info:SetText("Drag boxes to reposition, or drag their bottom-right corners to resize panels in real time.")
	info:SetWrap(true)
	info:Dock(TOP)
	info:DockMargin(6, 6, 6, 6)
	info:SetTextColor(Color(255, 255, 255))

	self.canvas = vgui.Create("DPanel", self.root)
	self.canvas:Dock(FILL)
	self.canvas:DockMargin(4, 0, 4, 4)
	self.canvas:SetMouseInputEnabled(true)
	self.canvas:SetCursor("arrow")

	local scrW, scrH = ScrW(), ScrH()

	self.canvas.Paint = function(cv, w, h)
		draw.RoundedBox(4, 0, 0, w, h, Color(8, 8, 16, 255))

		local padding = 40
		local availW, availH = w - padding, h - padding
		local scaleX = availW / scrW
		local scaleY = availH / scrH
		self.scale = math.min(scaleX, scaleY)

		local prevW = math.floor(scrW * self.scale)
		local prevH = math.floor(scrH * self.scale)

		local ox = math.floor((w - prevW) / 2)
		local oy = math.floor((h - prevH) / 2)
		self.canvasOX, self.canvasOY = ox, oy

		surface.SetDrawColor(20, 20, 34)
		surface.DrawRect(ox, oy, prevW, prevH)
		surface.SetDrawColor(30, 30, 50)
		local step = math.floor(100 * self.scale)
		for gx = ox, ox + prevW, step do surface.DrawLine(gx, oy, gx, oy + prevH) end
		for gy = oy, oy + prevH, step do surface.DrawLine(ox, gy, ox + prevW, gy) end
		surface.SetDrawColor(50, 80, 140)
		surface.DrawOutlinedRect(ox, oy, prevW, prevH, 1)

		draw.SimpleText("SCREEN  " .. scrW .. "x" .. scrH, "DermaDefault",
			ox + prevW / 2, oy + 8, Color(60, 80, 130), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)

		for _, box in ipairs(self.boxes) do
			local bx = ox + math.floor(box.px * self.scale)
			local by = oy + math.floor(box.py * self.scale)
			local bw = math.max(MIN_BOX, math.floor(box.pw * self.scale))
			local bh = math.max(MIN_BOX, math.floor(box.ph * self.scale))
			local col = box.color
			local isInteract = box.dragging or box.resizing

			draw.RoundedBox(3, bx + 2, by + 2, bw, bh, Color(0, 0, 0, 100))
			draw.RoundedBox(3, bx, by, bw, bh, Color(col.r, col.g, col.b, isInteract and 230 or 180))
			surface.SetDrawColor(col.r, col.g, col.b)
			surface.DrawOutlinedRect(bx, by, bw, bh, isInteract and 2 or 1)

			draw.SimpleText("◢", "DermaDefault", bx + bw - 3, by + bh - 2, Color(255, 255, 255, 150), TEXT_ALIGN_RIGHT,
				TEXT_ALIGN_BOTTOM)

			local label = box.label
			if #label > math.floor(bw / 6) then label = label:sub(1, math.floor(bw / 6) - 1) .. ".." end
			draw.SimpleText(label, "DermaDefault", bx + bw / 2, by + bh / 2, color_white, TEXT_ALIGN_CENTER,
				TEXT_ALIGN_CENTER)
		end
	end

	self.canvas.OnMousePressed = function(cv, mc)
		if mc ~= MOUSE_LEFT then return end
		local mx, my = cv:CursorPos()
		local ox, oy = self.canvasOX, self.canvasOY
		for i = #self.boxes, 1, -1 do
			local box = self.boxes[i]
			local bx = ox + math.floor(box.px * self.scale)
			local by = oy + math.floor(box.py * self.scale)
			local bw = math.max(MIN_BOX, math.floor(box.pw * self.scale))
			local bh = math.max(MIN_BOX, math.floor(box.ph * self.scale))

			if mx >= bx + bw - 12 and mx <= bx + bw and my >= by + bh - 12 and my <= by + bh then
				self.resizing = box
				box.resizing = true
				box.ox = (bx + bw) - mx
				box.oy = (by + bh) - my
				break
			elseif mx >= bx and mx <= bx + bw and my >= by and my <= by + bh then
				self.dragging = box
				box.dragging  = true
				box.ox        = mx - bx
				box.oy        = my - by
				break
			end
		end
	end

	self.canvas.OnMouseReleased = function()
		if self.dragging then
			self.dragging.dragging = false
			self.dragging = nil
		end
		if self.resizing then
			self.resizing.resizing = false
			self.resizing = nil
		end
		PinnedPanels.Save()
	end

	self.canvas.OnCursorMoved = function(cv, mx, my)
		local ox, oy = self.canvasOX, self.canvasOY

		if self.resizing then
			local box = self.resizing
			local bx = ox + math.floor(box.px * self.scale)
			local by = oy + math.floor(box.py * self.scale)
			local nW = (mx - bx + box.ox) / self.scale
			local nH = (my - by + box.oy) / self.scale

			box.pw = math.max(150, nW)
			box.ph = math.max(150, nH)

			local pin = PinnedPanels.Pins[box.id]
			if pin and IsValid(pin.frame) then
				pin.frame:SetSize(math.floor(box.pw), math.floor(box.ph))
			end
		elseif self.dragging then
			local box = self.dragging
			local bw = math.max(MIN_BOX, math.floor(box.pw * self.scale))
			local bh = math.max(MIN_BOX, math.floor(box.ph * self.scale))
			local npx = math.Clamp(mx - ox - box.ox, 0, math.floor(ScrW() * self.scale) - bw)
			local npy = math.Clamp(my - oy - box.oy, 0, math.floor(ScrH() * self.scale) - bh)
			box.px, box.py = npx / self.scale, npy / self.scale

			local pin = PinnedPanels.Pins[box.id]
			if pin and IsValid(pin.frame) then
				pin.frame:SetPos(math.floor(box.px), math.floor(box.py))
			end
		end
	end

	local thinkPanel = vgui.Create("DPanel", parent)
	thinkPanel:SetSize(0, 0)
	thinkPanel.Think = function()
		local activeCount = 0
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
		for id, pin in pairs(PinnedPanels.Pins) do
			if IsValid(pin.frame) then activeCount = activeCount + 1 end
		end

		if activeCount ~= #self.boxes and not self.dragging and not self.resizing then
			self:Rebuild()
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
				id = id,
				label = pin.title,
				color = GetColor(i),
				px = x,
				py = y,
				pw = w,
				ph = h,
				dragging = false,
				resizing = false,
				ox = 0,
				oy = 0,
			})
		end
	end
end

function PinnedPanels.CreateLayoutEditor(parent)
	return EDITOR:Create(parent)
end
