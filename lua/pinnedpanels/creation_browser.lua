local CREATION_PIN_OPTS = PinnedPanels.CREATION_OPTS
local C = PinnedPanels.C

function PinnedPanels.CreateCreationBrowser(parent)
	local root = vgui.Create("DPanel", parent)
	root.Paint = function() end

	local info = vgui.Create("DLabel", root)
	info:SetText(PinnedPanels.L("creation_info"))
	info:SetWrap(true)
	info:Dock(TOP)
	info:DockMargin(10, 10, 10, 4)
	info:SetTall(32)
	info:SetTextColor(C.textInfo)
	info:SetAutoStretchVertical(true)

	local scroll = vgui.Create("DScrollPanel", root)
	scroll:Dock(FILL)
	scroll:DockMargin(4, 4, 4, 4)

	PinnedPanels.ThrottleScroll(scroll)

	local allTabs    = {}
	local refreshers = {}

	local function Populate()
		scroll:Clear()
		table.Empty(refreshers)

		allTabs = PinnedPanels.GetAllCreationTabs()

		if #allTabs == 0 then
			local lbl = vgui.Create("DLabel", scroll)
			lbl:SetText(PinnedPanels.L("creation_none"))
			lbl:SetWrap(true)
			lbl:Dock(TOP)
			lbl:DockMargin(10, 12, 10, 0)
			lbl:SetTall(50)
			lbl:SetTextColor(C.errorMuted)
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
			lbl:SetTextColor(C.textLight)
			lbl:Dock(FILL)
			lbl:SetContentAlignment(4)
			lbl:SetMouseInputEnabled(false)

			if isstring(tab.tooltip) and tab.tooltip ~= "" then
				local tooltipLbl = vgui.Create("DLabel", row)
				tooltipLbl:SetText(tab.tooltip)
				tooltipLbl:SetFont("DermaDefault")
				tooltipLbl:SetTextColor(C.textMuted)
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
				pinBtn:SetText(pinned and PinnedPanels.L("btn_unpin") or PinnedPanels.L("btn_pin"))
				pinBtn:SetIcon(pinned and "icon16/lock_open.png" or "icon16/lock_add.png")
			end
			Refresh()
			refreshers[#refreshers + 1] = Refresh

			pinBtn.DoClick = function()
				local pin    = PinnedPanels.Pins[id]
				local pinned = pin and IsValid(pin.frame)
				if pinned then
					PinnedPanels.Unpin(id)
				else
					PinnedPanels.Pin(id, tab.label, tab.func, false, CREATION_PIN_OPTS)
				end
			end
		end
	end

	hook.Add("PinnedPanels_StateChanged", root, function()
		if not IsValid(root) then
			hook.Remove("PinnedPanels_StateChanged", root)
			return
		end
		for _, refresh in ipairs(refreshers) do refresh() end
	end)

	root.OnRemove = function()
		hook.Remove("PinnedPanels_StateChanged", root)
	end

	timer.Simple(0.5, function()
		if IsValid(scroll) then Populate() end
	end)

	return root
end
