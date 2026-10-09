-- The layout file (§13.2, §13.4): debounced atomic writes with a backup, quarantine of unreadable files,
-- Sanitize for files and imports alike (R2), and export/import strings (R1). The only file.* user.

local PP = PinnedPanels
PP.Storage = PP.Storage or {}
local Storage, Util = PP.Storage, PP.Util

local DIR = "pinnedpanels"
local MAIN = "pinnedpanels/layout.json"
local BAK = "pinnedpanels/layout_bak.json"
local TMP = "pinnedpanels/layout_tmp.json"
local TIMER = "PinnedPanels.Storage"
local DEBOUNCE = 0.5

local VERSION = 2
local PREFIX = "PP2:"
local MAX_IMPORT = 64 * 1024
local MAX_DECOMPRESSED = 256 * 1024
-- Bounds for what a saved or shared layout may hold. Windows: well above what anyone pins by hand (a
-- player with 62 was two away from the old limit of 64, past which windows were dropped on loading).
local MAX_WINDOWS, MAX_TABS = 512, 16
local MAX_TITLE, MAX_SRC = 64, 128
local MAX_COORD = 32768
local KINDS = { tool = true, creation = true, postprocess = true, adopt = true, active = true, quick = true }
local DFRAME_STRIP = 29 -- DFrame's top dock padding, cropped away when its contents are embedded (§33.6)
local STATES = { normal = true, minimized = true, maximized = true, rolled = true }
local ADOPT_MODES = { manage = true, embed = true, part = true }
local MAX_PATH = 16
local CONTROL_KINDS = { slider = true, check = true, combo = true }
local MAX_CONTROLS, MAX_CHOICES = 32, 32
local MAX_VALUE = 1e9

Storage.VERSION = VERSION
Storage.readOnly = false
local dirty = false

local PREFIX_COLOR = Color(255, 120, 120)

local function notify(key, ...)
	local text = PP.L(key, ...)
	notification.AddLegacy(text, NOTIFY_ERROR, 10)
	MsgC(PREFIX_COLOR, "[Pinned Panels] ", color_white, text, "\n")
end

-- ── Sanitize ────────────────────────────────────────────────

local function int(v, lo, hi)
	v = tonumber(v)
	if not Util.Finite(v) then return nil end
	return math.Clamp(math.Round(v), lo, hi)
end

-- Truncating by bytes can split a UTF-8 character; drop the broken tail.
local function text(v, max)
	if not isstring(v) or v == "" then return nil end
	if #v > max then v = v:sub(1, max):gsub("[\192-\255][\128-\191]*$", "") end
	return v
end

local function rectFields(t, minSize)
	if not istable(t) then return nil end
	local w, h = int(t.w, minSize, MAX_COORD), int(t.h, minSize, MAX_COORD)
	if not (w and h) then return nil end
	return int(t.x, -MAX_COORD, MAX_COORD), int(t.y, -MAX_COORD, MAX_COORD), w, h
end

-- An adopted panel's record (§33.10). A recipe that can't be used safely becomes "watch"; "session" is
-- never saved, so it never loads.
local function sanitizeRecipe(r)
	local kind = istable(r) and r.kind
	if kind == "class" then
		local class = text(r.class, MAX_TITLE)
		if class then return { kind = "class", class = class } end
	elseif kind == "desktop" then
		local id = text(r.id, MAX_TITLE)
		if id then return { kind = "desktop", id = id } end
	elseif kind == "command" then
		local command = text(r.command, MAX_TITLE)
		if command and command:match("^[%w_%.%-+]+$") then
			local args = text(r.args, MAX_SRC)
			if args and args:find("[%c]") then args = nil end
			return { kind = "command", command = command, args = args, confirmed = r.confirmed == true }
		end
	end
	return { kind = "watch" }
end

local function sanitizeAdopt(a)
	if not istable(a) or not ADOPT_MODES[a.mode] or not istable(a.signature) then return nil end
	local s = a.signature
	local sig = {
		src = text(s.src, MAX_SRC), src2 = text(s.src2, MAX_SRC), addon = text(s.addon, MAX_TITLE), class = text(s.class, MAX_TITLE),
		base = text(s.base, MAX_TITLE), title = text(s.title, MAX_TITLE),
		w = int(s.w, 0, MAX_COORD), h = int(s.h, 0, MAX_COORD), hud = s.hud == true, popup = s.popup == true,
		desktop = text(s.desktop, MAX_TITLE),
	}
	if not (sig.w and sig.h) then sig.w, sig.h = nil, nil end
	if a.mode == "part" then
		if not istable(s.path) or #s.path == 0 or #s.path > MAX_PATH then return nil end
		sig.path = {}
		for i, step in ipairs(s.path) do
			local index = istable(step) and int(step.i, 1, 4096)
			if not index then return nil end
			sig.path[i] = { i = index, class = text(step.class, MAX_TITLE) }
		end
	end
	local recipe = sanitizeRecipe(a.recipe)
	-- Reopening at join (D41) is on unless turned off; autoFails counts joins it didn't come back on.
	local autoOpen
	if a.autoOpen == false then autoOpen = false end
	return { mode = a.mode, signature = sig, recipe = recipe, needsKeyboard = a.needsKeyboard == true, noGeometry = a.noGeometry == true,
		autoOpen = autoOpen, autoFails = int(a.autoFails, 1, 9) }
end

local function number(v)
	v = tonumber(v)
	if not Util.Finite(v) then return nil end
	return math.Clamp(v, -MAX_VALUE, MAX_VALUE)
end

-- A quick control (FF2). Its convar must look like a convar name; whether it exists is checked when built.
local function sanitizeControl(c)
	if not istable(c) or not CONTROL_KINDS[c.kind] then return nil end
	local convar = text(c.convar, MAX_TITLE)
	if not convar or not convar:match("^[%w_%.%-]+$") then return nil end
	local out = { kind = c.kind, convar = convar, label = text(c.label, MAX_TITLE) or convar }
	if c.kind == "slider" then
		out.min, out.max, out.decimals = number(c.min), number(c.max), int(c.decimals, 0, 6) or 0
		if not (out.min and out.max) then return nil end
	elseif c.kind == "combo" then
		out.choices = {}
		for i, choice in ipairs(istable(c.choices) and c.choices or {}) do
			if i > MAX_CHOICES then break end
			local label = istable(choice) and text(choice.text, MAX_TITLE)
			if label then out.choices[#out.choices + 1] = { text = label, data = text(choice.data, MAX_SRC) } end
		end
	end
	return out
end

local function sanitizeControls(list)
	local out = {}
	for _, c in ipairs(istable(list) and list or {}) do
		if #out >= MAX_CONTROLS then break end
		out[#out + 1] = sanitizeControl(c)
	end
	return #out > 0 and out or nil
end

-- C-menu widgets used to be built in our own tab ("desktop:<id>"); now they are opened as the C menu does
-- and embedded, so an old tab becomes an embedded one that opens its widget again.
local function fromDesktop(t, id)
	return {
		src = "adopt:desktop." .. id, title = t.title, size = t.size,
		crop = istable(t.crop) and t.crop or { l = 0, t = DFRAME_STRIP, r = 0, b = 0 },
		adopt = { mode = "embed", signature = { desktop = id }, recipe = { kind = "desktop", id = id } },
	}
end

local function sanitizeTab(t, seen, summary)
	if not istable(t) then return nil end
	local widget = isstring(t.src) and t.src:match("^desktop:(.+)$")
	if widget then t = fromDesktop(t, widget) end
	local src = text(t.src, MAX_SRC)
	local kind = src and src:match("^(%a+):.")
	local adopt = kind == "adopt" and sanitizeAdopt(t.adopt)
	local controls = kind == "quick" and sanitizeControls(t.controls)
	if not kind or not KINDS[kind] or seen[src] or (kind == "adopt" and not adopt) or (kind == "quick" and not controls) then
		summary.dropped = summary.dropped + 1
		return nil
	end
	seen[src] = true
	local tab = { src = src, title = text(t.title, MAX_TITLE), adopt = adopt or nil, controls = controls or nil }
	if istable(t.size) then
		local w, h = int(t.size.w, 20, MAX_COORD), int(t.size.h, 20, MAX_COORD)
		if w and h then tab.size = { w = w, h = h } end
	end
	if istable(t.crop) then
		local c = t.crop
		local l, top, r, b = int(c.l, 0, MAX_COORD), int(c.t, 0, MAX_COORD), int(c.r, 0, MAX_COORD), int(c.b, 0, MAX_COORD)
		if l and top and r and b and l + top + r + b > 0 then tab.crop = { l = l, t = top, r = r, b = b } end
	end
	return tab
end

local function sanitizeWindow(w, seen, summary)
	if not istable(w) then return nil end
	local tabs = {}
	if istable(w.tabs) then
		for i, t in ipairs(w.tabs) do
			if i > MAX_TABS then
				summary.dropped = summary.dropped + 1
			else
				tabs[#tabs + 1] = sanitizeTab(t, seen, summary)
			end
		end
	end
	-- A managed window is exactly one managed tab (§33.10); a managed tab anywhere else is dropped.
	local managed = #tabs == 1 and tabs[1].adopt and tabs[1].adopt.mode == "manage"
	if not managed then
		for i = #tabs, 1, -1 do
			if tabs[i].adopt and tabs[i].adopt.mode == "manage" then
				table.remove(tabs, i)
				summary.dropped = summary.dropped + 1
			end
		end
	end
	local title = not managed and text(w.title, MAX_TITLE) or nil
	-- A window without tabs is only kept as a named group (§13.1).
	if #tabs == 0 and not title then return nil end

	local x, y, width, height = rectFields(w, 20)
	local win = {
		id = isstring(w.id) and w.id:match("^w%d+$") and w.id or nil,
		kind = managed and "managed" or nil,
		tabs = tabs,
		active = int(w.active, 1, math.max(#tabs, 1)) or 1,
		x = x or 120, y = y or 120, w = width or 280, h = height or 400,
		state = STATES[w.state] and w.state or "normal",
		title = title,
		accent = Util.ArrayToColor(w.accent),
		locked = w.locked == true,
		filterBar = w.filterBar == true,
		quickKey = int(w.quickKey, 1, 511),
		showWith = w.showWith == "contextmenu" and "contextmenu" or nil,
		colors = {},
	}
	local opacity = tonumber(w.opacity)
	if Util.Finite(opacity) then win.opacity = math.Clamp(opacity, 0, 1) end
	if istable(w.colors) then
		win.colors.bg = Util.ArrayToColor(w.colors.bg)
		win.colors.header = Util.ArrayToColor(w.colors.header)
		win.colors.text = Util.ArrayToColor(w.colors.text)
	end
	if win.state == "maximized" and not managed then
		local rx, ry, rw, rh = rectFields(w.restore, 20)
		if rx and ry then win.restore = { x = rx, y = ry, w = rw, h = rh } end
	end
	return win
end

-- Returns a clean document and { windows, tabs, dropped }. Never fails: junk becomes an empty document.
function Storage.Sanitize(raw)
	local summary = { windows = 0, tabs = 0, dropped = 0 }
	local doc = { v = VERSION, windows = {}, nextId = 1 }
	if not istable(raw) then return doc, summary end

	if istable(raw.screen) then
		local w, h = int(raw.screen.w, 320, MAX_COORD), int(raw.screen.h, 200, MAX_COORD)
		if w and h then doc.screen = { w = w, h = h } end
	end

	local seenSrc, seenId, maxId = {}, {}, 0
	if istable(raw.windows) then
		for _, w in ipairs(raw.windows) do
			if #doc.windows >= MAX_WINDOWS then
				summary.dropped = summary.dropped + 1
			else
				local win = sanitizeWindow(w, seenSrc, summary)
				if win then
					if win.id and not seenId[win.id] then
						seenId[win.id] = true
						maxId = math.max(maxId, tonumber(win.id:sub(2)))
					else
						win.id = nil
					end
					doc.windows[#doc.windows + 1] = win
					summary.windows = summary.windows + 1
					summary.tabs = summary.tabs + #win.tabs
				else
					summary.dropped = summary.dropped + 1
				end
			end
		end
	end

	-- Ids are only trusted when unique; everything else gets a fresh one.
	for _, win in ipairs(doc.windows) do
		if not win.id then
			maxId = maxId + 1
			win.id = "w" .. maxId
		end
	end
	doc.nextId = math.max(maxId + 1, int(raw.nextId, 1, 1e9) or 1)
	return doc, summary
end

-- ── Encode ──────────────────────────────────────────────────

local function colorOrNil(c) return c and Util.ColorToArray(c) or nil end

-- A JSON-safe copy of the document: colours become arrays, and adopted panels pinned for this session only
-- are left out (§33.9); nothing else changes.
function Storage.Encode(doc)
	local out = { v = VERSION, screen = doc.screen, nextId = doc.nextId, windows = {} }
	for _, w in ipairs(doc.windows) do
		local tabs = {}
		for _, t in ipairs(w.tabs) do
			if not (t.adopt and t.adopt.recipe.kind == "session") then
				tabs[#tabs + 1] = { src = t.src, title = t.title, size = t.size, crop = t.crop, adopt = t.adopt, controls = t.controls }
			end
		end
		if #tabs > 0 or w.title then
			out.windows[#out.windows + 1] = {
				id = w.id, kind = w.kind, tabs = tabs, active = math.min(w.active, math.max(#tabs, 1)),
				x = w.x, y = w.y, w = w.w, h = w.h, state = w.state, restore = w.restore,
				title = w.title, accent = colorOrNil(w.accent),
				locked = w.locked, filterBar = w.filterBar,
				opacity = w.opacity, quickKey = w.quickKey, showWith = w.showWith,
				colors = { bg = colorOrNil(w.colors.bg), header = colorOrNil(w.colors.header), text = colorOrNil(w.colors.text) },
			}
		end
	end
	return out
end

-- ── Files ───────────────────────────────────────────────────

local function readDoc(path)
	if not file.Exists(path, "DATA") then return nil, "missing" end
	local raw = util.JSONToTable(file.Read(path, "DATA") or "", true)
	if not istable(raw) or not istable(raw.windows) then return nil, "corrupt" end
	if (tonumber(raw.v) or 0) > VERSION then
		Storage.readOnly = true
		notify("storage.newer")
	end
	return (Storage.Sanitize(raw))
end

-- Moves an unreadable layout aside so nothing ever overwrites it (E6). If that fails, stop writing.
local function quarantine(path)
	local target = "pinnedpanels/layout_corrupt_" .. os.time() .. ".json"
	if file.Rename(path, target) then return target end
	Storage.readOnly = true
end

-- The saved document, or nil for a fresh start. Falls back to the backup when the main file is
-- damaged, or missing because a write was interrupted between its two renames.
function Storage.Load()
	Storage.readOnly = false
	local doc, err = readDoc(MAIN)
	if doc then return doc end
	if err == "missing" then return (readDoc(BAK)) end

	local moved = quarantine(MAIN)
	local bak = readDoc(BAK)
	if not moved then
		notify("storage.stuck")
	elseif bak then
		notify("storage.recovered", moved)
	else
		notify("storage.quarantined", moved)
	end
	return bak
end

-- Write the temp file, keep the current file as the backup, then rename the temp file into place (B2).
function Storage.Flush()
	timer.Remove(TIMER)
	if not dirty or Storage.readOnly then return end
	dirty = false

	local json = util.TableToJSON(Storage.Encode(PP.Layout.Document()), true)
	file.CreateDir(DIR)
	file.Write(TMP, json)
	if file.Size(TMP, "DATA") ~= #json then
		notify("storage.write_failed")
		return
	end
	if file.Exists(MAIN, "DATA") then
		file.Delete(BAK)
		file.Rename(MAIN, BAK)
	end
	if not file.Rename(TMP, MAIN) then
		file.Write(MAIN, json)
		file.Delete(TMP)
	end
end

-- Coalesces writes: the file is written once changes stop for DEBOUNCE seconds (R9, B7).
function Storage.MarkDirty()
	dirty = true
	timer.Create(TIMER, DEBOUNCE, 1, Storage.Flush)
end

hook.Add("ShutDown", "PinnedPanels.Storage", Storage.Flush)

-- ── Export / import ─────────────────────────────────────────

function Storage.Export(doc)
	return PREFIX .. util.Base64Encode(util.Compress(util.TableToJSON(Storage.Encode(doc))), true)
end

-- Parses a shared string without touching anything (R1, R3). Returns doc, summary or nil, reason key.
function Storage.Import(s)
	if not isstring(s) then return nil, "import.empty" end
	s = string.Trim(s)
	if s == "" then return nil, "import.empty" end
	if #s > MAX_IMPORT then return nil, "import.too_big" end
	if s:sub(1, #PREFIX) ~= PREFIX then return nil, "import.not_v2" end

	local packed = util.Base64Decode(s:sub(#PREFIX + 1))
	if not packed or packed == "" then return nil, "import.decode" end
	local json = util.Decompress(packed, MAX_DECOMPRESSED)
	if not json or json == "" then return nil, "import.corrupt" end
	local raw = util.JSONToTable(json)
	if not istable(raw) or not istable(raw.windows) then return nil, "import.invalid" end

	local doc, summary = Storage.Sanitize(raw)
	if #doc.windows == 0 then return nil, "import.invalid" end
	-- A shared layout never runs a command by itself: each one waits for the player to allow it (R16).
	-- Nor does it choose a panel class to create: those wait for their addon to open them.
	for _, w in ipairs(doc.windows) do
		for _, t in ipairs(w.tabs) do
			local kind = t.adopt and t.adopt.recipe.kind
			if kind == "command" then
				t.adopt.recipe.confirmed = false
			elseif kind == "class" then
				t.adopt.recipe = { kind = "watch" }
			end
		end
	end
	return doc, summary
end
