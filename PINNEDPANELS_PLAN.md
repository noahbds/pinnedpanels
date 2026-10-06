# Pinned Panels — Compatibility Plan (2.0 → 2.1)

> **Status:** active · **Started:** 2026-10-06 · **Work branch:** `PinnedPanels_Rewrite_Branch`
> **Replaces:** [`docs/archive/PINNEDPANELS_V2_REWRITE_PLAN.md`](docs/archive/PINNEDPANELS_V2_REWRITE_PLAN.md) (archived; the rewrite is built).
> **Evidence:** [`STATIC_REVIEW.md`](STATIC_REVIEW.md), four static passes against 28 addons, 37 findings.
>
> **Goal:** pinning another addon's window works for most addons without per-addon code, and when it cannot work, the window is given back untouched and the player is told.

---

## Contents

0. [How to use this document](#0-how-to-use-this-document)
1. [Where we are](#1-where-we-are)
2. [Goals, non-goals, success metrics](#2-goals-non-goals-success-metrics)
3. [Decisions](#3-decisions)
4. [New rules and platform facts](#4-new-rules-and-platform-facts)
5. [Design](#5-design)
6. [Roadmap](#6-roadmap)
7. [In-game spike](#7-in-game-spike)
8. [Carried over from the rewrite plan](#8-carried-over-from-the-rewrite-plan)
9. [Definition of done](#9-definition-of-done)
10. [Findings → work items](#10-findings--work-items)

---

## 0. How to use this document

- **§3–§5 are the design.** If the code has to differ, update this file in the same commit.
- **§6 is the work queue.** Each checkbox is roughly one commit.
- **The archived plan still defines everything not mentioned here**: architecture (§10), coding conventions (§24), performance budgets (§9), good-guest rules R1–R16 (§8). Its IDs stay valid.
- **ID series continue** from the archived plan so nothing collides:

| Series | Meaning | Archived plan ended at | This plan starts at |
|---|---|---|---|
| D | Decisions | D23 | D24 |
| R | Good-guest rules | R16 | R17 |
| G | Platform facts | G66 | G67 |
| E | Edge cases | E36 | E37 |

- **Review findings are cited with an `SR.` prefix** (`SR.B1`, `SR.C3`, `SR.N16`). The archived plan already uses bare `B` numbers for v1 bugs, so the prefix is required.
- Commit messages cite IDs, for example `Become ready without the spawn menu (SR.N16, D30)`.
- **⚑ game** marks an item that cannot be finished or verified without Garry's Mod running. Everything else is ordered so it can be done and checked statically first.
- Every file must still parse: `luajit -bl <file>` (available at `/opt/homebrew/bin/luajit`).

---

## 1. Where we are

**Built**: everything in phases 0–7 of the archived plan. That is the whole of v2 except the feature phases 8–10, translations, and the release pass.

**Never run in game since phase 6**: the two ⚑ spikes of the archived plan (phase 0 and §33.15) and the compatibility pass (6e) were left open.

**What the static review found** (details in `STATIC_REVIEW.md`):
- Embedding itself mostly holds.
- Almost every HIGH finding is in deciding **how a window comes back**: wrong recipe for PAC3, Wire, LVS, LFS, Glide, MQS and the PlayerModel Selector.
- Embed's remaining failures share one cause: the emptied window and the tab drift apart.
- In any gamemode without a spawn menu (TTT2, Cinema) nothing ever shows, and picking a window makes it vanish (SR.N16).

**Three things held for every window in 28 addons** (`STATIC_REVIEW.md` §8.3). The design below leans only on these:
1. A window is exactly one top-level panel.
2. Its owner drives it through a reference it keeps, and expects it to stay intact.
3. The player knows how to open it. We do not.

---

## 2. Goals, non-goals, success metrics

### Goals
1. **No silent wrong behaviour.** A pinned window either works or is released untouched with one notification.
2. **No foreign code runs unless the player asked for it**, in this session, by a click.
3. **No per-addon code.** Every rule is stated in terms of what a window does, never which addon it belongs to.
4. **Works in any gamemode**, with or without a spawn menu.

### Non-goals
- Pinning full-screen scenes (character screens, weapon customisation). They are refused.
- Making a single pinned part of a window as reliable as a whole window. Part mode stays best-effort.
- Fixing addons whose tab function has global side effects (Cloudbox). We detect and warn.
- New features from the archived plan's phases 8–10. They wait (§8).

### Success metrics
| Metric | Target |
|---|---|
| Review findings rated HIGH still open | 0 |
| Of the 28 reviewed addons, windows that pin and come back correctly, or are refused or released cleanly | all |
| Lua errors caused by us in another addon's code during the compatibility pass | 0 |
| Openers run without a click | 0 (rule check, §9) |
| Idle-frame budget of the archived plan (§9: ≤ 0.15 ms) with 3 embedded windows | still met |

---

## 3. Decisions

| ID | Question | Decision | Why |
|---|---|---|---|
| **D24** | How is another addon's window hosted? | **A ladder: Embed, then Wrap, then Manage.** Supersedes D23 ("Embed only"). Embed is still tried first for every window | Decided by the owner on 2026-10-06. Embed is best where it works; it is also the tier that depends on what addons do not agree on |
| **D25** | When may we run an opener? | **Only on an explicit click by the player, in this session.** Never at join, never from `Catch` | SR.B1, SR.B2, SR.N5, SR.N9. Seven of ten C-menu widgets are launchers; PAC's opener takes over the camera |
| **D26** | What is the default recipe? | **`watch`**: catch the window when its addon opens it. A command is suggested only with evidence tying it to the window; `class` is never suggested, only offered | SR.B1, SR.N8, SR.N13 |
| **D27** | What does `autoRestore` mean for adopted panels? | Windows already open are caught. Nothing is opened for the player. The Pinned page shows an "Open" button per waiting tab | D25 |
| **D28** | How is a window identified? | Source file, plus a **second source file** from deeper in the tree, plus class. Same source with a different title is a weak match. A weak match asks once and remembers the answer | SR.N2, SR.N6, SR.C6, SR.C9 |
| **D29** | Who owns the shell's size? | **The owner.** The tab follows the shell's size; a user resize is a request the owner may override | SR.N7, SR.N15, PAC's properties collapse |
| **D30** | When is the desktop ready? | When the catalogue is first built, and that no longer needs the spawn menu: it is built on `InitPostEntity` if nothing built it earlier | SR.N16 |
| **D31** | Who owns the cursor? | **Shared.** `input.lua` is still the only caller of `gui.EnableScreenClicker`, but it re-asserts instead of assuming | SR.B5. Eleven of 28 addons call it too |
| **D32** | What gets refused outright? | Full-screen panels with their own `Paint`; menus of any class (by `m_bIsMenuComponent` plus `AddOption`); everything R11 already refuses | SR.N18, SR.N14 |
| **D33** | Is Wrap built? | **Only if the stacking-order spike passes** (§7, item S1). If it fails, the ladder is Embed → Manage and Wrap is dropped with a note here | The one question that cannot be settled statically |
| **D34** | What falls back, and how? | A **health watch** after embedding steps a window down one tier, releases it untouched first, tells the player once, and remembers the working tier per signature. The player can force a tier from the tab's menu | Goal 1 |
| **D35** | Does part mode have a fallback? | **No.** Wrap and Manage act on whole windows. A part that fails is released and its tab removed | Non-goal 2 |
| **D36** | What ships as 2.0.0? | Phases A–D and the release work of §8. **Wrap and the health watch may ship as 2.1.0** if the spike slips; Manage ships in 2.0 either way, because it is the tier that cannot break | Manage is ≈ 280 lines that already existed (removed in `659d2ec`) |
| **D37** | Default cursor key | Stays `F4`, except when `F4` is bound to `gm_showspare2` and the gamemode is not sandbox: then unbound, with one notification | SR.N11 |
| **D38** | Singleton spawn-menu tabs | Not fixed. A builder that replaces console commands while it runs triggers a one-time warning; a host whose content dies rebuilds (capped) | SR.N1 |

---

## 4. New rules and platform facts

### Good-guest rules (continue R1–R16)

| ID | Rule | Check |
|---|---|---|
| **R17** | No opener, class constructor or widget `init` runs except from a click handler | `Recipes.Open` has exactly the callers listed in §5.1 |
| **R18** | Every call into a foreign panel's Lua method that can throw is wrapped (`GetTitle`, `Paint` passthrough, `init`) | Review |
| **R19** | Before putting a panel back, check where it is now. A panel its owner took back is left alone | `Embed.Release` reads the current parent |
| **R20** | A window is only taken once its size and alpha have been stable for two ticks | `Recipes.Catch` |
| **R21** | When hosting fails, release first, then step down, then tell the player once | D34 |

### Platform facts (continue G1–G66)

Verified in this install's GMod Lua during the review (`STATIC_REVIEW.md` §4).

| ID | Fact | Consequence |
|---|---|---|
| **G67** | `vgui.Create` sets `panel.ClassName` to the registered name, overwriting the addon's own field | Class is the registered name |
| **G68** | `derma.DefineControl` puts addon classes in the derma control list | The list is not "stock classes" (SR.C9) |
| **G69** | `Paint` runs on a panel whose alpha is 0 (vanilla XGUI depends on it) | A ghosted shell's `Paint` still runs; passthrough must not double-draw |
| **G70** | `DFrame:GetTitle` is `self.lblTitle:GetText()` with no validity check; Wire and StarfallEx remove `lblTitle` | R18 |
| **G71** | The C menu calls `init(icon, window)` on a frame it made; most addons ignore or remove that frame | D25 |
| **G72** | Gamemodes with `"base" "base"` have no spawn menu and never fire `PostReloadToolsMenu`; `spawnmenu.GetTools()` and the lists still exist | D30 |
| **G73** | `DVerticalDivider`, `DPropertySheet`, `DPanelList` manage children by stored reference, wherever those children are parented | Part mode is best-effort (D35) |
| **G74** | `vgui.CreateFromTable` does not set `ClassName` | Such panels report their base's class |

---

## 5. Design

Only what changes. Everything else is as the archived plan describes.

### 5.1 Coming back (recipes)

**Recipe kinds stay** (`watch`, `command`, `class`, `desktop`, `session`). What changes is who chooses and who runs them.

**Choosing** (`Recipes.Suggest`, `Openers.Best`):
- Default is `watch`.
- A `command` is suggested only if one of these holds:
  - it is the single non-risky command defined in the window's own file;
  - its function holds the window's functions as upvalues (existing evidence);
  - it is defined in the window's file or addon **and** its name contains a word from the window's title or class.
- Being in the same addon folder is never enough on its own.
- Opener words match as substrings (`openmenu` contains `open` and `menu`).
- `class` is never suggested. It stays in `Recipes.Choices`.
- `desktop` is suggested only for a widget window the C menu made and filled (a child of the C menu carrying the widget's title, or a frame we made ourselves).

**Running** (`Recipes.Open`): the only callers are
1. the "Open" button on the Pinned page,
2. `Openers.PinDesktop`, itself only called from a click in the hub or palette.

`PinnedPanelsCatalogChanged` calls `Recipes.Catch()` and nothing else.

**Launcher widgets** (`Openers.OpenDesktop`):
1. Snapshot the world panel's and the C menu's children.
2. Create the frame and run `init` under `ProtectedCall`.
3. If our frame is invalid, marked for deletion, or has no child beyond its chrome: remove it and return the single new top-level panel, if exactly one appeared.
4. `Signature.desktop` is set only on a frame we created ourselves, never by title.

**Catching** (`Recipes.Catch`):
- A panel is taken only after two consecutive ticks with the same size and alpha (R20).
- No synchronous `Catch()` after running a command.
- Cursor mode is entered only for a popup the player opened (`panel:IsPopup()`).
- `checked` survives `Wake()` unless the waiting set gained a signature.

### 5.2 Identity

`Recipes.Signature` gains one field and loses one assumption:

| Field | Change |
|---|---|
| `src` | Unchanged |
| `src2` | **New.** The first non-stock file, different from `src`, found by continuing the breadth-first walk. Nil if none |
| `class` | Kept unless the class's own functions live under `lua/vgui/` or `lua/derma/`. The derma control list is no longer consulted |
| `title` | Read under `pcall` |

`Recipes.Match`:
- When the saved signature has a `src2` and the live one differs, the match is **weak**, not refused: a window filled differently this time shows the same way. Old saves without `src2` match as before.
- Same `src`, different title: **weak** (was: no match).
- A refused weak match is remembered for that tab and panel until the next session.

`Storage.sanitizeAdopt` accepts `src2`, drops `w`/`h` unless both are present, and accepts modes `embed`, `part`, `wrap`, `manage`.

### 5.3 Hosting ladder

| Tier | Mode | What moves | Fails over to |
|---|---|---|---|
| 1 | `embed` | The window's contents, into the tab | `wrap` |
| 2 | `wrap` | Nothing. The window is kept positioned over the tab's content area | `manage` |
| 3 | `manage` | Nothing. The window stays where its addon put it | — |
| — | `part` | One panel, into the tab | Released (D35) |

`Sources.Get` and the tab host treat `wrap` like `embed`, with an empty box.

**Tier 1 — Embed, made robust** (`embed.lua`):

| Change | Mechanism |
|---|---|
| Owner's size wins (D29) | Each frame compare the shell's size with the box's. If they differ the same way for two frames, the owner set it: resize our window by the difference, once per disagreement. Skipped while the window is dragged, animated, cropped in the editor, or not in its normal state |
| Shell follows the tab | Each frame set the shell's position to the box's screen position |
| Ghost invariant | Each frame, three getters; re-ghost on any mismatch |
| New children | Each frame compare `shell:ChildCount()` with the count after the last adoption |
| Reclaimed or orphaned panels (R19) | Each tick, for every adopted panel: invalid → forget; parent is no longer the box → forget and do not put back. Part mode: placeholder gone → remove the target |
| Shell paint passthrough ⚑ game | `BOX:Paint` calls the shell's `Paint`, `BOX:PaintOver` its `PaintOver`, under `pcall`. Off by default until spike item S3 passes |

The per-frame work goes through the existing single `Think` hook: `Input.EachFrame(id, fn)`, a small registry in `input.lua`, so the "one `Think` hook" rule of the archived plan holds.

**Tier 2 — Wrap** (new `wrap.lua`, ≈ 200 lines, gated by D33):
- Each frame: position and size the foreign window over the tab's content rectangle; if the owner moved or resized it, move and resize our window instead.
- Keep the foreign window directly above ours.
- Visibility, opacity and click-through are applied to the foreign window through `SetVisible`, `SetAlpha`, `SetMouseInputEnabled`.
- Crop is unavailable; the crop actions are hidden for wrapped tabs.

**Tier 3 — Manage** (restore `manage.lua` from `659d2ec^`, then trim):
- Remembers and restores position and size; hides and shows; taskbar and Pinned-page entry; idle opacity.
- No frame of ours, no tabs.

**Health watch** (`embed.lua`, `wrap.lua`):

| Signal | Tier | Threshold |
|---|---|---|
| `OnLuaError` whose stack names one of the signature's source files | embed | 2 within 5 s of attaching |
| Shell needed re-ghosting | embed | on more than half the frames of any 2 s window |
| Adopted children left the box | embed | half or more of them |
| Foreign window could not be kept above ours | wrap | on more than half the frames of any 2 s window |
| Owner fights the position every frame | wrap | same |

On a trip: release (R21), re-host one tier down, `notification.AddLegacy` once, store `adopt.tier` on the tab.

### 5.4 Refusals (`Recipes.Refusal`)

Added to the existing list:
- **Scene**: covers the whole screen and has a non-stock `Paint` (D32).
- **Menu**: `p.m_bIsMenuComponent` and an `AddOption` method, on the panel itself. Added beside the `TRANSIENT` class table, which still covers tooltips. The mark alone is not enough: `DComboBox` carries it too.

### 5.5 Readiness, cursor, keys (`desktop.lua`, `sources.lua`, `input.lua`, `actions.lua`)

- `InitPostEntity`: if `Sources.catalogue` is empty, call `Sources.Rebuild()` (D30).
- `think()`: if `Input.clickerOn and not vgui.CursorVisible()`, call `gui.EnableScreenClicker(true)` (D31).
- `Embed`'s check: when the owner re-shows a window that was mouse-enabled, enter cursor mode.
- Cursor key default per D37.

### 5.6 Generic features on foreign content

`tab.adopt` (set on every adopted tab) gates:
- auto-size (returns early),
- collapse cookies (already gated),
- the filter bar (stays available, but remembers each row's prior visibility and restores only that).

---

## 6. Roadmap

Phases are ordered so that everything statically verifiable comes first. Phases A–C need no game.

### Phase A — Safety net (≈ 1 day)

Small, independent, each closes a finding outright.

- [x] A1 Ready without the spawn menu [`desktop.lua` or `sources.lua`; SR.N16, D30, G72]
  - verify: trace TTT2 — `InitPostEntity` → `Sources.Rebuild` → `Desktop.ready`; `wanted()` true for a picked window.
- [x] A2 `pcall` around `GetTitle` in `titleOf` and `DesktopId` [`recipes.lua`, `openers.lua`; SR.N10, R18, G70]
- [x] A3 `sanitizeAdopt` drops `w`/`h` unless both present [`storage.lua`; SR.C3]
- [x] A4 `Teardown` releases embeds before removing windows [`desktop.lua`; SR.C2]
- [x] A5 `Layout.Replace` releases embeds before loading; imported `class` recipes become `watch` [`layout.lua`, `storage.lua`; SR.C4, SR.C5]
- [x] A6 Auto-size skips adopted tabs [`vgui/window.lua`; SR.B6, §5.6]
- [x] A7 Cursor mode only for popups the player opened [`recipes.lua`; SR.N4]
- [x] A8 Refuse scenes and menus of any class [`recipes.lua`; SR.N18, SR.N14, D32]
  - Keyboard driving of other addons' menu classes (`nav.lua`) is left as it is: their option API can't be checked without the game. Revisit in phase G.
  - verify: Helix menu and `ArcCW.InvHUD` refused; PAC editor (240 wide) not; `MSD.DMenu`, `PIXEL.Menu` refused.
- [x] A9 Cursor key default avoids `gm_showspare2` outside sandbox [`actions.lua`; SR.N11, D37]
- [x] A10 Re-assert the screen clicker [`input.lua`; SR.B5 first half, D31]

### Phase B — Coming back (≈ 3 days)

- [x] B1 No opener at join; `autoRestore` only catches [`recipes.lua`; SR.B2, D25, D27, R17]
  - verify: `grep -n "Recipes.Open" lua` → only the Pinned page and `PinDesktop`.
- [x] B2 "Open" button for every waiting tab that has an opener [`vgui/hub_pinned.lua`; D27]
- [x] B3 Command evidence rules; substring opener words; unique same-file command [`openers.lua`; SR.N8, SR.N13, D26]
  - verify by trace: Wire E2 editor → nil; LVS → `lvs_openmenu`; PlayerModel Selector → `playermodel_selector`; PAC → nil.
- [x] B4 `class` never suggested [`recipes.lua`; SR.B1, D26]
  - `desktop` is still suggested for a window the C menu itself made and filled (B5 narrows what counts as one): that recipe is right for it, and it only runs on a click.
- [x] B5 Launcher widgets return the window they opened; `desktop` signature only on our own frames [`openers.lua`, `recipes.lua`; SR.N5, SR.N9, G71]
  - verify by trace: LVS, LFS, Glide, MQS, PlayerModel Selector, StormFox2 controller, Starfall user list each yield their real frame; Wire's and ACF's yield ours.
- [x] B6 `src2`; stock-class test by file; `Match` updates [`recipes.lua`, `storage.lua`; SR.N2, SR.C9, D28]
  - verify: libNyx showcase → `libnyx_maindemo.lua`; `xlib_Panel`, `F4MenuFrame` keep their class; a 2.0 save without `src2` still matches.
- [x] B7 Settle rule; no synchronous `Catch` [`recipes.lua`; SR.N3, SR.C7, R20]
- [x] B8 Different title is weak; a refused weak match is remembered [`recipes.lua`; SR.N6, SR.C6]
- [x] B9 `checked` survives `Wake`; cache `fileOf` and `Openers.Commands`; no HUD scan for desktop signatures [`recipes.lua`, `openers.lua`; review §11]
- [x] B10 Recipe descriptions no longer promise reopening; new strings went in with their items [`en/pinnedpanels.properties`]

### Phase C — Embed made robust (≈ 3 days)

- [x] C1 `Input.EachFrame` registry [`input.lua`]
  - verify: `grep -rn 'hook.Add( *"Think"' lua` → still 1 match.
- [x] C2 Per-frame ghost and `ChildCount` checks [`embed.lua`; SR.B4, SR.N12]
- [x] C3 Reclaimed, orphaned and dead panels; prune `moved` [`embed.lua`; SR.B3, SR.C1, R19]
  - verify by trace: ULX `processModules`, PAC tree `Populate`, Cloudbox `DContentMain:Think`, LVS `CreatePanel`.
- [x] C4 Shell follows the tab's position [`embed.lua`; SR.C8]
- [x] C5 Owner's size wins [`embed.lua`; SR.N7, SR.N15, D29]
  - verify by trace: PAC (`SetTall(ScrH())` each frame) → window settles at full height, no oscillation; a window that never resizes itself → user resize sticks.
- [x] C6 Enter cursor mode when an owner re-shows its window [`embed.lua`; SR.B5 second half]
- [x] C7 Host rebuilds when its built content dies (capped at 3); warn when a builder replaces commands [`vgui/tabs.lua`, `sources.lua`; SR.N1, D38]
- [ ] C8 Filter restores only what it hid [`vgui/tabs.lua`; SR.C13]
- [ ] C9 Shell paint passthrough behind a debug convar, off by default [`embed.lua`; R18, G69] ⚑ game to enable

### Phase D — Manage as the fallback (≈ 2 days)

- [ ] D1 Restore `manage.lua` from `659d2ec^`; trim to §5.3 [D24, D36]
- [ ] D2 `adopt.mode` accepts `manage` and `wrap`; `adopt.tier` saved; undo the D23 "manage loads as embed" migration [`storage.lua`, `layout.lua`]
- [ ] D3 "Host as…" submenu on adopted tabs: Embed, Manage (Wrap added in phase F) [`actions.lua`]
- [ ] D4 Managed windows in the taskbar, the Pinned page and the layout editor [`vgui/taskbar.lua`, `vgui/hub_pinned.lua`, `vgui/hub_layout.lua`]
- [ ] D5 Manual fallback only for now: releasing a failing embed and re-hosting as Manage from the menu [`embed.lua`, `manage.lua`; R21]

### Phase E — In-game spike (≈ ½ day) ⚑ game

- [ ] E1 Run §7 and write each result into §7's table.
- [ ] E2 Record the D33 outcome (Wrap built or dropped).
- [ ] E3 Turn the paint passthrough on by default, or remove it, per S3.

### Phase F — Wrap and the health watch (≈ 4 days) ⚑ game, only if D33 passes

- [ ] F1 `wrap.lua`: follow, stack, show/hide, opacity, click-through [D24, §5.3]
- [ ] F2 Wrapped tabs in window chrome: crop hidden, tab strip, roll-up
- [ ] F3 Health watch signals and thresholds [`embed.lua`, `wrap.lua`; D34]
- [ ] F4 Automatic step-down with one notification; tier remembered per signature [R21]
- [ ] F5 Probe before embedding: settle, scene, and "start at the remembered tier"

### Phase G — Compatibility pass (≈ 2 days) ⚑ game

This is the archived plan's item 6e.

- [ ] G1 The 28 reviewed addons, one row each in a matrix: pin whole window, close, reopen, rejoin, unpin. Result: works / refused / stepped down to which tier.
- [ ] G2 "Known to work" list in the README.
- [ ] G3 Any window that fits none of the five kinds of `STATIC_REVIEW.md` §8.1 is written up there; the model is wrong and §5 is revisited.

### Phase H — Release

The archived plan's phases 11 and 12 (§8 below), then cutover.

---

## 7. In-game spike

Each row settles something the review could not. Results go in the last column.

| # | Question | Decides | Result |
|---|---|---|---|
| S1 | Can a foreign popup be kept directly above our frame while its owner calls `MakePopup` or `MoveToFront`? Test with PAC (re-pops on focus) and XGUI | **D33**: whether Wrap is built | |
| S2 | Does a ghosted popup (mouse off, alpha 0) let clicks through to what is behind it? | The whole Embed design | |
| S3 | Does calling a shell's `Paint` from our box draw at the right origin and clip? Test with LVS (header), gPhone (body), PAC (render bar) | C9: passthrough on or removed | |
| S4 | Does resizing a `FILL`-docked child from outside re-invalidate its new parent's layout? | Part mode on PAC's divider | |
| S5 | With D29, does a tab holding PAC settle at full height without flicker? | C5 thresholds | |
| S6 | Is `IsValid` still true on a panel in the frame `Remove()` was called? | B5 detail | |
| S7 | Does `GetText` on a removed panel throw? | Whether A2 was fixing a real error | |
| S8 | After a click on an embedded panel with `needsKeyboard`, does the cursor key still work? | SR.C12 | |
| S9 | In TTT2 or Cinema after A1: do windows, taskbar and palette work? Is there any way to reach the hub's pages? | Whether the hub needs a standalone window | |
| S10 | In Wrap, does hiding an inactive tab's window make XGUI or DarkRP's F4 think it is closed? | F1 | |
| S11 | How long is the first `Catch` tick after a pin, spawn menu open, before and after B9? | Whether more caching is needed | |
| S12 | The two spikes left open in the archived plan (phase 0 and §33.15) | Their ⚑ items | |

---

## 8. Carried over from the rewrite plan

Unchecked in the archived plan's §26 and §27 on 2026-10-06. Nothing here is started.

### Folded into this plan
| Archived item | Now |
|---|---|
| Phase 0 ⚑ verify spike | §7, S12 |
| §33.15 spike | §7, S12 |
| 6e compatibility pass and "known to work" list | Phase G |

### Release work (phase H, after phase G)
- [ ] Side-by-side v1/v2 screenshots of every screen and menu
- [ ] 8 translations converted and completed [F33, B25]
- [ ] Live language switch across every screen [E11]
- [ ] Manual matrix (archived §28.2)
- [ ] Performance pass (archived §9)
- [ ] Good-guest pass (archived §8)
- [ ] README, release notes, Workshop icon
- [ ] Cutover (archived §3.2)

### Deferred until after 2.0.0
Kept in the archived plan's order. Not scheduled.

| Phase | Items |
|---|---|
| 8 | FF3 layout profiles · FF4 visibility rules · FF23 hide for screenshots · FF17 recent and favourite tools · FF7 drag tabs between windows |
| 9 | FF18 jump hints · FF19 modifier shortcuts · FF22 UI scale · FF25 public API · FF26 Wiremod and Advanced Duplicator 2 adapters |
| 10 | FF8 docks · FF9 linked windows · FF11 hover fade-in · FF12 auto-layout presets · FF14 automatic rebuild when a tool rebuilds its panel · FF15 pin a spawnlist folder · FF20 keyboard cheat sheet · FF21 theme presets · FF24 more languages |

Two of these are now better motivated by the review:
- **FF14** would close SR.N17 (tool pages refreshed by name, seen in Advanced Duplicator 2 and VJ Base).
- **FF25/FF26**: a public API is the only clean answer for addons that will never fit the model. It stays deferred; goal 3 is that it is not needed for the common case.

---

## 9. Definition of done

### Per commit
- [ ] One thing per commit, IDs cited.
- [ ] Every touched file parses (`luajit -bl`).
- [ ] The archived plan's §24 rules hold.
- [ ] New strings are in `en/pinnedpanels.properties`.
- [ ] This file is updated if the design changed.

### Rule checks (run before every phase is closed)
- [ ] `grep -rn "Recipes.Open(" lua` → only `vgui/hub_pinned.lua` and `openers.lua` (R17).
- [ ] `grep -rn 'hook.Add( *"Think"' lua` → 1 match (`input.lua`).
- [ ] `grep -rn "gui.EnableScreenClicker" lua` → only `input.lua`.
- [ ] `grep -rn "timer.Simple" lua` → only inside `Util.NextFrame`.
- [ ] `grep -rn "GetControlList" lua` → 0 matches (D28).
- [ ] No assignment to a global library field outside `Util.WithOverride` and `Util.BeginOverride`.

### For 2.0.0
- [ ] Phases A–D done; phase E run; phase G matrix complete.
- [ ] Every HIGH finding of `STATIC_REVIEW.md` §15 is closed or has a decision here.
- [ ] The success metrics of §2 are met.
- [ ] Phase H done.

### For 2.1.0
- [ ] Phase F done, or D33 recorded as "Wrap dropped" with the health watch stepping Embed → Manage.

---

## 10. Findings → work items

Every finding of `STATIC_REVIEW.md`, and where it goes.

| Finding | Severity | Work item | Notes |
|---|---|---|---|
| SR.B1 class recipe for PAC | HIGH | B4 | |
| SR.B2 openers at join | HIGH | B1, B2 | |
| SR.B3 part mode misses removal and reclaim | HIGH | C3 | |
| SR.N1 Cloudbox singleton tab | HIGH | C7 | Mitigated, not fixed (D38) |
| SR.N2 library windows share a signature | HIGH | B6 | Wire's three editors stay indistinguishable |
| SR.N3 caught mid-animation | HIGH | B7 | |
| SR.N8 unrelated command auto-picked | HIGH | B3 | |
| SR.N9 launcher widgets | HIGH | B5 | |
| SR.N16 never ready without a spawn menu | HIGH | A1 | |
| SR.B4 shell re-popped | MEDIUM | C2 | |
| SR.B5 screen clicker | MEDIUM | A10, C6 | |
| SR.B6 auto-size on embedded tabs | MEDIUM | A6 | |
| SR.N4 always-present frame forces cursor mode | MEDIUM | A7 | |
| SR.N5 widget removes its frame | MEDIUM | B5 | |
| SR.N10 unprotected `GetTitle` | MEDIUM | A2 | |
| SR.N11 F4 collides with DarkRP | MEDIUM | A9 | |
| SR.N12 direct-child swap | MEDIUM | C2 | |
| SR.C1 `moved` never pruned | LOW | C3 | |
| SR.C2 teardown order | LOW | A4 | |
| SR.C3 `w` without `h` | LOW | A3 | |
| SR.C4 import with live embeds | LOW | A5 | |
| SR.C5 imported class recipes | LOW | A5 | |
| SR.C6 weak-match question repeats | LOW | B8 | |
| SR.C7 alpha captured mid-fade | LOW | B7 | |
| SR.C8 shell position not synced | LOW | C4 | |
| SR.C9 addon derma classes treated as stock | LOW | B6 | |
| SR.C10 0.25 s of orphaned children | LOW | C3 | Shortened, not removed; S-check in phase G |
| SR.C11 hide keeps the shell ghosted | LOW | — | Accepted: hiding a pinned window hides its content |
| SR.C12 `needsKeyboard` may gate the cursor key | LOW | S8 | Decide after the spike |
| SR.C13 `unfilter` re-shows owner-hidden rows | LOW | C8 | |
| SR.N6 title change breaks matching | LOW | B8 | |
| SR.N7 size sync is one-way | LOW | C5 | |
| SR.N13 same-file opener missed | LOW | B3 | |
| SR.N14 custom menus not transient | LOW | A8 | |
| SR.N15 owner saves our geometry | LOW | C5 | Becomes correct: the owner's size is the real size |
| SR.N17 tool pages refreshed by name | LOW | — | Deferred to FF14 (§8) |
| SR.N18 full-screen scenes | LOW | A8 | |
| Root's own drawing lost | — | C9, S3 | Otherwise handled by Wrap or Manage |
| PAC properties collapse | — | C5 | |
| Performance (review §11) | — | B9, S11 | |
