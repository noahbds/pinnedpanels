local C = PinnedPanels.C

-- ── Settings Tab Shell ───────────────────────────────────────────────────────

function PinnedPanels.CreateSettingsTab(parent)
	local root = vgui.Create("DPanel", parent)
	root.Paint = function(_, w, h)
		draw.RoundedBox(0, 0, 0, w, h, C.bg)
	end

	local nav = vgui.Create("DPanel", root)
	nav:Dock(LEFT)
	nav:SetWide(150)
	nav:DockPadding(0, 8, 0, 8)
	nav.Paint = function(_, w, h)
		draw.RoundedBox(0, 0, 0, w, h, C.bgDarker)
		surface.SetDrawColor(C.bgHeaderLine)
		surface.DrawRect(w - 1, 0, 1, h)
	end

	local scroll = vgui.Create("DScrollPanel", root)
	scroll:Dock(FILL)
	scroll:DockMargin(16, 16, 16, 16)
	PinnedPanels.ThrottleScroll(scroll)

	local popups = {}
	local function ClosePopups()
		for key, popup in pairs(popups) do
			if IsValid(popup) then popup:Remove() end
			popups[key] = nil
		end
	end

	local activeId
	local navButtons = {}

	local function ShowPage(id)
		ClosePopups()
		activeId = id
		scroll:Clear()

		for pid, nb in pairs(navButtons) do
			if IsValid(nb.lbl) then
				nb.lbl:SetTextColor(pid == id and C.textBright or C.textBody)
			end
		end

		for _, page in ipairs(PinnedPanels.SettingsPages) do
			if page.id == id then
				page.build(scroll, {
					popups  = popups,
					Rebuild = function() ShowPage(id) end,
				})
				break
			end
		end
	end

	local function BuildNav()
		nav:Clear()
		navButtons = {}

		for _, page in ipairs(PinnedPanels.SettingsPages) do
			local btn = vgui.Create("DButton", nav)
			btn:Dock(TOP)
			btn:SetTall(34)
			btn:DockMargin(8, 2, 8, 0)
			btn:SetText("")
			btn.Paint = function(self, w, h)
				local active = activeId == page.id
				if active then
					draw.RoundedBox(4, 0, 0, w, h, C.bgCard)
					surface.SetDrawColor(C.accent)
					surface.DrawRect(0, 6, 2, h - 12)
				elseif self:IsHovered() then
					draw.RoundedBox(4, 0, 0, w, h, C.bgHover)
				end
			end

			local icon = vgui.Create("DImage", btn)
			icon:SetImage(page.icon)
			icon:SetSize(16, 16)
			icon:SetPos(10, 9)
			icon:SetMouseInputEnabled(false)

			local lbl = vgui.Create("DLabel", btn)
			lbl:SetText(PinnedPanels.L(page.nameKey))
			lbl:SetTextColor(page.id == activeId and C.textBright or C.textBody)
			lbl:Dock(FILL)
			lbl:DockMargin(34, 0, 0, 0)
			lbl:SetMouseInputEnabled(false)

			btn.DoClick = function() ShowPage(page.id) end
			navButtons[page.id] = { btn = btn, lbl = lbl }
		end
	end

	BuildNav()
	ShowPage(PinnedPanels.SettingsPages[1].id)

	hook.Add("PinnedPanels_LanguageChanged", root, function()
		if not IsValid(root) then return end
		BuildNav()
		ShowPage(activeId or PinnedPanels.SettingsPages[1].id)
	end)

	root.OnRemove = ClosePopups

	return root
end
