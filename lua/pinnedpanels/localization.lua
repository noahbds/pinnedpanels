-- ── Localization ─────────────────────────────────────────────────────────────
-- Lookup helpers for the strings defined in pinnedpanels/lang/<code>.lua.
--   PinnedPanels.L(key[, default])  → plain text
--   PinnedPanels.Lf(key, ...)       → string.format-style with arguments
--
-- The active language follows the gmod_language convar; region-suffixed codes
-- (es-ES, pt-BR, zh-CN) fall back to their base language table, and any missing
-- key falls back to English, then the supplied default, then the key itself.

PinnedPanels      = PinnedPanels or {}
PinnedPanels.Lang = PinnedPanels.Lang or {}

-- Resolve the active language from the gmod_language convar. The result is
-- cached against the raw convar string so L() stays cheap inside Paint hooks;
-- the cache refreshes automatically if the player changes language.
local cachedRaw, cachedLang

function PinnedPanels.ResolveLang()
	local cv  = GetConVar("gmod_language")
	local raw = cv and cv:GetString() or "en"
	if raw == cachedRaw and cachedLang and PinnedPanels.Lang[cachedLang] then
		return cachedLang
	end

	local lower = string.lower(raw)
	local resolved
	if PinnedPanels.Lang[lower] then
		resolved = lower
	else
		local base = string.match(lower, "^(%a+)")
		resolved = (base and PinnedPanels.Lang[base]) and base or "en"
	end

	cachedRaw, cachedLang = raw, resolved
	return resolved
end

function PinnedPanels.L(key, default)
	local en  = PinnedPanels.Lang["en"] or {}
	local tbl = PinnedPanels.Lang[PinnedPanels.ResolveLang()] or en
	return tbl[key] or en[key] or default or key
end

-- Format-string variant. Guarded so a bad %-specifier or argument-count mismatch
-- in any translation degrades to the raw template instead of erroring out the
-- calling UI/Paint code.
function PinnedPanels.Lf(key, ...)
	local str = PinnedPanels.L(key)
	local ok, res = pcall(string.format, str, ...)
	return ok and res or str
end
