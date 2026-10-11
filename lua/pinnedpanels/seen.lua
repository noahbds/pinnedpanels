-- Seen (X61): everything the player ever pinned, of any kind (a tool, a content page, a widget, another
-- addon's window or a part of one, a set of quick controls), kept after it is unpinned so it can be
-- pinned again as it was: its size and place, its crop, its name, and for another addon's window how it
-- is recognized and how it comes back. The hub's Seen page lists it. Kept in its own file, apart from the
-- layout: importing or resetting a layout doesn't forget what was seen.

local PP = PinnedPanels
PP.Seen = PP.Seen or {}
local Seen = PP.Seen
local Layout, Storage = PP.Layout, PP.Storage

local DIR, FILE = "pinnedpanels", "pinnedpanels/seen.json"
local MAX_ENTRIES = 300
local SAVE_TIMER, SAVE_DELAY = "PinnedPanels.Seen", 2
local KINDS = { tool = true, creation = true, postprocess = true, active = true, quick = true, adopt = true }

Seen.entries = Seen.entries or {} -- key -> entry
Seen.current = Seen.current or {} -- key -> the id of the window that has it now
local dirty = false

-- What a tab is, whatever window or layout it is in. A tool is its source; another addon's panel is what
-- it is recognized by (its "adopt:<n>" is only a number in one layout); quick controls are their convars.
local function keyOf(tab)
	local kind = tab.src:match("^(%a+):")
	if kind == "adopt" then
		local s = tab.adopt.signature
		local path = {}
		for i, step in ipairs(s.path or {}) do path[i] = (step.class or "?") .. "#" .. (step.n or step.i or 0) end
		return table.concat({ "adopt", tab.adopt.mode, s.desktop or "", s.src or "", s.class or "", s.title or "", table.concat(path, "/") }, "|")
	elseif kind == "quick" then
		local vars = {}
		for i, c in ipairs(tab.controls or {}) do vars[i] = tostring(c.convar) end
		table.sort(vars)
		return "quick|" .. table.concat(vars, ",")
	end
	return tab.src
end

local function entryOf(key, win, tab)
	local kind = tab.src:match("^(%a+):")
	return {
		key = key, kind = kind, src = kind ~= "adopt" and kind ~= "quick" and tab.src or nil,
		title = Layout.TabTitle(tab), custom = tab.title,
		addon = tab.adopt and tab.adopt.signature.addon or nil,
		x = win.x, y = win.y, w = win.w, h = win.h,
		crop = tab.crop and table.Copy(tab.crop) or nil,
		adopt = tab.adopt and table.Copy(tab.adopt) or nil,
		controls = tab.controls and table.Copy(tab.controls) or nil,
	}
end

local function save()
	local list = Seen.List()
	while #list > MAX_ENTRIES do table.remove(list) end
	file.CreateDir(DIR)
	file.Write(FILE, util.TableToJSON({ version = 1, entries = list }, true))
	dirty = false
end

local function touch()
	dirty = true
	timer.Create(SAVE_TIMER, SAVE_DELAY, 1, save)
end

local SAME = { "title", "custom", "x", "y", "w", "h" }

-- Looks at what is pinned now. Something that wasn't pinned a moment ago is new, or pinned once more;
-- something still pinned keeps its entry up to date, so what is remembered is how it was last.
function Seen.Scan()
	local now, listChanged = {}, false
	for _, win in ipairs(Layout.Windows()) do
		for _, tab in ipairs(win.tabs) do
			local key = keyOf(tab)
			now[key] = win.id
			local old, e = Seen.entries[key], entryOf(key, win, tab)
			if not old and Seen.scanned and Seen.current[key] then
				-- Forgotten while it was pinned: it stays off the list until it is pinned again.
				e = nil
			elseif not old then
				e.first, e.last, e.count = os.time(), os.time(), 1
				listChanged = true
				touch()
			else
				e.first, e.last, e.count = old.first, old.last, old.count
				-- Not on the first look of a session: what was already pinned at join wasn't pinned again.
				if Seen.scanned and not Seen.current[key] then
					e.last, e.count = os.time(), (old.count or 1) + 1
					listChanged = true
					touch()
				else
					for _, f in ipairs(SAME) do
						if e[f] ~= old[f] then
							touch()
							break
						end
					end
				end
			end
			Seen.entries[key] = e
		end
	end
	Seen.current, Seen.scanned = now, true
	if listChanged then hook.Run("PinnedPanelsSeenChanged") end
end

-- Most recently pinned first.
function Seen.List()
	local list = {}
	for _, e in pairs(Seen.entries) do list[#list + 1] = e end
	table.sort(list, function(a, b)
		if a.last ~= b.last then return (a.last or 0) > (b.last or 0) end
		return a.key < b.key
	end)
	return list
end

-- The id of the window that has an entry now, or nil.
function Seen.PinnedAt(e)
	local id = Seen.current[e.key]
	return id and Layout.Get(id) and id or nil
end

-- Whether it can be pinned now: a tool or a page whose addon isn't loaded can't.
function Seen.Available(e)
	if e.kind == "adopt" or e.kind == "quick" then return true end
	return PP.Sources.Get(e.src) ~= nil
end

-- Pins an entry again as it was, or brings its window up if it is pinned. Another addon's window is
-- pinned waiting: taken at once if it is open, opened if we know how, else when its addon opens it.
-- Returns the window id.
function Seen.Pin(e)
	local at = Seen.PinnedAt(e)
	if at then
		PP.Desktop.RestoreAndFront(at)
		return at
	end
	if e.kind == "adopt" then
		local id = Layout.PinAdopted(table.Copy(e.adopt), e.x or 200, e.y or 200, e.w or 400, e.h or 300)
		if e.crop then Layout.SetCrop(id, 1, table.Copy(e.crop)) end
		if e.custom then Layout.Rename(id, 1, e.custom) end
		PP.Desktop.Show(id)
		PP.Recipes.Wake()
		local rec = Layout.Get(id)
		local tab = rec and rec.tabs[1]
		if tab and PP.Recipes.CanOpen(tab.adopt) then PP.Recipes.Open(rec, tab) end
		PP.Desktop.Front(id)
		return id
	elseif e.kind == "quick" then
		local id
		for _, c in ipairs(e.controls or {}) do
			id = Layout.AddControl(id, id and 1 or nil, table.Copy(c)) or id
		end
		if id then
			Layout.SetGeometry(id, e.x or 200, e.y or 200, e.w or 280, e.h or 200)
			PP.Desktop.Show(id)
			PP.Desktop.Front(id)
		end
		return id
	end
	if not Seen.Available(e) then
		notification.AddLegacy(PP.L("seen.unavailable"), NOTIFY_HINT, 6)
		return nil
	end
	local id = PP.Desktop.PinSource(e.src)
	if id and e.w and e.h then Layout.SetGeometry(id, e.x or 200, e.y or 200, e.w, e.h) end
	return id
end

-- Takes an entry off the list. Something pinned now comes back on it the next time it is pinned, or
-- at the next join if it is still pinned then.
function Seen.Forget(key)
	if not Seen.entries[key] then return end
	Seen.entries[key] = nil
	touch()
	hook.Run("PinnedPanelsSeenChanged")
end

function Seen.Clear()
	Seen.entries = {}
	touch()
	hook.Run("PinnedPanelsSeenChanged")
end

-- ── The file ────────────────────────────────────────────────

local text, int = Storage.Text, Storage.Int

-- One entry read from the file, checked like a layout's tab is (another addon's panel and quick controls
-- go through the layout's own checks), or nil.
local function read(raw)
	if not istable(raw) then return nil end
	local key, kind = text(raw.key, 2048), raw.kind
	if not key or not KINDS[kind] then return nil end
	local e = {
		key = key, kind = kind, title = text(raw.title, 128) or "?", custom = text(raw.custom, 128), addon = text(raw.addon, 128),
		x = int(raw.x, -16384, 16384), y = int(raw.y, -16384, 16384), w = int(raw.w, 20, 16384), h = int(raw.h, 20, 16384),
		first = int(raw.first, 0, 2 ^ 40), last = int(raw.last, 0, 2 ^ 40) or 0, count = int(raw.count, 1, 2 ^ 30) or 1,
	}
	if istable(raw.crop) then
		local c = raw.crop
		local l, t, r, b = int(c.l, 0, 16384), int(c.t, 0, 16384), int(c.r, 0, 16384), int(c.b, 0, 16384)
		if l and t and r and b and l + t + r + b > 0 then e.crop = { l = l, t = t, r = r, b = b } end
	end
	if kind == "adopt" then
		e.adopt = Storage.SanitizeAdopt(raw.adopt)
		if not e.adopt then return nil end
	elseif kind == "quick" then
		e.controls = Storage.SanitizeControls(raw.controls)
		if not e.controls then return nil end
	else
		e.src = text(raw.src, 512)
		if not e.src or e.src:match("^(%a+):") ~= kind then return nil end
	end
	return e
end

function Seen.Load()
	local raw = util.JSONToTable(file.Read(FILE, "DATA") or "", true)
	local entries = {}
	for _, r in ipairs(istable(raw) and istable(raw.entries) and raw.entries or {}) do
		local e = read(r)
		if e then entries[e.key] = e end
	end
	Seen.entries = entries
end

-- Once, not again on a reload of this file: the list in memory is the newer one then.
if not Seen.loaded then
	Seen.loaded = true
	Seen.Load()
end

-- After every frame's changes to the layout, and once the first layout is there.
hook.Add("PinnedPanelsFlushed", "PinnedPanels.Seen", Seen.Scan)
hook.Add("PinnedPanelsCatalogChanged", "PinnedPanels.Seen", Seen.Scan)
hook.Add("ShutDown", "PinnedPanels.Seen", function()
	if dirty then save() end
end)
