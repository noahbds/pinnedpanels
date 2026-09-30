local Settings = PinnedPanels.Settings

local function events()
	local log = {}
	hook.Add("PinnedPanelsSettingChanged", "test", function(key, value) log[#log + 1] = { key, value } end)
	return log
end

return {
	["defaults are typed"] = function(t)
		t.eq(Settings.Get("autoRestore"), true)
		t.eq(Settings.Get("snapDistance"), 12)
		t.eq(Settings.Get("colorBg").a, 250)
		t.eq(Settings.Get("keyCursor"), KEY_F4)
	end,

	["convar names are snake case with the pinnedpanels_ prefix (D4)"] = function(t)
		t.eq(Settings.defs.snapDistance.convar, "pinnedpanels_snap_distance")
		t.ok(GetConVar("pinnedpanels_key_cursor") ~= nil)
		t.ok(GetConVar("pinnedpanels_color_bg") ~= nil)
	end,

	["Set updates immediately and fires one event"] = function(t)
		local log = events()
		Settings.Set("snapDistance", 20)
		t.eq(Settings.Get("snapDistance"), 20)
		t.eq(GetConVar("pinnedpanels_snap_distance"):GetString(), "20")
		t.eq(#log, 1)
		Settings.Set("snapDistance", 20)
		t.eq(#log, 1, "no event when unchanged")
	end,

	["numbers clamp to the declared range"] = function(t)
		Settings.Set("snapDistance", 500)
		t.eq(Settings.Get("snapDistance"), 40)
		Settings.Set("idleOpacity", 1)
		t.eq(Settings.Get("idleOpacity"), 10)
	end,

	["a console change is picked up"] = function(t)
		local log = events()
		GetConVar("pinnedpanels_auto_restore"):SetString("0")
		t.eq(Settings.Get("autoRestore"), false)
		t.eq(log[1][1], "autoRestore")
		t.eq(log[1][2], false)
	end,

	["junk in a convar reads as the default"] = function(t)
		GetConVar("pinnedpanels_color_text"):SetString("purple")
		t.eq(Settings.Get("colorText").r, 240)
		GetConVar("pinnedpanels_key_cursor"):SetString("nope")
		t.eq(Settings.Get("keyCursor"), KEY_F4)
	end,

	["colours round-trip and compare by value"] = function(t)
		local log = events()
		Settings.Set("colorHeader", Color(1, 2, 3, 4))
		t.eq(GetConVar("pinnedpanels_color_header"):GetString(), "1 2 3 4")
		Settings.Set("colorHeader", Color(1, 2, 3, 4))
		t.eq(#log, 1)
	end,

	["enums accept declared values only"] = function(t)
		Settings.Add("testSide", { type = "enum", values = { "bottom", "top" }, default = "bottom", page = "taskbar" })
		Settings.Set("testSide", "top")
		t.eq(Settings.Get("testSide"), "top")
		GetConVar("pinnedpanels_test_side"):SetString("sideways")
		t.eq(Settings.Get("testSide"), "bottom")
	end,

	["Reset restores the default"] = function(t)
		Settings.Set("snap", false)
		Settings.Reset("snap")
		t.eq(Settings.Get("snap"), true)
	end,
}
