-- Tabs (§15.2). PinnedPanelsTabStrip shows a window's tabs when it has two or more (F15).
-- PinnedPanelsTabHost holds one tab's content: built when first shown, one per frame (D13, E24), with an
-- optional filter bar (F19), remembered category collapse (F20, D14) and the size measurement behind
-- auto-size (F17). Its PinnedPanelsClip crops by moving the content inside it, never by reparenting (F16).
-- PinnedPanelsScroll throttles layout (L3, B6).

local PP = PinnedPanels
local Layout, Sources, Theme = PP.Layout, PP.Sources, PP.Theme

-- ── PinnedPanelsScroll ──────────────────────────────────────
-- Tool panels invalidate their scroll panel in storms while they build. Layout runs at most once per
-- THROTTLE seconds, and a skipped layout always runs later (trailing edge), unlike v1's leading-edge wrapper.

local THROTTLE = 0.1

local SCROLL = {}

function SCROLL:PerformLayout(w, h)
	local now = RealTime()
	if now < (self.nextLayout or 0) then
		self.layoutPending = true
		return
	end
	self.nextLayout = now + THROTTLE
	self.layoutPending = false
	baseclass.Get("DScrollPanel").PerformLayout(self, w, h)
end

function SCROLL:Think()
	local base = baseclass.Get("DScrollPanel")
	if base.Think then base.Think(self) end
	if self.layoutPending and RealTime() >= self.nextLayout then self:InvalidateLayout() end
end

vgui.Register("PinnedPanelsScroll", SCROLL, "DScrollPanel")

-- ── PinnedPanelsTabStrip ────────────────────────────────────

local STRIP_H, TAB_PAD, TAB_GAP, TAB_MIN = 22, 10, 2, 40

local STRIP = {}

function STRIP:Init()
	self:SetTall(STRIP_H)
	self:DockMargin(0, 0, 0, 2)
	self.items = {}
end

-- items: the window's available tabs, each { index (in rec.tabs), title }.
function STRIP:Setup(rec, items, shownIndex)
	self.rec, self.items, self.shown = rec, items, shownIndex
	self:InvalidateLayout()
end

-- Tabs share the width in proportion to their titles; titles are cut to fit here, not while painting.
function STRIP:PerformLayout(w)
	surface.SetFont("DermaDefaultBold")
	local total = 0
	for _, it in ipairs(self.items) do
		it.natural = surface.GetTextSize(it.title) + TAB_PAD * 2
		total = total + it.natural + TAB_GAP
	end
	local scale = total > w and w / total or 1
	local x = 0
	for _, it in ipairs(self.items) do
		it.x, it.w = x, math.max(TAB_MIN, math.floor(it.natural * scale))
		local room, label = it.w - TAB_PAD * 2, it.title
		if surface.GetTextSize(label) > room then
			while #label > 1 and surface.GetTextSize(label .. "..") > room do label = label:sub(1, -2) end
			label = label .. ".."
		end
		it.label = label
		x = x + it.w + TAB_GAP
	end
end

function STRIP:ItemAt(x)
	for _, it in ipairs(self.items) do
		if x >= it.x and x < it.x + it.w then return it end
	end
end

function STRIP:OnCursorMoved(x)
	self.hover = self:ItemAt(x)
end

function STRIP:OnCursorExited()
	self.hover = nil
end

function STRIP:OnMousePressed(code)
	local it = self:ItemAt(self:CursorPos())
	if not it then return end
	PP.Desktop.SetFocused(self.rec.id)
	if code == MOUSE_LEFT then
		Layout.Activate(self.rec.id, it.index)
	elseif code == MOUSE_RIGHT then
		PP.Actions.OpenTabMenu(self.rec.id, it.index)
	end
end

function STRIP:Paint(w, h)
	local accent = self.rec.accent or Theme.groupAccent
	for _, it in ipairs(self.items) do
		local active = it.index == self.shown
		local bg = active and Theme.tabActive or (self.hover == it and Theme.hover or Theme.tabIdle)
		draw.RoundedBoxEx(5, it.x, 0, it.w, h, bg, true, true, false, false)
		surface.SetDrawColor(accent.r, accent.g, accent.b, active and 255 or 80)
		if active then
			surface.DrawRect(it.x, 0, it.w, 2)
		else
			surface.DrawRect(it.x, h - 1, it.w, 1)
		end
		draw.SimpleText(it.label, "DermaDefaultBold", it.x + it.w / 2, h / 2,
			active and Theme.textBright or Theme.textSubtle, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end
end

vgui.Register("PinnedPanelsTabStrip", STRIP, "Panel")

-- ── PinnedPanelsClip ────────────────────────────────────────
-- Uncropped, the content fills the clip. Cropped, the content keeps the clip's size plus the insets and
-- sits at (-l, -t), so the clip shows exactly the kept part.

-- The clip keeps mouse input on: panels take their parent's mouse-input state when they are created, so a
-- disabled clip would disable everything built inside it (L22). The content covers it, so it never gets clicks.
local CLIP = {}

function CLIP:SetContent(content)
	self.content, self.docked = content, nil
	self:InvalidateLayout()
end

function CLIP:SetCrop(crop)
	local old = self.crop
	if old == crop or (old and crop and old.l == crop.l and old.t == crop.t and old.r == crop.r and old.b == crop.b) then return end
	self.crop = crop
	self:InvalidateLayout()
end

function CLIP:PerformLayout(w, h)
	local content, crop = self.content, self.crop
	if not IsValid(content) then return end
	if crop then
		if self.docked ~= false then
			content:Dock(NODOCK)
			self.docked = false
		end
		content:SetPos(-crop.l, -crop.t)
		content:SetSize(w + crop.l + crop.r, h + crop.t + crop.b)
	elseif self.docked ~= true then
		content:Dock(FILL)
		self.docked = true
	end
end

vgui.Register("PinnedPanelsClip", CLIP, "Panel")

-- ── Walking foreign content ─────────────────────────────────
-- Tool panels are other addons' controls; these only read them, except the filter, which hides rows
-- and puts them back exactly (v1 behaviour).

local MAX_DEPTH = 14

local function isCategory(p)
	return isfunction(p.GetExpanded) and isfunction(p.SetExpanded) and IsValid(p.Header) and p.Header:IsVisible()
end

local function categories(root, out, depth)
	for _, child in ipairs(root:GetChildren()) do
		if isCategory(child) then out[#out + 1] = child end
		if depth < MAX_DEPTH then categories(child, out, depth + 1) end
	end
	return out
end

local function categoryLabel(cat)
	local text = cat.Header:GetText()
	return isstring(text) and text ~= "" and text or nil
end

local function subtreeText(p, depth)
	local parts = {}
	if isfunction(p.GetText) then
		local t = p:GetText()
		if isstring(t) and t ~= "" then parts[#parts + 1] = t end
	end
	if isstring(p.m_NiceName) and p.m_NiceName ~= "" then parts[#parts + 1] = p.m_NiceName end
	if depth < 8 then
		for _, c in ipairs(p:GetChildren()) do parts[#parts + 1] = subtreeText(c, depth + 1) end
	end
	return table.concat(parts, "\n")
end

-- The first panel under root with a canvas (the tool panel's scroll panel), breadth first.
local function findCanvas(root)
	local queue, head = { root }, 1
	while queue[head] do
		local p = queue[head]
		head = head + 1
		if isfunction(p.GetCanvas) and IsValid(p:GetCanvas()) then return p, p:GetCanvas() end
		for _, c in ipairs(p:GetChildren()) do queue[#queue + 1] = c end
	end
end

local function unfilter(root, depth)
	for _, c in ipairs(root:GetChildren()) do
		if c.ppFiltered then
			c.ppFiltered = nil
			c:SetVisible(true)
			if c.ppSizeY ~= nil then c:SetSizeY(c.ppSizeY) end
			if c.ppTall then c:SetTall(c.ppTall) end
			c.ppSizeY, c.ppTall = nil, nil
			c:InvalidateLayout()
		end
		if c.ppFilterExpanded then
			c.ppFilterExpanded = nil
			c:SetExpanded(false)
		end
		if depth < MAX_DEPTH then unfilter(c, depth + 1) end
	end
end

-- DForm rows size themselves to their contents (DSizeToContents); that has to stop while hidden.
local function hideRow(p)
	p.ppFiltered = true
	p.ppTall = p.ppTall or p:GetTall()
	if isfunction(p.GetSizeY) and p.ppSizeY == nil then
		p.ppSizeY = p:GetSizeY()
		p:SetSizeY(false)
	end
	p:SetVisible(false)
	p:SetTall(0)
end

-- Hides rows whose text doesn't match; a matching row inside a category opens the category.
local function filterContent(content, query)
	unfilter(content, 0)
	local scroll, canvas = findCanvas(content)
	local root = canvas or content
	query = string.Trim(query:lower())
	if query ~= "" then
		local function match(text) return text:lower():find(query, 1, true) ~= nil end
		-- A tool panel is usually one ControlPanel holding the rows.
		local rowParent, visible = root, {}
		for _, k in ipairs(root:GetChildren()) do
			if k:IsVisible() then visible[#visible + 1] = k end
		end
		if #visible == 1 and #visible[1]:GetChildren() > 0 then rowParent = visible[1] end

		for _, row in ipairs(rowParent:GetChildren()) do
			if row:IsVisible() and row ~= rowParent.Header then
				if isCategory(row) and not match(categoryLabel(row) or "") then
					local any = false
					for _, inner in ipairs(row:GetChildren()) do
						if inner ~= row.Header and inner:IsVisible() then
							if match(subtreeText(inner, 0)) then any = true else hideRow(inner) end
						end
					end
					if not any then
						hideRow(row)
					elseif not row:GetExpanded() then
						row:SetExpanded(true)
						row.ppFilterExpanded = true
					end
				elseif not isCategory(row) and not match(subtreeText(row, 0)) then
					hideRow(row)
				end
			end
		end
		if rowParent ~= root then rowParent:InvalidateLayout(true) end
	end
	root:InvalidateChildren(true)
	root:InvalidateLayout(true)
	if scroll then scroll:InvalidateLayout(true) end
end

-- Auto-size measurement, as v1: the widest row's natural width and the lowest child's bottom.
local CLASS_MIN_W = { DNumSlider = 240, DColorMixer = 240, DComboBox = 180, DTextEntry = 160 }

local function textWidth(p)
	if not isfunction(p.GetText) or (isfunction(p.GetWrap) and p:GetWrap()) then return 0 end
	local text = p:GetText()
	if not isstring(text) or text == "" then return 0 end
	local font = isfunction(p.GetFont) and p:GetFont()
	if not (isstring(font) and pcall(surface.SetFont, font)) then surface.SetFont("DermaDefault") end
	local w = surface.GetTextSize(text)
	if w <= 0 then return 0 end
	return w + 16 + (IsValid(p.m_Image) and 24 or 0)
end

local function naturalWidth(p, depth)
	if depth > 12 or not p:IsVisible() then return 0 end
	local class = p.ClassName or p:GetClassName()
	if class:find("ScrollBar") or class:find("Grip") then return 0 end
	local w = math.max(textWidth(p), CLASS_MIN_W[class] or (class:find("Slider") and 240) or 0)
	for _, c in ipairs(p:GetChildren()) do
		local cw
		if c:GetDock() == NODOCK then
			cw = c:GetPos() + math.max(c:GetWide(), naturalWidth(c, depth + 1))
		else
			local ml, _, mr = c:GetDockMargin()
			cw = naturalWidth(c, depth + 1) + ml + mr
		end
		w = math.max(w, cw)
	end
	if w > 0 then
		local pl, _, pr = p:GetDockPadding()
		w = w + pl + pr
	end
	return w
end

local function bottomExtent(parent)
	local h = 0
	for _, c in ipairs(parent:GetChildren()) do
		if c:IsVisible() then
			c:InvalidateLayout(true)
			local _, y = c:GetPos()
			h = math.max(h, y + c:GetTall())
		end
	end
	return h
end

-- ── PinnedPanelsTabHost ─────────────────────────────────────

local HOST = {}

function HOST:Init()
	self.filter = self:Add("PinnedPanelsSearch")
	self.filter:Dock(TOP)
	self.filter:SetTall(22)
	self.filter:DockMargin(0, 0, 0, 4)
	self.filter:SetPlaceholderText(PP.L("filter.controls"))
	self.filter:SetVisible(false)
	self.filter.OnChange = function() self:ApplyFilter() end

	self.clip = self:Add("PinnedPanelsClip")
	self.clip:Dock(FILL)
end

function HOST:SetSource(src)
	self.src = src
end

-- Think only runs while the host is visible (G4), so hidden tabs and minimized windows wait.
function HOST:Think()
	if not self.built and PP.Desktop.ClaimBuild() then self:Build() end
end

function HOST:Build()
	self.built = true
	self.clip:Clear()
	-- Tabs usually build while their window is idle and ignoring the mouse. Panels take their parent's
	-- mouse-input state when created, so the chain the content is built under must accept the mouse now;
	-- the window gets its own state back afterwards (the desktop sets it from cursor mode).
	local win = self:GetParent()
	local winMouse = win:IsMouseInputEnabled()
	win:SetMouseInputEnabled(true)
	self:SetMouseInputEnabled(true)
	self.filter:SetMouseInputEnabled(true)
	self.clip:SetMouseInputEnabled(true)
	self.content = PP.Sources.Build(self.src, self.clip)
	win:SetMouseInputEnabled(winMouse)
	self.clip:SetContent(self.content)
	if not self.content then
		local err = self.clip:Add("PinnedPanelsError")
		err:Dock(FILL)
		err:SetMouseInputEnabled(true)
		err:SetRetry(function() self:Rebuild() end)
		return
	end
	-- Collapse memory: GMod's own cookie per category, saved on every toggle (G23).
	for _, cat in ipairs(categories(self.content, {}, 0)) do
		local label = categoryLabel(cat)
		if label then cat:SetCookieName("pinnedpanels." .. self.src .. "." .. label) end
	end
	if self.filter:GetValue() ~= "" then self:ApplyFilter() end
end

-- "Rebuild content": a tool that rebuilt its spawn-menu panel doesn't update pinned copies (E10, G15).
function HOST:Rebuild()
	self.built = false
end

function HOST:SetCrop(crop)
	self.clip:SetCrop(crop)
end

function HOST:SetFilterBar(on)
	if self.filter:IsVisible() == on then return end
	self.filter:SetVisible(on)
	if not on and self.filter:GetValue() ~= "" then
		self.filter:SetText("")
		self:ApplyFilter()
	end
	self:InvalidateLayout()
end

function HOST:ApplyFilter()
	if IsValid(self.content) then filterContent(self.content, self.filter:GetValue()) end
end

-- The content's natural width (tools only) and height, and the panel they were measured against, so the
-- window can add its own chrome. nil when there is nothing to measure.
function HOST:NaturalSize()
	local content = self.content
	if not IsValid(content) then return nil end
	local scroll, canvas = findCanvas(content)
	local ref = scroll or content
	if scroll then
		scroll:InvalidateLayout(true)
		canvas:InvalidateLayout(true)
	else
		content:InvalidateLayout(true)
	end
	local w
	if self.src:match("^tool:") then
		local natural = naturalWidth(canvas or content, 0)
		if natural > 60 then w = natural end
	end
	local h = bottomExtent(canvas or content)
	if h <= 0 then return nil end
	return w, h, ref
end

vgui.Register("PinnedPanelsTabHost", HOST, "Panel")
