-- Records → window controls (§16): creates, refreshes and removes PinnedPanelsWindows as the document
-- changes, rations tab builds to one per frame, and applies interactivity and idle opacity.

local PP = PinnedPanels
PP.Desktop = PP.Desktop or {}
local Desktop = PP.Desktop
local Layout, Sources, Input, Settings, Storage, Util = PP.Layout, PP.Sources, PP.Input, PP.Settings, PP.Storage, PP.Util

Desktop.panels = Desktop.panels or {}
-- Windows present at join while autoRestore is off: kept in the document, not shown until asked.
Desktop.held = Desktop.held or {}
Desktop.ready = Desktop.ready or false

local function hasAvailableTab(rec)
	for _, t in ipairs(rec.tabs) do
		if Sources.Get(t.src) then return true end
	end
	return false
end

-- A window gets a control once the catalogue is known, unless it is held, empty (a named group) or
-- only has unavailable tabs, which stay dormant in the document (E1, B1).
local function wanted(rec)
	return Desktop.ready and not Desktop.held[rec.id] and hasAvailableTab(rec)
end

local function create(rec)
	local win = vgui.Create("PinnedPanelsWindow")
	win:ParentToHUD() -- as v1; the Phase 0 spike decides whether this matters for the escape menu (G30, E27)
	win:MakePopup()
	win:SetKeyboardInputEnabled(false) -- G21: the mouse without blocking movement
	win:SetWindowId(rec.id)
	Desktop.panels[rec.id] = win
	return win
end

-- Visibility, mouse input and idle opacity, recomputed on changes, never per frame (§16.3, G27).
function Desktop.UpdateStates()
	local interactive = Input.Interactive()
	local idle = Settings.Get("idleOpacity") / 100
	for id, win in pairs(Desktop.panels) do
		local rec = Layout.Get(id)
		if IsValid(win) and rec then
			win:SetVisible(rec.state ~= "minimized")
			win:SetMouseInputEnabled(interactive)
			if not interactive then win:SetKeyboardInputEnabled(false) end
			local alpha = interactive and 1 or math.max(rec.opacity or idle, 0.05)
			win:SetAlpha(math.Round(alpha * 255))
		end
	end
end

function Desktop.Reconcile()
	local seen = {}
	for _, rec in ipairs(Layout.Windows()) do
		if wanted(rec) then
			seen[rec.id] = true
			local win = Desktop.panels[rec.id]
			if IsValid(win) then win:Refresh() else create(rec) end
		end
	end
	for id, win in pairs(Desktop.panels) do
		if not seen[id] then
			if IsValid(win) then win:Remove() end
			Desktop.panels[id] = nil
		end
	end
	Desktop.UpdateStates()
end

hook.Add("PinnedPanelsChanged", "PinnedPanels.Desktop", function(kind, id)
	if kind == "windows" or kind == "tabs" or not id then return Desktop.Reconcile() end
	local win = Desktop.panels[id]
	if IsValid(win) then win:Refresh() end
	if kind == "state" or kind == "style" then Desktop.UpdateStates() end
end)

hook.Add("PinnedPanelsInputChanged", "PinnedPanels.Desktop", Desktop.UpdateStates)

hook.Add("PinnedPanelsSettingChanged", "PinnedPanels.Desktop", function(key)
	if key == "idleOpacity" then Desktop.UpdateStates() end
end)

-- The first catalogue decides what "restore on join" means; later ones re-check dormant tabs (E1, E12).
hook.Add("PinnedPanelsCatalogChanged", "PinnedPanels.Desktop", function()
	if not Desktop.ready then
		Desktop.ready = true
		if not Settings.Get("autoRestore") then
			for _, rec in ipairs(Layout.Windows()) do Desktop.held[rec.id] = true end
		end
	end
	Desktop.Reconcile()
end)

-- Default titles follow the game language (L19, E11); the spawn menu rebuilds the hub itself (G11).
cvars.AddChangeCallback("gmod_language", function()
	Util.NextFrame(nil, function()
		for _, win in pairs(Desktop.panels) do
			if IsValid(win) then win:Refresh() end
		end
	end)
end, "PinnedPanels.Desktop")

-- ── Services for controls ───────────────────────────────────

-- One tab host may build per frame across all windows (§16.2).
local lastBuild = -1
function Desktop.ClaimBuild()
	local frame = FrameNumber()
	if frame == lastBuild then return false end
	lastBuild = frame
	return true
end

-- Records of the other windows on screen, for snapping.
function Desktop.SnapRects(exceptId)
	local rects = {}
	for id, win in pairs(Desktop.panels) do
		if id ~= exceptId and IsValid(win) and win:IsVisible() then rects[#rects + 1] = Layout.Get(id) end
	end
	return rects
end

-- Pins src (or brings back its window) and puts the window in front (E22).
function Desktop.PinSource(src)
	local id = Layout.Pin(src, Sources.DefaultSize(src))
	Desktop.held[id] = nil
	Util.NextFrame(nil, function()
		local win = Desktop.panels[id]
		if IsValid(win) then win:MoveToFront() end
	end)
	return id
end

-- Shows windows held back by autoRestore = off.
function Desktop.ShowHeld()
	Desktop.held = {}
	Desktop.Reconcile()
end

-- ── Lifecycle ───────────────────────────────────────────────

function Desktop.Teardown()
	for _, win in pairs(Desktop.panels) do
		if IsValid(win) then win:Remove() end
	end
	Desktop.panels = {}
end

-- Load the document; if the spawn menu already exists (a reload), read the catalogue now (E2).
hook.Add("PinnedPanelsLoaded", "PinnedPanels.Desktop", function()
	Layout.Load(Storage.Load())
	if IsValid(g_SpawnMenu) then Sources.Rebuild() end
end)
