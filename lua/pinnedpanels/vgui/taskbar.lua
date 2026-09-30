-- PinnedPanelsTaskbar (§20.2, F13): minimized windows as entries along one screen edge. Shown while
-- windows are interactive, fades with RealFrameTime (G5) and can slide away until the cursor comes near.
-- Entries, titles and icons are worked out on changes, never while painting (B23).

local PP = PinnedPanels
local Layout, Settings, Input, Theme = PP.Layout, PP.Settings, PP.Input, PP.Theme

local PAD, GAP, ICON, START = 4, 4, 16, 8
local MIN_ENTRY, MAX_ENTRY = 40, 170
local PEEK, REVEAL_MARGIN = 4, 6
local FADE_SPEED, SLIDE_SPEED = 6, 8

local ICONS = {
	tool = Material("icon16/wrench.png"),
	creation = Material("icon16/application_view_list.png"),
	group = Material("icon16/folder.png"),
}

local function kindOf(rec)
	if #rec.tabs > 1 then return "group" end
	return rec.tabs[1] and rec.tabs[1].src:match("^(%a+):") or "tool"
end

local function horizontal()
	local side = Settings.Get("taskbarSide")
	return side == "bottom" or side == "top"
end

local BAR = {}

function BAR:Init()
	self.entries = {}
	self.fade = 0
	self.slide = 0
	self:SetAlpha(0)
end

-- Minimized windows that have a window control (not held, not only unavailable tabs).
function BAR:Rebuild()
	local entries = {}
	for _, rec in ipairs(Layout.Windows()) do
		if rec.state == "minimized" and IsValid(PP.Desktop.panels[rec.id]) then
			entries[#entries + 1] = { id = rec.id, title = Layout.Title(rec), icon = ICONS[kindOf(rec)] or ICONS.tool }
		end
	end
	table.sort(entries, function(a, b) return a.title:lower() < b.title:lower() end)
	self.entries = entries
	self:LayoutEntries()
	self:Place()
	self:Wake()
end

-- Entry rectangles and truncated labels, measured once per change.
function BAR:LayoutEntries()
	local size = Settings.Get("taskbarSize")
	local labels = Settings.Get("taskbarLabels") and horizontal()
	surface.SetFont(Theme.FONT_TASKBAR)
	local offset = START
	for _, e in ipairs(self.entries) do
		if horizontal() then
			local w = MIN_ENTRY
			if labels then
				w = math.Clamp(ICON + 8 + surface.GetTextSize(e.title) + PAD * 2, MIN_ENTRY, MAX_ENTRY)
				local room = w - ICON - PAD * 2 - 8
				local label = e.title
				if surface.GetTextSize(label) > room then
					while #label > 1 and surface.GetTextSize(label .. "..") > room do label = label:sub(1, -2) end
					label = label .. ".."
				end
				e.label = label
			end
			e.x, e.y, e.w, e.h = offset, PAD, w, size - PAD * 2
			offset = offset + w + GAP
		else
			e.x, e.y, e.w, e.h = PAD, offset, size - PAD * 2, size - PAD * 2
			offset = offset + e.h + GAP
		end
	end
end

-- Position along the chosen edge, pushed off-screen by the slide amount (auto-hide).
function BAR:Place()
	local size, side = Settings.Get("taskbarSize"), Settings.Get("taskbarSide")
	local sw, sh = ScrW(), ScrH()
	local hide = math.floor((size - PEEK) * self.slide)
	if side == "top" then
		self:SetSize(sw, size)
		self:SetPos(0, -hide)
	elseif side == "left" then
		self:SetSize(size, sh)
		self:SetPos(-hide, 0)
	elseif side == "right" then
		self:SetSize(size, sh)
		self:SetPos(sw - size + hide, 0)
	else
		self:SetSize(sw, size)
		self:SetPos(0, sh - size + hide)
	end
end

function BAR:OnScreenSizeChanged()
	self:Place()
end

-- Think only runs while visible (G4); this makes the bar visible when it has something to fade to.
function BAR:Wake()
	if #self.entries > 0 and Input.Interactive() then self:SetVisible(true) end
end

local function cursorNearEdge()
	local size, side = Settings.Get("taskbarSize"), Settings.Get("taskbarSide")
	local mx, my = input.GetCursorPos()
	if side == "top" then return my <= size + REVEAL_MARGIN end
	if side == "left" then return mx <= size + REVEAL_MARGIN end
	if side == "right" then return mx >= ScrW() - size - REVEAL_MARGIN end
	return my >= ScrH() - size - REVEAL_MARGIN
end

function BAR:Think()
	local dt = RealFrameTime()
	local interactive = Input.Interactive()
	local target = (#self.entries > 0 and interactive) and 1 or 0
	self.fade = math.Approach(self.fade, target, FADE_SPEED * dt)
	self:SetAlpha(math.Round(self.fade * 255))

	local collapse = Settings.Get("taskbarAutoHide") and not (interactive and cursorNearEdge())
	local slide = math.Approach(self.slide, collapse and 1 or 0, SLIDE_SPEED * dt)
	if slide ~= self.slide then
		self.slide = slide
		self:Place()
	end

	self:SetMouseInputEnabled(interactive and self.fade > 0.05)
	if self.fade == 0 and target == 0 then
		self.hover = nil
		self:SetVisible(false)
	end
end

function BAR:EntryAt(x, y)
	for i, e in ipairs(self.entries) do
		if x >= e.x and x < e.x + e.w and y >= e.y and y < e.y + e.h then return i end
	end
end

function BAR:OnCursorMoved(x, y)
	self.hover = self:EntryAt(x, y)
end

function BAR:OnCursorExited()
	self.hover = nil
end

function BAR:OnMousePressed(code)
	local e = self.entries[self:EntryAt(self:CursorPos()) or 0]
	if not e then return end
	if code == MOUSE_LEFT then
		PP.Desktop.RestoreAndFront(e.id)
	elseif code == MOUSE_RIGHT then
		PP.Actions.OpenTaskbarMenu(e.id)
	end
end

function BAR:Paint(w, h)
	local side = Settings.Get("taskbarSide")
	draw.RoundedBox(0, 0, 0, w, h, Settings.Get("taskbarColorBg"))
	surface.SetDrawColor(Theme.taskbarBorder)
	if side == "bottom" then
		surface.DrawRect(0, 0, w, 1)
	elseif side == "top" then
		surface.DrawRect(0, h - 1, w, 1)
	elseif side == "left" then
		surface.DrawRect(w - 1, 0, 1, h)
	else
		surface.DrawRect(0, 0, 1, h)
	end

	local accent, text = Settings.Get("taskbarColorAccent"), Settings.Get("taskbarColorText")
	for i, e in ipairs(self.entries) do
		local hovered = self.hover == i
		draw.RoundedBox(4, e.x, e.y, e.w, e.h, hovered and Theme.taskbarEntryHover or Theme.taskbarEntry)
		if hovered then
			surface.SetDrawColor(accent)
			if side == "bottom" then
				surface.DrawRect(e.x, e.y + e.h - 2, e.w, 2)
			elseif side == "top" then
				surface.DrawRect(e.x, e.y, e.w, 2)
			elseif side == "left" then
				surface.DrawRect(e.x, e.y, 2, e.h)
			else
				surface.DrawRect(e.x + e.w - 2, e.y, 2, e.h)
			end
		end
		local iconX = e.label and e.x + PAD + 2 or e.x + math.floor((e.w - ICON) / 2)
		surface.SetMaterial(e.icon)
		surface.SetDrawColor(255, 255, 255, 255)
		surface.DrawTexturedRect(iconX, e.y + math.floor((e.h - ICON) / 2), ICON, ICON)
		if e.label then
			draw.SimpleText(e.label, Theme.FONT_TASKBAR, iconX + ICON + 6, e.y + e.h / 2,
				hovered and Theme.textBright or text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		end
	end
end

vgui.Register("PinnedPanelsTaskbar", BAR, "EditablePanel")
