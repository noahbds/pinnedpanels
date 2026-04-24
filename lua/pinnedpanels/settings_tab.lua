function PinnedPanels.CreateSettingsTab(parent)
	local root = vgui.Create("DPanel", parent)
	root:Dock(FILL)
	root.Paint = function(self, w, h)
		draw.RoundedBox(0, 0, 0, w, h, Color(30, 32, 40, 255))
	end

	local scroll = vgui.Create("DScrollPanel", root)
	scroll:Dock(FILL)
	scroll:DockMargin(16, 16, 16, 16)

	local function CreateSectionCard(title, height)
		local card = vgui.Create("DPanel", scroll)
		card:Dock(TOP)
		card:SetTall(height)
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

	local secBehavior = CreateSectionCard("Behavior", 85)

	local autoRestoreBox = vgui.Create("DCheckBoxLabel", secBehavior)
	autoRestoreBox:SetText("Auto-restore pinned panels when joining the server")
	autoRestoreBox:SetTextColor(Color(220, 225, 235))
	autoRestoreBox:Dock(TOP)
	autoRestoreBox:SetValue(PinnedPanels.Settings.autoRestore)
	autoRestoreBox.OnChange = function(self, val)
		PinnedPanels.Settings.autoRestore = val
		PinnedPanels.SaveSettings()
	end

	local secInteract = CreateSectionCard("Interact Mode (Cursor Toggle)", 130)

	local interactHelp = vgui.Create("DLabel", secInteract)
	interactHelp:SetText("Press your bound key in-game to show the cursor and freely interact with your pinned panels.")
	interactHelp:SetTextColor(Color(150, 160, 175))
	interactHelp:SetWrap(true)
	interactHelp:Dock(TOP)
	interactHelp:DockMargin(0, 0, 0, 12)

	local bindRow = vgui.Create("DPanel", secInteract)
	bindRow:Dock(TOP)
	bindRow:SetTall(28)
	bindRow.Paint = function() end

	local keyDisplay = vgui.Create("DLabel", bindRow)
	keyDisplay:Dock(LEFT)
	keyDisplay:SetWide(200)
	keyDisplay:SetFont("DermaDefaultBold")

	local function UpdateKeyDisplay()
		if not IsValid(keyDisplay) then return end
		local code = PinnedPanels.InteractMode.KeyCode
		if not code or code == KEY_NONE then
			keyDisplay:SetText("Current key: [ Not bound ]")
			keyDisplay:SetTextColor(Color(200, 80, 80))
		else
			keyDisplay:SetText("Current key: [ " .. input.GetKeyName(code) .. " ]")
			keyDisplay:SetTextColor(Color(80, 210, 120))
		end
	end
	UpdateKeyDisplay()

	local openBindBtn = vgui.Create("DButton", bindRow)
	openBindBtn:SetText("Change Key...")
	openBindBtn:SetIcon("icon16/keyboard.png")
	openBindBtn:Dock(LEFT)
	openBindBtn:SetWide(120)
	openBindBtn:DockMargin(0, 0, 8, 0)
	StyleDarkButton(openBindBtn)
	openBindBtn.DoClick = function() PinnedPanels.OpenKeyBindFrame(UpdateKeyDisplay) end

	local clearBtn = vgui.Create("DButton", bindRow)
	clearBtn:SetText("Clear")
	clearBtn:SetIcon("icon16/cross.png")
	clearBtn:Dock(LEFT)
	clearBtn:SetWide(70)
	clearBtn:DockMargin(0, 0, 8, 0)
	StyleDarkButton(clearBtn)
	clearBtn.DoClick = function()
		PinnedPanels.InteractMode.KeyCode = KEY_NONE
		RunConsoleCommand("pp_interact_key", tostring(KEY_NONE))
		UpdateKeyDisplay()
	end

	local toggleBtn = vgui.Create("DButton", bindRow)
	toggleBtn:SetText("Toggle Mode Now")
	toggleBtn:SetIcon("icon16/cursor.png")
	toggleBtn:Dock(LEFT)
	toggleBtn:SetWide(140)
	StyleDarkButton(toggleBtn)
	toggleBtn.DoClick = function() PinnedPanels.InteractMode.Toggle() end

	local secApp = CreateSectionCard("Appearance Colors", 550)

	local function AddColorSetting(parentCard, labelText, key)
		local row = vgui.Create("DPanel", parentCard)
		row:Dock(TOP)
		row:SetTall(140)
		row:DockMargin(0, 0, 0, 12)
		row.Paint = function() end

		local lbl = vgui.Create("DLabel", row)
		lbl:SetText(labelText)
		lbl:SetTextColor(Color(220, 225, 235))
		lbl:Dock(LEFT)
		lbl:SetWide(140)
		lbl:SetContentAlignment(7)
		lbl:DockMargin(0, 4, 0, 0)

		local mixer = vgui.Create("DColorMixer", row)
		mixer:Dock(LEFT)
		mixer:SetWide(300)
		mixer:SetPalette(false)
		mixer:SetAlphaBar(true)
		mixer:SetWangs(true)
		mixer:SetColor(PinnedPanels.Settings[key])
		mixer.ValueChanged = function(self, col)
			PinnedPanels.Settings[key] = col
			PinnedPanels.SaveSettings()
		end
	end

	AddColorSetting(secApp, "Background Color", "bg")
	AddColorSetting(secApp, "Header Bar Color", "header")
	AddColorSetting(secApp, "Header Text Color", "text")

	local btnContainer = vgui.Create("DPanel", secApp)
	btnContainer:Dock(TOP)
	btnContainer:SetTall(32)
	btnContainer.Paint = function() end

	local resetBtn = vgui.Create("DButton", btnContainer)
	resetBtn:SetText("Reset Colors to Default")
	resetBtn:Dock(LEFT)
	resetBtn:SetWide(200)
	StyleDarkButton(resetBtn)
	resetBtn.DoClick = function()
		PinnedPanels.Settings.bg = Color(235, 238, 242, 250)
		PinnedPanels.Settings.header = Color(32, 35, 42, 255)
		PinnedPanels.Settings.text = Color(240, 245, 255, 255)
		PinnedPanels.SaveSettings()

		if IsValid(root) then
			local p = root:GetParent()
			root:Remove()
			PinnedPanels.CreateSettingsTab(p)
		end
	end

	return root
end
