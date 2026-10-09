-- The hub's Tools, Content and Widgets pages (F2, F3, §33.9): PinnedPanelsCatalog lists one kind of
-- source, with search and category headers for tools and widgets. Rows read their pinned state when they
-- paint, never from a snapshot (L1).

local PP = PinnedPanels
local Layout, Sources, Desktop, T = PP.Layout, PP.Sources, PP.Desktop, PP.Theme

-- Searchable lists with category headers; "creation" is the plain one.
local LISTS = {
	tool = { entries = "tools", search = "search.tools", count = "count.tools", empty = "no.tools" },
	native = { entries = "natives", search = "search.native", count = "count.native", empty = "no.native" },
}

-- ── PinnedPanelsCatalogRow ──────────────────────────────────

local ROW = {}

function ROW:Init()
	self:SetTall(32)
	self.button = self:Add("PinnedPanelsButton")
	self.button:Dock(RIGHT)
	self.button:SetWide(70)
	self.button:DockMargin(0, 4, 4, 4)
	self.button.DoClick = function() self:Toggle() end
	self.pinText, self.unpinText = PP.L("btn.pin"), PP.L("btn.unpin")
end

function ROW:Setup(entry)
	self.src = entry.key
	self.title = Sources.Title(entry.key)
	self.search = self.title:lower()
	self.textX = 18
	if entry.kind == "creation" then
		self:SetTall(40)
		self.bold = true
		self.textX = 10
		self.tooltip = isstring(entry.tooltip) and entry.tooltip ~= "" and entry.tooltip or nil
		if isstring(entry.icon) and entry.icon ~= "" then
			local img = self:Add("DImage")
			img:SetImage(entry.icon)
			img:SetSize(16, 16)
			img:SetPos(10, 12)
			img:SetMouseInputEnabled(false)
			self.textX = 32
		end
	end
end

-- The window holding a row's source: a desktop widget is pinned as an embedded tab (Openers.FindDesktop).
local function pinnedAt(src)
	local widget = src:match("^desktop:(.+)$")
	if widget then return PP.Openers.FindDesktop(widget) end
	return Layout.Find(src)
end

function ROW:Toggle()
	local win, i = pinnedAt(self.src)
	if not win then
		Desktop.PinSource(self.src)
	elseif #win.tabs > 1 then
		Layout.UnpinTab(win.id, i)
	else
		Layout.Unpin(win.id)
	end
end

function ROW:Paint(w, h)
	local pinned = pinnedAt(self.src) ~= nil
	if pinned ~= self.pinned then
		self.pinned = pinned
		self.button:SetOn(pinned)
		self.button:SetLabel(pinned and self.unpinText or self.pinText)
		self.button:SetTooltip(PP.L(pinned and "tip.unpin" or "tip.pin"))
	end

	local hovered = self:IsHovered()
	local bg = pinned and (hovered and T.rowOnHover or T.rowOn) or (hovered and T.rowOffHover or T.rowOff)
	draw.RoundedBox(3, 0, 0, w, h, bg)
	if pinned then
		surface.SetDrawColor(T.success)
		surface.DrawRect(0, 0, 3, h)
	end

	if self.bold then
		local y = self.tooltip and 14 or h / 2
		draw.SimpleText(self.title, "DermaDefaultBold", self.textX, y, T.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		if self.tooltip then
			draw.SimpleText(self.tooltip, "DermaDefault", self.textX, 28, T.textMuted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		end
	else
		draw.RoundedBox(3, 8, h / 2 - 3, 6, 6, pinned and T.success or T.idle)
		draw.SimpleText(self.title, "DermaDefault", self.textX, h / 2, T.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	end
end

vgui.Register("PinnedPanelsCatalogRow", ROW, "DPanel")

-- ── PinnedPanelsCatalogHeader ───────────────────────────────

local HEADER = {}

function HEADER:Init()
	self:SetTall(24)
end

function HEADER:SetText(text)
	self.text = text:upper()
end

-- A tools category can be pinned whole: every tool of it that isn't pinned yet, in one tabbed window.
function HEADER:SetCategory(category)
	local b = self:Add("PinnedPanelsButton")
	b:Dock(RIGHT)
	b:SetWide(74)
	b:DockMargin(0, 2, 3, 2)
	b:SetLabel(PP.L("btn.pin_all"))
	b:SetIcon("icon16/folder_add.png")
	b:SetTooltip(PP.L("tip.pin_category"))
	b.DoClick = function()
		local made = PP.Batch.PinCategory(category)
		if #made == 0 then return notification.AddLegacy(PP.L("pin.category_none", category), NOTIFY_HINT, 5) end
		Desktop.RestoreAndFront(made[1])
	end
end

function HEADER:Paint(w, h)
	draw.RoundedBox(3, 0, 0, w, h, T.categoryBg)
	surface.SetDrawColor(T.accent)
	surface.DrawRect(0, 0, 3, h)
	draw.SimpleText(self.text, "DermaDefaultBold", 12, h / 2, T.textLabel, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
end

vgui.Register("PinnedPanelsCatalogHeader", HEADER, "DPanel")

-- ── PinnedPanelsCatalog ─────────────────────────────────────

local CATALOG = {}

function CATALOG:Init()
	self.top = self:Add("Panel")
	self.top:Dock(TOP)
	self.top:DockMargin(4, 4, 4, 2)

	self.list = self:Add("PinnedPanelsScroll")
	self.list:Dock(FILL)
	self.list:DockMargin(4, 2, 4, 4)

	hook.Add("PinnedPanelsCatalogChanged", self, self.Populate)
end

-- "tool" and "native" get a search box and category headers; "creation" gets an explanation line.
function CATALOG:SetKind(kind)
	self.kind = kind
	self.searchable = LISTS[kind]
	if self.searchable then
		self.top:SetTall(32)
		self.search = self.top:Add("PinnedPanelsSearch")
		self.search:Dock(FILL)
		self.search:SetPlaceholderText(PP.L(self.searchable.search))
		self.search.OnChange = function() self:Filter() end
		self.countLabel = self.top:Add("DLabel")
		self.countLabel:Dock(RIGHT)
		self.countLabel:SetWide(80)
		self.countLabel:DockMargin(4, 0, 0, 0)
		self.countLabel:SetContentAlignment(6)
		self.countLabel:SetTextColor(T.textSubtle)
	else
		local info = self.top:Add("DLabel")
		info:Dock(FILL)
		info:SetWrap(true)
		info:SetTextColor(T.textSubtle)
		info:SetText(PP.L("creation.info"))
		self.top:SetTall(40)
	end
	self:Populate()
end

function CATALOG:Populate()
	self.list:Clear()
	self.rows, self.headers = {}, {}

	self.empty = self.list:Add("DLabel")
	self.empty:Dock(TOP)
	self.empty:DockMargin(10, 10, 10, 0)
	self.empty:SetWrap(true)
	self.empty:SetAutoStretchVertical(true)
	self.empty:SetTextColor(T.textSubtle)
	local list = self.searchable
	self.empty:SetText(PP.L(list and list.empty or "creation.none"))

	local entries = list and Sources[list.entries] or Sources.creations
	local header, category
	for _, e in ipairs(entries) do
		if list and e.category ~= category then
			category = e.category
			header = self.list:Add("PinnedPanelsCatalogHeader")
			header:SetText(category)
			if self.kind == "tool" then header:SetCategory(category) end
			header:Dock(TOP)
			header:DockMargin(2, #self.headers == 0 and 1 or 6, 2, 2)
			self.headers[#self.headers + 1] = header
		end
		local row = self.list:Add("PinnedPanelsCatalogRow")
		row:Setup(e)
		row:Dock(TOP)
		row:DockMargin(2, 1, 2, list and 0 or 1)
		row.header = header
		self.rows[#self.rows + 1] = row
	end
	self:Filter()
end

-- Hides rows that don't match and headers left without rows.
function CATALOG:Filter()
	local query = self.search and self.search:GetValue():lower() or ""
	local shown, withRows = 0, {}
	for _, row in ipairs(self.rows) do
		local visible = query == "" or row.search:find(query, 1, true) ~= nil
		row:SetVisible(visible)
		if visible then
			shown = shown + 1
			if row.header then withRows[row.header] = true end
		end
	end
	for _, header in ipairs(self.headers) do header:SetVisible(withRows[header] == true) end
	self.empty:SetVisible(shown == 0)

	if self.countLabel then
		self.countLabel:SetText(query == "" and PP.L(self.searchable.count, #self.rows) or (shown .. " / " .. #self.rows))
	end
	self.list:GetCanvas():InvalidateLayout()
	self.list:InvalidateLayout()
end

function CATALOG:Paint() end

vgui.Register("PinnedPanelsCatalog", CATALOG, "DPanel")
