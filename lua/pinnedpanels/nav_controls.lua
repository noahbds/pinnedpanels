-- How keyboard navigation treats each kind of control (§19.4): which panels are leaves, containers or
-- skipped while scanning, and per adapter how Enter activates it, how arrows adjust it and which hint it
-- shows. Tool panels are other addons' controls; adapters only call their public methods.

local PP = PinnedPanels
PP.Nav = PP.Nav or {}
local Nav = PP.Nav

-- ── Classification (v1's scan rules) ────────────────────────

local SKIP = {
	DLabel = true, Label = true, DImage = true, Image = true, DDivider = true, Divider = true,
	DExpandButton = true, DVScrollBar = true, DHScrollBar = true,
}

local COLOR_CONTAINERS = { DColorMixer = true, CtrlColor = true, DColorCombo = true, DColorPalette = true }

local CONTAINERS = {
	ControlPanel = true, DForm = true, DCollapsibleCategory = true, DScrollPanel = true, DPropertySheet = true,
	DFrame = true, DCategoryList = true, DTree = true, DTree_Node = true, DListLayout = true, DIconLayout = true,
	DTileLayout = true, ContentContainer = true, SpawnmenuContentPanel = true, DMenu = true, DMenuBar = true,
	PinnedPanelsScroll = true, PinnedPanelsClip = true, PinnedPanelsTabHost = true,
}
for k in pairs(COLOR_CONTAINERS) do CONTAINERS[k] = true end

local LEAVES = {
	DButton = true, DImageButton = true, DComboBox = true, DTextEntry = true, DNumSlider = true,
	DTree_Node_Button = true, DRGBPicker = true, DAlphaBar = true, DNumberWang = true, PinnedPanelsSearch = true,
}

-- HTML panels are recognised by DHTML's own Lua methods; RunJavascript is on every panel (L20).
function Nav.IsHTML(p)
	if isfunction(p.QueueJavascript) and isfunction(p.OnDocumentReady) then return true end
	local class = p.ClassName or p:GetClassName()
	return class:find("HTML") ~= nil or class == "Awesomium"
end

local function customInteraction(p)
	if not p:IsMouseInputEnabled() then return false end
	if isfunction(p.DoClick) or isfunction(p.Toggle) then return true end
	if isfunction(p.SetValue) and isfunction(p.GetValue) then return true end
	-- Looked up here, not at load: Derma's controls aren't registered yet when autorun files run.
	local base = vgui.GetControlTable("DPanel")
	return isfunction(p.OnMousePressed) and p.OnMousePressed ~= (base and base.OnMousePressed)
end

-- "skip", "leaf", "container" (scan its children) or "custom" (a leaf if none of its children is one).
function Nav.Classify(p)
	local class = p.ClassName or p:GetClassName()
	if SKIP[class] or class:find("ScrollBar") or class:find("Grip") then return "skip" end
	if Nav.IsHTML(p) or LEAVES[class] or class:find("Slider") or class:find("CheckBox") then return "leaf" end
	if class:find("Color") and not COLOR_CONTAINERS[class] then return "leaf" end
	if not CONTAINERS[class] and customInteraction(p) then return "custom" end
	return "container"
end

-- ── Colour controls ─────────────────────────────────────────

local HUE_STEP, SV_STEP, ALPHA_STEP, ALPHABAR_STEP = 8, 0.04, 10, 0.04

-- The panel actually holding the colour: a colour cube, a mixer inside a colour control, or the control.
local function colorTarget(el)
	local class = el.ClassName or el:GetClassName()
	if class:find("ColorCube") then return el, class end
	if not class:find("Color") then return nil end
	local found, foundClass
	local function dig(p, depth)
		if found or depth > 5 then return end
		for _, c in ipairs(p:GetChildren()) do
			local cc = c.ClassName or c:GetClassName()
			if cc == "DColorMixer" or cc:find("ColorCube") then
				found, foundClass = c, cc
				return
			end
			dig(c, depth + 1)
		end
	end
	dig(el, 0)
	if found then return found, foundClass end
	if isfunction(el.GetColor) and isfunction(el.SetColor) and not isfunction(el.DoClick) then return el, class end
end

local function ownerMixer(el)
	local p = el:GetParent()
	for _ = 1, 6 do
		if not IsValid(p) then return nil end
		if IsValid(p.HSV) and isfunction(p.GetColor) and isfunction(p.SetColor) then return p end
		p = p:GetParent()
	end
end

local function withHSV(color, fn)
	local h, s, v = ColorToHSV(color)
	local nh, ns, nv = fn(h, s, v)
	local c = HSVToColor(nh % 360, math.Clamp(ns, 0, 1), math.Clamp(nv, 0, 1))
	c.a = color.a or 255
	return c
end

-- ── Adapters ────────────────────────────────────────────────
-- adapter = { id, matches(p, class), adjust = "1d" | "2d" | "vert" | "scroll" | nil, hint = "loc.key"?,
--             onAdjust(p, key, shift)?, onArrow(p, key) → consumed?, activate(p)? }
-- The first adapter that matches wins; activate defaults to clicking.

Nav.adapters = {}

function Nav.Control(def)
	Nav.adapters[#Nav.adapters + 1] = def
end

local function up(key) return key == KEY_UP or key == KEY_RIGHT end

-- HTML has no controls to walk; arrows scroll the page with JS (L20). The scroller varies by page.
local SCROLL_JS = "(function(){var v=document.querySelector('.viewport')||document.scrollingElement||" ..
	"document.documentElement||document.body;if(v){v.scrollTop+=(%d);v.scrollLeft+=(%d);}})();"

function Nav.ScrollHTML(p, key)
	local w, h = p:GetSize()
	local dy = key == KEY_DOWN and math.max(40, math.floor(h * 0.12)) or key == KEY_UP and -math.max(40, math.floor(h * 0.12)) or 0
	local dx = key == KEY_RIGHT and math.max(40, math.floor(w * 0.12)) or key == KEY_LEFT and -math.max(40, math.floor(w * 0.12)) or 0
	p:RunJavascript(SCROLL_JS:format(dy, dx))
end

Nav.Control({
	id = "html", adjust = "scroll", hint = "nav.hint_scroll",
	matches = function(p) return Nav.IsHTML(p) end,
	onAdjust = function(p, key) Nav.ScrollHTML(p, key) end,
})

Nav.Control({
	id = "rgbpicker", adjust = "vert", hint = "nav.hint_hue",
	matches = function(_, class) return class == "DRGBPicker" end,
	onAdjust = function(p, key)
		local mixer = ownerMixer(p)
		if not mixer then return end
		mixer:SetColor(withHSV(mixer:GetColor(), function(h, s, v)
			return h + (up(key) and HUE_STEP or -HUE_STEP), s < 0.05 and 1 or s, v < 0.05 and 1 or v
		end))
	end,
})

Nav.Control({
	id = "alphabar", adjust = "vert", hint = "nav.hint_alpha",
	matches = function(_, class) return class == "DAlphaBar" end,
	onAdjust = function(p, key)
		local v = math.Clamp((tonumber(p:GetValue()) or 1) + (up(key) and ALPHABAR_STEP or -ALPHABAR_STEP), 0, 1)
		p:SetValue(v)
		if isfunction(p.OnChange) then p:OnChange(v) end
	end,
})

-- Cube: left/right saturation, up/down value. Mixer: left/right hue, up/down value; Shift: saturation/alpha.
Nav.Control({
	id = "color", adjust = "2d",
	matches = function(p) return colorTarget(p) ~= nil end,
	hint = function(p)
		local _, class = colorTarget(p)
		return class:find("ColorCube") and "nav.hint_satval" or "nav.hint_huevalue"
	end,
	onAdjust = function(p, key, shift)
		local target, class = colorTarget(p)
		if class:find("ColorCube") then
			local color = isfunction(target.GetRGB) and target:GetRGB() or target:GetColor()
			local c = withHSV(color, function(h, s, v)
				if key == KEY_LEFT then s = s + SV_STEP elseif key == KEY_RIGHT then s = s - SV_STEP
				elseif key == KEY_UP then v = v + SV_STEP else v = v - SV_STEP end
				return h, s, v
			end)
			target:SetColor(c)
			if isfunction(target.OnUserChanged) then target:OnUserChanged(c) end
			return
		end
		local color = target:GetColor()
		local alpha = color.a or 255
		local c = withHSV(color, function(h, s, v)
			if shift then
				if key == KEY_LEFT then s = s + SV_STEP elseif key == KEY_RIGHT then s = s - SV_STEP
				elseif key == KEY_UP then alpha = alpha + ALPHA_STEP else alpha = alpha - ALPHA_STEP end
			else
				if key == KEY_LEFT then h = h - HUE_STEP elseif key == KEY_RIGHT then h = h + HUE_STEP
				elseif key == KEY_UP then v = v + SV_STEP else v = v - SV_STEP end
			end
			return h, s, v
		end)
		c.a = math.Clamp(math.Round(alpha), 0, 255)
		target:SetColor(c)
	end,
})

Nav.Control({
	id = "slider", adjust = "1d", hint = "nav.hint_slider",
	matches = function(_, class) return class:find("Slider") ~= nil end,
	onAdjust = function(p, key)
		local min, max = tonumber(p:GetMin()) or 0, tonumber(p:GetMax()) or 100
		local v = math.Clamp((tonumber(p:GetValue()) or min) + (max - min) / 30 * (key == KEY_RIGHT and 1 or -1), min, max)
		p:SetValue(v)
		if isfunction(p.OnValueChanged) then p:OnValueChanged(v) end
	end,
})

Nav.Control({
	id = "combobox", adjust = "1d", hint = "nav.hint_slider",
	matches = function(_, class) return class == "DComboBox" end,
	onAdjust = function(p, key)
		local n = istable(p.Choices) and #p.Choices or 0
		if n == 0 then return end
		local id = ((p:GetSelectedID() or 1) - 1 + (key == KEY_RIGHT and 1 or -1)) % n + 1
		p:ChooseOptionID(id)
	end,
})

Nav.Control({
	id = "checkbox",
	matches = function(_, class) return class:find("CheckBox") ~= nil end,
	activate = function(p)
		if isfunction(p.Toggle) then p:Toggle() else p:SetValue(not p:GetChecked()) end
	end,
})

-- Text fields get focus; the window then takes the keyboard through the focus hooks (G20).
Nav.Control({
	id = "textentry",
	matches = function(_, class) return class == "DTextEntry" or class == "DNumberWang" or class == "TextEntry" or class == "PinnedPanelsSearch" end,
	activate = function(p) p:RequestFocus() end,
})

-- Tree nodes: Enter selects, left/right collapse/expand before moving on (L21).
local function expandable(node)
	if isfunction(node.HasChildren) then return node:HasChildren() end
	local children = isfunction(node.GetChildNodes) and node:GetChildNodes()
	return istable(children) and #children > 0
end

Nav.Control({
	id = "treenode",
	matches = function(_, class) return class == "DTree_Node_Button" end,
	activate = function(p)
		local node = p:GetParent()
		if IsValid(node) and isfunction(node.InternalDoClick) then node:InternalDoClick() elseif isfunction(p.DoClick) then p:DoClick() end
	end,
	onArrow = function(p, key)
		local node = p:GetParent()
		if not (IsValid(node) and isfunction(node.GetExpanded) and expandable(node)) then return false end
		if key == KEY_RIGHT and not node:GetExpanded() then
			node:SetExpanded(true)
			return true
		elseif key == KEY_LEFT and node:GetExpanded() then
			node:SetExpanded(false)
			return true
		end
		return false
	end,
})

-- Anything else: its own click.
Nav.Control({
	id = "clickable",
	matches = function() return true end,
	activate = function(p)
		if isfunction(p.DoClick) then
			p:DoClick()
		elseif isfunction(p.Toggle) then
			p:Toggle()
		elseif isfunction(p.OnMousePressed) then
			p:OnMousePressed(MOUSE_LEFT)
			if isfunction(p.OnMouseReleased) then p:OnMouseReleased(MOUSE_LEFT) end
		end
	end,
})

function Nav.Adapter(p)
	local class = p.ClassName or p:GetClassName()
	for _, a in ipairs(Nav.adapters) do
		if a.matches(p, class) then return a end
	end
end

function Nav.HintFor(p)
	local a = Nav.Adapter(p)
	local hint = a.hint
	if isfunction(hint) then hint = hint(p) end
	return hint
end
