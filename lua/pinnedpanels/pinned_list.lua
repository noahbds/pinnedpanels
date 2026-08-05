local C = PinnedPanels.C

local function MakeActionBtn(parent, text, iconPath, width, bgNorm, bgHover, txtCol, ttText)
	local btn = vgui.Create("DButton", parent)
	btn:SetText(text)
	btn:SetWide(width)
	btn:Dock(RIGHT)
	btn:DockMargin(0, 5, 4, 5)
	btn:SetTextColor(txtCol)
	btn:SetIcon(iconPath)

	btn.Paint = function(self, w, h)
		local bg = self:IsHovered() and bgHover or bgNorm
		draw.RoundedBox(4, 0, 0, w, h, bg)
		surface.SetDrawColor(C.btnOutline)
		surface.DrawOutlinedRect(0, 0, w, h, 1)
	end

	btn:SetTooltip(ttText)
	return btn
end

function PinnedPanels.CreatePinnedList(parent)
	local root = vgui.Create("DPanel", parent)
	root.Paint = function(self, w, h)
		draw.RoundedBox(0, 0, 0, w, h, C.bg)
	end

	local scroll = vgui.Create("DScrollPanel", root)
	scroll:Dock(FILL)
	scroll:DockMargin(16, 16, 16, 16)

	PinnedPanels.ThrottleScroll(scroll)

	local isRebuilding = false
	local expandedGroups = {}

	local function Rebuild()
		if isRebuilding then return end
		isRebuilding = true

		scroll:Clear()

		local stale = {}
		for id, pin in pairs(PinnedPanels.Pins) do
			if not IsValid(pin.frame) then stale[#stale + 1] = id end
		end
		for _, id in ipairs(stale) do PinnedPanels.Pins[id] = nil end
		if #stale > 0 then PinnedPanels.Save() end

		local count = 0
		for _ in pairs(PinnedPanels.Pins) do count = count + 1 end

		if count == 0 then
			local emptyCard = vgui.Create("DPanel", scroll)
			emptyCard:Dock(TOP)
			emptyCard:SetTall(110)
			emptyCard.Paint = function(self, w, h)
				draw.RoundedBox(6, 0, 0, w, h, C.bgCard)
				draw.RoundedBoxEx(6, 0, 0, w, 30, C.bgCardHdr, true, true, false, false)
				draw.SimpleText(PinnedPanels.L("no_pinned"), "DermaDefaultBold", 12, 15, C.textTitle,
					TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
				draw.SimpleText(PinnedPanels.L("no_pinned_desc"), "DermaDefault",
					w / 2, h / 2 + 5, C.textBody, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
				draw.SimpleText(PinnedPanels.L("no_pinned_hint"), "DermaDefault",
					w / 2, h / 2 + 22, C.textMuted, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			end
			isRebuilding = false
			return
		end

		local sorted = {}
		for id, pin in pairs(PinnedPanels.Pins) do
			if IsValid(pin.frame) then sorted[#sorted + 1] = { id = id, pin = pin } end
		end
		table.sort(sorted, function(a, b) return a.pin.title < b.pin.title end)

		for _, entry in ipairs(sorted) do
			local id  = entry.id
			local pin = entry.pin

			local isFramePin   = pin.kind == "frame"
			local isCreation   = pin.kind == "creation"
			local isGroup      = pin.kind == "group"
			local isGrouped    = (not isGroup) and PinnedPanels.GetGroupForPanel(id) ~= nil

			if isGrouped then continue end

			local kindLabel, kindColor, accentColor, kindIcon
			if isGroup then
				kindLabel   = PinnedPanels.L("kind_group")
				kindColor   = C.kindCreation
				accentColor = C.accentGreen
				kindIcon    = "icon16/folder.png"
			elseif isFramePin then
				kindLabel   = PinnedPanels.L("kind_frame")
				kindColor   = C.kindFrame
				accentColor = C.accentFrame
				kindIcon    = "icon16/application.png"
			elseif isCreation then
				kindLabel   = PinnedPanels.L("kind_content")
				kindColor   = C.kindCreation
				accentColor = C.accentGreen
				kindIcon    = "icon16/application_view_list.png"
			else
				kindLabel   = PinnedPanels.L("kind_tool")
				kindColor   = C.kindTool
				accentColor = C.accent
				kindIcon    = "icon16/wrench.png"
			end

			local row = vgui.Create("DPanel", scroll)
			row:Dock(TOP)
			row:SetTall(40)
			row:DockMargin(0, 0, 0, 6)
			row.Paint = function(self, w, h)
				local bg = self:IsHovered() and C.bgRowHov or C.bgCard
				draw.RoundedBox(6, 0, 0, w, h, bg)
				surface.SetDrawColor(accentColor)
				surface.DrawRect(0, 0, 4, h)
			end

			local typeIcon = vgui.Create("DImage", row)
			typeIcon:SetImage(kindIcon)
			typeIcon:SetSize(14, 14)
			typeIcon:Dock(LEFT)
			typeIcon:DockMargin(10, 13, 6, 13)

			local titleText = pin.title
			if isGroup and pin.groupName then
				local memberCount = 0
				for _, g in ipairs(PinnedPanels.Settings.groups) do
					if g.name == pin.groupName then memberCount = #g.ids break end
				end
				titleText = titleText .. " " .. PinnedPanels.Lf("group_panels", memberCount)
			end
			if pin.minimized then
				titleText = titleText .. " " .. PinnedPanels.L("tag_minimized")
			end

			local lbl = vgui.Create("DLabel", row)
			lbl:SetText(titleText)
			lbl:SetFont("DermaDefaultBold")
			lbl:SetTextColor(C.textLight)
			lbl:Dock(FILL)
			lbl:SetMouseInputEnabled(false)

			local kindLbl = vgui.Create("DLabel", row)
			kindLbl:SetText(kindLabel)
			kindLbl:SetFont("DermaDefault")
			kindLbl:SetTextColor(kindColor)
			kindLbl:SetWide(46)
			kindLbl:Dock(RIGHT)
			kindLbl:DockMargin(0, 0, 4, 0)
			kindLbl:SetContentAlignment(6)
			kindLbl:SetMouseInputEnabled(false)

			local visBtn = MakeActionBtn(row,
				PinnedPanels.L("btn_hide"),
				"icon16/eye.png",
				72,
				C.btnBg, C.btnBgHov,
				C.btnText,
				PinnedPanels.L("tip_hide_panel"))

			local function UpdateVisBtn()
				if not IsValid(visBtn) or not IsValid(pin.frame) then return end
				if pin.minimized then
					visBtn:SetText(PinnedPanels.L("btn_restore"))
					visBtn:SetIcon("icon16/arrow_up.png")
					visBtn:SetTooltip(PinnedPanels.L("tip_restore_tb"))
				else
					local visible = pin.frame:IsVisible()
					visBtn:SetText(visible and PinnedPanels.L("btn_hide") or PinnedPanels.L("btn_show"))
					visBtn:SetIcon(visible and "icon16/eye.png" or "icon16/cancel.png")
					visBtn:SetTooltip(visible and PinnedPanels.L("tip_hide_panel") or PinnedPanels.L("tip_show_panel"))
				end
			end
			UpdateVisBtn()

			visBtn.DoClick = function()
				if IsValid(pin.frame) then
					if pin.minimized then
						PinnedPanels.RestoreFromTaskbar(id)
					else
						pin.frame:SetVisible(not pin.frame:IsVisible())
					end
					UpdateVisBtn()
				end
			end

			local focusBtn = MakeActionBtn(row,
				PinnedPanels.L("btn_move_front"),
				"icon16/shape_move_front.png",
				100,
				C.focusBg, C.focusBgHov,
				C.focusTxt,
				PinnedPanels.L("tip_move_front"))
			focusBtn.DoClick = function()
				if IsValid(pin.frame) then
					pin.frame:SetVisible(true)
					pin.frame:MoveToFront()
				end
			end

			if isGroup then
				local gName = pin.groupName

				local dissolveBtn = MakeActionBtn(row,
					PinnedPanels.L("btn_dissolve"),
					"icon16/folder_delete.png",
					68,
					C.unpinBg, C.unpinBgHov,
					C.unpinTxt,
					PinnedPanels.L("tip_dissolve"))
				dissolveBtn.DoClick = function()
					if gName then PinnedPanels.DeleteGroup(gName) end
				end

				local unpinAllBtn = MakeActionBtn(row,
					PinnedPanels.L("btn_unpin_all_s"),
					"icon16/cross.png",
					76,
					C.unpinBg, C.unpinBgHov,
					C.unpinTxt,
					PinnedPanels.L("tip_unpin_all_g"))
				unpinAllBtn.DoClick = function()
					PinnedPanels.Unpin(id)
				end

				local membersBtn = MakeActionBtn(row,
					PinnedPanels.L("btn_members"),
					"icon16/folder_explore.png",
					76,
					C.btnBg, C.btnBgHov,
					C.btnText,
					PinnedPanels.L("tip_members"))
				membersBtn.DoClick = function()
					if gName then
						expandedGroups[gName] = not expandedGroups[gName]
						Rebuild()
					end
				end
			else
				local remBtn = MakeActionBtn(row,
					PinnedPanels.L("btn_unpin"),
					"icon16/cross.png",
					68,
					C.unpinBg, C.unpinBgHov,
					C.unpinTxt,
					PinnedPanels.L("tip_unpin_simple"))
				remBtn.DoClick = function()
					PinnedPanels.Unpin(id)
				end

				if not isFramePin then
					local grpBtn = MakeActionBtn(row,
						PinnedPanels.L("btn_group"),
						"icon16/folder_go.png",
						64,
						C.btnBg, C.btnBgHov,
						C.btnText,
						PinnedPanels.L("tip_add_group"))
					grpBtn.DoClick = function()
						local m = DermaMenu()
						for _, g in ipairs(PinnedPanels.Settings.groups) do
							m:AddOption(g.name .. " (" .. #g.ids .. ")", function()
								PinnedPanels.AddToGroup(g.name, id)
							end):SetIcon("icon16/folder_go.png")
						end
						if #PinnedPanels.Settings.groups > 0 then m:AddSpacer() end
						m:AddOption(PinnedPanels.L("ctx_new_group"), function()
							PinnedPanels.PromptNewGroup(id)
						end):SetIcon("icon16/folder_add.png")
						m:Open()
					end
				end
			end

			if isGroup and pin.groupName and expandedGroups[pin.groupName] then
				local gData
				for _, g in ipairs(PinnedPanels.Settings.groups) do
					if g.name == pin.groupName then gData = g break end
				end
				for mi, memberId in ipairs(gData and gData.ids or {}) do
					local mPin = PinnedPanels.Pins[memberId]

					local mRow = vgui.Create("DPanel", scroll)
					mRow:Dock(TOP)
					mRow:SetTall(30)
					mRow:DockMargin(26, 0, 0, 4)
					mRow.Paint = function(_, w, h)
						draw.RoundedBox(4, 0, 0, w, h, C.bgCardHdr)
						surface.SetDrawColor(gData.color)
						surface.DrawRect(0, 0, 3, h)
					end

					local mLbl = vgui.Create("DLabel", mRow)
					mLbl:SetText(mi .. ". " .. (mPin and mPin.title or PinnedPanels.Lf("member_missing", memberId)))
					mLbl:SetTextColor(mPin and C.textLight or C.textMuted)
					mLbl:Dock(FILL)
					mLbl:DockMargin(10, 0, 0, 0)
					mLbl:SetMouseInputEnabled(false)

					local mUnpin = MakeActionBtn(mRow, PinnedPanels.L("btn_unpin"), "icon16/cross.png", 58,
						C.unpinBg, C.unpinBgHov, C.unpinTxt, PinnedPanels.L("tip_unpin_member"))
					mUnpin.DoClick = function() PinnedPanels.Unpin(memberId) end

					local mOut = MakeActionBtn(mRow, PinnedPanels.L("btn_ungroup"), "icon16/folder_delete.png", 70,
						C.btnBg, C.btnBgHov, C.btnText, PinnedPanels.L("tip_ungroup_mem"))
					mOut.DoClick = function() PinnedPanels.RemoveFromGroup(gData.name, memberId) end

					local mDown = MakeActionBtn(mRow, "▼", nil, 26,
						C.btnBg, C.btnBgHov, C.btnText, PinnedPanels.L("tip_move_down"))
					mDown.DoClick = function() PinnedPanels.MoveInGroup(gData.name, memberId, 1) end

					local mUp = MakeActionBtn(mRow, "▲", nil, 26,
						C.btnBg, C.btnBgHov, C.btnText, PinnedPanels.L("tip_move_up"))
					mUp.DoClick = function() PinnedPanels.MoveInGroup(gData.name, memberId, -1) end
				end
			end
		end

		isRebuilding = false
	end

	hook.Add("PinnedPanels_StateChanged", root, function()
		if IsValid(root) then Rebuild() else
			hook.Remove("PinnedPanels_StateChanged", root)
		end
	end)

	root.OnRemove = function()
		hook.Remove("PinnedPanels_StateChanged", root)
	end

	Rebuild()
	root.Rebuild = Rebuild
	return root
end
