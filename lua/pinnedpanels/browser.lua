local C = PinnedPanels.C

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
	searchBox:SetPlaceholderText(PinnedPanels.L("search_tools"))
	searchBox.Paint = function(self, w, h)
		draw.RoundedBox(4, 0, 0, w, h, C.searchBg)
		surface.SetDrawColor(C.searchBorder)
		surface.DrawOutlinedRect(0, 0, w, h, 1)
		self:DrawTextEntryText(C.textSearch, C.searchCursor, C.textSearch)
	end

	local countLbl = vgui.Create("DLabel", searchPanel)
	countLbl:Dock(RIGHT)
	countLbl:SetWide(80)
	countLbl:DockMargin(4, 0, 0, 0)
	countLbl:SetContentAlignment(6)
	countLbl:SetTextColor(C.mutedGray)
	countLbl:SetText("")

	local scroll = vgui.Create("DScrollPanel", root)
	scroll:Dock(FILL)
	scroll:DockMargin(4, 2, 4, 4)

	PinnedPanels.ThrottleScroll(scroll)

	local allTools = {}
	local rowCache = {}

	local rowHolder = vgui.Create("DPanel", root)
	rowHolder:SetSize(0, 0)
	rowHolder:SetVisible(false)
	rowHolder.Paint = function() end

	local noToolsLbl = vgui.Create("DLabel", rowHolder)
	noToolsLbl:SetText(PinnedPanels.L("no_tools"))
	noToolsLbl:SetTextColor(C.textSubtle)
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
			draw.RoundedBox(3, 0, 0, w, h, pinned and C.accentGreen or C.dotOff)
		end

		local lbl = vgui.Create("DLabel", row)
		lbl:SetText(t.niceName)
		lbl:SetTextColor(C.textLbl)
		lbl:Dock(FILL)
		lbl:DockMargin(18, 0, 0, 0)
		lbl:SetMouseInputEnabled(false)

		local pinBtn = vgui.Create("DButton", row)
		pinBtn:SetWide(68)
		pinBtn:Dock(RIGHT)
		pinBtn:DockMargin(0, 4, 4, 4)
		pinBtn:SetText("")

		pinBtn.Paint = function(self, w, h)
			local pin    = PinnedPanels.Pins[id]
			local pinned = pin and IsValid(pin.frame)
			local bgNorm  = pinned and C.unpinBtnBg or C.pinBtnBg
			local bgHov   = pinned and C.unpinBtnBgHov or C.pinBtnBgHov
			local txtCol  = pinned and C.unpinBtnTxt or C.pinBtnTxt
			local btnText = pinned and PinnedPanels.L("btn_unpin") or PinnedPanels.L("btn_pin")
			local bg = self:IsHovered() and bgHov or bgNorm
			draw.RoundedBox(4, 0, 0, w, h, bg)
			surface.SetDrawColor(pinned and C.unpinBtnOut or C.pinBtnOut)
			surface.DrawOutlinedRect(0, 0, w, h, 1)
			draw.SimpleText(btnText, "DermaDefault", w / 2, h / 2, txtCol, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end

		local function Refresh()
			if not IsValid(row) then return end
			local pin    = PinnedPanels.Pins[id]
			local pinned = pin and IsValid(pin.frame)
			pinBtn:SetTooltip(pinned and PinnedPanels.L("tip_unpin") or PinnedPanels.L("tip_pin"))
		end
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

		return row, Refresh
	end

	local inScroll = {}

	local function FilterList(filter)
		if #allTools == 0 then
			allTools = PinnedPanels.GetAllTools()
			for _, t in ipairs(allTools) do
				local id = "PP_" .. t.itemName
				if not rowCache[id] then
					local row, refresh = MakeRow(t, id)
					rowCache[id] = { panel = row, refresh = refresh, nameLower = t.niceName:lower() }
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
			if data and IsValid(data.panel) then
				local visible = not isFiltering or data.nameLower:find(lFilter, 1, true)

				if visible then
					data.panel:SetParent(scroll)
					data.panel:Dock(TOP)
					data.panel:DockMargin(2, 1, 2, 0)
					inScroll[id] = true
					count = count + 1
				end
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
		countLbl:SetText(isFiltering and (count .. " / " .. total) or PinnedPanels.Lf("count_tools", total))
	end

	hook.Add("PinnedPanels_StateChanged", root, function()
		if not IsValid(root) then
			hook.Remove("PinnedPanels_StateChanged", root)
			return
		end
		for _, data in pairs(rowCache) do
			if data.refresh then data.refresh() end
		end
	end)

	root.OnRemove = function()
		hook.Remove("PinnedPanels_StateChanged", root)
	end

	timer.Simple(0.5, function()
		if IsValid(scroll) then FilterList("") end
	end)

	searchBox.OnChange = function(self) FilterList(self:GetValue()) end

	return root
end
