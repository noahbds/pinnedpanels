-- The layout document (§13): windows holding 1..N tabs. Layout is its only writer (§10.2): every operation
-- validates, mutates, marks storage dirty and queues PinnedPanelsChanged(kind, id), flushed once per frame.
-- Each frame with changes is one undo step (FF10).

local PP = PinnedPanels
PP.Layout = PP.Layout or {}
local Layout, Geom, Util = PP.Layout, PP.Geom, PP.Util

local DEFAULT_W, DEFAULT_H = 280, 400
local SPAWN_X, SPAWN_Y = 120, 120
local SPLIT_OFFSET = 30
local MIN_SIZE = 40 -- a sanity floor; the window control enforces the real minimum while resizing
local MAX_TITLE = 64
local CLOSED_MAX = 15
local ARRANGE_MARGIN = 8
local KIND_ORDER = { windows = 1, tabs = 2, state = 3, geometry = 4, style = 5 }
local UNDO_MAX = 50

-- New named groups take the next accent in turn (as v1's group colours).
local GROUP_ACCENTS = {
	Color(255, 200, 60), Color(60, 200, 255), Color(200, 100, 255), Color(100, 255, 150),
	Color(255, 120, 100), Color(255, 160, 220), Color(160, 220, 80), Color(80, 220, 220),
}

-- "Recently closed" lives for the session only (§13.2) and survives pinnedpanels_reload.
Layout.closed = Layout.closed or {}

local doc = { v = 2, windows = {}, nextId = 1 }
local byId = {}
local bySrc -- src -> window, rebuilt lazily after tab changes

-- ── Change events ───────────────────────────────────────────

local pending, queued = {}, false

-- Undo (FF10): the first change in a frame pushes the document as it was when the last frame's changes
-- were flushed (stable), so a drag, a merge or "unpin all" is one step. Loading, refitting to the screen
-- and undo itself happen quietly and push nothing.
local undo, redo = {}, {}
local stable, stepOpen, quiet = nil, false, 0
local snapshot -- defined with the helpers below

function Layout.FlushChanges()
	queued = false
	stepOpen = false
	stable = snapshot()
	local list = {}
	for _, e in pairs(pending) do list[#list + 1] = e end
	pending = {}
	table.sort(list, function(a, b)
		if a.kind ~= b.kind then return KIND_ORDER[a.kind] < KIND_ORDER[b.kind] end
		return (a.id or "") < (b.id or "")
	end)
	for _, e in ipairs(list) do hook.Run("PinnedPanelsChanged", e.kind, e.id) end
end

-- id nil means "every window".
local function changed(kind, id, noSave)
	if not noSave then PP.Storage.MarkDirty() end
	if not noSave and quiet == 0 and not stepOpen and stable then
		stepOpen = true
		undo[#undo + 1] = stable
		if #undo > UNDO_MAX then table.remove(undo, 1) end
		redo = {}
	end
	if kind == "windows" or kind == "tabs" then bySrc = nil end
	local key = kind .. ":" .. (id or "*")
	if pending[key] then return end
	pending[key] = { kind = kind, id = id }
	if not queued then
		queued = true
		Util.NextFrame(nil, Layout.FlushChanges)
	end
end

-- ── Reading ─────────────────────────────────────────────────

function Layout.Document() return doc end
function Layout.Windows() return doc.windows end
function Layout.Get(id) return byId[id] end

-- The window holding src, and the tab's index in it.
function Layout.Find(src)
	if not bySrc then
		bySrc = {}
		for _, w in ipairs(doc.windows) do
			for _, t in ipairs(w.tabs) do bySrc[t.src] = w end
		end
	end
	local w = bySrc[src]
	if not w then return nil end
	for i, t in ipairs(w.tabs) do
		if t.src == src then return w, i end
	end
end

-- Custom titles win over the source's localized one (L19); an adopted panel is named by its signature.
function Layout.TabTitle(tab)
	return tab.title or (tab.adopt and PP.Recipes.Title(tab.adopt)) or PP.Sources.Title(tab.src)
end

function Layout.Title(w)
	if w.title then return w.title end
	local tab = w.tabs[w.active] or w.tabs[1]
	return tab and Layout.TabTitle(tab) or ""
end

-- ── Helpers ─────────────────────────────────────────────────

local function copy(t)
	if type(t) ~= "table" then return t end
	local c = setmetatable({}, getmetatable(t))
	for k, v in pairs(t) do c[k] = copy(v) end
	return c
end

function snapshot()
	return { windows = copy(doc.windows), nextId = doc.nextId }
end

local function quietly(fn, ...)
	quiet = quiet + 1
	local ok, err = pcall(fn, ...)
	quiet = quiet - 1
	if not ok then error(err, 0) end
end

local function others(except)
	local rects = {}
	for _, w in ipairs(doc.windows) do
		if w ~= except and w.state ~= "minimized" and #w.tabs > 0 then rects[#rects + 1] = w end
	end
	return rects
end

local function place(w, h, px, py)
	local ux, uy, uw, uh = Geom.Usable()
	w, h = math.min(w, uw), math.min(h, uh)
	local x, y = Geom.FreeSpot(w, h, others(), px, py, ux, uy, uw, uh)
	return x, y, w, h
end

local function add(win)
	win.id = "w" .. doc.nextId
	doc.nextId = doc.nextId + 1
	doc.windows[#doc.windows + 1] = win
	byId[win.id] = win
	changed("windows", win.id)
	return win
end

local function newWindow(tabs, x, y, w, h, title)
	return add({
		tabs = tabs, active = 1, x = x, y = y, w = w, h = h, state = "normal", title = title,
		locked = false, clickThrough = false, filterBar = false, colors = {},
	})
end

local function remove(win)
	for i, w in ipairs(doc.windows) do
		if w == win then
			table.remove(doc.windows, i)
			break
		end
	end
	byId[win.id] = nil
	changed("windows", win.id)
end

local function pushClosed(win)
	local stack = Layout.closed
	stack[#stack + 1] = copy(win)
	while #stack > CLOSED_MAX do table.remove(stack, 1) end
end

local function setRect(win, x, y, w, h)
	if win.x == x and win.y == y and win.w == w and win.h == h then return false end
	win.x, win.y, win.w, win.h = x, y, w, h
	changed("geometry", win.id)
	return true
end

-- The window takes the active tab's remembered size (L6), except while maximized.
local function applyTabSize(win)
	local tab = win.tabs[win.active]
	if not tab or not tab.size or win.state == "maximized" then return end
	setRect(win, Geom.Fit(win.x, win.y, tab.size.w, tab.size.h, Geom.Usable()))
end

-- Keeps the active tab pointing at the same tab after tab i was removed.
local function removedTab(win, i)
	if i < win.active then
		win.active = win.active - 1
	elseif i == win.active then
		win.active = math.Clamp(win.active, 1, math.max(#win.tabs, 1))
		applyTabSize(win)
	end
end

local function cleanTitle(title)
	if not isstring(title) then return nil end
	title = string.Trim(title)
	if title == "" then return nil end
	if #title > MAX_TITLE then title = title:sub(1, MAX_TITLE):gsub("[\192-\255][\128-\191]*$", "") end
	return title
end

-- ── Lifecycle ───────────────────────────────────────────────

-- Takes a sanitized document (or nil for a fresh one), rescaling it if it was saved at another resolution (E3).
function Layout.Load(loaded)
	doc = loaded or { v = 2, windows = {}, nextId = 1 }
	byId, bySrc = {}, nil
	for _, w in ipairs(doc.windows) do byId[w.id] = w end
	local screen = doc.screen
	doc.screen = { w = ScrW(), h = ScrH() }
	if screen and (screen.w ~= ScrW() or screen.h ~= ScrH()) then
		quietly(Layout.RescaleAll, screen.w, screen.h)
	else
		quietly(Layout.Refit)
	end
	undo, redo, stepOpen = {}, {}, false
	stable = snapshot()
	changed("windows", nil, true)
end

-- Puts a saved state back. Ids only go forward, so a window control never meets another window's id.
local function restore(state)
	quietly(function()
		doc.windows, doc.nextId = state.windows, math.max(doc.nextId, state.nextId)
		byId, bySrc = {}, nil
		for _, w in ipairs(doc.windows) do byId[w.id] = w end
		Layout.Refit()
		changed("windows")
	end)
	stable = snapshot()
end

function Layout.CanUndo() return #undo > 0 end
function Layout.CanRedo() return #redo > 0 end

function Layout.Undo()
	local state = table.remove(undo)
	if not state then return false end
	redo[#redo + 1] = snapshot()
	restore(state)
	return true
end

function Layout.Redo()
	local state = table.remove(redo)
	if not state then return false end
	undo[#undo + 1] = snapshot()
	restore(state)
	return true
end

-- Replaces the whole document (an import or its undo) and saves it. The write keeps the previous file as
-- the backup (R3, E34).
function Layout.Replace(newDoc)
	PP.Storage.Flush() -- pending changes reach the file first, so the backup is the layout as it was
	Layout.Load(newDoc)
	PP.Storage.MarkDirty()
end

-- ── Pinning ─────────────────────────────────────────────────

-- Pins src in a new window, or brings back the window that already has it (E22, D10).
-- Returns the window id and whether it already existed.
function Layout.Pin(src, w, h)
	local win, i = Layout.Find(src)
	if win then
		Layout.Restore(win.id)
		Layout.Activate(win.id, i)
		return win.id, true
	end
	local x, y
	x, y, w, h = place(w or DEFAULT_W, h or DEFAULT_H, SPAWN_X, SPAWN_Y)
	return newWindow({ { src = src } }, x, y, w, h).id, false
end

-- Removes a whole window; it comes back as one "recently closed" entry (E21, B20).
function Layout.Unpin(id)
	local win = byId[id]
	if not win then return false end
	if #win.tabs > 0 then pushClosed(win) end
	remove(win)
	return true
end

-- Removes one tab. The last tab takes the window with it unless keepEmpty (named groups, §13.1).
function Layout.UnpinTab(id, i, keepEmpty)
	local win = byId[id]
	local tab = win and win.tabs[i]
	if not tab then return false end
	if #win.tabs == 1 and not keepEmpty then return Layout.Unpin(id) end
	local closed = copy(win)
	closed.tabs, closed.active, closed.title = { copy(tab) }, 1, nil
	pushClosed(closed)
	table.remove(win.tabs, i)
	removedTab(win, i)
	changed("tabs", id)
	return true
end

-- Reopens the most recently closed window, minus tabs that were pinned again since (F24).
function Layout.Reopen()
	local stack = Layout.closed
	while #stack > 0 do
		local win = table.remove(stack)
		local tabs = {}
		for _, t in ipairs(win.tabs) do
			if not Layout.Find(t.src) then tabs[#tabs + 1] = t end
		end
		if #tabs > 0 then
			if win.state == "maximized" and win.restore then
				win.x, win.y, win.w, win.h = win.restore.x, win.restore.y, win.restore.w, win.restore.h
			end
			win.tabs, win.state, win.restore = tabs, "normal", nil
			win.active = math.Clamp(win.active, 1, #tabs)
			win.x, win.y, win.w, win.h = Geom.Fit(win.x, win.y, win.w, win.h, Geom.Usable())
			if win.quickKey then
				for _, w in ipairs(doc.windows) do
					if w.quickKey == win.quickKey then win.quickKey = nil end
				end
			end
			return add(win).id
		end
	end
end

-- Moves tab i of fromId to toIndex in toId: a reorder when toId == fromId, a merge into another
-- window, or a split into a new window when toId is nil (F15). Merging never nests windows (L7).
-- Returns the id of the window that now holds the tab.
function Layout.MoveTab(fromId, i, toId, toIndex)
	local from = byId[fromId]
	local tab = from and from.tabs[i]
	if not tab then return nil end
	-- A managed window is another addon's window: nothing moves in or out of it (§33.4).
	if from.kind == "managed" or (toId and byId[toId] and byId[toId].kind == "managed") then return nil end

	if toId == fromId then
		toIndex = math.Clamp(toIndex or #from.tabs, 1, #from.tabs)
		if toIndex ~= i then
			local activeTab = from.tabs[from.active]
			table.remove(from.tabs, i)
			table.insert(from.tabs, toIndex, tab)
			for j, t in ipairs(from.tabs) do
				if t == activeTab then from.active = j end
			end
			changed("tabs", fromId)
		end
		return fromId
	end

	local to = toId and byId[toId]
	if toId and not to then return nil end

	-- The tab remembers the size it had so it can have it again (L6).
	if i == from.active or not tab.size then tab.size = { w = from.w, h = from.h } end
	table.remove(from.tabs, i)

	if to then
		toIndex = math.Clamp(toIndex or #to.tabs + 1, 1, #to.tabs + 1)
		table.insert(to.tabs, toIndex, tab)
		if #to.tabs == 1 then
			to.active = 1
			applyTabSize(to)
		elseif toIndex <= to.active then
			to.active = to.active + 1
		end
		changed("tabs", toId)
	else
		local x, y, w, h = place(tab.size.w, tab.size.h, from.x + SPLIT_OFFSET, from.y + SPLIT_OFFSET)
		to = newWindow({ tab }, x, y, w, h)
	end

	-- An emptied window goes away unless it is a named group; one tab left keeps the window (E20).
	if #from.tabs == 0 and not from.title then
		remove(from)
	else
		removedTab(from, i)
		changed("tabs", fromId)
	end
	return to.id
end

function Layout.Activate(id, i)
	local win = byId[id]
	if not win or not win.tabs[i] or win.active == i then return false end
	if win.state ~= "maximized" then win.tabs[win.active].size = { w = win.w, h = win.h } end
	win.active = i
	applyTabSize(win)
	changed("tabs", id)
	return true
end

-- An empty named window that shows only in the Pinned list until it gets a tab (§13.1).
function Layout.NewGroup(title)
	title = cleanTitle(title)
	if not title then return nil end
	local groups = 0
	for _, w in ipairs(doc.windows) do
		if w.title then groups = groups + 1 end
	end
	local x, y, w, h = place(DEFAULT_W, DEFAULT_H, SPAWN_X, SPAWN_Y)
	local win = newWindow({}, x, y, w, h, title)
	local c = GROUP_ACCENTS[groups % #GROUP_ACCENTS + 1]
	win.accent = Color(c.r, c.g, c.b, c.a)
	return win.id
end

-- Every tab but the first goes to its own window; the first keeps this one, no longer a group (F15).
function Layout.Dissolve(id)
	local win = byId[id]
	if not win then return false end
	for i = #win.tabs, 2, -1 do Layout.MoveTab(id, i, nil) end
	if #win.tabs == 0 then return Layout.Unpin(id) end
	win.title, win.accent = nil, nil
	changed("style", id)
	return true
end

-- Unpins every tab. A named group stays as an empty group; anything else goes away. Either way the
-- tabs come back as one "recently closed" entry (B20).
function Layout.ClearTabs(id)
	local win = byId[id]
	if not win or #win.tabs == 0 then return false end
	if not win.title then return Layout.Unpin(id) end
	pushClosed(win)
	win.tabs, win.active = {}, 1
	changed("tabs", id)
	return true
end

-- ── Adopted panels (§33) ────────────────────────────────────
-- A panel another addon made. Managed ("manage"), it stays where its addon put it and its window record
-- has kind = "managed"; embedded ("embed", "part"), it lives in a tab like any source. Either way its tab
-- is "adopt:<n>" and carries the adopt record (§33.10).

local ADOPT_FIELDS = { mode = true, signature = true, recipe = true, needsKeyboard = true, noGeometry = true }

-- A new window holding one adopted tab. Returns the window id and the tab's src.
function Layout.PinAdopted(adopt, x, y, w, h)
	local n = doc.nextId
	while Layout.Find("adopt:" .. n) do n = n + 1 end
	doc.nextId = n
	local src = "adopt:" .. n
	x, y, w, h = Geom.Fit(math.Round(x), math.Round(y), math.max(math.Round(w), MIN_SIZE), math.max(math.Round(h), MIN_SIZE), Geom.Usable())
	local win = newWindow({ { src = src, adopt = adopt } }, x, y, w, h)
	if adopt.mode == "manage" then win.kind = "managed" end
	return win.id, src
end

-- Changes fields of tab i's adopt record. A new mode moves it between a managed window and a pinned one,
-- so managed mode needs the tab to be alone in its window.
function Layout.SetAdopt(id, i, fields)
	local win = byId[id]
	local tab = win and win.tabs[i]
	if not (tab and tab.adopt) then return false end
	if fields.mode == "manage" and #win.tabs > 1 then return false end
	for k, v in pairs(fields) do
		if ADOPT_FIELDS[k] then tab.adopt[k] = v end
	end
	local kind = tab.adopt.mode == "manage" and "managed" or nil
	if win.kind == kind then
		changed("style", id)
		return true
	end
	win.kind = kind
	if kind and win.state == "maximized" then
		local r = win.restore or win
		win.state, win.restore = "normal", nil
		win.x, win.y, win.w, win.h = r.x, r.y, r.w, r.h
	end
	changed("windows", id)
	return true
end

-- ── Window state ────────────────────────────────────────────

function Layout.Minimize(id)
	local win = byId[id]
	if not win or win.state == "minimized" then return false end
	win.state = "minimized"
	changed("state", id)
	return true
end

-- Back from minimized, to maximized if it was maximized before.
function Layout.Restore(id)
	local win = byId[id]
	if not win or win.state ~= "minimized" then return false end
	if win.restore then
		win.state = "maximized"
		setRect(win, Geom.Usable())
	else
		win.state = "normal"
	end
	changed("state", id)
	return true
end

-- Roll-up (FF6): a normal window shrinks to its header and keeps its size for when it unrolls.
function Layout.ToggleRoll(id)
	local win = byId[id]
	if not win or win.kind == "managed" then return false end
	if win.state == "rolled" then
		win.state = "normal"
	elseif win.state == "normal" then
		win.state = "rolled"
	else
		return false
	end
	changed("state", id)
	return true
end

-- Maximize fills the usable area; the crop is kept on the tab and suspended by the window (B27, E28).
function Layout.ToggleMaximize(id)
	local win = byId[id]
	if not win or win.locked or win.state == "minimized" then return false end
	if win.state == "maximized" then
		local r = win.restore or win
		win.state, win.restore = "normal", nil
		setRect(win, Geom.Fit(r.x, r.y, r.w, r.h, Geom.Usable()))
	else
		win.restore = { x = win.x, y = win.y, w = win.w, h = win.h }
		win.state = "maximized"
		setRect(win, Geom.Usable())
	end
	changed("state", id)
	return true
end

-- A user move or resize. Locked windows refuse unless force (auto-size may resize them, E18).
-- Moving a maximized window makes it a normal one at the new geometry.
function Layout.SetGeometry(id, x, y, w, h, force)
	local win = byId[id]
	if not win or (win.locked and not force) then return false end
	w, h = math.max(math.Round(w), MIN_SIZE), math.max(math.Round(h), MIN_SIZE)
	x, y, w, h = Geom.Fit(math.Round(x), math.Round(y), w, h, Geom.Usable())
	if win.state == "maximized" then
		win.state, win.restore = "normal", nil
		changed("state", id)
	end
	setRect(win, x, y, w, h)
	if #win.tabs > 1 then win.tabs[win.active].size = { w = win.w, h = win.h } end
	return true
end

local function setFlag(field, kind)
	return function(id, value)
		local win = byId[id]
		if not win then return false end
		value = value == true
		if win[field] ~= value then
			win[field] = value
			changed(kind, id)
		end
		return true
	end
end

Layout.SetLocked = setFlag("locked", "state")
Layout.SetClickThrough = setFlag("clickThrough", "state")
Layout.SetFilterBar = setFlag("filterBar", "style")

-- nil follows the idleOpacity setting.
function Layout.SetOpacity(id, frac)
	local win = byId[id]
	if not win then return false end
	win.opacity = Util.Finite(frac) and math.Clamp(frac, 0.05, 1) or nil
	changed("style", id)
	return true
end

-- colors = { bg?, header?, text? }; missing entries follow the settings.
function Layout.SetColors(id, colors)
	local win = byId[id]
	if not win then return false end
	win.colors = { bg = colors.bg, header = colors.header, text = colors.text }
	changed("style", id)
	return true
end

function Layout.SetAccent(id, color)
	local win = byId[id]
	if not win then return false end
	win.accent = color
	changed("style", id)
	return true
end

-- Renames tab i, or the window when i is nil. A single-tab window's name belongs to its tab so it
-- travels with it; an empty name goes back to the localized default (L19, F27, B8).
function Layout.Rename(id, i, title)
	local win = byId[id]
	if not win then return false end
	title = cleanTitle(title)
	if not i and #win.tabs == 1 then i = 1 end
	if i then
		if not win.tabs[i] then return false end
		win.tabs[i].title = title
	elseif title or #win.tabs > 0 then
		win.title = title
	else
		return false -- an empty group needs its name
	end
	changed("style", id)
	return true
end

-- One window per quick key (F21); KEY_NONE or nil clears it.
function Layout.SetQuickKey(id, key)
	local win = byId[id]
	if not win then return false end
	if key == KEY_NONE then key = nil end
	if key then
		for _, w in ipairs(doc.windows) do
			if w ~= win and w.quickKey == key then
				w.quickKey = nil
				changed("style", w.id)
			end
		end
	end
	win.quickKey = key
	changed("style", id)
	return true
end

-- crop = { l, t, r, b } insets in content pixels, or nil.
function Layout.SetCrop(id, i, crop)
	local win = byId[id]
	local tab = win and win.tabs[i]
	if not tab then return false end
	if crop then
		local function inset(v)
			v = tonumber(v)
			return Util.Finite(v) and math.max(0, math.Round(v)) or 0
		end
		local l, t, r, b = inset(crop.l), inset(crop.t), inset(crop.r), inset(crop.b)
		crop = l + t + r + b > 0 and { l = l, t = t, r = r, b = b } or nil
	end
	tab.crop = crop
	changed("tabs", id)
	return true
end

-- ── Whole layout ────────────────────────────────────────────

-- Tiles visible, unlocked windows in rows from the top-left, sorted by title (F18, E18).
function Layout.Arrange()
	local list = {}
	for _, win in ipairs(doc.windows) do
		if win.state ~= "minimized" and not win.locked and #win.tabs > 0 and not (win.kind == "managed" and win.tabs[1].adopt.noGeometry) then
			list[#list + 1] = win
		end
	end
	table.sort(list, function(a, b) return Layout.Title(a):lower() < Layout.Title(b):lower() end)

	local ux, uy, uw, uh = Geom.Usable()
	local m = ARRANGE_MARGIN
	local x, y, rowH = ux + m, uy + m, 0
	for _, win in ipairs(list) do
		if win.state == "maximized" then
			local r = win.restore or win
			win.state, win.restore = "normal", nil
			win.w, win.h = r.w, r.h
			changed("state", win.id)
		end
		local w, h = math.min(win.w, uw - m * 2), math.min(win.h, uh - m * 2)
		if x + w + m > ux + uw and x > ux + m then
			x, y, rowH = ux + m, y + rowH + m, 0
		end
		if y + h + m > uy + uh then y = uy + m end
		setRect(win, x, y, w, h)
		x = x + w + m
		rowH = math.max(rowH, h)
	end
end

-- Maximized windows fill the usable area; everything else is clamped into it (E4, E5).
function Layout.Refit()
	local ux, uy, uw, uh = Geom.Usable()
	for _, win in ipairs(doc.windows) do
		if win.state == "maximized" or (win.state == "minimized" and win.restore) then
			setRect(win, ux, uy, uw, uh)
		else
			setRect(win, Geom.Fit(win.x, win.y, win.w, win.h, ux, uy, uw, uh))
		end
		local r = win.restore
		if r then r.x, r.y, r.w, r.h = Geom.Fit(r.x, r.y, r.w, r.h, ux, uy, uw, uh) end
	end
end

-- Every stored rectangle scales with the resolution, then gets clamped (E3, B17). Crops are
-- content pixels, which don't scale.
function Layout.RescaleAll(oldW, oldH)
	local nw, nh = ScrW(), ScrH()
	doc.screen = { w = nw, h = nh }
	if not (Util.Finite(oldW) and Util.Finite(oldH)) or oldW <= 0 or oldH <= 0 then return end
	if oldW == nw and oldH == nh then return end
	local kx, ky = nw / oldW, nh / oldH
	local function scale(r)
		r.x, r.y = math.Round(r.x * kx), math.Round(r.y * ky)
		r.w, r.h = math.max(MIN_SIZE, math.Round(r.w * kx)), math.max(MIN_SIZE, math.Round(r.h * ky))
	end
	for _, win in ipairs(doc.windows) do
		scale(win)
		if win.restore then scale(win.restore) end
		for _, tab in ipairs(win.tabs) do
			if tab.size then
				tab.size.w = math.max(MIN_SIZE, math.Round(tab.size.w * kx))
				tab.size.h = math.max(MIN_SIZE, math.Round(tab.size.h * ky))
			end
		end
		changed("geometry", win.id)
	end
	Layout.Refit()
end

hook.Add("OnScreenSizeChanged", "PinnedPanels.Layout", function(oldW, oldH)
	quietly(Layout.RescaleAll, oldW, oldH)
end)

-- The taskbar's settings change the usable area (E5).
local USABLE_SETTINGS = { taskbar = true, taskbarSide = true, taskbarSize = true, taskbarAutoHide = true }
hook.Add("PinnedPanelsSettingChanged", "PinnedPanels.Layout", function(key)
	if USABLE_SETTINGS[key] then quietly(Layout.Refit) end
end)
