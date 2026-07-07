PinnedPanels       = PinnedPanels or {}
PinnedPanels.C     = {}
local C            = PinnedPanels.C

-- ── Backgrounds ──────────────────────────────────────────────────────────────
C.bg               = Color(30, 32, 40, 255)
C.bgDark           = Color(24, 26, 32, 255)
C.bgDarker         = Color(20, 22, 28, 255)
C.bgCard           = Color(40, 44, 52, 255)
C.bgCardHdr        = Color(25, 28, 34, 255)
C.bgHeader         = Color(18, 20, 26, 255)
C.bgHeaderLine     = Color(35, 38, 46, 255)
C.bgHover          = Color(35, 38, 48, 255)
C.bgRowHov         = Color(50, 55, 65, 255)
C.bgIcon           = Color(30, 34, 42, 255)
C.bgPopup          = Color(22, 24, 32, 255)

-- ── Text ─────────────────────────────────────────────────────────────────────
C.textBright       = Color(240, 245, 255)
C.textTitle        = Color(200, 210, 225)
C.textLight        = Color(220, 225, 235)
C.textLbl          = Color(220, 225, 240)
C.textBody         = Color(150, 160, 175)
C.textMuted        = Color(110, 120, 135)
C.textSubtle       = Color(140, 150, 165)
C.textLabel        = Color(180, 190, 210)
C.textSearch       = Color(210, 215, 230)
C.textInfo         = Color(130, 140, 160)
C.textPin          = Color(100, 130, 180)

-- ── Accent ───────────────────────────────────────────────────────────────────
C.accent           = Color(60, 140, 255)
C.accentGreen      = Color(60, 200, 80)
C.accentFrame      = Color(130, 80, 220)
C.imGreenBorder    = Color(60, 200, 120, 120)

-- ── Errors ───────────────────────────────────────────────────────────────────
C.errorRed         = Color(220, 80, 80)
C.errorMuted       = Color(160, 80, 80)
C.mutedGray        = Color(120, 130, 145)

-- ── Pin-row state backgrounds ────────────────────────────────────────────────
C.pinBgOn          = Color(18, 48, 18, 220)
C.pinBgOff         = Color(26, 26, 40, 200)
C.pinBgOnHov       = Color(25, 65, 25)
C.pinBgOffHov      = Color(38, 38, 58)

-- ── Kind labels (frame / creation / tool) ────────────────────────────────────
C.kindFrame        = Color(160, 110, 220)
C.kindCreation     = Color(70, 185, 100)
C.kindTool         = Color(80, 140, 200)

-- ── Generic buttons ──────────────────────────────────────────────────────────
C.btnBg            = Color(55, 60, 70)
C.btnBgHov         = Color(70, 75, 85)
C.btnText          = Color(210, 220, 235)
C.btnOutline       = Color(22, 24, 32)

-- ── Focus / bring-to-front button ────────────────────────────────────────────
C.focusBg          = Color(55, 75, 100)
C.focusBgHov       = Color(70, 100, 130)
C.focusTxt         = Color(200, 220, 245)

-- ── Danger / unpin buttons (pinned list) ─────────────────────────────────────
C.dangerBg         = Color(140, 35, 35)
C.dangerBgHov      = Color(180, 50, 50)
C.dangerBorder     = Color(60, 20, 20)
C.dangerTxt        = Color(240, 200, 200)
C.unpinBg          = Color(160, 40, 40)
C.unpinBgHov       = Color(200, 60, 60)
C.unpinTxt         = Color(255, 220, 220)

-- ── Pin / unpin toggle buttons (browser) ─────────────────────────────────────
C.pinBtnBg         = Color(35, 40, 55)
C.pinBtnBgHov      = Color(55, 65, 90)
C.pinBtnTxt        = Color(160, 175, 210)
C.pinBtnOut        = Color(50, 55, 80)
C.unpinBtnBg       = Color(30, 80, 30)
C.unpinBtnBgHov    = Color(50, 110, 50)
C.unpinBtnTxt      = Color(100, 230, 110)
C.unpinBtnOut      = Color(40, 120, 40)

-- ── Status dots ──────────────────────────────────────────────────────────────
C.dotOff           = Color(70, 75, 90)

-- ── Search box ───────────────────────────────────────────────────────────────
C.searchBg         = Color(18, 20, 28, 255)
C.searchBorder     = Color(50, 55, 75)
C.searchCursor     = Color(50, 100, 200, 150)

-- ── Interact-mode HUD ────────────────────────────────────────────────────────
C.hudBg            = Color(0, 0, 0, 190)
C.hudBorder        = Color(60, 200, 120)
C.hudText          = Color(60, 230, 130)

-- ── Keybind frame ────────────────────────────────────────────────────────────
C.bindBg           = Color(16, 16, 26, 255)
C.bindHeader       = Color(22, 22, 36, 255)
C.bindInstr        = Color(180, 195, 220)
C.bindBtnBg        = Color(25, 40, 75)
C.bindBtnBgHov     = Color(40, 60, 100)
C.bindTxtFocus     = Color(120, 255, 120)
C.bindTxtNorm      = Color(180, 210, 255)

-- ── Key display ──────────────────────────────────────────────────────────────
C.keyBound         = Color(80, 210, 120)

-- ── Settings ─────────────────────────────────────────────────────────────────
C.swatchBorder     = Color(80, 85, 100)

-- ── Layout editor ────────────────────────────────────────────────────────────
C.canvasBg         = Color(8, 8, 16, 255)
C.canvasScreen     = Color(20, 20, 34)
C.canvasBorder     = Color(50, 80, 140)
C.canvasLabel      = Color(60, 80, 130)
C.boxShadow        = Color(0, 0, 0, 100)
C.boxCoords        = Color(255, 255, 255, 80)
C.emptyText        = Color(80, 90, 110)
C.snapGuide        = Color(255, 200, 60, 180)

-- ── Group system ─────────────────────────────────────────────────────────────
C.groupBorder      = Color(255, 200, 60, 200)
C.groupBadgeBg     = Color(0, 0, 0, 160)
C.groupBadgeText   = Color(255, 220, 100)

-- ── Color changer popup ──────────────────────────────────────────────────────
C.colorPopupBg     = Color(20, 22, 30, 255)
C.colorPopupHdr    = Color(28, 30, 40, 255)
C.colorPopupBorder = Color(60, 140, 255, 100)

-- ── Lock indicator ───────────────────────────────────────────────────────────
C.lockIcon         = Color(255, 180, 60, 200)

-- ── Preview hint ─────────────────────────────────────────────────────────────
C._previewHint     = Color(0, 0, 0, 120)

-- ── Localization ─────────────────────────────────────────────────────────────
PinnedPanels.Lang = PinnedPanels.Lang or {
	["en"] = {
		["no_pinned"]      = "No Pinned Panels",
		["no_pinned_desc"] = "You have no valid pinned panels right now.",
		["no_pinned_hint"] = "Pin tools from the 'Tools' tab, or content browsers from the 'Content' tab.",
		["rename_title"]   = "Rename Panel",
		["rename_desc"]    = "Enter a custom name for this pinned panel:",
		["no_tools"]       = "No tools found.",
	}
}

function PinnedPanels.L(key, default)
	local lang = GetConVar("gmod_language") and GetConVar("gmod_language"):GetString() or "en"
	local tbl = PinnedPanels.Lang[lang] or PinnedPanels.Lang["en"]
	return tbl[key] or default or key
end
