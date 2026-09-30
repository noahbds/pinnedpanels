-- Loader (D12): the server only sends the client files (G1); the client includes them in order.
-- Files listed here must exist and be non-empty; order is load order.

local FILES = {
	"util.lua",
	"settings.lua",
	"storage.lua",
	"layout.lua",
	"input.lua",
	"sources.lua",
	"desktop.lua",
	"recipes.lua",
	"record.lua",
	"manage.lua",
	"embed.lua",
	"quick.lua",
	"actions.lua",
	"nav.lua",
	"nav_controls.lua",
	"vgui/theme.lua",
	"vgui/controls.lua",
	"vgui/tabs.lua",
	"vgui/crop_editor.lua",
	"vgui/window.lua",
	"vgui/hud.lua",
	"vgui/taskbar.lua",
	"vgui/hub.lua",
	"vgui/hub_catalog.lua",
	"vgui/hub_pinned.lua",
	"vgui/hub_layout.lua",
	"vgui/hub_settings.lua",
	"vgui/palette.lua",
	"vgui/picker.lua",
}

if SERVER then
	for _, path in ipairs(FILES) do
		AddCSLuaFile("pinnedpanels/" .. path)
	end
	return
end

PinnedPanels = PinnedPanels or {}
PinnedPanels.VERSION = "2.0"

for _, path in ipairs(FILES) do
	include("pinnedpanels/" .. path)
end

hook.Run("PinnedPanelsLoaded")
print("Pinned Panels " .. PinnedPanels.VERSION .. " loaded")
