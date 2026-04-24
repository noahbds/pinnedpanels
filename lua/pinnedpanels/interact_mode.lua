PinnedPanels.InteractMode = PinnedPanels.InteractMode or {}
local IM = PinnedPanels.InteractMode
IM.Active = IM.Active or false

local CVAR_KEY = "pp_interact_key"
local DEFAULT_KEY = KEY_F4

local keyConVar = CreateClientConVar(CVAR_KEY, tostring(DEFAULT_KEY), true, false,
	"PinnedPanels interact mode keybind")

IM.KeyCode = tonumber(keyConVar:GetString()) or DEFAULT_KEY
if IM.KeyCode == KEY_NONE or not IM.KeyCode then IM.KeyCode = DEFAULT_KEY end

cvars.AddChangeCallback(CVAR_KEY, function(_, _, new)
	local code = tonumber(new)
	if code then IM.KeyCode = code end
end, "PinnedPanels_KeyCVar")

local function SetInteractMode(on)
	if IM.Active == on then return end
	IM.Active = on
	gui.EnableScreenClicker(on)
	for _, pin in pairs(PinnedPanels.Pins) do
		if IsValid(pin.frame) then
			pin.frame:SetMouseInputEnabled(on)
		end
	end
	hook.Run("PinnedPanels_InteractModeChanged", on)
end

function PinnedPanels.InteractMode.Enable() SetInteractMode(true) end
function PinnedPanels.InteractMode.Disable() SetInteractMode(false) end
function PinnedPanels.InteractMode.Toggle() SetInteractMode(not IM.Active) end

local _keyWasDown = false
hook.Add("Think", "PinnedPanels_InteractKey", function()
	if not IM.KeyCode or IM.KeyCode == KEY_NONE then return end
	local down = input.IsKeyDown(IM.KeyCode)
	if down and not _keyWasDown then
		local focus = vgui.GetKeyboardFocus()
		if not IsValid(focus) then
			PinnedPanels.InteractMode.Toggle()
		end
	end
	_keyWasDown = down
end)

hook.Add("OnSpawnMenuOpen", "PinnedPanels_SpawnMenuOpen", function()
	SetInteractMode(false)
	for _, pin in pairs(PinnedPanels.Pins) do
		if IsValid(pin.frame) then pin.frame:SetMouseInputEnabled(true) end
	end
end)

hook.Add("OnSpawnMenuClose", "PinnedPanels_SpawnMenuClose", function()
	for _, pin in pairs(PinnedPanels.Pins) do
		if IsValid(pin.frame) then pin.frame:SetMouseInputEnabled(IM.Active) end
	end
end)

hook.Add("PinnedPanels_StateChanged", "PinnedPanels_InteractSyncNew", function()
	for _, pin in pairs(PinnedPanels.Pins) do
		if IsValid(pin.frame) and pin.frame:IsMouseInputEnabled() ~= IM.Active then
			pin.frame:SetMouseInputEnabled(IM.Active)
		end
	end
end)

surface.CreateFont("PP_InteractFont", { font = "DefaultBold", size = 14, weight = 600 })

hook.Add("HUDPaint", "PinnedPanels_InteractHUD", function()
	if not IM.Active then return end
	local keyName = (IM.KeyCode and IM.KeyCode ~= KEY_NONE) and input.GetKeyName(IM.KeyCode) or "?"
	local text = "INTERACT MODE  |  Press [" .. string.upper(keyName) .. "] to exit"
	local sw = ScrW()
	local bw = 400
	local bx = math.floor((sw - bw) / 2)
	draw.RoundedBox(6, bx, 6, bw, 24, Color(0, 0, 0, 190))
	surface.SetDrawColor(60, 200, 120)
	surface.DrawOutlinedRect(bx, 6, bw, 24, 1)
	draw.SimpleText(text, "PP_InteractFont", sw / 2, 18, Color(60, 230, 130), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end)

function PinnedPanels.OpenKeyBindFrame(onSaved)
	if IsValid(PinnedPanels._bindFrame) then PinnedPanels._bindFrame:Remove() end

	local frame = vgui.Create("DFrame")
	frame:SetTitle("Bind Interact Key")
	frame:SetSize(320, 180)
	frame:Center()
	frame:SetDraggable(true)
	frame:SetSizable(false)
	frame:SetDeleteOnClose(true)
	frame:MakePopup()
	PinnedPanels._bindFrame = frame

	frame.Paint = function(self, w, h)
		draw.RoundedBox(6, 0, 0, w, h, Color(16, 16, 26, 255))
		draw.RoundedBoxEx(6, 0, 0, w, 24, Color(22, 22, 36, 255), true, true, false, false)
		surface.SetDrawColor(60, 140, 255)
		surface.DrawRect(0, 22, w, 2)
	end

	local instrLabel = vgui.Create("DLabel", frame)
	instrLabel:SetText("Click the button below to listen for a key.\nEscape = cancel  |  Backspace = clear binding.")
	instrLabel:SetWrap(true)
	instrLabel:Dock(TOP)
	instrLabel:DockMargin(12, 10, 12, 8)
	instrLabel:SetTextColor(Color(180, 195, 220))
	instrLabel:SetAutoStretchVertical(true)

	local captureBtn = vgui.Create("DButton", frame)
	captureBtn:SetTall(50)
	captureBtn:Dock(TOP)
	captureBtn:DockMargin(12, 4, 12, 10)
	captureBtn:SetKeyboardInputEnabled(true)
	captureBtn:SetText("")

	captureBtn.Think = function(self)
		if self:HasFocus() then
			self:SetText(">> Press a key <<")
		else
			local code = PinnedPanels.InteractMode.KeyCode
			local keyName = (code and code ~= KEY_NONE) and input.GetKeyName(code) or "None"
			self:SetText("Click to bind  (Current: " .. string.upper(keyName) .. ")")
		end
	end

	captureBtn.Paint = function(self, w, h)
		local focused = self:HasFocus()
		local hovered = self:IsHovered()
		local bgCol = (hovered or focused) and Color(40, 60, 100) or Color(25, 40, 75)
		draw.RoundedBox(6, 0, 0, w, h, bgCol)
		surface.SetDrawColor(60, 140, 255)
		surface.DrawOutlinedRect(0, 0, w, h, focused and 2 or 1)
		local txtCol = focused and Color(120, 255, 120) or Color(180, 210, 255)
		draw.SimpleText(self:GetText(), "DermaDefaultBold", w / 2, h / 2, txtCol, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		return true
	end

	captureBtn.OnKeyCodePressed = function(self, keyCode)
		if keyCode == KEY_ESCAPE then
			frame:Close()
			return
		end
		if keyCode == KEY_BACKSPACE then
			PinnedPanels.InteractMode.KeyCode = KEY_NONE
			RunConsoleCommand(CVAR_KEY, tostring(KEY_NONE))
		else
			PinnedPanels.InteractMode.KeyCode = keyCode
			RunConsoleCommand(CVAR_KEY, tostring(keyCode))
		end
		if isfunction(onSaved) then onSaved() end
		frame:Close()
	end

	captureBtn.DoClick = function(self)
		self:RequestFocus()
	end
end

print("[PinnedPanels] Interact mode loaded.")
