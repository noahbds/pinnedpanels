PinnedPanels = PinnedPanels or {}
PinnedPanels.Pins = PinnedPanels.Pins or {}

local SAVEF = "pinnedpanels_save.json"
local SETTINGSF = "pinnedpanels_settings.json"

PinnedPanels.Settings = {
	bg = Color(235, 238, 242, 250),
	header = Color(32, 35, 42, 255),
	text = Color(240, 245, 255, 255),
	autoRestore = true
}

function PinnedPanels.SaveSettings()
	file.Write(SETTINGSF, util.TableToJSON(PinnedPanels.Settings, true))
	for id, pin in pairs(PinnedPanels.Pins) do
		if IsValid(pin.frame) then
			pin.frame.Paint = PinnedPanels.GetFramePaint(pin.title)
		end
	end
end

function PinnedPanels.LoadSettings()
	if not file.Exists(SETTINGSF, "DATA") then return end
	local t = util.JSONToTable(file.Read(SETTINGSF, "DATA"))
	if t then
		if t.bg then PinnedPanels.Settings.bg = Color(t.bg.r, t.bg.g, t.bg.b, t.bg.a) end
		if t.header then PinnedPanels.Settings.header = Color(t.header.r, t.header.g, t.header.b, t.header.a) end
		if t.text then PinnedPanels.Settings.text = Color(t.text.r, t.text.g, t.text.b, t.text.a) end
		if t.autoRestore ~= nil then PinnedPanels.Settings.autoRestore = tobool(t.autoRestore) end
	end
end

PinnedPanels.LoadSettings()

function PinnedPanels.Save()
	local data = {}
	for id, pin in pairs(PinnedPanels.Pins) do
		if IsValid(pin.frame) then
			local x, y = pin.frame:GetPos()
			local w, h = pin.frame:GetSize()
			data[id] = { x = x, y = y, w = w, h = h, title = pin.title }
		end
	end
	file.Write(SAVEF, util.TableToJSON(data, true))
end

function PinnedPanels.Load()
	if not file.Exists(SAVEF, "DATA") then return {} end
	return util.JSONToTable(file.Read(SAVEF, "DATA")) or {}
end

function PinnedPanels.GetFramePaint(title)
	return function(self, w, h)
		local th = PinnedPanels.Settings
		draw.RoundedBox(6, 0, 0, w, h, th.bg)
		draw.RoundedBoxEx(6, 0, 0, w, 24, th.header, true, true, false, false)
		draw.SimpleText(title, "DermaDefaultBold", 10, 12, th.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	end
end

function PinnedPanels.Pin(id, title, cpFunc)
	if PinnedPanels.Pins[id] and IsValid(PinnedPanels.Pins[id].frame) then
		PinnedPanels.Pins[id].frame:SetVisible(true)
		return PinnedPanels.Pins[id].frame
	end

	local saved = PinnedPanels.Load()
	local s = saved[id] or {}

	local frame = vgui.Create("DFrame")
	frame:SetTitle("")
	frame:SetSize(s.w or 280, s.h or 400)
	frame:SetPos(s.x or 120, s.y or 120)
	frame:SetDraggable(true)
	frame:SetSizable(true)
	frame:SetDeleteOnClose(false)
	frame:ParentToHUD()

	frame:MakePopup()
	frame:SetKeyboardInputEnabled(false)
	local isInteractActive = (PinnedPanels.InteractMode and PinnedPanels.InteractMode.Active)
	frame:SetMouseInputEnabled(isInteractActive)

	frame:ShowCloseButton(true)
	frame.OnClose         = function() frame:SetVisible(false) end

	frame.Paint           = PinnedPanels.GetFramePaint(title)

	frame.NextFocusCheck  = 0
	frame.Think           = function(self)
		local x, y = self:GetPos()
		local w, h = self:GetSize()
		local nx = math.Clamp(x, 0, ScrW() - w)
		local ny = math.Clamp(y, 0, ScrH() - h)
		if x ~= nx or y ~= ny then self:SetPos(nx, ny) end

		if CurTime() < self.NextFocusCheck then return end
		self.NextFocusCheck = CurTime() + 0.1

		local hovered = vgui.GetHoveredPanel()
		local focus = vgui.GetKeyboardFocus()
		local function isTextPanel(p)
			if not IsValid(p) then return false end
			local c = p:GetClassName()
			return c == "TextEntry" or c == "DTextEntry" or c == "RichText"
		end

		local needsKeyboard = (isTextPanel(hovered) and hovered:HasParent(self)) or
			(isTextPanel(focus) and focus:HasParent(self))

		if self:IsKeyboardInputEnabled() ~= needsKeyboard then
			self:SetKeyboardInputEnabled(needsKeyboard)
		end
	end

	frame.OnMouseReleased = function() PinnedPanels.Save() end
	frame.OnSizeChanged   = function() PinnedPanels.Save() end

	local scroll          = vgui.Create("DScrollPanel", frame)
	scroll:Dock(FILL)
	scroll:DockMargin(4, 6, 4, 4)

	local oldInvalidate = scroll.InvalidateLayout
	scroll.NextLayout = 0
	scroll.InvalidateLayout = function(self, layoutNow)
		if CurTime() < self.NextLayout then return end
		self.NextLayout = CurTime() + 0.1
		oldInvalidate(self, layoutNow)
	end

	if isfunction(cpFunc) then
		local ctrl = vgui.Create("ControlPanel", scroll)
		ctrl:Dock(TOP)
		ctrl:SetAutoSize(true)
		cpFunc(ctrl)
	else
		local lbl = vgui.Create("DLabel", scroll)
		lbl:SetText("This tool has no control panel.")
		lbl:SetWrap(true)
		lbl:Dock(TOP)
		lbl:DockMargin(8, 8, 8, 8)
		lbl:SetTextColor(Color(40, 40, 40))
	end

	PinnedPanels.Pins[id] = { frame = frame, title = title, cpFunc = cpFunc }
	PinnedPanels.Save()
	hook.Run("PinnedPanels_StateChanged")
	return frame
end

function PinnedPanels.Unpin(id)
	local pin = PinnedPanels.Pins[id]
	if pin and IsValid(pin.frame) then pin.frame:Remove() end
	PinnedPanels.Pins[id] = nil
	local d = PinnedPanels.Load()
	d[id] = nil
	file.Write(SAVEF, util.TableToJSON(d, true))

	hook.Run("PinnedPanels_StateChanged")
end

function PinnedPanels.GetAllTools()
	local list = {}
	local tabs = spawnmenu.GetTools()
	if not tabs then return list end
	for _, tab in SortedPairs(tabs) do
		if tab.Items then
			for _, category in ipairs(tab.Items) do
				for _, item in ipairs(category) do
					if istable(item) and item.ItemName then
						local nice = language.GetPhrase(item.Text or "")
						if not nice or nice == item.Text then nice = item.Text or item.ItemName end
						table.insert(list, { itemName = item.ItemName, niceName = nice, cpFunc = item.CPanelFunction })
					end
				end
			end
		end
	end
	table.sort(list, function(a, b) return a.niceName < b.niceName end)
	return list
end

hook.Add("Think", "PinnedPanels_AutoRestore", function()
	local tabs = spawnmenu.GetTools()
	if tabs then
		hook.Remove("Think", "PinnedPanels_AutoRestore")

		if not PinnedPanels.Settings.autoRestore then return end

		timer.Simple(1, function()
			local saved = PinnedPanels.Load()
			local allTools = PinnedPanels.GetAllTools()
			local toolMap = {}
			for _, t in ipairs(allTools) do toolMap["PP_" .. t.itemName] = t end

			for id, s in pairs(saved) do
				if toolMap[id] then
					PinnedPanels.Pin(id, s.title or toolMap[id].niceName, toolMap[id].cpFunc)
				end
			end
		end)
	end
end)
