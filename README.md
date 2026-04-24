# 📌 Pinned Tool Panels — GMod Addon

Pin any tool/spawn menu panel to your screen so it stays visible even when the spawn menu is closed.

---

## Installation

1. Extract the `pinnedpanels` folder into:
   ```
   GarrysMod/garrysmod/addons/pinnedpanels/
   ```
2. The structure should look like:
   ```
   addons/
   └── pinnedpanels/
       ├── addon.json
       └── lua/
           └── autorun/
               └── client/
                   └── cl_pinnedpanels.lua
   ```
3. Restart or reload GMod.

---

## How to Use

### Pinning a Panel
1. Open the **Spawn Menu** (default: `Q`)
2. Navigate to any tool tab (e.g., Tools, Utilities, a custom addon tab)
3. **Right-click** on any panel's **header bar** (the dark title strip at the top)
4. Select **"📌 Pin this panel"** from the context menu
5. A floating window will appear on screen — **drag it anywhere you like**

### Managing Pinned Panels
- Open the Spawn Menu → **📌 Pinned** tab to see all pinned panels
- **Show / Hide** toggles a panel's visibility
- **✕ Unpin** removes the pin entirely

### The Pin Button (📌 / 📍)
Each pinned frame has a small colored button in its top-left corner:
- 🟢 Green (📌) — Panel stays on screen always
- 🔴 Red (📍) — Panel can be hidden normally

Click it to toggle **always-on-top** behaviour.

---

## Console Commands

| Command | Description |
|---|---|
| `pinnedpanels_list` | Print all currently pinned panels |
| `pinnedpanels_show <name>` | Toggle visibility of a pinned panel by partial name |
| `pinnedpanels_clearall` | Remove all pinned panels and reset saved data |

---

## Features

- ✅ Works with any `DFrame`, `DCollapsibleCategory`, or `DPanel`
- ✅ Positions and sizes are **saved to disk** and restored next session
- ✅ Panels survive spawn menu close/open cycles
- ✅ Resizable and draggable windows
- ✅ Clean **📌 Pinned** management tab in the spawn menu
- ✅ No external dependencies — pure GMod Lua

---

## Compatibility

- **Game**: Garry's Mod (any branch)
- **Side**: Client-only (no server required)
- **Conflicts**: None known
