-- Adopted panels' identity and return (§33.8, §33.9): a panel's signature, the refusals (R11), how a pinned
-- panel comes back (its recipe) and catching it when it appears. Taking and releasing a panel is Manage's
-- job (and Embed's); this file decides which panel and when.

local PP = PinnedPanels
PP.Recipes = PP.Recipes or {}
local Recipes = PP.Recipes
local Layout, Desktop = PP.Layout, PP.Desktop

local CATCH_TIMER, CATCH_INTERVAL, HUD_EVERY = "PinnedPanels.Catch", 0.5, 2
local SCAN_LIMIT = 200
local MAX_TITLE = 64
local MAX_COMMANDS = 10
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

local function fileOf(fn)
	local info = debug.getinfo(fn, "S")
	return info and info.short_src
end

-- The file of a panel's own functions (G62): the preferred ones first, else the first file by name so the
-- answer is the same every time.
local function ownFile(p)
	local t = p:GetTable()
	for _, name in ipairs(PREFERRED) do
		local fn = rawget(t, name)
		if isfunction(fn) and not isStock(fileOf(fn)) then return fileOf(fn) end
	end
	local best
	for _, fn in pairs(t) do
		if isfunction(fn) then
			local src = fileOf(fn)
			if not isStock(src) and (not best or src < best) then best = src end
		end
	end
	return best
end

-- The file that built a panel: its own functions, else its children's (a plain DFrame whose buttons have
-- DoClick functions), breadth first.
function Recipes.SourceFile(panel)
	local queue, head = { panel }, 1
	while queue[head] and head <= SCAN_LIMIT do
		local p = queue[head]
		head = head + 1
		local src = ownFile(p)
		if src then return src end
		for _, c in ipairs(p:GetChildren()) do queue[#queue + 1] = c end
	end
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

-- Stock controls (G54) and ours don't identify anything. Read when first needed: Derma's tables are
-- empty while autorun files load.
local stock
local function isStockClass(class)
	if not stock then
		stock = {}
		for name, c in pairs(derma.GetControlList()) do stock[istable(c) and c.ClassName or name] = true end
	end
	return stock[class] or class:sub(1, 12) == "PinnedPanels"
end

local function titleOf(p)
	if not isfunction(p.GetTitle) then return nil end
	local title = p:GetTitle()
	if not isstring(title) or title == "" then return nil end
	return title:sub(1, MAX_TITLE)
end

-- class is kept only when it says more than the stock base it came from (G42, G53).
function Recipes.Signature(panel)
	local class = panel.ClassName
	if not isstring(class) or isStockClass(class) then class = nil end
	local base = panel.Base or panel.ClassName or panel:GetClassName()
	local src = Recipes.SourceFile(panel)
	local w, h = panel:GetSize()
	return {
		src = src, addon = Recipes.Addon(src), class = class, base = isstring(base) and base or nil,
		title = titleOf(panel), w = w, h = h, hud = panel:GetParent() ~= vgui.GetWorldPanel(), popup = panel:IsPopup(),
	}
end

-- How well a live panel's signature (cand) matches a saved one: nil when it can't be that panel.
-- Strong when the file or class agrees; a weak match needs the same title and asks the player once.
function Recipes.Match(sig, cand)
	if sig.src and cand.src ~= sig.src then return nil end
	if sig.class and cand.class ~= sig.class then return nil end
	local strong = sig.src ~= nil or sig.class ~= nil
	local sameTitle = sig.title ~= nil and cand.title == sig.title
	-- One file can make several windows; without a class, a titled window must keep its title.
	if not sig.class and sig.title and cand.title and not sameTitle then return nil end
	if not strong and not sameTitle then return nil end
	local score = (sig.src and 4 or 0) + (sig.class and 3 or 0) + (sameTitle and 2 or 0)
	if sig.w and math.abs(cand.w - sig.w) < 8 and math.abs(cand.h - sig.h) < 8 then score = score + 1 end
	return score, strong
end

local function phrase(text)
	if text:sub(1, 1) ~= "#" then return text end
	return language.GetPhrase(text:sub(2))
end

-- A name for lists: the window title, else its class, else its addon.
function Recipes.Title(adopt)
	local s = adopt.signature
	if s.title then return phrase(s.title) end
	return s.class or s.addon or PP.L("adopt.window")
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

-- The window or tab that already has this panel, if any.
function Recipes.Owner(p)
	return PP.Manage.byPanel[p]
end

-- Why panel (root's window, or root itself) can't be pinned: a localization key, or nil.
function Recipes.Refusal(panel, root)
	if not IsValid(panel) or panel:IsMarkedForDeletion() then return "refuse.gone" end
	if ours(panel) then return "refuse.ours" end
	if TRANSIENT[panel.ClassName] then return "refuse.transient" end
	local p = panel
	while IsValid(p) do
		if p:IsModal() then return "refuse.modal" end
		p = p:GetParent()
	end
	if panel == root then
		if Recipes.Owner(panel) then return "refuse.pinned" end
		if panel == g_SpawnMenu or panel == g_ContextMenu or panel == GetHUDPanel() then return "refuse.root" end
	end
end

-- ── Suggestions ─────────────────────────────────────────────

-- Lua console commands defined in the file that built a window (G48): likely its opener. Ours are left out.
function Recipes.CommandsIn(src)
	local out = {}
	if not src then return out end
	for name, fn in pairs(concommand.GetTable()) do
		if isfunction(fn) and name:sub(1, 13) ~= "pinnedpanels_" and fileOf(fn) == src then out[#out + 1] = name end
	end
	table.sort(out)
	while #out > MAX_COMMANDS do table.remove(out) end
	return out
end

-- A desktop widget's window (G47): a panel at or above this one titled like a widget we can build.
function Recipes.Native(panel)
	local byTitle = {}
	for _, e in ipairs(PP.Sources.natives) do
		if e.kind == "desktop" then byTitle[e.text] = e.key end
	end
	local p = panel
	while IsValid(p) do
		local title = titleOf(p)
		if title and byTitle[title] then return byTitle[title] end
		p = p:GetParent()
	end
end

-- What pinning panel (root, or a part of root) would do (§33.9): build it natively if it is a desktop
-- widget, else manage it; it comes back through the one command defined where it was built, else by
-- recreating its registered class, else when its addon opens it.
function Recipes.Suggest(panel, root)
	local sig = Recipes.Signature(root)
	local info = {
		mode = "manage", part = panel ~= root, signature = sig, native = Recipes.Native(panel), commands = Recipes.CommandsIn(sig.src),
	}
	if #info.commands == 1 then
		info.recipe = { kind = "command", command = info.commands[1], confirmed = true }
	elseif sig.class and vgui.GetControlTable(sig.class) then
		info.recipe = { kind = "class", class = sig.class }
	else
		info.recipe = { kind = "watch" }
	end
	if info.native then info.mode = "native" end
	return info
end

-- The modes the picker offers for a suggestion.
function Recipes.Modes(info)
	local modes = {}
	if info.native then modes[1] = "native" end
	if not info.part then modes[#modes + 1] = "manage" end
	return modes
end

-- The recipes the player can choose instead, the suggested one first. Commands chosen here are the
-- player's own choice, so they are allowed (R16 only holds back imported ones).
function Recipes.Choices(info)
	local list = { info.recipe }
	local function add(r)
		if r.kind ~= info.recipe.kind or r.command ~= info.recipe.command then list[#list + 1] = r end
	end
	local class = info.signature.class
	if class and vgui.GetControlTable(class) then add({ kind = "class", class = class }) end
	for _, command in ipairs(info.commands) do add({ kind = "command", command = command, confirmed = true }) end
	add({ kind = "watch" })
	add({ kind = "session" })
	return list
end

-- Pins panel in the given mode with the given recipe. Returns the window id.
function Recipes.Take(panel, root, mode, recipe)
	local adopt = { mode = mode, recipe = recipe, signature = Recipes.Signature(root) }
	return PP.Manage.Take(panel, adopt)
end

-- A line saying how a pinned panel comes back.
function Recipes.Describe(adopt)
	local r = adopt.recipe
	if r.kind == "class" then return PP.L("recipe.class", r.class) end
	if r.kind == "command" then
		local command = r.args and r.command .. " " .. r.args or r.command
		return PP.L(r.confirmed and "recipe.command" or "recipe.command_ask", command)
	end
	return PP.L("recipe." .. r.kind)
end

-- ── Waiting and catching (§33.9) ────────────────────────────

-- Whether tab (of window rec) has its panel now.
function Recipes.IsLive(rec, tab)
	return PP.Manage.live[rec.id] ~= nil
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

-- Gives a caught panel to its waiting tab; opened means the player just opened it.
function Recipes.Attach(w, panel, opened)
	PP.Manage.Attach(w.rec.id, panel, opened)
	return true
end

-- Top-level panels already looked at, so each is signed once while the waiting set stays the same.
local checked = setmetatable({}, { __mode = "k" })
local ticks = 0
-- Window id -> RealTime until which a window appearing for it is the one we opened (not the player).
local expecting = {}

local function ask(w, panel, sig)
	Derma_Query(PP.L("adopt.confirm", sig.title and phrase(sig.title) or Recipes.Title(w.tab.adopt)), PP.L("adopt.confirm_title"),
		PP.L("btn.yes"), function()
			if IsValid(panel) and not Recipes.Owner(panel) and not Recipes.IsLive(w.rec, w.tab) then Recipes.Attach(w, panel, true) end
		end,
		PP.L("btn.no"), function() end)
end

-- Looks at top-level panels not seen yet and gives each one to the waiting tab it matches best.
function Recipes.Catch()
	local waiting = Recipes.Waiting()
	if #waiting == 0 then
		timer.Remove(CATCH_TIMER)
		return
	end
	ticks = ticks + 1
	local hud = false
	for _, w in ipairs(waiting) do
		if w.tab.adopt.signature.hud then hud = true end
	end
	local list = hud and ticks % HUD_EVERY == 0 and Recipes.TopLevels() or vgui.GetWorldPanel():GetChildren()
	for _, p in ipairs(list) do
		if not checked[p] and IsValid(p) and p:IsVisible() and p:GetAlpha() > 0 then
			checked[p] = true
			if not Recipes.Refusal(p, p) then
				local cand = Recipes.Signature(p)
				local best, bestScore, bestStrong
				for _, w in ipairs(waiting) do
					local score, strong = Recipes.Match(w.tab.adopt.signature, cand)
					if score and (not best or score > bestScore) then best, bestScore, bestStrong = w, score, strong end
				end
				if best then
					local ours = (expecting[best.rec.id] or 0) > RealTime()
					if bestStrong then Recipes.Attach(best, p, not ours) else ask(best, p, cand) end
					waiting = Recipes.Waiting()
					if #waiting == 0 then return end
				end
			end
		end
	end
end

-- Starts catching when something waits; everything open is looked at again (G55: polling, not OnChildAdded).
function Recipes.Wake()
	checked = setmetatable({}, { __mode = "k" })
	if not timer.Exists(CATCH_TIMER) then timer.Create(CATCH_TIMER, CATCH_INTERVAL, 0, Recipes.Catch) end
end

-- ── Opening ─────────────────────────────────────────────────

-- Whether a waiting panel can be opened by us: a registered class, or a command the player allowed and
-- that exists now. Commands from an imported layout wait for the player (R16).
function Recipes.CanOpen(adopt)
	local r = adopt.recipe
	if r.kind == "class" then return vgui.GetControlTable(r.class) ~= nil end
	return r.kind == "command" and r.confirmed == true and concommand.GetTable()[r.command] ~= nil
end

-- Runs a waiting tab's opener, the only foreign code we call besides builders (R13). A class panel is
-- taken at once; a command's window is caught when it appears.
function Recipes.Open(rec, tab)
	if Recipes.IsLive(rec, tab) or not Recipes.CanOpen(tab.adopt) then return end
	local r = tab.adopt.recipe
	Recipes.Wake()
	expecting[rec.id] = RealTime() + OPEN_GRACE
	if r.kind == "class" then
		local panel
		ProtectedCall(function() panel = vgui.Create(r.class) end)
		if not IsValid(panel) then return end
		if tab.adopt.signature.popup then panel:MakePopup() end
		Recipes.Attach({ rec = rec, tab = tab }, panel)
	else
		ProtectedCall(function() concommand.Run(LocalPlayer(), r.command, r.args and string.Explode(" ", r.args) or {}, r.args or "") end)
		Recipes.Catch()
	end
end

hook.Add("PinnedPanelsChanged", "PinnedPanels.Recipes", function(kind)
	if kind == "windows" or kind == "tabs" then Recipes.Wake() end
end)
hook.Add("PinnedPanelsHeldChanged", "PinnedPanels.Recipes", Recipes.Wake)

-- On join, with autoRestore, windows already open are taken and the others are opened once. A reload
-- doesn't open them again: they are still open and get caught. Next frame, so the desktop is ready.
hook.Add("PinnedPanelsCatalogChanged", "PinnedPanels.Recipes", function()
	Recipes.Wake()
	if Recipes.restored then return end
	Recipes.restored = true
	PP.Util.NextFrame(nil, function()
		if not PP.Settings.Get("autoRestore") then return end
		Recipes.Catch()
		for _, w in ipairs(Recipes.Waiting()) do Recipes.Open(w.rec, w.tab) end
	end)
end)
