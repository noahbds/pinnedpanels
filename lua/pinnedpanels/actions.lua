-- The action list (§18): each command is declared once and feeds the window, tab and taskbar menus, the
-- palette, key settings (pinnedpanels_key_<id>) and a console command (pinnedpanels_<id> [windowId]).

local PP = PinnedPanels
PP.Actions = PP.Actions or {}
local Actions = PP.Actions
local Layout, Sources, Input, Settings, Storage, Desktop = PP.Layout, PP.Sources, PP.Input, PP.Settings, PP.Storage, PP.Desktop
-- PP.Dialogs and PP.CropEditor come from vgui files loaded later; they are looked up when an action runs.

Actions.list = {}
Actions.byId = {}

-- ── Declaration ─────────────────────────────────────────────
-- def = {
--   id, scope = "global" | "window" | "tab", icon,
--   label = "loc.key" | function(ctx) → text,   name = "loc.key" (context-free, for Controls and conflicts)
--   menu = { group, window = order?, tab = order?, taskbar = order? },
--   palette = true?, sub = "loc.key"? (palette subtitle), bindable = true?, key = default,
--   visible(ctx)?, enabled(ctx)?, children(ctx) → { { text, icon?, run, enabled? } | { spacer = true } }?,
--   run(ctx), release(ctx)? (bindable keys only),
--   managed = true? (also offered for managed windows, which are other addons' windows, §33.4),
-- }
-- ctx = { id, window, index, tab, menu = "window" | "tab" | "taskbar" | nil }
-- icon may also be function(ctx) → path, for toggles whose icon shows their state (menus only).

function Actions.Add(def)
	Actions.byId[def.id] = def
	Actions.list[#Actions.list + 1] = def
	if def.bindable then
		def.setting = "key" .. def.id:gsub("^%l", string.upper)
		Settings.Add(def.setting, { type = "key", default = def.key or KEY_NONE, page = "controls", action = def.id })
	end
	concommand.Add("pinnedpanels_" .. def.id, function(_, _, args) Actions.Run(def.id, args[1]) end)
end

local function context(id, index, menu)
	local rec = id and Layout.Get(id)
	if not rec then return nil end
	index = index or rec.active
	return { id = rec.id, window = rec, index = index, tab = rec.tabs[index], menu = menu }
end

local function text(v, ctx)
	if isfunction(v) then return v(ctx) end
	return PP.L(v)
end

function Actions.Name(def)
	return PP.L(def.name or def.label)
end

local function available(def, ctx)
	if def.scope ~= "global" and not ctx then return false end
	if def.scope == "tab" and not ctx.tab then return false end
	if ctx and ctx.window.kind == "managed" and not def.managed then return false end
	return not def.visible or def.visible(ctx) == true
end

local function allowed(def, ctx)
	return available(def, ctx) and (not def.enabled or def.enabled(ctx) == true)
end

-- Runs an action for a window (default: the focused one) and tab index (default: its active tab).
function Actions.Run(id, windowId, index)
	local def = Actions.byId[id]
	local ctx
	if def.scope ~= "global" then
		ctx = context(windowId or Desktop.focused, index)
		if not ctx then
			print("[Pinned Panels] " .. id .. ": no window. Click one first or pass its id (pinnedpanels_list).")
			return
		end
	end
	if allowed(def, ctx) then def.run(ctx) end
end

-- ── Menus ───────────────────────────────────────────────────
-- Real DMenus built from the list (G17), so the keyboard can drive the same menus later (§19.5).

local function addChildren(menu, items)
	for _, item in ipairs(items) do
		if item.spacer then
			menu:AddSpacer()
		else
			local o = menu:AddOption(item.text, item.run)
			if item.icon then o:SetIcon(item.icon) end
			if item.enabled == false then o:SetEnabled(false) end
		end
	end
end

local function fill(menu, where, ctx)
	local defs = {}
	for _, def in ipairs(Actions.list) do
		if def.menu and def.menu[where] and available(def, ctx) then defs[#defs + 1] = def end
	end
	table.sort(defs, function(a, b) return a.menu[where] < b.menu[where] end)

	local group
	for _, def in ipairs(defs) do
		if group and def.menu.group ~= group then menu:AddSpacer() end
		group = def.menu.group
		local label = text(where == "taskbar" and def.taskbarLabel or def.label, ctx)
		local option
		if def.children then
			local sub
			sub, option = menu:AddSubMenu(label)
			addChildren(sub, def.children(ctx))
		else
			option = menu:AddOption(label, function() def.run(ctx) end)
			if def.enabled and not def.enabled(ctx) then option:SetEnabled(false) end
		end
		local icon = def.icon
		if isfunction(icon) then icon = icon(ctx) end
		if icon then option:SetIcon(icon) end
	end
end

local function open(where, ctx)
	local menu = DermaMenu()
	fill(menu, where, ctx)
	menu:Open()
	return menu
end

function Actions.OpenWindowMenu(id)
	local ctx = context(id, nil, "window")
	if ctx then return open("window", ctx) end
end

function Actions.OpenTabMenu(id, index)
	local ctx = context(id, index, "tab")
	if ctx then return open("tab", ctx) end
end

-- One action's submenu on its own, e.g. the Pinned page's "Group" button.
function Actions.OpenChildren(actionId, id)
	local def, ctx = Actions.byId[actionId], context(id, nil, "window")
	if not ctx or not available(def, ctx) then return end
	local menu = DermaMenu()
	addChildren(menu, def.children(ctx))
	menu:Open()
	return menu
end

function Actions.OpenTaskbarMenu(id)
	local ctx = context(id, nil, "taskbar")
	if ctx then return open("taskbar", ctx) end
end

-- ── Keys ────────────────────────────────────────────────────

-- Everything a key is already used for (§18.4): its game bind, our actions and quick keys. F-keys also
-- get a warning that their game bind can't be blocked (G6).
function Actions.Conflicts(key, exceptTag)
	local out = {}
	if not key or key == KEY_NONE then return out end
	local bind = input.LookupKeyBinding(key)
	if isstring(bind) and bind ~= "" then
		out[#out + 1] = PP.L("conflict.game_bind", bind)
		if key >= KEY_F1 and key <= KEY_F12 then out[#out + 1] = PP.L("conflict.fkey") end
	end
	for _, def in ipairs(Actions.list) do
		if def.setting and Settings.Get(def.setting) == key and exceptTag ~= "action:" .. def.id then
			out[#out + 1] = PP.L("conflict.bind", Actions.Name(def))
		end
	end
	for _, rec in ipairs(Layout.Windows()) do
		if rec.quickKey == key and exceptTag ~= "quick:" .. rec.id then
			out[#out + 1] = PP.L("conflict.quick", Layout.Title(rec))
		end
	end
	for _, name in ipairs(Settings.order) do
		local def = Settings.defs[name]
		if def.section == "nav" and Settings.Get(name) == key and exceptTag ~= "setting:" .. name then
			out[#out + 1] = PP.L("conflict.nav", PP.L(def.label))
		end
	end
	return out
end

-- A quick key shows or minimizes one window (F21).
local function toggleWindow(id)
	local rec = Layout.Get(id)
	if not rec then return end
	if Desktop.held[id] or rec.state == "minimized" then
		Desktop.RestoreAndFront(id)
	else
		Layout.Minimize(id)
	end
end

local quickBound = {}

function Actions.BindKeys()
	for _, def in ipairs(Actions.list) do
		if def.setting then
			Input.SetKey("action:" .. def.id, Settings.Get(def.setting), function() Actions.Run(def.id) end,
				def.release and function() def.release() end)
		end
	end
	local bound = {}
	for _, rec in ipairs(Layout.Windows()) do
		if rec.quickKey then
			local id = rec.id
			bound[id] = true
			Input.SetKey("quick:" .. id, rec.quickKey, function() toggleWindow(id) end)
		end
	end
	for id in pairs(quickBound) do
		if not bound[id] then Input.SetKey("quick:" .. id, nil) end
	end
	quickBound = bound
end

hook.Add("PinnedPanelsSettingChanged", "PinnedPanels.Actions", function(key)
	if key:sub(1, 3) == "key" then Actions.BindKeys() end
end)

hook.Add("PinnedPanelsChanged", "PinnedPanels.Actions", function(kind)
	if kind == "windows" or kind == "style" then Actions.BindKeys() end
end)

-- ── Helpers for the declarations ────────────────────────────

local function isMulti(ctx) return #ctx.window.tabs > 1 end
local function notLocked(ctx) return not ctx.window.locked end
-- Tabs built from a function, which a rebuild runs again (E10); content tabs and adopted panels aren't.
local REBUILDABLE = { tool = true, postprocess = true, active = true }
local function rebuildable(ctx) return REBUILDABLE[ctx.tab.src:match("^(%a+):")] == true end
local function tabTitle(ctx) return Layout.TabTitle(ctx.tab) end

local function host(ctx)
	local win = Desktop.panels[ctx.id]
	return IsValid(win) and win.hosts[ctx.tab.src] or nil
end

local function autosize(id)
	local win = Desktop.panels[id]
	if IsValid(win) then win:AutoSize() end
end

-- ── Global ──────────────────────────────────────────────────

-- F-keys can't be blocked (G6): where the gamemode opens its own menu with F4, the cursor key starts
-- unbound and the player is told at each join until one is chosen (D37).
local function cursorKey()
	if engine.ActiveGamemode() ~= "sandbox" and input.LookupKeyBinding(KEY_F4) == "gm_showspare2" then return KEY_NONE end
	return KEY_F4
end

hook.Add("InitPostEntity", "PinnedPanels.Actions", function()
	if cursorKey() == KEY_NONE and Settings.Get("keyCursor") == KEY_NONE then
		notification.AddLegacy(PP.L("notify.cursor_unbound"), NOTIFY_HINT, 10)
	end
end)

Actions.Add({
	id = "cursor", scope = "global", icon = "icon16/cursor.png", label = "act.toggle_cursor",
	sub = "sub.show_cursor", palette = true, bindable = true, key = cursorKey(),
	run = function() Input.SetCursorMode(not Input.cursorMode) end,
})

Actions.Add({
	id = "palette", scope = "global", icon = "icon16/application_view_list.png", label = "card.palette", bindable = true,
	run = function() PP.Palette.Toggle() end,
})

Actions.Add({
	id = "peek", scope = "global", icon = "icon16/eye.png", label = "card.peek", bindable = true,
	run = function() Desktop.Peek(true) end,
	release = function() Desktop.Peek(false) end,
})

Actions.Add({
	id = "arrange", scope = "global", icon = "icon16/application_tile_horizontal.png", label = "act.auto_arrange",
	name = "kb.auto_arrange", sub = "sub.tile_visible", palette = true, bindable = true,
	-- Not the windows that aren't on screen (hidden, or waiting for their addon's window): they would
	-- take room from those that are.
	run = function()
		local how, minimized = Layout.Arrange(function(win) return Desktop.held[win.id] or Desktop.IsDormant(win) end)
		-- Said when windows were changed to make them fit, since nothing else tells why they shrank.
		if minimized > 0 then
			notification.AddLegacy(PP.L("arrange.minimized", minimized), NOTIFY_HINT, 8)
		elseif how == "grid" then
			notification.AddLegacy(PP.L("arrange.grid"), NOTIFY_HINT, 6)
		end
	end,
})

Actions.Add({
	id = "autosize_all", scope = "global", icon = "icon16/arrow_inout.png", label = "act.auto_size_all",
	sub = "sub.fit_content", palette = true, bindable = true,
	run = function()
		for id, win in pairs(Desktop.panels) do
			if win:IsVisible() then autosize(id) end
		end
	end,
})

Actions.Add({
	id = "reopen", scope = "global", icon = "icon16/arrow_undo.png", label = "act.reopen", name = "kb.reopen",
	sub = "sub.undo_unpin", palette = true, bindable = true,
	visible = function() return #Layout.closed > 0 end,
	run = function()
		local id = Layout.Reopen()
		if id then Desktop.Front(id) end
	end,
})

-- Layout undo and redo (FF10): moves, resizes, unpins, merges, crops and the rest, 50 steps back.
Actions.Add({
	id = "undo", scope = "global", icon = "icon16/arrow_rotate_anticlockwise.png", label = "act.undo",
	sub = "sub.undo", palette = true, bindable = true,
	visible = function() return Layout.CanUndo() end,
	run = function() Layout.Undo() end,
})

Actions.Add({
	id = "redo", scope = "global", icon = "icon16/arrow_rotate_clockwise.png", label = "act.redo",
	sub = "sub.redo", palette = true, bindable = true,
	visible = function() return Layout.CanRedo() end,
	run = function() Layout.Redo() end,
})

Actions.Add({
	id = "restore_all", scope = "global", icon = "icon16/application_get.png", label = "act.restore_all",
	taskbarLabel = "tb.restore_all", menu = { group = "taskbar", taskbar = 2 }, sub = "sub.bring_back", palette = true, bindable = true,
	run = function()
		for _, rec in ipairs(Layout.Windows()) do Layout.Restore(rec.id) end
	end,
})

Actions.Add({
	id = "pick", scope = "global", icon = "icon16/application_form_add.png", label = "act.pick",
	sub = "sub.pick", palette = true, bindable = true,
	run = function() PP.Picker.Open() end,
})

Actions.Add({
	id = "record", scope = "global", icon = "icon16/bullet_red.png", label = "act.record",
	sub = "sub.record", palette = true, bindable = true,
	run = function() PP.Record.Toggle() end,
})

Actions.Add({
	id = "unpin_all", scope = "global", icon = "icon16/cross.png", label = "act.unpin_all", sub = "sub.remove_every", palette = true,
	-- Asks first when there are more than a few (Batch.Unpin).
	run = function() PP.Batch.Unpin(PP.Batch.All()) end,
})

-- ── Window: tool ────────────────────────────────────────────

Actions.Add({
	id = "equip", scope = "tab", icon = "icon16/wrench.png", name = "kb.equip_tool", bindable = true,
	label = function(ctx) return PP.L("ctx.equip", tabTitle(ctx)) end,
	menu = { group = "tool", window = 10, tab = 10 },
	visible = function(ctx) return Sources.CanEquip(ctx.tab.src) end,
	run = function(ctx) Sources.Equip(ctx.tab.src) end,
})

-- ── Window: view ────────────────────────────────────────────

Actions.Add({
	id = "restore", scope = "window", managed = true, icon = "icon16/arrow_up.png", label = "btn.restore",
	taskbarLabel = "tb.restore", menu = { group = "taskbar", taskbar = 1 },
	run = function(ctx) Desktop.RestoreAndFront(ctx.id) end,
})

Actions.Add({
	id = "front", scope = "window", managed = true, icon = "icon16/arrow_up.png", label = "ctx.bring_front", name = "kb.bring_front",
	menu = { group = "view", window = 20 }, bindable = true,
	run = function(ctx) Desktop.RestoreAndFront(ctx.id) end,
})

Actions.Add({
	id = "minimize", scope = "window", managed = true, icon = "icon16/application_put.png", label = "ctx.minimize", name = "kb.minimize",
	menu = { group = "view", window = 21 }, bindable = true,
	run = function(ctx) Layout.Minimize(ctx.id) end,
})

Actions.Add({
	id = "maximize", scope = "window", icon = "icon16/application_double.png", label = "kb.maximize", bindable = true,
	enabled = notLocked,
	run = function(ctx) Layout.ToggleMaximize(ctx.id) end,
})

-- Rolled up to its header (FF6); double-clicking the header does the same.
Actions.Add({
	id = "roll", scope = "window", icon = "icon16/arrow_in.png", name = "kb.roll", bindable = true,
	label = function(ctx) return PP.L(ctx.window.state == "rolled" and "ctx.unroll" or "ctx.roll") end,
	menu = { group = "view", window = 22 },
	enabled = function(ctx) return ctx.window.state == "normal" or ctx.window.state == "rolled" end,
	run = function(ctx) Layout.ToggleRoll(ctx.id) end,
})

-- Only while the C menu is open (FF5), like GMod's own tool panel there.
Actions.Add({
	id = "context_menu", scope = "window", managed = true, name = "ctx.with_context",
	icon = function(ctx) return ctx.window.showWith and "icon16/tick.png" or "icon16/application_view_icons.png" end,
	label = "ctx.with_context", menu = { group = "view", window = 24 },
	run = function(ctx) Layout.SetShowWith(ctx.id, not ctx.window.showWith and "contextmenu" or nil) end,
})

-- ── Window: size and content ────────────────────────────────

Actions.Add({
	id = "autosize", scope = "window", icon = "icon16/arrow_inout.png", label = "ctx.autosize", name = "kb.autosize",
	menu = { group = "size", window = 30 }, bindable = true,
	run = function(ctx) autosize(ctx.id) end,
})

Actions.Add({
	id = "crop", scope = "tab", icon = "icon16/shape_handles.png",
	label = function(ctx) return PP.L(ctx.tab.crop and "ctx.edit_crop" or "ctx.crop_panel") end,
	name = "ctx.crop_panel", menu = { group = "size", window = 31, tab = 31 },
	run = function(ctx) PP.CropEditor.Open(ctx.id, ctx.index) end,
})

Actions.Add({
	id = "uncrop", scope = "tab", icon = "icon16/shape_square_delete.png", label = "ctx.remove_crop",
	menu = { group = "size", window = 32, tab = 32 },
	visible = function(ctx) return ctx.tab.crop ~= nil end,
	run = function(ctx)
		local c, rec = ctx.tab.crop, ctx.window
		Layout.SetCrop(ctx.id, ctx.index, nil)
		if ctx.index == rec.active and rec.state ~= "maximized" then
			Layout.SetGeometry(ctx.id, rec.x, rec.y, rec.w + c.l + c.r, rec.h + c.t + c.b, true)
		end
	end,
})

Actions.Add({
	id = "rebuild", scope = "tab", icon = "icon16/arrow_refresh.png", label = "ctx.rebuild",
	menu = { group = "size", window = 33, tab = 33 },
	visible = function(ctx) return rebuildable(ctx) and host(ctx) ~= nil end,
	run = function(ctx) host(ctx):Rebuild() end,
})

-- ── Window: style ───────────────────────────────────────────

Actions.Add({
	id = "colors", scope = "window", icon = "icon16/color_wheel.png", label = "ctx.change_colors",
	menu = { group = "style", window = 40 },
	run = function(ctx) PP.Dialogs.Colors(ctx.id) end,
})

Actions.Add({
	id = "rename", scope = "window", icon = "icon16/textfield_rename.png", label = "ctx.rename",
	menu = { group = "style", window = 41 },
	run = function(ctx)
		local rec = ctx.window
		PP.Dialogs.Text(PP.L("rename.title"), PP.L("rename.desc"), Layout.Title(rec), function(title)
			Layout.Rename(ctx.id, nil, title)
		end)
	end,
})

Actions.Add({
	id = "rename_tab", scope = "tab", icon = "icon16/textfield_rename.png", label = "ctx.rename",
	menu = { group = "style", tab = 41 },
	run = function(ctx)
		PP.Dialogs.Text(PP.L("rename.title"), PP.L("rename.desc"), tabTitle(ctx), function(title)
			Layout.Rename(ctx.id, ctx.index, title)
		end)
	end,
})

Actions.Add({
	id = "quick_key", scope = "window", managed = true, icon = "icon16/lightning.png", name = "ctx.assign_quick",
	label = function(ctx)
		local key = ctx.window.quickKey
		if not key then return PP.L("ctx.assign_quick") end
		return PP.L("ctx.quick_key", string.upper(input.GetKeyName(key) or "?"))
	end,
	menu = { group = "style", window = 42 },
	run = function(ctx)
		PP.Dialogs.Key({
			title = PP.L("quick.key_title", Layout.Title(ctx.window)),
			get = function() return (Layout.Get(ctx.id) or {}).quickKey or KEY_NONE end,
			set = function(key) Layout.SetQuickKey(ctx.id, key) end,
			tag = "quick:" .. ctx.id,
		})
	end,
})

Actions.Add({
	id = "filter", scope = "window", name = "ctx.show_filter",
	icon = function(ctx) return ctx.window.filterBar and "icon16/zoom_out.png" or "icon16/zoom.png" end,
	label = function(ctx) return PP.L(ctx.window.filterBar and "ctx.hide_filter" or "ctx.show_filter") end,
	menu = { group = "style", window = 43 },
	run = function(ctx) Layout.SetFilterBar(ctx.id, not ctx.window.filterBar) end,
})

-- Another addon's panel that isn't a text field (an editor, say) can take the keyboard when clicked
-- (§33.5, §33.6), embedded or managed.
Actions.Add({
	id = "needs_keyboard", scope = "tab", managed = true, name = "ctx.needs_keyboard", label = "ctx.needs_keyboard",
	icon = function(ctx) return ctx.tab.adopt.needsKeyboard and "icon16/tick.png" or "icon16/keyboard.png" end,
	menu = { group = "style", window = 45, tab = 45 },
	visible = function(ctx) return ctx.tab.adopt ~= nil end,
	run = function(ctx) Layout.SetAdopt(ctx.id, ctx.index, { needsKeyboard = not ctx.tab.adopt.needsKeyboard }) end,
})

-- A pin that comes back with a command the player allowed has it run at join (D41), unless this is
-- turned off: it is the one opener that runs without a click.
Actions.Add({
	id = "auto_open", scope = "tab", managed = true, name = "ctx.auto_open", label = "ctx.auto_open",
	icon = function(ctx) return PP.Recipes.AutoOpens(ctx.tab.adopt) and "icon16/tick.png" or "icon16/application_go.png" end,
	menu = { group = "style", window = 46, tab = 46 },
	visible = function(ctx)
		local a = ctx.tab.adopt
		return a ~= nil and a.recipe.kind == "command" and a.recipe.confirmed == true
	end,
	run = function(ctx) Layout.SetAdopt(ctx.id, ctx.index, { autoOpen = not PP.Recipes.AutoOpens(ctx.tab.adopt), autoFails = 0 }) end,
})

-- ── Window: groups (F15) ────────────────────────────────────

-- Merges every tab of fromId into toId, in order; fromId disappears unless it is a named group.
local function mergeInto(fromId, toId)
	local from = Layout.Get(fromId)
	while from and #from.tabs > 0 and Layout.Get(fromId) do
		if not Layout.MoveTab(fromId, 1, toId) then break end
	end
end

Actions.Add({
	id = "group", scope = "window", icon = "icon16/folder.png", label = "ctx.group",
	menu = { group = "group", window = 50 },
	visible = function(ctx) return not isMulti(ctx) end,
	children = function(ctx)
		local items = {}
		for _, rec in ipairs(Layout.Windows()) do
			if rec.id ~= ctx.id and (rec.title or #rec.tabs > 1) then
				local id = rec.id
				items[#items + 1] = { text = PP.L("group.row_count", Layout.Title(rec), #rec.tabs), icon = "icon16/folder_go.png",
					run = function() mergeInto(ctx.id, id) end }
			end
		end
		if #items > 0 then items[#items + 1] = { spacer = true } end
		items[#items + 1] = { text = PP.L("ctx.new_group"), icon = "icon16/folder_add.png", run = function()
			PP.Dialogs.Text(PP.L("new.group_title"), PP.L("new.group_desc"), "", function(name)
				local g = Layout.NewGroup(name)
				if g then mergeInto(ctx.id, g) end
			end, "btn.create")
		end }
		return items
	end,
})

Actions.Add({
	id = "move_out", scope = "tab", icon = "icon16/folder_go.png",
	label = function(ctx)
		if ctx.menu == "tab" then return PP.L("tab.move_out") end
		return PP.L("ctx.ungroup_active") .. " (" .. tabTitle(ctx) .. ")"
	end,
	name = "tab.move_out", menu = { group = "group", window = 51, tab = 51 },
	visible = isMulti,
	run = function(ctx)
		local id = Layout.MoveTab(ctx.id, ctx.index, nil)
		if id then Desktop.Front(id) end
	end,
})

Actions.Add({
	id = "move_left", scope = "tab", icon = "icon16/arrow_left.png", label = "tab.move_left",
	menu = { group = "group", tab = 52 },
	visible = function(ctx) return ctx.index > 1 end,
	run = function(ctx) Layout.MoveTab(ctx.id, ctx.index, ctx.id, ctx.index - 1) end,
})

Actions.Add({
	id = "move_right", scope = "tab", icon = "icon16/arrow_right.png", label = "tab.move_right",
	menu = { group = "group", tab = 53 },
	visible = function(ctx) return ctx.index < #ctx.window.tabs end,
	run = function(ctx) Layout.MoveTab(ctx.id, ctx.index, ctx.id, ctx.index + 1) end,
})

Actions.Add({
	id = "unpin_tab", scope = "tab", icon = "icon16/tab_delete.png",
	label = function(ctx)
		if ctx.menu == "tab" then return PP.L("ctx.unpin") end
		return PP.L("ctx.unpin_active") .. " (" .. tabTitle(ctx) .. ")"
	end,
	name = "ctx.unpin_active", menu = { group = "group", window = 54, tab = 90 },
	visible = isMulti,
	run = function(ctx) Layout.UnpinTab(ctx.id, ctx.index) end,
})

Actions.Add({
	id = "unpin_group_tabs", scope = "window", icon = "icon16/cross.png", label = "ctx.unpin_all_group",
	menu = { group = "group", window = 55 },
	visible = isMulti,
	run = function(ctx) Layout.ClearTabs(ctx.id) end,
})

Actions.Add({
	id = "dissolve", scope = "window", icon = "icon16/folder_delete.png", label = "ctx.dissolve",
	menu = { group = "group", window = 56 },
	visible = isMulti,
	run = function(ctx) Layout.Dissolve(ctx.id) end,
})

-- ── Window: opacity, position ───────────────────────────────

Actions.Add({
	id = "opacity", scope = "window", managed = true, icon = "icon16/contrast.png", label = "ctx.idle_opacity",
	menu = { group = "opacity", window = 60 },
	children = function(ctx)
		local current = ctx.window.opacity
		local function tick(on) return on and "icon16/tick.png" or nil end
		local items = {
			{ text = PP.L("ctx.use_global", Settings.Get("idleOpacity")), icon = tick(current == nil), run = function() Layout.SetOpacity(ctx.id, nil) end },
		}
		for _, pct in ipairs({ 100, 75, 50, 25, 0 }) do
			items[#items + 1] = { text = pct .. "%", icon = tick(current == pct / 100), run = function() Layout.SetOpacity(ctx.id, pct / 100) end }
		end
		items[#items + 1] = { spacer = true }
		items[#items + 1] = { text = PP.L("ctx.custom"), icon = "icon16/pencil.png", run = function()
			local pct = math.Round((current or Settings.Get("idleOpacity") / 100) * 100)
			PP.Dialogs.Text(PP.L("custom.idle_title"), PP.L("custom.idle_desc"), tostring(pct), function(value)
				local n = tonumber(value)
				if n then Layout.SetOpacity(ctx.id, math.Clamp(n, 0, 100) / 100) end
			end, "btn.apply")
		end }
		return items
	end,
})

Actions.Add({
	id = "lock", scope = "window", managed = true, name = "ctx.lock",
	icon = function(ctx) return ctx.window.locked and "icon16/lock_open.png" or "icon16/lock.png" end,
	label = function(ctx) return PP.L(ctx.window.locked and "ctx.unlock" or "ctx.lock") end,
	menu = { group = "position", window = 70 },
	run = function(ctx) Layout.SetLocked(ctx.id, not ctx.window.locked) end,
})

-- The geometry clipboard lives for the session (F29).
Actions.Add({
	id = "copy_geometry", scope = "window", managed = true, icon = "icon16/page_copy.png", label = "ctx.copy_pos",
	menu = { group = "position", window = 71 },
	run = function(ctx)
		local r = ctx.window
		Actions.clipboard = { x = r.x, y = r.y, w = r.w, h = r.h }
	end,
})

Actions.Add({
	id = "paste_geometry", scope = "window", managed = true, icon = "icon16/page_paste.png", label = "ctx.paste_pos",
	menu = { group = "position", window = 72 },
	enabled = function(ctx) return Actions.clipboard ~= nil and notLocked(ctx) end,
	run = function(ctx)
		local c = Actions.clipboard
		Layout.SetGeometry(ctx.id, c.x, c.y, c.w, c.h)
	end,
})

-- Moving another addon's panel between Manage and Embed (§33.6).
Actions.Add({
	id = "embed", scope = "window", managed = true, icon = "icon16/application_add.png", label = "ctx.embed",
	menu = { group = "adopt", window = 80 },
	visible = function(ctx) return ctx.window.kind == "managed" and PP.Manage.IsLive(ctx.id) end,
	run = function(ctx) PP.Recipes.SwitchMode(ctx.id, 1, "embed") end,
})

Actions.Add({
	id = "unembed", scope = "tab", icon = "icon16/application_link.png", label = "ctx.return_managed",
	menu = { group = "adopt", window = 81, tab = 81 },
	visible = function(ctx) return ctx.tab.adopt ~= nil and ctx.tab.adopt.mode == "embed" and PP.Embed.IsLive(ctx.tab.src) end,
	run = function(ctx) PP.Recipes.SwitchMode(ctx.id, ctx.index, "manage") end,
})

Actions.Add({
	id = "unpin", scope = "window", managed = true, icon = "icon16/cross.png", label = "ctx.unpin", name = "kb.unpin",
	taskbarLabel = "tb.unpin", menu = { group = "unpin", window = 90, taskbar = 3 }, bindable = true,
	run = function(ctx) Layout.Unpin(ctx.id) end,
})

-- ── Console only ────────────────────────────────────────────

-- +pinnedpanels_peek / -pinnedpanels_peek for binding peek with "bind" (D15).
concommand.Add("+pinnedpanels_peek", function() Desktop.Peek(true) end)
concommand.Add("-pinnedpanels_peek", function() Desktop.Peek(false) end)

-- The raw argument string keeps "tool:weld" whole; the console splits arguments at ":".
concommand.Add("pinnedpanels_pin", function(_, _, _, argStr)
	local src = string.Trim(argStr or ""):gsub('^"(.*)"$', "%1")
	if not Sources.catalogue[src] then
		print("[Pinned Panels] Unknown source: " .. src .. " (try tool:weld or creation:#spawnmenu.content_tab)")
		return
	end
	Desktop.PinSource(src)
end, function(cmd, argStr)
	local prefix = string.Trim(argStr):lower()
	local out = {}
	for key in pairs(Sources.catalogue) do
		if key:lower():sub(1, #prefix) == prefix then out[#out + 1] = cmd .. " " .. key end
	end
	table.sort(out)
	return out
end, "Pin a tool or content tab, e.g. pinnedpanels_pin tool:weld")

concommand.Add("pinnedpanels_list", function()
	for _, w in ipairs(Layout.Windows()) do
		print(string.format("%-5s %-9s %5d,%-5d %5dx%-5d %s%s%s", w.id, w.state, w.x, w.y, w.w, w.h,
			Layout.Title(w), w.kind == "managed" and "  (managed)" or "", Desktop.held[w.id] and "  (hidden)" or ""))
		for i, t in ipairs(w.tabs) do
			local here = Sources.Get(t.src) or (t.adopt and PP.Recipes.IsLive(w, t))
			print(string.format("      %s %s%s", i == w.active and "*" or " ", t.src, here and "" or (t.adopt and "  (waiting)" or "  (unavailable)")))
		end
	end
	print(string.format("[Pinned Panels] %d window(s).", #Layout.Windows()))
end, nil, "List pinned windows and their tabs")

-- pinnedpanels_debug panels: what the desktop holds, to check that merging and splitting leave nothing
-- behind (B9). nav: keyboard navigation's state. "perf" arrives with Phase 12.
concommand.Add("pinnedpanels_debug", function(_, _, args)
	if args[1] == "nav" then
		local Nav, el = PP.Nav, PP.Nav.element
		print(string.format("[Pinned Panels] nav: %s, window %s, %d controls, focused %s", Nav.state, tostring(Desktop.focused),
			#Nav.Elements(), IsValid(el) and (el.ClassName or el:GetClassName()) or "none"))
		return
	end
	if args[1] ~= "panels" then
		print("[Pinned Panels] usage: pinnedpanels_debug panels | nav")
		return
	end
	local controls, hosts, built = 0, 0, 0
	for _, win in pairs(Desktop.panels) do
		if IsValid(win) then
			controls = controls + 1
			for _, host in pairs(win.hosts) do
				hosts = hosts + 1
				if host.built then built = built + 1 end
			end
		end
	end
	print(string.format("[Pinned Panels] %d windows in the layout, %d window controls, %d tab hosts (%d built), %d managed, %d embedded, taskbar %s, %d Lua panels in total",
		#Layout.Windows(), controls, hosts, built, table.Count(PP.Manage.live), table.Count(PP.Embed.live), IsValid(Desktop.taskbar) and "on" or "off", #vgui.GetAll()))
end, nil, "Pinned Panels diagnostics: pinnedpanels_debug panels")

-- ── Several windows at once ─────────────────────────────────
-- A selection (made on the Pinned page or by Ctrl-clicking taskbar entries) and what can be done to a
-- list of windows in one go. Every operation takes the ids it works on, so "all" and "the selection"
-- are the same code; all of one call's changes land in the same frame, which makes them one undo step.

-- A table of its own each load, so nothing an earlier load defined lingers; the selection is kept.
PP.Batch = { selected = PP.Batch and PP.Batch.selected or {} } -- selected: window id -> true, for the session
local Batch = PP.Batch

local MAX_GROUP_TABS = 16 -- a window holds this many tabs at most (Storage's limit)
local CONFIRM_ABOVE = 3   -- unpinning more windows than this asks first

local function selectionChanged()
	hook.Run("PinnedPanelsSelectionChanged")
end

function Batch.IsSelected(id)
	return Batch.selected[id] == true
end

function Batch.Toggle(id, on)
	if on == nil then on = not Batch.selected[id] end
	Batch.selected[id] = on and true or nil
	selectionChanged()
end

function Batch.Set(ids)
	Batch.selected = {}
	for _, id in ipairs(ids) do Batch.selected[id] = true end
	selectionChanged()
end

function Batch.Clear()
	if next(Batch.selected) == nil then return end
	Batch.selected = {}
	selectionChanged()
end

local function byTitle(ids)
	table.sort(ids, function(a, b)
		local ta, tb = PP.Util.SortKey(Layout.Title(Layout.Get(a))), PP.Util.SortKey(Layout.Title(Layout.Get(b)))
		if ta ~= tb then return ta < tb end
		return a < b
	end)
	return ids
end

-- The selected windows that still exist, by title. Ones that were unpinned since are forgotten.
function Batch.Ids()
	local ids = {}
	for id in pairs(Batch.selected) do
		if Layout.Get(id) then ids[#ids + 1] = id else Batch.selected[id] = nil end
	end
	return byTitle(ids)
end

function Batch.Count()
	return #Batch.Ids()
end

-- Every window, by title.
function Batch.All()
	local ids = {}
	for _, rec in ipairs(Layout.Windows()) do ids[#ids + 1] = rec.id end
	return byTitle(ids)
end

local function each(ids, fn)
	local n = 0
	for _, id in ipairs(ids) do
		local rec = Layout.Get(id)
		if rec and fn(id, rec) ~= false then n = n + 1 end
	end
	return n
end

function Batch.Minimize(ids)
	return each(ids, function(id, rec)
		if rec.state == "minimized" or #rec.tabs == 0 then return false end
		Layout.Minimize(id)
	end)
end

-- Back on screen: restored if it was minimized, and shown if it was still held back from joining
-- (the "restore when joining" setting turned off).
function Batch.Restore(ids)
	Desktop.SetHeld(ids, false)
	return each(ids, function(id) Layout.Restore(id) end)
end

function Batch.Lock(ids, on)
	return each(ids, function(id) Layout.SetLocked(id, on) end)
end

function Batch.Opacity(ids, frac)
	return each(ids, function(id) Layout.SetOpacity(id, frac) end)
end

-- Unpins them. More than a few asks first, unless sure is given: this is how a layout gets lost.
function Batch.Unpin(ids, sure)
	local list = {}
	for _, id in ipairs(ids) do
		if Layout.Get(id) then list[#list + 1] = id end
	end
	if #list == 0 then return 0 end
	if #list > CONFIRM_ABOVE and not sure then
		Derma_Query(PP.L("batch.unpin_confirm", #list), PP.L("batch.unpin_title"),
			PP.L("batch.unpin_yes", #list), function() Batch.Unpin(list, true) end,
			PP.L("btn.cancel"), function() end)
		return 0
	end
	for _, id in ipairs(list) do
		Batch.selected[id] = nil
		Layout.Unpin(id)
	end
	selectionChanged()
	return #list
end

local function moveAll(fromId, toId)
	local from = Layout.Get(fromId)
	while from and #from.tabs > 0 and Layout.Get(fromId) do
		if not Layout.MoveTab(fromId, 1, toId) then break end
	end
end

local function tabCount(ids)
	local n = 0
	for _, id in ipairs(ids) do
		local rec = Layout.Get(id)
		if rec and rec.kind ~= "managed" then n = n + #rec.tabs end
	end
	return n
end

-- Puts the windows' tabs together in tabbed windows: one, or as many as it takes at MAX_GROUP_TABS
-- tabs each. Named title if given (a second one is "title (2)"), else the first window takes the
-- others. Managed windows are other addons' and stay as they are. Returns the ids of the windows
-- that hold them now.
function Batch.Group(ids, title)
	local sources = {}
	for _, id in ipairs(ids) do
		local rec = Layout.Get(id)
		if rec and rec.kind ~= "managed" and #rec.tabs > 0 then sources[#sources + 1] = id end
	end
	if tabCount(sources) < 2 then return {} end
	local targets, target = {}, nil
	local function room()
		local rec = target and Layout.Get(target)
		return rec and MAX_GROUP_TABS - #rec.tabs or 0
	end
	local function nextTarget(first)
		if title then
			target = Layout.NewGroup(#targets == 0 and title or (title .. " (" .. (#targets + 1) .. ")"))
		else
			target = first
		end
		targets[#targets + 1] = target
	end
	for _, id in ipairs(sources) do
		local rec = Layout.Get(id)
		if rec then
			if not target or (id ~= target and #rec.tabs > room()) then
				-- An untitled group grows from one of the windows themselves.
				nextTarget(id)
			end
			if id ~= target then moveAll(id, target) end
		end
	end
	for _, id in ipairs(sources) do Batch.selected[id] = nil end
	selectionChanged()
	return targets
end

-- The spawn-menu category of a window that holds a single tool, or nil.
local function categoryOf(rec)
	if rec.kind == "managed" or rec.title or #rec.tabs ~= 1 then return nil end
	local e = Sources.catalogue[rec.tabs[1].src]
	return e and e.kind == "tool" and e.category or nil
end

-- Tool windows are put together by spawn-menu category, each category in a tabbed window of its
-- name (sixty windows become a handful). A category with one window is left alone. Returns how many
-- windows were merged away and how many groups hold them.
function Batch.GroupByCategory(ids)
	local cats, order = {}, {}
	for _, id in ipairs(ids) do
		local rec = Layout.Get(id)
		local cat = rec and categoryOf(rec)
		if cat then
			if not cats[cat] then
				cats[cat] = {}
				order[#order + 1] = cat
			end
			cats[cat][#cats[cat] + 1] = id
		end
	end
	local merged, groups = 0, 0
	for _, cat in ipairs(order) do
		if #cats[cat] >= 2 then
			local made = Batch.Group(cats[cat], cat)
			merged, groups = merged + #cats[cat], groups + #made
		end
	end
	return merged, groups
end

-- One window's look (colours, accent, idle opacity) given to the others.
function Batch.CopyLook(fromId, ids)
	local from = Layout.Get(fromId)
	if not from then return 0 end
	local function copy(c) return c and Color(c.r, c.g, c.b, c.a) or nil end
	return each(ids, function(id)
		if id == fromId then return false end
		Layout.SetColors(id, { bg = copy(from.colors.bg), header = copy(from.colors.header), text = copy(from.colors.text) })
		Layout.SetAccent(id, copy(from.accent))
		Layout.SetOpacity(id, from.opacity)
	end)
end

-- One window's size given to the others, each where it is. Locked and managed windows keep theirs.
function Batch.CopySize(fromId, ids)
	local from = Layout.Get(fromId)
	if not from then return 0 end
	return each(ids, function(id, rec)
		if id == fromId or rec.locked or rec.kind == "managed" then return false end
		Layout.SetGeometry(id, rec.x, rec.y, from.w, from.h)
	end)
end

-- Pins every tool of a spawn-menu category that isn't pinned yet, together in a tabbed window named
-- after it (several when there are more than MAX_GROUP_TABS). Returns the ids of those windows.
function Batch.PinCategory(category)
	local keys = {}
	for _, e in ipairs(Sources.tools) do
		if e.category == category and not Layout.Find(e.key) then keys[#keys + 1] = e.key end
	end
	if #keys == 0 then return {} end
	if #keys == 1 then return { (Layout.Pin(keys[1])) } end
	local made = {}
	for _, key in ipairs(keys) do made[#made + 1] = (Layout.Pin(key)) end
	local groups = Batch.Group(made, category)
	for _, id in ipairs(groups) do Desktop.Show(id) end
	return groups
end

-- The menu for a list of windows: the Pinned page's "Actions" button and a right-click on a selected
-- taskbar entry.
function Actions.OpenBatchMenu(ids)
	if #ids == 0 then return end
	local menu = DermaMenu()
	local function add(key, icon, fn)
		menu:AddOption(PP.L(key, #ids), fn):SetIcon(icon)
	end
	add("batch.restore", "icon16/application_get.png", function() Batch.Restore(ids) end)
	add("batch.minimize", "icon16/application_put.png", function() Batch.Minimize(ids) end)
	menu:AddSpacer()
	add("batch.group", "icon16/folder_add.png", function()
		PP.Dialogs.Text(PP.L("new.group_title"), PP.L("new.group_desc"), "", function(name) Batch.Group(ids, name) end, "btn.create")
	end)
	add("batch.group_category", "icon16/folder_wrench.png", function() Batch.GroupByCategory(ids) end)
	menu:AddSpacer()
	add("batch.lock", "icon16/lock.png", function() Batch.Lock(ids, true) end)
	add("batch.unlock", "icon16/lock_open.png", function() Batch.Lock(ids, false) end)
	local sub, option = menu:AddSubMenu(PP.L("ctx.idle_opacity"))
	option:SetIcon("icon16/contrast.png")
	sub:AddOption(PP.L("ctx.use_global", Settings.Get("idleOpacity")), function() Batch.Opacity(ids, nil) end)
	for _, pct in ipairs({ 100, 75, 50, 25, 0 }) do
		sub:AddOption(pct .. "%", function() Batch.Opacity(ids, pct / 100) end)
	end
	menu:AddSpacer()
	add("batch.unpin", "icon16/cross.png", function() Batch.Unpin(ids) end)
	menu:AddSpacer()
	menu:AddOption(PP.L("batch.clear"), Batch.Clear):SetIcon("icon16/shape_square.png")
	menu:Open()
	return menu
end

Actions.Add({
	id = "minimize_all", scope = "global", icon = "icon16/application_put.png", label = "act.minimize_all",
	sub = "sub.minimize_all", palette = true, bindable = true,
	run = function() Batch.Minimize(Batch.All()) end,
})

Actions.Add({
	id = "group_by_category", scope = "global", icon = "icon16/folder_wrench.png", label = "act.group_category",
	sub = "sub.group_category", palette = true,
	run = function()
		local merged, groups = Batch.GroupByCategory(Batch.All())
		notification.AddLegacy(merged > 0 and PP.L("batch.grouped", merged, groups) or PP.L("batch.grouped_none"), NOTIFY_GENERIC, 6)
	end,
})

-- This window's look or size, given to every other window or to the selected ones.
Actions.Add({
	id = "apply_to_others", scope = "window", icon = "icon16/paintbrush.png", label = "ctx.apply_to_others",
	menu = { group = "opacity", window = 62 },
	children = function(ctx)
		local selected = Batch.Ids()
		local items = {
			{ text = PP.L("apply.look_all"), icon = "icon16/color_wheel.png", run = function() Batch.CopyLook(ctx.id, Batch.All()) end },
			{ text = PP.L("apply.size_all"), icon = "icon16/arrow_inout.png", run = function() Batch.CopySize(ctx.id, Batch.All()) end },
		}
		if #selected > 0 then
			items[#items + 1] = { spacer = true }
			items[#items + 1] = { text = PP.L("apply.look_selected", #selected), icon = "icon16/color_wheel.png", run = function() Batch.CopyLook(ctx.id, selected) end }
			items[#items + 1] = { text = PP.L("apply.size_selected", #selected), icon = "icon16/arrow_inout.png", run = function() Batch.CopySize(ctx.id, selected) end }
		end
		return items
	end,
})

-- Re-runs the loader (G2): windows rebuild from the saved document, with no duplicate hooks or panels (E25).
concommand.Add("pinnedpanels_reload", function()
	Storage.Flush()
	Desktop.Teardown()
	Desktop.held = {}
	include("autorun/pinnedpanels.lua")
end, nil, "Reload Pinned Panels and rebuild every window")

Actions.BindKeys()
