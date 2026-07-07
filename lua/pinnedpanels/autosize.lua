-- ── Auto-Size Panel ──────────────────────────────────────────────────────────
local function FindCanvasPanel(root)
	if not IsValid(root) then return nil end
	local queue, head = { root }, 1
	while queue[head] do
		local p = queue[head]
		head = head + 1
		if IsValid(p) then
			if isfunction(p.GetCanvas) then
				local canvas = p:GetCanvas()
				if IsValid(canvas) then return p, canvas end
			end
			for _, child in ipairs(p:GetChildren()) do
				queue[#queue + 1] = child
			end
		end
	end
end

function PinnedPanels.AutoSizePanel(id)
	local pin = PinnedPanels.Pins[id]
	if not pin or not IsValid(pin.frame) then return end
	local frame = pin.frame

	local content = pin.content
	if pin.kind == "group" then
		local memberId = PinnedPanels.GetActiveGroupMemberId(id)
		local mp = memberId and PinnedPanels.Pins[memberId]
		content = mp and mp.content or nil
	end

	local scroll, canvas = FindCanvasPanel(content)
	if not scroll then return end

	scroll:InvalidateLayout(true)
	canvas:InvalidateLayout(true)

	local contentH = 0
	for _, c in ipairs(canvas:GetChildren()) do
		if IsValid(c) and c:IsVisible() then
			c:InvalidateLayout(true)
			local _, cy = c:GetPos()
			local _, ch = c:GetSize()
			contentH = math.max(contentH, cy + ch)
		end
	end
	if contentH <= 0 then return end

	local chrome = frame:GetTall() - scroll:GetTall()
	local _, y = frame:GetPos()
	local target = math.Clamp(contentH + chrome + 4, 100, math.max(100, ScrH() - y))

	frame:SetTall(target)
	frame:InvalidateLayout(true)

	if pin.kind == "group" then
		local mid = PinnedPanels.GetActiveGroupMemberId(id)
		if mid then
			pin.tabSizes = pin.tabSizes or {}
			pin.tabSizes[mid] = { w = frame:GetWide(), h = target }
		end
	end

	PinnedPanels.Save()
end
