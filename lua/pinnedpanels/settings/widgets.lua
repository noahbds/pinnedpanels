local C = PinnedPanels.C

-- ── Settings UI Widget Library ───────────────────────────────────────────────

PinnedPanels.SettingsUI = PinnedPanels.SettingsUI or {}
local SUI = PinnedPanels.SettingsUI

-- ── Button Styling ───────────────────────────────────────────────────────────
function SUI.StyleDarkButton(btn)
	btn:SetTextColor(C.textLight)
	btn.Paint = function(self, w, h)
		local bg = self:IsHovered() and C.btnBgHov or C.btnBg
		draw.RoundedBox(4, 0, 0, w, h, bg)
		surface.SetDrawColor(C.btnOutline)
		surface.DrawOutlinedRect(0, 0, w, h, 1)
	end
end

-- ── Section Card (auto-sizes to its docked children) ─────────────────────────
function SUI.Card(parent, title)
	local card = vgui.Create("DPanel", parent)
	card:Dock(TOP)
	card:DockMargin(0, 0, 0, 12)
	card:DockPadding(16, 42, 16, 14)
	card.Paint = function(self, w, h)
		draw.RoundedBox(6, 0, 0, w, h, C.bgCard)
		draw.RoundedBoxEx(6, 0, 0, w, 30, C.bgCardHdr, true, true, false, false)
		draw.SimpleText(title, "DermaDefaultBold", 12, 15, C.textTitle, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	end
	card.PerformLayout = function(self)
		local _, _, _, padBottom = self:GetDockPadding()
		local tall = 0
		for _, child in ipairs(self:GetChildren()) do
			if IsValid(child) and child:IsVisible() then
				local _, y = child:GetPos()
				tall = math.max(tall, y + child:GetTall())
			end
		end
		self:SetTall(tall + padBottom)
	end
	return card
end

-- ── Help Text ────────────────────────────────────────────────────────────────
function SUI.Help(parent, text)
	local lbl = vgui.Create("DLabel", parent)
	lbl:SetText(text)
	lbl:SetTextColor(C.textBody)
	lbl:SetWrap(true)
	lbl:Dock(TOP)
	lbl:DockMargin(0, 0, 0, 10)
	lbl:SetAutoStretchVertical(true)
	return lbl
end

-- ── Transparent Button Row ───────────────────────────────────────────────────
function SUI.Row(parent, tall)
	local row = vgui.Create("DPanel", parent)
	row:Dock(TOP)
	row:SetTall(tall or 30)
	row.Paint = function() end
	return row
end

function SUI.Button(parent, text, icon, wide, onClick)
	local btn = vgui.Create("DButton", parent)
	btn:SetText(text)
	if icon then btn:SetIcon(icon) end
	btn:Dock(LEFT)
	btn:SetWide(wide)
	btn:DockMargin(0, 0, 6, 0)
	SUI.StyleDarkButton(btn)
	btn.DoClick = onClick
	return btn
end

-- ── Checkbox Row ─────────────────────────────────────────────────────────────
function SUI.CheckRow(parent, label, value, onChange)
	local box = vgui.Create("DCheckBoxLabel", parent)
	box:SetText(label)
	box:SetTextColor(C.textLight)
	box:Dock(TOP)
	box:DockMargin(0, 0, 0, 10)
	box:SetValue(value and true or false)
	box.OnChange = function(_, val)
		onChange(val)
		PinnedPanels.SaveSettings()
	end
	return box
end

-- ── Slider Row (debounced save) ──────────────────────────────────────────────
function SUI.SliderRow(parent, opts)
	local slider = vgui.Create("DNumSlider", parent)
	slider:Dock(TOP)
	slider:SetTall(30)
	slider:DockMargin(0, 0, 0, 8)
	slider:SetText(opts.label)
	slider:SetMin(opts.min)
	slider:SetMax(opts.max)
	slider:SetDecimals(0)
	slider:SetValue(opts.value)
	slider.Label:SetTextColor(C.textLight)
	slider.OnValueChanged = function(_, val)
		opts.onChange(math.Round(val))
		timer.Create(opts.saveTimer, 0.4, 1, function()
			PinnedPanels.SaveSettings()
		end)
	end
	return slider
end

-- ── Color Mixer Popup ────────────────────────────────────────────────────────
function SUI.OpenColorPopup(opts)
	local popup = vgui.Create("DFrame")
	popup:SetTitle(opts.title)
	popup:SetSize(260, 220)
	popup:SetDeleteOnClose(true)
	popup:MakePopup()
	popup:SetDraggable(true)
	popup:SetSizable(false)

	if IsValid(opts.anchor) then
		local sx, sy = opts.anchor:LocalToScreen(0, 0)
		popup:SetPos(
			math.Clamp(sx + 50, 0, ScrW() - 260),
			math.Clamp(sy - 60, 0, ScrH() - 220))
	else
		popup:Center()
	end

	popup.Paint = function(_, w, h)
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
	mixer:SetColor(opts.color)
	mixer.ValueChanged = function(_, col)
		opts.onChange(Color(col.r, col.g, col.b, col.a))
	end

	return popup
end

-- ── Color Swatch Row ─────────────────────────────────────────────────────────
function SUI.ColorRow(parent, opts)
	local row = SUI.Row(parent, 28)
	row:DockMargin(0, 0, 0, 4)

	local lbl = vgui.Create("DLabel", row)
	lbl:SetText(opts.label)
	lbl:SetTextColor(C.textLabel)
	lbl:Dock(LEFT)
	lbl:SetWide(120)
	lbl:SetContentAlignment(4)

	local swatch = vgui.Create("DButton", row)
	swatch:SetText("")
	swatch:Dock(LEFT)
	swatch:SetWide(40)
	swatch:DockMargin(0, 3, 8, 3)
	swatch.Paint = function(self, w, h)
		draw.RoundedBox(4, 0, 0, w, h, opts.get() or Color(128, 128, 128))
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
		local col = opts.get()
		if col then
			valLbl:SetText(string.format("R:%d G:%d B:%d A:%d", col.r, col.g, col.b, col.a))
		else
			valLbl:SetText("")
		end
	end
	UpdateValLbl()

	swatch.DoClick = function()
		if IsValid(opts.popups[opts.key]) then
			opts.popups[opts.key]:Remove()
			opts.popups[opts.key] = nil
			return
		end
		local popup = SUI.OpenColorPopup({
			title    = opts.popupTitle or opts.label,
			anchor   = swatch,
			color    = opts.get(),
			onChange = function(col)
				opts.set(col)
				PinnedPanels.SaveSettings()
				UpdateValLbl()
			end,
		})
		opts.popups[opts.key] = popup
		popup.OnClose = function()
			if opts.popups[opts.key] == popup then opts.popups[opts.key] = nil end
		end
	end

	return row, UpdateValLbl
end

-- ── Keybind Control Row ──────────────────────────────────────────────────────
function SUI.KeyControlRow(parent, opts)
	local row = SUI.Row(parent, 30)

	local keyDisplay = vgui.Create("DLabel", row)
	keyDisplay:Dock(LEFT)
	keyDisplay:SetWide(210)
	keyDisplay:SetFont("DermaDefaultBold")

	local function UpdateDisplay()
		if not IsValid(keyDisplay) then return end
		local code = opts.get()
		if not code or code == KEY_NONE then
			keyDisplay:SetText("Current key: [ Not bound ]")
			keyDisplay:SetTextColor(C.errorRed)
		else
			keyDisplay:SetText("Current key: [ " .. string.upper(input.GetKeyName(code) or "?") .. " ]")
			keyDisplay:SetTextColor(C.keyBound)
		end
	end
	UpdateDisplay()

	SUI.Button(row, "Change Key...", "icon16/keyboard.png", 130, function()
		PinnedPanels.OpenKeyBindFrame({
			title   = opts.bindTitle,
			get     = opts.get,
			set     = opts.set,
			onSaved = UpdateDisplay,
			ignore  = opts.ignore,
		})
	end)

	SUI.Button(row, "Clear", "icon16/cross.png", 70, function()
		opts.set(KEY_NONE)
		UpdateDisplay()
	end)

	if opts.extraText then
		SUI.Button(row, opts.extraText, opts.extraIcon, opts.extraWide or 110, opts.extraClick)
	end

	return row, UpdateDisplay
end

-- ── Code Popup (Export / Import) ─────────────────────────────────────────────
function SUI.ShowCodePopup(title, code, onApply)
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
		SUI.StyleDarkButton(applyBtn)
		applyBtn.DoClick = function()
			local value = entry:GetValue()
			p:Remove()
			onApply(value)
		end
	else
		entry:RequestFocus()
		entry:SelectAllOnFocus(true)
		entry:SelectAll()
		local hintLbl = vgui.Create("DLabel", bar)
		hintLbl:Dock(FILL)
		hintLbl:DockMargin(10, 0, 0, 0)
		hintLbl:SetText("Copy this code (Ctrl+C) and share it.")
		hintLbl:SetTextColor(C.textMuted)
	end

	return p
end
