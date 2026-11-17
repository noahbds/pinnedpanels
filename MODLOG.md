# MODLOG

## 2026-11-17: audit and API research
- Code audit written to `AUDIT.md` (Part 1). Nothing has been checked in game yet.
- Web research on GMod APIs and tooling is in `AUDIT.md`, Part 2, with source URLs, the queries used and how much to trust each source.
- Checked locally against `garrysmod/lua`:
  - `derma/init.lua`: the built-in Derma fonts use `extended=true` and DejaVu Sans on Linux.
  - `includes/extensions/client/panel.lua`: `GetSkin` falls back to the parent's skin, and `IsOurChild` is just `HasParent`.
- Still to check in game: the HUD panel's children, the addon fonts' non-Latin glyphs, and the P1–P4 timings.
