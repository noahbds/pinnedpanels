local C                     = PinnedPanels.C
local BuildWrapperFrame     = PinnedPanels._BuildWrapperFrame
local FindFreeSpawnPosition = PinnedPanels._FindFreeSpawnPosition
local DeserializeColor      = PinnedPanels._DeserializeColor

-- ── Content Builders ─────────────────────────────────────────────────────────
local function BuildFillContent(frame, cpFunc)
	local ok, result = pcall(cpFunc)
	if ok and IsValid(result) then
		result:SetParent(frame)
		result:Dock(FILL)
		result:DockMargin(0, 4, 0, 0)
		result:SetMouseInputEnabled(true)
		result:InvalidateLayout(true)
		return result
	end
	PinnedPanels.ErrorLabel(frame, "Error loading panel" .. (not ok and (": " .. tostring(result)) or "."))
		:DockMargin(8, 32, 8, 8)
end

local function BuildToolContent(frame, cpFunc, id)
	local scroll = vgui.Create("DScrollPanel", frame)
	scroll:Dock(FILL)
	scroll:DockMargin(4, 6, 4, 4)

	if isfunction(cpFunc) then
		PinnedPanels.PopulateToolControls(scroll, cpFunc, id:sub(4))
	else
		local lbl = vgui.Create("DLabel", scroll)
		lbl:SetText("This tool has no control panel.")
		lbl:SetWrap(true)
		lbl:Dock(TOP)
		lbl:DockMargin(8, 8, 8, 8)
		lbl:SetTextColor(C.mutedGray)
	end

	timer.Simple(0.2, function()
		if IsValid(scroll) then PinnedPanels.ThrottleScroll(scroll) end
	end)

	return scroll
end

-- ── Pin ──────────────────────────────────────────────────────────────────────
function PinnedPanels.Pin(id, title, cpFunc, noSave, opts)
	opts = opts or {}
	local existing = PinnedPanels.Pins[id]
	if existing and IsValid(existing.frame) then
		existing.frame:SetVisible(true)
		return existing.frame
	end
	PinnedPanels.Pins[id] = nil

	local s      = PinnedPanels.Load()[id] or {}
	local sw, sh = ScrW(), ScrH()
	local fw     = math.Clamp(s.w or opts.defaultW or 280, 150, sw)
	local fh     = math.Clamp(s.h or opts.defaultH or 400, 100, sh)
	local fx, fy
	if s.x ~= nil and s.y ~= nil then
		local scaledX, scaledY = PinnedPanels.ScaleSavedPos(s)
		fx = math.Clamp(scaledX or 120, 0, sw - fw)
		fy = math.Clamp(scaledY or 120, 0, sh - fh)
	else
		fx, fy = FindFreeSpawnPosition(fw, fh, 120, 120, id)
	end

	local frame = BuildWrapperFrame(title, id, fw, fh, fx, fy)
	local contentPanel
	if opts.fill then
		contentPanel = BuildFillContent(frame, cpFunc)
	else
		contentPanel = BuildToolContent(frame, cpFunc, id)
	end

	PinnedPanels.Pins[id] = {
		frame        = frame,
		title        = title,
		cpFunc       = cpFunc,
		kind         = opts.kind or "tool",
		content      = contentPanel,
		fill         = opts.fill or false,
		customBg     = s.customBg and DeserializeColor(s.customBg) or nil,
		customHeader = s.customHeader and DeserializeColor(s.customHeader) or nil,
		customText   = s.customText and DeserializeColor(s.customText) or nil,
		locked       = s.locked or false,
		idleAlpha    = tonumber(s.idleAlpha) or nil,
		minimized    = s.minimized or false,
		clickThrough = s.clickThrough or false,
		filterBar    = s.filterBar or false,
		collapsed    = istable(s.collapsed) and s.collapsed or nil,
	}

	if s.filterBar and PinnedPanels.AttachFilterBar then
		PinnedPanels.AttachFilterBar(id)
	end

	timer.Simple(0.25, function()
		if PinnedPanels.Pins[id] and PinnedPanels.ApplyCollapseMemory then
			PinnedPanels.ApplyCollapseMemory(id)
		end
	end)

	if s.w == nil and s.h == nil and not opts.fill then
		timer.Simple(0.35, function()
			if PinnedPanels.Pins[id] and not PinnedPanels.GetGroupForPanel(id) then
				PinnedPanels.AutoSizePanel(id)
			end
		end)
	end

	if istable(s.crop) and PinnedPanels.ApplyCrop then
		timer.Simple(0.5, function()
			local p = PinnedPanels.Pins[id]
			if p and IsValid(p.frame) and not p.crop and not PinnedPanels.GetGroupForPanel(id) then
				PinnedPanels.ApplyCrop(id, s.crop)
			end
		end)
	end

	if not noSave then PinnedPanels.Save() end

	if PinnedPanels.Pins[id] and PinnedPanels.Pins[id].minimized then
		frame:SetVisible(false)
	end

	hook.Run("PinnedPanels_StateChanged")
	return frame
end

-- ── Minimize / Restore ──────────────────────────────────────────────────────
function PinnedPanels.MinimizeToTaskbar(id)
	local pin = PinnedPanels.Pins[id]
	if not pin or not IsValid(pin.frame) then return end
	pin.frame:SetVisible(false)
	pin.minimized = true
	if PinnedPanels.EnsureTaskbar then PinnedPanels.EnsureTaskbar() end
	PinnedPanels.Save()
	hook.Run("PinnedPanels_StateChanged")
end

function PinnedPanels.ToggleMaximizePanel(id)
	local pin = PinnedPanels.Pins[id]
	if not pin or not IsValid(pin.frame) or pin.locked then return end
	local frame = pin.frame

	if pin.maximized then
		local b = pin.restoreBounds
		if b then
			frame:SetSize(b.w, b.h)
			frame:SetPos(b.x, b.y)
		end
		pin.maximized = false
	else
		if pin.crop and PinnedPanels.ClearCrop then PinnedPanels.ClearCrop(id) end
		local x, y = frame:GetPos()
		local w, h = frame:GetSize()
		pin.restoreBounds = { x = x, y = y, w = w, h = h }
		local ux, uy, uw, uh = PinnedPanels.GetUsableBounds()
		frame:SetPos(ux, uy)
		frame:SetSize(uw, uh)
		pin.maximized = true
	end

	frame:MoveToFront()
	if isfunction(frame.OnUserResized) then frame.OnUserResized(frame:GetSize()) end
	PinnedPanels.Save()
end

function PinnedPanels.RestoreFromTaskbar(id)
	local pin = PinnedPanels.Pins[id]
	if not pin or not IsValid(pin.frame) then return end
	pin.minimized = false
	pin.frame:SetVisible(true)
	pin.frame:MoveToFront()

	local interactive = PinnedPanels.PanelsInteractive()
	pin.frame:SetMouseInputEnabled(interactive)
	if interactive then pin.frame:SetAlpha(255) end

	PinnedPanels.Save()
	if PinnedPanels.UpdatePanelStates then PinnedPanels.UpdatePanelStates() end
	hook.Run("PinnedPanels_StateChanged")
end

function PinnedPanels.RestoreAllFromTaskbar()
	for id, pin in pairs(PinnedPanels.Pins) do
		if pin.minimized and IsValid(pin.frame) then
			pin.minimized = false
			pin.frame:SetVisible(true)
		end
	end
	PinnedPanels.Save()
	hook.Run("PinnedPanels_StateChanged")
end

function PinnedPanels.GetMinimizedPanels()
	local list = {}
	for id, pin in pairs(PinnedPanels.Pins) do
		if pin.minimized and IsValid(pin.frame) then
			list[#list + 1] = { id = id, title = pin.title, kind = pin.kind }
		end
	end
	table.sort(list, function(a, b) return a.title < b.title end)
	return list
end

-- ── Pin Frame (live panel reparenting) ───────────────────────────────────────
function PinnedPanels.PinFrame(livePanel, title)
	if not IsValid(livePanel) then return end

	local id = "PPF_" .. tostring(livePanel)
	local existing = PinnedPanels.Pins[id]
	if existing and IsValid(existing.frame) then
		existing.frame:SetVisible(true)
		return existing.frame
	end
	PinnedPanels.Pins[id] = nil

	local s      = PinnedPanels.Load()[id] or {}
	local sw, sh = ScrW(), ScrH()
	local ox, oy = livePanel:GetPos()
	local ow, oh = livePanel:GetSize()
	local fw     = math.Clamp(s.w or (ow + 8), 150, sw)
	local fh     = math.Clamp(s.h or (oh + 28), 100, sh)
	local fx, fy
	if s.x ~= nil and s.y ~= nil then
		local scaledX, scaledY = PinnedPanels.ScaleSavedPos(s)
		fx = math.Clamp(scaledX or ox, 0, sw - fw)
		fy = math.Clamp(scaledY or oy, 0, sh - fh)
	else
		fx, fy = FindFreeSpawnPosition(fw, fh, ox, oy, id)
	end

	local origParent  = livePanel:GetParent()
	local origPos     = { livePanel:GetPos() }
	local origSize    = { livePanel:GetSize() }
	local origVisible = livePanel:IsVisible()
	local origDock    = livePanel:GetDock()

	local frame = BuildWrapperFrame(title, id, fw, fh, fx, fy)

	livePanel:SetParent(frame)
	livePanel:SetDock(FILL)
	livePanel:DockMargin(0, 4, 0, 0)
	livePanel:SetVisible(true)
	livePanel:InvalidateLayout(true)

	local origOnRemove = livePanel.OnRemove
	livePanel.OnRemove = function(self)
		if PinnedPanels.Pins[id] then
			PinnedPanels.Pins[id] = nil
			PinnedPanels.ClearSavedPin(id)
			hook.Run("PinnedPanels_StateChanged")
		end
		if isfunction(origOnRemove) then origOnRemove(self) end
	end

	local baseOnRemove = frame.OnRemove
	frame.OnRemove = function()
		if isfunction(baseOnRemove) then baseOnRemove() end
		if IsValid(livePanel) then
			livePanel:SetDock(origDock)
			if IsValid(origParent) then
				livePanel:SetParent(origParent)
				if origDock == NODOCK then
					livePanel:SetPos(origPos[1], origPos[2])
					livePanel:SetSize(origSize[1], origSize[2])
				end
			end
			livePanel:SetVisible(origVisible)
		end
	end

	PinnedPanels.Pins[id] = {
		frame     = frame,
		title     = title,
		livePanel = livePanel,
		kind      = "frame",
	}
	PinnedPanels.Save()
	hook.Run("PinnedPanels_StateChanged")
	return frame
end

function PinnedPanels.IsPinnedFrame(livePanel)
	if not IsValid(livePanel) then return false end
	local pin = PinnedPanels.Pins["PPF_" .. tostring(livePanel)]
	return pin ~= nil and IsValid(pin.frame)
end

-- ── Recently Closed (undo unpin) ─────────────────────────────────────────────
PinnedPanels._closedStack = PinnedPanels._closedStack or {}
local CLOSED_MAX = 15

local function RecordClosed(id, pin)
	if not pin or (pin.kind ~= "tool" and pin.kind ~= "creation") then return end
	local entry = { id = id, title = pin.title, kind = pin.kind }
	if IsValid(pin.frame) then
		local x, y = pin.frame:GetPos()
		local w, h = pin.frame:GetSize()
		entry.x, entry.y, entry.w, entry.h = x, y, w, h
	end
	local stack = PinnedPanels._closedStack
	stack[#stack + 1] = entry
	while #stack > CLOSED_MAX do table.remove(stack, 1) end
end

function PinnedPanels.HasClosedPanels()
	return #PinnedPanels._closedStack > 0
end

function PinnedPanels.ReopenLastClosed()
	local stack = PinnedPanels._closedStack
	if #stack == 0 then return end
	local e = stack[#stack]

	local function finish(frame)
		table.remove(stack, #stack)
		if IsValid(frame) and e.x then
			local sw, sh = ScrW(), ScrH()
			frame:SetSize(math.Clamp(e.w, 150, sw), math.Clamp(e.h, 100, sh))
			frame:SetPos(math.Clamp(e.x, 0, sw - e.w), math.Clamp(e.y, 0, sh - e.h))
			frame:MoveToFront()
			PinnedPanels.Save()
		end
	end

	if e.kind == "tool" then
		for _, t in ipairs(PinnedPanels.GetAllTools()) do
			if "PP_" .. t.itemName == e.id then
				finish(PinnedPanels.Pin(e.id, e.title, t.cpFunc))
				return
			end
		end
	elseif e.kind == "creation" then
		for _, t in ipairs(PinnedPanels.GetAllCreationTabs()) do
			if t.id == e.id then
				finish(PinnedPanels.Pin(e.id, e.title, t.func, false, PinnedPanels.CREATION_OPTS))
				return
			end
		end
	end

	table.remove(stack, #stack)
	PinnedPanels.ReopenLastClosed()
end

-- ── Unpin ────────────────────────────────────────────────────────────────────
function PinnedPanels.Unpin(id)
	local pin = PinnedPanels.Pins[id]
	RecordClosed(id, pin)

	if pin and pin.kind == "group" and pin.groupName then
		PinnedPanels.UnpinGroupMembers(pin.groupName)
		local gp = PinnedPanels.Pins[id]
		if gp then
			if IsValid(gp.frame) then gp.frame:Remove() end
			PinnedPanels.Pins[id] = nil
		end
		PinnedPanels.ClearSavedPin(id)
		hook.Run("PinnedPanels_StateChanged")
		return
	end

	local group = pin and PinnedPanels.GetGroupForPanel(id) or nil

	if pin then
		if pin.kind == "frame" and IsValid(pin.livePanel) then
			pin.livePanel.OnRemove = nil
		end
		if IsValid(pin.frame) then pin.frame:Remove() end
	end

	PinnedPanels.Pins[id] = nil
	PinnedPanels.RemoveFromAllGroups(id)
	PinnedPanels.ClearSavedPin(id)

	if group then
		PinnedPanels.SaveSettings()
		PinnedPanels.RebuildGroupFrame(group.name)
	end

	hook.Run("PinnedPanels_StateChanged")
end

function PinnedPanels.UnpinAll()
	local ids = {}
	for id in pairs(PinnedPanels.Pins) do ids[#ids + 1] = id end
	for _, id in ipairs(ids) do PinnedPanels.Unpin(id) end
end

-- ── Scan Frames ──────────────────────────────────────────────────────────────
local FRAME_IGNORE_NAMES = {
	SpawnmenuTabs         = true,
	SpawnMenuContentPanel = true,
	DMenu                 = true,
	ContextMenu           = true,
}

function PinnedPanels.ScanFrames()
	local ownedPanels = {}
	for _, pin in pairs(PinnedPanels.Pins) do
		if IsValid(pin.frame) then ownedPanels[pin.frame] = true end
		if IsValid(pin.livePanel) then ownedPanels[pin.livePanel] = true end
	end

	local results = {}
	for _, p in ipairs(vgui.GetAll()) do
		if not IsValid(p) then continue end
		if ownedPanels[p] then continue end
		if p:GetClassName() ~= "DFrame" then continue end

		local name = p:GetName() or ""
		if FRAME_IGNORE_NAMES[name] then continue end
		if name:sub(1, 3) == "PP_" or name:sub(1, 4) == "PPF_" then continue end
		if not p:IsVisible() then continue end

		local titleText = ""
		if p.lblTitle and IsValid(p.lblTitle) then
			titleText = p.lblTitle:GetText() or ""
		end
		if titleText == "" then
			titleText = (name ~= "" and name) or ("Frame " .. (tostring(p):match("%d+$") or tostring(p)))
		end

		results[#results + 1] = {
			panel  = p,
			title  = titleText,
			id     = "PPF_" .. tostring(p),
			pinned = PinnedPanels.IsPinnedFrame(p),
		}
	end

	table.sort(results, function(a, b) return a.title:lower() < b.title:lower() end)
	return results
end
