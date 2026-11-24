# Changelog

## 1.0.0 — 2026-11-25

First public release. Tested on MM2 build 1467 with Xeno v1.3.65 (PC).

**Overview**
- Live round status: map, round timer, your role and coins, murderer, gun holder (Sheriff or Hero), dropped gun
- Roles and deaths straight from the game's player data, death feed in the log
- Quick actions: teleport to nearest coin, to the dropped gun, behind the gun holder; report roles; respawn

**Visuals**
- Player highlight with role colors, name tags and distance
- Coin, body and dropped-gun markers

**Movement**
- Walk speed, jump power, infinite jump, noclip, FOV, zoom distance, third person

**Teleport**
- Players, spectate, lobby and map spawn points, saved position

**Settings**
- English / Русский, accent color, toggle key, UI scale, FPS, console log
- Settings saved to `AERO/settings.json`
- Diagnostics: record a round to `AERO/collect_*.txt`, probe role data, scan map

**UI (DebugKit 2.1)**
- Tactical HUD skin, tab banners, stat cards, button grids
- Auto-fits small screens (phones), collapsible to a draggable button
