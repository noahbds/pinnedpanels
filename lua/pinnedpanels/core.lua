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
		local th      = PinnedPanels.Settings
		local inIM    = PinnedPanels.InteractMode and PinnedPanels.InteractMode.Active
		local hdrCol  = inIM and Color(
			math.min(th.header.r + 12, 255),
			math.min(th.header.g + 20, 255),
			math.min(th.header.b + 35, 255),
			th.header.a
		) or th.header
		draw.RoundedBox(6, 0, 0, w, h, th.bg)
		draw.RoundedBoxEx(6, 0, 0, w, 24, hdrCol, true, true, false, false)
		draw.SimpleText(title, "DermaDefaultBold", 10, 12, th.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		if inIM then
			surface.SetDrawColor(th.text.r, th.text.g, th.text.b, 60)
			for dx = 0, 4, 2 do
				for dy = 0, 4, 2 do
					surface.DrawRect(w - 22 + dx, 10 + dy, 1, 1)
				end
			end
			surface.SetDrawColor(60, 200, 120, 120)
			surface.DrawRect(w - 6, h - 6, 4, 1)
			surface.DrawRect(w - 6, h - 4, 1, 2)
		end
	end
end

local function BuildWrapperFrame(title, id, fw, fh, fx, fy)
	local frame = vgui.Create("DFrame")
	frame:SetTitle("")
	frame:SetSize(fw, fh)
	frame:SetPos(fx, fy)
	frame:SetDraggable(false)
	frame:SetSizable(false)
	frame:SetDeleteOnClose(false)
	frame:ParentToHUD()
	frame:MakePopup()
	frame:SetKeyboardInputEnabled(false)

	local titleOverlay
	local resizeOverlay

	local function ApplyInteractState(on)
		frame:SetMouseInputEnabled(on)
		frame:SetDraggable(false)
		frame:SetSizable(false)
		if IsValid(titleOverlay) then
			titleOverlay:SetMouseInputEnabled(on)
		end
		if IsValid(resizeOverlay) then
			resizeOverlay:SetMouseInputEnabled(on)
		end
	end

	local isInteractActive = PinnedPanels.InteractMode and PinnedPanels.InteractMode.Active
	ApplyInteractState(isInteractActive)

	local interactHook = "PinnedPanels_InteractFrame_" .. id .. "_" .. tostring(frame)
	hook.Add("PinnedPanels_InteractModeChanged", interactHook, function(on)
		if not IsValid(frame) then
			hook.Remove("PinnedPanels_InteractModeChanged", interactHook)
			return
		end
		ApplyInteractState(on)
	end)
	frame.OnRemove = function()
		hook.Remove("PinnedPanels_InteractModeChanged", interactHook)
	end

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

	local GRID          = 8
	local TITLE_HEIGHT  = 24
	local CORNER_SIZE   = 16
	local CLOSE_BTN_WIDTH = 30
	
	local imDrag        = false
	local imDragOffX, imDragOffY = 0, 0
	local imResize      = false
	local imResizeSX, imResizeSY = 0, 0
	local imResizeW, imResizeH   = 0, 0

	titleOverlay = vgui.Create("DPanel", frame)
	titleOverlay:SetPos(0, 0)
	titleOverlay:SetSize(frame:GetWide() - CLOSE_BTN_WIDTH, TITLE_HEIGHT)
	titleOverlay.Paint = function() end
	titleOverlay:SetMouseInputEnabled(false)
	
	resizeOverlay = vgui.Create("DPanel", frame)
	resizeOverlay:SetPos(frame:GetWide() - CORNER_SIZE, frame:GetTall() - CORNER_SIZE)
	resizeOverlay:SetSize(CORNER_SIZE, CORNER_SIZE)
	resizeOverlay.Paint = function() end
	resizeOverlay:SetMouseInputEnabled(false)

	ApplyInteractState(isInteractActive)

	local function UpdateOverlayPositions()
		local fw, fh = frame:GetSize()
		titleOverlay:SetSize(fw - CLOSE_BTN_WIDTH, TITLE_HEIGHT)
		resizeOverlay:SetPos(fw - CORNER_SIZE, fh - CORNER_SIZE)
	end

	titleOverlay.Think = function(self)
		if not imDrag then
			self:SetCursor("sizeall")
			return
		end
		local mx, my = gui.MouseX(), gui.MouseY()
		local w, h = frame:GetSize()
		local nx = math.floor(math.Clamp(mx - imDragOffX, 0, ScrW() - w) / GRID + 0.5) * GRID
		local ny = math.floor(math.Clamp(my - imDragOffY, 0, ScrH() - h) / GRID + 0.5) * GRID
		frame:SetPos(nx, ny)
	end

	resizeOverlay.Think = function(self)
		if not imResize then
			self:SetCursor("sizenwse")
			return
		end
		local fpx, fpy = frame:GetPos()
		local mx, my   = gui.MouseX(), gui.MouseY()
		local nw = math.floor(math.max(150, imResizeW + mx - imResizeSX) / GRID + 0.5) * GRID
		local nh = math.floor(math.max(100, imResizeH + my - imResizeSY) / GRID + 0.5) * GRID
		nw = math.min(nw, ScrW() - fpx)
		nh = math.min(nh, ScrH() - fpy)
		frame:SetSize(nw, nh)
		UpdateOverlayPositions()
	end

	titleOverlay.OnMousePressed = function(self, mc)
		if mc == MOUSE_LEFT then
			imDrag = true
			imDragOffX, imDragOffY = self:CursorPos()
			self:MouseCapture(true)
		elseif mc == MOUSE_RIGHT then
			local menu = DermaMenu()
			menu:AddOption("Bring to Front", function()
				frame:MoveToFront()
				frame:SetVisible(true)
			end):SetIcon("icon16/arrow_refresh.png")
			menu:AddSpacer()
			menu:AddOption("Unpin", function()
				PinnedPanels.Unpin(id)
			end):SetIcon("icon16/lock_open.png")
			menu:Open()
		end
	end

	titleOverlay.OnMouseReleased = function(self, _)
		if imDrag then
			imDrag = false
			self:MouseCapture(false)
			PinnedPanels.Save()
		end
	end

	resizeOverlay.OnMousePressed = function(self, mc)
		if mc == MOUSE_LEFT then
			imResize = true
			imResizeSX, imResizeSY = gui.MouseX(), gui.MouseY()
			imResizeW, imResizeH = frame:GetSize()
			self:MouseCapture(true)
		end
	end

	resizeOverlay.OnMouseReleased = function(self, _)
		if imResize then
			imResize = false
			self:MouseCapture(false)
			PinnedPanels.Save()
		end
	end

	frame.OnSizeChanged = function()
		UpdateOverlayPositions()
		DebouncedSave()
	end

	return frame
end

local function RectsOverlap(ax, ay, aw, ah, bx, by, bw, bh, pad)
	pad = pad or 0
	return ax < (bx + bw + pad)
		and bx < (ax + aw + pad)
		and ay < (by + bh + pad)
		and by < (ay + ah + pad)
end

local function IsSpawnOccupied(x, y, w, h, ignoreId)
	for id, pin in pairs(PinnedPanels.Pins) do
		if id ~= ignoreId and IsValid(pin.frame) and pin.frame:IsVisible() then
			local px, py = pin.frame:GetPos()
			local pw, ph = pin.frame:GetSize()
			if RectsOverlap(x, y, w, h, px, py, pw, ph, 20) then
				return true
			end
		end
	end
	return false
end

local function FindFreeSpawnPosition(w, h, preferredX, preferredY, ignoreId)
	local sw, sh = ScrW(), ScrH()
	local maxX = math.max(0, sw - w)
	local maxY = math.max(0, sh - h)
	local baseX = math.Clamp(preferredX or 120, 0, maxX)
	local baseY = math.Clamp(preferredY or 120, 0, maxY)

	if not IsSpawnOccupied(baseX, baseY, w, h, ignoreId) then
		return baseX, baseY
	end

	local STEP = 28
	for y = 0, maxY, STEP do
		for x = 0, maxX, STEP do
			if not IsSpawnOccupied(x, y, w, h, ignoreId) then
				return x, y
			end
		end
	end

	return baseX, baseY
end

function PinnedPanels.Pin(id, title, cpFunc, noSave, opts)
	opts = opts or {}
	local existing = PinnedPanels.Pins[id]
	if existing and IsValid(existing.frame) then
		existing.frame:SetVisible(true)
		return existing.frame
	end
	PinnedPanels.Pins[id] = nil

	local saved           = PinnedPanels.Load()
	local s               = saved[id] or {}
	local sw, sh          = ScrW(), ScrH()
	local fw              = math.Clamp(s.w or opts.defaultW or 280, 150, sw)
	local fh              = math.Clamp(s.h or opts.defaultH or 400, 100, sh)
	local hasSavedPos     = s.x ~= nil and s.y ~= nil
	local fx, fy
	if hasSavedPos then
		fx = math.Clamp(tonumber(s.x) or 120, 0, sw - fw)
		fy = math.Clamp(tonumber(s.y) or 120, 0, sh - fh)
	else
		fx, fy = FindFreeSpawnPosition(fw, fh, 120, 120, id)
	end

	local frame           = BuildWrapperFrame(title, id, fw, fh, fx, fy)

	if opts.fill then
		local ok, result = pcall(cpFunc)
		if ok and IsValid(result) then
			result:SetParent(frame)
			result:Dock(FILL)
			result:DockMargin(0, 4, 0, 0)
			result:SetMouseInputEnabled(true)
			result:InvalidateLayout(true)
		else
			local lbl = vgui.Create("DLabel", frame)
			lbl:SetText("Error loading panel" .. (not ok and (": " .. tostring(result)) or "."))
			lbl:SetWrap(true)
			lbl:Dock(FILL)
			lbl:DockMargin(8, 32, 8, 8)
			lbl:SetTextColor(Color(220, 80, 80))
		end
	else
		local scroll = vgui.Create("DScrollPanel", frame)
		scroll:Dock(FILL)
		scroll:DockMargin(4, 6, 4, 4)

		if isfunction(cpFunc) then
			local ctrl = vgui.Create("ControlPanel", scroll)
			ctrl:Dock(TOP)
			ctrl:SetAutoSize(true)
			local beforeCount = #ctrl:GetChildren()
			local ok, err = pcall(cpFunc, ctrl)
			if not ok then
				ctrl:Remove()
				local lbl = vgui.Create("DLabel", scroll)
				lbl:SetText("Error loading panel: " .. tostring(err))
				lbl:SetWrap(true)
				lbl:Dock(TOP)
				lbl:DockMargin(8, 8, 8, 8)
				lbl:SetTextColor(Color(220, 80, 80))
			else
				if #ctrl:GetChildren() <= beforeCount and controlpanel then
					local cpName = id:sub(4)
					local origGet = controlpanel.Get
					controlpanel.Get = function(name)
						if name == cpName then return ctrl end
						return origGet(name)
					end
					hook.Run("PostReloadToolsMenu")
					controlpanel.Get = origGet
				end
				ctrl:InvalidateLayout(true)
			end
		else
			local lbl = vgui.Create("DLabel", scroll)
			lbl:SetText("This tool has no control panel.")
			lbl:SetWrap(true)
			lbl:Dock(TOP)
			lbl:DockMargin(8, 8, 8, 8)
			lbl:SetTextColor(Color(120, 130, 145))
		end

		timer.Simple(0.2, function()
			if IsValid(scroll) then PinnedPanels.ThrottleScroll(scroll) end
		end)
	end

	PinnedPanels.Pins[id] = { frame = frame, title = title, cpFunc = cpFunc, kind = opts.kind or "tool" }

	if not noSave then
		PinnedPanels.Save()
	end
	hook.Run("PinnedPanels_StateChanged")

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
	local hasSavedPos     = s.x ~= nil and s.y ~= nil
	local fx, fy
	if hasSavedPos then
		fx = math.Clamp(tonumber(s.x) or ox, 0, sw - fw)
		fy = math.Clamp(tonumber(s.y) or oy, 0, sh - fh)
	else
		fx, fy = FindFreeSpawnPosition(fw, fh, ox, oy, id)
	end

	local origParent      = livePanel:GetParent()
	local origPos         = { livePanel:GetPos() }
	local origSize        = { livePanel:GetSize() }
	local origVisible     = livePanel:IsVisible()
	local origDock        = livePanel:GetDock()

	livePanel._pp_origParent  = origParent
	livePanel._pp_origPos     = origPos
	livePanel._pp_origSize    = origSize
	livePanel._pp_origVisible = origVisible
	livePanel._pp_origDock    = origDock

	local frame           = BuildWrapperFrame(title, id, fw, fh, fx, fy)

	livePanel:SetParent(frame)
	livePanel:SetDock(FILL)
	livePanel:DockMargin(0, 4, 0, 0)
	livePanel:SetVisible(true)
	livePanel:InvalidateLayout(true)

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

	local baseOnRemove = frame.OnRemove
	frame.OnRemove = function()
		baseOnRemove()
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
			pin.livePanel.OnRemove = nil
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
		if not IsValid(p) then goto cont end
		if ownedPanels[p] then goto cont end
		if p:GetClassName() ~= "DFrame" then goto cont end

		local name = p:GetName() or ""
		if FRAME_IGNORE_NAMES[name] then goto cont end
		if name:sub(1, 3) == "PP_" or name:sub(1, 4) == "PPF_" then goto cont end
		if not p:IsVisible() then goto cont end

		local title = ""
		if p.lblTitle and IsValid(p.lblTitle) then
			title = p.lblTitle:GetText() or ""
		end
		if title == "" then
			title = (name ~= "" and name) or ("Frame " .. (tostring(p):match("%d+$") or tostring(p)))
		end

		local alreadyPinned = PinnedPanels.IsPinnedFrame(p)
		table.insert(results, {
			panel  = p,
			title  = title,
			id     = "PPF_" .. tostring(p),
			pinned = alreadyPinned
		})
		::cont::
	end

	table.sort(results, function(a, b) return a.title:lower() < b.title:lower() end)
	return results
end

function PinnedPanels.ThrottleScroll(scroll)
	local orig = scroll.InvalidateLayout
	scroll.NextLayout = 0
	scroll.InvalidateLayout = function(self, layoutNow)
		if CurTime() < self.NextLayout then return end
		self.NextLayout = CurTime() + 0.1
		orig(self, layoutNow)
	end
end

function PinnedPanels.MakePinRowPaint(id, radius)
	radius = radius or 3
	return function(self, w, h)
		local pin    = PinnedPanels.Pins[id]
		local pinned = pin and IsValid(pin.frame)
		local bg     = pinned and Color(18, 48, 18, 220) or Color(26, 26, 40, 200)
		if self:IsHovered() then
			bg = pinned and Color(25, 65, 25) or Color(38, 38, 58)
		end
		draw.RoundedBox(radius, 0, 0, w, h, bg)
		if pinned then
			surface.SetDrawColor(60, 200, 80)
			surface.DrawRect(0, 0, 3, h)
		end
	end
end

function PinnedPanels.GetAllTools()
	local list = {}
	local seen = {}
	local tabs = spawnmenu.GetTools()
	if not tabs then return list end

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
							table.insert(list, {
								itemName = item.ItemName,
								niceName = nice,
								cpFunc   = item.CPanelFunction,
								category = catName,
								tabName  = tabName,
							})
						end
					end
				end
			end
		end
	end

	table.sort(list, function(a, b)
		return a.niceName:lower() < b.niceName:lower()
	end)
	return list
end

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

PinnedPanels.CREATION_OPTS = { kind = "creation", fill = true, defaultW = 350, defaultH = 560 }

function PinnedPanels.RestoreAll(noSave)
	local saved = PinnedPanels.Load()
	if not next(saved) then return end

	local allTools = PinnedPanels.GetAllTools()
	local toolMap  = {}
	for _, t in ipairs(allTools) do toolMap["PP_" .. t.itemName] = t end

	local allCreation = PinnedPanels.GetAllCreationTabs()
	local creationMap = {}
	for _, t in ipairs(allCreation) do creationMap[t.id] = t end

	for id, s in pairs(saved) do
		local kind = s.kind or "tool"
		if kind == "tool" and toolMap[id] then
			PinnedPanels.Pin(id, s.title or toolMap[id].niceName, toolMap[id].cpFunc, noSave)
		elseif kind == "creation" and creationMap[id] then
			local t = creationMap[id]
			PinnedPanels.Pin(id, s.title or t.label, t.func, noSave, PinnedPanels.CREATION_OPTS)
		end
	end
end

hook.Add("Think", "PinnedPanels_AutoRestore", function()
	local tabs = spawnmenu.GetTools()
	if not tabs then return end
	hook.Remove("Think", "PinnedPanels_AutoRestore")

	if not PinnedPanels.Settings.autoRestore then return end

	timer.Simple(1, function()
		PinnedPanels.RestoreAll(true)
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
