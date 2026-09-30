-- Quick controls (FF2): single sliders, checkboxes and dropdowns taken out of control panels into a compact
-- window. Each is rebuilt from what was read off the original (its convar, label, range, choices) with our
-- own convar-bound controls, so it keeps working when its tool rebuilds its panel (G15).

local PP = PinnedPanels
PP.Quick = PP.Quick or {}
local Quick = PP.Quick
local Layout, Desktop, Util = PP.Layout, PP.Desktop, PP.Util

local MAX_UP = 4
local MAX_CHOICES = 32
-- Tabs holding control panels, where a control can be pinned from.
local PANELS = { tool = true, active = true, postprocess = true }

local function convarOf(p)
	return IsValid(p) and isstring(p.m_strConVar) and p.m_strConVar ~= "" and p.m_strConVar or nil
end

local function textOf(p)
	if not IsValid(p) or not isfunction(p.GetText) then return nil end
	local text = p:GetText()
	return isstring(text) and text ~= "" and text or nil
end

-- The label a form puts beside a control (DForm:AddItem(left, right)).
local function siblingLabel(p)
	local parent = p:GetParent()
	if not IsValid(parent) then return nil end
	for _, c in ipairs(parent:GetChildren()) do
		if c ~= p and c.ClassName == "DLabel" then return textOf(c) end
	end
end

-- What a right-clicked panel belongs to: { kind, convar?, label?, min?, max?, decimals?, choices? }, or nil
-- when it isn't part of a slider, checkbox or dropdown. Stock controls keep their convar in m_strConVar:
-- on the scratch and text area for sliders, on the inner button for labelled checkboxes (S dnumslider.lua,
-- dcheckbox.lua).
function Quick.Describe(p)
	for _ = 1, MAX_UP do
		if not IsValid(p) then return nil end
		local class, parent = p.ClassName, p:GetParent()
		if class == "DNumSlider" then
			return { kind = "slider", convar = convarOf(p.Scratch) or convarOf(p.TextArea), label = textOf(p.Label),
				min = p:GetMin(), max = p:GetMax(), decimals = p:GetDecimals() }
		elseif class == "DCheckBoxLabel" then
			return { kind = "check", convar = convarOf(p.Button) or convarOf(p), label = textOf(p.Label) }
		elseif class == "DCheckBox" and not (IsValid(parent) and parent.ClassName == "DCheckBoxLabel") then
			return { kind = "check", convar = convarOf(p), label = siblingLabel(p) }
		elseif class == "DComboBox" then
			local choices = {}
			for i, text in ipairs(p.Choices or {}) do
				if i > MAX_CHOICES then break end
				local data = p.Data and p.Data[i]
				choices[i] = { text = tostring(text), data = data ~= nil and tostring(data) or nil }
			end
			return { kind = "combo", convar = convarOf(p), label = siblingLabel(p), choices = choices }
		end
		p = parent
	end
end

local function quickTab(rec)
	for i, t in ipairs(rec.tabs) do
		if t.controls then return i end
	end
end

-- Adds a control to the focused window's quick controls, else the first Quick Controls window, else a new
-- one, and shows that window.
function Quick.Pin(control)
	control.label = control.label or control.convar
	local id, index
	local focused = Desktop.focused and Layout.Get(Desktop.focused)
	if focused and quickTab(focused) then id, index = focused.id, quickTab(focused) end
	if not id then
		for _, rec in ipairs(Layout.Windows()) do
			index = quickTab(rec)
			if index then
				id = rec.id
				break
			end
		end
	end
	id = Layout.AddControl(id, index, control)
	if id then Desktop.RestoreAndFront(id) end
end

local function name(label)
	if label:sub(1, 1) == "#" then return language.GetPhrase(label:sub(2)) end
	return label
end

-- The list's identity, so a tab rebuilds only when its controls changed (adding, removing, undo).
local function key(tab)
	local parts = {}
	for i, c in ipairs(tab.controls) do parts[i] = c.convar end
	return table.concat(parts, "\n")
end

-- Our own form: stock convar-bound controls, the same ones tool panels use. A convar that doesn't exist
-- here (the tool's addon isn't loaded) shows as a note instead.
function Quick.Build(src, parent)
	local win, i = Layout.Find(src)
	if not win then return nil end
	local tab = win.tabs[i]
	local scroll, cp = PP.Sources.ControlPanel(parent)
	scroll.ppQuickKey = key(tab)
	for ci, c in ipairs(tab.controls) do
		local row
		if not GetConVar(c.convar) then
			row = cp:Help(PP.L("quick.missing", name(c.label)))
		elseif c.kind == "slider" then
			row = cp:NumSlider(c.label, c.convar, c.min, c.max, c.decimals)
		elseif c.kind == "check" then
			row = cp:CheckBox(c.label, c.convar)
		else
			row = cp:ComboBox(c.label, c.convar)
			for _, choice in ipairs(c.choices or {}) do row:AddChoice(choice.text, choice.data) end
		end
		row.ppQuickIndex = ci
	end
	return scroll
end

hook.Add("PinnedPanelsChanged", "PinnedPanels.Quick", function(kind)
	if kind ~= "windows" and kind ~= "tabs" then return end
	for _, win in pairs(Desktop.panels) do
		for src, host in pairs(IsValid(win) and win.hosts or {}) do
			local rec, i = Layout.Find(src)
			local tab = rec and rec.tabs[i]
			if tab and tab.controls and IsValid(host.content) and host.content.ppQuickKey ~= key(tab) then host:Rebuild() end
		end
	end
end)

-- ── Right-click menus ───────────────────────────────────────

local function hostOf(p)
	while IsValid(p) do
		if p.ClassName == "PinnedPanelsTabHost" then return p end
		p = p:GetParent()
	end
end

local function indexOf(p)
	for _ = 1, MAX_UP + 2 do
		if not IsValid(p) or p.ppQuickIndex then break end
		p = p:GetParent()
	end
	return IsValid(p) and p.ppQuickIndex or nil
end

-- Opened next frame: Derma closes menus on the same click (G17), which would take ours with them.
local function menu(text, icon, enabled, fn)
	Util.NextFrame(nil, function()
		local m = DermaMenu()
		local option = m:AddOption(text, fn)
		option:SetIcon(icon)
		if not enabled then option:SetEnabled(false) end
		m:Open()
	end)
end

-- Right-clicking a control in a control panel offers to pin it; in a quick tab, to remove it. Controls
-- without a convar can't be rebuilt, so their entry is greyed out.
hook.Add("VGUIMousePressed", "PinnedPanels.Quick", function(panel, code)
	if code ~= MOUSE_RIGHT then return end
	local host = hostOf(panel)
	local kind = host and host.src:match("^(%a+):")
	if kind == "quick" then
		local ci = indexOf(panel)
		local rec, i = Layout.Find(host.src)
		if ci and rec then
			menu(PP.L("quick.remove"), "icon16/lightning_delete.png", true, function() Layout.RemoveControl(rec.id, i, ci) end)
		end
	elseif PANELS[kind] then
		local control = Quick.Describe(panel)
		if control then
			local usable = control.convar ~= nil
			menu(PP.L(usable and "quick.pin" or "quick.no_setting"), "icon16/lightning_add.png", usable, function() Quick.Pin(control) end)
		end
	end
end)
