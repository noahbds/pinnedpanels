if not CLIENT then return end

include("pinnedpanels/core.lua")
include("pinnedpanels/layout_editor.lua")
include("pinnedpanels/browser.lua")
include("pinnedpanels/pinned_list.lua")
include("pinnedpanels/interact_mode.lua")
include("pinnedpanels/settings_tab.lua")

local function CreatePinnedPanelsTab()
	local root = vgui.Create("DPanel")
	root.Paint = function(self, w, h)
		draw.RoundedBox(0, 0, 0, w, h, Color(24, 26, 32, 255))
	end

	local header = vgui.Create("DPanel", root)
	header:Dock(TOP)
	header:SetTall(56)
	header.Paint = function(self, w, h)
		draw.RoundedBox(0, 0, 0, w, h, Color(18, 20, 26, 255))

		surface.SetDrawColor(35, 38, 46, 255)
		surface.DrawRect(0, h - 2, w, 2)
	end

	local iconContainer = vgui.Create("DPanel", header)
	iconContainer:Dock(LEFT)
	iconContainer:SetWide(56)
	iconContainer.Paint = function(self, w, h)
		draw.RoundedBox(8, 16, 16, 24, 24, Color(30, 34, 42, 255))
	end

	local icon = vgui.Create("DImage", iconContainer)
	icon:SetImage("icon16/application_double.png")
	icon:SetSize(16, 16)
	icon:SetPos(20, 20)

	local title = vgui.Create("DLabel", header)
	title:SetText("Pinned Tool Panels")
	title:SetFont("DermaLarge")
	title:SetTextColor(Color(240, 245, 255))
	title:Dock(LEFT)
	title:DockMargin(0, 0, 16, 0)
	title:SetContentAlignment(4)
	title:SizeToContentsX()

	local subtitle = vgui.Create("DLabel", header)
	subtitle:SetText("Manage and customize your on-screen tool menus")
	subtitle:SetFont("DermaDefault")
	subtitle:SetTextColor(Color(140, 150, 165))
	subtitle:Dock(LEFT)
	subtitle:DockMargin(0, 8, 0, 0)
	subtitle:SetContentAlignment(4)
	subtitle:SizeToContentsX()

	local sheet = vgui.Create("DPropertySheet", root)
	sheet:Dock(FILL)
	sheet:DockMargin(8, 8, 8, 8)

	sheet.Paint = function() end

	local browserPanel = PinnedPanels.CreateBrowser(nil)
	sheet:AddSheet("Tools", browserPanel, "icon16/wrench.png")

	local pinnedPanel = PinnedPanels.CreatePinnedList(nil)
	sheet:AddSheet("Pinned", pinnedPanel, "icon16/lock.png")

	local editorHost = vgui.Create("DPanel")
	editorHost.Paint = function(self, w, h)
		draw.RoundedBox(0, 0, 0, w, h, Color(30, 32, 40, 255))
	end
	local editor = PinnedPanels.CreateLayoutEditor(editorHost)
	sheet:AddSheet("Layout", editorHost, "icon16/application_view_columns.png")

	local settingsPanel = PinnedPanels.CreateSettingsTab(nil)
	sheet:AddSheet("Settings", settingsPanel, "icon16/cog.png")
	for _, item in ipairs(sheet:GetItems()) do
		local tab = item.Tab
		tab.Paint = function(self, w, h)
			local isActive = sheet:GetActiveTab() == self
			local bg = isActive and Color(30, 32, 40, 255) or Color(20, 22, 28, 255)

			if self:IsHovered() and not isActive then
				bg = Color(35, 38, 48, 255)
			end
			draw.RoundedBoxEx(6, 0, 0, w, h, bg, true, true, false, false)
			if isActive then
				surface.SetDrawColor(60, 140, 255)
				surface.DrawRect(0, 0, w, 2)
			end
		end
	end

	sheet.OnActiveTabChanged = function(self, old, new)
		if IsValid(pinnedPanel) and pinnedPanel.Rebuild then
			pinnedPanel:Rebuild()
		end
		if editor and new and IsValid(new.Panel) and new.Panel == editorHost then
			editor:Rebuild()
		end
	end

	return root
end

spawnmenu.AddCreationTab("Pinned Panels", CreatePinnedPanelsTab, "icon16/lock.png", 9999)

concommand.Add("pp_clearall", function()
	for id in pairs(PinnedPanels.Pins) do PinnedPanels.Unpin(id) end
	print("[PinnedPanels] All pins cleared.")
end, nil, "Remove all pinned panels")

concommand.Add("pp_list", function()
	for id, pin in pairs(PinnedPanels.Pins) do
		print(string.format("  %s  title=%s  valid=%s", id, pin.title, tostring(IsValid(pin.frame))))
	end
end, nil, "List pinned panels")

print("[PinnedPanels] Loaded.")
