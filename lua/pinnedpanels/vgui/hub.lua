-- PinnedPanelsHub (§20.1): the "Pinned Panels" spawn-menu tab. The spawn menu destroys and rebuilds it on
-- every rebuild (G11), so it holds no state and reads Layout and Sources when shown.

local PP = PinnedPanels
local Layout, Sources, T = PP.Layout, PP.Sources, PP.Theme

local HEADER_H = 56

local function noPaint() end

local function paintHeader(_, w, h)
	draw.RoundedBox(0, 0, 0, w, h, T.header)
	surface.SetDrawColor(T.headerLine)
	surface.DrawRect(0, h - 2, w, 2)
	draw.RoundedBox(8, 16, 16, 24, 24, T.bg)
end

local function paintTab(tab, w, h)
	local active = tab:GetPropertySheet():GetActiveTab() == tab
	local bg = active and T.bg or (tab:IsHovered() and T.hover or T.bgDarker)
	draw.RoundedBoxEx(6, 0, 0, w, h, bg, true, true, false, false)
	if active then
		surface.SetDrawColor(T.accent)
		surface.DrawRect(0, h - 2, w, 2)
	end
end

local HUB = {}

function HUB:Init()
	local header = self:Add("DPanel")
	header:Dock(TOP)
	header:SetTall(HEADER_H)
	header.Paint = paintHeader

	local icon = header:Add("DImage")
	icon:SetImage("icon16/application_double.png")
	icon:SetSize(16, 16)
	icon:SetPos(20, 20)

	local title = header:Add("DLabel")
	title:Dock(LEFT)
	title:DockMargin(HEADER_H, 0, 16, 0)
	title:SetFont("DermaLarge")
	title:SetTextColor(T.textBright)
	title:SetText(PP.L("app.title"))
	title:SizeToContentsX()

	local subtitle = header:Add("DLabel")
	subtitle:Dock(LEFT)
	subtitle:DockMargin(0, 8, 0, 0)
	subtitle:SetTextColor(T.textSubtle)
	subtitle:SetText(PP.L("app.subtitle"))
	subtitle:SizeToContentsX()

	self.count = header:Add("DLabel")
	self.count:Dock(RIGHT)
	self.count:SetWide(160)
	self.count:DockMargin(0, 0, 12, 0)
	self.count:SetContentAlignment(6)
	self.count:SetTextColor(T.accent)

	local sheet = self:Add("DPropertySheet")
	sheet:Dock(FILL)
	sheet:DockMargin(8, 8, 8, 8)
	sheet.Paint = noPaint

	local tools = vgui.Create("PinnedPanelsCatalog")
	tools:SetKind("tool")
	sheet:AddSheet(PP.L("tab.tools"), tools, "icon16/wrench.png")

	local content = vgui.Create("PinnedPanelsCatalog")
	content:SetKind("creation")
	sheet:AddSheet(PP.L("tab.content"), content, "icon16/application_view_list.png")

	local widgets = vgui.Create("PinnedPanelsCatalog")
	widgets:SetKind("native")
	sheet:AddSheet(PP.L("tab.widgets"), widgets, "icon16/application_view_tile.png")

	sheet:AddSheet(PP.L("tab.pinned"), vgui.Create("PinnedPanelsPinned"), "icon16/lock.png")
	sheet:AddSheet(PP.L("tab.layout"), vgui.Create("PinnedPanelsLayout"), "icon16/application_view_columns.png")
	sheet:AddSheet(PP.L("tab.settings"), vgui.Create("PinnedPanelsSettings"), "icon16/cog.png")

	for _, item in ipairs(sheet:GetItems()) do item.Tab.Paint = paintTab end

	self:UpdateCount()
	hook.Add("PinnedPanelsChanged", self, self.UpdateCount)
end

-- Windows the player can see a tab of; empty named groups don't count.
function HUB:UpdateCount()
	local n = 0
	for _, w in ipairs(Layout.Windows()) do
		if #w.tabs > 0 then n = n + 1 end
	end
	self.count:SetText(PP.L(n == 1 and "pin.count_one" or "pin.count_many", n))
end

function HUB:Paint(w, h)
	draw.RoundedBox(0, 0, 0, w, h, T.bgDark)
end

vgui.Register("PinnedPanelsHub", HUB, "DPanel")

spawnmenu.AddCreationTab(Sources.HUB_TAB, function()
	return vgui.Create("PinnedPanelsHub")
end, "icon16/lock.png", 9999)
