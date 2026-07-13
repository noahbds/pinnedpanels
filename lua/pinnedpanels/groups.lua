-- ── Group System (Tabbed Merged Panels) ──────────────────────────────────────
local C                     = PinnedPanels.C
local DeserializeColor      = PinnedPanels._DeserializeColor
local BuildWrapperFrame     = PinnedPanels._BuildWrapperFrame
local FindFreeSpawnPosition = PinnedPanels._FindFreeSpawnPosition

local GROUP_COLORS = {
	Color(255, 200, 60),  Color(60, 200, 255),  Color(200, 100, 255),
	Color(100, 255, 150), Color(255, 120, 100),  Color(255, 160, 220),
	Color(160, 220, 80),  Color(80, 220, 220),
}

local function GetGroupId(name) return "PPG_" .. name end

local function StowContent(pin)
	if not pin then return end
	local content, frame = pin.content, pin.frame
	if not IsValid(content) or not IsValid(frame) then return end
	content:SetParent(frame)
	content:Dock(FILL)
	content:DockMargin(pin.fill and 0 or 4, pin.fill and 4 or 6, pin.fill and 0 or 4, 4)
	content:SetVisible(true)
end

local function PlaceUngrouped(panelId, nearFrame)
	local pin = PinnedPanels.Pins[panelId]
	if not pin or not IsValid(pin.frame) then return end
	local f = pin.frame
	local w, h = f:GetSize()
	local px, py = 120, 120
	if IsValid(nearFrame) then
		px, py = nearFrame:GetPos()
		px, py = px + 40, py + 40
	end
	f:SetVisible(true)
	local x, y = FindFreeSpawnPosition(w, h, px, py, panelId)
	f:SetPos(x, y)
	f:MoveToFront()
end

-- ── Group Data Helpers ───────────────────────────────────────────────────────
function PinnedPanels.GetGroupForPanel(panelId)
	for _, g in ipairs(PinnedPanels.Settings.groups) do
		for _, id in ipairs(g.ids) do
			if id == panelId then return g end
		end
	end
	return nil
end

function PinnedPanels.GetGroupPanels(groupName)
	for _, g in ipairs(PinnedPanels.Settings.groups) do
		if g.name == groupName then return g.ids end
	end
	return {}
end

function PinnedPanels.RemoveFromAllGroups(panelId)
	for _, g in ipairs(PinnedPanels.Settings.groups) do
		for i = #g.ids, 1, -1 do
			if g.ids[i] == panelId then
				table.remove(g.ids, i)
			end
		end
	end
end

function PinnedPanels.GetActiveGroupMemberId(groupPinId)
	local gp = PinnedPanels.Pins[groupPinId]
	if not gp or not IsValid(gp.sheet) then return nil end
	local active = gp.sheet:GetActiveTab()
	if not IsValid(active) then return nil end
	return gp.tabToMember and gp.tabToMember[active:GetPanel()] or nil
end

function PinnedPanels.UnpinGroupMembers(groupName)
	local ids = {}
	for _, id in ipairs(PinnedPanels.GetGroupPanels(groupName)) do ids[#ids + 1] = id end
	for _, id in ipairs(ids) do PinnedPanels.Unpin(id) end
end

function PinnedPanels.MoveInGroup(groupName, panelId, dir)
	for _, g in ipairs(PinnedPanels.Settings.groups) do
		if g.name == groupName then
			for i, pid in ipairs(g.ids) do
				if pid == panelId then
					local j = i + dir
					if j < 1 or j > #g.ids then return false end
					g.ids[i], g.ids[j] = g.ids[j], g.ids[i]
					PinnedPanels.SaveSettings()
					PinnedPanels.RebuildGroupFrame(groupName)
					hook.Run("PinnedPanels_StateChanged")
					return true
				end
			end
			return false
		end
	end
	return false
end

-- ── Build Group Frame (Tabbed Merged Panels) ─────────────────────────────────
function PinnedPanels.RebuildGroupFrame(groupName)
	local group = nil
	for _, g in ipairs(PinnedPanels.Settings.groups) do
		if g.name == groupName then group = g break end
	end
	if not group then return end

	local groupId = GetGroupId(groupName)

	for _, panelId in ipairs(group.ids) do
		StowContent(PinnedPanels.Pins[panelId])
	end

	local oldX, oldY, oldW, oldH
	local oldPin = PinnedPanels.Pins[groupId]
	if oldPin and IsValid(oldPin.frame) then
		oldX, oldY = oldPin.frame:GetPos()
		oldW, oldH = oldPin.frame:GetSize()
		oldPin.frame:Remove()
	end
	PinnedPanels.Pins[groupId] = nil

	local members = {}
	for _, panelId in ipairs(group.ids) do
		local pin = PinnedPanels.Pins[panelId]
		if pin and (IsValid(pin.content) or pin.cpFunc) then
			members[#members + 1] = { id = panelId, pin = pin }
		end
	end

	if #members == 0 then
		PinnedPanels.Save()
		return
	end

	local saved = PinnedPanels.Load()
	local s = saved[groupId] or {}
	local sw, sh = ScrW(), ScrH()
	local fw = oldW or math.Clamp(s.w or 300, 150, sw)
	local fh = oldH or math.Clamp(s.h or 450, 100, sh)
	local fx, fy
	if oldX then
		fx, fy = oldX, oldY
	elseif s.x then
		local scaledX, scaledY = PinnedPanels.ScaleSavedPos(s)
		fx = math.Clamp(scaledX or 120, 0, sw - fw)
		fy = math.Clamp(scaledY or 120, 0, sh - fh)
	else
		local firstPin = members[1].pin
		if IsValid(firstPin.frame) then
			fx, fy = firstPin.frame:GetPos()
		else
			fx, fy = FindFreeSpawnPosition(fw, fh, 120, 120, groupId)
		end
	end

	local frame = BuildWrapperFrame(groupName, groupId, fw, fh, fx, fy)

	local sheet = vgui.Create("DPropertySheet", frame)
	sheet:Dock(FILL)
	sheet:DockMargin(2, 4, 2, 2)
	sheet.Paint = function() end

	local tabToMember = {}

	for _, member in ipairs(members) do
		local pin = member.pin
		local tabPanel = vgui.Create("DPanel")
		tabPanel.Paint = function() end

		if IsValid(pin.content) then
			pin.content:SetParent(tabPanel)
			pin.content:Dock(FILL)
			pin.content:DockMargin(pin.fill and 0 or 4, 4, pin.fill and 0 or 4, 4)
			pin.content:SetMouseInputEnabled(true)
			pin.content:SetVisible(true)
			pin.content:InvalidateLayout(true)
		elseif pin.kind == "creation" then
			local ok, result = pcall(pin.cpFunc)
			if ok and IsValid(result) then
				result:SetParent(tabPanel)
				result:Dock(FILL)
				result:SetMouseInputEnabled(true)
				result:InvalidateLayout(true)
				pin.content = result
			else
				local lbl = vgui.Create("DLabel", tabPanel)
				lbl:SetText("Error loading: " .. (not ok and tostring(result) or "unknown"))
				lbl:SetWrap(true)
				lbl:Dock(FILL)
				lbl:DockMargin(8, 8, 8, 8)
				lbl:SetTextColor(C.errorRed)
			end
		elseif isfunction(pin.cpFunc) then
			local scroll = vgui.Create("DScrollPanel", tabPanel)
			scroll:Dock(FILL)
			scroll:DockMargin(4, 4, 4, 4)
			pin.content = scroll

			local ctrl = vgui.Create("ControlPanel", scroll)
			ctrl:Dock(TOP)
			ctrl:SetAutoSize(true)
			local beforeCount = #ctrl:GetChildren()
			local ok, err = pcall(pin.cpFunc, ctrl)
			if not ok then
				ctrl:Remove()
				local lbl = vgui.Create("DLabel", scroll)
				lbl:SetText("Error: " .. tostring(err))
				lbl:SetWrap(true)
				lbl:Dock(TOP)
				lbl:DockMargin(8, 8, 8, 8)
				lbl:SetTextColor(C.errorRed)
			else
				if #ctrl:GetChildren() <= beforeCount and controlpanel then
					local cpName = member.id:sub(4)
					local origGet = controlpanel.Get
					controlpanel.Get = function(name)
						if name == cpName then return ctrl end
						return origGet(name)
					end
					hook.Run("PostReloadToolsMenu")
					controlpanel.Get = origGet
				end
				ctrl:InvalidateLayout(true)
			end

			timer.Simple(0.2, function()
				if IsValid(scroll) then PinnedPanels.ThrottleScroll(scroll) end
			end)
		else
			local lbl = vgui.Create("DLabel", tabPanel)
			lbl:SetText("No control panel available.")
			lbl:SetWrap(true)
			lbl:Dock(FILL)
			lbl:DockMargin(8, 8, 8, 8)
			lbl:SetTextColor(C.mutedGray)
		end

		local kindIcon = pin.kind == "creation" and "icon16/application_view_list.png" or "icon16/wrench.png"
		sheet:AddSheet(pin.title, tabPanel, kindIcon)
		tabToMember[tabPanel] = member.id

		if IsValid(pin.frame) then
			pin.frame:SetVisible(false)
		end
	end

	for _, item in ipairs(sheet:GetItems()) do
		local tab = item.Tab
		tab.Paint = function(self, w, h)
			local isActive = sheet:GetActiveTab() == self
			local bg = isActive and C.bg or C.bgDarker
			if self:IsHovered() and not isActive then bg = C.bgHover end
			draw.RoundedBoxEx(4, 0, 0, w, h, bg, true, true, false, false)
			if isActive then
				local gCol = group.color
				surface.SetDrawColor(gCol.r, gCol.g, gCol.b, 255)
				surface.DrawRect(0, h - 2, w, 2)
			end
		end
	end

	-- when rebuilding an existing pin its live state wins; on the first build
	-- after a restart fall back to what was saved
	local wantMinimized = oldPin and oldPin.minimized or (oldPin == nil and s.minimized) or false
	local wantFilterBar = oldPin and oldPin.filterBar or (oldPin == nil and s.filterBar) or false

	PinnedPanels.Pins[groupId] = {
		frame        = frame,
		title        = groupName,
		kind         = "group",
		groupName    = groupName,
		sheet        = sheet,
		tabToMember  = tabToMember,
		tabSizes     = (oldPin and oldPin.tabSizes) or (istable(s.tabSizes) and s.tabSizes) or {},
		locked       = (oldPin and oldPin.locked) or s.locked or false,
		minimized    = wantMinimized,
		clickThrough = oldPin and oldPin.clickThrough or (oldPin == nil and s.clickThrough) or false,
		idleAlpha    = (oldPin and oldPin.idleAlpha) or tonumber(s.idleAlpha) or nil,
		customBg     = (oldPin and oldPin.customBg) or (s.customBg and DeserializeColor(s.customBg)) or nil,
		customHeader = (oldPin and oldPin.customHeader) or (s.customHeader and DeserializeColor(s.customHeader)) or nil,
		customText   = (oldPin and oldPin.customText) or (s.customText and DeserializeColor(s.customText)) or nil,
	}

	if wantMinimized then frame:SetVisible(false) end

	local function ApplyTabSize(mid)
		local gp = PinnedPanels.Pins[groupId]
		if not gp or not IsValid(frame) then return end
		local sz = mid and gp.tabSizes and gp.tabSizes[mid]
		if not sz then return end
		local sw2, sh2 = ScrW(), ScrH()
		local nw = math.Clamp(tonumber(sz.w) or frame:GetWide(), 150, sw2)
		local nh = math.Clamp(tonumber(sz.h) or frame:GetTall(), 100, sh2)
		if frame:GetWide() ~= nw or frame:GetTall() ~= nh then
			frame:SetSize(nw, nh)
			local fx2, fy2 = frame:GetPos()
			frame:SetPos(math.Clamp(fx2, 0, sw2 - nw), math.Clamp(fy2, 0, sh2 - nh))
		end
	end

	frame.OnUserResized = function(w, h)
		local gp = PinnedPanels.Pins[groupId]
		local mid = gp and PinnedPanels.GetActiveGroupMemberId(groupId)
		if not mid then return end
		gp.tabSizes = gp.tabSizes or {}
		gp.tabSizes[mid] = { w = w, h = h }
	end

	sheet.OnActiveTabChanged = function(_, _, newTab)
		if not IsValid(newTab) then return end
		ApplyTabSize(tabToMember[newTab:GetPanel()])
		PinnedPanels.Save()
	end

	ApplyTabSize(members[1] and members[1].id)

	if wantFilterBar and PinnedPanels.AttachFilterBar then
		PinnedPanels.AttachFilterBar(groupId)
	end

	timer.Simple(0, function()
		if not IsValid(frame) then return end
		frame:InvalidateLayout(true)
		if IsValid(sheet) then sheet:InvalidateLayout(true) end
	end)

	PinnedPanels.Save()
end

-- ── Group Membership ─────────────────────────────────────────────────────────
function PinnedPanels.CreateGroup(name)
	local groups = PinnedPanels.Settings.groups
	for _, g in ipairs(groups) do
		if g.name == name then return g end
	end
	local colorIdx = (#groups % #GROUP_COLORS) + 1
	local group = { name = name, color = GROUP_COLORS[colorIdx], ids = {} }
	groups[#groups + 1] = group
	PinnedPanels.SaveSettings()
	hook.Run("PinnedPanels_StateChanged")
	return group
end

function PinnedPanels.AddToGroup(groupName, panelId)
	local pin = PinnedPanels.Pins[panelId]
	if not pin then return false end
	if pin.kind == "frame" or pin.kind == "group" then return false end
	StowContent(pin)
	local oldGroup = PinnedPanels.GetGroupForPanel(panelId)
	if oldGroup then
		for i = #oldGroup.ids, 1, -1 do
			if oldGroup.ids[i] == panelId then table.remove(oldGroup.ids, i) end
		end
		PinnedPanels.RebuildGroupFrame(oldGroup.name)
	end
	for _, g in ipairs(PinnedPanels.Settings.groups) do
		if g.name == groupName then
			g.ids[#g.ids + 1] = panelId
			if IsValid(pin.frame) then pin.frame:SetVisible(false) end
			PinnedPanels.SaveSettings()
			PinnedPanels.RebuildGroupFrame(groupName)
			hook.Run("PinnedPanels_StateChanged")
			return true
		end
	end
	return false
end

function PinnedPanels.RemoveFromGroup(groupName, panelId)
	for _, g in ipairs(PinnedPanels.Settings.groups) do
		if g.name == groupName then
			for i, id in ipairs(g.ids) do
				if id == panelId then
					local pin = PinnedPanels.Pins[panelId]
					local groupPin = PinnedPanels.Pins[GetGroupId(groupName)]
					local groupFrame = groupPin and groupPin.frame or nil
					StowContent(pin)
					table.remove(g.ids, i)
					PlaceUngrouped(panelId, groupFrame)
					PinnedPanels.SaveSettings()
					PinnedPanels.RebuildGroupFrame(groupName)
					hook.Run("PinnedPanels_StateChanged")
					return true
				end
			end
		end
	end
	return false
end

function PinnedPanels.DeleteGroup(name)
	local groups = PinnedPanels.Settings.groups
	for i, g in ipairs(groups) do
		if g.name == name then
			local groupId = GetGroupId(name)
			local groupPin = PinnedPanels.Pins[groupId]
			local groupFrame = groupPin and groupPin.frame or nil
			for _, panelId in ipairs(g.ids) do
				StowContent(PinnedPanels.Pins[panelId])
				PlaceUngrouped(panelId, groupFrame)
			end
			if groupPin and IsValid(groupPin.frame) then groupPin.frame:Remove() end
			PinnedPanels.Pins[groupId] = nil
			table.remove(groups, i)
			PinnedPanels.SaveSettings()
			PinnedPanels.Save()
			hook.Run("PinnedPanels_StateChanged")
			return true
		end
	end
	return false
end

-- ── Restore Refresh ──────────────────────────────────────────────────────────
function PinnedPanels.RefreshRestoredGroups()
	if not PinnedPanels._pendingGroupRefresh then return end
	PinnedPanels._pendingGroupRefresh = nil
	for _, g in ipairs(PinnedPanels.Settings.groups) do
		if #g.ids > 0 then
			PinnedPanels.RebuildGroupFrame(g.name)
		end
	end
	if PinnedPanels.UpdatePanelStates then PinnedPanels.UpdatePanelStates() end
end

hook.Add("OnSpawnMenuOpen", "PinnedPanels_GroupRefreshAfterRestore", function()
	if PinnedPanels.CursorMode then PinnedPanels.CursorMode.SpawnMenuOpen = true end
	PinnedPanels.RefreshRestoredGroups()
end)
