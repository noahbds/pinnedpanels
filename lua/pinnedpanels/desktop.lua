-- Records → window controls (§16): creates, refreshes and removes PinnedPanelsWindows as the document
-- changes, rations tab builds to one per frame, applies interactivity, idle opacity and peek, and owns the
-- taskbar control.

local PP = PinnedPanels
PP.Desktop = PP.Desktop or {}
local Desktop = PP.Desktop
local Layout, Sources, Input, Settings, Storage, Util = PP.Layout, PP.Sources, PP.Input, PP.Settings, PP.Storage, PP.Util

Desktop.panels = Desktop.panels or {}
-- Held back: kept in the document, no control until shown. Windows present at join while autoRestore
-- is off start this way.
Desktop.held = Desktop.held or {}
-- When each window was last clicked or brought up: the order they are stacked in (Desktop.Raise).
Desktop.stack = Desktop.stack or {}
Desktop.stackTop = Desktop.stackTop or 0
Desktop.ready = Desktop.ready or false
Desktop.peeking = false

local function hasAvailableTab(rec)
	for _, t in ipairs(rec.tabs) do
		if Sources.Get(t.src) then return true end
	end
	return false
end

-- A window gets a control once the catalogue is known, unless it is held, empty (a named group) or
-- only has unavailable tabs, which stay dormant in the document (E1, B1).
local function wanted(rec)
	return Desktop.ready and not Desktop.held[rec.id] and hasAvailableTab(rec)
end

-- Dormant: nothing to show now. For adopted panels that means waiting for the panel (§33.9).
function Desktop.IsDormant(rec)
	return #rec.tabs > 0 and not hasAvailableTab(rec)
end

-- Our window control for a window, or nil.
function Desktop.PanelOf(id)
	local win = Desktop.panels[id]
	if IsValid(win) then return win end
end

local function create(rec)
	local win = vgui.Create("PinnedPanelsWindow")
	win:ParentToHUD() -- as v1; the Phase 0 spike decides whether this matters for the escape menu (G30, E27)
	win:MakePopup()
	win:SetKeyboardInputEnabled(false) -- G21: the mouse without blocking movement
	win:SetWindowId(rec.id)
	Desktop.panels[rec.id] = win
	return win
end

-- Whether a window shows now: not minimized, and the C menu open if it only shows with it (FF5). Peek shows
-- everything (F22).
function Desktop.Shown(rec)
	return (rec.state ~= "minimized" and (rec.showWith ~= "contextmenu" or Input.ContextOpen())) or Desktop.peeking
end

-- Visibility, mouse input and idle opacity, recomputed on changes, never per frame (§16.3, G27).
-- Peek shows every window, minimized ones too, at full opacity (F22); so is the window keyboard
-- navigation just used (L11).
function Desktop.UpdateStates()
	Desktop.StaleRects()
	local interactive = Input.Interactive()
	local idle = Settings.Get("idleOpacity") / 100
	for id, win in pairs(Desktop.panels) do
		local rec = Layout.Get(id)
		if IsValid(win) and rec then
			win:SetVisible(Desktop.Shown(rec))
			win:SetMouseInputEnabled(interactive and not Desktop.covered)
			if not interactive then win:SetKeyboardInputEnabled(false) end
			local alpha = (interactive or Desktop.peeking or PP.Nav.Opaque(id)) and 1 or (rec.opacity or idle)
			win:SetAlpha(math.Round(alpha * 255))
		end
	end
	if IsValid(Desktop.taskbar) then Desktop.taskbar:Wake() end
end

function Desktop.Reconcile()
	local seen = {}
	for _, rec in ipairs(Layout.Windows()) do
		if wanted(rec) then
			seen[rec.id] = true
			local win = Desktop.panels[rec.id]
			if IsValid(win) then win:Refresh() else create(rec) end
		end
	end
	for id, win in pairs(Desktop.panels) do
		if not seen[id] then
			if IsValid(win) then
				win:Unbuild()
				win:Remove()
			end
			Desktop.panels[id] = nil
		end
	end
	if Desktop.focused and not IsValid(Desktop.PanelOf(Desktop.focused)) then Desktop.focused = nil end
	local front = Desktop.panels[Desktop.pendingFront or ""]
	if IsValid(front) then
		front:MoveToFront()
		Desktop.pendingFront = nil
	end
	Desktop.UpdateStates()
	-- Made here too if it is wanted and gone: a reload removes it, and nothing else would bring it back.
	Desktop.UpdateTaskbar()
end

hook.Add("PinnedPanelsChanged", "PinnedPanels.Desktop", function(kind, id)
	if kind == "windows" or kind == "tabs" or not id then return Desktop.Reconcile() end
	local win = Desktop.panels[id]
	if IsValid(win) then win:Refresh() end
	if kind == "state" or kind == "style" then
		Desktop.statesStale = true
	end
end)

-- Every window's visibility and opacity, and the taskbar, are worked out once for a frame's changes,
-- not once for each (restoring sixty windows is sixty of them); keyboard navigation then sees the
-- taskbar's entries as they are.
hook.Add("PinnedPanelsFlushed", "PinnedPanels.Desktop", function()
	local states = Desktop.statesStale
	if states then
		Desktop.statesStale = false
		Desktop.UpdateStates()
		-- Made or removed as well as filled: switched off, it is still there while a window is minimized.
		Desktop.UpdateTaskbar()
	end
	-- After the windows are shown or hidden as they should be, which is what it looks at.
	if states or PP.Nav.stale then
		PP.Nav.stale = false
		PP.Nav.Refresh()
	end
end)

hook.Add("PinnedPanelsInputChanged", "PinnedPanels.Desktop", Desktop.UpdateStates)

-- The spawn menu and the C menu are full-screen layers that come to the front each time they open: a
-- pinned window under one shows through its empty parts but gets none of the clicks. So our windows go
-- back in front of them, in the order they were stacked, and the taskbar last (FF5, X48).
function Desktop.Raise()
	local wins = {}
	for id, win in pairs(Desktop.panels) do
		if IsValid(win) then wins[#wins + 1] = { win = win, at = Desktop.stack[id] or 0 } end
	end
	table.sort(wins, function(a, b) return a.at < b.at end)
	for _, w in ipairs(wins) do w.win:MoveToFront() end
	if IsValid(Desktop.taskbar) then Desktop.taskbar:MoveToFront() end
	-- A menu that is open belongs above everything, as it was: a menu bar's on the world panel, and
	-- every drop-down, a combo box's too (its parent is the box), in the order they opened.
	for _, p in ipairs(vgui.GetWorldPanel():GetChildren()) do
		if p.m_bIsMenuComponent and p:IsVisible() then p:MoveToFront() end
	end
	local menus = {}
	for menu, at in pairs(Desktop.menus) do
		if IsValid(menu) and menu:IsVisible() then menus[#menus + 1] = { menu = menu, at = at } end
	end
	table.sort(menus, function(a, b) return a.at < b.at end)
	for _, m in ipairs(menus) do m.menu:MoveToFront() end
end

-- ── What is in front ────────────────────────────────────────
-- Our windows are drawn with the HUD, under everything on the world panel, but as popups they are asked
-- for the mouse in popup order, and Desktop.Raise and a click put them first in it. So a window lying
-- behind another addon's menu took the clicks meant for that menu (X50). While the cursor is on
-- something that is drawn over them, our windows leave the mouse alone.

Desktop.covered = Desktop.covered or false
-- Drop-down menus that were opened, and when. Nothing lists the open ones, so they are noted as they
-- register for closing (the real function is kept across reloads, so it is never wrapped twice).
Desktop.menus = Desktop.menus or setmetatable({}, { __mode = "k" })
Desktop.menuCount = Desktop.menuCount or 0
Desktop.rawRegisterMenu = Desktop.rawRegisterMenu or RegisterDermaMenuForClose
local rawRegisterMenu = Desktop.rawRegisterMenu
if rawRegisterMenu then
	function RegisterDermaMenuForClose(menu)
		Desktop.menuCount = Desktop.menuCount + 1
		Desktop.menus[menu] = Desktop.menuCount
		return rawRegisterMenu(menu)
	end
end

local at = Util.Contains

local function shownToRoot(p)
	while IsValid(p) do
		if not p:IsVisible() then return false end
		p = p:GetParent()
	end
	return true
end

-- Whether the point is on the place a pinned part left in root: nothing is drawn there but a line of
-- text, and the part may well be in a window right behind it.
local function onPlaceholder(root, x, y)
	for _, e in pairs(PP.Embed.live) do
		local ph = e.placeholder
		if IsValid(ph) and at(ph, x, y) and ph:HasParent(root) and shownToRoot(ph) then return true end
	end
	return false
end

-- Whether something on the world panel is drawn at the point and takes the mouse there. The spawn menu
-- and the C menu fill the screen and are empty around what they hold: only what they hold counts.
local function coveredAt(x, y)
	for menu in pairs(Desktop.menus) do
		if IsValid(menu) and menu:IsVisible() and at(menu, x, y) then return true end
	end
	for _, p in ipairs(vgui.GetWorldPanel():GetChildren()) do
		if p:IsVisible() and p:IsMouseInputEnabled() and p:IsPopup() and at(p, x, y) and not onPlaceholder(p, x, y) then
			if p ~= g_SpawnMenu and p ~= g_ContextMenu then return true end
			for _, c in ipairs(p:GetChildren()) do
				if c:IsVisible() and c:IsMouseInputEnabled() and at(c, x, y) then return true end
			end
		end
	end
	return false
end

-- Where the windows that show are, as plain numbers kept from one change to the next: this is asked
-- every frame, and asking each window's control (or even the layout, a call apiece) is most of what it
-- costs. A rolled-up window is its header.
local ROLLED_H = 24
local rects, rectsStale = {}, true
function Desktop.StaleRects() rectsStale = true end
local staleRects = Desktop.StaleRects
hook.Add("PinnedPanelsChanged", "PinnedPanels.Desktop.Rects", staleRects)
hook.Add("PinnedPanelsInputChanged", "PinnedPanels.Desktop.Rects", staleRects)

local function overWindow(x, y)
	if rectsStale then
		rectsStale = false
		rects = {}
		for id in pairs(Desktop.panels) do
			local rec = Layout.Get(id)
			if rec and Desktop.Shown(rec) then
				local n = #rects
				rects[n + 1], rects[n + 2], rects[n + 3], rects[n + 4] = rec.x, rec.y, rec.x + rec.w, rec.y + (rec.state == "rolled" and ROLLED_H or rec.h)
			end
		end
	end
	for i = 1, #rects, 4 do
		if x >= rects[i] and y >= rects[i + 1] and x < rects[i + 2] and y < rects[i + 3] then return true end
	end
	return false
end

local COVER_LOOK = 0.1
local lastX, lastY, nextLook = -1, -1, 0

-- Asked every frame while windows take the mouse, and applied only when it changes. Not while a button
-- is down: a window being dragged over a menu keeps the mouse.
Input.EachFrame("covered", function()
	if not next(Desktop.panels) or not Input.Interactive() or input.IsMouseDown(MOUSE_LEFT) or input.IsMouseDown(MOUSE_RIGHT) then return end
	local x, y = input.GetCursorPos()
	-- What is drawn over a window is looked for when the cursor is on one and has moved, or ten times a
	-- second while it rests (a menu can open under a cursor that doesn't move): it is the costly half.
	local over, now = overWindow(x, y), RealTime()
	if over and x == lastX and y == lastY and now < nextLook then return end
	lastX, lastY, nextLook = x, y, now + COVER_LOOK
	local covered = over and coveredAt(x, y)
	if covered == Desktop.covered then return end
	Desktop.covered = covered
	for _, win in pairs(Desktop.panels) do
		if IsValid(win) then win:SetMouseInputEnabled(not covered) end
	end
end)

-- The menu is made a popup after the hook, so a frame later.
local function raiseSoon()
	Util.NextFrame(nil, Desktop.Raise)
end
hook.Add("OnContextMenuOpen", "PinnedPanels.Desktop", raiseSoon)
hook.Add("OnSpawnMenuOpen", "PinnedPanels.Desktop", raiseSoon)

-- A click in either menu brings it to the front again, over our windows, so they go back in front after
-- every click that lands in one. (VGUIMousePressed is for a click on a panel, GUIMousePressed for one on
-- the world through the C menu.)
local function inMenu(p)
	while IsValid(p) do
		if p == g_SpawnMenu or p == g_ContextMenu then return true end
		p = p:GetParent()
	end
	return false
end
hook.Add("VGUIMousePressed", "PinnedPanels.Desktop", function(panel)
	if inMenu(panel) then raiseSoon() end
end)
hook.Add("GUIMousePressed", "PinnedPanels.Desktop", function()
	if IsValid(g_ContextMenu) and g_ContextMenu:IsVisible() then raiseSoon() end
end)
-- An adopted panel was taken, let go or closed by its addon (§33).
hook.Add("PinnedPanelsAdoptChanged", "PinnedPanels.Desktop", function() Desktop.Reconcile() end)

-- ── Taskbar ─────────────────────────────────────────────────

function Desktop.UpdateTaskbar()
	local want = Desktop.ready and Settings.Get("taskbar")
	-- Switched off, it still shows while a window is minimized (and only those): told to look for it
	-- "in the Pinned tab or the command palette", the player had the addon's work to do (Z7).
	if Desktop.ready and not want then
		for _, rec in ipairs(Layout.Windows()) do
			if rec.state == "minimized" and #rec.tabs > 0 then
				want = true
				break
			end
		end
	end
	if want and not IsValid(Desktop.taskbar) then
		Desktop.taskbar = vgui.Create("PinnedPanelsTaskbar")
		Desktop.taskbar:MakePopup()
		Desktop.taskbar:SetKeyboardInputEnabled(false)
	elseif not want and IsValid(Desktop.taskbar) then
		Desktop.taskbar:Remove()
		Desktop.taskbar = nil
	end
	if IsValid(Desktop.taskbar) then Desktop.taskbar:Rebuild() end
end

hook.Add("PinnedPanelsSettingChanged", "PinnedPanels.Desktop", function(key)
	if key == "idleOpacity" then
		Desktop.UpdateStates()
	elseif key:sub(1, 7) == "taskbar" then
		Desktop.UpdateTaskbar()
	end
end)

-- The first catalogue decides what "restore on join" means; later ones re-check dormant tabs (E1, E12).
hook.Add("PinnedPanelsCatalogChanged", "PinnedPanels.Desktop", function()
	if not Desktop.ready then
		Desktop.ready = true
		if not Settings.Get("autoRestore") then
			for _, rec in ipairs(Layout.Windows()) do Desktop.held[rec.id] = true end
		end
		Desktop.UpdateTaskbar()
	end
	Desktop.Reconcile()
end)

-- Windows follow the game language (L19, E11); the spawn menu rebuilds the hub itself (G11), and the
-- catalogue's default titles come back with it.
cvars.AddChangeCallback("gmod_language", function()
	Util.NextFrame(nil, function()
		for _, win in pairs(Desktop.panels) do
			if IsValid(win) then win:Relocalize() end
		end
		if IsValid(Desktop.taskbar) then Desktop.taskbar:Rebuild() end
	end)
end, "PinnedPanels.Desktop")

-- The active tool window follows the tool gun (FF1): its tab builds the new tool's panel and its title changes.
cvars.AddChangeCallback("gmod_toolmode", function()
	Util.NextFrame(nil, function()
		for _, win in pairs(Desktop.panels) do
			local host = IsValid(win) and win.hosts[Sources.ACTIVE]
			if host then
				host:Rebuild()
				win:Refresh()
			end
		end
		if IsValid(Desktop.taskbar) then Desktop.taskbar:Rebuild() end
	end)
end, "PinnedPanels.Desktop")

-- ── Services ────────────────────────────────────────────────

-- One tab host may build per frame across all windows (§16.2).
local lastBuild = -1
function Desktop.ClaimBuild()
	local frame = FrameNumber()
	if frame == lastBuild then return false end
	lastBuild = frame
	return true
end

-- Records of the other windows on screen, for snapping.
function Desktop.SnapRects(exceptId)
	local rects = {}
	for id, win in pairs(Desktop.panels) do
		local rec = Layout.Get(id)
		if id ~= exceptId and rec and IsValid(win) and win:IsVisible() then
			rects[#rects + 1] = rec.state == "rolled" and { x = rec.x, y = rec.y, w = rec.w, h = win:GetTall() } or rec
		end
	end
	return rects
end

-- The window keys and console commands act on when no id is given: the last one clicked or brought up.
function Desktop.SetFocused(id)
	Desktop.focused = id
	if id then
		Desktop.stackTop = Desktop.stackTop + 1
		Desktop.stack[id] = Desktop.stackTop
	end
end

-- A window that doesn't have its control yet comes to the front when the desktop creates it.
function Desktop.Front(id)
	local win = Desktop.panels[id]
	if IsValid(win) then
		win:MoveToFront()
	else
		Desktop.pendingFront = id
	end
	Desktop.SetFocused(id)
end

-- Pins src (or brings back its window) and puts the window in front (E22). A desktop widget is opened and
-- embedded instead (Openers.PinDesktop).
function Desktop.PinSource(src)
	local widget = src:match("^desktop:(.+)$")
	if widget then return PP.Openers.PinDesktop(widget) end
	if Sources.single[src] then
		local own = Sources.PinOwn(src)
		if own then return own end
	end
	local id = Layout.Pin(src, Sources.DefaultSize(src))
	Desktop.Show(id)
	Desktop.Front(id)
	return id
end

function Desktop.RestoreAndFront(id)
	Layout.Restore(id)
	Desktop.Show(id)
	Desktop.Front(id)
end

-- Held windows are the ones not brought up at join because "restore when joining" is off: they wait,
-- without a window control, until the player asks for them. (There used to be a Hide action that put
-- any window in this state for the session; it did nothing Minimize doesn't, and is gone.) Showing
-- one isn't a document change, so it has its own event for the hub.
function Desktop.Show(id)
	if not Desktop.held[id] then return end
	Desktop.held[id] = nil
	Desktop.Reconcile()
	hook.Run("PinnedPanelsHeldChanged")
end

-- Holds or shows several windows in one go: one reconcile for all of them.
function Desktop.SetHeld(ids, held)
	local any = false
	for _, id in ipairs(ids) do
		if Layout.Get(id) and (Desktop.held[id] == true) ~= held then
			Desktop.held[id] = held or nil
			any = true
		end
	end
	if not any then return end
	Desktop.Reconcile()
	hook.Run("PinnedPanelsHeldChanged")
end

-- Shows every window held back by autoRestore = off.
function Desktop.ShowHeld()
	Desktop.held = {}
	Desktop.Reconcile()
	hook.Run("PinnedPanelsHeldChanged")
end

function Desktop.Peek(on)
	if Desktop.peeking == on then return end
	Desktop.peeking = on
	Desktop.UpdateStates()
end

-- ── Lifecycle ───────────────────────────────────────────────

function Desktop.Teardown()
	-- First, while the windows still exist: each release reconciles, which would otherwise make new ones.
	PP.Embed.ReleaseAll()
	for _, win in pairs(Desktop.panels) do
		if IsValid(win) then
			win:Unbuild()
			win:Remove()
		end
	end
	Desktop.panels = {}
	if IsValid(Desktop.taskbar) then Desktop.taskbar:Remove() end
	Desktop.taskbar = nil
	if IsValid(PP.Picker.panel) then PP.Picker.panel:Remove() end
end

-- Load the document; if the spawn menu already exists (a reload), read the catalogue now (E2).
hook.Add("PinnedPanelsLoaded", "PinnedPanels.Desktop", function()
	Layout.Load(Storage.Load())
	if IsValid(g_SpawnMenu) then Sources.Rebuild() end
end)

-- A gamemode without a spawn menu never reloads the tools menu (G72): read the catalogue anyway, so
-- windows, the taskbar and catching work there too (D30).
hook.Add("InitPostEntity", "PinnedPanels.Desktop", function()
	if not next(Sources.catalogue) then Sources.Rebuild() end
end)
