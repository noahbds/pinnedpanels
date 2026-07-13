-- ── Command Palette (fuzzy launcher for tools, panels & actions) ─────────────
local C = PinnedPanels.C

local CVAR_KEY = "pp_palette_key"
CreateClientConVar(CVAR_KEY, tostring(KEY_NONE), true, false, "PinnedPanels command palette key")

surface.CreateFont("PP_PaletteItem", { font = "Roboto", size = 17, weight = 500 })
surface.CreateFont("PP_PaletteSub",  { font = "Roboto", size = 12, weight = 400 })
surface.CreateFont("PP_PaletteQuery", { font = "Roboto", size = 20, weight = 400 })

-- ── Entry Sources ────────────────────────────────────────────────────────────
local function BuildEntries()
	local list = {}

	local function add(cat, text, sub, icon, run)
		list[#list + 1] = { cat = cat, text = text or "", sub = sub, icon = icon, run = run }
	end

	-- Global actions
	add("Action", "Toggle Cursor Mode", "Show cursor to interact", "icon16/cursor.png",
		function() PinnedPanels.CursorMode.Toggle() end)
	add("Action", "Auto-Arrange Panels", "Tile visible panels", "icon16/application_tile_horizontal.png",
		function() PinnedPanels.AutoArrange() end)
	add("Action", "Auto-Size All Panels", "Fit every panel to its content", "icon16/arrow_inout.png",
		function() RunConsoleCommand("pp_autosize_all") end)
	if PinnedPanels.HasClosedPanels and PinnedPanels.HasClosedPanels() then
		add("Action", "Reopen Last Closed Panel", "Undo the last unpin", "icon16/arrow_undo.png",
			function() PinnedPanels.ReopenLastClosed() end)
	end
	add("Action", "Restore All Minimized", "Bring back minimized panels", "icon16/application_get.png",
		function() PinnedPanels.RestoreAllFromTaskbar() end)
	add("Action", "Unpin All Panels", "Remove every pinned panel", "icon16/cross.png",
		function() PinnedPanels.UnpinAll() end)

	-- Currently pinned panels
	for id, pin in pairs(PinnedPanels.Pins) do
		if IsValid(pin.frame) and (pin.kind == "group" or not PinnedPanels.GetGroupForPanel(id)) then
			local pid = id
			add("Pinned", pin.title or id, "Show / bring to front", "icon16/application_double.png",
				function()
					local p = PinnedPanels.Pins[pid]
					if not p or not IsValid(p.frame) then return end
					if p.minimized then PinnedPanels.RestoreFromTaskbar(pid) end
					p.frame:SetVisible(true)
					p.frame:MoveToFront()
					if not PinnedPanels.CursorMode.Active then PinnedPanels.CursorMode.Enable() end
				end)
		end
	end

	-- Click-through panels need a mouse-free way back to interactive
	for id, pin in pairs(PinnedPanels.Pins) do
		if pin.clickThrough and IsValid(pin.frame) then
			local pid = id
			add("Action", "Restore Interaction: " .. (pin.title or id), "Disable click-through", "icon16/cursor.png",
				function()
					local p = PinnedPanels.Pins[pid]
					if not p then return end
					p.clickThrough = false
					PinnedPanels.Save()
					if PinnedPanels.UpdatePanelStates then PinnedPanels.UpdatePanelStates() end
				end)
		end
	end

	-- All tools (pin)
	for _, t in ipairs(PinnedPanels.GetAllTools()) do
		local itemName, nice, cp = t.itemName, t.niceName, t.cpFunc
		add("Tool", nice, t.category, "icon16/wrench.png",
			function() PinnedPanels.Pin("PP_" .. itemName, nice, cp) end)
	end

	-- All content browsers (pin)
	for _, t in ipairs(PinnedPanels.GetAllCreationTabs()) do
		local cid, label, fn = t.id, t.label, t.func
		add("Content", label, "Content browser", t.icon or "icon16/application_view_list.png",
			function() PinnedPanels.Pin(cid, label, fn, false, PinnedPanels.CREATION_OPTS) end)
	end

	return list
end

-- ── Fuzzy Scoring (lower = better; nil = no match) ───────────────────────────
local function Score(hay, needle)
	hay = hay:lower()
	local idx = hay:find(needle, 1, true)
	if idx then return idx end
	-- subsequence fallback
	local hi = 1
	for i = 1, #needle do
		local f = hay:find(needle:sub(i, i), hi, true)
		if not f then return nil end
		hi = f + 1
	end
	return 500 + #hay
end

local CAT_ORDER = { Action = 1, Pinned = 2, Tool = 3, Content = 4 }

local function FilterEntries(entries, query)
	query = string.Trim((query or ""):lower())
	local out = {}
	if query == "" then
		for _, e in ipairs(entries) do out[#out + 1] = { e = e, s = 0 } end
	else
		for _, e in ipairs(entries) do
			local s = Score(e.text, query)
			local subS = e.sub and Score(e.sub, query) or nil
			if subS and (not s or subS + 200 < s) then s = subS + 200 end
			if s then out[#out + 1] = { e = e, s = s } end
		end
	end
	table.sort(out, function(a, b)
		if a.s ~= b.s then return a.s < b.s end
		local ca, cb = CAT_ORDER[a.e.cat] or 9, CAT_ORDER[b.e.cat] or 9
		if ca ~= cb then return ca < cb end
		return a.e.text:lower() < b.e.text:lower()
	end)
	local res = {}
	for i = 1, math.min(#out, 80) do res[i] = out[i].e end
	return res, #out
end

-- ── Palette UI ───────────────────────────────────────────────────────────────
function PinnedPanels.OpenCommandPalette()
	if IsValid(PinnedPanels._palette) then
		PinnedPanels._palette:Remove()
		PinnedPanels._palette = nil
		return
	end

	local entries = BuildEntries()
	gui.EnableScreenClicker(true)

	local W, H       = 580, 470
	local HDR_H      = 48
	local FOOT_H     = 24
	local ROW_H      = 44

	local frame = vgui.Create("DFrame")
	frame:SetSize(W, H)
	frame:Center()
	frame:SetTitle("")
	frame:ShowCloseButton(false)
	frame:SetDraggable(false)
	frame:MakePopup()
	PinnedPanels._palette = frame

	frame.OnRemove = function()
		PinnedPanels._palette = nil
		-- Only release the cursor if nothing else still needs it.
		if not PinnedPanels.PanelsInteractive() then
			gui.EnableScreenClicker(false)
		end
	end

	local rows, sel, resultTotal = {}, 1, 0

	frame.Paint = function(_, w, h)
		draw.RoundedBox(8, 0, 0, w, h, C.bgPopup)
		draw.RoundedBoxEx(8, 0, 0, w, HDR_H, C.colorPopupHdr, true, true, false, false)
		surface.SetDrawColor(C.accent.r, C.accent.g, C.accent.b, 180)
		surface.DrawRect(0, HDR_H - 1, w, 1)

		draw.RoundedBoxEx(8, 0, h - FOOT_H, w, FOOT_H, C.paletteFooterBg, false, false, true, true)
		draw.SimpleText("Up / Down: navigate    Enter: run    Esc: close", "PP_PaletteSub",
			14, h - FOOT_H / 2, C.textMuted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		local countTxt = (#rows >= resultTotal) and (#rows .. " results")
			or (#rows .. " of " .. resultTotal .. " results")
		draw.SimpleText(countTxt, "PP_PaletteSub",
			w - 14, h - FOOT_H / 2, C.textInfo, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)

		surface.SetDrawColor(C.searchBorder)
		surface.DrawOutlinedRect(0, 0, w, h, 1)
	end

	local search = vgui.Create("DTextEntry", frame)
	search:SetPos(16, 10)
	search:SetSize(W - 32, 28)
	search:SetFont("PP_PaletteQuery")
	search:SetPlaceholderText("Search tools, panels & actions…")
	search:SetUpdateOnType(true)
	search:SetPaintBackground(false)
	search:SetTextColor(C.textBright)
	search:SetCursorColor(C.textBright)
	search:RequestFocus()

	local list = vgui.Create("DScrollPanel", frame)
	list:SetPos(8, HDR_H + 4)
	list:SetSize(W - 16, H - HDR_H - FOOT_H - 8)

	-- While the keyboard scrolls the list, rows slide under the stationary
	-- mouse and fire OnCursorEntered; ignore those until the mouse really moves.
	local guardX, guardY
	local function ArmHoverGuard()
		guardX, guardY = gui.MouseX(), gui.MouseY()
	end

	local function Activate(entry)
		if not entry then return end
		frame:Remove()
		local ok, err = pcall(entry.run)
		if not ok then ErrorNoHalt("[PinnedPanels] Palette action error: " .. tostring(err) .. "\n") end
	end

	-- Scroll just enough to keep the selection in view — no animated centering.
	local function EnsureVisible()
		local r = rows[sel]
		if not IsValid(r) then return end
		list:InvalidateLayout(true)
		list:GetCanvas():InvalidateLayout(true)

		local _, y   = r:GetPos()
		local vbar   = list:GetVBar()
		local viewH  = list:GetTall()
		local scroll = vbar:GetScroll()
		if y - 4 < scroll then
			vbar:SetScroll(y - 4)
		elseif y + r:GetTall() + 4 > scroll + viewH then
			vbar:SetScroll(y + r:GetTall() + 4 - viewH)
		end
	end

	local function HighlightRows(scrollToSel)
		for i, r in ipairs(rows) do r.selected = (i == sel) end
		if scrollToSel then
			ArmHoverGuard()
			EnsureVisible()
		end
	end

	local function Rebuild()
		list:Clear()
		rows = {}
		sel = 1
		local vbar = list:GetVBar()
		if IsValid(vbar) then vbar:SetScroll(0) end
		ArmHoverGuard()

		local filtered
		filtered, resultTotal = FilterEntries(entries, search:GetValue())

		if #filtered == 0 then
			local empty = vgui.Create("DLabel", list)
			empty:Dock(TOP)
			empty:DockMargin(12, 14, 12, 0)
			empty:SetText("No matches.")
			empty:SetFont("PP_PaletteItem")
			empty:SetContentAlignment(5)
			empty:SetTextColor(C.textMuted)
			return
		end

		for i, entry in ipairs(filtered) do
			local row = vgui.Create("DButton", list)
			row:Dock(TOP)
			row:DockMargin(4, 2, 4, 0)
			row:SetTall(ROW_H)
			row:SetText("")
			row.selected = (i == sel)
			if entry.icon and entry.icon ~= "" then row._mat = Material(entry.icon, "smooth mips") end

			row.DoClick = function() Activate(entry) end
			row.OnCursorEntered = function()
				if guardX then
					local mx, my = gui.MouseX(), gui.MouseY()
					if mx == guardX and my == guardY then return end
					guardX, guardY = nil, nil
				end
				sel = i
				HighlightRows(false)
			end

			row.Paint = function(self, w, h)
				if self.selected then
					draw.RoundedBox(5, 0, 0, w, h, C.paletteSelBg)
					surface.SetDrawColor(C.accent)
					surface.DrawRect(0, 4, 3, h - 8)
				elseif self:IsHovered() then
					draw.RoundedBox(5, 0, 0, w, h, C.bgHover)
				end

				local tx = 14
				if self._mat and not self._mat:IsError() then
					surface.SetDrawColor(255, 255, 255, 255)
					surface.SetMaterial(self._mat)
					surface.DrawTexturedRect(14, h / 2 - 8, 16, 16)
					tx = 40
				end

				local hasSub  = entry.sub and entry.sub ~= ""
				local mainCol = self.selected and C.textBright or C.textLight
				if hasSub then
					draw.SimpleText(entry.text, "PP_PaletteItem", tx, 7,
						mainCol, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
					draw.SimpleText(entry.sub, "PP_PaletteSub", tx, h - 7,
						self.selected and C.textLight or C.textMuted, TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM)
				else
					draw.SimpleText(entry.text, "PP_PaletteItem", tx, h / 2,
						mainCol, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
				end
				draw.SimpleText(entry.cat, "PP_PaletteSub", w - 12, h / 2,
					self.selected and C.textLight or C.textInfo, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
			end

			rows[i] = row
		end
		HighlightRows(true)
	end

	search.OnValueChange = function() Rebuild() end

	local function Move(delta)
		if #rows == 0 then return end
		sel = (sel - 1 + delta) % #rows + 1
		HighlightRows(true)
	end

	search.OnKeyCodeTyped = function(_, code)
		if code == KEY_ESCAPE then
			frame:Remove()
			return true
		elseif code == KEY_ENTER or code == KEY_PAD_ENTER then
			local r = rows[sel]
			if IsValid(r) and isfunction(r.DoClick) then r:DoClick() end
			return true
		elseif code == KEY_DOWN or code == KEY_TAB then
			Move(1)
			return true
		elseif code == KEY_UP then
			Move(-1)
			return true
		elseif code == KEY_PAGEDOWN then
			if #rows > 0 then sel = math.min(#rows, sel + 8) HighlightRows(true) end
			return true
		elseif code == KEY_PAGEUP then
			if #rows > 0 then sel = math.max(1, sel - 8) HighlightRows(true) end
			return true
		elseif code == KEY_HOME and search:GetValue() == "" then
			if #rows > 0 then sel = 1 HighlightRows(true) end
			return true
		elseif code == KEY_END and search:GetValue() == "" then
			if #rows > 0 then sel = #rows HighlightRows(true) end
			return true
		end
	end

	Rebuild()
end

concommand.Add("pp_palette", PinnedPanels.OpenCommandPalette, nil, "Open the PinnedPanels command palette")

-- ── Open Hotkey ──────────────────────────────────────────────────────────────
local paletteKey = tonumber(GetConVar(CVAR_KEY):GetString()) or KEY_NONE
cvars.AddChangeCallback(CVAR_KEY, function(_, _, new)
	paletteKey = tonumber(new) or KEY_NONE
end, "PinnedPanels_PaletteKey")

PinnedPanels.GetPaletteKey = function() return paletteKey end
PinnedPanels.SetPaletteKey = function(code)
	paletteKey = code or KEY_NONE
	RunConsoleCommand(CVAR_KEY, tostring(paletteKey))
end

local paletteDown = false
hook.Add("Think", "PinnedPanels_PaletteKey", function()
	if not paletteKey or paletteKey == KEY_NONE then return end
	local down = input.IsKeyDown(paletteKey)
	if down and not paletteDown and not IsValid(vgui.GetKeyboardFocus()) then
		PinnedPanels.OpenCommandPalette()
	end
	paletteDown = down
end)
