# Pinned Panels v2 — Full Rewrite Plan

> **Status:** proposal (rev. 2) · **Work branch:** `PinnedPanels_Rewrite_Branch` · **Baseline:** v1 (`origin/main` @ `5b6def9`)
> **End state:** v1 archived on `legacy/v1` (tag `1.0.0`); v2 merged into `main` and becomes the only version.
>
> **What this addon is:** a **client-only** Derma UI addon. It floats spawn-menu tool panels and content tabs on the HUD, with a taskbar, groups, crop, keyboard navigation, a command palette and a layout editor. There is no gameplay code, no networking and no server logic. The server's only job is `AddCSLuaFile`, because the client can't `include` files that weren't sent (G1).
>
> **No backward compatibility (D1, confirmed in Phase 0).** v2 does not read `pinnedpanels_save.json` / `pinnedpanels_settings.json` or keep v1 convar and command names.
>
> **Sources:** all 44 v1 Lua files (code and translations) and the 35-commit history; the [GMod wiki](https://wiki.facepunch.com/gmod/); and the GMod base Lua source ([Facepunch/garrysmod](https://github.com/Facepunch/garrysmod)) wherever the wiki is silent: spawn-menu build order, `ControlPanel`, `DMenu`, `DBinder`, `DTextEntry`, skins, `hook` (§5.2).
>
> **Goal:** rebuild Pinned Panels from scratch with **every v1 feature**, structured the way a GMod UI addon should be: **registered Derma controls**, **one layout document**, **one input dispatcher**, and **one action list**. It should not lose data, patch globals or depend on timing guesses.

---

## Contents

**Part I — Context**
0. [How to use this document](#0-how-to-use-this-document)
1. [TL;DR](#1-tldr)
2. [Goals, non-goals, success metrics](#2-goals-non-goals-success-metrics)
3. [Branch & release strategy](#3-branch--release-strategy)
4. [Audit of v1](#4-audit-of-v1)
5. [Lessons learned](#5-lessons-learned)

**Part II — Requirements**
6. [Feature parity inventory](#6-feature-parity-inventory)
7. [Edge cases](#7-edge-cases)
8. [Being a good guest](#8-being-a-good-guest)
9. [Performance budgets](#9-performance-budgets)

**Part III — Design**
10. [Architecture](#10-architecture)
11. [File tree & line budgets](#11-file-tree--line-budgets)
12. [Old → new file mapping](#12-old--new-file-mapping)
13. [The layout document](#13-the-layout-document)
14. [Sources: tools and content tabs](#14-sources-tools-and-content-tabs)
15. [Windows (Derma controls)](#15-windows-derma-controls)
16. [Desktop: records → panels](#16-desktop-records--panels)
17. [Input](#17-input)
18. [Actions](#18-actions)
19. [Keyboard navigation](#19-keyboard-navigation)
20. [The hub, taskbar, palette and HUD](#20-the-hub-taskbar-palette-and-hud)
21. [Settings](#21-settings)
22. [Theme](#22-theme)
23. [Localization](#23-localization)

**Part IV — Execution**
24. [Coding conventions](#24-coding-conventions)
25. [Tooling](#25-tooling)
26. [Roadmap](#26-roadmap)
27. [Definition of done](#27-definition-of-done)
28. [Testing strategy](#28-testing-strategy)
29. [Risks & mitigations](#29-risks--mitigations)
30. [v1 bugs not to carry over](#30-v1-bugs-not-to-carry-over)
31. [Open decisions](#31-open-decisions)

**Part V — Future**
32. [Future features](#32-future-features)
33. [Pinning any panel from the game or from Workshop addons](#33-pinning-any-panel-from-the-game-or-from-workshop-addons)

**Appendices:** [A. Events & hooks](#appendix-a--events--hooks) · [B. Glossary](#appendix-b--glossary)

---

# Part I — Context

## 0. How to use this document

- **Sections 6–9 are the requirements.** Nothing is "done" until it meets them.
- **Sections 10–23 are the design.** If the code has to differ, update this document in the same commit and note it under the phase (§26). The plan and the code must never disagree.
- **Section 26 is the work queue.** Each checkbox is roughly one commit.
- IDs are stable so commits can cite them: **F**-features (§6), **E**-edge cases (§7), **R**-good-guest rules (§8), **L**-lessons from v1 history (§5.1), **G**-platform facts (§5.2), **B**-v1 bugs (§30), **D**-decisions (§31).
- Commit messages reference IDs, e.g. `Add crop editor (F16, L15, L22)`.
- **⚑ verify** marks a platform behaviour that neither the wiki nor the base source settles. Each has a 5-minute in-game check in Phase 0 (§26).

## 1. TL;DR

| | v1 (today) | v2 (target) |
|---|---|---|
| Code structure | closures on `vgui.Create("DPanel")` with overridden `Paint`/`Think`, shared through 97 `PinnedPanels.*` functions and 12 underscore "private" fields | **registered Derma controls** (`vgui.Register`) with their own `PANEL` tables, plus a handful of plain modules |
| Kinds of pinned thing | 4 (`tool`, `creation`, `frame`, `group`), with `pin.kind` checks in 15 files | **1**: a *window* holding 1..N *tabs*; a group is a window with more than one tab (D2) |
| Panels per grouped item | the group frame **plus a hidden full frame per member** | the group window only |
| Source of truth | live panels plus two JSON files, re-read on every pin | **one layout document** in memory, written debounced and atomically |
| Readiness | `Think` until `spawnmenu.GetTools()` is truthy (it always is, G12) → `timer.Simple(1)` | the spawn menu's own `PostReloadToolsMenu` event (G11) |
| Ordering | 12 `timer.Simple` guesses (`0`–`1 s`) | Derma's own `PerformLayout`/`InvalidateLayout`, one-frame deferral only |
| Menus | DMenu for mouse; a keyboard replica fed by scraping a hidden DMenu while `DermaMenu`, `vgui.Create`, `gui.MouseX/Y` are patched | **one action list** → real `DMenu`s, driven by mouse or keyboard (G17) |
| Input | 7 `Think` hooks, each with its own key polling | **1** dispatcher |
| Keyboard focus for text fields | per-window `Think` enabling keyboard input whenever a text box is *hovered* | the stock `OnTextEntryGetFocus`/`LoseFocus` hooks, as the spawn menu does (G20) |
| Time source for UI | `CurTime`/`FrameTime` (freeze on pause, scale with `host_timescale`) | `RealTime`/`RealFrameTime` (G5) |
| Settings | a JSON file with hand-written load/clamp/save per field + 17 loose key convars | **client convars** declared once, bound straight to controls (D3) |
| Lua files / lines (excl. translations) | 35 / ~9,170 | **24 / ~6,700** |

The ideas that do most of the work:

1. **Controls, not closures.** Every visual element is a registered Derma control whose lifecycle (`Init`, `PerformLayout`, `Paint`, `Think`, `OnRemove`) replaces v1's timers, per-row hooks and hand cleanup.
2. **Windows hold tabs.** Tools, content tabs and groups stop being different things (§13).
3. **One document, one writer.** `Layout` owns the document. Controls report gestures, `Layout` changes the data, and one coalesced event updates every view. Tabs whose tool isn't loaded stay *dormant* instead of being deleted (B1).
4. **One action list.** The right-click menu, taskbar menu, keyboard menu, palette, key bindings and console commands are all generated from it (§18).
5. **Use what GMod already provides.** `PostReloadToolsMenu` for readiness, `OnTextEntryGetFocus` for keyboard focus, `DBinder` for key capture, convar-bound controls for settings, `DCollapsibleCategory` cookies for collapse memory, `DScrollPanel:ScrollToChild`, `SetClipboardText`, and `.properties` translations.

## 2. Goals, non-goals, success metrics

### Goals
- **100% parity** with v1 (§6). A feature can only disappear through a decision in §31 (so far: the unreachable "pin a live frame", D7, and the in-addon language override, D5).
- **Never lose a layout** (B1, B2, E1, E6).
- **Be a good guest** in other people's games (§8): no global patching, no keys taken unless used, no movement blocked by hovering a text box, no disk churn.
- **Behave the same in singleplayer, when paused, and under `host_timescale`** (G5, B28).
- **Readable**: no file over ~500 lines, one control or concern per file.

### Non-goals
- New features during the rewrite; add them to Future features (§32). The only additions are small fixes for platform limits found in research: a "Rebuild content" action (E10) and restoring the cursor position like GMod's own menus (D16, optional).
- A visual redesign: keep the v1 look.
- Server-side features or networking of any kind.
- Compatibility with v1 data, convars or commands (D1).

### Success metrics (checked in Phase 7)
- [ ] Every F-item passes the manual matrix (§28.2).
- [ ] Every L- and G-item has a named test, matrix row or rule check.
- [ ] `grep -rn "timer.Simple" lua` → only inside `Util.NextFrame`.
- [ ] `grep -rn 'hook.Add( *"Think"' lua` → 1 match (`input.lua`).
- [ ] `grep -rnE "\b(CurTime|FrameTime)\(" lua` → 0 matches (G5).
- [ ] `file.*` only in `storage.lua`; `gui.EnableScreenClicker`, `input.IsKeyDown`, `CreateMove`, `PlayerBindPress` only in `input.lua`.
- [ ] No assignment to a global library field outside `Sources.WithControlPanelFallback` (§14.3).
- [ ] A corrupt layout file, a decompression-bomb import and a layout naming 20 missing tools all leave the layout intact (E6, E7, E1).
- [ ] Every budget in §9 is met on the reference scene.

---

## 3. Branch & release strategy

### 3.1 Current state (verified 2026-09-30)

| Ref | Commit | Notes |
|---|---|---|
| `origin/main` = local `main` | `5b6def9` "Add HTML keyboard scrolling and browser headers" | last v1 commit; untracked `.DS_Store` |
| `feature/localization` | `896bc58` | an ancestor of `main`, already merged |
| tags | none | v1 has no version constant or tag |

`.gitignore` lists `.vscode/settings.json`, but the file is tracked anyway; `.vscode/launch.json` also has a server attach config that a client addon doesn't need.

### 3.2 Steps

**Phase 0:**
1. `git branch legacy/v1 5b6def9 && git push -u origin legacy/v1`; `git tag -a 1.0.0 5b6def9 -m "Final v1 release" && git push origin 1.0.0`; protect `legacy/v1` on GitHub. (`5b6def9`, not `main`: `main` already carries the plan commit `04a8496`.)
2. `git switch -c PinnedPanels_Rewrite_Branch main`; commit this plan.
3. `git branch -d feature/localization`.
4. `.gitignore`: add `**/.DS_Store`; either stop tracking `.vscode/settings.json` or drop it from `.gitignore`.
5. First code commit: "Remove v1 tree, add v2 skeleton".

**During development:** commit to the rewrite branch; `main` gets nothing but the final merge. Pre-release tags: `2.0.0-alpha.N` (Phase 3), `2.0.0-beta.N` (Phase 5), `2.0.0-rc.N` (Phase 7).

**Cutover:** every §2 metric ticked; one long building session in singleplayer and one on a multiplayer server with rc; merge PR "Pinned Panels v2" with a **merge commit**; tag `2.0.0`; update the Workshop item; add an "Archived" banner to `legacy/v1`'s README; delete the rewrite branch.

### 3.3 Release notes template (2.0.0)
- **Fresh start**: v2 doesn't read v1 layouts or settings (D1).
- **Renamed**: commands and convars now start with `pinnedpanels_` (D4), because `pp_` is GMod's post-processing namespace (G32).
- **Changed defaults**: arrow-key navigation runs only in cursor mode unless enabled everywhere (D8).
- **Language**: follows the game language (D5).
- **Fixed**: panels no longer disappear after playing once without an addon (B1); a damaged save no longer wipes the layout (B2); hovering a text box no longer stops you walking (B32); key repeat and animations work while paused or in slow motion (B28).

---

## 4. Audit of v1

### 4.1 Size by area

| Area | Files | Lines | Notes |
|---|---:|---:|---|
| Windows & pins (`frame`, `pin`, `groups`, `crop`, `autosize`, `content_tools`, `popups`, `context_menu`) | 8 | 2,997 | the pin/group split causes most special cases |
| Screens (client autorun tab, `browser`, `creation_browser`, `pinned_list`, `layout_editor`, `settings/*`) | 8 | 2,462 | every row hand-built and hand-painted |
| Keyboard navigation (`keyboard/*`) | 8 | 1,652 | includes a replica menu renderer and a DMenu scraper |
| Features (`cursor_mode`, `taskbar`, `command_palette`, `actions`) | 4 | 1,278 | each polls its own keys |
| Infra (`core`, `persistence`, `helpers`, `colors`, `localization`, `filelist`, server autorun) | 7 | 776 | |
| Translations (`lang/*`, 9 languages × 263 keys) | 9 | ~2,680 | format specifiers consistent in every language; 4 keys missing from the 8 non-English files (B25); a few identical-to-English values are legitimate (`Action`, `Accent`) |
| **Total** | **44** | **11,846** | ~9,170 excluding translations |

### 4.2 Structural problems

1. **Closure-built UI.** Nearly every visual piece is a `vgui.Create("DPanel")` with `Paint`, `Think` and `OnMousePressed` assigned inline, sharing state through upvalues. There's no `PerformLayout` anywhere in the addon, so layout "settles" on timers (`0.2/0.25/0.35/0.5 s`).
2. **Four pin kinds.** `tool`, `creation`, `frame`, `group` — `pin.kind` checks in 15 files; `frame` is unreachable (B16).
3. **Groups on top of pins.** A grouped panel keeps its own hidden `DFrame` while its content is moved into the group's `DPropertySheet` (`StowContent`); every membership change destroys and rebuilds the group frame, then re-applies per-tab size and crop on timers.
4. **No single source of truth.** Live panels hold state (`pin.crop`, `pin.maximized`, `pin.tabSizes`…); `pinnedpanels_save.json` holds geometry; `pinnedpanels_settings.json` holds groups and quick slots. `Pin()` re-reads the save file per pin; `Save()` is called from 36 places.
5. **Monkeypatching**: `ThrottleScroll` replaces `InvalidateLayout`; tool population replaces `controlpanel.Get` and re-fires `PostReloadToolsMenu`; keyboard menus replace `DermaMenu`, `vgui.Create`, `gui.MouseX`, `gui.MouseY` (B4–B6).
6. **Input in 7 places**, each with its own edge detection and its own idea of "is the player typing", none aware of chat, console, escape menu or window focus.
7. **Three menu implementations** (mouse DMenu, keyboard replica, taskbar DMenu).
8. **Load-order anxiety**: 57 `if PinnedPanels.X then` checks.
9. **Colours**: 90+ named colours plus 185 inline `Color(...)` calls, many inside `Paint`.
10. **Settings written 4 times each** (default, save, load/clamp, UI row).

---

## 5. Lessons learned

### 5.1 From v1's git history

| ID | Lesson (source commit) | v2 answer |
|---|---|---|
| L1 | Pin buttons showed stale state because it was computed when the row was built (`03fa74e`) | Controls read the document when painting or on `Changed`; no state captured in closures |
| L2 | Some tools add nothing when their `CPanelFunction` runs; their panel is filled through `controlpanel.Get(name)` by hooks (`03fa74e`) | Kept as an isolated fallback with guaranteed restore (§14.3) |
| L3 | Scroll throttling had to wait 0.2 s for layouts to settle (`03fa74e`) | Trailing-edge throttle inside the tab host control; no timers (B6) |
| L4 | One `StateChanged` hook per browser row leaked and was slow (`ab7f807`) | One listener per control, with the control as hook identifier (G31) |
| L5 | Clamping every frame in `Think` was wasted work (`ab7f807`) | Clamp on geometry changes only |
| L6 | Per-tab sizes applied unreliably on rebuild and tab change (`ab7f807`) | Size and crop are tab fields, applied by the window on activation |
| L7 | Groups and frames had to be prevented from joining groups (`ab7f807`) | Structurally impossible (§13) |
| L8 | The cursor-mode banner was moved to a render target for speed (`ab7f807`) | Cached text + one pre-made font; no RT for one line of text (G29) |
| L9 | Keyboard menus scraped a hidden DMenu that must never show (`f383f31`) | Keyboard drives a real DMenu (§19.5, G17) |
| L10 | Many fixes for focus recovery, taskbar handoff and key repeat (`f383f31`, `0376917`) | One explicit state machine (§19.1), transitions tested |
| L11 | Windows must stay opaque while keyboard-navigated (`f383f31`) | Opacity rule (§16.3) |
| L12 | Placement and resizing must avoid the taskbar (`f8bfd5f`) | One `Geom.Usable()` everywhere |
| L13 | Renaming "interact" → "cursor mode" renamed persisted keys (`7e3887c`) | Names fixed before 2.0.0 |
| L14 | Spatial nav skipped nearby controls; overlapping candidates must rank by edge gap (`a21851f`) | Pure `Nav.Rank` with fixture tests (§19.3) |
| L15 | Cropped-away controls must not be navigable (`a21851f`) | Scan filters by the tab's clip rect |
| L16 | Click-through needs a way back: ALT, and the palette (`a21851f`, `c89133a`) | Kept (F11) |
| L17 | `keyboard.lua` and `settings_tab.lua` grew into monoliths (`9819a4f`, `a21851f`) | One control or concern per file |
| L18 | Region codes fall back to base language; missing keys to English; bad format strings must not error (`cb8b2a2`) | `.properties` fallback + guarded `L()` (§23) |
| L19 | Custom titles survive language changes; default titles re-localize (`e1673ae`) | A tab stores `title` only when renamed |
| L20 | HTML panels are recognized by `QueueJavascript` + `OnDocumentReady`, not `RunJavascript` (every panel has it) (`5b6def9`) | HTML control adapter |
| L21 | DTree leaves must not swallow left/right (`5b6def9`) | Tree adapter |
| L22 | The crop viewport must not take mouse input; the content must (`5b6def9`) | Tab host's clip panel created that way once |
| L23 | New windows spawned on top of each other (`659bf81`) | `Geom.FreeSpot` |
| L24 | Native DFrame drag/size fought the overlays (`659bf81`, `2e34d2f`) | The window control hit-tests itself; no overlay panels |
| L25 | Hooks keyed by `tostring(frame)` had to be removed by hand (`frame.lua`) | Controls as hook identifiers (G31) |
| L26 | The pinned list deleted "stale" pins and saved (`11d8634`) | Views never mutate the document |
| L27 | GMod's `continue` breaks `luac -p`/`luajit` checks on `pin.lua`, `pinned_list.lua` (project memory) | Plain Lua syntax only (§24) |
| L28 | Tools can be listed under several tabs; v1 dedupes by `ItemName` | Same in the catalogue |

### 5.2 Platform facts

**W** = GMod wiki, **S** = GMod base source (`Facepunch/garrysmod`, read 2026-09-30).

**Loading & realms**

| ID | Fact (source) | v2 impact |
|---|---|---|
| G1 | `lua/autorun/` and `lua/autorun/client/` are sent to clients automatically; any other file needs `AddCSLuaFile` or the client's `include` errors; each file ≤ 64 KB compressed; the Lua filesystem is shared by every addon (W `AddCSLuaFile`, `include`) | One shared `lua/autorun/pinnedpanels.lua`: server → `AddCSLuaFile` each file and return; client → `include`. Unique folder `pinnedpanels/` |
| G2 | Auto-refresh doesn't work on macOS or for dynamically included files (W `Auto_Refresh`) | `pinnedpanels_reload` re-runs the loader; every file reload-safe |
| G3 | `vgui.Register(name, PANEL, base)` registers a control (W `vgui.Register`); `Derma_Install_Convar_Functions(PANEL)` gives a control `SetConVar`/`ConVarChanged`/`ConVarNumberThink` (S `dbinder.lua`) | Every visual piece is a registered control; settings controls bind to convars the stock way |
| G4 | `PANEL:Think` runs every frame **only while visible**; `PANEL:OnScreenSizeChanged(oldW, oldH, newW, newH)` exists per panel (W) | Hidden/minimized windows cost nothing per frame; per-control resolution handling |

**Time**

| ID | Fact (source) | v2 impact |
|---|---|---|
| G5 | `CurTime` and `FrameTime` follow game time: they stop on pause and scale with `host_timescale`; `RealTime`/`RealFrameTime` don't and are "more suited for GUIs or HUDs" (W `CurTime`, `RealTime`, `FrameTime`) | UI timing (repeat, throttle, debounce, fades, pulses, idle timers) uses `RealTime`/`RealFrameTime` (B28) |

**Spawn menu & tool panels**

| ID | Fact (source) | v2 impact |
|---|---|---|
| G11 | The spawn menu is built on `OnGamemodeLoaded` and on `spawnmenu_reload`: `PreReloadToolsMenu` → `ClearToolMenus` → `AddToolMenuTabs` → categories → `PopulateToolMenu` → `SpawnMenu` created → `SpawnMenuCreated` → context menu → **`PostReloadToolsMenu`**. Changing `gmod_language` rebuilds it too (deferred until it's closed) (S `spawnmenu.lua`) | Catalogue ready = `PostReloadToolsMenu`; the hub tab is destroyed and rebuilt on every rebuild, so it must hold no state |
| G12 | `spawnmenu.GetTools()` returns the tab **array**, initially `{}` (never nil); each tab `{Name, Label, Icon, Items}`, each category `{ItemName, Text, [n] = tool}`, each tool `{ItemName, Text, Command, Controls, CPanelFunction}`; Utilities option pages are listed the same way (S `spawnmenu` module, W) | v1's readiness check (`if not spawnmenu.GetTools()`) never waits (B26); options pages are pinnable sources too |
| G13 | `spawnmenu.AddCreationTab(name, fn, icon, order, tooltip)`; `fn` runs lazily and returns a container, so each call builds a new, independent instance (W) | Content tabs are built per pinned tab, only when first shown |
| G14 | The spawn menu fills a tool panel with `controlpanel.Get(name)` (creates a hidden `ControlPanel` if missing, re-creates one marked for deletion) then `cp:FillViaTable{ Text, ControlPanelBuildFunction }`, which sets `Initialized`, the name, and calls the build function. `ControlPanel` derives from `DForm` (S `controlpanel` module, `controlpanel.lua`) | v2 builds its own `ControlPanel` the same way (`FillViaTable`), so pinned tools look like the spawn-menu ones |
| G15 | `TOOL:RebuildControlPanel(...)` clears and rebuilds **only** `controlpanel.Get(self.Mode)`, the spawn menu's copy (S `stool_cl.lua`) | A pinned copy of a tool that rebuilds its panel goes stale; v2 adds a "Rebuild content" action (E10, D17) |
| G16 | `spawnmenu.ActivateTool(name, noCommand)` runs the tool's `Command` (e.g. `gmod_tool weld`, which switches to the tool gun) unless `noCommand`, fills and shows the spawn menu's panel (S). The wiki's "menu only" wording is misleading | "Equip tool" is one call; v1's extra `gmod_toolmode` + `input.SelectWeapon` go away |
| G18 | Opening the context menu moves `spawnmenu.ActiveControlPanel()` into itself (S `contextmenu.lua`) | Never host the spawn menu's own panel instances — always build copies |

**Menus, focus, controls**

| ID | Fact (source) | v2 impact |
|---|---|---|
| G17 | `DMenu` has `GetChild(n)`, `ChildCount()`, `HighlightItem(item)`, `ClearHighlights()`, `OpenSubMenu(item, submenu)`, `CloseSubMenu()`; `AddOption` sets the option's `DoClick`; `DermaMenu()` closes other menus; every DMenu registers itself with the global `RegisterDermaMenuForClose`; a mouse press on any non-menu panel closes menus (`VGUIMousePressed` → `CloseDermaMenus`) (S `dmenu.lua`, `derma_menus.lua`) | The keyboard can drive a real DMenu: highlight, open submenus, `DoClick`. Finding a *foreign* menu opened by an element is ⚑ verify (§19.5) |
| G19 | `DBinder`: click → `input.StartKeyTrapping()`, `Think` → `input.CheckKeyTrapping()`, Escape cancels, right-click offers clear/reset to default, `SetConVar` binds it to a convar, `0` means none (S `dbinder.lua`, W `input.StartKeyTrapping`) | Key binding rows are `DBinder`s bound to our key convars, with a conflict check in `OnChange` |
| G20 | `DTextEntry` fires `OnTextEntryGetFocus` when clicked or focused and `OnTextEntryLoseFocus` when it loses focus; the spawn menu and context menu use exactly this to turn keyboard input on and off ("StartKeyFocus/EndKeyFocus") (S `dtextentry.lua`, `spawnmenu.lua`, W) | Windows take keyboard input only while one of their text entries has focus — not when one is merely hovered (B32) |
| G21 | `MakePopup` then `SetKeyboardInputEnabled(false)` gives a panel the mouse without blocking player movement; derive popups from `EditablePanel` (W `Panel:SetMouseInputEnabled`, `Panel:MakePopup`) | `PinnedPanelsWindow` derives from `EditablePanel` |
| G22 | `Panel:GetSkin()` inherits the **parent's** skin when a panel has none of its own (S `panel.lua`); `Panel:SetSkin` calls `derma.RefreshSkins()` for every panel (W) | Never set a skin on a window: hosted tool panels would inherit it. Our controls paint themselves from theme tokens (D6) |
| G23 | `DCollapsibleCategory:SetCookieName(name)` loads its open state from `cookie` and saves it on every toggle (S `dcategorycollapse.lua`, `panel.lua`) | Collapse memory is one `SetCookieName` per category (D14) |
| G24 | `DScrollPanel:ScrollToChild(panel)` animates a child into view (S `dscrollpanel.lua`) | Nav scroll-into-view |
| G25 | `PANEL:TestHover(x, y)` decides whether the cursor counts as over the panel; returning false makes that area ignore the mouse (W) | A click-through window can keep its header grabbable without v1's separate grip popup ⚑ verify for popups |
| G26 | `Panel:SetPopupStayAtBack(true)` keeps a popup from jumping in front when it gets focus (W) | Keep pinned windows behind the spawn menu, dialogs and DMenus ⚑ verify |
| G27 | `Panel:SetAlpha` multiplies children's alpha and doesn't block input (W) | Idle opacity is purely visual; interactivity is separate |
| G28 | `DisableClipping(bool)` returns the previous state (W) | Always restore it (B29) |
| G29 | `GetRenderTarget` sizes are powers of two and RTs are never garbage-collected; `Material()` is "very expensive" in render hooks; `surface.CreateFont` must be called once, for sizes actually used (W) | No RTs; materials and fonts cached at file level (B19, B23) |
| G30 | `GetHUDPanel()`: panels parented to it hide when the main menu opens (W). v1 calls `ParentToHUD()` **then** `MakePopup()` | Which wins for escape-menu visibility is ⚑ verify (E27) |
| G31 | `hook.Add` accepts any object with `IsValid` as identifier and drops it when invalid (S `hook.lua`, W) | All per-control listeners |

**Input**

| ID | Fact (source) | v2 impact |
|---|---|---|
| G6 | `PlayerBindPress` is **not called for F1–F12**, can be bypassed by `alias`, and movement binds need `CreateMove`/`StartCommand` (W) | Suppression can't stop an F-key's game bind; v1's default cursor key is F4 (B11). The binder warns |
| G7 | `PlayerButtonDown` isn't called on the client in singleplayer (predicted) nor while a keyboard-enabled panel is open (W) | Not usable for hotkeys; poll `input.IsKeyDown` once per frame |
| G8 | `gui.IsGameUIVisible()`, `gui.IsConsoleVisible()`, `system.HasFocus()`; `StartChat`/`FinishChat` bracket the chat box (W) | Hotkey gating (E13, E35) |
| G9 | `gui.EnableScreenClicker`: some `CUserCmd` values are wrong while it's on; the spawn/context menus use `RememberCursorPosition`/`RestoreCursorPosition` (W, S) | One cursor owner; optional cursor-position restore (D16) |
| G10 | `input.LookupKeyBinding(key)` → the key's game bind; `input.GetKeyName(key)` (W) | Conflict detection |

**Storage & strings**

| ID | Fact (source) | v2 impact |
|---|---|---|
| G32 | GMod's own post-processing convars use `pp_` (`pp_bloom`, `pp_colormod`, …); `concommand.Add` **silently fails** if the name exists (W `concommand.Add`, base game) | Prefix `pinnedpanels_` (D4, B18) |
| G33 | `CreateClientConVar(name, default, save, userinfo, help, min, max)` persists to `cfg/client.vdf` and clamps; `ConVar:SetString/SetInt` change Lua-created convars **immediately**; `RunConsoleCommand` may be blocked for some commands; `cvars.AddChangeCallback` doesn't fire for `FCVAR_REPLICATED` convars on the client (W) | Settings are archive-only client convars set with `ConVar:SetX` (v1 used `RunConsoleCommand` + a manual cache) |
| G34 | `file.Write`/`file.Rename` lowercase names, only allow some extensions (`.json`, `.txt`, `.dat`… not `.bak`/`.tmp`) and return a success bool (W) | `layout.json`, `layout_bak.json`, `layout_tmp.json`; every return checked |
| G35 | `util.JSONToTable(s, ignoreLimits, ignoreConversions)`: 15,000-key limit; numeric-string keys become numbers; `Color` loses its metatable. `util.TableToJSON` stringifies keys, so `[5]` and `["5"]` collide (W) | Arrays with `id` fields, colours as `[r,g,b,a]`, own file decoded with `ignoreLimits` |
| G36 | `util.Decompress(s, maxSize)` — always pass `maxSize` for user data (W) | Import cap (R1, B3) |
| G37 | `SetClipboardText` exists; there is no clipboard *read* (W) | Export copies straight to the clipboard; import needs a paste box |
| G38 | `ProtectedCall` runs a function without stopping and **still prints** the error; `pcall` swallows it (W) | Third-party builders run under `ProtectedCall`-style handling so errors show in console *and* in the tab |
| G39 | Localization: `resource/localization/<code>/<name>.properties`, first line empty, English loaded first as fallback, `#key` in Derma, `language.GetPhrase`; Workshop allows `lua/`, `resource/localization/`, `materials/`; `addon.json` `type` + up to two `tags`; icon 512×512 baseline JPEG (W `Addon_Localization`, `Workshop_Addon_Creation`) | §23, §25 |

---

# Part II — Requirements

## 6. Feature parity inventory

| # | Feature | v1 location | v2 owner |
|---|---|---|---|
| F1 | "Pinned Panels" spawn-menu creation tab: header (title, subtitle, window count), sub-tabs Tools, Content, Pinned, Layout, Settings | client autorun | `vgui/hub.lua` |
| F2 | Tools list: search, count, category headers, pin/unpin rows with status dot | `browser.lua` | `vgui/hub_catalog.lua` |
| F3 | Content list: creation tabs with icon, label, tooltip, pin/unpin | `creation_browser.lua` | `vgui/hub_catalog.lua` |
| F4 | Pinned list: windows with kind icon, minimized tag, show/hide/restore, bring to front, unpin; multi-tab windows expand to tabs with unpin / move out / move up / down; "add to window" | `pinned_list.lua` | `vgui/hub_pinned.lua` |
| F5 | Layout editor: scaled screen, box per visible window, drag + 8-way resize, snap guides, tab names and count badge, lock/cropped badges, coordinates, taskbar preview with minimized entries, right-click menu, live two-way sync | `layout_editor.lua` | `vgui/hub_layout.lua` |
| F6 | Settings: General, Controls, Appearance, Taskbar, Groups, Data | `settings/*` | `vgui/hub_settings.lua` |
| F7 | Pin a tool's (or Utilities option page's) control panel | `pin.lua`, `helpers.lua` | `sources.lua` |
| F8 | Pin a spawn-menu content tab | `pin.lua` | `sources.lua` |
| F9 | Window chrome: title + indicators (click-through, cropped), lock mark, minimize/maximize/close, drag by header, resize from 8 edges/corners, snap to screen edges/centre and other windows (ALT disables), clamp to usable area, per-window colours | `frame.lua` | `vgui/window.lua` |
| F10 | Cursor mode: toggle key, banner, windows interactive in cursor mode or while the spawn menu is open; idle opacity otherwise (global and per window) | `cursor_mode.lua` | `input.lua`, `desktop.lua`, `vgui/hud.lua` |
| F11 | Click-through windows, header stays grabbable, ALT to interact, palette entry to restore | `frame.lua`, `cursor_mode.lua` | `vgui/window.lua` |
| F12 | Maximize/restore within the usable area | `pin.lua` | `layout.lua` |
| F13 | Minimize; taskbar on any side with size, auto-hide, labels, colours, hover, click to restore, right-click menu, fade outside cursor mode, keyboard focus with tooltip | `taskbar.lua` | `vgui/taskbar.lua` |
| F14 | Window menu: equip tool, front, minimize, hide, auto-size, crop/edit/remove, colours, rename, quick key, filter bar, click-through, group submenu, opacity submenu (global/100/75/50/25/custom), lock, copy/paste geometry, unpin | `context_menu.lua` | `actions.lua` |
| F15 | Groups = multi-tab windows: merge, accent colours, per-tab size, per-tab crop, reorder, move out, dissolve, create named group | `groups.lua` | `layout.lua`, `vgui/tabs.lua` |
| F16 | Crop: editor (draw, move, handles, full, apply, cancel, right-click cancel), persisted, edge-resize adjusts crop, nav skips cropped-away controls | `crop.lua` | `vgui/crop_editor.lua`, `vgui/tabs.lua` |
| F17 | Auto-size (natural width and height, animated), per tab, "auto-size all" | `autosize.lua` | `vgui/tabs.lua` |
| F18 | Auto-arrange | `actions.lua` | `layout.lua` |
| F19 | Filter bar for a tool panel's controls | `content_tools.lua` | `vgui/tabs.lua` |
| F20 | Collapse memory for categories | `content_tools.lua` | `vgui/tabs.lua` (cookies, D14) |
| F21 | Quick keys toggling one window | `actions.lua` | `input.lua` |
| F22 | Peek (hold to show everything) | `actions.lua` | `input.lua`, `desktop.lua` |
| F23 | Command palette | `command_palette.lua` | `vgui/palette.lua` |
| F24 | Reopen recently closed (15, session-only) | `pin.lua` | `layout.lua` |
| F25 | Keyboard navigation (window focus incl. taskbar, tabs, content nav, spatial moves, value adjustment for sliders/checkboxes/combos/colour controls, activation, HTML scroll, hints, memory, repeat, element menu, window menu, popup nav, nav opacity, suppression, optional outside cursor mode) | `keyboard/*` | `nav.lua`, `nav_controls.lua` |
| F26 | Rebindable keys with conflict detection | `keyboard/keybinds.lua`, `cursor_mode.lua` | `actions.lua`, `vgui/controls.lua` |
| F27 | Rename (custom title survives language changes) | `popups.lua` | `layout.lua` |
| F28 | Lock | `context_menu.lua` | `layout.lua` |
| F29 | Copy/paste geometry | `context_menu.lua` | `actions.lua` |
| F30 | Export/import layout string | `persistence.lua` | `storage.lua` |
| F31 | Persistence: auto-restore on join (setting), resolution-independent geometry, all per-window state | `persistence.lua`, `core.lua` | `storage.lua`, `layout.lua` |
| F32 | Resolution changes | `core.lua` | `layout.lua` |
| F33 | 9 languages, live refresh including spawn-tab name and default titles | `localization.lua`, `lang/*` | `.properties` (D5) |
| F34 | Console: clear, list, reload, arrange, reopen, auto-size all, palette | autorun, `actions.lua`, … | `actions.lua` (§18.3) |
| F35 | Equip tool gun for a tool window | `context_menu.lua` | `sources.lua` (G16) |
| F36 | Free-spot placement | `frame.lua` | `util.lua` |
| F37 | Typing into text fields inside windows | `frame.lua` | `input.lua` (G20) |
| F38 | ~~Pin an arbitrary live `DFrame`~~ (v1 code, never reachable and never working) | `pin.lua` | **replaced** by §33 (D7, D19, B16) |
| F39 | ~~In-addon language override~~ | `localization.lua` | **dropped** (D5) |

---

## 7. Edge cases

| ID | Scenario | Expected |
|---|---|---|
| E1 | A saved tab's tool/content tab comes from an addon that's now disabled | The tab is **dormant**: kept in the file, greyed in the Pinned list, restored when the addon returns. Never deleted by a save (B1) |
| E2 | Addon loads before the spawn menu is built, or after it (dev reload) | Restore runs on the first `PostReloadToolsMenu`, or immediately if `g_SpawnMenu` is already valid (G11) |
| E3 | Resolution, window mode or MSAA changes | Every stored rectangle (position, size, crop base, per-tab sizes, maximize restore bounds) is rescaled once, then clamped (B17) |
| E4 | Layout made on a bigger screen | Windows shrink to fit the usable area; positions clamp |
| E5 | Taskbar side, size or auto-hide changes | Usable area changes; maximized windows refit, others re-clamp |
| E6 | Layout file corrupt or hand-edited into invalid JSON | Load `layout_bak.json`; else quarantine as `layout_corrupt_<time>.json`, start empty, show a notification, never overwrite the corrupt file (B2) |
| E7 | Import string that's empty, not Base64, not compressed, a decompression bomb, > 15,000 keys, wrong types, unknown sources, 500 windows, or a v1 string | Rejected with a reason, or accepted after sanitizing with a summary ("12 windows, 2 unavailable"); applied only after confirmation, with the current layout backed up (R1–R3, B3) |
| E8 | A tool's build function or a content tab's builder errors | That tab shows the error; the console shows it too (G38); everything else works |
| E9 | A tool fills its panel only through `controlpanel.Get` in a hook | Fallback (§14.3) |
| E10 | A tool rebuilds its panel with `RebuildControlPanel` (G15) | The pinned copy doesn't follow automatically; "Rebuild content" on the tab rebuilds it |
| E11 | Language change | Spawn menu rebuilds itself (G11); our hub is rebuilt with it; default titles, menus, settings, palette refresh; custom titles unchanged (L19) |
| E12 | `spawnmenu_reload` | Catalogue refreshes on `PostReloadToolsMenu`; pinned content keeps working (convars are shared with the spawn-menu copies) |
| E13 | Chat, console or escape menu open | No hotkey fires, nothing suppressed (G8) |
| E14 | Mouse **hovering** a text box inside a window while walking in cursor mode | Movement keys still work; the window only takes the keyboard once the box is clicked/focused (G20, B32) |
| E15 | Binding an action to F1–F12 that has a game bind | Binder warns the game bind still runs (G6) |
| E16 | Spawn menu opens during cursor mode | Windows stay interactive; cursor mode resumes after |
| E17 | Click-through window + ALT | Interactive while ALT is held; header draggable without ALT |
| E18 | Locked window | No drag, resize, maximize, arrange or paste-geometry; auto-size may change size only |
| E19 | Content shrinks under a crop | Insets clamp so ≥ 40 px stay visible |
| E20 | Last-but-one tab moved out of a group | Window stays, now single-tab, no rebuild |
| E21 | Unpinning a multi-tab window | One "recently closed" entry restores the whole window (B20) |
| E22 | Pinning something already pinned | Existing window comes to front, restoring if minimized |
| E23 | Minimize with the taskbar disabled | Window minimizes; restorable from the Pinned list, palette, quick key; a one-time notification says where (B15) |
| E24 | 50 windows, 10 multi-tab | §9 budgets hold; inactive tabs not built until shown |
| E25 | `pinnedpanels_reload` | All windows rebuild from the document; no duplicate hooks, panels or timers |
| E26 | HTML content (Dupes, Saves tabs) | Keyboard scrolls it (L20) |
| E27 | Escape menu open | Windows hidden, or at least non-interactive ⚑ verify (G30) |
| E28 | Restoring a maximized cropped window | Crop comes back (B27) |
| E29 | Keyboard menu on an element whose right-click handler errors | Error shown once; no global stays patched (B4) |
| E30 | Key conflicts between any two bindings or quick keys | Listed before saving |
| E31 | Palette, cursor mode and another addon all want the cursor | One owner keeps a reason set; never turns off a cursor it didn't turn on |
| E32 | Singleplayer pause/unpause | No stuck keys, repeat and animations keep working (G5, B28) |
| E33 | Rename a group then add a tab | Name persists (B8) |
| E34 | Import while windows are open | Current windows close cleanly, imported layout restores, one "Undo import" |
| E35 | Game window loses focus (alt-tab while holding ALT) | Keys reset; click-through override doesn't stick (G8) |
| E36 | Spawn menu opened while windows overlap it | Windows stay behind the spawn menu and its dialogs ⚑ verify (G26) |

---

## 8. Being a good guest

A client addon's threats are **untrusted layout strings** (shared by other players or pasted from the web), **hand-edited files**, **other addons' panel code** running inside our windows, and **the addon itself** degrading the game.

| ID | Rule | Where |
|---|---|---|
| R1 | Import: ≤ 64 KB input, `util.Decompress(s, 256 KB)`, JSON decoded **with** the 15,000-key limit (G35, G36) | `storage.lua` |
| R2 | One `Storage.Sanitize(doc)` for files and imports: known fields only, finite clamped numbers, titles ≤ 64 chars, source keys ≤ 128, colours 0–255, ≤ 64 windows, ≤ 16 tabs per window, unknown source kinds dropped | `storage.lua` |
| R3 | Import writes nothing until confirmed; the current layout is backed up first | `storage.lua`, `vgui/hub_settings.lua` |
| R4 | No `RunString`/`CompileString`, no string-built commands. "Equip" only runs `spawnmenu.ActivateTool` for a tool that resolved in the live catalogue (an imported layout can't make you run arbitrary commands) | review + rule check |
| R5 | No global patching except `Sources.WithControlPanelFallback`, which restores in every path (`xpcall`, restore before returning) and is unit-tested with a throwing hook | `sources.lua` |
| R6 | Third-party code (build functions, creation-tab builders, foreign right-click handlers) runs so errors are printed *and* contained (G38) | `sources.lua`, `nav_controls.lua` |
| R7 | Keys are suppressed only while we consume them (a bound action, content nav, keyboard menu), never with chat/console/escape menu/text focus or when the window is unfocused | `input.lua` |
| R8 | Keyboard input is taken only while a text entry inside our window has focus (G20) | `input.lua` |
| R9 | Writes debounced ≥ 0.5 s; paths are constants under `data/pinnedpanels/` | `storage.lua` |
| R10 | Never set a skin on a window (hosted panels would inherit it, G22); never create fonts, materials or RTs in hooks (G29) | review + rule check |

---

## 9. Performance budgets

Reference scene: gm_construct, singleplayer, 20 windows (4 multi-tab × 3 tabs, 2 cropped, 3 minimized), taskbar on, cursor mode off.

| Operation | Budget | Measured with |
|---|---|---|
| Idle frame, cursor mode off | ≤ 0.15 ms Lua in our hooks and `Think`s (excl. hosted panels' own paint) | `pinnedpanels_debug perf` |
| Input dispatcher | ≤ 0.03 ms per frame | same |
| Cursor mode on, mouse over a window | ≤ 0.3 ms | same |
| Restore | ≤ 8 ms per frame; one tab built per frame, visible active tabs first; inactive tabs and minimized windows only when shown | debug log |
| Save | debounced ≥ 0.5 s; ≤ 3 ms for 20 windows | debug log |
| Nav rescan | ≤ 0.5 ms; on layout change or ≤ 4 Hz while navigating | debug log |
| Layout editor paint | ≤ 0.5 ms | same |
| Panels | 1 window control per window, no hidden per-tab frames (B9) | `pinnedpanels_debug panels` |
| Allocations in `Paint`/`Think` | none from our code (G29) | review + rule check |

---

# Part III — Design

## 10. Architecture

### 10.1 Shape of the addon

Pinned Panels is a UI program living inside GMod's VGUI. It has three kinds of code:

1. **Data** — the layout document (windows, tabs) and the settings (convars). Plain tables and convars; no panels.
2. **Controls** — registered Derma controls that draw and handle the mouse: the window, its tab strip and tab host, the crop editor, taskbar, palette, hub pages, and shared small controls.
3. **Coordinators** — small modules that connect the two and GMod: `desktop` (records ↔ window controls), `input` (keys, cursor, focus), `actions` (commands), `sources` (the spawn menu's catalogue), `nav` (keyboard navigation).

```
            GMod events                          user gestures
  (PostReloadToolsMenu, OnScreenSizeChanged,   (drag, resize, click, keys)
   OnTextEntryGetFocus, StartChat, …)                   │
                │                                        ▼
                ▼                               ┌──────────────────┐
        ┌──────────────┐   actions/ops          │  Derma controls  │
        │ coordinators │ ─────────────────────► │  window · tabs · │
        │ input·actions│ ◄───── gestures ────── │  taskbar · hub … │
        │ sources·nav  │                        └────────▲─────────┘
        └──────┬───────┘                                 │ reconcile
               │ Layout.* operations                     │
               ▼                                  ┌──────┴──────┐
        ┌──────────────┐  PinnedPanelsChanged    │   desktop   │
        │    layout    │ ───────────────────────► │ records →   │
        │  (document)  │   (coalesced/frame)      │  controls   │
        └──────┬───────┘                          └─────────────┘
               │ dirty
               ▼
        ┌──────────────┐
        │   storage    │  data/pinnedpanels/layout.json (atomic, backup)
        └──────────────┘
```

### 10.2 Principles
1. **One global** `PinnedPanels`; sub-tables per module; controls are registered classes (`PinnedPanelsWindow`, …).
2. **Controls own their visuals and gestures, nothing else.** They get a record (or an ID) and call `Layout.*` / `Actions.Run` when the user does something. They never write files, never poll keys, never mutate records.
3. **`Layout` is the only writer** of the document and fires one coalesced `PinnedPanelsChanged(kind, id)` per frame.
4. **Derma does the timing.** Layout happens in `PerformLayout` after `InvalidateLayout`; the only deferral is `Util.NextFrame(panel, fn)`, a guarded `timer.Simple(0)`.
5. **Everything reload-safe** (G2): `X = X or {}`, fixed hook IDs or control IDs, controls re-registered by name.
6. **Pure where possible**: geometry, snapping, rescaling, free-spot search, nav ranking, fuzzy scoring, sanitizing and key-repeat timing are pure functions.
7. **Fail soft per item**: a bad tab, source or import entry is skipped and reported; it never aborts a restore.

### 10.3 Lifecycle
1. `lua/autorun/pinnedpanels.lua` (shared, auto-sent, G1): on the server, `AddCSLuaFile` every file and return. On the client, `include` them in order.
2. At include time, files only define functions and register controls; no panels, files or timers.
3. `PinnedPanelsLoaded` (end of loader): create convars, fonts, and cached materials; load the document; register the creation tab.
4. On `PostReloadToolsMenu` (or immediately if the spawn menu already exists): rebuild the catalogue; the first time, restore windows through the desktop queue if `autoRestore` is on.
5. `ShutDown`: flush a pending write.

---

## 11. File tree & line budgets

```
addon.json ........................................ type "tool", tags ["build"], ignore list (§25)
resource/localization/<lang>/pinnedpanels.properties   translations (D5)
lua/autorun/pinnedpanels.lua ............... 40   file list; server: AddCSLuaFile; client: include + PinnedPanelsLoaded
lua/pinnedpanels/
├─ util.lua ............................... 250  Geom (rects, usable area, clamp, rescale, free spot, snap), fuzzy match, colour codec, L(), RealTime helpers, NextFrame, trailing throttle
├─ settings.lua ........................... 180  convar declarations → typed getters, change hook, reset
├─ layout.lua ............................. 500  the document: windows/tabs, every operation, coalesced change event, closed stack, quick keys, arrange, rescale
├─ storage.lua ............................ 220  layout.json read/write (tmp + rename, backup, quarantine), debounce, Sanitize, export/import strings
├─ sources.lua ............................ 250  catalogue from the spawn menu (tools, option pages, content tabs), titles, builders, controlpanel fallback, equip
├─ desktop.lua ............................ 350  records → window controls: create/update/remove, lazy tabs, restore queue, z-order, interactivity, opacity, peek
├─ input.lua .............................. 300  the one Think: gating, edges, repeat, action/quick/peek keys, cursor mode, ALT, cursor owner, suppression, text-entry focus
├─ actions.lua ............................ 350  action list → window menu, taskbar menu, palette entries, key convars, conflict check, console commands
├─ nav.lua ................................ 450  keyboard nav state machine, zones, scan cache, Rank, hints, memory, DMenu driver
├─ nav_controls.lua ....................... 280  per-control keyboard behaviour
└─ vgui/
   ├─ theme.lua ........................... 150  colour tokens, fonts (once), cached materials, paint helpers
   ├─ controls.lua ........................ 350  PinnedPanelsButton, Toggle, Slider, ColorSwatch, KeyBinder (DBinder), SearchBox, Card, ListRow, Empty + dialogs
   ├─ window.lua .......................... 450  PinnedPanelsWindow (EditablePanel): header, buttons, drag/resize/snap hit-testing, click-through, focus ring
   ├─ tabs.lua ............................ 350  PinnedPanelsTabStrip + PinnedPanelsTabHost: clip, crop offsets, filter bar, scroll throttle, collapse cookies, auto-size
   ├─ crop_editor.lua ..................... 230  PinnedPanelsCropEditor
   ├─ taskbar.lua ......................... 280  PinnedPanelsTaskbar
   ├─ palette.lua ......................... 230  PinnedPanelsPalette
   ├─ hud.lua ............................. 60   cursor-mode banner
   ├─ hub.lua ............................. 200  PinnedPanelsHub: creation-tab shell
   ├─ hub_catalog.lua ..................... 250  Tools + Content pages (one list control, two sources)
   ├─ hub_pinned.lua ...................... 220  Pinned page
   ├─ hub_layout.lua ...................... 380  layout editor canvas
   └─ hub_settings.lua .................... 350  settings pages
```

**Totals:** 24 Lua files, ≈ 6,700 lines. Budgets flag problems; a file more than 25% over should be checked for doing two jobs.

---

## 12. Old → new file mapping

| v1 | → v2 |
|---|---|
| `autorun/server/sv_pinnedpanels.lua`, `filelist.lua`, loader part of `autorun/client/cl_pinnedpanels.lua` | `autorun/pinnedpanels.lua` |
| rest of `autorun/client/cl_pinnedpanels.lua` (tab shell, commands) | `vgui/hub.lua`, `actions.lua` |
| `core.lua` | `util.lua` (bounds), `layout.lua` (rescale), `desktop.lua` (restore) |
| `persistence.lua` | `storage.lua` (document), `settings.lua` (settings) |
| `helpers.lua` | `sources.lua` (catalogue, tool panel building), `vgui/tabs.lua` (scroll throttle), `vgui/controls.lua` (error label) |
| `colors.lua` | `vgui/theme.lua` |
| `localization.lua`, `lang/*` | `.properties` + `L()` in `util.lua` |
| `pin.lua`, `groups.lua` | `layout.lua`, `desktop.lua`, `sources.lua` |
| `frame.lua` | `vgui/window.lua` |
| `crop.lua` | `vgui/crop_editor.lua` + clip in `vgui/tabs.lua` |
| `autosize.lua`, `content_tools.lua` | `vgui/tabs.lua` |
| `popups.lua` | `vgui/controls.lua` (colour dialog) + actions (rename) |
| `context_menu.lua` | `actions.lua` |
| `actions.lua` | `layout.lua` (arrange), `input.lua` (quick keys, peek) |
| `cursor_mode.lua` | `input.lua`, `vgui/hud.lua`, `vgui/controls.lua` (binder) |
| `taskbar.lua` | `vgui/taskbar.lua` |
| `command_palette.lua` | `vgui/palette.lua` |
| `browser.lua`, `creation_browser.lua` | `vgui/hub_catalog.lua` |
| `pinned_list.lua` | `vgui/hub_pinned.lua` |
| `layout_editor.lua` | `vgui/hub_layout.lua` |
| `settings/*` | `vgui/hub_settings.lua`, `vgui/controls.lua` |
| `keyboard/*` (except `controls.lua`, `keybinds.lua`) | `nav.lua` (+ repeat/suppression in `input.lua`) |
| `keyboard/controls.lua` | `nav_controls.lua` |
| `keyboard/keybinds.lua` | `actions.lua` |

---

## 13. The layout document

### 13.1 Records

```
window = {
  id = "w12",
  tabs = { tab, … }, active = 1,
  x, y, w, h,                              -- normal-state geometry
  state = "normal" | "minimized" | "maximized",
  restore = { x, y, w, h }?,               -- only while maximized
  title?, accent?,                         -- title nil unless renamed (L19)
  locked, clickThrough, opacity?,          -- opacity nil = setting
  colors = { bg?, header?, text? },
  filterBar, quickKey?,
}
tab = {
  src = "tool:weld" | "creation:#spawnmenu.content_tab",
  title?,                                  -- nil unless renamed
  size = { w, h }?,                        -- remembered size for this tab
  crop = { l, t, r, b }?,
}
```

One tab: no tab strip, looks exactly like a v1 pin. Several tabs: tab strip with the accent colour, like a v1 group. "New group" creates an empty titled window that shows only in the Pinned list until it gets a tab.

### 13.2 File

```
data/pinnedpanels/layout.json              the document
data/pinnedpanels/layout_bak.json          previous good version; also the import-undo point
data/pinnedpanels/layout_corrupt_<t>.json  quarantined unreadable file (E6)
```

```json
{
  "v": 2,
  "screen": { "w": 2560, "h": 1440 },
  "nextId": 13,
  "windows": [
    { "id": "w12", "state": "normal", "x": 40, "y": 120, "w": 320, "h": 540,
      "tabs": [ { "src": "tool:weld", "size": { "w": 320, "h": 540 } },
                { "src": "tool:rope", "crop": { "l": 0, "t": 36, "r": 0, "b": 120 } } ],
      "active": 1, "title": "Constraints", "accent": [255, 200, 60, 255],
      "locked": false, "clickThrough": false, "opacity": 0.5,
      "colors": { "bg": [235, 238, 242, 250] }, "filterBar": true, "quickKey": 79 }
  ]
}
```

- Arrays with `id` fields and `[r,g,b,a]` colours (G35).
- Geometry is rescaled on load when `screen` differs (E3).
- Dormant tabs keep their record untouched (E1).
- "Recently closed" and collapse state are not in the file (session / cookies, D14).

### 13.3 Operations (`layout.lua`)

`Pin(src)`, `Unpin(id)`, `UnpinTab(id, i)`, `Reopen()`, `MoveTab(fromId, i, toId|nil, toIndex)` (merge, split and reorder are one function), `Activate(id, i)`, `Minimize`, `Restore`, `ToggleMaximize`, `SetGeometry`, `SetLocked`, `SetClickThrough`, `SetOpacity`, `SetColors`, `Rename(id, i|nil, title)`, `SetQuickKey`, `SetCrop`, `SetFilterBar`, `NewGroup(title)`, `Arrange()`, `RescaleAll(oldW, oldH)`.

Each: validate → mutate → `Storage.MarkDirty()` → queue `Changed(kind, id)`. Kinds: `"windows"` (added/removed), `"tabs"`, `"geometry"`, `"state"`, `"style"`. The queue flushes once per frame, so drag storms produce one event per frame.

### 13.4 Storage (`storage.lua`)

Write: encode → `file.Write("pinnedpanels/layout_tmp.json")` (check bool) → current → `layout_bak.json` → `file.Rename(tmp, "layout.json")` (check bool; on failure write directly and log). Read: `layout.json` → `layout_bak.json` → quarantine + notification (E6). A document with a newer `v` is opened read-only. Export: `"PP2:" .. util.Base64Encode(util.Compress(json), true)` copied with `SetClipboardText` (G37). Import: prefix check (rejects v1 strings with a clear message), size cap, decompress with `maxSize`, decode with limits, `Sanitize`, return `doc, summary` for confirmation (R1–R3).

---

## 14. Sources: tools and content tabs

### 14.1 Catalogue

Rebuilt on every `PostReloadToolsMenu` (G11) from `spawnmenu.GetTools()` (G12) and `spawnmenu.GetCreationTabs()` (G13):

```
catalogue["tool:weld"] = { kind = "tool", key, name = "weld", title = "Weld", category = "Constraints", tab = "Tools", item = <tool table> }
catalogue["creation:#spawnmenu.content_tab"] = { kind = "creation", key, title, icon, order, tooltip, fn }
```

Titles come from `language.GetPhrase` at build time, so a rebuild after a language change re-localizes them (L19). Tools are deduped by `ItemName` (L28). Tabs whose `src` isn't in the catalogue are dormant; each rebuild re-checks them.

### 14.2 Building content

- **Tool**: a `DScrollPanel` holding `vgui.Create("ControlPanel")` filled with `FillViaTable{ Text = item.Text, ControlPanelBuildFunction = item.CPanelFunction }` — the same call the spawn menu makes (G14). The header is hidden as in v1.
- **Content tab**: `fn()` returns a container that fills the tab (G13).
- Both run with error containment (R6, G38); on error the tab shows the message and a *Retry* button.
- **Rebuild content** (E10): clear the host and build again. Offered as a tab action for every tool tab.

### 14.3 The `controlpanel.Get` fallback

If the built `ControlPanel` gained no children (L2), run `Sources.WithControlPanelFallback(name, panel, function() hook.Run("PostReloadToolsMenu") end)`: temporarily makes `controlpanel.Get(name)` return our panel so a hook that fills it by name fills ours. This is the only global replacement in v2 (R5). It restores the original in every path and is unit-tested with a throwing hook. It fires every addon's `PostReloadToolsMenu`, so it runs only when the normal build produced nothing. ⚑ verify which popular tools need it (Phase 0 spike).

### 14.4 Equip

`spawnmenu.ActivateTool(name)` (G16) for a catalogued tool only (R4).

---

## 15. Windows (Derma controls)

### 15.1 `PinnedPanelsWindow` (`vgui/window.lua`, base `EditablePanel`, G21)

- **Built by** `desktop` with a window ID; reads its record from `Layout.Get(id)`.
- `MakePopup()`, then `SetKeyboardInputEnabled(false)` (G21); `SetPopupStayAtBack(true)` if Phase 0 confirms it (G26).
- **Hit-testing in one place**: `OnMousePressed`/`OnCursorMoved` classify the cursor as header, one of 8 resize zones, button (min/max/close) or tab strip. This replaces v1's title overlay, 8 zone child panels and separate click-through grip popup (L24).
- **Click-through**: `TestHover` returns true only over the header (unless ALT is held), so the body lets clicks through while the header can still be dragged (G25 ⚑ verify; fallback: a thin header-only popup as in v1).
- **Drag/resize** go through `Geom.Snap` (ALT disables) and `Geom.Clamp(Geom.Usable())`; on release `Layout.SetGeometry`.
- `PerformLayout` places header, buttons, tab strip and host — no timers.
- `Paint` uses the record's colours or the settings' colours via cached theme values; `PaintOver` draws the keyboard focus ring and hint (data from `nav`).
- `OnScreenSizeChanged` is not handled here — `layout.RescaleAll` owns rescaling (G4) so unbuilt windows rescale too.

### 15.2 `PinnedPanelsTabStrip` and `PinnedPanelsTabHost` (`vgui/tabs.lua`)

- **Tab strip**: shown only with ≥ 2 tabs; accent colour; click to activate, right-click for the tab menu, drag-hover switches (like `DTab`).
- **Tab host** (one per tab, created lazily when the tab is first shown, D13):
  - a permanent **clip panel** with mouse input disabled (L22); content docked `FILL` inside it, or, when cropped, undocked at the uncropped size and positioned at `(-l, -t)`. Crop never reparents content.
  - **filter bar** slot (F19) and the filter itself (hide non-matching rows, expand matching categories, restore on clear).
  - **collapse memory** (F20, D14): each `DCollapsibleCategory` inside a tool panel gets `SetCookieName("pinnedpanels." .. src .. "." .. label)` (G23).
  - **scroll throttle**: trailing-edge throttle of the scroll panel's layout (L3, B6), implemented by the host scheduling one `InvalidateLayout` per interval instead of replacing the method.
  - **auto-size** measurement (natural width and height, F17).
- Switching tabs applies the tab's `size` and `crop` (L6). Maximize suspends the crop and restores it after (B27).

### 15.3 `PinnedPanelsCropEditor` (`vgui/crop_editor.lua`)

The v1 editor as a control: overlay on the window, draw/move/resize selection, *Apply*, *Full*, *Cancel*, right-click cancels; it asks `input` for a cursor reason while open and closes if cursor mode ends.

---

## 16. Desktop: records → panels

### 16.1 Reconcile

`desktop` keeps `panels[id]`. On `Changed`:
- `"windows"`: create controls for new records, `Remove()` controls for deleted ones.
- `"tabs"`: the window updates its strip; tab hosts are created on first show and removed when their tab is.
- `"geometry" | "state" | "style"`: the window re-reads its record (`InvalidateLayout`).

### 16.2 Restore queue

After the catalogue is ready: create every non-minimized window frame at once (so the layout appears immediately), then build **one tab host per frame**, visible active tabs first. Inactive tabs and minimized windows build when first shown (D13, E24).

### 16.3 Interactivity and opacity

```
interactive(w) = Input.Interactive() and (not w.clickThrough or Input.AltHeld())
opacity(w)     = 1  if Input.Interactive() or peeking or keyboard-focused within 2 s (L11)
               = (w.opacity or Settings.idleOpacity/100), min 0.05, otherwise
```
Recomputed on mode/focus/setting changes, never per frame. `SetAlpha` is visual only (G27).

### 16.4 Peek
Peek shows every window (incl. minimized) at full opacity, remembers what it changed, and puts it back on release — as v1.

---

## 17. Input

`input.lua` owns the only `Think` hook (`PinnedPanels.Input`), `input.IsKeyDown`, `CreateMove`, `PlayerBindPress`, `gui.EnableScreenClicker` and the text-entry focus hooks.

Per frame:
1. **Gate**: chat open (`StartChat`/`FinishChat`), `gui.IsConsoleVisible()`, `gui.IsGameUIVisible()`, `not system.HasFocus()`, key trapping active (G19), or a text entry focused → reset edge state (E13, E32, E35) and return.
2. **Edges** for the precomputed `watched` key set (action keys, quick keys, peek, nav keys while navigating). Rebuilt when a binding changes.
3. **Dispatch**: press → action, quick key or peek start; release → peek end; nav keys → `nav` with `Input.Repeat` (0.35 s delay, 0.055 s interval, **`RealTime`**, G5).
4. **ALT** changes → `desktop` updates click-through interactivity.

**Cursor mode**: a state toggled by the `cursor` action; suspended while the spawn menu is open (E16). **Cursor owner** `Input.Cursor(reason, on)` keeps a reason set (`cursor`, `palette`, `crop`) and is the only caller of `gui.EnableScreenClicker` (E31, G9). Optionally remembers and restores the cursor position like the spawn menu (D16).

**Text focus** (G20, R8): on `OnTextEntryGetFocus(pnl)` → if `pnl` is inside a window, `window:SetKeyboardInputEnabled(true)`; on `OnTextEntryLoseFocus` → false. No hover polling (B32, E14).

**Suppression** (R7): `CreateMove` clears movement/buttons and `PlayerBindPress` returns true only for keys consumed this frame. F-keys can't be blocked through `PlayerBindPress` (G6); the binder warns.

---

## 18. Actions

### 18.1 Declaration

```lua
Actions.Add({
    id       = "crop",                          -- console: pinnedpanels_crop; key convar: pinnedpanels_key_crop
    scope    = "tab",                           -- global | window | tab
    icon     = "icon16/shape_handles.png",
    menu     = { group = "view", order = 40 },  -- where it appears in the window menu
    palette  = true,
    bindable = true, key = KEY_NONE,
    label    = function(ctx) return ctx.tab.crop and "action.crop.edit" or "action.crop" end,
    enabled  = function(ctx) return not ctx.window.locked end,
    run      = function(ctx) PinnedPanels.CropEditor.Open(ctx.window.id) end,
})
```

`ctx = { window = record, tab = record, index = i }`, resolved from the focused, right-clicked or named window. Submenus (opacity presets, "move tab to…", "add to group…") use `children(ctx)`.

### 18.2 What's generated from the list
- The **window menu** and **tab menu** (real `DMenu`s, grouped and ordered) — mouse and keyboard (§19.5).
- The **taskbar entry menu** (restore, restore all, unpin).
- **Palette** entries.
- **Key convars** `pinnedpanels_key_<id>` for every `bindable` action, and the Controls settings page rows.
- **Console commands** `pinnedpanels_<id>` (optional `windowId` argument; defaults to the focused window). Anything can be bound with `bind x pinnedpanels_<id>` (D15). Peek also gets `+pinnedpanels_peek` / `-pinnedpanels_peek`.

### 18.3 Console surface
`pinnedpanels_<action>` for every action (cursor, palette, arrange, reopen, autosize_all, restore_all, unpin_all, …), plus `pinnedpanels_list`, `pinnedpanels_reload`, `pinnedpanels_pin <src>`, `pinnedpanels_debug perf|panels|nav`. Replaces `pp_clearall`, `pp_list`, `pp_reload`, `pp_arrange`, `pp_reopen`, `pp_autosize_all`, `pp_palette` (G32).

### 18.4 Conflicts
`Actions.Conflicts(key, exceptId)` lists the key's game bind (`input.LookupKeyBinding`, G10), other actions and quick keys, and whether it's an F-key whose game bind can't be blocked (G6).

---

## 19. Keyboard navigation

### 19.1 State machine (`nav.lua`)

```
 OFF ──► WINDOWS ◄──► TASKBAR
  ▲         │ ▲
  │   enter │ │ Backspace, or Up at the top edge
  │         ▼ │
  │      CONTENT ── Enter on adjustable ──► ADJUST
  │         │    ◄── Enter / Backspace ─────┘
  │         │ Shift+Enter / menu key
  │         ▼
  └────── MENU (drives a real DMenu)
```
`OFF` whenever nav is disabled (not cursor mode and `navEverywhere` off, D8). Each transition is a named function with a test (L10). Taskbar and popups (the colour dialog) are **zones**, not magic IDs (v1's `"__TASKBAR__"`).

### 19.2 Scan
`Nav.Scan(host)` walks the focused tab host (depth ≤ 20) using the control adapters to tell leaves from containers, drops elements under 4 px and outside the clip rect (L15), caches per host, invalidates on the host's layout, ≤ 4 Hz while navigating.

### 19.3 Ranking
`Nav.Rank(rects, from, dir)` is pure (L14): candidates beyond a 2 px epsilon in `dir`; overlapping ones on the perpendicular axis rank by edge gap (4 px tie band) then perpendicular distance; vertical moves fall back to `primary + 4 × perpendicular`. Scroll-into-view uses `DScrollPanel:ScrollToChild` (G24) up the parent chain.

### 19.4 Control adapters (`nav_controls.lua`)
```lua
Nav.Control({ id = "slider", matches = function(p, class) return class:find("Slider") ~= nil end,
              adjust = "1d", hint = "nav.hint.slider", onAdjust = function(p, key, shift) … end })
```
Button, checkbox, combo box, text entry / number wang (hand focus to the entry), tree node (L21), slider, colour mixer (HSV; Shift = saturation/alpha), colour cube, RGB picker, alpha bar, HTML (JS scroll, L20), and a generic clickable fallback. Hints come from the adapter.

### 19.5 Menus
- **Window/tab menu**: build the real `DMenu` from actions, open it next to the window, then drive it: Up/Down move `HighlightItem`, Right/Enter `OpenSubMenu` or `option:DoClick()` + `CloseDermaMenus()`, Left/Backspace close (G17).
- **Element menu** (Shift+Enter on a control): call the element's own right-click handler, find the DMenu it opened, move it next to the element, drive it the same way. Finding it without patching is ⚑ verify: first try diffing children of `vgui.GetWorldPanel()`; fallback is wrapping only `RegisterDermaMenuForClose` for the duration of the synchronous call inside the R5 helper. v1 patched `DermaMenu`, `vgui.Create`, `gui.MouseX`, `gui.MouseY` (B4, B5).

---

## 20. The hub, taskbar, palette and HUD

### 20.1 Hub (`vgui/hub*.lua`)
`spawnmenu.AddCreationTab("#pinnedpanels.spawn_tab", fn, "icon16/lock.png", 9999)`; `fn` returns a `PinnedPanelsHub`. The spawn menu destroys and rebuilds it on every rebuild (G11), so pages hold no state and read `Layout`/`Sources` on creation and on `Changed`.
- **Tools / Content** (`hub_catalog.lua`): one `PinnedPanelsCatalogList` control given a list and a filter; category headers for tools; rows re-read pinned state on paint (L1).
- **Pinned** (`hub_pinned.lua`): windows, tabs, dormant entries with an *unavailable* badge and *Remove*.
- **Layout** (`hub_layout.lua`): the editor canvas; snapping via `Geom.Snap` and the `snapDistance` setting (B22).
- **Settings** (`hub_settings.lua`): §21.

### 20.2 Taskbar (`vgui/taskbar.lua`)
`PinnedPanelsTaskbar` popup; entries = minimized windows; icons and colours cached (B23); fade and slide with `RealFrameTime` (G5); keyboard zone for nav; restores `DisableClipping` state (B29).

### 20.3 Palette (`vgui/palette.lua`)
`PinnedPanelsPalette`: entries from actions (palette = true), open windows, the catalogue, and "restore interactivity" for click-through windows (L16). Category order by ID, not localized name (B14). Cursor reason `palette`.

### 20.4 HUD (`vgui/hud.lua`)
Cursor-mode banner: cached localized text, key name from the binding, one `draw` call (L8).

---

## 21. Settings

### 21.1 Declarations (`settings.lua`)

```lua
Settings.Add("snapDistance", { type = "int", min = 0, max = 40, default = 12, page = "general", section = "snapping" })
Settings.Add("taskbarSide",  { type = "enum", values = { "bottom", "top", "left", "right" }, default = "bottom", page = "taskbar" })
Settings.Add("colorBg",      { type = "color", default = Color(235, 238, 242, 250), page = "appearance" })
```
Each creates `pinnedpanels_<snake_key>` with `FCVAR_ARCHIVE` and engine min/max (G33). `Settings.Get(key)` returns a cached, typed value refreshed by `cvars.AddChangeCallback`; `Settings.Set` uses `ConVar:SetX` (immediate, G33). Declare a setting in the commit that first reads it.

### 21.2 Table

| v1 | v2 key | Type / range | Default | Notes |
|---|---|---|---|---|
| `autoRestore` | `autoRestore` | bool | 1 | |
| `keyboardNavOutsideCursorMode` | `navEverywhere` | bool | **0** | D8 |
| `idleAlpha` (0.1–1) | `idleOpacity` | int 10–100 | 100 | |
| `snapEnabled` / `snapDistance` | `snap` / `snapDistance` | bool / int 0–40 | 1 / 12 | |
| `bg` / `header` / `text` | `colorBg` / `colorHeader` / `colorText` | colour `"r g b a"` | as v1 | |
| `taskbar.enabled` | `taskbar` | bool | 1 | |
| `taskbar.position` | `taskbarSide` | enum | bottom | |
| `taskbar.height` | `taskbarSize` | int 20–64 | 32 | |
| `taskbar.revealOnHover` | `taskbarAutoHide` | bool | 0 | |
| `taskbar.showLabels` | `taskbarLabels` | bool | 1 | |
| `taskbar.*Color` | `taskbarColorBg/Text/Accent` | colour | as v1 | |
| `language` | removed | | | D5 |
| `quickSlots`, `groups` | in the layout document | | | §13 |
| `pp_interact_key` | `pinnedpanels_key_cursor` | key | F4 | binder warns (G6) |
| `pp_key_peek`, `pp_palette_key`, `pp_key_<14>` | `pinnedpanels_key_<action>` | key | as v1 | generated (§18) |

### 21.3 Pages
Rows are generated per `page`/`section` with our convar-bound controls (`Derma_Install_Convar_Functions`, G3): toggles, sliders, dropdowns, colour swatches, `DBinder`-based key rows (G19) with conflict dialog. Hand-written parts: the Appearance live preview, the Groups page (multi-tab and empty named windows) and the Data page (export to clipboard, import box with preview summary and confirm, unpin all).

---

## 22. Theme

`vgui/theme.lua`: ≈ 20 colour tokens (backgrounds, surfaces, text levels, accent, success, danger, warning, focus, nav focus/selected, taskbar), a fixed font set created once (G29), cached `Material()`s for the icon16 set we draw ourselves, and paint helpers (card, pill, outline, truncated text). Our controls paint from tokens; hosted panels keep GMod's Default skin — windows never call `SetSkin` (G22, D6). The window body default stays light (as v1) so hosted default-skinned controls stay readable.

---

## 23. Localization

- `resource/localization/<code>/pinnedpanels.properties`, first line empty (G39). English is loaded first, so missing keys fall back automatically (L18).
- Codes: v1 `pt` → `pt-BR`, `zh` → `zh-CN`, `es` → `es-ES`; `en`, `fr`, `de`, `ru`, `pl`, `tr` unchanged.
- Keys `pinnedpanels.<area>.<thing>`; Derma labels use `"#pinnedpanels.key"`; code uses `L(key, …)` = `language.GetPhrase` + guarded `string.format`.
- Refresh: the spawn menu already rebuilds itself on `gmod_language` (G11), so the hub refreshes for free; windows, taskbar, palette and settings listen to one `cvars.AddChangeCallback("gmod_language")`.
- v1's 9 tables are converted once, by hand or a throwaway script (no tools are kept, D21): v1 key `ctx_lock` becomes `pinnedpanels.ctx.lock` (first `_` → `.`), newlines are written as `\n`. Missing keys fall back to English (B25 is checked by review).
- Limitation: a player who receives the Lua from a server without having the addon installed won't have the `.properties` files and sees raw keys. Pinned Panels is meant to be installed by the player, so this is documented, not designed around.

---

# Part IV — Execution

## 24. Coding conventions

- **One control per `vgui.Register`**, named `PinnedPanels<Thing>`; a file may hold a control and its small private helpers.
- **File header**: 1–3 lines stating the responsibility.
- **Plain Lua syntax**: no `continue`, `!=`, `&&`, `||`, `!`, `//`, `/* */` (L27).
- **Time**: `RealTime`/`RealFrameTime`/`SysTime` only (G5).
- **No** `timer.Simple` outside `Util.NextFrame`; named `timer.Create("PinnedPanels.X")` otherwise.
- **No** defensive checks on things load order guarantees.
- **No global patching** outside the R5 helper.
- **Controls don't mutate records**; they call `Layout.*` or `Actions.Run`.
- **Hot paths** (`Paint`, `PaintOver`, `Think`, `HUDPaint`): no `Color(`, `Material(`, `surface.CreateFont` (G29).
- **User text** through `L()` or `#key` only.
- **Reload-safe** (G2): `X = X or {}`, fixed hook IDs or control IDs.
- Comments explain *why*; no commented-out code; lowercase file names; no empty files (G1).

## 25. Tooling

Kept small: most of this addon is VGUI and is tested in game.

- **No tool scripts and no CI** (D21): the §24 rules and the §2 grep metrics are checked by review. A Lua parse check before committing: `luajit -bl <file> > /dev/null` (L27).
- **No unit tests** (D20): the owner tests in game and reports problems. A suite covering `util`, `settings`, `storage` (sanitize, quarantine, import fixtures), `layout`, `input`, the R5 helper and headless window wiring was written for Phases 1–2, then removed (it is in the git history before the removal commit).
- **Editor**: keep `.gluarc.json`; drop the server attach config from `.vscode/launch.json` (no server code to debug).
- **Dev loop on macOS** (G2): `pinnedpanels_reload` re-includes the loader; controls re-register; windows rebuild from the document (E25).
- **Packaging** (G39): `addon.json` `{ "title": "Pinned Panels", "type": "tool", "tags": ["build"], "ignore": ["*.md", ".vscode/*", ".gluarc.json", "**/.DS_Store"] }`; `gmad create` must contain only `lua/` and `resource/localization/`; 512×512 baseline JPEG icon.

## 26. Roadmap

Each phase ends with the addon loading cleanly and its acceptance passing. Record deviations and in-game findings under each phase.

### Phase 0 — Groundwork (½ day)
- [x] Branches and tag (§3.2); confirm D1 and D4
  - *Done 2026-09-30:* `legacy/v1` and `1.0.0` at `5b6def9`, pushed; `feature/localization` deleted; D1 (no compat) and D4 (`pinnedpanels_`) confirmed. Branch protection on `legacy/v1` is left to the repo owner.
- [ ] **⚑ verify spike** (≈ 1 hour), results written into §5.2. Done by hand in game (the spike script was removed with `tools/`, D21). *Results pending.*
  - G30/E27: pinned windows during the escape menu (`ParentToHUD` + `MakePopup`)
  - G26/E36: `SetPopupStayAtBack(true)` keeps a popup behind the spawn menu and `Derma_Query`
  - G25: `TestHover` on a popup makes the body click-through with the header still draggable
  - §19.5: open an element's DMenu, find it via `vgui.GetWorldPanel()` children, drive it with `HighlightItem`/`OpenSubMenu`/`DoClick`
  - §14.3: which tools in a common pack (Wiremod, Easy Precision, Advanced Duplicator 2) produce an empty `ControlPanel` without the fallback
  - G8: chat open is visible to Lua only via `StartChat`/`FinishChat` (not `vgui.GetKeyboardFocus`)
  - §33.15: the "pin any panel" spike (where windows live, Manage, Embed, reproduce the v1 failure, Record, real addons)
- [x] Remove the v1 tree; add loader, `addon.json`. Rule checks, unit tests and CI were added, then removed after Phase 2 (D20, D21)
  - *Deviation:* `README.md` still describes v1 until Phase 7.
- **Accept:** the game boots and prints `Pinned Panels 2.0 loaded`.

### Phase 1 — Data and input (2 days)
- [x] `util.lua` (+ tests) [F36, L5, L12, L23, G5, G35]
- [x] `settings.lua` [G33]
- [x] `storage.lua` (+ tests) [F30, F31, R1–R3, R9, G34–G37, B2, B3, E6, E7]
- [x] `layout.lua` operations headless (+ tests) [F12, F15, F18, F24, F27, F28, F32, L6, L7, B8, B17, B20, B27, E3–E5, E20–E22, E28, E33]
- [x] `input.lua` (+ tests) [F10, F21, F22, F37, R7, R8, G6–G9, G20, B10, B11, B28, B32, E13, E14, E31, E32, E35]
- [x] English `.properties`, `L()` [F33, L18, G39] (the converter and lang check were written, then removed, D21)
- **Accept** (in game, still to check): a corrupted `layout.json` is quarantined with a notification; hotkeys don't fire in chat, console, escape menu or after alt-tab.
- *Deviations:*
  - `input.lua` has no key repeat and no `CreateMove` suppression yet. Only keyboard nav uses them, so they arrive in Phase 5. `PlayerBindPress` suppression is in.
  - Input announces cursor-mode, ALT and spawn-menu changes with an internal `PinnedPanelsInputChanged` event (Appendix A).
  - Fuzzy matching moves to Phase 4 with the palette, its only user. The taskbar's share of `Geom.Usable()` arrives with the taskbar in Phase 3.
  - Renaming a single-tab window renames its tab, so the name travels if the tab is moved; a window `title` is a group name (§13.1).

### Phase 2 — Windows on screen (3 days)
- [x] `sources.lua` + fallback helper (+ test) [F7, F8, F35, L2, L28, G11–G16, G18, R4–R6, B26, E2, E8–E10, E12]
- [x] `vgui/theme.lua`, `vgui/controls.lua` core [G22, G29, D6]
- [x] `vgui/window.lua` [F9, F11, L22, L24, G21, G25, G26, E17, E18]
- [x] `vgui/tabs.lua` single-tab host (clip, scroll throttle) [L3, B6]
- [x] `desktop.lua` (reconcile, restore queue, opacity, interactivity) [L11, G27, B1, B9, E1, E24]
- [x] `vgui/hud.lua` [L8, B19]
- [x] Minimal hub: Tools and Content pages [F1–F3, L1, L4]
- **Accept** (in game, still to check): pin 10 tools, 3 content tabs and 2 option pages; drag/resize/snap; restart; everything returns. Disable an addon, restart: its windows are dormant; re-enable: they come back.
- *Deviations:*
  - `actions.lua` starts here with the cursor key and `pinnedpanels_cursor`, `_pin`, `_list`, `_reload`, so Phase 2 can be tried in game. Phase 3 turns it into the action list.
  - With `autoRestore` off, the windows saved at join are *held*: kept in the document, not shown until `Desktop.ShowHeld()` (Pinned page in Phase 4). Pinning something else doesn't show them.
  - Windows keep v1's `ParentToHUD()` + `MakePopup()` until the Phase 0 spike settles G30/E27.
  - No right-click menu yet (actions, Phase 3), and minimizing has no taskbar to restore from until Phase 3.
  - The theme keeps v1's specific button and row colours, so it has about 40 tokens, not 20.
  - `storage.lua` is 291 lines (budget 220): `Sanitize` is most of it, and it's still one job (the file format). `layout.lua` is 557 (budget 500).

### Phase 3 — Window features (3 days) → `2.0.0-alpha.1`
- [x] Multi-tab windows: tab strip, `MoveTab`, per-tab size, accents [F15]
- [x] Crop editor and clip crop [F16, L15, E19, E28]
- [x] Filter bar, collapse cookies, auto-size [F17, F19, F20, G23, D14]
- [x] Minimize/maximize, `vgui/taskbar.lua` [F12, F13, B15, B23, B29, E23]
- [x] `actions.lua` + window/tab/taskbar menus, colour dialog, rename, lock, geometry copy/paste, equip, rebuild content [F14, F26–F29, F34, F35, G32, D15, D17, E10]
- [x] Quick keys, peek, arrange, reopen [F18, F21, F22, F24]
- **Accept** (in game, still to check): every v1 context-menu entry exists; merging 3 tools into one window and splitting them back leaves no extra panels (`pinnedpanels_debug panels`); idle and restore budgets met.
- *Deviations:*
  - "Hide" is for this session only (the desktop's held set, like autoRestore off); the Pinned page, the palette or the window's quick key show it again. It isn't saved.
  - The tab strip switches tabs on click and opens the tab menu on right-click. There's no drag to reorder or drag-hover switching; the tab menu has Move Left/Right/To Its Own Window.
  - Each tab has its own filter text; the window's filter-bar setting shows or hides all of them.
  - Crop insets are content pixels. Dragging a cropped window's edge trims or reveals content (v1); other size changes (arrange, rescale, the layout editor) keep the insets.
  - Extra actions beyond v1's menu: `restore` (taskbar), `maximize` (key only), `palette`, `rename_tab`, `move_left`/`move_right`/`move_out`, `unpin_tab`, `unpin_group_tabs`, `dissolve`.
  - `pinnedpanels_debug` has only `panels` for now.
  - The taskbar's keyboard zone waits for Phase 5; `SetPopupStayAtBack` waits for the Phase 0 spike (G26).

### Phase 4 — Hub (3 days)
- [x] Pinned page with dormant entries [F4, L26]
- [x] Layout editor [F5, B22]
- [x] Settings pages, key binders with conflicts, Groups, Data with import preview [F6, F26, G19, R3, E15, E30, E34]
- [x] Palette [F23, L16, B14]
- **Accept** (in game, still to check): every §21.2 setting is visible and resets; importing a bomb string is rejected with a message and changes nothing.
- *Deviations:*
  - Resizing a cropped window's box in the layout editor keeps its crop insets (v1 adjusted them).
  - An import applies in place after the confirm; nothing reloads.

### Phase 5 — Keyboard navigation (3–4 days) → `2.0.0-beta.1`
- [ ] `nav.lua` state machine, zones, scan, `Rank` [F25, L10, L11, L14, L15, G24, D8]
- [ ] `nav_controls.lua` [L20, L21]
- [ ] Keyboard-driven DMenus, window and element menus [L9, G17, B4, B5, E29, D9]
- [ ] Taskbar and popup zones
- **Accept:** everything the mouse can do inside a pinned window, the keyboard can do.

### Phase 6 — Parity & translations (2 days)
- [ ] Side-by-side v1/v2 screenshots of every screen and menu; close gaps or record a decision
- [ ] 8 translations converted and completed [F33, B25]
- [ ] Live language switch across every screen [E11]
- **Accept:** every F-item has a working v2 owner or a D-decision.

### Phase 7 — Hardening & release (2 days) → `2.0.0-rc.1` → cutover
- [ ] Manual matrix (§28.2)
- [ ] Performance pass (§9)
- [ ] Good-guest pass (§8): import fixtures pasted in game; movement with hovered text boxes; F-key binds; slow motion and pause
- [ ] README (features, keys, settings table), release notes, Workshop icon
- [ ] Cutover (§3.2)
- **Accept:** every §2 metric ticked.

**Total:** ~18–20 focused days.

**After 2.0:** see Future features (§32). Ideas that come up during the rewrite go there, not into the current phase.

## 27. Definition of done
- [ ] One thing per commit, IDs referenced.
- [ ] The §24 rules hold (by review); every file parses (`luajit -bl`).
- [ ] Behaviour has a matrix row.
- [ ] Strings in `en/pinnedpanels.properties`.
- [ ] Plan updated if the design changed; file within budget or overrun explained.

## 28. Testing strategy

### 28.1 Unit tests
None (D20). Bugs are reported from in-game testing and fixed against the matrix below.

### 28.2 Manual matrix (`MATRIX.md`, one tick column per rc)

| Environment | Covers |
|---|---|
| Singleplayer, no other addons | all F-items; E1–E12, E16–E28, E33, E34 |
| Singleplayer with Wiremod, Easy Precision, Advanced Duplicator 2 | E8–E10, L2 fallback, many tools, E24 |
| Listen server and a dedicated server you join (addon installed on your client) | loading (G1), E2, hotkeys vs. server binds |
| Chat, console, escape menu, spawn menu, C menu, alt-tab during every hotkey | E13, E16, E27, E31, E32, E35, R7 |
| Walking in cursor mode with the mouse over text boxes | E14, R8 |
| `host_timescale 0.2` (with `sv_cheats 1`) and SP pause | B28, E32 |
| 1920×1080 → 1280×720 → windowed → MSAA toggle | E3–E5 |
| Each of the 9 languages | E11, F33 |
| Import fixtures pasted in game | E7, E34, R1–R3 |

## 29. Risks & mitigations

| Risk | Mitigation |
|---|---|
| Hidden v1 behaviour lost | §5.1 table, `git log -p` per file on `legacy/v1`, Phase 6 side-by-side parity |
| A ⚑ item fails (e.g. `TestHover` on popups, finding foreign DMenus) | each has a named fallback in its section; the spike decides before the dependent phase |
| Tools whose panels only fill via hooks | L2 fallback, matrix row with popular packs, error + *Retry* instead of a blank tab |
| Pinned tool copies going stale (G15) | "Rebuild content" action; automatic tracking is FF14 (§32) |
| Lazy tabs surprise features that expect all tabs built | filter, auto-size, nav act on the active tab only (as v1) |
| Unifying pins and groups confuses v1 users | every group action exists; the Groups settings page stays |
| Scope creep | Future features list (§32); phase acceptance gates |

## 30. v1 bugs not to carry over

| ID | Bug (where) | v2 fix |
|---|---|---|
| B1 | **Data loss:** restore skips pins whose tool/content tab isn't found and the next `Save()` rewrites the file from live pins only, **deleting** them (`core.lua`, `persistence.lua`) | dormant tabs (E1) |
| B2 | **Data loss:** an unreadable file loads as `{}` and the next save overwrites it; writes aren't atomic, unchecked, unbacked (`persistence.lua`) | §13.4 (E6) |
| B3 | Import calls `util.Decompress` without `maxSize`, writes the decoded pins unvalidated, and replaces groups with no confirmation or undo (`persistence.lua`) | R1–R3 |
| B4 | Keyboard menus override `gui.MouseX/MouseY` inside the `pcall`ed function; if the menu opener errors, the restore line never runs and **`gui.MouseX` stays broken for every addon** (`keyboard/menu.lua`) | §19.5 |
| B5 | `DermaMenu` and `vgui.Create` replaced globally during capture; tool population replaces `controlpanel.Get` and re-fires `PostReloadToolsMenu` (`keyboard/menu.lua`, `helpers.lua`) | R5 |
| B6 | `ThrottleScroll` is leading-edge only and can drop the final layout (`helpers.lua`) | trailing throttle (L3) |
| B7 | Write storms: `Save()` on every colour-mixer tick and collapse toggle; `Pin()` re-reads and decodes the file per pin (N+1 reads per restore); `ClearSavedPin` reads then writes | debounced storage (R9) |
| B8 | Renaming a group is lost at the next rebuild or reload (`groups.lua` ignores `customTitle`) | window `title` (E33) |
| B9 | Each grouped pin keeps a hidden full `DFrame` with chrome, 8 zones, buttons, hooks | tabs have no frame (D2) |
| B10 | 7 `Think` hooks poll keys; none checks chat, console, escape menu or window focus | §17 |
| B11 | Suppression relies on `PlayerBindPress`, which never fires for F1–F12; default cursor key is F4 (G6) | binder warning (E15) |
| B12 | Hardcoded English: cursor banner, quick-key conflict line, "Clear" button, 3 "Error loading…" labels | `L()` only |
| B13 | Keybind names computed once at load, stale after a language change (`keyboard/keybinds.lua`) | labels resolved at display |
| B14 | Palette sorts categories by English names while entries carry localized ones, so order breaks in every language except English (`command_palette.lua`) | order by ID |
| B15 | Minimize with the taskbar disabled hides the window into a taskbar that doesn't exist | E23 |
| B16 | `PinFrame`/`ScanFrames`/`IsPinnedFrame` have no callers, yet `kind == "frame"` is special-cased in 7 files. They also couldn't work: `ScanFrames` compares `GetClassName()` (engine class) to `"DFrame"`, which never matches (G42); `PinFrame` reparents the whole popup, which loses input (G45); pins are keyed by `tostring(panel)`, so nothing survives a restart | rebuilt properly (§33, D7, D19) |
| B17 | Resolution change rescales `x,y` only; sizes, crop bases, tab sizes, maximize bounds untouched; saved `w,h` never rescaled on load | `Layout.RescaleAll` (E3) |
| B18 | `pp_*` commands share GMod's post-processing namespace; `concommand.Add` silently fails on a clash (G32) | `pinnedpanels_` (D4) |
| B19 | Cursor banner uses a never-freed 1024×32 render target for one line of text (G29) | cached text (L8) |
| B20 | Unpinning a group records each member separately in "recently closed" | whole-window entries (E21) |
| B21 | Settings colour rows save on every mixer tick | covered by B7 |
| B22 | Layout editor has its own snapping with a hardcoded 8 px, ignoring snap settings | `Geom.Snap` |
| B23 | Taskbar allocates a `Color` per entry per frame and calls `Material()` in `Paint` — "very expensive" per the wiki (G29) | cached |
| B24 | Arrows and Enter captured globally by default whenever any window is visible | default off (D8) |
| B25 | 4 keys missing from all 8 non-English files | lang check |
| B26 | Restore waits for `spawnmenu.GetTools()` to be truthy, but it's always a table (G12), so the check never waits and restore really depends on `timer.Simple(1)` | `PostReloadToolsMenu` (E2) |
| B27 | Maximizing a cropped window clears the crop permanently | crop suspended (E28) |
| B28 | UI timing uses `CurTime`/`FrameTime`: key repeat, save debounce, scroll throttle, nav idle, taskbar idle timeout and pulse animations freeze on pause and scale with `host_timescale`; taskbar fades use `FrameTime` (G5) | `RealTime`/`RealFrameTime` |
| B29 | Taskbar `PaintOver` calls `DisableClipping(false)` instead of restoring the previous state (G28) | restore returned state |
| B30 | "Equip tool" runs `gmod_toolmode`, then `spawnmenu.ActivateTool` (which already runs the tool's `gmod_tool` command), then `input.SelectWeapon` (G16) | one `ActivateTool` call |
| B31 | Keyboard key convars are set with `RunConsoleCommand` plus a hand-maintained cache because the change isn't immediate (G33) | `ConVar:SetX` |
| B32 | A window takes **keyboard input whenever the mouse hovers a text box** (`frame.lua` `Think`), so walking stops while the cursor rests over a text field in cursor mode | focus hooks (G20, E14) |

## 31. Open decisions

| # | Question | Options | Recommendation |
|---|---|---|---|
| D1 | Read v1 layouts/settings? | importer · **none** | **None** — confirmed in Phase 0 |
| D2 | Unify pins and groups | separate kinds · **windows with tabs** | **Windows with tabs** — removes hidden frames (B9), group rebuilds, per-tab sync code and the pin/group data split |
| D3 | Settings storage | JSON file · `cookie` · **client convars** | **Convars**: engine persistence and clamping, console access, change callbacks, stock convar binding for controls |
| D4 | Command/convar prefix | `pp_` · **`pinnedpanels_`** | **`pinnedpanels_`** (G32, B18) — confirmed in Phase 0 |
| D5 | Translations | Lua tables + in-addon override · **`.properties`** | **`.properties`** — native fallback, `#key` in Derma, no Lua loaded for strings; follows the game language (the spawn menu already rebuilds on change, G11) |
| D6 | Styling | Derma skin · **our controls paint from theme tokens** | **Theme tokens**: a skin on a window would be inherited by hosted tool panels (G22) and `SetSkin` refreshes every panel |
| D7 | v1's "pin a live DFrame" code | keep · **drop and rebuild** | **Drop the v1 code** (B16); the feature is redesigned in §33 |
| D8 | Nav outside cursor mode by default | on (v1) · **off** | **Off** (B24) |
| D9 | Keyboard menus | scrape a hidden DMenu · **drive the real DMenu** | **Drive it** (G17); foreign-menu discovery per Phase 0 spike |
| D10 | Same source pinned twice | yes · **no** | **No**, as v1 (E22) |
| D11 | Strategy | **clean slate** · incremental | **Clean slate**: the closure-built UI and pin/group split don't convert piecemeal |
| D12 | Loading | auto-loader · **explicit list** | **Explicit list** in the one autorun file (24 files, one order for server and client) |
| D13 | Tab building | eager · **lazy** | **Lazy** (§16.2) |
| D14 | Collapse memory | in the layout doc (v1) · **`DCollapsibleCategory` cookies** | **Cookies** (G23): ~10 lines instead of wrapping `OnToggle`; trade-off: not included in exported layouts |
| D15 | Console | one dispatcher · **one command per action** | **One command per action** (`pinnedpanels_<id>`): shows up in console autocomplete and binds naturally |
| D16 | Restore cursor position when toggling cursor mode (like the spawn menu, G9) | yes · no | **Yes if trivial** (two calls); otherwise move to §32 |
| D17 | "Rebuild content" action for tool tabs (G15) | add · skip | **Add**: small, fixes a real staleness limit |
| D18 | Global name | **`PinnedPanels`** · `PP` | **Keep `PinnedPanels`** |
| D19 | When to ship "pin any panel" (§33) | in 2.0 · **as the core of 2.1** | **Core of 2.1** (§33.16, ≈ 15 days), with the §33.15 spike in Phase 0 so the approach is proven before 2.0's window, input and source code is finalized. 2.1-a (picker + Manage) alone delivers the original vision for most windows |
| D20 | Unit tests | offline suite · **none** | **None**: the owner tests in game and reports problems (decided after Phase 2; the suite was removed) |
| D21 | Tool scripts and CI | `tools/` + CI · **none** | **None**: rules are checked by review, translations and the Phase 0 spike by hand (decided after Phase 2; `tools/` and CI were removed) |

---

# Part V — Future

## 32. Future features

None of this is in 2.0 (§2 non-goals). Each item says what it is, why it fits Pinned Panels, how the v2 design supports it, and what it costs. IDs are **FF**-numbers so issues and commits can cite them. Anything else that comes up during the rewrite gets added here instead of being built.

**Effort:** S ≈ ½ day · M ≈ 1–2 days · L ≈ 3+ days. **Value:** how much it changes day-to-day building, from ★ to ★★★.

### 32.1 The big ideas

These change what the addon *is*, and each is cheap because of a v2 design choice.

| ID | Feature | Why | How (v2 hooks in) | Effort · Value |
|---|---|---|---|---|
| FF1 | **Active tool window** — a special tab that always shows the control panel of the tool currently selected on the tool gun | The most common reason to open the spawn menu is to tweak the current tool. One window that follows you replaces pinning 20 tools | A new source kind `active:tool` in `sources.lua`; watches the `gmod_toolmode` client convar with `cvars.AddChangeCallback` and rebuilds its host with the new tool's panel (§14.2). Lazy building and the tab host already exist | M · ★★★ |
| FF2 | **Pin a single control** — right-click any slider, checkbox or dropdown inside a pinned panel → "Pin this control" into a compact *Quick controls* window | Most builders only touch 2–3 settings per tool (weld strength, rope width, material). A strip of just those beats whole panels | Stock convar-bound controls keep their convar in `m_strConVar` (on the inner button for checkboxes, on the scratch/text area for sliders, S `derma/init.lua`, `dnumslider.lua`, `dcheckbox.lua`). v2 walks up from the right-clicked element to find it, reads the label, and stores `{ convar, label, kind, min, max }` as a new source kind `convar:`. Rebuilt with our own convar-bound controls, so it survives tool rebuilds (G15). Controls with no convar get the entry greyed out | M · ★★★ |
| FF3 | **Layout profiles** — named layouts ("Building", "Posing", "Wiring", "Screenshots") switched from the palette, a key, or the Pinned page | Different jobs need different windows; today you unpin and re-pin | The document already holds everything; a profile is one more document in `data/pinnedpanels/profiles/<name>.json` through the same `storage.lua` (atomic write, sanitize). Switching = `Storage.Replace` + desktop reconcile | M · ★★★ |
| FF4 | **Visibility rules** per window: show only while holding the tool gun / a given weapon / a given tool mode, hide in vehicles, hide while dead, hide while holding the camera | Windows that appear only when relevant keep the screen clean without manual hiding | A `rules` field on the window record; `desktop` re-evaluates them on the `gmod_toolmode` change callback and by checking the active weapon, alive and vehicle state a few times per second (not per frame). Pairs with FF1 and FF3 | M · ★★ |
| FF5 | **Context-menu mode** — windows can be set to appear (and be interactive) only while the C menu is held, like GMod's own tool panel | Many players want panels out of the way until they reach for them, with zero new keys to learn | `OnContextMenuOpen` / `OnContextMenuClose` (W) feed one more reason into `Input.Cursor` and a `showWith = "contextmenu"` window field. Also the simplest answer to "make windows interactive while C is held" | S · ★★ |

### 32.2 Windows & layout

| ID | Feature | Why | How | Effort · Value |
|---|---|---|---|---|
| FF6 | **Roll-up** — double-click a header to collapse the window to its title bar | Keeps a window's place without its bulk; a classic desktop feature that fits floating tool panels | `state = "rolled"` in the record; the window's `PerformLayout` hides the host. Taskbar untouched | S · ★★ |
| FF7 | **Drag tabs between windows** — drag a tab onto another window to merge, out onto the desktop to split | Makes groups discoverable; today grouping lives in menus | Derma drag-and-drop (`Panel:Droppable`, `Panel:Receiver`) on the tab strip, calling the existing `Layout.MoveTab` | M · ★★ |
| FF8 | **Docks** — screen-edge columns that stack windows vertically and share the height | Tidy "sidebar" setups without hand-aligning windows | A dock is a record in the document with an ordered list of window IDs; `desktop` lays them out; snapping already knows the screen edges (`Geom`) | L · ★★ |
| FF9 | **Linked windows** — windows snapped together move together | Keeps a built arrangement intact while repositioning it | `links` computed from snapped edges on drag end; drag moves the linked set; ALT breaks the link | M · ★ |
| FF10 | **Layout undo/redo** (move, resize, close, merge, crop) | Mis-drags and accidental unpins are common; "reopen closed" only covers one case | `Layout` is the single writer, so each operation can push the previous record(s) to a small ring buffer (50 steps). `pinnedpanels_undo` / `_redo` actions | S · ★★ |
| FF11 | **Hover fade-in** — idle windows fade to full opacity when the cursor approaches | Idle opacity keeps windows readable at a glance without cursor mode | Opacity rule gains a "cursor near" term (§16.3), only while cursor mode or a cursor reason is active | S · ★ |
| FF12 | **Auto-layout presets** — "stack right", "grid", "cascade" in addition to Arrange | One-click tidy-up for different screen shapes | Pure functions in `util.lua` next to `Arrange`, unit-testable | S · ★ |

### 32.3 Tools & content

| ID | Feature | Why | How | Effort · Value |
|---|---|---|---|---|
| FF13 | **Server tool restrictions shown in windows** — a banner like the spawn menu's when a pinned tool is disabled on this server (`toolmode_allow_<tool>` = 0 or `CanTool` refuses) or the player has no tool gun | Avoids "why doesn't my weld work" on servers that restrict tools; parity with the spawn menu | The spawn menu polls these every 1.5 s because `toolmode_allow_*` is replicated and change callbacks don't fire for it on the client (S `toolpanel.lua`, G33). The tab host does the same while visible | S · ★★ |
| FF14 | **Automatic rebuild when a tool rebuilds its panel** | Removes the one staleness case left in 2.0 (G15, E10) | Detect when the spawn menu's copy (`controlpanel.Get(mode)`) was cleared and refilled — for example by comparing its child list when our tab is shown — then rebuild ours. Needs a spike to avoid creating panels just to look | M · ★ |
| FF15 | **Pin a spawnlist folder** — one spawnlist (or a search) as its own window instead of the whole Spawnlists tab | Builders reuse a handful of prop folders; a small icon grid is faster than the full browser | A `spawnlist:` source that builds a content container from `spawnmenu.GetPropTable()` / `GetCustomPropTable()` entries with `spawnmenu.CreateContentIcon` (S `spawnmenu` module) | M · ★★ |
| FF16 | **Pin any panel** from the game or Workshop addons — the addon's original goal | See §33 for feasibility, limits and design | Picker + Manage / Embed + recipes + Record (§33) | L · ★★★ |
| FF17 | **Recent & favourite tools** in the hub and palette; the palette ranks by use | Speeds up the most common action in the addon | Usage counts in a cookie (session-independent, not in the layout); `Fuzzy.Score` gets a small bonus term | S · ★★ |

### 32.4 Keyboard

| ID | Feature | Why | How | Effort · Value |
|---|---|---|---|---|
| FF18 | **Jump hints** — press a key and every control in the focused window shows a 1–2 letter label; type it to jump there (like browser "hint" extensions) | Much faster than arrowing through long tool panels | Reuses `Nav.Scan` and the focus ring painter; labels drawn in the window's `PaintOver` | M · ★★ |
| FF19 | **Modifier shortcuts** (Ctrl/Shift/Alt + key) | Single keys run out fast and clash with game binds (E30) | Bindings store `{ key, mods }`; the dispatcher checks modifiers; a small custom binder replaces the plain `DBinder` for these rows | M · ★★ |
| FF20 | **Keyboard cheat sheet** — hold a key to overlay the current bindings | Discoverability for the 17+ bindable actions | Generated from the action list (§18), drawn by `hud.lua` | S · ★ |

### 32.5 Look & accessibility

| ID | Feature | Why | How | Effort · Value |
|---|---|---|---|---|
| FF21 | **Theme presets** (dark, light, translucent, high contrast) + export/import of a theme | Fast restyling; high contrast helps readability over bright maps | Themes are sets of the colour settings (§21); a preset applies several convars at once | S · ★ |
| FF22 | **UI scale** for our own chrome (header, taskbar, palette, hub) on 1440p/4K | Fixed pixel sizes are tiny on large screens | A scale setting feeding `theme.lua` sizes and a small fixed set of font sizes (G29: no per-size font creation). Hosted tool panels can't be scaled (Derma has no transform), so this only covers our parts | M · ★★ |
| FF23 | **Hide for screenshots** — hide all windows while holding the camera, and a "hide all" toggle | Pinned windows are popups, not HUD, so they show up in camera shots | Visibility rule (FF4) on `gmod_camera`; the screenshot key itself can't be detected (F5 is an F-key, G6), so the toggle covers other cases | S · ★★ |
| FF24 | **More languages** (ja, ko, uk, zh-TW, it, cs, …) | Wider audience; `.properties` makes it a data-only change | New files under `resource/localization/` | S each · ★ |

### 32.6 For other addons

| ID | Feature | Why | How | Effort · Value |
|---|---|---|---|---|
| FF25 | **Public API** — `PinnedPanels.RegisterSource`, `RegisterAction`, `Nav.Control`, `Pin`/`Unpin`, stable events | Lets other addons make their own panels pinnable and keyboard-navigable without patching Pinned Panels | The registries already exist internally (§14, §18, §19.4); the work is freezing their shape, versioning it (`PinnedPanels.API`) and documenting it | M · ★★ |
| FF26 | **Wiremod / Advanced Duplicator 2 adapters** as the first API users | Popular build addons with complex panels; proves the API | Nav control adapters for their custom controls, and a source for AD2's file browser | M · ★ |

### 32.7 Suggested order

1. **2.1 — "Pin anything"**: FF16 / §33 (D19), then FF1 Active tool window, FF2 Pin a single control, FF5 Context-menu mode, FF6 Roll-up, FF10 Undo, FF13 Server restrictions. All build directly on 2.0 pieces and change daily use the most.
2. **2.2 — "Right windows at the right time"**: FF3 Profiles, FF4 Visibility rules, FF23 Hide for screenshots, FF17 Recent & favourites, FF7 Drag tabs.
3. **2.3 — "Power users & extensibility"**: FF18 Jump hints, FF19 Modifier shortcuts, FF25 Public API, FF26 Adapters, FF22 UI scale.
4. **Later / on demand**: FF8 Docks, FF9 Linked windows, FF11, FF12, FF14, FF15, FF20, FF21, FF24.

### 32.8 Considered and rejected

| Idea | Why not |
|---|---|
| Scaling hosted tool panels (zoom a whole window) | Derma has no transform for child panels; only our own chrome can scale (FF22) |
| Syncing layouts between computers or players through a server | Pinned Panels is client-only by design; export strings and profiles (FF3) cover sharing |
| Detecting the screenshot key to hide windows | `jpeg` is usually on F5 and `PlayerBindPress` doesn't fire for F-keys (G6); FF23 uses the camera weapon instead |
| Running pinned panels while the escape menu is open | The escape menu should stay GMod's; E27 hides windows there |

## 33. Pinning any panel from the game or from Workshop addons

The original goal of Pinned Panels was to pin **any** frame or panel: a Workshop addon's settings window, the E2 editor, Super DOF, a gamemode menu, part of another addon's UI. v1 tried (`PinFrame` / `ScanFrames`) and it never worked. This section is the result of a deeper research pass (wiki, the GMod base Lua source, the Facepunch issue tracker). **2.1 is built around it** (D19).

### 33.1 Verdict

**Possible for every panel made in Lua**, which covers nearly all addon and gamemode UI. **Impossible for everything that isn't a Lua panel** (§33.12). Three things make it work:

1. **Manage, don't move.** By default v2 does **not** reparent another addon's window. It leaves the window where the addon put it and *manages* it with public, reversible panel methods (`SetPos`, `SetSize`, `SetVisible`, `SetAlpha`, `SetMouseInputEnabled`, `SetKeyboardInputEnabled`, `MoveToFront`). That's enough for geometry memory, minimize to taskbar, idle fade, click-through, lock, quick keys, peek, profiles, and — the big one — **keeping an addon's window on screen while you play**. Nothing is reparented, so none of the popup bugs apply (G45, G52).
2. **Embed only on request.** For full Pinned Panels features (groups, crop, filter, keyboard nav), v2 can move the window's *contents* (never the window) into a pinned window. This is riskier and depends on how the addon is written, so it's opt-in per window.
3. **Recipes, not panels, are saved.** A live panel can't survive a restart. v2 saves how to get it back: native builders where the game exposes them (desktop widgets, post-process panels, registered classes), the console command that opens it, or a watch that grabs it when it reappears. A time-boxed **Record** mode finds the opener automatically by reading the call stack when the window is created (§33.9).

**Why v1 failed** (all confirmed):
1. `ScanFrames` kept panels where `GetClassName() == "DFrame"`, but `GetClassName` returns the engine base class (G42), so it found nothing.
2. `PinFrame` reparented the popup window itself. After `MakePopup` a panel's position is treated in screen space even when parented (G52), and Facepunch's own code says moving windows "causes loss of input" (G45).
3. Pins were keyed by `tostring(panel)` (a memory address), so nothing survived a restart.

### 33.2 Research findings

**W** = wiki, **S** = GMod base source (`Facepunch/garrysmod`), **I** = Facepunch issue tracker (`Facepunch/garrysmod-issues`).

**Finding panels**

| ID | Finding (source) | Consequence |
|---|---|---|
| G40 | `vgui.GetAll()` returns every **Lua-created** panel; meant for auto-refresh; includes panels marked for deletion until they go (W) | The picker and the HUD fallback use it; never per frame |
| G41 | `vgui.GetWorldPanel()` is the parent of every panel except the HUD panel (W). A frame created with no parent ends up under it, and walking its children finds frames (I #802 report) ⚑ verify | Watching for new windows = diffing the world panel's children |
| G51 | `ParentToHUD()` does **not** parent to `GetHUDPanel()` but to "a completely different panel" (a Facepunch developer, I #802). `GetHUDPanel():GetChildren()` doesn't see those | HUD-parented windows can only be found through `vgui.GetAll()` |
| G42 | `GetClassName()` returns the engine class, "not Lua classname" (W). `vgui.Create` stores the Lua class in `panel.ClassName` and passes it as the panel's name (S `scriptedpanels.lua`) | Identify by `ClassName`, `GetName()`, title and source file (§33.8) |
| G53 | `vgui.RegisterTable` + `vgui.CreateFromTable` create **unnamed** classes: no `ClassName`, the name defaults to the base (`"DFrame"`). The class's functions are **copied into the panel** (`table.Merge`) (S `scriptedpanels.lua`). The base game's own Super DOF window works this way, opened by `pp_superdof` (S `postprocess/super_dof.lua`) | A class recipe can't work for these; a command recipe can. `debug.getinfo` on the copied functions still reveals the file that built the window |
| G54 | `vgui.GetControlTable(name)` / `vgui.Exists(name)` read the registered class table; `derma.GetControlList()` lists stock Derma controls (S `scriptedpanels.lua`, `derma.lua`) | Tell addon classes from stock controls; find a panel's base class |
| G55 | `PANEL:OnChildAdded` is called **before** the child's metatable is set (W, I #2759, open) | Can't be used to detect new windows reliably; polling is used instead |
| G56 | Walking children by index while changing the tree can crash the client (I #1565) | Always snapshot `GetChildren()` before moving anything |
| G49 | `vgui.GetHoveredPanel()` is one frame late (W) | Fine for a click-to-pick tool |

**Moving panels**

| ID | Finding (source) | Consequence |
|---|---|---|
| G44 | GMod moves **non-popup** panels between windows routinely: the context menu reparents `spawnmenu.ActiveControlPanel()` into itself and back to `OldParent` (S `contextmenu.lua`) | Moving a window's contents is a supported pattern (Embed, §33.6) |
| G45 | Moving a **window** is not: *"Changing parents causes loss of input and I don't have time to figure out why"*; the context menu removes a moved window instead of moving it back. The only pop-out GMod does is `SetParent()` + `MakePopup()` (S `contextmenu.lua`, `editor_player.lua`) | Never reparent a foreign popup |
| G52 | After `MakePopup`, a panel "unparents"; it stays parented but its position is in screen space (I #2606) | Confirms G45; explains v1's broken positions |
| G43 | `Panel:IsPopup()`, `IsModal()`, `DoModal()` (W) | Popups → Manage; modal → refuse |
| G57 | `DFrame` chrome is `btnClose`, `btnMaxim`, `btnMinim`, `lblTitle` (+ optional `imgIcon`); `DockPadding(5, 29, 5, 5)`; `Close()` = hide, **`Remove()` if `DeleteOnClose` (default true)**, then `OnClose()`; `SetDraggable`, `SetSizable`, `SetScreenLock`, `ShowCloseButton` are public (S `dframe.lua`) | Minimize must use `SetVisible(false)`, never `Close()`; lock uses `SetDraggable/SetSizable(false)`; Embed skips the chrome and mirrors the dock padding |
| G58 | `Panel:Remove()` is deferred to the next frame; children are removed in later frames; `IsMarkedForDeletion()` tells (W) | Watchers check `IsMarkedForDeletion()`, not just `IsValid()` |
| G59 | `Panel:MoveToFront()`: a non-popup always draws behind popups (W) | Managed popups and our windows are popups; z-order is managed with `MoveToFront` |
| G27 | `SetAlpha` multiplies children and doesn't block input (W) | Idle fade works on foreign windows; interactivity is separate |
| G50 | `PaintAt` "briefly unparents and reparents the panel" each call; `PaintManual` needs `SetPaintedManually(true)` (W); GMod uses manual painting for the icon editor preview (S `iconeditor.lua`) | No live mirrors (§33.12) |

**Finding the opener and the owner**

| ID | Finding (source) | Consequence |
|---|---|---|
| G48 | `concommand.GetTable()` returns every Lua command name → callback (W, S `concommand.lua`); no hook is fired when a command runs (S `concommand.lua`) | Command callbacks can be matched against the window's source file or the call stack |
| G60 | `net.Receivers` is a public table: message name (lowercase) → handler (S `includes/extensions/net.lua`) | A window created inside a net handler was opened by the server → `watch` recipe |
| G61 | `hook.GetTable()` returns every hook name → id → function (W) | A window created inside a hook (e.g. a key hook) → `watch` recipe with a hint |
| G62 | `debug.getinfo(fn or level, "fS")` returns the function and its `short_src`/`linedefined` in every realm (W). `debug.getlocal`/`getupvalue` still exist but are **deprecated**; `setlocal`/`setupvalue` were **removed for security** (W `debug`) | Identification and Record mode use `getinfo` only; `getlocal` is an optional extra (command arguments) |
| G63 | `engine.GetAddons()` lists mounted Workshop addons (`title`, `wsid`, `file`, `mounted`); an addon's GMA title can be used as a file-search path (`file.Find`/`file.Exists(path, title)`) (W `engine.GetAddons`, `file.Find`, `File_Search_Paths`) | Map a window's source file to "Wiremod" / "Advanced Duplicator 2" for the picker and the Pinned list |
| G47 | `list.Get("DesktopWindows")` entries `{ title, icon, width, height, onewindow, init(icon, window) }`; the context menu builds each with `init` (S `contextmenu.lua`, `editor_player.lua`) | Native `desktop:` source |
| G64 | `list.Get("PostProcess")` entries have either `cpanel(CPanel)` (e.g. Bloom) or `onclick` (e.g. Super DOF runs `pp_superdof`) (S `postprocess/bloom.lua`, `super_dof.lua`) | Native `postprocess:` source for `cpanel` entries; `command:` for `onclick` ones |
| G46 | `vgui.Create(class)` creates the base, merges the class and calls `Init` (S `scriptedpanels.lua`) | `class:` recipe for self-building classes |

**Input**

| ID | Finding (source) | Consequence |
|---|---|---|
| G65 | `VGUIMousePressed(panel, mouseCode)` fires for mouse presses on any panel (W); Derma uses it to close menus (S `derma_menus.lua`) | Click-to-focus for managed and embedded windows that need the keyboard (§33.5) |
| G20 | `DTextEntry` fires `OnTextEntryGetFocus`/`LoseFocus` (S) | Typing into fields of managed/embedded windows without keeping the keyboard the rest of the time |
| G6 | `PlayerBindPress` is not called for F1–F12 (W) | Record mode can capture bound commands on other keys only |
| G66 | The main menu, escape menu and server browser run in the separate **menu** Lua state; states share no globals or panels (W `States`) | Out of reach (§33.12) |

### 33.3 What's on screen, and where it lives

| Where | What it is | Found through | Pinnable as |
|---|---|---|---|
| Children of the world panel | Normal windows (`DFrame`s, custom `EditablePanel` windows), usually popups | `vgui.GetWorldPanel():GetChildren()` (G41) | **Manage** (default) or **Embed** |
| HUD-parented panels | Derma HUD elements and windows using `ParentToHUD` | `vgui.GetAll()` only (G51) | **Manage**; often repositioned by their owner every frame (then not worth it) |
| Inside another window | A list, form or preview inside an addon's window, the spawn menu or the context menu | `vgui.GetHoveredPanel()` + walking parents (picker) | **Embed a part** |
| Game registries | C-menu desktop widgets, post-process panels, tools, content tabs | `list.Get("DesktopWindows")`, `list.Get("PostProcess")`, `spawnmenu.*` | **Native** (our own instance) |
| Engine and menu state | Console, chat, options, server browser, main/escape menu | not reachable | ✗ (§33.12) |
| Drawn, not panels | HUDs drawn in `HUDPaint`, 3D2D screens | nothing to take | ✗ (§33.12) |

### 33.4 The three integration modes

| | **Native** | **Manage** | **Embed** (window contents / a part) |
|---|---|---|---|
| What happens | We build our own instance (`init`, `cpanel`, class, tool, content tab) inside a normal pinned tab | The foreign window stays where it is; we control its public properties | Its content children move into a pinned tab; the original window is kept alive but invisible |
| Reparenting | none (ours) | **none** | contents only (never a popup) |
| Remember position/size | ✓ | ✓ (re-applied every time it appears) | ✓ |
| Minimize to taskbar, restore | ✓ | ✓ (`SetVisible`) | ✓ |
| Visible while playing (no cursor, no input) | ✓ | ✓ — the headline feature | ✓ |
| Idle fade, click-through, lock, quick key, peek | ✓ | ✓ | ✓ |
| Tabs / groups, crop, filter bar, keyboard nav, auto-size | ✓ | ✗ (it's their window) | ✓ |
| Our header, colours, rename | ✓ | ✗ (their title bar) | ✓ |
| Comes back after restart | ✓ always | via recipe (§33.9) | via recipe (§33.9) |
| Risk of breaking the other addon | none | very low | medium (depends on the addon's code) |
| Default for | registry sources | any top-level window | nothing — opt-in ("Embed for full features") |

### 33.5 Manage mode in detail (`manage.lua`)

**Taking a window under management:**
1. Record its **original state**: position, size, visibility, alpha, mouse/keyboard input flags, and for a `DFrame` also draggable, sizable and screen lock (G57).
2. Create a *managed window record* in the layout document (`kind = "managed"`, signature, recipe, geometry, flags). It shows in the Pinned list, the layout editor (as a box without our header), the taskbar, the palette and profiles like any other window.
3. Apply our state.

**What v2 applies, using public methods only:**

| Our feature | Applied as |
|---|---|
| Geometry | `SetPos`/`SetSize` from the record; applied again every time the window (re)appears |
| Minimize / restore | `SetVisible(false/true)` — never `Close()`, which usually removes the window (G57) |
| Outside cursor mode | `SetMouseInputEnabled(false)`, `SetKeyboardInputEnabled(false)`: the window stays on screen and the player moves and aims normally. This is exactly what v1 does to its own popup windows |
| In cursor mode / spawn menu open | `SetMouseInputEnabled(true)`; keyboard per the focus rule below |
| Idle opacity, peek | `SetAlpha` (G27) |
| Click-through | mouse input off even in cursor mode; ALT turns it back on |
| Lock | `DFrame:SetDraggable(false)`, `SetSizable(false)`; we stop applying user moves |
| Focus / bring to front | `MoveToFront()` (G59) |

**Keyboard focus rule** (managed and embedded windows):
- A text field inside gets focus → that window takes the keyboard (G20).
- A window flagged **needs keyboard** (auto-set when it had keyboard input when taken; user-toggleable) also takes the keyboard when clicked in cursor mode (`VGUIMousePressed`, G65). This covers custom editors that aren't `DTextEntry`, like Wiremod's E2 editor.
- Leaving cursor mode or clicking elsewhere gives the keyboard back to the game.

**Keeping it applied** — a watcher at 4 Hz, only while at least one managed window exists:
- *Removed* (`!IsValid` or `IsMarkedForDeletion`, G58) → the record goes **waiting**; the recipe decides whether it comes back (§33.9).
- *Hidden by the addon* → the taskbar entry shows "closed by addon".
- *Shown again, recreated, or re-popped* (`MakePopup` turns input back on) → re-apply our state.
- *Moved by the user through its own title bar* → store the new geometry and snap it once after the mouse is released.
- *Moved by the addon on every check* ("fighting", e.g. a HUD that positions itself every frame) → stop applying geometry and tell the user this window can't be positioned.

**Release** (unpin, `pinnedpanels_reload`, or the window's recipe deleted): restore every recorded original property.

### 33.6 Embed mode in detail (`embed.lua`)

**Embed a window's contents** — for full features, offered in the picker and on managed windows ("Embed for full features — may not work with every addon"):
1. Snapshot `shell:GetChildren()` (G56). Skip the `DFrame` chrome (G57).
2. Create an **inner panel** in a new tab host with the shell's size and dock padding. Add a crop of the title strip (29 px for a `DFrame`) so child positions, docking and the owner's layout math stay identical.
3. For each child, record parent, z-order, dock, dock margins, position and size, then `SetParent(inner)` in the same order.
4. **Ghost the shell**: mouse and keyboard off, `SetAlpha(0)`, kept **visible** so its `Think` keeps running (G4); many addons refresh their UI in the window's `Think`. Keep its size synced with the tab, so the owner's `PerformLayout` computes with the right sizes. ⚑ verify whether `SetPaintedManually(true)` stops painting while keeping `Think` alive; that would be cheaper than alpha 0.
5. **Watcher**:
   - Shell marked for deletion (the addon closed it) → remove the adopted children too (honouring the owner's intent and running their `OnRemove`); the tab goes waiting.
   - New children appear in the shell (the addon rebuilt its UI) → adopt them.
   - Shell hidden by the addon → the tab shows "closed by addon".
6. **Release**: move children back in their original order with their original layout; drop the inner panel; `InvalidateLayout(true)` on the shell; restore its alpha, input and visibility.

**Embed a part** (a list, form or preview inside any window):
1. Put an invisible **placeholder** in its place with the same dock, margins, size and z-order, so the owner's layout doesn't collapse.
2. Move the panel into the tab host; release restores it and removes the placeholder.

**Known breakers:**
- Children calling `self:GetParent()` expecting the original window (e.g. a button doing `self:GetParent():Close()`).
- Owners positioning children with screen coordinates (`LocalToScreen`).
- Owners that walk their own children by index.
- Children that are popups themselves (never moved; they stay managed).

The picker suggests Manage when any of these show up, and every embedded tab has "Return to managed mode".

### 33.7 The picker (`vgui/picker.lua`)

Open it from the hub ("Pin something on screen…"), the palette, or `pinnedpanels_pick`.
- A full-screen overlay with its own cursor reason. It highlights `vgui.GetHoveredPanel()` (G49) with an outline and an info card:
  - **Addon**: from the source file of the panel's functions (G62) mapped to a Workshop title (G63), or "Garry's Mod" for base files.
  - **Lua class** or "unnamed class" (G53), base class, name, window title, size.
  - **Suggested mode and recipe** (§33.9).
- **Mouse wheel / Up–Down**: walk to the parent or back to the child, to pick a whole window or just one part. **Left–Right**: cycle overlapping candidates.
- **Click**: pin with the suggested mode. **Right-click**: choose Manage / Embed / Embed part. **Escape**: cancel.
- **A second list view** ("Open windows") shows every top-level Lua window from the world panel plus `vgui.GetAll()` HUD windows (G41, G51), for windows that are hard to hover.
- **Refused, with the reason on the card**: our own panels; modal panels (G43); DMenus, tooltips, drag previews; panels marked for deletion; the spawn menu and context menu **roots** (their inner parts are fine).

### 33.8 Identification (signature)

Saved with every pin; used to recognise the window next time.

| Field | From | Stability |
|---|---|---|
| `src` | `short_src` of the class functions or the instance's own overridden functions (`Init`, `Paint`, `PerformLayout`, `OnClose`, children's `DoClick`) (G62) | **strongest**: survives language changes and anonymous classes |
| `addon` | `src` mapped through `engine.GetAddons()` (G63) | display, and to mark the pin *unavailable* when the addon isn't mounted |
| `class` | `panel.ClassName` (G42) | strong when present |
| `base` | the registered base (G54), engine class | weak |
| `title` | `DFrame:GetTitle()` | medium (may be localized or dynamic) |
| `size` | `GetSize()` | weak tie-breaker |
| `path` | for parts: the index path and class chain from the window root to the part | needed to find the same part again |

Matching scores `src` + `class` + `title` + `size`. A weak match (no `src`, no `class`) asks the user once ("Is this the window you pinned?") before auto-taking it.

Example — Super DOF: `class` none (G53), name `"DFrame"`, `src` `lua/postprocess/super_dof.lua`, `addon` "Garry's Mod".

### 33.9 Getting it back: recipes (`recipes.lua`)

| Recipe | How it comes back | Found by | Examples |
|---|---|---|---|
| `tool:`, `creation:` (2.0) | Built natively (§14) | catalogue | every tool, spawn-menu content tabs |
| `desktop:<id>` | Native: our tab provides the window and we call `init(icon, window)` (G47) | the picker sees the window came from a desktop widget, or the hub lists them | Player model editor, addon C-menu widgets |
| `postprocess:<name>` | Native: a `ControlPanel` filled by the entry's `cpanel` (G64) | hub list | Bloom, Sharpen, Sobel, Toy Town, DOF |
| `class:<ClassName>` | `vgui.Create(ClassName)` (G46), then Manage/Embed | panel has a registered, non-stock class (G54) | addon windows whose `Init` builds everything |
| `command:<cmd> [args]` | Run the command, then **catch** the new window (up to 3 s) and Manage/Embed it | static match or Record mode | Super DOF (`pp_superdof`), addons with an "open menu" command |
| `watch` | No opener known: wait; take it whenever a matching window appears | fallback; server- or key-opened windows | gamemode menus opened through the server |
| `clone` (experimental, off by default) | Build a class table from the instance's own functions and its base, `vgui.CreateFromTable` it | unnamed classes without an opener (G53) | self-contained unnamed windows; breaks addons that keep a reference to "their" window |
| `session` | Not restored | last resort | one-off dialogs |

**Automatic recipe detection**, in order:
1. **Registries**: is it a desktop widget or post-process panel? → native.
2. **Static match**: callbacks in `concommand.GetTable()` (G48) defined in the same file as the window (`src`). One match → suggest `command:`; several → list them.
3. **Record mode** (the reliable one):
   - The user clicks **Record**, then opens the window the normal way (menu, key, command, button). Recording lasts at most 30 s.
   - During recording, `vgui.Create` and `vgui.CreateFromTable` are wrapped **inside the audited override helper** (R5; restored on every path, on timeout and on `ShutDown`).
   - When a top-level panel is created (no parent), walk the stack with `debug.getinfo(level, "fS")` (G62) and compare each function against:
     - `concommand.GetTable()` → exact command name (arguments via deprecated `debug.getlocal` when available);
     - `net.Receivers` → "opened by the server" → `watch`;
     - `hook.GetTable()` → "opened by hook *X*" → `watch` with that hint;
     - `list.Get("DesktopWindows")` `init` functions → `desktop:`.
   - Also listen to `PlayerBindPress` during recording to show which bind the player pressed (not F-keys, G6).
4. Otherwise `watch`, with `session` as the explicit alternative.

**Catching a window** (for `command:` and `watch`): compare the world panel's children with the previous snapshot whenever their count changes (at most twice a second, and only while something is waiting), plus a `vgui.GetAll()` scan once a second for HUD-parented targets (G51). Score candidates by signature (§33.8).

**Imported layouts**: `desktop:`, `postprocess:`, `class:` and `watch` are kept. `command:` becomes `watch` unless the user confirms each command. A shared layout string must never run commands on its own (extends R4).

### 33.10 Data model additions

```
window.kind = "pinned" | "managed"          -- managed = a foreign window we control in place (§33.5)
tab.src     = … | "desktop:<id>" | "postprocess:<name>" | "adopt:<sig-id>"
record.adopt = {
  mode      = "manage" | "embed" | "part",
  signature = { src, addon, class, base, title, w, h, path? },
  recipe    = { kind = "class"|"command"|"watch"|"clone"|"session", class?, command?, args?, confirmed? },
  needsKeyboard = true | false,
}
```
Live bookkeeping (original properties, moved children, placeholders) is never saved; it's rebuilt when the window is taken again.

### 33.11 Safety rules (added to §8)

| ID | Rule |
|---|---|
| R11 | Never take our own panels, modal panels, menus, tooltips, drag previews, or the spawn/context menu roots |
| R12 | Only public panel methods are used on foreign panels; every change is recorded and restored on release |
| R13 | The only foreign code we call: the chosen recipe's opener (`init`, `cpanel`, class `Init`, the confirmed command), under `ProtectedCall` (G38) |
| R14 | Global wrapping happens only during an explicit Record session, through the R5 helper, and is always restored |
| R15 | A foreign panel is only ever removed when its owner removed its window (embed cleanup) |
| R16 | Recipes that run commands are local; imported ones need confirmation (§33.9) |

### 33.12 What can't be pinned, and why

| Thing | Why | What v2 offers instead |
|---|---|---|
| Console, chat box, options dialog, server browser, loading screen | Engine (C++) panels, not Lua panels (G40) | — |
| Main menu, escape menu | Separate **menu** Lua state; no shared globals or panels (G66) | — |
| HUDs drawn in `HUDPaint`/`DrawOverlay`, crosshairs, most HUD addons | No panel exists, only draw calls | — |
| 3D2D in-world screens | Their owner paints them manually in 3D (`PaintManual`) | — |
| Modal dialogs (`DoModal`) | They hold all input by design (G43) | — |
| DMenus, tooltips, drag previews | Transient | — |
| A live mirror of a panel left in place | Only `PaintAt`/`PaintManual`, which re-parent or take over painting every frame (G50) and can't receive clicks | Manage mode (the window itself stays usable) |
| Windows whose addon repositions them every frame | The addon wins every frame | Managed without geometry; embed if it's a window |
| Reopening a window opened by the server or by an F-key bind without the player's action | No client-side opener exists; F-keys aren't visible to `PlayerBindPress` (G6) | `watch` recipe: it's taken over as soon as the player opens it |

### 33.13 Code for 2.1

| File | Lines | Job |
|---|---:|---|
| `manage.lua` | ≈ 250 | take/apply/release managed windows, watcher, focus rule |
| `embed.lua` | ≈ 300 | contents and part embedding, ghost shell, watcher, release |
| `recipes.lua` | ≈ 300 | signatures, matching, native registries (desktop, post-process), static opener match, Record mode, catching |
| `vgui/picker.lua` | ≈ 250 | overlay, info card, hierarchy walk, open-windows list |
| changes | ≈ 200 | `sources.lua` (new kinds), `desktop.lua` (managed windows), `input.lua` (focus rule, cursor reason), hub Pinned page and layout editor (managed windows), taskbar |

≈ 1,300 lines in total. The 2.0 design is what keeps this small:
- one window/tab model and document;
- dormant tabs, which become *waiting*;
- one input dispatcher with cursor reasons and the text-focus hooks;
- one guarded override helper;
- the source catalogue.

### 33.14 Compatibility targets

The test list for 2.1, with the expected result:

| Target | How it's opened | Expected mode · recipe |
|---|---|---|
| Super DOF (base game) | `pp_superdof` (G53) | Manage or Embed · `command:pp_superdof` (static match finds it) |
| Bloom / Sharpen / Toy Town (base game) | Post Process tab | Native · `postprocess:` |
| Player model editor (base game) | C-menu desktop widget | Native · `desktop:PlayerEditor` |
| Wiremod E2 editor | tool / command | Manage (needs keyboard) · `command:` via Record |
| Advanced Duplicator 2 file browser | tool panel / window | Embed part or Manage · `class:` or Record |
| An addon settings window (any `DFrame`) | console command or button | Manage · Record |
| DarkRP F4 menu (server-opened) | F4 → server → net | Manage · `watch` (Record reports "opened by the server") |
| A Derma HUD addon using `ParentToHUD` | always on | Manage (found through `vgui.GetAll`, G51); geometry only if it doesn't fight |
| The spawn menu's Utilities list or another window's sub-panel | — | Embed part |

### 33.15 Phase 0 spike (≈ ½ day, on v1)

Pass criteria in brackets.

1. **Where windows live**: create a `DFrame` without parent, one with `MakePopup`, one with `ParentToHUD`. Check which are world-panel children (G41, G51). [matches the table in §33.3]
2. **Manage**:
   - On a `MakePopup` `DFrame` with a text field and a slider: `SetMouseInputEnabled(false)` + `SetKeyboardInputEnabled(false)` while visible. [player moves and aims; window stays drawn]
   - Back in cursor mode: re-enable mouse. [clicking works]
   - Click the text field. [`OnTextEntryGetFocus` fires and typing works after enabling keyboard]
3. **Embed**:
   - Move the same frame's content children into another popup's inner panel. [clicks, typing, sliders, docking work]
   - Ghost the shell. [its `Think` still runs]
   - Release. [original window fully works again]
   - Also check `SetPaintedManually(true)` + `Think`.
4. **Reproduce the v1 failure**: reparent the whole popup. [input or position breaks, confirming G45/G52]
5. **Record**:
   - Wrap `vgui.Create`, run `pp_superdof`, walk the stack with `debug.getinfo`. [the `concommand.GetTable()` callback for `pp_superdof` is found]
   - Same inside a `net.Receive` handler on a listen server. [the `net.Receivers` entry is found]
6. **Real addons**: E2 editor (keyboard), AD2, one settings window, one `DHTML` window (does it reload when moved?). [results written into §33.14]

### 33.16 2.1 roadmap

| Step | Content | Days |
|---|---|---:|
| 2.1-a | Picker + **Manage** + `session`/`watch` recipes + managed windows in taskbar, Pinned list, layout editor, profiles | 4 |
| 2.1-b | Native registries (`desktop:`, `postprocess:`), `class:`, static command match, catching | 3 |
| 2.1-c | **Record** mode | 2 |
| 2.1-d | **Embed** (contents and part), switch between Manage/Embed | 4 |
| 2.1-e | Compatibility pass (§33.14), a public "known to work" list in the README, polish | 2 |

≈ 15 days. 2.1-a alone already delivers the original vision for most windows ("pin it, keep it on screen while playing, it comes back when the addon opens it").

### 33.17 Risks

| Risk | Mitigation |
|---|---|
| An addon re-enables input or re-centres its window constantly | watcher re-applies at 4 Hz; "fighting" detection stops geometry and tells the user |
| Embed breaks an addon | opt-in only; "Return to managed mode"; release restores everything; compatibility list |
| Record's temporary wrap conflicts with another addon wrapping `vgui.Create` | wrap for ≤ 30 s only on user request; restore by identity (only if our wrapper is still installed, else warn) |
| `debug.getlocal`/`getupvalue` removed in a future GMod | only `debug.getinfo` is required; `getlocal` just adds command arguments |
| Wrong window auto-taken on a weak signature | weak matches ask once; the user can undo (FF10) |
| Performance with many managed windows | watchers run only while needed, at 2–4 Hz, on snapshots; no per-frame work |


---

## Appendix A — Events & hooks

**Our events** (internal to the addon in 2.0; a public API is FF25, §32):

| Event | Args | Fired by |
|---|---|---|
| `PinnedPanelsLoaded` | — | loader |
| `PinnedPanelsChanged` | `kind, windowId?` | `layout` (coalesced per frame) |
| `PinnedPanelsCatalogChanged` | — | `sources`, after each `PostReloadToolsMenu` |
| `PinnedPanelsCursorMode` | `active` | `input` |
| `PinnedPanelsSettingChanged` | `key, value` | `settings` |
| `PinnedPanelsInputChanged` | — | `input` (cursor mode, ALT, spawn menu open/close) |

**GMod hooks used:** `Think` (one, `input`), `CreateMove`, `PlayerBindPress`, `StartChat`, `FinishChat`, `OnTextEntryGetFocus`, `OnTextEntryLoseFocus`, `OnSpawnMenuOpen`, `OnSpawnMenuClose`, `PostReloadToolsMenu`, `OnScreenSizeChanged`, `ShutDown`. Hook identifiers are `"PinnedPanels.<Area>"` or the owning control.

## Appendix B — Glossary

| Term | Meaning |
|---|---|
| **Window** | a floating pinned panel; holds 1..N tabs |
| **Tab** | one pinned source inside a window; a window with several tabs is a group |
| **Source** | something pinnable: a tool or option page (`tool:`) or a spawn-menu content tab (`creation:`) |
| **Catalogue** | the list of available sources, rebuilt on `PostReloadToolsMenu` |
| **Dormant** | a tab whose source isn't available now; kept and restored later |
| **Desktop** | the module that turns window records into window controls |
| **Hub** | the "Pinned Panels" spawn-menu tab |
| **Cursor mode** | the toggle that shows the mouse and makes windows interactive |
| **Usable area** | the screen minus the taskbar |
| **Click-through** | a window that ignores the mouse except its header (ALT to use it) |
| **Peek** | hold a key to show every window |
| **Quick key** | a key that toggles one window |
| **Crop** | showing a sub-rectangle of a tab's content |
| **Action** | a declared command used by menus, palette, keys and console |
| **Zone** | an area keyboard nav can focus: windows, taskbar, content, menu, popup |
| **Control adapter** | how keyboard nav handles one kind of control |
