-- ============================================================
--  PinnedPanels / autorun entry point
-- ============================================================

if not CLIENT then return end

include("pinnedpanels/core.lua")
include("pinnedpanels/layout_editor.lua")
include("pinnedpanels/browser.lua")
include("pinnedpanels/pinned_list.lua")

local function CreatePinnedPanelsTab()
	local root = vgui.Create("DPanel")
	root.Paint = function(self, w, h)
		draw.RoundedBox(0, 0, 0, w, h, Color(12, 12, 20, 255))
	end

	local header = vgui.Create("DPanel", root)
	header:Dock(TOP)
	header:SetTall(32)
	header.Paint = function(self, w, h)
		draw.RoundedBox(0, 0, 0, w, h, Color(18, 18, 30, 255))
		surface.SetDrawColor(60, 140, 255)
		surface.DrawRect(0, h - 2, w, 2)
	end

	local icon = vgui.Create("DImage", header)
	icon:SetImage("icon16/lock.png")
	icon:SetSize(16, 16)
	icon:Dock(LEFT)
	icon:DockMargin(8, 8, 4, 8)

	local title = vgui.Create("DLabel", header)
	title:SetText("Pinned Tool Panels")
	title:SetFont("DermaLarge")
	title:SetTextColor(Color(180, 210, 255))
	title:Dock(LEFT)
	title:SizeToContents()

	local sheet = vgui.Create("DPropertySheet", root)
	sheet:Dock(FILL)

	local browserPanel = PinnedPanels.CreateBrowser(nil)
	sheet:AddSheet("Tools", browserPanel, "icon16/wrench.png")

	local pinnedPanel = PinnedPanels.CreatePinnedList(nil)
	sheet:AddSheet("Pinned", pinnedPanel, "icon16/lock.png")

	local editorHost = vgui.Create("DPanel")
	editorHost.Paint = function() end
	local editor = PinnedPanels.CreateLayoutEditor(editorHost)
	sheet:AddSheet("Layout", editorHost, "icon16/application_view_columns.png")

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
