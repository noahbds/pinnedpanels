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
	return res
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

	local W, H = 560, 460
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

	frame.Paint = function(_, w, h)
		draw.RoundedBox(8, 0, 0, w, h, C.bgPopup)
		draw.RoundedBoxEx(8, 0, 0, w, 46, C.colorPopupHdr, true, true, false, false)
		surface.SetDrawColor(C.accent)
		surface.DrawOutlinedRect(0, 0, w, h, 1)
	end

	local search = vgui.Create("DTextEntry", frame)
	search:SetPos(14, 10)
	search:SetSize(W - 28, 28)
	search:SetFont("PP_PaletteQuery")
	search:SetPlaceholderText("Search tools, panels & actions…")
	search:SetPaintBackground(false)
	search:SetTextColor(C.textBright)
	search:RequestFocus()

	local list = vgui.Create("DScrollPanel", frame)
	list:SetPos(8, 52)
	list:SetSize(W - 16, H - 60)

	local rows, sel = {}, 1

	local function Activate(entry)
		if not entry then return end
		frame:Remove()
		local ok, err = pcall(entry.run)
		if not ok then ErrorNoHalt("[PinnedPanels] Palette action error: " .. tostring(err) .. "\n") end
	end

	local function HighlightRows()
		for i, r in ipairs(rows) do r.selected = (i == sel) end
		local r = rows[sel]
		if IsValid(r) then list:ScrollToChild(r) end
	end

	local function Rebuild()
		list:Clear()
		rows = {}
		local filtered = FilterEntries(entries, search:GetValue())
		sel = 1

		if #filtered == 0 then
			local empty = vgui.Create("DLabel", list)
			empty:Dock(TOP)
			empty:DockMargin(12, 10, 12, 0)
			empty:SetText("No matches.")
			empty:SetTextColor(C.textMuted)
			return
		end

		for i, entry in ipairs(filtered) do
			local row = vgui.Create("DButton", list)
			row:Dock(TOP)
			row:DockMargin(6, 3, 6, 0)
			row:SetTall(42)
			row:SetText("")
			row.selected = (i == sel)
			if entry.icon and entry.icon ~= "" then row._mat = Material(entry.icon, "smooth mips") end

			row.DoClick = function() Activate(entry) end
			row.OnCursorEntered = function()
				sel = i
				HighlightRows()
			end

			row.Paint = function(self, w, h)
				if self.selected or self:IsHovered() then
					draw.RoundedBox(5, 0, 0, w, h, self.selected and C.accent or C.bgHover)
				end
				local tx = 14
				if self._mat and not self._mat:IsError() then
					surface.SetDrawColor(255, 255, 255, 255)
					surface.SetMaterial(self._mat)
					surface.DrawTexturedRect(12, h / 2 - 8, 16, 16)
					tx = 38
				end
				local mainCol = self.selected and C.textBright or C.textLight
				draw.SimpleText(entry.text, "PP_PaletteItem", tx, entry.sub and 9 or h / 2 - 8,
					mainCol, TEXT_ALIGN_LEFT, entry.sub and TEXT_ALIGN_TOP or TEXT_ALIGN_TOP)
				if entry.sub and entry.sub ~= "" then
					draw.SimpleText(entry.sub, "PP_PaletteSub", tx, h - 10,
						self.selected and C.textLight or C.textMuted, TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM)
				end
				draw.SimpleText(entry.cat, "PP_PaletteSub", w - 12, h / 2,
					self.selected and C.textLight or C.textInfo, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
			end

			rows[i] = row
		end
		HighlightRows()
	end

	search.OnValueChange = function() Rebuild() end

	search.OnKeyCodeTyped = function(_, code)
		if code == KEY_ESCAPE then
			frame:Remove()
			return true
		elseif code == KEY_ENTER then
			local r = rows[sel]
			if IsValid(r) and isfunction(r.DoClick) then r:DoClick() end
			return true
		elseif code == KEY_DOWN then
			if #rows > 0 then sel = (sel % #rows) + 1 HighlightRows() end
			return true
		elseif code == KEY_UP then
			if #rows > 0 then sel = (sel - 2) % #rows + 1 HighlightRows() end
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
