function PinnedPanels.CreateBrowser(parent)
	local root = vgui.Create("DPanel", parent)
	root.Paint = function() end

	local searchPanel = vgui.Create("DPanel", root)
	searchPanel:Dock(TOP)
	searchPanel:SetTall(32)
	searchPanel:DockMargin(4, 4, 4, 2)
	searchPanel.Paint = function() end

	local searchBox = vgui.Create("DTextEntry", searchPanel)
	searchBox:Dock(FILL)
	searchBox:SetPlaceholderText("Search tools...")

	local countLbl = vgui.Create("DLabel", searchPanel)
	countLbl:Dock(RIGHT)
	countLbl:SetWide(80)
	countLbl:DockMargin(4, 0, 0, 0)
	countLbl:SetContentAlignment(6)
	countLbl:SetTextColor(Color(120, 130, 145))
	countLbl:SetText("")

	local scroll = vgui.Create("DScrollPanel", root)
	scroll:Dock(FILL)
	scroll:DockMargin(4, 2, 4, 4)

	local oldInvalidate = scroll.InvalidateLayout
	scroll.NextLayout   = 0
	scroll.InvalidateLayout = function(self, layoutNow)
		if CurTime() < self.NextLayout then return end
		self.NextLayout = CurTime() + 0.1
		oldInvalidate(self, layoutNow)
	end

	local allTools  = {}
	local rowCache  = {}
	local hookNames = {}

	local rowHolder = vgui.Create("DPanel", root)
	rowHolder:SetSize(0, 0)
	rowHolder:SetVisible(false)
	rowHolder.Paint = function() end

	local noToolsLbl = vgui.Create("DLabel", rowHolder)
	noToolsLbl:SetText("No tools found.")
	noToolsLbl:SetTextColor(Color(140, 150, 165))
	noToolsLbl:SetTall(30)
	noToolsLbl:SetVisible(false)

	local function MakeRow(t, id)
		local row = vgui.Create("DPanel", rowHolder)
		row:SetTall(32)

		row.Paint = function(self, w, h)
			local pin    = PinnedPanels.Pins[id]
			local pinned = pin and IsValid(pin.frame)
			local bg     = pinned and Color(18, 48, 18, 220) or Color(26, 26, 40, 200)
			if self:IsHovered() then
				bg = pinned and Color(25, 65, 25) or Color(38, 38, 58)
			end
			draw.RoundedBox(3, 0, 0, w, h, bg)
			if pinned then
				surface.SetDrawColor(60, 200, 80)
				surface.DrawRect(0, 0, 3, h)
			end
		end

		local statusIcon = vgui.Create("DImage", row)
		statusIcon:SetSize(14, 14)
		statusIcon:Dock(LEFT)
		statusIcon:DockMargin(6, 9, 4, 9)

		local lbl = vgui.Create("DLabel", row)
		lbl:SetText(t.niceName)
		lbl:SetTextColor(Color(220, 225, 240))
		lbl:Dock(FILL)
		lbl:SetMouseInputEnabled(false)

		local pinBtn = vgui.Create("DButton", row)
		pinBtn:SetWide(64)
		pinBtn:Dock(RIGHT)
		pinBtn:DockMargin(0, 4, 4, 4)

		local function Refresh()
			if not IsValid(row) then return end
			local pin    = PinnedPanels.Pins[id]
			local pinned = pin and IsValid(pin.frame)
			statusIcon:SetImage(pinned and "icon16/tick.png" or "icon16/cross.png")
			pinBtn:SetText(pinned and "Unpin" or "Pin")
			pinBtn:SetIcon(pinned and "icon16/lock_open.png" or "icon16/lock_add.png")
		end

		local hookName = "PinnedPanels_Browser_" .. id
		hookNames[id]  = hookName
		hook.Add("PinnedPanels_StateChanged", hookName, function()
			if IsValid(row) then
				Refresh()
			else
				hook.Remove("PinnedPanels_StateChanged", hookName)
			end
		end)

		Refresh()

		pinBtn.DoClick = function()
			local pin    = PinnedPanels.Pins[id]
			local pinned = pin and IsValid(pin.frame)
			if pinned then
				PinnedPanels.Unpin(id)
			else
				PinnedPanels.Pin(id, t.niceName, t.cpFunc)
			end
			Refresh()
		end

		return row
	end

	local inScroll = {}

	local function FilterList(filter)
		if #allTools == 0 then
			allTools = PinnedPanels.GetAllTools()
			for _, t in ipairs(allTools) do
				local id = "PP_" .. t.itemName
				if not rowCache[id] then
					rowCache[id] = { panel = MakeRow(t, id), niceName = t.niceName }
				end
			end
		end

		for id in pairs(inScroll) do
			local data = rowCache[id]
			if data and IsValid(data.panel) then
				data.panel:SetParent(rowHolder)
			end
			inScroll[id] = nil
		end
		if IsValid(noToolsLbl) then
			noToolsLbl:SetParent(rowHolder)
		end

		local lFilter = filter and filter:lower() or ""
		local count   = 0
		local total   = #allTools

		for _, t in ipairs(allTools) do
			local id   = "PP_" .. t.itemName
			local data = rowCache[id]
			if not data or not IsValid(data.panel) then continue end
			local visible = lFilter == "" or data.niceName:lower():find(lFilter, 1, true)
			if visible then
				data.panel:SetParent(scroll)
				data.panel:Dock(TOP)
				data.panel:DockMargin(2, 1, 2, 0)
				inScroll[id] = true
				count = count + 1
			end
		end

		if IsValid(noToolsLbl) then
			noToolsLbl:SetVisible(count == 0 and total > 0)
			if count == 0 and total > 0 then
				noToolsLbl:SetParent(scroll)
				noToolsLbl:Dock(TOP)
				noToolsLbl:DockMargin(10, 10, 10, 0)
			end
		end
		countLbl:SetText(lFilter == "" and (total .. " tools") or (count .. " / " .. total))
	end

	root.OnRemove = function()
		for _, name in pairs(hookNames) do
			hook.Remove("PinnedPanels_StateChanged", name)
		end
	end

	timer.Simple(0.5, function()
		if IsValid(scroll) then FilterList("") end
	end)

	searchBox.OnChange = function(self) FilterList(self:GetValue()) end

	return root
end

