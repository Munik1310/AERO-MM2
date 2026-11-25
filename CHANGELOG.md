# Changelog

## 1.2.0 — 2026-11-25

**Startup intro (new)**
- "Calibration" splash when the script starts: screen dims, scanline sweep, corner brackets fly in
  to a reticle, radar sweep, glitch title, live boot log (DebugKit, player data, map, banners,
  coins, role), calibration counter; then it collapses into the top bar and the window springs in
- Click, tap or any key skips it; Settings → Startup intro turns it off, Settings → Play intro replays it

**UI (DebugKit 2.3)**
- New `Window:PlayIntro({ Title, Subtitle, Lines, Footer, OnDone })`; lines can show live values

## 1.1.0 — 2026-11-25

**Farm tab (new)**
- Coin auto farm: glide (adjustable speed) or teleport, pause per coin, skips coins near the murderer,
  stops when the bag is full (coin limit from the round) and can go to the lobby or a saved position
- Auto grab gun: picks up GunDrop and returns to where you were (not as murderer)
- Anti-AFK, murderer proximity alert

**Your own pictures**
- Settings → Custom images: put any PNG/JPEG on all tabs, one tab or the window background
  (URL, Roblox asset id, or a file in your workspace); saved with your settings
- Or drop files into `workspace/AERO/images` (`overview.png`, `farm.jpg`, `background.png`, …)
- **Reset all** clears every custom picture at once
- Default tab photos are AERO-graded copies hosted in this repo (`assets/banners`), Unsplash originals as fallback

**Top bar**
- Draggable info bar in the same style: FPS, ping, time, map, round time left, your role
- Optional event feed under it (log lines that fade out); center/left/right position

**Fixes**
- Top bar no longer shakes while dragging; its dragged position is saved
- Dropdown choices are saved language-neutral, so switching EN/RU keeps them

**UI (DebugKit 2.2)**
- New: `Tab:CreateInput`, `Window:SetBackground`, `Window:CreateWatermark`, `Window.Fps`
- `Library:LoadImage` accepts a list of sources, bare asset ids and local files (checked to be PNG/JPEG);
  every URL gets its own cache file

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
