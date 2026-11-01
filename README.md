# Azure

Dark/gold basketball hub UI for **Practical Basketball** (`Azure.lua`, no dependencies).

## Quick load (one-liner)

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/gg2444-dev/azure/main/Azure.lua"))()
```

Or use `loader.lua` — it downloads, caches, validates, and falls back if HttpGet is blocked.

## Run it (in-game script)

**In a game, with your executor:**
- Open the game, open your executor, paste the **entire contents of `Azure.lua`** into it and hit **Execute** — the window appears right away (`RightShift` toggles it), or
- Save the file to your executor's workspace and run:
  ```lua
  local Hub = loadstring(readfile("Azure.lua"))()
  ```
The Output/console shows `[Azure] v1.1 loaded` when it's up. Config saves through the executor's `writefile` to `Azure_config.json`, and the hub is available afterwards as `Azure` (in `_G` / `getgenv()`), e.g. `Azure:Notify("hi")`.

**Controller (PS5 / Xbox):** press the **Select/Create (Share)** button to open/close the menu, thumbstick or D-pad to move the selection, **×/A** to press the highlighted control. Keybinds can be captured from controller buttons too (e.g. set a keybind and press `ButtonX`).

**Roblox Studio (optional, for previewing the UI):**
1. Insert a **LocalScript** into `StarterPlayer > StarterPlayerScripts`
2. Paste the contents of `Azure.lua` into it
3. Press **Play**

## What you get

- Tabs: `Azure`, `SHOOTING`, `PLAYER`, `DRIBBLING`, `DEFENSE`, `EXTRAS`, `SETTINGS`, `PRACTICAL BASKETBALL`
- **Live gameplay features (work now, keyboard + controller):**
  - **Walk Speed / Auto Sprint / Sprint Speed / Jump Power** — drives the Humanoid directly, keep-alive loop so the game can't quietly reset it
  - **Perfect Release / Auto Green** (SHOOTING tab) — reads the game's shot meter GUI and simulates releasing the shoot button (`E` on keyboard, `Square`/`ButtonX` on controller) at the configured **Green Release %**; release delay and input device are configurable
- Widgets: toggles, sliders, dropdowns (incl. multi-select, e.g. "Block These Shots"), keybinds, buttons, info rows — all navigable by controller
- Window: drag by titlebar, `○` hide, `—` minimize, `X` destroy, `RightShift` or **Select button** to toggle
- Settings: UI scale, accent color (Gold/Red/Cyan/Purple/Green/White), animations
- Config: auto-saves to `Azure_config.json` (executor file API); Save/Load/Reset buttons in Settings
- Extras: anti-AFK, watermark with FPS, notifications, rejoin/server-hop/reset/copy-PlaceId tools
- `PRACTICAL BASKETBALL` tab: aim offsets (X/Y/Z), block/rebound Y offsets, auto-offset toggle

## Wiring the remaining features to your game

Movement and Auto Green are fully implemented. The rest (auto block, dribble glides, auto shoot, offsets…) only store state — plug your own game logic in through `Changed`:

```lua
local Hub = loadstring(readfile("Azure.lua"))() -- or paste-and-run

Hub.Changed:Connect(function(id, value)
    if id == "defense.autoBlock" then
        -- your auto-block logic here (runs when the toggle flips)
    elseif id == "offsets.x" then
        -- your offset logic here
    end
end)

Hub:Get("defense.masterRange") -- read current value any time
```

Ids: `hub.enabled` (master switch — check `Hub:IsEnabled()` before acting), `shoot.*`,
`player.*`, `dribble.*`, `defense.*`, `offsets.*`, `extras.*`, `ui.*`.

## Notes

- Keybinds save as names (`"G"`, `"RightShift"`, `"ButtonX"`, `"MouseButton2"`).
- Auto Green needs the game's **Meter** turned on (game Settings) and an executor with
  `VirtualInputManager` (Xeno/Solara/Delta/Wave-class executors have it). Tune **Green Release %**
  if releases land early/late.
- The remaining gameplay features are stubs — remote events and part names differ per game,
  so hook them up where you know the target's internals, and keep automation to practice/private
  use (public-server automation can violate the game's terms).
