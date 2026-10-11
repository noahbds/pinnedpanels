-- Trace (Z3): what opens a window, found out as it happens, for the one kind of opener we can run again:
-- a console command. Nothing in the game says what opened a window, but while a Lua command runs
-- we know it is running, so a window made during it, or hidden before it and shown after, was opened
-- by it, arguments and all. That is read when a window is pinned (the picker suggests it) and when a
-- waiting pin's window comes back (a pin that only "comes back when its addon opens it" learns its
-- command), so the player never has to say how a window opens. (There was a Record mode the player
-- started by hand, which also named the net message or hook behind a window: neither can be run
-- again, and it is gone.)
--
-- The cost, since this runs for every panel made and every command run (measured in game, Z3): a panel
-- with a parent (nearly all of them) costs one extra function call and a comparison, too little to
-- measure; a command costs a look at the world panel's children before and after it, about 2 µs for each
-- of them (0.1 ms with 24 on screen), so that look is had at most ten times a second: an addon that
-- runs commands every frame pays some 20 µs for each, not that.
-- Windows the server opens, or that open a moment after their command (a timer, an answer from the
-- server), are not seen this way; the second kind is tried by time (Trace.Recent).

local PP = PinnedPanels
local Recipes = PP.Recipes

PP.Trace = PP.Trace or {}
local Trace = PP.Trace

local TRACE_KEEP, TRACE_RECENT = 8, 2 -- commands remembered, and for how many seconds one can explain a window
local TRACE_LOOK = 0.1                -- seconds between two looks at what a command showed
Trace.lastLook = Trace.lastLook or 0
Trace.tagged = Trace.tagged or setmetatable({}, { __mode = "k" }) -- window -> the command that opened it
Trace.recent = Trace.recent or {}
Trace.installed = Trace.installed or {}
local tagged = Trace.tagged
local running -- the command being run now, while FrameNumber() is still its frame

-- A command that could be how a window opens: Lua's, not ours, not a held key's.
local function worth(name)
	return name:sub(1, 13) ~= "pinnedpanels_" and not name:find("^[%+%-]") and isfunction(concommand.GetTable()[name])
end

local function now()
	-- A command that threw never cleared `running`: it only counts in the frame it started in.
	if running and running.frame ~= FrameNumber() then running = nil end
	return running
end

local function visibleTops()
	local set = {}
	for _, p in ipairs(vgui.GetWorldPanel():GetChildren()) do
		if p:IsVisible() then set[p] = true end
	end
	return set
end

-- tbl[key] becomes make(what is there now). Loaded again, our own wrapper is replaced, not wrapped;
-- another addon's wrapper put over ours since is kept under the new one.
local function install(tbl, key, make)
	local slot, current = Trace.installed[key], tbl[key]
	if not isfunction(current) then return end
	local raw = (slot and current == slot.wrapper) and slot.raw or current
	local wrapper = make(raw)
	tbl[key] = wrapper
	Trace.installed[key] = { wrapper = wrapper, raw = raw }
end

local function created(raw)
	return function(class, parent, ...)
		local panel = raw(class, parent, ...)
		if parent == nil and running and panel and now() then tagged[panel] = running end
		return panel
	end
end
install(vgui, "Create", created)
install(vgui, "CreateFromTable", created)

install(concommand, "Run", function(raw)
	return function(ply, command, args, argStr, ...)
		local name = isstring(command) and command:lower() or nil
		if not name or not worth(name) then return raw(ply, command, args, argStr, ...) end
		local t = RealTime()
		-- From the list of arguments, each without the quotes it can come in ('"show"', seen in game).
		local text = ""
		if istable(args) then
			local words = {}
			for i, a in ipairs(args) do words[i] = tostring(a):gsub('^"(.*)"$', "%1") end
			text = string.Trim(table.concat(words, " "))
		end
		local entry = { name = name, args = text ~= "" and text or nil, at = t, frame = FrameNumber() }
		local before
		if t - Trace.lastLook >= TRACE_LOOK then
			Trace.lastLook = t
			before = visibleTops()
		end
		Trace.recent[#Trace.recent + 1] = entry
		if #Trace.recent > TRACE_KEEP then table.remove(Trace.recent, 1) end
		local outer = now()
		running = entry
		local a, b = raw(ply, command, args, argStr, ...)
		running = outer
		if before then
			for _, p in ipairs(vgui.GetWorldPanel():GetChildren()) do
				-- Also one tagged before: shown again another way, that is how it opens now.
				if not before[p] and p:IsVisible() then tagged[p] = entry end
			end
		end
		return a, b
	end
end)

local function recipeOf(entry)
	if not entry or PP.Openers.Risky(entry.name) or not worth(entry.name) then return nil end
	return { kind = "command", command = entry.name, args = entry.args, confirmed = true }
end

-- The command a window was seen being opened by, as a recipe, or nil.
function Trace.Of(panel)
	return recipeOf(tagged[panel])
end

-- For a window that appeared a moment after its command ended: the last command run in the past seconds
-- that is of the window's file or addon, as a recipe, or nil.
function Trace.Recent(sig)
	local t = RealTime()
	for i = #Trace.recent, 1, -1 do
		local entry = Trace.recent[i]
		if t - entry.at > TRACE_RECENT then return nil end
		local fn = concommand.GetTable()[entry.name]
		local from = isfunction(fn) and Recipes.FileOf(fn)
		if from and Recipes.SameMaker(sig, from) then return recipeOf(entry) end
	end
end
