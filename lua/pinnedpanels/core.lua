-- ============================================================
--  PinnedPanels / core.lua
-- ============================================================

PinnedPanels = PinnedPanels or {}
PinnedPanels.Pins = PinnedPanels.Pins or {}

local SAVEF = "pinnedpanels_save.json"

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

function PinnedPanels.Pin(id, title, cpFunc)
	if PinnedPanels.Pins[id] and IsValid(PinnedPanels.Pins[id].frame) then
		PinnedPanels.Pins[id].frame:SetVisible(true)
		return PinnedPanels.Pins[id].frame
	end

	local saved = PinnedPanels.Load()
	local s = saved[id] or {}

	-- Use DFrame parented to HUD so it persists regardless of spawn menu state
	-- and never steals game input focus
	local frame = vgui.Create("DFrame")
	frame:SetTitle(title)
	frame:SetSize(s.w or 280, s.h or 400)
	frame:SetPos(s.x or 120, s.y or 120)
	frame:SetDraggable(true)
	frame:SetSizable(true)
	frame:SetDeleteOnClose(false)
	-- ParentToHUD: stays visible always, never captures game input
	frame:ParentToHUD()

	-- FIX: Make it a popup so sliders/buttons get VGUI focus, but disable keyboard so WASD still works
	frame:MakePopup()
	frame:SetKeyboardInputEnabled(false)

	-- Initialize mouse state based on current interact mode
	local isInteractActive = (PinnedPanels.InteractMode and PinnedPanels.InteractMode.Active)
	frame:SetMouseInputEnabled(isInteractActive)

	-- Custom close: hide instead of remove
	frame:ShowCloseButton(true)
	frame.OnClose         = function() frame:SetVisible(false) end

	-- Keep inside screen
	frame.Think           = function(self)
		local x, y = self:GetPos()
		local w, h = self:GetSize()
		local nx = math.Clamp(x, 0, ScrW() - w)
		local ny = math.Clamp(y, 0, ScrH() - h)

		-- Only apply SetPos if the frame is actually outside the screen
		if x ~= nx or y ~= ny then
			self:SetPos(nx, ny)
		end
	end

	frame.OnMouseReleased = function() PinnedPanels.Save() end
	frame.OnSizeChanged   = function() PinnedPanels.Save() end

	local scroll          = vgui.Create("DScrollPanel", frame)
	scroll:Dock(FILL)
	scroll:DockMargin(2, 2, 2, 2)

	if isfunction(cpFunc) then
		local ctrl = vgui.Create("ControlPanel", scroll)
		ctrl:Dock(TOP)
		ctrl:SetAutoSize(true)
		cpFunc(ctrl)
	else
		local lbl = vgui.Create("DLabel", scroll)
		lbl:SetText("This tool has no control panel.")
		lbl:SetWrap(true)
		lbl:SetAutoStretchVertical(true)
		lbl:Dock(TOP)
		lbl:DockMargin(8, 8, 8, 8)
	end

	PinnedPanels.Pins[id] = { frame = frame, title = title, cpFunc = cpFunc }
	PinnedPanels.Save()
	return frame
end

function PinnedPanels.Unpin(id)
	local pin = PinnedPanels.Pins[id]
	if pin and IsValid(pin.frame) then pin.frame:Remove() end
	PinnedPanels.Pins[id] = nil
	local d = PinnedPanels.Load()
	d[id] = nil
	file.Write("pinnedpanels_save.json", util.TableToJSON(d, true))
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
						table.insert(list, {
							itemName = item.ItemName,
							niceName = nice,
							cpFunc   = item.CPanelFunction,
						})
					end
				end
			end
		end
	end
	table.sort(list, function(a, b) return a.niceName < b.niceName end)
	return list
end

print("[PinnedPanels] Core loaded.")
