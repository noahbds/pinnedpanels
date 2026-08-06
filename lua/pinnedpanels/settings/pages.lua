local C = PinnedPanels.C
local SUI = PinnedPanels.SettingsUI

-- ── Settings Pages ───────────────────────────────────────────────────────────

-- ── General ──────────────────────────────────────────────────────────────────
local function BuildGeneral(parent, ctx)
	local secBehavior = SUI.Card(parent, PinnedPanels.L("card_behavior"))

	SUI.CheckRow(secBehavior, PinnedPanels.L("opt_autorestore"),
		PinnedPanels.Settings.autoRestore, function(val)
			PinnedPanels.Settings.autoRestore = val
		end)

	SUI.CheckRow(secBehavior, PinnedPanels.L("opt_kbnav_outside"),
		PinnedPanels.Settings.keyboardNavOutsideCursorMode, function(val)
			PinnedPanels.Settings.keyboardNavOutsideCursorMode = val
		end)

	SUI.SliderRow(secBehavior, {
		label     = PinnedPanels.L("opt_idle_alpha"),
		min       = 10,
		max       = 100,
		value     = math.Round((PinnedPanels.Settings.idleAlpha or 1) * 100),
		saveTimer = "PinnedPanels_IdleAlphaSave",
		onChange  = function(val)
			PinnedPanels.Settings.idleAlpha = math.Clamp(val, 10, 100) / 100
			if PinnedPanels.UpdatePanelStates then PinnedPanels.UpdatePanelStates() end
		end,
	})

	local secSnap = SUI.Card(parent, PinnedPanels.L("card_snapping"))

	local snapBox = SUI.CheckRow(secSnap,
		PinnedPanels.L("opt_snap"),
		PinnedPanels.Settings.snapEnabled ~= false, function(val)
			PinnedPanels.Settings.snapEnabled = val
		end)
	snapBox:SetWrap(true)
	snapBox:SetTall(34)

	SUI.SliderRow(secSnap, {
		label     = PinnedPanels.L("opt_snap_dist"),
		min       = 0,
		max       = 40,
		value     = PinnedPanels.Settings.snapDistance or 12,
		saveTimer = "PinnedPanels_SnapSave",
		onChange  = function(val)
			PinnedPanels.Settings.snapDistance = math.Clamp(val, 0, 64)
		end,
	})

	-- Language switcher
	local secLang = SUI.Card(parent, PinnedPanels.L("card_language"))

	local langRow = SUI.Row(secLang, 28)

	local langLbl = vgui.Create("DLabel", langRow)
	langLbl:SetText(PinnedPanels.L("opt_language"))
	langLbl:SetTextColor(C.textLabel)
	langLbl:Dock(LEFT)
	langLbl:SetWide(120)
	langLbl:SetContentAlignment(4)

	local langCombo = vgui.Create("DComboBox", langRow)
	langCombo:Dock(FILL)

	local langNames = {
		en = "English",
		de = "Deutsch",
		es = "Español",
		fr = "Français",
		pl = "Polski",
		pt = "Português",
		ru = "Русский",
		tr = "Türkçe",
		zh = "中文",
	}

	local supported = { "en", "de", "es", "fr", "pl", "pt", "ru", "tr", "zh" }

	local function GameLangName()
		local cv   = GetConVar("gmod_language")
		local raw  = string.lower(cv and cv:GetString() or "en")
		local base = string.match(raw, "^(%a+)") or "en"
		local code = PinnedPanels.Lang[raw] and raw
			or (PinnedPanels.Lang[base] and base) or "en"
		return langNames[code] or code
	end

	local DEFAULT_DATA = ""
	local override     = PinnedPanels.Settings.language
	local hasOverride  = isstring(override) and override ~= "" and PinnedPanels.Lang[override] ~= nil

	langCombo:AddChoice(PinnedPanels.Lf("opt_language_default", GameLangName()),
		DEFAULT_DATA, not hasOverride)

	for _, code in ipairs(supported) do
		langCombo:AddChoice(langNames[code] or code, code, hasOverride and code == override)
	end

	langCombo.OnSelect = function(_, _, _, data)
		if data == nil or data == DEFAULT_DATA then
			PinnedPanels.SetLanguage(nil)
		else
			PinnedPanels.SetLanguage(data)
		end
	end
end

-- ── Controls & Keys ──────────────────────────────────────────────────────────
local function BuildControls(parent, ctx)
	local secInteract = SUI.Card(parent, PinnedPanels.L("card_cursor_mode"))

	SUI.Help(secInteract, PinnedPanels.L("help_cursor_mode"))

	SUI.KeyControlRow(secInteract, {
		bindTitle  = PinnedPanels.L("bind_interact"),
		get        = function() return PinnedPanels.CursorMode.KeyCode end,
		set        = function(k)
			PinnedPanels.CursorMode.KeyCode = k
			RunConsoleCommand("pp_interact_key", tostring(k))
		end,
		ignore     = "cursor",
		extraText  = PinnedPanels.L("btn_toggle_now"),
		extraIcon  = "icon16/cursor.png",
		extraClick = function() PinnedPanels.CursorMode.Toggle() end,
	})

	local secPeek = SUI.Card(parent, PinnedPanels.L("card_peek"))

	SUI.Help(secPeek, PinnedPanels.L("help_peek"))

	SUI.KeyControlRow(secPeek, {
		bindTitle = PinnedPanels.L("bind_peek"),
		get       = function() return PinnedPanels.GetPeekKey and PinnedPanels.GetPeekKey() or KEY_NONE end,
		set       = function(k) PinnedPanels.SetPeekKey(k) end,
		ignore    = "peek",
	})

	local secPalette = SUI.Card(parent, PinnedPanels.L("card_palette"))

	SUI.Help(secPalette, PinnedPanels.L("help_palette"))

	SUI.KeyControlRow(secPalette, {
		bindTitle  = PinnedPanels.L("bind_palette"),
		get        = function() return PinnedPanels.GetPaletteKey and PinnedPanels.GetPaletteKey() or KEY_NONE end,
		set        = function(k) PinnedPanels.SetPaletteKey(k) end,
		ignore     = "palette",
		extraText  = PinnedPanels.L("btn_open_now"),
		extraIcon  = "icon16/application_view_list.png",
		extraClick = function() PinnedPanels.OpenCommandPalette() end,
	})

	local secKeys = SUI.Card(parent, PinnedPanels.L("card_kbnav"))

	SUI.Help(secKeys, PinnedPanels.L("help_kbnav"))

	local function KeyName(code)
		if not code or code == KEY_NONE then return PinnedPanels.L("key_not_bound") end
		return string.upper(input.GetKeyName(code) or "?")
	end

	local keyRefreshers = {}

	for _, bind in ipairs(PinnedPanels.Keybinds or {}) do
		local row = vgui.Create("DPanel", secKeys)
		row:Dock(TOP)
		row:SetTall(26)
		row:DockMargin(0, 0, 0, 4)
		row.Paint = function(_, w, h)
			draw.RoundedBox(4, 0, 0, w, h, C.bgCardHdr)
		end

		local nameLbl = vgui.Create("DLabel", row)
		nameLbl:SetText(bind.name)
		nameLbl:SetTextColor(C.textLight)
		nameLbl:Dock(LEFT)
		nameLbl:DockMargin(8, 0, 0, 0)
		nameLbl:SetWide(200)
		nameLbl:SetMouseInputEnabled(false)

		local keyLbl = vgui.Create("DLabel", row)
		keyLbl:Dock(LEFT)
		keyLbl:SetWide(90)
		keyLbl:SetContentAlignment(5)

		local function UpdateKey()
			if not IsValid(keyLbl) then return end
			local code = PinnedPanels.GetBind(bind.id)
			keyLbl:SetText(KeyName(code))
			keyLbl:SetTextColor((code and code ~= KEY_NONE) and C.keyBound or C.textMuted)
		end
		UpdateKey()
		keyRefreshers[#keyRefreshers + 1] = UpdateKey

		local resetBtn = vgui.Create("DButton", row)
		resetBtn:SetText(PinnedPanels.L("btn_reset"))
		resetBtn:SetWide(52)
		resetBtn:Dock(RIGHT)
		resetBtn:DockMargin(0, 3, 6, 3)
		SUI.StyleDarkButton(resetBtn)
		resetBtn.DoClick = function()
			PinnedPanels.ResetBind(bind.id)
			UpdateKey()
		end

		local unbindBtn = vgui.Create("DButton", row)
		unbindBtn:SetText(PinnedPanels.L("btn_unbind"))
		unbindBtn:SetWide(58)
		unbindBtn:Dock(RIGHT)
		unbindBtn:DockMargin(0, 3, 4, 3)
		SUI.StyleDarkButton(unbindBtn)
		unbindBtn.DoClick = function()
			PinnedPanels.SetBind(bind.id, KEY_NONE)
			UpdateKey()
		end

		local bindBtn = vgui.Create("DButton", row)
		bindBtn:SetText(PinnedPanels.L("btn_bind"))
		bindBtn:SetWide(52)
		bindBtn:Dock(RIGHT)
		bindBtn:DockMargin(0, 3, 4, 3)
		SUI.StyleDarkButton(bindBtn)
		bindBtn.DoClick = function()
			PinnedPanels.OpenKeyBindFrame({
				title   = PinnedPanels.Lf("bind_prefix", bind.name),
				get     = function() return PinnedPanels.GetBind(bind.id) end,
				set     = function(k) PinnedPanels.SetBind(bind.id, k) end,
				onSaved = UpdateKey,
				ignore  = "bind:" .. bind.id,
			})
		end
	end

	local keysBottom = SUI.Row(secKeys, 28)
	keysBottom:DockMargin(0, 6, 0, 0)

	SUI.Button(keysBottom, PinnedPanels.L("btn_reset_all_def"), "icon16/arrow_undo.png", 160, function()
		PinnedPanels.ResetAllBinds()
		for _, refresh in ipairs(keyRefreshers) do refresh() end
	end)
end

-- ── Appearance ───────────────────────────────────────────────────────────────
local function BuildAppearance(parent, ctx)
	local secApp = SUI.Card(parent, PinnedPanels.L("card_panel_colors"))

	local colorEntries = {
		{ label = PinnedPanels.L("color_panel_bg"),   key = "bg" },
		{ label = PinnedPanels.L("color_header_bar"), key = "header" },
		{ label = PinnedPanels.L("color_header_text"), key = "text" },
	}

	for _, entry in ipairs(colorEntries) do
		SUI.ColorRow(secApp, {
			label      = entry.label,
			popupTitle = entry.label,
			get        = function() return PinnedPanels.Settings[entry.key] end,
			set        = function(col) PinnedPanels.Settings[entry.key] = col end,
			popups     = ctx.popups,
			key        = "panel_" .. entry.key,
		})
	end

	local resetRow = SUI.Row(secApp, 30)
	resetRow:DockMargin(0, 8, 0, 0)

	SUI.Button(resetRow, PinnedPanels.L("btn_reset_default"), "icon16/arrow_undo.png", 160, function()
		PinnedPanels.Settings.bg     = Color(235, 238, 242, 250)
		PinnedPanels.Settings.header = Color(32, 35, 42, 255)
		PinnedPanels.Settings.text   = Color(240, 245, 255, 255)
		PinnedPanels.SaveSettings()
		ctx.Rebuild()
	end)

	local previewCard = SUI.Card(parent, PinnedPanels.L("card_live_preview"))

	local preview = vgui.Create("DPanel", previewCard)
	preview:Dock(TOP)
	preview:SetTall(84)
	preview.Paint = function(_, w, h)
		local th = PinnedPanels.Settings
		draw.RoundedBox(6, 0, 0, w, h, th.bg)
		draw.RoundedBoxEx(6, 0, 0, w, 26, th.header, true, true, false, false)
		draw.SimpleText(PinnedPanels.L("preview_title"), "DermaDefaultBold", 10, 13, th.text,
			TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		C._previewHint.r = th.text.r
		C._previewHint.g = th.text.g
		C._previewHint.b = th.text.b
		draw.SimpleText(PinnedPanels.L("preview_hint"), "DermaDefault",
			10, h - 10, C._previewHint,
			TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM)
	end
end

-- ── Taskbar ──────────────────────────────────────────────────────────────────
local function BuildTaskbar(parent, ctx)
	local tb = PinnedPanels.Settings.taskbar

	local secTaskbar = SUI.Card(parent, PinnedPanels.L("card_taskbar"))

	SUI.CheckRow(secTaskbar, PinnedPanels.L("opt_taskbar_enable"),
		tb.enabled ~= false, function(val)
			PinnedPanels.Settings.taskbar.enabled = val
			if val then PinnedPanels.CreateTaskbar() else PinnedPanels.DestroyTaskbar() end
		end)

	local posRow = SUI.Row(secTaskbar, 28)
	posRow:DockMargin(0, 0, 0, 8)

	local posLbl = vgui.Create("DLabel", posRow)
	posLbl:SetText(PinnedPanels.L("lbl_position"))
	posLbl:SetTextColor(C.textLabel)
	posLbl:Dock(LEFT)
	posLbl:SetWide(80)

	local posLabels = {
		bottom = PinnedPanels.L("pos_bottom"),
		top    = PinnedPanels.L("pos_top"),
		left   = PinnedPanels.L("pos_left"),
		right  = PinnedPanels.L("pos_right"),
	}

	local posCombo = vgui.Create("DComboBox", posRow)
	posCombo:Dock(FILL)
	posCombo:SetValue(posLabels[tb.position or "bottom"] or posLabels.bottom)
	posCombo:AddChoice(posLabels.bottom, "bottom")
	posCombo:AddChoice(posLabels.top, "top")
	posCombo:AddChoice(posLabels.left, "left")
	posCombo:AddChoice(posLabels.right, "right")
	posCombo.OnSelect = function(_, _, _, data)
		PinnedPanels.Settings.taskbar.position = data
		PinnedPanels.SaveSettings()
	end

	SUI.SliderRow(secTaskbar, {
		label     = PinnedPanels.L("opt_bar_thickness"),
		min       = 20,
		max       = 64,
		value     = tb.height or 32,
		saveTimer = "PinnedPanels_TaskbarHeightSave",
		onChange  = function(val)
			PinnedPanels.Settings.taskbar.height = math.Clamp(val, 20, 64)
		end,
	})

	SUI.CheckRow(secTaskbar, PinnedPanels.L("opt_reveal_hover"),
		tb.revealOnHover == true, function(val)
			PinnedPanels.Settings.taskbar.revealOnHover = val
		end)

	SUI.CheckRow(secTaskbar, PinnedPanels.L("opt_show_labels"),
		tb.showLabels ~= false, function(val)
			PinnedPanels.Settings.taskbar.showLabels = val
		end)

	local secColors = SUI.Card(parent, PinnedPanels.L("card_taskbar_colors"))

	local tbColorEntries = {
		{ label = PinnedPanels.L("color_background"), key = "bgColor" },
		{ label = PinnedPanels.L("color_text"),       key = "textColor" },
		{ label = PinnedPanels.L("color_accent"),     key = "accentColor" },
	}

	for _, ce in ipairs(tbColorEntries) do
		SUI.ColorRow(secColors, {
			label      = ce.label,
			popupTitle = PinnedPanels.Lf("taskbar_color_pfx", ce.label),
			get        = function() return PinnedPanels.Settings.taskbar[ce.key] end,
			set        = function(col) PinnedPanels.Settings.taskbar[ce.key] = col end,
			popups     = ctx.popups,
			key        = "taskbar_" .. ce.key,
		})
	end

	local resetRow = SUI.Row(secColors, 30)
	resetRow:DockMargin(0, 8, 0, 0)

	SUI.Button(resetRow, PinnedPanels.L("btn_reset_taskbar"), "icon16/arrow_undo.png", 180, function()
		PinnedPanels.Settings.taskbar = table.Copy(PinnedPanels.DEFAULT_TASKBAR)
		PinnedPanels.SaveSettings()
		PinnedPanels.CreateTaskbar()
		ctx.Rebuild()
	end)
end

-- ── Groups ───────────────────────────────────────────────────────────────────
local function BuildGroups(parent, ctx)
	local secGroups = SUI.Card(parent, PinnedPanels.L("card_panel_groups"))

	SUI.Help(secGroups, PinnedPanels.L("help_groups"))

	local listHolder = vgui.Create("DPanel", secGroups)
	listHolder:Dock(TOP)
	listHolder.Paint = function() end

	local function RebuildGroups()
		if not IsValid(listHolder) then return end
		listHolder:Clear()

		local groups = PinnedPanels.Settings.groups
		if #groups == 0 then
			local emptyLbl = vgui.Create("DLabel", listHolder)
			emptyLbl:SetText(PinnedPanels.L("groups_none"))
			emptyLbl:SetTextColor(C.textMuted)
			emptyLbl:Dock(TOP)
			emptyLbl:DockMargin(0, 0, 0, 4)
			listHolder:SetTall(24)
			return
		end

		for _, g in ipairs(groups) do
			local row = vgui.Create("DPanel", listHolder)
			row:Dock(TOP)
			row:SetTall(28)
			row:DockMargin(0, 0, 0, 2)
			row.Paint = function(self, w, h)
				local bg = self:IsHovered() and C.bgRowHov or C.bgCardHdr
				draw.RoundedBox(4, 0, 0, w, h, bg)
				surface.SetDrawColor(g.color)
				surface.DrawRect(0, 0, 4, h)
			end

			local nameLbl = vgui.Create("DLabel", row)
			nameLbl:SetText(PinnedPanels.Lf("group_row_count", g.name, #g.ids))
			nameLbl:SetTextColor(C.textLight)
			nameLbl:Dock(FILL)
			nameLbl:DockMargin(10, 0, 0, 0)
			nameLbl:SetMouseInputEnabled(false)

			local delBtn = vgui.Create("DButton", row)
			delBtn:SetText(PinnedPanels.L("btn_delete"))
			delBtn:SetWide(55)
			delBtn:Dock(RIGHT)
			delBtn:DockMargin(0, 3, 4, 3)
			delBtn:SetTextColor(C.unpinTxt)
			delBtn.Paint = function(self, w, h)
				draw.RoundedBox(3, 0, 0, w, h, self:IsHovered() and C.unpinBgHov or C.unpinBg)
			end
			delBtn.DoClick = function()
				PinnedPanels.DeleteGroup(g.name)
				RebuildGroups()
			end
		end

		listHolder:SetTall(#groups * 30)
	end

	RebuildGroups()

	hook.Add("PinnedPanels_StateChanged", listHolder, function(pnl)
		if IsValid(pnl) then RebuildGroups() end
	end)

	local addRow = SUI.Row(secGroups, 28)
	addRow:DockMargin(0, 6, 0, 0)

	SUI.Button(addRow, PinnedPanels.L("ctx_new_group"), "icon16/folder_add.png", 120, function()
		PinnedPanels.PromptNewGroup(nil, RebuildGroups)
	end)
end

-- ── Backup & Data ────────────────────────────────────────────────────────────
local function BuildData(parent, ctx)
	local secBackup = SUI.Card(parent, PinnedPanels.L("card_backup"))

	SUI.Help(secBackup, PinnedPanels.L("help_backup"))

	local backupRow = SUI.Row(secBackup, 30)

	SUI.Button(backupRow, PinnedPanels.L("btn_export"), "icon16/page_white_get.png", 160, function()
		local code = PinnedPanels.ExportLayout()
		if not code or code == "" then
			Derma_Message(PinnedPanels.L("export_nothing"), PinnedPanels.L("export_title"), PinnedPanels.L("btn_ok"))
			return
		end
		SUI.ShowCodePopup(PinnedPanels.L("export_title"), code, nil)
	end)

	SUI.Button(backupRow, PinnedPanels.L("btn_import"), "icon16/page_white_put.png", 160, function()
		SUI.ShowCodePopup(PinnedPanels.L("import_title"), "", function(value)
			local ok, err = PinnedPanels.ImportLayout(value)
			if ok then
				RunConsoleCommand("pp_reload")
				Derma_Message(PinnedPanels.L("import_success"), PinnedPanels.L("import_title"), PinnedPanels.L("btn_ok"))
			else
				Derma_Message(PinnedPanels.Lf("import_failed", tostring(err)), PinnedPanels.L("import_title"), PinnedPanels.L("btn_ok"))
			end
		end)
	end)

	local dangerCard = SUI.Card(parent, PinnedPanels.L("card_danger"))

	local unpinAllBtn = vgui.Create("DButton", dangerCard)
	unpinAllBtn:SetText(PinnedPanels.L("btn_unpin_all"))
	unpinAllBtn:Dock(TOP)
	unpinAllBtn:SetTall(30)
	unpinAllBtn.Paint = function(self, w, h)
		local bg = self:IsHovered() and C.dangerBgHov or C.dangerBg
		draw.RoundedBox(4, 0, 0, w, h, bg)
		surface.SetDrawColor(C.dangerBorder)
		surface.DrawOutlinedRect(0, 0, w, h, 1)
		draw.SimpleText(self:GetText(), "DermaDefaultBold", w / 2, h / 2,
			C.dangerTxt, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		return true
	end
	unpinAllBtn.DoClick = function()
		PinnedPanels.UnpinAll()
	end
end

-- ── Page Registry ────────────────────────────────────────────────────────────
PinnedPanels.SettingsPages = {
	{ id = "general",    nameKey = "page_general",    icon = "icon16/cog.png",              build = BuildGeneral },
	{ id = "controls",   nameKey = "page_controls",   icon = "icon16/keyboard.png",         build = BuildControls },
	{ id = "appearance", nameKey = "page_appearance", icon = "icon16/palette.png",          build = BuildAppearance },
	{ id = "taskbar",    nameKey = "page_taskbar",    icon = "icon16/application_put.png",  build = BuildTaskbar },
	{ id = "groups",     nameKey = "page_groups",     icon = "icon16/folder.png",           build = BuildGroups },
	{ id = "data",       nameKey = "page_data",       icon = "icon16/disk.png",             build = BuildData },
}
