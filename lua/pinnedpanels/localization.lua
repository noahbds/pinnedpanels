-- ── Localization ─────────────────────────────────────────────────────────────

PinnedPanels      = PinnedPanels or {}
PinnedPanels.Lang = PinnedPanels.Lang or {}
local cachedRaw, cachedLang

function PinnedPanels.ResolveLang()
	local override = PinnedPanels.Settings and PinnedPanels.Settings.language
	local raw
	if isstring(override) and override ~= "" then
		raw = override
	else
		local cv = GetConVar("gmod_language")
		raw = cv and cv:GetString() or "en"
	end
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

function PinnedPanels.SetLanguage(code)
	PinnedPanels.Settings = PinnedPanels.Settings or {}
	PinnedPanels.Settings.language = code
	cachedRaw, cachedLang = nil, nil
	if PinnedPanels.SaveSettings then PinnedPanels.SaveSettings() end
	hook.Run("PinnedPanels_LanguageChanged", code)
end

function PinnedPanels.Lf(key, ...)
	local str = PinnedPanels.L(key)
	local ok, res = pcall(string.format, str, ...)
	return ok and res or str
end
