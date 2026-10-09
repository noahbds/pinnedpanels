-- Manage mode (§33.5): another addon's window stays where its addon put it, and a managed window record
-- controls it with public panel methods only (R12): geometry, minimize, hide, idle opacity, click-through,
-- lock, and no input outside cursor mode so it stays on screen while the player plays. What we change is
-- recorded when the window is taken and put back when it is released. Nothing is reparented (G45, G52).

local PP = PinnedPanels
PP.Manage = PP.Manage or {}
local Manage = PP.Manage
local Layout, Input, Settings, Desktop, Geom = PP.Layout, PP.Input, PP.Settings, PP.Desktop, PP.Geom

local TIMER, INTERVAL = "PinnedPanels.Manage", 0.25
local FIGHT_LIMIT = 3

-- id -> { panel, original, applied, ownerHidden?, keyboard?, dragging?, fights }
Manage.live = Manage.live or {}
Manage.byPanel = Manage.byPanel or {}

local function adoptOf(rec) return rec.tabs[1].adopt end

local function changedLive()
	hook.Run("PinnedPanelsAdoptChanged")
end

function Manage.IsLive(id) return Manage.live[id] ~= nil end

function Manage.Panel(id)
	local entry = Manage.live[id]
	return entry and entry.panel
end

-- Closed by its addon without being removed (DFrame:Close with DeleteOnClose off, G57).
function Manage.OwnerHidden(id)
	local entry = Manage.live[id]
	return entry ~= nil and entry.ownerHidden == true
end

-- ── Applying ────────────────────────────────────────────────

-- Shown unless minimized or hidden (peek shows it); the mouse in cursor mode unless click-through (ALT
-- overrides); the keyboard while one of its text fields has focus or after a click when it needs the
-- keyboard (§33.5); idle opacity outside cursor mode (G27).
local function desired(id, rec, entry)
	local interactive = Input.Interactive()
	local shown = (Desktop.Shown(rec) and not Desktop.held[id]) or Desktop.peeking
	local mouse = interactive
	local focus = vgui.GetKeyboardFocus()
	local typing = IsValid(focus) and (focus == entry.panel or focus:HasParent(entry.panel))
	local keyboard = mouse and (entry.keyboard == true or typing)
	local alpha = (interactive or Desktop.peeking) and 1 or (rec.opacity or Settings.Get("idleOpacity") / 100)
	return shown, mouse, keyboard, math.Round(alpha * 255)
end

function Manage.Apply(id)
	local entry, rec = Manage.live[id], Layout.Get(id)
	if not (entry and rec) or not IsValid(entry.panel) then return end
	local p, a, o = entry.panel, entry.applied, entry.original
	local shown, mouse, keyboard, alpha = desired(id, rec, entry)
	if not entry.ownerHidden then
		if p:IsVisible() ~= shown then p:SetVisible(shown) end
		a.visible = shown
	end
	p:SetMouseInputEnabled(mouse)
	p:SetKeyboardInputEnabled(keyboard)
	a.mouse, a.keyboard = mouse, keyboard
	p:SetAlpha(alpha)
	if o.draggable ~= nil then p:SetDraggable(o.draggable and not rec.locked) end
	if o.sizable ~= nil then p:SetSizable(o.sizable and not rec.locked) end
	if not adoptOf(rec).noGeometry then
		local x, y = p:GetPos()
		if x ~= rec.x or y ~= rec.y then p:SetPos(rec.x, rec.y) end
		if p:GetWide() ~= rec.w or p:GetTall() ~= rec.h then p:SetSize(rec.w, rec.h) end
		a.x, a.y, a.w, a.h = rec.x, rec.y, rec.w, rec.h
	end
end

-- Called by the desktop whenever interactivity, peek, holds or opacity change.
function Manage.UpdateStates()
	local interactive = Input.Interactive()
	for id, entry in pairs(Manage.live) do
		if not interactive then entry.keyboard = nil end
		Manage.Apply(id)
	end
end

-- ── Taking and releasing ────────────────────────────────────

local function watch()
	if not timer.Exists(TIMER) then timer.Create(TIMER, INTERVAL, 0, function() Manage.Check() end) end
end

-- Puts panel under window id's control. opened: the player just opened it, so cursor mode comes on to
-- make it usable (a managed window only takes the mouse in cursor mode).
function Manage.Attach(id, panel, opened)
	local o = { visible = panel:IsVisible(), alpha = panel:GetAlpha(), mouse = panel:IsMouseInputEnabled(), keyboard = panel:IsKeyboardInputEnabled() }
	o.x, o.y = panel:GetPos()
	o.w, o.h = panel:GetSize()
	if isfunction(panel.GetDraggable) and isfunction(panel.SetDraggable) then o.draggable = panel:GetDraggable() end
	if isfunction(panel.GetSizable) and isfunction(panel.SetSizable) then o.sizable = panel:GetSizable() end
	Manage.live[id] = { panel = panel, original = o, applied = {}, fights = 0 }
	Manage.byPanel[panel] = id
	Input.keyboardOwners[panel] = true
	if opened and o.visible and o.mouse and panel:IsPopup() and not Input.cursorMode then Input.SetCursorMode(true) end
	Manage.Apply(id)
	watch()
	changedLive()
end

-- A new managed window for panel, where it is now. Returns the window id.
function Manage.Take(panel, adopt)
	adopt.mode = "manage"
	adopt.needsKeyboard = panel:IsKeyboardInputEnabled()
	local x, y = panel:GetPos()
	local id = Layout.PinAdopted(adopt, x, y, panel:GetWide(), panel:GetTall())
	Manage.Attach(id, panel)
	return id
end

local function forget(id, entry)
	Manage.live[id] = nil
	Manage.byPanel[entry.panel] = nil
	Input.keyboardOwners[entry.panel] = nil
	if not next(Manage.live) then timer.Remove(TIMER) end
end

-- Gives the window back exactly as it was taken (unpin, mode change, reload).
function Manage.Release(id)
	local entry = Manage.live[id]
	if not entry then return end
	forget(id, entry)
	local p, o = entry.panel, entry.original
	if IsValid(p) and not p:IsMarkedForDeletion() then
		PP.Recipes.Forget(p)
		p:SetPos(o.x, o.y)
		p:SetSize(o.w, o.h)
		p:SetAlpha(o.alpha)
		p:SetMouseInputEnabled(o.mouse)
		p:SetKeyboardInputEnabled(o.keyboard)
		if o.draggable ~= nil then p:SetDraggable(o.draggable) end
		if o.sizable ~= nil then p:SetSizable(o.sizable) end
		if not entry.ownerHidden then p:SetVisible(o.visible) end
	end
	changedLive()
end

function Manage.ReleaseAll()
	for id in pairs(Manage.live) do Manage.Release(id) end
end

-- The addon removed its window: the record waits for it to come back (§33.9), or goes if it was only for
-- this session.
local function gone(id, entry)
	forget(id, entry)
	local rec = Layout.Get(id)
	if rec and adoptOf(rec).recipe.kind == "session" then
		Layout.Unpin(id)
	else
		PP.Recipes.Wake()
	end
	changedLive()
end

-- Records without a managed record (unpinned, embedded now) let go of their window.
function Manage.Reconcile()
	for id in pairs(Manage.live) do
		local rec = Layout.Get(id)
		if not rec or rec.kind ~= "managed" then Manage.Release(id) end
	end
end

-- ── Keeping it applied ──────────────────────────────────────

-- The addon hid, showed, moved, removed or re-popped its window (MakePopup turns input back on), or the
-- player moved it by its own title bar (stored and snapped once, when the mouse is released).
local function check(id, entry)
	local rec, p = Layout.Get(id), entry.panel
	if not rec then return Manage.Release(id) end
	if not IsValid(p) or p:IsMarkedForDeletion() then return gone(id, entry) end
	local a, visible = entry.applied, p:IsVisible()
	if entry.ownerHidden then
		if not visible then return end
		entry.ownerHidden = nil
		if p:IsMouseInputEnabled() and not Input.cursorMode then Input.SetCursorMode(true) end
		Manage.Apply(id)
		return changedLive()
	end
	if a.visible and not visible then
		entry.ownerHidden = true
		return changedLive()
	end
	if p:IsMouseInputEnabled() ~= a.mouse or p:IsKeyboardInputEnabled() ~= a.keyboard then Manage.Apply(id) end

	if adoptOf(rec).noGeometry then return end
	local x, y = p:GetPos()
	local w, h = p:GetSize()
	if x == a.x and y == a.y and w == a.w and h == a.h then
		entry.fights = 0
		return
	end
	if Input.Interactive() and input.IsMouseDown(MOUSE_LEFT) then
		entry.dragging = true
		return
	end
	if entry.dragging then
		entry.dragging = nil
		if Settings.Get("snap") then
			x, y = Geom.SnapMove(x, y, w, h, Desktop.SnapRects(id), Settings.Get("snapDistance"), Geom.Usable())
		end
		Layout.SetGeometry(id, x, y, w, h)
		return Manage.Apply(id)
	end
	-- Moved by its addon: put it back, and stop trying if the addon keeps moving it (§33.12).
	entry.fights = entry.fights + 1
	if entry.fights >= FIGHT_LIMIT then
		Layout.SetAdopt(id, 1, { noGeometry = true })
		notification.AddLegacy(PP.L("adopt.fighting", Layout.Title(rec)), NOTIFY_HINT, 8)
		return
	end
	Manage.Apply(id)
end

function Manage.Check()
	for id, entry in pairs(Manage.live) do check(id, entry) end
end

-- Brings a managed window up; one its addon closed comes back as it was (the taskbar lists those).
function Manage.Front(id)
	local entry = Manage.live[id]
	if not entry or not IsValid(entry.panel) then return end
	if entry.ownerHidden then
		entry.ownerHidden = nil
		entry.panel:SetVisible(true)
		changedLive()
	end
	entry.panel:MoveToFront()
	Manage.Apply(id)
end

hook.Add("PinnedPanelsChanged", "PinnedPanels.Manage", function(kind, id)
	if kind == "windows" or kind == "tabs" or not id then return Manage.Reconcile() end
	if Manage.live[id] then Manage.Apply(id) end
end)

-- ── Clicks (§33.5) ──────────────────────────────────────────

local function managedOf(p)
	while IsValid(p) do
		local id = Manage.byPanel[p]
		if id then return id, p end
		p = p:GetParent()
	end
end

-- A click in a managed window focuses it for window keys; one that needs the keyboard (like an editor
-- that isn't a DTextEntry) takes it in cursor mode until a click elsewhere. Right-clicking its title bar
-- opens our window menu. A click anywhere else gives the keyboard back.
hook.Add("VGUIMousePressed", "PinnedPanels.Manage", function(panel, code)
	local id, root = managedOf(panel)
	for other, entry in pairs(Manage.live) do
		if other ~= id and entry.keyboard then
			entry.keyboard = nil
			Manage.Apply(other)
		end
	end
	if not id then return end
	Desktop.SetFocused(id)
	local entry, rec = Manage.live[id], Layout.Get(id)
	if code == MOUSE_RIGHT and (panel == root or panel == root.lblTitle) then
		PP.Actions.OpenWindowMenu(id)
	elseif rec and adoptOf(rec).needsKeyboard and Input.Interactive() and not entry.keyboard then
		entry.keyboard = true
		Manage.Apply(id)
	end
end)

hook.Add("GUIMousePressed", "PinnedPanels.Manage", function()
	for id, entry in pairs(Manage.live) do
		if entry.keyboard then
			entry.keyboard = nil
			Manage.Apply(id)
		end
	end
end)
