PinnedPanels          = PinnedPanels or {}
PinnedPanels.Pins     = PinnedPanels.Pins or {}

local SAVEF           = "pinnedpanels_save.json"
local SETTINGSF       = "pinnedpanels_settings.json"

PinnedPanels.Settings = PinnedPanels.Settings or {
	bg          = Color(235, 238, 242, 250),
	header      = Color(32, 35, 42, 255),
	text        = Color(240, 245, 255, 255),
	autoRestore = true
}

local function SerializeColor(c)
	return { r = c.r, g = c.g, b = c.b, a = c.a }
end

local function DeserializeColor(t, fallback)
	if not istable(t) then return fallback end
	return Color(
		math.Clamp(tonumber(t.r) or 0, 0, 255),
		math.Clamp(tonumber(t.g) or 0, 0, 255),
		math.Clamp(tonumber(t.b) or 0, 0, 255),
		math.Clamp(tonumber(t.a) or 255, 0, 255)
	)
end

function PinnedPanels.SaveSettings()
	local t = {
		bg          = SerializeColor(PinnedPanels.Settings.bg),
		header      = SerializeColor(PinnedPanels.Settings.header),
		text        = SerializeColor(PinnedPanels.Settings.text),
		autoRestore = PinnedPanels.Settings.autoRestore
	}
	file.Write(SETTINGSF, util.TableToJSON(t, true))
	for _, pin in pairs(PinnedPanels.Pins) do
		if IsValid(pin.frame) then
			pin.frame.Paint = PinnedPanels.GetFramePaint(pin.title)
		end
	end
end

function PinnedPanels.LoadSettings()
	if not file.Exists(SETTINGSF, "DATA") then return end
	local raw = file.Read(SETTINGSF, "DATA")
	if not raw or raw == "" then return end
	local t = util.JSONToTable(raw)
	if not istable(t) then return end
	PinnedPanels.Settings.bg     = DeserializeColor(t.bg, PinnedPanels.Settings.bg)
	PinnedPanels.Settings.header = DeserializeColor(t.header, PinnedPanels.Settings.header)
	PinnedPanels.Settings.text   = DeserializeColor(t.text, PinnedPanels.Settings.text)
	if t.autoRestore ~= nil then PinnedPanels.Settings.autoRestore = tobool(t.autoRestore) end
end

PinnedPanels.LoadSettings()

function PinnedPanels.Save()
	local data = {}
	for id, pin in pairs(PinnedPanels.Pins) do
		if IsValid(pin.frame) then
			local x, y = pin.frame:GetPos()
			local w, h = pin.frame:GetSize()
			data[id] = { x = x, y = y, w = w, h = h, title = pin.title, kind = pin.kind or "tool" }
		end
	end
	file.Write(SAVEF, util.TableToJSON(data, true))
end

function PinnedPanels.Load()
	if not file.Exists(SAVEF, "DATA") then return {} end
	local raw = file.Read(SAVEF, "DATA")
	if not raw or raw == "" then return {} end
	return util.JSONToTable(raw) or {}
end

function PinnedPanels.GetFramePaint(title)
	return function(self, w, h)
		local th = PinnedPanels.Settings
		draw.RoundedBox(6, 0, 0, w, h, th.bg)
		draw.RoundedBoxEx(6, 0, 0, w, 24, th.header, true, true, false, false)
		draw.SimpleText(title, "DermaDefaultBold", 10, 12, th.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	end
end

local function BuildWrapperFrame(title, id, fw, fh, fx, fy)
	local frame = vgui.Create("DFrame")
	frame:SetTitle("")
	frame:SetSize(fw, fh)
	frame:SetPos(fx, fy)
	frame:SetDraggable(true)
	frame:SetSizable(true)
	frame:SetDeleteOnClose(false)
	frame:ParentToHUD()
	frame:MakePopup()
	frame:SetKeyboardInputEnabled(false)

	local isInteractActive = PinnedPanels.InteractMode and PinnedPanels.InteractMode.Active
	frame:SetMouseInputEnabled(isInteractActive and true or false)

	frame:ShowCloseButton(true)
	frame.OnClose      = function() frame:SetVisible(false) end
	frame.Paint        = PinnedPanels.GetFramePaint(title)

	local saveDebounce = 0
	local function DebouncedSave()
		local t = CurTime()
		if t > saveDebounce + 0.2 then
			saveDebounce = t
			PinnedPanels.Save()
		end
	end
	frame.OnMouseReleased = function() DebouncedSave() end
	frame.OnSizeChanged   = function() DebouncedSave() end

	frame.NextFocusCheck  = 0
	frame.Think           = function(self)
		local x, y = self:GetPos()
		local w, h = self:GetSize()
		local nx = math.Clamp(x, 0, ScrW() - w)
		local ny = math.Clamp(y, 0, ScrH() - h)
		if x ~= nx or y ~= ny then self:SetPos(nx, ny) end

		if CurTime() < self.NextFocusCheck then return end
		self.NextFocusCheck = CurTime() + 0.1

		local hovered       = vgui.GetHoveredPanel()
		local focus         = vgui.GetKeyboardFocus()
		local function isTextPanel(p)
			if not IsValid(p) then return false end
			local c = p:GetClassName()
			return c == "TextEntry" or c == "DTextEntry" or c == "RichText"
		end
		local needsKeyboard = (isTextPanel(hovered) and hovered:HasParent(self))
			or (isTextPanel(focus) and focus:HasParent(self))
		if self:IsKeyboardInputEnabled() ~= needsKeyboard then
			self:SetKeyboardInputEnabled(needsKeyboard)
		end
	end

	return frame
end

function PinnedPanels.Pin(id, title, cpFunc, noSave)
	local existing = PinnedPanels.Pins[id]
	if existing and IsValid(existing.frame) then
		existing.frame:SetVisible(true)
		return existing.frame
	end
	PinnedPanels.Pins[id] = nil

	local saved           = PinnedPanels.Load()
	local s               = saved[id] or {}
	local sw, sh          = ScrW(), ScrH()
	local fw              = math.Clamp(s.w or 280, 150, sw)
	local fh              = math.Clamp(s.h or 400, 100, sh)
	local fx              = math.Clamp(s.x or 120, 0, sw - fw)
	local fy              = math.Clamp(s.y or 120, 0, sh - fh)

	local frame           = BuildWrapperFrame(title, id, fw, fh, fx, fy)

	local scroll          = vgui.Create("DScrollPanel", frame)
	scroll:Dock(FILL)
	scroll:DockMargin(4, 6, 4, 4)

	local oldInvalidate     = scroll.InvalidateLayout
	scroll.NextLayout       = 0
	scroll.InvalidateLayout = function(self, layoutNow)
		if CurTime() < self.NextLayout then return end
		self.NextLayout = CurTime() + 0.1
		oldInvalidate(self, layoutNow)
	end

	if isfunction(cpFunc) then
		local ctrl = vgui.Create("ControlPanel", scroll)
		ctrl:Dock(TOP)
		ctrl:SetAutoSize(true)
		local ok, err = pcall(cpFunc, ctrl)
		if not ok then
			ctrl:Remove()
			local lbl = vgui.Create("DLabel", scroll)
			lbl:SetText("Error loading panel: " .. tostring(err))
			lbl:SetWrap(true)
			lbl:Dock(TOP)
			lbl:DockMargin(8, 8, 8, 8)
			lbl:SetTextColor(Color(220, 80, 80))
		end
	else
		local lbl = vgui.Create("DLabel", scroll)
		lbl:SetText("This tool has no control panel.")
		lbl:SetWrap(true)
		lbl:Dock(TOP)
		lbl:DockMargin(8, 8, 8, 8)
		lbl:SetTextColor(Color(120, 130, 145))
	end

	PinnedPanels.Pins[id] = { frame = frame, title = title, cpFunc = cpFunc, kind = "tool" }

	if not noSave then
		PinnedPanels.Save()
	end

	return frame
end

function PinnedPanels.PinFrame(livePanel, title)
	if not IsValid(livePanel) then return end

	local id = "PPF_" .. tostring(livePanel)

	local existing = PinnedPanels.Pins[id]
	if existing and IsValid(existing.frame) then
		existing.frame:SetVisible(true)
		return existing.frame
	end
	PinnedPanels.Pins[id] = nil

	local saved           = PinnedPanels.Load()
	local s               = saved[id] or {}
	local sw, sh          = ScrW(), ScrH()

	local ox, oy          = livePanel:GetPos()
	local ow, oh          = livePanel:GetSize()
	local fw              = math.Clamp(s.w or (ow + 8), 150, sw)
	local fh              = math.Clamp(s.h or (oh + 28), 100, sh)
	local fx              = math.Clamp(s.x or ox, 0, sw - fw)
	local fy              = math.Clamp(s.y or oy, 0, sh - fh)

	local origParent      = livePanel:GetParent()
	local origPos         = { livePanel:GetPos() }
	local origSize        = { livePanel:GetSize() }
	local origVisible     = livePanel:IsVisible()
	local origDock        = livePanel:GetDock()

	local frame           = BuildWrapperFrame(title, id, fw, fh, fx, fy)

	livePanel:SetParent(frame)
	livePanel:SetDock(FILL)
	livePanel:DockMargin(0, 4, 0, 0)
	livePanel:SetVisible(true)

	local origOnRemove = livePanel.OnRemove
	livePanel.OnRemove = function(self)
		if PinnedPanels.Pins[id] then
			PinnedPanels.Pins[id] = nil
			local d               = PinnedPanels.Load()
			d[id]                 = nil
			file.Write(SAVEF, util.TableToJSON(d, true))
			hook.Run("PinnedPanels_StateChanged")
		end
		if isfunction(origOnRemove) then origOnRemove(self) end
	end

	frame.OnRemove = function()
		if IsValid(livePanel) then
			livePanel:SetDock(origDock)
			if IsValid(origParent) then
				livePanel:SetParent(origParent)
				if origDock == NODOCK then
					livePanel:SetPos(origPos[1], origPos[2])
					livePanel:SetSize(origSize[1], origSize[2])
				end
			end
			livePanel:SetVisible(origVisible)
		end
	end

	PinnedPanels.Pins[id] = {
		frame     = frame,
		title     = title,
		livePanel = livePanel,
		kind      = "frame"
	}
	PinnedPanels.Save()
	hook.Run("PinnedPanels_StateChanged")
	return frame
end

function PinnedPanels.IsPinnedFrame(livePanel)
	if not IsValid(livePanel) then return false end
	local id = "PPF_" .. tostring(livePanel)
	local pin = PinnedPanels.Pins[id]
	return pin ~= nil and IsValid(pin.frame)
end

function PinnedPanels.Unpin(id)
	local pin = PinnedPanels.Pins[id]
	if pin then
		if pin.kind == "frame" and IsValid(pin.livePanel) then
			local lp = pin.livePanel
			lp.OnRemove = nil
			if IsValid(pin.frame) then
				local origParent  = lp._pp_origParent
				local origPos     = lp._pp_origPos
				local origSize    = lp._pp_origSize
				local origVisible = lp._pp_origVisible
				local origDock    = lp._pp_origDock
				lp:SetDock(origDock or NODOCK)
				if IsValid(origParent) then
					lp:SetParent(origParent)
					if (origDock or NODOCK) == NODOCK then
						lp:SetPos(origPos and origPos[1] or 0, origPos and origPos[2] or 0)
						lp:SetSize(origSize and origSize[1] or 200, origSize and origSize[2] or 200)
					end
				end
				lp:SetVisible(origVisible ~= false)
			end
		end
		if IsValid(pin.frame) then pin.frame:Remove() end
	end
	PinnedPanels.Pins[id] = nil

	local d               = PinnedPanels.Load()
	d[id]                 = nil
	file.Write(SAVEF, util.TableToJSON(d, true))
	hook.Run("PinnedPanels_StateChanged")
end

function PinnedPanels.UnpinAll()
	local ids = {}
	for id in pairs(PinnedPanels.Pins) do ids[#ids + 1] = id end
	for _, id in ipairs(ids) do PinnedPanels.Unpin(id) end
end

local FRAME_IGNORE_NAMES = {
	SpawnmenuTabs         = true,
	SpawnMenuContentPanel = true,
	DMenu                 = true,
	ContextMenu           = true,
}

function PinnedPanels.ScanFrames()
	local ownedPanels = {}
	for _, pin in pairs(PinnedPanels.Pins) do
		if IsValid(pin.frame) then ownedPanels[pin.frame] = true end
		if IsValid(pin.livePanel) then ownedPanels[pin.livePanel] = true end
	end

	local results = {}
	for _, p in ipairs(vgui.GetAll()) do
		if not IsValid(p) then continue end
		if ownedPanels[p] then continue end
		if p:GetClassName() ~= "DFrame" then continue end

		local name = p:GetName() or ""
		if FRAME_IGNORE_NAMES[name] then continue end
		if name:sub(1, 3) == "PP_" or name:sub(1, 4) == "PPF_" then continue end
		if not p:IsVisible() then continue end

		local title = ""
		if p.lblTitle and IsValid(p.lblTitle) then
			title = p.lblTitle:GetText() or ""
		end
		if title == "" then
			title = (name ~= "" and name) or ("Frame " .. tostring(p):match("%d+$") or tostring(p))
		end

		local alreadyPinned = PinnedPanels.IsPinnedFrame(p)
		table.insert(results, {
			panel  = p,
			title  = title,
			id     = "PPF_" .. tostring(p),
			pinned = alreadyPinned
		})
	end

	table.sort(results, function(a, b) return a.title:lower() < b.title:lower() end)
	return results
end

function PinnedPanels.GetAllTools()
	local list = {}
	local seen = {}
	local tabs = spawnmenu.GetTools()
	if not tabs then return list end
	for _, tab in SortedPairs(tabs) do
		if tab.Items then
			for _, category in ipairs(tab.Items) do
				for _, item in ipairs(category) do
					if istable(item) and item.ItemName and not seen[item.ItemName] then
						seen[item.ItemName] = true
						local nice = language.GetPhrase(item.Text or "")
						if not nice or nice == "" or nice == item.Text then
							nice = item.Text or item.ItemName
						end
						table.insert(list, {
							itemName = item.ItemName,
							niceName = nice,
							cpFunc   = item.CPanelFunction
						})
					end
				end
			end
		end
	end
	table.sort(list, function(a, b) return a.niceName:lower() < b.niceName:lower() end)
	return list
end

hook.Add("Think", "PinnedPanels_AutoRestore", function()
	local tabs = spawnmenu.GetTools()
	if not tabs then return end
	hook.Remove("Think", "PinnedPanels_AutoRestore")

	if not PinnedPanels.Settings.autoRestore then return end

	timer.Simple(1, function()
		local saved = PinnedPanels.Load()
		if not next(saved) then return end

		local allTools = PinnedPanels.GetAllTools()
		local toolMap  = {}
		for _, t in ipairs(allTools) do toolMap["PP_" .. t.itemName] = t end

		for id, s in pairs(saved) do
			local kind = s.kind or "tool"
			if kind == "tool" and toolMap[id] then
				PinnedPanels.Pin(id, s.title or toolMap[id].niceName, toolMap[id].cpFunc, true)
			end
		end
	end)
end)

hook.Add("OnScreenSizeChanged", "PinnedPanels_ScreenResize", function(oldW, oldH)
	local nw, nh = ScrW(), ScrH()
	if nw == oldW and nh == oldH then return end
	for _, pin in pairs(PinnedPanels.Pins) do
		if IsValid(pin.frame) then
			local x, y = pin.frame:GetPos()
			local w, h = pin.frame:GetSize()
			pin.frame:SetPos(math.Clamp(x, 0, nw - w), math.Clamp(y, 0, nh - h))
		end
	end
end)
