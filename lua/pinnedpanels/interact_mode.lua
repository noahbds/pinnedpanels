PinnedPanels.InteractMode = PinnedPanels.InteractMode or {}
local IM = PinnedPanels.InteractMode
IM.Active = IM.Active or false

local C = PinnedPanels.C

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

IM.SpawnMenuOpen = IsValid(g_SpawnMenu) and g_SpawnMenu:IsVisible() or false

-- ── Panel Input / Idle Opacity ───────────────────────────────────────────────
function PinnedPanels.UpdatePanelStates()
	local interactive = PinnedPanels.PanelsInteractive()
	for _, pin in pairs(PinnedPanels.Pins) do
		if IsValid(pin.frame) then
			if pin.frame:IsMouseInputEnabled() ~= interactive then
				pin.frame:SetMouseInputEnabled(interactive)
			end
			local frac = interactive and 1
				or (pin.idleAlpha or PinnedPanels.Settings.idleAlpha or 1)
			local a = math.Round(math.Clamp(frac, 0.05, 1) * 255)
			if pin.frame:GetAlpha() ~= a then pin.frame:SetAlpha(a) end
		end
	end
	hook.Run("PinnedPanels_InteractModeChanged", interactive)
end

local function SetInteractMode(on)
	if IM.Active == on then return end
	IM.Active = on
	gui.EnableScreenClicker(on)
	if on and PinnedPanels.RefreshRestoredGroups then
		PinnedPanels.RefreshRestoredGroups()
	end
	PinnedPanels.UpdatePanelStates()
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
	IM.SpawnMenuOpen = true
	SetInteractMode(false)
	PinnedPanels.UpdatePanelStates()
end)

hook.Add("OnSpawnMenuClose", "PinnedPanels_SpawnMenuClose", function()
	IM.SpawnMenuOpen = false
	PinnedPanels.UpdatePanelStates()
end)

hook.Add("PinnedPanels_StateChanged", "PinnedPanels_InteractSyncNew", function()
	PinnedPanels.UpdatePanelStates()
end)

surface.CreateFont("PP_InteractFont", { font = "DefaultBold", size = 14, weight = 600 })

local HUD_H = 24
local HUD_RT_W = 1024
local HUD_RT_H = 32
local hudMat = CreateMaterial("PinnedPanels_InteractHUD", "UnlitGeneric", {
	["$translucent"] = 1,
	["$vertexalpha"] = 1,
	["$vertexcolor"] = 1,
})
local hudW, hudKeyCode = -1, nil

local function RebuildHud(bw)
	hudW, hudKeyCode = bw, IM.KeyCode
	local keyName = (IM.KeyCode and IM.KeyCode ~= KEY_NONE) and input.GetKeyName(IM.KeyCode) or "?"
	local text = "INTERACT MODE  |  Drag title bar to move, drag bottom-right corner to resize  |  Press ["
		.. string.upper(keyName) .. "] to exit"

	local rt = GetRenderTarget("PinnedPanels_InteractHUD_RT", HUD_RT_W, HUD_RT_H)
	render.PushRenderTarget(rt)
	render.Clear(0, 0, 0, 0, true, true)
	cam.Start2D()
	draw.RoundedBox(6, 0, 0, bw, HUD_H, C.hudBg)
	surface.SetDrawColor(C.hudBorder)
	surface.DrawOutlinedRect(0, 0, bw, HUD_H, 1)
	draw.SimpleText(text, "PP_InteractFont", bw / 2, HUD_H / 2, C.hudText, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	cam.End2D()
	render.PopRenderTarget()

	hudMat:SetTexture("$basetexture", rt)
end

hook.Add("HUDPaint", "PinnedPanels_InteractHUD", function()
	if not IM.Active then return end
	local sw = ScrW()
	local bw = math.max(220, math.min(760, sw - 20))
	if hudW ~= bw or hudKeyCode ~= IM.KeyCode then RebuildHud(bw) end
	surface.SetMaterial(hudMat)
	surface.SetDrawColor(255, 255, 255, 255)
	surface.DrawTexturedRectUV(math.floor((sw - bw) / 2), 6, bw, HUD_H, 0, 0, bw / HUD_RT_W, HUD_H / HUD_RT_H)
end)

function PinnedPanels.OpenKeyBindFrame(opts)
	opts = opts or {}
	local getKey  = opts.get or function() return KEY_NONE end
	local setKey  = opts.set or function() end
	local onSaved = opts.onSaved

	if IsValid(PinnedPanels._bindFrame) then PinnedPanels._bindFrame:Remove() end

	local frame = vgui.Create("DFrame")
	frame:SetTitle(opts.title or "Bind Key")
	frame:SetSize(320, 180)
	frame:Center()
	frame:SetDraggable(true)
	frame:SetSizable(false)
	frame:SetDeleteOnClose(true)
	frame:MakePopup()
	PinnedPanels._bindFrame = frame

	frame.Paint = function(self, w, h)
		draw.RoundedBox(6, 0, 0, w, h, C.bindBg)
		draw.RoundedBoxEx(6, 0, 0, w, 24, C.bindHeader, true, true, false, false)
		surface.SetDrawColor(C.accent)
		surface.DrawRect(0, 22, w, 2)
	end

	local instrLabel = vgui.Create("DLabel", frame)
	instrLabel:SetText("Click the button below to listen for a key.\nEscape = cancel  |  Backspace = clear binding.")
	instrLabel:SetWrap(true)
	instrLabel:Dock(TOP)
	instrLabel:DockMargin(12, 10, 12, 8)
	instrLabel:SetTextColor(C.bindInstr)
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
			local code = getKey()
			local keyName = (code and code ~= KEY_NONE) and input.GetKeyName(code) or "None"
			self:SetText("Click to bind  (Current: " .. string.upper(keyName) .. ")")
		end
	end

	captureBtn.Paint = function(self, w, h)
		local focused = self:HasFocus()
		local hovered = self:IsHovered()
		local bgCol = (hovered or focused) and C.bindBtnBgHov or C.bindBtnBg
		draw.RoundedBox(6, 0, 0, w, h, bgCol)
		surface.SetDrawColor(C.accent)
		surface.DrawOutlinedRect(0, 0, w, h, focused and 2 or 1)
		local txtCol = focused and C.bindTxtFocus or C.bindTxtNorm
		draw.SimpleText(self:GetText(), "DermaDefaultBold", w / 2, h / 2, txtCol, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		return true
	end

	captureBtn.OnKeyCodePressed = function(self, keyCode)
		if keyCode == KEY_ESCAPE then
			frame:Close()
			return
		end
		setKey(keyCode == KEY_BACKSPACE and KEY_NONE or keyCode)
		if isfunction(onSaved) then onSaved() end
		frame:Close()
	end

	captureBtn.DoClick = function(self)
		self:RequestFocus()
	end
end
