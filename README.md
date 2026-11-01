# Azure

Dark/gold basketball hub UI (`Azure.lua`, ~1370 lines, no dependencies).

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
The Output/console shows `[Azure] v1.0 loaded` when it's up. Config saves through the executor's `writefile` to `Azure_config.json`, and the hub is available afterwards as `Azure` (in `_G` / `getgenv()`), e.g. `Azure:Notify("hi")`.

**Roblox Studio (optional, for previewing the UI):**
1. Insert a **LocalScript** into `StarterPlayer > StarterPlayerScripts`
2. Paste the contents of `Azure.lua` into it
3. Press **Play**

## What you get

- Tabs: `Azure`, `SHOOTING`, `PLAYER`, `DRIBBLING`, `DEFENSE`, `EXTRAS`, `SETTINGS`, `PRACTICAL BASKETBALL`
- Widgets: toggles, sliders, dropdowns (incl. multi-select, e.g. "Block These Shots"), keybinds, buttons, info rows
- Window: drag by titlebar, `○` hide, `—` minimize, `X` destroy, `RightShift` (rebindable) to toggle
- Settings: UI scale, accent color (Gold/Red/Cyan/Purple/Green/White), animations
- Config: auto-saves to `Azure_config.json` (executor file API); Save/Load/Reset buttons in Settings
- Extras: anti-AFK, watermark with FPS, notifications, rejoin/server-hop/reset/copy-PlaceId tools
- `PRACTICAL BASKETBALL` tab: aim offsets (X/Y/Z), block/rebound Y offsets, auto-offset toggle

## Wiring features to your game

The UI only stores state — plug your own game logic in through `Changed`:

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

- Keybinds save as names (`"G"`, `"RightShift"`, `"MouseButton2"`).
- Gameplay features are intentionally stubs — remote events and part names differ per game,
  so hook them up where you know the target's internals, and keep automation to practice/private
  use (public-server automation can violate the game's terms).
