-- ── Panel Actions: Auto-Arrange & Quick Slots ───────────────────────────────

-- ── Auto-Arrange (tile visible panels top-left, wrapping into rows) ──────────
function PinnedPanels.AutoArrange()
	local list = {}
	for id, pin in pairs(PinnedPanels.Pins) do
		if IsValid(pin.frame) and pin.frame:IsVisible() and not pin.locked then
			if pin.kind == "group" or not PinnedPanels.GetGroupForPanel(id) then
				list[#list + 1] = { id = id, pin = pin, frame = pin.frame, title = pin.title or "" }
			end
		end
	end
	if #list == 0 then return end
	table.sort(list, function(a, b) return a.title:lower() < b.title:lower() end)

	local margin = 8
	local ux, uy, uw, uh = PinnedPanels.GetUsableBounds()
	local x, y, rowH = ux + margin, uy + margin, 0

	for _, e in ipairs(list) do
		if e.pin.maximized then
			e.pin.maximized = false
			e.pin.restoreBounds = nil
		end
		local w, h = e.frame:GetSize()
		w = math.min(w, uw - margin * 2)
		h = math.min(h, uh - margin * 2)

		if x + w + margin > ux + uw and x > ux + margin then
			x = ux + margin
			y = y + rowH + margin
			rowH = 0
		end
		if y + h + margin > uy + uh then y = uy + margin end

		e.frame:SetSize(w, h)
		e.frame:SetPos(x, y)
		e.frame:MoveToFront()

		x = x + w + margin
		if h > rowH then rowH = h end
	end

	PinnedPanels.Save()
	hook.Run("PinnedPanels_StateChanged")
end

concommand.Add("pp_arrange", PinnedPanels.AutoArrange, nil, "Auto-arrange all visible pinned panels into a grid")
concommand.Add("pp_reopen", function()
	if PinnedPanels.ReopenLastClosed then PinnedPanels.ReopenLastClosed() end
end, nil, "Reopen the most recently unpinned panel")

-- ── Quick Slots (bind a key to toggle a specific panel) ──────────────────────
local function ToggleQuickPanel(id)
	local pin = PinnedPanels.Pins[id]
	if not pin or not IsValid(pin.frame) then return end

	if pin.minimized then
		PinnedPanels.RestoreFromTaskbar(id)
	elseif pin.frame:IsVisible() then
		local ts = PinnedPanels.Settings.taskbar
		if ts and ts.enabled ~= false then
			PinnedPanels.MinimizeToTaskbar(id)
		else
			pin.frame:SetVisible(false)
		end
	else
		pin.frame:SetVisible(true)
		pin.frame:MoveToFront()
		if PinnedPanels.UpdatePanelStates then PinnedPanels.UpdatePanelStates() end
	end
end

-- Assign (or clear, with KEY_NONE) a quick-slot key for a panel. A panel may
-- own at most one key, and a key at most one panel.
function PinnedPanels.SetQuickSlot(keycode, id)
	local S = PinnedPanels.Settings
	S.quickSlots = S.quickSlots or {}
	for k, v in pairs(S.quickSlots) do
		if v == id then S.quickSlots[k] = nil end
	end
	if keycode and keycode ~= KEY_NONE and id then
		S.quickSlots[tostring(keycode)] = id
	end
	PinnedPanels.SaveSettings()
end

function PinnedPanels.GetQuickSlotFor(id)
	for k, v in pairs(PinnedPanels.Settings.quickSlots or {}) do
		if v == id then return tonumber(k) end
	end
	return nil
end

local quickDown = {}

hook.Add("Think", "PinnedPanels_QuickSlots", function()
	local slots = PinnedPanels.Settings.quickSlots
	if not slots or not next(slots) then return end
	if IsValid(vgui.GetKeyboardFocus()) then return end

	for kStr, id in pairs(slots) do
		local code = tonumber(kStr)
		if code and code ~= KEY_NONE then
			local down = input.IsKeyDown(code)
			if down and not quickDown[code] then ToggleQuickPanel(id) end
			quickDown[code] = down
		end
	end
end)

hook.Add("PlayerBindPress", "PinnedPanels_QuickSlotsSuppress", function(_, _, _, code)
	if not code or IsValid(vgui.GetKeyboardFocus()) then return end
	local slots = PinnedPanels.Settings.quickSlots
	if slots and slots[tostring(code)] then return true end
end)

-- ── Peek (hold to reveal every panel) ────────────────────────────────────────
local peekCvar = CreateClientConVar("pp_key_peek", tostring(KEY_NONE), true, false,
	"PinnedPanels: hold to temporarily reveal all panels")
local peekKey = tonumber(peekCvar:GetString()) or KEY_NONE
cvars.AddChangeCallback("pp_key_peek", function(_, _, new)
	peekKey = tonumber(new) or KEY_NONE
end, "PinnedPanels_PeekKey")

function PinnedPanels.GetPeekKey() return peekKey end
function PinnedPanels.SetPeekKey(code)
	peekKey = code or KEY_NONE
	RunConsoleCommand("pp_key_peek", tostring(peekKey))
end

local peekState = nil

-- Grouped members are empty husk frames — their content lives inside the
-- group frame's tab sheet — so revealing them shows big blank boxes.
local function IsPeekable(id, pin)
	if not IsValid(pin.frame) then return false end
	if pin.kind ~= "group" and PinnedPanels.GetGroupForPanel(id) then return false end
	return true
end

local function StartPeek()
	peekState = {}
	PinnedPanels._peeking = true
	for id, pin in pairs(PinnedPanels.Pins) do
		if IsPeekable(id, pin) then
			peekState[id] = { visible = pin.frame:IsVisible(), minimized = pin.minimized }
			pin.frame:SetVisible(true)
			pin.frame:SetAlpha(255)
		end
	end
end

local function EndPeek()
	if not peekState then return end
	for id, st in pairs(peekState) do
		local pin = PinnedPanels.Pins[id]
		-- if the minimize state changed mid-peek (e.g. restored from the
		-- taskbar), the new state wins over the snapshot
		if pin and IsValid(pin.frame) and pin.minimized == st.minimized then
			pin.frame:SetVisible(st.visible)
		end
	end
	peekState = nil
	PinnedPanels._peeking = nil
	if PinnedPanels.UpdatePanelStates then PinnedPanels.UpdatePanelStates() end
end

hook.Add("Think", "PinnedPanels_Peek", function()
	if not peekKey or peekKey == KEY_NONE then
		if peekState then EndPeek() end
		return
	end
	local down = input.IsKeyDown(peekKey) and not IsValid(vgui.GetKeyboardFocus())
	if down and not peekState then
		StartPeek()
	elseif not down and peekState then
		EndPeek()
	end
end)

hook.Add("PlayerBindPress", "PinnedPanels_PeekSuppress", function(_, _, _, code)
	if code and code == peekKey and peekKey ~= KEY_NONE
		and not IsValid(vgui.GetKeyboardFocus()) then
		return true
	end
end)
