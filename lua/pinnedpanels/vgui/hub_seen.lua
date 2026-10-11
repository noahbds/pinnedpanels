-- The hub's Seen page (X61): everything pinned before, of any kind, most recently pinned first, each
-- with a button that pins it again as it was. Rows read whether they are pinned when they paint, never
-- from a snapshot (L1); the list is made again only when what was seen changes.

local PP = PinnedPanels
local Seen, T = PP.Seen, PP.Theme

local ROW_H = 40
local KIND = T.KIND

-- ── PinnedPanelsSeenRow ─────────────────────────────────────

local ROW = {}

function ROW:Init()
	self:SetTall(ROW_H)
	self.forget = self:Add("PinnedPanelsButton")
	self.forget:Dock(RIGHT)
	self.forget:SetWide(28)
	self.forget:DockMargin(0, 7, 6, 7)
	self.forget:SetIcon("icon16/cross.png")
	self.forget:SetTooltip(PP.L("tip.forget"))
	self.forget.DoClick = function() Seen.Forget(self.entry.key) end

	self.button = self:Add("PinnedPanelsButton")
	self.button:Dock(RIGHT)
	self.button:SetWide(74)
	self.button:DockMargin(0, 7, 4, 7)
	self.button.DoClick = function() Seen.Pin(self.entry) end
end

function ROW:Setup(e)
	self.entry = e
	local kind = KIND[e.kind] or KIND.tool
	self.icon = T.Icon(kind.icon)
	self.title = e.custom or e.title or "?"
	local parts = { PP.L(kind.label) }
	if e.addon then parts[#parts + 1] = e.addon end
	if e.adopt then parts[#parts + 1] = PP.Recipes.Describe(e.adopt) end
	parts[#parts + 1] = PP.L("seen.last", os.date("%Y-%m-%d", e.last or 0))
	if (e.count or 1) > 1 then parts[#parts + 1] = PP.L("seen.times", e.count) end
	self.sub = table.concat(parts, "  ·  ")
	self.search = (self.title .. " " .. self.sub):lower()
end

function ROW:Paint(w, h)
	local e = self.entry
	local pinned = Seen.PinnedAt(e) ~= nil
	local available = pinned or Seen.Available(e)
	local state = pinned and "pinned" or (available and "free" or "gone")
	if state ~= self.state then
		self.state = state
		self.button:SetOn(pinned)
		self.button:SetLabel(PP.L(pinned and "btn.show" or "btn.pin"))
		self.button:SetTooltip(PP.L(pinned and "tip.seen_show" or (available and "tip.seen_pin" or "seen.unavailable")))
		self.button:SetEnabled(available)
	end

	local hovered = self:IsHovered()
	draw.RoundedBox(3, 0, 0, w, h, pinned and (hovered and T.rowOnHover or T.rowOn) or (hovered and T.rowOffHover or T.rowOff))
	if pinned then
		surface.SetDrawColor(T.success)
		surface.DrawRect(0, 0, 3, h)
	end
	surface.SetMaterial(self.icon)
	surface.SetDrawColor(255, 255, 255, available and 255 or 90)
	surface.DrawTexturedRect(12, (h - 16) / 2, 16, 16)
	-- Up to the buttons, not under them.
	local room = w - 40 - 74 - 28 - 20
	draw.SimpleText(T.Fit(self.title, "DermaDefaultBold", room), "DermaDefaultBold", 38, 13, available and T.text or T.textMuted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	draw.SimpleText(T.Fit(self.sub, "DermaDefault", room), "DermaDefault", 38, 28, available and T.textSubtle or T.textMuted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
end

vgui.Register("PinnedPanelsSeenRow", ROW, "DPanel")

-- ── PinnedPanelsSeen ────────────────────────────────────────

local PAGE = {}

function PAGE:Init()
	local top = self:Add("Panel")
	top:Dock(TOP)
	top:SetTall(32)
	top:DockMargin(4, 4, 4, 2)

	local clear = top:Add("PinnedPanelsButton")
	clear:Dock(RIGHT)
	clear:SetWide(96)
	clear:DockMargin(4, 4, 0, 4)
	clear:SetLabel(PP.L("btn.clear_seen"))
	clear:SetIcon("icon16/bin.png")
	clear:SetTooltip(PP.L("tip.clear_seen"))
	clear.DoClick = function()
		if next(Seen.entries) == nil then return end
		Derma_Query(PP.L("seen.clear_ask"), PP.L("tab.seen"), PP.L("btn.yes"), function() Seen.Clear() end, PP.L("btn.no"), function() end)
	end

	self.countLabel = top:Add("DLabel")
	self.countLabel:Dock(RIGHT)
	self.countLabel:SetWide(80)
	self.countLabel:DockMargin(4, 0, 0, 0)
	self.countLabel:SetContentAlignment(6)
	self.countLabel:SetTextColor(T.textSubtle)

	self.search = top:Add("PinnedPanelsSearch")
	self.search:Dock(FILL)
	self.search:SetPlaceholderText(PP.L("search.seen"))
	self.search.OnChange = function() self:Filter() end

	self.list = self:Add("PinnedPanelsScroll")
	self.list:Dock(FILL)
	self.list:DockMargin(4, 2, 4, 4)

	hook.Add("PinnedPanelsSeenChanged", self, self.Populate)
	self:Populate()
end

function PAGE:Populate()
	self.list:Clear()
	self.rows = {}

	self.empty = self.list:Add("DLabel")
	self.empty:Dock(TOP)
	self.empty:DockMargin(10, 10, 10, 0)
	self.empty:SetWrap(true)
	self.empty:SetAutoStretchVertical(true)
	self.empty:SetTextColor(T.textSubtle)
	self.empty:SetText(PP.L("seen.none"))

	for _, e in ipairs(Seen.List()) do
		local row = self.list:Add("PinnedPanelsSeenRow")
		row:Setup(e)
		row:Dock(TOP)
		row:DockMargin(2, 1, 2, 1)
		self.rows[#self.rows + 1] = row
	end
	self:Filter()
end

function PAGE:Filter()
	local query = self.search:GetValue():lower()
	local shown = 0
	for _, row in ipairs(self.rows) do
		local visible = query == "" or row.search:find(query, 1, true) ~= nil
		row:SetVisible(visible)
		if visible then shown = shown + 1 end
	end
	self.empty:SetVisible(shown == 0)
	self.countLabel:SetText(query == "" and PP.LN("count.seen", #self.rows) or (shown .. " / " .. #self.rows))
	self.list:GetCanvas():InvalidateLayout()
	self.list:InvalidateLayout()
end

function PAGE:Paint() end

vgui.Register("PinnedPanelsSeen", PAGE, "DPanel")
