-- Phase 0 spike (§26, §33.15): in-game checks for the ⚑ verify items. Throwaway code, never shipped (addon.json ignores tools/).
-- Setup: copy to garrysmod/lua/pp_spike.lua, start singleplayer sandbox, run `lua_openscript_cl pp_spike.lua`, then `ppspike_help`.
-- Every check is a console command `ppspike_<name>` printing "[spike] ..."; `ppspike_cleanup` undoes everything.

local created = {}
local restores = {}

local function log(fmt, ...)
	local args = { ... }
	for i = 1, select("#", ...) do
		if type(args[i]) ~= "number" then args[i] = tostring(args[i]) end
	end
	MsgC(Color(120, 200, 255), "[spike] ", color_white, string.format(fmt, unpack(args)), "\n")
end

local function track(p)
	created[#created + 1] = p
	return p
end

local function cmd(name, fn)
	concommand.Add("ppspike_" .. name, function(_, _, args) fn(args[1]) end)
end

local function frame(title, x, y, w, h, parent)
	local f = track(vgui.Create("DFrame", parent))
	f:SetTitle(title)
	f:SetPos(x, y)
	f:SetSize(w, h)
	return f
end

local function popup(title, x, y, w, h)
	local f = frame(title, x, y, w, h)
	f:MakePopup()
	f:SetKeyboardInputEnabled(false)
	return f
end

local function contains(list, p)
	for _, c in ipairs(list) do
		if c == p then return true end
	end
	return false
end

local function cleanup()
	for i = #restores, 1, -1 do restores[i]() end
	restores = {}
	for _, p in ipairs(created) do
		if IsValid(p) then p:Remove() end
	end
	created = {}
	gui.EnableScreenClicker(false)
end

cmd("cleanup", function()
	cleanup()
	log("cleaned up")
end)

local cursor = false
cmd("cursor", function()
	cursor = not cursor
	gui.EnableScreenClicker(cursor)
	log("cursor %s", cursor and "on" or "off")
end)

-- G41, G51, §33.3: which parent each kind of window ends up with.
cmd("where", function()
	local plain = frame("plain (no parent)", 50, 50, 220, 100)
	local pop = popup("MakePopup", 300, 50, 220, 100)
	local hud = frame("ParentToHUD", 550, 50, 220, 100)
	hud:ParentToHUD()
	for _, p in ipairs({ plain, pop, hud }) do
		log("%-18s world child=%s  GetHUDPanel child=%s  in vgui.GetAll=%s  IsPopup=%s  parent=%s",
			p:GetTitle(), contains(vgui.GetWorldPanel():GetChildren(), p), contains(GetHUDPanel():GetChildren(), p),
			contains(vgui.GetAll(), p), p:IsPopup(), p:GetParent())
	end
	log("expected: plain and MakePopup are world children; ParentToHUD is found only through vgui.GetAll")
end)

-- G30, E27: what the escape menu does to each kind of window.
cmd("escape", function()
	local v1 = frame("ParentToHUD then MakePopup (v1)", 50, 200, 260, 100)
	v1:ParentToHUD()
	v1:MakePopup()
	v1:SetKeyboardInputEnabled(false)
	popup("MakePopup only", 330, 200, 260, 100)
	frame("ParentToHUD only", 610, 200, 260, 100):ParentToHUD()
	log("press Escape: note which of the three windows stay visible, and whether any can be clicked over the escape menu")
end)

-- G26, E36: SetPopupStayAtBack against other popups, the spawn menu and a dialog.
cmd("stayback", function(arg)
	local cx, cy = ScrW() / 2, ScrH() / 2
	if arg == "query" then
		Derma_Query("Is the 'A2 stay-at-back' window behind this dialog?", "spike", "Close", function() end)
		popup("A2 stay-at-back (created after the dialog)", cx - 250, cy - 120, 500, 240):SetPopupStayAtBack(true)
		log("A2 was created after the dialog: it passes if it draws behind the dialog")
		return
	end
	popup("A stay-at-back", cx - 300, cy - 150, 360, 260):SetPopupStayAtBack(true)
	popup("B normal", cx - 60, cy - 50, 360, 260)
	log("1) ppspike_cursor, click A then B then A: A should never draw over B")
	log("2) open the spawn menu and click the parts of A and B you can reach: B may jump in front of it, A should not")
	log("3) ppspike_stayback query")
end)

-- G25: TestHover on a popup, so the body lets clicks through and the header stays draggable.
cmd("testhover", function()
	local behind = popup("behind", 200, 200, 500, 300)
	local target = vgui.Create("DButton", behind)
	target:Dock(FILL)
	target:SetText("behind: click me through the front window")
	target.DoClick = function() log("PASS-ish: the button behind got the click") end

	local front = popup("front: drag me by the header", 300, 250, 300, 200)
	local frontButton = vgui.Create("DButton", front)
	frontButton:Dock(FILL)
	frontButton:SetText("front body (should not be clickable)")
	frontButton.DoClick = function() log("FAIL: the front body took the click") end

	local logged = false
	front.TestHover = function(self, x, y)
		if not logged then
			logged = true
			local sx, sy = self:LocalToScreen(0, 0)
			log("TestHover got (%d, %d); the panel's screen origin is (%d, %d): tells whether coordinates are screen or local", x, y, sx, sy)
		end
		local _, ly = self:ScreenToLocal(x, y)
		return ly >= 0 and ly <= 24
	end
	log("ppspike_cursor, then click the front window's body (should reach the button behind) and drag its header")
end)

-- §19.5, G17: find a DMenu an element opened, then drive it from code.
cmd("dmenu", function()
	local host = popup("dmenu host", 100, 300, 300, 200)
	local clicked

	local function opener(parent)
		local m = DermaMenu(false, parent)
		m:AddOption("First", function() clicked = "First" end)
		local sub, subOption = m:AddSubMenu("Sub")
		sub:AddOption("Inner", function() clicked = "Inner" end)
		m:Open()
		return subOption
	end

	for _, withParent in ipairs({ false, true }) do
		local name = withParent and "DermaMenu(false, host)" or "DermaMenu()"
		local before = {}
		for _, c in ipairs(vgui.GetWorldPanel():GetChildren()) do before[c] = true end

		local captured
		local original = RegisterDermaMenuForClose
		RegisterDermaMenuForClose = function(m)
			captured = captured or m
			return original(m)
		end
		local ok, subOption = xpcall(opener, debug.traceback, withParent and host or nil)
		RegisterDermaMenuForClose = original
		if not ok then
			log("%s: opener errored: %s", name, subOption)
		else
			local diffed
			for _, c in ipairs(vgui.GetWorldPanel():GetChildren()) do
				if not before[c] and c.ClassName == "DMenu" then diffed = c end
			end
			log("%s: found by world-panel diff=%s, by RegisterDermaMenuForClose wrap=%s", name, diffed ~= nil, captured ~= nil)

			local menu = diffed or captured
			if menu then
				clicked = nil
				menu:HighlightItem(menu:GetChild(2))
				menu:OpenSubMenu(subOption, subOption.SubMenu)
				local subOpen = IsValid(subOption.SubMenu) and subOption.SubMenu:IsVisible()
				subOption.SubMenu:GetChild(1):DoClick()
				CloseDermaMenus()
				log("%s: ChildCount=%d, submenu opened=%s, DoClick reached=%s (want Inner)", name, menu:ChildCount(), subOpen, clicked)
			end
		end
	end
end)

-- §14.3, L2: tools whose ControlPanel stays empty after FillViaTable; "fallback" also tries the controlpanel.Get hook trick.
cmd("emptytools", function(arg)
	local function count(p)
		local n = 0
		for _, c in ipairs(p:GetChildren()) do n = n + 1 + count(c) end
		return n
	end
	local blank = vgui.Create("ControlPanel")
	blank:FillViaTable({ Text = "blank" })
	local baseline = count(blank)
	blank:Remove()

	local seen, total, empty, failed = {}, 0, {}, {}
	for _, tab in ipairs(spawnmenu.GetTools()) do
		for _, category in ipairs(tab.Items) do
			for _, tool in ipairs(category) do
				if not seen[tool.ItemName] then
					seen[tool.ItemName] = true
					total = total + 1
					local cp = vgui.Create("ControlPanel")
					cp:SetVisible(false)
					local ok, err = pcall(cp.FillViaTable, cp, { Text = tool.Text, ControlPanelBuildFunction = tool.CPanelFunction })
					if not ok then
						failed[#failed + 1] = tool.ItemName .. ": " .. tostring(err)
					elseif count(cp) <= baseline then
						local note = tool.CPanelFunction and "has CPanelFunction" or "no CPanelFunction"
						if arg == "fallback" then
							local original = controlpanel.Get
							controlpanel.Get = function(name)
								if name == tool.ItemName then return cp end
								return original(name)
							end
							pcall(hook.Run, "PostReloadToolsMenu")
							controlpanel.Get = original
							note = note .. (count(cp) > baseline and ", FILLED by the fallback" or ", still empty with the fallback")
						end
						empty[#empty + 1] = string.format("%s [%s / %s] %s", tool.ItemName, tab.Name, category.ItemName, note)
					end
					cp:Remove()
				end
			end
		end
	end
	log("%d tools and option pages, %d empty, %d errored", total, #empty, #failed)
	for _, line in ipairs(empty) do log("  empty: %s", line) end
	for _, line in ipairs(failed) do log("  error: %s", line) end
end)

-- G8: is the chat box visible to Lua other than through StartChat/FinishChat?
cmd("chat", function()
	hook.Add("StartChat", "ppspike", function() log("StartChat fired") end)
	hook.Add("FinishChat", "ppspike", function() log("FinishChat fired") end)
	restores[#restores + 1] = function()
		hook.Remove("StartChat", "ppspike")
		hook.Remove("FinishChat", "ppspike")
		timer.Remove("ppspike_chat")
	end
	timer.Create("ppspike_chat", 0.5, 40, function()
		log("keyboard focus=%s  IsGameUIVisible=%s  IsConsoleVisible=%s  HasFocus=%s",
			vgui.GetKeyboardFocus(), gui.IsGameUIVisible(), gui.IsConsoleVisible(), system.HasFocus())
	end)
	log("open and close the chat box within 20 s; compare the focus lines while it's open")
end)

-- §33.15.2, G20, G21: a foreign popup left on screen while playing, then used in cursor mode.
local managed
cmd("manage", function(arg)
	if arg == "on" and IsValid(managed) then
		managed:SetMouseInputEnabled(true)
		log("mouse on: clicking and the slider should work; click the text field next")
		return
	end
	managed = popup("managed window", 100, 100, 320, 160)
	local entry = vgui.Create("DTextEntry", managed)
	entry:Dock(TOP)
	local slider = vgui.Create("DNumSlider", managed)
	slider:Dock(TOP)
	slider:SetText("slider")
	managed:SetMouseInputEnabled(false)

	hook.Add("OnTextEntryGetFocus", "ppspike", function(p)
		log("OnTextEntryGetFocus fired; taking the keyboard")
		if IsValid(managed) and p:HasParent(managed) then managed:SetKeyboardInputEnabled(true) end
	end)
	hook.Add("OnTextEntryLoseFocus", "ppspike", function()
		log("OnTextEntryLoseFocus fired; giving the keyboard back")
		if IsValid(managed) then managed:SetKeyboardInputEnabled(false) end
	end)
	restores[#restores + 1] = function()
		hook.Remove("OnTextEntryGetFocus", "ppspike")
		hook.Remove("OnTextEntryLoseFocus", "ppspike")
	end
	log("mouse and keyboard off: walk and aim, the window should stay drawn; then ppspike_cursor and ppspike_manage on")
end)

-- §33.15.3, G4, G56: move a window's contents into another popup, ghost the shell, release.
local shell, host, moved, thinks
cmd("embed", function(arg)
	if arg == nil then
		shell = popup("shell", 100, 100, 320, 200)
		local entry = vgui.Create("DTextEntry", shell)
		entry:Dock(TOP)
		local slider = vgui.Create("DNumSlider", shell)
		slider:Dock(TOP)
		slider:SetText("slider")
		local button = vgui.Create("DButton", shell)
		button:Dock(FILL)
		button:SetText("button")
		button.DoClick = function() log("button clicked") end
		thinks = 0
		local baseThink = shell.Think
		shell.Think = function(self)
			thinks = thinks + 1
			if baseThink then baseThink(self) end
		end
		log("shell created; then: ppspike_embed move, ppspike_embed manual, ppspike_embed release")
	elseif arg == "move" and IsValid(shell) then
		host = popup("host (embedded contents)", 500, 100, 320, 230)
		local inner = vgui.Create("Panel", host)
		inner:SetPos(0, 30)
		inner:SetSize(shell:GetSize())
		inner:DockPadding(shell:GetDockPadding())
		local chrome = { [shell.btnClose] = true, [shell.btnMaxim] = true, [shell.btnMinim] = true, [shell.lblTitle] = true, [shell.imgIcon or false] = true }
		moved = {}
		for _, c in ipairs(shell:GetChildren()) do
			if not chrome[c] then moved[#moved + 1] = c end
		end
		for _, c in ipairs(moved) do c:SetParent(inner) end
		shell:SetAlpha(0)
		shell:SetMouseInputEnabled(false)
		shell:SetKeyboardInputEnabled(false)
		local start = thinks
		timer.Simple(1, function() log("ghosted shell Think calls in 1 s: %d (want > 0)", thinks - start) end)
		log("moved %d children; with ppspike_cursor, check clicks, typing (click the field) and the slider in the host", #moved)
	elseif arg == "manual" and IsValid(shell) then
		shell:SetPaintedManually(true)
		shell:SetAlpha(255)
		local start = thinks
		timer.Simple(1, function() log("SetPaintedManually shell Think calls in 1 s: %d; is the shell invisible? (want yes and > 0)", thinks - start) end)
	elseif arg == "release" and IsValid(shell) then
		for _, c in ipairs(moved) do c:SetParent(shell) end
		shell:SetPaintedManually(false)
		shell:SetAlpha(255)
		shell:SetMouseInputEnabled(true)
		shell:InvalidateLayout(true)
		if IsValid(host) then host:Remove() end
		log("released: the shell should work exactly as at the start")
	end
end)

-- §33.15.4, G45, G52: reproduce v1's failure by reparenting a whole popup.
cmd("reparent", function()
	local outer = popup("outer", 100, 100, 500, 400)
	local inner = popup("inner popup, reparented into outer", 150, 150, 300, 200)
	local button = vgui.Create("DButton", inner)
	button:Dock(FILL)
	button:SetText("click me")
	button.DoClick = function() log("reparented popup still takes clicks") end
	inner:SetParent(outer)
	inner:SetPos(20, 40)
	local x, y = inner:LocalToScreen(0, 0)
	log("inner:SetPos(20, 40) inside outer at (100, 100) → screen (%d, %d) (120, 140 if positions stay local)", x, y)
	log("ppspike_cursor, then click the button and drag outer: expect broken input or position (G45, G52)")
end)

-- §33.15.5, G48, G60–G62: while recording, name the opener of each new top-level panel from the call stack.
cmd("record", function(arg)
	local names = {}
	for name, fn in pairs(concommand.GetTable()) do names[fn] = "concommand " .. name end
	for name, fn in pairs(net.Receivers) do names[fn] = "net message " .. name end
	for event, ids in pairs(hook.GetTable()) do
		for id, fn in pairs(ids) do names[fn] = "hook " .. event .. " / " .. tostring(id) end
	end

	local function report(kind, parent)
		if parent ~= nil then return end
		local level, found = 3, {}
		while true do
			local info = debug.getinfo(level, "fS")
			if not info then break end
			if names[info.func] then found[#found + 1] = names[info.func] .. " (" .. info.short_src .. ")" end
			level = level + 1
		end
		log("%s created a top-level panel; openers on the stack: %s", kind, #found > 0 and table.concat(found, ", ") or "none")
	end

	local create, fromTable = vgui.Create, vgui.CreateFromTable
	vgui.Create = function(class, parent, name)
		report("vgui.Create(" .. tostring(class) .. ")", parent)
		return create(class, parent, name)
	end
	vgui.CreateFromTable = function(meta, parent, name)
		report("vgui.CreateFromTable", parent)
		return fromTable(meta, parent, name)
	end
	local function unwrap()
		if vgui.Create ~= create then vgui.Create, vgui.CreateFromTable = create, fromTable end
	end
	restores[#restores + 1] = unwrap
	timer.Simple(10, function()
		unwrap()
		log("recording stopped")
	end)

	if arg == "net" then
		net.Receive("ppspike_open", function() track(vgui.Create("DFrame")):SetTitle("opened by the server") end)
		names[net.Receivers["ppspike_open"]] = "net message ppspike_open"
		log("recording 10 s; on a listen server run: lua_run util.AddNetworkString(\"ppspike_open\") net.Start(\"ppspike_open\") net.Broadcast()")
	else
		log("recording 10 s; running pp_superdof (want: concommand pp_superdof found)")
		RunConsoleCommand("pp_superdof")
	end
end)

cmd("help", function()
	for _, line in ipairs({
		"ppspike_cursor         toggle the mouse cursor (bind it to a key)",
		"ppspike_where          G41/G51: where plain, popup and HUD windows live",
		"ppspike_escape         G30/E27: windows during the escape menu",
		"ppspike_stayback       G26/E36: SetPopupStayAtBack (then: ppspike_stayback query)",
		"ppspike_testhover      G25: click-through body, draggable header",
		"ppspike_dmenu          §19.5: find and drive an element's DMenu",
		"ppspike_emptytools     §14.3: tools with empty panels (ppspike_emptytools fallback also tries the hook trick)",
		"ppspike_chat           G8: chat visibility to Lua",
		"ppspike_manage         §33.15.2: manage a popup (then: ppspike_manage on)",
		"ppspike_embed          §33.15.3: embed contents (then: move, manual, release)",
		"ppspike_reparent       §33.15.4: v1's reparenting failure",
		"ppspike_record         §33.15.5: opener from the stack (ppspike_record net on a listen server)",
		"ppspike_cleanup        remove everything the spike created",
		"By hand (§33.15.6): E2 editor (keyboard), Advanced Duplicator 2, one addon settings window, one DHTML window (reload when moved?)",
	}) do
		log(line)
	end
end)

log("loaded; type ppspike_help")
