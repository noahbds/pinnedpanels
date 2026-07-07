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
	local secBehavior = CreateSectionCard("Behavior", 140)

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

	local opacitySlider = vgui.Create("DNumSlider", secBehavior)
	opacitySlider:Dock(TOP)
	opacitySlider:SetTall(30)
	opacitySlider:SetText("Panel opacity outside interact mode (%)")
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

	-- ── Interact Mode Section ────────────────────────────────────────────────
	local secInteract = CreateSectionCard("Interact Mode (Cursor Toggle)", 140)

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
		local code = PinnedPanels.InteractMode.KeyCode
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
	openBindBtn.DoClick = function() PinnedPanels.OpenKeyBindFrame(UpdateKeyDisplay) end

	local clearBtn = vgui.Create("DButton", bindRow)
	clearBtn:SetText("Clear")
	clearBtn:SetIcon("icon16/cross.png")
	clearBtn:Dock(LEFT)
	clearBtn:SetWide(70)
	clearBtn:DockMargin(0, 0, 6, 0)
	StyleDarkButton(clearBtn)
	clearBtn.DoClick = function()
		PinnedPanels.InteractMode.KeyCode = KEY_NONE
		RunConsoleCommand("pp_interact_key", tostring(KEY_NONE))
		UpdateKeyDisplay()
	end

	local toggleBtn = vgui.Create("DButton", bindRow)
	toggleBtn:SetText("Toggle Now")
	toggleBtn:SetIcon("icon16/cursor.png")
	toggleBtn:Dock(LEFT)
	toggleBtn:SetWide(110)
	StyleDarkButton(toggleBtn)
	toggleBtn.DoClick = function() PinnedPanels.InteractMode.Toggle() end

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
		Derma_StringRequest("New Group", "Enter a name for the new group:", "",
			function(name)
				if name and name ~= "" then
					PinnedPanels.CreateGroup(name)
					RebuildGroups()
				end
			end, function() end, "Create", "Cancel")
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
	end

	return root
end
