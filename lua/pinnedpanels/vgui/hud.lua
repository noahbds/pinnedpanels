-- The cursor-mode banner (§20.4): localized text cached until the mode, key or language changes (L8, B12, B19).

local PP = PinnedPanels
local Input, Settings, Theme = PP.Input, PP.Settings, PP.Theme

local BANNER_H, BANNER_Y, PAD = 24, 6, 32
local text, width

local function invalidate()
	text = nil
end

hook.Add("HUDPaint", "PinnedPanels.Hud", function()
	if not Input.cursorMode then return end
	if not text then
		local key = Settings.Get("keyCursor")
		local name = key ~= KEY_NONE and input.GetKeyName(key) or "?"
		text = PP.L("hud.banner", string.upper(name or "?"))
		surface.SetFont(Theme.FONT_BANNER)
		width = surface.GetTextSize(text) + PAD
	end
	local sw = ScrW()
	local w = math.min(width, sw - 20)
	local x = math.floor((sw - w) / 2)
	draw.RoundedBox(6, x, BANNER_Y, w, BANNER_H, Theme.hudBg)
	surface.SetDrawColor(Theme.hudBorder)
	surface.DrawOutlinedRect(x, BANNER_Y, w, BANNER_H, 1)
	draw.SimpleText(text, Theme.FONT_BANNER, sw / 2, BANNER_Y + BANNER_H / 2, Theme.hudText, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end)

hook.Add("PinnedPanelsSettingChanged", "PinnedPanels.Hud", function(key)
	if key == "keyCursor" then invalidate() end
end)
cvars.AddChangeCallback("gmod_language", invalidate, "PinnedPanels.Hud")
