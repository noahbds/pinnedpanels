function PinnedPanels.CreatePinnedList(parent)
	local root = vgui.Create("DPanel", parent)
	root.Paint = function(self, w, h)
		draw.RoundedBox(0, 0, 0, w, h, Color(30, 32, 40, 255))
	end

	local scroll = vgui.Create("DScrollPanel", root)
	scroll:Dock(FILL)
	scroll:DockMargin(16, 16, 16, 16)

	PinnedPanels.ThrottleScroll(scroll)

	local isRebuilding = false

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
				draw.RoundedBox(6, 0, 0, w, h, Color(40, 44, 52, 255))
				draw.RoundedBoxEx(6, 0, 0, w, 30, Color(25, 28, 34, 255), true, true, false, false)
				draw.SimpleText("No Pinned Panels", "DermaDefaultBold", 12, 15, Color(200, 210, 225),
					TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
				draw.SimpleText("You have no valid pinned panels right now.", "DermaDefault",
					w / 2, h / 2 + 5, Color(150, 160, 175), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
				draw.SimpleText("Pin tools from 'Tools' tab, or frames from the 'Frames' tab.", "DermaDefault",
					w / 2, h / 2 + 22, Color(110, 120, 135), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			end
			isRebuilding = false
			return
		end

		local sorted = {}
		for id, pin in pairs(PinnedPanels.Pins) do
			if IsValid(pin.frame) then sorted[#sorted + 1] = { id = id, pin = pin } end
		end
		table.sort(sorted, function(a, b) return a.pin.title < b.pin.title end)

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
				surface.SetDrawColor(22, 24, 32)
				surface.DrawOutlinedRect(0, 0, w, h, 1)
			end

			btn._ttText = ttText
			btn.OnCursorEntered = function(self)
				if not self._tt or not IsValid(self._tt) then
					local tt = vgui.Create("DTooltip")
					tt:SetText(self._ttText)
					tt:SetPos(self:LocalToScreen(0, self:GetTall() + 2))
					tt:MakePopup()
					tt:SetMouseInputEnabled(false)
					self._tt = tt
				end
			end
			btn.OnCursorExited = function(self)
				if IsValid(self._tt) then self._tt:Remove() end
				self._tt = nil
			end
			btn.OnRemove = function(self)
				if IsValid(self._tt) then self._tt:Remove() end
			end

			return btn
		end

		for _, entry in ipairs(sorted) do
			local id  = entry.id
			local pin = entry.pin

			local isFramePin   = pin.kind == "frame"
			local isCreation   = pin.kind == "creation"
			local kindLabel    = isFramePin and "Frame" or isCreation and "Content" or "Tool"
			local kindColor    = isFramePin and Color(160, 110, 220) or isCreation and Color(70, 185, 100) or Color(80, 140, 200)
			local accentColor  = isFramePin and Color(130, 80, 220) or isCreation and Color(60, 200, 80) or Color(60, 140, 255)
			local kindIcon     = isFramePin and "icon16/application.png" or isCreation and "icon16/application_view_list.png" or "icon16/wrench.png"

			local row = vgui.Create("DPanel", scroll)
			row:Dock(TOP)
			row:SetTall(40)
			row:DockMargin(0, 0, 0, 6)
			row.Paint = function(self, w, h)
				local bg = self:IsHovered() and Color(50, 55, 65, 255) or Color(40, 44, 52, 255)
				draw.RoundedBox(6, 0, 0, w, h, bg)
				surface.SetDrawColor(accentColor)
				surface.DrawRect(0, 0, 4, h)
			end

			local typeIcon = vgui.Create("DImage", row)
			typeIcon:SetImage(kindIcon)
			typeIcon:SetSize(14, 14)
			typeIcon:Dock(LEFT)
			typeIcon:DockMargin(10, 13, 6, 13)

			local lbl = vgui.Create("DLabel", row)
			lbl:SetText(pin.title)
			lbl:SetFont("DermaDefaultBold")
			lbl:SetTextColor(Color(220, 225, 235))
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
				"Hide",
				"icon16/eye.png",
				72,
				Color(55, 60, 70), Color(70, 75, 85),
				Color(210, 220, 235),
				"Hide panel")

			local function UpdateVisBtn()
				if not IsValid(visBtn) or not IsValid(pin.frame) then return end
				local visible = pin.frame:IsVisible()
				visBtn:SetText(visible and "Hide" or "Show")
				visBtn:SetIcon(visible and "icon16/eye.png" or "icon16/cancel.png")
				visBtn._ttText = visible and "Hide panel" or "Show panel"
			end
			UpdateVisBtn()

			visBtn.DoClick = function()
				if IsValid(pin.frame) then
					pin.frame:SetVisible(not pin.frame:IsVisible())
					UpdateVisBtn()
				end
			end

			local focusBtn = MakeActionBtn(row,
				"Move to Front",
				"icon16/shape_move_front.png",
				100,
				Color(55, 75, 100), Color(70, 100, 130),
				Color(200, 220, 245),
				"Bring to front")
			focusBtn.DoClick = function()
				if IsValid(pin.frame) then
					pin.frame:SetVisible(true)
					pin.frame:MoveToFront()
				end
			end

			local remBtn = MakeActionBtn(row,
				"Unpin",
				"icon16/cross.png",
				74,
				Color(160, 40, 40), Color(200, 60, 60),
				Color(255, 220, 220),
				"Unpin")
			remBtn.DoClick = function()
				PinnedPanels.Unpin(id)
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
