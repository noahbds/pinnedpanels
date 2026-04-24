function PinnedPanels.CreatePinnedList(parent)
	local root = vgui.Create("DPanel", parent)
	root.Paint = function(self, w, h)
		draw.RoundedBox(0, 0, 0, w, h, Color(30, 32, 40, 255))
	end

	local scroll = vgui.Create("DScrollPanel", root)
	scroll:Dock(FILL)
	scroll:DockMargin(16, 16, 16, 16)

	local oldInvalidate     = scroll.InvalidateLayout
	scroll.NextLayout       = 0
	scroll.InvalidateLayout = function(self, layoutNow)
		if CurTime() < self.NextLayout then return end
		self.NextLayout = CurTime() + 0.1
		oldInvalidate(self, layoutNow)
	end

	local isRebuilding      = false

	local function Rebuild()
		if isRebuilding then return end
		isRebuilding = true

		scroll:Clear()

		local stale = {}
		for id, pin in pairs(PinnedPanels.Pins) do
			if not IsValid(pin.frame) then stale[#stale + 1] = id end
		end
		for _, id in ipairs(stale) do PinnedPanels.Unpin(id) end

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

		local function MakeIconBtn(parent, iconPath, bgNorm, bgHover, ttText)
			local btn = vgui.Create("DButton", parent)
			btn:SetText("")
			btn:SetWide(28)
			btn:Dock(RIGHT)
			btn:DockMargin(0, 5, 4, 5)

			local img = vgui.Create("DImage", btn)
			img:SetImage(iconPath)
			img:SetSize(14, 14)
			img:SetPos(7, 0)
			img:SetMouseInputEnabled(false)

			btn.Paint = function(self, w, h)
				img:SetPos(7, math.floor((h - 14) / 2))
				local bg = self:IsHovered() and bgHover or bgNorm
				draw.RoundedBox(4, 0, 0, w, h, bg)
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

			return btn, img
		end

		for _, entry in ipairs(sorted) do
			local id         = entry.id
			local pin        = entry.pin

			local isFramePin = pin.kind == "frame"

			local row        = vgui.Create("DPanel", scroll)
			row:Dock(TOP)
			row:SetTall(40)
			row:DockMargin(0, 0, 0, 6)
			row.Paint = function(self, w, h)
				local bg = self:IsHovered() and Color(50, 55, 65, 255) or Color(40, 44, 52, 255)
				draw.RoundedBox(6, 0, 0, w, h, bg)
				local accentCol = isFramePin and Color(130, 80, 220) or Color(60, 140, 255)
				surface.SetDrawColor(accentCol)
				surface.DrawRect(0, 0, 4, h)
			end

			local typeIcon = vgui.Create("DImage", row)
			typeIcon:SetImage(isFramePin and "icon16/application.png" or "icon16/wrench.png")
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
			kindLbl:SetText(isFramePin and "Frame" or "Tool")
			kindLbl:SetFont("DermaDefault")
			kindLbl:SetTextColor(isFramePin and Color(160, 110, 220) or Color(80, 140, 200))
			kindLbl:SetWide(38)
			kindLbl:Dock(RIGHT)
			kindLbl:DockMargin(0, 0, 4, 0)
			kindLbl:SetContentAlignment(6)
			kindLbl:SetMouseInputEnabled(false)

			local visBtn, visIcon = MakeIconBtn(row,
				"icon16/eye.png",
				Color(55, 60, 70), Color(70, 75, 85),
				"Hide panel")

			local function UpdateVisBtn()
				if not IsValid(visBtn) or not IsValid(pin.frame) then return end
				local visible = pin.frame:IsVisible()
				visIcon:SetImage(visible and "icon16/eye.png" or "icon16/cancel.png")
				visBtn._ttText = visible and "Hide panel" or "Show panel"
			end
			UpdateVisBtn()

			visBtn.DoClick = function()
				if IsValid(pin.frame) then
					pin.frame:SetVisible(not pin.frame:IsVisible())
					UpdateVisBtn()
				end
			end

			local focusBtn = MakeIconBtn(row,
				"icon16/arrow_refresh.png",
				Color(55, 75, 100), Color(70, 100, 130),
				"Bring to front")
			focusBtn.DoClick = function()
				if IsValid(pin.frame) then
					pin.frame:SetVisible(true)
					pin.frame:MoveToFront()
				end
			end

			local remBtn = MakeIconBtn(row,
				"icon16/cross.png",
				Color(160, 40, 40), Color(200, 60, 60),
				"Unpin")
			remBtn.DoClick = function()
				PinnedPanels.Unpin(id)
			end
		end

		isRebuilding = false
	end

	hook.Add("PinnedPanels_StateChanged", root, function()
		if IsValid(root) then
			Rebuild()
		else
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
