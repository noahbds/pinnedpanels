# Pinned Panels: readability plan

**Goal:** make the code readable by a developer who didn't write it. Names should say what a thing is without the reader first learning the architecture or the spec codes. This is about understanding, not line count:
- Don't lengthen a name that is already clear.
- Don't delete a single-use helper that names a real step.
- Don't inline logic until it turns into one long expression.

**Modelled on:** Rareload's `docs/architecture/READABILITY_AUDIT.md`, as it was at `ba4c92dd^`. It has the same sections, and its rules are adapted here for a client-only Derma addon.

**Scope and method:**
- Every file under `lua/` was read in full for `AUDIT.md`.
- The counts below come from greps run on 2026-11-18 at `b27c3a5`.
- The naming dictionary (§2) and the name collisions (§3) apply to the whole codebase.
- The tables in §4 cite lines where the pattern is clearest. The same pattern repeats in the other files.

**When to apply it:**
1. After the in-game check of `AUDIT.md`,
2. and after its bug fixes, so the line numbers in `AUDIT.md` still match the code while the bugs are fixed.
3. Then this plan, as its own series of commits.

None of it changes behaviour, so most of it can be checked with the linters alone. §8 marks the few steps that need the game.

---

## 1. Summary

Pinned Panels is **well structured for a GMod addon**:
- one `PinnedPanels` namespace,
- one module per concern (`Layout` is the only writer of the document, `Input` the only Think hook, `Storage` the only `file.*` user),
- public functions in `PascalCase`, constants in `SCREAMING_SNAKE`,
- comments that explain *why*.

So this plan is targeted, not a rewrite.

There are **four real problems**, in order of how much they slow a new reader down:

1. **Single letters with several meanings across files** (§3).
   - `w` is a window record in 93 places but a width in 119 (`Paint(w, h)`).
   - `e` is six kinds of entry (133 uses).
   - `s`, `r` and `c` each have three or four meanings.
   - Fixing these first gets most of the benefit.
2. **One verb used for different actions** (§5):
   - `Rebuild` means "rebuild now" in `Sources`, "mark for rebuild" in `HOST`, and "re-lay out" in `BAR`.
   - Seven functions return "the name of something" with no rule for which to call.
   - `Wake`, `Front`, `Show`, `Refresh` and `touch` each mean two things.
3. **Comments that only make sense with documents that no longer exist** (§6): 323 references like `(§33.6, G45, R15, X60)` point to the deleted planning docs, plus "There used to be…" history notes.
4. **Some files and functions doing too much** (§7):
   - `recipes.lua` does five jobs, `actions.lua` three, `embed.lua` three.
   - Nine functions are 60–94 lines long, three of them nested 7 levels deep.
   - 322 lines are over 120 characters.

---

## 2. Naming dictionary (short name → name that says what it is)

Apply these where they make the code clearer. Keep the short form only inside a 1–3 line scope where it is the usual idiom: a `for i = 1, n` counter, `local a, b` in a sort comparator, or `x, y, w, h` in geometry maths.

| Current | Rename to | Where and why |
|---|---|---|
| `w` (window record) | `record` | `for _, w in ipairs(doc.windows)` in `storage.lua`, `layout.lua`, `seen.lua`, `actions.lua` and `hub_settings.lua`. **`w` is kept for width only.** See §3.1. |
| `win` (record) | `record` | `layout.lua` uses `win` for the record (`byId[id]`), while `desktop.lua` uses `win` for the panel. See §3.2. |
| `win` (window control) | `windowPanel` | `Desktop.panels[id]`, `Desktop.PanelOf`, `crop_editor.lua`, `nav.lua`. |
| `rec` | `record` | Already consistent, so the new names line up with it. One word everywhere: `record`. |
| `e` | see §3.3 | Six meanings. |
| `s` | `shell` / `signature` / `slot` | `embed.lua` (`e.shell`), `recipes.lua` (`adopt.signature`), `layout.lua:603` |
| `r` | `recipe` / `rect` / `restoreRect` / `resizeState` | `recipes.lua`, `layout.lua:570,800`, `window.lua:248` |
| `c` | `child` / `control` / `crop` / `color` | `storage.lua:183`, `quick.lua`, `layout.lua:427`, `recipes.lua` loops |
| `t` | `tab` / `panelTable` / `now` | `storage.lua:164` (raw tab), `embed.lua:103`, `recipes.lua:49` (`p:GetTable()`), `trace.lua:77` (`RealTime()`) |
| `a` | `adoptRecord` | `local a = w.tab.adopt` (`recipes.lua:769,829`) |
| `m` | `movedRecord` / `match` / `menu` | `embed.lua:577`, `recipes.lua:849`, `desktop.lua:159` |
| `k` | `kind` | `recipes.lua:347-428` (`kindOf(p)` result) |
| `b` | `bind` / `backdrop` / `button` | `input.lua:93`, `embed.lua:620`, the hub files |
| `it` | `tabItem` | `tabs.lua` STRIP |
| `ph` | `placeholder` | `embed.lua:347,463`. It is the main object of `shield()`; give it its full name. |
| `sig` / `cand` | `signature` / `candidateSignature` | `recipes.lua:826-831`. `sig` is fine where it is the only signature in scope. |
| `cp` | **keep** | `controlPanel` is clearer, but `cp` is what GMod's own tool code calls it. Note it in CONVENTIONS. |
| `p` | `panel` (when it outlives a few lines) | Nearly always means a panel here, so no collision. Lengthen it only in long scopes like `Recipes.Catch`. |
| `out` | name what is built | `candidates`, `commands`, `rects`, `tops`, `lines`, `parts`, `entries`. Never leave it as `out`. |
| `fn` | `callback` / `builder` | When it lives longer than one line (`sources.lua:161`, `input.lua:96`) |
| `ok, err` | **keep** in 2-line `pcall` scopes; `succeeded, errorText` in longer ones | |
| `T`, `PP`, `Util`, `Geom`, `Layout`, … | **keep**, and document them | File-level aliases for `PinnedPanels.*`. Caching them as locals is correct GLua; list them in CONVENTIONS. |

---

## 3. Names with several meanings (fix these first)

### 3.1 `w`: window record or width (the worst one)
- **Record:** 93 uses (`storage.lua:190-233`, `layout.lua:97,174,421,674`, `seen.lua:71`, `actions.lua:697`).
- **Width:** 119 uses (`Paint(w, h)`, `PerformLayout(w, h)`, `Geom.*`, `setRect(win, x, y, w, h)`).
- `layout.lua` mixes both in one function: `place(w, h, …)` takes a width, while `newWindow` builds a record with a `w` *field*.
- **Rename:** `record` for the record. `w`/`h` stay for width and height only. The record's `w`/`h` *fields* stay, because they are saved in the document (§8.1).

### 3.2 `win`: window record or window panel
- In `layout.lua`, `sources.lua:283` and `seen.lua`, `win` is the **record**.
- In `desktop.lua`, `nav.lua`, `crop_editor.lua` and `actions.lua:232`, `win` is the **`PinnedPanelsWindow` panel**.
- `desktop.lua:UpdateStates` has both in one loop (`win` the panel, `rec` the record), which only works because the reader happens to know the convention.
- **Rename:** `record` and `windowPanel`.

### 3.3 `e`: six kinds of entry
| Meaning | Where | Rename to |
|---|---|---|
| Embed entry (`{ mode, target, shell, box, moved … }`) | `embed.lua` throughout, `desktop.lua:196` | `embedEntry` |
| Catalogue entry (`{ kind, key, name, item … }`) | `sources.lua:43-83,217-331`, `actions.lua:968`, `palette.lua:37-46` | `sourceEntry` |
| Seen entry | `seen.lua`, `hub_seen.lua` | `seenEntry` |
| Taskbar item | `taskbar.lua:114-452` | `taskbarItem` |
| Palette item | `palette.lua:51-124` | `paletteItem` |
| Change event | `layout.lua:57-63` | `event` |

`Embed.byPanel[p]` returns an embed entry, while `Sources.catalogue[src]` returns a catalogue entry, and both are called `e`. `sources.lua:300` has `local e2 = PP.Embed.byPanel[page]` beside `local e = Sources.catalogue[key]`. That is exactly the line a new reader stops on.

### 3.4 Words with two meanings
| Word | Meanings | Rename |
|---|---|---|
| `held` | `Desktop.held` = windows held back at join; `input.lua` `held` = keys being held | `Desktop.heldBack` (internal, all uses are in our own code), `keysDown` |
| `closed` | `Layout.closed` = the "recently closed" stack; `e.closed` = the owner hid its window; `BOX:SetClosed` | `Layout.recentlyClosed`, `embedEntry.ownerHidden`, `BOX:SetOwnerHidden` |
| `seen` | the `Seen` module; `embed.lua:401` `seen` (shell → visibility override); the `seen` set in `Sanitize`; `Seen.scanned` | `visibilityOverrides`, `seenSources` |
| `ours` | three functions: `input.lua:113 ourPanel`, `recipes.lua:225 ours` (walks parents), `openers.lua:60 ours(name)` (a command name) | One `Util.IsOurPanel(panel)` (walks parents), plus `isOurCommand(name)` |
| `touch` | `seen.lua:60` marks the file dirty; `nav.lua:210` keeps the focused window opaque | `markDirty`, `keepFocusedOpaque` |
| `stale` | Rects (`desktop.lua`), `Nav.stale`, `statesStale`, the hub pages' `self.stale` | Fine as a word. Name what is out of date: `rectsStale`, `navNeedsRefresh`, `rowsStale`. |

---

## 4. Findings by file

### 4.1 `layout.lua` (the core document; most of the vocabulary starts here)
| Line(s) | Current | Proposed |
|---|---|---|
| 128 | `copy(t)` | `deepCopy(value)` |
| 139 | `quietly(fn, …)` | `withoutUndo(fn, …)`. It suppresses undo steps, not output. |
| 147 | `places()` | `occupiedRects()` |
| 155 | `place(w, h, px, py)` | `findFreeRect(width, height, preferredX, preferredY)` |
| 162/178 | `add(win)` / `remove(win)` | `addWindow(record)` / `removeWindow(record)` |
| 195 | `setRect(win, …)` | `setRecordRect(record, …)`. It returns whether anything changed; say so in its comment. |
| 50, 135 | `local snapshot` … `function snapshot()` | Move the helper above `FlushChanges`, or write `snapshot = function()`. The bare `function snapshot()` reads like a global (§7.3). |
| 69 | `changed(kind, id, noSave)` | `noteChange(kind, id, skipSave)` |

### 4.2 `recipes.lua`
| Line(s) | Current | Proposed |
|---|---|---|
| 22, 102 | `isStock(src)` / `isStockClass` | `isStockFile(sourcePath)` / keep |
| 48 | `ownFile(p, skip)` | `panelSourceFile(panel, skipFile)` |
| 248 | `isScene(p)` | keep (the comment explains it) |
| 346 | `kindOf(p)` | `controlKind(panel)` → `"whole" \| "piece" \| "click" \| "shown" \| false` |
| 380 | `substance(p, depth)` | `hasContent(panel, depth)` |
| 735-761 | `checked`, `settling`, `present`, `known`, `expecting` | `lookedAt`, `lastSize`, `presentAtWake`, `waitingSources`, `openedByUs`. These five tables are the catch state machine; say so in one comment block above them. |
| 768 | `takeIfOnly(w, …)` | `takeIfOnlyCandidate(waitingTab, …)` |
| 788 | `learn(w, panel)` | `learnOpener(waitingTab, panel)` |
| everywhere | `w` (a waiting row `{ rec, index, tab }`) | `waitingTab`. This is a fourth meaning of `w`. |

### 4.3 `embed.lua`
| Line(s) | Current | Proposed |
|---|---|---|
| 102 | `standIn(inner, s)` | `forwardMethodsTo(stand, window)` |
| 144 | `adopt(e, p)` | `moveIntoBox(embedEntry, panel)`. `adopt` is also the record kind. |
| 159/181 | `ghost` / `ghostBackdrop` | `hideShell` / `hideBackdrop` |
| 188 | `watch()` | `startWatching()` |
| 211 | `paintOn(s, w, h, shade, points, ref)` | `samplePaint(shell, width, height, clearShade, points, refPoint)` |
| 235 | `common(black, white, from, to)` | `dominantColour(overBlack, overWhite, firstPoint, lastPoint)` |
| 346 | `shield(e)` | `redirectPlacementToPlaceholder(embedEntry)` |
| 403 | `seenShell(e)` | `overrideShellVisibility(embedEntry)` |
| 679 / 693 / 712 / 774 | `follow`, `ownerSize`, `frame`, `check` | `followTab`, `applyOwnerSize`, `watchFrame`, `checkStillOwned` |

### 4.4 `sources.lua`, `openers.lua`, `trace.lua`
| Line(s) | Current | Proposed |
|---|---|---|
| `sources.lua:161` | `run(src, fn, …)` | `runBuilder(sourceKey, builder, …)` |
| `sources.lua:186` | `notice(parent, text)` | `noticePage(parent, text)` |
| `sources.lua:207` | `holds(fn, panel)` | `builderKeepsPanel(builder, panel)` |
| `sources.lua:276` | `pinOwn(e, commands)` | `pinSpawnMenuPageInstead(sourceEntry, originalCommands)` |
| `openers.lua:222` | `tops()` | `desktopWindowParents()` |
| `openers.lua:231-244` | `local filled` + `function Openers.Filled` + `function filled` | Define `filled` first, then `Openers.Filled = filled`. |
| `trace.lua:33` | `worth(name)` | `isTraceableCommand(name)` |
| `trace.lua:54` | `install(tbl, key, make)` | `installWrapper(...)`. Name it as a detour, and move it to `Util` (§7.2). |

### 4.5 `input.lua`, `desktop.lua`, `nav.lua`
| Line(s) | Current | Proposed |
|---|---|---|
| `input.lua:84` | `gated()` | `hotkeysSuppressed()` |
| `input.lua:91` | `fire(key, pressed)` | `runBindings(key, phase)` |
| `input.lua:102` | `repeats(key)` | `hasRepeatingBinding(key)` |
| `desktop.lua:29` | `wanted(rec)` | `needsWindowPanel(record)` |
| `desktop.lua:183` | `local at = Util.Contains` | Use `Util.Contains`. An alias called `at` reads as a position. |
| `desktop.lua:205` | `coveredAt(x, y)` | `foreignPanelAt(x, y)` |
| `nav.lua:201` | `go(state)` | `setNavState(state)` |
| `nav.lua:560` | `bind(name, …)` | `bindNavKey(name, …)` |

### 4.6 vgui files
| Line(s) | Current | Proposed |
|---|---|---|
| `tabs.lua:438` | `HOST:Rebuild()` | `HOST:MarkForRebuild()`. It only clears `built`; the build happens in `Think`. |
| `taskbar.lua:76` | `BAR:Rebuild()` | `BAR:RefreshEntries()` |
| `taskbar.lua:194` / `recipes.lua:880` | `BAR:Wake()` / `Recipes.Wake()` | `BAR:ShowIfNeeded()` / `Recipes.StartCatching()` |
| `hub_pinned.lua:145`, `hub_settings.lua:68` | `button(...)` (a local function) | `addRowButton`, `addCardButton`. A bare `button` reads like the button itself. |
| `hub_settings.lua:38,60,49` | `card`, `row`, `help` | `addCard`, `addRow`, `addHelpText` |
| `quick.lua:88,94,154` | `name`, `key`, `menu` (local functions) | `phraseOf`, `controlsKey`, `openMenuNextFrame` |
| `controls.lua:137` | `dialog(title, w, h)` | `makeDialog(title, width, height)` |

---

## 5. Function names: one verb, one meaning

- **"The name of something": seven functions with no rule for which to call.** Keep them, and add one comment block in `layout.lua` saying which is for what:
  - `Layout.Title(record)`: the window's header. **Keep.**
  - `Layout.TabTitle(tab)`: a tab's name. **Keep.**
  - `Sources.Title(src)`: a catalogue source's default name. **Keep.**
  - `Recipes.Title(adopt)` → **`Recipes.PinTitle`**: a pin's name from its signature.
  - `Recipes.SigTitle(sig)` → **`Recipes.LiveTitle`**: a live panel's name, used by the picker list.
  - `Recipes.PartName(panel)`: a part under the cursor. **Keep.**
  - `Recipes.ControlName(panel)`: one control. **Keep.**
- **`Describe`:** `Recipes.Describe(adopt)` returns a sentence, while `Quick.Describe(panel)` returns a control descriptor table. Rename the second one `Quick.ReadControl`.
- **`Rebuild`:** see §4.6. `Sources.Rebuild` really rebuilds the catalogue; rename it `Sources.RebuildCatalogue` so it can't be confused with a tab's rebuild.
- **`Refresh`:** `PANEL:Refresh()` re-reads the record, and `Nav.Refresh()` re-checks the navigation state. Rename them `PANEL:ApplyRecord()` and `Nav.Revalidate()`.
- **`Front` / `Show`:**
  - `Desktop.Front` brings a window up and focuses it.
  - `Embed.Front` does the same and keeps it on top for 4 frames → rename it `Embed.KeepInFront`.
  - `Desktop.Show(id)` releases a held window → rename it `Desktop.Unhold(id)`. Not `Release`, which `Embed.Release` already uses.
  - `PinButton.Show` really does show.
- **Leave alone, already clear:** `Layout.Pin/Unpin/MoveTab/Activate/Arrange/Refit`, `Storage.Sanitize/Encode/Import/Export/Flush`, `Geom.FreeSpot/SnapAxis`, `Embed.Attach/Release`, `Recipes.Signature/Match/Suggest/Take/Catch/Open`, `Nav.Rank`.

---

## 6. Comments: keep the *why*, drop the bookkeeping

The comments are the addon's best documentation, so don't reduce them. Two kinds of noise need to go:

1. **323 spec references in 32 files:** `(§33.6)`, `(G45, R15)`, `(X60)`, `(D41)`, `(Z7)`. The documents they point to were deleted in `2a65396`. Rareload's 5.5 commit `ba4c92dd` did exactly this ("plan references out of docs and comments").
   - Remove each code.
   - Where the reference *was* the explanation, put the reason into words. For example, `(G6)` becomes "F1–F12 never reach PlayerBindPress".
   - Keep the engine facts that are worth knowing (the `G*` entries) as plain sentences. Optionally collect them in `docs/ENGINE_NOTES.md`, one line each.
2. **History in the source:** "There used to be a Hide action…", "There was a Record mode…", "There was a third mode, manage…", and "The player used to be told … (Z7)". Move these to the commit message, and leave the comment saying what the code does now.

Also:
- The first sentence of each function's comment should say what it returns or does, in plain words. Most already do. The ones that open with a story instead: `recipes.lua:763-767`, `sources.lua:271-275` and `embed.lua:317-345`.
- Some comments use private shorthand ("the owner, 2026-10-11", "as v1", "the Phase 0 spike"). Replace it with the actual reason.

---

## 7. Structure: size, nesting and placement

### 7.1 Files that do more than one job (split them; behaviour unchanged)
| File | Jobs in it | Split into |
|---|---|---|
| `recipes.lua` (1039 lines) | signing a panel; what can or should be picked; suggestions and `Take`; catching waiting pins; opening and auto-open at join | `signature.lua` (Signature, Match, SourceFile, Addon, the title functions), `pickable.lua` (Refusal, Worth, Pickable, Lineage, kinds), `catch.lua` (Waiting, Catch, Attach, Wake, learn), `open.lua` (CanOpen, Open, Hurry, AutoOpen). `recipes.lua` keeps Suggest, Choices, Take, Describe and Status. |
| `actions.lua` (1054 lines) | action declarations and menus; `PP.Batch` (lines 735–1010); console commands | `actions.lua`, `batch.lua`, `commands.lua` |
| `embed.lua` (856 lines) | the box control and moving panels; method forwarding and shields; colour probe | `embed.lua`, `embed_shield.lua` (standIn, shield, seenShell, placeholder paint), `embed_colours.lua` (probe) |
| `controls.lua` | shared controls; `PP.Dialogs` | `controls.lua`, `dialogs.lua` |

Each new file goes into `FILES` in `autorun/pinnedpanels.lua` at the point its code loads today, so the load order doesn't change.

### 7.2 Code that lives in another module's file
- `PP.Input.clickerHeld` is **defined in `recipes.lua:684`**. Move it to `input.lua` as `Input.SetClickerOwnerCheck(fn)`, which `recipes.lua` (or `catch.lua`) calls.
- `trace.lua:install` and `input.lua`'s direct reassignment of `gui.EnableScreenClicker` are two ways to detour a global. Use one `Util.InstallDetour(tbl, key, make)` for all five detours. This also fixes Audit O1.
- The `RegisterDermaMenuForClose` detour and the open-menus table are in `desktop.lua`, but the pin button and nav read them too. Move them to `input.lua` (as `Input.OpenMenus()`) or to the `compat.lua` from Audit R4.
- `Nav.stale` is set in `nav.lua` and read and cleared in `desktop.lua`. Give it a function: `Nav.MarkStale()` / `Nav.RefreshIfStale()`.

### 7.3 Forward declarations
Nine file-level forward declarations, for example `local snapshot` then `function snapshot()` at `layout.lua:50/135`, and the same for `filled`, `giveKeyboard`, `sheetTabName`, `bindKeys`. Lua allows this, but a reader seeing `function snapshot()` takes it for a global. Prefer, in this order:
1. Move the definition above its first use.
2. Write `name = function(...)`.
3. Keep the forward declaration, and add a comment saying it is a local defined at line N.

### 7.4 Long or deeply nested functions (extract steps that already have names)
| Function | Lines | Nesting | Extract |
|---|---|---|---|
| `hub_pinned.lua:158 PAGE:AddWindowRow` | 94 | | `windowRowTitle(record)`, `addWindowRowButtons(row, record, state)` |
| `embed.lua:567 Embed.Release` | 81 | | `returnMovedPanels(embedEntry)`, `restoreShell(embedEntry, close)` |
| `layout.lua:711 Layout.Arrange` | 79 | | `arrangeInRows(list, area)`, `arrangeInGrid(list, area)`. The comment already names both strategies. |
| `recipes.lua:797 Recipes.Catch` | 78 | **7** | `matchingPins(panel, candidateSignature, waiting, partsOnly)`, `giveToPins(matches, panel, isMenu)` |
| `hub_settings.lua:445 openImport` | 73 | | `previewImport(...)` |
| `controls.lua:196 Dialogs.Colors` | 68 | | `addColourRow(scroll, row, …)` |
| `hub_layout.lua:270 CANVAS:Paint` | 66 | | `paintTaskbarPreview`, `paintBox` |
| `sources.lua:35 Sources.Rebuild` | 66 | | `readTools()`, `readCreationTabs()`, `readNatives()` |
| `tabs.lua:242 filterContent` | | **7** | `filterCategory(row, match)` |
| `seen.lua:69 Seen.Scan` | | **7** | `updateSeenEntry(key, record, tab)` |

### 7.5 Line length
322 lines are over 120 characters (counting a tab as 4 spaces), 51 of them over 160. They are mostly long `if … and … then` lines and the one-line table literals in `sources.lua`, `storage.lua` and `recipes.lua`. Rareload's lint cap is 120. Wrap them at `and`/`or`, and give one-line tables one field per line.

---

## 8. Applying it safely

### 8.1 Never rename across a contract
These are read by other code, by saved files or by the player, so they **keep their names**:
- The `PinnedPanels` global.
- Hook names: `PinnedPanelsLoaded/Changed/Flushed/SettingChanged/CatalogChanged/AdoptChanged/HeldChanged/SeenChanged/InputChanged/CursorMode/SelectionChanged`.
- Registered vgui class names `PinnedPanels*`. `input.lua:114` and `recipes.lua:227` also recognize our panels by that prefix.
- Convar names `pinnedpanels_*`, including the generated `pinnedpanels_key_<action>`.
- Concommand names and action ids.
- Saved document keys: `v, windows, nextId, screen, id, tabs, active, x, y, w, h, state, restore, title, accent, locked, filterBar, opacity, quickKey, showWith, colors, src, size, crop, adopt, mode, signature, recipe, kind, controls, …`.
- Source prefixes `tool: creation: postprocess: active: adopt: quick: desktop:`.
- The `PP2:` export prefix.
- Localization keys.
- Cookie names: `pinnedpanels.<src>.<label>` and `pinnedpanels_cursor_key_chosen`.
- File paths under `data/pinnedpanels/`.
- Panel flags read across files: `ppOurs`, `ppTakesKeyboard`, `ppPlaceholder`, `ppEntry`, `ppDesktop`, `ppQuickIndex`, `ppQuickKey`.

`PP.*` module functions (`Recipes.Title`, `Desktop.Show`, …) are internal. Renaming one is fine, but only together with **every** call site in the same commit (`grep -rn "Recipes.Title"`).

### 8.2 Order
1. **Lint setup first.** Add a `.glualint.json` based on Rareload's:
   - `lint_shadowing: true`, `lint_maxScopeDepth: 7`, `lint_unusedVars: true`, `lint_maxLineLength: 120`;
   - `prettyprint_indentation: "\t"`, because this addon uses tabs, unlike Rareload.

   Fill in `.gluarc.json` too (Audit R5). Note how many warnings it gives today, and only lower that number from then on.
2. **§3 collisions:** `w`/`win`/`e`. One module per commit, in this order: `layout` → `storage` → `seen` → `desktop` → `embed` → `recipes` → `sources` → the vgui files.
3. The rest of the **§2 dictionary** and the **§4 local function names**: file by file, lint after each.
4. **§5 public renames:** one function per commit, with every call site.
5. **§6 comments:** strip the spec codes file by file.
6. **§7.3/7.4:** reorder forward declarations and extract the named steps.
7. **§7.1/7.2 file splits:** last, since these are the only steps that change the include list.

### 8.3 What needs the game, and what doesn't
- **Lint only (can be done before the weekend):** steps 2–6. These are renames, comments and extractions inside a file. `lint_shadowing` catches a rename that collides with another name, and `glua_check` catches an undefined global from a missed rename.
- **Needs a game run:** step 7. A split changes load order and file-level `local`s become cross-file. After each split: `pinnedpanels_reload`, open the hub, pin a tool, pin an addon window, then `pinnedpanels_debug panels`.
- Also run the in-game `AUDIT.md` checks once after the whole pass, so the readability work hasn't hidden a bug.

### 8.4 Don't touch
- Idiomatic short scopes: `for i = 1, n`, sort comparators, `x, y, w, h` geometry, `tr`, `ok, err` in two lines.
- The file-level module aliases.
- Comments that explain *why* (§6 only removes codes and history).
- The record **fields** `w`/`h`/`x`/`y` (they are saved).

## 9. What not to do

- Don't lengthen names that are already clear: `Layout.Pin`, `Storage.Sanitize`, `Geom.FreeSpot`, `Embed.Attach`, `Nav.Rank`, `isScene`, `byCategory`, `settled`.
- Don't delete single-use helpers that name a real step: `settled`, `backdropOf`, `onPlaceholder`, `overWindow`, `shownToRoot`, `pickable`, `chainAt`, `partsOf`.
- Don't inline logic into long expressions without names.
- Don't rename anything listed in §8.1.
- Don't change behaviour in a readability commit. If a rename turns up a bug, write it in `AUDIT.md` and fix it in its own commit.
- Don't grow the line count as a side effect, except for the line-wrapping in §7.5.
