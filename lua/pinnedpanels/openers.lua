-- How another addon's window is opened (§33.9): ranking the Lua console commands that could open it,
-- learning one from the key bind the player pressed, and C-menu desktop widgets (G47), which we open the way
-- the C menu's own icon does so they are embedded like any window.

local PP = PinnedPanels
PP.Openers = PP.Openers or {}
local Openers = PP.Openers
local Layout = PP.Layout

local MAX_COMMANDS = 10
local MAX_UPVALUES, MAX_FIELDS = 30, 64
local AUTO_SCORE, AUTO_MARGIN = 7, 2
local BIND_WINDOW = 2 -- seconds between pressing a bind and its window appearing

-- Words that make a command look like an opener, and words that mean it does something else. A risky
-- command is listed for the player to choose but never suggested or learned on its own.
local OPEN_WORDS = { menu = 3, open = 3, gui = 2, panel = 2, window = 2, editor = 2, config = 2, settings = 2, options = 2, browser = 2, show = 1, toggle = 1 }
local RISKY = {
	remove = true, delete = true, reset = true, clear = true, kill = true, spawn = true, undo = true, save = true, load = true,
	reload = true, ban = true, kick = true, give = true, buy = true, sell = true, drop = true, admin = true, exec = true,
	run = true, close = true, hide = true, dump = true, debug = true, cleanup = true, restart = true, disconnect = true,
}
local STOP_WORDS = { the = true, ["and"] = true, ["for"] = true, with = true, your = true }
-- Folders shared by many addons, which say nothing about which addon a file belongs to.
local SHARED_ROOTS = { ["lua/autorun/"] = true, ["lua/vgui/"] = true, ["lua/includes/"] = true, ["lua/entities/"] = true,
	["lua/weapons/"] = true, ["lua/effects/"] = true, ["lua/matproxy/"] = true, ["lua/postprocess/"] = true }

local function fileOf(fn)
	local info = debug.getinfo(fn, "S")
	return info and info.short_src
end

local function rootOf(src)
	local root = src:match("^(addons/[^/]+/)") or src:match("^(gamemodes/[^/]+/)") or src:match("^(lua/[^/]+/)")
	return root and not SHARED_ROOTS[root] and root or nil
end

-- Lower-case words of a name: "wire_expression2_editor" or "Expression2EditorFrame" → expression2, editor, …
local function words(text)
	local out = {}
	if not isstring(text) then return out end
	text = text:gsub("^#", ""):gsub("([%l%d])(%u)", "%1_%2"):lower()
	for w in text:gmatch("%w+") do
		if #w >= 3 and not STOP_WORDS[w] then out[#out + 1] = w end
	end
	return out
end

local function set(list)
	local out = {}
	for _, v in ipairs(list) do out[v] = true end
	return out
end

local function ours(name)
	return name:sub(1, 13) == "pinnedpanels_"
end

-- How much a word of a command's name says "this opens something". Opener words count inside longer
-- ones too: "openmenu", "showcase".
local function openScore(word)
	local score = 0
	for open, points in pairs(OPEN_WORDS) do
		if word:find(open, 1, true) then score = score + points end
	end
	return score
end

function Openers.Risky(name)
	for _, w in ipairs(words(name)) do
		if RISKY[w] then return true end
	end
	return false
end

-- A command whose own variables hold a function from the window's file (or a table of them) leads to it.
-- Upvalues are read with the deprecated debug.getupvalue while it exists (G62); without it this adds nothing.
local function upvalueEvidence(fn, src)
	if not debug.getupvalue then return 0 end
	for i = 1, MAX_UPVALUES do
		local ok, name, v = pcall(debug.getupvalue, fn, i)
		if not ok or name == nil then break end
		if isfunction(v) and fileOf(v) == src then return 6 end
		if istable(v) then
			local n = 0
			for _, f in pairs(v) do
				n = n + 1
				if n > MAX_FIELDS then break end
				if isfunction(f) and fileOf(f) == src then return 4 end
			end
		end
	end
	return 0
end

-- The Lua commands that could open a window with this signature, best first:
-- { { name, score, risky, sameFile, tied } }. Only commands related to the window count: defined in its
-- file, in its addon, or holding its functions. Their names then score for opener words and for the
-- window's title and class words. tied: something ties the command to this window and not just to its
-- addon, which is what a suggestion needs (D26).
function Openers.Commands(sig)
	local out = {}
	local src = sig.src
	if not src then return out end
	local root = rootOf(src)
	local titleWords, classWords = set(words(sig.title)), set(words(sig.class))
	for name, fn in pairs(concommand.GetTable()) do
		if isfunction(fn) and not ours(name) and not name:find("^[%+%-]") then
			local from = fileOf(fn)
			local score = 0
			if from == src then
				score = 6
			elseif root and rootOf(from) == root then
				score = 3
			elseif sig.addon and file.Exists(from, sig.addon) then
				score = 3
			end
			local evidence = upvalueEvidence(fn, src)
			score = score + evidence
			if score > 0 then
				local named = false
				for _, w in ipairs(words(name)) do
					score = score + openScore(w) + (titleWords[w] and 2 or 0) + (classWords[w] and 1 or 0)
					named = named or titleWords[w] or classWords[w] or false
				end
				out[#out + 1] = { name = name, score = score, risky = Openers.Risky(name), sameFile = from == src, tied = evidence > 0 or named }
			end
		end
	end
	table.sort(out, function(a, b)
		if a.score ~= b.score then return a.score > b.score end
		return a.name < b.name
	end)
	while #out > MAX_COMMANDS do table.remove(out) end
	return out
end

-- The command to suggest, if one stands out: the only safe command in the window's own file, or the best
-- one tied to the window, scoring at least AUTO_SCORE and clearly ahead of the next. Being in the same
-- addon is never enough (an addon's "open the sound browser" isn't how its editor opens), and risky
-- commands never qualify (D26).
function Openers.Best(commands)
	local inFile, only = 0, nil
	local first, second
	for _, c in ipairs(commands) do
		if not c.risky then
			if c.sameFile then inFile, only = inFile + 1, c end
			if c.tied then
				if not first then first = c elseif not second then second = c end
			end
		end
	end
	if inFile == 1 then return only.name end
	if not first or first.score < AUTO_SCORE then return nil end
	if not second or first.score - second.score >= AUTO_MARGIN then return first.name end
end

-- The command behind the bind the player pressed just now, if it is a Lua command that isn't ours or risky.
-- F-keys never reach PlayerBindPress (G6), so those binds can't be learned.
function Openers.FromBind()
	local Input = PP.Input
	local bind = Input.lastBind
	if not bind or RealTime() - (Input.lastBindTime or 0) > BIND_WINDOW then return nil end
	local command, args = bind:match("^%s*([^%s;]+)%s*([^;]*)")
	if not command then return nil end
	command, args = command:lower(), string.Trim(args)
	if command:find("^[%+%-]") or ours(command) or Openers.Risky(command) or not isfunction(concommand.GetTable()[command]) then return nil end
	return { kind = "command", command = command, args = args ~= "" and args or nil, confirmed = true }
end

-- ── C-menu desktop widgets (G47) ────────────────────────────

-- The widget a window is, by its title (the C menu titles each window after its list entry).
function Openers.DesktopId(panel)
	if not isfunction(panel.GetTitle) then return nil end
	local ok, title = pcall(panel.GetTitle, panel) -- G70
	if not ok or not isstring(title) or title == "" then return nil end
	for _, e in ipairs(PP.Sources.natives) do
		if e.kind == "desktop" and e.text == title then return e.name end
	end
end

-- Opens a widget as the C menu's icon does: a DFrame in the C menu, sized and titled from its entry and
-- filled by its init, under ProtectedCall (R13). The icon argument is a stand-in holding the window.
function Openers.OpenDesktop(id)
	local w = list.Get("DesktopWindows")[id]
	if not (istable(w) and isfunction(w.init)) then return nil end
	local frame = vgui.Create("DFrame", IsValid(g_ContextMenu) and g_ContextMenu or nil)
	frame:SetSize(tonumber(w.width) or 400, tonumber(w.height) or 400)
	frame:SetTitle(isstring(w.title) and w.title or id)
	frame:Center()
	local ok = ProtectedCall(function() w.init({ Window = frame }, frame) end)
	if not ok and IsValid(frame) then frame:Remove() end
	return IsValid(frame) and frame or nil
end

function Openers.CanOpenDesktop(id)
	local w = list.Get("DesktopWindows")[id]
	return istable(w) and isfunction(w.init)
end

-- The window and tab that already hold a widget, if it is pinned.
function Openers.FindDesktop(id)
	for _, rec in ipairs(Layout.Windows()) do
		for i, tab in ipairs(rec.tabs) do
			if tab.adopt and tab.adopt.recipe.kind == "desktop" and tab.adopt.recipe.id == id then return rec, i end
		end
	end
end

-- Pins a widget from the hub or the palette: its window again if it is pinned, else a new one embedded.
-- Returns the window id.
function Openers.PinDesktop(id)
	local rec, i = Openers.FindDesktop(id)
	if rec then
		if not PP.Recipes.IsLive(rec, rec.tabs[i]) then PP.Recipes.Open(rec, rec.tabs[i]) end
		PP.Desktop.RestoreAndFront(rec.id)
		Layout.Activate(rec.id, i)
		return rec.id
	end
	local frame = Openers.OpenDesktop(id)
	if not frame then return nil end
	return PP.Recipes.Take(frame, frame, "embed", { kind = "desktop", id = id })
end
