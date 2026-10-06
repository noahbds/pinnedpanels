-- Embed mode (§33.6): another addon's panel in a pinned tab, for everything our windows do (groups, crop,
-- filter, keyboard navigation). A window's contents move into the tab and the emptied window (the shell)
-- stays alive but invisible, so its Think keeps running (G4); the window itself is never reparented (G45).
-- A part of a window moves alone and leaves an invisible placeholder so its owner's layout holds. Release
-- puts everything back as it was; adopted panels are only removed when their owner removed its window (R15).

local PP = PinnedPanels
PP.Embed = PP.Embed or {}
local Embed = PP.Embed
local Layout, Desktop, Input = PP.Layout, PP.Desktop, PP.Input

local TIMER, INTERVAL = "PinnedPanels.Embed", 0.25
-- Our window's chrome around a tab's content: its edges, and its header when there is no title strip to crop.
local CHROME_W, CHROME_H, CHROME_HEADER = 10, 4, 29
local CHROME = { "btnClose", "btnMaxim", "btnMinim", "lblTitle", "imgIcon" } -- DFrame's own (G57)

-- src -> { mode, target, shell, box, moved = { { panel, parent, dock, margin, x, y, w, h, z } }, skip,
--          original?, placeholder?, closed? }
Embed.live = Embed.live or {}
Embed.byPanel = Embed.byPanel or {} -- adopted panel -> entry
Embed.shells = Embed.shells or {}   -- emptied window -> entry

-- A part its owner keeps taking back is let go for good: this many times within this many seconds.
local FIGHT_MAX, FIGHT_TIME = 3, 10
local fights = {} -- src -> { since, n }

-- ── PinnedPanelsEmbedBox ────────────────────────────────────
-- The tab content: holds the adopted panels while the tab exists, hidden and unparented while it doesn't.
-- An embedded window's shell follows its size, so its owner lays the contents out for the size they have.

local BOX = {}

-- Mouse input on for both: panels take their parent's state when created (L22), and the box is made
-- before any window holds it.
function BOX:Init()
	self:SetMouseInputEnabled(true)
	self.inner = self:Add("Panel")
	self.inner:SetMouseInputEnabled(true)
	self.inner:Dock(FILL)
end

function BOX:SetClosed(closed)
	self.inner:SetVisible(not closed)
	self.notice = closed and PP.L("embed.closed") or nil
end

function BOX:PerformLayout(w, h)
	local e = Embed.live[self.src]
	if e and e.mode == "embed" and IsValid(e.shell) then e.shell:SetSize(w, h) end
end

function BOX:Paint(w, h)
	if self.notice then draw.SimpleText(self.notice, "DermaDefault", w / 2, h / 2, PP.Theme.textMuted, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER) end
end

vgui.Register("PinnedPanelsEmbedBox", BOX, "Panel")

-- ── Moving panels ───────────────────────────────────────────

local function remember(p)
	local x, y = p:GetPos()
	return { panel = p, parent = p:GetParent(), dock = p:GetDock(), margin = { p:GetDockMargin() }, x = x, y = y, w = p:GetWide(), h = p:GetTall(), z = p:GetZPos() }
end

local function adopt(e, p)
	e.moved[#e.moved + 1] = remember(p)
	Embed.byPanel[p] = e
	p:SetParent(e.box.inner)
end

-- The shell's children, in order, from a snapshot (G56): not its chrome, never a popup.
local function adoptChildren(e)
	for _, c in ipairs(e.shell:GetChildren()) do
		if not e.skip[c] and not Embed.byPanel[c] and not c:IsPopup() then adopt(e, c) end
	end
	e.count = e.shell:ChildCount()
end

-- The shell: no input, invisible, still visible to the engine so it keeps thinking (§33.6).
local function ghost(e)
	local s = e.shell
	s:SetMouseInputEnabled(false)
	s:SetKeyboardInputEnabled(false)
	s:SetAlpha(0)
end

local function watch()
	if not timer.Exists(TIMER) then timer.Create(TIMER, INTERVAL, 0, Embed.Check) end
	Input.EachFrame("embed", Embed.Frame)
end

-- The window whose part this is: the panel just below a root (the world panel, or the HUD's).
local function windowOf(p)
	while IsValid(p:GetParent()) and IsValid(p:GetParent():GetParent()) do p = p:GetParent() end
	return p
end

-- Moves target into tab src: a window's contents (mode "embed") or the one panel (mode "part").
function Embed.Attach(src, target, mode)
	local e = { mode = mode, target = target, moved = {}, skip = {} }
	e.box = vgui.Create("PinnedPanelsEmbedBox")
	e.box.src = src
	e.box:SetVisible(false)
	Embed.live[src] = e
	if mode == "part" then
		e.shell = windowOf(target)
		local ph = vgui.Create("Panel", target:GetParent())
		ph:SetMouseInputEnabled(false)
		ph:SetPos(target:GetPos())
		ph:SetSize(target:GetSize())
		ph:Dock(target:GetDock())
		ph:DockMargin(target:GetDockMargin())
		ph:SetZPos(target:GetZPos())
		ph:MoveToBefore(target)
		e.placeholder = ph
		adopt(e, target)
		target:Dock(FILL)
	else
		local s = target
		e.shell = s
		e.original = { alpha = s:GetAlpha(), mouse = s:IsMouseInputEnabled(), keyboard = s:IsKeyboardInputEnabled() }
		e.original.w, e.original.h = s:GetSize()
		for _, k in ipairs(CHROME) do
			if IsValid(s[k]) then e.skip[s[k]] = true end
		end
		e.box:SetSize(s:GetSize())
		e.box.inner:DockPadding(s:GetDockPadding())
		Embed.shells[s] = e
		adoptChildren(e)
		ghost(e)
	end
	watch()
	hook.Run("PinnedPanelsAdoptChanged")
end

-- A new pinned window for target, where it is on screen. A window's title strip is cropped away, so its
-- contents keep the positions their owner gave them (§33.6). Returns the window id. waiting: the window
-- is only made; the panel is taken when it is caught.
function Embed.Take(target, adoptRec, waiting)
	local x, y = target:LocalToScreen(0, 0)
	local w, h = target:GetSize()
	local _, top = target:GetDockPadding()
	local strip = adoptRec.mode == "embed" and IsValid(target.lblTitle) and top or 0
	local id, src = Layout.PinAdopted(adoptRec, x - CHROME_W / 2, y - CHROME_H, w + CHROME_W, h - strip + CHROME_HEADER + CHROME_H)
	if strip > 0 then Layout.SetCrop(id, 1, { l = 0, t = strip, r = 0, b = 0 }) end
	if not waiting then Embed.Attach(src, target, adoptRec.mode) end
	Desktop.Front(id)
	return id
end

-- Gives everything back: children to their parents with their layout, in their order; the part to its
-- placeholder's place; the shell its size, alpha and input. If the owner removed its window, or the place
-- the part was in, the adopted panels go too (R15). A panel its owner already took back is left where the
-- owner put it (R19).
function Embed.Release(src)
	local e = Embed.live[src]
	if not e then return end
	Embed.live[src] = nil
	if not next(Embed.live) then
		timer.Remove(TIMER)
		Input.EachFrame("embed", nil)
	end
	for _, m in ipairs(e.moved) do
		local p, parent = m.panel, m.parent
		Embed.byPanel[p] = nil
		if IsValid(p) and not p:IsMarkedForDeletion() and p:GetParent() == e.box.inner then
			if not e.orphaned and IsValid(parent) and not parent:IsMarkedForDeletion() and IsValid(e.shell) and not e.shell:IsMarkedForDeletion() then
				p:SetParent(parent)
				if IsValid(e.placeholder) then p:MoveToBefore(e.placeholder) end
				p:Dock(m.dock)
				p:DockMargin(m.margin[1], m.margin[2], m.margin[3], m.margin[4])
				p:SetPos(m.x, m.y)
				p:SetSize(m.w, m.h)
				p:SetZPos(m.z)
			else
				p:Remove()
			end
		end
	end
	if IsValid(e.placeholder) then e.placeholder:Remove() end
	local s, o = e.shell, e.original
	if o then Embed.shells[s] = nil end
	if o and IsValid(s) and not s:IsMarkedForDeletion() then
		s:SetSize(o.w, o.h)
		s:SetAlpha(o.alpha)
		s:SetMouseInputEnabled(o.mouse)
		s:SetKeyboardInputEnabled(o.keyboard)
		s:InvalidateLayout(true)
	end
	if IsValid(e.box) then e.box:Remove() end
	hook.Run("PinnedPanelsAdoptChanged")
end

function Embed.ReleaseAll()
	for src in pairs(Embed.live) do Embed.Release(src) end
end

-- ── Tab content ─────────────────────────────────────────────

function Embed.IsLive(src)
	return Embed.live[src] ~= nil
end

-- The tab host shows the box; Unbuild takes it back before the host is cleared or removed.
function Embed.Build(src, parent)
	local e = Embed.live[src]
	if not e then return nil end
	e.box:SetParent(parent)
	e.box:SetVisible(true)
	return e.box
end

function Embed.Unbuild(src, content)
	local e = Embed.live[src]
	if not e or e.box ~= content or not IsValid(content) then return end
	content:SetVisible(false)
	content:SetParent(nil)
end

-- ── Watching ────────────────────────────────────────────────

-- Every frame, for a window's contents, with getters only. The owner re-popped its window: it is ghosted
-- again before it shows or takes a click. The owner gave it new children: they are adopted, so a window
-- that swaps its page on every click doesn't go blank.
local function frame(e, s)
	if s:IsMouseInputEnabled() or s:IsKeyboardInputEnabled() or s:GetAlpha() > 0 then ghost(e) end
	if s:ChildCount() ~= e.count then adoptChildren(e) end
end

function Embed.Frame()
	for _, e in pairs(Embed.live) do
		local s = e.shell
		if e.mode == "embed" and IsValid(s) and not s:IsMarkedForDeletion() then frame(e, s) end
	end
end

-- Panels that are gone, or that their owner took back out of the box, are no longer ours to return (R19).
local function prune(e)
	for n = #e.moved, 1, -1 do
		local p = e.moved[n].panel
		if not IsValid(p) or p:IsMarkedForDeletion() or p:GetParent() ~= e.box.inner then
			Embed.byPanel[p] = nil
			table.remove(e.moved, n)
		end
	end
end

-- Whether src's part was taken back too often to try again.
local function fighting(src)
	local f, now = fights[src], RealTime()
	if not f or now - f.since > FIGHT_TIME then
		f = { since = now, n = 0 }
		fights[src] = f
	end
	f.n = f.n + 1
	return f.n >= FIGHT_MAX
end

-- Four times a second. The owner removed its window or the part: release, which removes what it left
-- behind (R15), and the tab waits (or goes, if it was for this session). A part can also lose its place
-- (its owner removed what held it: the part goes too) or be taken back by its owner (it is the owner's
-- again, and the tab waits for it to settle somewhere). The owner hid its window: the tab says so.
local function check(src, e)
	local win, i = Layout.Find(src)
	if not win then return Embed.Release(src) end
	local s = e.shell
	local gone = not IsValid(s) or s:IsMarkedForDeletion() or not IsValid(e.target) or e.target:IsMarkedForDeletion()
	local tookBack = false
	if e.mode == "part" and not gone then
		e.orphaned = not IsValid(e.placeholder)
		tookBack = not e.orphaned and e.target:GetParent() ~= e.box.inner
		gone = e.orphaned or tookBack
	end
	if gone then
		Embed.Release(src)
		if win.tabs[i].adopt.recipe.kind == "session" then
			Layout.UnpinTab(win.id, i)
		elseif tookBack and fighting(src) then
			notification.AddLegacy(PP.L("embed.fighting", Layout.TabTitle(win.tabs[i])), NOTIFY_HINT, 8)
			Layout.UnpinTab(win.id, i)
		else
			PP.Recipes.Wake()
		end
		return
	end
	if e.mode ~= "embed" then return end
	prune(e)
	local closed = not s:IsVisible()
	if closed ~= (e.closed == true) then
		e.closed = closed
		e.box:SetClosed(closed)
	end
end

function Embed.Check()
	for src, e in pairs(Embed.live) do check(src, e) end
end

-- Tabs that were unpinned let go of their panels at once.
hook.Add("PinnedPanelsChanged", "PinnedPanels.Embed", function(kind)
	if kind ~= "windows" and kind ~= "tabs" then return end
	for src in pairs(Embed.live) do
		if not Layout.Find(src) then Embed.Release(src) end
	end
end)

-- An embedded panel that needs the keyboard (an editor that isn't a DTextEntry, §33.5) gives its window
-- the keyboard when clicked in cursor mode, until a click elsewhere; leaving cursor mode takes it back
-- (Desktop.UpdateStates).
local keyboardWindow

local function giveKeyboard(win)
	if IsValid(keyboardWindow) and keyboardWindow ~= win then keyboardWindow:SetKeyboardInputEnabled(false) end
	keyboardWindow = win
	if IsValid(win) then win:SetKeyboardInputEnabled(true) end
end

hook.Add("VGUIMousePressed", "PinnedPanels.Embed", function(panel)
	local p = panel
	while IsValid(p) do
		local e = Embed.byPanel[p]
		if e then
			local win, i = Layout.Find(e.box.src)
			if win and win.tabs[i].adopt.needsKeyboard and Input.Interactive() then return giveKeyboard(Desktop.panels[win.id]) end
			break
		end
		p = p:GetParent()
	end
	giveKeyboard(nil)
end)

hook.Add("GUIMousePressed", "PinnedPanels.Embed", function() giveKeyboard(nil) end)
