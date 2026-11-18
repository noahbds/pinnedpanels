# MODLOG

## 2026-11-17: audit and API research
- Code audit written to `AUDIT.md` (Part 1). Nothing has been checked in game yet.
- Web research on GMod APIs and tooling is in `AUDIT.md`, Part 2, with source URLs, the queries used and how much to trust each source.
- Checked locally against `garrysmod/lua`:
  - `derma/init.lua`: the built-in Derma fonts use `extended=true` and DejaVu Sans on Linux.
  - `includes/extensions/client/panel.lua`: `GetSkin` falls back to the parent's skin, and `IsOurChild` is just `HasParent`.
- Still to check in game: the HUD panel's children, the addon fonts' non-Latin glyphs, and the P1–P4 timings.

## 2026-11-17: review of popular addons and feature ideas
- Read source from wiremod/wire, CapsAdmin/pac3, StarfallEx, ULX/XGUI, EasyChat and pixel-ui (fetched with `gh api` into the session scratchpad, read only), plus the local stock Derma code (`dframe.lua`, `dragdrop.lua`, `animation.lua`).
- Findings and feature list F1–F23 are in `AUDIT.md`, Part 3.
- Main leads:
  - `SetWorldClicker` on the world panel, used by E2 and Starfall, to click the world while in cursor mode (F1).
  - Stock Derma drag and drop for tabs (F2).
  - DFrame's `GetMinWidth/MinHeight` for embedded windows (F8).
  - Turning on "needs keyboard" automatically for non-DTextEntry editors (F13).
  - "Only with the tool gun" (F21).
  - PIXEL-style scaling and fonts (F17).
- ULX's `xgui.anchor` show/hide supports audit bug B5.
- Not checked in game yet: F1 (do our windows still take their own clicks while the world clicker is on?) and F13 (typing into the E2 editor once pinned).

## 2026-11-17: local repo folder
- `/Users/noah/vehicule_addon/` has 29 cloned GMod repos, and the user said more can be cloned there. Grepped it for prior art; results are in the addendum to AUDIT.md Part 3.
- TTT2's HUD editor gives Shift modifiers and per-element minimum sizes (F3/F6). TTT2's `appearance` library is the model for the scale setting (F17). gPhone and helix show the drag-and-drop `Receiver` hover and drop pattern (F2).
- Wire and pac3 both toggle the world panel's world clicker, so F1 must only turn it off when it was the one that turned it on.

## 2026-11-17: repos cloned for this audit
- Shallow clones in `/Users/noah/vehicule_addon/`: garrysmod, Falcos-Prop-protection, FreSpawnmenu, gm-mediaplayer, wire-extras, improved-stacker, annotations-gmod-glua-ls, gmod-annotations (the `gluals-annotations` branch), GLuaFixer, GLuaTest, Small-GLua-Things, cfc_glua_style_guidelines.
- New compatibility risk: FreSpawnmenu returns `false` from `OnSpawnMenuOpen`/`Close`, which can stop our hooks from running (C1).
- FPP's `AdminPanel` upvalue is a real target for B3.
- No deprecated API is used. The "deprecated getupvalue" comments are out of date.
- `Panel:IsWorldClicker` exists, which F1 needs.
- GLuaTest supports `clientside = true` cases.

## 2026-11-18: readability plan
- Wrote `READABILITY_PLAN.md`, following Rareload's `docs/architecture/READABILITY_AUDIT.md` from `ba4c92dd^`: naming dictionary, names with several meanings (`w`, `win`, `e`), verb clashes, removing spec codes, file splits, a safe order and what must not be renamed.
- It is meant to be applied after the in-game check and the bug fixes in AUDIT.md. Steps 1–6 can be checked with the linters alone; the file splits (step 7) need a game run.
