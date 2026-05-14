local CREATION_PIN_OPTS = PinnedPanels.CREATION_OPTS

function PinnedPanels.CreateCreationBrowser(parent)
	local root = vgui.Create("DPanel", parent)
	root.Paint = function() end

	local info = vgui.Create("DLabel", root)
	info:SetText(
		"Pin GMod's built-in content browsers as floating panels — props, entities, NPCs, saves, and more. " ..
		"Requires the sandbox gamemode."
	)
	info:SetWrap(true)
	info:Dock(TOP)
	info:DockMargin(10, 10, 10, 4)
	info:SetTall(32)
	info:SetTextColor(Color(130, 140, 160))
	info:SetAutoStretchVertical(true)

	local scroll = vgui.Create("DScrollPanel", root)
	scroll:Dock(FILL)
	scroll:DockMargin(4, 4, 4, 4)

	PinnedPanels.ThrottleScroll(scroll)

	local allTabs   = {}
	local hookNames = {}

	local function Populate()
		scroll:Clear()
		for _, name in pairs(hookNames) do
			hook.Remove("PinnedPanels_StateChanged", name)
		end
		hookNames = {}

		allTabs = PinnedPanels.GetAllCreationTabs()

		if #allTabs == 0 then
			local lbl = vgui.Create("DLabel", scroll)
			lbl:SetText("No creation tabs found. Make sure you are playing on a sandbox-based gamemode.")
			lbl:SetWrap(true)
			lbl:Dock(TOP)
			lbl:DockMargin(10, 12, 10, 0)
			lbl:SetTall(50)
			lbl:SetTextColor(Color(160, 80, 80))
			lbl:SetAutoStretchVertical(true)
			return
		end

		for _, tab in ipairs(allTabs) do
			local id = tab.id

			local row = vgui.Create("DPanel", scroll)
			row:Dock(TOP)
			row:SetTall(40)
			row:DockMargin(2, 1, 2, 1)

			row.Paint = PinnedPanels.MakePinRowPaint(id, 4)

			if isstring(tab.icon) and tab.icon ~= "" then
				local img = vgui.Create("DImage", row)
				img:SetImage(tab.icon)
				img:SetSize(16, 16)
				img:Dock(LEFT)
				img:DockMargin(10, 12, 6, 12)
				img:SetMouseInputEnabled(false)
			end

			local lbl = vgui.Create("DLabel", row)
			lbl:SetText(tab.label)
			lbl:SetFont("DermaDefaultBold")
			lbl:SetTextColor(Color(215, 220, 235))
			lbl:Dock(FILL)
			lbl:SetContentAlignment(4)
			lbl:SetMouseInputEnabled(false)

			if isstring(tab.tooltip) and tab.tooltip ~= "" then
				local tooltipLbl = vgui.Create("DLabel", row)
				tooltipLbl:SetText(tab.tooltip)
				tooltipLbl:SetFont("DermaDefault")
				tooltipLbl:SetTextColor(Color(110, 120, 140))
				tooltipLbl:Dock(BOTTOM)
				tooltipLbl:SetTall(14)
				tooltipLbl:DockMargin(0, 0, 6, 3)
				tooltipLbl:SetMouseInputEnabled(false)
				tooltipLbl:SizeToContentsX()
			end

			local pinBtn = vgui.Create("DButton", row)
			pinBtn:SetWide(70)
			pinBtn:Dock(RIGHT)
			pinBtn:DockMargin(0, 6, 6, 6)

			local function Refresh()
				if not IsValid(pinBtn) then return end
				local pin    = PinnedPanels.Pins[id]
				local pinned = pin and IsValid(pin.frame)
				pinBtn:SetText(pinned and "Unpin" or "Pin")
				pinBtn:SetIcon(pinned and "icon16/lock_open.png" or "icon16/lock_add.png")
			end
			Refresh()

			local hookName = "PPC_Browser_" .. id
			hookNames[id]  = hookName
			hook.Add("PinnedPanels_StateChanged", hookName, function()
				if IsValid(pinBtn) then Refresh()
				else hook.Remove("PinnedPanels_StateChanged", hookName) end
			end)

			local capturedTab = tab
			pinBtn.DoClick = function()
				local pin    = PinnedPanels.Pins[id]
				local pinned = pin and IsValid(pin.frame)
				if pinned then
					PinnedPanels.Unpin(id)
				else
					PinnedPanels.Pin(id, capturedTab.label, capturedTab.func, false, CREATION_PIN_OPTS)
				end
			end
		end
	end

	root.OnRemove = function()
		for _, name in pairs(hookNames) do
			hook.Remove("PinnedPanels_StateChanged", name)
		end
	end

	timer.Simple(0.5, function()
		if IsValid(scroll) then Populate() end
	end)

	return root
end
