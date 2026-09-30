-- PinnedPanelsCropEditor (§15.3, F16): an overlay on a window showing its tab uncropped. Draw a new
-- rectangle, move it, drag its edges or corners; Apply keeps that part, Full selects everything, Cancel
-- or right-click leaves the crop as it was. It closes if windows stop being interactive.

local PP = PinnedPanels
local Layout, Input, Theme = PP.Layout, PP.Input, PP.Theme

PP.CropEditor = PP.CropEditor or {}

local MIN_VISIBLE = 40 -- E19
local HANDLE = 12
local HANDLE_DRAW = 6

local EDITOR = {}

-- rect = the content's area in window coordinates; sel starts at rect minus the current crop.
function EDITOR:Setup(win, index, rect, crop)
	self.win, self.index, self.rect = win, index, rect
	self.sel = { x = rect.x, y = rect.y, w = rect.w, h = rect.h }
	if crop then
		self.sel = { x = rect.x + crop.l, y = rect.y + crop.t, w = rect.w - crop.l - crop.r, h = rect.h - crop.t - crop.b }
	end
	self:Clamp()

	local w, h = win:GetSize()
	self:SetPos(0, 0)
	self:SetSize(w, h)
	local bw = math.min(64, math.floor((w - 24) / 3))
	local startX = math.max(4, math.floor((w - (bw * 3 + 12)) / 2))
	local buttons = {
		{ "btn.apply", function() self:Apply() end },
		{ "crop.full", function() self.sel = { x = rect.x, y = rect.y, w = rect.w, h = rect.h } end },
		{ "btn.cancel", function() self:Cancel() end },
	}
	for i, b in ipairs(buttons) do
		local btn = self:Add("PinnedPanelsButton")
		btn:SetLabel(PP.L(b[1]))
		btn:SetSize(bw, 22)
		btn:SetPos(startX + (bw + 6) * (i - 1), h - 30)
		btn.DoClick = b[2]
	end
	hook.Add("PinnedPanelsInputChanged", self, function()
		if not Input.Interactive() then self:Cancel() end
	end)
end

function EDITOR:Clamp()
	local r, s = self.rect, self.sel
	s.w = math.Clamp(s.w, MIN_VISIBLE, r.w)
	s.h = math.Clamp(s.h, MIN_VISIBLE, r.h)
	s.x = math.Clamp(s.x, r.x, r.x + r.w - s.w)
	s.y = math.Clamp(s.y, r.y, r.y + r.h - s.h)
end

-- "move" inside the selection, { l, r, t, b } near its edges, nil elsewhere.
function EDITOR:HitTest(mx, my)
	local s = self.sel
	if mx < s.x - HANDLE or mx > s.x + s.w + HANDLE or my < s.y - HANDLE or my > s.y + s.h + HANDLE then return nil end
	local l, r = math.abs(mx - s.x) <= HANDLE, math.abs(mx - (s.x + s.w)) <= HANDLE
	local t, b = math.abs(my - s.y) <= HANDLE, math.abs(my - (s.y + s.h)) <= HANDLE
	if l and r then
		if mx - s.x <= s.x + s.w - mx then r = false else l = false end
	end
	if t and b then
		if my - s.y <= s.y + s.h - my then b = false else t = false end
	end
	if l or r or t or b then return { l = l, r = r, t = t, b = b } end
	return "move"
end

function EDITOR:InContent(mx, my)
	local r = self.rect
	return mx >= r.x and mx <= r.x + r.w and my >= r.y and my <= r.y + r.h
end

function EDITOR:OnMousePressed(code)
	if code == MOUSE_RIGHT then return self:Cancel() end
	if code ~= MOUSE_LEFT then return end
	local mx, my = self:CursorPos()
	local s = self.sel
	local hit = self:HitTest(mx, my)
	if hit == "move" then
		self.drag = { kind = "move", dx = mx - s.x, dy = my - s.y }
	elseif hit then
		self.drag = { kind = "edge", edge = hit,
			dx = hit.l and mx - s.x or hit.r and mx - (s.x + s.w) or 0,
			dy = hit.t and my - s.y or hit.b and my - (s.y + s.h) or 0 }
	elseif self:InContent(mx, my) then
		self.drag = { kind = "new", ax = mx, ay = my }
		s.x, s.y, s.w, s.h = mx, my, 1, 1
	end
	if self.drag then self:MouseCapture(true) end
end

function EDITOR:OnMouseReleased()
	if self.drag and self.drag.kind == "new" then self:Clamp() end
	self.drag = nil
	self:MouseCapture(false)
end

local EDGE_CURSOR = { lt = "sizenwse", rb = "sizenwse", rt = "sizenesw", lb = "sizenesw" }

function EDITOR:OnCursorMoved(mx, my)
	local d, s, r = self.drag, self.sel, self.rect
	if not d then
		local hit = self:HitTest(mx, my)
		if hit == "move" then
			self:SetCursor("sizeall")
		elseif hit then
			local key = (hit.l and "l" or hit.r and "r" or "") .. (hit.t and "t" or hit.b and "b" or "")
			self:SetCursor(EDGE_CURSOR[key] or ((hit.l or hit.r) and "sizewe" or "sizens"))
		else
			self:SetCursor(self:InContent(mx, my) and "crosshair" or "arrow")
		end
		return
	end
	if d.kind == "move" then
		s.x, s.y = mx - d.dx, my - d.dy
		self:Clamp()
	elseif d.kind == "new" then
		local bx, by = math.Clamp(mx, r.x, r.x + r.w), math.Clamp(my, r.y, r.y + r.h)
		s.x, s.w = math.min(d.ax, bx), math.abs(bx - d.ax)
		s.y, s.h = math.min(d.ay, by), math.abs(by - d.ay)
	else
		local ex, ey, e = mx - d.dx, my - d.dy, d.edge
		if e.l then
			local right = s.x + s.w
			s.x = math.Clamp(ex, r.x, right - MIN_VISIBLE)
			s.w = right - s.x
		elseif e.r then
			s.w = math.Clamp(ex - s.x, MIN_VISIBLE, r.x + r.w - s.x)
		end
		if e.t then
			local bottom = s.y + s.h
			s.y = math.Clamp(ey, r.y, bottom - MIN_VISIBLE)
			s.h = bottom - s.y
		elseif e.b then
			s.h = math.Clamp(ey - s.y, MIN_VISIBLE, r.y + r.h - s.y)
		end
	end
end

function EDITOR:Close()
	local win = self.win
	self:Remove()
	if IsValid(win) then
		win.editing = false
		win:Refresh()
	end
end

-- Keeps the selection: the window keeps its position and shrinks by the insets.
function EDITOR:Apply()
	local r, s, win = self.rect, self.sel, self.win
	local crop = { l = s.x - r.x, t = s.y - r.y, r = r.x + r.w - s.x - s.w, b = r.y + r.h - s.y - s.h }
	local x, y = win:GetPos()
	local w, h = win:GetSize()
	Layout.SetCrop(win.id, self.index, crop)
	Layout.SetGeometry(win.id, x, y, w - crop.l - crop.r, h - crop.t - crop.b, true)
	self:Close()
end

function EDITOR:Cancel()
	self:Close()
end

function EDITOR:Paint(w, h)
	local s = self.sel
	surface.SetDrawColor(Theme.cropShade)
	surface.DrawRect(0, 0, w, s.y)
	surface.DrawRect(0, s.y + s.h, w, h - s.y - s.h)
	surface.DrawRect(0, s.y, s.x, s.h)
	surface.DrawRect(s.x + s.w, s.y, w - s.x - s.w, s.h)

	surface.SetDrawColor(Theme.accent)
	surface.DrawOutlinedRect(s.x, s.y, s.w, s.h, 2)
	local half = HANDLE_DRAW / 2
	for _, px in ipairs({ s.x, s.x + s.w / 2, s.x + s.w }) do
		for _, py in ipairs({ s.y, s.y + s.h / 2, s.y + s.h }) do
			if px ~= s.x + s.w / 2 or py ~= s.y + s.h / 2 then surface.DrawRect(px - half, py - half, HANDLE_DRAW, HANDLE_DRAW) end
		end
	end
	draw.SimpleText(PP.L("crop.hint"), "DermaDefault", w / 2, 4, Theme.textBright, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
end

vgui.Register("PinnedPanelsCropEditor", EDITOR, "Panel")

-- Opens the editor on tab index of window id: restores and un-maximizes the window, makes windows
-- interactive (closing the spawn menu, which would cover it) and shows the tab uncropped.
function PP.CropEditor.Open(id, index)
	local win = PP.Desktop.panels[id]
	local rec = Layout.Get(id)
	if not IsValid(win) or not rec or not rec.tabs[index] then return end
	if IsValid(win.cropEditor) then win.cropEditor:Remove() end
	if rec.state == "minimized" then Layout.Restore(id) end
	if rec.state == "maximized" then Layout.ToggleMaximize(id) end
	if IsValid(g_SpawnMenu) and g_SpawnMenu:IsVisible() then g_SpawnMenu:Close() end
	Input.SetCursorMode(true)
	if index ~= rec.active then Layout.Activate(id, index) end
	win:Refresh()
	win:SetVisible(true)

	local host = win:ShownHost()
	if not host or not IsValid(host.content) then return end
	local crop = rec.tabs[index].crop

	-- Show the tab uncropped: grow the window by the insets and let the content fill the clip again.
	win.editing = true
	if crop then win:SetSize(rec.w + crop.l + crop.r, rec.h + crop.t + crop.b) end
	win:Refresh()
	win:InvalidateLayout(true)
	host:InvalidateLayout(true)
	host.clip:InvalidateLayout(true)

	local sx, sy = host.clip:LocalToScreen(0, 0)
	local x, y = win:ScreenToLocal(sx, sy)
	local cw, ch = host.clip:GetSize()
	win:MoveToFront()
	local editor = win:Add("PinnedPanelsCropEditor")
	editor:Setup(win, index, { x = x, y = y, w = cw, h = ch }, crop)
	win.cropEditor = editor
end
