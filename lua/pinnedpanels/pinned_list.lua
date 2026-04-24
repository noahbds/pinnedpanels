-- ============================================================
--  PinnedPanels / pinned_list.lua
-- ============================================================

function PinnedPanels.CreatePinnedList(parent)
	local root = vgui.Create("DPanel", parent)
	root:Dock(FILL)
	root.Paint = function() end

	local scroll = vgui.Create("DScrollPanel", root)
	scroll:Dock(FILL)
	scroll:DockMargin(4, 4, 4, 4)

	local function Rebuild()
		scroll:Clear()
		local count = 0
		for id, pin in pairs(PinnedPanels.Pins) do
			if not IsValid(pin.frame) then PinnedPanels.Pins[id] = nil
			else count = count + 1 end
		end

		if count == 0 then
			local lbl = vgui.Create("DLabel", scroll)
			lbl:SetText("No panels pinned yet.\nGo to the Tools tab and click Pin.")
			lbl:SetWrap(true)
			lbl:SetAutoStretchVertical(true)
			lbl:Dock(TOP)
			lbl:DockMargin(10, 20, 10, 0)
			lbl:SetTextColor(Color(140, 150, 170))
			return
		end

		for id, pin in pairs(PinnedPanels.Pins) do
			if not IsValid(pin.frame) then break end

			local row = vgui.Create("DPanel", scroll)
			row:Dock(TOP)
			row:SetTall(32)
			row:DockMargin(2, 1, 2, 0)
			row.Paint = function(self, w, h)
				draw.RoundedBox(3, 0, 0, w, h, Color(18, 48, 18, 220))
				surface.SetDrawColor(60, 200, 80)
				surface.DrawRect(0, 0, 3, h)
			end

			local lockIcon = vgui.Create("DImage", row)
			lockIcon:SetImage("icon16/lock.png")
			lockIcon:SetSize(14, 14)
			lockIcon:Dock(LEFT)
			lockIcon:DockMargin(6, 9, 4, 9)

			local lbl = vgui.Create("DLabel", row)
			lbl:SetText(pin.title)
			lbl:SetTextColor(Color(220, 230, 245))
			lbl:Dock(FILL)
			lbl:SetMouseInputEnabled(false)

			local visBtn = vgui.Create("DButton", row)
			visBtn:SetText("")
			visBtn:SetIcon("icon16/eye.png")
			visBtn:SetWide(26)
			visBtn:Dock(RIGHT)
			visBtn:DockMargin(0, 4, 2, 4)
			visBtn:SetTooltip("Show / Hide")
			visBtn.DoClick = function()
				if IsValid(pin.frame) then
					pin.frame:SetVisible(not pin.frame:IsVisible())
				end
			end

			local remBtn = vgui.Create("DButton", row)
			remBtn:SetText("")
			remBtn:SetIcon("icon16/cross.png")
			remBtn:SetWide(26)
			remBtn:Dock(RIGHT)
			remBtn:DockMargin(0, 4, 2, 4)
			remBtn:SetTooltip("Unpin")
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
