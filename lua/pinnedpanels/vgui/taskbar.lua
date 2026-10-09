-- PinnedPanelsTaskbar (§20.2, F13): the pinned windows as entries along one screen edge. Every window
-- has one (or only the minimized ones, by setting): the one in front is marked, minimized and hidden
-- ones are dimmed, and a pin waiting for its addon's window says so. A click does what the entry needs:
-- bring to the front, minimize, restore, show, or open. The bar is as long as its entries, so the rest
-- of the edge stays the game's; entries that don't fit shrink, then scroll. Shown while windows are
-- interactive, fades with RealFrameTime (G5) and can slide away until the cursor comes near.
-- Entries, labels, icons and the tooltip are worked out on changes, never while painting (B23).

local PP = PinnedPanels
local Layout, Settings, Input, Theme = PP.Layout, PP.Settings, PP.Input, PP.Theme

local PAD, GAP, ICON, START, EDGE = 4, 4, 16, 6, 8
local MIN_ENTRY, MAX_ENTRY, ICON_ONLY, LABEL_ROOM, LABEL_MIN = 40, 180, 30, 24, 72
local PEEK, REVEAL_MARGIN = 4, 6
local FADE_SPEED, SLIDE_SPEED = 6, 8
local WHEEL_STEP, ARROW = 60, 12

local ICONS = {
	tool = Material("icon16/wrench.png"),
	active = Material("icon16/wand.png"),
	creation = Material("icon16/application_view_list.png"),
	postprocess = Material("icon16/color_wheel.png"),
	quick = Material("icon16/lightning.png"),
	adopt = Material("icon16/application.png"),
	desktop = Material("icon16/application_double.png"),
	group = Material("icon16/folder.png"),
	managed = Material("icon16/application_link.png"),
}
-- How strongly an entry's icon and label show, by state.
local DIM = { shown = 255, minimized = 165, hidden = 105, waiting = 105, closed = 105 }
local ALIGN = { start = 0, center = 0.5, ["end"] = 1 }

local function kindOf(rec)
	if rec.kind == "managed" then return "managed" end
	if #rec.tabs > 1 then return "group" end
	return rec.tabs[1] and rec.tabs[1].src:match("^(%a+):") or "tool"
end

local function horizontal()
	local side = Settings.Get("taskbarSide")
	return side == "bottom" or side == "top"
end

-- One character less, whole: a title cut in the middle of an accented letter draws as a box.
local function chop(s)
	s = s:sub(1, -2)
	while #s > 0 and s:byte(-1) >= 0x80 and s:byte(-1) < 0xC0 do s = s:sub(1, -2) end
	if #s > 0 and s:byte(-1) >= 0xC0 then s = s:sub(1, -2) end
	return s
end

-- Two characters for an entry without room for its label, so that sixty tool windows aren't sixty
-- wrenches: the first letters of its first two words that count ("Data - Plug/Socket" is DP,
-- "Paramètres du serveur" Ps), or its first two letters when it is one word. Characters are whole.
-- A word: letters and digits, and any byte of a character outside ASCII (an accented letter).
local WORD = "[%w" .. string.char(128) .. "-" .. string.char(255) .. "]+"
local function initials(title)
	local first, second
	for word in title:gmatch(WORD) do
		local chars = {}
		for char in word:gmatch(utf8.charpattern) do chars[#chars + 1] = char end
		if not first then
			first = chars
		elseif #chars >= 3 or not second then
			second = chars
			if #chars >= 3 then break end
		end
	end
	if not first then return "" end
	if second and #second >= 3 then return first[1] .. second[1] end
	return first[1] .. (first[2] or (second and second[1]) or "")
end

-- What a window's entry says about it, or nil when it has none: "shown", "minimized", "hidden" (held
-- back or hidden by the player), "waiting" (a pin whose addon's window isn't open) or "closed" (a
-- managed window its addon closed).
local function stateOf(rec)
	local Desktop = PP.Desktop
	if #rec.tabs == 0 then return nil end
	if Desktop.held[rec.id] then return "hidden" end
	if PP.Manage.OwnerHidden(rec.id) then return "closed" end
	if not IsValid(Desktop.PanelOf(rec.id)) then
		for _, tab in ipairs(rec.tabs) do
			if tab.adopt then return "waiting" end
		end
		return nil -- a tool that isn't installed any more: nothing to bring back
	end
	return rec.state == "minimized" and "minimized" or "shown"
end

local BAR = {}

function BAR:Init()
	self.items, self.entries = {}, {}
	self.fade, self.slide, self.scroll, self.maxScroll, self.length = 0, 0, 0, 0, 0
	self:SetAlpha(0)
end

-- items: every entry, in order. entries: the ones keyboard navigation goes through, which are those
-- that aren't on screen as windows (the same tables, so the ring is drawn where the entry is).
function BAR:Rebuild()
	local items, entries = {}, {}
	local all = Settings.Get("taskbarShow") == "all"
	for _, rec in ipairs(Layout.Windows()) do
		local state = stateOf(rec)
		local away = state == "minimized" or state == "closed"
		if state and (all or away) then
			local title = Layout.Title(rec)
			local item = { id = rec.id, title = title, state = state, icon = ICONS[kindOf(rec)] or ICONS.tool, sort = PP.Util.SortKey(title), short = initials(title) }
			items[#items + 1] = item
			if away then entries[#entries + 1] = item end
		end
	end
	local function byTitle(a, b)
		if a.sort ~= b.sort then return a.sort < b.sort end
		return a.id < b.id
	end
	table.sort(items, byTitle)
	table.sort(entries, byTitle)
	self.items, self.entries = items, entries
	self.hover, self.tip = nil, nil
	self:LayoutEntries()
	self:Place()
	self:Wake()
end

-- Entry rectangles and truncated labels, measured once per change. Along a horizontal bar an entry is
-- as wide as its label; when they don't all fit they shrink together, down to the icon alone, and
-- what still doesn't fit scrolls.
function BAR:LayoutEntries()
	local size, horiz = Settings.Get("taskbarSize"), horizontal()
	local labels = Settings.Get("taskbarLabels") and horiz
	local cell = size - PAD * 2
	local n = #self.items
	surface.SetFont(Theme.FONT_TASKBAR)

	local total = 0
	for _, e in ipairs(self.items) do
		e.textW = labels and surface.GetTextSize(e.title) or 0
		e.len = labels and math.Clamp(ICON + 6 + e.textW + PAD * 2 + 4, MIN_ENTRY, MAX_ENTRY) or (horiz and ICON_ONLY or cell)
		total = total + e.len
	end
	local gaps = GAP * math.max(n - 1, 0)
	local room = (horiz and ScrW() or ScrH()) - EDGE * 2 - START * 2
	if labels and total + gaps > room then
		-- Like tabs in a browser: no entry wider than a common limit, the widest that lets them all
		-- fit. Under LABEL_MIN a label is three letters and two dots: then none has one, and each
		-- shows its initials instead.
		local limit = MAX_ENTRY
		while limit >= LABEL_MIN do
			total = 0
			for _, e in ipairs(self.items) do total = total + math.min(e.len, limit) end
			if total + gaps <= room then break end
			limit = limit - 4
		end
		labels = limit >= LABEL_MIN
		total = 0
		for _, e in ipairs(self.items) do
			e.len = labels and math.min(e.len, limit) or ICON_ONLY
			total = total + e.len
		end
	end
	total = total + gaps
	self.maxScroll = math.max(total - room, 0)
	self.scroll = math.Clamp(self.scroll, 0, self.maxScroll)
	self.length = math.min(total, room) + START * 2

	local offset = START - self.scroll
	for _, e in ipairs(self.items) do
		if horiz then
			e.x, e.y, e.w, e.h = offset, PAD, e.len, cell
		else
			e.x, e.y, e.w, e.h = PAD, offset, cell, e.len
		end
		offset = offset + e.len + GAP
		e.label = nil
		local space = e.len - ICON - PAD * 2 - 8
		-- Room for the whole label, or for enough of it to be worth cutting.
		if labels and space >= math.min(e.textW, LABEL_ROOM) then
			local label = e.title
			if e.textW > space then
				while #label > 1 and surface.GetTextSize(label .. "..") > space do label = chop(label) end
				label = label .. ".."
			end
			e.label = label
		end
	end
end

-- Along the chosen edge, where the alignment puts it, pushed off-screen by the slide amount (auto-hide).
function BAR:Place()
	local size, side = Settings.Get("taskbarSize"), Settings.Get("taskbarSide")
	local sw, sh = ScrW(), ScrH()
	local hide = math.floor((size - PEEK) * self.slide)
	local along = ALIGN[Settings.Get("taskbarAlign")] or 0.5
	if side == "top" or side == "bottom" then
		local x = math.floor(EDGE + (sw - EDGE * 2 - self.length) * along)
		self:SetSize(self.length, size)
		self:SetPos(x, side == "top" and -hide or sh - size + hide)
	else
		local y = math.floor(EDGE + (sh - EDGE * 2 - self.length) * along)
		self:SetSize(size, self.length)
		self:SetPos(side == "left" and -hide or sw - size + hide, y)
	end
end

function BAR:OnScreenSizeChanged()
	self:LayoutEntries()
	self:Place()
end

-- Shown while windows are interactive, or while keyboard navigation is on the bar (its zone, §19.1).
local function wanted(self)
	return #self.items > 0 and (Input.Interactive() or PP.Nav.state == "taskbar")
end

-- Think only runs while visible (G4); this makes the bar visible when it has something to fade to.
function BAR:Wake()
	if wanted(self) then self:SetVisible(true) end
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
	local target = wanted(self) and 1 or 0
	self.fade = math.Approach(self.fade, target, FADE_SPEED * dt)
	self:SetAlpha(math.Round(self.fade * 255))

	local collapse = Settings.Get("taskbarAutoHide") and PP.Nav.state ~= "taskbar" and not (interactive and cursorNearEdge())
	local slide = math.Approach(self.slide, collapse and 1 or 0, SLIDE_SPEED * dt)
	if slide ~= self.slide then
		self.slide = slide
		self:Place()
	end

	self:SetMouseInputEnabled(interactive and self.fade > 0.05)
	if self.fade == 0 and target == 0 then
		self:SetHover(nil)
		self:SetVisible(false)
	end
end

function BAR:EntryAt(x, y)
	for i, e in ipairs(self.items) do
		if x >= e.x and x < e.x + e.w and y >= e.y and y < e.y + e.h then return i end
	end
end

-- What a click on an entry does, as a string key: also the tooltip's second half.
local function actionOf(e)
	if e.state == "shown" then return PP.Desktop.focused == e.id and "minimize" or "front" end
	if e.state == "hidden" then return "show" end
	if e.state == "waiting" then return "open" end
	return "restore"
end

-- The tooltip is measured when the hovered entry changes, not while painting.
function BAR:SetHover(i)
	if self.hover == i then return end
	self.hover = i
	local e = i and self.items[i]
	if not e then
		self.tip = nil
		return
	end
	local text = e.title
	if e.state ~= "shown" then text = text .. "  ·  " .. PP.L("tb.state." .. e.state) end
	text = text .. "  ·  " .. PP.L("tb.click." .. actionOf(e))
	surface.SetFont(Theme.FONT_TASKBAR)
	self.tip = text
	self.tipW, self.tipH = surface.GetTextSize(text)
end

function BAR:OnCursorMoved(x, y)
	self:SetHover(self:EntryAt(x, y))
end

function BAR:OnCursorExited()
	self:SetHover(nil)
end

-- A waiting pin's window is opened the way its pin says, if it says: this is a click (R17).
local function open(e)
	local rec = Layout.Get(e.id)
	for _, tab in ipairs(rec and rec.tabs or {}) do
		if tab.adopt and not PP.Recipes.IsLive(rec, tab) then
			if PP.Recipes.CanOpen(tab.adopt) then return PP.Recipes.Open(rec, tab) end
			return notification.AddLegacy(PP.L("tb.waiting_hint", e.title), NOTIFY_HINT, 6)
		end
	end
end

function BAR:OnMousePressed(code)
	local i = self:EntryAt(self:CursorPos())
	local e = i and self.items[i]
	if not e then return end
	local Desktop = PP.Desktop
	-- Ctrl-click picks entries, and a right-click on one of several picked is about all of them.
	if code == MOUSE_LEFT and Input.CtrlHeld() then
		PP.Batch.Toggle(e.id)
		return
	end
	if code == MOUSE_RIGHT and PP.Batch.IsSelected(e.id) and PP.Batch.Count() > 1 then
		return PP.Actions.OpenBatchMenu(PP.Batch.Ids())
	end
	if code == MOUSE_RIGHT then
		-- A window that is away has the bar's own menu; one on screen has its window menu.
		if e.state == "minimized" or e.state == "closed" then return PP.Actions.OpenTaskbarMenu(e.id) end
		return PP.Actions.OpenWindowMenu(e.id)
	end
	if code == MOUSE_MIDDLE then
		if e.state == "shown" then Layout.Minimize(e.id) elseif e.state == "minimized" then Desktop.RestoreAndFront(e.id) end
		return
	end
	if code ~= MOUSE_LEFT then return end
	local action = actionOf(e)
	if action == "minimize" then
		Layout.Minimize(e.id)
	elseif action == "front" then
		Desktop.Front(e.id)
	elseif action == "show" then
		Desktop.Show(e.id)
		Desktop.RestoreAndFront(e.id)
	elseif action == "open" then
		open(e)
	else
		Desktop.RestoreAndFront(e.id)
	end
	-- What the entry does next has changed with it.
	self.hover = nil
	self:SetHover(i)
end

-- More entries than fit: the wheel moves along them.
function BAR:OnMouseWheeled(delta)
	if self.maxScroll <= 0 then return end
	self.scroll = math.Clamp(self.scroll - delta * WHEEL_STEP, 0, self.maxScroll)
	self:LayoutEntries()
	self.hover = nil
	self:SetHover(self:EntryAt(self:CursorPos()))
	return true
end

local function mark(side, e, color, share)
	surface.SetDrawColor(color)
	if side == "bottom" or side == "top" then
		local w = math.floor(e.w * share)
		surface.DrawRect(e.x + math.floor((e.w - w) / 2), side == "bottom" and e.y + e.h - 2 or e.y, w, 2)
	else
		local h = math.floor(e.h * share)
		surface.DrawRect(side == "left" and e.x or e.x + e.w - 2, e.y + math.floor((e.h - h) / 2), 2, h)
	end
end

function BAR:Paint(w, h)
	local side = Settings.Get("taskbarSide")
	-- Rounded on the side away from the screen edge.
	draw.RoundedBoxEx(6, 0, 0, w, h, Settings.Get("taskbarColorBg"),
		side == "bottom" or side == "right", side == "bottom" or side == "left", side == "top" or side == "right", side == "top" or side == "left")

	local accent, text = Settings.Get("taskbarColorAccent"), Settings.Get("taskbarColorText")
	local focused = PP.Desktop.focused
	local selected = PP.Batch.selected
	for i, e in ipairs(self.items) do
		local hovered = self.hover == i
		local front = e.state == "shown" and focused == e.id
		draw.RoundedBox(4, e.x, e.y, e.w, e.h, (hovered or front) and Theme.taskbarEntryHover or Theme.taskbarEntry)
		-- The window in front has a full mark, the others on screen a short one, a waiting pin its own.
		if front then
			mark(side, e, accent, 1)
		elseif e.state == "shown" then
			mark(side, e, accent, 0.35)
		elseif e.state == "waiting" then
			mark(side, e, Theme.warning, 0.35)
		end
		if selected[e.id] then
			surface.SetDrawColor(accent)
			surface.DrawOutlinedRect(e.x, e.y, e.w, e.h, 1)
		end
		local dim = hovered and 255 or DIM[e.state]
		local c = hovered and Theme.textBright or text
		if e.label then
			local iconX = e.x + PAD + 2
			surface.SetMaterial(e.icon)
			surface.SetDrawColor(255, 255, 255, dim)
			surface.DrawTexturedRect(iconX, e.y + math.floor((e.h - ICON) / 2), ICON, ICON)
			surface.SetAlphaMultiplier(dim / 255)
			draw.SimpleText(e.label, Theme.FONT_TASKBAR, iconX + ICON + 6, e.y + e.h / 2, c, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			surface.SetAlphaMultiplier(1)
		else
			-- No room for a label: its initials say more than the icon of its kind.
			surface.SetAlphaMultiplier(dim / 255)
			draw.SimpleText(e.short, Theme.FONT_TASKBAR, e.x + e.w / 2, e.y + e.h / 2, c, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			surface.SetAlphaMultiplier(1)
		end
	end

	-- More that way.
	if self.maxScroll > 0 then
		local horiz = side == "bottom" or side == "top"
		local bg = Settings.Get("taskbarColorBg")
		if self.scroll > 0 then
			draw.RoundedBox(0, 0, 0, horiz and ARROW or w, horiz and h or ARROW, bg)
			draw.SimpleText(horiz and "<" or "^", Theme.FONT_TASKBAR, horiz and ARROW / 2 or w / 2, horiz and h / 2 or ARROW / 2, accent, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end
		if self.scroll < self.maxScroll then
			draw.RoundedBox(0, horiz and w - ARROW or 0, horiz and 0 or h - ARROW, horiz and ARROW or w, horiz and h or ARROW, bg)
			draw.SimpleText(horiz and ">" or "v", Theme.FONT_TASKBAR, horiz and w - ARROW / 2 or w / 2, horiz and h / 2 or h - ARROW / 2, accent, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end
	end
end

-- A bubble beside the bar, over whatever is there: the bar itself is too thin to hold it.
local function bubble(self, e, textW, textH, paint)
	local side = Settings.Get("taskbarSide")
	local bw, bh = textW + 14, textH + 14
	local sx, sy = self:LocalToScreen(0, 0)
	local bx, by
	if horizontal() then
		bx = math.Clamp(e.x + e.w / 2 - bw / 2, 4 - sx, ScrW() - bw - 4 - sx)
		by = side == "top" and e.y + e.h + 8 or e.y - bh - 8
	else
		by = math.Clamp(e.y + e.h / 2 - bh / 2, 4 - sy, ScrH() - bh - 4 - sy)
		bx = side == "left" and e.x + e.w + 8 or e.x - bw - 8
	end
	local old = DisableClipping(true)
	paint(bx, by, bw, bh)
	DisableClipping(old) -- B29
end

-- The keyboard's entry: a ring and a tooltip ("title · Enter to restore"). Else the mouse's: what the
-- entry is and what a click on it does.
function BAR:PaintOver(w, h)
	local Nav = PP.Nav
	local accent = Settings.Get("taskbarColorAccent")
	local function box(text)
		return function(bx, by, bw, bh)
			draw.RoundedBox(5, bx, by, bw, bh, Theme.popupBg)
			surface.SetDrawColor(accent)
			surface.DrawOutlinedRect(bx, by, bw, bh, 1)
			draw.SimpleText(text, Theme.FONT_TASKBAR, bx + 7, by + bh / 2, Theme.textBright, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		end
	end
	local e = Nav.state == "taskbar" and self.entries[Nav.taskIndex or 0]
	if e then
		surface.SetDrawColor(Theme.focusRing)
		surface.DrawOutlinedRect(e.x - 2, e.y - 2, e.w + 4, e.h + 4, 2)
	end
	-- The mouse's tooltip wins while it is over an entry: that is where the player is looking.
	local over = self.hover and self.items[self.hover]
	if over and self.tip then return bubble(self, over, self.tipW, self.tipH, box(self.tip)) end
	if e then bubble(self, e, Nav.hintW, Nav.hintH, box(Nav.hint)) end
end

vgui.Register("PinnedPanelsTaskbar", BAR, "EditablePanel")
