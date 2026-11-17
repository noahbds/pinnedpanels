# Pinned Panels: code audit

**Scope:** every Lua file under `lua/` (33 files, about 12,700 lines), the 9 localization files, `addon.json` and the README. The audit was done by reading the code. Nothing was run yet.
**Date:** 2026-11-17, at commit `b27c3a5`.
**Note:** `addon.json` ignores `*.md`, so this file is never uploaded to the Workshop.

Each finding has:
- an ID,
- a severity: **High** means data loss or a broken feature; **Medium** means wrong behaviour in a real case, or a measurable cost; **Low** means an edge case, cleanup or polish,
- a status: **Confirmed (read)** means the code path is certain from reading; **Needs game** means it depends on engine or addon behaviour and must be checked in game,
- an in-game check, written as client Lua for the GMod MCP.

> ⚠️ Several checks change the layout. Before testing, back up `garrysmod/data/pinnedpanels/layout.json` and `seen.json`, or test on a throwaway layout.

---

## Summary

| ID | Sev | Area | Finding | Status |
|---|---|---|---|---|
| B1 | High | Layout/Storage | Windows can hold more than 16 tabs, and the extra tabs are silently dropped at the next load | Confirmed (read) |
| B2 | High | Batch | "Group…" with an empty name splits every selected window into one window per tab | Confirmed (read) |
| B3 | Medium | Sources | Active-tool window destroys a "kept" tool page (the FPP fix does not hold there) | Confirmed (read) |
| B4 | Medium | Recipes | `takeIfOnly` overwrites a pin's signature before it knows the attach worked | Confirmed (read) |
| B5 | Medium | Recipes | `present[]` never clears, so a window that was open at a Wake never counts as "opened" again (no cursor, no front, no learning) | Needs game |
| B6 | Medium | Storage | A minimized-from-maximized window loses `restore` on reload and comes back as a full-screen "normal" window | Confirmed (read) |
| B7 | Medium | Undo | The colour dialog makes one undo step per frame while dragging and fills the 50-step history | Confirmed (read) |
| B8 | Low | Openers | Desktop widget launch: a window first seen on the last look is neither taken nor reported | Confirmed (read) |
| B9 | Low | Openers | `Openers.launching` is shared by all widgets being launched at the same time | Confirmed (read) |
| B10 | Low | Actions | Console `pinnedpanels_peek` turns peek on with no way to turn it off | Confirmed (read) |
| B11 | Low | Storage | A failed write clears `dirty` with no retry, and the `MAIN→BAK` rename result is never checked | Confirmed (read) |
| B12 | Low | Storage | `active` index can point to the wrong tab after tabs were dropped by Sanitize | Confirmed (read) |
| B13 | Low | Recipes | Command arguments are split on spaces, so quoted arguments break | Confirmed (read) |
| B14 | Low | Recipes | Auto-open fail counting is skipped if the layout tables were replaced during the grace time (undo or import) | Confirmed (read) |
| B15 | Low | Embed | Colour-probe render target keeps the first resolution's size | Confirmed (read) |
| B16 | Low | Controls | Colours dialog keeps a stale `rec` after undo or redo | Confirmed (read) |
| B17 | Low | Layout | Setters mark the layout changed even when the value is the same, which makes empty undo steps and writes | Confirmed (read) |
| B18 | Low | Layout | Inconsistent minimum sizes (40 / 100 / 150): paste-geometry and copy-size can go below the window's own minimum | Confirmed (read) |
| P1 | Medium | Recipes | `vgui.GetAll()` once a second while any HUD-parented pin is waiting | Needs game (measure) |
| P2 | Medium | Desktop | `Reconcile` runs once per changed window per flush, and each run refreshes every window | Needs game (measure) |
| P3 | Medium | PinButton | Full `Recipes.Signature` (breadth-first walk of up to 200 panels) 10 times a second while hovering a window | Needs game (measure) |
| P4 | Medium | Embed | Shielded parts call `debug.getlocal` plus `HasParent` on every getter call | Needs game (measure) |
| P5 | Low | Layout | Deep copy of the whole document on every flush (undo snapshot) | Confirmed (read) |
| P6 | Low | Seen | `Seen.Scan` rebuilds and deep-copies every entry on every flush | Confirmed (read) |
| P7 | Low | Layout | `Arrange` and hub sorts call `SortKey(Title)` inside the comparator | Confirmed (read) |
| P8 | Low | Theme | `Theme.Fit` builds a string key per call, every frame, for every label | Confirmed (read) |
| P9 | Low | Sources | `buildCreation` copies the whole concommand table twice per build | Confirmed (read) |
| U1 | Medium | Controls | Disabled `PinnedPanelsButton` looks exactly like an enabled one | Confirmed (read) |
| U2 | Medium | Settings | Colour picker popups stay open over the game after the spawn menu closes | Needs game |
| U3 | Medium | Hub/Pinned | Row titles are clipped with no ellipsis behind up to 6 buttons in a narrow spawn menu | Needs game |
| U4 | Low | HUD | Cursor-mode banner overlaps a taskbar docked at the top | Needs game |
| U5 | Low | Palette | Long names run under the right-aligned category label | Needs game |
| U6 | Low | Hub/Layout | Layout preview draws rolled windows at full height and shows "C-menu only" windows; its taskbar does not match the real one | Confirmed (read) |
| U7 | Low | Tabs/Taskbar | Two ellipsis styles: `..` in the tab strip and taskbar, `…` everywhere else | Confirmed (read) |
| U8 | Low | Settings | Groups card "Delete" unpins a whole group with its tabs, without asking | Confirmed (read) |
| U9 | Low | Settings | Enum combo boxes don't follow changes made elsewhere (console, Reset) | Confirmed (read) |
| U10 | Low | Nav | `Nav.EnterPopup` replaces the popup's own `PaintOver` | Confirmed (read) |
| U11 | High | Theme | The addon's 5 fonts don't set `extended = true` and have no Linux fallback, so Polish, Turkish, Russian and Chinese text may not draw (see Part 2, R1) | Confirmed (read), check rendering in game |
| L1–L8 | Low | Legacy | Stale comments, dead state, a debug convar, migration code, and 322 references to deleted spec docs | Confirmed (read) |
| D1–D10 | Low | Duplication | Repeated constants, helpers and comparators | Confirmed (read) |
| O1–O4 | Info | Oversights | Permanent global detours, empty README, version string, wording that is no longer accurate | Confirmed (read) |

Localization: all 9 languages have the same 422 keys, and every `{n}` and `%s`/`%d` placeholder matches English. No missing keys were found. This was checked with a script that compared the keys used in the Lua code with the ones in the `.properties` files.

---

## Bugs

### B1 · High · Windows can hold more than 16 tabs, but only 16 are loaded back
- `storage.lua:21` has `MAX_TABS = 16`, and `sanitizeWindow` (`storage.lua:194-199`) drops every tab after the 16th, adding it to `summary.dropped`.
- `Layout.MoveTab` (`layout.lua:356`) and `Layout.AddControl` have **no tab limit**. Only `Batch.Group` respects it (`actions.lua:744`, `MAX_GROUP_TABS`).
- The window menu's **Group → existing group** (`actions.lua:526 moveAll`), the Pinned page, and plain `MoveTab` calls can all go past 16.
- On the next join, `Storage.Load → readDoc` throws the summary away (`storage.lua:320`). The extra tabs are gone, and the player is not told.

**Fix:** enforce `MAX_TABS` in `Layout.MoveTab`: refuse, or split into a new window. Share the constant with Storage. Also tell the player when `summary.dropped > 0` at load.

**In-game check:**
```lua
local PP=PinnedPanels local L=PP.Layout
local g=L.NewGroup("Audit17") local n=0
for _,e in ipairs(PP.Sources.tools) do if n>=17 then break end
  if not L.Find(e.key) then local id=L.Pin(e.key) L.MoveTab(id,1,g) n=n+1 end end
print("tabs in memory", #L.Get(g).tabs)            -- 17
PP.Storage.Flush()
local _,s=PP.Storage.Sanitize(util.JSONToTable(file.Read("pinnedpanels/layout.json","DATA")))
print("dropped on load", s.dropped)                 -- 1  → bug
```

### B2 · High · "Group…" with an empty name splits every selected window
- The batch menu's "Group…" (`actions.lua:991`) calls `Batch.Group(ids, name)` with whatever `Derma_StringRequest` returns, including `""`.
- `""` is truthy. `nextTarget` then calls `Layout.NewGroup("")`, which returns `nil` (`cleanTitle`), so `target` is `nil`.
- `moveAll(id, nil)` (`actions.lua:529`) then runs `MoveTab(id, 1, nil)`, which is a **split**, again and again until the window is empty.
- Result: every multi-tab window in the selection ends up as one window per tab, single-tab windows get moved, and the selection is cleared. Undo can recover it, but the player does not expect this.

**Fix:** in `Batch.Group`, treat a blank or whitespace title as "no title", or stop when `NewGroup` returns nil. The `group` action's "New group" path is already guarded (`if g then`).

**In-game check:** pick one window with ≥2 tabs (`id`) plus one other window (`id2`):
```lua
local L=PinnedPanels.Layout print("before", #L.Windows())
PinnedPanels.Batch.Group({ "<id>", "<id2>" }, "")
print("after", #L.Windows())   -- more windows than before → bug
```

### B3 · Medium · The active-tool window removes a "kept" tool page
- `Sources.kept` (`sources.lua:204`) keeps tool pages whose builder holds on to its panel (the Falco's Prop Protection case), keyed by **`e.key` = `"tool:<name>"`**.
- `buildActive` reuses `buildTool(tool, …)` for the tool gun's current tool, so the page is stored under `"tool:<name>"`.
- When the tool changes, `HOST:Build` calls `Sources.Unbuild("active:tool", content)` (`sources.lua:347`). That looks up `Sources.kept["active:tool"]`, which never exists, so the page is not detached. `clip:Clear()` then **removes it**, and the tool is left holding a NULL panel: the exact bug `kept` was added to prevent.
- If the same "kept" tool is also pinned on its own, the two windows take turns stealing the one page (`kept:SetParent(parent)`).

**Fix:** have `Unbuild` check every `kept` value (`for k,v in pairs(Sources.kept) if v == content`), or remember the key on the content (`content.ppKeptKey`).

**In-game check:**
```lua
local held
spawnmenu.AddToolMenuOption("Utilities","Audit","audit_hold","Audit Hold","","",function(p) held = held or p p:Help("held") end)
RunConsoleCommand("spawnmenu_reload")
-- next: RunConsoleCommand("gmod_toolmode","audit_hold"); PinnedPanels.Desktop.PinSource("active:tool")
-- wait for it to build, then: RunConsoleCommand("gmod_toolmode","weld")
-- then: print(IsValid(PinnedPanels.Sources.kept["tool:audit_hold"]))  -- false → bug
```

### B4 · Medium · `takeIfOnly` rewrites a pin's signature before knowing the attach worked
`recipes.lua:776-779`:
- `Layout.SetAdopt(... { signature = sig })` runs **before** `Recipes.Attach(...)`.
- `Attach` can still return `false`: in part mode, the path leads to a placeholder or to an already-owned panel (`recipes.lua:715`).
- When it does, the pin keeps the weak candidate's signature, which is the wrong file, title and size, plus an undo step. Every later match is judged against the wrong window.

**Fix:** attach first, and call `SetAdopt` only on success. Or keep the old signature and put it back on failure.

**In-game check:** needs two windows of one addon with different titles, where one part is already pinned. Easier to check by reading than by running. To force the path, pin a part with "watch", then call `Recipes.Catch()` while the matching part's slot holds a placeholder, and compare `tab.adopt.signature.title` before and after.

### B5 · Medium · Needs game · `present[]` never forgets a window
- `Recipes.Wake` marks every top-level panel as `present` when a new pin starts waiting (`recipes.lua:889`). `Recipes.Forget` does the same.
- No code ever clears that mark. The table is weak-keyed, so the mark lasts as long as the panel exists.
- Many addons hide and re-show the same frame (XGUI, most DFrame menus with `SetDeleteOnClose(false)`). For those, `opened = not ours and not present[p]` (`recipes.lua:851`) stays **false** for good.
- Re-opening such a window later never brings the cursor, never brings the window to the front, and **never teaches the pin its command** (`learn` only runs when `opened`).

**Fix:** clear `present[p]` when the panel is seen hidden during a Catch, or when it is caught.

**In-game check (ULX/XGUI or any hide/show addon):**
1. Open the XGUI menu once, close it.
2. Pin it with the picker, choosing "when its addon opens it".
3. Unpin it, then pin it again from the Seen page (it waits).
4. Open it with its bind.

Expected: "learned" notification and the window in front. Bug: no notification, and `recipe.kind` stays `"watch"`.

### B6 · Medium · A window minimized while maximized loses its "maximized" state on reload
- `Storage.Encode` always writes `restore` (`storage.lua:299`).
- `sanitizeWindow` only reads it back when `state == "maximized"` (`storage.lua:228`).
- For `state == "minimized"` with a `restore`, which is how `Layout.Restore` knows to go back to maximized (`layout.lua:540`), the restore rectangle is dropped.
- After a reload, restoring gives a **normal** window that fills the screen, and the maximize button then "maximizes" to the same size.

**Fix:** keep `restore` for `minimized` too.

**In-game check:**
```lua
local L=PinnedPanels.Layout local id=L.Windows()[1].id
L.ToggleMaximize(id) L.Minimize(id) PinnedPanels.Storage.MarkDirty()
-- then run: pinnedpanels_reload
-- then: L.Restore(id) print(L.Get(id).state)   -- "normal" → bug (expected "maximized")
```

### B7 · Medium · The colour dialog fills the undo history
- `Dialogs.Colors` calls `Layout.SetColors` from `DColorMixer.ValueChanged` (`controls.lua:236`), which fires every frame while dragging.
- Each frame with a change is its own undo step (`layout.lua:71`), and the history holds 50.
- About one second of dragging pushes out every earlier step: moves, merges, unpins.
- The Settings colour popups don't touch the layout, so they are fine.

**Fix:** apply the colour live to the window control only, and commit one `SetColors` when the mouse is released. Or merge consecutive `style` changes for the same id into one step.

**In-game check:** make a few moves, open the window's colours, drag the hue for about 2 s, then:
```lua
local L=PinnedPanels.Layout local n=0 while L.Undo() do n=n+1 end print(n) for i=1,n do L.Redo() end
-- n == 50 and the earlier moves can't be reached → bug
```

### B8 · Low · Desktop widget launch: the last look does nothing
In `openers.lua:316-325`, a window first seen on look 14 of 14 goes to the `elseif found` branch, which only sets `Openers.launching`. The timer has no repetitions left, so the window is never taken and the "nothing opened" notice is skipped too.
**Fix:** on the last try, take `found` as it is, or give it one more look.

### B9 · Low · One shared `Openers.launching` for every widget
Two widgets pinned within 2 s of each other share `Openers.launching`, and can steal or reset each other's candidate.
**Fix:** keep it per widget id, for example inside the timer closure.

### B10 · Low · `pinnedpanels_peek` gets stuck on
`Actions.Add` makes a console command that only runs `def.run`. For `peek` that is `Desktop.Peek(true)`, and nothing turns it off. The `+/-pinnedpanels_peek` pair exists, but the plain command is a trap.
**Fix:** make the plain command toggle, or don't register it for actions that have `release`.

### B11 · Low · Failed writes are not retried, and the rename is unchecked
- `Storage.Flush` sets `dirty = false` before the size check (`storage.lua:354-361`). After a "write failed" notice, nothing is written again until the next change.
- `file.Rename(MAIN, BAK)`'s result is ignored. If it fails, `file.Rename(TMP, MAIN)` fails as well, and the fallback `file.Write(MAIN)` overwrites the main file without a backup.
- Quarantined files (`layout_corrupt_<time>.json`) pile up forever.
- `seen.json` is written in place, without the temp-file and backup steps the layout uses.

### B12 · Low · The active tab can point to the wrong tab after Sanitize
`active = int(w.active, 1, #tabs)` is computed after invalid tabs were dropped (`storage.lua:210`). If tab 2 of 4 was dropped and tab 3 was active, tab 4 is now active.

### B13 · Low · Command arguments are split on spaces
`Recipes.Open` runs `string.Explode(" ", r.args)` (`recipes.lua:952`). A traced command run as `foo "two words"` comes back as three arguments, and `Trace` has already stripped the quotes.

### B14 · Low · Auto-open fail counting can be skipped
`rec.tabs[w.index] == w.tab` (`recipes.lua:1005`) compares by identity. An undo, redo, import or reload during the 6 s grace replaces the tables, so that join's failure is never counted.

### B15 · Low · The probe render target keeps its first size
`GetRenderTarget("PinnedPanelsProbe", ScrW(), ScrH())` (`embed.lua:276`) is created once. After switching to a larger resolution, sample points past the old size read outside the target.

### B16 · Low · Stale record in the Colours dialog
`Dialogs.Colors` keeps `rec`, and `set()` reads `rec.colors` (`controls.lua:210-215`). After an undo or redo, `rec` is an old copy, so changing one colour brings back the other two from that old copy.

### B17 · Low · Setters that change nothing still count as changes
`SetShowWith`, `SetOpacity`, `SetColors`, `SetAccent` and `SetAdopt` always call `changed()`. `Batch.CopyLook` on windows that already match makes an undo step and writes the file for nothing.

### B18 · Low · Three different minimum sizes
- `Layout.MIN_SIZE = 40`
- `window.lua MIN_W/MIN_H = 150/100`
- `Storage` minimum = 20

Paste geometry, Copy size and Seen re-pin all go through `SetGeometry`, which allows 40×40. That is smaller than the window's own resize minimum.

---

## Performance

All of these need numbers from the game. Snippets are given.

### P1 · Medium · `vgui.GetAll()` once a second while a HUD-parented pin waits
- `Recipes.Catch` runs every 0.5 s for as long as **anything** waits.
- When any waiting pin has `signature.hud` (it was parented to the HUD), every second tick calls `Recipes.TopLevels() → Recipes.HudPanels() → vgui.GetAll()` (`recipes.lua:809`). That is every panel in the game.
- A pin for an addon that is not installed waits forever, so this runs for the whole session.

```lua
local t=SysTime() for i=1,10 do vgui.GetAll() end print(#vgui.GetAll(),"panels",(SysTime()-t)*100,"ms per call")
local t=SysTime() PinnedPanels.Recipes.TopLevels() print("TopLevels",(SysTime()-t)*1000,"ms")
```
**Fix:** look up the HUD root once (`GetHUDPanel():GetChildren()`) instead of `vgui.GetAll()`, and back off for pins whose addon is not loaded (`signature.addon` not mounted).

### P2 · Medium · Repeated `Desktop.Reconcile` calls
- The `PinnedPanelsChanged` hook calls `Reconcile()` for **every** `windows`/`tabs` event (`desktop.lua:110`).
- `FlushChanges` sends one event per (kind, id). Grouping 20 windows sends about 40 events, so about 40 Reconciles, and each one calls `Refresh()` on **every** window (titles, tab strip layout with text measuring, hosts) plus `UpdateStates` plus `UpdateTaskbar` (a full rebuild).
- `PinnedPanelsFlushed` already exists for once-per-frame work, and the states use it.

```lua
local t=SysTime() PinnedPanels.Desktop.Reconcile() print("Reconcile",(SysTime()-t)*1000,"ms with",table.Count(PinnedPanels.Desktop.panels),"windows")
```
**Fix:** set `Desktop.reconcileStale = true` in the hook, and reconcile once in `PinnedPanelsFlushed`.

### P3 · Medium · PinButton signs the hovered window 10 times a second
- `targetUnder` calls `Recipes.Signature(root)` on every look (`pinbutton.lua:111`), which is 10 Hz whenever a cursor shows over a foreign window.
- `Signature` runs `SourceFile`, a breadth-first walk of up to 200 panels that reads each panel's table, plus `DesktopId`.
- The result only changes when the window changes.

```lua
local p=vgui.GetHoveredPanel() -- hover a big addon window first (e.g. run from a bind)
local t=SysTime() for i=1,100 do PinnedPanels.Recipes.Signature(p) end print((SysTime()-t)*10,"ms per Signature")
```
**Fix:** cache per root, using a weak table invalidated when `ChildCount` changes, or skip the call while the root is unchanged.

### P4 · Medium · Getters on pinned parts are slower
- `shield()` (`embed.lua:373-385`) wraps 11 getters on a pinned part, including `GetWide`, `GetTall`, `GetSize` and `IsVisible`.
- Every call then runs `debug.getlocal(2,1)` and up to two `HasParent` walks.
- Layout code calls these many times per frame, and a pinned spawn-menu part has hundreds of descendants that call into it.

```lua
-- after pinning a part (e.g. the spawn menu's tool menu): local part = <its panel>
local META=FindMetaTable("Panel") local n=1e5
local t=SysTime() for i=1,n do part:GetWide() end local a=SysTime()-t
t=SysTime() for i=1,n do META.GetWide(part) end local b=SysTime()-t
print("shielded",a*1e6/n,"µs  raw",b*1e6/n,"µs")
```

### P5–P9 · Low
- **P5** `Layout.FlushChanges` deep-copies the whole document on every flush (`layout.lua:55`), adopt signatures and controls included. Only the first change of a step needs `stable`. A copy-on-write or lazy snapshot would avoid most of these copies.
- **P6** `Seen.Scan` runs on every flush and calls `table.Copy` on every adopt record and control list (`seen.lua:39-50`), even when nothing changed.
- **P7** `Layout.Arrange` (`layout.lua:719`), `hub_pinned` (`:294`) and `Nav.Windows` call `SortKey(Title())` inside the sort comparator (O(n log n) gsubs). `Batch.byTitle` already shows the right pattern (precompute the keys).
- **P8** `Theme.Fit` builds `font.."\1"..room.."\1"..text` per call, every frame, for every label (window titles, Seen rows, picker). The 600-entry flush also throws the whole cache away at once.
- **P9** `buildCreation` copies the whole `concommand.GetTable()` before and after every content-tab build (`sources.lua:313-321`).

---

## UI / UX

- **U1 · Medium:** `PinnedPanelsButton:Paint` ignores `IsEnabled()`. Disabled buttons look clickable: Import's "confirm" before preview, Seen "Pin" for an unavailable tool, the Pinned page's ↑/↓ at the ends of a list. *Check:* open Settings → Data → Import and compare the confirm button with the preview button. **Fix:** dim the background and text when disabled.
- **U2 · Medium · Needs game:** Settings colour swatches open a `DFrame` popup (`hub_settings.lua:164`). Its only close paths are re-clicking the swatch, `ShowPage` and `OnRemove`. Closing the spawn menu leaves it floating over the game with a cursor. *Check:* Settings → Appearance → click a swatch → release Q.
- **U3 · Medium · Needs game:** Pinned page rows dock up to 6 buttons on the right (about 420 px) plus the kind label, and the title `DLabel` takes what is left with no ellipsis. Titles also include `· addon · status`. On a small spawn menu (1366×768, or `spawnmenu_border` high) titles are cut mid-word or vanish. *Check:* resize to 1280×720, open the Pinned tab with a group and an embedded pin.
- **U4 · Low · Needs game:** the cursor-mode banner is drawn at y=6 (`hud.lua:6`), so it sits on top of a taskbar docked at the top.
- **U5 · Low · Needs game:** palette rows draw `e.text` without fitting it, so long tool or window names run under the right-aligned category word.
- **U6 · Low:** the Layout page draws rolled windows at full `rec.h` and includes windows hidden until the C menu opens. Its taskbar is always a full-edge strip, while the real bar is centred and only as long as its entries.
- **U7 · Low:** the tab strip and taskbar cut labels with `..` (`tabs.lua:71`, `taskbar.lua:158`), but `Theme.Fit` uses `…` everywhere else. `Theme.Fit` could be used for both.
- **U8 · Low:** Settings → Groups "Delete" calls `Layout.Unpin` on a group *with its tabs*, without asking (`hub_settings.lua:365`). "Reopen closed" can bring it back, but the label says it deletes the group, and nothing says the tabs go too.
- **U9 · Low:** Settings enum combos are filled once. A `Reset` from another card or a console change leaves them showing the old value.
- **U10 · Low:** `Nav.EnterPopup` sets `panel.PaintOver = Nav.PaintPopup` and never puts the old one back.
- **Polish:** the taskbar right-click on a "hidden" or "waiting" entry opens the full window menu for a window that has no control. Middle-click does nothing for those two states.

---

## Legacy and dead code

- **L1:** `taskbar.lua:307` checks `e.state == "closed"`, a state `stateOf` never returns.
- **L2:** stale comments that point to plans which are finished or deleted:
  - `desktop.lua:46` "the Phase 0 spike decides whether this matters"
  - `actions.lua:709` `"perf" arrives with Phase 12`
- **L3:** `pinnedpanels_debug_shellpaint` (`embed.lua:58`) is an "experimental", "off until tried in game" convar. It can now be decided on: test it, then remove it or make it default.
- **L4:** `nav.lua:617` `hook.Remove("PinnedPanelsFlushed", "PinnedPanels.Nav")` cleans up a hook from an older load. It only matters across a `pinnedpanels_reload` from that version, and can go.
- **L5:** migration code for old layouts: `"manage"` → `"embed"` (`storage.lua:27,112`), `desktop:<id>` tabs → embedded (`storage.lua:151-167`), and the old path format without `n` (`recipes.lua:716`). Keep it while old layouts may exist, but put a date on it so it can be removed later.
- **L6:** `taskbar.lua:321` "show" calls `Desktop.Show(id)` and then `Desktop.RestoreAndFront(id)`, which calls `Show` again.
- **L7:** **322 references** such as `(§33.6, G45, R15, X60, D41, Z7)` across the Lua code point to `PINNEDPANELS_PLAN.md`, `STATIC_REVIEW.md` and the V2 rewrite plan. Those were deleted in `2a65396`. They are now noise that new readers can't look up. Either strip them, or bring back a short `docs/DECISIONS.md` index for the ones still worth keeping.
- **L8:** comments that describe removed features ("There was a Record mode…", "There used to be a Hide action…", "There was a third mode, manage…"). They belong in git history, not in the source.

---

## Duplicated code

| ID | What | Where |
|---|---|---|
| D1 | DFrame chrome list `CHROME = { btnClose, … }` and "skip chrome children" loops | `embed.lua:16,493,516`, `openers.lua:15,237` |
| D2 | "panel just below a root" walk | `embed.lua:310 windowOf`, `pinbutton.lua:81 topOf` (identical) |
| D3 | "is this ours" check | `input.lua:113 ourPanel`, `recipes.lua:225 ours` (one walks parents, the other doesn't) |
| D4 | UTF-8-safe title truncation | `storage.lua:55 text`, `layout.lua:219 cleanTitle`, `theme.lua:93 chop` |
| D5 | Limits defined twice | `MAX_TITLE` ×3 (`layout`, `recipes`, `storage`), `MAX_CONTROLS` ×2, `MAX_CHOICES` ×2 (`storage`, `quick`), `MAX_TABS`/`MAX_GROUP_TABS` (see B1) |
| D6 | Window minimum sizes and `snapping()` | `window.lua:12,166`, `hub_layout.lua:10,28` |
| D7 | Default sizes 280×400 | `layout.lua:9`, `sources.lua:22`, `storage.lua:211` |
| D8 | "sort windows by `SortKey(Title)` then id" comparator | `layout.lua:719`, `actions.lua:774`, `nav.lua:76`, `hub_pinned.lua:294`, `taskbar.lua:90` |
| D9 | `#phrase` lookup | `sources.lua:25 phrase`, `recipes.lua:167 phrase`, `quick.lua:88 name`, `recipes.lua:409` inline |
| D10 | "is this a scroll panel's canvas" pcall | `recipes.lua:425` and `recipes.lua:604` |

Smaller repeats: `tabs.lua` label chopping repeated in `taskbar.lua`; the `Color(c.r,c.g,c.b,c.a)` copy helper in `actions.lua:945` and inline elsewhere; and the "lowest child bottom" layout loops in `tabs.lua:319` and `hub_settings.lua:26`.

Proposed home: a `PP.Util.Limits` table, plus `Util.TopOf`, `Util.IsOurs`, `Util.Truncate`, `Util.ByTitle(ids|recs)`, `Util.Phrase` and `Util.CHROME`.

---

## Oversights and risks

- **O1 · Global detours:** the header comment on `Util.WithOverride` says it is "The addon's only way to replace a field of a global table (R5)". That is no longer true. These five are replaced **permanently**:
  - `gui.EnableScreenClicker` (`input.lua:34`)
  - `RegisterDermaMenuForClose` (`desktop.lua:176`)
  - `vgui.Create`, `vgui.CreateFromTable` and `concommand.Run` (`trace.lua:70-105`)

  Each one is guarded against double-wrapping across reloads. But a `pinnedpanels_reload` **overwrites** any wrapper another addon put on `gui.EnableScreenClicker` after us (`input.lua` reassigns it directly, unlike `trace.lua`'s `install`). Worth documenting in the Workshop description, and worth moving `input.lua` to the same `install` helper.
- **O2:** the README is one line (`Pinned Panel`, and the name is wrong). There is nothing on the console commands (`pinnedpanels_pin/list/debug/reload`, `+pinnedpanels_peek`), the data files, or the convars.
- **O3:** `PP.VERSION = "2.0"` is hard-coded, and nothing writes it to the layout file or a changelog. `addon.json` has no `description`.
- **O4:** reload edge: `Input.binds` survive `pinnedpanels_reload`, so navigation keys bound in the old state keep calling the old file's local functions until navigation changes state.

---

## Suggested in-game test order (MCP)

1. **Perf numbers first, which change nothing:** P1, P2, P3, then P4 after pinning a part.
2. **B6, B7, B10:** quick, and can be undone.
3. **B2:** use a throwaway layout.
4. **B1:** use a throwaway layout. It adds 17 tools.
5. **B3:** needs a test tool option and a `spawnmenu_reload`.
6. **U1–U5:** screenshots at 1280×720 with the spawn menu open.
7. **B5:** needs ULX/XGUI or a similar hide/show addon.

When a check is done, mark it in the summary table with **✔ reproduced**, **✘ not reproduced** or **? inconclusive**, plus the numbers.

---

# Part 2: Better methods and reducing hardcoding

This part comes from web research (2026-11-17) on the GMod wiki, GitHub and the GMod Lua source on this machine (`garrysmod/lua/`). Each item says which source it comes from. "Keep" means a better-looking option was checked and turned down, with the reason.

## What is hardcoded now

Counts from `lua/pinnedpanels/` (grep, 2026-11-17):

| What | Count | Where it lives |
|---|---|---|
| `Color(r,g,b)` literals | 114 | 75 in `theme.lua` and `settings.lua`. The other 39 are spread over 12 files, mostly `hub_layout.lua` (16) and `layout.lua` (8). |
| `"icon16/…png"` paths | 132 | Inline in every vgui file and in `actions.lua` |
| Numeric `local UPPER = n` constants | about 90 | 20 files. Several have the same value under different names (see D5–D7). |
| Panel class-name lists (`X = true`) | 139 entries | `recipes.lua` (WHOLE/PIECE/CLICK/SHOWN/WEB/TRANSIENT), `nav_controls.lua`, `input.lua`, `openers.lua` |
| Source prefix parsing (`src:match("^(%a+):")`, `"adopt:"`, `"quick:"`…) | 45 | About 15 files |
| Window state strings (`"minimized"`, `"maximized"`, `"rolled"`, `"normal"`) | 63 | Everywhere |
| `notification.AddLegacy(…, NOTIFY_*, <seconds>)` | 19 | Durations 5, 6, 8 and 10 picked by hand at each call |
| Engine and Derma internals (`m_strConVar`, `btnClose`, `g_SpawnMenu.CreateMenu`, `.Items`…) | 40 | Spread out, so a GMod update can break them in many places at once |
| Fixed pixel sizes (header 24, rows 32/36/40/44, palette 580×470, cards 300–520…) | most of the constants above | Nothing scales with resolution |

## R1 · Fonts: `extended`, Linux, and scaling (do this first)

- **The facts.** [FontData](https://wiki.facepunch.com/gmod/Structures/FontData) says `extended` defaults to `false` and *"Allow[s] the font to display glyphs that are outside of the Latin-1 range"*. The same page says it has no effect on Linux.
- **What GMod itself does.** Its own `lua/derma/init.lua` (read on this machine) creates `DermaDefault`, `DermaDefaultBold` and `DermaLarge` with `extended = true`. On Linux it switches to `"DejaVu Sans"`.
- **What the addon does.** `theme.lua:215-221` creates `PinnedPanels.Banner`, `.Taskbar`, `.PaletteItem`, `.PaletteSub` and `.PaletteQuery` with neither.
- **Why that matters.** Polish (ł ś ż ć ń ę ą), Turkish (ğ ş ı İ), Russian and Chinese all need glyphs outside Latin-1. Those 4 of the 9 shipped languages risk drawing wrong in the taskbar, the palette and the cursor banner.
- **Fix:** keep the fonts in one table and create them with `extended = true`. Pick a Linux face the way `derma/init.lua` does (`system.IsLinux()`). Make each size `math.Round(base * Theme.scale)`.
- **Check in game:**
  ```lua
  for _,f in ipairs{"DermaDefault","PinnedPanels.Taskbar","PinnedPanels.PaletteItem"} do surface.SetFont(f) print(f, surface.GetTextSize("Привет łğ 你好")) end
  -- then gmod_language ru / zh-CN, open the palette and look at the taskbar
  ```

## R2 · Scale the UI with the screen

- **Today:** every size is in fixed pixels, so the windows, taskbar, palette and picker cards are half as big on a 4K screen as on 1080p.
- **The GMod tools.** [ScreenScale](https://wiki.facepunch.com/gmod/Global.ScreenScale) and [ScreenScaleH](https://wiki.facepunch.com/gmod/Global.ScreenScaleH) scale a number from a 640×480 base. The wiki notes ScreenScale ignores aspect ratio, so ScreenScaleH is the safer one for UI heights. [GM:OnScreenSizeChanged](https://wiki.facepunch.com/gmod/GM:OnScreenSizeChanged) gets both old and new sizes (the new ones were added 2023-10-24). The addon already hooks it for the layout.
- **Proposal:**
  - One `Theme.scale`, set from a new setting `uiScale` (`auto` = `ScrH()/1080` clamped to 0.75–2, or a fixed 75–200 %).
  - One helper `Theme.S(px)`, used for every size constant that is drawn.
  - Fonts and cached measurements (`Theme.Fit`'s cache, the taskbar's layout) rebuilt in `OnScreenSizeChanged` and when the setting changes.
  - The wiki says not to create fonts again and again or inside paint hooks. Rebuilding them only on those two events follows that.
  - This removes the reason for most of the numeric constants. They become "design pixels at 1080p" in one table (R4).

## R3 · Engine functions to use instead of hand-written code

| Replace | With | Source | Gain |
|---|---|---|---|
| `Recipes.HudPanels()` → `vgui.GetAll()` (fixes P1) | `GetHUDPanel():GetChildren()` | [GetHUDPanel](https://wiki.facepunch.com/gmod/Global.GetHUDPanel): "the panel that is used as a wrapper for the HUD"; [ParentToHUD](https://wiki.facepunch.com/gmod/Panel:ParentToHUD) parents to it | One child list instead of every Lua panel in the game. **Check in game** that `ParentToHUD` panels are its direct children: `pnl:ParentToHUD() print(pnl:GetParent()==GetHUDPanel())` |
| Parent-walk loops (`desktop.lua inMenu`, `input.lua windowOf`, `recipes.lua ours`, `nav.lua clipOf`, `quick.lua hostOf`) | `p:HasParent(root)`, which is engine-side; `Panel:IsOurChild` is just `child:HasParent(self)` (`includes/extensions/client/panel.lua:489`) | [HasParent](https://wiki.facepunch.com/gmod/Panel:HasParent), [IsOurChild](https://wiki.facepunch.com/gmod/Panel:IsOurChild) | Shorter. `inMenu(p)` becomes `p:HasParent(g_SpawnMenu) or p:HasParent(g_ContextMenu)` |
| B11: unchecked `file.Rename` | Use its return value: it returns `true`/`false`, forces names to lowercase, and only works in `data/` | [file.Rename](https://wiki.facepunch.com/gmod/file.Rename) | A safe fallback when the rename fails |
| Hand-written `GetX/SetX` pairs on our panels (`BUTTON:SetOn/SetDanger`…) | `AccessorFunc(PANEL, "on", "On", FORCE_BOOL)` | [AccessorFunc](https://wiki.facepunch.com/gmod/Global.AccessorFunc) | Less code and the usual Derma style. Low priority. |

**Keep (checked and turned down):**
- **`PlayerButtonDown` instead of polling `input.IsKeyDown` in `Think`.** [The wiki](https://wiki.facepunch.com/gmod/GM:PlayerButtonDown) says *"This will not be called if player has a panel opened with keyboard input enabled"*, and it is predicted, so in single-player it doesn't run on the client. Both would break the hotkeys. Polling with the gate in `input.lua` is the right design.
- **A Derma skin (`derma.DefineSkin` + `SetSkin`) for the windows.** `Panel:GetSkin` falls back to the parent's skin (`panel.lua:378-403`, read locally), so setting a skin on a window would re-skin every tool panel hosted in it. The code comments already say this (G22/R10). A named skin could still drive the hub, the palette, the taskbar and the dialogs, but the token table (R4) gets most of that benefit with less risk.
- **`language.FormatPhrase`.** [The wiki](https://wiki.facepunch.com/gmod/language.FormatPhrase) says it was added 2026-08-14 and may only be on the dev branch. It is also just `string.format` on `GetPhrase`. `PP.L` already does that and also supports `{1}` reordering, so keep `PP.L`.
- **`PANEL:Pre/PostAutoRefresh` for hot reload.** These [only run](https://wiki.facepunch.com/gmod/PANEL:PostAutoRefresh) for controls made with `derma.DefineControl` that set `AllowAutoRefresh`. The addon uses `vgui.Register`, and its own handover in `pinnedpanels_reload` does more than these hooks would.
- **`util.JSONToTable(…, true)` (ignoreLimits) for the layout and seen files.** [The default cap](https://wiki.facepunch.com/gmod/util.JSONToTable) is 15,000 keys, and a 512-window layout can go past that. Keep it for our own files and keep the limits for imports, as the code already does. Add a comment saying why.

## R4 · A plan for cutting the hardcoding

Ordered by payoff. Each step is a separate change you can verify on its own.

1. **`lua/pinnedpanels/config.lua`** (loaded right after `util.lua`). It holds `PP.Config = { limits = {…}, timing = {…}, size = {…} }` with one comment per value.
   - It replaces the about 90 `local UPPER = n` constants and fixes D5/D6/D7 and B1/B18 at their source.
   - `MAX_TABS`, `MAX_TITLE`, `MIN_W` and the rest are each defined **once**.
   - These are internal constants, not settings. Only R2's `uiScale` becomes a new convar, because adding settings for everything else would be configurability nobody asked for (CLAUDE.md).
2. **`PP.Src` helpers** to replace the 45 prefix parsings: `Src.Kind(src)`, `Src.Name(src)`, `Src.Make(kind, name)` and `Src.KINDS`. Also `PP.State = { NORMAL="normal", MINIMIZED=… }` for the 63 state strings.
   - This makes a typo like `"closed"` (L1) a nil index that a linter catches, instead of a silent false.
3. **Theme tokens only.**
   - Move the 39 stray colours (`hub_layout.lua` COLORS/SCREEN_*, the picker and pin-button OUTLINE/FILL, which are duplicated, the probe text colours, `layout.lua` GROUP_ACCENTS) into `theme.lua`.
   - Add `T.Icon.*` names for the 132 icon paths, e.g. `T.ICON.unpin = "icon16/cross.png"`.
   - Derive hover and pressed shades with one helper, e.g. `T.Shade(c, +12)`, instead of storing each variant. The window header already does this by hand (`window.lua:395`).
4. **Class knowledge as data plus a public API.**
   - Move WHOLE/PIECE/CLICK/SHOWN/TRANSIENT/WEB (recipes), SKIP/CONTAINERS/LEAVES (nav), TYPING (input), OPEN_WORDS/RISKY/PLAIN_FILES (openers) and BIND_BUTTONS into `data/classes.lua`.
   - Add `PinnedPanels.SetPanelKind(class, kind)` and `PinnedPanels.SetOpener(classOrFile, recipe)`, so other addons can say how their panels should be treated instead of us guessing for every addon. `PinnedPanelsLoaded` already exists as the time to call them.
5. **One `PP.Notify(level, key, …)`** with a duration per level, in place of the 19 `notification.AddLegacy` calls with hand-picked numbers.
6. **`compat.lua`** for the 40 uses of engine and Derma internals (`g_SpawnMenu.CreateMenu/ToolMenu`, `sheet.Items`, `m_strConVar`, DFrame chrome names, `m_bIsMenuComponent`).
   - When a GMod update renames one, the fix goes in one file, and a startup self-check can print which internal went missing.

## R5 · Tools: linting, tests, CI and publishing

- **Language server and checks.** `.gluarc.json` is `{}` right now. [GLuaLS](https://wiki.facepunch.com/gmod/LuaLanguageServer) reads it for per-diagnostic settings, and [glua_check](https://docs.rs/crate/glua_check/0.1.5) runs the same diagnostics from the command line. Its README has a sample GitHub Actions workflow. Setting the `PinnedPanels` global and the realm would turn many of D1–D10 and L1 into editor warnings.
- **Linter and formatter.** [glualint / GLuaFixer](https://github.com/FPtje/GLuaFixer) is the standard GLua linter. The [CFC style guide](https://github.com/CFC-Servers/cfc_glua_style_guidelines) builds on it and asks for named constants instead of magic numbers, which matches R4. No maintained GitHub Action was found for glualint ([the old one](https://repos.ecosyste.ms/hosts/GitHub/repositories/talemke/action-glua-lint) is abandoned), so CI would download the release binary.
- **Tests.**
  - [GLuaTest](https://github.com/CFC-Servers/GLuaTest) (CFC) runs tests from `lua/tests/<project>/` on a test server, with a reusable GitHub workflow. Its README only talks about server runs, and this addon is client-only.
  - So the practical route is to **pull the pure logic out** (`Geom.*`, `Storage.Sanitize/Encode/Import`, `Nav.Rank`, `Util.Fuzzy/SortKey`, `Layout` operations on a document) so it doesn't touch `ScrW`/`vgui`, and test it with plain LuaJIT and a tiny stub.
  - B1, B2, B6 and B12 are exactly the kind of bug those tests catch.
- **Publishing.** [gmod-workshop/workshop-upload](https://github.com/gmod-workshop/workshop-upload) runs on Linux and supports changelogs and icons. [GSW-action](https://github.com/Earu/GSW-action) needs Windows, and [gmod-upload](https://awesome.ecosyste.ms/projects/github.com%2Fvurv78%2Fgmod-upload) hasn't had a release in two years. Either one would also fix O3, a version string that nothing updates.

## Research notes

**Queries used:**
- surface.CreateFont extended
- ScreenScaleH
- GLuaTest
- glualint GitHub Action
- derma.DefineSkin / Derma_Hook
- PlayerButtonDown vs IsKeyDown
- OnScreenSizeChanged
- Workshop upload actions
- IsOurChild / FocusedHasParent
- GLuaLS `.gluarc.json`
- GetHUDPanel / ParentToHUD
- vgui.GetAll performance
- CFC magic numbers
- string.Interpolate / language.GetPhrase
- Panel cookies
- Prior-art addons for pinning tool panels (none found)

**How much to trust each source:**
- The GMod wiki and the local `garrysmod/lua` source count as primary. The local source was read for `SetSkin`/`GetSkin`, `IsOurChild` and the Derma fonts.
- The GitHub READMEs are primary for what each tool claims to do. Whether each tool is still maintained came from ecosyste.ms listings, which is a weaker source.
- **Gaps:**
  - Whether GLuaTest can run client-realm tests was not confirmed.
  - Whether `ParentToHUD` panels are direct children of `GetHUDPanel()` was not confirmed. Check it in game.
  - No existing Workshop addon that does tool-panel pinning was found to compare against.

---

# Part 3: What popular addons do, and in-game improvements

This part comes from reading source code (2026-11-17) from popular, actively maintained GMod addons on GitHub, fetched with `gh api`, plus the stock Derma code in local `garrysmod/lua`. Stars and last-push dates are from the GitHub API on the same day.

| Repo | ★ | Last push | Files read |
|---|---|---|---|
| [wiremod/wire](https://github.com/wiremod/wire) | 602 | 2026-11-17 | `lua/wire/client/text_editor/wire_expression2_editor.lua` |
| [CapsAdmin/pac3](https://github.com/CapsAdmin/pac3) | 232 | 2026-11-01 | `lua/pac3/editor/client/panels/editor.lua`, `lua/pac3/editor/client/view.lua` |
| [thegrb93/StarfallEx](https://github.com/thegrb93/StarfallEx) | 214 | 2026-11-15 | `lua/starfall/editor/sfframe.lua`, `sfderma.lua` |
| [TeamUlysses/ulx](https://github.com/TeamUlysses/ulx) | 193 | 2026-04-26 | `lua/ulx/modules/cl/xgui_client.lua` |
| [Earu/EasyChat](https://github.com/Earu/EasyChat) | 110 | 2026-10-24 | `lua/easychat/easychat.lua` |
| [TomDotBat/pixel-ui](https://github.com/TomDotBat/pixel-ui) | 65 | 2026-06-29 | `core/cl_scaling.lua`, `core/cl_fonts.lua`, `elements/cl_frame.lua` |
| Facepunch/garrysmod (local copy) | 1327 | n/a | `vgui/dframe.lua`, `includes/extensions/client/panel/{dragdrop,animation}.lua`, `derma/init.lua` |

## What each addon does well, and how it applies here

| Pattern | Seen in | How it applies to Pinned Panels |
|---|---|---|
| **Scaled constants and a font registry.** `PIXEL.Scale(v) = max(v * ScrH()/1080, 1)`. Constants and fonts are registered once by alias, and recomputed or re-created in `OnScreenSizeChanged`. Fonts are shared by `font..size..weight` and always made with `extended = true`. | pixel-ui `cl_scaling.lua:20-48`, `cl_fonts.lua:20-80` | The exact shape for R1/R2: `Theme.S()`, `Theme.RegisterFont(alias, face, size, weight)`, and a `Theme.SetFont(alias)` wrapper. It also gives the U11 fix. |
| **Focus by click, with a fade and a debounce.** `GainFocus` calls `MakePopup` and `AlphaTo(255, 0.1)`. `KillFocus` turns off mouse and keyboard and the screen clicker, then `AlphaTo(0)`. A 0.2 s `allowclick` guard stops a double toggle. | pac3 `editor.lua:450-508` | Our idle-opacity and minimize changes are instant `SetAlpha` jumps (`desktop.lua:74`). A 0.1 s `AlphaTo` makes the change between interactive and idle readable. The debounce idea also fits the cursor-key toggle. |
| **Click outside to close.** A `VGUIMousePressed` hook closes a popup when `not popup:IsOurChild(pnl)`. | pac3 `view.lua:1088-1100` | The palette and the Settings colour popups (U2) never close on an outside click. Use the same 6 lines. |
| **Clicking the world behind an editor.** `GetParent():SetWorldClicker(true)` is set on the world panel while the editor is open, behind a client convar, "so we can update E2's without closing the editor". | wire `wire_expression2_editor.lua:1787-1789`, StarfallEx `sfframe.lua:1096,1453`, [wiki](https://wiki.facepunch.com/gmod/Panel:SetWorldClicker) ("weapon aim follows the cursor") | **The biggest gain in game** (F1 below): in cursor mode, a click on empty screen uses the tool gun on what is under the cursor. You could change a pinned tool's settings and click the prop without toggling. |
| **Remembered divider and window bounds.** `DHorizontalDivider:SetCookieName("sf_editor_divider")`. E2 stores its size and position in convars and **resets a window that is off-screen** when it loads. | StarfallEx `sfframe.lua:868`, wire `:200-224` | We already refit on load. Cookies are a cheap way to remember splitter and filter state inside our hub and tabs. |
| **Type to focus, and focus memory per tab.** Each tab remembers its `FocusOn` text entry and re-focuses it on `OnActiveTabChanged`. A key pressed while no entry has focus is put into it (`OnKeyCodePressed` → `RequestFocus` + append). | EasyChat `easychat.lua:2268-2278, 2902-2916` | Gives F4 (search the focused window) and F5 (each tab gets its focused field back). |
| **A shortcut registry for other addons.** `EasyChat.RegisterCTRLShortcut(key, fn)` refuses Enter, Esc and Tab. | EasyChat `:1828-1846` | The model for the public API in R4 §4 (`PinnedPanels.SetPanelKind`, `SetOpener`), and for refusing keys we must never take. |
| **Configurable binds by key name.** `input.IsButtonDown(input.GetKeyCode(cvar:GetString()))`, so the convar stores `"w"`, not a number. | pac3 `view.lua:281` | Our key convars store numbers (`KEY_*` codes), which are unreadable in the console and in `config.cfg`. Storing names makes `pinnedpanels_key_cursor F6` work. |
| **One long-lived window, shown and hidden with an animation.** `xgui.anchor` is never removed. `show` and `hide` toggle the screen clicker and `animOpen`/`animClose`. | ulx `xgui_client.lua:346-421` | **Supports B5:** a window that was present at a Wake stays present forever, so XGUI never counts as "opened" again. It also confirms the "wait until settled" rule (R20) is needed. XGUI animates. |
| **What not to copy.** E2's `Editor:Think` clamps and calls `SetPos`/`SetSize` every frame, even when nothing moved. | wire `:300-370` | We already only clamp on change (`Layout.Refit`). Keep it that way. |
| **Stock Derma drag and drop.** `Panel:Droppable(name)`, `Panel:Receiver(name, fn(receiver, panels, dropped, menuIndex, x, y))` and `SetDragParent`, used by `DIconLayout`, `DTileLayout`, `DTree_Node` and `DHorizontalScroller`. | local `includes/extensions/client/panel/dragdrop.lua:306-330` | Gives F2 (drag tabs). Using the same system as the spawn menu makes it feel native. |
| **DFrame's own limits.** `m_iMinWidth`/`m_iMinHeight` (`GetMinWidth/GetMinHeight`), `m_bScreenLock`, `m_bSizable`. | local `vgui/dframe.lua:4-14,137-170` | Gives F8: an embedded DFrame says how small it can go. Use that instead of our fixed 150×100. |

## In-game improvements, by priority

Effort: **S** < 1 day, **M** = 1–3 days, **L** = more. Each one says how to build it and how to check it.

### Interactivity

- **F1 · High · M · Click through to the world in cursor mode.**
  - **What:** set `vgui.GetWorldPanel():SetWorldClicker(true)` while `Input.cursorMode` is on, behind a setting that is on by default, as E2 and Starfall do. Turn it off when cursor mode ends and on `ShutDown`.
  - **Why:** clicks on empty screen then go to the world, with weapon aim following the cursor, as in the C menu. The player changes a weld setting in a pinned window and clicks the prop straight away.
  - **Check in game:** turn on cursor mode, equip the tool gun, click a prop with the cursor, and see the tool fire.
  - **Risk:** our windows must still eat their own clicks. They are popups above the world panel, so they should, but check it.
  - **Shared state:** other addons switch the world clicker on and off too. Wire's sound browser turns it on while open and off when done, with the comment "Not allow the breakage of other addons installed" (`wire/lua/wire/client/sound_browser.lua:997,1018`). pac3 forces it off when its editor opens (`pac3/lua/pac3/editor/client/init.lua:159`). So only turn it off if we turned it on, the same ownership rule `Input.Cursor` follows for the screen clicker, and turn it on again when another addon's window closes.
- **F2 · High · M · Drag tabs between windows.**
  - **Today:** merging, splitting and reordering are only in right-click menus.
  - **What:** each tab-strip item becomes `Droppable("PinnedPanels.Tab")` (it is painted, so add a small item panel per tab, or a custom drag start in `STRIP:OnMousePressed` using `dragndrop`). Each window header and strip becomes a `Receiver`:
    - drop on a strip: `Layout.MoveTab(from, i, to, index)` at the drop x;
    - drop on empty screen: split at the cursor.
  - Also let a hub catalog row be dropped on a window, which pins the source as a new tab there.
  - Enforce `MAX_TABS` here (B1).
- **F3 · Medium · S · Snap guides on real windows.** The hub Layout page draws guide lines while dragging (`hub_layout.lua:188`), but dragging the real window shows nothing. Reuse `CANVAS:Guides` to draw them in `DrawOverlay` while `win.drag` is set.
- **F6 · Medium · S · Edge tiling.** Drag a header to a screen edge or corner and a half or quarter of the usable area lights up; release to fill it. A `Geom.Zone(mx, my, Usable())` → rect, reusing `SetGeometry`. It removes much of the need for "Auto-arrange".
- **F7 · Medium · S · Smooth transitions.**
  - Change opacity with `AlphaTo(target, 0.1)` (pac3) instead of jumping.
  - Optionally, `MoveTo`/`SizeTo` a minimizing window toward its taskbar entry.
  - The stock `animation.lua` is enough. Add an "Animations" setting so people can turn it off.
- **F9 · Low · S · Outside clicks and the wheel.**
  - Close the palette and the colour popups on an outside click (the pac3 pattern; this also fixes U2).
  - The mouse wheel over a window header changes that window's idle opacity.

### Keyboard

- **F4 · High · S · "Search in the focused window."** A new bindable action, default Ctrl+F:
  - it shows the focused window's filter bar if hidden (`Layout.SetFilterBar`);
  - it calls `host.filter:RequestFocus()`. The window then takes the keyboard through the existing `OnTextEntryGetFocus` hook.
  - This is EasyChat's "type to focus", fitted to an addon that must not take the keyboard by default.
- **F5 · Medium · S · Focus memory per tab, and Esc to let go.**
  - Remember the last focused text entry per tab (`host.focusOn`) and re-focus it when that tab becomes active from the keyboard (EasyChat `OnActiveTabChanged`).
  - Esc while a text entry in a pinned window has focus: `KillFocus` + `gui.HideGameUI()` next frame. The picker already does this (`picker.lua:98-101`). Today, Esc opens the game menu while you are typing in a pinned window.
- **F10 · Medium · S · Tab switching with the keyboard.** While a pinned window has keyboard focus, Ctrl+Tab and Ctrl+Shift+Tab switch its tabs, and Ctrl+1…9 jump to one (`Layout.Activate`).
- **F11 · Low · S · Readable key convars.**
  - Store key settings as names, read with `input.GetKeyCode(name)` (pac3's `view.lua:281` pattern), so `pinnedpanels_key_cursor "F6"` works from the console and from `config.cfg`.
  - Old numeric values still load, and `decode` accepts both.
- **F12 · Low · S · Hold a quick key to peek.** Holding a window's quick key shows that one window, and releasing hides it (per-window peek). Tapping it still toggles. `Input.SetKey` already has `release`.

### Embedding

- **F8 · High · S · Respect the embedded window's own size limits.**
  - Read `shell:GetMinWidth()/GetMinHeight()` (DFrame `AccessorFunc`s, `dframe.lua:11-12`) and use them, plus our chrome, as the minimum resize size of the pinned window, instead of `MIN_W/MIN_H = 150/100`.
  - If `GetSizable()` is false, offer "lock size" by default.
  - Also add `MIN_W/MIN_H` to `Layout.SetGeometry` (B18).
- **F13 · High · S · Turn on "needs keyboard" automatically.**
  - Today the player must find "Takes the keyboard" for editors that are not DTextEntry. E2's custom text editor and Starfall's Monaco DHTML (`tab_monaco.lua`) don't fire `OnTextEntryGetFocus`, so typing into them does nothing.
  - At take time, set `needsKeyboard` when the subtree has an HTML-family panel (`Nav.IsHTML`), or an addon-made panel with its own `OnKeyCodeTyped`/`OnKeyCodePressed`.
  - **Check in game:** pin the E2 editor and type.
- **F14 · Medium · S · Live title.** For an embedded DFrame, read `shell:GetTitle()` (pcall, as `titleOf` does) at the 4 Hz `Embed.Check`, and show it unless the player renamed the tab. Example: E2 shows the open file's name.
- **F15 · Medium · M · Per-addon embedding profiles.** A data table (R4 §4) keyed by the signature's file or class, with fixes for windows we know:
  - XGUI: "watch the anchor; its own animation runs on show".
  - E2 editor: "needs keyboard; recipe `wire_expression2_editor`".
  - PAC3: "not pinnable; full-screen editor".
  - Starfall: "needs keyboard".

  Other addons can register their own through the public API. This turns case-by-case fixes like `X51`/`X52`/`X54` into data.
- **F16 · Medium · S · Fix B5.** Clear `present[p]` when a caught or checked window is seen hidden. Without this, XGUI never teaches its command or comes to the front when reopened.

### Dynamic sizing

- **F17 · High · M · UI scale** (R1/R2, PIXEL's pattern): `Theme.S()`, a font registry and a `uiScale` setting. It covers windows, the taskbar, the palette, the picker cards and the hub.
- **F18 · Medium · S · "Fit height to content", kept on.**
  - A per-window toggle. While on, `HOST:Think` looks at the content height about every 0.25 s and calls `AutoSize(true)` when it changed by more than the deadband.
  - Tool panels that open categories or rebuild (`E10`) then stay fitted without clicking "Auto-size".
  - It grows down and keeps the top edge, flipping upward near the bottom of the screen.
- **F19 · Medium · S · Remember screen edges when the resolution changes.**
  - Today `Layout.RescaleAll` scales everything in proportion, so a window snapped to the right edge drifts off it at another resolution.
  - Note which screen edges a window touches when it is placed (`setRect` within `snapDistance` of a usable-area edge), and keep those edges on rescale: right stays right, bottom stays bottom.
- **F20 · Low · S · Auto-size limits from the usable area.** `AUTOSIZE_MAX_W/H` = 0.6/0.92 of `ScrW/ScrH` (`window.lua:15`) ignores the taskbar and side docking. Use `Geom.Usable()` and the config.

### More

- **F21 · High · S · "Show only with the tool gun."**
  - Add a third `showWith` value, `"toolgun"`, beside `contextmenu`. The window shows while the active weapon is `gmod_tool`, checked on `PlayerSwitchWeapon` and on a slow 0.5 s look, since there is no client hook for every weapon change.
  - Make it the default for tool and active-tool windows, behind a setting. Pinned tool panels then vanish when you switch to the physgun or a weapon.
- **F22 · Medium · M · Layout profiles per gamemode or server.**
  - Several named layouts in `data/pinnedpanels/profiles/`.
  - Switch automatically on `engine.ActiveGamemode()` (or the server address, read only on the client and never sent anywhere).
  - Export and import already exist, and `Layout.Replace` already does the swap safely.
- **F23 · Low · S · `pinnedpanels_debug perf`,** which the code has promised since "Phase 12": print P1–P4 timings, the panel count and the Catch/Seen/Reconcile counts from the last 10 s. It also replaces the manual snippets in Part 1.

**Suggested order:** F16 (bug) → F1 → F4 → F13 → F8 → F21 → F17 → F2 → F18 → the rest. F1, F4, F13, F8 and F21 are each small, can each be tested on their own, and change how the addon feels in daily play the most.

## Research notes (Part 3)

**Queries used:**
- Wiremod E2 editor keyboard focus
- pac3 SetKeyboardInputEnabled
- PIXEL UI scaling
- Derma dragndrop Droppable/Receiver
- FreSpawnMenu
- Then `gh api repos/<r>` and `gh search code "<api>" --repo <r>` across 14 repos, for:
  - `SetKeyboardInputEnabled`
  - `IsGameUIVisible`
  - `PIXEL.Scale`
  - `ScreenScale`
  - `EnableScreenClicker`
  - `pace.KillFocus`
  - `pace.GainFocus`

**How much to trust it:** all of it is primary source code, read at the HEAD of each repo's default branch on 2026-11-17. The wiki was used for `SetWorldClicker`.

**Gaps:**
- FreSpawnMenu (6★) was looked at but not read.
- No repo was found that does tool-panel pinning, so F2 and F18 have no prior art to compare with.
- Whether `SetWorldClicker` on the world panel still lets our ParentToHUD popups take their own clicks is **untested**. Check F1 before building on it.

## Part 3 addendum: the local repo folder (`/Users/noah/vehicule_addon/`)

I grepped the 29 cloned repos for the APIs behind F1–F23. Usage counts are files per repo.

| API | Used by |
|---|---|
| `SetWorldClicker` | wire (4), pac3 (1), StarfallEx (1) |
| `:Droppable(` / `:Receiver(` | gPhone, helix (inventory), pac3, TTT2, EasyChat |
| fonts with `extended = true` | TTT2 (7), EasyChat (5), DarkRP (5), helix (3), ACF-3 (2), pixel-ui |
| `OnScreenSizeChanged` | pixel-ui, melonlib, libnyx, TTT2, wire, helix, gmod-glide |
| HUD editor (move and resize elements) | TTT2 (34 files), lvs_base (7) |

What it adds:

- **TTT2's HUD editor** (`TTT2/gamemodes/terrortown/gamemode/client/cl_hud_editor.lua:60-174`) is the closest prior art to our window gestures:
  - **Shift while resizing** keeps the aspect ratio. Elements can also lock it for good (`AspectRatioIsLocked`).
  - **Shift while moving** keeps the move on one axis.
  - Each element has its own `GetMinSize()`.
  - When the minimum is hit, the edge being dragged stops and the other side stays put, instead of the whole rect jumping.

  These go into **F3/F6**, for both the real windows and the hub Layout page. Today `window.lua:ResizeTo` has neither modifier.
- **TTT2's global scale** (`TTT2/lua/ttt2/libraries/appearance.lua:64-125`) is the model for the `uiScale` setting in **F17**:
  - one archived convar, defaulting to `math.Round(ScrW()/1920, 1)`, that the player can change;
  - on a resolution change it is multiplied by `new/old` width, so a scale the player chose survives;
  - scale changes are announced to a callback list (`appearance.RegisterCallback`).

  Put together with pixel-ui's font registry, this is the whole design.
- **gPhone and helix drag and drop** (`gPhone/lua/gphone/cl_phone.lua:459-…`, `helix/gamemode/core/derma/cl_inventory.lua:42,288`) show the two ways `Receiver(name, fn(pnl, items, drop, menuIndex, x, y))` is used:
  - while hovering (`drop == false`), draw where the item would land;
  - on release (`drop == true`), commit.

  **F2** needs exactly this. Drop on a strip: insert at the x position (preview the gap while hovering). Drop on a header: merge. Release over nothing: split.

Queries used: local `grep -rli --include='*.lua'` for the APIs in the table, then I read the matching files. No network access was needed.

## Part 3 addendum 2: repos cloned for this audit

Cloned shallow into `/Users/noah/vehicule_addon/` on 2026-11-17:
- `garrysmod` (Facepunch upstream Lua)
- `Falcos-Prop-protection`
- `FreSpawnmenu`
- `gm-mediaplayer` (PurrCoding's maintained fork)
- `wire-extras`
- `improved-stacker`
- `annotations-gmod-glua-ls`, plus its generated output on the `gluals-annotations` branch, cloned as `gmod-annotations`
- `GLuaFixer`
- `GLuaTest`
- `Small-GLua-Things`
- `cfc_glua_style_guidelines`

Each was picked to test one part of this audit.

- **New compatibility risk C1 · Medium:** `OnSpawnMenuOpen`/`OnSpawnMenuClose` can be taken by another addon.
  - FreSpawnmenu's hooks `return false` (`FreSpawnmenu/lua/frespawnmenu/core.lua:1022-1048, 1051-1073`), and `hook.Run` stops at the first hook that returns a value.
  - When its hook runs before ours, `input.lua:294`'s `spawnOpen = true` and `desktop.lua:274`'s `raiseSoon` never run.
  - Windows still turn interactive through the `foreignCursor()` fallback, since FreSpawnmenu's frame is a popup. But they are **not raised over it**, and none of the "parts of the spawn menu" pins (CreateMenu/ToolMenu) can show, because `g_SpawnMenu` is hidden.
  - The same happens with any addon that returns from those hooks.
  - **Fix:** don't rely only on the hooks. Treat "a visible popup that fills the screen" as the spawn menu for raising. Detect `IsValid(FreSpawnMenu)`, or more generally whether `g_SpawnMenu` stays hidden while the spawn menu key is held. Tell the player that spawn-menu parts can't be pinned while a replacement spawn menu is in use.
- **B3 has a real target.** FPP's admin menu keeps its panel in a file-level upvalue (`Falcos-Prop-protection/lua/fpp/client/menu.lua:1,55`: `local AdminPanel` … `AdminPanel = Panel`), and code run later by FPP fills it. The addon's comment (`sources.lua:199-203`) says `AdminPanel = AdminPanel or Panel`. The real code reassigns on every build, but the result is the same: the last panel built is held. Test B3 with FPP's admin settings pinned through the active-tool window, instead of the made-up tool.
- **Tools that call `controlpanel.Get` directly** (and so depend on the `WithControlPanelFallback` path in `sources.lua:149`): `advdupe2`, six `VJ-Base` tools, `wire-extras/wire_modular_panel`, `improved-stacker`. They are good targets for checking that a pinned copy of the page fills in, and that "Rebuild" works (E10).
- **API check against the generated annotations** (160 deprecated functions or methods, from the wiki): Pinned Panels calls **no deprecated function**. The only name that matched was `Player:GetName`, which is a false positive: the code calls `Panel:GetName`.
  - The comments calling `debug.getupvalue` "deprecated" (`openers.lua:96`, and the reasoning behind `sources.lua:208`) are **out of date**. The current annotation has no `@deprecated` on it. Reword them, but keep the `if not debug.getupvalue` guard.
- **F1 can check who owns the world clicker:** `Panel:IsWorldClicker()` exists (`gmod-annotations/panel.lua:1342-1347`). Read `vgui.GetWorldPanel():IsWorldClicker()` before turning it on, and only turn it off if it was off before and we turned it on.
- **Correction to Part 2, R5:** GLuaTest can run client tests. A case with `clientside = true` is sent to clients when its "run clientside" convar is on (`GLuaTest/lua/gluatest/loader.lua:4-15`). The pure-logic split is still worth doing, but client-side GLuaTest cases are now an option for `Layout`, `Storage` and `Nav.Rank`.
