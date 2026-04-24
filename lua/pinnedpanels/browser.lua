-- ============================================================
--  PinnedPanels / browser.lua
-- ============================================================

function PinnedPanels.CreateBrowser(parent)
	local root = vgui.Create("DPanel", parent)
	root:Dock(FILL)
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

	local allTools = {}

	local function MakeRow(t)
		local id = "PP_" .. t.itemName

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
		Refresh()

		pinBtn.DoClick = function()
			local pinned = PinnedPanels.Pins[id] and IsValid(PinnedPanels.Pins[id].frame)
			if pinned then PinnedPanels.Unpin(id) else PinnedPanels.Pin(id, t.niceName, t.cpFunc) end
			Refresh()
		end
	end

	local function Rebuild(filter)
		scroll:Clear()
		if #allTools == 0 then allTools = PinnedPanels.GetAllTools() end
		local lFilter = filter and filter:lower() or ""
		local count = 0
		for _, t in ipairs(allTools) do
			if lFilter == "" or t.niceName:lower():find(lFilter, 1, true) then
				MakeRow(t)
				count = count + 1
			end
		end
		if count == 0 then
			local lbl = vgui.Create("DLabel", scroll)
			lbl:SetText("No tools found.")
			lbl:Dock(TOP)
			lbl:DockMargin(10, 10, 10, 0)
		end
	end

	timer.Simple(0.5, function()
		if IsValid(scroll) then Rebuild("") end
	end)

	searchBox.OnChange = function(self) Rebuild(self:GetValue()) end

	return root
end
