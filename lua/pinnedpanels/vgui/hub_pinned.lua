-- The hub's Pinned page (F4): every window, including hidden, minimized, dormant (its addon isn't loaded,
-- E1), waiting (an adopted panel that isn't open, §33.9) and empty named groups. Multi-tab windows expand
-- to their tabs. The page only calls Layout, Desktop and Actions; it never changes the document itself (L26).

local PP = PinnedPanels
local Layout, Sources, Desktop, T = PP.Layout, PP.Sources, PP.Desktop, PP.Theme

local ROW_H, TAB_ROW_H = 40, 30

local function kindOf(rec)
	if rec.kind == "managed" then return "managed" end
	if rec.title or #rec.tabs > 1 then return "group" end
	return rec.tabs[1].src:match("^(%a+):") or "tool"
end

local KIND = {
	group = { label = "kind.group", icon = "icon16/folder.png", color = T.success },
	creation = { label = "kind.content", icon = "icon16/application_view_list.png", color = T.success },
	tool = { label = "kind.tool", icon = "icon16/wrench.png", color = T.accent },
	managed = { label = "kind.managed", icon = "icon16/application_link.png", color = T.warning },
	adopt = { label = "kind.embedded", icon = "icon16/application_add.png", color = T.warning },
	postprocess = { label = "kind.widget", icon = "icon16/application_view_tile.png", color = T.accent },
	active = { label = "kind.tool", icon = "icon16/wrench_orange.png", color = T.accent },
	quick = { label = "kind.quick", icon = "icon16/lightning.png", color = T.accent },
}

-- Rows read whether they are selected when they paint, never from a snapshot (L1).
local function paintRow(row, w, h)
	local selected = PP.Batch.IsSelected(row.id)
	draw.RoundedBox(6, 0, 0, w, h, (selected or row:IsHovered()) and T.rowHover or T.card)
	surface.SetDrawColor(row.stripe)
	surface.DrawRect(0, 0, 4, h)
	if selected then
		surface.SetDrawColor(T.accent)
		surface.DrawOutlinedRect(0, 0, w, h, 1)
	end
end

-- The tick box at the left of a window's row: filled when its window is selected.
local function paintCheck(check, w, h)
	local x, y = math.floor((w - 14) / 2), math.floor((h - 14) / 2)
	local on = PP.Batch.IsSelected(check.id)
	surface.SetDrawColor(on and T.accent or T.textMuted)
	surface.DrawOutlinedRect(x, y, 14, 14, 1)
	if on then draw.RoundedBox(2, x + 3, y + 3, 8, 8, T.accent) end
end

local function paintTabRow(row, w, h)
	draw.RoundedBox(4, 0, 0, w, h, T.cardHeader)
	surface.SetDrawColor(row.stripe)
	surface.DrawRect(0, 0, 3, h)
end

local function paintEmpty(card, w, h)
	draw.RoundedBox(6, 0, 0, w, h, T.card)
	draw.RoundedBoxEx(6, 0, 0, w, 30, T.cardHeader, true, true, false, false)
	draw.SimpleText(card.texts[1], "DermaDefaultBold", 12, 15, T.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	draw.SimpleText(card.texts[2], "DermaDefault", w / 2, h / 2 + 5, T.textSubtle, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	draw.SimpleText(card.texts[3], "DermaDefault", w / 2, h / 2 + 22, T.textMuted, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end

local PAGE = {}

function PAGE:Init()
	self.expanded = {}
	self.bar = self:Add("Panel")
	self.bar:Dock(TOP)
	self.bar:SetTall(28)
	self.bar:DockMargin(16, 16, 16, 0)
	local pick = self.bar:Add("PinnedPanelsButton")
	pick:Dock(LEFT)
	pick:SetWide(220)
	pick:SetLabel(PP.L("btn.pick"))
	pick:SetIcon("icon16/application_form_add.png")
	pick:SetTooltip(PP.L("tip.pick"))
	pick.DoClick = function() PP.Picker.Open() end
	local record = self.bar:Add("PinnedPanelsButton")
	record:Dock(LEFT)
	record:DockMargin(6, 0, 0, 0)
	record:SetWide(220)
	record:SetLabel(PP.L("btn.record"))
	record:SetIcon("icon16/bullet_red.png")
	record:SetTooltip(PP.L("tip.record"))
	record.DoClick = function() PP.Record.Toggle() end

	-- Several windows at once: tick rows (Shift-click for a range), then one menu for all of them.
	-- With nothing ticked, the same menu is about every window.
	self.batch = self:Add("Panel")
	self.batch:Dock(TOP)
	self.batch:SetTall(26)
	self.batch:DockMargin(16, 8, 16, 0)
	local function batchButton(key, icon, wide, tip, fn)
		local b = self.batch:Add("PinnedPanelsButton")
		b:Dock(LEFT)
		b:DockMargin(0, 0, 6, 0)
		b:SetWide(wide)
		b:SetLabel(PP.L(key))
		b:SetIcon(icon)
		b:SetTooltip(PP.L(tip))
		b.DoClick = fn
		return b
	end
	batchButton("btn.select_all", "icon16/table_multiple.png", 100, "tip.select_all", function() PP.Batch.Set(self.order or {}) end)
	batchButton("btn.select_none", "icon16/shape_square.png", 70, "tip.select_none", function() PP.Batch.Clear() end)
	self.actions = batchButton("btn.batch_all", "icon16/cog.png", 190, "tip.batch", function()
		local ids = PP.Batch.Ids()
		PP.Actions.OpenBatchMenu(#ids > 0 and ids or PP.Batch.All())
	end)
	batchButton("act.group_category", "icon16/folder_wrench.png", 190, "tip.group_category", function()
		local ids = PP.Batch.Ids()
		local merged, groups = PP.Batch.GroupByCategory(#ids > 0 and ids or PP.Batch.All())
		notification.AddLegacy(merged > 0 and PP.L("batch.grouped", merged, groups) or PP.L("batch.grouped_none"), NOTIFY_GENERIC, 6)
	end)
	self.selectedCount = -1

	self.list = self:Add("PinnedPanelsScroll")
	self.list:Dock(FILL)
	self.list:DockMargin(16, 8, 16, 16)
	self:Rebuild()
	-- The list is made again when it is next looked at, once, however many changes there were: made
	-- again on each one, restoring sixty windows rebuilt sixty rows sixty times in a single frame, for
	-- a page nobody was looking at.
	local function stale() self.stale = true end
	hook.Add("PinnedPanelsChanged", self, function(_, kind)
		if kind ~= "geometry" then self.stale = true end
	end)
	hook.Add("PinnedPanelsCatalogChanged", self, stale)
	hook.Add("PinnedPanelsHeldChanged", self, stale)
	hook.Add("PinnedPanelsAdoptChanged", self, stale)
end

-- Think only runs while the page is visible (G4).
function PAGE:Think()
	if self.stale then
		self.stale = false
		self:Rebuild()
	end
	-- The menu button says what it is about: the ticked windows, or all of them.
	local n = PP.Batch.Count()
	if n ~= self.selectedCount then
		self.selectedCount = n
		self.actions:SetLabel(n > 0 and PP.L("btn.batch_selected", n) or PP.L("btn.batch_all"))
		self.actions:SetOn(n > 0)
	end
end

-- A click on a row's tick box, or on the row itself: that window in or out of the selection. With
-- Shift, every row from the last one clicked to this one, as that one was set.
function PAGE:Select(id)
	local on = not PP.Batch.IsSelected(id)
	if PP.Input.ShiftHeld() and self.lastSelected and self.lastSelected ~= id then
		local from, to
		for i, other in ipairs(self.order) do
			if other == self.lastSelected then from = i end
			if other == id then to = i end
		end
		if from and to then
			for i = math.min(from, to), math.max(from, to) do PP.Batch.Toggle(self.order[i], on) end
			self.lastSelected = id
			return
		end
	end
	PP.Batch.Toggle(id, on)
	self.lastSelected = id
end

-- A button docked to the right of a row, right to left in the order they are added.
local function button(row, label, icon, wide, tip, fn, danger)
	local b = row:Add("PinnedPanelsButton")
	b:Dock(RIGHT)
	b:DockMargin(0, 5, 4, 5)
	b:SetWide(wide)
	b:SetLabel(label)
	b:SetIcon(icon)
	b:SetDanger(danger)
	if tip then b:SetTooltip(PP.L(tip)) end
	b.DoClick = fn
	return b
end

function PAGE:AddWindowRow(rec)
	local kind = kindOf(rec)
	local info = KIND[kind]
	local id = rec.id
	local dormant = Desktop.IsDormant(rec)
	local adopt = #rec.tabs == 1 and rec.tabs[1].adopt

	local row = self.list:Add("DPanel")
	row:Dock(TOP)
	row:SetTall(ROW_H)
	row:DockMargin(0, 0, 0, 6)
	row.stripe = info.color
	row.id = id
	row.Paint = paintRow
	row.OnMousePressed = function(_, code)
		if code == MOUSE_LEFT then self:Select(id) end
	end

	local check = row:Add("DButton")
	check:SetText("")
	check:Dock(LEFT)
	check:SetWide(22)
	check:DockMargin(6, 0, 0, 0)
	check.id = id
	check.Paint = paintCheck
	check.DoClick = function() self:Select(id) end

	local icon = row:Add("DImage")
	icon:SetImage(info.icon)
	icon:SetSize(14, 14)
	icon:Dock(LEFT)
	icon:DockMargin(4, 13, 6, 13)

	local title = Layout.Title(rec)
	if kind == "group" then title = title .. " " .. PP.L("group.panels", #rec.tabs) end
	if rec.state == "minimized" then title = title .. " " .. PP.L("tag.minimized") end
	if Desktop.held[id] then title = title .. " " .. PP.L("tag.hidden") end
	if kind == "managed" and PP.Manage.OwnerHidden(id) then title = title .. " " .. PP.L("tag.closed_by_addon") end
	if adopt then title = title .. "  ·  " .. PP.Recipes.AddonName(adopt.signature) .. "  ·  " .. PP.Recipes.Describe(adopt) end

	if dormant then
		button(row, PP.L("btn.remove"), "icon16/cross.png", 80, adopt and "tip.remove_waiting" or "tip.remove_dormant", function() Layout.Unpin(id) end, true)
		-- A command from an imported layout runs only once the player allows it (R16).
		local r = adopt and adopt.recipe
		if r and r.kind == "command" and not r.confirmed then
			button(row, PP.L("btn.allow"), "icon16/accept.png", 70, "tip.allow", function()
				Derma_Query(PP.L("allow.query", r.args and r.command .. " " .. r.args or r.command), PP.L("allow.title"),
					PP.L("btn.allow"), function()
						Layout.SetAdopt(id, 1, { recipe = { kind = "command", command = r.command, args = r.args, confirmed = true } })
					end,
					PP.L("btn.cancel"), function() end)
			end)
		elseif adopt and PP.Recipes.CanOpen(adopt) then
			button(row, PP.L("btn.open"), "icon16/application_go.png", 70, "tip.open_adopted", function() PP.Recipes.Open(rec, rec.tabs[1]) end)
		end
	elseif #rec.tabs == 0 then
		button(row, PP.L("btn.delete"), "icon16/cross.png", 70, nil, function() Layout.Unpin(id) end, true)
	else
		if kind == "group" and #rec.tabs > 1 then
			button(row, PP.L("btn.dissolve"), "icon16/folder_delete.png", 76, "tip.dissolve", function() Layout.Dissolve(id) end, true)
			button(row, PP.L("btn.unpin_all_s"), "icon16/cross.png", 80, "tip.unpin_all_g", function() Layout.ClearTabs(id) end, true)
			button(row, PP.L("btn.members"), "icon16/folder_explore.png", 86, "tip.members", function()
				self.expanded[id] = not self.expanded[id]
				self:Rebuild()
			end)
		else
			button(row, PP.L("btn.unpin"), "icon16/cross.png", 70, "tip.unpin_simple", function() Layout.Unpin(id) end, true)
			if kind ~= "managed" then
				button(row, PP.L("btn.group"), "icon16/folder_go.png", 70, "tip.add_group", function() PP.Actions.OpenChildren("group", id) end)
			end
		end
		button(row, PP.L("btn.move_front"), "icon16/shape_move_front.png", 104, "tip.move_front", function() Desktop.RestoreAndFront(id) end)
		if Desktop.held[id] then
			button(row, PP.L("btn.show"), "icon16/eye.png", 74, "tip.show_panel", function() Desktop.Show(id) end)
		elseif rec.state == "minimized" then
			button(row, PP.L("btn.restore"), "icon16/arrow_up.png", 74, "tip.restore_tb", function() Desktop.RestoreAndFront(id) end)
		else
			button(row, PP.L("btn.minimize"), "icon16/application_put.png", 84, "tip.minimize_panel", function() Layout.Minimize(id) end)
		end
	end

	local kindLabel = row:Add("DLabel")
	kindLabel:Dock(RIGHT)
	kindLabel:SetWide(dormant and 90 or 50)
	kindLabel:DockMargin(0, 0, 6, 0)
	kindLabel:SetContentAlignment(6)
	kindLabel:SetText(dormant and PP.L(adopt and "tag.waiting" or "tag.unavailable") or PP.L(info.label))
	kindLabel:SetTextColor(dormant and T.danger or info.color)

	local label = row:Add("DLabel")
	label:Dock(FILL)
	label:SetFont("DermaDefaultBold")
	label:SetTextColor(dormant and T.textMuted or T.text)
	label:SetText(title)

	if self.expanded[id] and #rec.tabs > 1 then
		for i, tab in ipairs(rec.tabs) do self:AddTabRow(rec, i, tab) end
	end
end

function PAGE:AddTabRow(rec, i, tab)
	local id = rec.id
	local row = self.list:Add("DPanel")
	row:Dock(TOP)
	row:SetTall(TAB_ROW_H)
	row:DockMargin(26, 0, 0, 4)
	row.stripe = rec.accent or T.groupAccent
	row.Paint = paintTabRow

	button(row, PP.L("btn.unpin"), "icon16/cross.png", 64, "tip.unpin_member", function() Layout.UnpinTab(id, i) end, true)
	button(row, PP.L("btn.ungroup"), "icon16/folder_delete.png", 76, "tip.ungroup_mem", function() Layout.MoveTab(id, i, nil) end)
	local down = button(row, "", "icon16/arrow_down.png", 26, "tip.move_down", function() Layout.MoveTab(id, i, id, i + 1) end)
	local up = button(row, "", "icon16/arrow_up.png", 26, "tip.move_up", function() Layout.MoveTab(id, i, id, i - 1) end)
	down:SetEnabled(i < #rec.tabs)
	up:SetEnabled(i > 1)
	if tab.adopt and not PP.Recipes.IsLive(rec, tab) and PP.Recipes.CanOpen(tab.adopt) then
		button(row, PP.L("btn.open"), "icon16/application_go.png", 64, "tip.open_adopted", function() PP.Recipes.Open(rec, tab) end)
	end

	local available = Sources.Get(tab.src) ~= nil
	local label = row:Add("DLabel")
	label:Dock(FILL)
	label:DockMargin(10, 0, 0, 0)
	label:SetTextColor(available and T.text or T.textMuted)
	local title = Layout.TabTitle(tab)
	label:SetText(i .. ". " .. (available and title or PP.L("member.missing", title)))
end

function PAGE:Rebuild()
	self.list:Clear()
	self.order = {}
	local windows = {}
	for _, rec in ipairs(Layout.Windows()) do windows[#windows + 1] = rec end
	if #windows == 0 then
		local empty = self.list:Add("DPanel")
		empty:Dock(TOP)
		empty:SetTall(110)
		empty.texts = { PP.L("no.pinned"), PP.L("no.pinned_desc"), PP.L("no.pinned_hint") }
		empty.Paint = paintEmpty
		return
	end
	table.sort(windows, function(a, b)
		local ta, tb = PP.Util.SortKey(Layout.Title(a)), PP.Util.SortKey(Layout.Title(b))
		if ta ~= tb then return ta < tb end
		return a.id < b.id
	end)
	for i, rec in ipairs(windows) do
		self.order[i] = rec.id
		self:AddWindowRow(rec)
	end
end

function PAGE:Paint(w, h)
	draw.RoundedBox(0, 0, 0, w, h, T.bg)
end

vgui.Register("PinnedPanelsPinned", PAGE, "DPanel")
