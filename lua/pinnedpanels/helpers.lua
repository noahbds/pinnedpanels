local C = PinnedPanels.C

-- ── Throttle Scroll ──────────────────────────────────────────────────────────
function PinnedPanels.ThrottleScroll(scroll)
	local orig = scroll.InvalidateLayout
	scroll.NextLayout = 0
	scroll.InvalidateLayout = function(self, layoutNow)
		if CurTime() < self.NextLayout then return end
		self.NextLayout = CurTime() + 0.1
		orig(self, layoutNow)
	end
end

-- ── Pin Row Paint ────────────────────────────────────────────────────────────
function PinnedPanels.MakePinRowPaint(id, radius)
	radius = radius or 3
	return function(self, w, h)
		local pin    = PinnedPanels.Pins[id]
		local pinned = pin and IsValid(pin.frame)
		local bg     = pinned and C.pinBgOn or C.pinBgOff
		if self:IsHovered() then
			bg = pinned and C.pinBgOnHov or C.pinBgOffHov
		end
		draw.RoundedBox(radius, 0, 0, w, h, bg)
		if pinned then
			surface.SetDrawColor(C.accentGreen)
			surface.DrawRect(0, 0, 3, h)
		end
	end
end

-- ── Get All Tools ────────────────────────────────────────────────────────────
function PinnedPanels.GetAllTools()
	local tabs = spawnmenu.GetTools()
	if not tabs then return {} end

	local list, seen = {}, {}
	for tabKey, tab in SortedPairs(tabs) do
		local tabName = isstring(tab.Label) and tab.Label or tabKey
		if istable(tab.Items) then
			for _, cat in pairs(tab.Items) do
				if istable(cat) then
					local catRaw = isstring(cat.Text) and cat.Text or "Other"
					local catName = language.GetPhrase(catRaw)
					if not catName or catName == catRaw then
						catName = catRaw:gsub("^#", "")
					end

					for _, item in ipairs(cat) do
						if istable(item) and item.ItemName and not seen[item.ItemName] then
							seen[item.ItemName] = true

							local nice = item.Text and language.GetPhrase(item.Text) or ""
							if nice == "" or nice == item.Text then
								nice = item.Text or item.ItemName
							end
							list[#list + 1] = {
								itemName = item.ItemName,
								niceName = nice,
								cpFunc   = item.CPanelFunction,
								category = catName,
								tabName  = tabName,
							}
						end
					end
				end
			end
		end
	end

	table.sort(list, function(a, b) return a.niceName:lower() < b.niceName:lower() end)
	return list
end

-- ── Get All Creation Tabs ────────────────────────────────────────────────────
function PinnedPanels.GetAllCreationTabs()
	local raw = spawnmenu.GetCreationTabs and spawnmenu.GetCreationTabs()
	if not istable(raw) then return {} end

	local list = {}
	for name, tab in pairs(raw) do
		if isstring(name) and isfunction(tab.Function) then
			local label = language.GetPhrase(name)
			if not label or label == name then label = name:gsub("^#", "") end
			list[#list + 1] = {
				id      = "PPC_" .. name,
				name    = name,
				label   = label,
				icon    = tab.Icon,
				order   = tab.Order or 1000,
				tooltip = tab.Tooltip,
				func    = tab.Function,
			}
		end
	end

	table.sort(list, function(a, b) return a.order < b.order end)
	return list
end
