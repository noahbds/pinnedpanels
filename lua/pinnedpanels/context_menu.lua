-- ── Right-Click Context Menu ─────────────────────────────────────────────────

function PinnedPanels.GetPinTool(id)
	local pin = PinnedPanels.Pins[id]
	if not pin then return end
	if pin.kind == "tool" then
		return id:sub(4), pin.title
	elseif pin.kind == "group" then
		local activeId = PinnedPanels.GetActiveGroupMemberId(id)
		local activePin = activeId and PinnedPanels.Pins[activeId]
		if activePin and activePin.kind == "tool" then
			return activeId:sub(4), activePin.title
		end
	end
end

function PinnedPanels.EquipToolgun(toolClass)
	if not toolClass or toolClass == "" then return end
	RunConsoleCommand("gmod_toolmode", toolClass)
	if isfunction(spawnmenu.ActivateTool) then pcall(spawnmenu.ActivateTool, toolClass) end
	local ply = LocalPlayer()
	if IsValid(ply) then
		local wep = ply:GetWeapon("gmod_tool")
		if IsValid(wep) then input.SelectWeapon(wep) end
	end
end

local function PromptNewGroup(panelId)
	Derma_StringRequest("New Group", "Enter a name for the new group:", "",
		function(name)
			if name and name ~= "" then
				PinnedPanels.CreateGroup(name)
				if panelId then PinnedPanels.AddToGroup(name, panelId) end
			end
		end, function() end, "Create", "Cancel")
end

local function AddGroupSubmenu(menu, id)
	local groupSub, groupParent = menu:AddSubMenu("Group")
	if groupParent then groupParent:SetIcon("icon16/folder.png") end
	local currentGroup = PinnedPanels.GetGroupForPanel(id)

	if currentGroup then
		groupSub:AddOption("Remove from \"" .. currentGroup.name .. "\"", function()
			PinnedPanels.RemoveFromGroup(currentGroup.name, id)
		end):SetIcon("icon16/folder_delete.png")
		groupSub:AddSpacer()
	end

	for _, g in ipairs(PinnedPanels.Settings.groups) do
		local isInGroup = currentGroup and currentGroup.name == g.name
		local opt = groupSub:AddOption(g.name .. " (" .. #g.ids .. ")", function()
			if not isInGroup then PinnedPanels.AddToGroup(g.name, id) end
		end)
		opt:SetIcon(isInGroup and "icon16/tick.png" or "icon16/folder_go.png")
	end

	groupSub:AddSpacer()
	groupSub:AddOption("New Group...", function() PromptNewGroup(id) end):SetIcon("icon16/folder_add.png")
end

local function AddGroupFrameOptions(menu, id, gName)
	menu:AddSpacer()

	local activeId  = PinnedPanels.GetActiveGroupMemberId(id)
	local activePin = activeId and PinnedPanels.Pins[activeId]
	local suffix    = activePin and (" (" .. activePin.title .. ")") or ""

	local ungroupOpt = menu:AddOption("Ungroup Active Tab" .. suffix, function()
		if activeId then PinnedPanels.RemoveFromGroup(gName, activeId) end
	end)
	ungroupOpt:SetIcon("icon16/folder_go.png")
	if not activeId then ungroupOpt:SetEnabled(false) end

	local tabOpt = menu:AddOption("Unpin Active Tab" .. suffix, function()
		if activeId then PinnedPanels.Unpin(activeId) end
	end)
	tabOpt:SetIcon("icon16/tab_delete.png")
	if not activeId then tabOpt:SetEnabled(false) end

	menu:AddOption("Unpin All In Group", function()
		PinnedPanels.Unpin(id)
	end):SetIcon("icon16/cross.png")

	menu:AddOption("Dissolve Group (keep panels)", function()
		PinnedPanels.DeleteGroup(gName)
	end):SetIcon("icon16/folder_delete.png")
end

local function AddOpacitySubmenu(menu, pin)
	local opSub, opParent = menu:AddSubMenu("Idle Opacity")
	if opParent then opParent:SetIcon("icon16/contrast.png") end

	local function SetIdleOpacity(frac)
		pin.idleAlpha = frac
		PinnedPanels.Save()
		if PinnedPanels.UpdatePanelStates then PinnedPanels.UpdatePanelStates() end
	end

	local globalPct = math.Round((PinnedPanels.Settings.idleAlpha or 1) * 100)
	local gOpt = opSub:AddOption("Use Global (" .. globalPct .. "%)", function() SetIdleOpacity(nil) end)
	if pin.idleAlpha == nil then gOpt:SetIcon("icon16/tick.png") end

	for _, pct in ipairs({ 100, 75, 50, 25 }) do
		local opt = opSub:AddOption(pct .. "%", function() SetIdleOpacity(pct / 100) end)
		if pin.idleAlpha == pct / 100 then opt:SetIcon("icon16/tick.png") end
	end

	opSub:AddSpacer()
	opSub:AddOption("Custom...", function()
		local current = math.Round((pin.idleAlpha or PinnedPanels.Settings.idleAlpha or 1) * 100)
		Derma_StringRequest("Custom Idle Opacity",
			"Enter opacity in percent (10-100):", tostring(current),
			function(txt)
				local pct = tonumber(txt)
				if pct then SetIdleOpacity(math.Clamp(pct, 10, 100) / 100) end
			end, function() end, "Apply", "Cancel")
	end):SetIcon("icon16/pencil.png")
end

local function AddPositionOptions(menu, id, pin, frame)
	local lockText = pin.locked and "Unlock Position" or "Lock Position"
	local lockIcon = pin.locked and "icon16/lock_open.png" or "icon16/lock.png"
	menu:AddOption(lockText, function()
		pin.locked = not pin.locked
		PinnedPanels.Save()
	end):SetIcon(lockIcon)

	menu:AddOption("Copy Position", function()
		if IsValid(frame) then
			local x, y = frame:GetPos()
			local w, h = frame:GetSize()
			PinnedPanels._clipboard = { x = x, y = y, w = w, h = h }
		end
	end):SetIcon("icon16/page_copy.png")

	local pasteOpt = menu:AddOption("Paste Position", function()
		if PinnedPanels._clipboard and IsValid(frame) and not pin.locked then
			local c = PinnedPanels._clipboard
			local sw, sh = ScrW(), ScrH()
			frame:SetPos(math.Clamp(c.x, 0, sw - c.w), math.Clamp(c.y, 0, sh - c.h))
			frame:SetSize(math.Clamp(c.w, 150, sw), math.Clamp(c.h, 100, sh))
			PinnedPanels.Save()
		end
	end)
	pasteOpt:SetIcon("icon16/page_paste.png")
	if not PinnedPanels._clipboard then pasteOpt:SetEnabled(false) end
end

function PinnedPanels.OpenContextMenu(id, frame)
	local pin = PinnedPanels.Pins[id]
	if not pin then return end

	local menu = DermaMenu()

	local toolClass, toolTitle = PinnedPanels.GetPinTool(id)
	if toolClass then
		menu:AddOption("Equip Tool: " .. toolTitle, function()
			PinnedPanels.EquipToolgun(toolClass)
		end):SetIcon("icon16/wrench.png")
		menu:AddSpacer()
	end

	menu:AddOption("Bring to Front", function()
		if IsValid(frame) then
			frame:MoveToFront()
			frame:SetVisible(true)
		end
	end):SetIcon("icon16/arrow_up.png")

	menu:AddOption("Minimize to Taskbar", function()
		PinnedPanels.MinimizeToTaskbar(id)
	end):SetIcon("icon16/application_put.png")

	menu:AddOption("Hide Panel", function()
		if IsValid(frame) then frame:SetVisible(false) end
	end):SetIcon("icon16/eye.png")

	menu:AddSpacer()

	menu:AddOption("Auto Size", function() PinnedPanels.AutoSizePanel(id) end):SetIcon("icon16/arrow_inout.png")
	menu:AddOption("Change Colors...", function() PinnedPanels.OpenColorChanger(id) end):SetIcon("icon16/color_wheel.png")
	menu:AddOption("Rename...", function() PinnedPanels.OpenRenamePopup(id) end):SetIcon("icon16/textfield_rename.png")

	if pin.kind ~= "frame" and pin.kind ~= "group" then
		AddGroupSubmenu(menu, id)
	elseif pin.kind == "group" and pin.groupName then
		AddGroupFrameOptions(menu, id, pin.groupName)
	end

	AddOpacitySubmenu(menu, pin)

	menu:AddSpacer()
	AddPositionOptions(menu, id, pin, frame)

	if pin.kind ~= "group" then
		menu:AddSpacer()
		menu:AddOption("Unpin", function() PinnedPanels.Unpin(id) end):SetIcon("icon16/cross.png")
	end

	menu:Open(gui.MouseX(), gui.MouseY())
end
