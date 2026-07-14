-- ── Taskbar ──────────────────────────────────────────────────────────────────
local C = PinnedPanels.C

PinnedPanels.Taskbar = PinnedPanels.Taskbar or {}
local TB = PinnedPanels.Taskbar

surface.CreateFont("PP_TaskbarFont", { font = "Tahoma", size = 13, weight = 500 })
surface.CreateFont("PP_TaskbarFontBold", { font = "Tahoma", size = 13, weight = 700 })

-- ── Constants ────────────────────────────────────────────────────────────────
local ENTRY_PAD   = 4
local ENTRY_GAP   = 4
local ICON_SIZE   = 16
local MIN_ENTRY_W = 40
local MAX_ENTRY_W = 170
local START_PAD   = 8
local PEEK        = 4

-- ── Helpers ──────────────────────────────────────────────────────────────────
local function GetSettings()
	if not PinnedPanels.Settings or not PinnedPanels.Settings.taskbar then
		return PinnedPanels.DEFAULT_TASKBAR
	end
	return PinnedPanels.Settings.taskbar
end

local function IsHorizontal()
	local pos = GetSettings().position
	return pos == "bottom" or pos == "top"
end

local function GetKindIcon(kind)
	if kind == "creation" then return "icon16/application_view_list.png" end
	if kind == "frame"    then return "icon16/application.png" end
	if kind == "group"    then return "icon16/folder.png" end
	return "icon16/wrench.png"
end

local function ComputeEntryRects(entries)
	local ts = GetSettings()
	local horiz = IsHorizontal()
	local showLabels = ts.showLabels ~= false
	local h = ts.height or 32
	local rects = {}

	local offset = START_PAD
	for i, entry in ipairs(entries) do
		if horiz then
			local ew
			if showLabels then
				surface.SetFont("PP_TaskbarFont")
				local tw = surface.GetTextSize(entry.title)
				ew = math.Clamp(ICON_SIZE + 8 + tw + ENTRY_PAD * 2, MIN_ENTRY_W, MAX_ENTRY_W)
			else
				ew = MIN_ENTRY_W
			end
			rects[i] = { x = offset, y = ENTRY_PAD, w = ew, h = h - ENTRY_PAD * 2 }
			offset = offset + ew + ENTRY_GAP
		else
			local ew = h - ENTRY_PAD * 2
			local eh = h - ENTRY_PAD * 2
			rects[i] = { x = ENTRY_PAD, y = offset, w = ew, h = eh }
			offset = offset + eh + ENTRY_GAP
		end
	end
	return rects
end

-- ── Internal panel builder ────────────────────────────────────────────────────
local function BuildTaskbar()
	if IsValid(TB.panel) then TB.panel:Remove() end

	local bar = vgui.Create("DPanel")
	bar:MakePopup()
	bar:SetKeyboardInputEnabled(false)
	bar:SetMouseInputEnabled(false)
	bar._pp_skipNav   = true
	bar._pp_isTaskbar = true

	TB.panel      = bar
	TB.entries    = {}
	TB.hoverIndex = nil
	TB.fadeAlpha  = 0
	TB.slide      = 0
	TB.kbFocused  = false

	local function LayoutBar()
		local ts = GetSettings()
		local sw, sh = ScrW(), ScrH()
		local h = ts.height or 32
		local hide = math.floor((h - PEEK) * (TB.slide or 0))

		if ts.position == "top" then
			bar:SetSize(sw, h)
			bar:SetPos(0, -hide)
		elseif ts.position == "left" then
			bar:SetSize(h, sh)
			bar:SetPos(-hide, 0)
		elseif ts.position == "right" then
			bar:SetSize(h, sh)
			bar:SetPos(sw - h + hide, 0)
		else
			bar:SetSize(sw, h)
			bar:SetPos(0, sh - h + hide)
		end
	end

	local function CursorTriggersReveal()
		local ts = GetSettings()
		local sw, sh = ScrW(), ScrH()
		local h = ts.height or 32
		local margin = 6
		local mx, my = gui.MouseX(), gui.MouseY()
		if ts.position == "top" then
			return my <= h + margin
		elseif ts.position == "left" then
			return mx <= h + margin
		elseif ts.position == "right" then
			return mx >= sw - h - margin
		else
			return my >= sh - h - margin
		end
	end

	-- ── Entry list ────────────────────────────────────────────────────────────
	local function RebuildEntries()
		TB.entries = PinnedPanels.GetMinimizedPanels()
		if not TB.kbFocused then
			TB.hoverIndex = nil
		elseif #TB.entries == 0 then
			PinnedPanels.UnfocusTaskbar()
		elseif TB.hoverIndex then
			TB.hoverIndex = math.Clamp(TB.hoverIndex, 1, #TB.entries)
		end
	end

	local function GetEntryRects()
		return ComputeEntryRects(TB.entries)
	end

	local function EntryAtCursor()
		if not bar:IsVisible() then return nil end
		local mx, my = bar:CursorPos()
		local bw, bh = bar:GetSize()
		if mx < 0 or my < 0 or mx > bw or my > bh then return nil end

		local rects = GetEntryRects()
		for i, r in ipairs(rects) do
			if mx >= r.x and mx <= r.x + r.w and my >= r.y and my <= r.y + r.h then
				return i
			end
		end
		return nil
	end

	-- ── Paint ────────────────────────────────────────────────────────────────
	bar.Paint = function(self, w, h)
		local ts    = GetSettings()
		local alpha = TB.fadeAlpha
		if alpha <= 0 then return end

		local pos   = ts.position
		local horiz = IsHorizontal()
		local bgCol = ts.bgColor or C.taskbarBg
		draw.RoundedBox(0, 0, 0, w, h, Color(bgCol.r, bgCol.g, bgCol.b, math.floor(bgCol.a * alpha)))

		local borderCol = C.taskbarBorder
		surface.SetDrawColor(borderCol.r, borderCol.g, borderCol.b, math.floor(borderCol.a * alpha))
		if pos == "bottom" then
			surface.DrawRect(0, 0, w, 1)
		elseif pos == "top" then
			surface.DrawRect(0, h - 1, w, 1)
		elseif pos == "left" then
			surface.DrawRect(w - 1, 0, 1, h)
		else
			surface.DrawRect(0, 0, 1, h)
		end

		if #TB.entries == 0 then return end

		local rects      = GetEntryRects()
		local showLabels = ts.showLabels ~= false
		local textCol    = ts.textColor or C.taskbarText
		local accentCol  = ts.accentColor or C.taskbarEntryAct

		for i, entry in ipairs(TB.entries) do
			local r = rects[i]
			if not r then break end
			local isHov = (TB.hoverIndex == i)

			local ebg = isHov and C.taskbarEntryHov or C.taskbarEntry
			draw.RoundedBox(4, r.x, r.y, r.w, r.h, Color(ebg.r, ebg.g, ebg.b, math.floor(ebg.a * alpha)))

			if isHov then
				surface.SetDrawColor(accentCol.r, accentCol.g, accentCol.b, math.floor(220 * alpha))
				if pos == "bottom" then
					surface.DrawRect(r.x, r.y + r.h - 2, r.w, 2)
				elseif pos == "top" then
					surface.DrawRect(r.x, r.y, r.w, 2)
				elseif pos == "left" then
					surface.DrawRect(r.x, r.y, 2, r.h)
				else
					surface.DrawRect(r.x + r.w - 2, r.y, 2, r.h)
				end
			end

			local iconX = r.x + ENTRY_PAD + 2
			local iconY = r.y + math.floor((r.h - ICON_SIZE) / 2)
			if not (horiz and showLabels) then
				iconX = r.x + math.floor((r.w - ICON_SIZE) / 2)
			end
			local mat = Material(GetKindIcon(entry.kind))
			if mat and not mat:IsError() then
				surface.SetMaterial(mat)
				surface.SetDrawColor(255, 255, 255, math.floor(255 * alpha))
				surface.DrawTexturedRect(iconX, iconY, ICON_SIZE, ICON_SIZE)
			end

			if showLabels and horiz then
				local tc = isHov and C.taskbarTextHov or textCol
				local maxTextW = r.w - ICON_SIZE - ENTRY_PAD * 2 - 8
				local txtX = iconX + ICON_SIZE + 6
				local txtY = r.y + math.floor(r.h / 2)

				surface.SetFont("PP_TaskbarFont")
				local tw = surface.GetTextSize(entry.title)
				local displayTitle = entry.title
				if tw > maxTextW and maxTextW > 10 then
					while tw > maxTextW and #displayTitle > 1 do
						displayTitle = displayTitle:sub(1, -2)
						tw = surface.GetTextSize(displayTitle .. "..")
					end
					displayTitle = displayTitle .. ".."
				end

				draw.SimpleText(displayTitle, "PP_TaskbarFont", txtX, txtY,
					Color(tc.r, tc.g, tc.b, math.floor(tc.a * alpha)),
					TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			end
		end
	end

	-- ── Think (fade, auto-hide, reveal-on-hover, mouse hover) ─────────────────
	bar.Think = function(self)
		local ts = GetSettings()

		if not TB._nextRebuild or CurTime() >= TB._nextRebuild then
			TB._nextRebuild = CurTime() + 0.15
			RebuildEntries()
		end

		local hasEntries  = #TB.entries > 0
		local interactive = PinnedPanels.PanelsInteractive()
		local shouldShow = hasEntries and (interactive or TB.kbFocused)
		TB.fadeAlpha = math.Approach(TB.fadeAlpha, shouldShow and 1 or 0, 6 * FrameTime())

		local wantCollapse = false
		if ts.revealOnHover and not TB.kbFocused then
			if interactive then
				wantCollapse = not CursorTriggersReveal()
			else
				wantCollapse = true
			end
		end
		TB.slide = math.Approach(TB.slide or 0, wantCollapse and 1 or 0, 8 * FrameTime())

		LayoutBar()

		local wantMouse = interactive and TB.fadeAlpha > 0.05
		if self:IsMouseInputEnabled() ~= wantMouse then
			self:SetMouseInputEnabled(wantMouse)
		end

		if not TB.kbFocused then
			if interactive and TB.slide < 0.5 and TB.fadeAlpha > 0.05 then
				TB.hoverIndex = EntryAtCursor()
			else
				TB.hoverIndex = nil
			end
		end
	end

	-- ── PaintOver (keyboard focus visual: clean highlight + tooltip) ──────────
	bar.PaintOver = function(self, w, h)
		if not TB.kbFocused then return end
		local IM2 = PinnedPanels.CursorMode
		if not IM2 or IM2.Focused ~= "__TASKBAR__" then return end

		local ts  = GetSettings()
		local pos = ts.position

		local ac = ts.accentColor or C.accent
		surface.SetDrawColor(ac.r, ac.g, ac.b, 230)
		if pos == "bottom" then surface.DrawRect(0, 0, w, 2)
		elseif pos == "top" then surface.DrawRect(0, h - 2, w, 2)
		elseif pos == "left" then surface.DrawRect(w - 2, 0, 2, h)
		else surface.DrawRect(0, 0, 2, h) end

		local idx = TB.hoverIndex
		if not idx or not TB.entries[idx] then return end
		local rects = GetEntryRects()
		local r = rects[idx]
		if not r then return end

		local pulse = 0.55 + 0.45 * math.abs(math.sin(CurTime() * 4))
		surface.SetDrawColor(C.focusRing.r, C.focusRing.g, C.focusRing.b, 255)
		surface.DrawOutlinedRect(r.x - 2, r.y - 2, r.w + 4, r.h + 4, 2)
		surface.SetDrawColor(C.focusRing.r, C.focusRing.g, C.focusRing.b, math.floor(50 * pulse))
		surface.DrawRect(r.x, r.y, r.w, r.h)

		local entry = TB.entries[idx]
		surface.SetFont("PP_TaskbarFontBold")
		local label = entry.title .. "   ·   Enter to restore"
		local tw, th = surface.GetTextSize(label)
		local pad = 7
		local bw = tw + pad * 2
		local bh = th + pad * 2

		local bx, by
		if IsHorizontal() then
			bx = math.Clamp(r.x + r.w / 2 - bw / 2, 4, w - bw - 4)
			by = (pos == "top") and (r.y + r.h + 8) or (r.y - bh - 8)
		else
			by = math.Clamp(r.y + r.h / 2 - bh / 2, 4, h - bh - 4)
			bx = (pos == "left") and (r.x + r.w + 8) or (r.x - bw - 8)
		end

		DisableClipping(true)
		draw.RoundedBox(5, bx, by, bw, bh, Color(14, 16, 22, 245))
		surface.SetDrawColor(ac.r, ac.g, ac.b, 200)
		surface.DrawOutlinedRect(bx, by, bw, bh, 1)
		draw.SimpleText(label, "PP_TaskbarFontBold", bx + pad, by + bh / 2,
			C.textBright, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		DisableClipping(false)
	end

	-- ── Mouse clicks (OnMousePressed is the reliable one for a DPanel popup) ──
	bar.OnMousePressed = function(self, mc)
		local idx = EntryAtCursor()
		if not idx or not TB.entries[idx] then return end
		local entry = TB.entries[idx]
		TB.hoverIndex = idx

		if mc == MOUSE_LEFT then
			PinnedPanels.RestoreFromTaskbar(entry.id)
		elseif mc == MOUSE_RIGHT then
			local menu = DermaMenu()
			menu:AddOption("Restore", function()
				PinnedPanels.RestoreFromTaskbar(entry.id)
			end):SetIcon("icon16/arrow_up.png")
			menu:AddOption("Restore All", function()
				PinnedPanels.RestoreAllFromTaskbar()
			end):SetIcon("icon16/arrow_refresh.png")
			menu:AddSpacer()
			menu:AddOption("Unpin", function()
				PinnedPanels.Unpin(entry.id)
			end):SetIcon("icon16/cross.png")
			menu:Open()
		end
	end

	-- ── State change & resize hooks ──────────────────────────────────────────
	hook.Add("PinnedPanels_StateChanged", "PinnedPanels_TaskbarSync", function()
		if IsValid(bar) then RebuildEntries() end
	end)

	hook.Add("OnScreenSizeChanged", "PinnedPanels_TaskbarResize", function()
		if IsValid(bar) then LayoutBar() end
	end)

	bar.OnRemove = function()
		hook.Remove("PinnedPanels_StateChanged", "PinnedPanels_TaskbarSync")
		hook.Remove("OnScreenSizeChanged", "PinnedPanels_TaskbarResize")
		TB.panel = nil
	end

	LayoutBar()
	RebuildEntries()
	return bar
end

-- ── Public API ───────────────────────────────────────────────────────────────
function PinnedPanels.CreateTaskbar()
	local ts = GetSettings()
	if not ts.enabled then
		if IsValid(TB.panel) then TB.panel:Remove() end
		return
	end
	BuildTaskbar()
end

function PinnedPanels.EnsureTaskbar()
	local ts = GetSettings()
	if not ts.enabled then return end
	if not IsValid(TB.panel) then BuildTaskbar() end
end

function PinnedPanels.DestroyTaskbar()
	if IsValid(TB.panel) then TB.panel:Remove() end
	TB.panel = nil
end

-- ── Keyboard focus (driven by keyboard.lua's navigation) ──────────────────────
function PinnedPanels.FocusTaskbar()
	PinnedPanels.EnsureTaskbar()
	if not IsValid(TB.panel) then return end

	TB.kbFocused = true
	TB.slide     = 0
	TB.entries   = PinnedPanels.GetMinimizedPanels()
	if #TB.entries == 0 then
		TB.hoverIndex = nil
	elseif not TB.hoverIndex or TB.hoverIndex < 1 or TB.hoverIndex > #TB.entries then
		TB.hoverIndex = 1
	end
	local IM2 = PinnedPanels.CursorMode
	if IM2 then IM2.Focused = "__TASKBAR__" end
end

function PinnedPanels.UnfocusTaskbar()
	TB.kbFocused  = false
	TB.hoverIndex = nil
	local IM2 = PinnedPanels.CursorMode
	if IM2 and IM2.Focused == "__TASKBAR__" then IM2.Focused = nil end
end

-- ── Robust creation: several safe triggers, all idempotent ──────────────────
local function TryCreate()
	if not PinnedPanels.Settings or not PinnedPanels.Settings.taskbar then return end
	PinnedPanels.EnsureTaskbar()
end

hook.Add("InitPostEntity", "PinnedPanels_TaskbarInit", TryCreate)
hook.Add("PinnedPanels_SettingsLoaded", "PinnedPanels_TaskbarInit2", TryCreate)

hook.Add("PinnedPanels_StateChanged", "PinnedPanels_TaskbarEnsure", function()
	local ts = GetSettings()
	if ts.enabled == false then return end
	if not IsValid(TB.panel) then PinnedPanels.EnsureTaskbar() end
end)

timer.Simple(1, function()
	if not IsValid(TB.panel) then TryCreate() end
end)

if IsValid(TB.panel) then
	PinnedPanels.CreateTaskbar()
end
