-- ── English ─────────────────────────────────────────────────────────────
PinnedPanels      = PinnedPanels or {}
PinnedPanels.Lang = PinnedPanels.Lang or {}

PinnedPanels.Lang["en"] = {
	-- ── App shell ──
	app_title        = "Pinned Tool Panels",
	app_subtitle     = "Manage and customize your on-screen tool menus",
	pin_count_one    = "%d panel pinned",
	pin_count_many   = "%d panels pinned",
	tab_tools        = "Tools",
	tab_content      = "Content",
	tab_pinned       = "Pinned",
	tab_layout       = "Layout",
	tab_settings     = "Settings",

	-- ── Common buttons ──
	btn_ok           = "OK",
	btn_cancel       = "Cancel",
	btn_create       = "Create",
	btn_apply        = "Apply",
	btn_reset        = "Reset",
	btn_unbind       = "Unbind",
	btn_bind         = "Bind",
	btn_delete       = "Delete",
	btn_pin          = "Pin",
	btn_unpin        = "Unpin",
	btn_hide         = "Hide",
	btn_show         = "Show",
	btn_restore      = "Restore",

	-- ── Context menu ──
	ctx_group             = "Group",
	ctx_remove_from       = "Remove from \"%s\"",
	ctx_new_group         = "New Group...",
	ctx_ungroup_active    = "Ungroup Active Tab",
	ctx_unpin_active      = "Unpin Active Tab",
	ctx_unpin_all_group   = "Unpin All In Group",
	ctx_dissolve          = "Dissolve Group (keep panels)",
	ctx_idle_opacity      = "Idle Opacity",
	ctx_use_global        = "Use Global (%d%%)",
	ctx_custom            = "Custom...",
	custom_idle_title     = "Custom Idle Opacity",
	custom_idle_desc      = "Enter opacity in percent (10-100):",
	ctx_lock              = "Lock Position",
	ctx_unlock            = "Unlock Position",
	ctx_copy_pos          = "Copy Position",
	ctx_paste_pos         = "Paste Position",
	ctx_equip             = "Equip Tool: %s",
	ctx_bring_front       = "Bring to Front",
	ctx_minimize          = "Minimize to Taskbar",
	ctx_hide_panel        = "Hide Panel",
	ctx_autosize          = "Auto Size",
	ctx_edit_crop         = "Edit Crop...",
	ctx_crop_panel        = "Crop Panel...",
	ctx_remove_crop       = "Remove Crop",
	ctx_change_colors     = "Change Colors...",
	ctx_rename            = "Rename...",
	ctx_quick_key         = "Quick Key: [ %s ]",
	ctx_assign_quick      = "Assign Quick Key...",
	quick_key_title       = "Quick Key: %s",
	ctx_hide_filter       = "Hide Filter Bar",
	ctx_show_filter       = "Show Filter Bar",
	ctx_disable_ct        = "Disable Click-Through",
	ctx_clickthrough      = "Click-Through (Reference Mode)",
	clickthrough_notify   = "Panel now ignores the mouse. Hold ALT to use it, or re-enable via the command palette or keyboard nav (Shift+Enter).",
	ctx_unpin             = "Unpin",

	-- ── Taskbar ──
	tb_restore     = "Restore",
	tb_restore_all = "Restore All",
	tb_unpin       = "Unpin",

	-- ── Layout editor ──
	layout_info    = "Drag boxes to reposition panels. Drag any edge or corner to resize. Right-click for options. Grouped panels have a highlighted border and member badge. Changes apply live.",
	layout_screen  = "SCREEN",
	layout_cropped = "CROPPED",
	layout_taskbar = "TASKBAR",
	layout_more    = "+%d more",
	layout_empty   = "No pinned panels. Pin tools from the Tools tab.",

	-- ── Key bind frame ──
	bind_key_title     = "Bind Key",
	bind_instr         = "Click the button below to listen for a key.\nEscape = cancel  |  Backspace = clear binding.",
	bind_press_key     = ">> Press a key <<",
	bind_click_current = "Click to bind  (Current: %s)",
	key_none           = "None",

	-- ── Pinned list ──
	kind_group        = "Group",
	kind_frame        = "Frame",
	kind_content      = "Content",
	kind_tool         = "Tool",
	group_panels      = "(%d panels)",
	layout_badge      = "[ %d panels ]",
	tag_minimized     = "[minimized]",
	tip_hide_panel    = "Hide panel",
	tip_show_panel    = "Show panel",
	tip_restore_tb    = "Restore from taskbar",
	member_missing    = "%s (missing)",
	btn_move_front    = "Move to Front",
	tip_move_front    = "Bring to front",
	btn_dissolve      = "Dissolve",
	tip_dissolve      = "Dissolve group and restore individual panels",
	btn_unpin_all_s   = "Unpin All",
	tip_unpin_all_g   = "Unpin every panel in this group (the empty group is kept)",
	btn_members       = "Members",
	tip_members       = "Show / hide the member list to reorder or remove panels",
	tip_unpin_simple  = "Unpin",
	btn_group         = "Group",
	tip_add_group     = "Add this panel to a group",
	tip_unpin_member  = "Unpin this panel",
	btn_ungroup       = "Ungroup",
	tip_ungroup_mem   = "Remove from group (panel stays pinned)",
	tip_move_down     = "Move down (tab order)",
	tip_move_up       = "Move up (tab order)",

	-- ── Tool browser ──
	search_tools   = "Search tools...",
	no_tools       = "No tools found.",
	tip_pin        = "Pin this tool to screen",
	tip_unpin      = "Remove this tool from screen",
	count_tools    = "%d tools",

	-- ── Groups ──
	group_no_cp       = "No control panel available.",
	new_group_title   = "New Group",
	new_group_desc    = "Enter a name for the new group:",

	-- ── Creation browser ──
	creation_info  = "Pin GMod's built-in content browsers as floating panels — props, entities, NPCs, saves, and more. Requires the sandbox gamemode.",
	creation_none  = "No creation tabs found. Make sure you are playing on a sandbox-based gamemode.",

	-- ── Content tools ──
	filter_controls = "Filter controls…",

	-- ── Pin (no control panel) ──
	pin_no_cp = "This tool has no control panel.",

	-- ── Command palette ──
	palette_search       = "Search tools, panels & actions…",
	palette_nav          = "Up / Down: navigate    Enter: run    Esc: close",
	palette_no_matches   = "No matches.",
	palette_results      = "%d results",
	palette_results_of   = "%d of %d results",
	cat_action           = "Action",
	cat_pinned           = "Pinned",
	cat_tool             = "Tool",
	cat_content          = "Content",
	act_toggle_cursor    = "Toggle Cursor Mode",
	act_auto_arrange     = "Auto-Arrange Panels",
	act_auto_size_all    = "Auto-Size All Panels",
	act_reopen           = "Reopen Last Closed Panel",
	act_restore_all      = "Restore All Minimized",
	act_unpin_all        = "Unpin All Panels",
	act_restore_inter    = "Restore Interaction: %s",
	sub_show_cursor      = "Show cursor to interact",
	sub_tile_visible     = "Tile visible panels",
	sub_fit_content      = "Fit every panel to its content",
	sub_undo_unpin       = "Undo the last unpin",
	sub_bring_back       = "Bring back minimized panels",
	sub_remove_every     = "Remove every pinned panel",
	sub_disable_ct       = "Disable click-through",
	sub_show_front       = "Show / bring to front",
	sub_content_browser  = "Content browser",

	-- ── Settings: page names ──
	page_general    = "General",
	page_controls   = "Controls",
	page_appearance = "Appearance",
	page_taskbar    = "Taskbar",
	page_groups     = "Groups",
	page_data       = "Backup & Data",

	-- ── Settings: General ──
	card_behavior     = "Behavior",
	opt_autorestore   = "Auto-restore pinned panels when joining the server",
	opt_kbnav_outside = "Allow keyboard navigation outside cursor mode",
	opt_idle_alpha    = "Panel opacity outside cursor mode (%)",
	card_snapping     = "Window Snapping",
	opt_snap          = "Snap panels to screen edges and each other while dragging (hold Alt to bypass)",
	opt_snap_dist     = "Snap distance (px)",

	-- ── Settings: Controls ──
	card_cursor_mode  = "Cursor Mode (Cursor Toggle)",
	help_cursor_mode  = "Press your bound key in-game to show the cursor and freely interact with your pinned panels. The spawn menu always enables interaction while open.",
	bind_interact     = "Bind Interact Key",
	btn_toggle_now    = "Toggle Now",
	card_peek         = "Peek (Hold to Reveal)",
	help_peek         = "Hold this key to temporarily show every panel — hidden, minimized or faded — at full opacity. Release to put everything back.",
	bind_peek         = "Bind Peek Key",
	card_palette      = "Command Palette",
	help_palette      = "Open a searchable list of every tool, content browser, pinned panel and action. Bind a key to open it anywhere in-game.",
	bind_palette      = "Bind Command Palette",
	btn_open_now      = "Open Now",
	card_kbnav        = "Keyboard Navigation",
	help_kbnav        = "Shortcuts work while cursor mode is on, and can also be enabled globally from General. The focused panel is outlined; cycle focus, switch group tabs, or equip the focused tool.",
	key_not_bound     = "Not bound",
	bind_prefix       = "Bind: %s",
	btn_reset_all_def = "Reset All to Default",

	-- ── Settings: Appearance ──
	card_panel_colors = "Panel Colors",
	color_panel_bg    = "Panel Background",
	color_header_bar  = "Header Bar",
	color_header_text = "Header Text",
	btn_reset_default = "Reset to Default",
	card_live_preview = "Live Preview",
	preview_title     = "Example Panel Title",
	preview_hint      = "(this is how your pinned panels will look)",

	-- ── Settings: Taskbar ──
	card_taskbar        = "Taskbar",
	opt_taskbar_enable  = "Enable taskbar (minimized panels appear in a bar)",
	lbl_position        = "Position:",
	pos_bottom          = "Bottom",
	pos_top             = "Top",
	pos_left            = "Left",
	pos_right           = "Right",
	opt_bar_thickness   = "Bar thickness (px)",
	opt_reveal_hover    = "Reveal on hover (collapse until the cursor is near the bar)",
	opt_show_labels     = "Show text labels on entries",
	card_taskbar_colors = "Taskbar Colors",
	color_background    = "Background",
	color_text          = "Text",
	color_accent        = "Accent",
	taskbar_color_pfx   = "Taskbar: %s",
	btn_reset_taskbar   = "Reset Taskbar to Default",

	-- ── Settings: Groups ──
	card_panel_groups = "Panel Groups",
	help_groups       = "Grouped panels merge into one tabbed window. Create groups here or via right-click on panel headers.",
	groups_none       = "No groups yet.",
	group_row_count   = "%s (%d panels)",

	-- ── Settings: Backup & Data ──
	card_backup     = "Backup & Sharing",
	help_backup     = "Export your current layout (panels + groups) to a shareable code, or paste a code to import. Importing replaces your current layout.",
	btn_export      = "Export Layout...",
	btn_import      = "Import Layout...",
	export_title    = "Export Layout",
	import_title    = "Import Layout",
	export_nothing  = "Nothing to export yet.",
	import_success  = "Layout imported successfully.",
	import_failed   = "Import failed: %s",
	card_danger     = "Danger Zone",
	btn_unpin_all   = "Unpin All Panels",

	-- ── Settings: widgets ──
	current_key_none  = "Current key: [ Not bound ]",
	current_key       = "Current key: [ %s ]",
	btn_import_reload = "Import & Reload",
	code_hint         = "Copy this code (Ctrl+C) and share it.",

	-- ── Color changer popup ──
	color_popup_title  = "Panel Colors: %s",
	nav_hint_popup     = "Arrows: move / adjust   Enter: select   Backspace: back",
	color_bg           = "Background",
	color_header       = "Header",
	color_text_swatch  = "Text",
	btn_reset_global   = "Reset All to Global",

	-- ── Rename popup ──
	rename_title = "Rename Panel",
	rename_desc  = "Enter a custom name for this pinned panel:",

	-- ── Empty pinned list ──
	no_pinned      = "No Pinned Panels",
	no_pinned_desc = "You have no valid pinned panels right now.",
	no_pinned_hint = "Pin tools from the 'Tools' tab, or content browsers from the 'Content' tab.",

	-- ── Frame nav hints ──
	nav_hint_panel     = "Backspace: back | Enter: use | Arrows: move | Shift+Enter: context menu",
	nav_hint_hue       = "Arrows: Hue | Enter or Backspace: done",
	nav_hint_alpha     = "Arrows: Alpha | Enter or Backspace: done",
	nav_hint_satval    = "Arrows: Saturation / Value | Enter or Backspace: done",
	nav_hint_huevalue  = "Arrows: Hue / Value | Shift+Arrows: Saturation / Alpha | Enter or Backspace: done",
	nav_hint_slider    = "Left / Right: adjust | Enter or Backspace: done",
	clickthrough_bar   = "click-through · hold ALT to use · right-click for menu",

	-- ── Crop editor ──
	crop_hint = "Drag edges · move inside · draw in dark area · right-click cancels",
	crop_full = "Full",

	-- ── Keybind names (Controls page) ──
	kb_focus_next   = "Focus Next Panel",
	kb_focus_prev   = "Focus Previous Panel",
	kb_tab_next     = "Next Tab (Group)",
	kb_tab_prev     = "Previous Tab (Group)",
	kb_enter_nav    = "Enter Panel Content Nav",
	kb_equip_tool   = "Equip Focused Tool",
	kb_toggle_hide  = "Hide / Show Focused",
	kb_bring_front  = "Bring Focused To Front",
	kb_minimize     = "Minimize Focused (Taskbar)",
	kb_maximize     = "Maximize Focused (Fill Screen)",
	kb_unpin        = "Unpin Focused",
	kb_auto_arrange = "Auto-Arrange Panels",
	kb_autosize     = "Auto-Size Focused",
	kb_reopen       = "Reopen Last Closed",

	-- ── Key conflict dialog ──
	conflict_game_bind   = "Game bind: %s",
	conflict_cursor      = "PinnedPanels: Cursor Mode key",
	conflict_peek        = "PinnedPanels: Peek key",
	conflict_palette     = "PinnedPanels: Command Palette key",
	conflict_bind        = "PinnedPanels: %s",
	conflict_query       = "[ %s ] is already used by:\n\n- %s\n\nEverything bound to this key will trigger together.\nBind it anyway?",
	conflict_title       = "Key Already In Use",
	conflict_bind_anyway = "Bind Anyway",
	btn_change_key       = "Change Key...",

	-- ── Import errors ──
	import_empty   = "Empty import string.",
	import_decode  = "Could not decode string.",
	import_corrupt = "Corrupt or invalid data.",
	import_invalid = "Not a valid layout.",

	-- ── Misc ──
	frame_default = "Frame %s",
}
