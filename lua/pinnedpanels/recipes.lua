-- Adopted panels' identity and return (§33.8, §33.9): a panel's signature, the refusals (R11), how a pinned
-- panel comes back (its recipe) and catching it when it appears. Taking and releasing a panel is Embed's
-- job; this file decides which panel and when. Record mode is record.lua.

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

local function phrase(text)
	if text:sub(1, 1) ~= "#" then return text end
	return language.GetPhrase(text:sub(2))
end

-- A name for lists: the window title, else its class, else its addon.
function Recipes.Title(adopt)
	local s = adopt.signature
	if s.title then return phrase(s.title) end
	if s.desktop then return PP.Sources.Title("desktop:" .. s.desktop) end
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
local function isScene(p)
	if p:GetWide() < ScrW() or p:GetTall() < ScrH() then return false end
	return isfunction(p.Paint) and not isStock(fileOf(p.Paint))
end

-- Why panel (root's window, or root itself) can't be pinned: a localization key, or nil.
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

-- A part's place in its window: child indices and classes from the root down (§33.8).
function Recipes.Path(root, part)
	local path, p = {}, part
	while p ~= root do
		local parent = p:GetParent()
		for i, c in ipairs(parent:GetChildren()) do
			if c == p then
				table.insert(path, 1, { i = i, class = c.ClassName or c:GetClassName() })
				break
			end
		end
		p = parent
	end
	return path
end

-- The same part in a window made again, or nil when the window is laid out differently now.
function Recipes.FollowPath(root, path)
	local p = root
	for _, step in ipairs(path) do
		p = p:GetChildren()[step.i]
		if not IsValid(p) or (step.class and (p.ClassName or p:GetClassName()) ~= step.class) then return nil end
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

-- What pinning panel (root, or a part of root) would do (§33.9): embed it. A desktop widget's own window
-- comes back by being opened as the C menu does; anything else through the command that is tied to it
-- (Openers.Best), else when its addon opens it. Recreating its class is never suggested, only offered
-- (Recipes.Choices): most windows need what their opener does around the panel (D26).
function Recipes.Suggest(panel, root)
	local sig = Recipes.Signature(root)
	local info = { mode = panel ~= root and "part" or "embed", part = panel ~= root, signature = sig, commands = PP.Openers.Commands(sig) }
	local best = PP.Openers.Best(info.commands)
	if sig.desktop then
		info.recipe = { kind = "desktop", id = sig.desktop }
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
	if class and vgui.GetControlTable(class) then add({ kind = "class", class = class }) end
	for _, c in ipairs(info.commands) do add({ kind = "command", command = c.name, confirmed = true }) end
	add({ kind = "watch" })
	add({ kind = "session" })
	return list
end

-- Pins panel (root, or a part of root) in the given mode with the given recipe. Returns the window id.
-- waiting: the pinned window is made now and takes the panel when it is caught.
function Recipes.Take(panel, root, mode, recipe, waiting)
	local adopt = { mode = mode, recipe = recipe, signature = Recipes.Signature(root), needsKeyboard = root:IsKeyboardInputEnabled() }
	if mode == "part" then adopt.signature.path = Recipes.Path(root, panel) end
	return PP.Embed.Take(mode == "part" and panel or root, adopt, waiting)
end

-- A line saying how a pinned panel comes back.
function Recipes.Describe(adopt)
	local r = adopt.recipe
	if r.kind == "class" then return PP.L("recipe.class", r.class) end
	if r.kind == "desktop" then return PP.L("recipe.desktop", PP.Sources.Title("desktop:" .. r.id)) end
	if r.kind == "command" then
		local command = r.args and r.command .. " " .. r.args or r.command
		return PP.L(r.confirmed and "recipe.command" or "recipe.command_ask", command)
	end
	return PP.L("recipe." .. r.kind)
end

-- ── Waiting and catching (§33.9) ────────────────────────────

-- Whether tab (of window rec) has its panel now.
function Recipes.IsLive(_, tab)
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

-- Gives a caught window to its waiting tab, which takes it whole or the part at its path; opened means
-- the player just opened it. Only a popup brings the cursor: a frame that is always there doesn't.
function Recipes.Attach(w, panel, opened)
	local mode = w.tab.adopt.mode
	if opened and panel:IsVisible() and panel:IsPopup() and panel:IsMouseInputEnabled() and not PP.Input.cursorMode then PP.Input.SetCursorMode(true) end
	if mode == "part" then panel = Recipes.FollowPath(panel, w.tab.adopt.signature.path) end
	if not IsValid(panel) then return false end
	PP.Embed.Attach(w.tab.src, panel, mode)
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
local ticks = 0
-- Window id -> RealTime until which a window appearing for it is the one we opened (not the player).
local expecting = {}

-- Questions put this session: tab src -> { the candidate's identity -> true }. An open question isn't
-- asked twice, and "no" stays no for every window that looks the same.
local asked = {}

-- "Yes" also teaches the pin what its window looks like now, so the question doesn't come back.
local function ask(w, panel, sig)
	local src = w.tab.src
	local key = table.concat({ sig.src or "", sig.src2 or "", sig.class or "", sig.title or "" }, "\n")
	asked[src] = asked[src] or {}
	if asked[src][key] then return end
	asked[src][key] = true
	Derma_Query(PP.L("adopt.confirm", sig.title and phrase(sig.title) or Recipes.Title(w.tab.adopt)), PP.L("adopt.confirm_title"),
		PP.L("btn.yes"), function()
			asked[src][key] = nil
			if IsValid(panel) and not Recipes.Owner(panel) and not Recipes.IsLive(w.rec, w.tab) then
				sig.path = w.tab.adopt.signature.path
				Layout.SetAdopt(w.rec.id, w.index, { signature = sig })
				Recipes.Attach(w, panel, true)
			end
		end,
		PP.L("btn.no"), function() end)
end

-- A waiting window the player just opened with a bind teaches its pin that command (§33.9), so we can open
-- it ourselves next time. Only pins that had no opener learn; a known one is kept.
local function learn(w)
	if w.tab.adopt.recipe.kind ~= "watch" then return end
	local recipe = PP.Openers.FromBind()
	if not recipe then return end
	Layout.SetAdopt(w.rec.id, w.index, { recipe = recipe })
	notification.AddLegacy(PP.L("record.updated", Recipes.Title(w.tab.adopt), Recipes.Describe({ recipe = recipe })), NOTIFY_GENERIC, 6)
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
		if not checked[p] and IsValid(p) and p:IsVisible() and p:GetAlpha() > 0 and settled(p) then
			checked[p] = true
			-- The spawn and context menus can't be taken whole, but a part of them can.
			local refusal = Recipes.Refusal(p, p)
			local partsOnly = refusal == "refuse.root"
			if not refusal or partsOnly then
				local cand = Recipes.Signature(p)
				local best, bestScore, bestStrong
				for _, w in ipairs(waiting) do
					local a = w.tab.adopt
					local fits = a.mode ~= "part" or Recipes.FollowPath(p, a.signature.path) ~= nil
					local score, strong = Recipes.Match(a.signature, cand)
					if score and fits and (a.mode == "part" or not partsOnly) and (not best or score > bestScore) then
						best, bestScore, bestStrong = w, score, strong
					end
				end
				if best then
					local ours = (expecting[best.rec.id] or 0) > RealTime()
					if bestStrong then
						Recipes.Attach(best, p, not ours)
						if not ours then learn(best) end
					else
						ask(best, p, cand)
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
	if fresh then checked = setmetatable({}, { __mode = "k" }) end
	if not timer.Exists(CATCH_TIMER) then timer.Create(CATCH_TIMER, CATCH_INTERVAL, 0, Recipes.Catch) end
end

-- ── Opening ─────────────────────────────────────────────────

-- Whether a waiting panel can be opened by us: a registered class, a desktop widget, or a command the player
-- allowed and that exists now. Commands from an imported layout wait for the player (R16).
function Recipes.CanOpen(adopt)
	local r = adopt.recipe
	if r.kind == "class" then return vgui.GetControlTable(r.class) ~= nil end
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
	expecting[rec.id] = RealTime() + OPEN_GRACE
	if r.kind == "desktop" then
		-- A window the widget launched is caught like any other, once it has settled.
		local panel, launched = PP.Openers.OpenDesktop(r.id)
		if panel and not launched then Recipes.Attach({ rec = rec, tab = tab }, panel) end
	elseif r.kind == "class" then
		local panel
		ProtectedCall(function() panel = vgui.Create(r.class) end)
		if not IsValid(panel) then return end
		if tab.adopt.signature.popup then panel:MakePopup() end
		Recipes.Attach({ rec = rec, tab = tab }, panel)
	else
		ProtectedCall(function() concommand.Run(LocalPlayer(), r.command, r.args and string.Explode(" ", r.args) or {}, r.args or "") end)
	end
end

hook.Add("PinnedPanelsChanged", "PinnedPanels.Recipes", function(kind)
	if kind == "windows" or kind == "tabs" then Recipes.Wake() end
end)
hook.Add("PinnedPanelsHeldChanged", "PinnedPanels.Recipes", Recipes.Wake)

-- On join, windows already open are caught, and the rest wait for the player to open them: an opener is
-- another addon's code, and only a click runs it (D25, R17).
hook.Add("PinnedPanelsCatalogChanged", "PinnedPanels.Recipes", Recipes.Wake)
