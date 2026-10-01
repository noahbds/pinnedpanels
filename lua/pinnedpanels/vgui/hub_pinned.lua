-- The hub's Pinned page (F4): every window, including hidden, minimized, dormant (its addon isn't loaded,
-- E1), waiting (an adopted panel that isn't open, §33.9) and empty named groups. Multi-tab windows expand
-- to their tabs. The page only calls Layout, Desktop and Actions; it never changes the document itself (L26).

local PP = PinnedPanels
local Layout, Sources, Desktop, T = PP.Layout, PP.Sources, PP.Desktop, PP.Theme

local ROW_H, TAB_ROW_H = 40, 30

local function kindOf(rec)
	if rec.title or #rec.tabs > 1 then return "group" end
	return rec.tabs[1].src:match("^(%a+):") or "tool"
end

local KIND = {
	group = { label = "kind.group", icon = "icon16/folder.png", color = T.success },
	creation = { label = "kind.content", icon = "icon16/application_view_list.png", color = T.success },
	tool = { label = "kind.tool", icon = "icon16/wrench.png", color = T.accent },
	adopt = { label = "kind.embedded", icon = "icon16/application_add.png", color = T.warning },
	postprocess = { label = "kind.widget", icon = "icon16/application_view_tile.png", color = T.accent },
	active = { label = "kind.tool", icon = "icon16/wrench_orange.png", color = T.accent },
	quick = { label = "kind.quick", icon = "icon16/lightning.png", color = T.accent },
}

local function paintRow(row, w, h)
	draw.RoundedBox(6, 0, 0, w, h, row:IsHovered() and T.rowHover or T.card)
	surface.SetDrawColor(row.stripe)
	surface.DrawRect(0, 0, 4, h)
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

	self.list = self:Add("PinnedPanelsScroll")
	self.list:Dock(FILL)
	self.list:DockMargin(16, 8, 16, 16)
	self:Rebuild()
	hook.Add("PinnedPanelsChanged", self, function(_, kind)
		if kind ~= "geometry" then self:Rebuild() end
	end)
	hook.Add("PinnedPanelsCatalogChanged", self, self.Rebuild)
	hook.Add("PinnedPanelsHeldChanged", self, self.Rebuild)
	hook.Add("PinnedPanelsAdoptChanged", self, self.Rebuild)
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
	row.Paint = paintRow

	local icon = row:Add("DImage")
	icon:SetImage(info.icon)
	icon:SetSize(14, 14)
	icon:Dock(LEFT)
	icon:DockMargin(10, 13, 6, 13)

	local title = Layout.Title(rec)
	if kind == "group" then title = title .. " " .. PP.L("group.panels", #rec.tabs) end
	if rec.state == "minimized" then title = title .. " " .. PP.L("tag.minimized") end
	if Desktop.held[id] then title = title .. " " .. PP.L("tag.hidden") end
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
			button(row, PP.L("btn.group"), "icon16/folder_go.png", 70, "tip.add_group", function() PP.Actions.OpenChildren("group", id) end)
		end
		button(row, PP.L("btn.move_front"), "icon16/shape_move_front.png", 104, "tip.move_front", function() Desktop.RestoreAndFront(id) end)
		if Desktop.held[id] then
			button(row, PP.L("btn.show"), "icon16/eye.png", 74, "tip.show_panel", function() Desktop.Show(id) end)
		elseif rec.state == "minimized" then
			button(row, PP.L("btn.restore"), "icon16/arrow_up.png", 74, "tip.restore_tb", function() Desktop.RestoreAndFront(id) end)
		else
			button(row, PP.L("btn.hide"), "icon16/eye.png", 74, "tip.hide_panel", function() Desktop.Hide(id) end)
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
	table.sort(windows, function(a, b) return Layout.Title(a):lower() < Layout.Title(b):lower() end)
	for _, rec in ipairs(windows) do self:AddWindowRow(rec) end
end

function PAGE:Paint(w, h)
	draw.RoundedBox(0, 0, 0, w, h, T.bg)
end

vgui.Register("PinnedPanelsPinned", PAGE, "DPanel")
