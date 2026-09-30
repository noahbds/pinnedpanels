-- A headless stand-in for Derma, enough to create our controls and drive their gestures from tests.
-- Panels keep position, size, visibility, input flags and children; methods it doesn't model are no-ops,
-- so these tests catch our own mistakes (nil values, wrong names), not Derma behaviour. That's for in-game tests.

FILL, LEFT, RIGHT, TOP, BOTTOM, NODOCK = 1, 2, 3, 4, 5, 0
MOUSE_LEFT, MOUSE_RIGHT = 107, 108
TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, TEXT_ALIGN_RIGHT = 0, 1, 2

draw = setmetatable({}, { __index = function() return function() end end })
surface = setmetatable({ GetTextSize = function(s) return #tostring(s) * 6, 14 end }, { __index = function() return function() end end })

local registry, created
local methods = {}

local function lookup(class, key)
	local seen = 0
	while class and seen < 20 do
		local t = registry[class]
		if not t then break end
		local v = rawget(t, key)
		if v ~= nil then return v end
		class = rawget(t, "Base")
		seen = seen + 1
	end
	return methods[key]
end

local function noop() end

local META = {
	__index = function(p, key)
		local v = lookup(rawget(p, "ClassName"), key)
		if v == nil and type(key) == "string" and key:match("^%u") then return noop end
		return v
	end,
}

function Stub.Derma()
	registry = {}
	created = {}
	for _, name in ipairs({ "Panel", "EditablePanel", "DPanel", "DLabel", "DButton", "DTextEntry", "DImage", "DScrollPanel", "DPropertySheet" }) do
		registry[name] = { Base = name ~= "Panel" and "Panel" or nil }
	end
	registry.ControlPanel = {
		Base = "DPanel",
		FillViaTable = function(self, t)
			if t.ControlPanelBuildFunction then t.ControlPanelBuildFunction(self) end
		end,
	}
	registry.DPropertySheet.AddSheet = function(self, label, panel, icon)
		local tab = vgui.Create("DPanel")
		tab.sheet = self
		self.items = self.items or {}
		self.items[#self.items + 1] = { Tab = tab, Panel = panel, label = label }
		panel:SetParent(self)
		return self.items[#self.items]
	end
	registry.DPropertySheet.GetItems = function(self) return self.items or {} end
	registry.DPropertySheet.GetActiveTab = function(self) return self.items and self.items[1].Tab end
	registry.DPanel.GetPropertySheet = function(self) return self.sheet end
	registry.DScrollPanel.GetCanvas = function(self) return self end
	registry.DScrollPanel.PerformLayout = function(self) self.layouts = (self.layouts or 0) + 1 end
end

function Stub.Created() return created end

vgui.Register = function(name, t, base)
	t.Base = base or "Panel"
	registry[name] = t
	return t
end

vgui.GetControlTable = function(name) return registry[name] end
baseclass = { Get = function(name) return registry[name] end }

vgui.Create = function(class, parent)
	assert(registry[class], "unknown panel class " .. tostring(class))
	local p = setmetatable({ ClassName = class, x = 0, y = 0, w = 64, h = 24, visible = true, alpha = 255,
		mouse = true, keyboard = true, children = {} }, META)
	created[#created + 1] = p
	if parent then p:SetParent(parent) end
	local init = lookup(class, "Init")
	if init then init(p) end
	return p
end

function methods:IsValid() return not self.removed end
function methods:Remove()
	if self.removed then return end
	self.removed = true
	for _, c in ipairs(self:GetChildren()) do c:Remove() end
	if self.parent then self:SetParent(nil) end
	if self.OnRemove then self:OnRemove() end
end
function methods:SetParent(parent)
	if self.parent then
		for i, c in ipairs(self.parent.children) do
			if c == self then table.remove(self.parent.children, i) break end
		end
	end
	self.parent = parent
	if parent then parent.children[#parent.children + 1] = self end
end
function methods:GetParent() return self.parent end
function methods:GetChildren()
	local out = {}
	for i, c in ipairs(self.children) do out[i] = c end
	return out
end
function methods:Add(class)
	if type(class) == "string" then return vgui.Create(class, self) end
	class:SetParent(self)
	return class
end
function methods:Clear() for _, c in ipairs(self:GetChildren()) do c:Remove() end end
function methods:SetPos(x, y) self.x, self.y = x, y end
function methods:GetPos() return self.x, self.y end
function methods:SetSize(w, h) self.w, self.h = w, h end
function methods:GetSize() return self.w, self.h end
function methods:SetWide(w) self.w = w end
function methods:SetTall(h) self.h = h end
function methods:GetWide() return self.w end
function methods:GetTall() return self.h end
function methods:SetVisible(v) self.visible = v end
function methods:IsVisible() return self.visible end
function methods:SetAlpha(a) self.alpha = a end
function methods:GetAlpha() return self.alpha end
function methods:SetMouseInputEnabled(on) self.mouse = on end
function methods:IsMouseInputEnabled() return self.mouse end
function methods:SetKeyboardInputEnabled(on) self.keyboard = on end
function methods:IsKeyboardInputEnabled() return self.keyboard end
function methods:MakePopup() self.popup = true end
function methods:MouseCapture(on) self.captured = on end
function methods:SetCursor(c) self.cursor = c end
function methods:IsHovered() return false end
function methods:LocalToScreen(x, y)
	local p, sx, sy = self, x, y
	while p do sx, sy, p = sx + p.x, sy + p.y, p.parent end
	return sx, sy
end
function methods:ScreenToLocal(x, y)
	local sx, sy = self:LocalToScreen(0, 0)
	return x - sx, y - sy
end
function methods:CursorPos() return self:ScreenToLocal(input.GetCursorPos()) end
function methods:SetText(t) self.text = t end
function methods:GetText() return self.text or "" end
function methods:GetValue() return self.text or "" end
function methods:SetTooltip(t) self.tooltip = t end
function methods:SetPlaceholderText(t) self.placeholder = t end
function methods:GetPlaceholderText() return self.placeholder end
function methods:GetFont() return "DermaDefault" end

local cursorX, cursorY = 0, 0
function input.GetCursorPos() return cursorX, cursorY end
function Stub.Cursor(x, y) cursorX, cursorY = x, y end

-- Clicks and drags in screen coordinates, delivered to panel as Derma would with mouse capture.
function Stub.Press(panel, x, y, code)
	Stub.Cursor(x, y)
	panel:OnMousePressed(code or MOUSE_LEFT)
end
function Stub.Move(panel, x, y)
	Stub.Cursor(x, y)
	panel:OnCursorMoved(panel:ScreenToLocal(x, y))
end
function Stub.Release(panel, x, y, code)
	Stub.Cursor(x, y)
	panel:OnMouseReleased(code or MOUSE_LEFT)
end

-- Runs Think on every visible panel whose ancestors are visible too (G4), like one rendered frame.
function Stub.ThinkPanels()
	for _, p in ipairs(created) do
		local shown, q = not p.removed, p
		while shown and q do
			shown, q = q.visible, q.parent
		end
		if shown and p.Think then p:Think() end
	end
end
