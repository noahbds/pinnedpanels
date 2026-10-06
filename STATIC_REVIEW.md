# Pinned Panels — static review, four passes

Adversarial static analysis of Pinned Panels 2.0 (branch `PinnedPanels_Rewrite_Branch`) against twenty-eight real addons. Passes 1–3 written on 2026-10-05, pass 4 on 2026-10-06.

**Nothing in this document was executed.** No Garry's Mod instance was available. Every finding comes from reading source: all of `lua/pinnedpanels`, the target addons under `/Users/noah/vehicule_addon`, and the GMod Lua shipped with this install (`garrysmod/lua`, `gamemodes/sandbox`) for engine-side Lua behaviour. No file in Pinned Panels or in any target addon was modified.

---

## Contents

1. [How to read this document](#1-how-to-read-this-document)
2. [What was reviewed](#2-what-was-reviewed)
3. [How Pinned Panels works, as traced](#3-how-pinned-panels-works-as-traced)
4. [Engine facts verified from GMod's own Lua](#4-engine-facts-verified-from-gmods-own-lua)
5. [Pass 1 — PAC3, ULib, ULX](#5-pass-1--pac3-ulib-ulx)
6. [Pass 2 — Cloudbox, PlayerModel Selector, gPhone, libNyx](#6-pass-2--cloudbox-playermodel-selector-gphone-libnyx)
7. [Pass 3 — Wire, DarkRP, WAC, LFS, LVS, Glide, simfphys, MQS, Aden, VPhysics-Jolt](#7-pass-3--wire-darkrp-wac-lfs-lvs-glide-simfphys-mqs-aden-vphysics-jolt)
8. [Pass 4 — a general model, tested on twelve more addons](#8-pass-4--a-general-model-tested-on-twelve-more-addons)
9. [Cross-pass patterns](#9-cross-pass-patterns)
10. [Hostile cases A–O](#10-hostile-cases-ao)
11. [Performance](#11-performance)
12. [Memory](#12-memory)
13. [Networking, security and persistence](#13-networking-security-and-persistence)
14. [Architecture](#14-architecture)
15. [Consolidated findings index](#15-consolidated-findings-index)
16. [Consolidated patch plan](#16-consolidated-patch-plan)
17. [In-game test checklist](#17-in-game-test-checklist)
18. [Ten changes before production](#18-ten-changes-before-production)

---

## 1. How to read this document

### Confidence labels

| Label | Meaning |
|---|---|
| **Proven** | Follows from the source of Pinned Panels, the target addon and GMod's Lua. No engine behaviour is assumed. |
| **Inferred** | The control flow is proven, but the visible outcome depends on engine (C++) behaviour that could not be read. |
| **Runtime** | Cannot be established statically — requires runtime testing. |

### Severity

`CRITICAL` (crash, data loss, or another addon's panels destroyed), `HIGH` (a feature does the wrong thing for a mainstream addon, silently or on every join), `MEDIUM` (visible misbehaviour with a workaround), `LOW` (cosmetic, rare, or needs corrupt data).

### Finding identifiers

| Prefix | Origin |
|---|---|
| `B1`–`B6` | Pass 1, important bugs |
| `C1`–`C13` | Pass 1, edge cases |
| `N1`–`N7` | Pass 2, new findings |
| `N8`–`N15` | Pass 3, new findings |
| `N16`–`N18` | Pass 4, new findings |

Later passes sometimes refine an earlier fix. Where that happens it is called out (see B2, corrected by N5 and N9).

### Vocabulary

- **Shell**: the other addon's window after its contents were moved out. It stays alive, invisible (alpha 0) and without input.
- **Box**: `PinnedPanelsEmbedBox`, the panel inside a pinned tab that holds adopted panels.
- **Embed mode**: a whole window's contents are moved. **Part mode**: one panel is moved and a placeholder is left behind.
- **Recipe**: how a pinned panel comes back in a later session: `class`, `command`, `desktop`, `watch` or `session`.
- **Signature**: what identifies a panel across sessions: source file, addon, class, base, title, size.

---

## 2. What was reviewed

### Pinned Panels

All 29 client files (about 7,000 lines), read in full except the three hub pages and the palette, which were searched for hooks, timers, embed and import usage.

| Area | Files |
|---|---|
| Loader, helpers | `autorun/pinnedpanels.lua`, `util.lua`, `settings.lua` |
| Document | `layout.lua`, `storage.lua` |
| Input | `input.lua`, `nav.lua`, `nav_controls.lua` |
| Sources | `sources.lua`, `quick.lua` |
| Adopted panels | `embed.lua`, `recipes.lua`, `openers.lua`, `record.lua` |
| Windows | `desktop.lua`, `vgui/window.lua`, `vgui/tabs.lua`, `vgui/crop_editor.lua`, `vgui/taskbar.lua`, `vgui/picker.lua`, `vgui/controls.lua`, `vgui/hud.lua`, `vgui/hub*.lua`, `vgui/palette.lua` |
| Commands | `actions.lua` |

### Target addons

| Pass | Addon | What was traced |
|---|---|---|
| 1 | **pac3** | `editor/client/init.lua`, `panels/editor.lua` in full; `view.lua`, `panels/properties.lua`, `panels/tree.lua`, `shortcuts.lua`, every `pace.Editor` reference, every focus/popup call site, the console command list |
| 1 | **ulib** | `shared/hook.lua` (the hook library replacement), `shared/commands.lua` command registration |
| 1 | **ulx** | `modules/cl/xgui_client.lua`, `xgui_helpers.lua`, `xlib.lua` (frame helpers, animation queue), `motdmenu.lua` |
| 2 | **cloudbox13** | `client/spawnmenu.lua`, `content_main.lua`, `content_downloads.lua`, `options.lua` |
| 2 | **Enhanced-PlayerModel-Selector** | `lf_playermodel_selector.lua` window setup, keyboard hooks, toggle command, C-menu override |
| 2 | **gPhone** | `cl_phone.lua` build/show/hide/destroy and key polling; `cl_animations.lua` rotation; base-frame geometry uses |
| 2 | **libnyx** | `libnyx_components.lua` frame constructor, fx layer, global menu and notification patches; `libnyx_maindemo.lua`; `libnyx_liquidglass.lua` |
| 3 | **wire** | `text_editor/wire_expression2_editor.lua`, `texteditor.lua` focus handling, `e2_viewrequest_menu.lua`, the client command list |
| 3 | **DarkRP** | `f4menu/cl_init.lua`, `cl_frame.lua`; every `DoModal`, `ParentToHUD`, `SetPaintedManually`, `EnableScreenClicker` |
| 3 | **wac** | Tool menu registration, key panel class, bundled gamemodes |
| 3 | **LunasFlightSchool** | C-menu widget and `lfs_openmenu` |
| 3 | **lvs_base** | `cl_menu.lua` `OpenMenu`, `CreatePanel`, C-menu widget |
| 3 | **gmod-glide** | `config.lua` `OpenFrame`, StyledTheme frame classes, C-menu widget |
| 3 | **simfphys_base** | Tool panel and spawn-list registration |
| 3 | **macs-quest-system** | `msd_ui` menu globals (`msdmenu.lua`), `msdcontext.lua` menu manager, C-menu widget, fades |
| 3 | **aden-character-system** | `cl_base.lua` full-screen frame, manual painting call sites |
| 3 | **VPhysics-Jolt** | Contains no Lua (native physics module). Nothing to test. |
| 4 | **pixel-ui** | Class list; `elements/cl_frame.lua` (frame lifecycle, layout, paint); menu and modal popups |
| 4 | **melonlib** | Draggable and resizable element bases; class list |
| 4 | **helix** | `core/derma/cl_menu.lua` lifecycle; gamemode base and menu hooks |
| 4 | **TTT2** | Gamemode base; spawn-menu hooks; API survey |
| 4 | **cinema** | Gamemode base; popup and cursor call sites |
| 4 | **EasyChat** | Chatbox open and close in `easychat.lua` |
| 4 | **StarfallEx** | `editor/sfframe.lua` frame lifecycle; C-menu widget |
| 4 | **ACF-3** | C-menu widget; API survey |
| 4 | **VJ-Base** | `controlpanel.Get` call sites; API survey |
| 4 | **advdupe2** | `controlpanel.Get` call site; API survey |
| 4 | **ArcCW** | `cl_customize2.lua` customisation screen |
| 4 | **StormFox2** | Both C-menu widgets; API survey |

---

## 3. How Pinned Panels works, as traced

This section records the actual behaviour, not the intent in the comments. Findings later refer back to it.

### 3.1 Load and boundaries

- The server only runs `AddCSLuaFile`. There are **no net messages, no receivers and no server state**.
- The client includes 29 files in a fixed order, then fires `PinnedPanelsLoaded`.
- `Desktop` loads the layout on `PinnedPanelsLoaded`. Windows are only created after the first `PostReloadToolsMenu` (`Desktop.ready`).

### 3.2 The document

- `Layout` is the only writer. Every mutation calls `changed(kind, id)`, which marks storage dirty and queues one `PinnedPanelsChanged` per (kind, id), flushed next frame through `timer.Simple(0)`.
- Each frame with changes is one undo step (deep snapshots, 50 kept).
- `Storage` writes a temp file, keeps the old file as backup, renames. Everything read back goes through `Sanitize`.

### 3.3 Windows

- `Desktop.Reconcile` creates, refreshes or removes one `PinnedPanelsWindow` per record that has an available tab.
- Each window is `ParentToHUD()` then `MakePopup()` with keyboard input off. Mouse input follows `Input.Interactive()` (cursor mode, spawn menu or C menu open).
- Tab content is built lazily, one host per frame across all windows.

### 3.4 Embedding another addon's panel

`Embed.Attach` ([embed.lua:93](lua/pinnedpanels/embed.lua#L93)):

- **Embed mode**
  1. Records the shell's alpha, input flags and size.
  2. Marks the five stock `DFrame` chrome fields to skip.
  3. Copies the shell's dock padding to the box.
  4. Moves every other non-popup child into the box, remembering parent, dock, margin, position, size and Z.
  5. Ghosts the shell: mouse off, keyboard off, alpha 0. It stays visible so its `Think` runs.
- **Part mode**
  1. Finds the window the panel belongs to.
  2. Creates a plain `Panel` placeholder in the panel's parent, copying position, size, dock, margin and Z.
  3. Moves the panel into the box and docks it `FILL`.

Then a 0.25 s timer (`Embed.Check`) runs `check` per live embed ([embed.lua:214](lua/pinnedpanels/embed.lua#L214)):

- Releases if the tab is gone, or if the shell or target is invalid.
- Embed mode only: adopts new direct children, shows a "closed" notice when the shell is hidden, re-ghosts if the owner re-enabled input or alpha.

`BOX:PerformLayout` sets the shell's size to the box's size. **Position is never synced, and the shell's size never flows back to the box.**

`Embed.Release` puts each panel back with its remembered layout, or removes it if its original parent or the shell is gone.

### 3.5 Bringing a panel back

- `Recipes.Signature` builds identity. The source file is the file of the panel's own `Init`, `Paint`, `PerformLayout`, `OnClose` or `Think` (first non-stock), else any own function, else its children's, breadth first up to 200 panels.
- `Recipes.Match` compares a saved signature with a live one. A matching file or class is "strong" (taken silently). A title-only match is "weak" (asks).
- `Recipes.Catch` runs every 0.5 s while any tab waits. It looks at top-level panels not yet seen since the last `Wake`, signs each once and attaches the best match.
- `Recipes.Suggest` picks a recipe: desktop widget → best command → registered class → watch.
- `Recipes.Open` runs the recipe. On the first catalogue of a session with `autoRestore`, **every waiting tab's opener is run**.

### 3.6 Input

- One `Think` hook polls watched keys with repeat, and tracks ALT.
- `gated()` silences hotkeys while chat, console, game UI, key trapping or **any keyboard focus** is active.
- `Input.Cursor` is the only caller of `gui.EnableScreenClicker`, tracked in `Input.clickerOn`.
- `OnTextEntryGetFocus` / `LoseFocus` toggle keyboard input on our windows.
- Embedded panels that need keys without a `DTextEntry` use `needsKeyboard`: a click inside gives our window the keyboard until a click elsewhere.

### 3.7 Global state and overrides

| What | Where | Lifetime |
|---|---|---|
| `controlpanel.Get` | `Sources.WithControlPanelFallback` | Scoped to one call, always restored |
| `RegisterDermaMenuForClose` | `Nav.captureMenu` | Scoped to one call, always restored |
| `vgui.Create`, `vgui.CreateFromTable` | Record mode | Up to 30 s; restored only if still ours, otherwise left as a pass-through |
| Tables surviving `pinnedpanels_reload` | `Embed.live/byPanel/shells`, `Desktop.panels/held/ready`, `Input.reasons/clickerOn/cursorMode`, `Layout.closed`, `Recipes.restored` | Session |

---

## 4. Engine facts verified from GMod's own Lua

These were checked in this install's `garrysmod/lua` and `gamemodes/sandbox`, because several findings depend on them.

| Fact | Source | Used by |
|---|---|---|
| `vgui.Create` merges the class table into the panel's table and then sets `panel.ClassName = classname` (the registered name), for each Lua base in turn | `includes/extensions/client/panel/scriptedpanels.lua` | B1, C9, N2 |
| `vgui.CreateFromTable` does **not** set `ClassName`; the panel keeps its base's | same file | Pass 3, Wire |
| `derma.DefineControl` stores every class in the derma control list, addon classes included | `derma/derma.lua` | C9 |
| `DVerticalDivider:DoConstraints` clamps the top height to `tall - bottomMin - dividerHeight` | `vgui/dverticaldivider.lua:76-82` | PAC properties collapse |
| `DVerticalDivider:PerformLayout` calls `StretchToParent` and `SetTall` on its top and bottom panels by reference | `vgui/dverticaldivider.lua:84-106` | Part mode on PAC |
| `DFrame:Close` hides, then removes if `DeleteOnClose` | `vgui/dframe.lua:89-99` | Lifecycle traces |
| `DFrame:GetTitle` returns `self.lblTitle:GetText()` with no validity check | `vgui/dframe.lua:77-79` | N10 |
| `DTooltip` detaches its contents with `SetParent(nil)` before being removed | `vgui/dtooltip.lua:129` | Confirms `Embed.Unbuild` is a supported idiom |
| `DTextEntry` fires `OnTextEntryGetFocus` / `OnTextEntryLoseFocus` | `vgui/dtextentry.lua:355,363` | Keyboard traces |
| `DScrollPanel:OnChildAdded` reparents to its canvas; `DListLayout:OnChildAdded` docks the child `TOP` | `vgui/dscrollpanel.lua`, `vgui/dlistlayout.lua` | Placeholder behaviour |
| `DPropertySheet:AddSheet` parents each tab panel directly to the sheet and manages it by reference | `vgui/dpropertysheet.lua` | DarkRP F4 |
| The C menu creates a `DFrame`, sizes and titles it from the list entry, then calls `init(icon, window)` | `gamemodes/sandbox/gamemode/spawnmenu/contextmenu.lua:201-224` | N5, N9 |

One engine fact was established indirectly: **`Paint` runs on a panel whose alpha is 0.** ULX's XGUI fades in from alpha 0, and that fade is pumped from the same panel's `Paint`. If `Paint` did not run at alpha 0, vanilla XGUI could never open.

---

## 5. Pass 1 — PAC3, ULib, ULX

### 5.1 Critical bugs

None proven. The crash and data-loss paths that were traced hold up:

- `SetParent(nil)` on the box before a host clears is the idiom `DTooltip` uses.
- Storage writes are atomic with a backup, and unreadable files are quarantined.
- Hooks, timers and convar callbacks are named, so `pinnedpanels_reload` replaces rather than duplicates them.
- Hooks keyed by a panel (hub pages, crop editor) are removed by the hook library when the panel dies. ULib's replacement hook library does the same.

### 5.2 B1 — The PAC3 editor is pinned with a "recreate its class" recipe

**Severity:** HIGH. **Confidence:** Proven.

**Evidence**
- [recipes.lua:253-261](lua/pinnedpanels/recipes.lua#L253) — recipe choice.
- [recipes.lua:437-442](lua/pinnedpanels/recipes.lua#L437) — class recipe execution.
- [openers.lua:126-132](lua/pinnedpanels/openers.lua#L126) — `Best`.
- PAC `editor/client/init.lua:95-162` — `pace.OpenEditor`.

**Control flow**
1. `vgui.Create("pace_editor")` leaves `panel.ClassName == "pace_editor"`. PAC's own `PANEL.ClassName = "editor"` is overwritten.
2. `pace_editor` is registered with `vgui.Register`, not derma, so `isStockClass` keeps it and `vgui.GetControlTable` finds it.
3. `Openers.Commands` scores PAC's commands. Each starts at 3 (same addon folder):
   - `pac_editor`: +2 (`editor` opener word) +1 (class word) = 6
   - `pac_editor_panic`: 6
   - `pace_settings`: +2 (`settings`) +1 (`pace` class word) = 6
   - `pac_asset_browser`: 5
4. The top score is below `AUTO_SCORE = 7`, so `Best` returns nil.
5. `Suggest` falls through to `{ kind = "class", class = "pace_editor" }`.
6. `Recipes.Open` then runs a bare `vgui.Create("pace_editor")` and optionally `MakePopup`.

**What `pace.OpenEditor` does that is skipped**
- `pace.Editor = editor`, `pace.Active = true`
- the `editor.Close` override that routes to `pace.CloseEditor`
- `pac.Enable()`, `pace.RefreshFiles()`, `pace.SetLanguage()`
- `RunConsoleCommand("pac_in_editor", "1")`, `pace.SetInPAC3Editor(true)`
- `pace.Call("OpenEditor")`, which enables the editor view and its mouse hooks

**Reproduction**
1. Open PAC, open the picker, click the editor, accept the default.
2. Rejoin with `autoRestore` on (the default).

**Impact**
- A half-initialised editor appears at spawn. Its exit button and zoom frame (created in `Init` as world-panel children) appear on screen.
- `pace.Editor` is still `NULL`. `pace.ShowSpecial` and `pace.FixMenu` (`panels/properties.lua:31,39`) call methods on it and error.
- The exit button calls the stock `DFrame:Close`, not `pace.CloseEditor`.
- Running `pac_editor` afterwards creates a second editor. `pace.tree` and `pace.properties` are overwritten, so the pinned one is orphaned from PAC's logic.

**Fix**
```lua
elseif sig.class and vgui.GetControlTable(sig.class) and #info.commands == 0 then
	info.recipe = { kind = "class", class = sig.class }
```
`class` remains in `Recipes.Choices` for a deliberate choice.

### 5.3 B2 — Auto-restore runs openers at join and leaves their side effects active

**Severity:** HIGH. **Confidence:** Proven.

**Evidence**
- [recipes.lua:456-465](lua/pinnedpanels/recipes.lua#L456) — the join hook.
- [recipes.lua:444](lua/pinnedpanels/recipes.lua#L444) — `concommand.Run`.

**Control flow**
1. First `PinnedPanelsCatalogChanged` of the session → next frame → `Recipes.Catch()`, then `Recipes.Open` for every tab still waiting.
2. `expecting[rec.id]` is set, so the caught window attaches with `opened = false`. Cursor mode is not entered.
3. The shell is ghosted: mouse off, alpha 0.

**Impact, PAC** (recipe `pac_editor`, chosen by hand or learned from a bind)
- Every join runs `pace.OpenEditor`: PAC's camera takes over, movement is PAC's, the server is told the player is in the editor.
- The popup that gave PAC its cursor is ghosted, so there is no cursor until the player enters cursor mode.

**Impact, ULX** (recipe learned from the `ulx menu` bind)
- `xgui.toggle` → `xgui.show` calls `gui.EnableScreenClicker(true)` (`xgui_client.lua:407`). Every join starts with a free cursor.
- The command is a **toggle**. A manual "Open" on a tab whose XGUI is already visible elsewhere would hide it.

**Fix (as first proposed)**: at join, only `Catch()`; open on join only for `desktop` recipes or behind a per-pin flag that defaults off.

**Correction from passes 2 and 3**: `desktop` recipes are not safe to run at join either. Widget `init` functions are arbitrary code (N5, N9). The corrected rule: **run no opener at join**. Catch what is already open, and let the player open the rest.

### 5.4 B3 — Part mode never notices the owner removing an ancestor or taking the panel back

**Severity:** HIGH. **Confidence:** Proven.

**Evidence**
- [embed.lua:214-224](lua/pinnedpanels/embed.lua#L214) — `check` tests shell and target validity, then `if e.mode ~= "embed" then return end`.
- No code anywhere in `embed.lua` reads an adopted panel's current parent.

**Why (removal)**
- A reparented panel is no longer a descendant of its old ancestors, so removing them does not remove it.
- PAC's `panels/tree.lua:603-618` removes top-level nodes in `Populate`. A pinned sub-node survives, showing a part that may no longer exist.
- The placeholder dies with the ancestor, which is the only trace.

**Why (reclaim)**
- ULX's `xgui.processModules` (`xgui_client.lua:222-259`) calls `xgui.base:Clear()`, which sets every sheet panel's parent to `xgui.null`, then re-adds permitted ones with `AddSheet`. It runs on every `UCLAuthed` for the local player.
- A pinned module panel leaves the box. The target and shell are both still valid, so the tab stays "live" and empty.

**Counter-example that is handled**
- PAC's `properties.lua:1129-1137` removes rows by reference (`data.left:Remove()`). The target itself becomes invalid, and `check` releases it.

**Impact**
- A stale panel shown indefinitely, or an empty tab.
- On release, `p:SetParent(m.parent)` forces the panel back with a dock and position remembered from before, fighting whatever the owner did since.

**Fix**
```lua
if e.mode == "part" then
	if not IsValid(e.placeholder) then e.orphaned = true return Embed.Release(src) end
	if e.target:GetParent() ~= e.box.inner then e.reclaimed = true return Embed.Release(src) end
end
```
In `Release`: remove the target when `orphaned`; when `reclaimed`, remove only the placeholder and leave the target alone.

**Extension from pass 2**: the parent check should also apply to embed mode's adopted children. Cloudbox's `DContentMain` reparents itself to the HUD panel in every `Think`.

### 5.5 B4 — A re-popped shell is corrected only every 0.25 s

**Severity:** MEDIUM. **Confidence:** Proven for the state; the visual extent is Runtime.

**Evidence**
- [embed.lua:231](lua/pinnedpanels/embed.lua#L231).
- PAC `panels/editor.lua:458-475`: `GainFocus` calls `MakePopup()`, `SetVisible(true)`, `AlphaTo(255, 0.1, 0)`.
- PAC `panels/properties.lua:810-811`: clearing the property search calls `pace.Editor:KillFocus()` then `MakePopup()`.

**Timeline for `GainFocus`**
- t = 0: shell becomes a mouse- and keyboard-enabled popup; alpha animates from 0 to 255 over 0.1 s.
- t ≤ 0.25 s: `check` calls `ghost`. If the animation is still running, it overwrites `SetAlpha(0)` on the next frame.
- t ≤ 0.35 s (next tick + animation end): the following `check` ghosts it for good.

**Impact**
- The emptied PAC frame (it paints a full-height tab-control texture and the render-time bar) flashes.
- For the same window it takes mouse and keyboard at its old position.

**Fix**: move the three-getter test (`IsMouseInputEnabled`, `IsKeyboardInputEnabled`, `GetAlpha`) to a per-frame check while `Embed.live` is non-empty. Keep `adoptChildren` off the frame path (see N12 for the cheap version).

**Confirmed again in pass 3**: MQS re-shows its menu with `AlphaTo(255, 0.4)` on the shell, a flash of up to about 0.65 s.

### 5.6 B5 — Cursor ownership desyncs with owners that call `gui.EnableScreenClicker`

**Severity:** MEDIUM. **Confidence:** Proven for the state; whether the cursor disappears is Runtime.

**Evidence**
- [input.lua:149-161](lua/pinnedpanels/input.lua#L149) — `Input.Cursor` returns early when `want == Input.clickerOn`.
- Callers in other addons:

| Addon | Where | Call |
|---|---|---|
| PAC3 | `panels/editor.lua:484` (`KillFocus`) | `EnableScreenClicker(false)` |
| PAC3 | `settings.lua:2488,2496` | both |
| ULX | `xgui_client.lua:407,418` | on show, off on hide |
| libNyx | `libnyx_liquidglass.lua:127,134` | on open, off in `OnRemove` |
| DarkRP | `base/cl_gamemode_functions.lua:18` | toggled by F3 |
| DarkRP FAdmin | `cl_scoreboard.lua:110,128` | on/off with the scoreboard |

**Why**
- After another addon turns the clicker off, `Input.clickerOn` is still true. No later call re-enables it until cursor mode is toggled off and on.
- Separately, when an owner re-shows a hidden embedded window, [embed.lua:226-230](lua/pinnedpanels/embed.lua#L226) only clears the "closed" notice. Cursor mode is only entered on the first attach.

**Impact**
- The banner says cursor mode while the engine's clicker is off.
- A re-shown XGUI or DarkRP F4 menu appears in its tab but ignores the mouse until the cursor key is pressed.

**Fix**
- In `think()`: if `Input.clickerOn and not vgui.CursorVisible()`, call `gui.EnableScreenClicker(true)`.
- In `check`, on a closed→open transition: if the shell was mouse-enabled before re-ghosting, `Input.SetCursorMode(true)`.

### 5.7 B6 — Auto-size measures the wrong thing on embedded tabs

**Severity:** MEDIUM. **Confidence:** Proven.

**Evidence**
- [window.lua:332-364](lua/pinnedpanels/vgui/window.lua#L332) — `AutoSize`.
- [tabs.lua:200-208](lua/pinnedpanels/vgui/tabs.lua#L200) — `findCanvas`, an unbounded breadth-first walk.
- [tabs.lua:466-485](lua/pinnedpanels/vgui/tabs.lua#L466) — `NaturalSize`.

**Why**
- `findCanvas` returns the first descendant with `GetCanvas`. In an embedded window that is some inner list, not the window.
- `bottomExtent` calls `InvalidateLayout(true)` on each of that canvas's children.
- `autosize` and `autosize_all` have no visibility filter for adopted tabs.

**Impact**: a pinned PAC editor is resized to the height of its part tree.

**Fix**: `if tab.adopt then return end` at the top of `AutoSize`, matching the adopt skip already at [tabs.lua:414](lua/pinnedpanels/vgui/tabs.lua#L414).

### 5.8 Edge cases C1–C13

| # | Issue | Evidence | Confidence |
|---|---|---|---|
| C1 | `e.moved` and `Embed.byPanel` are never pruned. Each PAC `MakeBar()` (language change, file refresh) adds a dead entry; LVS adds one per tab click (N12) | [embed.lua:61-72](lua/pinnedpanels/embed.lua#L61) | Proven, LOW |
| C2 | `Teardown` clears `Desktop.panels` before `Embed.ReleaseAll()`. Each release fires `PinnedPanelsAdoptChanged` → `Reconcile`, which creates windows mid-reload. Those survive the reload running the old code | [desktop.lua:275-288](lua/pinnedpanels/desktop.lua#L275) | Proven, LOW |
| C3 | `sanitizeAdopt` accepts a signature with `w` but no `h`. `Match` then does `cand.h - nil` and errors on every Catch tick | [recipes.lua:134](lua/pinnedpanels/recipes.lua#L134), [storage.lua:94](lua/pinnedpanels/storage.lua#L94) | Proven; needs a hand-edited file or import |
| C4 | Importing a layout while embeds are live: an imported `adopt:<n>` with the same number passes the "still pinned?" test and inherits the wrong live panel | [hub_settings.lua:430-432](lua/pinnedpanels/vgui/hub_settings.lua#L430), [embed.lua:239-244](lua/pinnedpanels/embed.lua#L239) | Proven |
| C5 | `Storage.Import` un-confirms `command` recipes but not `class` ones. A shared string can make a later "Open" construct any registered panel class | [storage.lua:396-400](lua/pinnedpanels/storage.lua#L396) | Proven, LOW |
| C6 | A weak match asks with `Derma_Query`. `Wake()` resets `checked`, so the same question returns after every pin, unpin, merge or hide. "No" is not remembered | [recipes.lua:339-345](lua/pinnedpanels/recipes.lua#L339), [recipes.lua:411-412](lua/pinnedpanels/recipes.lua#L411) | Proven |
| C7 | The shell's original alpha is read at attach. Caught mid-fade, it is restored semi-transparent on release | [embed.lua:115](lua/pinnedpanels/embed.lua#L115) | Plausible in pass 1; concrete with MQS in pass 3 |
| C8 | Only the shell's size follows the box, not its position. Owner popups placed relative to the shell appear at its old location | [embed.lua:43-46](lua/pinnedpanels/embed.lua#L43); PAC `properties.lua:31,39`, `extra_properties.lua:956-960`, `animation_timeline.lua:259-260` | Proven |
| C9 | `isStockClass` builds its list from `derma.GetControlList()`, which includes every addon class registered through `derma.DefineControl` | [recipes.lua:88-95](lua/pinnedpanels/recipes.lua#L88) | Proven |
| C10 | After the owner removes its window, adopted children are orphans in our box for up to 0.25 s, with their `Think` and `Paint` still running | [embed.lua:218](lua/pinnedpanels/embed.lua#L218) | Proven; whether any error is Runtime |
| C11 | Hiding a pinned window with a live embed removes our window but keeps the shell ghosted. The owner's window is gone from the screen though still "open" | [desktop.lua:247-251](lua/pinnedpanels/desktop.lua#L247) | Proven; possibly intended |
| C12 | With `needsKeyboard`, a click inside gives our window the keyboard. If that produces a keyboard focus, `gated()` silences every hotkey including the cursor key until a world click | [input.lua:28-31](lua/pinnedpanels/input.lua#L28), [embed.lua:251-271](lua/pinnedpanels/embed.lua#L251) | Runtime |
| C13 | `unfilter` calls `SetVisible(true)` on every row it hid, even if the owner hid that row itself in the meantime | [tabs.lua:210-226](lua/pinnedpanels/vgui/tabs.lua#L210) | Plausible |

### 5.9 PAC3 compatibility in detail

**The editor's structure**
- `pace_editor` derives from `DFrame`. Its direct children are the stock chrome, a `DVerticalDivider` (docked `FILL`) and a `DMenuBar`.
- The divider holds the part tree (top) and the properties panel (bottom).
- The exit button and zoom frame are created with no parent. They are world-panel children positioned against the screen in the editor's `Think`.

**Why embed mode is structurally sound**
- Only the divider and the menu bar change parent. Neither reads `GetParent()`.
- Everything PAC rebuilds dynamically (tree nodes, property rows) is below the divider and moves with it.
- `MakeBar()` removes and recreates the menu bar. The new one is a new direct child of the shell and is adopted on the next tick.
- Property text editing uses a parentless popup `DTextEntry` positioned with `LocalToScreen` and re-positioned in its own `Paint`, so it follows the embedded label.

**What goes wrong**

| Problem | Detail | Fixable here? |
|---|---|---|
| Recipe | B1 | Yes |
| Join behaviour | B2 | Yes |
| Focus toggle | `KillFocus` hides the shell after a 0.1 s fade, so the tab shows "closed" (reasonable). `GainFocus` causes B4 | Yes (B4) |
| Properties collapse | `editor.lua:409-433` (default `pac_auto_size_properties 1`) sets the divider's top height to `ScrH() - min(propertiesHeight + …, ScrH()/1.5)`. In a pinned window shorter than the screen, `DoConstraints` clamps it and the properties get their 40 px minimum on every part selection | No. Document it |
| Lost drawing | The editor's `PaintOver` draws the render-time bar and version text on the shell | Possibly (shell paint passthrough, §9.4) |
| Outside the window | Exit button and zoom frame stay where PAC puts them | No |
| Shell-relative geometry | C8: special popups, menus, timeline, part-tutorial popups, and `wires.lua:294-295` hit-testing all use the shell's old rectangle | Partly (sync position) |
| Shell fights its size | `Think` calls `SetTall(ScrH())`, `SetWide(max(w, 200))` and `SetPos` every frame. After each box layout the shell is set to the box size, then back: one extra shell layout per box layout, no loop | Harmless |
| Part mode on tree or properties | `DVerticalDivider:PerformLayout` keeps calling `StretchToParent` and `SetTall` on the moved panel, now measured against our box. Whether the `FILL` dock immediately wins it back is Inferred | See B3 |
| Screen clicker | `KillFocus` turns it off (B5) | Yes |

### 5.10 ULX and ULib compatibility in detail

**ULib**
- It replaces the `hook` library. `hook.GetTable()` returns a classic-shaped table, so Record mode's opener scan works.
- Non-string hook identifiers are supported and are removed when `IsValid` fails, so panel-keyed hooks behave as in stock.
- A hook returning a non-nil value stops the chain. No Pinned Panels hook returns a stray value (only `PlayerBindPress` returns `true`, intentionally).

**XGUI structure**
- `xgui.anchor` is an `xlib_Panel` popup created once at init and kept for the session: hidden and alpha 0 when closed.
- `xgui.base` (a property sheet), the info bar and the progress box are its direct children, positioned without docking.
- `xgui.anchor.Paint` runs the whole `xlib` animation queue (`hook.Call("XLIBDoAnimation")`).

**Why whole-window embed is robust**
- The anchor is never removed, so the tab stays live and toggles between content and "closed".
- The animation queue keeps running on the ghosted anchor (see §4).
- Text entries: ULX's hook enables the keyboard on the anchor, ours enables it on our window, and the next `check` re-ghosts the anchor.
- `processModules` only rearranges panels below `xgui.base`.

**What goes wrong**

| Problem | Detail |
|---|---|
| Opener is a toggle | B2 |
| Screen clicker left on at join | B2 |
| Re-shown XGUI ignores the mouse | B5 |
| Module panels in part mode | B3 |
| Identity | C9: `xlib_Panel` is dropped as "stock". The source file then resolves to `xlib.lua` through `Init`, a helper library shared by every xlib window |
| No command suggested | `ulx menu` is registered from ULib's `commands.lua`, which is in another addon folder. Recipe is `watch` until learned from the bind |

---

## 6. Pass 2 — Cloudbox, PlayerModel Selector, gPhone, libNyx

### 6.1 N1 — Pinning the Cloudbox content tab hijacks Cloudbox's singleton state

**Severity:** HIGH. **Confidence:** Proven.

**Evidence**
- [sources.lua:235-246](lua/pinnedpanels/sources.lua#L235) — `buildCreation` calls the tab's function again.
- Cloudbox `client/spawnmenu.lua:131-241` — `AddCloudboxTab`.

**Why**
The comment says "Each call returns a new, independent container (G13)". For Cloudbox that is false. Each call:
- re-registers `cloudbox_localmode` and `cloudbox_reload` with closures over the **new** panel;
- overwrites the file-level `cbHtmlOnline` / `cbHtmlOffline`.

**Reproduction**
1. Pin `creation:Cloudbox`.
2. Click "Reconnect" in either copy, or change `cloudbox_lowfps` or `cloudbox_url` (both run `cloudbox_reload`).

**What `cloudbox_reload` then does to our tab**
1. `spnMenu = panel:GetParent()` — that is our `PinnedPanelsClip`.
2. `panel:Remove()` — our host's content is removed from under it.
3. Next frame: `newPanel = AddCloudboxTab()`, `newPanel:Dock(FILL)`, `spnMenu:Add(newPanel)`.

**Impact**
- The spawn menu's own Cloudbox tab is no longer the one that reloads or receives updates.
- The replacement panel fills our clip, so the tab looks alive. But `host.content` is the dead panel and `host.built` is still true: crop, filter, auto-size and `Unbuild` all silently stop working on that tab.
- After unpinning, `cbHtmlOnline` points at a removed panel until the spawn menu rebuilds.

**Fix**
There is no clean automatic fix. Two cheap mitigations:
- In `HOST:Think`: rebuild when `self.built` and the content has become invalid (with a retry cap).
- Around `e.fn`: snapshot `concommand.GetTable()`. If the builder replaced any command, warn once that this tab is single-instance and is better pinned from the spawn menu with the picker.

**What works**
- The Options pages (`tool:CloudboxUser`, `tool:CloudboxServer`) are ordinary control panels.
- The DHTML panel reports focus through `OnTextEntryGetFocus`, which our hook handles.

### 6.2 N2 — Every libNyx window has the same signature

**Severity:** HIGH. **Confidence:** Proven.

**Evidence**
- [recipes.lua:39-53](lua/pinnedpanels/recipes.lua#L39) — `ownFile`.
- [recipes.lua:126-135](lua/pinnedpanels/recipes.lua#L126) — `Match`.
- libNyx `libnyx_components.lua:235-365` — `createFrame`.

**Why**
- `createFrame` builds a plain `DFrame` and assigns `Paint`, `Think`, `PerformLayout`, `Close` and `Remove` from the library file.
- `ownFile` checks `Init` first (stock for a `DFrame`, skipped), then `Paint`, which is in `libnyx_components.lua`.
- No class (stock `DFrame`). No title (`SetTitle("")`; libNyx draws its own `f.title`).
- That leaves the source file alone, and `Match` treats a file match as strong.

**Impact**: a pinned libNyx window silently takes any other libNyx window from any addon when it opens. No confirmation is asked.

**The same failure elsewhere**
- ULX: `xlib.lua` (C9).
- Glide on a non-Workshop install: `styled_theme_tabbed_frame.lua` (pass 3).

**Fix**
- Continue the breadth-first walk past the first hit and store `src2`: the first non-stock file that differs from `src`. For the showcase that is `libnyx_maindemo.lua`.
- `Match` requires `src2` to be equal when the saved signature has one. Old saves without it still match.

**Known limit**: Wire's E2, CPU and GPU editors share class and files and have no title. `src2` cannot separate them.

### 6.3 N3 — A window caught mid-open-animation is embedded broken

**Severity:** HIGH. **Confidence:** Proven.

**Evidence**
- [recipes.lua:445](lua/pinnedpanels/recipes.lua#L445) — `Recipes.Open` calls `Catch()` synchronously after running a command.
- [recipes.lua:378](lua/pinnedpanels/recipes.lua#L378) — `Catch` only tests the frame's own visibility and alpha.
- [embed.lua:115-116](lua/pinnedpanels/embed.lua#L115) — original alpha and size are read at attach.
- libNyx `libnyx_components.lua:260-330`.

**Why**
- A libNyx frame opens over 0.22 s. It starts at 12% of its size with its **children** at alpha 0; the frame's own alpha is 255.
- `OnChildAdded` sets each new child's alpha to the current `contentAlpha`.
- `Think` raises the alpha by looping over `self:GetChildren()`.
- Once the children are in our box, that loop no longer reaches them.

**Impact**
- Opened by command: caught on frame 0, always. The tab's content is invisible permanently.
- Opened by the player: the 0.5 s tick lands inside a 0.22 s animation roughly 4 times in 10.
- `e.original.w/h` is the thumbnail size, so release restores a thumbnail.

**Fix**
- Catch only a settled window: seen on two consecutive ticks with the same size **and alpha** (the alpha part comes from MQS in pass 3).
- Drop the synchronous `Catch()` in `Recipes.Open`.

### 6.4 N4 — Catching an always-present frame forces cursor mode

**Severity:** MEDIUM. **Confidence:** Proven.

**Evidence**: [recipes.lua:326](lua/pinnedpanels/recipes.lua#L326).

**Why**
- gPhone's `phoneBase` is a `DFrame` created once and kept, parked with 40 px showing at the bottom of the screen.
- A `DFrame` is mouse-enabled by default. It is not a popup until `showPhone` first calls `MakePopup`.
- `Catch` finds it visible, and since we did not open it, attaches with `opened = true`.

**Impact**: with gPhone pinned, cursor mode turns on at every join and after every phone reboot (destroy then build).

**Fix**: add `and panel:IsPopup()` to the condition.

### 6.5 N5 — Pinning the "Player Model" C-menu widget leaves a dead tab

**Severity:** MEDIUM. **Confidence:** Inferred on one point.

**Evidence**
- [openers.lua:161-171](lua/pinnedpanels/openers.lua#L161).
- Selector `lf_playermodel_selector.lua:1538-1553`: the widget's `init` is replaced with `window:Remove()` plus `RunConsoleCommand("playermodel_selector")`.

**Why**
- `OpenDesktop` tests only `IsValid(frame)`.
- The inferred point: whether `IsValid` is still true in the frame `Remove()` was called. Pinned Panels itself checks `IsMarkedForDeletion` elsewhere, which suggests it is.
- If so, the doomed empty frame is embedded and vanishes on the next tick.

**Impact**
- The tab waits forever: its signature says "desktop widget", and the real selector window has no such signature.
- Each "Open" runs `init` again, which toggles the selector's visibility.

**Fix**: `if not IsValid(frame) or frame:IsMarkedForDeletion() then return nil end`. Superseded by the fuller fix in N9.

### 6.6 N6 — A changed title makes a pin unmatchable

**Severity:** LOW. **Confidence:** Proven.

**Evidence**: [recipes.lua:131](lua/pinnedpanels/recipes.lua#L131).

**Why**: the selector's title is `"Enhanced PlayerModel Selector " .. Version`. Without a class, a titled window must keep its title, so after an update `Match` returns nil.

**Fix**: same source with a different title becomes a weak match (ask once) instead of no match.

### 6.7 N7 — Size sync is one-way

**Severity:** LOW (limitation). **Confidence:** Proven.

**Evidence**
- [embed.lua:43-46](lua/pinnedpanels/embed.lua#L43).
- gPhone `cl_animations.lua:28-77` resizes `phoneBase` for landscape apps.

**Why**: the box sets the shell's size. Nothing carries a size the owner sets on its own window back to the box.

**Impact**: gPhone's rotated screen is laid out for a size our box does not have, and it clips.

**Fix**: none that is safe in general. PAC forces its shell to screen height every frame, so following the shell would break PAC. Document it.

### 6.8 Per-addon notes

**Enhanced PlayerModel Selector**
- `playermodel_selector` is correctly chosen: same file (6) + `selector` title word (2) = 8.
- It is a toggle (`ToggleVisible` when the frame exists). `Recipes.Open` only runs when the tab is not live, so that is safe in practice.
- Its own `OnTextEntryGetFocus` hook tests `pnl:HasParent(Frame)`. After embedding that is false, so only our hook acts. Clean.
- The minimise and maximise buttons are `DFrame` chrome and stay in the hidden shell.
- Under B2 it opens at every join.

**gPhone**
- "Open" and "close" are position animations of the frame, not visibility. The tab never shows "closed".
- On hide, gPhone disables mouse input on `phoneScreen`, which is in our box. So the pinned screen is visible but dead while the phone is "hidden", and live when shown. Coherent, if surprising.
- `phoneBase.Paint` draws the phone body. Embedded, there is a screen and a home button with no bezel.
- The camera app reads `phoneBase:GetPos()` (C8).
- Destroy and rebuild are handled: release, then re-catch.

**libNyx**
- `installGlobalMenuSkin` patches the `DMenu`, `DMenuOption` and `DMenuDivider` class tables. Class names are unchanged, so keyboard-driven menus still find their options.
- `notification.AddLegacy` is replaced with a function taking the same arguments. Our calls work.
- Components use `gui.MousePos()` with `ScreenToLocal`, so they survive reparenting.
- The frame's `OnChildAdded` runs when panels are returned on release. It only sets alpha (255 when idle) and clears a background flag.
- The liquid-glass demo draws everything in its root's `Paint` and closes on Escape through the root's `OnKeyCodePressed`. Embedded, it is an empty tab that cannot be closed from the keyboard.

---

## 7. Pass 3 — Wire, DarkRP, WAC, LFS, LVS, Glide, simfphys, MQS, Aden, VPhysics-Jolt

### 7.1 N8 — `Openers.Best` auto-picks an unrelated command from the same addon

**Severity:** HIGH. **Confidence:** Proven.

**Evidence**
- [openers.lua:99-112](lua/pinnedpanels/openers.lua#L99) — scoring.
- [openers.lua:126-132](lua/pinnedpanels/openers.lua#L126) — `Best`.

**Why**
- Any command whose function lives in the window's addon folder starts at 3.
- Opener words in the command's name add up to 3 each.
- Nothing has to connect the command to the window.

**Wire trace, for the Expression 2 editor**

| Command | Score |
|---|---|
| `wire_sound_browser_open` | 3 + `browser` 2 + `open` 3 = **8** |
| `flir_toggle` | 3 + 1 = 4 |
| `wire_pod_hud_show` | 3 + 1 = 4 |
| `wire_expression2_reloadeditor`, `toolcpanel`, `e2helper` | 3 |

8 ≥ `AUTO_SCORE` and the margin is 4 ≥ `AUTO_MARGIN`. The command is not "risky". It is suggested with `confirmed = true`.

**Impact**
- Pin the E2 editor with the default: every join and every "Open" opens the Wire **sound browser**.
- The tab never fills, because the sound browser's class does not match.
- The same suggestion is made for any Wire window.

**Fix**: a folder-only command never auto-qualifies. Require one of: defined in the window's file, upvalue evidence, or a title or class word in its name.

### 7.2 N9 — Most C-menu widgets are launchers, and we embed their empty frame

**Severity:** HIGH. **Confidence:** Proven.

**Evidence**
- [openers.lua:161-171](lua/pinnedpanels/openers.lua#L161) — `OpenDesktop`.
- [openers.lua:189-200](lua/pinnedpanels/openers.lua#L189) — `PinDesktop`.
- [openers.lua:150-157](lua/pinnedpanels/openers.lua#L150) — `DesktopId`.

**Why**: `OpenDesktop` assumes `init` fills the frame it is handed.

| Widget | Addon | What `init` does |
|---|---|---|
| `WireExpression2_ViewRequestMenu` | Wire | Fills the frame. **Works** |
| `LFSMenu` | LFS | Ignores the frame, calls its own `OpenMenu()` |
| `LVSMenu` | LVS | Ignores the frame, calls `LVS:OpenMenu()` (close-then-recreate) |
| `GlideDesktopIcon` | Glide | Ignores the frame, calls `Config:OpenFrame()` (a toggle) |
| `MSDModulesSetup` | MQS | `window:Close()`, then opens its own frame under the C menu |
| `PlayerEditor` (overridden) | PlayerModel Selector | `window:Remove()`, then runs a command |

**Impact**: an empty 400×400 `DFrame` is pinned, and the real menu opens beside it unpinned.

**Glide's extra problem**
- Glide's real frame has the same title as its widget entry.
- `DesktopId` identifies a widget window by title, so it tags the real frame as that widget.
- Picking the real frame by hand therefore saves a `desktop` recipe.
- Reopening runs `OpenDesktop`: it embeds the empty frame while `Config:OpenFrame()` toggles the real one.

**Fix**
1. Before `init`, snapshot the world panel's and the C menu's children.
2. After `init`: if our frame is invalid, marked for deletion, or has no children beyond its chrome, remove it and return the single new window instead.
3. `Signature` sets `desktop` only for a frame `OpenDesktop` itself created, never by title alone.

### 7.3 N10 — `GetTitle` is called unprotected on foreign frames

**Severity:** MEDIUM. **Confidence:** Inferred.

**Evidence**
- [recipes.lua:97-102](lua/pinnedpanels/recipes.lua#L97) — `titleOf`.
- [openers.lua:150-153](lua/pinnedpanels/openers.lua#L150) — `DesktopId`.
- GMod `dframe.lua:77-79`.
- Wire `wire_expression2_editor.lua:160`: `for _, v in pairs(self:GetChildren()) do v:Remove() end` in `Init`.

**Why**
- Wire's editor frames remove every stock `DFrame` child. The `lblTitle` field still holds the removed panel.
- `GetTitle` calls `GetText` on it.
- The inferred point: whether the engine throws on that call.

**Impact if it throws**
- `Recipes.Signature` throws inside `Catch`. That tick is abandoned whenever an editor is visible and any tab waits. (`checked[p]` is set first, so the panel is skipped on later ticks until the next `Wake`.)
- `RootFor` calls `DesktopId` on every ancestor of the hovered panel, so the picker errors on hover and the editor cannot be picked.

**Fix**: wrap both calls in `pcall`.

### 7.4 N11 — The default cursor key is F4, DarkRP's menu key

**Severity:** MEDIUM. **Confidence:** Proven.

**Evidence**
- [actions.lua:245](lua/pinnedpanels/actions.lua#L245) — `key = KEY_F4`.
- DarkRP `f4menu/cl_frame.lua:120-132` polls the key bound to `gm_showspare2`.

**Why**
- F-keys never reach `PlayerBindPress`, so their game bind cannot be blocked.
- One press toggles both cursor mode and the F4 menu.
- Once the F4 menu holds keyboard focus, `gated()` silences our half, and the two drift out of step.

**Fix**: at load, if the default key's bind is `gm_showspare2` and the gamemode is not sandbox, leave the key unbound and say so once.

### 7.5 N12 — Windows that swap a direct child go blank for up to 0.25 s

**Severity:** MEDIUM. **Confidence:** Proven.

**Evidence**
- [embed.lua:68-72](lua/pinnedpanels/embed.lua#L68), [embed.lua:225](lua/pinnedpanels/embed.lua#L225).
- LVS `cl_menu.lua:746-755`: `CreatePanel` removes `OldPanel` and creates a new `DPanel` directly under `LVS.Frame`.

**Why**: the new panel sits in the invisible shell until the next poll. Each swap also leaves a dead entry in `e.moved` (C1).

**Fix**: each frame, compare `shell:ChildCount()` with the count recorded after the last adoption; adopt when it differs. One C call, no allocation.

### 7.6 N13 — Obvious same-file openers are missed

**Severity:** LOW. **Confidence:** Proven.

**Evidence**
- [openers.lua:39-47](lua/pinnedpanels/openers.lua#L39) — `words`.
- [openers.lua:129](lua/pinnedpanels/openers.lua#L129) — the "only command" shortcut.

**Why**
- `lvs_openmenu` and `lfs_openmenu` are in the same file as their window (score 6). `openmenu` is one word and matches neither `open` nor `menu`, so they stay below 7.
- The shortcut requires `#commands == 1`, but `commands` holds every command in the addon, not the file.
- The comment claims `Expression2EditorFrame` yields `expression2`, `editor`. It yields `expression2editor`, `frame`: the lower→upper split does not fire after a digit.

**Fix**
- Match opener words as substrings.
- Pick the command when exactly one non-risky command lives in the window's file.

### 7.7 N14 — Custom menu classes are not recognised as transient

**Severity:** LOW. **Confidence:** Proven.

**Evidence**
- [recipes.lua:18](lua/pinnedpanels/recipes.lua#L18) — `TRANSIENT`.
- [nav.lua:427-433](lua/pinnedpanels/nav.lua#L427) — `options`.
- MQS `msdmenu.lua:4-41`.

**Why**: MQS uses its own `MSD.DMenu` and option classes.

**Impact**
- The picker can offer an open MQS menu as a window.
- Keyboard menu driving finds no options in it.

**What is compatible**: MQS replaces the globals `RegisterDermaMenuForClose` and `CloseDermaMenus` with versions bound to a private table. Our capture wraps whatever is installed for one call and restores it, so it still works, and stock `DMenu`s register into MQS's table and are closed by MQS's function.

**Fix**: test `p.m_bIsMenuComponent` instead of class names.

### 7.8 N15 — Owners that save their window geometry save ours

**Severity:** LOW. **Confidence:** Proven.

**Evidence**: [embed.lua:43-46](lua/pinnedpanels/embed.lua#L43); Wire `Editor:Close` → `SaveEditorSettings`.

**Why**: the E2 editor writes its size and position to `wire_expression2_editor_size` / `_pos` on close. While embedded, the shell's size is the tab's.

**Fix**: none cheap. Document it.

### 7.9 Per-addon notes

**Wire**
- The text editor is a custom panel with a hidden raw `TextEntry` as key sink. It never fires `OnTextEntryGetFocus`. This is the case `needsKeyboard` exists for, and the path holds: `Take` reads `root:IsKeyboardInputEnabled()` (true while the editor is visible).
- `Editor:PerformLayout` positions components from the shell's size, which we sync, so the layout follows the tab.
- The editor is a session singleton: created hidden, shown with `SetV(true)` (`MakePopup`, so B4), hidden on close. The tab toggles between content and "closed".
- `SetV` calls `self:GetParent():SetWorldClicker(...)` on the world panel; unaffected.
- Panels made with `vgui.CreateFromTable` keep their base's `ClassName`. Record mode wraps that function too.
- The "Wire" tool tab and its pages are standard.

**DarkRP**
- `F4MenuFrame` **is** a property sheet: the window's direct children are the tab scroller and every tab's panel. `DPropertySheet` manages them by reference and sizes the active one from its own size, which we sync. Embed should hold; tabs added later are new direct children and are adopted.
- The close button lives in the tab scroller and calls `Hide`. The tab shows "closed".
- The frame's `Think` polls the F4 key and hides itself; that still runs on the shell.
- It is `ParentToHUD()`, so its signature has `hud = true` (see §11).
- `F4MenuFrame` is registered through `derma.DefineControl`, so its class is dropped (C9). The source file `cl_frame.lua` still identifies it.
- No command is suggested (`_DarkRP_AnimationMenu` scores 6). The menu is opened by a server message, which cannot be learned. Recipe: `watch`.
- FAdmin's kick/ban and MOTD windows use `DoModal`. `Refusal` rejects them, as intended.

**LVS and LFS**
- N9, N12, N13.
- `LVS.Frame.Paint` draws the header bar, title and background on the shell.
- The frame is a stock `DFrame`; its close button is skipped chrome. Once embedded, the only way to close it is to unpin.

**Glide**
- N9 including the title collision.
- StyledTheme lives under `lua/includes/modules/`. On a Workshop install its path starts with `lua/includes/` and `isStock` skips it, so the source resolves to Glide's `config.lua` (good by accident). On a folder install it starts with `addons/…`, is not skipped, and the source is the shared theme file (N2).
- Because `Styled_TabbedFrame` has a class, the title rule at [recipes.lua:131](lua/pinnedpanels/recipes.lua#L131) does not apply: a different title still matches strongly.

**MQS**
- N9, N14.
- Every window fades in from alpha 0 with `AlphaTo` (N3, C7) and fades out before closing.
- Re-show is `AlphaTo(255, 0.4)` on the shell, whose `Paint` draws a background (B4).

**simfphys and WAC**
- Only tool pages, spawn lists and a custom key-binding control inside a tool page. Nothing unusual. WAC's bundled gamemodes are separate gamemodes and out of scope.

**Aden Character System**
- The character screen is a full-screen `DFrame` opened by the server, whose `Paint` calls `MoveToBack()` every frame and whose `OnRemove` exits the scene.
- Manually painted models are painted from a sibling's `Paint`; both would move together.
- It can be picked, but there is no reason to. No finding.

**VPhysics-Jolt**
- No Lua. Nothing to interact with.

---

## 8. Pass 4 — a general model, tested on twelve more addons

Passes 1–3 produced 34 findings across sixteen addons. Fixing them one addon at a time does not converge, so pass 4 changed the question. Instead of hunting bugs, it states a general model of how addon GUIs work, then classifies twelve more addons against it to see where the model fails.

**Result:** the model's six axes and three invariants held for all twelve. It needed two amendments (§8.4, §8.5) and one caveat (§8.6). The pass also found one new HIGH bug (N16).

### 8.1 The model: five kinds of GUI

Every GUI traced in 28 addons is one of these. The fifth kind was added by this pass.

| Kind | How it is made | Examples | Safe way to pin |
|---|---|---|---|
| **Control panel** | A function fills a panel we supply | Every tool and Utilities page; ACF-3, VJ Base, Advanced Duplicator 2, Wire, WAC, simfphys | Call the function ourselves. Solid, with the caveat in §8.6 |
| **Spawn-menu tab** | A function returns a new panel | Cloudbox, VJ Base, ArcCW | Calling it again is usually fine, but not guaranteed (N1) |
| **Disposable window** | Created on open, removed on close | PAC3, LVS, LFS, libNyx, Glide, MQS, PlayerModel Selector, StormFox2 | Catch it when it appears |
| **Persistent window** | Created once, then hidden and shown | XGUI, Wire and Starfall editors, DarkRP F4, gPhone, EasyChat | Catch it once; it stays |
| **Full-screen scene** | A screen-sized panel over a 3D scene | Helix, ArcCW customisation, Aden, libNyx liquid-glass | Do not pin (§8.4) |

### 8.2 The model: six axes with no majority convention

Windows differ on six axes. On none of them does one convention cover most addons, which is why per-addon fixes kept appearing.

| Axis | Variants seen | Examples |
|---|---|---|
| **Close signal** | `Remove()`; `SetVisible(false)`; alpha fade then either; moving off-screen; an overridden `Remove` that animates first | PAC; XGUI, EasyChat; PIXEL UI, MQS; gPhone; libNyx, Helix |
| **Layout** | Docking; the root's `PerformLayout` from its own size; fixed positions; a container managing children by reference | PlayerModel Selector; Wire, PIXEL UI; XGUI, LVS; PAC's divider, DarkRP's property sheet |
| **Drawing** | Children draw everything; the root's own `Paint` draws real content | Most; PAC, gPhone, LVS, MQS, PIXEL UI, libNyx |
| **Cursor** | `MakePopup`; `gui.EnableScreenClicker`; both | See the tally in §8.7 |
| **Keyboard** | `DTextEntry` hooks; a raw `TextEntry` key sink; popup focus | ULX; Wire, Starfall, PIXEL UI; PAC |
| **Identity** | Registered class; source file; `DFrame` title | Each is unreliable somewhere: UI libraries (class and file), versioned titles, removed chrome |

### 8.3 The model: three invariants

Only these held for every window in all 28 addons:

1. **A window is exactly one top-level panel.**
2. **Its owner drives it through a reference it keeps, and expects it to stay intact.** Owners call methods on the window, read its position and size, and manage its children by reference. None reaches its window by walking up from a child.
3. **The player knows how to open it.** Pinned Panels does not, and every automatic guess failed somewhere (B1, N5, N8, N9, N13).

The current design leans on the variable axes instead: Embed moves contents out (against invariant 2) and recipes guess openers (ignoring invariant 3).

### 8.4 Amendment 1 — full-screen scenes are not windows (N18)

**Severity:** LOW. **Confidence:** Proven.

Four addons use a screen-sized panel as an overlay on a 3D scene:

| Addon | Screen | Evidence |
|---|---|---|
| Helix | Tab menu and character screens | `gamemode/core/derma/cl_menu.lua:33-35` sets `ScrW() × ScrH()`; `PANEL:Remove` at line 442 is overridden to animate |
| ArcCW | Weapon customisation | `cl_customize2.lua:306-313`, `ArcCW.InvHUD`, with `gui.EnableScreenClicker` |
| Aden | Character creation | Pass 3 |
| libNyx | Liquid-glass demo | Pass 2 |

**Why it matters**: pinning one is meaningless in any hosting tier. Embedding moves a few floating buttons into a window and loses the scene; the picker and the catcher will still offer and take them.

**Fix**: in `Recipes.Refusal`, refuse a root that covers the whole screen and has its own non-stock `Paint`.

### 8.5 Amendment 2 — the spawn menu is not a given (N16)

**Severity:** HIGH. **Confidence:** Proven.

**Evidence**
- TTT2 `gamemodes/terrortown/terrortown.txt` and Cinema `cinema/cinema.txt` both declare `"base" "base"`. Neither has a spawn menu or C menu, and neither fires `PostReloadToolsMenu`.
- [desktop.lua:158-167](lua/pinnedpanels/desktop.lua#L158) — `Desktop.ready` is set only on the first `PinnedPanelsCatalogChanged`.
- [sources.lua:103-105](lua/pinnedpanels/sources.lua#L103) and [desktop.lua:291-294](lua/pinnedpanels/desktop.lua#L291) — the only two triggers of `Sources.Rebuild`: `PostReloadToolsMenu`, and load time when `g_SpawnMenu` already exists.
- [desktop.lua:26-28](lua/pinnedpanels/desktop.lua#L26) — `wanted` requires `Desktop.ready`.
- [recipes.lua:309-311](lua/pinnedpanels/recipes.lua#L309) — `Waiting` returns nothing until ready.

**Control flow in a non-sandbox gamemode**
1. Neither trigger fires. `Desktop.ready` stays false for the session.
2. No window control is ever created, no taskbar, nothing is caught. The hub is a spawn-menu tab and is unreachable.
3. The picker, palette and console commands still work, because they do not depend on readiness.
4. Picking a window runs `Embed.Take`: a record is added, the contents move into the box, and the shell is ghosted.
5. `Reconcile` runs, `wanted` is false, and no window is created to show the box.

**Impact**: the picked window disappears. Its contents sit in a hidden, unparented box. The only way back is `pinnedpanels_unpin_all` in the console.

**Fix**: become ready without the spawn menu. On `InitPostEntity`, if no catalogue has been built, call `Sources.Rebuild()`. `spawnmenu.GetTools()`, `spawnmenu.GetCreationTabs()` and the lists exist in every gamemode, so the rebuild itself is safe; it simply finds fewer sources.

### 8.6 Caveat — control panels updated by name (N17)

**Severity:** LOW. **Confidence:** Proven.

**Evidence**
- Advanced Duplicator 2 `stools/advdupe2.lua:1666`: `controlpanel.Get("advdupe2")`.
- VJ Base `stools/vj_tool_spawner.lua:39,170`, `vj_tool_mover.lua:96,115`, `vj_tool_bullseye.lua:28`, `vj_tool_equipment.lua:26`, `vj_tool_health.lua:31`.

**Why**: these tools refresh their page by fetching it by name. That returns the spawn menu's copy. A pinned copy is a second panel built by the same function; nothing updates it.

**Impact**: a pinned copy of those pages (the duplicator's file list, VJ's spawner lists) goes stale until "Rebuild content" is used.

**Fix**: none general without replacing `controlpanel.Get` permanently, which the design rightly avoids. A cheap mitigation: rebuild a pinned tool tab when the spawn menu's own panel for that tool changes its child count. Otherwise document it.

### 8.7 Tallies across all 28 addons

| Pattern | Count | Addons |
|---|---|---|
| Calls `gui.EnableScreenClicker` itself | 11 | PAC3, ULX, libNyx, DarkRP, ACF-3, ArcCW, EasyChat, StarfallEx, TTT2, Helix, Cinema |
| C-menu widget is a launcher, not a filler | 7 of 10 widgets | LFS, LVS, Glide, MQS, PlayerModel Selector, StormFox2 controller, Starfall user list. Fillers: Wire view requests, ACF scanner, StormFox2 settings (the last not read in full) |
| Frames built by a shared UI library | 7 libraries | xlib (ULX), libNyx, StyledTheme (Glide), MSD (MQS), PIXEL UI, MelonLib, vskin (TTT2) |
| Root's own `Paint` draws real content | 6 | PAC3, gPhone, LVS, MQS, PIXEL UI, libNyx |
| Editor frame with stock chrome removed (N10) | 2 | Wire, StarfallEx (`sfframe.lua:165`, a copy of Wire's editor) |
| Own menu class instead of `DMenu` (N14) | 2 | MQS, PIXEL UI (`PIXEL.Menu`) |
| Overrides `Remove` to animate | 2 | libNyx, Helix |
| Refreshes its tool page by name (N17) | 2 | Advanced Duplicator 2, VJ Base |
| No spawn menu at all (N16) | 2 gamemodes | TTT2, Cinema |

### 8.8 The twelve addons, classified

| Addon | Kind | Axes | Fits? |
|---|---|---|---|
| **PIXEL UI** | Library; disposable or persistent windows | `PIXEL.Frame` derives from `EditablePanel` with no `DFrame` chrome. Fades alpha over 0.1 s, then hides or removes (`GetRemoveOnClose`). Root paints the header and title. Root `PerformLayout` places the close button and sidebar. Own drag and resize from `gui.MouseX/Y`. Own `PIXEL.Menu`. Text entry wraps a raw `TextEntry` | Yes |
| **MelonLib** | Library | Draggable and resizable bases over `MakePopup`; manual painting helpers | Yes |
| **Helix** | Full-screen scene; many small windows | 92 registered classes; own animation system; manually painted children | Needed amendment 1 |
| **TTT2** | Windows in a non-sandbox gamemode | Own `vskin` library, 40 classes via `derma.DefineControl` (C9) | Needed amendment 2 |
| **Cinema** | Non-sandbox gamemode; a few popups | Scoreboard toggles the screen clicker; theatre panel is HUD-parented | Needed amendment 2 |
| **EasyChat** | Persistent window | `Show` + `MakePopup` to open; mouse and keyboard off, clicker off, `Hide` to close. Same shape as XGUI | Yes |
| **StarfallEx** | Persistent window | Same shape as Wire's editor, including removed chrome | Yes |
| **ACF-3** | Control panels; one filler widget | Large tool menu | Yes |
| **VJ Base** | Control panels; spawn-menu tab | Refreshes pages by name | Yes, with the caveat |
| **Advanced Duplicator 2** | Control panel | File browser refreshed by name | Yes, with the caveat |
| **ArcCW** | Full-screen scene; a tool page | `ArcCW.InvHUD` | Needed amendment 1 |
| **StormFox2** | Disposable windows; two widgets | One filler, one launcher; 24 classes via `derma.DefineControl` | Yes |

### 8.9 What the model implies for the design

Six rules. The first four were proposed before pass 4; the last two come from it.

1. **Never guess how a window opens, and never run foreign code unasked.**
   - The default recipe is always "catch it when it appears". That worked for every window in 28 addons.
   - An opener exists only if the player demonstrated it (Record mode, or a learned bind) and runs only on an explicit click.
   - This removes B1, B2, N5, N8, N9 and N13 as a class rather than one by one.
2. **Host by a ladder, chosen by probing the window, not by addon.** The ladder is Embed, then Wrap, then Manage (§8.10–§8.14).
3. **Treat the cursor and keyboard as shared.** Observe and re-assert; never assume ownership. Eleven of 28 addons toggle the screen clicker.
4. **Confirm identity, do not infer it.** Fingerprint the whole tree (class chain plus the set of source files). When two candidates fit, ask once and remember. Seven UI libraries make single-file identity unreliable.
5. **Refuse full-screen scenes** (N18).
6. **Do not depend on the spawn menu to become ready** (N16).

### 8.10 Six ways to host a foreign window

These are all the approaches available in GMod. Three are usable, and they form the ladder.

| # | Approach | How it works | Verdict |
|---|---|---|---|
| 1 | **Embed** | Move the window's contents into a pinned tab; keep the emptied window invisible | Tier 1, the default |
| 2 | **Wrap** | Leave the window whole, but keep it positioned exactly over the tab's content area, with our frame drawn around it | Tier 2, first fallback |
| 3 | **Manage** | Leave the window where its addon put it; remember and restore its position and size, hide and show it, list it in the taskbar | Tier 3, last fallback |
| 4 | Reparent the whole window | Make the window itself a child of the tab | Dead. This is what v1 did. A popup keeps a screen-space position and loses input once reparented (plan G45, G52) |
| 5 | Mirror | Leave the window elsewhere, draw it into the tab with `PaintManual`, forward mouse and keys by hand | Dead. Input forwarding would have to be reimplemented per control type; the plan already rules it out (G50) |
| 6 | Recreate | Build a second instance of the window's class inside the tab | Only safe for self-contained classes. PAC shows why it fails (B1) |

**Decision (owner, 2026-10-06):** Embed stays the default and should be made as robust as possible. Wrap is added. Manage returns as the fallback. This reverses the "Embed only" half of plan decision D23; Embed remains the mode every window is tried in first.

| | Embed | Wrap | Manage |
|---|---|---|---|
| Window's own drawing, layout and buttons | Lost or fragile today; mostly restored by §8.11 | Kept | Kept |
| Lives inside a pinned window | Yes | Yes | No |
| Tabs and groups | Yes | Yes (inactive tab's window is hidden) | No |
| Taskbar, minimise, quick keys, peek | Yes | Yes | Yes |
| Roll-up | Yes | Yes (hide the window) | No |
| Idle opacity | Yes | Yes (`SetAlpha` on the window) | Yes, same way |
| Click-through | Yes | Yes (window's mouse input off) | Possible the same way |
| Crop | Yes | No | No |
| Single clean header | Yes | No: a stock `DFrame` shows its header under ours | Not applicable |
| Keyboard navigation, filter bar | Yes | Yes (they only walk the panel tree) | No |
| Main risk | The shell and the tab drift apart | Stacking order between two popups | None |

### 8.11 Tier 1 — Embed, made robust

Almost every Embed failure in passes 1–4 has one cause: the emptied window (the shell) and the tab drift apart. The owner keeps talking to the shell, and nothing carries that across. The general fix is to make the shell and the tab behave as one window, in five ways.

1. **The owner's size wins.**
   - Today the tab pushes its size onto the shell and never listens back ([embed.lua:43-46](lua/pinnedpanels/embed.lua#L43)).
   - Instead: when the owner resizes its window, resize the tab to match. A user resize becomes a request; if the owner snaps back, the tab follows.
   - Fixes PAC's collapsing properties (the tab stays full height, as PAC requires), gPhone's landscape apps (N7), libNyx's opening animation, and Wire saving the wrong size (N15).
   - Consequence: a tab holding PAC cannot be made shorter than the screen, because PAC does not allow it.
2. **The shell follows the tab's position.**
   - Move the shell to wherever the tab's content is on screen.
   - Fixes every popup and menu an addon places relative to its window (C8).
3. **The tab draws what the shell would have drawn.**
   - The box calls the shell's own `Paint` and `PaintOver` under `pcall`.
   - Brings back PAC's render bar, gPhone's phone body, and the headers of LVS, MQS and PIXEL UI (§9.4).
   - Runtime: whether it draws at the right origin cannot be established statically.
4. **Check every frame, not four times a second.**
   - Re-ghosting, new direct children (`ChildCount`), and "has the owner taken this panel back" are each one or two cheap calls.
   - Fixes B4, N12 and the reclaim half of B3.
5. **Only take a window that has finished opening, and let go cleanly.**
   - Wait until size and alpha are stable across two ticks before embedding (N3, C7).
   - If the owner errors or keeps fighting afterwards, step down the ladder (§8.14).

**What Embed still cannot do**
- Full-screen scenes: refused in every tier (N18).
- One part of a window whose container manages it by reference (PAC's divider, a property-sheet page): part mode stays best-effort, and has no fallback tier, because Wrap and Manage act on whole windows.
- Spawn-menu tabs with singleton state (N1): not a hosting problem.

### 8.12 Tier 2 — Wrap

The window stays a real, intact top-level popup, so everything Manage gets right stays right: its own drawing, layout, buttons, cursor and keyboard. But it sits inside our frame, so it keeps most of what Embed offers.

**How it works**
- A pinned window is created as usual, with an empty content area for the tab.
- Each frame the foreign window is positioned and sized to cover that content area exactly.
- If the owner moves or resizes its window itself, our frame follows it (the same "owner wins" rule as §8.11).
- Nothing is reparented and nothing is ghosted. There is no release step: unpinning just stops following.

**How each feature maps**

| Feature | In Wrap |
|---|---|
| Move, resize, snap | Drag our frame; the window follows |
| Tabs and groups | `SetVisible(false)` on the inactive tab's window |
| Minimise, roll-up, taskbar, quick keys, peek, "show with C menu" | Hide and show |
| Idle opacity | `SetAlpha` on the window. May fight addons that animate their own alpha |
| Click-through | `SetMouseInputEnabled(false)` on the window |
| "Closed" notice | The owner hid or removed its window, as in Embed |
| Crop | Not available |

**What it cannot do**
- **Crop.** The engine draws the window at full size.
- **Hide the window's own title bar.** A stock `DFrame` shows its header under ours. Embed avoids this by cropping the strip away.

**Open questions, all Runtime**
- **Stacking order.** Our frame and their window are two separate popups, and theirs must stay just above ours. Addons that call `MakePopup` or `MoveToFront` on their own window will reorder them. How reliably that can be corrected each frame is unknown. This must be tested in game before Wrap is built.
- Whether an addon's own drag handling (PAC, PIXEL UI, Wire all implement dragging themselves) feels acceptable when our frame follows it.
- Whether hiding a window with `SetVisible(false)` for an inactive tab confuses owners that treat "not visible" as "closed" (XGUI's toggle, DarkRP's F4).

### 8.13 Tier 3 — Manage, as the last fallback

Manage is the mode built in phase 6a and removed under D23. It returns only as the tier of last resort.

**How it works**
- The window stays where its addon put it, with no frame of ours around it.
- Pinned Panels remembers and restores its position and size, hides and shows it, and lists it in the taskbar and the Pinned page.
- It relies only on invariants 1 and 2 of §8.3, so it cannot break the window.

**What it gives**
- Geometry memory across sessions.
- Taskbar entry, minimise, quick key, peek.
- Idle opacity through `SetAlpha`.

**What it does not give**
- Tabs and groups, crop, roll-up, a frame, keyboard navigation, the filter bar.

**When a window lands here**
- It failed Embed's probe or health watch, and Wrap is unavailable or failed too: for example the stacking order cannot be held, or the owner fights the position every frame.

**Saved layouts**: the plan currently loads an old `manage` pin as `embed` ([storage.lua:86-88](lua/pinnedpanels/storage.lua#L86)). With Manage back, `sanitizeAdopt` must accept `manage` again, and `wrap`.

### 8.14 Choosing a tier

The choice is made from the window's behaviour, never from which addon it belongs to.

**Probe, before embedding** (generic, read-only):

| Check | Result |
|---|---|
| Covers the whole screen and has its own non-stock `Paint` | Refuse (N18) |
| Size or alpha still changing across two ticks | Wait; it has not finished opening (N3) |
| Otherwise | Try Embed |

**Health watch, after embedding** (a few seconds, then cheap):

| Signal | Meaning |
|---|---|
| Lua errors whose source is one of the owner's files | The owner depends on something Embed moved |
| The owner re-enables input or alpha on the shell every frame | It will not stay ghosted |
| Adopted children keep leaving the box | The owner manages them by parent |
| The owner keeps overriding the size in a way the tab cannot follow | Layout cannot be shared |

**Stepping down**
- On a failed health watch: release the window exactly as it was, then host it in the next tier.
- Embed → Wrap → Manage. A failed Manage cannot happen; it does nothing that can fail.
- The tier that worked is remembered per signature, so the next session starts there.
- The player is told once when a window steps down, and can force a tier from the tab's menu.

**Unchanged by the ladder**: how a window comes back (rule 1), telling library-built windows apart (rule 4), and non-sandbox gamemodes (rule 6) break every tier equally and must be fixed regardless.

---

## 9. Cross-pass patterns

The sixteen addons of passes 1–3 produced a small number of recurring failure shapes. Pass 4 turned these into a model (§8) and counted them across all 28 addons (§8.7). These matter more than any single finding.

### 9.1 Deciding how a window comes back is the weakest part

Embedding mostly holds. Almost every HIGH finding is in recipe choice or execution.

| Addon | What the auto-chosen recipe does |
|---|---|
| PAC3 | Recreates the class, bypassing `pace.OpenEditor` (B1) |
| Wire | Runs the sound browser command (N8) |
| LVS, LFS | Widget: embeds an empty frame (N9). Picker: `watch`, missing the obvious command (N13) |
| Glide | Widget and picker both end at an empty frame (N9) |
| MQS | Widget: embeds a closed frame (N9) |
| PlayerModel Selector | Widget: embeds a removed frame (N5). Picker: correct command |
| ULX | `watch`, then a learned toggle (B2) |
| DarkRP, gPhone | `watch` (correct; nothing better exists) |

### 9.2 Identity by source file fails for UI libraries

| Library | Used by | Result |
|---|---|---|
| `xlib.lua` | ULX | All xlib panels share a source (C9) |
| `libnyx_components.lua` | Any libNyx addon | All frames identical (N2) |
| `styled_theme_tabbed_frame.lua` | Glide and other StyledTheme addons | Shared on folder installs (N2) |
| `wire_expression2_editor.lua` | E2, CPU and GPU editors | Three singletons identical; no fix proposed |

### 9.3 Other addons own the screen clicker too

Six call sites across four addons (table in B5). Pinned Panels assumes it is the only caller.

### 9.4 The root's own drawing is lost

| Addon | What the shell draws |
|---|---|
| PAC3 | Render-time bar, version text |
| gPhone | The phone body |
| libNyx liquid-glass | The whole demo |
| LVS | Header bar, title, background |
| MQS | Background and header |

A possible fix, untested: have `BOX:Paint` call the shell's `Paint(shell, w, h)` under `pcall`. It would work for paints that only use their own width and height. Whether the draw origin is right is Runtime.

### 9.5 Windows are caught before they have settled

| Addon | Animation | Effect of an early catch |
|---|---|---|
| libNyx | Size and child alpha over 0.22 s | Invisible content (N3) |
| MQS | Shell alpha over 0.3 s | Semi-transparent on release (C7) |
| ULX | Anchor alpha over 0.22 s | None visible (anchor draws nothing) |
| PAC3 | `GainFocus` alpha over 0.1 s | Flash (B4) |

### 9.6 Polling at 4 Hz carries correctness

Ghosting (B4), child adoption (N12) and removal detection (C10) all wait for the next tick. The first two have per-frame checks that cost one to three C calls.

---

## 10. Hostile cases A–O

Traced against the code, with the addon that exercises each.

| Case | What happens | Exercised by |
|---|---|---|
| **A.** Pinned panel removed by its owner | `check` sees the shell or target invalid within 0.25 s, releases, removes what was left in the box, and the tab waits (or goes, for `session`). Gap: C10 | PAC `CloseEditor`, gPhone `destroyPhone` |
| **B.** Owner replaces it with a new panel | As A, then `Wake` → `Catch` matches the new one by signature on the 0.5 s tick | PAC `OpenEditor`, LVS `OpenMenu` |
| **C.** Child created after pinning | A new direct child of the shell is adopted on the next tick (N12 gap). Deeper children need nothing | PAC `MakeBar`, DarkRP `addF4MenuTab`, LVS `CreatePanel` |
| **D.** Parent removed while a pinned child survives | **B3**: zombie in part mode | PAC tree `Populate` |
| **E.** UI opened and closed rapidly | Bounded by polling. Each recreated direct child leaves a stale `moved` entry (C1) | — |
| **F.** Pin and unpin repeatedly | Release restores parent, order, dock, margin, position, size and Z. Each change calls `Wake`, which re-signs every visible top-level panel (§11) | — |
| **G.** Several nested panels pinned | A part inside an already-embedded window lives in our window, and `ours()` refuses it | — |
| **H.** A panel containing another pinned panel | Part first, then its whole window: allowed (part-mode shells are not registered in `Embed.shells`). The divider carrying the placeholder moves; release works in either order | PAC |
| **I.** Resize during the owner's layout | No recursion found. `BOX:PerformLayout` sets the shell size; a same-size `SetSize` is a no-op. PAC's `Think` resets the height each frame: one extra shell layout per box layout | PAC |
| **J.** Addon reloaded while panels exist | C2 | — |
| **K.** Map change or disconnect | The client Lua state is destroyed; `ShutDown` flushes storage and stops Record mode. Then B2 on the next join | — |
| **L.** Panel invalid between two operations in one frame | Deferred callbacks (`ask`, `take`, auto-size completion, `NextFrame`) re-validate. `Recipes.Attach` checks validity after following a path | — |
| **M.** Two addons, same class name | The later `vgui.Register` wins; signatures differ by source file | — |
| **N.** Unusual or custom VGUI | Containers that track children in Lua tables keep laying out a moved part: `DVerticalDivider`, `DHorizontalDivider`, `DPanelList.Items`, `DPropertySheet.Items`, `DListView` lines. Custom menus: N14. Custom frames with removed chrome: N10 | PAC, Wire, MQS |
| **O.** PAC rebuilds a large section | Fine in embed mode (everything is below the divider). B3 in part mode | PAC |

---

## 11. Performance

No measurement was possible. The costs below are reasoned from the code; the millisecond figures are rough estimates.

| Path | Why it costs | When | Seriousness |
|---|---|---|---|
| `Recipes.Signature` on every visible top-level panel | `ownFile` runs `debug.getinfo` on every function in a panel's table. Because `vgui.Create` merges class tables into each panel, that is 50–150 functions per panel. `SourceFile` walks up to 200 panels when nothing non-stock is found. Estimate: tens of ms per stock-only window | First `Catch` tick after every `Wake()`, which fires on any window or tab change, any hide/show, and the first catalogue, **while at least one tab waits** | **High, momentary** |
| `Openers.Commands` | Loops every console command (thousands on a modded client). For a Workshop addon it also calls `file.Exists(from, addon)` per command | Each time the picker's selection changes | **Moderate** |
| `vgui.GetAll()` in `Recipes.HudPanels` | Allocates a table of every Lua panel and calls `GetParent` twice on each | Every second while a tab with a `hud` signature waits. That can be all session: a pinned DarkRP F4 menu waits until the first F4 press. Also triggered for desktop-widget signatures, which are found through the C menu anyway | **Moderate** |
| Picker `Select` | Two `Signature` calls plus `Suggest` (a third) | Per selection change | Low–Moderate |
| `Input` Think | A dozen `input.IsKeyDown` calls and five gate checks | Every frame | Negligible |
| `Embed.Check` | One `GetChildren()` allocation per embed | 4 Hz | Negligible |
| HUD banner | Cached text, three draw calls | Per frame in cursor mode only | Negligible |
| Taskbar `Think` | Runs only while visible | Per frame | Negligible |
| Window `Paint` | Reads cached setting colours; no allocation except `Color` reuse | Per frame per window | Negligible |

**Fixes, in order of value**
1. Keep `checked` across `Wake()` unless the waiting set gained a signature.
2. Cache `fileOf(fn)` per function and `Openers.Commands` per source file for the picker's lifetime.
3. Skip the HUD scan for desktop signatures; consider a lower rate or back-off for long waits.

---

## 12. Memory

| Item | Growth | Bound | Verdict |
|---|---|---|---|
| `e.moved`, `Embed.byPanel` | One entry per adopted panel, never pruned while the embed lives (C1) | Until release | **Leak while pinned**; small per entry, unbounded for LVS-style churn |
| `Nav.memory` | Last focused element per window id; holds a panel reference | Session | Minor |
| `checked` | Weak keys | Collected | Fine |
| `addons` cache in `Recipes.Addon` | One entry per source file | Session | Fine |
| Undo stack | 50 deep snapshots of the document | Capped | Fine |
| `Layout.closed` | 15 entries | Capped | Fine |
| Record mode `rec.created` | Every parentless panel created during recording | 30 s | Fine |
| Hooks keyed by panels | Removed when the panel dies | — | Fine |
| Timers | `Embed`, `Catch`, `Record`, `Storage`, two Nav timers; all named, all removed on their exit paths | — | Fine. `Catch` runs as long as anything waits |

---

## 13. Networking, security and persistence

### Networking
- None. No `net` calls, no receivers, no user messages, no server-side state. The server file list is the whole server side.

### Security
- **Imported layouts** are size-capped, decompression-capped and fully sanitised. Imported `command` recipes are un-confirmed and wait for the player.
- **C5**: imported `class` recipes are not gated. A shared string can name any registered panel class; a later "Open" constructs it. Not code injection, but it runs an arbitrary panel constructor of the importer's client. LOW.
- **Commands** are restricted to names matching `^[%w_%.%-+]+$`, arguments may not contain control characters, and they run through `concommand.Run`, which only reaches Lua commands.
- **Record mode** reads call stacks with `debug.getinfo` and `debug.getlocal`. It only reads.

### Persistence
- **What is saved**: window geometry and state, tab sources, titles, crop, quick controls, and for adopted panels the mode, signature, recipe and `needsKeyboard`. `session` recipes are never saved.
- **Identity stability**: signatures are stable within a session and across sessions for a given install. They are not stable across an addon update that changes a title (N6), across install types for library-located classes (Glide), or between a Workshop and a folder install.
- **Corrupt data**: quarantined, with the backup tried. `Sanitize` never fails. Gap: C3.
- **Version**: a newer file sets read-only mode. An old `desktop:<id>` tab is migrated to an embedded one.
- **Duplicates**: sources and window ids are de-duplicated on load.
- **Can a PAC or ULX panel realistically be restored?**
  - ULX: yes. The anchor exists all session; it is caught the first time it is shown.
  - PAC: only by catching it after the player opens it. The auto-chosen recipe is wrong (B1) and running the real command at join is harmful (B2).
  - In general: `watch` plus catching is the only universally safe path found across sixteen addons.

---

## 14. Architecture

Only structural points with a concrete consequence.

1. **Polling carries correctness.** Ghosting is an invariant that is cheap to check per frame, but is checked at 4 Hz (B4, N12, C10).
2. **`Embed` has no notion of the owner changing its mind.** It remembers where a panel came from and never looks at where it is now (B3, C1).
3. **`Recipes.Open` treats three trust levels alike.** A widget `init`, a class constructor and a console command are all "foreign code we run". Join-time restore runs all three (B1, B2, C5, N5, N9).
4. **Opener choice has no notion of evidence.** Being in the same addon folder is treated as relatedness (N8), while being in the same file is not treated as sufficient (N13).
5. **Generic window features assume our own content.** Auto-size, the filter and collapse cookies each need the same "is this tab foreign?" gate; only cookies have it (B6, C13).
6. **Identity assumes one file per window.** UI libraries break that (N2, C9).

What is sound and should be left alone: the single-writer document with batched change events, one `Think` hook, sanitise-on-every-load, scoped global overrides that restore on every path, and never reparenting a foreign popup.

---

## 15. Consolidated findings index

| ID | Title | Severity | Confidence | Pass |
|---|---|---|---|---|
| B1 | PAC editor pinned with a class recipe | HIGH | Proven | 1 |
| B2 | Openers run at join leave side effects | HIGH | Proven | 1 |
| B3 | Part mode misses ancestor removal and reclaim | HIGH | Proven | 1 |
| N1 | Cloudbox tab function is not side-effect free | HIGH | Proven | 2 |
| N2 | Library-built windows share a signature | HIGH | Proven | 2 |
| N3 | Window caught mid-animation | HIGH | Proven | 2 |
| N8 | Unrelated same-addon command auto-picked | HIGH | Proven | 3 |
| N9 | Launcher widgets embed an empty frame | HIGH | Proven | 3 |
| N16 | Never ready without a spawn menu; picked windows vanish | HIGH | Proven | 4 |
| B4 | Re-popped shell corrected only at 4 Hz | MEDIUM | Proven / Runtime | 1 |
| B5 | Screen clicker ownership desync | MEDIUM | Proven / Runtime | 1 |
| B6 | Auto-size on embedded tabs | MEDIUM | Proven | 1 |
| N4 | Always-present frame forces cursor mode | MEDIUM | Proven | 2 |
| N5 | Widget that removes its frame | MEDIUM | Inferred | 2 |
| N10 | Unprotected `GetTitle` | MEDIUM | Inferred | 3 |
| N11 | Default key F4 collides with DarkRP | MEDIUM | Proven | 3 |
| N12 | Direct-child swap blanks the tab | MEDIUM | Proven | 3 |
| C1 | `moved` / `byPanel` never pruned | LOW | Proven | 1 |
| C2 | Teardown order | LOW | Proven | 1 |
| C3 | `Match` with `w` but no `h` | LOW | Proven | 1 |
| C4 | Import with live embeds | LOW | Proven | 1 |
| C5 | Imported class recipes not gated | LOW | Proven | 1 |
| C6 | Weak-match question repeats | LOW | Proven | 1 |
| C7 | Alpha captured mid-fade | LOW | Proven (MQS) | 1, 3 |
| C8 | Shell position not synced | LOW | Proven | 1 |
| C9 | Addon derma classes treated as stock | LOW | Proven | 1 |
| C10 | 0.25 s of orphaned children | LOW | Proven / Runtime | 1 |
| C11 | Hide keeps the shell ghosted | LOW | Proven | 1 |
| C12 | `needsKeyboard` may gate the cursor key | LOW | Runtime | 1 |
| C13 | `unfilter` re-shows owner-hidden rows | LOW | Plausible | 1 |
| N6 | Title change breaks matching | LOW | Proven | 2 |
| N7 | Size sync is one-way | LOW | Proven | 2 |
| N13 | Same-file opener missed | LOW | Proven | 3 |
| N14 | Custom menus not transient | LOW | Proven | 3 |
| N15 | Owner saves our geometry | LOW | Proven | 3 |
| N17 | Tool pages refreshed by name leave pinned copies stale | LOW | Proven | 4 |
| N18 | Full-screen scenes offered as windows | LOW | Proven | 4 |

---

## 16. Consolidated patch plan

Small, independently verifiable changes. Ordered by priority.

### P0 — must fix

| # | File / function | Problem | Change | Possible regression | Static check |
|---|---|---|---|---|---|
| 1 | `recipes.lua` `Suggest` | B1 | Suggest `class` only when `#info.commands == 0` | Self-contained class windows from addons that also have commands start as `watch` | PAC: commands non-empty → `watch` |
| 2 | `recipes.lua` CatalogChanged hook | B2, N5, N9 | At join, `Catch()` only. Run no opener | Pins no longer reappear by themselves; the player opens them | The hook contains no `Recipes.Open` call |
| 3 | `embed.lua` `check`, `Release` | B3 | Placeholder and current-parent checks, for parts and for adopted children | A panel the owner briefly reparents is released | Walk ULX `processModules`, PAC `Populate`, Cloudbox `Think` |
| 4 | `openers.lua` `Commands`, `Best` | N8, N13 | Folder-only commands never auto-qualify; a unique non-risky same-file command wins; opener words match as substrings | Fewer auto-suggestions | Wire E2 → nil; LVS → `lvs_openmenu`; Selector → unchanged |
| 5 | `openers.lua` `OpenDesktop`, `DesktopId`; `recipes.lua` `Signature` | N5, N9 | Detect launcher widgets and return the window they opened; set `desktop` only for frames we created | A widget that opens two windows returns none | LVS, LFS, Glide, MQS, Selector each yield their real frame; Wire's yields ours |
| 6 | `recipes.lua` `SourceFile`, `Signature`, `Match`; `storage.lua` `sanitizeAdopt` | N2 | Add `src2`; require equality when saved | Windows whose second file varies stop matching | libNyx showcase → `libnyx_maindemo.lua`; old saves still match |
| 7 | `recipes.lua` `Catch`, `Open` | N3, C7 | Settle rule on size and alpha across two ticks; no synchronous catch | Windows appear in their tab up to 1 s later | libNyx and MQS: first tick skipped |

Added by pass 4:

| # | File / function | Problem | Change | Possible regression | Static check |
|---|---|---|---|---|---|
| 27 | `desktop.lua` or `sources.lua`, new `InitPostEntity` hook | N16 | If no catalogue has been built, call `Sources.Rebuild()` | In sandbox the spawn menu rebuilds it again shortly after; the first-catalogue logic must still run once | TTT2: hook fires → `Desktop.ready` true → picked window gets a control |
| 28 | `recipes.lua` `Refusal` | N18 | Refuse a root covering the whole screen with its own non-stock `Paint` | A genuinely maximised window with a custom paint is refused | Helix menu, `ArcCW.InvHUD` refused; PAC editor (240 wide) not |

### P1 — should fix

| # | File / function | Problem | Change | Possible regression | Static check |
|---|---|---|---|---|---|
| 8 | `embed.lua` | B4, N12 | Per-frame re-ghost and `ChildCount` check while embeds are live | One more frame hook | No allocation in the loop |
| 9 | `input.lua` `think`; `embed.lua` `check` | B5 | Re-assert the clicker; enter cursor mode on an owner's re-show | Fights an addon that wants the cursor off | Only runs while `clickerOn` |
| 10 | `window.lua` `AutoSize` | B6 | Return for `tab.adopt` | None | Both callers reach the guard |
| 11 | `recipes.lua` `Attach` | N4 | Add `panel:IsPopup()` | A non-popup window the player opened will not enter cursor mode | gPhone at join → no cursor mode |
| 12 | `recipes.lua` `titleOf`; `openers.lua` `DesktopId` | N10 | `pcall` around `GetTitle` | None | Wire editor → nil, no error |
| 13 | `actions.lua` cursor key default | N11 | Skip the default when it collides with a gamemode bind | DarkRP players must bind a key | `gm_showspare2` outside sandbox → unbound |
| 14 | `desktop.lua` `Teardown` | C2 | `Embed.ReleaseAll()` before removing windows | None | `Reconcile` sees existing windows |
| 15 | `storage.lua` `sanitizeAdopt` | C3 | Drop `w`/`h` unless both present | None | `sig.w` implies `sig.h` |
| 16 | `layout.lua` `Replace`; `storage.lua` `Import` | C4, C5 | Release embeds before load; imported `class` → `watch` | Imported pins need re-teaching | No live source survives `Replace` |
| 17 | `tabs.lua` `HOST:Think`; `sources.lua` `buildCreation` | N1 | Rebuild on invalid content (capped); warn when a builder replaces commands | A self-destructing builder retries a few times | Cloudbox reload → host rebuilds |

### P2 — improvement

| # | File / function | Problem | Change | Possible regression | Static check |
|---|---|---|---|---|---|
| 18 | `embed.lua` `check` | C1, C8 | Prune invalid `moved` entries; sync the shell's position to the box | An owner may clamp it back (PAC does) | `moved` holds only valid panels after a tick |
| 19 | `recipes.lua` `Catch`, `Wake`; `openers.lua` | §11 | Keep `checked` across `Wake`; cache `fileOf` and `Commands`; skip the HUD scan for desktop signatures | A window that changes identity while open is not re-signed | No `Signature` call on an already-checked panel |
| 20 | `recipes.lua` `Match`, `ask` | N6, C6 | Same source, different title → weak; remember a "No" per (tab, panel) | One extra prompt after an addon update | Selector after a version bump → asks once |
| 21 | `recipes.lua` `TRANSIENT`; `nav.lua` `options` | N14 | Use `m_bIsMenuComponent` | None | `MSD.DMenu` refused |
| 22 | `recipes.lua` `isStockClass` | C9 | Build the stock list from classes whose functions live under `lua/vgui/` or `lua/derma/` | Classes change from dropped to kept; old saves with no class still match | `xlib_Panel`, `F4MenuFrame` kept |

### P3 — optional

| # | Item |
|---|---|
| 23 | `BOX:Paint` passes the shell's `Paint` through (§9.4). Needs the in-game origin check |
| 24 | C11: release the embed when its window is hidden for the session |
| 25 | C13: remember prior visibility in `hideRow` and restore only that |
| 26 | Document: PAC properties collapse, N7, N15, exit button and zoom frame staying outside |
| 29 | N17: rebuild a pinned tool tab when the spawn menu's own panel for that tool changes its child count; otherwise document it |
| 30 | Robust Embed (§8.11): owner's size wins, shell follows the tab, shell paint passthrough, settle rule. Per-frame checks are patch 8 |
| 31 | Wrap (§8.12). Test stacking order in game first |
| 32 | Manage as the last fallback (§8.13); `sanitizeAdopt` accepts `manage` and `wrap` |
| 33 | Probe, health watch and stepping down (§8.14) |

---

## 17. In-game test checklist

Each item settles something marked Inferred or Runtime.

| # | Question | Settles |
|---|---|---|
| 1 | Does a ghosted popup (mouse off, alpha 0) let clicks through to what is behind it? | The whole embed design |
| 2 | Does resizing a `FILL`-docked child from outside re-invalidate its new parent's layout? | Part mode on PAC's divider |
| 3 | Is the cursor still visible after another addon calls `EnableScreenClicker(false)` while a Pinned Panels window is interactive? | B5 impact |
| 4 | How long is the PAC `GainFocus` flash, and the MQS re-show flash? | B4 priority |
| 5 | Is `IsValid` still true on a panel in the frame `Remove()` was called? | N5 |
| 6 | Does calling `GetText` on a removed panel throw? | N10 |
| 7 | Does calling a shell's `Paint` from our box draw at the right origin? | Patch 23 |
| 8 | After a click on an embedded panel with `needsKeyboard`, does the cursor key still work? | C12 |
| 9 | Do orphaned PAC children error during the 0.25 s after the editor is closed? | C10 |
| 10 | How long does the first `Catch` tick take after a pin, with the spawn menu open? | §11 |
| 11 | In TTT2 or Cinema, does anything Pinned Panels owns ever appear, and does a picked window vanish? | N16 |
| 12 | Does a pinned Advanced Duplicator 2 page update its file list after a save? | N17 |
| 13 | Wrap: can a foreign popup be kept just above our frame when its owner calls `MakePopup` or `MoveToFront`? | §8.12, before building Wrap |
| 14 | Wrap: does hiding an inactive tab's window make XGUI or DarkRP's F4 think it is closed? | §8.12 |
| 15 | Embed: does the owner's size winning feel right with PAC (tab locked to full height)? | §8.11 |

Suggested addon order for testing, shortest path to the most coverage: ULX (whole-window embed, simplest), gPhone (always-present frame), PAC3 (focus toggling, recipes), Wire (keyboard), LVS (widgets, child swap), libNyx (animations, identity).

---

## 18. Ten changes before production

1. **Run no opener at join.** Catch what is open; let the player open the rest (B2, N5, N9).
2. **Stop suggesting `class` when the addon has commands** (B1).
3. **Require real evidence before auto-picking a command**, and accept a unique same-file command (N8, N13).
4. **Handle launcher widgets** by returning the window they actually open (N9).
5. **Add a second identity file** so library-built windows can be told apart (N2).
6. **Catch only settled windows** (N3, C7).
7. **Detect a removed placeholder or a changed parent** (B3).
8. **Make ghosting and child adoption per-frame checks** (B4, N12).
9. **Share the screen clicker**: re-assert it, and enter cursor mode when an owner re-shows its window (B5), without forcing it for non-popup frames (N4).
10. **Gate foreign content out of generic features and harden the edges**: auto-size on adopted tabs (B6), `pcall` around `GetTitle` (N10), `sanitizeAdopt` (C3), release embeds before `Replace` and `Teardown` (C4, C2).

### Added by pass 4

11. **Become ready without the spawn menu** (N16). Until this is fixed, the picker makes windows disappear in any non-sandbox gamemode.
12. **Refuse full-screen scenes** (N18).
13. **Build the hosting ladder** (§8.10–§8.14): make Embed robust first, then test Wrap's stacking order in game, then restore Manage as the last fallback. Items 5–8 above are the per-symptom fixes; the ladder is the general answer to the same problems.
