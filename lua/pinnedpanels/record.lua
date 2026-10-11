-- Record mode (§33.9): the player starts recording, then opens a window the usual way. For at most
-- RECORD_TIME seconds, vgui.Create and vgui.CreateFromTable are wrapped through the timed override helper
-- (R14), and the call stack of each panel created without a parent is read (G62) for the nearest function
-- that opens things: a console command, a net message handler (the server opened it) or a hook.

local PP = PinnedPanels
PP.Record = PP.Record or {}
local Record = PP.Record
local Recipes, Layout = PP.Recipes, PP.Layout

local RECORD_TIMER, RECORD_TIME, RECORD_POLL = "PinnedPanels.Record", 30, 0.1
local STACK_DEPTH = 40
local MIN_WINDOW = 40

-- Every function that might open a window, looked up once when recording starts.
local function openers()
	local fns = {}
	for name, fn in pairs(concommand.GetTable()) do
		if isfunction(fn) then fns[fn] = { kind = "command", name = name } end
	end
	for name, fn in pairs(net.Receivers) do
		if isfunction(fn) then fns[fn] = fns[fn] or { kind = "net", name = name } end
	end
	for event, hooks in pairs(hook.GetTable()) do
		for _, fn in pairs(hooks) do
			if isfunction(fn) then fns[fn] = fns[fn] or { kind = "hook", name = event } end
		end
	end
	return fns
end

-- The nearest opener on the current stack. A command's argument string is its callback's fourth local,
-- read only while the deprecated debug.getlocal still exists (G62).
local function openerOnStack(fns)
	for level = 2, STACK_DEPTH do
		local info = debug.getinfo(level, "f")
		if not info then return nil end
		local hit = fns[info.func]
		if hit then
			if hit.kind == "command" and debug.getlocal then
				local _, args = debug.getlocal(level, 4)
				if isstring(args) and args ~= "" then return { kind = hit.kind, name = hit.name, args = args } end
			end
			return hit
		end
	end
end

-- The first recorded top-level panel that turned out to be a window (menus and tooltips are also created
-- without a parent), or nothing when time runs out.
local function poll(rec)
	for _, c in ipairs(rec.created) do
		local p = c.panel
		if IsValid(p) and p:IsVisible() and p:GetWide() >= MIN_WINDOW and p:GetTall() >= MIN_WINDOW and not Recipes.Refusal(p, p) then
			Record.Stop()
			return rec.done({ panel = p, via = c.via, bind = PP.Input.lastBind })
		end
	end
	if RealTime() >= rec.deadline then
		Record.Stop()
		rec.done(nil)
	end
end

function Record.Start(done)
	if Record.active then return false end
	local rec = { done = done, fns = openers(), created = {}, deadline = RealTime() + RECORD_TIME }
	Record.active = rec
	PP.Input.lastBind = nil
	-- Our wrappers pass every call through, and stay harmless if another addon wraps over them.
	local function seen(panel, parent)
		if Record.active ~= rec or parent ~= nil or not IsValid(panel) then return end
		rec.created[#rec.created + 1] = { panel = panel, via = openerOnStack(rec.fns) }
	end
	local create, fromTable = vgui.Create, vgui.CreateFromTable
	rec.restores = {
		PP.Util.BeginOverride(vgui, "Create", function(class, parent, name, ...)
			local panel = create(class, parent, name, ...)
			pcall(seen, panel, parent)
			return panel
		end),
		PP.Util.BeginOverride(vgui, "CreateFromTable", function(meta, parent, name, ...)
			local panel = fromTable(meta, parent, name, ...)
			pcall(seen, panel, parent)
			return panel
		end),
	}
	timer.Create(RECORD_TIMER, RECORD_POLL, 0, function() poll(rec) end)
	return true
end

-- Restores vgui on every path: found, timeout, cancel, reload and ShutDown (R14).
function Record.Stop()
	local rec = Record.active
	if not rec then return end
	Record.active = nil
	timer.Remove(RECORD_TIMER)
	for _, restore in ipairs(rec.restores) do
		if not restore() then print("[Pinned Panels] Another addon wrapped vgui while recording; our wrapper stays in place and only passes calls through.") end
	end
end

hook.Add("ShutDown", "PinnedPanels.Record", Record.Stop)

local function how(result)
	local v = result.via
	local text
	if not v then
		text = PP.L("record.by_unknown")
	elseif v.kind == "command" then
		text = PP.L("record.by_command", v.args and v.name .. " " .. v.args or v.name)
	elseif v.kind == "net" then
		text = PP.L("record.by_server", v.name)
	else
		text = PP.L("record.by_hook", v.name)
	end
	if result.bind then text = text .. "\n" .. PP.L("record.bind", result.bind) end
	return text
end

-- A recorded window: one already pinned learns how it opens; any other can be pinned with that recipe.
-- Opened by the server or a hook means there is no opener of ours to run, so it is watched for.
local function recorded(result)
	if not result then return notification.AddLegacy(PP.L("record.nothing"), NOTIFY_ERROR, 6) end
	local panel, v = result.panel, result.via
	-- No opener on the stack (a hook polling keys, say): the bind pressed just before is the next best.
	local recipe = v and v.kind == "command" and { kind = "command", command = v.name, args = v.args, confirmed = true }
		or (not v and PP.Openers.FromBind()) or { kind = "watch" }
	local cand = Recipes.Signature(panel)
	for _, rec in ipairs(Layout.Windows()) do
		for i, tab in ipairs(rec.tabs) do
			local strong = tab.adopt and select(2, Recipes.Match(tab.adopt.signature, cand))
			if strong then
				if recipe.kind == "watch" and not v then return notification.AddLegacy(PP.L("record.no_opener", Recipes.Title(tab.adopt)), NOTIFY_HINT, 8) end
				Layout.SetAdopt(rec.id, i, { recipe = recipe })
				return notification.AddLegacy(PP.L("record.updated", Recipes.Title(tab.adopt), Recipes.Describe({ recipe = recipe })), NOTIFY_GENERIC, 8)
			end
		end
	end
	local function take(mode)
		return function()
			if IsValid(panel) and not Recipes.Owner(panel) then Recipes.Take(panel, panel, mode, recipe) end
		end
	end
	Derma_Query(PP.L("record.found", Recipes.SigTitle(cand), how(result)), PP.L("record.title"),
		PP.L("picker.mode_embed"), take("embed"), PP.L("btn.cancel"), function() end)
end

-- Starts recording, or stops it when it is running.
function Record.Toggle()
	if Record.active then
		Record.Stop()
		return notification.AddLegacy(PP.L("record.stopped"), NOTIFY_GENERIC, 4)
	end
	notification.AddLegacy(PP.L("record.start", RECORD_TIME), NOTIFY_HINT, 8)
	Record.Start(recorded)
end

-- ── Always watching (Z3) ────────────────────────────────────
-- What Record mode finds out when asked, found out all the time, for the one kind of opener we can run
-- again: a console command. Nothing in the game says what opened a window, but while a Lua command runs
-- we know it is running, so a window made during it, or hidden before it and shown after, was opened
-- by it, arguments and all. That is read when a window is pinned (the picker suggests it) and when a
-- waiting pin's window comes back (a pin that only "comes back when its addon opens it" learns its
-- command), so the player never has to record anything.
--
-- The cost, since this runs for every panel made and every command run (measured in game, Z3): a panel
-- with a parent (nearly all of them) costs one extra function call and a comparison, too little to
-- measure; a command costs a look at the world panel's children before and after it, about 2 µs for each
-- of them (0.1 ms with 24 on screen), so that look is had at most ten times a second: an addon that
-- runs commands every frame pays some 20 µs for each, not that.
-- Windows the server opens, or that open a moment after their command (a timer, an answer from the
-- server), are not seen this way; the second kind is tried by time (Trace.Recent).

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
