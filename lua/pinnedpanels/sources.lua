-- The catalogue of pinnable things (§14): tools and Utilities option pages ("tool:<name>") and spawn-menu
-- content tabs ("creation:<name>"), rebuilt on every PostReloadToolsMenu (G11). Builds their content.

local PP = PinnedPanels
PP.Sources = PP.Sources or {}
local Sources = PP.Sources

Sources.HUB_TAB = "#pinnedpanels.spawn.tab"
Sources.catalogue = Sources.catalogue or {}
Sources.tools = Sources.tools or {}
Sources.creations = Sources.creations or {}
Sources.inFallback = false

local DEFAULT_SIZE = { tool = { 280, 400 }, creation = { 350, 560 } }

-- "#tool.weld.name" → the current language's text; unknown phrases fall back to the key without "#".
local function phrase(text)
	if not isstring(text) or text == "" then return "" end
	local key = text:gsub("^#", "")
	local out = language.GetPhrase(key)
	return out ~= key and out or key
end

-- ── Catalogue ───────────────────────────────────────────────

-- Reads the spawn menu's lists (G12, G13). Tools are deduped by ItemName (L28); our own hub tab is left out.
function Sources.Rebuild()
	local catalogue, tools, creations = {}, {}, {}

	for _, tab in ipairs(spawnmenu.GetTools()) do
		for _, category in ipairs(istable(tab.Items) and tab.Items or {}) do
			for _, item in ipairs(category) do
				local key = istable(item) and isstring(item.ItemName) and "tool:" .. item.ItemName
				if key and not catalogue[key] then
					local e = {
						kind = "tool", key = key, name = item.ItemName, text = item.Text or item.ItemName,
						category = phrase(category.Text), item = item,
					}
					catalogue[key] = e
					tools[#tools + 1] = e
				end
			end
		end
	end

	for name, tab in pairs(spawnmenu.GetCreationTabs()) do
		if isstring(name) and name ~= Sources.HUB_TAB and isfunction(tab.Function) then
			local e = {
				kind = "creation", key = "creation:" .. name, name = name, text = name,
				icon = tab.Icon, order = tab.Order or 1000, tooltip = tab.Tooltip, fn = tab.Function,
			}
			catalogue[e.key] = e
			creations[#creations + 1] = e
		end
	end

	table.sort(tools, function(a, b)
		local ca, cb = a.category:lower(), b.category:lower()
		if ca ~= cb then return ca < cb end
		return phrase(a.text):lower() < phrase(b.text):lower()
	end)
	table.sort(creations, function(a, b)
		if a.order ~= b.order then return a.order < b.order end
		return a.name < b.name
	end)

	Sources.catalogue, Sources.tools, Sources.creations = catalogue, tools, creations
	hook.Run("PinnedPanelsCatalogChanged")
end

-- Our own fallback re-fires PostReloadToolsMenu; that must not rebuild the catalogue mid-build.
hook.Add("PostReloadToolsMenu", "PinnedPanels.Sources", function()
	if not Sources.inFallback then Sources.Rebuild() end
end)

function Sources.Get(src)
	return Sources.catalogue[src]
end

-- Resolved at call time so a language change shows up without a rebuild (L19).
function Sources.Title(src)
	local e = Sources.catalogue[src]
	if e then return phrase(e.text) end
	return phrase(src:match("^%a+:(.+)$") or src)
end

function Sources.DefaultSize(src)
	local size = DEFAULT_SIZE[src:match("^(%a+):")] or DEFAULT_SIZE.tool
	return size[1], size[2]
end

-- ── Content ─────────────────────────────────────────────────

-- The only global replacement in the addon (R5): while fn runs, controlpanel.Get(name) returns panel,
-- so hooks that fill a tool's panel by name fill ours (L2). The original is restored on every path.
function Sources.WithControlPanelFallback(name, panel, fn)
	local original = controlpanel.Get
	controlpanel.Get = function(n)
		if n == name then return panel end
		return original(n)
	end
	Sources.inFallback = true
	local ok, err = xpcall(fn, debug.traceback)
	Sources.inFallback = false
	controlpanel.Get = original
	if not ok then ErrorNoHalt("[Pinned Panels] " .. tostring(err) .. "\n") end
	return ok
end

-- Build functions are other addons' code: errors are printed and contained (R6, G38).
local function run(src, fn, ...)
	local ok, result = xpcall(fn, debug.traceback, ...)
	if ok then return true, result end
	ErrorNoHalt("[Pinned Panels] " .. src .. ": " .. tostring(result) .. "\n")
	return false, result
end

-- The same ControlPanel + FillViaTable the spawn menu uses (G14), inside a throttled scroll panel.
local function buildTool(e, parent)
	local scroll = vgui.Create("PinnedPanelsScroll", parent)
	scroll:Dock(FILL)
	if not isfunction(e.item.CPanelFunction) then
		local label = scroll:Add("DLabel")
		label:SetText(PP.L("pin.no_cp"))
		label:SetWrap(true)
		label:SetAutoStretchVertical(true)
		label:Dock(TOP)
		label:DockMargin(8, 8, 8, 8)
		label:SetTextColor(PP.Theme.textMuted)
		return scroll
	end

	local cp = scroll:Add("ControlPanel")
	cp:Dock(TOP)
	cp:SetAutoSize(true)
	if IsValid(cp.Header) then
		cp.Header:SetVisible(false)
		cp:SetHeaderHeight(0)
	end
	local before = #cp:GetChildren()
	local ok = run(e.key, cp.FillViaTable, cp, { Text = e.item.Text, ControlPanelBuildFunction = e.item.CPanelFunction })
	if not ok then
		scroll:Remove()
		return nil
	end
	if #cp:GetChildren() <= before then
		Sources.WithControlPanelFallback(e.name, cp, function() hook.Run("PostReloadToolsMenu") end)
	end
	return scroll
end

-- Each call returns a new, independent container (G13).
local function buildCreation(e, parent)
	local ok, panel = run(e.key, e.fn)
	if not ok then return nil end
	if not IsValid(panel) then
		ErrorNoHalt("[Pinned Panels] " .. e.key .. ": the content tab returned no panel\n")
		return nil
	end
	panel:SetParent(parent)
	panel:Dock(FILL)
	panel:SetMouseInputEnabled(true)
	return panel
end

-- Fills parent with src's content. Returns the content panel, or nil if src is unavailable or failed.
function Sources.Build(src, parent)
	local e = Sources.catalogue[src]
	if not e then return nil end
	if e.kind == "tool" then return buildTool(e, parent) end
	return buildCreation(e, parent)
end

-- "Equip" only ever runs a tool that resolved in the live catalogue (R4, G16, F35).
function Sources.CanEquip(src)
	local e = Sources.catalogue[src]
	return e ~= nil and e.kind == "tool" and isstring(e.item.Command) and e.item.Command ~= ""
end

function Sources.Equip(src)
	if not Sources.CanEquip(src) then return false end
	spawnmenu.ActivateTool(Sources.catalogue[src].name)
	return true
end
