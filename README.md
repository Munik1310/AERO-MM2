# AERO // MM2

Tactical HUD for **Murder Mystery 2** (Roblox). [Русский ниже ↓](#русский)

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/Munik1310/AERO-MM2/main/loader.lua"))()
```

Run it in your executor while in MM2. The loader only starts in MM2 (PlaceId `142823291`).

## Features

| Tab | What it does |
| --- | --- |
| Overview | Map, round timer, your role and coins, murderer, gun holder (Sheriff/Hero), dropped gun; quick teleports |
| Visuals | Player highlight in role colors, name tags, distance; coin, body and dropped-gun markers |
| Farm | Coin auto farm (glide or teleport, avoids the murderer, stops when the bag is full), auto grab gun, anti-AFK, murderer alert |
| Movement | Walk speed, jump power, infinite jump, noclip, FOV, camera zoom, third person |
| Teleport | Teleport to players, spectate, lobby and map spawns, save/return position |
| Settings | Language (English/Русский), accent color, toggle key, UI scale, diagnostics |

Roles and deaths come from the game's own player data, so they update the moment the round starts.

## Controls

- **Insert** shows/hides the window (change it in Settings).
- **–** in the title bar collapses the window to a small button; drag it anywhere, tap it to open again. On phones this is the way to open and close.
- Drag the window by its title bar.

## Your own pictures

**Settings → Custom images**: choose *All tabs*, one tab or *Window background*, paste an image and press **Apply**.
Accepted: a direct PNG/JPEG link, a Roblox asset id (`123456789`), or a file path inside your executor's `workspace`.
**Reset** brings back the default picture.

Or simply drop files into `workspace/AERO/images`:
`overview.png`, `visuals.png`, `farm.png`, `movement.png`, `teleport.png`, `settings.png`, `background.png` (`.jpg` works too).

## Top bar

A small bar at the top of the screen shows FPS, ping, time, map, round time left and your role. Drag it anywhere, or pick center/left/right in **Settings → Top bar**. **Event feed** shows the latest log lines under it.

## Saved settings

Your settings are saved to `AERO/settings.json` in your executor's `workspace` folder and load automatically next time. **Settings → Reset all settings** restores the defaults.

## Requirements

| Function | Needed for |
| --- | --- |
| `loadstring`, `game:HttpGet` | required |
| `writefile`, `readfile`, `isfile` | saved settings, diagnostics |
| `getcustomasset` | tab banner photos (without it the banners stay plain) |
| `gethui` | hides the UI from the game (falls back to CoreGui / PlayerGui) |

Tested on **Xeno v1.3.65 (PC)**, MM2 build 1467. Other executors and mobile are not tested yet — reports welcome.

## When MM2 updates

If the game changes, AERO shows a warning on start. To help fix it: **Settings → Record a round**, play one round, then send the file `AERO/collect_*.txt` from your `workspace` folder.

## Credits

- UI: [DebugKit](https://github.com/Munik1310/DebugKit) v2
- Banner photos from [Unsplash](https://unsplash.com/license), free under the Unsplash License (AERO-graded copies in `assets/banners`): [Laurentiu Morariu](https://unsplash.com/photos/0xpS2jc784M), [F9BEO9-4Kuo](https://unsplash.com/photos/F9BEO9-4Kuo), [Olga Guryanova](https://unsplash.com/photos/x1xg7wtIAvU), [qQwxU7NJWTI](https://unsplash.com/photos/qQwxU7NJWTI), [Ioann-Mark Kuznietsov](https://unsplash.com/photos/gtCWBwbZNpM)

Use at your own risk.

---

## Русский

Тактический HUD для **Murder Mystery 2** (Roblox).

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/Munik1310/AERO-MM2/main/loader.lua"))()
```

Запусти в экзекьюторе, находясь в MM2. В других играх loader не запускается (нужен PlaceId `142823291`).

### Возможности

| Вкладка | Что умеет |
| --- | --- |
| Обзор | Карта, таймер раунда, твоя роль и монеты, убийца, у кого пистолет (шериф/герой), пистолет на земле; быстрые телепорты |
| Визуал | Подсветка игроков цветом роли, подписи, расстояние; метки монет, тел и выпавшего пистолета |
| Фарм | Автофарм монет (плавно или телепортом, обходит убийцу, останавливается при полной сумке), автоподбор пистолета, анти-AFK, предупреждение об убийце |
| Движение | Скорость, сила прыжка, бесконечный прыжок, noclip, FOV, отдаление камеры, вид от третьего лица |
| Телепорт | К игрокам, наблюдение, точки спавна в лобби и на карте, сохранение позиции |
| Настройки | Язык (English/Русский), цвет акцента, клавиша окна, масштаб, диагностика |

Роли и смерти берутся из данных самой игры, поэтому видны сразу в начале раунда.

### Управление

- **Insert** — показать/скрыть окно (клавишу можно сменить в настройках).
- **–** в заголовке сворачивает окно в маленькую кнопку: её можно перетащить, нажатие открывает окно. На телефоне открывай и закрывай так.
- Окно перетаскивается за заголовок.

### Свои картинки

**Настройки → Свои картинки**: выбери «Все вкладки», одну вкладку или «Фон окна», вставь картинку и нажми **Применить**.
Подходит прямая ссылка на PNG/JPEG, asset id Roblox (`123456789`) или путь к файлу в `workspace` экзекьютора.
**Сбросить** возвращает картинку по умолчанию.

Или просто положи файлы в `workspace/AERO/images`:
`overview.png`, `visuals.png`, `farm.png`, `movement.png`, `teleport.png`, `settings.png`, `background.png` (можно `.jpg`).

### Верхняя панель

Небольшая панель сверху экрана: FPS, пинг, время, карта, сколько осталось до конца раунда и твоя роль. Её можно перетащить или выбрать положение в **Настройки → Верхняя панель**. **Лента событий** показывает под ней последние строки лога.

### Сохранение настроек

Настройки сохраняются в `AERO/settings.json` в папке `workspace` экзекьютора и подгружаются при следующем запуске. **Настройки → Сбросить настройки** возвращает значения по умолчанию.

### Требования

| Функция | Для чего |
| --- | --- |
| `loadstring`, `game:HttpGet` | обязательно |
| `writefile`, `readfile`, `isfile` | сохранение настроек, диагностика |
| `getcustomasset` | фото в шапках вкладок (без неё шапки без фото) |
| `gethui` | прячет интерфейс от игры (иначе CoreGui / PlayerGui) |

Проверено на **Xeno v1.3.65 (ПК)**, сборка MM2 1467. Другие экзекьюторы и телефоны пока не проверялись — пишите, как работает.

### Если MM2 обновилась

При изменении игры AERO покажет предупреждение при запуске. Чтобы помочь с исправлением: **Настройки → Записать раунд**, сыграй один раунд и пришли файл `AERO/collect_*.txt` из папки `workspace`.

### Авторы

- Интерфейс: [DebugKit](https://github.com/Munik1310/DebugKit) v2
- Фото в шапках — [Unsplash](https://unsplash.com/license), бесплатная лицензия Unsplash (ссылки на авторов выше); обработанные копии в `assets/banners`.

Используешь на свой риск.
