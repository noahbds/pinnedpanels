-- The one input dispatcher (§17): the addon's only Think hook (others join it through Input.EachFrame)
-- and key polling with repeat, cursor
-- ownership, bind and movement suppression, and keyboard input for windows while one of their text
-- entries has focus (G20).

local PP = PinnedPanels
PP.Input = PP.Input or {}
local Input = PP.Input

-- Cursor state survives pinnedpanels_reload so the screen clicker never gets out of step.
Input.reasons = Input.reasons or {}
Input.clickerOn = Input.clickerOn or false
Input.cursorMode = Input.cursorMode or false
-- Other addons' windows under management take the keyboard like ours (§33.5); keyed by panel.
Input.keyboardOwners = Input.keyboardOwners or setmetatable({}, { __mode = "k" })

local binds = {}   -- id -> { key, press, release, repeating }
local watched = {} -- key -> true
local held = {}    -- key -> true when its press fired, false when it was already down during a gate
local nextRepeat = {} -- key -> RealTime of its next repeat, while held with a repeating binding
local chatOpen, spawnOpen, contextOpen, altHeld = false, false, false, false
local frames = {}  -- id -> function called every frame (Input.EachFrame)

-- Held keys repeat after a delay, on real time so pause and host_timescale don't matter (G5, B28).
local REPEAT_DELAY, REPEAT_INTERVAL = 0.35, 0.055

local function inputChanged()
	hook.Run("PinnedPanelsInputChanged")
end

-- Hotkeys stay quiet while the player is typing or looking at another UI (E13, E35, G8, G19).
local function gated()
	return chatOpen or gui.IsConsoleVisible() or gui.IsGameUIVisible() or not system.HasFocus()
		or input.IsKeyTrapping() or IsValid(vgui.GetKeyboardFocus())
end

-- pressed: true (press), false (release) or "repeat" (only repeating bindings). Handlers are collected
-- first because they may rebind keys (keyboard navigation changes its keys with its state).
local function fire(key, pressed)
	local fns = {}
	for _, b in pairs(binds) do
		if b.key == key and (pressed ~= "repeat" or b.repeating) then
			local fn = pressed and b.press or b.release
			if fn then fns[#fns + 1] = fn end
		end
	end
	for _, fn in ipairs(fns) do fn() end
end

local function repeats(key)
	for _, b in pairs(binds) do
		if b.key == key and b.repeating then return true end
	end
	return false
end

local function think()
	local alt = system.HasFocus() and (input.IsKeyDown(KEY_LALT) or input.IsKeyDown(KEY_RALT))
	if alt ~= altHeld then
		altHeld = alt
		inputChanged()
	end

	-- Other addons turn the screen clicker off as well (D31): ours comes back while a reason wants it.
	if Input.clickerOn and not vgui.CursorVisible() then gui.EnableScreenClicker(true) end

	local gate = gated()
	local now = RealTime()
	for key in pairs(watched) do
		local isDown = input.IsKeyDown(key)
		local was = held[key]
		if gate then
			-- End what was started, and ignore keys held through the gate until they are released.
			if was then fire(key, false) end
			if isDown then held[key] = false else held[key] = nil end
			nextRepeat[key] = nil
		elseif isDown and was == nil then
			held[key] = true
			if repeats(key) then nextRepeat[key] = now + REPEAT_DELAY end
			fire(key, true)
		elseif not isDown and was ~= nil then
			held[key] = nil
			nextRepeat[key] = nil
			if was then fire(key, false) end
		elseif isDown and was and nextRepeat[key] and now >= nextRepeat[key] then
			nextRepeat[key] = now + REPEAT_INTERVAL
			fire(key, "repeat")
		end
	end
	-- Keys no longer bound are forgotten once released (until then they still count as held).
	for key in pairs(held) do
		if not watched[key] and not input.IsKeyDown(key) then held[key] = nil end
	end
	for _, fn in pairs(frames) do fn() end
end

hook.Add("Think", "PinnedPanels.Input", think)

-- Runs fn every frame from the addon's one Think hook, until called again with nil. For work that has to
-- hold from one frame to the next; it must stay as cheap as a few getters.
function Input.EachFrame(id, fn)
	frames[id] = fn
end

-- ── Key bindings ────────────────────────────────────────────

-- Calls press/release when key goes down/up, and press again while held if repeating. KEY_NONE or nil
-- removes the binding. A key already held when it gets a binding waits for its next press, and a held
-- key stays held through rebinding (navigation rebinds its keys from inside their own handlers), so it
-- doesn't press again.
function Input.SetKey(id, key, press, release, repeating)
	if key == KEY_NONE then key = nil end
	binds[id] = key and { key = key, press = press, release = release, repeating = repeating } or nil
	watched = {}
	for _, b in pairs(binds) do watched[b.key] = true end
	for k in pairs(nextRepeat) do
		if not watched[k] then nextRepeat[k] = nil end
	end
end

function Input.ShiftHeld()
	return input.IsKeyDown(KEY_LSHIFT) or input.IsKeyDown(KEY_RSHIFT)
end

-- The game bind of a key we act on doesn't run too (R7). F1-F12 never reach this hook (G6). The last bind
-- pressed is kept for Record mode, which reports how a window was opened (§33.9).
hook.Add("PlayerBindPress", "PinnedPanels.Input", function(_, bind, pressed, code)
	if pressed then Input.lastBind, Input.lastBindTime = bind, RealTime() end
	if pressed and code and watched[code] and not gated() then return true end
end)

-- Movement binds aren't stopped by PlayerBindPress (G6), so keys we are acting on (held since their press
-- fired) also have their bind's movement and buttons cleared (R7).
local BIND_BUTTONS = {
	["+attack"] = IN_ATTACK, ["+attack2"] = IN_ATTACK2, ["+jump"] = IN_JUMP, ["+duck"] = IN_DUCK,
	["+forward"] = IN_FORWARD, ["+back"] = IN_BACK, ["+use"] = IN_USE, ["+moveleft"] = IN_MOVELEFT,
	["+moveright"] = IN_MOVERIGHT, ["+left"] = IN_LEFT, ["+right"] = IN_RIGHT, ["+reload"] = IN_RELOAD,
	["+speed"] = IN_SPEED, ["+walk"] = IN_WALK,
}

hook.Add("CreateMove", "PinnedPanels.Input", function(cmd)
	if not next(held) then return end
	local buttons, changed = cmd:GetButtons(), false
	for key, pressed in pairs(held) do
		local bind = pressed and input.LookupKeyBinding(key)
		if bind then
			local button = BIND_BUTTONS[bind]
			if button then
				buttons = bit.band(buttons, bit.bnot(button))
				changed = true
			end
			if bind == "+forward" or bind == "+back" then cmd:SetForwardMove(0) end
			if bind == "+moveleft" or bind == "+moveright" then cmd:SetSideMove(0) end
		end
	end
	if changed then cmd:SetButtons(buttons) end
end)

-- ── Cursor ──────────────────────────────────────────────────

-- The only caller of gui.EnableScreenClicker. The cursor shows while any reason wants it and is only
-- turned off by us if we turned it on (E31); its position comes back like the spawn menu's (D16, G9).
function Input.Cursor(reason, on)
	Input.reasons[reason] = on or nil
	local want = next(Input.reasons) ~= nil
	if want == Input.clickerOn then return end
	Input.clickerOn = want
	if want then
		gui.EnableScreenClicker(true)
		RestoreCursorPosition()
	else
		RememberCursorPosition()
		gui.EnableScreenClicker(false)
	end
end

function Input.SetCursorMode(on)
	on = on == true
	if Input.cursorMode == on then return end
	Input.cursorMode = on
	Input.Cursor("cursor", on)
	hook.Run("PinnedPanelsCursorMode", on)
	inputChanged()
end

-- Windows take the mouse in cursor mode and while the spawn menu or the C menu is open (F10, E16, FF5).
function Input.Interactive()
	return Input.cursorMode or spawnOpen or contextOpen
end

-- Windows set to show with the C menu appear only while it is open (FF5).
function Input.ContextOpen()
	return contextOpen
end

function Input.AltHeld()
	return altHeld
end

hook.Add("OnSpawnMenuOpen", "PinnedPanels.Input", function()
	spawnOpen = true
	inputChanged()
end)

hook.Add("OnSpawnMenuClose", "PinnedPanels.Input", function()
	spawnOpen = false
	inputChanged()
end)

-- The C menu shows its own cursor, like the spawn menu, so it needs no cursor reason of ours.
hook.Add("OnContextMenuOpen", "PinnedPanels.Input", function()
	contextOpen = true
	inputChanged()
end)

hook.Add("OnContextMenuClose", "PinnedPanels.Input", function()
	contextOpen = false
	inputChanged()
end)

hook.Add("StartChat", "PinnedPanels.Input", function() chatOpen = true end)
hook.Add("FinishChat", "PinnedPanels.Input", function() chatOpen = false end)

-- ── Text focus ──────────────────────────────────────────────
-- Our windows and dialogs (marked ppTakesKeyboard) and managed windows take the keyboard only while a
-- text entry inside them has focus, never on hover (R8, B32, E14).

local function windowOf(p)
	while IsValid(p) do
		if p.ppTakesKeyboard or Input.keyboardOwners[p] then return p end
		p = p:GetParent()
	end
end

hook.Add("OnTextEntryGetFocus", "PinnedPanels.Input", function(p)
	local win = windowOf(p)
	if win then win:SetKeyboardInputEnabled(true) end
end)

hook.Add("OnTextEntryLoseFocus", "PinnedPanels.Input", function(p)
	local win = windowOf(p)
	if win then win:SetKeyboardInputEnabled(false) end
end)
