-- Adopted panels' identity and return (§33.8, §33.9): a panel's signature, the refusals (R11), how a pinned
-- panel comes back (its recipe) and catching it when it appears. Taking and releasing a panel is Embed's
-- job; this file decides which panel and when. What opened a window is trace.lua.

local PP = PinnedPanels
PP.Recipes = PP.Recipes or {}
local Recipes = PP.Recipes
local Layout, Desktop = PP.Layout, PP.Desktop

local CATCH_TIMER, CATCH_INTERVAL, HUD_EVERY = "PinnedPanels.Catch", 0.5, 2
local SCAN_LIMIT = 200
local MAX_TITLE = 64
local OPEN_GRACE = 3 -- seconds in which a window we opened ourselves is expected

-- Files whose functions say nothing about who made a panel: Derma, the base libraries and us.
local STOCK_DIRS = { "lua/vgui/", "lua/derma/", "lua/includes/", "lua/pinnedpanels/" }
local PREFERRED = { "Init", "Paint", "PerformLayout", "OnClose", "Think" }
local TRANSIENT = { DMenu = true, DMenuOption = true, DTooltip = true, DMenuBar = true }

-- ── Signature (§33.8) ───────────────────────────────────────

local function isStock(src)
	if not src or src == "" then return true end
	local first = src:sub(1, 1)
	if first == "[" or first == "=" then return true end
	for _, dir in ipairs(STOCK_DIRS) do
		if src:sub(1, #dir) == dir then return true end
	end
	return false
end

-- A function's file never changes, and the walk below asks about every function of up to SCAN_LIMIT
-- panels: each is looked up once.
local files = setmetatable({}, { __mode = "k" })
local function fileOf(fn)
	local src = files[fn]
	if src == nil then
		local info = debug.getinfo(fn, "S")
		src = info and info.short_src or false
		files[fn] = src
	end
	return src or nil
end
Recipes.FileOf = fileOf

-- The file of a panel's own functions (G62), other than skip: the preferred ones first, else the first
-- file by name so the answer is the same every time.
local function ownFile(p, skip)
	local t = p:GetTable()
	for _, name in ipairs(PREFERRED) do
		local fn = rawget(t, name)
		local src = isfunction(fn) and fileOf(fn)
		if src and src ~= skip and not isStock(src) then return src end
	end
	local best
	for _, fn in pairs(t) do
		if isfunction(fn) then
			local src = fileOf(fn)
			if src ~= skip and not isStock(src) and (not best or src < best) then best = src end
		end
	end
	return best
end

-- The file that built a panel: its own functions, else its children's (a plain DFrame whose buttons have
-- DoClick functions), breadth first. Then a second file from the same walk, if there is one: a window
-- made by a UI library has the library's file first, and what tells it from that library's other
-- windows is whose code filled it (D28).
function Recipes.SourceFile(panel)
	local queue, head, src = { panel }, 1, nil
	while queue[head] and head <= SCAN_LIMIT do
		local p = queue[head]
		head = head + 1
		src = src or ownFile(p)
		local other = src and ownFile(p, src)
		if other then return src, other end
		for _, c in ipairs(p:GetChildren()) do queue[#queue + 1] = c end
	end
	return src
end

-- The Workshop addon or gamemode a file comes from (G63), nil for the base game. Cached per file.
local addons = {}
function Recipes.Addon(src)
	if not src then return nil end
	if addons[src] ~= nil then return addons[src] or nil end
	local name = src:match("^addons/([^/]+)/") or src:match("^gamemodes/([^/]+)/")
	if not name then
		for _, a in ipairs(engine.GetAddons()) do
			if a.mounted and file.Exists(src, a.title) then
				name = a.title
				break
			end
		end
	end
	addons[src] = name or false
	return name
end

-- Stock controls (G54) and ours don't identify anything. A class is stock when none of its functions
-- comes from an addon: being registered through Derma doesn't make it so, addons do that too (G68).
local stock = {}
local function isStockClass(class)
	if class:sub(1, 12) == "PinnedPanels" then return true end
	if stock[class] == nil then
		local found = true
		for _, fn in pairs(vgui.GetControlTable(class) or {}) do
			if isfunction(fn) and not isStock(fileOf(fn)) then
				found = false
				break
			end
		end
		stock[class] = found
	end
	return stock[class]
end

local function titleOf(p)
	if not isfunction(p.GetTitle) then return nil end
	-- A frame that removed its title label still has DFrame's GetTitle, which reads it (G70, R18).
	local ok, title = pcall(p.GetTitle, p)
	if not ok or not isstring(title) or title == "" then return nil end
	return title:sub(1, MAX_TITLE)
end

-- class is kept only when it says more than the stock base it came from (G42, G53).
function Recipes.Signature(panel)
	local class = panel.ClassName
	if not isstring(class) or isStockClass(class) then class = nil end
	local base = panel.Base or panel.ClassName or panel:GetClassName()
	local src, src2 = Recipes.SourceFile(panel)
	local w, h = panel:GetSize()
	return {
		src = src, src2 = src2, addon = Recipes.Addon(src), class = class, base = isstring(base) and base or nil,
		title = titleOf(panel), w = w, h = h, hud = panel:GetParent() ~= vgui.GetWorldPanel(), popup = panel:IsPopup(),
		desktop = PP.Openers.DesktopId(panel),
	}
end

-- How well a live panel's signature (cand) matches a saved one: nil when it can't be that panel.
-- Strong when the file or class agrees and nothing else disagrees; a weak match asks the player once.
function Recipes.Match(sig, cand)
	-- A desktop widget's window is known by the widget it is (G47).
	if sig.desktop then
		if cand.desktop ~= sig.desktop then return nil end
		return 10, true
	end
	if sig.src and cand.src ~= sig.src then return nil end
	if sig.class and cand.class ~= sig.class then return nil end
	local strong = sig.src ~= nil or sig.class ~= nil
	local sameTitle = sig.title ~= nil and cand.title == sig.title
	if not strong and not sameTitle then return nil end
	-- One file can make several windows: without a class, another title makes it a question. An addon's
	-- update can also rename its window.
	if not sig.class and sig.title and cand.title and not sameTitle then strong = false end
	-- Other files in its tree: likely another window of the same library. A question, not a refusal,
	-- since a window filled differently this time shows the same way (D28).
	local sameTree = sig.src2 ~= nil and cand.src2 == sig.src2
	if sig.src2 and not sameTree then strong = false end
	local score = (sig.src and 4 or 0) + (sig.class and 3 or 0) + (sameTitle and 2 or 0) + (sameTree and 2 or 0)
	if sig.w and math.abs(cand.w - sig.w) < 8 and math.abs(cand.h - sig.h) < 8 then score = score + 1 end
	return score, strong
end

local sheetTabName

local function phrase(text)
	if text:sub(1, 1) ~= "#" then return text end
	return language.GetPhrase(text:sub(2))
end

-- A name for lists: the window title, else its class, else its addon.
-- Parts everyone knows by another name than their class.
local NAMES = { CreationMenu = "name.creation_menu", ToolMenu = "name.tool_menu" }

-- A class as words: "ContentContainer" → "Content Container", "xlib_Panel" → "xlib Panel".
local function spaced(class)
	return (class:gsub("_", " "):gsub("(%l)(%u)", "%1 %2"))
end

function Recipes.Title(adopt)
	local s = adopt.signature
	-- A part is named after itself, not after the window it came from: two parts of the spawn menu are
	-- the creation menu and the tool menu, not twice "sandbox". A stock class says nothing, so then the
	-- window does.
	local last = s.path and s.path[#s.path]
	if last and isstring(last.class) and not isStockClass(last.class) then
		return NAMES[last.class] and PP.L(NAMES[last.class]) or spaced(last.class)
	end
	if s.title then return phrase(s.title) end
	if s.desktop then return PP.Sources.Title("desktop:" .. s.desktop) end
	-- Its addon says more than a class like "xlib_Panel" does.
	return s.addon or (s.class and spaced(s.class)) or PP.L("adopt.window")
end

-- A live panel's name, for the picker: its title, else its class or base.
function Recipes.SigTitle(sig)
	if sig.title then return phrase(sig.title) end
	return sig.class or sig.base or PP.L("adopt.window")
end

function Recipes.AddonName(sig)
	return sig.addon or PP.L("adopt.base_game")
end

-- ── What can be taken (R11) ─────────────────────────────────

-- Every panel that is a window somewhere: the world panel's children (G41), and the children of other
-- roots such as the one ParentToHUD uses, which only vgui.GetAll() reaches (G51). Not for every frame.
function Recipes.HudPanels()
	local world, out = vgui.GetWorldPanel(), {}
	for _, p in ipairs(vgui.GetAll()) do
		local parent = p:GetParent()
		if IsValid(parent) and parent ~= world and not IsValid(parent:GetParent()) then out[#out + 1] = p end
	end
	return out
end

function Recipes.TopLevels()
	local out = vgui.GetWorldPanel():GetChildren()
	for _, p in ipairs(Recipes.HudPanels()) do out[#out + 1] = p end
	return out
end

local function ours(p)
	while IsValid(p) do
		if p.ppTakesKeyboard or p.ppOurs or (isstring(p.ClassName) and p.ClassName:sub(1, 12) == "PinnedPanels") then return true end
		p = p:GetParent()
	end
	return false
end

-- Whether a panel is already pinned: an embedded window's shell or an embedded panel.
function Recipes.Owner(p)
	return PP.Embed.shells[p] or PP.Embed.byPanel[p]
end

-- A menu of any class: addons with their own menu controls still mark them as Derma's do. The option
-- list tells a menu from a combo box, which carries the same mark.
local function isMenu(p)
	return p.m_bIsMenuComponent == true and isfunction(p.AddOption)
end

-- A full-screen panel that paints itself is a scene over the world (a character screen, a weapon
-- bench), not a window (D32).
-- So is a full-screen layer that isn't a window at all: a web page over the whole screen (an addon's
-- HUD drawn in HTML), or anything that size that takes no clicks.
local WEB = { HTML = true, HtmlPanel = true, Awesomium = true, Chromium = true }
local function isScene(p)
	if p:GetWide() < ScrW() or p:GetTall() < ScrH() then return false end
	if WEB[p:GetClassName()] or not p:IsMouseInputEnabled() then return true end
	return isfunction(p.Paint) and not isStock(fileOf(p.Paint))
end

-- The spawn menu and the C menu: made once by the gamemode and kept, shown and hidden with their keys.
-- They can't be pinned whole, a part of them can, and nothing has to open them: they are always there.
function Recipes.IsMenuRoot(p)
	return p == g_SpawnMenu or p == g_ContextMenu
end

-- Making another one of these is never how a pin comes back.
local function menuRootClass(class)
	return (IsValid(g_SpawnMenu) and g_SpawnMenu.ClassName == class) or (IsValid(g_ContextMenu) and g_ContextMenu.ClassName == class)
end

-- Why panel (root's window, or root itself) can't be pinned: a code ("refuse.root", …), or nil. The
-- codes were once shown to the player; the picker now passes over what can't be pinned (X55).
function Recipes.Refusal(panel, root)
	if not IsValid(panel) or panel:IsMarkedForDeletion() then return "refuse.gone" end
	if ours(panel) then return "refuse.ours" end
	if TRANSIENT[panel.ClassName] or isMenu(panel) then return "refuse.transient" end
	local p = panel
	while IsValid(p) do
		if p:IsModal() then return "refuse.modal" end
		p = p:GetParent()
	end
	if Recipes.Owner(panel) then return "refuse.pinned" end
	if panel == root and (panel == g_SpawnMenu or panel == g_ContextMenu or panel == GetHUDPanel()) then return "refuse.root" end
	if isScene(panel) then return "refuse.scene" end
end

local function classOf(p)
	return p.ClassName or p:GetClassName()
end

-- ── What is worth pinning (X55) ─────────────────────────────
-- A player pins something to keep using or watching it while playing: a window, a page, a list, a
-- group of settings, a preview, a map, and also one thing to click out of any of those: a button, a
-- spawn icon, a tick box, a slider, a row of a list. What is never offered is what nobody would use
-- alone: the pieces a control is built from (a scroll bar, a divider's bar, a sheet's strip of tabs),
-- plain text and pictures that take no click, and holders with nothing in them. The picker offers only
-- what passes here.

-- A panel is known by its class or any class that one is based on (an addon's "ContentIcon" is a
-- DButton), down to the engine's own. The nearest one that says something decides.

-- Something by itself, however little is in it. A model preview is a DButton, but not one to click.
local WHOLE = {}
for _, c in ipairs({
	"DModelPanel", "DHTML", "HTML", "HtmlPanel", "Awesomium", "Chromium", "RichText", "DListView", "DTree", "DProperties",
	"DColorMixer", "DFileBrowser", "DIconBrowser",
}) do WHOLE[c] = true end

-- A piece of a control: no use without the rest of it.
local PIECE = {}
for _, c in ipairs({
	"DScrollBarGrip", "DVScrollBar", "DHScrollBar", "DHorizontalScroller", "DHorizontalDividerBar", "DVerticalDividerBar",
	"DListView_Column", "DListView_DraggerBar", "DListViewLabel", "DListViewHeaderLabel", "DTree_Node_Button",
	"DCategoryHeader", "DExpandButton", "DMenuOption", "DMenuBar", "DTooltip", "DBubbleContainer", "DPanelOverlay", "DNotify",
	"ScrollBar", "ScrollBarSlider", "MenuItem",
}) do PIECE[c] = true end

-- One thing to click, drag or type in.
local CLICK = {}
for _, c in ipairs({
	"DButton", "DCheckBoxLabel", "DNumSlider", "DNumberScratch", "DSlider", "DTextEntry", "DNumPad", "DRGBPicker", "DAlphaBar",
	"DListViewLine", "DListView_Line", "DListBoxItem", "DTree_Node", "DProperty_Generic", "ImageCheckBox", "DLabelURL",
	"Button", "CheckButton", "RadioButton", "ToggleButton", "Slider", "TextEntry", "URLLabel",
}) do CLICK[c] = true end

-- Text or a picture: only something to pin when an addon made it take clicks.
local SHOWN = {}
for _, c in ipairs({
	"DLabel", "DImage", "DSprite", "DShape", "DKillIcon", "DProgress", "ModelImage", "Label", "ImagePanel", "Material",
}) do SHOWN[c] = true end

local MIN_PART_W, MIN_PART_H = 80, 40   -- a holder smaller than this is a row
local MIN_CLICK_W, MIN_CLICK_H = 12, 12 -- one control can be as small as a tick box

-- A class and the ones it is based on, nearest first, ending with the engine's.
function Recipes.Lineage(p)
	local out, seen = {}, {}
	local c = isstring(p.ClassName) and p.ClassName or (isstring(p.Base) and p.Base) or nil
	while isstring(c) and not seen[c] and #out < 24 do
		seen[c] = true
		out[#out + 1] = c
		local t = vgui.GetControlTable(c)
		c = t and t.Base
	end
	local engine = p:GetClassName()
	if not seen[engine] then out[#out + 1] = engine end
	return out
end

local kinds = {} -- nearest Lua class -> "whole", "piece", "click", "shown" or false (a holder)
local function kindOf(p)
	local key = isstring(p.ClassName) and p.ClassName or (isstring(p.Base) and p.Base) or p:GetClassName()
	local k = kinds[key]
	if k == nil then
		k = false
		for _, c in ipairs(Recipes.Lineage(p)) do
			k = WHOLE[c] and "whole" or PIECE[c] and "piece" or CLICK[c] and "click" or SHOWN[c] and "shown"
			if k then break end
		end
		kinds[key] = k or false
	end
	return k
end

local shown = PP.Util.Drawn

-- Whether an addon gave p something to do when clicked: a label or a bare panel used as a button.
local HANDLERS = { "DoClick", "DoRightClick", "DoDoubleClick", "OnMousePressed", "OnMouseReleased" }
local function handlesClicks(p)
	for _, name in ipairs(HANDLERS) do
		local fn = p[name]
		if isfunction(fn) and not isStock(fileOf(fn)) then return true end
	end
	return false
end

-- Whether p is one thing to click.
local function clickable(p, k)
	if not p:IsMouseInputEnabled() then return false end
	return k == "click" or ((k == "shown" or k == false) and handlesClicks(p))
end

-- Whether there is something in a holder: it holds at least two things, the one thing it holds has
-- something in it, or it is empty but draws itself with an addon's code (a map, a graph).
local function substance(p, depth)
	local k = kindOf(p)
	if k == "whole" then return true end
	if k then return clickable(p, k) end
	local n, only = 0, nil
	for _, c in ipairs(p:GetChildren()) do
		if shown(c) then
			n, only = n + 1, c
			if n > 1 then return true end
		end
	end
	if n == 0 then return (isfunction(p.Paint) and not isStock(fileOf(p.Paint))) or clickable(p, k) end
	return depth < 6 and substance(only, depth + 1)
end

-- What one control is called: what is written on it, else what a spawn icon is of, else its class.
-- nil for anything that isn't one control.
function Recipes.ControlName(p)
	if kindOf(p) ~= "click" then return nil end
	local tries = {
		function() return p:GetText() end,
		function() return p.m_NiceName end,
		function() return p:GetTooltip() end,
		function() return string.StripExtension(string.GetFileFromFilename(p:GetModelName())) end,
	}
	for _, try in ipairs(tries) do
		local ok, text = pcall(try)
		if ok and isstring(text) and text:Trim() ~= "" then
			text = text:Trim()
			if text:sub(1, 1) == "#" then text = language.GetPhrase(text:sub(2)) end
			return text:sub(1, MAX_TITLE)
		end
	end
	return Recipes.Lineage(p)[1]
end

-- Whether a part is worth a window of its own.
function Recipes.Worth(panel)
	local w, h = panel:GetSize()
	local k = kindOf(panel)
	if k == "piece" then return false end
	if clickable(panel, k) then return w >= MIN_CLICK_W and h >= MIN_CLICK_H end
	if w < MIN_PART_W or h < MIN_PART_H then return false end
	-- A scroll panel's canvas is the scroll panel (Recipes.Take).
	local parent = panel:GetParent()
	local ok, canvas = pcall(function() return isfunction(parent.GetCanvas) and parent:GetCanvas() end)
	if ok and canvas == panel then return false end
	return substance(panel, 0)
end

-- Whether the picker offers panel: nothing refuses it, and a part of a window is worth pinning.
function Recipes.Pickable(panel, root)
	if Recipes.Refusal(panel, root) then return false end
	return panel == root or Recipes.Worth(panel)
end

-- A part's place in its window, from the root down (§33.8): at each step the child's class, which one of
-- its parent's children of that class it is (n), and its place among all of them (i). The place alone
-- doesn't hold: the spawn menu's children aren't in the same order from one session to the next (X49).
function Recipes.Path(root, part)
	local path, p = {}, part
	while p ~= root do
		local parent = p:GetParent()
		local class, n = classOf(p), 0
		for i, c in ipairs(parent:GetChildren()) do
			if classOf(c) == class then n = n + 1 end
			if c == p then
				table.insert(path, 1, { i = i, n = n, class = class })
				break
			end
		end
		p = parent
	end
	return path
end

-- The same part in a window made again, or nil when the window is laid out differently now. A step is
-- the n-th child of its class; a path saved before n was kept takes the child at its old place if the
-- class agrees, else the only child of that class.
function Recipes.FollowPath(root, path)
	local p = root
	for _, step in ipairs(path) do
		local kids = p:GetChildren()
		local found
		if not step.class then
			found = kids[step.i]
		else
			local same = {}
			for _, c in ipairs(kids) do
				if classOf(c) == step.class then same[#same + 1] = c end
			end
			if step.n then
				found = same[step.n]
			else
				local at = kids[step.i]
				found = (IsValid(at) and classOf(at) == step.class) and at or (#same == 1 and same[1] or nil)
			end
		end
		if not IsValid(found) then return nil end
		p = found
	end
	return p
end

-- ── Suggestions ─────────────────────────────────────────────

-- The window a picked panel belongs to: its top-level panel, or a desktop widget's window, which is a child
-- of the C menu rather than top-level (G47).
function Recipes.RootFor(panel, root)
	local p = panel
	while IsValid(p) and p ~= root do
		if PP.Openers.DesktopId(p) then return p end
		p = p:GetParent()
	end
	return root
end

-- Whether a panel is a window: just below a root (the world panel, or the HUD's), or a desktop widget's
-- window in the C menu (G47).
function Recipes.IsWindow(p)
	local parent = p:GetParent()
	return not IsValid(parent) or not IsValid(parent:GetParent()) or PP.Openers.DesktopId(p) ~= nil
end

-- What pinning panel (root, or a part of root) would do (§33.9): embed it. A desktop widget's own window
-- comes back by being opened as the C menu does; anything else through the command that is tied to it
-- (Openers.Best), else when its addon opens it. Recreating its class is never suggested, only offered
-- (Recipes.Choices): most windows need what their opener does around the panel (D26).
function Recipes.Suggest(panel, root)
	local sig = Recipes.Signature(root)
	local info = { mode = panel ~= root and "part" or "embed", part = panel ~= root, signature = sig }
	-- A part of the spawn menu or the C menu: nothing opens those, they are made once and kept. A
	-- command from the gamemode's files was once guessed for them (a tool panel that "reopened" with
	-- the player model window's command).
	if Recipes.IsMenuRoot(root) then
		info.commands, info.always, info.recipe = {}, true, { kind = "watch" }
		return info
	end
	info.commands = PP.Openers.Commands(sig)
	local best = PP.Openers.Best(info.commands)
	-- The command it was seen being opened by is no guess (Trace, Z3): it comes before the best guess.
	local seen = PP.Trace and PP.Trace.Of(root)
	if sig.desktop then
		info.recipe = { kind = "desktop", id = sig.desktop }
	elseif seen then
		info.recipe = seen
	elseif best then
		info.recipe = { kind = "command", command = best, confirmed = true }
	else
		info.recipe = { kind = "watch" }
	end
	return info
end

-- The recipes the player can choose instead, the suggested one first. Commands chosen here are the
-- player's own choice, so they are allowed (R16 only holds back imported ones).
function Recipes.Choices(info)
	local list = { info.recipe }
	local function add(r)
		if r.kind ~= info.recipe.kind or r.command ~= info.recipe.command then list[#list + 1] = r end
	end
	local class = info.signature.class
	if info.signature.desktop then add({ kind = "desktop", id = info.signature.desktop }) end
	if class and vgui.GetControlTable(class) and not menuRootClass(class) then add({ kind = "class", class = class }) end
	for _, c in ipairs(info.commands) do add({ kind = "command", command = c.name, confirmed = true }) end
	add({ kind = "watch" })
	add({ kind = "session" })
	return list
end

-- The name on the tab that shows panel, when panel is a page of a tab sheet.
function sheetTabName(panel)
	local sheet = panel:GetParent()
	local items = IsValid(sheet) and sheet.Items
	if not istable(items) then return nil end
	for _, item in pairs(items) do
		if istable(item) and item.Panel == panel then
			local name = item.Name
			if not isstring(name) and IsValid(item.Tab) then name = item.Tab:GetText() end
			if isstring(name) and name ~= "" then return phrase(name) end
		end
	end
end

Recipes.SheetTabName = sheetTabName

-- What is written at the top of a category ("Construction", in the tool list).
local function headerName(panel)
	local header = panel.Header
	if ispanel(header) and IsValid(header) and isfunction(header.GetText) then
		local text = phrase(header:GetText():Trim())
		if text ~= "" then return text:sub(1, MAX_TITLE) end
	end
end

-- What a live panel is called where the player chooses one (the picker's card and list, the pin
-- button's): what is written on a control, the tab that shows a page, what is written at the top of a
-- category, the name everyone knows it by, its title, else its own class ("DColorMixer" says more
-- than the "DPanel" a signature keeps for it).
function Recipes.PartName(panel)
	local control = Recipes.ControlName(panel)
	if control then return control end
	local tab = sheetTabName(panel)
	if tab then return tab end
	local header = headerName(panel)
	if header then return header end
	local class = Recipes.Lineage(panel)[1]
	if NAMES[class] then return PP.L(NAMES[class]) end
	local title = titleOf(panel)
	if title then return phrase(title) end
	-- A window without a title of its own is called what its pin will be: after its addon ("ULX" says
	-- more than "xlib_Panel", "Rareload" more than "DFrame").
	if Recipes.IsWindow(panel) then return Recipes.Title({ signature = Recipes.Signature(panel) }) end
	return class or PP.L("adopt.window")
end

-- Pins panel (root, or a part of root) in the given mode with the given recipe. Returns the window id.
-- waiting: the pinned window is made now and takes the panel when it is caught.
function Recipes.Take(panel, root, mode, recipe, waiting)
	-- A scroll panel's canvas is a piece of it, not a panel of its own: taken alone, its owner can no
	-- longer scroll it or reach what is in it (a tool list stops clearing its selected row). The scroll
	-- panel is what is meant.
	while panel ~= root do
		local parent = panel:GetParent()
		local ok, canvas = pcall(function() return isfunction(parent.GetCanvas) and parent:GetCanvas() end)
		if not (ok and canvas == panel) then break end
		panel = parent
	end
	if panel == root and mode == "part" then mode = "embed" end
	-- A tool's page in the spawn menu is the spawn menu's: it takes the page back and lays it out again
	-- every time the tool is chosen. The tool itself is pinned instead, with a page of its own.
	if panel.ClassName == "ControlPanel" and isstring(panel.Name) and PP.Sources.catalogue["tool:" .. panel.Name] then
		return Desktop.PinSource("tool:" .. panel.Name)
	end
	-- Only a window is taken whole. A panel that sits inside one by now (a tool's page, recorded as it
	-- was made and then put in the spawn menu) is a part of it: emptied like a window, its children
	-- would lose the parent they call into.
	if mode ~= "part" and not Recipes.IsWindow(root) then
		panel, mode = root, "part"
		while not Recipes.IsWindow(root) do root = root:GetParent() end
	end
	local adopt = { mode = mode, recipe = recipe, signature = Recipes.Signature(root), needsKeyboard = root:IsKeyboardInputEnabled() }
	if mode == "part" then adopt.signature.path = Recipes.Path(root, panel) end
	-- A page of a tab sheet is called what its tab is called ("Weapons"), which its class never says.
	local name = mode == "part" and sheetTabName(panel)
	-- One control is called what is written on it ("Weld"), not what its window is.
	if mode == "part" and not name then name = Recipes.ControlName(panel) or headerName(panel) end
	local id = PP.Embed.Take(mode == "part" and panel or root, adopt, waiting)
	if id and name then Layout.Rename(id, 1, name) end
	return id
end

-- A line saying how a pinned panel comes back.
function Recipes.Describe(adopt)
	local r = adopt.recipe
	if adopt.always then return PP.L("recipe.always") end
	if r.kind == "class" then return PP.L("recipe.class", r.class) end
	if r.kind == "desktop" then return PP.L("recipe.desktop", PP.Sources.Title("desktop:" .. r.id)) end
	-- A command nobody allowed (a layout imported before commands were asked about at import, Z6) isn't
	-- run: the pin waits for its addon like one without a command.
	if r.kind == "command" and r.confirmed then
		return PP.L("recipe.command", r.args and r.command .. " " .. r.args or r.command)
	end
	return PP.L(r.kind == "session" and "recipe.session" or "recipe.watch")
end

-- What to say about a pin whose window isn't open, in a list: that it isn't, and how it comes back.
function Recipes.Status(adopt)
	if Recipes.CanOpen(adopt) then return PP.L("status.reopens") end
	return PP.L("status.waits", Recipes.AddonName(adopt.signature))
end

-- ── Waiting and catching (§33.9) ────────────────────────────

-- Whether tab (of window rec) has its panel now.
function Recipes.IsLive(rec, tab)
	return PP.Embed.live[tab.src] ~= nil
end

-- Adopted tabs waiting for their panel, once the desktop knows which windows are held. Hidden windows
-- don't wait: their panels stay the addon's.
function Recipes.Waiting()
	local out = {}
	if not Desktop.ready then return out end
	for _, rec in ipairs(Layout.Windows()) do
		if not Desktop.held[rec.id] then
			for i, tab in ipairs(rec.tabs) do
				if tab.adopt and not Recipes.IsLive(rec, tab) then out[#out + 1] = { rec = rec, index = i, tab = tab } end
			end
		end
	end
	return out
end

-- Whether file is of the window signed sig, or of the same addon.
local function sameMaker(sig, file)
	if sig.src == file or sig.src2 == file then return true end
	return sig.addon ~= nil and Recipes.Addon(file) == sig.addon
end

Recipes.SameMaker = sameMaker

-- Whether a window we hold now was made by file or by its addon: a screen clicker asked for from there
-- is asked for one of our windows (Input, X51).
function PP.Input.clickerHeld(file)
	for _, rec in ipairs(Layout.Windows()) do
		for _, tab in ipairs(rec.tabs) do
			if tab.adopt and Recipes.IsLive(rec, tab) and sameMaker(tab.adopt.signature, file) then return true end
		end
	end
	return false
end

-- The window signed sig is being taken. If it is its addon that turned the screen clicker on, to show a
-- cursor for it, the clicker stops being someone else's: left on, it would keep every window taking
-- the mouse with cursor mode off, for as long as the window is pinned. Returns whether it was.
function Recipes.TakeClicker(sig)
	local by = PP.Input.foreignClicker and PP.Input.foreignClickerBy
	if not by or not sameMaker(sig, by) then return false end
	PP.Input.DropForeignClicker()
	return true
end

-- Gives a caught window to its waiting tab, which takes it whole or the part at its path; opened means
-- the player just opened it. Only a window that showed a cursor brings it (a popup, or one whose addon
-- turned the screen clicker on): a frame that is always there doesn't.
function Recipes.Attach(w, panel, opened)
	local mode = w.tab.adopt.mode
	local clicker = Recipes.TakeClicker(w.tab.adopt.signature)
	local cursor = opened and panel:IsVisible() and (clicker or (panel:IsPopup() and panel:IsMouseInputEnabled())) and not PP.Input.cursorMode
	if cursor then PP.Input.SetCursorMode(true) end
	if mode == "part" then
		local root = panel
		panel = Recipes.FollowPath(root, w.tab.adopt.signature.path)
		-- Already in another pin: what stands at its place is that pin's placeholder.
		if not IsValid(panel) or panel.ppPlaceholder or Recipes.Owner(panel) then return false end
		-- A path saved the old way is written again as it is kept now.
		if w.index and not w.tab.adopt.signature.path[1].n then
			local sig = table.Copy(w.tab.adopt.signature)
			sig.path = Recipes.Path(root, panel)
			Layout.SetAdopt(w.rec.id, w.index, { signature = sig })
		end
	end
	if not IsValid(panel) then return false end
	PP.Embed.Attach(w.tab.src, panel, mode)
	PP.Embed.live[w.tab.src].cursor = cursor or nil -- the window brought the cursor: closing it takes it back
	-- The player just opened it: it shows, in front, where it would have.
	if opened and w.index then
		Layout.Activate(w.rec.id, w.index)
		PP.Embed.Front(w.rec.id)
	end
	return true
end

-- Top-level panels already looked at, so each is signed once while the waiting set stays the same.
local checked = setmetatable({}, { __mode = "k" })
-- A window is taken once it has stopped opening: the same size and alpha on two ticks running (R20).
-- Taken while it animates, it would keep the size and alpha of that moment.
local settling = setmetatable({}, { __mode = "k" })
local function settled(p)
	local w, h, a = p:GetWide(), p:GetTall(), p:GetAlpha()
	local s = settling[p]
	if s and s[1] == w and s[2] == h and s[3] == a then return true end
	settling[p] = { w, h, a }
	return false
end
-- Windows that were already on screen when a tab started waiting (at join, after a reload, given back):
-- caught like any other, but the player didn't just open them, so they don't bring the cursor or come
-- to the front. Noted the moment a tab starts waiting: by the first look, half a second later, a
-- window opened in between would count as one of them.
local present = setmetatable({}, { __mode = "k" })

-- A window given back while it is still open (its part was taken back, its tab reloaded) is looked at
-- again: it was marked as seen when it was caught.
function Recipes.Forget(panel)
	checked[panel] = nil
	present[panel] = true
end

local ticks = 0
-- Window id -> RealTime until which a window appearing for it is the one we opened (not the player).
local expecting = {}

-- A window that looks like a pin's but not surely (its file agrees, its title or what is in it
-- doesn't) used to be a question, "Is this the window you pinned?" (D42, Z5: the addon decides). It is
-- taken when it is the only window on screen that could be that pin's, and the pin learns what it
-- looks like now, so it is sure next time; with two candidates it is left for its addon to settle.
-- Said in one line, since a wrong take is undone by unpinning.
local function takeIfOnly(w, panel, sig, tops, opened)
	local a = w.tab.adopt
	for _, other in ipairs(tops) do
		if other ~= panel and IsValid(other) and other:IsVisible() and not Recipes.Refusal(other, other)
			and Recipes.Match(a.signature, Recipes.Signature(other)) then
			return false
		end
	end
	local was = Recipes.Title(a)
	sig.path = a.signature.path
	Layout.SetAdopt(w.rec.id, w.index, { signature = sig })
	if not Recipes.Attach(w, panel, opened) then return false end
	local now = Recipes.Title(w.tab.adopt)
	if now ~= was then notification.AddLegacy(PP.L("adopt.took", now, was), NOTIFY_GENERIC, 8) end
	return true
end

-- A waiting window the player just opened teaches its pin the command that opened it (§33.9, Z3), so we
-- can open it ourselves next time: the command it was seen being opened by, else the bind just pressed,
-- else a command of its addon run a moment ago. Only pins that had no opener learn; a known one is kept.
local function learn(w, panel)
	if w.tab.adopt.recipe.kind ~= "watch" then return end
	local recipe = PP.Trace.Of(panel) or PP.Openers.FromBind() or PP.Trace.Recent(w.tab.adopt.signature)
	if not recipe then return end
	Layout.SetAdopt(w.rec.id, w.index, { recipe = recipe })
	notification.AddLegacy(PP.L("adopt.learned", Recipes.Title(w.tab.adopt), Recipes.Describe({ recipe = recipe })), NOTIFY_GENERIC, 6)
end

-- Looks at top-level panels not seen yet and gives each one to the waiting tab it matches best.
function Recipes.Catch()
	local waiting = Recipes.Waiting()
	if #waiting == 0 then
		timer.Remove(CATCH_TIMER)
		return
	end
	ticks = ticks + 1
	local hud, desktop = false, false
	for _, w in ipairs(waiting) do
		-- A widget's window is in the C menu, looked at below: it doesn't need the scan of every panel.
		if w.tab.adopt.signature.desktop then desktop = true elseif w.tab.adopt.signature.hud then hud = true end
	end
	local list = hud and ticks % HUD_EVERY == 0 and Recipes.TopLevels() or vgui.GetWorldPanel():GetChildren()
	-- Desktop widgets' windows are children of the C menu (G47).
	if desktop and IsValid(g_ContextMenu) then
		for _, p in ipairs(g_ContextMenu:GetChildren()) do list[#list + 1] = p end
	end
	-- Newest first: of two windows that match, the one just opened is the one the player wants.
	for n = #list, 1, -1 do
		local p = list[n]
		-- The spawn menu and the C menu are there while hidden: their parts are taken without anyone
		-- having to open them first (X49).
		local menu = IsValid(p) and Recipes.IsMenuRoot(p)
		if not checked[p] and IsValid(p) and (menu or (p:IsVisible() and p:GetAlpha() > 0 and settled(p))) then
			checked[p] = true
			-- The spawn and context menus can't be taken whole, but a part of them can.
			local refusal = Recipes.Refusal(p, p)
			local partsOnly = refusal == "refuse.root"
			if not refusal or partsOnly then
				local cand = Recipes.Signature(p)
				local matches = {}
				for _, w in ipairs(waiting) do
					local a = w.tab.adopt
					local fits = a.mode ~= "part" or Recipes.FollowPath(p, a.signature.path) ~= nil
					local score, strong = Recipes.Match(a.signature, cand)
					if score and fits and (a.mode == "part" or not partsOnly) then
						matches[#matches + 1] = { w = w, score = score, strong = strong }
					end
				end
				table.sort(matches, function(a, b) return a.score > b.score end)
				local best = matches[1]
				if best then
					-- A window goes whole to the one pin it matches best. Parts don't compete: every pin
					-- that is a part of this window gets its own (the creation menu and the tool menu are
					-- two parts of the one spawn menu).
					local takers = { best }
					if best.w.tab.adopt.mode == "part" then
						takers = {}
						for _, m in ipairs(matches) do
							if m.w.tab.adopt.mode == "part" then takers[#takers + 1] = m end
						end
					end
					for _, m in ipairs(takers) do
						local ours = (expecting[m.w.rec.id] or 0) > RealTime()
						local opened = not ours and not present[p] and p:IsVisible()
						-- A pin saved with "make another spawn menu" as its way back never had one.
						local r = m.w.tab.adopt.recipe
						if r.kind == "class" and menuRootClass(r.class) then
							Layout.SetAdopt(m.w.rec.id, m.w.index, { recipe = { kind = "watch" } })
						end
						-- A part of the spawn menu or the C menu is never a question: there is one of each,
						-- its file agreed and the part's path leads somewhere. What else is in the menu
						-- says nothing (pinned while another part was out, it "looks different" once
						-- both are back, and asked whether the creation menu was the creation menu).
						if m.strong or (menu and m.w.tab.adopt.mode == "part") then
							Recipes.Attach(m.w, p, opened)
							if opened then learn(m.w, p) end
						else
							takeIfOnly(m.w, p, cand, list, opened)
						end
					end
					waiting = Recipes.Waiting()
					if #waiting == 0 then return end
				end
			end
		end
	end
end

-- Starts catching when something waits (G55: polling, not OnChildAdded). Everything open is looked at
-- again only when a tab waits that didn't before: signing every window on every layout change is the
-- costliest thing we do.
local known = {}
function Recipes.Wake()
	local now, fresh = {}, false
	for _, w in ipairs(Recipes.Waiting()) do
		now[w.tab.src] = true
		fresh = fresh or not known[w.tab.src]
	end
	known = now
	if fresh then
		checked = setmetatable({}, { __mode = "k" })
		for _, p in ipairs(Recipes.TopLevels()) do present[p] = true end
		if IsValid(g_ContextMenu) then
			for _, p in ipairs(g_ContextMenu:GetChildren()) do present[p] = true end
		end
	end
	-- Through the table, so the timer runs this file's Catch and not the one it was made with.
	if not timer.Exists(CATCH_TIMER) then timer.Create(CATCH_TIMER, CATCH_INTERVAL, 0, function() Recipes.Catch() end) end
end

-- A timer left running by an earlier load of this file (a pin was still waiting when the addon was
-- reloaded) would go on calling that load's Catch, which knows nothing of what this one opens.
timer.Remove(CATCH_TIMER)

-- ── Opening ─────────────────────────────────────────────────

-- Whether a waiting panel can be opened by us: a registered class, a desktop widget, or a command the player
-- allowed and that exists now. Commands from an imported layout wait for the player (R16).
function Recipes.CanOpen(adopt)
	local r = adopt.recipe
	if r.kind == "class" then return vgui.GetControlTable(r.class) ~= nil and not menuRootClass(r.class) end
	if r.kind == "desktop" then return PP.Openers.CanOpenDesktop(r.id) end
	return r.kind == "command" and r.confirmed == true and concommand.GetTable()[r.command] ~= nil
end

-- Runs a waiting tab's opener, the only foreign code we call besides builders (R13), and only from a
-- click (R17). A class panel or a desktop widget is taken at once; a command's window is caught when it
-- appears.
function Recipes.Open(rec, tab)
	if Recipes.IsLive(rec, tab) or not Recipes.CanOpen(tab.adopt) then return end
	local r = tab.adopt.recipe
	Recipes.Wake()
	-- Its window may be open already and only not taken yet (a pin made a moment ago, from the Seen
	-- page say): it is taken, not opened, since many commands close the window when it is open ("xgui").
	-- Two looks, because a window is taken on the second one that finds it unchanged (R20).
	Recipes.Catch()
	Recipes.Catch()
	rec = Layout.Get(rec.id)
	if not rec or Recipes.IsLive(rec, tab) then return end
	expecting[rec.id] = RealTime() + OPEN_GRACE
	if r.kind == "desktop" then
		-- A window the widget launched is caught like any other, once it has settled.
		local panel, launched = PP.Openers.OpenDesktop(r.id)
		if panel and not launched then Recipes.Attach({ rec = rec, tab = tab }, panel) end
	elseif r.kind == "class" then
		local panel
		ProtectedCall(function() panel = vgui.Create(r.class) end)
		if not IsValid(panel) then return end
		-- A class that only makes a bare frame (a UI library's, filled by whoever uses it) isn't the
		-- window: it would sit in the tab empty. The pin goes back to what does open it.
		if not PP.Openers.Filled(panel) then
			panel:Remove()
			expecting[rec.id] = nil
			local best = PP.Openers.Best(PP.Openers.Commands(tab.adopt.signature))
			local recipe = best and { kind = "command", command = best, confirmed = true } or { kind = "watch" }
			for i, other in ipairs(rec.tabs) do
				if other == tab then Layout.SetAdopt(rec.id, i, { recipe = recipe }) end
			end
			notification.AddLegacy(PP.L("recipe.class_empty", Recipes.Title(tab.adopt), Recipes.Describe({ recipe = recipe })), NOTIFY_HINT, 10)
			return
		end
		if tab.adopt.signature.popup then panel:MakePopup() end
		Recipes.Attach({ rec = rec, tab = tab }, panel)
	else
		ProtectedCall(function() concommand.Run(LocalPlayer(), r.command, r.args and string.Explode(" ", r.args) or {}, r.args or "") end)
	end
	Recipes.Hurry()
end

-- A window we just asked for is looked for twenty times a second for as long as it is expected, not
-- twice: caught on the half second, and then only once it had looked the same on two looks running
-- (R20), it sat on screen for up to a second and a half before it went into its pin.
local FAST_TIMER, FAST_INTERVAL = "PinnedPanels.CatchFast", 0.05
function Recipes.Hurry()
	timer.Create(FAST_TIMER, FAST_INTERVAL, math.ceil(OPEN_GRACE / FAST_INTERVAL), function()
		if #Recipes.Waiting() == 0 then return timer.Remove(FAST_TIMER) end
		Recipes.Catch()
	end)
end

hook.Add("PinnedPanelsChanged", "PinnedPanels.Recipes", function(kind)
	if kind == "windows" or kind == "tabs" then Recipes.Wake() end
end)
hook.Add("PinnedPanelsHeldChanged", "PinnedPanels.Recipes", Recipes.Wake)

-- ── Reopening at join (D41) ─────────────────────────────────

-- Five seconds, not sooner: tried at two (X59), XGUI wasn't ready for its own command on a real join. It
-- showed nothing, and left the screen clicker it turns on for its window switched on.
local AUTO_TIMER, AUTO_DELAY, AUTO_GRACE, AUTO_RETRY, AUTO_STRIKES = "PinnedPanels.AutoOpen", 5, 6, 2, 2
-- Whether a pin is reopened at join: one that comes back with a command the player allowed, unless
-- the player turned that off (or it stopped working).
function Recipes.AutoOpens(adopt)
	return adopt.autoOpen ~= false and adopt.recipe.kind == "command" and adopt.recipe.confirmed == true
end

-- The one case where an opener runs without a click (D25, R17): a pin's allowed command, at join.
-- Once per session, a few seconds after the player is in the game, when the other addons have loaded
-- (the catalogue is ready much earlier, on the loading screen). A pin whose window doesn't come back
-- on AUTO_STRIKES joins running stops being reopened, and says so.
local function autoOpen()
	-- Not in the game yet: the opener would run against a player that doesn't exist.
	if not Desktop.ready or not IsValid(LocalPlayer()) then
		return timer.Create(AUTO_TIMER, AUTO_RETRY, 1, autoOpen)
	end
	local tried = {}
	for _, w in ipairs(Recipes.Waiting()) do
		local a = w.tab.adopt
		if Recipes.AutoOpens(a) and Recipes.CanOpen(a) then
			Recipes.Open(w.rec, w.tab)
			tried[#tried + 1] = w
		end
	end
	if #tried == 0 then return end
	timer.Create(AUTO_TIMER, AUTO_GRACE, 1, function()
		for _, w in ipairs(tried) do
			local rec = Layout.Get(w.rec.id)
			if rec and rec.tabs[w.index] == w.tab then
				local back = Recipes.IsLive(rec, w.tab)
				-- A command that opened nothing may still have turned the screen clicker on for the window
				-- it meant to show: that cursor is nobody's now, and goes.
				if not back then Recipes.TakeClicker(w.tab.adopt.signature) end
				local fails = not back and (w.tab.adopt.autoFails or 0) + 1 or nil
				if fails and fails >= AUTO_STRIKES then
					Layout.SetAdopt(rec.id, w.index, { autoOpen = false, autoFails = 0 })
					notification.AddLegacy(PP.L("auto.failed", Recipes.Title(w.tab.adopt), w.tab.adopt.recipe.command), NOTIFY_HINT, 10)
				elseif fails ~= w.tab.adopt.autoFails then
					Layout.SetAdopt(rec.id, w.index, { autoFails = fails or 0 })
				end
			end
		end
	end)
end
Recipes.AutoOpen = autoOpen

-- Loaded into a session that is already under way (a reload): that isn't a join.
if Desktop.ready and IsValid(LocalPlayer()) then Recipes.joined = true end

local function joined()
	if Recipes.joined then return end
	Recipes.joined = true
	timer.Create(AUTO_TIMER, AUTO_DELAY, 1, autoOpen)
end
Recipes.Joined = joined

-- On join, windows already open are caught; the rest wait for the player to open them (an opener is
-- another addon's code, and only a click runs it: D25, R17), or are reopened by their command (D41).
hook.Add("PinnedPanelsCatalogChanged", "PinnedPanels.Recipes", Recipes.Wake)
hook.Add("InitPostEntity", "PinnedPanels.Recipes", joined)

-- Reloaded on its own while pins wait: the timer removed above starts again.
if Desktop.ready then Recipes.Wake() end
