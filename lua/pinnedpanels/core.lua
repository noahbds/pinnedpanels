-- ── Bootstrap ────────────────────────────────────────────────────────────────
PinnedPanels                   = PinnedPanels or {}
PinnedPanels.Pins              = PinnedPanels.Pins or {}
PinnedPanels._clipboard        = nil

PinnedPanels.RebuildGroupFrame = PinnedPanels.RebuildGroupFrame or function() end

PinnedPanels.CREATION_OPTS     = { kind = "creation", fill = true, defaultW = 350, defaultH = 560 }

function PinnedPanels.PanelsInteractive()
	local IM = PinnedPanels.CursorMode
	return not not (IM and (IM.Active or IM.SpawnMenuOpen))
end

-- ── Usable Screen Bounds ─────────────────────────────────────────────────────
function PinnedPanels.GetUsableBounds()
	local x, y, w, h = 0, 0, ScrW(), ScrH()
	local ts = PinnedPanels.Settings and PinnedPanels.Settings.taskbar
	if ts and ts.enabled ~= false and not ts.revealOnHover then
		local th  = math.Clamp(tonumber(ts.height) or 32, 0, ScrH())
		local pos = ts.position or "bottom"
		if pos == "top" then
			y, h = th, h - th
		elseif pos == "left" then
			x, w = th, w - th
		elseif pos == "right" then
			w = w - th
		else
			h = h - th
		end
	end
	return x, y, w, h
end

function PinnedPanels.ClampToUsable(px, py, w, h)
	local ux, uy, uw, uh = PinnedPanels.GetUsableBounds()
	local nx = math.Clamp(px, ux, math.max(ux, ux + uw - w))
	local ny = math.Clamp(py, uy, math.max(uy, uy + uh - h))
	return nx, ny
end

-- ── Restore All ──────────────────────────────────────────────────────────────
function PinnedPanels.RestoreAll(noSave)
	local saved = PinnedPanels.Load()
	if not next(saved) then return end

	local toolMap = {}
	for _, t in ipairs(PinnedPanels.GetAllTools()) do toolMap["PP_" .. t.itemName] = t end

	local creationMap = {}
	for _, t in ipairs(PinnedPanels.GetAllCreationTabs()) do creationMap[t.id] = t end

	for id, s in pairs(saved) do
		local kind = s.kind or "tool"
		if kind == "tool" and toolMap[id] then
			local title = (s.customTitle and s.title) or toolMap[id].niceName
			PinnedPanels.Pin(id, title, toolMap[id].cpFunc, noSave)
		elseif kind == "creation" and creationMap[id] then
			local t = creationMap[id]
			local title = (s.customTitle and s.title) or t.label
			PinnedPanels.Pin(id, title, t.func, noSave, PinnedPanels.CREATION_OPTS)
		end
	end

	local rebuiltGroups = false
	for _, g in ipairs(PinnedPanels.Settings.groups) do
		if #g.ids > 0 then
			for _, panelId in ipairs(g.ids) do
				local pin = PinnedPanels.Pins[panelId]
				if pin and IsValid(pin.frame) then pin.frame:SetVisible(false) end
			end
			PinnedPanels.RebuildGroupFrame(g.name)
			rebuiltGroups = true
		end
	end

	if PinnedPanels.UpdatePanelStates then PinnedPanels.UpdatePanelStates() end
	if rebuiltGroups then PinnedPanels._pendingGroupRefresh = true end
end

-- ── Auto-Restore Hook ────────────────────────────────────────────────────────
hook.Add("Think", "PinnedPanels_AutoRestore", function()
	if not spawnmenu.GetTools() then return end
	hook.Remove("Think", "PinnedPanels_AutoRestore")
	if not PinnedPanels.Settings.autoRestore then return end
	timer.Simple(1, function() PinnedPanels.RestoreAll(true) end)
end)

-- ── Screen Resize Handler ────────────────────────────────────────────────────
hook.Add("OnScreenSizeChanged", "PinnedPanels_ScreenResize", function(oldW, oldH)
	local nw, nh = ScrW(), ScrH()
	if nw == oldW and nh == oldH then return end
	local kx = (oldW and oldW > 0) and (nw / oldW) or 1
	local ky = (oldH and oldH > 0) and (nh / oldH) or 1
	for _, pin in pairs(PinnedPanels.Pins) do
		if IsValid(pin.frame) then
			local x, y = pin.frame:GetPos()
			local w, h = pin.frame:GetSize()
			w, h = math.min(w, nw), math.min(h, nh)
			pin.frame:SetSize(w, h)
			pin.frame:SetPos(PinnedPanels.ClampToUsable(math.Round(x * kx), math.Round(y * ky), w, h))
		end
	end
	PinnedPanels.Save()
end)
