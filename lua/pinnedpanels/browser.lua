function PinnedPanels.CreateBrowser(parent)
	local root = vgui.Create("DPanel", parent)
	root.Paint = function() end

	local searchPanel = vgui.Create("DPanel", root)
	searchPanel:Dock(TOP)
	searchPanel:SetTall(28)
	searchPanel:DockMargin(4, 4, 4, 2)
	searchPanel.Paint = function() end

	local searchBox = vgui.Create("DTextEntry", searchPanel)
	searchBox:Dock(FILL)
	searchBox:SetPlaceholderText("Search tools...")

	local scroll = vgui.Create("DScrollPanel", root)
	scroll:Dock(FILL)
	scroll:DockMargin(4, 2, 4, 4)

	local oldInvalidate = scroll.InvalidateLayout
	scroll.NextLayout = 0
	scroll.InvalidateLayout = function(self, layoutNow)
		if CurTime() < self.NextLayout then return end
		self.NextLayout = CurTime() + 0.1
		oldInvalidate(self, layoutNow)
	end

	local allTools = {}
	local rowCache = {}

	local noToolsLbl = vgui.Create("DLabel", scroll)
	noToolsLbl:SetText("No tools found.")
	noToolsLbl:Dock(TOP)
	noToolsLbl:DockMargin(10, 10, 10, 0)
	noToolsLbl:SetVisible(false)

	local function MakeRow(t, id)
		local row = vgui.Create("DPanel", scroll)
		row:Dock(TOP)
		row:SetTall(30)
		row:DockMargin(2, 1, 2, 0)

		row.Paint = function(self, w, h)
			local pinned = PinnedPanels.Pins[id] and IsValid(PinnedPanels.Pins[id].frame)
			local bg = pinned and Color(18, 48, 18, 220) or Color(26, 26, 40, 200)
			if self:IsHovered() then bg = pinned and Color(25, 65, 25) or Color(38, 38, 58) end
			draw.RoundedBox(3, 0, 0, w, h, bg)
			if pinned then
				surface.SetDrawColor(60, 200, 80)
				surface.DrawRect(0, 0, 3, h)
			end
		end

		local statusIcon = vgui.Create("DImage", row)
		statusIcon:SetSize(14, 14)
		statusIcon:Dock(LEFT)
		statusIcon:DockMargin(6, 8, 4, 8)

		local lbl = vgui.Create("DLabel", row)
		lbl:SetText(t.niceName)
		lbl:SetTextColor(Color(220, 225, 240))
		lbl:Dock(FILL)
		lbl:SetMouseInputEnabled(false)

		local pinBtn = vgui.Create("DButton", row)
		pinBtn:SetWide(60)
		pinBtn:Dock(RIGHT)
		pinBtn:DockMargin(0, 4, 4, 4)

		local function Refresh()
			local pinned = PinnedPanels.Pins[id] and IsValid(PinnedPanels.Pins[id].frame)
			statusIcon:SetImage(pinned and "icon16/tick.png" or "icon16/cross.png")
			pinBtn:SetText(pinned and "Unpin" or "Pin")
			pinBtn:SetIcon(pinned and "icon16/lock_open.png" or "icon16/lock_add.png")
		end

		hook.Add("PinnedPanels_StateChanged", row, function()
			Refresh()
		end)

		pinBtn.DoClick = function()
			local pinned = PinnedPanels.Pins[id] and IsValid(PinnedPanels.Pins[id].frame)
			if pinned then PinnedPanels.Unpin(id) else PinnedPanels.Pin(id, t.niceName, t.cpFunc) end
			Refresh()
		end

		return row
	end

	local function FilterList(filter)
		if #allTools == 0 then
			allTools = PinnedPanels.GetAllTools()
			for _, t in ipairs(allTools) do
				local id = "PP_" .. t.itemName
				rowCache[id] = { panel = MakeRow(t, id), niceName = t.niceName }
			end
		end

		local lFilter = filter and filter:lower() or ""
		local count = 0

		for id, data in pairs(rowCache) do
			if lFilter == "" or data.niceName:lower():find(lFilter, 1, true) then
				data.panel:SetVisible(true)
				data.panel:Dock(TOP)
				count = count + 1
			else
				data.panel:SetVisible(false)
			end
		end

		noToolsLbl:SetVisible(count == 0)
	end

	timer.Simple(0.5, function()
		if IsValid(scroll) then FilterList("") end
	end)

	searchBox.OnChange = function(self) FilterList(self:GetValue()) end

	return root
end
