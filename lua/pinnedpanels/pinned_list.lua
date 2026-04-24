function PinnedPanels.CreatePinnedList(parent)
	local root = vgui.Create("DPanel", parent)
	root.Paint = function(self, w, h)
		draw.RoundedBox(0, 0, 0, w, h, Color(30, 32, 40, 255))
	end

	local scroll = vgui.Create("DScrollPanel", root)
	scroll:Dock(FILL)
	scroll:DockMargin(16, 16, 16, 16)

	local oldInvalidate = scroll.InvalidateLayout
	scroll.NextLayout = 0
	scroll.InvalidateLayout = function(self, layoutNow)
		if CurTime() < self.NextLayout then return end
		self.NextLayout = CurTime() + 0.1
		oldInvalidate(self, layoutNow)
	end

	local function Rebuild()
		scroll:Clear()
		local count = 0
		for id, pin in pairs(PinnedPanels.Pins) do
			if not IsValid(pin.frame) then
				PinnedPanels.Unpin(id)
			else
				count = count + 1
			end
		end
		if count == 0 then
			local emptyCard = vgui.Create("DPanel", scroll)
			emptyCard:Dock(TOP)
			emptyCard:SetTall(110)
			emptyCard.Paint = function(self, w, h)
				draw.RoundedBox(6, 0, 0, w, h, Color(40, 44, 52, 255))
				draw.RoundedBoxEx(6, 0, 0, w, 30, Color(25, 28, 34, 255), true, true, false, false)
				draw.SimpleText("No Pinned Panels", "DermaDefaultBold", 12, 15, Color(200, 210, 225), TEXT_ALIGN_LEFT,
					TEXT_ALIGN_CENTER)
				draw.SimpleText("You have no valid pinned panels right now.", "DermaDefault", w / 2, h / 2 + 5,
					Color(150, 160, 175), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
				draw.SimpleText("Go to the 'Tools' tab and click 'Pin' on any tool.", "DermaDefault", w / 2, h / 2 + 25,
					Color(110, 120, 135), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			end
			return
		end
		for id, pin in pairs(PinnedPanels.Pins) do
			if not IsValid(pin.frame) then break end

			local row = vgui.Create("DPanel", scroll)
			row:Dock(TOP)
			row:SetTall(40)
			row:DockMargin(0, 0, 0, 8)
			row.Paint = function(self, w, h)
				local bg = self:IsHovered() and Color(50, 55, 65, 255) or Color(40, 44, 52, 255)
				draw.RoundedBox(6, 0, 0, w, h, bg)
				surface.SetDrawColor(60, 140, 255)
				surface.DrawRect(0, 0, 4, h)
			end

			local lockIcon = vgui.Create("DImage", row)
			lockIcon:SetImage("icon16/lock.png")
			lockIcon:SetSize(14, 14)
			lockIcon:Dock(LEFT)
			lockIcon:DockMargin(12, 13, 8, 13)

			local lbl = vgui.Create("DLabel", row)
			lbl:SetText(pin.title)
			lbl:SetFont("DermaDefaultBold")
			lbl:SetTextColor(Color(220, 225, 235))
			lbl:Dock(FILL)
			lbl:SetMouseInputEnabled(false)

			local visBtn = vgui.Create("DButton", row)
			visBtn:SetText("")
			visBtn:SetIcon("icon16/eye.png")
			visBtn:SetWide(32)
			visBtn:Dock(RIGHT)
			visBtn:DockMargin(0, 4, 4, 4)
			visBtn:SetTooltip("Show / Hide")
			visBtn.Paint = function(self, w, h)
				local bg = self:IsHovered() and Color(70, 75, 85) or Color(55, 60, 70)
				draw.RoundedBox(4, 0, 0, w, h, bg)
			end
			visBtn.DoClick = function()
				if IsValid(pin.frame) then
					pin.frame:SetVisible(not pin.frame:IsVisible())
				end
			end

			local remBtn = vgui.Create("DButton", row)
			remBtn:SetText("")
			remBtn:SetIcon("icon16/cross.png")
			remBtn:SetWide(32)
			remBtn:Dock(RIGHT)
			remBtn:DockMargin(0, 4, 4, 4)
			remBtn:SetTooltip("Unpin")
			remBtn.Paint = function(self, w, h)
				local bg = self:IsHovered() and Color(200, 60, 60) or Color(160, 40, 40)
				draw.RoundedBox(4, 0, 0, w, h, bg)
			end
			remBtn.DoClick = function()
				PinnedPanels.Unpin(id)
				Rebuild()
			end
		end
	end

	Rebuild()
	root.Rebuild = Rebuild
	return root
end
