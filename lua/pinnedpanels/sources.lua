-- The catalogue of pinnable things (§14): tools and Utilities option pages ("tool:<name>"), spawn-menu
-- content tabs ("creation:<name>"), post-process panels ("postprocess:<name>", G64) and the active tool
-- ("active:tool", FF1), rebuilt on every PostReloadToolsMenu
-- (G11). Builds their content. Quick controls ("quick:<n>", FF2) are built by Quick from their tab. Embedded
-- panels ("adopt:<n>", §33.6) aren't in the catalogue: Embed answers for them while it holds them.

local PP = PinnedPanels
PP.Sources = PP.Sources or {}
local Sources = PP.Sources

Sources.HUB_TAB = "#pinnedpanels.spawn.tab"
Sources.ACTIVE = "active:tool"
Sources.catalogue = Sources.catalogue or {}
Sources.tools = Sources.tools or {}
Sources.creations = Sources.creations or {}
Sources.natives = Sources.natives or {}
-- C-menu desktop widgets ("desktop:<id>", G47) are listed with the natives but aren't sources: pinning one
-- opens it as the C menu does and embeds it (Openers.PinDesktop).
Sources.desktops = Sources.desktops or {}
Sources.inFallback = false

local DEFAULT_SIZE = { tool = { 280, 400 }, creation = { 350, 560 }, postprocess = { 280, 400 }, active = { 280, 400 } }

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

	-- Built natively like tools: our tab gives the effect its control panel, and the active tool window shows
	-- whichever tool the tool gun has (FF1). Desktop widgets are listed here too.
	local natives, desktops = {}, {}
	local active = { kind = "active", key = Sources.ACTIVE, name = "tool", text = "#pinnedpanels.active.name", category = PP.L("native.toolgun") }
	catalogue[active.key] = active
	natives[1] = active
	for id, w in pairs(list.Get("DesktopWindows")) do
		if isstring(id) and istable(w) and isfunction(w.init) then
			local e = { kind = "desktop", key = "desktop:" .. id, name = id, text = isstring(w.title) and w.title or id, category = PP.L("native.desktop") }
			desktops[e.key] = e
			natives[#natives + 1] = e
		end
	end
	for name, pp in pairs(list.Get("PostProcess")) do
		if isstring(name) and istable(pp) and isfunction(pp.cpanel) then
			local e = { kind = "postprocess", key = "postprocess:" .. name, name = name, text = name, category = PP.L("native.postprocess"), cpanel = pp.cpanel }
			catalogue[e.key] = e
			natives[#natives + 1] = e
		end
	end

	local function byCategory(a, b)
		local ca, cb = a.category:lower(), b.category:lower()
		if ca ~= cb then return ca < cb end
		return phrase(a.text):lower() < phrase(b.text):lower()
	end
	table.sort(tools, byCategory)
	table.sort(natives, byCategory)
	table.sort(creations, function(a, b)
		if a.order ~= b.order then return a.order < b.order end
		return a.name < b.name
	end)

	Sources.catalogue, Sources.tools, Sources.creations, Sources.natives, Sources.desktops = catalogue, tools, creations, natives, desktops
	hook.Run("PinnedPanelsCatalogChanged")
end

-- Our own fallback re-fires PostReloadToolsMenu; that must not rebuild the catalogue mid-build.
hook.Add("PostReloadToolsMenu", "PinnedPanels.Sources", function()
	if not Sources.inFallback then Sources.Rebuild() end
end)

local function adopted(src)
	return src:sub(1, 6) == "adopt:"
end

local QUICK = { kind = "quick" }
local function quick(src)
	return src:sub(1, 6) == "quick:"
end

function Sources.Get(src)
	if adopted(src) then return PP.Embed.live[src] end
	if quick(src) then return QUICK end
	return Sources.catalogue[src]
end

-- Resolved at call time so a language change shows up without a rebuild (L19).
function Sources.Title(src)
	if quick(src) then return PP.L("quick.title") end
	local e = Sources.catalogue[src] or Sources.desktops[src]
	if e and e.kind == "active" then
		local tool = Sources.ActiveTool()
		return PP.L("active.title", tool and phrase(tool.text) or PP.L("active.no_tool"))
	end
	if e then return phrase(e.text) end
	return phrase(src:match("^%a+:(.+)$") or src)
end

-- The catalogue entry of the tool selected on the tool gun, if it is one we know.
function Sources.ActiveTool()
	local mode = GetConVar("gmod_toolmode")
	return mode and Sources.catalogue["tool:" .. mode:GetString()] or nil
end

function Sources.DefaultSize(src)
	local size = DEFAULT_SIZE[src:match("^(%a+):")] or DEFAULT_SIZE.tool
	return size[1], size[2]
end

-- ── Content ─────────────────────────────────────────────────

-- While fn runs, controlpanel.Get(name) returns panel, so hooks that fill a tool's panel by name fill ours
-- (L2). Util.WithOverride restores the original on every path (R5).
function Sources.WithControlPanelFallback(name, panel, fn)
	local original = controlpanel.Get
	Sources.inFallback = true
	local ok = PP.Util.WithOverride(controlpanel, "Get", function(n)
		if n == name then return panel end
		return original(n)
	end, fn)
	Sources.inFallback = false
	return ok
end

-- Build functions are other addons' code: errors are printed and contained (R6, G38).
local function run(src, fn, ...)
	local ok, result = xpcall(fn, debug.traceback, ...)
	if ok then return true, result end
	ErrorNoHalt("[Pinned Panels] " .. src .. ": " .. tostring(result) .. "\n")
	return false, result
end

-- A ControlPanel like the spawn menu's, headerless, inside a throttled scroll panel (L3).
function Sources.ControlPanel(parent)
	local scroll = vgui.Create("PinnedPanelsScroll", parent)
	scroll:Dock(FILL)
	local cp = scroll:Add("ControlPanel")
	cp:Dock(TOP)
	cp:SetAutoSize(true)
	if IsValid(cp.Header) then
		cp.Header:SetVisible(false)
		cp:SetHeaderHeight(0)
	end
	return scroll, cp
end

local controlPanel = Sources.ControlPanel

-- The same ControlPanel + FillViaTable the spawn menu uses (G14).
-- A tab that only says why it is empty.
local function notice(parent, text)
	local scroll = vgui.Create("PinnedPanelsScroll", parent)
	scroll:Dock(FILL)
	local label = scroll:Add("DLabel")
	label:SetText(text)
	label:SetWrap(true)
	label:SetAutoStretchVertical(true)
	label:Dock(TOP)
	label:DockMargin(8, 8, 8, 8)
	label:SetTextColor(PP.Theme.textMuted)
	return scroll
end

-- Some tools keep hold of the first control panel they are given and fill that one from then on
-- (Falco's Prop Protection: `AdminPanel = AdminPanel or Panel`). Removing ours leaves them holding
-- nothing, and their page errors from then on, in the spawn menu as well, until the map changes. So a
-- page whose builder still refers to our panel isn't removed with its tab: it is hidden, and shown
-- again wherever the tool is next pinned.
Sources.kept = Sources.kept or {} -- key -> the scroll panel holding the page
local MAX_UPVALUES = 30

local function holds(fn, panel)
	if not debug.getupvalue then return false end
	for i = 1, MAX_UPVALUES do
		local ok, name, v = pcall(debug.getupvalue, fn, i)
		if not ok or name == nil then break end
		if v == panel then return true end
	end
	return false
end

local function buildTool(e, parent)
	if not isfunction(e.item.CPanelFunction) then return notice(parent, PP.L("pin.no_cp")) end

	local kept = Sources.kept[e.key]
	if IsValid(kept) then
		kept:SetParent(parent)
		kept:Dock(FILL)
		kept:SetVisible(true)
		return kept
	end

	local scroll, cp = controlPanel(parent)
	local before = #cp:GetChildren()
	local ok = run(e.key, cp.FillViaTable, cp, { Text = e.item.Text, ControlPanelBuildFunction = e.item.CPanelFunction })
	if not ok then
		scroll:Remove()
		return nil
	end
	if #cp:GetChildren() <= before then
		Sources.WithControlPanelFallback(e.name, cp, function() hook.Run("PostReloadToolsMenu") end)
	end
	if holds(e.item.CPanelFunction, cp) then Sources.kept[e.key] = scroll end
	return scroll
end

-- A post-process entry's cpanel fills a control panel, as its spawn-menu icon does (G64).
local function buildPostProcess(e, parent)
	local scroll, cp = controlPanel(parent)
	if not run(e.key, e.cpanel, cp) then
		scroll:Remove()
		return nil
	end
	return scroll
end

-- The active tool window builds the current tool's panel; the desktop rebuilds it when the tool changes.
local function buildActive(_, parent)
	local tool = Sources.ActiveTool()
	if not tool then return notice(parent, PP.L("active.none")) end
	return buildTool(tool, parent)
end

local BUILDERS = { tool = buildTool, postprocess = buildPostProcess, active = buildActive }

-- Each call returns a new, independent container (G13). Nearly always: a tab that registers console
-- commands while it builds has just pointed them at our copy, away from the spawn menu's, and the player
-- is told once that this tab is better pinned from the spawn menu with the picker (D38).
local warned = {}
local function buildCreation(e, parent)
	local commands = {}
	for name, fn in pairs(concommand.GetTable()) do commands[name] = fn end
	local ok, panel = run(e.key, e.fn)
	if not warned[e.key] then
		for name, fn in pairs(concommand.GetTable()) do
			if commands[name] and commands[name] ~= fn then
				warned[e.key] = true
				notification.AddLegacy(PP.L("source.singleton", Sources.Title(e.key)), NOTIFY_HINT, 10)
				break
			end
		end
	end
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
	if adopted(src) then return PP.Embed.Build(src, parent) end
	if quick(src) then return PP.Quick.Build(src, parent) end
	local e = Sources.catalogue[src]
	if not e then return nil end
	return (BUILDERS[e.kind] or buildCreation)(e, parent)
end

-- Before a tab host clears or removes its content: an embedded panel's box goes back to Embed, since
-- other addons' panels are never removed with our controls (R15).
function Sources.Unbuild(src, content)
	if adopted(src) then return PP.Embed.Unbuild(src, content) end
	-- A page its tool holds on to is taken out before the host clears itself (see Sources.kept).
	if Sources.kept[src] == content and IsValid(content) then
		content:SetVisible(false)
		content:SetParent(nil)
	end
end

-- "Equip" only ever runs a tool that resolved in the live catalogue (R4, G16, F35).
function Sources.CanEquip(src)
	local e = Sources.catalogue[src]
	return e ~= nil and e.kind == "tool" and isstring(e.item.Command) and e.item.Command ~= ""
end

-- The tool gun mode a tab is about, for server restrictions (FF13): a tool, or the active tool, never an
-- option page.
function Sources.ToolName(src)
	local e = src == Sources.ACTIVE and Sources.ActiveTool() or Sources.catalogue[src]
	if e and Sources.CanEquip(e.key) then return e.name end
end

function Sources.Equip(src)
	if not Sources.CanEquip(src) then return false end
	spawnmenu.ActivateTool(Sources.catalogue[src].name)
	return true
end
