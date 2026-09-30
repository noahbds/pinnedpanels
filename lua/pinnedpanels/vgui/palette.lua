-- PinnedPanelsPalette (§20.3, F23): a searchable launcher for actions, pinned windows (including a way
-- back from click-through, L16), tools and content tabs. Categories sort by id, not by their translated
-- names (B14). It holds the "palette" cursor reason while open (E31).

local PP = PinnedPanels
local Layout, Sources, Desktop, Input, Util, T = PP.Layout, PP.Sources, PP.Desktop, PP.Input, PP.Util, PP.Theme

PP.Palette = PP.Palette or {}

local W, H, HEADER_H, FOOTER_H, ROW_H = 580, 470, 48, 24, 44
local MAX_ROWS = 80
local CATEGORIES = { action = { 1, "cat.action" }, pinned = { 2, "cat.pinned" }, tool = { 3, "cat.tool" }, content = { 4, "cat.content" } }

-- Everything the palette can run, collected when it opens.
local function collect()
	local list = {}
	local function add(cat, text, sub, icon, run)
		list[#list + 1] = { cat = cat, order = CATEGORIES[cat][1], catText = PP.L(CATEGORIES[cat][2]), text = text or "", sub = sub, icon = icon, run = run }
	end

	for _, def in ipairs(PP.Actions.list) do
		if def.palette and (not def.visible or def.visible()) then
			add("action", PP.Actions.Name(def), def.sub and PP.L(def.sub), def.icon, function() PP.Actions.Run(def.id) end)
		end
	end
	for _, rec in ipairs(Layout.Windows()) do
		if #rec.tabs > 0 and not Desktop.IsDormant(rec) then
			local id, title = rec.id, Layout.Title(rec)
			add("pinned", title, PP.L("sub.show_front"), "icon16/application_double.png", function()
				Desktop.RestoreAndFront(id)
				Input.SetCursorMode(true)
			end)
			if rec.clickThrough then
				add("action", PP.L("act.restore_inter", title), PP.L("sub.disable_ct"), "icon16/cursor.png", function()
					Layout.SetClickThrough(id, false)
				end)
			end
		end
	end
	for _, e in ipairs(Sources.tools) do
		add("tool", Sources.Title(e.key), e.category, "icon16/wrench.png", function() Desktop.PinSource(e.key) end)
	end
	for _, e in ipairs(Sources.creations) do
		add("content", Sources.Title(e.key), PP.L("sub.content_browser"), e.icon or "icon16/application_view_list.png",
			function() Desktop.PinSource(e.key) end)
	end
	return list
end

-- Best matches first (the subtitle counts, less than the name), then category, then name.
local function filter(entries, query)
	query = string.Trim(query:lower())
	local scored = {}
	for _, e in ipairs(entries) do
		local s = 0
		if query ~= "" then
			s = Util.Fuzzy(e.text, query)
			local subScore = e.sub and Util.Fuzzy(e.sub, query)
			if subScore and (not s or subScore + 200 < s) then s = subScore + 200 end
		end
		if s then scored[#scored + 1] = { e = e, s = s } end
	end
	table.sort(scored, function(a, b)
		if a.s ~= b.s then return a.s < b.s end
		if a.e.order ~= b.e.order then return a.e.order < b.e.order end
		return a.e.text:lower() < b.e.text:lower()
	end)
	local out = {}
	for i = 1, math.min(#scored, MAX_ROWS) do out[i] = scored[i].e end
	return out, #scored
end

-- ── Rows ────────────────────────────────────────────────────

local ROW = {}

function ROW:Init()
	self:SetText("")
	self:SetTall(ROW_H)
end

function ROW:Setup(palette, index, entry)
	self.palette, self.index, self.entry = palette, index, entry
	self.mat = entry.icon and T.Icon(entry.icon)
end

function ROW:DoClick()
	self.palette:Run(self.entry)
end

-- The mouse only takes the selection once it actually moves, so scrolling by keyboard under a resting
-- cursor doesn't steal it.
function ROW:OnCursorEntered()
	local p = self.palette
	local mx, my = input.GetCursorPos()
	if p.guardX == mx and p.guardY == my then return end
	p.guardX, p.guardY = nil, nil
	p.sel = self.index
end

function ROW:Paint(w, h)
	local e, selected = self.entry, self.palette.sel == self.index
	if selected then
		draw.RoundedBox(5, 0, 0, w, h, T.paletteSelected)
		surface.SetDrawColor(T.accent)
		surface.DrawRect(0, 4, 3, h - 8)
	elseif self:IsHovered() then
		draw.RoundedBox(5, 0, 0, w, h, T.hover)
	end
	local x = 14
	if self.mat then
		surface.SetMaterial(self.mat)
		surface.SetDrawColor(255, 255, 255, 255)
		surface.DrawTexturedRect(14, h / 2 - 8, 16, 16)
		x = 40
	end
	local main = selected and T.textBright or T.text
	if e.sub and e.sub ~= "" then
		draw.SimpleText(e.text, T.FONT_PALETTE_ITEM, x, 7, main, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
		draw.SimpleText(e.sub, T.FONT_PALETTE_SUB, x, h - 7, selected and T.text or T.textMuted, TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM)
	else
		draw.SimpleText(e.text, T.FONT_PALETTE_ITEM, x, h / 2, main, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	end
	draw.SimpleText(e.catText, T.FONT_PALETTE_SUB, w - 12, h / 2, selected and T.text or T.textSubtle, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
end

vgui.Register("PinnedPanelsPaletteRow", ROW, "DButton")

-- ── The palette ─────────────────────────────────────────────

local PALETTE = {}

function PALETTE:Init()
	self:SetSize(W, H)
	self:Center()
	self.entries = collect()
	self.rows = {}
	self.sel = 1
	self.navText = PP.L("palette.nav")

	self.search = self:Add("DTextEntry")
	self.search:SetPos(16, 10)
	self.search:SetSize(W - 32, 28)
	self.search:SetFont(T.FONT_PALETTE_QUERY)
	self.search:SetPlaceholderText(PP.L("palette.search"))
	self.search:SetUpdateOnType(true)
	self.search:SetPaintBackground(false)
	self.search:SetTextColor(T.textBright)
	self.search:SetCursorColor(T.textBright)
	self.search.OnValueChange = function() self:Rebuild() end
	self.search.OnKeyCodeTyped = function(_, code) return self:Key(code) end

	self.list = self:Add("DScrollPanel")
	self.list:SetPos(8, HEADER_H + 4)
	self.list:SetSize(W - 16, H - HEADER_H - FOOTER_H - 8)
	self:Rebuild()
end

function PALETTE:Rebuild()
	self.list:Clear()
	self.rows, self.sel = {}, 1
	self.list:GetVBar():SetScroll(0)
	self.guardX, self.guardY = input.GetCursorPos()

	local shown, total = filter(self.entries, self.search:GetValue())
	self.countText = #shown >= total and PP.L("palette.results", #shown) or PP.L("palette.results_of", #shown, total)
	if #shown == 0 then
		local empty = self.list:Add("DLabel")
		empty:Dock(TOP)
		empty:DockMargin(12, 14, 12, 0)
		empty:SetFont(T.FONT_PALETTE_ITEM)
		empty:SetContentAlignment(5)
		empty:SetTextColor(T.textMuted)
		empty:SetText(PP.L("palette.no_matches"))
		return
	end
	for i, e in ipairs(shown) do
		local row = self.list:Add("PinnedPanelsPaletteRow")
		row:Dock(TOP)
		row:DockMargin(4, 2, 4, 0)
		row:Setup(self, i, e)
		self.rows[i] = row
	end
end

-- Keeps the selected row in view after keyboard moves.
function PALETTE:Select(index)
	if #self.rows == 0 then return end
	self.sel = math.Clamp(index, 1, #self.rows)
	self.guardX, self.guardY = input.GetCursorPos()
	local row = self.rows[self.sel]
	self.list:InvalidateLayout(true)
	local _, y = row:GetPos()
	local bar, view = self.list:GetVBar(), self.list:GetTall()
	if y - 4 < bar:GetScroll() then
		bar:SetScroll(y - 4)
	elseif y + row:GetTall() + 4 > bar:GetScroll() + view then
		bar:SetScroll(y + row:GetTall() + 4 - view)
	end
end

function PALETTE:Key(code)
	local n = #self.rows
	if code == KEY_ESCAPE then
		self:Remove()
	elseif code == KEY_ENTER or code == KEY_PAD_ENTER then
		local row = self.rows[self.sel]
		if row then self:Run(row.entry) end
	elseif code == KEY_DOWN or code == KEY_TAB then
		if n > 0 then self:Select(self.sel % n + 1) end
	elseif code == KEY_UP then
		if n > 0 then self:Select((self.sel - 2) % n + 1) end
	elseif code == KEY_PAGEDOWN then
		self:Select(self.sel + 8)
	elseif code == KEY_PAGEUP then
		self:Select(self.sel - 8)
	else
		return
	end
	return true
end

-- Other addons' code can run from here (a content tab's builder); errors are printed, the palette closes.
function PALETTE:Run(entry)
	self:Remove()
	local ok, err = xpcall(entry.run, debug.traceback)
	if not ok then ErrorNoHalt("[Pinned Panels] palette: " .. tostring(err) .. "\n") end
end

function PALETTE:OnRemove()
	Input.Cursor("palette", false)
	if PP.Palette.panel == self then PP.Palette.panel = nil end
end

function PALETTE:Paint(w, h)
	draw.RoundedBox(8, 0, 0, w, h, T.popupBg)
	draw.RoundedBoxEx(8, 0, 0, w, HEADER_H, T.popupHeader, true, true, false, false)
	surface.SetDrawColor(T.accent)
	surface.DrawRect(0, HEADER_H - 1, w, 1)
	draw.RoundedBoxEx(8, 0, h - FOOTER_H, w, FOOTER_H, T.paletteFooter, false, false, true, true)
	draw.SimpleText(self.navText, T.FONT_PALETTE_SUB, 14, h - FOOTER_H / 2, T.textMuted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	draw.SimpleText(self.countText, T.FONT_PALETTE_SUB, w - 14, h - FOOTER_H / 2, T.textSubtle, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
	surface.SetDrawColor(T.inputBorder)
	surface.DrawOutlinedRect(0, 0, w, h, 1)
end

vgui.Register("PinnedPanelsPalette", PALETTE, "EditablePanel")

-- Opens the palette, or closes it if it's open.
function PP.Palette.Toggle()
	if IsValid(PP.Palette.panel) then
		PP.Palette.panel:Remove()
		return
	end
	Input.Cursor("palette", true)
	local p = vgui.Create("PinnedPanelsPalette")
	p:MakePopup()
	p.search:RequestFocus()
	PP.Palette.panel = p
end
