-- The hub's Settings page (F6, §21.3). Rows are generated from the setting declarations and bound to their
-- convars the stock way (G3); key rows use the key dialog with conflicts (F26). Hand-written parts: the
-- colour preview, Groups, and Data (export, import with a preview and confirm, undo, E34, R3).

local PP = PinnedPanels
local Layout, Settings, Storage, Desktop, Sources, Input, T = PP.Layout, PP.Settings, PP.Storage, PP.Desktop, PP.Sources, PP.Input, PP.Theme

local SECTION_TITLES = {
	["general.behavior"] = "card.behavior", ["general.snapping"] = "card.snapping",
	["appearance.colors"] = "card.panel_colors",
	["taskbar.taskbar"] = "card.taskbar", ["taskbar.colors"] = "card.taskbar_colors",
}

-- The layout before the last import, for "Undo import" (session only).
local undoImport

-- ── Building blocks ─────────────────────────────────────────

local function paintCard(card, w, h)
	draw.RoundedBox(6, 0, 0, w, h, T.card)
	draw.RoundedBoxEx(6, 0, 0, w, 30, T.cardHeader, true, true, false, false)
	draw.SimpleText(card.title, "DermaDefaultBold", 12, 15, T.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
end

-- A titled card that grows to fit its docked rows.
local function layoutCard(card)
	local _, _, _, bottom = card:GetDockPadding()
	local tall = 0
	for _, c in ipairs(card:GetChildren()) do
		if c:IsVisible() then
			local _, y = c:GetPos()
			tall = math.max(tall, y + c:GetTall())
		end
	end
	if card:GetTall() ~= tall + bottom then card:SetTall(tall + bottom) end
end

local function card(parent, titleKey)
	local c = parent:Add("DPanel")
	c:Dock(TOP)
	c:DockMargin(0, 0, 0, 12)
	c:DockPadding(16, 42, 16, 14)
	c.title = PP.L(titleKey)
	c.Paint = paintCard
	c.PerformLayout = layoutCard
	return c
end

local function help(parent, key)
	local label = parent:Add("DLabel")
	label:Dock(TOP)
	label:DockMargin(0, 0, 0, 10)
	label:SetWrap(true)
	label:SetAutoStretchVertical(true)
	label:SetTextColor(T.textSubtle)
	label:SetText(PP.L(key))
	return label
end

local function row(parent, tall)
	local r = parent:Add("Panel")
	r:Dock(TOP)
	r:SetTall(tall or 28)
	r:DockMargin(0, 0, 0, 6)
	return r
end

local function button(parent, labelKey, icon, wide, fn)
	local b = parent:Add("PinnedPanelsButton")
	b:Dock(LEFT)
	b:SetWide(wide)
	b:DockMargin(0, 0, 6, 0)
	b:SetLabel(PP.L(labelKey))
	b:SetIcon(icon)
	b.DoClick = fn
	return b
end

local function keyName(key)
	if not key or key == KEY_NONE then return PP.L("key.not_bound") end
	return string.upper(input.GetKeyName(key) or "?")
end

local function colorText(c)
	return string.format("R:%d G:%d B:%d A:%d", c.r, c.g, c.b, c.a)
end

-- ── Setting rows ────────────────────────────────────────────

local ROWS = {}

function ROWS.bool(page, parent, def)
	local box = parent:Add("DCheckBoxLabel")
	box:Dock(TOP)
	box:DockMargin(0, 0, 0, 10)
	box:SetText(PP.L(def.label))
	box:SetTextColor(T.text)
	box:SetConVar(def.convar)
end

function ROWS.int(page, parent, def)
	local slider = parent:Add("DNumSlider")
	slider:Dock(TOP)
	slider:SetTall(30)
	slider:DockMargin(0, 0, 0, 8)
	slider:SetText(PP.L(def.label))
	slider:SetMin(def.min)
	slider:SetMax(def.max)
	slider:SetDecimals(0)
	slider:SetConVar(def.convar)
	slider.Label:SetTextColor(T.text)
end

function ROWS.enum(page, parent, def)
	local r = row(parent)
	local label = r:Add("DLabel")
	label:Dock(LEFT)
	label:SetWide(120)
	label:SetTextColor(T.textLabel)
	label:SetText(PP.L(def.label))
	local combo = r:Add("DComboBox")
	combo:Dock(FILL)
	for _, v in ipairs(def.values) do combo:AddChoice(PP.L(def.choices[v]), v, Settings.Get(def.key) == v) end
	combo.OnSelect = function(_, _, _, value) Settings.Set(def.key, value) end
end

-- A swatch that opens a colour mixer beside it; the value text follows the setting.
function ROWS.color(page, parent, def)
	local r = row(parent)
	local label = r:Add("DLabel")
	label:Dock(LEFT)
	label:SetWide(120)
	label:SetTextColor(T.textLabel)
	label:SetText(PP.L(def.label))

	local swatch = r:Add("DButton")
	swatch:Dock(LEFT)
	swatch:SetWide(40)
	swatch:DockMargin(0, 3, 8, 3)
	swatch:SetText("")
	swatch.Paint = function(self, w, h)
		draw.RoundedBox(4, 0, 0, w, h, Settings.Get(def.key))
		surface.SetDrawColor(self:IsHovered() and T.accent or T.buttonOutline)
		surface.DrawOutlinedRect(0, 0, w, h, 1)
	end

	local value = r:Add("DLabel")
	value:Dock(FILL)
	value:SetTextColor(T.textMuted)
	value:SetText(colorText(Settings.Get(def.key)))
	hook.Add("PinnedPanelsSettingChanged", value, function(_, key, v)
		if key == def.key then value:SetText(colorText(v)) end
	end)

	swatch.DoClick = function()
		if IsValid(page.popups[def.key]) then
			page.popups[def.key]:Remove()
			return
		end
		local popup = vgui.Create("DFrame")
		popup:SetTitle(def.page == "taskbar" and PP.L("taskbar.color_pfx", PP.L(def.label)) or PP.L(def.label))
		popup:SetSize(260, 220)
		local sx, sy = swatch:LocalToScreen(0, 0)
		popup:SetPos(math.Clamp(sx + 50, 0, ScrW() - 260), math.Clamp(sy - 60, 0, ScrH() - 220))
		popup:MakePopup()
		popup:SetKeyboardInputEnabled(false)
		popup.ppTakesKeyboard = true
		local mixer = popup:Add("DColorMixer")
		mixer:Dock(FILL)
		mixer:SetPalette(false)
		mixer:SetAlphaBar(true)
		mixer:SetWangs(true)
		mixer:SetColor(Settings.Get(def.key))
		mixer.ValueChanged = function(_, c) Settings.Set(def.key, Color(c.r, c.g, c.b, c.a)) end
		page.popups[def.key] = popup
	end
end

-- A key: its action's (or navigation's) name, the current key, Bind (with conflicts), Clear and Reset.
function ROWS.key(page, parent, def)
	local action = def.action and PP.Actions.byId[def.action]
	local title = action and PP.Actions.Name(action) or PP.L(def.label)
	local r = row(parent, 26)
	r.Paint = function(_, w, h) draw.RoundedBox(4, 0, 0, w, h, T.cardHeader) end

	local name = r:Add("DLabel")
	name:Dock(LEFT)
	name:DockMargin(8, 0, 0, 0)
	name:SetWide(220)
	name:SetTextColor(T.text)
	name:SetText(title)

	local key = r:Add("DLabel")
	key:Dock(LEFT)
	key:SetWide(100)
	key:SetContentAlignment(5)
	local function update()
		local k = Settings.Get(def.key)
		key:SetText(keyName(k))
		key:SetTextColor(k ~= KEY_NONE and T.success or T.textMuted)
	end
	update()
	hook.Add("PinnedPanelsSettingChanged", key, function(_, changed)
		if changed == def.key then update() end
	end)

	local function small(labelKey, fn)
		local b = r:Add("PinnedPanelsButton")
		b:Dock(RIGHT)
		b:SetWide(58)
		b:DockMargin(0, 3, 4, 3)
		b:SetLabel(PP.L(labelKey))
		b.DoClick = fn
	end
	small("btn.reset", function() Settings.Reset(def.key) end)
	small("btn.unbind", function() Settings.Set(def.key, KEY_NONE) end)
	small("btn.bind", function()
		PP.Dialogs.Key({
			title = PP.L("bind.prefix", title),
			get = function() return Settings.Get(def.key) end,
			set = function(k) Settings.Set(def.key, k) end,
			tag = action and "action:" .. action.id or "setting:" .. def.key,
		})
	end)
end

-- Every declared setting of a page (and section), in declaration order.
local function settingsOf(pageId, section)
	local out = {}
	for _, key in ipairs(Settings.order) do
		local def = Settings.defs[key]
		if def.page == pageId and (not section or def.section == section) then out[#out + 1] = def end
	end
	return out
end

local function addRows(page, parent, pageId, section)
	for _, def in ipairs(settingsOf(pageId, section)) do ROWS[def.type](page, parent, def) end
end

local function resetButton(parent, labelKey, pageId, section)
	local r = row(parent, 30)
	r:DockMargin(0, 8, 0, 0)
	button(r, labelKey, "icon16/arrow_undo.png", 180, function()
		for _, def in ipairs(settingsOf(pageId, section)) do Settings.Reset(def.key) end
	end)
end

local function sectionCard(page, parent, pageId, section, resetKey)
	local c = card(parent, SECTION_TITLES[pageId .. "." .. section])
	addRows(page, c, pageId, section)
	if resetKey then resetButton(c, resetKey, pageId, section) end
	return c
end

-- ── Pages ───────────────────────────────────────────────────

local PAGES = {}

PAGES[#PAGES + 1] = { id = "general", label = "page.general", icon = "icon16/cog.png", build = function(page, parent)
	sectionCard(page, parent, "general", "behavior")
	sectionCard(page, parent, "general", "snapping")
end }

-- As v1: cursor mode, peek and the palette each get a card with their help, then navigation, then the
-- other actions.
local OWN_CARD = { keyCursor = true, keyPeek = true, keyPalette = true }

local function keyCard(page, parent, titleKey, helpKey, setting)
	local c = card(parent, titleKey)
	help(c, helpKey)
	ROWS.key(page, c, Settings.defs[setting])
	return c
end

PAGES[#PAGES + 1] = { id = "controls", label = "page.controls", icon = "icon16/keyboard.png", build = function(page, parent)
	local cursor = keyCard(page, parent, "card.cursor_mode", "help.cursor_mode", "keyCursor")
	local r = row(cursor, 30)
	r:DockMargin(0, 8, 0, 0)
	button(r, "btn.toggle_now", "icon16/cursor.png", 130, function() Input.SetCursorMode(not Input.cursorMode) end)

	keyCard(page, parent, "card.peek", "help.peek", "keyPeek")

	local palette = keyCard(page, parent, "card.palette", "help.palette", "keyPalette")
	r = row(palette, 30)
	r:DockMargin(0, 8, 0, 0)
	button(r, "btn.open_now", "icon16/application_view_list.png", 130, function() PP.Palette.Toggle() end)

	local nav = card(parent, "card.kbnav")
	help(nav, "help.kbnav")
	addRows(page, nav, "controls", "nav")

	local c = card(parent, "card.keys")
	help(c, "help.keys")
	for _, def in ipairs(settingsOf("controls")) do
		if not def.section and not OWN_CARD[def.key] then ROWS.key(page, c, def) end
	end
	r = row(c, 30)
	r:DockMargin(0, 8, 0, 0)
	button(r, "btn.reset_all_def", "icon16/arrow_undo.png", 170, function()
		for _, def in ipairs(settingsOf("controls")) do Settings.Reset(def.key) end
	end)
end }

local previewHint = Color(0, 0, 0, 120)

local function paintPreview(p, w, h)
	local bg, header, text = Settings.Get("colorBg"), Settings.Get("colorHeader"), Settings.Get("colorText")
	draw.RoundedBox(6, 0, 0, w, h, bg)
	draw.RoundedBoxEx(6, 0, 0, w, 26, header, true, true, false, false)
	draw.SimpleText(p.title, "DermaDefaultBold", 10, 13, text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	previewHint.r, previewHint.g, previewHint.b = text.r, text.g, text.b
	draw.SimpleText(p.hint, "DermaDefault", 10, h - 10, previewHint, TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM)
end

PAGES[#PAGES + 1] = { id = "appearance", label = "page.appearance", icon = "icon16/palette.png", build = function(page, parent)
	sectionCard(page, parent, "appearance", "colors", "btn.reset_default")
	local c = card(parent, "card.live_preview")
	local preview = c:Add("DPanel")
	preview:Dock(TOP)
	preview:SetTall(84)
	preview.title, preview.hint = PP.L("preview.title"), PP.L("preview.hint")
	preview.Paint = paintPreview
end }

PAGES[#PAGES + 1] = { id = "taskbar", label = "page.taskbar", icon = "icon16/application_put.png", build = function(page, parent)
	sectionCard(page, parent, "taskbar", "taskbar")
	local c = sectionCard(page, parent, "taskbar", "colors")
	local r = row(c, 30)
	r:DockMargin(0, 8, 0, 0)
	button(r, "btn.reset_taskbar", "icon16/arrow_undo.png", 190, function()
		for _, def in ipairs(settingsOf("taskbar")) do Settings.Reset(def.key) end
	end)
end }

-- Named groups are windows with a title (§13.1).
PAGES[#PAGES + 1] = { id = "groups", label = "page.groups", icon = "icon16/folder.png", build = function(page, parent)
	local c = card(parent, "card.panel_groups")
	help(c, "help.groups")
	local list = c:Add("Panel")
	list:Dock(TOP)

	local function fill()
		list:Clear()
		local n = 0
		for _, rec in ipairs(Layout.Windows()) do
			if rec.title then
				n = n + 1
				local r = row(list, 28)
				r:DockMargin(0, 0, 0, 2)
				r.stripe = rec.accent or T.groupAccent
				r.Paint = function(self, w, h)
					draw.RoundedBox(4, 0, 0, w, h, T.cardHeader)
					surface.SetDrawColor(self.stripe)
					surface.DrawRect(0, 0, 4, h)
				end
				local del = r:Add("PinnedPanelsButton")
				del:Dock(RIGHT)
				del:SetWide(64)
				del:DockMargin(0, 3, 4, 3)
				del:SetLabel(PP.L("btn.delete"))
				del:SetDanger(true)
				local id = rec.id
				del.DoClick = function() Layout.Unpin(id) end
				local label = r:Add("DLabel")
				label:Dock(FILL)
				label:DockMargin(10, 0, 0, 0)
				label:SetTextColor(T.text)
				label:SetText(PP.L("group.row_count", rec.title, #rec.tabs))
			end
		end
		if n == 0 then
			local label = list:Add("DLabel")
			label:Dock(TOP)
			label:SetTextColor(T.textMuted)
			label:SetText(PP.L("groups.none"))
			n = 1
		end
		list:SetTall(n * 30)
		c:InvalidateLayout()
	end
	fill()
	hook.Add("PinnedPanelsChanged", list, function(_, kind)
		if kind == "windows" or kind == "tabs" or kind == "style" then fill() end
	end)

	local r = row(c, 28)
	r:DockMargin(0, 6, 0, 0)
	button(r, "ctx.new_group", "icon16/folder_add.png", 130, function()
		PP.Dialogs.Text(PP.L("new.group_title"), PP.L("new.group_desc"), "", function(name) Layout.NewGroup(name) end)
	end)
end }

-- ── Data: export, import with preview, undo ─────────────────

local function codeDialog(titleKey)
	local frame = vgui.Create("DFrame")
	frame:SetTitle(PP.L(titleKey))
	frame:SetSize(480, 280)
	frame:Center()
	frame:MakePopup()
	local bar = frame:Add("Panel")
	bar:Dock(BOTTOM)
	bar:SetTall(30)
	bar:DockMargin(0, 6, 0, 0)
	local entry = frame:Add("DTextEntry")
	entry:Dock(FILL)
	entry:SetMultiline(true)
	return frame, entry, bar
end

local function openExport()
	if #Layout.Windows() == 0 then
		Derma_Message(PP.L("export.nothing"), PP.L("export.title"), PP.L("btn.ok"))
		return
	end
	local code = Storage.Export(Layout.Document())
	SetClipboardText(code) -- G37
	local frame, entry, bar = codeDialog("export.title")
	entry:SetText(code)
	local hint = bar:Add("DLabel")
	hint:Dock(FILL)
	hint:SetTextColor(T.textMuted)
	hint:SetText(PP.L("export.copied") .. "  " .. PP.L("code.hint"))
	return frame
end

-- Imports replace the layout only after a preview and a confirm; the current layout is kept for undo and,
-- through the next write, as the backup file (R3, E34).
local function applyImport(doc, page)
	undoImport = Storage.Sanitize(Storage.Encode(Layout.Document()))
	Layout.Replace(doc)
	Desktop.ShowHeld()
	page:ShowPage("data")
	notification.AddLegacy(PP.L("import.success"), NOTIFY_GENERIC, 5)
end

local function openImport(page)
	local frame, entry, bar = codeDialog("import.title")
	local summary = bar:Add("DLabel")
	summary:Dock(FILL)
	summary:DockMargin(4, 0, 4, 0)
	local confirm = bar:Add("PinnedPanelsButton")
	confirm:Dock(RIGHT)
	confirm:SetWide(110)
	confirm:SetLabel(PP.L("btn.import_reload"))
	confirm:SetEnabled(false)
	local preview = bar:Add("PinnedPanelsButton")
	preview:Dock(RIGHT)
	preview:SetWide(90)
	preview:DockMargin(0, 0, 6, 0)
	preview:SetLabel(PP.L("import.preview"))

	local doc
	entry.OnChange = function()
		doc = nil
		confirm:SetEnabled(false)
		summary:SetText("")
	end
	preview.DoClick = function()
		local result, info = Storage.Import(entry:GetValue())
		if not result then
			summary:SetTextColor(T.danger)
			summary:SetText(PP.L("import.failed", PP.L(info)))
			return
		end
		local unavailable = 0
		for _, w in ipairs(result.windows) do
			for _, t in ipairs(w.tabs) do
				if not Sources.Get(t.src) then unavailable = unavailable + 1 end
			end
		end
		doc = result
		summary:SetTextColor(T.success)
		summary:SetText(PP.L("import.summary", info.windows, info.tabs, unavailable))
		confirm:SetEnabled(true)
	end
	confirm.DoClick = function()
		if not doc then return end
		frame:Close()
		applyImport(doc, page)
	end
	entry:RequestFocus()
end

PAGES[#PAGES + 1] = { id = "data", label = "page.data", icon = "icon16/disk.png", build = function(page, parent)
	local c = card(parent, "card.backup")
	help(c, "help.backup")
	local r = row(c, 30)
	button(r, "btn.export", "icon16/page_white_get.png", 150, openExport)
	button(r, "btn.import", "icon16/page_white_put.png", 150, function() openImport(page) end)
	if undoImport then
		button(r, "btn.undo_import", "icon16/arrow_undo.png", 140, function()
			local doc = undoImport
			undoImport = nil
			Layout.Replace(doc)
			Desktop.ShowHeld()
			page:ShowPage("data")
		end)
	end

	local danger = card(parent, "card.danger")
	local unpin = danger:Add("PinnedPanelsButton")
	unpin:Dock(TOP)
	unpin:SetTall(30)
	unpin:SetDanger(true)
	unpin:SetLabel(PP.L("btn.unpin_all"))
	unpin.DoClick = function() PP.Actions.Run("unpin_all") end
end }

-- ── Page shell ──────────────────────────────────────────────

local SETTINGS = {}

function SETTINGS:Init()
	self.popups = {}
	self.nav = self:Add("DPanel")
	self.nav:Dock(LEFT)
	self.nav:SetWide(150)
	self.nav:DockPadding(0, 8, 0, 8)
	self.nav.Paint = function(_, w, h)
		draw.RoundedBox(0, 0, 0, w, h, T.bgDarker)
		surface.SetDrawColor(T.headerLine)
		surface.DrawRect(w - 1, 0, 1, h)
	end
	self.content = self:Add("PinnedPanelsScroll")
	self.content:Dock(FILL)
	self.content:DockMargin(16, 16, 16, 16)

	for _, p in ipairs(PAGES) do
		local b = self.nav:Add("DButton")
		b:Dock(TOP)
		b:SetTall(34)
		b:DockMargin(8, 2, 8, 0)
		b:SetText("")
		b.pageId, b.label, b.icon = p.id, PP.L(p.label), T.Icon(p.icon)
		b.Paint = function(btn, w, h)
			local active = self.pageId == btn.pageId
			if active then
				draw.RoundedBox(4, 0, 0, w, h, T.card)
				surface.SetDrawColor(T.accent)
				surface.DrawRect(0, 6, 2, h - 12)
			elseif btn:IsHovered() then
				draw.RoundedBox(4, 0, 0, w, h, T.hover)
			end
			surface.SetMaterial(btn.icon)
			surface.SetDrawColor(255, 255, 255, 255)
			surface.DrawTexturedRect(10, 9, 16, 16)
			draw.SimpleText(btn.label, "DermaDefault", 34, h / 2, active and T.textBright or T.textSubtle, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		end
		b.DoClick = function() self:ShowPage(p.id) end
	end
	self:ShowPage(PAGES[1].id)
end

function SETTINGS:ClosePopups()
	for key, popup in pairs(self.popups) do
		if IsValid(popup) then popup:Remove() end
		self.popups[key] = nil
	end
end

function SETTINGS:ShowPage(id)
	self:ClosePopups()
	self.pageId = id
	self.content:Clear()
	for _, p in ipairs(PAGES) do
		if p.id == id then p.build(self, self.content) end
	end
end

function SETTINGS:OnRemove()
	self:ClosePopups()
end

function SETTINGS:Paint(w, h)
	draw.RoundedBox(0, 0, 0, w, h, T.bg)
end

vgui.Register("PinnedPanelsSettings", SETTINGS, "DPanel")
