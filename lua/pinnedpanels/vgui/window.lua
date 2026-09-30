-- PinnedPanelsWindow (§15.1): a popup showing one window record. It draws its header and buttons and
-- hit-tests drag, 8-way resize and the buttons itself, with no overlay panels (L24). It only reports
-- gestures to Layout; the desktop applies records back to it.

local PP = PinnedPanels
local Layout, Geom, Input, Settings, Sources, Theme = PP.Layout, PP.Geom, PP.Input, PP.Settings, PP.Sources, PP.Theme

local HEADER = 24
local EDGE = 5
local CORNER = 16
local BTN_W, BTN_H, BTN_Y = 26, 18, 3
local MIN_W, MIN_H = 150, 100

-- Slot 1 is the rightmost button.
local BUTTONS = { "close", "max", "min" }
local BUTTON_SLOT = { close = 1, max = 2, min = 3 }

local ZONES = {
	n = { n = true }, s = { s = true }, e = { e = true }, w = { w = true },
	ne = { n = true, e = true }, nw = { n = true, w = true }, se = { s = true, e = true }, sw = { s = true, w = true },
}
local CURSORS = {
	n = "sizens", s = "sizens", e = "sizewe", w = "sizewe",
	ne = "sizenesw", sw = "sizenesw", nw = "sizenwse", se = "sizenwse", header = "sizeall",
}

local headerTint = Color(0, 0, 0)

local PANEL = {}

function PANEL:Init()
	self:DockPadding(EDGE, HEADER + 4, EDGE, EDGE)
	self.hosts = {}
	self.titleText = ""
	self.ppTakesKeyboard = true
end

function PANEL:SetWindowId(id)
	self.id = id
	self:Refresh()
end

-- The tab to show: the active one, or the first available one while the active one is dormant (E1).
local function shownTab(rec)
	local tab = rec.tabs[rec.active]
	if tab and Sources.Get(tab.src) then return tab end
	for _, t in ipairs(rec.tabs) do
		if Sources.Get(t.src) then return t end
	end
end

-- Re-reads the record: geometry (unless a gesture is in progress), title and the shown tab.
function PANEL:Refresh()
	local rec = Layout.Get(self.id)
	if not rec then return end
	self.rec = rec
	if not (self.drag or self.resize) then
		self:SetPos(rec.x, rec.y)
		self:SetSize(rec.w, rec.h)
	end

	local tab = shownTab(rec)
	local title = rec.title or (tab and Layout.TabTitle(tab)) or ""
	if rec.clickThrough then title = title .. "  " .. PP.L("ind.clickthrough") end
	self.titleText = title

	local keep = {}
	for _, t in ipairs(rec.tabs) do
		if Sources.Get(t.src) then keep[t.src] = true end
	end
	for src, host in pairs(self.hosts) do
		if not keep[src] then
			host:Remove()
			self.hosts[src] = nil
		end
	end
	if tab and not self.hosts[tab.src] then
		local host = self:Add("PinnedPanelsTabHost")
		host:Dock(FILL)
		host:SetSource(tab.src)
		self.hosts[tab.src] = host
	end
	for src, host in pairs(self.hosts) do
		host:SetVisible(tab ~= nil and src == tab.src)
	end
end

-- ── Hit-testing ─────────────────────────────────────────────

-- Returns "close"/"max"/"min", a resize zone ("n", "se", …), "header" or nil (the body).
function PANEL:Zone(x, y)
	local w, h = self:GetSize()
	if x < 0 or y < 0 or x >= w or y >= h then return nil end
	if y >= BTN_Y and y < BTN_Y + BTN_H then
		local slot = math.floor((w - 2 - x) / BTN_W) + 1
		if x < w - 2 and BUTTONS[slot] then return BUTTONS[slot] end
	end
	local n, s, west, e = y < EDGE, y >= h - EDGE, x < EDGE, x >= w - EDGE
	if n or s or west or e then
		if n or s then
			west, e = west or x < CORNER, e or x >= w - CORNER
		else
			n, s = y < CORNER, y >= h - CORNER
		end
		return (n and "n" or s and "s" or "") .. (west and "w" or e and "e" or "")
	end
	if y < HEADER then return "header" end
end

-- Click-through windows let clicks through everywhere but the header, unless ALT is held (F11, G25).
function PANEL:TestHover(x, y)
	local rec = self.rec
	if rec and rec.clickThrough and not Input.AltHeld() then
		local _, ly = self:ScreenToLocal(x, y)
		return ly >= 0 and ly < HEADER
	end
end

-- ── Gestures ────────────────────────────────────────────────

local function snapping()
	return Settings.Get("snap") and not Input.AltHeld()
end

function PANEL:OnCursorMoved(x, y)
	if self.drag then return self:DragTo() end
	if self.resize then return self:ResizeTo() end
	local zone = self:Zone(x, y)
	if zone == self.hover then return end
	self.hover = zone
	local locked = self.rec and self.rec.locked
	self:SetCursor(not locked and CURSORS[zone] or "arrow")
end

function PANEL:OnCursorExited()
	if not (self.drag or self.resize) then self.hover = nil end
end

function PANEL:OnMousePressed(code)
	self:MoveToFront()
	if code ~= MOUSE_LEFT then return end
	local rec = self.rec
	local zone = self:Zone(self:CursorPos())
	if BUTTON_SLOT[zone] then
		self.pressed = zone
		self:MouseCapture(true)
		return
	end
	if not zone or rec.locked then return end

	local mx, my = input.GetCursorPos()
	local x, y = self:GetPos()
	local w, h = self:GetSize()
	if zone == "header" then
		-- Dragging a maximized window restores it under the cursor, keeping the grab point in proportion.
		if rec.state == "maximized" then
			local fx = (mx - x) / w
			Layout.ToggleMaximize(self.id)
			w, h = rec.w, rec.h
			x = math.Round(mx - fx * w)
			self:SetSize(w, h)
			self:SetPos(x, y)
		end
		self.drag = { dx = mx - x, dy = my - y }
	else
		self.resize = { zone = ZONES[zone], mx = mx, my = my, x = x, y = y, w = w, h = h }
	end
	self.others = PP.Desktop.SnapRects(self.id)
	self:MouseCapture(true)
end

function PANEL:DragTo()
	local mx, my = input.GetCursorPos()
	local w, h = self:GetSize()
	local ux, uy, uw, uh = Geom.Usable()
	local x, y = mx - self.drag.dx, my - self.drag.dy
	if snapping() then x, y = Geom.SnapMove(x, y, w, h, self.others, Settings.Get("snapDistance"), ux, uy, uw, uh) end
	x, y = Geom.Fit(x, y, w, h, ux, uy, uw, uh)
	self:SetPos(x, y)
end

-- Moves only the dragged edges; each snaps to lines on its own axis (a size-0 rect).
function PANEL:ResizeTo()
	local r, z = self.resize, self.resize.zone
	local mx, my = input.GetCursorPos()
	local ux, uy, uw, uh = Geom.Usable()
	local snap, dist = snapping(), Settings.Get("snapDistance")
	local x, y, w, h = r.x, r.y, r.w, r.h
	local right, bottom = r.x + r.w, r.y + r.h

	if z.e then
		local edge = math.min(right + mx - r.mx, ux + uw)
		if snap then edge = Geom.SnapAxis(edge, 0, ux, uw, self.others, "x", dist) end
		w = math.max(MIN_W, edge - x)
	elseif z.w then
		local edge = math.max(r.x + mx - r.mx, ux)
		if snap then edge = Geom.SnapAxis(edge, 0, ux, uw, self.others, "x", dist) end
		w = math.max(MIN_W, right - edge)
		x = right - w
	end
	if z.s then
		local edge = math.min(bottom + my - r.my, uy + uh)
		if snap then edge = Geom.SnapAxis(edge, 0, uy, uh, self.others, "y", dist) end
		h = math.max(MIN_H, edge - y)
	elseif z.n then
		local edge = math.max(r.y + my - r.my, uy)
		if snap then edge = Geom.SnapAxis(edge, 0, uy, uh, self.others, "y", dist) end
		h = math.max(MIN_H, bottom - edge)
		y = bottom - h
	end
	self:SetPos(x, y)
	self:SetSize(w, h)
end

function PANEL:OnMouseReleased(code)
	if code ~= MOUSE_LEFT then return end
	self:MouseCapture(false)
	if self.pressed then
		local button = self.pressed
		self.pressed = nil
		if self:Zone(self:CursorPos()) ~= button then return end
		if button == "close" then
			Layout.Unpin(self.id)
		elseif button == "max" then
			Layout.ToggleMaximize(self.id)
		else
			Layout.Minimize(self.id)
		end
		return
	end
	if self.drag or self.resize then
		self.drag, self.resize, self.others = nil, nil, nil
		local x, y = self:GetPos()
		local w, h = self:GetSize()
		Layout.SetGeometry(self.id, x, y, w, h)
	end
end

-- ── Painting ────────────────────────────────────────────────

local function paintButton(self, name, w, color)
	local bx = w - 2 - BTN_W * BUTTON_SLOT[name]
	local hovered = self.hover == name
	if hovered then
		draw.RoundedBox(3, bx + 1, BTN_Y + 1, BTN_W - 2, BTN_H - 2, name == "close" and Theme.chromeClose or Theme.chromeHover)
		if name == "close" then color = color_white end
	end
	surface.SetDrawColor(color.r, color.g, color.b, 235)
	local cx, cy = bx + math.floor(BTN_W / 2), BTN_Y + math.floor(BTN_H / 2)
	if name == "min" then
		surface.DrawRect(cx - 5, cy + 4, 11, 2)
	elseif name == "max" then
		if self.rec.state == "maximized" then
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

function PANEL:Paint(w, h)
	local rec = self.rec
	if not rec then return end
	local colors = rec.colors
	local bg = colors.bg or Settings.Get("colorBg")
	local header = colors.header or Settings.Get("colorHeader")
	local text = colors.text or Settings.Get("colorText")
	local interactive = Input.Interactive()
	if interactive then
		headerTint.r, headerTint.g, headerTint.b, headerTint.a = math.min(header.r + 12, 255), math.min(header.g + 20, 255), math.min(header.b + 35, 255), header.a
		header = headerTint
	end

	draw.RoundedBox(6, 0, 0, w, h, bg)
	draw.RoundedBoxEx(6, 0, 0, w, HEADER, header, true, true, false, false)
	draw.SimpleText(self.titleText, "DermaDefaultBold", 10, HEADER / 2, text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

	if rec.locked then
		surface.SetDrawColor(Theme.warning)
		surface.DrawRect(w - BTN_W * #BUTTONS - 14, 9, 6, 6)
	end
	if interactive then
		surface.SetDrawColor(Theme.chromeInteractive)
		surface.DrawRect(w - 6, h - 6, 4, 1)
		surface.DrawRect(w - 6, h - 4, 1, 2)
	end
	for _, name in ipairs(BUTTONS) do paintButton(self, name, w, text) end
end

vgui.Register("PinnedPanelsWindow", PANEL, "EditablePanel")
