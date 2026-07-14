local clientFiles = {
	"autorun/client/cl_pinnedpanels.lua",
	"pinnedpanels/colors.lua",
	"pinnedpanels/core.lua",
	"pinnedpanels/persistence.lua",
	"pinnedpanels/helpers.lua",
	"pinnedpanels/frame.lua",
	"pinnedpanels/popups.lua",
	"pinnedpanels/context_menu.lua",
	"pinnedpanels/pin.lua",
	"pinnedpanels/groups.lua",
	"pinnedpanels/autosize.lua",
	"pinnedpanels/content_tools.lua",
	"pinnedpanels/layout_editor.lua",
	"pinnedpanels/taskbar.lua",
	"pinnedpanels/browser.lua",
	"pinnedpanels/creation_browser.lua",
	"pinnedpanels/pinned_list.lua",
	"pinnedpanels/cursor_mode.lua",
	"pinnedpanels/keyboard.lua",
	"pinnedpanels/actions.lua",
	"pinnedpanels/command_palette.lua",
	"pinnedpanels/settings_tab.lua",
}

for _, filePath in ipairs(clientFiles) do
	AddCSLuaFile(filePath)
end