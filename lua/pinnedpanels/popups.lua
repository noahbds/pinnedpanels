local C = PinnedPanels.C

-- ── Color Changer Popup ──────────────────────────────────────────────────────
function PinnedPanels.OpenColorChanger(id)
	local pin = PinnedPanels.Pins[id]
	if not pin or not IsValid(pin.frame) then return end

	if IsValid(PinnedPanels._colorFrame) then PinnedPanels._colorFrame:Remove() end

	local frame = vgui.Create("DFrame")
	frame:SetTitle("")
	frame:SetSize(320, 420)
	frame:Center()
	frame:SetDraggable(true)
	frame:SetSizable(false)
	frame:SetDeleteOnClose(true)
	frame:MakePopup()
	PinnedPanels._colorFrame = frame

	frame.Paint = function(self, w, h)
		draw.RoundedBox(6, 0, 0, w, h, C.colorPopupBg)
		draw.RoundedBoxEx(6, 0, 0, w, 28, C.colorPopupHdr, true, true, false, false)
		surface.SetDrawColor(C.colorPopupBorder)
		surface.DrawOutlinedRect(0, 0, w, h, 1)
		draw.SimpleText("Panel Colors: " .. pin.title, "DermaDefaultBold", 10, 14,
			C.textBright, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	end

	local scroll = vgui.Create("DScrollPanel", frame)
	scroll:Dock(FILL)
	scroll:DockMargin(8, 8, 8, 8)

	local function Repaint()
		pin.frame.Paint = PinnedPanels.GetFramePaint(pin.title, id)
	end

	local function AddColorRow(labelText, key, defaultCol)
		local row = vgui.Create("DPanel", scroll)
		row:Dock(TOP)
		row:SetTall(24)
		row:DockMargin(0, 0, 0, 4)
		row.Paint = function() end

		local lbl = vgui.Create("DLabel", row)
		lbl:SetText(labelText)
		lbl:SetTextColor(C.textLabel)
		lbl:Dock(LEFT)
		lbl:SetWide(90)

		local swatch = vgui.Create("DPanel", row)
		swatch:Dock(LEFT)
		swatch:SetWide(24)
		swatch:DockMargin(0, 2, 8, 2)
		swatch.Paint = function(self, w, h)
			draw.RoundedBox(3, 0, 0, w, h, pin[key] or defaultCol)
			surface.SetDrawColor(C.swatchBorder)
			surface.DrawOutlinedRect(0, 0, w, h, 1)
		end

		local clearBtn = vgui.Create("DButton", row)
		clearBtn:SetText("Reset")
		clearBtn:SetWide(50)
		clearBtn:Dock(RIGHT)
		clearBtn:DockMargin(4, 2, 0, 2)
		clearBtn:SetTextColor(C.textMuted)
		clearBtn.Paint = function(self, w, h)
			draw.RoundedBox(3, 0, 0, w, h, self:IsHovered() and C.btnBgHov or C.btnBg)
		end
		clearBtn.DoClick = function()
			pin[key] = nil
			Repaint()
			PinnedPanels.Save()
		end

		local mixer = vgui.Create("DColorMixer", scroll)
		mixer:Dock(TOP)
		mixer:SetTall(100)
		mixer:DockMargin(0, 0, 0, 8)
		mixer:SetPalette(false)
		mixer:SetAlphaBar(true)
		mixer:SetWangs(true)
		mixer:SetColor(pin[key] or defaultCol)
		mixer.ValueChanged = function(self, col)
			pin[key] = Color(col.r, col.g, col.b, col.a)
			Repaint()
			PinnedPanels.Save()
		end
	end

	AddColorRow("Background", "customBg", PinnedPanels.Settings.bg)
	AddColorRow("Header", "customHeader", PinnedPanels.Settings.header)
	AddColorRow("Text", "customText", PinnedPanels.Settings.text)

	local resetAll = vgui.Create("DButton", scroll)
	resetAll:SetText("Reset All to Global")
	resetAll:SetIcon("icon16/arrow_undo.png")
	resetAll:Dock(TOP)
	resetAll:SetTall(28)
	resetAll:DockMargin(0, 4, 0, 0)
	resetAll:SetTextColor(C.textLight)
	resetAll.Paint = function(self, w, h)
		draw.RoundedBox(4, 0, 0, w, h, self:IsHovered() and C.btnBgHov or C.btnBg)
	end
	resetAll.DoClick = function()
		pin.customBg, pin.customHeader, pin.customText = nil, nil, nil
		Repaint()
		PinnedPanels.Save()
		frame:Close()
	end
end

-- ── Rename Popup ─────────────────────────────────────────────────────────────
function PinnedPanels.OpenRenamePopup(id)
	local pin = PinnedPanels.Pins[id]
	if not pin then return end

	Derma_StringRequest(
		PinnedPanels.L("rename_title"),
		PinnedPanels.L("rename_desc"),
		pin.title,
		function(newName)
			if newName and newName ~= "" then
				pin.title = newName
				if IsValid(pin.frame) then
					pin.frame.Paint = PinnedPanels.GetFramePaint(newName, id)
				end
				PinnedPanels.Save()
				hook.Run("PinnedPanels_StateChanged")
			end
		end,
		function() end,
		"OK",
		"Cancel"
	)
end
