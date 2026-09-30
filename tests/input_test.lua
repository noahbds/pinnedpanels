local Input = PinnedPanels.Input

local function counter(id, key)
	local c = { press = 0, release = 0 }
	Input.SetKey(id, key, function() c.press = c.press + 1 end, function() c.release = c.release + 1 end)
	return c
end

local function tap(key)
	Stub.Key(key, true)
	Stub.Frame()
	Stub.Key(key, false)
	Stub.Frame()
end

local panel = { IsValid = function() return true end }

return {
	["a press fires once however long the key is held"] = function(t)
		local c = counter("x", KEY_A)
		Stub.Key(KEY_A, true)
		for _ = 1, 5 do Stub.Frame() end
		t.eq(c.press, 1)
		t.eq(c.release, 0)
		Stub.Key(KEY_A, false)
		Stub.Frame()
		t.eq(c.release, 1)
	end,

	["gates block hotkeys (E13, E35, G8, G19)"] = function(t)
		local c = counter("x", KEY_A)
		local gates = {
			function(on) hook.Run(on and "StartChat" or "FinishChat") end,
			function(on) Stub.Set("console", on) end,
			function(on) Stub.Set("gameUI", on) end,
			function(on) Stub.Set("focus", not on) end,
			function(on) Stub.Set("trapping", on) end,
			function(on) Stub.Set("kbFocus", on and panel or nil) end,
		}
		for i, gate in ipairs(gates) do
			gate(true)
			tap(KEY_A)
			gate(false)
			t.eq(c.press, 0, "gate " .. i)
		end
		tap(KEY_A)
		t.eq(c.press, 1)
	end,

	["a gate ends a held key and ignores it until released (E32, E35)"] = function(t)
		local c = counter("peek", KEY_A)
		Stub.Key(KEY_A, true)
		Stub.Frame()
		t.eq(c.press, 1)
		Stub.Set("focus", false)
		Stub.Frame()
		t.eq(c.release, 1, "alt-tab ends the hold")
		Stub.Set("focus", true)
		Stub.Frame()
		t.eq(c.press, 1, "still held after the gate: no new press")
		Stub.Key(KEY_A, false)
		Stub.Frame()
		t.eq(c.release, 1, "no second release")
		tap(KEY_A)
		t.eq(c.press, 2)
	end,

	["rebinding and unbinding"] = function(t)
		local c = counter("x", KEY_A)
		counter("x", KEY_B)
		tap(KEY_A)
		t.eq(c.press, 0)
		Input.SetKey("x", KEY_NONE)
		t.eq(hook.Run("PlayerBindPress", nil, "+jump", true, KEY_B), nil)
	end,

	["game binds of our keys are suppressed only when we'd act (R7)"] = function(t)
		counter("x", KEY_A)
		t.eq(hook.Run("PlayerBindPress", nil, "+jump", true, KEY_A), true)
		t.eq(hook.Run("PlayerBindPress", nil, "+jump", true, KEY_B), nil)
		t.eq(hook.Run("PlayerBindPress", nil, "-jump", false, KEY_A), nil)
		hook.Run("StartChat")
		t.eq(hook.Run("PlayerBindPress", nil, "+jump", true, KEY_A), nil)
	end,

	["ALT is tracked and announced"] = function(t)
		local changes = 0
		hook.Add("PinnedPanelsInputChanged", "test", function() changes = changes + 1 end)
		Stub.Key(KEY_LALT, true)
		Stub.Frame()
		Stub.Frame()
		t.eq(Input.AltHeld(), true)
		t.eq(changes, 1)
		Stub.Set("focus", false)
		Stub.Frame()
		t.eq(Input.AltHeld(), false, "ALT doesn't stick after alt-tab (E35)")
	end,

	["the cursor stays while any reason wants it (E31)"] = function(t)
		Input.Cursor("cursor", true)
		Input.Cursor("palette", true)
		t.eq(Stub.Get("clicker"), true)
		Input.Cursor("cursor", false)
		t.eq(Stub.Get("clicker"), true)
		Input.Cursor("palette", false)
		t.eq(Stub.Get("clicker"), false)
		t.eq(Stub.Get("clickerCalls"), 2)
	end,

	["releasing a reason we never took leaves someone else's cursor alone"] = function(t)
		Input.Cursor("palette", false)
		t.eq(Stub.Get("clickerCalls"), 0)
	end,

	["cursor mode and the spawn menu make windows interactive (F10, E16)"] = function(t)
		local modes = {}
		hook.Add("PinnedPanelsCursorMode", "test", function(on) modes[#modes + 1] = on end)
		t.eq(Input.Interactive(), false)
		Input.SetCursorMode(true)
		Input.SetCursorMode(true)
		t.eq(Input.Interactive(), true)
		t.eq(#modes, 1)
		Input.SetCursorMode(false)
		hook.Run("OnSpawnMenuOpen")
		t.eq(Input.Interactive(), true)
		hook.Run("OnSpawnMenuClose")
		t.eq(Input.Interactive(), false)
	end,

	["a window takes the keyboard only while its text entry has focus (R8, B32)"] = function(t)
		local keyboard
		local win = { ClassName = "PinnedPanelsWindow", IsValid = function() return true end,
			SetKeyboardInputEnabled = function(_, on) keyboard = on end }
		local entry = { IsValid = function() return true end, GetParent = function() return win end }
		local other = { IsValid = function() return true end, GetParent = function() return nil end }
		hook.Run("OnTextEntryGetFocus", entry)
		t.eq(keyboard, true)
		hook.Run("OnTextEntryLoseFocus", entry)
		t.eq(keyboard, false)
		keyboard = nil
		hook.Run("OnTextEntryGetFocus", other)
		t.eq(keyboard, nil, "entries outside our windows are left alone")
	end,
}
