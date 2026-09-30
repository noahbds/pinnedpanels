-- Keyboard navigation (§19, F25): a state machine over pinned windows, the taskbar, a window's controls,
-- value adjustment and menus (L10). Its keys go through Input only while navigation is on, so they are
-- taken, and their game binds blocked, only then (D8, R7). The focused window is Desktop.focused.
--
--   off ─► windows ◄──► taskbar          windows ── enter key ──► content ── Enter on adjustable ──► adjust
--              ▲  ◄── Backspace / Up at the top ──┘   └─ Shift+Enter ─► menu (a real DMenu, G17)

local PP = PinnedPanels
PP.Nav = PP.Nav or {}
local Nav = PP.Nav
local Layout, Desktop, Input, Settings, Util = PP.Layout, PP.Desktop, PP.Input, PP.Settings, PP.Util

local SCAN_DEPTH, MIN_SIZE, MIN_VISIBLE, SCAN_TTL = 20, 4, 8, 0.25
local EPSILON, GAP_BAND, PERP_WEIGHT = 2, 4, 4
local OPAQUE_FOR, TASKBAR_IDLE = 2, 5
local MENU_PROBES = 10

Nav.state = "off"
Nav.memory = Nav.memory or {} -- window id → last focused element (session)
Nav.recent = false

-- ── Ranking (pure) ──────────────────────────────────────────

-- The best rect to move to from `from` in dir ("left", "right", "up", "down"), as v1 (L14): candidates
-- beyond EPSILON in that direction; ones overlapping on the other axis win, by edge gap (within a GAP_BAND
-- tie) then distance across; up/down fall back to the nearest by distance plus PERP_WEIGHT × across.
-- rects are { x, y, w, h }; returns an index or nil.
function Nav.Rank(rects, from, dir)
	local horizontal = dir == "left" or dir == "right"
	local fcx, fcy = from.x + from.w / 2, from.y + from.h / 2
	local bestGap, bestPerp, bestOverlap = math.huge, math.huge, nil
	local bestScore, bestAny = math.huge, nil
	for i, r in ipairs(rects) do
		local dx, dy = r.x + r.w / 2 - fcx, r.y + r.h / 2 - fcy
		local ahead = (dir == "left" and dx < -EPSILON) or (dir == "right" and dx > EPSILON)
			or (dir == "up" and dy < -EPSILON) or (dir == "down" and dy > EPSILON)
		if ahead then
			local overlap, gap, perp
			if horizontal then
				overlap = r.y < from.y + from.h and from.y < r.y + r.h
				gap = dir == "left" and from.x - (r.x + r.w) or r.x - (from.x + from.w)
				perp = math.abs(dy)
			else
				overlap = r.x < from.x + from.w and from.x < r.x + r.w
				gap = dir == "up" and from.y - (r.y + r.h) or r.y - (from.y + from.h)
				perp = math.abs(dx)
			end
			gap = math.max(gap, 0)
			if overlap then
				if gap < bestGap - GAP_BAND or (gap < bestGap + GAP_BAND and perp < bestPerp) then
					bestGap, bestPerp, bestOverlap = gap, perp, i
				end
			else
				local score = (horizontal and math.abs(dx) or math.abs(dy)) + perp * PERP_WEIGHT
				if score < bestScore then bestScore, bestAny = score, i end
			end
		end
	end
	return bestOverlap or (not horizontal and bestAny or nil)
end

-- ── Where navigation can go ─────────────────────────────────

local function focusedWindow()
	local win = Desktop.panels[Desktop.focused or ""]
	return IsValid(win) and win:IsVisible() and win or nil
end

-- Visible windows by title, as v1.
function Nav.Windows()
	local list = {}
	for id, win in pairs(Desktop.panels) do
		local rec = Layout.Get(id)
		if IsValid(win) and win:IsVisible() and rec then list[#list + 1] = { id = id, title = Layout.Title(rec):lower() } end
	end
	table.sort(list, function(a, b)
		if a.title ~= b.title then return a.title < b.title end
		return a.id < b.id
	end)
	return list
end

local function taskbarEntries()
	local bar = Desktop.taskbar
	return IsValid(bar) and bar.entries or {}
end

local function enabled()
	if not (Input.cursorMode or Settings.Get("navEverywhere")) then return false end
	return #Nav.Windows() > 0 or #taskbarEntries() > 0
end

-- ── Scanning a window's controls (§19.2) ────────────────────

-- The panel a rectangle must show through: the tab's clip panel, so cropped-away controls are skipped (L15).
local function clipOf(p, root)
	while IsValid(p) and p ~= root do
		if p.ClassName == "PinnedPanelsClip" then return p end
		p = p:GetParent()
	end
end

local function visibleEnough(el, root)
	local w, h = el:GetSize()
	if w <= MIN_SIZE or h <= MIN_SIZE then return false end
	local clip = clipOf(el:GetParent(), root)
	if not clip then return true end
	local ex, ey = el:LocalToScreen(0, 0)
	local cx, cy = clip:LocalToScreen(0, 0)
	local cw, ch = clip:GetSize()
	return math.min(ex + w, cx + cw) - math.max(ex, cx) >= MIN_VISIBLE and math.min(ey + h, cy + ch) - math.max(ey, cy) >= MIN_VISIBLE
end

local function collect(p, depth, out)
	if depth > SCAN_DEPTH or not p:IsVisible() then return 0 end
	local kind = Nav.Classify(p)
	if kind == "skip" then return 0 end
	if kind == "leaf" then
		out[#out + 1] = p
		return 1
	end
	local found = 0
	for _, c in ipairs(p:GetChildren()) do found = found + collect(c, depth + 1, out) end
	if kind == "custom" and found == 0 then
		out[#out + 1] = p
		return 1
	end
	return found
end

local cache = { root = nil, at = -math.huge, list = {} }

-- The navigable controls under root, rescanned at most SCAN_TTL apart or when root changes.
function Nav.Elements()
	local root = Nav.root
	if not IsValid(root) then return {} end
	if cache.root ~= root or RealTime() - cache.at > SCAN_TTL then
		local all, list = {}, {}
		collect(root, 0, all)
		for _, el in ipairs(all) do
			if visibleEnough(el, root) then list[#list + 1] = el end
		end
		cache.root, cache.at, cache.list = root, RealTime(), list
	end
	return cache.list
end

local function rectOf(el)
	local x, y = el:LocalToScreen(0, 0)
	local w, h = el:GetSize()
	return { x = x, y = y, w = w, h = h }
end

local function topmost(list)
	local best, bx, by
	for _, el in ipairs(list) do
		local x, y = el:LocalToScreen(0, 0)
		if not best or y < by - 2 or (math.abs(y - by) <= 2 and x < bx) then best, bx, by = el, x, y end
	end
	return best
end

local function indexOf(list, el)
	for i, e in ipairs(list) do
		if e == el then return i end
	end
end

-- Scroll panels up the chain bring the element into view if it's outside them (G24).
local function scrollIntoView(el)
	local p = el:GetParent()
	while IsValid(p) do
		if isfunction(p.ScrollToChild) then
			local _, ey = el:LocalToScreen(0, 0)
			local _, py = p:LocalToScreen(0, 0)
			if ey < py or ey + el:GetTall() > py + p:GetTall() then p:ScrollToChild(el) end
		end
		p = p:GetParent()
	end
end

-- ── State ───────────────────────────────────────────────────

local bindKeys

-- The hint under the focused window (or the taskbar's tooltip), worked out on changes, never while painting.
local function updateHint()
	if Nav.state == "taskbar" then
		local e = taskbarEntries()[Nav.taskIndex or 1]
		Nav.hint = (e and e.title or "") .. "   ·   " .. PP.L("tb.enter_restore")
		surface.SetFont(PP.Theme.FONT_TASKBAR)
	else
		local key = "nav.hint_panel"
		if Nav.state == "adjust" and IsValid(Nav.element) then key = Nav.HintFor(Nav.element) or key end
		Nav.hint = PP.L(key)
		surface.SetFont("DermaDefault")
	end
	Nav.hintW, Nav.hintH = surface.GetTextSize(Nav.hint)
end

local function go(state)
	Nav.state = state
	bindKeys()
	updateHint()
	Desktop.UpdateStates()
	if IsValid(Desktop.taskbar) then Desktop.taskbar:Wake() end
end

-- The focused window stays opaque for OPAQUE_FOR seconds after a nav key (L11).
local function touch()
	if not Nav.recent then
		Nav.recent = true
		Desktop.UpdateStates()
	end
	timer.Create("PinnedPanels.NavRecent", OPAQUE_FOR, 1, function()
		Nav.recent = false
		Desktop.UpdateStates()
	end)
end

function Nav.Opaque(id)
	return Nav.recent and Nav.state ~= "off" and Desktop.focused == id
end

function Nav.FocusWindow(id)
	Desktop.Front(id)
	go("windows")
end

function Nav.FocusTaskbar(dir)
	local entries = taskbarEntries()
	if #entries == 0 then return end
	Nav.taskIndex = dir < 0 and #entries or 1
	go("taskbar")
	timer.Create("PinnedPanels.NavTaskbarIdle", TASKBAR_IDLE, 1, function()
		if Nav.state == "taskbar" and not Input.Interactive() then Nav.Refresh(true) end
	end)
end

local function setElement(el)
	Nav.element = el
	if IsValid(el) then scrollIntoView(el) end
	updateHint()
end

-- Enters the controls of root (the focused window's tab, or a popup) at the remembered or topmost one.
local function enterRoot(root, memoryKey)
	Nav.root, Nav.memoryKey = root, memoryKey
	local list = Nav.Elements()
	local remembered = memoryKey and Nav.memory[memoryKey]
	setElement(indexOf(list, remembered) and remembered or topmost(list))
	go("content")
end

function Nav.EnterContent()
	local win = focusedWindow()
	local host = win and win:ShownHost()
	if host and host.built then enterRoot(host, win.id) end
end

-- A dialog opened while navigating becomes the zone until it closes or Backspace leaves it.
function Nav.EnterPopup(panel)
	if Nav.state == "off" then return end
	panel.PaintOver = Nav.PaintPopup
	enterRoot(panel, nil)
end

local function leaveContent()
	if Nav.memoryKey and IsValid(Nav.element) then Nav.memory[Nav.memoryKey] = Nav.element end
	Nav.root, Nav.element = nil, nil
	go("windows")
end

-- Keeps the state consistent with what exists: windows can close, minimize or be unpinned under us.
-- leaveTaskbar forces the taskbar idle timeout.
function Nav.Refresh(leaveTaskbar)
	if not enabled() then
		if Nav.state == "menu" then CloseDermaMenus() end
		Nav.root, Nav.element, Nav.menus = nil, nil, nil
		if Nav.state ~= "off" then go("off") end
		return
	end
	local s = Nav.state
	if s == "menu" and not (Nav.menus and IsValid(Nav.menus[1]) and Nav.menus[1]:IsVisible()) then
		Nav.menus = nil
		s = Nav.menuReturn or "windows"
		Nav.state = s
	end
	if (s == "content" or s == "adjust") and not IsValid(Nav.root) then
		Nav.root, Nav.element = nil, nil
		s = "windows"
	end
	if s == "taskbar" and (leaveTaskbar or #taskbarEntries() == 0) then s = "windows" end
	if s == "off" then s = "windows" end
	if s == "windows" and not focusedWindow() then
		local first = Nav.Windows()[1]
		if first then
			Desktop.SetFocused(first.id)
		elseif #taskbarEntries() > 0 then
			return Nav.FocusTaskbar(1)
		end
	end
	if s == "taskbar" then Nav.taskIndex = math.Clamp(Nav.taskIndex or 1, 1, #taskbarEntries()) end
	go(s)
end

-- ── Windows and taskbar ─────────────────────────────────────

-- Moves through visible windows, then the taskbar (if it has entries), and around.
function Nav.Cycle(dir)
	if Nav.state == "taskbar" then
		local i = Nav.taskIndex + dir
		if i >= 1 and i <= #taskbarEntries() then
			Nav.taskIndex = i
			return go("taskbar")
		end
	end
	local slots = Nav.Windows()
	if #taskbarEntries() > 0 then slots[#slots + 1] = { taskbar = true } end
	if #slots == 0 then return end
	local at = 0
	for i, slot in ipairs(slots) do
		if (Nav.state == "taskbar" and slot.taskbar) or (Nav.state ~= "taskbar" and slot.id == Desktop.focused) then at = i end
	end
	local slot = slots[(at - 1 + dir) % #slots + 1]
	if slot.taskbar then Nav.FocusTaskbar(dir) else Nav.FocusWindow(slot.id) end
end

function Nav.SwitchTab(dir)
	local win = focusedWindow()
	local rec = win and win.rec
	if not rec then return end
	local _, shown = win:ShownTab()
	local available = {}
	for i, t in ipairs(rec.tabs) do
		if PP.Sources.Get(t.src) then available[#available + 1] = i end
	end
	if #available < 2 then return end
	local at = indexOf(available, shown) or 1
	Layout.Activate(rec.id, available[(at - 1 + dir) % #available + 1])
end

-- Enter on a window equips its tool and leaves cursor mode (v1); Shift+Enter opens its menu.
function Nav.Use()
	local win = focusedWindow()
	if not win then return end
	if Input.ShiftHeld() then
		local menu = PP.Actions.OpenWindowMenu(win.id)
		if menu then
			local x, y = win:LocalToScreen(0, 0)
			Nav.DriveMenu(menu, x + win:GetWide() / 2, y + 16, "windows")
		end
		return
	end
	local tab = win:ShownTab()
	if tab and PP.Sources.Equip(tab.src) then Input.SetCursorMode(false) end
end

function Nav.RestoreFromTaskbar()
	local e = taskbarEntries()[Nav.taskIndex or 1]
	if not e then return end
	Desktop.RestoreAndFront(e.id)
	if #taskbarEntries() <= 1 then go("windows") end
end

-- ── Content ─────────────────────────────────────────────────

local DIRS = { [KEY_LEFT] = "left", [KEY_RIGHT] = "right", [KEY_UP] = "up", [KEY_DOWN] = "down" }

local function currentElement()
	local list = Nav.Elements()
	if not (IsValid(Nav.element) and indexOf(list, Nav.element)) then setElement(topmost(list)) end
	return Nav.element, list
end

function Nav.Arrow(key)
	local el, list = currentElement()
	if not el then
		if key == KEY_UP then leaveContent() end
		return
	end
	local adapter = Nav.Adapter(el)
	-- A page that is only HTML scrolls straight away (L20).
	local htmlOnly = #list == 1 and adapter.id == "html"
	if Nav.state == "adjust" or htmlOnly then
		local a = adapter.adjust
		if a == "2d" or a == "vert" or a == "scroll" or (a == "1d" and (key == KEY_LEFT or key == KEY_RIGHT)) then
			return adapter.onAdjust(el, key, Input.ShiftHeld())
		end
		if Nav.state == "adjust" then return go("content") end
	end
	if adapter.onArrow and adapter.onArrow(el, key) then return end
	local others, rects = {}, {}
	for _, e in ipairs(list) do
		if e ~= el then
			others[#others + 1] = e
			rects[#rects + 1] = rectOf(e)
		end
	end
	local target = Nav.Rank(rects, rectOf(el), DIRS[key])
	if target then
		setElement(others[target])
	elseif key == KEY_UP then
		leaveContent() -- Up at the top edge
	end
end

function Nav.Activate()
	local el = currentElement()
	if not el then return end
	if Input.ShiftHeld() then return Nav.ElementMenu(el) end
	if Nav.state == "adjust" then return go("content") end
	local adapter = Nav.Adapter(el)
	if adapter.adjust then return go("adjust") end
	adapter.activate(el)
end

function Nav.Back()
	if Nav.state == "adjust" then return go("content") end
	leaveContent()
end

-- ── Menus (§19.5) ───────────────────────────────────────────
-- A real DMenu, driven by the keyboard: Up/Down highlight, Right/Enter open a submenu, Enter runs an
-- option, Left/Backspace close a submenu, Backspace at the top closes the menu.

local function options(menu)
	local out = {}
	for _, c in ipairs(menu:GetCanvas():GetChildren()) do
		if c.ClassName == "DMenuOption" or c.ClassName == "DMenuOptionCVar" then out[#out + 1] = c end
	end
	return out
end

local function highlight()
	local menu = Nav.menus[#Nav.menus]
	local opts = options(menu)
	local opt = opts[Nav.menuIndex]
	menu:ClearHighlights()
	if opt then menu:HighlightItem(opt) end
end

function Nav.DriveMenu(menu, x, y, returnState)
	menu:SetKeyboardInputEnabled(false)
	if x then menu:SetPos(math.Clamp(x, 0, ScrW() - menu:GetWide()), math.Clamp(y, 0, ScrH() - menu:GetTall())) end
	Nav.menus, Nav.menuIndex, Nav.menuReturn = { menu }, 1, returnState
	local opts = options(menu)
	while opts[Nav.menuIndex] and not opts[Nav.menuIndex]:IsEnabled() and Nav.menuIndex < #opts do Nav.menuIndex = Nav.menuIndex + 1 end
	go("menu")
	highlight()
end

local function menuValid()
	if Nav.menus and IsValid(Nav.menus[1]) and Nav.menus[1]:IsVisible() then return true end
	Nav.Refresh()
	return false
end

-- An option may have moved navigation on already (a dialog opened as a popup zone); that one stays.
local function endMenu()
	CloseDermaMenus()
	Nav.menus = nil
	if Nav.state == "menu" then go(Nav.menuReturn or "windows") end
	Nav.Refresh()
end

function Nav.MenuMove(dir)
	if not menuValid() then return end
	local opts = options(Nav.menus[#Nav.menus])
	if #opts == 0 then return end
	local i = Nav.menuIndex
	for _ = 1, #opts do
		i = (i - 1 + dir) % #opts + 1
		if opts[i]:IsEnabled() then break end
	end
	Nav.menuIndex = i
	highlight()
end

function Nav.MenuOpen(run)
	if not menuValid() then return end
	local menu = Nav.menus[#Nav.menus]
	local opt = options(menu)[Nav.menuIndex]
	if not opt or not opt:IsEnabled() then return end
	if IsValid(opt.SubMenu) then
		menu:OpenSubMenu(opt, opt.SubMenu)
		opt.SubMenu:SetKeyboardInputEnabled(false)
		Nav.menus[#Nav.menus + 1] = opt.SubMenu
		Nav.menuIndex = 1
		return highlight()
	end
	if run then
		opt:DoClick()
		endMenu()
	end
end

function Nav.MenuBack(close)
	if not menuValid() then return end
	if #Nav.menus > 1 then
		local sub = table.remove(Nav.menus)
		Nav.menus[#Nav.menus]:CloseSubMenu(sub)
		Nav.menuIndex = 1
		return highlight()
	end
	if close then endMenu() end
end

-- Opens an element's own right-click menu and finds it without patching menus: first through
-- RegisterDermaMenuForClose, wrapped only during the call (R5), else as a new child of the world panel.
-- Errors in the element's handler are printed once and nothing stays replaced (E29, B4, B5).
local function captureMenu(fn)
	local before = {}
	for _, c in ipairs(vgui.GetWorldPanel():GetChildren()) do before[c] = true end
	local captured
	local original = RegisterDermaMenuForClose
	Util.WithOverride(_G, "RegisterDermaMenuForClose", function(m)
		captured = captured or m
		return original(m)
	end, fn)
	if not IsValid(captured) then
		for _, c in ipairs(vgui.GetWorldPanel():GetChildren()) do
			if not before[c] and c.ClassName == "DMenu" then captured = c end
		end
	end
	return IsValid(captured) and captured or nil
end

local OPENERS = {
	function(p) if isfunction(p.OpenGenericSpawnmenuRightClickMenu) then p:OpenGenericSpawnmenuRightClickMenu() end end,
	function(p) if isfunction(p.DoRightClick) then p:DoRightClick() end end,
	function(p) if isfunction(p.OpenMenu) then p:OpenMenu() end end,
	function(p)
		if isfunction(p.OnMousePressed) then
			p:OnMousePressed(MOUSE_RIGHT)
			if isfunction(p.OnMouseReleased) then p:OnMouseReleased(MOUSE_RIGHT) end
		end
	end,
}

function Nav.ElementMenu(el)
	local target = el
	for _ = 1, MENU_PROBES do
		if not IsValid(target) or target == Nav.root then return end
		for _, open in ipairs(OPENERS) do
			local menu = captureMenu(function() open(target) end)
			if menu then
				local x, y = el:LocalToScreen(0, 0)
				return Nav.DriveMenu(menu, x + el:GetWide() / 2, y + el:GetTall() / 2, "content")
			end
		end
		target = target:GetParent()
	end
end

-- ── Keys ────────────────────────────────────────────────────

local NAMES = { "next", "prev", "tabnext", "tabprev", "enter", "use", "up", "down", "left", "right", "ok", "back" }

local function bind(name, key, fn, repeating)
	Input.SetKey("nav:" .. name, key, function()
		touch()
		fn()
	end, nil, repeating)
end

function bindKeys()
	for _, name in ipairs(NAMES) do Input.SetKey("nav:" .. name, nil) end
	local s, get = Nav.state, Settings.Get
	if s == "windows" or s == "taskbar" then
		bind("next", get("navNext"), function() Nav.Cycle(1) end)
		bind("prev", get("navPrev"), function() Nav.Cycle(-1) end)
	end
	if s == "windows" then
		bind("tabnext", get("navTabNext"), function() Nav.SwitchTab(1) end)
		bind("tabprev", get("navTabPrev"), function() Nav.SwitchTab(-1) end)
		bind("enter", get("navEnter"), Nav.EnterContent)
		bind("use", get("navUse"), Nav.Use)
	elseif s == "taskbar" then
		bind("use", get("navUse"), Nav.RestoreFromTaskbar)
		bind("back", KEY_BACKSPACE, function() go("windows") Nav.Refresh() end)
	elseif s == "content" or s == "adjust" then
		for key, name in pairs(DIRS) do bind(name, key, function() Nav.Arrow(key) end, true) end
		bind("ok", KEY_ENTER, Nav.Activate)
		bind("back", KEY_BACKSPACE, Nav.Back)
	elseif s == "menu" then
		bind("up", KEY_UP, function() Nav.MenuMove(-1) end, true)
		bind("down", KEY_DOWN, function() Nav.MenuMove(1) end, true)
		bind("right", KEY_RIGHT, function() Nav.MenuOpen(false) end)
		bind("ok", KEY_ENTER, function() Nav.MenuOpen(true) end)
		bind("left", KEY_LEFT, function() Nav.MenuBack(false) end)
		bind("back", KEY_BACKSPACE, function() Nav.MenuBack(true) end)
	end
end

local function refreshLater() Nav.Refresh() end
hook.Add("PinnedPanelsInputChanged", "PinnedPanels.Nav", refreshLater)
hook.Add("PinnedPanelsHeldChanged", "PinnedPanels.Nav", refreshLater)
hook.Add("PinnedPanelsChanged", "PinnedPanels.Nav", function(kind)
	if kind ~= "geometry" then Nav.Refresh() end
end)
hook.Add("PinnedPanelsSettingChanged", "PinnedPanels.Nav", function(key)
	if key == "navEverywhere" then Nav.Refresh() elseif key:sub(1, 3) == "nav" then bindKeys() end
end)

-- ── Drawing (called from the window's and the popup's PaintOver) ──

-- The element ring: outlined in black for contrast, pulsing on real time (G5); an HTML page gets a
-- scrollbar-like strip instead of a ring around the whole page.
local function paintElement(panel, el)
	local Theme = PP.Theme
	local ex, ey = el:LocalToScreen(0, 0)
	local x, y = panel:ScreenToLocal(ex, ey)
	local w, h = el:GetSize()
	if Nav.IsHTML(el) then
		x, w = x + w - 14, 14
	end
	local ring = Nav.state == "adjust" and Theme.navSelected or Theme.navElement
	surface.SetDrawColor(0, 0, 0, 255)
	surface.DrawOutlinedRect(x - 3, y - 3, w + 6, h + 6, 1)
	surface.SetDrawColor(ring)
	surface.DrawOutlinedRect(x - 2, y - 2, w + 4, h + 4, 2)
	surface.SetDrawColor(ring.r, ring.g, ring.b, 12 + 24 * math.abs(math.sin(RealTime() * 6)))
	surface.DrawRect(x, y, w, h)
end

-- The hint box under the window (above it near the bottom of the screen), drawn outside its bounds.
local function paintHint(panel, w, h)
	local Theme = PP.Theme
	local bw, bh = Nav.hintW + 16, Nav.hintH + 6
	local bx = math.floor((w - bw) / 2)
	local sx, sy = panel:LocalToScreen(bx, h + 4 + bh)
	if sx < 4 then bx = bx + 4 - sx elseif sx + bw > ScrW() - 4 then bx = bx - (sx + bw - ScrW() + 4) end
	local by = sy > ScrH() - 4 and -bh - 4 or h + 4
	local old = DisableClipping(true)
	draw.RoundedBox(4, bx, by, bw, bh, Theme.hintBg)
	draw.SimpleText(Nav.hint, "DermaDefault", bx + bw / 2, by + bh / 2, Theme.hintText, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	DisableClipping(old) -- B29
end

function Nav.PaintWindow(win, w, h)
	local s = Nav.state
	if s == "off" or s == "taskbar" or Desktop.focused ~= win.id then return end
	local inside = s == "content" or s == "adjust" or (s == "menu" and Nav.menuReturn == "content")
	surface.SetDrawColor(inside and PP.Theme.navRing or PP.Theme.focusRing)
	surface.DrawOutlinedRect(0, 0, w, h, 2)
	if inside and Nav.root ~= nil and Nav.memoryKey == win.id then
		paintHint(win, w, h)
		if IsValid(Nav.element) then paintElement(win, Nav.element) end
	end
end

function Nav.PaintPopup(popup, w, h)
	if Nav.root ~= popup or (Nav.state ~= "content" and Nav.state ~= "adjust") then return end
	if IsValid(Nav.element) then paintElement(popup, Nav.element) end
	paintHint(popup, w, h)
end
