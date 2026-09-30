-- Colour tokens and fonts for our own controls (§22), created once (G29). Hosted tool panels keep GMod's
-- Default skin: windows never call SetSkin (G22, D6, R10). Values keep the v1 look.

local PP = PinnedPanels
PP.Theme = PP.Theme or {}
local T = PP.Theme

-- Surfaces
T.bg = Color(30, 32, 40)
T.bgDark = Color(24, 26, 32)
T.bgDarker = Color(20, 22, 28)
T.header = Color(18, 20, 26)
T.headerLine = Color(35, 38, 46)
T.hover = Color(35, 38, 48)
T.categoryBg = Color(25, 28, 34)

-- Text
T.textBright = Color(240, 245, 255)
T.text = Color(220, 225, 235)
T.textLabel = Color(180, 190, 210)
T.textSubtle = Color(140, 150, 165)
T.textMuted = Color(110, 120, 135)

-- Meaning
T.accent = Color(60, 140, 255)
T.success = Color(60, 200, 80)
T.danger = Color(220, 80, 80)
T.warning = Color(255, 180, 60, 200)
T.idle = Color(70, 75, 90)

-- Pinned / not pinned: list rows and the pin button
T.rowOn, T.rowOnHover = Color(18, 48, 18, 220), Color(25, 65, 25)
T.rowOff, T.rowOffHover = Color(26, 26, 40, 200), Color(38, 38, 58)
T.button, T.buttonHover, T.buttonText, T.buttonOutline = Color(35, 40, 55), Color(55, 65, 90), Color(160, 175, 210), Color(50, 55, 80)
T.buttonOn, T.buttonOnHover, T.buttonOnText, T.buttonOnOutline = Color(30, 80, 30), Color(50, 110, 50), Color(100, 230, 110), Color(40, 120, 40)

-- Text entries
T.inputBg, T.inputBorder, T.inputText, T.inputCursor = Color(18, 20, 28), Color(50, 55, 75), Color(210, 215, 230), Color(50, 100, 200, 150)

-- Window chrome
T.chromeHover = Color(255, 255, 255, 34)
T.chromeClose = Color(210, 60, 60, 225)
T.chromeInteractive = Color(60, 200, 120, 120)

-- Cursor-mode banner
T.hudBg, T.hudBorder, T.hudText = Color(0, 0, 0, 190), Color(60, 200, 120), Color(60, 230, 130)

-- Tabs of multi-tab windows; accent when a window has none of its own
T.groupAccent = Color(255, 200, 60)
T.tabActive, T.tabIdle = Color(40, 44, 52), Color(20, 22, 28)

-- Taskbar entries (the bar's own colours are settings)
T.taskbarBorder, T.taskbarEntry, T.taskbarEntryHover = Color(50, 55, 75, 180), Color(40, 44, 55, 200), Color(55, 65, 85, 230)

-- Dialogs, cards and list rows
T.popupBg, T.popupHeader, T.popupBorder = Color(22, 24, 32), Color(28, 30, 40), Color(60, 140, 255, 100)
T.card, T.cardHeader, T.rowHover = Color(40, 44, 52), Color(25, 28, 34), Color(50, 55, 65)
T.dangerBg, T.dangerHover, T.dangerText = Color(140, 35, 35), Color(180, 50, 50), Color(240, 200, 200)

-- Crop editor
T.cropShade = Color(0, 0, 0, 160)

-- Keyboard navigation: window focus, focus inside a window, the focused control, a control being adjusted
T.focusRing, T.navRing, T.navElement, T.navSelected = Color(90, 200, 255), Color(255, 50, 50), Color(0, 200, 255), Color(0, 255, 0)
T.hintBg, T.hintText = Color(150, 30, 30, 235), Color(255, 225, 225)

-- Icon materials are made once per path and never while painting (G29).
local icons = {}
function T.Icon(path)
	icons[path] = icons[path] or Material(path)
	return icons[path]
end

-- Command palette
T.paletteSelected, T.paletteFooter = Color(42, 72, 116), Color(16, 18, 24)

T.FONT_BANNER = "PinnedPanels.Banner"
T.FONT_TASKBAR = "PinnedPanels.Taskbar"
T.FONT_PALETTE_ITEM = "PinnedPanels.PaletteItem"
T.FONT_PALETTE_SUB = "PinnedPanels.PaletteSub"
T.FONT_PALETTE_QUERY = "PinnedPanels.PaletteQuery"

hook.Add("PinnedPanelsLoaded", "PinnedPanels.Theme", function()
	surface.CreateFont(T.FONT_BANNER, { font = "DefaultBold", size = 14, weight = 600 })
	surface.CreateFont(T.FONT_TASKBAR, { font = "Tahoma", size = 13, weight = 500 })
	surface.CreateFont(T.FONT_PALETTE_ITEM, { font = "Roboto", size = 17, weight = 500 })
	surface.CreateFont(T.FONT_PALETTE_SUB, { font = "Roboto", size = 12, weight = 400 })
	surface.CreateFont(T.FONT_PALETTE_QUERY, { font = "Roboto", size = 20, weight = 400 })
end)
