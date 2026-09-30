local Sources = PinnedPanels.Sources

local function tool(name, text, cpanel, command)
	return { ItemName = name, Text = text, CPanelFunction = cpanel, Command = command }
end

local function setupSpawnMenu()
	Stub.Set("tools", {
		{ Name = "Main", Label = "#spawnmenu.tools_tab", Items = {
			{ ItemName = "Constraints", Text = "#spawnmenu.tools.constraints", tool("weld", "#tool.weld.name", function() end, "gmod_tool weld"), tool("rope", "Rope") },
			{ ItemName = "Other", Text = "Other", tool("weld", "Duplicate weld") },
		} },
		{ Name = "Utilities", Label = "Utilities", Items = {
			{ ItemName = "User", Text = "User", tool("options", "Options", function() end) },
		} },
	})
	Stub.Set("creationTabs", {
		["#spawnmenu.content_tab"] = { Function = function() end, Icon = "icon16/application_view_tile.png", Order = -10 },
		["#spawnmenu.category.dupes"] = { Function = function() end, Order = 200 },
		[Sources.HUB_TAB] = { Function = function() end, Order = 9999 },
	})
	language.Add("tool.weld.name", "Weld")
	language.Add("spawnmenu.tools.constraints", "Constraints")
	Sources.Rebuild()
end

return {
	["Rebuild lists tools once each and leaves out our own tab (L28)"] = function(t)
		setupSpawnMenu()
		t.eq(#Sources.tools, 3)
		t.eq(Sources.Get("tool:weld").category, "Constraints")
		t.eq(#Sources.creations, 2)
		t.eq(Sources.creations[1].key, "creation:#spawnmenu.content_tab")
		t.eq(Sources.Get("creation:" .. Sources.HUB_TAB), nil)
	end,

	["Rebuild announces the new catalogue"] = function(t)
		local fired = 0
		hook.Add("PinnedPanelsCatalogChanged", "test", function() fired = fired + 1 end)
		setupSpawnMenu()
		hook.Run("PostReloadToolsMenu")
		t.eq(fired, 2)
	end,

	["titles are localized, with readable fallbacks for unknown sources"] = function(t)
		setupSpawnMenu()
		t.eq(Sources.Title("tool:weld"), "Weld")
		t.eq(Sources.Title("tool:rope"), "Rope")
		t.eq(Sources.Title("tool:gone"), "gone")
		t.eq(Sources.Title("creation:#spawnmenu.category.npcs"), "spawnmenu.category.npcs")
		language.Add("tool.weld.name", "Soudure")
		t.eq(Sources.Title("tool:weld"), "Soudure", "a language change shows without a rebuild")
	end,

	["default sizes depend on the kind"] = function(t)
		t.eq(select(2, Sources.DefaultSize("creation:x")), 560)
		t.eq(Sources.DefaultSize("tool:x"), 280)
	end,

	["the controlpanel fallback redirects only its tool and always restores (R5)"] = function(t)
		local original = controlpanel.Get
		local seen
		Sources.WithControlPanelFallback("weld", "ours", function()
			seen = { controlpanel.Get("weld"), controlpanel.Get("rope") }
			t.eq(Sources.inFallback, true)
		end)
		t.eq(seen[1], "ours")
		t.eq(seen[2], "spawnmenu panel rope")
		t.eq(controlpanel.Get, original)

		local ok = Sources.WithControlPanelFallback("weld", "ours", function() error("a hook blew up") end)
		t.eq(ok, false)
		t.eq(controlpanel.Get, original, "restored after an error")
		t.eq(Sources.inFallback, false)
		t.ok(Stub.Get("errors")[1]:find("a hook blew up", 1, true) ~= nil, "the error is printed (G38)")
	end,

	["the fallback's PostReloadToolsMenu doesn't rebuild the catalogue"] = function(t)
		setupSpawnMenu()
		local fired = 0
		hook.Add("PinnedPanelsCatalogChanged", "test", function() fired = fired + 1 end)
		Sources.WithControlPanelFallback("weld", "ours", function() hook.Run("PostReloadToolsMenu") end)
		t.eq(fired, 0)
	end,

	["only catalogued tools with a command can be equipped (R4, G16)"] = function(t)
		setupSpawnMenu()
		t.eq(Sources.Equip("tool:weld"), true)
		t.eq(Stub.Get("activated"), "weld")
		t.eq(Sources.CanEquip("tool:rope"), false)
		t.eq(Sources.CanEquip("tool:not_installed"), false)
		t.eq(Sources.CanEquip("creation:#spawnmenu.content_tab"), false)
	end,
}
