-- Windows, the desktop and the hub, driven through the headless Derma stub. These catch wiring mistakes;
-- how things look and feel is checked in game (§28.2).

local PP = PinnedPanels
local Layout, Desktop, Settings, Input = PP.Layout, PP.Desktop, PP.Settings, PP.Input

local function tool(name, build, command)
	return { ItemName = name, Text = name, CPanelFunction = build, Command = command }
end

local function fills(cp) cp:Add("DLabel") end

local function setup(opts)
	opts = opts or {}
	Stub.Set("tools", { { Name = "Main", Items = { {
		Text = "Constraints",
		tool("weld", fills, "gmod_tool weld"), tool("rope", fills), tool("axis", fills),
		tool("broken", function() error("boom") end), tool("hookfilled", function() end),
	} } } })
	Stub.Set("creationTabs", { ["#spawnmenu.content_tab"] = { Function = function() return vgui.Create("DPanel") end, Order = 1 } })
	if opts.autoRestore == false then Settings.Set("autoRestore", false) end
	if opts.saved then Stub.Files()["pinnedpanels/layout.json"] = util.TableToJSON(opts.saved) end
	hook.Run("PinnedPanelsLoaded")
	if not opts.noCatalogue then hook.Run("PostReloadToolsMenu") end
	Stub.Frame()
end

-- One rendered frame: visible panels think, then hooks and timers run.
local function frames(n)
	for _ = 1, n or 1 do
		Stub.ThinkPanels()
		Stub.Frame()
	end
end

local function pinned(src)
	local id = Desktop.PinSource(src)
	frames(2)
	return Desktop.panels[id], id
end

local function hostOf(win)
	for _, host in pairs(win.hosts) do
		if host:IsVisible() then return host end
	end
end

local function catalogRow(hub, src)
	for _, p in ipairs(Stub.Created()) do
		if p.ClassName == "PinnedPanelsCatalogRow" and p.src == src and not p.removed then return p end
	end
end

return {
	["pinning from the hub opens a window whose tab builds (F1-F3, F7)"] = function(t)
		setup()
		local hub = vgui.Create("PinnedPanelsHub")
		local row = catalogRow(hub, "tool:weld")
		row:Toggle()
		frames(2)
		local win = Desktop.panels[Layout.Find("tool:weld").id]
		t.ok(IsValid(win))
		t.eq(win.popup, true)
		t.eq(win.keyboard, false, "the mouse without the keyboard (G21)")
		local host = hostOf(win)
		t.ok(host.built)
		t.ok(IsValid(host.content))
		row:Paint(300, 32)
		t.eq(row.button.label, PP.L("btn.unpin"))
		row:Toggle()
		frames(1)
		t.eq(Layout.Find("tool:weld"), nil)
		t.ok(not IsValid(win), "the window control is removed")
	end,

	["content tabs pin too (F8)"] = function(t)
		setup()
		local win = pinned("creation:#spawnmenu.content_tab")
		t.eq(win.w, 350)
		t.ok(IsValid(hostOf(win).content))
	end,

	["one tab builds per frame (D13, E24)"] = function(t)
		setup()
		Layout.Pin("tool:weld")
		Layout.Pin("tool:rope")
		Layout.Pin("tool:axis")
		Stub.Frame()
		frames(1)
		local built = 0
		for _, win in pairs(Desktop.panels) do
			if hostOf(win).built then built = built + 1 end
		end
		t.eq(built, 1)
		frames(2)
		built = 0
		for _, win in pairs(Desktop.panels) do
			if hostOf(win).built then built = built + 1 end
		end
		t.eq(built, 3)
	end,

	["minimized windows don't build until shown"] = function(t)
		setup()
		local id = Layout.Pin("tool:weld")
		Layout.Minimize(id)
		frames(3)
		local win = Desktop.panels[id]
		t.eq(win.visible, false)
		t.ok(not hostOf(win).built)
		Layout.Restore(id)
		frames(2)
		t.ok(hostOf(win).built)
	end,

	["a failing build shows the error with a Retry that rebuilds (E8)"] = function(t)
		setup()
		local win = pinned("tool:broken")
		local host = hostOf(win)
		t.eq(host.content, nil)
		local box = host.clip:GetChildren()[1]
		t.eq(box.ClassName, "PinnedPanelsError")
		t.ok(Stub.Get("errors")[1]:find("boom", 1, true) ~= nil, "printed to the console")
		box.retry:DoClick()
		frames(1)
		t.eq(#Stub.Get("errors"), 2, "built again")
	end,

	["a tool filled through controlpanel.Get gets filled by the fallback (L2, E9)"] = function(t)
		setup()
		hook.Add("PostReloadToolsMenu", "SomeAddon", function()
			local cp = controlpanel.Get("hookfilled")
			if istable(cp) then cp:Add("DLabel") end
		end)
		local win = pinned("tool:hookfilled")
		local cp = hostOf(win).content:GetChildren()[1]
		t.eq(cp.ClassName, "ControlPanel")
		t.eq(#cp:GetChildren(), 1)
	end,

	["dragging the header moves the window, snaps and saves once (F9)"] = function(t)
		setup()
		local win, id = pinned("tool:weld")
		Layout.SetGeometry(id, 400, 300, 280, 400)
		frames(1)
		Stub.Press(win, 450, 310)
		t.ok(win.drag ~= nil)
		Stub.Move(win, 250, 110)
		t.eq(win.x, 200)
		Stub.Move(win, 57, 110)
		t.eq(win.x, 0, "snapped to the screen edge")
		Stub.Release(win, 57, 110)
		t.eq(Layout.Get(id).x, 0)
		t.eq(Layout.Get(id).y, 100)
		t.eq(win.captured, false)
	end,

	["ALT disables snapping"] = function(t)
		setup()
		local win, id = pinned("tool:weld")
		Layout.SetGeometry(id, 400, 300, 280, 400)
		frames(1)
		Stub.Key(KEY_LALT, true)
		Stub.Frame()
		Stub.Press(win, 450, 310)
		Stub.Move(win, 57, 310)
		t.eq(win.x, 7)
	end,

	["resizing from an edge respects the minimum size"] = function(t)
		setup()
		local win, id = pinned("tool:weld")
		Layout.SetGeometry(id, 400, 300, 280, 400)
		frames(1)
		Stub.Press(win, 400 + 280 - 2, 500)
		t.eq(win.resize.zone.e, true)
		Stub.Move(win, 1000, 500)
		t.eq(win.w, 602)
		Stub.Move(win, 100, 500)
		t.eq(win.w, 150)
		Stub.Release(win, 100, 500)
		t.eq(Layout.Get(id).w, 150)
	end,

	["corners resize both ways"] = function(t)
		setup()
		local win = pinned("tool:weld")
		t.eq(win:Zone(2, 2), "nw")
		t.eq(win:Zone(10, win.h - 2), "sw")
		t.eq(win:Zone(win.w - 2, 10), "ne")
		t.eq(win:Zone(win.w - 2, 100), "e")
		t.eq(win:Zone(100, 12), "header")
		t.eq(win:Zone(100, 100), nil)
		t.eq(win:Zone(win.w - 10, 10), "close")
		t.eq(win:Zone(win.w - 30, 10), "max")
		t.eq(win:Zone(win.w - 60, 10), "min")
	end,

	["locked windows don't move or resize (E18)"] = function(t)
		setup()
		local win, id = pinned("tool:weld")
		Layout.SetLocked(id, true)
		frames(1)
		local x = win.x
		Stub.Press(win, x + 50, win.y + 10)
		Stub.Move(win, x + 300, win.y + 10)
		t.eq(win.x, x)
		t.eq(win.drag, nil)
	end,

	["header buttons minimize, maximize and close"] = function(t)
		setup()
		local win, id = pinned("tool:weld")
		local function click(zoneX)
			local sx, sy = win:LocalToScreen(zoneX, 10)
			Stub.Press(win, sx, sy)
			Stub.Release(win, sx, sy)
			frames(1)
		end
		click(win.w - 30)
		t.eq(Layout.Get(id).state, "maximized")
		t.eq(win.w, 1920)
		click(win.w - 30)
		t.eq(Layout.Get(id).state, "normal")
		click(win.w - 60)
		t.eq(win.visible, false)
		Layout.Restore(id)
		frames(1)
		click(win.w - 10)
		t.eq(Layout.Get(id), nil)
		t.ok(not IsValid(win))
	end,

	["dragging a maximized window restores it under the cursor"] = function(t)
		setup()
		local win, id = pinned("tool:weld")
		Layout.ToggleMaximize(id)
		frames(1)
		Stub.Press(win, 960, 10)
		Stub.Move(win, 980, 200)
		Stub.Release(win, 980, 200)
		t.eq(Layout.Get(id).state, "normal")
		t.eq(Layout.Get(id).w, 280)
	end,

	["click-through windows pass clicks except on the header, ALT overrides (F11, E17)"] = function(t)
		setup()
		local win, id = pinned("tool:weld")
		Layout.SetClickThrough(id, true)
		frames(1)
		t.eq(win:TestHover(win.x + 50, win.y + 10), true)
		t.eq(win:TestHover(win.x + 50, win.y + 100), false)
		Stub.Key(KEY_LALT, true)
		Stub.Frame()
		t.eq(win:TestHover(win.x + 50, win.y + 100), nil)
		t.ok(win.titleText:find(PP.L("ind.clickthrough"), 1, true) ~= nil)
	end,

	["idle opacity outside cursor mode, full and clickable inside (F10)"] = function(t)
		setup()
		local win, id = pinned("tool:weld")
		Settings.Set("idleOpacity", 50)
		t.eq(win.alpha, 128)
		t.eq(win.mouse, false)
		Layout.SetOpacity(id, 0.25)
		frames(1)
		t.eq(win.alpha, 64)
		Input.SetCursorMode(true)
		t.eq(win.alpha, 255)
		t.eq(win.mouse, true)
		t.eq(Stub.Get("clicker"), true)
	end,

	["the cursor key toggles cursor mode, not while typing"] = function(t)
		setup()
		Stub.Key(KEY_F4, true)
		Stub.Frame()
		t.eq(Input.cursorMode, true)
		Stub.Key(KEY_F4, false)
		Stub.Frame()
		Stub.Set("kbFocus", { IsValid = function() return true end })
		Stub.Key(KEY_F4, true)
		Stub.Frame()
		t.eq(Input.cursorMode, true)
	end,

	["the banner shows the cursor key (L8)"] = function(t)
		setup()
		language.Add("pinnedpanels.hud.banner", "press %s")
		local drawn
		draw.SimpleText = function(text) drawn = text end
		Input.SetCursorMode(true)
		hook.Run("HUDPaint")
		draw.SimpleText = nil
		t.eq(drawn, "press KEY" .. KEY_F4)
	end,

	["unavailable sources stay dormant and come back (E1, B1)"] = function(t)
		setup({ saved = { v = 2, windows = { { id = "w1", tabs = { { src = "tool:wire_gate" } }, x = 10, y = 10, w = 300, h = 300 } } } })
		t.eq(Desktop.panels.w1, nil)
		t.ok(Layout.Get("w1") ~= nil)
		local tools = Stub.Get("tools")
		table.insert(tools[1].Items[1], tool("wire_gate", fills))
		hook.Run("PostReloadToolsMenu")
		frames(1)
		t.ok(IsValid(Desktop.panels.w1))
	end,

	["a window shows an available tab while its active one is dormant"] = function(t)
		setup({ saved = { v = 2, windows = { { id = "w1", active = 1, x = 10, y = 10, w = 300, h = 300,
			tabs = { { src = "tool:wire_gate" }, { src = "tool:rope" } } } } } })
		frames(2)
		local host = hostOf(Desktop.panels.w1)
		t.eq(host.src, "tool:rope")
		t.eq(Layout.Get("w1").active, 1, "the document is untouched")
	end,

	["nothing is shown before the catalogue is known (E2)"] = function(t)
		setup({ noCatalogue = true, saved = { v = 2, windows = { { id = "w1", tabs = { { src = "tool:weld" } }, x = 10, y = 10, w = 300, h = 300 } } } })
		t.eq(Desktop.panels.w1, nil)
		hook.Run("PostReloadToolsMenu")
		t.ok(IsValid(Desktop.panels.w1))
	end,

	["with autoRestore off, saved windows wait until asked"] = function(t)
		setup({ autoRestore = false, saved = { v = 2, windows = { { id = "w1", tabs = { { src = "tool:weld" } }, x = 10, y = 10, w = 300, h = 300 } } } })
		t.eq(Desktop.panels.w1, nil)
		Desktop.PinSource("tool:rope")
		frames(1)
		t.eq(Desktop.panels.w1, nil, "pinning something else doesn't show them")
		Desktop.ShowHeld()
		t.ok(IsValid(Desktop.panels.w1))
	end,

	["console commands pin and list"] = function(t)
		setup()
		Stub.Command("pinnedpanels_pin", ' "tool:weld" ')
		frames(1)
		t.ok(Layout.Find("tool:weld") ~= nil)
		local oldPrint = print
		local lines = 0
		print = function() lines = lines + 1 end
		Stub.Command("pinnedpanels_pin", "tool:nope")
		Stub.Command("pinnedpanels_list")
		print = oldPrint
		t.eq(lines, 4)
		Stub.Command("pinnedpanels_cursor")
		t.eq(Input.cursorMode, true)
	end,

	["the hub counts windows and filters tools"] = function(t)
		setup()
		local hub = vgui.Create("PinnedPanelsHub")
		Desktop.PinSource("tool:weld")
		frames(1)
		t.eq(hub.count.text, PP.L("pin.count_one", 1))
		local catalog
		for _, p in ipairs(Stub.Created()) do
			if p.ClassName == "PinnedPanelsCatalog" and p.kind == "tool" then catalog = p end
		end
		catalog.search.text = "ROP"
		catalog:Filter()
		t.eq(catalog.countLabel.text, "1 / 5")
		t.eq(catalogRow(hub, "tool:rope").visible, true)
		t.eq(catalogRow(hub, "tool:weld").visible, false)
		catalog.search.text = "zzz"
		catalog:Filter()
		t.eq(catalog.empty.visible, true)
	end,

	["a window takes the keyboard for its focused text entry, and gives it back when cursor mode ends"] = function(t)
		setup()
		local win = pinned("tool:weld")
		Input.SetCursorMode(true)
		local entry = vgui.Create("DTextEntry", hostOf(win).content)
		hook.Run("OnTextEntryGetFocus", entry)
		t.eq(win.keyboard, true)
		Input.SetCursorMode(false)
		t.eq(win.keyboard, false)
	end,
}
