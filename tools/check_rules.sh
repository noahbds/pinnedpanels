#!/usr/bin/env bash
# Static checks for the plan's code rules (§24, §25, §8). Exits non-zero on any violation.
# The pattern checks are heuristics: they skip text after "--", so a "--" inside a string can hide a hit.
set -u
cd "$(dirname "$0")/.."

fail=0

# Every Lua file must parse as plain LuaJIT, so GMod-only syntax (continue, !=, &&, //) fails here (L27).
for f in $(find lua tools -name '*.lua' 2>/dev/null); do
	if ! err=$(luajit -bl "$f" 2>&1 >/dev/null); then
		echo "parse error: $err"
		fail=1
	fi
done

# rule <message> <awk regex> [the one file allowed to match]
# Use [(] and [.] instead of backslash escapes: awk -v rewrites backslashes.
rule() {
	local hits
	hits=$(find lua -name '*.lua' -print0 | xargs -0 awk -v re="$2" -v allow="${3:-}" '
		FILENAME == allow { nextfile }
		{ code = $0; sub(/--.*/, "", code); if (code ~ re) print "  " FILENAME ":" FNR ": " $0 }')
	if [ -n "$hits" ]; then
		echo "$1:"
		echo "$hits"
		fail=1
	fi
}

LIBS='(gui|vgui|input|surface|draw|render|hook|timer|net|util|file|spawnmenu|controlpanel|language|cvars|concommand|derma|list|cookie|engine|system|string|table|math|os|debug|game)'
GLOBALS='(DermaMenu|CloseDermaMenus|RegisterDermaMenuForClose|include|AddCSLuaFile|RunConsoleCommand)'

rule "timer.Simple outside Util.NextFrame (§24)" 'timer[.]Simple' lua/pinnedpanels/util.lua
rule "Think hook outside input.lua (§17)" 'hook[.]Add[(][ \t]*"Think"' lua/pinnedpanels/input.lua
rule "CurTime/FrameTime in UI code; use RealTime/RealFrameTime (G5)" '(^|[^A-Za-z0-9_])(CurTime|FrameTime)[(]'
rule "file.* outside storage.lua (§2)" '(^|[^A-Za-z0-9_.:])file[.][A-Za-z]' lua/pinnedpanels/storage.lua
rule "Cursor, key polling or bind hooks outside input.lua (§17)" 'gui[.]EnableScreenClicker|input[.]IsKeyDown|"CreateMove"|"PlayerBindPress"' lua/pinnedpanels/input.lua
rule "Global library patched outside Sources.WithControlPanelFallback (R5)" \
	"^[ \t]*((_G|$LIBS)[.][A-Za-z_]+|$GLOBALS)[ \t]*=[^=]|^[ \t]*function[ \t]+($LIBS[.:]|$GLOBALS[ \t]*[(])" lua/pinnedpanels/sources.lua
rule "util.Decompress without maxSize (R1, G36)" 'Decompress[(][^,()]*[)]'
rule "SetSkin (R10, G22)" 'SetSkin[(]'
rule "RunString/CompileString (R4)" '(^|[^A-Za-z0-9_])(RunString|RunStringEx|CompileString)[(]'

# Color(, Material( and surface.CreateFont( inside Paint/PaintOver/Think bodies and HUDPaint/Think hooks (G29).
# A body starts on a matching line and ends at an "end" with the same indentation; "-- cached-ok" justifies a line.
hot=$(find lua -name '*.lua' -print0 | xargs -0 awk '
	FNR == 1 { hot = 0 }
	{
		code = $0; sub(/--.*/, "", code)
		bad = code ~ /(^|[^A-Za-z0-9_])(Color|Material)[(]|surface[.]CreateFont[(]/ && $0 !~ /cached-ok/
		if (!hot && code ~ /function[ \t]+[A-Za-z0-9_.:]*[.:](Paint|PaintOver|Think)[ \t]*[(]|[.:](Paint|PaintOver|Think)[ \t]*=[ \t]*function|hook[.]Add[(][ \t]*"(HUDPaint|Think)"/) {
			if (bad) print "  " FILENAME ":" FNR ": " $0
			if (code ~ /[ \t)]end[) \t]*$/) next
			match($0, /^[ \t]*/); indent = substr($0, 1, RLENGTH); hot = 1; next
		}
		if (hot && $0 ~ ("^" indent "end")) { hot = 0; next }
		if (hot && bad) print "  " FILENAME ":" FNR ": " $0
	}')
if [ -n "$hot" ]; then
	echo "Color(/Material(/CreateFont( in a hot path; cache it or mark -- cached-ok (G29):"
	echo "$hot"
	fail=1
fi

# .properties files must start with an empty line (G39).
for f in $(find resource -name '*.properties' 2>/dev/null); do
	if [ -n "$(head -n 1 "$f" | tr -d '\r')" ]; then
		echo "first line not empty: $f"
		fail=1
	fi
done

if [ "$fail" -eq 0 ]; then
	echo "check_rules: ok"
fi
exit "$fail"
