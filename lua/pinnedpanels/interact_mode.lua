-- ============================================================
--  PinnedPanels / interact_mode.lua
-- ============================================================

PinnedPanels.InteractMode = PinnedPanels.InteractMode or {}
local IM                  = PinnedPanels.InteractMode
IM.Active                 = false

local CVAR_KEY            = "pp_interact_key"
local DEFAULT_KEY         = KEY_F4

local keyConVar           = CreateClientConVar(CVAR_KEY, tostring(DEFAULT_KEY), true, false,
	"PinnedPanels interact mode keybind")

IM.KeyCode                = tonumber(keyConVar:GetString()) or DEFAULT_KEY
if IM.KeyCode == KEY_NONE then IM.KeyCode = DEFAULT_KEY end

local function SetInteractMode(on)
	if IM.Active == on then return end
	IM.Active = on
	gui.EnableScreenClicker(on)
end

function PinnedPanels.InteractMode.Toggle()
	SetInteractMode(not IM.Active)
end

local _keyWasDown = false
hook.Add("Think", "PinnedPanels_InteractKey", function()
	if IM.KeyCode == KEY_NONE then return end
	local down = input.IsKeyDown(IM.KeyCode)
	if down and not _keyWasDown then
		if not IsValid(vgui.GetKeyboardFocus()) then
			PinnedPanels.InteractMode.Toggle()
		end
	end
	_keyWasDown = down
end)

hook.Add("SpawnMenuOpen", "PinnedPanels_InteractOff", function()
	SetInteractMode(false)
end)

surface.CreateFont("PP_InteractFont", { font = "DefaultBold", size = 14, weight = 600 })

hook.Add("HUDPaint", "PinnedPanels_InteractHUD", function()
	if not IM.Active then return end
	local keyName = IM.KeyCode ~= KEY_NONE and input.GetKeyName(IM.KeyCode) or "?"
	local text = "INTERACT MODE  |  Press [" .. keyName .. "] to exit"
	local sw = ScrW()
	local bw = 380
	local bx = math.floor((sw - bw) / 2)
	draw.RoundedBox(6, bx, 6, bw, 22, Color(0, 0, 0, 190))
	surface.SetDrawColor(60, 200, 120)
	surface.DrawOutlinedRect(bx, 6, bw, 22, 1)
	draw.SimpleText(text, "PP_InteractFont", sw / 2, 17,
		Color(60, 230, 130), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end)

-- ----------------------------------------------------------------
-- Key bind popup frame
-- ----------------------------------------------------------------
function PinnedPanels.OpenKeyBindFrame(onSaved)
	if IsValid(PinnedPanels._bindFrame) then
		PinnedPanels._bindFrame:Remove()
	end

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
	instrLabel:SetText("Press any key to bind it.\nEscape = cancel  |  Backspace = clear binding.")
	instrLabel:SetWrap(true)
	instrLabel:SetAutoStretchVertical(true)
	instrLabel:Dock(TOP)
	instrLabel:DockMargin(12, 10, 12, 8)
	instrLabel:SetTextColor(Color(180, 195, 220))

	local captureBtn = vgui.Create("DButton", frame)
	captureBtn:SetTall(50)
	captureBtn:Dock(TOP)
	captureBtn:DockMargin(12, 0, 12, 10)
	captureBtn:SetText(">> Press any key <<")
	captureBtn:SetKeyboardInputEnabled(true)

	captureBtn.Paint = function(self, w, h)
		draw.RoundedBox(6, 0, 0, w, h, self:IsHovered() and Color(40, 60, 100) or Color(25, 40, 75))
		surface.SetDrawColor(60, 140, 255)
		surface.DrawOutlinedRect(0, 0, w, h, 1)
		draw.SimpleText(self:GetText(), "DermaDefaultBold", w / 2, h / 2,
			Color(180, 210, 255), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end

	captureBtn:RequestFocus()

	captureBtn.OnKeyCodePressed = function(self, keyCode)
		if keyCode == KEY_ESCAPE then
			frame:Close()
			return
		end
		if keyCode == KEY_BACKSPACE then
			IM.KeyCode = KEY_NONE
			RunConsoleCommand(CVAR_KEY, tostring(KEY_NONE))
		else
			IM.KeyCode = keyCode
			RunConsoleCommand(CVAR_KEY, tostring(keyCode))
		end
		if onSaved then onSaved() end
		frame:Close()
	end

	captureBtn.DoClick = function() captureBtn:RequestFocus() end
end

-- ----------------------------------------------------------------
-- Settings panel
-- ----------------------------------------------------------------
function PinnedPanels.CreateInteractSettings(parent)
	local root = vgui.Create("DPanel", parent)
	root:Dock(FILL)
	root.Paint = function() end

	local statusGroup = vgui.Create("DPanel", root)
	statusGroup:Dock(TOP)
	statusGroup:SetTall(44)
	statusGroup:DockMargin(8, 8, 8, 4)
	statusGroup.Paint = function(self, w, h)
		draw.RoundedBox(4, 0, 0, w, h, Color(20, 28, 40, 200))
	end

	local statusLabel = vgui.Create("DLabel", statusGroup)
	statusLabel:Dock(LEFT)
	statusLabel:DockMargin(10, 0, 0, 0)
	statusLabel:SetWide(160)
	statusLabel:SetFont("DermaDefaultBold")
	statusGroup.Think = function()
		if IM.Active then
			statusLabel:SetText("Status: ACTIVE")
			statusLabel:SetTextColor(Color(60, 220, 100))
		else
			statusLabel:SetText("Status: Inactive")
			statusLabel:SetTextColor(Color(160, 170, 190))
		end
	end

	local toggleBtn = vgui.Create("DButton", statusGroup)
	toggleBtn:SetText("Toggle Now")
	toggleBtn:SetIcon("icon16/cursor.png")
	toggleBtn:Dock(RIGHT)
	toggleBtn:DockMargin(0, 8, 8, 8)
	toggleBtn:SetWide(110)
	toggleBtn.DoClick = function() PinnedPanels.InteractMode.Toggle() end

	local bindGroup = vgui.Create("DPanel", root)
	bindGroup:Dock(TOP)
	bindGroup:DockMargin(8, 4, 8, 4)
	bindGroup:SetTall(80)
	bindGroup.Paint = function(self, w, h)
		draw.RoundedBox(4, 0, 0, w, h, Color(20, 28, 40, 200))
	end

	local bindTitle = vgui.Create("DLabel", bindGroup)
	bindTitle:SetText("Keybind")
	bindTitle:SetFont("DermaDefaultBold")
	bindTitle:SetTextColor(Color(180, 200, 255))
	bindTitle:Dock(TOP)
	bindTitle:DockMargin(10, 8, 0, 0)
	bindTitle:SetAutoStretchVertical(true)

	local keyDisplay = vgui.Create("DLabel", bindGroup)
	keyDisplay:Dock(TOP)
	keyDisplay:SetTall(20)
	keyDisplay:DockMargin(10, 2, 10, 0)

	local function UpdateKeyDisplay()
		if not IsValid(keyDisplay) then return end
		if IM.KeyCode == KEY_NONE then
			keyDisplay:SetText("Current key: [ Not bound ]")
			keyDisplay:SetTextColor(Color(200, 80, 80))
		else
			keyDisplay:SetText("Current key: [ " .. input.GetKeyName(IM.KeyCode) .. " ]")
			keyDisplay:SetTextColor(Color(80, 210, 120))
		end
	end
	UpdateKeyDisplay()

	local bindRow = vgui.Create("DPanel", bindGroup)
	bindRow:Dock(TOP)
	bindRow:SetTall(28)
	bindRow:DockMargin(8, 4, 8, 8)
	bindRow.Paint = function() end

	local openBindBtn = vgui.Create("DButton", bindRow)
	openBindBtn:SetText("Change Key...")
	openBindBtn:SetIcon("icon16/keyboard.png")
	openBindBtn:Dock(LEFT)
	openBindBtn:SetWide(140)
	openBindBtn.DoClick = function()
		PinnedPanels.OpenKeyBindFrame(UpdateKeyDisplay)
	end

	local clearBtn = vgui.Create("DButton", bindRow)
	clearBtn:SetText("Clear")
	clearBtn:SetIcon("icon16/cross.png")
	clearBtn:Dock(LEFT)
	clearBtn:SetWide(65)
	clearBtn:DockMargin(6, 0, 0, 0)
	clearBtn.DoClick = function()
		IM.KeyCode = KEY_NONE
		RunConsoleCommand(CVAR_KEY, tostring(KEY_NONE))
		UpdateKeyDisplay()
	end

	local helpGroup = vgui.Create("DPanel", root)
	helpGroup:Dock(TOP)
	helpGroup:DockMargin(8, 4, 8, 4)
	helpGroup:SetTall(90)
	helpGroup.Paint = function(self, w, h)
		draw.RoundedBox(4, 0, 0, w, h, Color(20, 28, 40, 200))
	end

	local helpTitle = vgui.Create("DLabel", helpGroup)
	helpTitle:SetText("How it works")
	helpTitle:SetFont("DermaDefaultBold")
	helpTitle:SetTextColor(Color(180, 200, 255))
	helpTitle:Dock(TOP)
	helpTitle:DockMargin(10, 8, 0, 4)
	helpTitle:SetAutoStretchVertical(true)

	local helpText = vgui.Create("DLabel", helpGroup)
	helpText:SetText(
		"Press your bound key in-game to show the cursor.\n" ..
		"Click and drag pinned panels freely. Movement is NOT blocked.\n" ..
		"Default key: F4"
	)
	helpText:SetWrap(true)
	helpText:SetAutoStretchVertical(true)
	helpText:Dock(TOP)
	helpText:DockMargin(10, 0, 10, 8)
	helpText:SetTextColor(Color(150, 165, 190))

	return root
end

print("[PinnedPanels] Interact mode loaded. Default key: F4")
