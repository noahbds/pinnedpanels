local C = PinnedPanels.C

function PinnedPanels.CreateSettingsTab(parent)
	local root = vgui.Create("DPanel", parent)
	root.Paint = function(self, w, h)
		draw.RoundedBox(0, 0, 0, w, h, C.bg)
	end

	local scroll = vgui.Create("DScrollPanel", root)
	scroll:Dock(FILL)
	scroll:DockMargin(16, 16, 16, 16)

	PinnedPanels.ThrottleScroll(scroll)

	local function CreateSectionCard(title, height)
		local card = vgui.Create("DPanel", scroll)
		card:Dock(TOP)
		if height then card:SetTall(height) end
		card:DockMargin(0, 0, 0, 16)
		card:DockPadding(16, 46, 16, 16)
		card.Paint = function(self, w, h)
			draw.RoundedBox(6, 0, 0, w, h, C.bgCard)
			draw.RoundedBoxEx(6, 0, 0, w, 30, C.bgCardHdr, true, true, false, false)
			draw.SimpleText(title, "DermaDefaultBold", 12, 15, C.textTitle, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		end
		return card
	end

	local function StyleDarkButton(btn)
		btn:SetTextColor(C.textLight)
		btn.Paint = function(self, w, h)
			local bg = self:IsHovered() and C.btnBgHov or C.btnBg
			draw.RoundedBox(4, 0, 0, w, h, bg)
			surface.SetDrawColor(C.btnOutline)
			surface.DrawOutlinedRect(0, 0, w, h, 1)
		end
	end

	-- ── Behavior Section ─────────────────────────────────────────────────────
	local secBehavior = CreateSectionCard("Behavior", 180)

	local autoRestoreBox = vgui.Create("DCheckBoxLabel", secBehavior)
	autoRestoreBox:SetText("Auto-restore pinned panels when joining the server")
	autoRestoreBox:SetTextColor(C.textLight)
	autoRestoreBox:Dock(TOP)
	autoRestoreBox:DockMargin(0, 0, 0, 10)
	autoRestoreBox:SetValue(PinnedPanels.Settings.autoRestore)
	autoRestoreBox.OnChange = function(self, val)
		PinnedPanels.Settings.autoRestore = val
		PinnedPanels.SaveSettings()
	end

	local keyboardNavBox = vgui.Create("DCheckBoxLabel", secBehavior)
	keyboardNavBox:SetText("Allow keyboard navigation outside cursor mode")
	keyboardNavBox:SetTextColor(C.textLight)
	keyboardNavBox:Dock(TOP)
	keyboardNavBox:DockMargin(0, 0, 0, 10)
	keyboardNavBox:SetValue(PinnedPanels.Settings.keyboardNavOutsideCursorMode)
	keyboardNavBox.OnChange = function(self, val)
		PinnedPanels.Settings.keyboardNavOutsideCursorMode = val
		PinnedPanels.SaveSettings()
	end

	local opacitySlider = vgui.Create("DNumSlider", secBehavior)
	opacitySlider:Dock(TOP)
	opacitySlider:SetTall(30)
	opacitySlider:SetText("Panel opacity outside cursor mode (%)")
	opacitySlider:SetMin(10)
	opacitySlider:SetMax(100)
	opacitySlider:SetDecimals(0)
	opacitySlider:SetValue(math.Round((PinnedPanels.Settings.idleAlpha or 1) * 100))
	opacitySlider.Label:SetTextColor(C.textLight)
	opacitySlider.OnValueChanged = function(_, val)
		PinnedPanels.Settings.idleAlpha = math.Clamp(math.Round(val), 10, 100) / 100
		if PinnedPanels.UpdatePanelStates then PinnedPanels.UpdatePanelStates() end
		timer.Create("PinnedPanels_IdleAlphaSave", 0.4, 1, function()
			PinnedPanels.SaveSettings()
		end)
	end

	-- ── cursor mode Section ────────────────────────────────────────────────
	local secInteract = CreateSectionCard("cursor mode (Cursor Toggle)", 140)

	local interactHelp = vgui.Create("DLabel", secInteract)
	interactHelp:SetText(
		"Press your bound key in-game to show the cursor and freely interact with your pinned panels. " ..
		"The spawn menu always enables interaction while open."
	)
	interactHelp:SetTextColor(C.textBody)
	interactHelp:SetWrap(true)
	interactHelp:Dock(TOP)
	interactHelp:DockMargin(0, 0, 0, 10)
	interactHelp:SetAutoStretchVertical(true)

	local bindRow = vgui.Create("DPanel", secInteract)
	bindRow:Dock(TOP)
	bindRow:SetTall(30)
	bindRow.Paint = function() end

	local keyDisplay = vgui.Create("DLabel", bindRow)
	keyDisplay:Dock(LEFT)
	keyDisplay:SetWide(210)
	keyDisplay:SetFont("DermaDefaultBold")

	local function UpdateKeyDisplay()
		if not IsValid(keyDisplay) then return end
		local code = PinnedPanels.CursorMode.KeyCode
		if not code or code == KEY_NONE then
			keyDisplay:SetText("Current key: [ Not bound ]")
			keyDisplay:SetTextColor(C.errorRed)
		else
			keyDisplay:SetText("Current key: [ " .. string.upper(input.GetKeyName(code)) .. " ]")
			keyDisplay:SetTextColor(C.keyBound)
		end
	end
	UpdateKeyDisplay()

	local openBindBtn = vgui.Create("DButton", bindRow)
	openBindBtn:SetText("Change Key...")
	openBindBtn:SetIcon("icon16/keyboard.png")
	openBindBtn:Dock(LEFT)
	openBindBtn:SetWide(130)
	openBindBtn:DockMargin(0, 0, 6, 0)
	StyleDarkButton(openBindBtn)
	openBindBtn.DoClick = function()
		PinnedPanels.OpenKeyBindFrame({
			title = "Bind Interact Key",
			get = function() return PinnedPanels.CursorMode.KeyCode end,
			set = function(k)
				PinnedPanels.CursorMode.KeyCode = k
				RunConsoleCommand("pp_interact_key", tostring(k))
			end,
			onSaved = UpdateKeyDisplay,
			ignore  = "cursor",
		})
	end

	local clearBtn = vgui.Create("DButton", bindRow)
	clearBtn:SetText("Clear")
	clearBtn:SetIcon("icon16/cross.png")
	clearBtn:Dock(LEFT)
	clearBtn:SetWide(70)
	clearBtn:DockMargin(0, 0, 6, 0)
	StyleDarkButton(clearBtn)
	clearBtn.DoClick = function()
		PinnedPanels.CursorMode.KeyCode = KEY_NONE
		RunConsoleCommand("pp_interact_key", tostring(KEY_NONE))
		UpdateKeyDisplay()
	end

	local toggleBtn = vgui.Create("DButton", bindRow)
	toggleBtn:SetText("Toggle Now")
	toggleBtn:SetIcon("icon16/cursor.png")
	toggleBtn:Dock(LEFT)
	toggleBtn:SetWide(110)
	StyleDarkButton(toggleBtn)
	toggleBtn.DoClick = function() PinnedPanels.CursorMode.Toggle() end

	-- ── Keyboard Navigation Section ──────────────────────────────────────────
	local secKeys = CreateSectionCard("Keyboard Navigation", 320)

	local keysHelp = vgui.Create("DLabel", secKeys)
	keysHelp:SetText("Shortcuts work while cursor mode is on, and can also be enabled globally from Behavior. The focused panel is outlined; cycle focus, switch group tabs, or equip the focused tool.")
	keysHelp:SetTextColor(C.textBody)
	keysHelp:SetWrap(true)
	keysHelp:Dock(TOP)
	keysHelp:DockMargin(0, 0, 0, 8)
	keysHelp:SetAutoStretchVertical(true)

	local keyScroll = vgui.Create("DScrollPanel", secKeys)
	keyScroll:Dock(FILL)

	local function KeyName(code)
		if not code or code == KEY_NONE then return "Not bound" end
		return string.upper(input.GetKeyName(code) or "?")
	end

	local keyRefreshers = {}

	for _, bind in ipairs(PinnedPanels.Keybinds or {}) do
		local row = vgui.Create("DPanel", keyScroll)
		row:Dock(TOP)
		row:SetTall(26)
		row:DockMargin(0, 0, 0, 4)
		row.Paint = function(_, w, h)
			draw.RoundedBox(4, 0, 0, w, h, C.bgCard)
		end

		local nameLbl = vgui.Create("DLabel", row)
		nameLbl:SetText(bind.name)
		nameLbl:SetTextColor(C.textLight)
		nameLbl:Dock(LEFT)
		nameLbl:DockMargin(8, 0, 0, 0)
		nameLbl:SetWide(170)
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
		resetBtn:SetText("Reset")
		resetBtn:SetWide(52)
		resetBtn:Dock(RIGHT)
		resetBtn:DockMargin(0, 3, 6, 3)
		StyleDarkButton(resetBtn)
		resetBtn.DoClick = function()
			PinnedPanels.ResetBind(bind.id)
			UpdateKey()
		end

		local unbindBtn = vgui.Create("DButton", row)
		unbindBtn:SetText("Unbind")
		unbindBtn:SetWide(58)
		unbindBtn:Dock(RIGHT)
		unbindBtn:DockMargin(0, 3, 4, 3)
		StyleDarkButton(unbindBtn)
		unbindBtn.DoClick = function()
			PinnedPanels.SetBind(bind.id, KEY_NONE)
			UpdateKey()
		end

		local bindBtn = vgui.Create("DButton", row)
		bindBtn:SetText("Bind")
		bindBtn:SetWide(52)
		bindBtn:Dock(RIGHT)
		bindBtn:DockMargin(0, 3, 4, 3)
		StyleDarkButton(bindBtn)
		bindBtn.DoClick = function()
			PinnedPanels.OpenKeyBindFrame({
				title = "Bind: " .. bind.name,
				get = function() return PinnedPanels.GetBind(bind.id) end,
				set = function(k) PinnedPanels.SetBind(bind.id, k) end,
				onSaved = UpdateKey,
				ignore  = "bind:" .. bind.id,
			})
		end
	end

	local keysBottom = vgui.Create("DPanel", secKeys)
	keysBottom:Dock(BOTTOM)
	keysBottom:SetTall(28)
	keysBottom:DockMargin(0, 6, 0, 0)
	keysBottom.Paint = function() end

	local resetAllKeys = vgui.Create("DButton", keysBottom)
	resetAllKeys:SetText("Reset All to Default")
	resetAllKeys:SetIcon("icon16/arrow_undo.png")
	resetAllKeys:Dock(LEFT)
	resetAllKeys:SetWide(160)
	StyleDarkButton(resetAllKeys)
	resetAllKeys.DoClick = function()
		PinnedPanels.ResetAllBinds()
		for _, refresh in ipairs(keyRefreshers) do refresh() end
	end

	-- ── Appearance Colors (Compact Swatch UI) ────────────────────────────────
	local secApp = CreateSectionCard("Appearance Colors", 200)

	local colorEntries = {
		{ label = "Panel Background", key = "bg" },
		{ label = "Header Bar",       key = "header" },
		{ label = "Header Text",      key = "text" },
	}

	local activeMixers = {}

	for _, entry in ipairs(colorEntries) do
		local row = vgui.Create("DPanel", secApp)
		row:Dock(TOP)
		row:SetTall(30)
		row:DockMargin(0, 0, 0, 4)
		row.Paint = function() end

		local lbl = vgui.Create("DLabel", row)
		lbl:SetText(entry.label)
		lbl:SetTextColor(C.textLabel)
		lbl:Dock(LEFT)
		lbl:SetWide(120)
		lbl:SetContentAlignment(4)

		local swatch = vgui.Create("DButton", row)
		swatch:SetText("")
		swatch:Dock(LEFT)
		swatch:SetWide(40)
		swatch:DockMargin(0, 4, 8, 4)
		swatch.Paint = function(self, w, h)
			draw.RoundedBox(4, 0, 0, w, h, PinnedPanels.Settings[entry.key])
			surface.SetDrawColor(C.swatchBorder)
			surface.DrawOutlinedRect(0, 0, w, h, 1)
			if self:IsHovered() then
				surface.SetDrawColor(C.accent)
				surface.DrawOutlinedRect(0, 0, w, h, 2)
			end
		end

		local valLbl = vgui.Create("DLabel", row)
		valLbl:Dock(FILL)
		valLbl:SetTextColor(C.textMuted)
		local function UpdateValLbl()
			if not IsValid(valLbl) then return end
			local col = PinnedPanels.Settings[entry.key]
			valLbl:SetText(string.format("R:%d G:%d B:%d A:%d", col.r, col.g, col.b, col.a))
		end
		UpdateValLbl()

		swatch.DoClick = function()
			if IsValid(activeMixers[entry.key]) then
				activeMixers[entry.key]:Remove()
				activeMixers[entry.key] = nil
				return
			end

			local popup = vgui.Create("DFrame")
			popup:SetTitle(entry.label)
			popup:SetSize(260, 220)
			popup:SetDeleteOnClose(true)
			popup:MakePopup()
			popup:SetDraggable(true)
			popup:SetSizable(false)

			local sx, sy = swatch:LocalToScreen(0, 0)
			popup:SetPos(sx + 50, sy - 60)

			popup.Paint = function(self, w, h)
				draw.RoundedBox(6, 0, 0, w, h, C.colorPopupBg)
				draw.RoundedBoxEx(6, 0, 0, w, 24, C.colorPopupHdr, true, true, false, false)
				surface.SetDrawColor(C.colorPopupBorder)
				surface.DrawOutlinedRect(0, 0, w, h, 1)
			end

			local mixer = vgui.Create("DColorMixer", popup)
			mixer:Dock(FILL)
			mixer:DockMargin(8, 8, 8, 8)
			mixer:SetPalette(false)
			mixer:SetAlphaBar(true)
			mixer:SetWangs(true)
			mixer:SetColor(PinnedPanels.Settings[entry.key])
			mixer.ValueChanged = function(self, col)
				PinnedPanels.Settings[entry.key] = Color(col.r, col.g, col.b, col.a)
				PinnedPanels.SaveSettings()
				UpdateValLbl()
			end

			activeMixers[entry.key] = popup

			popup.OnClose = function()
				activeMixers[entry.key] = nil
			end
		end
	end

	local resetRow = vgui.Create("DPanel", secApp)
	resetRow:Dock(TOP)
	resetRow:SetTall(30)
	resetRow:DockMargin(0, 8, 0, 0)
	resetRow.Paint = function() end

	local resetBtn = vgui.Create("DButton", resetRow)
	resetBtn:SetText("Reset to Default")
	resetBtn:SetIcon("icon16/arrow_undo.png")
	resetBtn:Dock(LEFT)
	resetBtn:SetWide(160)
	StyleDarkButton(resetBtn)
	resetBtn.DoClick = function()
		PinnedPanels.Settings.bg     = Color(235, 238, 242, 250)
		PinnedPanels.Settings.header = Color(32, 35, 42, 255)
		PinnedPanels.Settings.text   = Color(240, 245, 255, 255)
		PinnedPanels.SaveSettings()
		for key, popup in pairs(activeMixers) do
			if IsValid(popup) then popup:Close() end
		end
		activeMixers = {}
	end

	-- ── Live Preview ─────────────────────────────────────────────────────────
	local previewCard = CreateSectionCard("Live Preview", 130)

	local preview = vgui.Create("DPanel", previewCard)
	preview:Dock(FILL)
	preview.Paint = function(self, w, h)
		local th = PinnedPanels.Settings
		draw.RoundedBox(6, 0, 0, w, h, th.bg)
		draw.RoundedBoxEx(6, 0, 0, w, 26, th.header, true, true, false, false)
		draw.SimpleText("Example Panel Title", "DermaDefaultBold", 10, 13, th.text,
			TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		C._previewHint.r = th.text.r
		C._previewHint.g = th.text.g
		C._previewHint.b = th.text.b
		draw.SimpleText("(this is how your pinned panels will look)", "DermaDefault",
			10, h - 10, C._previewHint,
			TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM)
	end

	-- ── Groups Manager ───────────────────────────────────────────────────────
	local secGroups = CreateSectionCard("Panel Groups", 180)

	local groupScroll = vgui.Create("DScrollPanel", secGroups)
	groupScroll:Dock(FILL)

	local function RebuildGroups()
		if not IsValid(groupScroll) then return end
		groupScroll:Clear()

		local groups = PinnedPanels.Settings.groups
		if #groups == 0 then
			local emptyLbl = vgui.Create("DLabel", groupScroll)
			emptyLbl:SetText("No groups yet. Create groups via right-click on panel headers.")
			emptyLbl:SetTextColor(C.textMuted)
			emptyLbl:SetWrap(true)
			emptyLbl:Dock(TOP)
			emptyLbl:DockMargin(0, 4, 0, 0)
			emptyLbl:SetAutoStretchVertical(true)
			return
		end

		for _, g in ipairs(groups) do
			local row = vgui.Create("DPanel", groupScroll)
			row:Dock(TOP)
			row:SetTall(28)
			row:DockMargin(0, 0, 0, 2)
			row.Paint = function(self, w, h)
				local bg = self:IsHovered() and C.bgRowHov or C.bgCard
				draw.RoundedBox(4, 0, 0, w, h, bg)
				surface.SetDrawColor(g.color)
				surface.DrawRect(0, 0, 4, h)
			end

			local nameLbl = vgui.Create("DLabel", row)
			nameLbl:SetText(g.name .. " (" .. #g.ids .. " panels)")
			nameLbl:SetTextColor(C.textLight)
			nameLbl:Dock(FILL)
			nameLbl:DockMargin(10, 0, 0, 0)
			nameLbl:SetMouseInputEnabled(false)

			local delBtn = vgui.Create("DButton", row)
			delBtn:SetText("Delete")
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
	end

	RebuildGroups()

	local groupHookName = "PinnedPanels_SettingsGroups_" .. tostring(root)
	hook.Add("PinnedPanels_StateChanged", groupHookName, function()
		if IsValid(groupScroll) then
			RebuildGroups()
		else
			hook.Remove("PinnedPanels_StateChanged", groupHookName)
		end
	end)

	local addGroupRow = vgui.Create("DPanel", secGroups)
	addGroupRow:Dock(BOTTOM)
	addGroupRow:SetTall(28)
	addGroupRow.Paint = function() end

	local addGroupBtn = vgui.Create("DButton", addGroupRow)
	addGroupBtn:SetText("New Group...")
	addGroupBtn:SetIcon("icon16/folder_add.png")
	addGroupBtn:Dock(LEFT)
	addGroupBtn:SetWide(120)
	StyleDarkButton(addGroupBtn)
	addGroupBtn.DoClick = function()
		PinnedPanels.PromptNewGroup(nil, RebuildGroups)
	end

	-- ── Taskbar Section ──────────────────────────────────────────────────────
	local secTaskbar = CreateSectionCard("Taskbar", 400)

	local tb = PinnedPanels.Settings.taskbar or {}

	local tbEnabledBox = vgui.Create("DCheckBoxLabel", secTaskbar)
	tbEnabledBox:SetText("Enable taskbar (minimized panels appear in a bar)")
	tbEnabledBox:SetTextColor(C.textLight)
	tbEnabledBox:Dock(TOP)
	tbEnabledBox:DockMargin(0, 0, 0, 8)
	tbEnabledBox:SetValue(tb.enabled ~= false)
	tbEnabledBox.OnChange = function(_, val)
		PinnedPanels.Settings.taskbar.enabled = val
		PinnedPanels.SaveSettings()
		if val then PinnedPanels.CreateTaskbar() else PinnedPanels.DestroyTaskbar() end
	end

	local posRow = vgui.Create("DPanel", secTaskbar)
	posRow:Dock(TOP)
	posRow:SetTall(28)
	posRow:DockMargin(0, 0, 0, 8)
	posRow.Paint = function() end

	local posLbl = vgui.Create("DLabel", posRow)
	posLbl:SetText("Position:")
	posLbl:SetTextColor(C.textLabel)
	posLbl:Dock(LEFT)
	posLbl:SetWide(80)

	local posCombo = vgui.Create("DComboBox", posRow)
	posCombo:Dock(FILL)
	posCombo:SetValue(string.upper((tb.position or "bottom"):sub(1, 1)) .. (tb.position or "bottom"):sub(2))
	posCombo:AddChoice("Bottom", "bottom")
	posCombo:AddChoice("Top", "top")
	posCombo:AddChoice("Left", "left")
	posCombo:AddChoice("Right", "right")
	posCombo.OnSelect = function(_, _, _, data)
		PinnedPanels.Settings.taskbar.position = data
		PinnedPanels.SaveSettings()
	end

	local heightSlider = vgui.Create("DNumSlider", secTaskbar)
	heightSlider:Dock(TOP)
	heightSlider:SetTall(30)
	heightSlider:DockMargin(0, 0, 0, 8)
	heightSlider:SetText("Bar thickness (px)")
	heightSlider:SetMin(20)
	heightSlider:SetMax(64)
	heightSlider:SetDecimals(0)
	heightSlider:SetValue(tb.height or 32)
	heightSlider.Label:SetTextColor(C.textLight)
	heightSlider.OnValueChanged = function(_, val)
		PinnedPanels.Settings.taskbar.height = math.Clamp(math.Round(val), 20, 64)
		timer.Create("PinnedPanels_TaskbarHeightSave", 0.4, 1, function()
			PinnedPanels.SaveSettings()
		end)
	end

	local tbRevealBox = vgui.Create("DCheckBoxLabel", secTaskbar)
	tbRevealBox:SetText("Reveal on hover (collapse until the cursor is near the bar)")
	tbRevealBox:SetTextColor(C.textLight)
	tbRevealBox:Dock(TOP)
	tbRevealBox:DockMargin(0, 0, 0, 8)
	tbRevealBox:SetValue(tb.revealOnHover == true)
	tbRevealBox.OnChange = function(_, val)
		PinnedPanels.Settings.taskbar.revealOnHover = val
		PinnedPanels.SaveSettings()
	end

	local tbLabelsBox = vgui.Create("DCheckBoxLabel", secTaskbar)
	tbLabelsBox:SetText("Show text labels on entries")
	tbLabelsBox:SetTextColor(C.textLight)
	tbLabelsBox:Dock(TOP)
	tbLabelsBox:DockMargin(0, 0, 0, 8)
	tbLabelsBox:SetValue(tb.showLabels ~= false)
	tbLabelsBox.OnChange = function(_, val)
		PinnedPanels.Settings.taskbar.showLabels = val
		PinnedPanels.SaveSettings()
	end

	local tbColorEntries = {
		{ label = "Background", key = "bgColor" },
		{ label = "Text",       key = "textColor" },
		{ label = "Accent",     key = "accentColor" },
	}

	local tbMixers = {}

	for _, ce in ipairs(tbColorEntries) do
		local crow = vgui.Create("DPanel", secTaskbar)
		crow:Dock(TOP)
		crow:SetTall(28)
		crow:DockMargin(0, 0, 0, 4)
		crow.Paint = function() end

		local clbl = vgui.Create("DLabel", crow)
		clbl:SetText(ce.label)
		clbl:SetTextColor(C.textLabel)
		clbl:Dock(LEFT)
		clbl:SetWide(100)
		clbl:SetContentAlignment(4)

		local cswatch = vgui.Create("DButton", crow)
		cswatch:SetText("")
		cswatch:Dock(LEFT)
		cswatch:SetWide(36)
		cswatch:DockMargin(0, 3, 8, 3)
		cswatch.Paint = function(self, w, h)
			local col = PinnedPanels.Settings.taskbar[ce.key]
			draw.RoundedBox(3, 0, 0, w, h, col or Color(128, 128, 128))
			surface.SetDrawColor(C.swatchBorder)
			surface.DrawOutlinedRect(0, 0, w, h, 1)
			if self:IsHovered() then
				surface.SetDrawColor(C.accent)
				surface.DrawOutlinedRect(0, 0, w, h, 2)
			end
		end

		local cvalLbl = vgui.Create("DLabel", crow)
		cvalLbl:Dock(FILL)
		cvalLbl:SetTextColor(C.textMuted)
		local function UpdateCVal()
			if not IsValid(cvalLbl) then return end
			local col = PinnedPanels.Settings.taskbar[ce.key]
			if col then
				cvalLbl:SetText(string.format("R:%d G:%d B:%d A:%d", col.r, col.g, col.b, col.a))
			end
		end
		UpdateCVal()

		cswatch.DoClick = function()
			if IsValid(tbMixers[ce.key]) then
				tbMixers[ce.key]:Remove()
				tbMixers[ce.key] = nil
				return
			end
			local popup = vgui.Create("DFrame")
			popup:SetTitle("Taskbar: " .. ce.label)
			popup:SetSize(260, 220)
			popup:SetDeleteOnClose(true)
			popup:MakePopup()
			popup:SetDraggable(true)
			popup:SetSizable(false)
			local sx, sy = cswatch:LocalToScreen(0, 0)
			popup:SetPos(sx + 50, sy - 60)
			popup.Paint = function(self, w, h)
				draw.RoundedBox(6, 0, 0, w, h, C.colorPopupBg)
				draw.RoundedBoxEx(6, 0, 0, w, 24, C.colorPopupHdr, true, true, false, false)
				surface.SetDrawColor(C.colorPopupBorder)
				surface.DrawOutlinedRect(0, 0, w, h, 1)
			end
			local mixer = vgui.Create("DColorMixer", popup)
			mixer:Dock(FILL)
			mixer:DockMargin(8, 8, 8, 8)
			mixer:SetPalette(false)
			mixer:SetAlphaBar(true)
			mixer:SetWangs(true)
			mixer:SetColor(PinnedPanels.Settings.taskbar[ce.key])
			mixer.ValueChanged = function(_, col)
				PinnedPanels.Settings.taskbar[ce.key] = Color(col.r, col.g, col.b, col.a)
				PinnedPanels.SaveSettings()
				UpdateCVal()
			end
			tbMixers[ce.key] = popup
			popup.OnClose = function() tbMixers[ce.key] = nil end
		end
	end

	local tbResetRow = vgui.Create("DPanel", secTaskbar)
	tbResetRow:Dock(TOP)
	tbResetRow:SetTall(30)
	tbResetRow:DockMargin(0, 8, 0, 0)
	tbResetRow.Paint = function() end

	local tbResetBtn = vgui.Create("DButton", tbResetRow)
	tbResetBtn:SetText("Reset Taskbar to Default")
	tbResetBtn:SetIcon("icon16/arrow_undo.png")
	tbResetBtn:Dock(LEFT)
	tbResetBtn:SetWide(180)
	StyleDarkButton(tbResetBtn)
	tbResetBtn.DoClick = function()
		PinnedPanels.Settings.taskbar = table.Copy(PinnedPanels.DEFAULT_TASKBAR)
		PinnedPanels.SaveSettings()
		PinnedPanels.CreateTaskbar()
		for _, popup in pairs(tbMixers) do
			if IsValid(popup) then popup:Close() end
		end
		tbMixers = {}
		tbEnabledBox:SetValue(true)
		posCombo:SetValue("Bottom")
		heightSlider:SetValue(32)
		tbRevealBox:SetValue(false)
		tbLabelsBox:SetValue(true)
	end

	-- ── Window Snapping ──────────────────────────────────────────────────────
	local secSnap = CreateSectionCard("Window Snapping", 120)

	local snapBox = vgui.Create("DCheckBoxLabel", secSnap)
	snapBox:SetText("Snap panels to screen edges and each other while dragging (hold Alt to bypass)")
	snapBox:SetTextColor(C.textLight)
	snapBox:Dock(TOP)
	snapBox:DockMargin(0, 0, 0, 10)
	snapBox:SetWrap(true)
	snapBox:SetTall(34)
	snapBox:SetValue(PinnedPanels.Settings.snapEnabled ~= false)
	snapBox.OnChange = function(_, val)
		PinnedPanels.Settings.snapEnabled = val
		PinnedPanels.SaveSettings()
	end

	local snapSlider = vgui.Create("DNumSlider", secSnap)
	snapSlider:Dock(TOP)
	snapSlider:SetTall(30)
	snapSlider:SetText("Snap distance (px)")
	snapSlider:SetMin(0)
	snapSlider:SetMax(40)
	snapSlider:SetDecimals(0)
	snapSlider:SetValue(PinnedPanels.Settings.snapDistance or 12)
	snapSlider.Label:SetTextColor(C.textLight)
	snapSlider.OnValueChanged = function(_, val)
		PinnedPanels.Settings.snapDistance = math.Clamp(math.Round(val), 0, 64)
		timer.Create("PinnedPanels_SnapSave", 0.4, 1, function() PinnedPanels.SaveSettings() end)
	end

	-- ── Peek ─────────────────────────────────────────────────────────────────
	local secPeek = CreateSectionCard("Peek (Hold to Reveal)", 120)

	local peekHelp = vgui.Create("DLabel", secPeek)
	peekHelp:SetText("Hold this key to temporarily show every panel — hidden, minimized or faded — at full opacity. Release to put everything back.")
	peekHelp:SetTextColor(C.textBody)
	peekHelp:SetWrap(true)
	peekHelp:Dock(TOP)
	peekHelp:DockMargin(0, 0, 0, 10)
	peekHelp:SetAutoStretchVertical(true)

	local peekRow = vgui.Create("DPanel", secPeek)
	peekRow:Dock(TOP)
	peekRow:SetTall(30)
	peekRow.Paint = function() end

	local peekKeyDisplay = vgui.Create("DLabel", peekRow)
	peekKeyDisplay:Dock(LEFT)
	peekKeyDisplay:SetWide(210)
	peekKeyDisplay:SetFont("DermaDefaultBold")

	local function UpdatePeekDisplay()
		if not IsValid(peekKeyDisplay) then return end
		local code = PinnedPanels.GetPeekKey and PinnedPanels.GetPeekKey() or KEY_NONE
		if not code or code == KEY_NONE then
			peekKeyDisplay:SetText("Current key: [ Not bound ]")
			peekKeyDisplay:SetTextColor(C.errorRed)
		else
			peekKeyDisplay:SetText("Current key: [ " .. string.upper(input.GetKeyName(code)) .. " ]")
			peekKeyDisplay:SetTextColor(C.keyBound)
		end
	end
	UpdatePeekDisplay()

	local peekBindBtn = vgui.Create("DButton", peekRow)
	peekBindBtn:SetText("Change Key...")
	peekBindBtn:SetIcon("icon16/keyboard.png")
	peekBindBtn:Dock(LEFT)
	peekBindBtn:SetWide(130)
	peekBindBtn:DockMargin(0, 0, 6, 0)
	StyleDarkButton(peekBindBtn)
	peekBindBtn.DoClick = function()
		PinnedPanels.OpenKeyBindFrame({
			title = "Bind Peek Key",
			get = function() return PinnedPanels.GetPeekKey() end,
			set = function(k) PinnedPanels.SetPeekKey(k) end,
			onSaved = UpdatePeekDisplay,
			ignore  = "peek",
		})
	end

	local peekClearBtn = vgui.Create("DButton", peekRow)
	peekClearBtn:SetText("Clear")
	peekClearBtn:SetIcon("icon16/cross.png")
	peekClearBtn:Dock(LEFT)
	peekClearBtn:SetWide(70)
	StyleDarkButton(peekClearBtn)
	peekClearBtn.DoClick = function()
		PinnedPanels.SetPeekKey(KEY_NONE)
		UpdatePeekDisplay()
	end

	-- ── Command Palette ──────────────────────────────────────────────────────
	local secPalette = CreateSectionCard("Command Palette", 130)

	local palHelp = vgui.Create("DLabel", secPalette)
	palHelp:SetText("Open a searchable list of every tool, content browser, pinned panel and action. Bind a key to open it anywhere in-game.")
	palHelp:SetTextColor(C.textBody)
	palHelp:SetWrap(true)
	palHelp:Dock(TOP)
	palHelp:DockMargin(0, 0, 0, 10)
	palHelp:SetAutoStretchVertical(true)

	local palRow = vgui.Create("DPanel", secPalette)
	palRow:Dock(TOP)
	palRow:SetTall(30)
	palRow.Paint = function() end

	local palKeyDisplay = vgui.Create("DLabel", palRow)
	palKeyDisplay:Dock(LEFT)
	palKeyDisplay:SetWide(210)
	palKeyDisplay:SetFont("DermaDefaultBold")

	local function UpdatePalDisplay()
		if not IsValid(palKeyDisplay) then return end
		local code = PinnedPanels.GetPaletteKey and PinnedPanels.GetPaletteKey() or KEY_NONE
		if not code or code == KEY_NONE then
			palKeyDisplay:SetText("Current key: [ Not bound ]")
			palKeyDisplay:SetTextColor(C.errorRed)
		else
			palKeyDisplay:SetText("Current key: [ " .. string.upper(input.GetKeyName(code)) .. " ]")
			palKeyDisplay:SetTextColor(C.keyBound)
		end
	end
	UpdatePalDisplay()

	local palBindBtn = vgui.Create("DButton", palRow)
	palBindBtn:SetText("Change Key...")
	palBindBtn:SetIcon("icon16/keyboard.png")
	palBindBtn:Dock(LEFT)
	palBindBtn:SetWide(130)
	palBindBtn:DockMargin(0, 0, 6, 0)
	StyleDarkButton(palBindBtn)
	palBindBtn.DoClick = function()
		PinnedPanels.OpenKeyBindFrame({
			title = "Bind Command Palette",
			get = function() return PinnedPanels.GetPaletteKey() end,
			set = function(k) PinnedPanels.SetPaletteKey(k) end,
			onSaved = UpdatePalDisplay,
			ignore  = "palette",
		})
	end

	local palClearBtn = vgui.Create("DButton", palRow)
	palClearBtn:SetText("Clear")
	palClearBtn:SetIcon("icon16/cross.png")
	palClearBtn:Dock(LEFT)
	palClearBtn:SetWide(70)
	palClearBtn:DockMargin(0, 0, 6, 0)
	StyleDarkButton(palClearBtn)
	palClearBtn.DoClick = function()
		PinnedPanels.SetPaletteKey(KEY_NONE)
		UpdatePalDisplay()
	end

	local palOpenBtn = vgui.Create("DButton", palRow)
	palOpenBtn:SetText("Open Now")
	palOpenBtn:SetIcon("icon16/application_view_list.png")
	palOpenBtn:Dock(LEFT)
	palOpenBtn:SetWide(110)
	StyleDarkButton(palOpenBtn)
	palOpenBtn.DoClick = function() PinnedPanels.OpenCommandPalette() end

	-- ── Backup & Sharing ─────────────────────────────────────────────────────
	local secBackup = CreateSectionCard("Backup & Sharing", 120)

	local backupHelp = vgui.Create("DLabel", secBackup)
	backupHelp:SetText("Export your current layout (panels + groups) to a shareable code, or paste a code to import. Importing replaces your current layout.")
	backupHelp:SetTextColor(C.textBody)
	backupHelp:SetWrap(true)
	backupHelp:Dock(TOP)
	backupHelp:DockMargin(0, 0, 0, 10)
	backupHelp:SetAutoStretchVertical(true)

	local function ShowCodePopup(title, code, onApply)
		local p = vgui.Create("DFrame")
		p:SetSize(480, 260)
		p:Center()
		p:SetTitle(title)
		p:MakePopup()
		p.Paint = function(_, w, h)
			draw.RoundedBox(6, 0, 0, w, h, C.bgPopup)
			draw.RoundedBoxEx(6, 0, 0, w, 24, C.colorPopupHdr, true, true, false, false)
			surface.SetDrawColor(C.colorPopupBorder)
			surface.DrawOutlinedRect(0, 0, w, h, 1)
		end

		local bar = vgui.Create("DPanel", p)
		bar:Dock(BOTTOM)
		bar:SetTall(34)
		bar:DockMargin(0, 6, 0, 0)
		bar.Paint = function() end

		local entry = vgui.Create("DTextEntry", p)
		entry:Dock(FILL)
		entry:DockMargin(10, 30, 10, 4)
		entry:SetMultiline(true)
		entry:SetText(code or "")

		if onApply then
			local applyBtn = vgui.Create("DButton", bar)
			applyBtn:SetText("Import & Reload")
			applyBtn:Dock(RIGHT)
			applyBtn:SetWide(140)
			StyleDarkButton(applyBtn)
			applyBtn.DoClick = function()
				local ok, err = PinnedPanels.ImportLayout(entry:GetValue())
				p:Remove()
				if ok then
					RunConsoleCommand("pp_reload")
					Derma_Message("Layout imported successfully.", "Import Layout", "OK")
				else
					Derma_Message("Import failed: " .. tostring(err), "Import Layout", "OK")
				end
			end
		else
			entry:RequestFocus()
			entry:SelectAllOnFocus(true)
			entry:SelectAll()
			local hintLbl = vgui.Create("DLabel", bar)
			hintLbl:Dock(FILL)
			hintLbl:SetText("Copy this code (Ctrl+C) and share it.")
			hintLbl:SetTextColor(C.textMuted)
		end
		return p
	end

	local backupRow = vgui.Create("DPanel", secBackup)
	backupRow:Dock(TOP)
	backupRow:SetTall(30)
	backupRow.Paint = function() end

	local exportBtn = vgui.Create("DButton", backupRow)
	exportBtn:SetText("Export Layout...")
	exportBtn:SetIcon("icon16/page_white_get.png")
	exportBtn:Dock(LEFT)
	exportBtn:SetWide(160)
	exportBtn:DockMargin(0, 0, 6, 0)
	StyleDarkButton(exportBtn)
	exportBtn.DoClick = function()
		local code = PinnedPanels.ExportLayout()
		if not code or code == "" then
			Derma_Message("Nothing to export yet.", "Export Layout", "OK")
			return
		end
		ShowCodePopup("Export Layout", code, nil)
	end

	local importBtn = vgui.Create("DButton", backupRow)
	importBtn:SetText("Import Layout...")
	importBtn:SetIcon("icon16/page_white_put.png")
	importBtn:Dock(LEFT)
	importBtn:SetWide(160)
	StyleDarkButton(importBtn)
	importBtn.DoClick = function()
		ShowCodePopup("Import Layout", "", true)
	end

	-- ── Danger Zone ──────────────────────────────────────────────────────────
	local dangerCard = CreateSectionCard("Danger Zone", 85)

	local unpinAllBtn = vgui.Create("DButton", dangerCard)
	unpinAllBtn:SetText("Unpin All Panels")
	unpinAllBtn:SetIcon("icon16/cross.png")
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

	root.OnRemove = function()
		hook.Remove("PinnedPanels_StateChanged", groupHookName)
		for _, popup in pairs(activeMixers) do
			if IsValid(popup) then popup:Remove() end
		end
		for _, popup in pairs(tbMixers) do
			if IsValid(popup) then popup:Remove() end
		end
	end

	return root
end
