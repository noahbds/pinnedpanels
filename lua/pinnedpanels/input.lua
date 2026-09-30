-- The one input dispatcher (§17): the addon's only Think hook and key polling, cursor ownership,
-- bind suppression, and keyboard input for windows while one of their text entries has focus (G20).

local PP = PinnedPanels
PP.Input = PP.Input or {}
local Input = PP.Input

-- Cursor state survives pinnedpanels_reload so the screen clicker never gets out of step.
Input.reasons = Input.reasons or {}
Input.clickerOn = Input.clickerOn or false
Input.cursorMode = Input.cursorMode or false

local binds = {}   -- id -> { key, press, release }
local watched = {} -- key -> true
local held = {}    -- key -> true when its press fired, false when it was already down during a gate
local chatOpen, spawnOpen, altHeld = false, false, false

local function inputChanged()
	hook.Run("PinnedPanelsInputChanged")
end

-- Hotkeys stay quiet while the player is typing or looking at another UI (E13, E35, G8, G19).
local function gated()
	return chatOpen or gui.IsConsoleVisible() or gui.IsGameUIVisible() or not system.HasFocus()
		or input.IsKeyTrapping() or IsValid(vgui.GetKeyboardFocus())
end

local function fire(key, pressed)
	for _, b in pairs(binds) do
		if b.key == key then
			local fn = pressed and b.press or b.release
			if fn then fn() end
		end
	end
end

local function think()
	local alt = system.HasFocus() and (input.IsKeyDown(KEY_LALT) or input.IsKeyDown(KEY_RALT))
	if alt ~= altHeld then
		altHeld = alt
		inputChanged()
	end

	local gate = gated()
	for key in pairs(watched) do
		local isDown = input.IsKeyDown(key)
		local was = held[key]
		if gate then
			-- End what was started, and ignore keys held through the gate until they are released.
			if was then fire(key, false) end
			if isDown then held[key] = false else held[key] = nil end
		elseif isDown and was == nil then
			held[key] = true
			fire(key, true)
		elseif not isDown and was ~= nil then
			held[key] = nil
			if was then fire(key, false) end
		end
	end
end

hook.Add("Think", "PinnedPanels.Input", think)

-- ── Key bindings ────────────────────────────────────────────

-- Calls press/release when key goes down/up. KEY_NONE or nil removes the binding.
function Input.SetKey(id, key, press, release)
	if key == KEY_NONE then key = nil end
	binds[id] = key and { key = key, press = press, release = release } or nil
	watched = {}
	for _, b in pairs(binds) do watched[b.key] = true end
	for k in pairs(held) do
		if not watched[k] then held[k] = nil end
	end
end

-- The game bind of a key we act on doesn't run too (R7). F1-F12 never reach this hook (G6).
hook.Add("PlayerBindPress", "PinnedPanels.Input", function(_, _, pressed, code)
	if pressed and code and watched[code] and not gated() then return true end
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

-- Windows take the mouse in cursor mode and while the spawn menu is open (F10, E16).
function Input.Interactive()
	return Input.cursorMode or spawnOpen
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

hook.Add("StartChat", "PinnedPanels.Input", function() chatOpen = true end)
hook.Add("FinishChat", "PinnedPanels.Input", function() chatOpen = false end)

-- ── Text focus ──────────────────────────────────────────────
-- Our windows and dialogs (marked ppTakesKeyboard) take the keyboard only while a text entry inside them
-- has focus, never on hover (R8, B32, E14).

local function windowOf(p)
	while IsValid(p) do
		if p.ppTakesKeyboard then return p end
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
