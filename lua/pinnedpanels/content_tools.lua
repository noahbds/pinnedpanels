-- ── Content Tools: Filter Bar & Collapse Memory ──────────────────────────────
local C = PinnedPanels.C

-- ── Shared Scanning ──────────────────────────────────────────────────────────
local function IsCategory(p)
	return isfunction(p.GetExpanded) and isfunction(p.SetExpanded) and IsValid(p.Header)
end

local function ScanCategories(root, out, depth)
	out, depth = out or {}, depth or 0
	if not IsValid(root) or depth > 12 then return out end
	for _, child in ipairs(root:GetChildren()) do
		if IsValid(child) then
			if IsCategory(child) then out[#out + 1] = child end
			ScanCategories(child, out, depth + 1)
		end
	end
	return out
end

local function CategoryLabel(cat)
	local h = cat.Header
	if IsValid(h) and isfunction(h.GetText) then
		local t = h:GetText()
		if isstring(t) and t ~= "" then return t end
	end
	return nil
end

local function SubtreeText(p, depth)
	if not IsValid(p) or depth > 8 then return "" end
	local parts = {}
	if isfunction(p.GetText) then
		local t = p:GetText()
		if isstring(t) and t ~= "" then parts[#parts + 1] = t end
	end
	if isstring(p.m_NiceName) and p.m_NiceName ~= "" then
		parts[#parts + 1] = p.m_NiceName
	end
	for _, c in ipairs(p:GetChildren()) do
		local s = SubtreeText(c, depth + 1)
		if s ~= "" then parts[#parts + 1] = s end
	end
	return table.concat(parts, "\n")
end

-- ── Collapse Memory ──────────────────────────────────────────────────────────
function PinnedPanels.ApplyCollapseMemory(id)
	local pin = PinnedPanels.Pins[id]
	if not pin or not IsValid(pin.content) then return end

	local collapsed = pin.collapsed or {}
	local any = false

	for _, cat in ipairs(ScanCategories(pin.content)) do
		local label = CategoryLabel(cat)
		if label then
			if not cat._pp_collapseHooked then
				cat._pp_collapseHooked = true
				local orig = cat.OnToggle
				cat.OnToggle = function(self, expanded)
					if isfunction(orig) then orig(self, expanded) end
					local p = PinnedPanels.Pins[id]
					if not p then return end
					p.collapsed = p.collapsed or {}
					p.collapsed[label] = (not expanded) or nil
					PinnedPanels.Save()
				end
			end
			if collapsed[label] and cat:GetExpanded() then
				cat:SetExpanded(false)
				any = true
			end
		end
	end

	if any then
		pin.content:InvalidateLayout(true)
	end
end

-- ── Content Filter ───────────────────────────────────────────────────────────
local function RestoreFiltered(root, depth)
	if not IsValid(root) or depth > 14 then return end
	for _, c in ipairs(root:GetChildren()) do
		if IsValid(c) then
			if c._pp_filtered then
				c._pp_filtered = nil
				c:SetVisible(true)
				if c._pp_prevSizeY ~= nil then
					c:SetSizeY(c._pp_prevSizeY)
					c._pp_prevSizeY = nil
				end
				if c._pp_prevTall ~= nil then
					c:SetTall(c._pp_prevTall)
					c._pp_prevTall = nil
				end
				c:InvalidateLayout()
			end
			if c._pp_filterExpanded then
				c._pp_filterExpanded = nil
				if isfunction(c.SetExpanded) then c:SetExpanded(false) end
			end
			RestoreFiltered(c, depth + 1)
		end
	end
end

local function HideRow(p)
	p._pp_filtered = true
	p:SetVisible(false)
	if p._pp_prevTall == nil then
		p._pp_prevTall = p:GetTall()
		if isfunction(p.GetSizeY) and isfunction(p.SetSizeY) then
			p._pp_prevSizeY = p:GetSizeY()
			p:SetSizeY(false)
		end
	end
	p:SetTall(0)
end

local function FilterContent(content, query)
	if not IsValid(content) then return end

	query = string.Trim((query or ""):lower())
	RestoreFiltered(content, 0)

	local scroll, canvas = PinnedPanels.FindCanvasPanel(content)
	local root = IsValid(canvas) and canvas or content
	local rowParent = root

	if query ~= "" then
		local function match(txt)
			return txt ~= "" and txt:lower():find(query, 1, true) ~= nil
		end

		local visKids = {}
		for _, k in ipairs(root:GetChildren()) do
			if IsValid(k) and k:IsVisible() then visKids[#visKids + 1] = k end
		end
		if #visKids == 1 and #visKids[1]:GetChildren() > 0 then rowParent = visKids[1] end

		for _, row in ipairs(rowParent:GetChildren()) do
			if IsValid(row) and row:IsVisible() and row ~= rowParent.Header then
				if IsCategory(row) then
					local headerTxt = CategoryLabel(row) or ""
					if not match(headerTxt) then
						local anyInside = false
						for _, inner in ipairs(row:GetChildren()) do
							if IsValid(inner) and inner ~= row.Header and inner:IsVisible() then
								if match(SubtreeText(inner, 0)) then anyInside = true else HideRow(inner) end
							end
						end
						if anyInside then
							if not row:GetExpanded() then
								row:SetExpanded(true)
								row._pp_filterExpanded = true
							end
						else
							HideRow(row)
						end
					end
				else
					if not match(SubtreeText(row, 0)) then HideRow(row) end
				end
			end
		end
	end

	if IsValid(rowParent) and rowParent ~= root then rowParent:InvalidateLayout(true) end
	root:InvalidateChildren(true)
	root:InvalidateLayout(true)
	if IsValid(scroll) then scroll:InvalidateLayout(true) end
	content:InvalidateLayout(true)
end

function PinnedPanels.ApplyContentFilter(id, query)
	local pin = PinnedPanels.Pins[id]
	if not pin then return end

	if pin.kind == "group" then
		local activeId = PinnedPanels.GetActiveGroupMemberId(id)
		for _, mid in ipairs(PinnedPanels.GetGroupPanels(pin.groupName or "")) do
			local mp = PinnedPanels.Pins[mid]
			if mp and IsValid(mp.content) then
				FilterContent(mp.content, mid == activeId and query or "")
			end
		end
		return
	end

	FilterContent(pin.content, query)
end

-- ── Filter Bar UI ────────────────────────────────────────────────────────────
function PinnedPanels.AttachFilterBar(id)
	local pin = PinnedPanels.Pins[id]
	if not pin or not IsValid(pin.frame) then return end
	if IsValid(pin.filterBarPanel) then return end

	local bar = vgui.Create("DPanel", pin.frame)
	bar:Dock(TOP)
	bar:SetTall(24)
	bar:DockMargin(4, 4, 4, 0)
	bar.Paint = function(_, w, h)
		draw.RoundedBox(4, 0, 0, w, h, C.searchBg)
		surface.SetDrawColor(C.searchBorder)
		surface.DrawOutlinedRect(0, 0, w, h, 1)
	end

	local clearBtn = vgui.Create("DButton", bar)
	clearBtn:Dock(RIGHT)
	clearBtn:SetWide(22)
	clearBtn:SetText("")
	clearBtn:SetVisible(false)
	clearBtn.Paint = function(self, w, h)
		draw.SimpleText("×", "DermaDefaultBold", w / 2, h / 2 - 1,
			self:IsHovered() and C.textBright or C.textMuted, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end

	local entry = vgui.Create("DTextEntry", bar)
	entry:Dock(FILL)
	entry:DockMargin(6, 3, 2, 3)
	entry:SetPaintBackground(false)
	entry:SetTextColor(C.textSearch)
	entry:SetCursorColor(C.textSearch)
	entry:SetPlaceholderText(PinnedPanels.L("filter_controls"))
	entry:SetUpdateOnType(true)
	entry.OnValueChange = function(_, val)
		clearBtn:SetVisible(val ~= "")
		PinnedPanels.ApplyContentFilter(id, val)
	end

	clearBtn.DoClick = function()
		entry:SetText("")
		clearBtn:SetVisible(false)
		PinnedPanels.ApplyContentFilter(id, "")
	end

	if pin.kind == "group" and IsValid(pin.sheet) and not pin.sheet._pp_filterHooked then
		local sheet = pin.sheet
		sheet._pp_filterHooked = true
		local origTabChanged = sheet.OnActiveTabChanged
		sheet.OnActiveTabChanged = function(s, old, new)
			if isfunction(origTabChanged) then origTabChanged(s, old, new) end
			local fp = PinnedPanels.Pins[id]
			if fp and IsValid(fp.filterBarPanel) and IsValid(entry) and entry:GetValue() ~= "" then
				PinnedPanels.ApplyContentFilter(id, entry:GetValue())
			end
		end
	end

	pin.filterBarPanel = bar
	pin.filterBar = true
	pin.frame:InvalidateLayout(true)
end

function PinnedPanels.DetachFilterBar(id)
	local pin = PinnedPanels.Pins[id]
	if not pin then return end
	pin.filterBar = nil
	if IsValid(pin.filterBarPanel) then pin.filterBarPanel:Remove() end
	pin.filterBarPanel = nil
	PinnedPanels.ApplyContentFilter(id, "")
	if IsValid(pin.frame) then pin.frame:InvalidateLayout(true) end
end

function PinnedPanels.ToggleFilterBar(id)
	local pin = PinnedPanels.Pins[id]
	if not pin then return end
	if pin.filterBar then
		PinnedPanels.DetachFilterBar(id)
	else
		PinnedPanels.AttachFilterBar(id)
	end
	PinnedPanels.Save()
end
