function PinnedPanels.CreateSettingsTab(parent)
	local root = vgui.Create("DPanel", parent)
	root.Paint = function(self, w, h)
		draw.RoundedBox(0, 0, 0, w, h, Color(30, 32, 40, 255))
	end

	local scroll = vgui.Create("DScrollPanel", root)
	scroll:Dock(FILL)
	scroll:DockMargin(16, 16, 16, 16)

	local oldInvalidate = scroll.InvalidateLayout
	scroll.NextLayout = 0
	scroll.InvalidateLayout = function(self, layoutNow)
		if CurTime() < self.NextLayout then return end
		self.NextLayout = CurTime() + 0.1
		oldInvalidate(self, layoutNow)
	end

	local function CreateSectionCard(title, height)
		local card = vgui.Create("DPanel", scroll)
		card:Dock(TOP)
		if height then card:SetTall(height) end
		card:DockMargin(0, 0, 0, 16)
		card:DockPadding(16, 46, 16, 16)
		card.Paint = function(self, w, h)
			draw.RoundedBox(6, 0, 0, w, h, Color(40, 44, 52, 255))
			draw.RoundedBoxEx(6, 0, 0, w, 30, Color(25, 28, 34, 255), true, true, false, false)
			draw.SimpleText(title, "DermaDefaultBold", 12, 15, Color(200, 210, 225), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		end
		return card
	end

	local function StyleDarkButton(btn)
		btn:SetTextColor(Color(220, 225, 235))
		btn.Paint = function(self, w, h)
			local bg = self:IsHovered() and Color(70, 75, 85) or Color(55, 60, 70)
			draw.RoundedBox(4, 0, 0, w, h, bg)
			surface.SetDrawColor(20, 20, 20)
			surface.DrawOutlinedRect(0, 0, w, h, 1)
		end
	end

	local secBehavior = CreateSectionCard("Behavior", 80)

	local autoRestoreBox = vgui.Create("DCheckBoxLabel", secBehavior)
	autoRestoreBox:SetText("Auto-restore pinned panels when joining the server")
	autoRestoreBox:SetTextColor(Color(220, 225, 235))
	autoRestoreBox:Dock(TOP)
	autoRestoreBox:DockMargin(0, 0, 0, 10)
	autoRestoreBox:SetValue(PinnedPanels.Settings.autoRestore)
	autoRestoreBox.OnChange = function(self, val)
		PinnedPanels.Settings.autoRestore = val
		PinnedPanels.SaveSettings()
	end

	local secInteract = CreateSectionCard("Interact Mode (Cursor Toggle)", 140)

	local interactHelp = vgui.Create("DLabel", secInteract)
	interactHelp:SetText(
		"Press your bound key in-game to show the cursor and freely interact with your pinned panels. " ..
		"The spawn menu always enables interaction while open."
	)
	interactHelp:SetTextColor(Color(150, 160, 175))
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
			keyDisplay:SetTextColor(Color(200, 80, 80))
		else
			keyDisplay:SetText("Current key: [ " .. string.upper(input.GetKeyName(code)) .. " ]")
			keyDisplay:SetTextColor(Color(80, 210, 120))
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

	local MIXER_ROW_H = 140
	local MIXER_COUNT = 3
	local RESET_BTN_H = 32
	local APP_PADDING_TOP = 46
	local APP_PADDING_BOT = 16
	local secAppH = APP_PADDING_TOP + (MIXER_ROW_H * MIXER_COUNT) + RESET_BTN_H + APP_PADDING_BOT + 8
	local secApp = CreateSectionCard("Appearance Colors", secAppH)

	local colorMixers = {}

	local function AddColorSetting(parentCard, labelText, key)
		local row = vgui.Create("DPanel", parentCard)
		row:Dock(TOP)
		row:SetTall(MIXER_ROW_H)
		row:DockMargin(0, 0, 0, 0)
		row.Paint = function(self, w, h)
			surface.SetDrawColor(35, 38, 48)
			surface.DrawRect(0, h - 1, w, 1)
		end

		local lbl = vgui.Create("DLabel", row)
		lbl:SetText(labelText)
		lbl:SetTextColor(Color(180, 190, 210))
		lbl:Dock(LEFT)
		lbl:SetWide(110)
		lbl:SetContentAlignment(7)
		lbl:DockMargin(0, 4, 0, 4)

		local swatch = vgui.Create("DPanel", row)
		swatch:Dock(LEFT)
		swatch:SetWide(20)
		swatch:DockMargin(0, 8, 6, 8)
		swatch.Paint = function(self, w, h)
			draw.RoundedBox(3, 0, 0, w, h, PinnedPanels.Settings[key])
			surface.SetDrawColor(80, 85, 100)
			surface.DrawOutlinedRect(0, 0, w, h, 1)
		end

		local mixer = vgui.Create("DColorMixer", row)
		mixer:Dock(FILL)
		mixer:DockMargin(0, 4, 0, 4)
		mixer:SetPalette(false)
		mixer:SetAlphaBar(true)
		mixer:SetWangs(true)
		mixer:SetColor(PinnedPanels.Settings[key])
		mixer.ValueChanged = function(self, col)
			PinnedPanels.Settings[key] = col
			PinnedPanels.SaveSettings()
		end

		colorMixers[key] = mixer
		return row
	end

	AddColorSetting(secApp, "Background", "bg")
	AddColorSetting(secApp, "Header Bar", "header")
	AddColorSetting(secApp, "Header Text", "text")

	local btnContainer = vgui.Create("DPanel", secApp)
	btnContainer:Dock(TOP)
	btnContainer:SetTall(RESET_BTN_H)
	btnContainer:DockMargin(0, 8, 0, 0)
	btnContainer.Paint = function() end

	local resetBtn = vgui.Create("DButton", btnContainer)
	resetBtn:SetText("Reset Colors to Default")
	resetBtn:SetIcon("icon16/arrow_undo.png")
	resetBtn:Dock(LEFT)
	resetBtn:SetWide(200)
	StyleDarkButton(resetBtn)
	resetBtn.DoClick = function()
		PinnedPanels.Settings.bg = Color(235, 238, 242, 250)
		PinnedPanels.Settings.header = Color(32, 35, 42, 255)
		PinnedPanels.Settings.text = Color(240, 245, 255, 255)
		PinnedPanels.SaveSettings()

		for key, mixer in pairs(colorMixers) do
			if IsValid(mixer) then
				mixer:SetColor(PinnedPanels.Settings[key])
			end
		end
	end

	local PREVIEW_H = 80
	local previewCard = CreateSectionCard("Live Preview", APP_PADDING_TOP + PREVIEW_H + APP_PADDING_BOT)

	local preview = vgui.Create("DPanel", previewCard)
	preview:Dock(FILL)
	preview.Paint = function(self, w, h)
		local th = PinnedPanels.Settings
		draw.RoundedBox(6, 0, 0, w, h, th.bg)
		draw.RoundedBoxEx(6, 0, 0, w, 26, th.header, true, true, false, false)
		draw.SimpleText("Example Panel Title", "DermaDefaultBold", 10, 13, th.text,
			TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		draw.SimpleText("(this is how your pinned panels will look)", "DermaDefault",
			10, h - 10, Color(th.text.r, th.text.g, th.text.b, 120),
			TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM)
	end

	local dangerCard = CreateSectionCard("Danger Zone", 78)

	local unpinAllBtn = vgui.Create("DButton", dangerCard)
	unpinAllBtn:SetText("Unpin All Panels")
	unpinAllBtn:SetIcon("icon16/cross.png")
	unpinAllBtn:Dock(TOP)
	unpinAllBtn:SetTall(30)
	unpinAllBtn.Paint = function(self, w, h)
		local bg = self:IsHovered() and Color(180, 50, 50) or Color(140, 35, 35)
		draw.RoundedBox(4, 0, 0, w, h, bg)
		surface.SetDrawColor(60, 20, 20)
		surface.DrawOutlinedRect(0, 0, w, h, 1)
		draw.SimpleText(self:GetText(), "DermaDefaultBold", w / 2, h / 2,
			Color(240, 200, 200), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end
	unpinAllBtn.DoClick = function()
		PinnedPanels.UnpinAll()
	end

	return root
end
