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
local BIG, BIG_START = 0.8, 0.6 -- of the screen, each way
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
-- An embedded window's shell is given its size, so its owner lays the contents out for the size they
-- have; if the owner then sets another, the window follows that (ownerSize, D29).

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

-- What the emptied window would have drawn itself (a header, a background, a phone's body), drawn here
-- by its own function (R18). Off until tried in game: whether it lands in the right place can't be told
-- without it, and the shell's own Paint still runs unseen (G69), so anything it does besides drawing
-- happens twice.
local shellPaint = CreateClientConVar("pinnedpanels_debug_shellpaint", "0", false, false, "Draw an embedded window's own background and overlay inside its tab (experimental)", 0, 1)

local function paintShell(self, name, w, h)
	local e = shellPaint:GetBool() and Embed.live[self.src]
	local s = e and e.mode == "embed" and not e.closed and e.shell
	if not (IsValid(s) and isfunction(s[name])) then return end
	local ok, err = pcall(s[name], s, w, h)
	if not ok and not e.paintError then
		e.paintError = true
		ErrorNoHalt("[Pinned Panels] " .. self.src .. " " .. name .. ": " .. tostring(err) .. "\n")
	end
end

function BOX:Paint(w, h)
	paintShell(self, "Paint", w, h)
	if self.notice then draw.SimpleText(self.notice, "DermaDefault", w / 2, h / 2, PP.Theme.textMuted, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER) end
end

function BOX:PaintOver(w, h)
	paintShell(self, "PaintOver", w, h)
end

vgui.Register("PinnedPanelsEmbedBox", BOX, "Panel")

-- ── Standing in for the window ──────────────────────────────
-- A window's contents call into it through GetParent(): a tab button tells its frame which tab is
-- active, a close button closes it. Their parent is our box now, so the box answers for the window:
-- every Lua method the window has and a plain panel hasn't is passed on to it, and what they read
-- from their parent is read from the window. What the engine itself calls on a panel is left out, or
-- the window would think, lay out and paint twice.
local ENGINE = {
	Init = true, Paint = true, PaintOver = true, Think = true, PerformLayout = true, AnimationThink = true, ApplySchemeSettings = true,
	OnRemove = true, OnDeletion = true, OnChildAdded = true, OnChildRemoved = true, OnSizeChanged = true, OnScreenSizeChanged = true,
	OnMousePressed = true, OnMouseReleased = true, OnMouseWheeled = true, OnCursorMoved = true, OnCursorEntered = true,
	OnCursorExited = true, OnKeyCodePressed = true, OnKeyCodeReleased = true, OnFocusChanged = true, OnTextChanged = true,
	TestHover = true, ActionSignal = true, DragHoverClick = true, DragHoverEnd = true, DroppedOn = true, LoadCookies = true,
	PreAutoRefresh = true, PostAutoRefresh = true, GenerateExample = true, PaintManual = true, DoModal = true,
	-- Nor what says which panel this is, or how the engine left it.
	ClassName = true, Base = true, BaseClass = true, ThisClass = true, Hovered = true, Depressed = true, Dragging = true,
}

local function standIn(inner, s)
	local t = inner:GetTable()
	local function forward(name)
		return function(_, ...)
			if not IsValid(s) then return end
			local fn = s[name]
			if isfunction(fn) then return fn(s, ...) end
		end
	end
	for name, v in pairs(s:GetTable()) do
		if isstring(name) and isfunction(v) and not ENGINE[name] and inner[name] == nil then t[name] = forward(name) end
	end
	-- Anything else it is asked for: the window's value, as it is at that moment.
	setmetatable(t, { __index = function(_, name)
		if ENGINE[name] or not IsValid(s) then return nil end
		local v = s:GetTable()[name]
		if isfunction(v) then
			v = forward(name)
			rawset(t, name, v)
		end
		return v
	end })
end

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

-- An overlay window comes with a backdrop: a bare full-screen popup, painted by the same file, that
-- dims the screen and closes the window when clicked. Left as it is, it would dim the tab its window
-- is in and take every click meant for it. It is ghosted with its window and comes back with it; its
-- owner removes it when the window goes.
local function backdropOf(s)
	local from = isfunction(s.Paint) and PP.Recipes.FileOf(s.Paint)
	if not from then return nil end
	for _, p in ipairs(vgui.GetWorldPanel():GetChildren()) do
		if p ~= s and p:IsVisible() and p:IsPopup() and p:ChildCount() == 0 and isfunction(p.Paint) and PP.Recipes.FileOf(p.Paint) == from
			and PP.Recipes.Refusal(p, p) == "refuse.scene" then
			return { panel = p, alpha = p:GetAlpha(), mouse = p:IsMouseInputEnabled(), keyboard = p:IsKeyboardInputEnabled() }
		end
	end
end

local function ghostBackdrop(b)
	local p = b.panel
	p:SetMouseInputEnabled(false)
	p:SetKeyboardInputEnabled(false)
	p:SetAlpha(0)
end

local function watch()
	-- Through the table, so a reload of this file is what runs from then on.
	if not timer.Exists(TIMER) then timer.Create(TIMER, INTERVAL, 0, function() Embed.Check() end) end
	Input.EachFrame("embed", function() Embed.Frame() end)
end

-- ── Colours ─────────────────────────────────────────────────
-- A window that paints itself dark puts light text on it, which our own background would make
-- unreadable. So a pinned window takes the colours of the one it holds: what the emptied window paints
-- is drawn into a render target, once over black and once over white. Where the two agree it painted
-- that colour; where they differ as the clears do, it painted nothing. The body's and the title
-- strip's most common colours become the window's, unless the player has chosen colours already.

local PROBE_HOOK = "PinnedPanels.Embed.Colours"
local PROBE_COLS, PROBE_ROWS = 8, 5
local PROBE_SOLID = 0.5   -- less opaque than this isn't a background
local PROBE_SHARE = 1 / 3 -- of the samples that have to agree
local PROBE_DARK = 140    -- a header darker than this gets light text
local probing = {}        -- src -> true
local probeRT

-- The shell's Paint over a grey level, read at the points and at one point outside it (the clear itself,
-- as the target gives it back). Its own function, under pcall (R18).
local function paintOn(s, w, h, shade, points, ref)
	render.PushRenderTarget(probeRT)
	render.Clear(shade, shade, shade, 255, true, true)
	cam.Start2D()
	-- Whatever was painted last left its alpha and its clipping behind: a ghosted shell's 0, a
	-- rectangle somewhere else on screen.
	local alpha = surface.GetAlphaMultiplier()
	local clipping = DisableClipping(true)
	surface.SetAlphaMultiplier(1)
	local ok = pcall(s.Paint, s, w, h)
	surface.SetAlphaMultiplier(alpha)
	DisableClipping(clipping)
	cam.End2D()
	local out
	if ok then
		render.CapturePixels()
		out = { ref = { render.ReadPixel(ref[1], ref[2]) } }
		for i, pt in ipairs(points) do out[i] = { render.ReadPixel(pt[1], pt[2]) } end
	end
	render.PopRenderTarget()
	return out
end

-- The most common painted colour at points[from..to], or nil when too little there was painted alike.
local function common(black, white, from, to)
	local span = math.max((white.ref[1] - black.ref[1] + white.ref[2] - black.ref[2] + white.ref[3] - black.ref[3]) / 3, 1)
	local buckets, best = {}, nil
	for i = from, to do
		local b, w = black[i], white[i]
		local alpha = 1 - (w[1] - b[1] + w[2] - b[2] + w[3] - b[3]) / 3 / span
		if alpha >= PROBE_SOLID then
			-- A see-through background has no colour of its own on screen: it gets the one it shows
			-- over mid grey. (Dividing the blend out isn't exact here: the target doesn't blend linearly.)
			local r, g, bl = (b[1] + w[1]) / 2, (b[2] + w[2]) / 2, (b[3] + w[3]) / 2
			local key = math.floor(r / 8) * 1024 + math.floor(g / 8) * 32 + math.floor(bl / 8)
			local bucket = buckets[key] or { n = 0, r = 0, g = 0, b = 0 }
			buckets[key] = bucket
			bucket.n, bucket.r, bucket.g, bucket.b = bucket.n + 1, bucket.r + r, bucket.g + g, bucket.b + bl
			if not best or bucket.n > best.n then best = bucket end
		end
	end
	if not best or best.n < (to - from + 1) * PROBE_SHARE then return nil end
	return Color(math.Round(best.r / best.n), math.Round(best.g / best.n), math.Round(best.b / best.n))
end

local function probe(src)
	local e, win = Embed.live[src], Layout.Find(src)
	local s = e and e.shell	if not (e and win and e.mode == "embed" and IsValid(s) and isfunction(s.Paint)) then return end
	if #win.tabs ~= 1 or next(win.colors) ~= nil then return end
	local w, h = s:GetSize()
	w, h = math.min(w, ScrW() - 2), math.min(h, ScrH() - 2)
	if w < PROBE_COLS or h < PROBE_ROWS then return end
	local _, top = s:GetDockPadding()
	local strip = IsValid(s.lblTitle) and top >= 8 and top < h / 2 and top or 0
	local points = {}
	for row = 1, PROBE_ROWS do
		for col = 1, PROBE_COLS do
			points[#points + 1] = { math.floor(w * (col - 0.5) / PROBE_COLS), math.floor(strip + (h - strip) * (row - 0.5) / PROBE_ROWS) }
		end
	end
	local body = #points
	for col = 1, strip > 0 and PROBE_COLS or 0 do
		points[#points + 1] = { math.floor(w * (col - 0.5) / PROBE_COLS), math.floor(strip / 2) }
	end
	probeRT = probeRT or GetRenderTarget("PinnedPanelsProbe", ScrW(), ScrH())
	local ref = { w + 1, h + 1 }
	local black = paintOn(s, w, h, 0, points, ref)
	local white = black and paintOn(s, w, h, 255, points, ref)
	if not white then return end
	local bg = common(black, white, 1, body)
	if not bg then return end
	-- No strip of its own, or nothing painted there: a header a shade off its background.
	local header = body < #points and common(black, white, body + 1, #points)
	if not header then
		local shift = (bg.r + bg.g + bg.b) / 3 < PROBE_DARK and 18 or -18
		header = Color(math.Clamp(bg.r + shift, 0, 255), math.Clamp(bg.g + shift, 0, 255), math.Clamp(bg.b + shift, 0, 255))
	end
	local light = (header.r * 299 + header.g * 587 + header.b * 114) / 1000 < PROBE_DARK
	Layout.SetColors(win.id, { bg = bg, header = header, text = light and Color(240, 240, 240) or Color(30, 30, 30) })
end

-- Drawing is only possible while the frame is drawn, so the look is taken in the next one.
local function probeSoon(src)
	if not Embed.live[src] then return end
	probing[src] = true
	hook.Add("PostRenderVGUI", PROBE_HOOK, function()
		hook.Remove("PostRenderVGUI", PROBE_HOOK)
		local list = probing
		probing = {}
		for s in pairs(list) do
			local ok, err = pcall(probe, s)
			if not ok then ErrorNoHalt("[Pinned Panels] " .. s .. " colours: " .. tostring(err) .. "\n") end
		end
	end)
end
Embed.MatchColours = probeSoon

-- The window whose part this is: the panel just below a root (the world panel, or the HUD's).
local function windowOf(p)
	while IsValid(p:GetParent()) and IsValid(p:GetParent():GetParent()) do p = p:GetParent() end
	return p
end

local giveKeyboard

-- A part is still its owner's to show, hide, place and size: a tab sheet hides the page it leaves and
-- lays out the one it shows, a list re-docks its rows. Left alone, that reaches the part in our window
-- (a pinned page went blank the moment another tab was chosen). So while a part is pinned, what its
-- owner says to it about its place goes to the placeholder, which is what stands in that place; the
-- part stays shown and filling its tab. The engine's own functions are kept to act on the part itself.
local META = FindMetaTable("Panel")
local PLACE = { "SetVisible", "SetPos", "SetSize", "SetWide", "SetTall", "Dock", "DockMargin", "SetZPos" }

local function shield(e)
	local t, ph = e.target:GetTable(), e.placeholder
	e.shielded = {}
	for _, name in ipairs(PLACE) do
		e.shielded[name] = rawget(t, name) or false
		t[name] = function(_, ...)
			if IsValid(ph) then return META[name](ph, ...) end
		end
	end
end

local function unshield(e)
	if not e.shielded or not IsValid(e.target) then return end
	local t = e.target:GetTable()
	for name, was in pairs(e.shielded) do t[name] = was or nil end
	e.shielded = nil
end

-- Says where the part went, in the place it left (its sheet still has a tab for it).
local function paintPlaceholder(_, w, h)
	draw.SimpleText(PP.L("embed.elsewhere"), "DermaDefault", w / 2, h / 2, PP.Theme.textMuted, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end

-- Moves target into tab src: a window's contents (mode "embed") or the one panel (mode "part").
function Embed.Attach(src, target, mode)
	-- A pinned window that was given the keyboard gives it back first: the window being emptied loses
	-- it, and the engine would hand it to that one and raise it.
	giveKeyboard(nil)
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
		-- The placeholder answers for the part where it was: an owner that goes through its children and
		-- calls them (a tool list clearing every category's selected row) still reaches the part.
		standIn(ph, target)
		ph.ppPlaceholder = true
		ph.Paint = paintPlaceholder
		ph:SetVisible(target:IsVisible())
		e.placeholder = ph
		adopt(e, target)
		-- Filling its tab, without the margins it had in its owner's layout (the spawn menu keeps its
		-- inside a hundred pixels from every edge), and shown even if it was a page its sheet had hidden.
		target:Dock(FILL)
		target:DockMargin(0, 0, 0, 0)
		target:SetVisible(true)
		shield(e)
	else
		local s = target
		e.shell = s
		e.original = { alpha = s:GetAlpha(), mouse = s:IsMouseInputEnabled(), keyboard = s:IsKeyboardInputEnabled() }
		e.original.w, e.original.h = s:GetSize()
		e.original.x, e.original.y = s:GetPos()
		for _, k in ipairs(CHROME) do
			if IsValid(s[k]) then e.skip[s[k]] = true end
		end
		e.box:SetSize(s:GetSize())
		e.box.inner:DockPadding(s:GetDockPadding())
		Embed.shells[s] = e
		standIn(e.box.inner, s)
		adoptChildren(e)
		ghost(e)
		e.backdrop = backdropOf(s)
		if e.backdrop then ghostBackdrop(e.backdrop) end
		probeSoon(src)
	end
	watch()
	hook.Run("PinnedPanelsAdoptChanged")
end

-- How much of a window's top is only its title strip, which our own header replaces: a DFrame's top
-- padding, but no further down than the first thing its owner put there (header buttons stay).
function Embed.Strip(s)
	if not IsValid(s.lblTitle) then return 0 end
	local _, top = s:GetDockPadding()
	local chrome = {}
	for _, k in ipairs(CHROME) do
		if IsValid(s[k]) then chrome[s[k]] = true end
	end
	for _, c in ipairs(s:GetChildren()) do
		if not chrome[c] and c:IsVisible() and not c:IsPopup() then
			local _, y = c:GetPos()
			top = math.min(top, math.max(y, 0))
		end
	end
	return top
end

-- A new pinned window for target, where it is on screen. A window's title strip is cropped away, so its
-- contents keep the positions their owner gave them (§33.6). Returns the window id. waiting: the window
-- is only made; the panel is taken when it is caught.
function Embed.Take(target, adoptRec, waiting)
	local x, y = target:LocalToScreen(0, 0)
	local w, h = target:GetSize()
	-- A part that fills the screen where it is (the whole inside of the spawn menu) would cover the game
	-- for good once pinned: it starts at a size that leaves room, and can be made larger.
	if adoptRec.mode == "part" and w > ScrW() * BIG and h > ScrH() * BIG then
		local nw, nh = math.Round(ScrW() * BIG_START), math.Round(ScrH() * BIG_START)
		x, y, w, h = x + (w - nw) / 2, y + (h - nh) / 2, nw, nh
	end
	local strip = adoptRec.mode == "embed" and Embed.Strip(target) or 0
	local id, src = Layout.PinAdopted(adoptRec, x - CHROME_W / 2, y - CHROME_H, w + CHROME_W, h - strip + CHROME_HEADER + CHROME_H)
	if strip > 0 then Layout.SetCrop(id, 1, { l = 0, t = strip, r = 0, b = 0 }) end
	if not waiting then Embed.Attach(src, target, adoptRec.mode) end
	Embed.Front(id)
	return id
end

-- Brings the window that just took a panel to the front, and keeps it there for a few frames: a
-- window that loses the keyboard by being emptied hands it back to whichever had it before, and the
-- engine raises that one over ours right after.
local FRONT_FRAMES = 4
local fronting = {} -- window id -> frames left

function Embed.Front(id)
	Desktop.Front(id)
	fronting[id] = FRONT_FRAMES
end

-- Gives everything back: children to their parents with their layout, in their order; the part to its
-- placeholder's place; the shell its size, alpha and input. If the owner removed its window, or the place
-- the part was in, the adopted panels go too (R15). A panel its owner already took back is left where the
-- owner put it (R19). close: the player unpinned it, so a window is then closed as its own close button
-- would (D39) instead of coming back on screen; one without a Close is hidden if it is a popup.
function Embed.Release(src, close)
	local e = Embed.live[src]
	if not e then return end
	Embed.live[src] = nil
	if not next(Embed.live) then
		timer.Remove(TIMER)
		Input.EachFrame("embed", nil)
	end
	unshield(e)
	for _, m in ipairs(e.moved) do
		local p, parent = m.panel, m.parent
		Embed.byPanel[p] = nil
		if IsValid(p) and not p:IsMarkedForDeletion() and p:GetParent() == e.box.inner then
			if not e.orphaned and IsValid(parent) and not parent:IsMarkedForDeletion() and IsValid(e.shell) and not e.shell:IsMarkedForDeletion() then
				p:SetParent(parent)
				local ph = e.placeholder
				if IsValid(ph) then
					-- A part goes back as its owner has its place now, which the placeholder kept.
					p:MoveToBefore(ph)
					p:Dock(ph:GetDock())
					p:DockMargin(ph:GetDockMargin())
					p:SetPos(ph:GetPos())
					p:SetSize(ph:GetSize())
					p:SetZPos(ph:GetZPos())
					p:SetVisible(ph:IsVisible())
				else
					p:Dock(m.dock)
					p:DockMargin(m.margin[1], m.margin[2], m.margin[3], m.margin[4])
					p:SetPos(m.x, m.y)
					p:SetSize(m.w, m.h)
					p:SetZPos(m.z)
				end
			else
				p:Remove()
			end
		end
	end
	if IsValid(e.placeholder) then e.placeholder:Remove() end
	local s, o = e.shell, e.original
	if o then Embed.shells[s] = nil end
	local alive = IsValid(s) and not s:IsMarkedForDeletion()
	if alive then PP.Recipes.Forget(s) end
	local b = e.backdrop
	-- Unpinned, the window is closed and its owner removes the backdrop; if it only hides the window,
	-- the backdrop stays as it is, unseen, rather than dimming the screen for a window that isn't there.
	if b and alive and not close and IsValid(b.panel) and not b.panel:IsMarkedForDeletion() then
		b.panel:SetAlpha(b.alpha)
		b.panel:SetMouseInputEnabled(b.mouse)
		b.panel:SetKeyboardInputEnabled(b.keyboard)
	end
	if o and alive then
		s:SetPos(o.x, o.y)
		s:SetSize(o.w, o.h)
		s:SetAlpha(o.alpha)
		s:SetMouseInputEnabled(o.mouse)
		s:SetKeyboardInputEnabled(o.keyboard)
		s:InvalidateLayout(true)
		if close and s:IsVisible() and PP.Recipes.IsWindow(s) then
			if isfunction(s.Close) then
				ProtectedCall(function() s:Close() end) -- R18
			elseif s:IsPopup() then
				s:SetVisible(false)
			end
		end
	end
	-- The window brought the cursor and is gone or closed now: the cursor goes with it.
	if e.cursor and (close or not alive) then Input.SetCursorMode(false) end
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

-- The shell sits where its contents show, so what its owner places beside "its window" (menus, pickers,
-- side panels) lands beside the tab. A popup's position is in screen space whatever its parent (G52).
local function follow(s, box)
	local x, y = box:LocalToScreen(0, 0)
	local parent = s:GetParent()
	if IsValid(parent) and not s:IsPopup() then x, y = parent:ScreenToLocal(x, y) end
	local sx, sy = s:GetPos()
	if sx ~= x or sy ~= y then s:SetPos(x, y) end
end

-- The owner's size wins (D29). The tab gives the shell its size (BOX:PerformLayout); when the shell then
-- has another, its owner set it, and the window is resized by the difference so the contents get the
-- size their owner lays them out for. Acted on once per disagreement, and only when it has held for two
-- frames (a layout still on its way looks the same for one). A window that can't be given that size
-- (it wouldn't fit the screen) keeps what fits; a resize by the player is undone only if the owner
-- insists.
local function ownerSize(src, e, s, box)
	local sw, sh = s:GetSize()
	local bw, bh = box:GetSize()
	if sw == bw and sh == bh then return end
	if e.sw ~= sw or e.sh ~= sh or e.bw ~= bw or e.bh ~= bh then
		e.sw, e.sh, e.bw, e.bh, e.sized = sw, sh, bw, bh, false
		return
	end
	if e.sized then return end
	local win = Layout.Find(src)
	local panel = win and Desktop.panels[win.id]
	if not IsValid(panel) or panel.drag or panel.resize or panel.animating or panel.editing or win.state ~= "normal" then return end
	e.sized = true
	Layout.SetGeometry(win.id, win.x, win.y, win.w + sw - bw, win.h + sh - bh, true)
end

-- Every frame, for a window's contents, with getters only. The owner re-popped its window: it is ghosted
-- again before it shows or takes a click. The owner gave it new children: they are adopted, so a window
-- that swaps its page on every click doesn't go blank.
local function frame(src, e, s)
	-- Hidden or shown by its owner: the tab says so. A window that takes the mouse brings the cursor
	-- when it comes back, as it did when it first opened, and takes it away again if it brought it.
	local closed = not s:IsVisible()
	if closed ~= (e.closed == true) then
		e.closed = closed
		e.box:SetClosed(closed)
		if closed and e.cursor then
			e.cursor = nil
			Input.SetCursorMode(false)
		elseif not closed and e.original.mouse and s:IsPopup() and not Input.cursorMode then
			e.cursor = true
			Input.SetCursorMode(true)
		end
	end
	if s:IsMouseInputEnabled() or s:IsKeyboardInputEnabled() or s:GetAlpha() > 0 then ghost(e) end
	local b = e.backdrop
	if b and IsValid(b.panel) and (b.panel:IsMouseInputEnabled() or b.panel:GetAlpha() > 0) then ghostBackdrop(b) end
	if s:ChildCount() ~= e.count then adoptChildren(e) end
	local box = e.box
	if e.closed or not box:IsVisible() or not IsValid(box:GetParent()) then return end
	follow(s, box)
	ownerSize(src, e, s, box)
end

function Embed.Frame()
	for id, left in pairs(fronting) do
		if Layout.Get(id) then Desktop.Front(id) end
		fronting[id] = left > 1 and left - 1 or nil
	end
	for src, e in pairs(Embed.live) do
		local s = e.shell
		if e.mode == "embed" and IsValid(s) and not s:IsMarkedForDeletion() then frame(src, e, s) end
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
-- again, and the tab waits for it to settle somewhere).
local function check(src, e)
	local win, i = Layout.Find(src)
	if not win then return Embed.Release(src) end
	local s = e.shell
	-- Something in the window removed its parent, which was our box: it meant the window.
	if e.mode == "embed" and IsValid(s) and not (IsValid(e.box) and IsValid(e.box.inner)) then s:Remove() end
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
	if e.mode == "embed" then prune(e) end
end

function Embed.Check()
	for src, e in pairs(Embed.live) do check(src, e) end
end

-- Tabs that were unpinned, or moved to managed mode, let go of their panels at once.
hook.Add("PinnedPanelsChanged", "PinnedPanels.Embed", function(kind)
	if kind ~= "windows" and kind ~= "tabs" then return end
	for src in pairs(Embed.live) do
		local win, i = Layout.Find(src)
		if not win then
			Embed.Release(src, true)
		elseif win.tabs[i].adopt.mode == "manage" then
			Embed.Release(src)
		end
	end
end)

-- An embedded panel that needs the keyboard (an editor that isn't a DTextEntry, §33.5) gives its window
-- the keyboard when clicked in cursor mode, until a click elsewhere; leaving cursor mode takes it back
-- (Desktop.UpdateStates).
local keyboardWindow

function giveKeyboard(win)
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
