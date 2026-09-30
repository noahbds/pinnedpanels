local PP = PinnedPanels
local Layout, Storage, Geom = PP.Layout, PP.Storage, PP.Geom

local function setup()
	PP.Sources = PP.Sources or { Title = function(src) return src:match(":(.+)$") end }
	Layout.Load(nil)
	Stub.Frame()
end

local function pin(src, w, h)
	return (Layout.Pin(src, w, h))
end

local function events()
	local log = {}
	hook.Add("PinnedPanelsChanged", "test", function(kind, id) log[#log + 1] = kind .. ":" .. tostring(id) end)
	return log
end

local function saveAndReload()
	Storage.MarkDirty()
	Storage.Flush()
	Layout.Load(Storage.Load())
end

return {
	["Pin creates a window that doesn't overlap the others (F36)"] = function(t)
		setup()
		local a = Layout.Get(pin("tool:weld"))
		local b = Layout.Get(pin("tool:rope"))
		t.eq(#Layout.Windows(), 2)
		t.eq(a.tabs[1].src, "tool:weld")
		t.ok(not Geom.Overlap(a, b), "windows overlap")
	end,

	["pinning something already pinned brings its window back (E22)"] = function(t)
		setup()
		local id = pin("tool:weld")
		Layout.MoveTab(pin("tool:rope"), 1, id)
		Layout.Minimize(id)
		local again, existed = Layout.Pin("tool:weld")
		t.eq(again, id)
		t.eq(existed, true)
		t.eq(Layout.Get(id).state, "normal")
		t.eq(Layout.Get(id).active, 1)
		t.eq(#Layout.Windows(), 1)
	end,

	["unpinning a multi-tab window reopens as one window (E21, B20)"] = function(t)
		setup()
		local id = pin("tool:weld")
		Layout.MoveTab(pin("tool:rope"), 1, id)
		Layout.Rename(id, nil, "Constraints")
		Layout.Unpin(id)
		t.eq(#Layout.Windows(), 0)
		local back = Layout.Get(Layout.Reopen())
		t.eq(#back.tabs, 2)
		t.eq(back.title, "Constraints")
		t.eq(Layout.Reopen(), nil, "only one entry")
	end,

	["Reopen skips tabs that were pinned again"] = function(t)
		setup()
		local id = pin("tool:weld")
		Layout.MoveTab(pin("tool:rope"), 1, id)
		Layout.Unpin(id)
		pin("tool:weld")
		local back = Layout.Get(Layout.Reopen())
		t.eq(#back.tabs, 1)
		t.eq(back.tabs[1].src, "tool:rope")
	end,

	["recently closed keeps 15 entries"] = function(t)
		setup()
		for i = 1, 20 do Layout.Unpin(pin("tool:t" .. i)) end
		t.eq(#Layout.closed, 15)
		t.eq(Layout.Get(Layout.Reopen()).tabs[1].src, "tool:t20")
	end,

	["unpinning the last tab removes the window"] = function(t)
		setup()
		local id = pin("tool:weld")
		Layout.UnpinTab(id, 1)
		t.eq(Layout.Get(id), nil)
	end,

	["unpinning one tab of several keeps the window and can be reopened"] = function(t)
		setup()
		local id = pin("tool:weld")
		Layout.MoveTab(pin("tool:rope"), 1, id)
		Layout.UnpinTab(id, 1)
		t.eq(#Layout.Get(id).tabs, 1)
		t.eq(Layout.Get(id).tabs[1].src, "tool:rope")
		t.eq(Layout.Get(Layout.Reopen()).tabs[1].src, "tool:weld")
	end,

	["merging moves the tab and removes the emptied window (F15, L7)"] = function(t)
		setup()
		local a, b = pin("tool:weld"), pin("tool:rope")
		t.eq(Layout.MoveTab(b, 1, a), a)
		t.eq(Layout.Get(b), nil)
		t.eq(#Layout.Get(a).tabs, 2)
		t.eq(Layout.Get(a).active, 1, "the target keeps its active tab")
		t.eq(select(1, Layout.Find("tool:rope")).id, a)
	end,

	["merging a group into a group moves tabs, never windows (L7)"] = function(t)
		setup()
		local a, b = pin("tool:a"), pin("tool:b")
		Layout.MoveTab(pin("tool:a2"), 1, a)
		Layout.MoveTab(pin("tool:b2"), 1, b)
		Layout.MoveTab(b, 1, a)
		Layout.MoveTab(b, 1, a)
		t.eq(Layout.Get(b), nil)
		t.eq(#Layout.Get(a).tabs, 4)
		for _, tab in ipairs(Layout.Get(a).tabs) do t.ok(tab.tabs == nil) end
	end,

	["moving out the last-but-one tab keeps a single-tab window (E20)"] = function(t)
		setup()
		local a = pin("tool:weld")
		Layout.MoveTab(pin("tool:rope"), 1, a)
		local split = Layout.MoveTab(a, 2, nil)
		t.ok(split ~= a)
		t.eq(#Layout.Get(a).tabs, 1)
		t.eq(Layout.Get(split).tabs[1].src, "tool:rope")
		t.ok(not Geom.Overlap(Layout.Get(a), Layout.Get(split)), "split window is placed free")
	end,

	["reordering keeps the same tab active"] = function(t)
		setup()
		local a = pin("tool:a")
		Layout.MoveTab(pin("tool:b"), 1, a)
		Layout.MoveTab(pin("tool:c"), 1, a)
		Layout.Activate(a, 2)
		Layout.MoveTab(a, 3, a, 1)
		local win = Layout.Get(a)
		t.eq(win.tabs[1].src, "tool:c")
		t.eq(win.tabs[win.active].src, "tool:b")
	end,

	["each tab keeps its own size (L6)"] = function(t)
		setup()
		local a = pin("tool:a", 300, 500)
		Layout.MoveTab(pin("tool:b", 600, 200), 1, a)
		t.eq(Layout.Get(a).w, 300)
		Layout.Activate(a, 2)
		t.eq(Layout.Get(a).w, 600)
		t.eq(Layout.Get(a).h, 200)
		Layout.SetGeometry(a, 10, 10, 650, 250)
		Layout.Activate(a, 1)
		t.eq(Layout.Get(a).w, 300)
		Layout.Activate(a, 2)
		t.eq(Layout.Get(a).w, 650)
	end,

	["a named group starts empty and takes its first tab's size"] = function(t)
		setup()
		local g = Layout.NewGroup("  Build  ")
		t.eq(Layout.Get(g).title, "Build")
		t.eq(#Layout.Get(g).tabs, 0)
		Layout.MoveTab(pin("tool:weld", 500, 300), 1, g)
		t.eq(Layout.Get(g).w, 500)
		t.eq(Layout.NewGroup("   "), nil)
	end,

	["an emptied named group stays"] = function(t)
		setup()
		local g = Layout.NewGroup("Build")
		Layout.MoveTab(pin("tool:weld"), 1, g)
		Layout.MoveTab(g, 1, nil)
		t.ok(Layout.Get(g) ~= nil)
		Layout.UnpinTab(Layout.Get(select(1, Layout.Find("tool:weld")).id).id, 1)
		t.ok(Layout.Get(g) ~= nil)
	end,

	["renaming a group survives adding a tab (B8, E33)"] = function(t)
		setup()
		local a = pin("tool:a")
		Layout.MoveTab(pin("tool:b"), 1, a)
		Layout.Rename(a, nil, "Mine")
		Layout.MoveTab(pin("tool:c"), 1, a)
		saveAndReload()
		t.eq(Layout.Get(a).title, "Mine")
	end,

	["a single window's name belongs to its tab and travels with it (L19)"] = function(t)
		setup()
		local a = pin("tool:weld")
		Layout.Rename(a, nil, "My weld")
		t.eq(Layout.Get(a).title, nil)
		t.eq(Layout.Title(Layout.Get(a)), "My weld")
		local g = pin("tool:rope")
		Layout.MoveTab(a, 1, g)
		t.eq(Layout.Get(g).tabs[2].title, "My weld")
		Layout.Rename(g, 2, "")
		t.eq(Layout.TabTitle(Layout.Get(g).tabs[2]), "weld", "empty name goes back to the default")
	end,

	["locked windows refuse moves, maximize and arrange (E18)"] = function(t)
		setup()
		local a = pin("tool:a")
		local before = Layout.Get(a).x
		Layout.SetLocked(a, true)
		t.eq(Layout.SetGeometry(a, 500, 500, 300, 300), false)
		t.eq(Layout.ToggleMaximize(a), false)
		Layout.Arrange()
		t.eq(Layout.Get(a).x, before)
		t.eq(Layout.SetGeometry(a, before, Layout.Get(a).y, 350, 300, true), true, "auto-size may resize")
		t.eq(Layout.Get(a).w, 350)
	end,

	["geometry is clamped into the usable area"] = function(t)
		setup()
		local a = pin("tool:a")
		Layout.SetGeometry(a, 5000, -300, 400, 5000)
		local w = Layout.Get(a)
		t.eq(w.h, 1080)
		t.eq(w.y, 0)
		t.eq(w.x, 1520)
	end,

	["maximize and restore round-trip, keeping the crop (B27, E28)"] = function(t)
		setup()
		local a = pin("tool:a")
		Layout.SetGeometry(a, 100, 100, 300, 400)
		Layout.SetCrop(a, 1, { l = 0, t = 30, r = 0, b = 50 })
		Layout.ToggleMaximize(a)
		local w = Layout.Get(a)
		t.eq(w.state, "maximized")
		t.eq(w.w, 1920)
		Layout.ToggleMaximize(a)
		t.eq(w.state, "normal")
		t.eq(w.x, 100)
		t.eq(w.w, 300)
		t.eq(w.tabs[1].crop.t, 30)
	end,

	["minimizing a maximized window restores it maximized"] = function(t)
		setup()
		local a = pin("tool:a")
		Layout.ToggleMaximize(a)
		Layout.Minimize(a)
		Layout.Restore(a)
		t.eq(Layout.Get(a).state, "maximized")
	end,

	["dragging a maximized window makes it normal"] = function(t)
		setup()
		local a = pin("tool:a")
		Layout.ToggleMaximize(a)
		Layout.SetGeometry(a, 50, 50, 300, 300)
		t.eq(Layout.Get(a).state, "normal")
		t.eq(Layout.Get(a).restore, nil)
	end,

	["a quick key belongs to one window (F21)"] = function(t)
		setup()
		local a, b = pin("tool:a"), pin("tool:b")
		Layout.SetQuickKey(a, KEY_A)
		Layout.SetQuickKey(b, KEY_A)
		t.eq(Layout.Get(a).quickKey, nil)
		t.eq(Layout.Get(b).quickKey, KEY_A)
		Layout.SetQuickKey(b, KEY_NONE)
		t.eq(Layout.Get(b).quickKey, nil)
	end,

	["Arrange tiles visible windows without overlap (F18)"] = function(t)
		setup()
		local ids = {}
		for i = 1, 8 do ids[i] = pin("tool:t" .. i, 400, 300) end
		Layout.Minimize(ids[8])
		local hidden = Layout.Get(ids[8]).x
		Layout.ToggleMaximize(ids[1])
		Layout.Arrange()
		for i = 1, 7 do
			for j = i + 1, 7 do
				t.ok(not Geom.Overlap(Layout.Get(ids[i]), Layout.Get(ids[j])), i .. " overlaps " .. j)
			end
		end
		t.eq(Layout.Get(ids[1]).state, "normal")
		t.eq(Layout.Get(ids[1]).w, 400)
		t.eq(Layout.Get(ids[8]).x, hidden, "minimized windows stay put")
	end,

	["a resolution change rescales every rectangle once (E3, B17)"] = function(t)
		setup()
		local a = pin("tool:a")
		Layout.SetGeometry(a, 960, 540, 400, 300)
		local g = pin("tool:b")
		Layout.MoveTab(pin("tool:c", 800, 600), 1, g)
		local m = pin("tool:d")
		Layout.SetGeometry(m, 100, 100, 400, 400)
		Layout.ToggleMaximize(m)
		Stub.SetScreen(960, 540)
		Layout.RescaleAll(1920, 1080)
		local w = Layout.Get(a)
		t.eq(w.x, 480)
		t.eq(w.w, 200)
		t.eq(Layout.Get(g).tabs[2].size.w, 400)
		t.eq(Layout.Get(m).w, 960, "maximized refits")
		t.eq(Layout.Get(m).restore.w, 200)
		Layout.ToggleMaximize(m)
		t.eq(Layout.Get(m).x, 50)
	end,

	["a layout saved at another resolution is rescaled on load"] = function(t)
		setup()
		local a = pin("tool:a")
		Layout.SetGeometry(a, 1000, 500, 400, 400)
		Storage.MarkDirty()
		Storage.Flush()
		Stub.SetScreen(1280, 720)
		Layout.Load(Storage.Load())
		local w = Layout.Get(a)
		t.eq(w.x, math.Round(1000 * 1280 / 1920))
		t.eq(Layout.Document().screen.w, 1280)
	end,

	["unavailable sources survive a save (E1, B1)"] = function(t)
		setup()
		pin("tool:from_disabled_addon")
		saveAndReload()
		saveAndReload()
		t.ok(Layout.Find("tool:from_disabled_addon") ~= nil)
	end,

	["everything round-trips through the file (F31)"] = function(t)
		setup()
		local a = pin("tool:a")
		Layout.MoveTab(pin("tool:b"), 1, a)
		Layout.Activate(a, 2)
		Layout.SetLocked(a, true)
		Layout.SetClickThrough(a, true)
		Layout.SetOpacity(a, 0.5)
		Layout.SetColors(a, { bg = Color(1, 2, 3, 4) })
		Layout.SetAccent(a, Color(9, 9, 9))
		Layout.SetFilterBar(a, true)
		Layout.SetQuickKey(a, KEY_B)
		Layout.SetCrop(a, 1, { l = 1, t = 2, r = 3, b = 4 })
		saveAndReload()
		local w = Layout.Get(a)
		t.eq(w.active, 2)
		t.eq(w.locked, true)
		t.eq(w.clickThrough, true)
		t.eq(w.opacity, 0.5)
		t.eq(w.colors.bg.a, 4)
		t.eq(w.accent.r, 9)
		t.eq(w.filterBar, true)
		t.eq(w.quickKey, KEY_B)
		t.eq(w.tabs[1].crop.r, 3)
		t.eq(Layout.Pin("tool:new"), "w" .. (tonumber(a:sub(2)) + 2), "ids keep counting up")
	end,

	["changes are coalesced into one event per kind and window per frame"] = function(t)
		setup()
		local a = pin("tool:a")
		Stub.Frame()
		local log = events()
		for i = 1, 10 do Layout.SetGeometry(a, i * 10, 0, 300, 300) end
		Layout.SetLocked(a, true)
		t.eq(#log, 0, "nothing before the frame ends")
		Stub.Frame()
		t.eq(table.concat(log, " "), "state:" .. a .. " geometry:" .. a)
	end,

	["operations on unknown ids fail softly"] = function(t)
		setup()
		t.eq(Layout.Unpin("w99"), false)
		t.eq(Layout.SetGeometry("w99", 0, 0, 1, 1), false)
		t.eq(Layout.MoveTab("w99", 1, nil), nil)
		t.eq(Layout.Rename("w99", nil, "x"), false)
		t.eq(Layout.Reopen(), nil)
	end,
}
