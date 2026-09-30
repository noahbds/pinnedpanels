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
local REBUILDABLE = { tool = true, postprocess = true, desktop = true }
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

Actions.Add({
	id = "cursor", scope = "global", icon = "icon16/cursor.png", label = "act.toggle_cursor",
	sub = "sub.show_cursor", palette = true, bindable = true, key = KEY_F4,
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
	run = function() Layout.Arrange() end,
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
	run = function() PP.Recipes.Record() end,
})

Actions.Add({
	id = "unpin_all", scope = "global", icon = "icon16/cross.png", label = "act.unpin_all", sub = "sub.remove_every", palette = true,
	run = function()
		local ids = {}
		for _, rec in ipairs(Layout.Windows()) do ids[#ids + 1] = rec.id end
		for _, id in ipairs(ids) do Layout.Unpin(id) end
	end,
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

-- Hidden for this session; the Pinned page and palette show it again.
Actions.Add({
	id = "hide", scope = "window", managed = true, icon = "icon16/eye.png", label = "ctx.hide_panel", name = "kb.toggle_hide",
	menu = { group = "view", window = 22 }, bindable = true,
	run = function(ctx)
		if Desktop.held[ctx.id] then Desktop.Show(ctx.id) else Desktop.Hide(ctx.id) end
	end,
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

Actions.Add({
	id = "clickthrough", scope = "window", managed = true, name = "ctx.clickthrough",
	icon = function(ctx) return ctx.window.clickThrough and "icon16/shape_square.png" or "icon16/shape_square_go.png" end,
	label = function(ctx) return PP.L(ctx.window.clickThrough and "ctx.disable_ct" or "ctx.clickthrough") end,
	menu = { group = "style", window = 44 },
	run = function(ctx)
		local on = not ctx.window.clickThrough
		Layout.SetClickThrough(ctx.id, on)
		if on then notification.AddLegacy(PP.L("clickthrough.notify"), NOTIFY_GENERIC, 6) end
	end,
})

-- A managed window that isn't a text field (an editor, say) can take the keyboard when clicked (§33.5).
Actions.Add({
	id = "needs_keyboard", scope = "window", managed = true, name = "ctx.needs_keyboard", label = "ctx.needs_keyboard",
	icon = function(ctx) return ctx.window.tabs[1].adopt.needsKeyboard and "icon16/tick.png" or "icon16/keyboard.png" end,
	menu = { group = "style", window = 45 },
	visible = function(ctx) return ctx.window.kind == "managed" end,
	run = function(ctx) Layout.SetAdopt(ctx.id, 1, { needsKeyboard = not ctx.window.tabs[1].adopt.needsKeyboard }) end,
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
		for _, pct in ipairs({ 100, 75, 50, 25, 1 }) do
			items[#items + 1] = { text = pct .. "%", icon = tick(current == pct / 100), run = function() Layout.SetOpacity(ctx.id, pct / 100) end }
		end
		items[#items + 1] = { spacer = true }
		items[#items + 1] = { text = PP.L("ctx.custom"), icon = "icon16/pencil.png", run = function()
			local pct = math.Round((current or Settings.Get("idleOpacity") / 100) * 100)
			PP.Dialogs.Text(PP.L("custom.idle_title"), PP.L("custom.idle_desc"), tostring(pct), function(value)
				local n = tonumber(value)
				if n then Layout.SetOpacity(ctx.id, math.Clamp(n, 10, 100) / 100) end
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
	if not Sources.Get(src) then
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
	print(string.format("[Pinned Panels] %d windows in the layout, %d window controls, %d tab hosts (%d built), %d managed, taskbar %s, %d Lua panels in total",
		#Layout.Windows(), controls, hosts, built, table.Count(PP.Manage.live), IsValid(Desktop.taskbar) and "on" or "off", #vgui.GetAll()))
end, nil, "Pinned Panels diagnostics: pinnedpanels_debug panels")

-- Re-runs the loader (G2): windows rebuild from the saved document, with no duplicate hooks or panels (E25).
concommand.Add("pinnedpanels_reload", function()
	Storage.Flush()
	Desktop.Teardown()
	Desktop.held = {}
	include("autorun/pinnedpanels.lua")
end, nil, "Reload Pinned Panels and rebuild every window")

Actions.BindKeys()
