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
	searchBox.Paint = function(self, w, h)
		draw.RoundedBox(4, 0, 0, w, h, Color(18, 20, 28, 255))
		surface.SetDrawColor(50, 55, 75)
		surface.DrawOutlinedRect(0, 0, w, h, 1)
		self:DrawTextEntryText(Color(210, 215, 230), Color(50, 100, 200, 150), Color(210, 215, 230))
	end

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

	PinnedPanels.ThrottleScroll(scroll)

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

		row.Paint = PinnedPanels.MakePinRowPaint(id, 3)

		local statusDot = vgui.Create("DPanel", row)
		statusDot:SetSize(6, 6)
		statusDot:SetPos(8, 13)
		statusDot:SetMouseInputEnabled(false)
		statusDot.Paint = function(self, w, h)
			local pin    = PinnedPanels.Pins[id]
			local pinned = pin and IsValid(pin.frame)
			draw.RoundedBox(3, 0, 0, w, h, pinned and Color(60, 200, 80) or Color(70, 75, 90))
		end

		local lbl = vgui.Create("DLabel", row)
		lbl:SetText(t.niceName)
		lbl:SetTextColor(Color(220, 225, 240))
		lbl:Dock(FILL)
		lbl:DockMargin(18, 0, 0, 0)
		lbl:SetMouseInputEnabled(false)

		local pinBtn = vgui.Create("DButton", row)
		pinBtn:SetWide(68)
		pinBtn:Dock(RIGHT)
		pinBtn:DockMargin(0, 4, 4, 4)
		pinBtn:SetText("")

		local function Refresh()
			if not IsValid(row) then return end
			local pin    = PinnedPanels.Pins[id]
			local pinned = pin and IsValid(pin.frame)
			local btnText = pinned and "Unpin" or "Pin"
			local btnIcon = pinned and "icon16/lock_open.png" or "icon16/lock_add.png"
			local bgNorm  = pinned and Color(30, 80, 30) or Color(35, 40, 55)
			local bgHov   = pinned and Color(50, 110, 50) or Color(55, 65, 90)
			local txtCol  = pinned and Color(100, 230, 110) or Color(160, 175, 210)
			pinBtn.Paint = function(self, w, h)
				local bg = self:IsHovered() and bgHov or bgNorm
				draw.RoundedBox(4, 0, 0, w, h, bg)
				surface.SetDrawColor(pinned and Color(40, 120, 40) or Color(50, 55, 80))
				surface.DrawOutlinedRect(0, 0, w, h, 1)
				draw.SimpleText(btnText, "DermaDefault", w / 2, h / 2, txtCol, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			end
			pinBtn:SetTooltip(pinned and "Remove this tool from screen" or "Pin this tool to screen")
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
		end

		return row
	end

	local inScroll       = {}

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
		if IsValid(noToolsLbl) then noToolsLbl:SetParent(rowHolder) end

		local lFilter     = filter and filter:lower() or ""
		local isFiltering = lFilter ~= ""
		local count       = 0
		local total       = #allTools

		for _, t in ipairs(allTools) do
			local id   = "PP_" .. t.itemName
			local data = rowCache[id]
			if not data or not IsValid(data.panel) then continue end
			local visible = isFiltering and data.niceName:lower():find(lFilter, 1, true)
				or not isFiltering

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
		countLbl:SetText(isFiltering and (count .. " / " .. total) or (total .. " tools"))
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
