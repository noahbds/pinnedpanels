-- Console commands and key bindings (§18). Phase 3 turns this into the declared action list that also
-- feeds menus and the palette; for now it has the cursor toggle, pin, list and reload.

local PP = PinnedPanels
local Layout, Sources, Input, Settings, Storage, Desktop = PP.Layout, PP.Sources, PP.Input, PP.Settings, PP.Storage, PP.Desktop

local function toggleCursor()
	Input.SetCursorMode(not Input.cursorMode)
end

local function bindKeys()
	Input.SetKey("cursor", Settings.Get("keyCursor"), toggleCursor)
end

bindKeys()
hook.Add("PinnedPanelsSettingChanged", "PinnedPanels.Actions", function(key)
	if key == "keyCursor" then bindKeys() end
end)

concommand.Add("pinnedpanels_cursor", toggleCursor, nil, "Toggle Pinned Panels cursor mode")

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
		print(string.format("%-5s %-9s %5d,%-5d %5dx%-5d %s%s", w.id, w.state, w.x, w.y, w.w, w.h,
			Layout.Title(w), Desktop.held[w.id] and "  (held)" or ""))
		for i, t in ipairs(w.tabs) do
			print(string.format("      %s %s%s", i == w.active and "*" or " ", t.src, Sources.Get(t.src) and "" or "  (unavailable)"))
		end
	end
	print(string.format("[Pinned Panels] %d window(s).", #Layout.Windows()))
end, nil, "List pinned windows and their tabs")

-- Re-runs the loader (G2): windows rebuild from the saved document, with no duplicate hooks or panels (E25).
concommand.Add("pinnedpanels_reload", function()
	Storage.Flush()
	Desktop.Teardown()
	Desktop.held = {}
	include("autorun/pinnedpanels.lua")
end, nil, "Reload Pinned Panels and rebuild every window")
