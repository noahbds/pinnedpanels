-- ── Auto-Size Panel ──────────────────────────────────────────────────────────
local MIN_W, MIN_H   = 150, 100
local MAX_W_FRAC     = 0.6   -- never wider than this fraction of the screen
local MAX_H_FRAC     = 0.92  -- never taller than this fraction of the screen
local WIDTH_DEADBAND = 12    -- ignore width changes smaller than this
local ANIM_TIME      = 0.12

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
PinnedPanels.FindCanvasPanel = FindCanvasPanel

-- ── Width Measurement ────────────────────────────────────────────────────────
-- Docked children stretch to whatever width the frame has, so their current
-- width says nothing about what they *need*. Instead we look for intrinsic
-- widths: text extents, fixed-size (NODOCK) children, and sensible per-class
-- minimums, recursing into containers.

local function TextWidth(p)
	if not isfunction(p.GetText) then return 0 end
	-- wrapped labels reflow to any width; they must not force one
	if isfunction(p.GetWrap) and p:GetWrap() then return 0 end
	local txt = p:GetText()
	if not isstring(txt) or txt == "" then return 0 end

	local font = "DermaDefault"
	if isfunction(p.GetFont) then
		local f = p:GetFont()
		if isstring(f) and f ~= "" then font = f end
	end
	if not pcall(surface.SetFont, font) then
		surface.SetFont("DermaDefault")
	end
	local tw = select(1, surface.GetTextSize(txt)) or 0
	if tw <= 0 then return 0 end

	tw = tw + 16 -- breathing room
	if p.m_Image and IsValid(p.m_Image) then tw = tw + 24 end -- icon'd buttons/options
	return tw
end

-- Minimum useful widths for controls whose text alone under-measures them.
local CLASS_MIN_W = {
	DNumSlider  = 240,
	DColorMixer = 240,
	DComboBox   = 180,
	DTextEntry  = 160,
}

local function NaturalWidth(p, depth)
	if not IsValid(p) or depth > 12 or not p:IsVisible() or p._pp_skipNav then return 0 end
	local cls = p.ClassName or p:GetClassName()
	if cls:find("ScrollBar") or cls:find("Grip") then return 0 end

	local w = TextWidth(p)
	if CLASS_MIN_W[cls] then w = math.max(w, CLASS_MIN_W[cls]) end
	if cls:find("Slider") and not CLASS_MIN_W[cls] then w = math.max(w, 240) end

	for _, child in ipairs(p:GetChildren()) do
		if IsValid(child) and child:IsVisible() then
			local ccls = child.ClassName or child:GetClassName()
			if not (ccls:find("ScrollBar") or ccls:find("Grip")) then
				local cw
				local dock = isfunction(child.GetDock) and child:GetDock() or NODOCK
				if dock == NODOCK then
					-- fixed placement: its actual footprint is meaningful
					local cx = select(1, child:GetPos()) or 0
					cw = cx + math.max(child:GetWide(), NaturalWidth(child, depth + 1))
				else
					local ml, _, mr = 0, 0, 0
					if isfunction(child.GetDockMargin) then ml, _, mr = child:GetDockMargin() end
					cw = NaturalWidth(child, depth + 1) + (ml or 0) + (mr or 0)
				end
				if cw > w then w = cw end
			end
		end
	end

	if w > 0 and isfunction(p.GetDockPadding) then
		local pl, _, pr = p:GetDockPadding()
		w = w + (pl or 0) + (pr or 0)
	end
	return w
end

-- ── Height Measurement ───────────────────────────────────────────────────────
local function BottomExtent(parent)
	local h = 0
	for _, c in ipairs(parent:GetChildren()) do
		if IsValid(c) and c:IsVisible() then
			c:InvalidateLayout(true)
			local _, cy = c:GetPos()
			local ch = select(2, c:GetSize()) or 0
			h = math.max(h, cy + ch)
		end
	end
	return h
end

-- ── Core Pass ────────────────────────────────────────────────────────────────
local function ResolveContent(id, pin)
	local content, srcPin = pin.content, pin
	if pin.kind == "group" then
		local memberId = PinnedPanels.GetActiveGroupMemberId(id)
		srcPin  = memberId and PinnedPanels.Pins[memberId] or pin
		content = srcPin and srcPin.content or nil
	elseif pin.kind == "frame" then
		content = IsValid(pin.livePanel) and pin.livePanel or pin.content
	end
	return content, srcPin
end

local function AutoSizePass(id, animate)
	local pin = PinnedPanels.Pins[id]
	if not pin or not IsValid(pin.frame) then return end
	local frame = pin.frame

	-- autosizing a maximized panel implies leaving maximized state
	if pin.maximized then
		pin.maximized = false
		pin.restoreBounds = nil
	end

	local content, srcPin = ResolveContent(id, pin)
	if not IsValid(content) then return end

	local scroll, canvas = FindCanvasPanel(content)
	if IsValid(scroll) then
		scroll:InvalidateLayout(true)
		canvas:InvalidateLayout(true)
	else
		content:InvalidateLayout(true)
	end

	local sw, sh = ScrW(), ScrH()
	local curW, curH = frame:GetSize()

	-- ── width: tool-style content only; browsers/live grids reflow to any width
	local newW = curW
	if srcPin and srcPin.kind == "tool" and not srcPin.fill then
		local nat = NaturalWidth(canvas or content, 0)
		if nat > 60 then
			newW = math.Clamp(nat + 28, MIN_W, math.floor(sw * MAX_W_FRAC))
			if math.abs(newW - curW) <= WIDTH_DEADBAND then newW = curW end
		end
	end

	-- ── height
	local contentH, chrome
	if IsValid(canvas) then
		contentH = BottomExtent(canvas)
		chrome   = frame:GetTall() - scroll:GetTall()
	else
		contentH = BottomExtent(content)
		chrome   = frame:GetTall() - content:GetTall()
	end
	if not contentH or contentH <= 0 then return end

	local newH = math.Clamp(contentH + chrome + 4, MIN_H, math.floor(sh * MAX_H_FRAC))

	-- ── position: grow past the bottom/right edge by shifting the panel
	local x, y = frame:GetPos()
	local newX = math.Clamp(x, 0, math.max(0, sw - newW))
	local newY = math.Clamp(y, 0, math.max(0, sh - newH))
	if pin.locked then newX, newY = x, y end

	local sizeChanged = (newW ~= curW) or (math.abs(newH - curH) > 2)
	local posChanged  = (newX ~= x) or (newY ~= y)

	if sizeChanged then
		if animate then
			frame:SizeTo(newW, newH, ANIM_TIME, 0, -1)
		else
			frame:SetSize(newW, newH)
			frame:InvalidateLayout(true)
		end
	end
	if posChanged then
		if animate then
			frame:MoveTo(newX, newY, ANIM_TIME, 0, -1)
		else
			frame:SetPos(newX, newY)
		end
	end

	if pin.kind == "group" then
		local mid = PinnedPanels.GetActiveGroupMemberId(id)
		if mid then
			pin.tabSizes = pin.tabSizes or {}
			pin.tabSizes[mid] = { w = newW, h = newH }
		end
	end

	if sizeChanged or posChanged then PinnedPanels.Save() end
	return sizeChanged
end

-- ── Public API ───────────────────────────────────────────────────────────────
-- Derma layouts (and word-wrapped labels after a width change) settle over a
-- few frames, so one measurement is never trustworthy: apply an animated first
-- pass, then re-measure and correct once things have settled.
function PinnedPanels.AutoSizePanel(id)
	AutoSizePass(id, true)

	timer.Create("PinnedPanels_AutoSize_" .. tostring(id), ANIM_TIME + 0.15, 1, function()
		local pin = PinnedPanels.Pins[id]
		if pin and IsValid(pin.frame) then
			AutoSizePass(id, false)
		end
	end)
end

concommand.Add("pp_autosize_all", function()
	for id, pin in pairs(PinnedPanels.Pins) do
		if IsValid(pin.frame) and pin.frame:IsVisible()
			and (pin.kind == "group" or not PinnedPanels.GetGroupForPanel(id)) then
			PinnedPanels.AutoSizePanel(id)
		end
	end
end, nil, "Auto-size every visible pinned panel")
