if not CLIENT then return end

include("pinnedpanels/colors.lua")
include("pinnedpanels/core.lua")
include("pinnedpanels/persistence.lua")
include("pinnedpanels/helpers.lua")
include("pinnedpanels/frame.lua")
include("pinnedpanels/popups.lua")
include("pinnedpanels/context_menu.lua")
include("pinnedpanels/pin.lua")
include("pinnedpanels/groups.lua")
include("pinnedpanels/autosize.lua")
include("pinnedpanels/layout_editor.lua")
include("pinnedpanels/taskbar.lua")
include("pinnedpanels/browser.lua")
include("pinnedpanels/creation_browser.lua")
include("pinnedpanels/pinned_list.lua")
include("pinnedpanels/cursor_mode.lua")
include("pinnedpanels/keyboard.lua")
include("pinnedpanels/settings_tab.lua")

local C = PinnedPanels.C

local function CreatePinnedPanelsTab()
	local root = vgui.Create("DPanel")
	root.Paint = function(self, w, h)
		draw.RoundedBox(0, 0, 0, w, h, C.bgDark)
	end

	local header = vgui.Create("DPanel", root)
	header:Dock(TOP)
	header:SetTall(56)
	header.Paint = function(self, w, h)
		draw.RoundedBox(0, 0, 0, w, h, C.bgHeader)
		surface.SetDrawColor(C.bgHeaderLine)
		surface.DrawRect(0, h - 2, w, 2)
	end

	local iconContainer = vgui.Create("DPanel", header)
	iconContainer:Dock(LEFT)
	iconContainer:SetWide(56)
	iconContainer.Paint = function(self, w, h)
		draw.RoundedBox(8, 16, 16, 24, 24, C.bgIcon)
	end

	local icon = vgui.Create("DImage", iconContainer)
	icon:SetImage("icon16/application_double.png")
	icon:SetSize(16, 16)
	icon:SetPos(20, 20)

	local title = vgui.Create("DLabel", header)
	title:SetText("Pinned Tool Panels")
	title:SetFont("DermaLarge")
	title:SetTextColor(C.textBright)
	title:Dock(LEFT)
	title:DockMargin(0, 0, 16, 0)
	title:SetContentAlignment(4)
	title:SizeToContentsX()

	local subtitle = vgui.Create("DLabel", header)
	subtitle:SetText("Manage and customize your on-screen tool menus")
	subtitle:SetFont("DermaDefault")
	subtitle:SetTextColor(C.textSubtle)
	subtitle:Dock(LEFT)
	subtitle:DockMargin(0, 8, 0, 0)
	subtitle:SetContentAlignment(4)
	subtitle:SizeToContentsX()

	local pinCount = vgui.Create("DLabel", header)
	pinCount:Dock(RIGHT)
	pinCount:SetWide(130)
	pinCount:DockMargin(0, 0, 12, 0)
	pinCount:SetContentAlignment(6)
	pinCount:SetFont("DermaDefault")
	pinCount:SetTextColor(C.textPin)

	local function UpdatePinCount()
		if not IsValid(pinCount) then return end
		local n = 0
		for id, pin in pairs(PinnedPanels.Pins or {}) do
			if IsValid(pin.frame) and not (pin.kind ~= "group" and PinnedPanels.GetGroupForPanel(id)) then
				n = n + 1
			end
		end
		pinCount:SetText(n .. " panel" .. (n == 1 and "" or "s") .. " pinned")
	end
	UpdatePinCount()
	hook.Add("PinnedPanels_StateChanged", pinCount, function()
		if IsValid(pinCount) then UpdatePinCount() else
			hook.Remove("PinnedPanels_StateChanged", pinCount)
		end
	end)

	local sheet = vgui.Create("DPropertySheet", root)
	sheet:Dock(FILL)
	sheet:DockMargin(8, 8, 8, 8)
	sheet.Paint = function() end

	local browserPanel = PinnedPanels.CreateBrowser(nil)
	sheet:AddSheet("Tools", browserPanel, "icon16/wrench.png")

	local contentPanel = PinnedPanels.CreateCreationBrowser(nil)
	sheet:AddSheet("Content", contentPanel, "icon16/application_view_list.png")

	local pinnedPanel = PinnedPanels.CreatePinnedList(nil)
	sheet:AddSheet("Pinned", pinnedPanel, "icon16/lock.png")

	local editorHost = vgui.Create("DPanel")
	editorHost.Paint = function(self, w, h)
		draw.RoundedBox(0, 0, 0, w, h, C.bg)
	end
	local editor = PinnedPanels.CreateLayoutEditor(editorHost)
	sheet:AddSheet("Layout", editorHost, "icon16/application_view_columns.png")

	local settingsPanel = PinnedPanels.CreateSettingsTab(nil)
	sheet:AddSheet("Settings", settingsPanel, "icon16/cog.png")

	for _, item in ipairs(sheet:GetItems()) do
		local tab = item.Tab
		tab.Paint = function(self, w, h)
			local isActive = sheet:GetActiveTab() == self
			local bg = isActive and C.bg or C.bgDarker
			if self:IsHovered() and not isActive then
				bg = C.bgHover
			end
			draw.RoundedBoxEx(6, 0, 0, w, h, bg, true, true, false, false)
			if isActive then
				surface.SetDrawColor(C.accent)
				surface.DrawRect(0, h - 2, w, 2)
			end
		end
	end

	sheet.OnActiveTabChanged = function(self, old, new)
		if not IsValid(new) then return end
		local newPanel = new:GetPanel()
		if IsValid(pinnedPanel) and newPanel == pinnedPanel and pinnedPanel.Rebuild then
			pinnedPanel:Rebuild()
		end
		if editor and IsValid(editorHost) and newPanel == editorHost then
			editor:Rebuild()
		end
	end

	return root
end

spawnmenu.AddCreationTab("Pinned Panels", CreatePinnedPanelsTab, "icon16/lock.png", 9999)

concommand.Add("pp_clearall", function()
	PinnedPanels.UnpinAll()
	print("[PinnedPanels] All pins cleared.")
end, nil, "Remove all pinned panels")

concommand.Add("pp_list", function()
	local count = 0
	for id, pin in pairs(PinnedPanels.Pins) do
		local x, y, w, h = 0, 0, 0, 0
		if IsValid(pin.frame) then
			x, y = pin.frame:GetPos()
			w, h = pin.frame:GetSize()
		end
		local group = PinnedPanels.GetGroupForPanel(id)
		local groupName = group and (" group=" .. group.name) or ""
		print(string.format("  %-30s  title=%-25s  valid=%-5s  pos=%d,%d  size=%dx%d%s",
			id, pin.title, tostring(IsValid(pin.frame)), x, y, w, h, groupName))
		count = count + 1
	end
	print(string.format("[PinnedPanels] %d pin(s) total.", count))
end, nil, "List pinned panels")

concommand.Add("pp_reload", function()
	local ids = {}
	for id in pairs(PinnedPanels.Pins) do ids[#ids + 1] = id end
	for _, id in ipairs(ids) do
		local pin = PinnedPanels.Pins[id]
		if pin and IsValid(pin.frame) then pin.frame:Remove() end
		PinnedPanels.Pins[id] = nil
	end
	PinnedPanels.LoadSettings()
	PinnedPanels.CreateTaskbar()
	PinnedPanels.RestoreAll(true)
	print("[PinnedPanels] Reloaded.")
end, nil, "Reload and restore all pinned panels from disk")

print("[PinnedPanels] Loaded.")
