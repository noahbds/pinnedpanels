-- PinnedPanelsTabHost (§15.2): one per built tab, created when the tab is first shown and built one per
-- frame (D13, E24). Its clip panel ignores the mouse and the content takes it (L22), so a crop can later
-- move the content inside it without reparenting. PinnedPanelsScroll throttles tool-panel layout (L3, B6).

local PP = PinnedPanels

-- ── PinnedPanelsScroll ──────────────────────────────────────
-- Tool panels invalidate their scroll panel in storms while they build. Layout runs at most once per
-- THROTTLE seconds, and a skipped layout always runs later (trailing edge), unlike v1's leading-edge wrapper.

local THROTTLE = 0.1

local SCROLL = {}

function SCROLL:PerformLayout(w, h)
	local now = RealTime()
	if now < (self.nextLayout or 0) then
		self.layoutPending = true
		return
	end
	self.nextLayout = now + THROTTLE
	self.layoutPending = false
	baseclass.Get("DScrollPanel").PerformLayout(self, w, h)
end

function SCROLL:Think()
	local base = baseclass.Get("DScrollPanel")
	if base.Think then base.Think(self) end
	if self.layoutPending and RealTime() >= self.nextLayout then self:InvalidateLayout() end
end

vgui.Register("PinnedPanelsScroll", SCROLL, "DScrollPanel")

-- ── PinnedPanelsTabHost ─────────────────────────────────────

local HOST = {}

function HOST:Init()
	self.clip = self:Add("Panel")
	self.clip:Dock(FILL)
	self.clip:SetMouseInputEnabled(false)
end

function HOST:SetSource(src)
	self.src = src
end

-- Think only runs while the host is visible (G4), so hidden tabs and minimized windows wait.
function HOST:Think()
	if not self.built and PP.Desktop.ClaimBuild() then self:Build() end
end

function HOST:Build()
	self.built = true
	self.clip:Clear()
	self.content = PP.Sources.Build(self.src, self.clip)
	if not self.content then
		local err = self.clip:Add("PinnedPanelsError")
		err:Dock(FILL)
		err:SetMouseInputEnabled(true)
		err:SetRetry(function() self.built = false end)
	end
end

vgui.Register("PinnedPanelsTabHost", HOST, "Panel")
