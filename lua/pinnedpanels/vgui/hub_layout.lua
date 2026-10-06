-- The hub's Layout page (F5): a scaled screen with a box per window on screen. Drag or resize a box and
-- the real window follows live; the result is saved on release. Snapping uses the same Geom functions and
-- settings as windows (B22). Boxes are prepared on changes, so painting only draws.

local PP = PinnedPanels
local Layout, Geom, Settings, Input, Desktop, T = PP.Layout, PP.Geom, PP.Settings, PP.Input, PP.Desktop, PP.Theme

local MIN_BOX = 24
local EDGE = 6
local MIN_W, MIN_H, MIN_CROPPED = 150, 100, 60
local PADDING = 40
local TITLE_H, LINE_H, MAX_NAMES = 14, 11, 15

local COLORS = {
	Color(80, 160, 255), Color(80, 220, 120), Color(255, 170, 60), Color(220, 80, 80),
	Color(180, 80, 220), Color(80, 210, 210), Color(255, 120, 170), Color(160, 200, 80),
}
local SCREEN_BG, SCREEN_FILL, SCREEN_BORDER = Color(8, 8, 16), Color(20, 20, 34), Color(50, 80, 140)
local LABEL, SHADOW, COORDS, GUIDE = Color(60, 80, 130), Color(0, 0, 0, 100), Color(255, 255, 255, 80), Color(255, 200, 60, 180)
local CROP_LABEL = Color(255, 210, 110, 230)

-- Counts characters, not bytes, so translated titles aren't cut inside a character.
local function fit(text, chars)
	if (utf8.len(text) or #text) <= chars then return text end
	return text:sub(1, (utf8.offset(text, math.max(1, chars - 2) + 1) or #text + 1) - 1) .. ".."
end

local function snapping()
	return Settings.Get("snap") and not Input.AltHeld()
end

local CANVAS = {}

function CANVAS:Init()
	self.boxes = {}
	self.guides = {}
	self.scale, self.ox, self.oy = 0.25, 0, 0
	self.screenText = ""
	self:Prepare()
	hook.Add("PinnedPanelsChanged", self, function() if not self.drag then self:Prepare() end end)
	hook.Add("PinnedPanelsHeldChanged", self, self.Prepare)
	hook.Add("PinnedPanelsAdoptChanged", self, self.Prepare)
end

function CANVAS:PerformLayout(w, h)
	local sw, sh = ScrW(), ScrH()
	self.scale = math.min((w - PADDING) / sw, (h - PADDING) / sh)
	self.ox = math.floor((w - sw * self.scale) / 2)
	self.oy = math.floor((h - sh * self.scale) / 2)
	self.screenText = PP.L("layout.screen") .. "  " .. sw .. "×" .. sh
	self:Prepare()
end

-- Canvas pixels for a rect in screen pixels.
function CANVAS:ToCanvas(x, y, w, h)
	local s = self.scale
	return self.ox + math.floor(x * s), self.oy + math.floor(y * s), math.max(MIN_BOX, math.floor(w * s)), math.max(MIN_BOX, math.floor(h * s))
end

-- Labels and coordinates for one box at its current rect.
function CANVAS:Describe(box)
	box.cx, box.cy, box.cw, box.ch = self:ToCanvas(box.x, box.y, box.w, box.h)
	local chars = math.max(3, math.floor(box.cw / 6))
	box.label = fit(box.title, chars)
	-- Multi-tab windows list their tabs under the title, as many as fit, then "+N more" (v1).
	if box.tabNames then
		local room = math.min(math.floor((box.ch - TITLE_H - 24) / LINE_H), MAX_NAMES)
		local names = #box.tabNames
		local shown = names > room and math.max(room - 1, 0) or names
		box.lines = {}
		for i = 1, shown do box.lines[i] = fit(box.tabNames[i], chars) end
		box.more = shown < names and PP.L("layout.more", names - shown) or nil
		local rows = shown + (box.more and 1 or 0)
		box.blockY = box.cy + math.floor((box.ch - TITLE_H - rows * LINE_H) / 2)
	end
	box.coords = math.floor(box.x) .. "," .. math.floor(box.y) .. "  " .. math.floor(box.w) .. "×" .. math.floor(box.h)
end

-- Windows on screen (a control or a managed panel, not minimized), in document order; later ones are on
-- top. A managed window its addon keeps moving can't be positioned (§33.5), so it shows as locked.
function CANVAS:Prepare()
	local boxes = {}
	for i, rec in ipairs(Layout.Windows()) do
		if IsValid(Desktop.PanelOf(rec.id)) and rec.state ~= "minimized" then
			local tab = rec.tabs[rec.active]
			local fixed = rec.kind == "managed" and tab.adopt.noGeometry
			local box = {
				id = rec.id, x = rec.x, y = rec.y, w = rec.w, h = rec.h,
				title = Layout.Title(rec), color = rec.accent or COLORS[(i - 1) % #COLORS + 1],
				locked = rec.locked or fixed, cropped = tab and tab.crop ~= nil and rec.state ~= "maximized",
				badge = #rec.tabs > 1 and PP.L("layout.badge", #rec.tabs) or nil,
			}
			if #rec.tabs > 1 then
				box.tabNames = {}
				for j, t in ipairs(rec.tabs) do box.tabNames[j] = Layout.TabTitle(t) end
			end
			self:Describe(box)
			boxes[#boxes + 1] = box
		end
	end
	self.boxes = boxes
	self.croppedText, self.taskbarText, self.emptyText = PP.L("layout.cropped"), PP.L("layout.taskbar"), PP.L("layout.empty")

	local minimized = {}
	for _, rec in ipairs(Layout.Windows()) do
		if rec.state == "minimized" and IsValid(Desktop.PanelOf(rec.id)) then minimized[#minimized + 1] = Layout.Title(rec) end
	end
	self:PrepareTaskbar(minimized)
end

-- The taskbar's place on the scaled screen, with an entry per minimized window.
function CANVAS:PrepareTaskbar(titles)
	self.taskbar = nil
	if not Settings.Get("taskbar") then return end
	local sw, sh, s = ScrW(), ScrH(), self.scale
	local size, side = math.floor(Settings.Get("taskbarSize") * s), Settings.Get("taskbarSide")
	local pw, ph = math.floor(sw * s), math.floor(sh * s)
	local bar = { x = self.ox, y = self.oy, w = pw, h = ph, entries = {} }
	if side == "top" then
		bar.h = size
	elseif side == "left" then
		bar.w = size
	elseif side == "right" then
		bar.x, bar.w = self.ox + pw - size, size
	else
		bar.y, bar.h = self.oy + ph - size, size
	end
	local across = side == "bottom" or side == "top"
	local offset = 3
	for _, title in ipairs(titles) do
		local e = across
			and { x = bar.x + offset, y = bar.y + 3, w = math.min(60, math.floor((bar.w - 6) / #titles)), h = bar.h - 6 }
			or { x = bar.x + 3, y = bar.y + offset, w = bar.w - 6, h = math.min(14, math.floor((bar.h - 6) / #titles)) }
		if across and e.w > 20 then e.label = fit(title, math.max(2, math.floor(e.w / 6))) end
		bar.entries[#bar.entries + 1] = e
		offset = offset + (across and e.w or e.h) + 2
	end
	self.taskbar = bar
end

function CANVAS:BoxAt(mx, my)
	for i = #self.boxes, 1, -1 do
		local b = self.boxes[i]
		if mx >= b.cx and mx <= b.cx + b.cw and my >= b.cy and my <= b.cy + b.ch then return b end
	end
end

local function zoneAt(b, mx, my)
	local z = { w = mx <= b.cx + EDGE, e = mx >= b.cx + b.cw - EDGE, n = my <= b.cy + EDGE, s = my >= b.cy + b.ch - EDGE }
	if z.w or z.e or z.n or z.s then return z end
end

local function cursorFor(z)
	if not z then return "sizeall" end
	if (z.n and z.w) or (z.s and z.e) then return "sizenwse" end
	if (z.n and z.e) or (z.s and z.w) then return "sizenesw" end
	return (z.e or z.w) and "sizewe" or "sizens"
end

-- The other boxes' rects, for snapping.
function CANVAS:Others(box)
	local rects = {}
	for _, b in ipairs(self.boxes) do
		if b ~= box then rects[#rects + 1] = b end
	end
	return rects
end

function CANVAS:OnMousePressed(code)
	local mx, my = self:CursorPos()
	local box = self:BoxAt(mx, my)
	if not box then return end
	if code == MOUSE_RIGHT then return PP.Actions.OpenWindowMenu(box.id) end
	if code ~= MOUSE_LEFT or box.locked then return end
	self.drag = { box = box, zone = zoneAt(box, mx, my), mx = mx, my = my, x = box.x, y = box.y, w = box.w, h = box.h, others = self:Others(box) }
	self:MouseCapture(true)
end

-- A vertical and a horizontal guide at any box edge that lines up with the screen or another box.
function CANVAS:Guides(box, others)
	local guides = {}
	local ux, uy, uw, uh = Geom.Usable()
	local xs, ys = { ux, ux + uw, ux + math.floor(uw / 2) }, { uy, uy + uh, uy + math.floor(uh / 2) }
	for _, o in ipairs(others) do
		xs[#xs + 1], xs[#xs + 2] = o.x, o.x + o.w
		ys[#ys + 1], ys[#ys + 2] = o.y, o.y + o.h
	end
	local s = self.scale
	for _, v in ipairs(xs) do
		if v == box.x or v == box.x + box.w or v == box.x + math.floor(box.w / 2) then
			guides[#guides + 1] = { self.ox + math.floor(v * s), self.oy, self.ox + math.floor(v * s), self.oy + math.floor(ScrH() * s) }
		end
	end
	for _, v in ipairs(ys) do
		if v == box.y or v == box.y + box.h or v == box.y + math.floor(box.h / 2) then
			guides[#guides + 1] = { self.ox, self.oy + math.floor(v * s), self.ox + math.floor(ScrW() * s), self.oy + math.floor(v * s) }
		end
	end
	return guides
end

function CANVAS:OnCursorMoved(mx, my)
	local d = self.drag
	if not d then
		local box = self:BoxAt(mx, my)
		self:SetCursor(box and not box.locked and cursorFor(zoneAt(box, mx, my)) or "arrow")
		return
	end
	local box, z, s = d.box, d.zone, self.scale
	local dx, dy = (mx - d.mx) / s, (my - d.my) / s
	local ux, uy, uw, uh = Geom.Usable()
	local snap, dist = snapping(), Settings.Get("snapDistance")
	local x, y, w, h = d.x, d.y, d.w, d.h

	if not z then
		x, y = math.Round(d.x + dx), math.Round(d.y + dy)
		if snap then x, y = Geom.SnapMove(x, y, w, h, d.others, dist, ux, uy, uw, uh) end
		x, y = Geom.Fit(x, y, w, h, ux, uy, uw, uh)
	else
		local minW, minH = MIN_W, MIN_H
		if box.cropped then minW, minH = MIN_CROPPED, MIN_CROPPED end
		local right, bottom = d.x + d.w, d.y + d.h
		local function edge(v, lo, span, axis)
			v = math.Round(v)
			if snap then v = Geom.SnapAxis(v, 0, lo, span, d.others, axis, dist) end
			return v
		end
		if z.e then
			w = math.Clamp(edge(right + dx, ux, uw, "x") - d.x, minW, ux + uw - d.x)
		elseif z.w then
			x = math.Clamp(edge(d.x + dx, ux, uw, "x"), ux, right - minW)
			w = right - x
		end
		if z.s then
			h = math.Clamp(edge(bottom + dy, uy, uh, "y") - d.y, minH, uy + uh - d.y)
		elseif z.n then
			y = math.Clamp(edge(d.y + dy, uy, uh, "y"), uy, bottom - minH)
			h = bottom - y
		end
	end

	box.x, box.y, box.w, box.h = x, y, w, h
	self:Describe(box)
	self.guides = snap and self:Guides(box, d.others) or {}
	local win = Desktop.PanelOf(box.id)
	if IsValid(win) then
		win:SetPos(x, y)
		win:SetSize(w, h)
	end
end

function CANVAS:OnMouseReleased()
	local d = self.drag
	self.drag, self.guides = nil, {}
	self:MouseCapture(false)
	if d then
		local b = d.box
		Layout.SetGeometry(b.id, b.x, b.y, b.w, b.h)
	end
end

function CANVAS:Paint(w, h)
	draw.RoundedBox(4, 0, 0, w, h, SCREEN_BG)
	local sw, sh, s = ScrW(), ScrH(), self.scale
	local pw, ph = math.floor(sw * s), math.floor(sh * s)
	surface.SetDrawColor(SCREEN_FILL)
	surface.DrawRect(self.ox, self.oy, pw, ph)
	surface.SetDrawColor(SCREEN_BORDER)
	surface.DrawOutlinedRect(self.ox, self.oy, pw, ph, 1)
	draw.SimpleText(self.screenText, "DermaDefault", self.ox + pw / 2, self.oy + 8, LABEL, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)

	local bar = self.taskbar
	if bar then
		local bg = Settings.Get("taskbarColorBg")
		surface.SetDrawColor(bg.r, bg.g, bg.b, 200)
		surface.DrawRect(bar.x, bar.y, bar.w, bar.h)
		surface.SetDrawColor(T.taskbarBorder)
		surface.DrawOutlinedRect(bar.x, bar.y, bar.w, bar.h, 1)
		for _, e in ipairs(bar.entries) do
			surface.SetDrawColor(T.taskbarEntry)
			surface.DrawRect(e.x, e.y, e.w, e.h)
			if e.label then
				draw.SimpleText(e.label, "DermaDefault", e.x + e.w / 2, e.y + e.h / 2, Settings.Get("taskbarColorText"), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			end
		end
		if #bar.entries == 0 then
			draw.SimpleText(self.taskbarText, "DermaDefault", bar.x + bar.w / 2, bar.y + bar.h / 2, T.textMuted, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end
	end

	local active = self.drag and self.drag.box
	for _, b in ipairs(self.boxes) do
		local c = b.color
		local strong = b == active
		draw.RoundedBox(3, b.cx + 2, b.cy + 2, b.cw, b.ch, SHADOW)
		surface.SetDrawColor(c.r, c.g, c.b, strong and 230 or 180)
		surface.DrawRect(b.cx, b.cy, b.cw, b.ch)
		surface.SetDrawColor(c.r, c.g, c.b, 255)
		surface.DrawOutlinedRect(b.cx, b.cy, b.cw, b.ch, strong and 2 or 1)
		local mid = b.cx + b.cw / 2
		if b.lines then
			draw.SimpleText(b.label, "DermaDefaultBold", mid, b.blockY, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
			local y = b.blockY + TITLE_H
			for _, name in ipairs(b.lines) do
				draw.SimpleText(name, "DermaDefault", mid, y, T.groupAccent, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
				y = y + LINE_H
			end
			if b.more then draw.SimpleText(b.more, "DermaDefault", mid, y, T.textMuted, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP) end
		else
			draw.SimpleText(b.label, "DermaDefault", mid, b.cy + b.ch / 2, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end
		draw.SimpleText(b.coords, "DermaDefault", b.cx + b.cw / 2, b.cy + b.ch - 10, COORDS, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)
		if b.badge then draw.SimpleText(b.badge, "DermaDefault", b.cx + 4, b.cy + 3, T.groupAccent, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP) end
		if b.cropped then draw.SimpleText(self.croppedText, "DermaDefaultBold", b.cx + b.cw - 4, b.cy + 2, CROP_LABEL, TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP) end
		if b.locked then
			surface.SetDrawColor(T.warning)
			surface.DrawRect(b.cx + b.cw - 10, b.cy + b.ch - 10, 6, 6)
		end
	end

	surface.SetDrawColor(GUIDE)
	for _, g in ipairs(self.guides) do surface.DrawLine(g[1], g[2], g[3], g[4]) end

	if #self.boxes == 0 then
		draw.SimpleText(self.emptyText, "DermaDefault", w / 2, h / 2, T.textMuted, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end
end

vgui.Register("PinnedPanelsLayoutCanvas", CANVAS, "Panel")

local PAGE = {}

function PAGE:Init()
	local info = self:Add("DLabel")
	info:Dock(TOP)
	info:DockMargin(6, 6, 6, 4)
	info:SetWrap(true)
	info:SetAutoStretchVertical(true)
	info:SetTextColor(T.textLabel)
	info:SetText(PP.L("layout.info"))

	local canvas = self:Add("PinnedPanelsLayoutCanvas")
	canvas:Dock(FILL)
	canvas:DockMargin(4, 0, 4, 4)
end

function PAGE:Paint(w, h)
	draw.RoundedBox(0, 0, 0, w, h, T.bg)
end

vgui.Register("PinnedPanelsLayout", PAGE, "DPanel")
