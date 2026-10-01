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
