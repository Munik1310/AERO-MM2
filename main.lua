--[[
	AERO // MM2 tactical HUD (main.lua) — release build, see README.md
	Run through loader.lua; UI library: lib/DebugKit.lua (DebugKit v2) from the same release tag.

	Game paths and formats below were measured from:
	  - dex_dump_mm2.txt (2026-11-24, map MilBase)
	  - AERO/collect_142823291_20261124_190219.txt (one full Classic round on House2,
	    PlaceVersion 1467, Xeno v1.3.65)
	A different PlaceVersion triggers a warning on start: re-run Collect all to re-measure.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then
	error("[AERO] Must run on the client (Players.LocalPlayer is nil)")
end

local AERO_VERSION = "1.1.0"
-- Raw base of the release this file was published with (loader.lua points at the same tag).
local AERO_BASE_URL = "https://raw.githubusercontent.com/Munik1310/AERO-MM2/v" .. AERO_VERSION
local MM2_PLACE_ID = 142823291

if game.PlaceId ~= MM2_PLACE_ID then
	warn(string.format("[AERO] This script is for Murder Mystery 2 (PlaceId %d); current PlaceId is %d.", MM2_PLACE_ID, game.PlaceId))
	return
end

--------------------------------------------------------------------------
-- Game config. Paths are child-name lists from game. nil = not measured.
--------------------------------------------------------------------------

local GameConfig = {
	Source = "dex_dump_mm2.txt + collect_142823291_20261124_190219.txt (PlaceVersion 1467, Xeno v1.3.65)",
	PlaceVersion = 1467,

	Remotes = {
		-- RemoteFunction. Path measured; response format NOT measured.
		GetPlayerData = { "ReplicatedStorage", "Remotes", "Extras", "GetPlayerData" },
		-- RemoteEvents (listen only). Paths measured; argument formats NOT measured.
		RoundStart = { "ReplicatedStorage", "Remotes", "Gameplay", "RoundStart" },
		GameOver = { "ReplicatedStorage", "Remotes", "Gameplay", "GameOver" },
		LoadingMap = { "ReplicatedStorage", "Remotes", "Gameplay", "LoadingMap" },
		RoleSelect = { "ReplicatedStorage", "Remotes", "Gameplay", "RoleSelect" },
		KillEvent = { "ReplicatedStorage", "Remotes", "Gameplay", "KillEvent" },
		-- Recorded by the collector only (no HUD log line). Paths measured.
		ShowRoleSelect = { "ReplicatedStorage", "Remotes", "Gameplay", "ShowRoleSelect" },
		VictoryScreen = { "ReplicatedStorage", "Remotes", "Gameplay", "VictoryScreen" },
		CoinsStarted = { "ReplicatedStorage", "Remotes", "Gameplay", "CoinsStarted" },
		PlayerDataChanged = { "ReplicatedStorage", "Remotes", "Gameplay", "PlayerDataChanged" },
	},

	-- Workspace.RegularLobby.Spawns: 11 SpawnLocations named "Spawn"
	LobbySpawnsPath = { "Workspace", "RegularLobby", "Spawns" },
	-- Workspace.RoundTimerPart.SurfaceGui with TextLabels "CurrentRound" and "Timer"
	RoundTimerGuiPath = { "Workspace", "RoundTimerPart", "SurfaceGui" },

	-- Active map = a Workspace child Model with Spawns AND (Base OR CoinContainer).
	-- CoinContainer only appears at CoinsStarted (~27 s after LoadingMap), Base and Spawns
	-- are there on load (House2, MilBase). RegularLobby has Spawns but neither of the others.
	Map = {
		SpawnsName = "Spawns", -- MilBase.Spawns: 21 Parts, House2.Spawns: 12 Parts
		BaseName = "Base",
		CoinContainerName = "CoinContainer", -- coins spawn into it gradually during the round
		CoinName = "Coin_Server", -- Part with TouchInterest + CoinVisual
		RagdollName = "Raggy", -- MilBase.Raggy: dead body model
		RagdollPlayerValue = "PlayerName", -- StringValue on Raggy (= dead player's name)
		RagdollCreatorValue = "Creator", -- ObjectValue on Raggy; meaning NOT confirmed
	},

	-- Player data table: measured in collect_142823291_20261124_190219.txt (PlaceVersion 1467).
	-- Same shape from GetPlayerData, PlayerDataChanged arg1 and RoundStart arg2:
	--   { [PlayerName] = { Role = "Murderer"|"Sheriff"|"Innocent", Dead = bool, Killed = bool,
	--                      DeadTime = number?, Coins = number, Knife, Gun, Perk, XP, UserId, Effect? } }
	-- GetPlayerData returns an empty table in the lobby.
	RoleData = {
		Field = "Role",
		MurdererValue = "Murderer",
		SheriffValue = "Sheriff",
		-- Measured (collect_..._191126): an innocent who picks up GunDrop becomes "Hero";
		-- the dead sheriff keeps Role "Sheriff" with Dead = true. Hero counts as gun holder.
		HeroValue = "Hero",
		DeadField = "Dead",
		CoinsField = "Coins",
		PollInterval = 5, -- seconds; backup only, PlayerDataChanged pushes updates
		MaxAge = 20, -- seconds before polled roles count as stale
	},

	-- Measured: other players' Backpacks replicate; murderer holds Tool "Knife", sheriff Tool "Gun".
	MurdererToolName = "Knife",
	SheriffToolName = "Gun",

	-- Measured: Part "GunDrop" (Fire, SpecialMesh, TouchInterest) parented to the active map.
	DroppedGunName = "GunDrop",
}

--------------------------------------------------------------------------
-- Library
--------------------------------------------------------------------------

-- Release builds load the library vendored in the same repo and tag as this script.
-- Dev: set getgenv().AERO_DEV = true to load AERO/Gui.lua from the executor workspace instead.
local LIBRARY_URL = AERO_BASE_URL .. "/lib/DebugKit.lua"
local LIBRARY_LOCAL = "AERO/Gui.lua"
local DEV = typeof(getgenv) == "function" and getgenv().AERO_DEV == true

local LibrarySource = "release"
local okLib, Library = pcall(function()
	local source
	if DEV and typeof(isfile) == "function" and typeof(readfile) == "function" and isfile(LIBRARY_LOCAL) then
		source = readfile(LIBRARY_LOCAL)
		LibrarySource = "local " .. LIBRARY_LOCAL
	else
		source = game:HttpGet(LIBRARY_URL)
	end
	local chunk, compileErr = loadstring(source)
	if not chunk then
		error(compileErr)
	end
	return chunk()
end)
if not okLib or type(Library) ~= "table" or type(Library.CreateWindow) ~= "function" then
	error("[AERO] Failed to load DebugKit: " .. tostring(Library))
end

local genv = (typeof(getgenv) == "function" and getgenv()) or _G
if type(genv.AeroMM2Unload) == "function" then
	pcall(genv.AeroMM2Unload)
end

--------------------------------------------------------------------------
-- Saved settings (AERO/settings.json via writefile; silently off without file APIs)
--------------------------------------------------------------------------

local HttpService = game:GetService("HttpService")
local SETTINGS_FILE = "AERO/settings.json"

local Persist = {
	Values = {},
	Elements = {}, -- [key] = library element (Toggle / Slider / Dropdown)
	SavePending = false,
	Available = typeof(writefile) == "function" and typeof(readfile) == "function" and typeof(isfile) == "function",
}

do
	if Persist.Available then
		local ok, data = pcall(function()
			if not isfile(SETTINGS_FILE) then
				return nil
			end
			return HttpService:JSONDecode(readfile(SETTINGS_FILE))
		end)
		if ok and type(data) == "table" then
			for key, value in pairs(data) do
				local kind = type(value)
				if type(key) == "string" and (kind == "boolean" or kind == "number" or kind == "string") then
					Persist.Values[key] = value
				end
			end
		end
	end
end

local function persistWriteNow()
	if not Persist.Available then
		return false
	end
	return pcall(function()
		if typeof(isfolder) == "function" and typeof(makefolder) == "function" and not isfolder("AERO") then
			makefolder("AERO")
		end
		writefile(SETTINGS_FILE, HttpService:JSONEncode(Persist.Values))
	end)
end

local function persistSaveSoon()
	if Persist.SavePending or not Persist.Available then
		return
	end
	Persist.SavePending = true
	task.delay(1, function()
		Persist.SavePending = false
		persistWriteNow()
	end)
end

-- Wraps an element callback so every change is stored under `key`.
local function saved(key, fn)
	return function(value)
		Persist.Values[key] = value
		persistSaveSoon()
		if fn then
			return fn(value)
		end
	end
end

-- Remembers the element so the saved value can be applied after the UI is built.
local function persist(key, element)
	Persist.Elements[key] = element
	return element
end

--------------------------------------------------------------------------
-- Localisation (UI text; log lines stay English)
--------------------------------------------------------------------------

local LANGUAGES = { "English", "Русский" }
local LANGUAGE_CODES = { English = "en", ["Русский"] = "ru" }

local Lang = Persist.Values.language
if Lang ~= "en" and Lang ~= "ru" then
	local locale = string.lower(tostring(LocalPlayer.LocaleId or ""))
	Lang = string.sub(locale, 1, 2) == "ru" and "ru" or "en"
end

local STRINGS = {
	en = {
		tab_overview = "Overview", tab_visuals = "Visuals", tab_movement = "Movement",
		tab_teleport = "Teleport", tab_settings = "Settings",
		meta_visuals = "ESP · markers", meta_movement = "Locomotion · camera", meta_teleport = "Players · spawns",

		sec_round = "// Round status",
		card_map = "Map", card_timer = "Timer", card_you = "You",
		card_murderer = "Murderer", card_gun = "Gun", card_data = "Role data",
		st_lobby = "Lobby", st_no_map = "no active map", st_coins_bodies = "%d coins · %d bodies",
		st_left = "%s left", st_dead = "dead", st_in_round = "in round", st_lobby_state = "lobby",
		st_coins = "%s coins", st_alive = "%d alive", st_unknown = "Unknown", st_on_ground = "On ground",
		st_ago = "%ds ago", st_round_live = "Round live · %s", st_round_left = "Round · %s left",

		role_Murderer = "Murderer", role_Sheriff = "Sheriff", role_Hero = "Hero", role_Innocent = "Innocent",

		sec_actions = "// Quick actions",
		btn_tp_coin = "TP nearest coin", btn_tp_gun = "TP dropped gun", btn_tp_holder = "TP behind gun",
		btn_report = "Report roles", btn_respawn = "Respawn",

		sec_players = "// Players",
		esp_players = "Player highlight", esp_players_d = "Highlight + name tag through walls",
		role_colors = "Role colors", role_colors_d = "Murderer red · Sheriff blue · others green",
		server_roles = "Live role data", server_roles_d = "Role and death updates from the game",
		name_tags = "Name tags", show_distance = "Show distance",
		fill = "Fill transparency", max_distance = "Max distance",
		sec_objects = "// Map objects",
		coins = "Coin markers", coins_d = "Coins on the current map",
		bodies = "Body markers", bodies_d = "Bodies with the player's name",
		gun_esp = "Dropped gun highlight", gun_esp_d = "Gun dropped by the sheriff",

		sec_loco = "// Locomotion",
		speed_on = "Override walk speed", speed_on_d = "Re-applied every frame", speed = "Walk speed",
		jump_on = "Override jump power", jump = "Jump power", inf_jump = "Infinite jump",
		noclip = "Noclip", noclip_d = "Walk through walls",
		sec_camera = "// Camera",
		fov_on = "Override FOV", fov = "Field of view", zoom = "Max zoom distance", third = "Force third person",

		sec_tp_players = "// Players",
		target = "Target player", tp_player = "Teleport to player", spectate = "Spectate selected",
		refresh_players = "Refresh player list",
		sec_points = "// Spawn points",
		point = "Spawn point", no_points = "(no points found)", refresh_points = "Refresh spawn points",
		tp_point = "Teleport to spawn point", tp_lobby = "Teleport to lobby",
		sec_saved = "// Saved position", save_pos = "Save current position", return_pos = "Return to saved position",

		sec_interface = "// Interface",
		language = "Language", accent = "Accent color", key = "Toggle key", ui_scale = "UI scale",
		fps = "Show FPS", console = "Mirror log to console",
		sec_diag = "// Diagnostics",
		collect = "Record a round", collect_d = "Saves AERO/collect_*.txt for bug reports",
		save_collect = "Save record", probe = "Probe role data", scan = "Scan map & tools",
		sec_session = "// Session",
		reset = "Reset all settings", unload = "Unload AERO",
		lang_reload = "Language changed · reloading", lang_restart = "Language saved · run the script again",
		tab_farm = "Farm", meta_farm = "Coins · gun · utility",
		sec_farm = "// Coin farm",
		farm = "Auto farm coins", farm_d = "Collects coins until the bag is full",
		farm_mode = "Movement", mode_tween = "Glide", mode_tp = "Teleport",
		farm_speed = "Glide speed", farm_delay = "Pause on coin",
		avoid = "Avoid murderer", avoid_d = "Skips coins near the murderer", avoid_radius = "Avoid radius",
		on_full = "When the bag is full", full_stop = "Stay", full_lobby = "Go to lobby", full_saved = "Go to saved position",
		farm_status = "Farm: %s · coins %s · +%d this round",
		fs_off = "off", fs_paused = "paused", fs_no_map = "no map", fs_waiting_for_round = "waiting for round",
		fs_dead = "dead", fs_not_on_map = "not on map", fs_bag_full = "bag full", fs_farming = "farming", fs_no_coins = "no coins",
		sec_gun = "// Gun",
		grab = "Auto grab gun", grab_d = "Picks up the dropped gun (not as murderer)", grab_return = "Return after grab",
		sec_util = "// Utility",
		antiafk = "Anti-AFK", antiafk_d = "Prevents the idle kick",
		alert = "Murderer alert", alert_d = "Log warning when the murderer is close", alert_radius = "Alert radius",
		sec_hud = "// Top bar", hud_bar = "Info bar", hud_bar_d = "FPS · ping · time · map · round · role",
		hud_feed = "Event feed", hud_feed_d = "Log lines under the bar", hud_align = "Position",
		align_center = "Center", align_left = "Left", align_right = "Right",
		sec_images = "// Custom images", img_target = "Where", img_all = "All tabs", img_background = "Window background",
		img_source = "Image", img_placeholder = "URL, asset id or file in workspace",
		img_apply = "Apply", img_reset = "Reset", bg_opacity = "Background opacity",
		img_hint = "Or put files into workspace/AERO/images: overview.png, visuals.jpg, farm.png, movement.png, teleport.png, settings.png, background.png",
	},
	ru = {
		tab_overview = "Обзор", tab_visuals = "Визуал", tab_movement = "Движение",
		tab_teleport = "Телепорт", tab_settings = "Настройки",
		meta_visuals = "ESP · метки", meta_movement = "Движение · камера", meta_teleport = "Игроки · спавны",

		sec_round = "// Статус раунда",
		card_map = "Карта", card_timer = "Таймер", card_you = "Вы",
		card_murderer = "Убийца", card_gun = "Пистолет", card_data = "Данные ролей",
		st_lobby = "Лобби", st_no_map = "карта не загружена", st_coins_bodies = "%d монет · %d тел",
		st_left = "осталось %s", st_dead = "мёртв", st_in_round = "в раунде", st_lobby_state = "лобби",
		st_coins = "монет %s", st_alive = "%d живы", st_unknown = "Неизвестно", st_on_ground = "На земле",
		st_ago = "%d с назад", st_round_live = "Раунд · %s", st_round_left = "Раунд · осталось %s",

		role_Murderer = "Убийца", role_Sheriff = "Шериф", role_Hero = "Герой", role_Innocent = "Мирный",

		sec_actions = "// Быстрые действия",
		btn_tp_coin = "ТП к монете", btn_tp_gun = "ТП к пистолету", btn_tp_holder = "ТП за стрелка",
		btn_report = "Роли в лог", btn_respawn = "Респавн",

		sec_players = "// Игроки",
		esp_players = "Подсветка игроков", esp_players_d = "Подсветка и подпись сквозь стены",
		role_colors = "Цвета ролей", role_colors_d = "Убийца красный · шериф синий · остальные зелёные",
		server_roles = "Роли в реальном времени", server_roles_d = "Роли и смерти прямо из игры",
		name_tags = "Подписи", show_distance = "Показывать расстояние",
		fill = "Прозрачность заливки", max_distance = "Макс. дистанция",
		sec_objects = "// Объекты карты",
		coins = "Метки монет", coins_d = "Монеты на текущей карте",
		bodies = "Метки тел", bodies_d = "Тела с ником игрока",
		gun_esp = "Подсветка пистолета", gun_esp_d = "Пистолет, выпавший у шерифа",

		sec_loco = "// Передвижение",
		speed_on = "Своя скорость", speed_on_d = "Применяется каждый кадр", speed = "Скорость",
		jump_on = "Своя сила прыжка", jump = "Сила прыжка", inf_jump = "Бесконечный прыжок",
		noclip = "Noclip", noclip_d = "Проход сквозь стены",
		sec_camera = "// Камера",
		fov_on = "Свой FOV", fov = "Угол обзора", zoom = "Макс. отдаление камеры", third = "Вид от третьего лица",

		sec_tp_players = "// Игроки",
		target = "Игрок", tp_player = "ТП к игроку", spectate = "Наблюдать за игроком",
		refresh_players = "Обновить список",
		sec_points = "// Точки спавна",
		point = "Точка", no_points = "(точек нет)", refresh_points = "Обновить точки",
		tp_point = "ТП к точке", tp_lobby = "ТП в лобби",
		sec_saved = "// Сохранённая позиция", save_pos = "Запомнить позицию", return_pos = "Вернуться на позицию",

		sec_interface = "// Интерфейс",
		language = "Язык", accent = "Цвет акцента", key = "Клавиша окна", ui_scale = "Масштаб окна",
		fps = "Показывать FPS", console = "Дублировать лог в консоль",
		sec_diag = "// Диагностика",
		collect = "Записать раунд", collect_d = "Сохраняет AERO/collect_*.txt для отчёта",
		save_collect = "Сохранить запись", probe = "Проверить роли", scan = "Скан карты",
		sec_session = "// Сессия",
		reset = "Сбросить настройки", unload = "Выгрузить AERO",
		lang_reload = "Язык изменён · перезапуск", lang_restart = "Язык сохранён · запусти скрипт заново",
		tab_farm = "Фарм", meta_farm = "Монеты · пистолет · утилиты",
		sec_farm = "// Фарм монет",
		farm = "Автофарм монет", farm_d = "Собирает монеты, пока сумка не заполнится",
		farm_mode = "Перемещение", mode_tween = "Плавно", mode_tp = "Телепорт",
		farm_speed = "Скорость полёта", farm_delay = "Пауза на монете",
		avoid = "Избегать убийцу", avoid_d = "Пропускает монеты рядом с убийцей", avoid_radius = "Радиус избегания",
		on_full = "Когда сумка полна", full_stop = "Остаться", full_lobby = "В лобби", full_saved = "На сохранённую позицию",
		farm_status = "Фарм: %s · монет %s · +%d за раунд",
		fs_off = "выкл", fs_paused = "пауза", fs_no_map = "нет карты", fs_waiting_for_round = "ждёт раунд",
		fs_dead = "мёртв", fs_not_on_map = "не на карте", fs_bag_full = "сумка полна", fs_farming = "собирает", fs_no_coins = "нет монет",
		sec_gun = "// Пистолет",
		grab = "Автоподбор пистолета", grab_d = "Подбирает выпавший пистолет (не за убийцу)", grab_return = "Вернуться после подбора",
		sec_util = "// Утилиты",
		antiafk = "Анти-AFK", antiafk_d = "Не даёт кикнуть за бездействие",
		alert = "Предупреждение об убийце", alert_d = "Пишет в лог, когда убийца рядом", alert_radius = "Радиус предупреждения",
		sec_hud = "// Верхняя панель", hud_bar = "Инфо-панель", hud_bar_d = "FPS · пинг · время · карта · раунд · роль",
		hud_feed = "Лента событий", hud_feed_d = "Строки лога под панелью", hud_align = "Позиция",
		align_center = "По центру", align_left = "Слева", align_right = "Справа",
		sec_images = "// Свои картинки", img_target = "Куда", img_all = "Все вкладки", img_background = "Фон окна",
		img_source = "Картинка", img_placeholder = "Ссылка, asset id или файл в workspace",
		img_apply = "Применить", img_reset = "Сбросить", bg_opacity = "Яркость фона",
		img_hint = "Или положи файлы в workspace/AERO/images: overview.png, visuals.jpg, farm.png, movement.png, teleport.png, settings.png, background.png",
	},
}

local LIBRARY_STRINGS = {
	ru = {
		Ready = "Оверлей готов",
		Active = "АКТИВНО",
		Minimized = "Окно <b>свёрнуто</b>",
		Restored = "Окно <b>развёрнуто</b>",
		Reset = "Настройки <b>сброшены</b>",
		TabSwitched = "Вкладка → <b>%s</b>",
		ButtonPressed = "Кнопка <b>%s</b>",
	},
}

local function T(key, ...)
	local text = (STRINGS[Lang] and STRINGS[Lang][key]) or STRINGS.en[key] or key
	if select("#", ...) > 0 then
		return string.format(text, ...)
	end
	return text
end

-- Server role value ("Murderer", "Hero", …) → display text; unknown values pass through.
local function roleText(value)
	if value == nil then
		return nil
	end
	local key = "role_" .. tostring(value)
	local text = (STRINGS[Lang] and STRINGS[Lang][key]) or STRINGS.en[key]
	return text or tostring(value)
end

if type(Library.Strings) == "table" and LIBRARY_STRINGS[Lang] then
	for key, value in pairs(LIBRARY_STRINGS[Lang]) do
		Library.Strings[key] = value
	end
end
Library.LogToConsole = Persist.Values.console == true

-- Tab banner photos: rbxassetid, a workspace path, or a direct PNG/JPEG URL
-- (loaded through Library:LoadImage → HttpGet → writefile → getcustomasset). nil = no photo.
-- Banners: AERO-graded copies in the repo (assets/banners, same release tag), the original
-- Unsplash photo as fallback. Photos are free under the Unsplash License; credits in README.
local function unsplash(id)
	return "https://images.unsplash.com/photo-" .. id .. "?fm=jpg&q=70&w=1200&h=220&fit=crop&crop=entropy"
end
local function banner(name, unsplashId)
	return { AERO_BASE_URL .. "/assets/banners/" .. name .. ".jpg", unsplash(unsplashId) }
end
local BANNERS = {
	Overview = banner("overview", "1611125161572-7dcd6b336a3f"), -- Tokyo at night, Laurentiu Morariu
	Visuals = banner("visuals", "1501397605259-3ba06b1c69ad"), -- Dana Point at night (unsplash.com/photos/F9BEO9-4Kuo)
	Farm = banner("farm", "1557728834-7fa63a44489a"), -- Moscow at night (mirrored), Olga Guryanova
	Movement = banner("movement", "1557728834-7fa63a44489a"), -- Moscow at night, Olga Guryanova
	Teleport = banner("teleport", "1443175679639-685643a7fd62"), -- city lights (unsplash.com/photos/qQwxU7NJWTI)
	Settings = banner("settings", "1451988336904-b1a6e8846746"), -- map on wood, Ioann-Mark Kuznietsov
}

local ACCENTS = {
	Amber = Color3.fromRGB(255, 184, 28),
	Emerald = Color3.fromRGB(16, 224, 160),
	Cyan = Color3.fromRGB(34, 211, 238),
	Violet = Color3.fromRGB(168, 120, 255),
	Crimson = Color3.fromRGB(255, 82, 102),
}
local ACCENT_ORDER = { "Amber", "Emerald", "Cyan", "Violet", "Crimson" }
local KEYBINDS = { "Insert", "RightShift", "RightControl", "LeftAlt", "Home", "F4" }

local Window = Library:CreateWindow("AERO // MM2", {
	Subtitle = "TACTICAL HUD",
	Size = Vector2.new(700, 500),
	Accent = ACCENTS.Amber,
	Keybind = Enum.KeyCode.Insert,
})
local HasV2 = type(Window.SetStatus) == "function" -- false on the old GitHub v1 library

--------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------

local Connections = {}
local Unloaded = false

local function track(connection)
	table.insert(Connections, connection)
	return connection
end

local function esc(s)
	return (tostring(s):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

local function log(message)
	if not Unloaded then
		Window:Log(message)
	end
end

local function warnLog(message)
	log('<font color="#FF6B81">✕</font> ' .. message)
end

local function okLog(message)
	log('<font color="#7CFFB2">✓</font> ' .. message)
end

local function isSet(value)
	return value ~= nil and value ~= ""
end

local function gatedLog(feature, key)
	warnLog(esc(feature) .. " disabled: GameConfig.<b>" .. key .. "</b> is unset (not in dump)")
end

local lastErrorAt = 0
local function safe(tag, fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok and os.clock() - lastErrorAt > 3 then
		lastErrorAt = os.clock()
		warnLog(esc(tag) .. " error: " .. esc(err))
	end
	return ok
end

local function resolvePath(path)
	if type(path) ~= "table" or #path == 0 then
		return nil
	end
	local node = nil
	for i, name in ipairs(path) do
		if i == 1 then
			local ok, service = pcall(game.GetService, game, name)
			node = (ok and service) or game:FindFirstChild(name)
		else
			node = node:FindFirstChild(name)
		end
		if not node then
			return nil
		end
	end
	return node
end

local function finiteVector(v)
	return typeof(v) == "Vector3" and v.X == v.X and v.Y == v.Y and v.Z == v.Z and v.Magnitude < 1e6
end

local function instancePosition(inst)
	if not inst then
		return nil
	end
	if inst:IsA("BasePart") then
		return inst.Position
	end
	if inst:IsA("Model") then
		local ok, pivot = pcall(inst.GetPivot, inst)
		if ok then
			return pivot.Position
		end
	end
	if inst:IsA("Attachment") then
		return inst.WorldPosition
	end
	return nil
end

local function getCharacter(player)
	player = player or LocalPlayer
	local character = player and player.Character
	if character and character.Parent then
		return character
	end
	return nil
end

local function getHumanoid(player)
	local character = getCharacter(player)
	return character and character:FindFirstChildOfClass("Humanoid")
end

local function getRoot(player)
	local character = getCharacter(player)
	if not character then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

local function isAlive(player)
	local humanoid = getHumanoid(player)
	return humanoid ~= nil and humanoid.Health > 0
end

local function distanceTo(position)
	local root = getRoot()
	if not root or not finiteVector(position) then
		return nil
	end
	return (root.Position - position).Magnitude
end

local function summarizeArgs(...)
	local count = select("#", ...)
	local parts = {}
	for i = 1, math.min(count, 3) do
		local value = select(i, ...)
		local kind = typeof(value)
		local text
		if kind == "string" or kind == "number" or kind == "boolean" then
			text = tostring(value)
		elseif kind == "Instance" then
			text = value.Name
		else
			text = kind
		end
		table.insert(parts, esc(string.sub(text, 1, 24)))
	end
	return count .. " arg" .. (count == 1 and "" or "s") .. (#parts > 0 and (": " .. table.concat(parts, ", ")) or "")
end

--------------------------------------------------------------------------
-- Map / lobby / round (measured paths)
--------------------------------------------------------------------------

local MapCache = { Instance = nil, BoxCFrame = nil, BoxSize = nil }

local function findActiveMap()
	local cfg = GameConfig.Map
	for _, child in ipairs(workspace:GetChildren()) do
		if
			child:IsA("Model")
			and child:FindFirstChild(cfg.SpawnsName)
			and (child:FindFirstChild(cfg.BaseName) or child:FindFirstChild(cfg.CoinContainerName))
		then
			return child
		end
	end
	return nil
end

local function refreshMapBox(map)
	if MapCache.Instance == map then
		return
	end
	MapCache.Instance = map
	MapCache.BoxCFrame, MapCache.BoxSize = nil, nil
	if map then
		local ok, cf, size = pcall(map.GetBoundingBox, map)
		if ok and typeof(cf) == "CFrame" and typeof(size) == "Vector3" and finiteVector(size) then
			MapCache.BoxCFrame, MapCache.BoxSize = cf, size
		end
	end
end

local function isInsideMap(position)
	if not MapCache.BoxCFrame or not finiteVector(position) then
		return false
	end
	local p = MapCache.BoxCFrame:PointToObjectSpace(position)
	local half = MapCache.BoxSize / 2 + Vector3.new(40, 60, 40)
	return math.abs(p.X) <= half.X and math.abs(p.Y) <= half.Y and math.abs(p.Z) <= half.Z
end

local function getCoins(map)
	local coins = {}
	local container = map and map:FindFirstChild(GameConfig.Map.CoinContainerName)
	if not container then
		return coins
	end
	for _, coin in ipairs(container:GetChildren()) do
		if coin.Name == GameConfig.Map.CoinName and coin:IsA("BasePart") then
			table.insert(coins, coin)
			if #coins >= 300 then
				break
			end
		end
	end
	return coins
end

local function getBodies(map)
	local bodies = {}
	if not map then
		return bodies
	end
	for _, child in ipairs(map:GetChildren()) do
		if child.Name == GameConfig.Map.RagdollName and child:IsA("Model") then
			table.insert(bodies, child)
			if #bodies >= 30 then
				break
			end
		end
	end
	return bodies
end

local function bodyInfo(body)
	local nameValue = body:FindFirstChild(GameConfig.Map.RagdollPlayerValue)
	local creatorValue = body:FindFirstChild(GameConfig.Map.RagdollCreatorValue)
	local name = (nameValue and nameValue:IsA("StringValue") and nameValue.Value) or "?"
	local creator = nil
	if creatorValue and creatorValue:IsA("ObjectValue") and creatorValue.Value then
		creator = creatorValue.Value.Name
	end
	local root = body:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		root = body.PrimaryPart or body:FindFirstChildWhichIsA("BasePart")
	end
	return name, creator, root
end

local function getSpawnPoints(folder, prefix)
	local points = {}
	if not folder then
		return points
	end
	for index, point in ipairs(folder:GetChildren()) do
		if point:IsA("BasePart") then
			local pos = point.Position
			if finiteVector(pos) then
				table.insert(points, { Name = string.format("%s #%d", prefix, index), Position = pos })
			end
		end
	end
	return points
end

local function getMapPoints()
	local points = getSpawnPoints(resolvePath(GameConfig.LobbySpawnsPath), "Lobby")
	local map = findActiveMap()
	if map then
		for _, point in ipairs(getSpawnPoints(map:FindFirstChild(GameConfig.Map.SpawnsName), map.Name)) do
			table.insert(points, point)
		end
	end
	return points
end

local function readRoundTimer()
	local gui = resolvePath(GameConfig.RoundTimerGuiPath)
	if not gui then
		return nil, nil
	end
	local roundLabel = gui:FindFirstChild("CurrentRound")
	local timerLabel = gui:FindFirstChild("Timer")
	local roundText = roundLabel and roundLabel:IsA("TextLabel") and roundLabel.Text or nil
	local timerText = timerLabel and timerLabel:IsA("TextLabel") and timerLabel.Text or nil
	return roundText, timerText
end

--------------------------------------------------------------------------
-- Roles: GetPlayerData (runtime-discovered format) with optional Tool fallback
--------------------------------------------------------------------------

local RoleData = {
	ByPlayer = {}, -- [Player] = { Class = "Murderer"|"Sheriff"|"Other", Label = raw value }
	UpdatedAt = 0,
	Status = "not fetched",
	Inflight = false,
	InflightSince = 0,
	Field = GameConfig.RoleData.Field,
	MurdererValue = GameConfig.RoleData.MurdererValue,
	SheriffValue = GameConfig.RoleData.SheriffValue,
	Announced = false,
}

-- Round facts pushed by events (measured arg formats, collect file PlaceVersion 1467)
local RoundInfo = {
	-- GetPlayerData keeps returning the finished round's table after VictoryScreen,
	-- so player data is only applied between RoleSelect/RoundStart and the round end.
	Active = false,
	Length = nil, -- RoundStart arg1 (number, 180 in the recorded round)
	StartedAt = nil,
	CoinLimit = nil, -- CoinsStarted arg1.Coin.CollectionLimit (40)
}

local function discoverRoleValues(data)
	local found = {}
	for key, entry in pairs(data) do
		if type(key) == "string" and type(entry) == "table" then
			for field, value in pairs(entry) do
				if type(field) == "string" and type(value) == "string" then
					local lower = string.lower(value)
					local slot = found[field] or {}
					if string.find(lower, "murder", 1, true) then
						slot.M = slot.M or value
					end
					if string.find(lower, "sheriff", 1, true) then
						slot.S = slot.S or value
					end
					found[field] = slot
				end
			end
		end
	end
	local bestField, bestScore = nil, 0
	for field, slot in pairs(found) do
		local score = (slot.M and 1 or 0) + (slot.S and 1 or 0)
		if score > bestScore then
			bestField, bestScore = field, score
		end
	end
	if bestField then
		return bestField, found[bestField].M, found[bestField].S
	end
	return nil
end

local function parseRoleData(data)
	if type(data) ~= "table" then
		return nil, "response is " .. typeof(data)
	end

	if not RoleData.Field or not RoleData.MurdererValue or not RoleData.SheriffValue then
		local field, murderer, sheriff = discoverRoleValues(data)
		if field and (not RoleData.Field or RoleData.Field == field) then
			local changed = RoleData.Field ~= field
				or (murderer and not RoleData.MurdererValue)
				or (sheriff and not RoleData.SheriffValue)
			RoleData.Field = field
			RoleData.MurdererValue = RoleData.MurdererValue or murderer
			RoleData.SheriffValue = RoleData.SheriffValue or sheriff
			if changed then
				okLog(string.format(
					"Role format discovered: field <b>%s</b> · murderer=%s · sheriff=%s",
					esc(field),
					esc(RoleData.MurdererValue or "?"),
					esc(RoleData.SheriffValue or "?")
				))
			end
		end
	end
	if not RoleData.Field then
		return nil, "no role field found"
	end

	local result, count = {}, 0
	for key, entry in pairs(data) do
		if type(key) == "string" and type(entry) == "table" then
			local player = Players:FindFirstChild(key)
			local value = entry[RoleData.Field]
			if player and player:IsA("Player") and value ~= nil then
				local class = "Other"
				if RoleData.MurdererValue and value == RoleData.MurdererValue then
					class = "Murderer"
				elseif RoleData.SheriffValue and value == RoleData.SheriffValue then
					class = "Sheriff"
				elseif GameConfig.RoleData.HeroValue and value == GameConfig.RoleData.HeroValue then
					class = "Sheriff" -- gun holder; label keeps "Hero"
				end
				local cfg = GameConfig.RoleData
				result[player] = {
					Class = class,
					Label = string.sub(tostring(value), 1, 20),
					Dead = cfg.DeadField ~= nil and entry[cfg.DeadField] == true,
					Coins = cfg.CoinsField and tonumber(entry[cfg.CoinsField]) or nil,
				}
				count += 1
			end
		end
	end
	if count == 0 then
		if next(data) == nil then
			return nil, "empty (lobby)"
		end
		return nil, "no player entries matched"
	end
	return result
end

-- Applies a player-data table (GetPlayerData / PlayerDataChanged / RoundStart) and
-- logs deaths as a kill feed (KillEvent did not fire in the recorded round).
local function ingestRoleTable(data, source)
	if not RoundInfo.Active then
		RoleData.Status = "idle (no round)"
		return false
	end
	local parsed, err = parseRoleData(data)
	if not parsed then
		RoleData.Status = err
		if err ~= "empty (lobby)" and not RoleData.Announced then
			RoleData.Announced = true
			warnLog("Role data: <b>" .. esc(err) .. "</b> · run Probe role data")
		end
		return false
	end
	for player, entry in pairs(parsed) do
		local previous = RoleData.ByPlayer[player]
		if entry.Dead and previous and not previous.Dead then
			local color = entry.Class == "Murderer" and "#FF4050" or (entry.Class == "Sheriff" and "#409CFF" or "#BEBEC8")
			log(string.format('☠ <font color="%s">%s</font> (%s) died', color, esc(player.Name), esc(entry.Label)))
		end
	end
	RoleData.ByPlayer = parsed
	RoleData.UpdatedAt = os.clock()
	RoleData.Status = "ok (" .. source .. ")"
	return true
end

local function fetchRoleData()
	if Unloaded then
		return
	end
	if RoleData.Inflight and os.clock() - RoleData.InflightSince < 15 then
		return
	end
	local remote = resolvePath(GameConfig.Remotes.GetPlayerData)
	if not remote or not remote:IsA("RemoteFunction") then
		RoleData.Status = "remote missing"
		return
	end
	RoleData.Inflight, RoleData.InflightSince = true, os.clock()
	task.spawn(function()
		local ok, data = pcall(remote.InvokeServer, remote)
		RoleData.Inflight = false
		if Unloaded then
			return
		end
		if not ok then
			RoleData.Status = "invoke error"
			return
		end
		ingestRoleTable(data, "poll")
	end)
end

local function toolRolesConfigured()
	return isSet(GameConfig.MurdererToolName) and isSet(GameConfig.SheriffToolName)
end

local function hasTool(player, toolName)
	if not isSet(toolName) then
		return false
	end
	local character = getCharacter(player)
	local tool = character and character:FindFirstChild(toolName)
	if tool and tool:IsA("Tool") then
		return true
	end
	local backpack = player:FindFirstChildOfClass("Backpack")
	tool = backpack and backpack:FindFirstChild(toolName)
	return tool ~= nil and tool:IsA("Tool")
end

local function roleDataFresh()
	return string.sub(RoleData.Status, 1, 2) == "ok" and os.clock() - RoleData.UpdatedAt <= GameConfig.RoleData.MaxAge
end

-- Returns class ("Murderer" | "Sheriff" | "Other" | "Unknown") and a display label.
local function getRoleInfo(player)
	if roleDataFresh() then
		local entry = RoleData.ByPlayer[player]
		if entry then
			return entry.Class, entry.Label
		end
	end
	if toolRolesConfigured() then
		if hasTool(player, GameConfig.MurdererToolName) then
			return "Murderer", "Murderer"
		end
		if hasTool(player, GameConfig.SheriffToolName) then
			return "Sheriff", "Sheriff"
		end
		return "Other", "No weapon"
	end
	return "Unknown", nil
end

-- Prefers a living holder: a dead sheriff keeps Role "Sheriff" while a Hero carries the gun.
local function findPlayerByRole(class)
	local fallback = nil
	local fresh = roleDataFresh()
	for _, player in ipairs(Players:GetPlayers()) do
		if getRoleInfo(player) == class then
			local entry = fresh and RoleData.ByPlayer[player] or nil
			local dead = (entry ~= nil and entry.Dead) or not isAlive(player)
			if not dead then
				return player
			end
			fallback = fallback or player
		end
	end
	return fallback
end

local function findDroppedGun()
	if not isSet(GameConfig.DroppedGunName) then
		return nil
	end
	local map = findActiveMap()
	local inst = map and map:FindFirstChild(GameConfig.DroppedGunName)
	if not inst then
		inst = workspace:FindFirstChild(GameConfig.DroppedGunName, true)
	end
	if inst and instancePosition(inst) then
		return inst
	end
	return nil
end

-- true only when fresh server data says the player is dead
local function isDeadInData(player)
	if not roleDataFresh() then
		return false
	end
	local entry = RoleData.ByPlayer[player]
	return entry ~= nil and entry.Dead == true
end

--------------------------------------------------------------------------
-- Teleport
--------------------------------------------------------------------------

local function teleportCFrame(cframe, targetName)
	local root = getRoot()
	if not root then
		warnLog("Teleport failed: <b>no character</b>")
		return false
	end
	if typeof(cframe) ~= "CFrame" or not finiteVector(cframe.Position) then
		warnLog("Teleport failed: invalid target position")
		return false
	end
	local ok = safe("Teleport", function()
		root.AssemblyLinearVelocity = Vector3.zero
		root.CFrame = cframe
	end)
	if ok then
		okLog("Teleported → <b>" .. esc(targetName) .. "</b>")
	end
	return ok
end

local function teleportPosition(position, targetName)
	if not finiteVector(position) then
		warnLog("Teleport failed: invalid target position")
		return false
	end
	return teleportCFrame(CFrame.new(position + Vector3.new(0, 3, 0)), targetName)
end

--------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------

local State = {
	PlayerESP = false,
	RoleColors = true,
	ShowLabels = true,
	ShowDistance = true,
	CoinESP = false,
	BodyESP = false,
	GunESP = false,
	FillTransparency = 0.6,
	MaxDistance = 1000,
	ServerRoles = true,

	SpeedEnabled = false,
	WalkSpeed = 16,
	JumpEnabled = false,
	JumpPower = 50,
	InfiniteJump = false,
	Noclip = false,

	FOVEnabled = false,
	FOV = 70,

	Spectate = false,
	SelectedPlayer = nil,
	SelectedPoint = nil,
	SavedCFrame = nil,

	-- Automation (uncalibrated defaults)
	AutoFarm = false,
	FarmMode = "tween", -- "tween" | "teleport"
	FarmSpeed = 24, -- studs per second in tween mode
	FarmDelay = 0.4, -- seconds standing on each coin
	AvoidMurderer = true,
	AvoidRadius = 30,
	FarmOnFull = "stop", -- "stop" | "lobby" | "saved"
	AutoGrabGun = false,
	GrabReturn = true,
	AntiAFK = false,
	MurdererAlert = false,
	AlertRadius = 35,

	-- Interface
	HudBar = true,
	BgOpacity = 0.25,
}

local ROLE_COLORS = {
	Murderer = Color3.fromRGB(255, 64, 80),
	Sheriff = Color3.fromRGB(64, 156, 255),
	Other = Color3.fromRGB(80, 230, 120),
}
local COIN_COLOR = Color3.fromRGB(255, 214, 64)
local BODY_COLOR = Color3.fromRGB(190, 190, 200)
local GUN_COLOR = Color3.fromRGB(255, 140, 30)

local Original = {}
local NoclipSaved = setmetatable({}, { __mode = "k" })

--------------------------------------------------------------------------
-- ESP
--------------------------------------------------------------------------

local ESP_TAG = "AeroESP"
local EspObjects = {} -- [Player] = { Highlight, Billboard, Label }
local CoinMarkers = {} -- [coin Part] = BoxHandleAdornment
local BodyMarkers = {} -- [Raggy Model] = { Billboard }
local GunEsp = nil

local function makeBillboard(adornee, color, text)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = ESP_TAG
	billboard.AlwaysOnTop = true
	billboard.Size = UDim2.fromOffset(220, 34)
	billboard.StudsOffset = Vector3.new(0, 3.2, 0)
	billboard.LightInfluence = 0
	billboard.ResetOnSpawn = false
	billboard.Adornee = adornee

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.Code
	label.TextSize = 13
	label.TextColor3 = color
	label.TextStrokeTransparency = 0.35
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	label.Text = text or ""
	label.Parent = billboard

	billboard.Parent = Window.Gui
	return billboard, label
end

local function makeHighlight(parent, color)
	local highlight = Instance.new("Highlight")
	highlight.Name = ESP_TAG
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.FillColor = color
	highlight.OutlineColor = color
	highlight.FillTransparency = State.FillTransparency
	highlight.OutlineTransparency = 0
	highlight.Parent = parent
	return highlight
end

local function clearPlayerEsp(player)
	local obj = EspObjects[player]
	if not obj then
		return
	end
	if obj.Highlight then
		obj.Highlight:Destroy()
	end
	if obj.Billboard then
		obj.Billboard:Destroy()
	end
	EspObjects[player] = nil
end

local function clearCoinMarkers()
	for coin, adornment in pairs(CoinMarkers) do
		adornment:Destroy()
		CoinMarkers[coin] = nil
	end
end

local function clearBodyMarkers()
	for body, billboard in pairs(BodyMarkers) do
		billboard:Destroy()
		BodyMarkers[body] = nil
	end
end

local function clearGunEsp()
	if not GunEsp then
		return
	end
	if GunEsp.Highlight then
		GunEsp.Highlight:Destroy()
	end
	if GunEsp.Billboard then
		GunEsp.Billboard:Destroy()
	end
	GunEsp = nil
end

local function clearAllEsp()
	for player in pairs(EspObjects) do
		clearPlayerEsp(player)
	end
	clearCoinMarkers()
	clearBodyMarkers()
	clearGunEsp()
end

local function updatePlayerEsp(player)
	local character = getCharacter(player)
	local root = getRoot(player)
	local distance = root and distanceTo(root.Position)
	if
		not State.PlayerESP
		or not character
		or not root
		or not isAlive(player)
		or isDeadInData(player)
		or (distance and distance > State.MaxDistance)
	then
		clearPlayerEsp(player)
		return
	end

	local class, label = getRoleInfo(player)
	local color = (State.RoleColors and ROLE_COLORS[class]) or Window.Accent

	local obj = EspObjects[player]
	if obj and (not obj.Highlight or obj.Highlight.Parent ~= character or not obj.Billboard or obj.Billboard.Adornee ~= root) then
		clearPlayerEsp(player)
		obj = nil
	end
	if not obj then
		local billboard, text = makeBillboard(root, color)
		obj = { Highlight = makeHighlight(character, color), Billboard = billboard, Label = text }
		EspObjects[player] = obj
	end

	obj.Highlight.FillColor = color
	obj.Highlight.OutlineColor = color
	obj.Highlight.FillTransparency = State.FillTransparency
	obj.Billboard.Enabled = State.ShowLabels
	obj.Label.TextColor3 = color

	local parts = { player.Name }
	if label then
		table.insert(parts, "[" .. string.upper(roleText(label)) .. "]")
	end
	if State.ShowDistance and distance then
		table.insert(parts, string.format("%dst", math.floor(distance + 0.5)))
	end
	obj.Label.Text = table.concat(parts, "  ")
end

local function updateCoinMarkers(map)
	if not State.CoinESP or not map then
		clearCoinMarkers()
		return
	end
	local seen = {}
	for _, coin in ipairs(getCoins(map)) do
		seen[coin] = true
		if not CoinMarkers[coin] then
			local box = Instance.new("BoxHandleAdornment")
			box.Name = ESP_TAG
			box.Adornee = coin
			box.AlwaysOnTop = true
			box.ZIndex = 5
			box.Size = Vector3.new(1.4, 1.4, 1.4)
			box.Color3 = COIN_COLOR
			box.Transparency = 0.25
			box.Parent = Window.Gui
			CoinMarkers[coin] = box
		end
	end
	for coin, box in pairs(CoinMarkers) do
		if not seen[coin] or not coin.Parent then
			box:Destroy()
			CoinMarkers[coin] = nil
		end
	end
end

local function updateBodyMarkers(map)
	if not State.BodyESP or not map then
		clearBodyMarkers()
		return
	end
	local seen = {}
	for _, body in ipairs(getBodies(map)) do
		local name, _, root = bodyInfo(body)
		if root then
			seen[body] = true
			local billboard = BodyMarkers[body]
			if not billboard or billboard.Adornee ~= root then
				if billboard then
					billboard:Destroy()
				end
				billboard = makeBillboard(root, BODY_COLOR, "☠ " .. name)
				billboard.StudsOffset = Vector3.new(0, 2, 0)
				BodyMarkers[body] = billboard
			end
		end
	end
	for body, billboard in pairs(BodyMarkers) do
		if not seen[body] or not body.Parent then
			billboard:Destroy()
			BodyMarkers[body] = nil
		end
	end
end

local function updateGunEsp()
	if not State.GunESP then
		clearGunEsp()
		return
	end
	local gun = findDroppedGun()
	if not gun then
		clearGunEsp()
		return
	end
	if GunEsp and (GunEsp.Target ~= gun or not GunEsp.Highlight or GunEsp.Highlight.Parent ~= gun) then
		clearGunEsp()
	end
	if not GunEsp then
		local billboard, label = makeBillboard(gun, GUN_COLOR, "GUN")
		GunEsp = { Target = gun, Highlight = makeHighlight(gun, GUN_COLOR), Billboard = billboard, Label = label }
	end
	local distance = distanceTo(instancePosition(gun))
	GunEsp.Label.Text = distance and string.format("GUN  %dst", math.floor(distance + 0.5)) or "GUN"
end

local function updateEsp()
	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= LocalPlayer then
			updatePlayerEsp(player)
		end
	end
	for player in pairs(EspObjects) do
		if player.Parent ~= Players then
			clearPlayerEsp(player)
		end
	end
	local map = MapCache.Instance
	updateCoinMarkers(map)
	updateBodyMarkers(map)
	updateGunEsp()
end

--------------------------------------------------------------------------
-- Movement
--------------------------------------------------------------------------

local function applyMovement()
	local humanoid = getHumanoid()
	if humanoid then
		if State.SpeedEnabled and humanoid.WalkSpeed ~= State.WalkSpeed then
			humanoid.WalkSpeed = State.WalkSpeed
		end
		if State.JumpEnabled then
			if not humanoid.UseJumpPower then
				humanoid.UseJumpPower = true
			end
			if humanoid.JumpPower ~= State.JumpPower then
				humanoid.JumpPower = State.JumpPower
			end
		end
	end
	if State.FOVEnabled then
		local camera = workspace.CurrentCamera
		if camera and camera.FieldOfView ~= State.FOV then
			camera.FieldOfView = State.FOV
		end
	end
end

local function restoreNoclip()
	for part in pairs(NoclipSaved) do
		if part.Parent then
			pcall(function()
				part.CanCollide = true
			end)
		end
	end
	table.clear(NoclipSaved)
end

local function setSpeedEnabled(on)
	local humanoid = getHumanoid()
	if on then
		if humanoid then
			Original.WalkSpeed = humanoid.WalkSpeed
		end
	elseif humanoid and Original.WalkSpeed then
		humanoid.WalkSpeed = Original.WalkSpeed
		Original.WalkSpeed = nil
	end
	State.SpeedEnabled = on
end

local function setJumpEnabled(on)
	local humanoid = getHumanoid()
	if on then
		if humanoid then
			Original.JumpPower = humanoid.JumpPower
			Original.UseJumpPower = humanoid.UseJumpPower
		end
	elseif humanoid and Original.JumpPower then
		humanoid.JumpPower = Original.JumpPower
		humanoid.UseJumpPower = Original.UseJumpPower
		Original.JumpPower, Original.UseJumpPower = nil, nil
	end
	State.JumpEnabled = on
end

local function setFovEnabled(on)
	local camera = workspace.CurrentCamera
	if on then
		if camera then
			Original.FOV = camera.FieldOfView
		end
	elseif camera and Original.FOV then
		camera.FieldOfView = Original.FOV
		Original.FOV = nil
	end
	State.FOVEnabled = on
end

--------------------------------------------------------------------------
-- Spectate
--------------------------------------------------------------------------

local spectateToggle -- assigned in the Teleport tab

local function resolveSelectedPlayer()
	if not State.SelectedPlayer then
		return nil
	end
	local player = Players:FindFirstChild(State.SelectedPlayer)
	if player and player:IsA("Player") and player ~= LocalPlayer then
		return player
	end
	return nil
end

local function restoreCamera()
	local camera = workspace.CurrentCamera
	local humanoid = getHumanoid()
	if camera and humanoid then
		camera.CameraSubject = humanoid
	end
end

local function setSpectate(on)
	State.Spectate = on
	if not on then
		restoreCamera()
		return true
	end
	local target = resolveSelectedPlayer()
	local humanoid = target and getHumanoid(target)
	local camera = workspace.CurrentCamera
	if not humanoid or not camera then
		State.Spectate = false
		warnLog("Spectate failed: <b>no valid target selected</b>")
		return false
	end
	camera.CameraSubject = humanoid
	okLog("Spectating <b>" .. esc(target.Name) .. "</b>")
	return true
end

--------------------------------------------------------------------------
-- Probes (print real runtime data to console for config pinning)
--------------------------------------------------------------------------

local function copyToClipboard(text)
	if typeof(setclipboard) == "function" then
		return pcall(setclipboard, text)
	end
	return false
end

local function describeValue(value, depth, indent, lines, maxLines)
	if #lines >= maxLines then
		return
	end
	if type(value) ~= "table" then
		return
	end
	for key, child in pairs(value) do
		if #lines >= maxLines then
			table.insert(lines, indent .. "... (truncated)")
			return
		end
		local kind = typeof(child)
		local shown
		if kind == "string" then
			shown = string.format("%q", string.sub(child, 1, 60))
		elseif kind == "number" or kind == "boolean" then
			shown = tostring(child)
		elseif kind == "Instance" then
			shown = "Instance " .. child:GetFullName()
		elseif kind == "table" then
			shown = "{table}"
		else
			shown = kind
		end
		table.insert(lines, string.format("%s[%s] = %s", indent, tostring(key), shown))
		if kind == "table" and depth > 1 then
			describeValue(child, depth - 1, indent .. "  ", lines, maxLines)
		end
	end
end

local function probeRoleData()
	local remote = resolvePath(GameConfig.Remotes.GetPlayerData)
	if not remote or not remote:IsA("RemoteFunction") then
		warnLog("Probe: <b>Remotes.Extras.GetPlayerData</b> not found")
		return
	end
	log("Probe: invoking <b>GetPlayerData</b>…")
	task.spawn(function()
		local ok, data = pcall(remote.InvokeServer, remote)
		if Unloaded then
			return
		end
		if not ok then
			warnLog("Probe: invoke failed · " .. esc(data))
			return
		end
		local lines = { "==== AERO probe · GetPlayerData · " .. typeof(data) .. " ====" }
		describeValue(data, 3, "", lines, 250)
		local text = table.concat(lines, "\n")
		print(text)
		local copied = copyToClipboard(text)
		local parsed, err = parseRoleData(data)
		if parsed then
			okLog("Probe: role data parsed · field <b>" .. esc(RoleData.Field) .. "</b>" .. (copied and " · copied" or " · see F9"))
		else
			warnLog("Probe: " .. esc(err) .. (copied and " · structure copied" or " · structure in F9"))
		end
	end)
end

local function scanStructure()
	local lines = { "==== AERO scan · PlaceId " .. game.PlaceId .. " · PlaceVersion " .. game.PlaceVersion .. " ====" }
	local map = findActiveMap()
	table.insert(lines, "Active map: " .. (map and map:GetFullName() or "none"))
	if map then
		for _, child in ipairs(map:GetChildren()) do
			table.insert(lines, string.format("  %s  %s  (%d children)", child.ClassName, child.Name, #child:GetChildren()))
		end
	end
	table.insert(lines, "-- Tools per player (Backpack + Character)")
	for _, player in ipairs(Players:GetPlayers()) do
		local names = {}
		local backpack = player:FindFirstChildOfClass("Backpack")
		if backpack then
			for _, tool in ipairs(backpack:GetChildren()) do
				if tool:IsA("Tool") then
					table.insert(names, "bp:" .. tool.Name)
				end
			end
		end
		local character = getCharacter(player)
		if character then
			for _, tool in ipairs(character:GetChildren()) do
				if tool:IsA("Tool") then
					table.insert(names, "char:" .. tool.Name)
				end
			end
		end
		table.insert(lines, player.Name .. ": " .. (#names > 0 and table.concat(names, ", ") or "(none visible)"))
	end
	table.insert(lines, "-- Workspace children (gun drop candidates appear here mid-round)")
	for _, child in ipairs(workspace:GetChildren()) do
		table.insert(lines, string.format("  %s  %s", child.ClassName, child.Name))
	end
	local text = table.concat(lines, "\n")
	print(text)
	local copied = copyToClipboard(text)
	okLog("Scan done" .. (copied and " · copied to clipboard" or " · see console (F9)"))
end

--------------------------------------------------------------------------
-- Collector: records one round of everything GameConfig still needs into one file
-- (environment, GetPlayerData responses, event args, tools, new map/workspace objects)
--------------------------------------------------------------------------

local Collector = {
	Active = false,
	Lines = {},
	Truncated = false,
	StartedAt = 0,
	SeenTools = {},
	LastToolSig = nil,
	EventCounts = {},
	Conns = {},
	MapConn = nil,
	FileName = nil,
}
local COLLECT_MAX_LINES = 20000
local COLLECT_MAX_PER_EVENT = 30

local function cAdd(line)
	if not Collector.Active then
		return
	end
	if #Collector.Lines >= COLLECT_MAX_LINES then
		Collector.Truncated = true
		return
	end
	table.insert(Collector.Lines, line)
end

local function cStamp()
	return string.format("[%7.1fs]", os.clock() - Collector.StartedAt)
end

local function cSection(title)
	cAdd("")
	cAdd(cStamp() .. " ==== " .. title .. " ====")
end

local function dumpTree(inst, depth, indent)
	local line = indent .. "[" .. inst.ClassName .. "] " .. inst.Name
	if inst:IsA("ValueBase") then
		local ok, value = pcall(function()
			return inst.Value
		end)
		if ok then
			line ..= " = " .. tostring(value)
		end
	elseif inst:IsA("BasePart") then
		local p = inst.Position
		line ..= string.format(" (Pos: %.0f, %.0f, %.0f)", p.X, p.Y, p.Z)
	end
	cAdd(line)
	local ok, children = pcall(inst.GetChildren, inst)
	if not ok or #children == 0 then
		return
	end
	if depth <= 0 then
		cAdd(indent .. "  ... " .. #children .. " children")
		return
	end
	for index, child in ipairs(children) do
		if index > 60 then
			cAdd(indent .. "  ... (" .. #children .. " total)")
			break
		end
		dumpTree(child, depth - 1, indent .. "  ")
	end
end

local function collectEnvironment()
	cSection("ENVIRONMENT")
	local executor = "unknown"
	if typeof(identifyexecutor) == "function" then
		local ok, name, version = pcall(identifyexecutor)
		if ok then
			executor = tostring(name) .. (version and (" " .. tostring(version)) or "")
		end
	end
	cAdd("Executor: " .. executor)
	cAdd(string.format("PlaceId: %d · PlaceVersion: %d · JobId: %s", game.PlaceId, game.PlaceVersion, game.JobId))
	local functions = {
		{ "getcustomasset", getcustomasset },
		{ "getsynasset", getsynasset },
		{ "writefile", writefile },
		{ "readfile", readfile },
		{ "isfile", isfile },
		{ "makefolder", makefolder },
		{ "isfolder", isfolder },
		{ "gethui", gethui },
		{ "setclipboard", setclipboard },
		{ "identifyexecutor", identifyexecutor },
		{ "getgenv", getgenv },
		{ "loadstring", loadstring },
	}
	for _, entry in ipairs(functions) do
		cAdd(string.format("  %-18s %s", entry[1], typeof(entry[2])))
	end
	cAdd("  game:HttpGet       " .. (pcall(function()
		return game.HttpGet
	end) and "present" or "missing"))
end

local function collectRoleData(tag)
	local remote = resolvePath(GameConfig.Remotes.GetPlayerData)
	if not remote or not remote:IsA("RemoteFunction") then
		cSection("GetPlayerData · " .. tag)
		cAdd("remote missing")
		return
	end
	task.spawn(function()
		local ok, data = pcall(remote.InvokeServer, remote)
		if not Collector.Active then
			return
		end
		cSection("GetPlayerData · " .. tag .. " · " .. typeof(data))
		if not ok then
			cAdd("invoke error: " .. tostring(data))
			return
		end
		if type(data) == "table" then
			local lines = {}
			describeValue(data, 4, "  ", lines, 400)
			for _, line in ipairs(lines) do
				cAdd(line)
			end
		else
			cAdd("  " .. tostring(data))
		end
	end)
end

local function toolSnapshot()
	local perPlayer, sigParts = {}, {}
	for _, player in ipairs(Players:GetPlayers()) do
		local tools = {}
		local backpack = player:FindFirstChildOfClass("Backpack")
		if backpack then
			for _, tool in ipairs(backpack:GetChildren()) do
				if tool:IsA("Tool") then
					table.insert(tools, { Where = "bp", Tool = tool })
				end
			end
		end
		local character = getCharacter(player)
		if character then
			for _, tool in ipairs(character:GetChildren()) do
				if tool:IsA("Tool") then
					table.insert(tools, { Where = "char", Tool = tool })
				end
			end
		end
		perPlayer[player] = tools
		local names = {}
		for _, entry in ipairs(tools) do
			table.insert(names, entry.Where .. ":" .. entry.Tool.Name)
		end
		table.insert(sigParts, player.Name .. "=" .. table.concat(names, ","))
	end
	table.sort(sigParts)
	return perPlayer, table.concat(sigParts, ";")
end

local function collectTools(tag)
	local perPlayer, sig = toolSnapshot()
	Collector.LastToolSig = sig
	cSection("TOOLS · " .. tag)
	for player, tools in pairs(perPlayer) do
		local names = {}
		for _, entry in ipairs(tools) do
			table.insert(names, entry.Where .. ":" .. entry.Tool.Name)
		end
		cAdd(string.format("  %s%s: %s", player.Name, player == LocalPlayer and " (you)" or "", #names > 0 and table.concat(names, ", ") or "(none visible)"))
	end
	for _, tools in pairs(perPlayer) do
		for _, entry in ipairs(tools) do
			local key = entry.Tool.Name
			if not Collector.SeenTools[key] then
				Collector.SeenTools[key] = true
				cSection("TOOL TREE · " .. key)
				dumpTree(entry.Tool, 3, "  ")
			end
		end
	end
end

local function collectMap(tag)
	cSection("MAP · " .. tag)
	local map = findActiveMap()
	cAdd("Active map: " .. (map and map:GetFullName() or "none"))
	if map then
		for _, child in ipairs(map:GetChildren()) do
			cAdd(string.format("  [%s] %s (%d children)", child.ClassName, child.Name, #child:GetChildren()))
		end
	end
	cAdd("-- Workspace children")
	for _, child in ipairs(workspace:GetChildren()) do
		cAdd(string.format("  [%s] %s", child.ClassName, child.Name))
	end
end

local function onNewInstance(where, child)
	if not Collector.Active then
		return
	end
	if Players:GetPlayerFromCharacter(child) then
		cAdd(cStamp() .. " + character " .. child.Name .. " in " .. where)
		return
	end
	-- give children time to replicate before dumping
	task.delay(0.5, function()
		if not Collector.Active or not child.Parent then
			return
		end
		cSection("NEW in " .. where .. ": [" .. child.ClassName .. "] " .. child.Name)
		local big = #child:GetChildren() > 20
		dumpTree(child, big and 1 or 3, "  ")
	end)
end

function Collector.WatchMap(map)
	if Collector.MapConn then
		Collector.MapConn:Disconnect()
		Collector.MapConn = nil
	end
	if not Collector.Active or not map then
		return
	end
	Collector.MapConn = map.ChildAdded:Connect(function(child)
		onNewInstance(map.Name, child)
	end)
	collectMap("map changed → " .. map.Name)
end

local function collectorText()
	local header = {
		"AERO collect file",
		"Config: " .. GameConfig.Source,
		"Lines: " .. #Collector.Lines .. (Collector.Truncated and " (TRUNCATED at " .. COLLECT_MAX_LINES .. ")" or ""),
	}
	return table.concat(header, "\n") .. "\n" .. table.concat(Collector.Lines, "\n")
end

local function saveCollect(reason)
	local text = collectorText()
	if typeof(writefile) == "function" then
		local ok, err = pcall(writefile, Collector.FileName, text)
		if ok then
			okLog(string.format("Collect saved (%s): <b>%s</b> · %d lines", esc(reason), esc(Collector.FileName), #Collector.Lines))
			return true
		end
		warnLog("Collect: writefile failed · " .. esc(err))
	end
	if copyToClipboard(text) then
		okLog("Collect copied to clipboard (" .. esc(reason) .. ") · " .. #Collector.Lines .. " lines")
		return true
	end
	print(text)
	warnLog("Collect: no writefile / clipboard · printed to console (F9)")
	return false
end

function Collector.OnEvent(key, ...)
	Collector.EventCounts[key] = (Collector.EventCounts[key] or 0) + 1
	if Collector.EventCounts[key] > COLLECT_MAX_PER_EVENT then
		return
	end
	local count = select("#", ...)
	cSection(string.format("EVENT %s #%d · %d args", key, Collector.EventCounts[key], count))
	for i = 1, math.min(count, 8) do
		local value = select(i, ...)
		local kind = typeof(value)
		if kind == "table" then
			cAdd("  arg" .. i .. " = {table}")
			local lines = {}
			describeValue(value, 3, "    ", lines, 200)
			for _, line in ipairs(lines) do
				cAdd(line)
			end
		elseif kind == "Instance" then
			cAdd(string.format("  arg%d = Instance %s [%s]", i, value:GetFullName(), value.ClassName))
		else
			cAdd(string.format("  arg%d = %s %s", i, kind, tostring(value)))
		end
	end

	if key == "RoleSelect" or key == "RoundStart" then
		task.delay(2, function()
			if Collector.Active then
				collectRoleData(key .. " +2s")
				collectTools(key .. " +2s")
				collectMap(key .. " +2s")
			end
		end)
	elseif key == "KillEvent" then
		collectRoleData("after KillEvent")
	elseif key == "GameOver" or key == "VictoryScreen" then
		collectRoleData(key)
		collectMap(key)
		task.delay(3, function()
			if Collector.Active then
				saveCollect("GameOver")
			end
		end)
	end
end

function Collector.Poll()
	if not Collector.Active then
		return
	end
	local _, sig = toolSnapshot()
	if sig ~= Collector.LastToolSig then
		collectTools("change")
	end
end

function Collector.Start()
	if Collector.Active then
		return
	end
	Collector.Active = true
	Collector.StartedAt = os.clock()
	Collector.Lines = {}
	Collector.Truncated = false
	Collector.SeenTools = {}
	Collector.LastToolSig = nil
	Collector.EventCounts = {}

	local stamp = os.date("!%Y%m%d_%H%M%S")
	local folderOk = false
	if typeof(makefolder) == "function" and typeof(isfolder) == "function" then
		folderOk = pcall(function()
			if not isfolder("AERO") then
				makefolder("AERO")
			end
		end)
	end
	Collector.FileName = string.format("%scollect_%d_%s.txt", folderOk and "AERO/" or "AERO_", game.PlaceId, stamp)

	cAdd("Started " .. os.date("!%Y-%m-%d %H:%M:%S") .. " UTC")
	collectEnvironment()
	collectMap("start")
	collectTools("start")
	collectRoleData("start")

	table.insert(Collector.Conns, workspace.ChildAdded:Connect(function(child)
		onNewInstance("Workspace", child)
	end))
	Collector.WatchMap(findActiveMap())
	okLog("Collect <b>on</b> · play one round; file saves at round end")
end

function Collector.Stop(save)
	if not Collector.Active then
		return
	end
	if save then
		saveCollect("stopped")
	end
	Collector.Active = false
	for _, connection in ipairs(Collector.Conns) do
		connection:Disconnect()
	end
	table.clear(Collector.Conns)
	if Collector.MapConn then
		Collector.MapConn:Disconnect()
		Collector.MapConn = nil
	end
end

--------------------------------------------------------------------------
-- UI: Overview
--------------------------------------------------------------------------

--------------------------------------------------------------------------
-- Automation: coin farm, auto gun grab, anti-AFK, murderer alert
-- Uses measured data only: CoinContainer.Coin_Server, player-data Coins,
-- CoinsStarted CollectionLimit, GunDrop, Role. Speeds/delays are uncalibrated defaults.
--------------------------------------------------------------------------

local Farm = {
	Thread = nil,
	Moving = false, -- read by the noclip Stepped handler
	Paused = false, -- set while the gun grab owns the character
	Skip = setmetatable({}, { __mode = "k" }), -- [coin] = os.clock() until which it is skipped
	Status = "off",
	FullHandled = false,
	Collected = 0,
}

local FARM_MODES = { Tween = "tween", Teleport = "teleport" }
local FULL_ACTIONS = { "stop", "lobby", "saved" }

local function myCoinState()
	local entry = roleDataFresh() and RoleData.ByPlayer[LocalPlayer] or nil
	return entry and entry.Coins, RoundInfo.CoinLimit
end

local function murdererRoot()
	local murderer = findPlayerByRole("Murderer")
	if not murderer or murderer == LocalPlayer or not isAlive(murderer) or isDeadInData(murderer) then
		return nil
	end
	return getRoot(murderer)
end

-- Returns ok, reason. Reason is shown in the Farm status line.
local function farmCanRun()
	if Unloaded or not State.AutoFarm then
		return false, "off"
	end
	if Farm.Paused then
		return false, "paused"
	end
	local map = MapCache.Instance
	if not map then
		return false, "no map"
	end
	if not RoundInfo.Active then
		return false, "waiting for round"
	end
	if not isAlive(LocalPlayer) or isDeadInData(LocalPlayer) then
		return false, "dead"
	end
	local root = getRoot()
	if not root or not isInsideMap(root.Position) then
		return false, "not on map"
	end
	local coins, limit = myCoinState()
	if coins and limit and coins >= limit then
		return false, "bag full"
	end
	return true, "farming"
end

local function pickCoin()
	local map = MapCache.Instance
	local root = getRoot()
	if not map or not root then
		return nil
	end
	local danger = State.AvoidMurderer and murdererRoot() or nil
	local now = os.clock()
	local best, bestDistance = nil, math.huge
	for _, coin in ipairs(getCoins(map)) do
		local skipUntil = Farm.Skip[coin]
		if not skipUntil or skipUntil < now then
			local safe = not danger or (coin.Position - danger.Position).Magnitude > State.AvoidRadius
			if safe then
				local d = (coin.Position - root.Position).Magnitude
				if d < bestDistance then
					best, bestDistance = coin, d
				end
			end
		end
	end
	return best
end

-- Moves the root to `coin`; false when interrupted (coin gone, farm stopped, murderer close).
local function moveToCoin(coin)
	local target = coin.Position
	if not finiteVector(target) then
		return false
	end
	if State.FarmMode == "teleport" then
		local root = getRoot()
		if not root then
			return false
		end
		root.AssemblyLinearVelocity = Vector3.zero
		root.CFrame = CFrame.new(target) * (root.CFrame - root.CFrame.Position)
		return true
	end

	local deadline = os.clock() + 15
	Farm.Moving = true
	while os.clock() < deadline do
		if not farmCanRun() or not coin.Parent then
			Farm.Moving = false
			return false
		end
		local root = getRoot()
		if not root then
			Farm.Moving = false
			return false
		end
		if State.AvoidMurderer then
			local danger = murdererRoot()
			if danger and (danger.Position - root.Position).Magnitude < State.AvoidRadius then
				Farm.Skip[coin] = os.clock() + 4
				Farm.Moving = false
				return false
			end
		end
		local delta = target - root.Position
		local distance = delta.Magnitude
		if distance < 1 then
			break
		end
		local dt = RunService.Heartbeat:Wait()
		local step = math.min(distance, State.FarmSpeed * math.min(dt, 0.1))
		root.CFrame = CFrame.new(root.Position + delta.Unit * step) * (root.CFrame - root.CFrame.Position)
		root.AssemblyLinearVelocity = Vector3.zero
	end
	Farm.Moving = false
	return os.clock() < deadline
end

local function handleBagFull()
	if Farm.FullHandled then
		return
	end
	Farm.FullHandled = true
	local coins, limit = myCoinState()
	okLog(string.format("Farm: bag <b>full</b> (%s/%s)", tostring(coins), tostring(limit)))
	if State.FarmOnFull == "lobby" then
		local points = getSpawnPoints(resolvePath(GameConfig.LobbySpawnsPath), "Lobby")
		if #points > 0 then
			teleportPosition(points[math.random(1, #points)].Position, "lobby")
		end
	elseif State.FarmOnFull == "saved" and State.SavedCFrame then
		teleportCFrame(State.SavedCFrame, "saved position")
	end
end

local function farmLoop()
	while not Unloaded and State.AutoFarm do
		local ok, reason = farmCanRun()
		Farm.Status = reason
		if ok then
			local coin = pickCoin()
			if coin then
				local before = myCoinState()
				local arrived = moveToCoin(coin)
				if arrived then
					task.wait(math.max(0.05, State.FarmDelay))
					local after = myCoinState()
					if before and after and after > before then
						Farm.Collected += after - before
					elseif coin.Parent then
						-- still there after touching it: not collectable for us, skip for this round
						Farm.Skip[coin] = math.huge
					end
				end
			else
				Farm.Status = "no coins"
				task.wait(0.5)
			end
		else
			if reason == "bag full" then
				handleBagFull()
			end
			task.wait(0.5)
		end
	end
	Farm.Moving = false
	Farm.Status = "off"
	if not State.Noclip then
		restoreNoclip()
	end
end

local function setAutoFarm(on)
	State.AutoFarm = on
	if on and not Farm.Thread then
		Farm.Thread = task.spawn(function()
			local ok, err = pcall(farmLoop)
			Farm.Thread = nil
			Farm.Moving = false
			if not ok then
				warnLog("Farm error: " .. esc(err))
			end
		end)
	end
end

-- Auto gun grab -----------------------------------------------------------

local GunGrab = { Busy = false, LastAttempt = 0 }

local function tryGrabGun()
	if GunGrab.Busy or os.clock() - GunGrab.LastAttempt < 2 then
		return
	end
	if not RoundInfo.Active or not isAlive(LocalPlayer) or isDeadInData(LocalPlayer) then
		return
	end
	local myClass = getRoleInfo(LocalPlayer)
	if myClass == "Murderer" or myClass == "Sheriff" then
		return
	end
	local gun = findDroppedGun()
	local position = gun and instancePosition(gun)
	local root = getRoot()
	if not finiteVector(position) or not root then
		return
	end
	GunGrab.Busy, GunGrab.LastAttempt = true, os.clock()
	Farm.Paused = true
	local back = root.CFrame
	task.spawn(function()
		local okMove = pcall(function()
			root.AssemblyLinearVelocity = Vector3.zero
			root.CFrame = CFrame.new(position)
		end)
		task.wait(0.4)
		local got = hasTool(LocalPlayer, GameConfig.SheriffToolName)
		if okMove and State.GrabReturn and root.Parent then
			pcall(function()
				root.AssemblyLinearVelocity = Vector3.zero
				root.CFrame = back
			end)
		end
		if got then
			okLog("Gun <b>grabbed</b>")
		else
			warnLog("Gun grab: <b>no gun after touch</b> · retrying in 2 s")
		end
		Farm.Paused = false
		GunGrab.Busy = false
	end)
end

-- Murderer alert ----------------------------------------------------------

local Alert = { Near = false }

local function checkMurdererAlert()
	if not State.MurdererAlert or not RoundInfo.Active then
		Alert.Near = false
		return
	end
	local danger = murdererRoot()
	local root = getRoot()
	if not danger or not root then
		Alert.Near = false
		return
	end
	local distance = (danger.Position - root.Position).Magnitude
	local near = distance <= State.AlertRadius
	if near and not Alert.Near then
		warnLog(string.format('<font color="#FF4050">Murderer close</font> · <b>%dst</b>', math.floor(distance + 0.5)))
	end
	-- hysteresis: re-arm only after moving clearly away
	Alert.Near = near or (Alert.Near and distance <= State.AlertRadius * 1.3)
end

-- Anti-AFK ----------------------------------------------------------------

track(LocalPlayer.Idled:Connect(function()
	if not State.AntiAFK then
		return
	end
	pcall(function()
		local virtualUser = game:GetService("VirtualUser")
		virtualUser:CaptureController()
		virtualUser:ClickButton2(Vector2.new())
	end)
end))

local updateFarmStatus -- assigned in the Farm tab

-- Tab factory: v2 tabs get a banner photo and a meta line; v1 falls back to plain tabs.
local TAB_META = {
	Overview = T("st_lobby"),
	Visuals = T("meta_visuals"),
	Farm = T("meta_farm"),
	Movement = T("meta_movement"),
	Teleport = T("meta_teleport"),
	Settings = "AERO " .. AERO_VERSION .. " · DebugKit " .. tostring(Library.Version),
}

local TAB_KEYS = { "Overview", "Visuals", "Farm", "Movement", "Teleport", "Settings" }
local TabsByKey = {}
local USER_IMAGE_FOLDER = "AERO/images"

-- Player's own pictures, highest priority first:
--   1) Settings → Custom images for this target, 2) the "all tabs" picture (tabs only),
--   3) a file workspace/AERO/images/<name>.png|jpg|jpeg
local function userImageSources(name)
	local list = {}
	local custom = Persist.Values["img_" .. name]
	if type(custom) == "string" and custom ~= "" then
		table.insert(list, custom)
	end
	if name ~= "background" then
		local all = Persist.Values.img_all
		if type(all) == "string" and all ~= "" then
			table.insert(list, all)
		end
	end
	if typeof(isfile) == "function" then
		for _, ext in ipairs({ "png", "jpg", "jpeg" }) do
			local path = USER_IMAGE_FOLDER .. "/" .. name .. "." .. ext
			local ok, exists = pcall(isfile, path)
			if ok and exists then
				table.insert(list, path)
				break
			end
		end
	end
	return list
end

local function applyBanner(key)
	local tab = TabsByKey[key]
	if not HasV2 or not tab then
		return
	end
	local sources = userImageSources(string.lower(key))
	local userCount = #sources
	for _, source in ipairs(BANNERS[key] or {}) do
		table.insert(sources, source)
	end
	task.spawn(function()
		local image, err = Library:LoadImage(sources, "aero")
		if Unloaded then
			return
		end
		if image then
			tab:SetBanner(image)
		else
			tab:SetBanner(nil)
			warnLog("Banner " .. esc(key) .. ": " .. esc(err))
		end
		if userCount > 0 and not image then
			warnLog("Custom image for <b>" .. esc(key) .. "</b> failed")
		end
	end)
end

local CurrentBackground = nil

local function applyBackground()
	if not HasV2 then
		return
	end
	local sources = userImageSources("background")
	if #sources == 0 then
		CurrentBackground = nil
		Window:SetBackground(nil)
		return
	end
	task.spawn(function()
		local image, err = Library:LoadImage(sources, "aero_user")
		if Unloaded then
			return
		end
		CurrentBackground = image
		Window:SetBackground(image, State.BgOpacity)
		if not image then
			warnLog("Background: " .. esc(err))
		end
	end)
end

local function makeTab(key)
	local title = T("tab_" .. string.lower(key))
	if not HasV2 then
		return Window:CreateTab(title)
	end
	local tab = Window:CreateTab(title, { Meta = TAB_META[key] })
	TabsByKey[key] = tab
	applyBanner(key)
	return tab
end

-- Top info bar (v2): FPS · ping · time · map · round · role, with an optional event feed.
local Watermark = HasV2 and Window:CreateWatermark({ Align = "center" }) or nil

local function getPing()
	local ok, value = pcall(function()
		return game:GetService("Stats").Network.ServerStatsItem["Data Ping"]:GetValue()
	end)
	if ok and type(value) == "number" and value == value and value >= 0 and value < 100000 then
		return math.floor(value + 0.5)
	end
	return nil
end

local function updateWatermark()
	if not Watermark or not State.HudBar then
		return
	end
	local items = { { Text = "AERO", Accent = true } }
	table.insert(items, (Window.Fps and tostring(Window.Fps) or "--") .. " FPS")
	local ping = getPing()
	table.insert(items, (ping and tostring(ping) or "--") .. " MS")
	table.insert(items, os.date("%H:%M:%S"))
	local map = MapCache.Instance
	table.insert(items, map and map.Name or T("st_lobby"))
	if RoundInfo.Length and RoundInfo.StartedAt then
		local left = math.max(0, RoundInfo.Length - (os.clock() - RoundInfo.StartedAt))
		table.insert(items, string.format("%d:%02d", math.floor(left / 60), math.floor(left % 60)))
	end
	local class, label = getRoleInfo(LocalPlayer)
	if label then
		table.insert(items, { Text = string.upper(roleText(label)), Color = ROLE_COLORS[class] })
	end
	Watermark:SetItems(items)
end

--------------------------------------------------------------------------
-- UI: Overview
--------------------------------------------------------------------------

local Overview = makeTab("Overview")

Overview:CreateSection(T("sec_round"))

-- StatusView(key, value, sub, valueTone): cards on v2, one text line per key on v1.
local StatusView
if HasV2 then
	local stats = Overview:CreateStats(3, {
		{ Key = "map", Label = T("card_map") },
		{ Key = "timer", Label = T("card_timer") },
		{ Key = "you", Label = T("card_you") },
		{ Key = "murderer", Label = T("card_murderer"), Tone = "danger" },
		{ Key = "gun", Label = T("card_gun"), Tone = "info" },
		{ Key = "data", Label = T("card_data") },
	})
	StatusView = function(key, value, sub, valueTone)
		stats:Set(key, { Value = value, Sub = sub or "", ValueTone = valueTone or false })
	end
else
	local lines = {}
	for _, key in ipairs({ "map", "timer", "you", "murderer", "gun", "data" }) do
		local line = Overview:CreateSection("// " .. T("card_" .. key) .. " · --")
		line.TextTruncate = Enum.TextTruncate.AtEnd
		line.TextColor3 = Library.Theme.Text
		line.TextSize = 11
		lines[key] = line
	end
	StatusView = function(key, value, sub)
		lines[key].Text = string.upper(string.format("// %s · %s%s", T("card_" .. key), tostring(value), (sub and sub ~= "") and (" · " .. sub) or ""))
	end
end

local refreshPoints -- forward (Teleport tab)
local KnownBodies = setmetatable({}, { __mode = "k" })
local lastMurderer, lastSheriff = nil, nil

local function distanceText(player)
	local root = player and getRoot(player)
	local d = root and distanceTo(root.Position)
	return d and string.format("%dst", math.floor(d + 0.5)) or nil
end

local function updateStatus()
	local map = findActiveMap()
	if map ~= MapCache.Instance then
		refreshMapBox(map)
		clearCoinMarkers()
		clearBodyMarkers()
		if map then
			okLog("Map detected: <b>" .. esc(map.Name) .. "</b>")
		else
			log("Map <b>unloaded</b> · lobby")
		end
		if refreshPoints then
			refreshPoints(true)
		end
		if Collector.Active then
			Collector.WatchMap(map)
		end
	end

	-- Map
	if map then
		StatusView("map", map.Name, T("st_coins_bodies", #getCoins(map), #getBodies(map)))
		for _, body in ipairs(getBodies(map)) do
			if not KnownBodies[body] then
				KnownBodies[body] = true
				local name, creator = bodyInfo(body)
				log("Body: <b>" .. esc(name) .. "</b>" .. (creator and (" · Creator=" .. esc(creator)) or ""))
			end
		end
	else
		StatusView("map", T("st_lobby"), T("st_no_map"), "muted")
	end

	-- Timer
	local roundText, timerText = readRoundTimer()
	local left = nil
	if RoundInfo.Length and RoundInfo.StartedAt then
		left = math.max(0, RoundInfo.Length - (os.clock() - RoundInfo.StartedAt))
	end
	local leftText = left and string.format("%d:%02d", math.floor(left / 60), math.floor(left % 60)) or nil
	local timerSub = table.concat({ roundText or "", timerText or "" }, roundText and timerText and " · " or "")
	StatusView("timer", leftText and T("st_left", leftText) or (timerText or "—"), timerSub, leftText == nil and "muted" or nil)

	-- You
	local inRound = 0
	for _, player in ipairs(Players:GetPlayers()) do
		local root = getRoot(player)
		if isAlive(player) and not isDeadInData(player) and root and isInsideMap(root.Position) then
			inRound += 1
		end
	end
	local _, myLabel = getRoleInfo(LocalPlayer)
	local myEntry = roleDataFresh() and RoleData.ByPlayer[LocalPlayer] or nil
	local myRoot = getRoot()
	local myState = (not isAlive(LocalPlayer) or isDeadInData(LocalPlayer)) and T("st_dead")
		or (myRoot and isInsideMap(myRoot.Position) and T("st_in_round") or T("st_lobby_state"))
	local youSub = { myState }
	if myEntry and myEntry.Coins then
		table.insert(youSub, T("st_coins", tostring(myEntry.Coins) .. (RoundInfo.CoinLimit and ("/" .. RoundInfo.CoinLimit) or "")))
	end
	table.insert(youSub, T("st_alive", inRound))
	StatusView("you", roleText(myLabel) or T("st_unknown"), table.concat(youSub, " · "), myLabel == nil and "muted" or nil)

	-- Murderer / gun holder
	local murderer = findPlayerByRole("Murderer")
	local sheriff = findPlayerByRole("Sheriff")
	StatusView("murderer", murderer and murderer.Name or "—", murderer and distanceText(murderer) or "", murderer == nil and "muted" or nil)

	local gunLabel = nil
	if sheriff then
		local _, label = getRoleInfo(sheriff)
		gunLabel = label
	end
	local holderAlive = sheriff ~= nil and isAlive(sheriff) and not isDeadInData(sheriff)
	local gunDrop = map and findDroppedGun() or nil
	if gunDrop and not holderAlive then
		local d = distanceTo(instancePosition(gunDrop))
		StatusView("gun", T("st_on_ground"), d and string.format("GunDrop · %dst", math.floor(d + 0.5)) or "GunDrop", "accent")
	elseif sheriff then
		local sub = roleText(gunLabel or "Sheriff")
		local dist = distanceText(sheriff)
		StatusView("gun", sheriff.Name, dist and (sub .. " · " .. dist) or sub, holderAlive and nil or "muted")
	else
		StatusView("gun", "—", "", "muted")
	end

	local mName, sName = murderer and murderer.Name, sheriff and sheriff.Name
	if mName and mName ~= lastMurderer then
		log('Murderer: <font color="#FF4050">' .. esc(mName) .. "</font>")
	end
	if sName and sName ~= lastSheriff then
		log('Sheriff: <font color="#409CFF">' .. esc(sName) .. "</font>")
	end
	lastMurderer, lastSheriff = mName, sName

	-- Role data
	local age = RoleData.UpdatedAt > 0 and math.floor(os.clock() - RoleData.UpdatedAt) or nil
	local fresh = roleDataFresh()
	StatusView("data", RoleData.Status, age and T("st_ago", age) or "", fresh and "success" or "muted")

	-- Header pill + Overview banner meta
	if HasV2 then
		Window:SetStatus(map and T("st_round_live", map.Name) or T("st_lobby"))
		Overview:SetMeta(leftText and T("st_round_left", leftText) or (map and map.Name or T("st_lobby")))
	end

	if State.Spectate then
		local target = resolveSelectedPlayer()
		if not target or not isAlive(target) then
			if spectateToggle then
				spectateToggle:Set(false, true)
			end
			setSpectate(false)
			warnLog("Spectate stopped: <b>target lost</b>")
		end
	end
end

-- Button grid on v2, one button per row on v1.
local function addButtons(tab, columns, specs)
	if HasV2 then
		return tab:CreateButtonGrid(columns, specs)
	end
	local result = {}
	for i, spec in ipairs(specs) do
		result[i] = tab:CreateButton(spec[1], spec[2], spec[3])
	end
	return result
end

local function reportRoles()
	local murderer = findPlayerByRole("Murderer")
	local sheriff = findPlayerByRole("Sheriff")
	if not murderer and not sheriff then
		warnLog("Roles unknown · role data: <b>" .. esc(RoleData.Status) .. "</b>")
		return
	end
	log(string.format(
		'Murderer: <font color="#FF4050">%s</font> · Gun: <font color="#409CFF">%s</font>',
		murderer and esc(murderer.Name) or "—",
		sheriff and esc(sheriff.Name) or "—"
	))
end

local function teleportNearestCoin()
	local map = MapCache.Instance or findActiveMap()
	local root = getRoot()
	if not map then
		warnLog("Coin teleport: <b>no active map</b>")
		return
	end
	if not root then
		warnLog("Coin teleport: <b>no character</b>")
		return
	end
	local best, bestDistance = nil, math.huge
	for _, coin in ipairs(getCoins(map)) do
		local d = (coin.Position - root.Position).Magnitude
		if d < bestDistance then
			best, bestDistance = coin, d
		end
	end
	if not best then
		warnLog("Coin teleport: <b>no coins</b> in " .. esc(map.Name))
		return
	end
	teleportCFrame(CFrame.new(best.Position), string.format("coin (%dst)", math.floor(bestDistance + 0.5)))
end

local function teleportBehindGunHolder()
	local sheriff = findPlayerByRole("Sheriff")
	local root = sheriff and getRoot(sheriff)
	if not root then
		warnLog("Gun teleport: <b>holder unknown</b> · role data: " .. esc(RoleData.Status))
		return
	end
	local _, label = getRoleInfo(sheriff)
	teleportCFrame(root.CFrame * CFrame.new(0, 0, 4), string.format("%s (%s)", sheriff.Name, label or "sheriff"))
end

local function teleportToDroppedGun()
	if not isSet(GameConfig.DroppedGunName) then
		gatedLog("Gun teleport", "DroppedGunName")
		return
	end
	local gun = findDroppedGun()
	if not gun then
		warnLog("Gun teleport: <b>no dropped gun on map</b>")
		return
	end
	local position = instancePosition(gun)
	if not finiteVector(position) then
		warnLog("Gun teleport: invalid GunDrop position")
		return
	end
	-- stand on it: GunDrop carries a TouchInterest
	teleportCFrame(CFrame.new(position), "dropped gun")
end

local function respawnCharacter()
	local humanoid = getHumanoid()
	if not humanoid then
		warnLog("Respawn: <b>no humanoid</b>")
		return
	end
	humanoid.Health = 0
	okLog("Character <b>reset</b>")
end

Overview:CreateSection(T("sec_actions"))
addButtons(Overview, 3, {
	{ T("btn_tp_coin"), teleportNearestCoin, { Primary = true } },
	{ T("btn_tp_gun"), teleportToDroppedGun, { Primary = true } },
	{ T("btn_tp_holder"), teleportBehindGunHolder },
	{ T("btn_report"), reportRoles },
	{ T("btn_respawn"), respawnCharacter, { Danger = true } },
})

--------------------------------------------------------------------------
-- UI: Visuals
--------------------------------------------------------------------------

local Visuals = makeTab("Visuals")

Visuals:CreateSection(T("sec_players"))
persist("esp_players", Visuals:CreateToggle(T("esp_players"), false, saved("esp_players", function(on)
	State.PlayerESP = on
	if not on then
		for player in pairs(EspObjects) do
			clearPlayerEsp(player)
		end
	end
end), T("esp_players_d")))

persist("role_colors", Visuals:CreateToggle(T("role_colors"), true, saved("role_colors", function(on)
	State.RoleColors = on
end), T("role_colors_d")))

persist("server_roles", Visuals:CreateToggle(T("server_roles"), true, saved("server_roles", function(on)
	State.ServerRoles = on
	if on then
		fetchRoleData()
	end
end), T("server_roles_d")))

persist("name_tags", Visuals:CreateToggle(T("name_tags"), true, saved("name_tags", function(on)
	State.ShowLabels = on
end)))

persist("show_distance", Visuals:CreateToggle(T("show_distance"), true, saved("show_distance", function(on)
	State.ShowDistance = on
end)))

persist("fill", Visuals:CreateSlider(T("fill"), 0, 1, 0.6, saved("fill", function(value)
	State.FillTransparency = value
end), { Increment = 0.05, Decimals = 2 }))

persist("max_distance", Visuals:CreateSlider(T("max_distance"), 50, 2000, 1000, saved("max_distance", function(value)
	State.MaxDistance = value
end), { Increment = 50, Suffix = " st" }))

Visuals:CreateSection(T("sec_objects"))
persist("coins", Visuals:CreateToggle(T("coins"), false, saved("coins", function(on)
	State.CoinESP = on
	if not on then
		clearCoinMarkers()
	end
end), T("coins_d")))

persist("bodies", Visuals:CreateToggle(T("bodies"), false, saved("bodies", function(on)
	State.BodyESP = on
	if not on then
		clearBodyMarkers()
	end
end), T("bodies_d")))

persist("gun_esp", Visuals:CreateToggle(T("gun_esp"), false, saved("gun_esp", function(on)
	State.GunESP = on
	if not on then
		clearGunEsp()
	end
end), T("gun_esp_d")))

--------------------------------------------------------------------------
-- UI: Farm
--------------------------------------------------------------------------

local FarmTab = makeTab("Farm")

-- Status line: a label on v2, a section line on v1.
local farmStatusSet
if HasV2 then
	local statusLabel = FarmTab:CreateLabel("", { Mono = true })
	farmStatusSet = function(text)
		statusLabel:Set(text)
	end
else
	local line = FarmTab:CreateSection("// --")
	farmStatusSet = function(text)
		line.Text = string.upper("// " .. text)
	end
end

updateFarmStatus = function()
	local coins, limit = myCoinState()
	local coinText = coins and (tostring(coins) .. (limit and ("/" .. limit) or "")) or "—"
	local reasonKey = "fs_" .. string.gsub(Farm.Status, " ", "_")
	farmStatusSet(T("farm_status", T(reasonKey), coinText, Farm.Collected))
end

FarmTab:CreateSection(T("sec_farm"))
persist("farm", FarmTab:CreateToggle(T("farm"), false, saved("farm", function(on)
	setAutoFarm(on)
end), T("farm_d")))

-- Localised option labels ↔ stored identifiers
local MODE_LABELS = { [T("mode_tween")] = "tween", [T("mode_tp")] = "teleport" }
persist("farm_mode", FarmTab:CreateDropdown(T("farm_mode"), { T("mode_tween"), T("mode_tp") }, saved("farm_mode", function(label)
	State.FarmMode = MODE_LABELS[label] or "tween"
end), T("mode_tween")))

persist("farm_speed", FarmTab:CreateSlider(T("farm_speed"), 10, 60, 24, saved("farm_speed", function(value)
	State.FarmSpeed = value
end), { Increment = 1, Suffix = " st/s" }))

persist("farm_delay", FarmTab:CreateSlider(T("farm_delay"), 0, 2, 0.4, saved("farm_delay", function(value)
	State.FarmDelay = value
end), { Increment = 0.1, Decimals = 1, Suffix = " s" }))

persist("avoid", FarmTab:CreateToggle(T("avoid"), true, saved("avoid", function(on)
	State.AvoidMurderer = on
end), T("avoid_d")))

persist("avoid_radius", FarmTab:CreateSlider(T("avoid_radius"), 10, 80, 30, saved("avoid_radius", function(value)
	State.AvoidRadius = value
end), { Increment = 5, Suffix = " st" }))

local FULL_LABELS = { [T("full_stop")] = "stop", [T("full_lobby")] = "lobby", [T("full_saved")] = "saved" }
persist("on_full", FarmTab:CreateDropdown(T("on_full"), { T("full_stop"), T("full_lobby"), T("full_saved") }, saved("on_full", function(label)
	State.FarmOnFull = FULL_LABELS[label] or "stop"
end), T("full_stop")))

FarmTab:CreateSection(T("sec_gun"))
persist("grab", FarmTab:CreateToggle(T("grab"), false, saved("grab", function(on)
	State.AutoGrabGun = on
end), T("grab_d")))

persist("grab_return", FarmTab:CreateToggle(T("grab_return"), true, saved("grab_return", function(on)
	State.GrabReturn = on
end)))

FarmTab:CreateSection(T("sec_util"))
persist("antiafk", FarmTab:CreateToggle(T("antiafk"), false, saved("antiafk", function(on)
	State.AntiAFK = on
end), T("antiafk_d")))

persist("alert", FarmTab:CreateToggle(T("alert"), false, saved("alert", function(on)
	State.MurdererAlert = on
end), T("alert_d")))

persist("alert_radius", FarmTab:CreateSlider(T("alert_radius"), 10, 100, 35, saved("alert_radius", function(value)
	State.AlertRadius = value
end), { Increment = 5, Suffix = " st" }))

--------------------------------------------------------------------------
-- UI: Movement
--------------------------------------------------------------------------

local Movement = makeTab("Movement")

Movement:CreateSection(T("sec_loco"))
persist("speed_on", Movement:CreateToggle(T("speed_on"), false, saved("speed_on", function(on)
	safe("Walk speed", setSpeedEnabled, on)
end), T("speed_on_d")))
persist("speed", Movement:CreateSlider(T("speed"), 8, 100, 16, saved("speed", function(value)
	State.WalkSpeed = value
end), { Increment = 1, Suffix = " st/s" }))

persist("jump_on", Movement:CreateToggle(T("jump_on"), false, saved("jump_on", function(on)
	safe("Jump power", setJumpEnabled, on)
end)))
persist("jump", Movement:CreateSlider(T("jump"), 20, 200, 50, saved("jump", function(value)
	State.JumpPower = value
end), { Increment = 5 }))

persist("inf_jump", Movement:CreateToggle(T("inf_jump"), false, saved("inf_jump", function(on)
	State.InfiniteJump = on
end)))

persist("noclip", Movement:CreateToggle(T("noclip"), false, saved("noclip", function(on)
	State.Noclip = on
	if not on then
		restoreNoclip()
	end
end), T("noclip_d")))

Movement:CreateSection(T("sec_camera"))
persist("fov_on", Movement:CreateToggle(T("fov_on"), false, saved("fov_on", function(on)
	safe("FOV", setFovEnabled, on)
end)))
persist("fov", Movement:CreateSlider(T("fov"), 40, 120, 70, saved("fov", function(value)
	State.FOV = value
end), { Increment = 1, Suffix = "°" }))

persist("zoom", Movement:CreateSlider(T("zoom"), 10, 400, 128, saved("zoom", function(value)
	safe("Zoom", function()
		LocalPlayer.CameraMaxZoomDistance = value
	end)
end), { Increment = 5, Suffix = " st" }))

persist("third", Movement:CreateToggle(T("third"), false, saved("third", function(on)
	safe("Camera mode", function()
		if on then
			Original.CameraMode = Original.CameraMode or LocalPlayer.CameraMode
			LocalPlayer.CameraMode = Enum.CameraMode.Classic
		elseif Original.CameraMode then
			LocalPlayer.CameraMode = Original.CameraMode
			Original.CameraMode = nil
		end
	end)
end)))

--------------------------------------------------------------------------
-- UI: Teleport
--------------------------------------------------------------------------

local Teleport = makeTab("Teleport")

local function otherPlayerNames()
	local names = {}
	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= LocalPlayer then
			table.insert(names, player.Name)
		end
	end
	table.sort(names, function(a, b)
		return a:lower() < b:lower()
	end)
	return names
end

Teleport:CreateSection(T("sec_tp_players"))
local playerDropdown = Teleport:CreateDropdown(T("target"), otherPlayerNames(), function(name)
	State.SelectedPlayer = name
	if State.Spectate then
		setSpectate(true)
	end
end)
State.SelectedPlayer = playerDropdown.Value

local function refreshPlayers(silent)
	playerDropdown:Refresh(otherPlayerNames(), true)
	State.SelectedPlayer = playerDropdown.Value
	if not silent then
		log("Player list refreshed: <b>" .. #playerDropdown.Options .. "</b> targets")
	end
end

Teleport:CreateButton(T("tp_player"), function()
	local target = resolveSelectedPlayer()
	if not target then
		warnLog("Teleport: <b>no valid player selected</b>")
		return
	end
	local root = getRoot(target)
	if not root then
		warnLog("Teleport: <b>" .. esc(target.Name) .. "</b> has no character")
		return
	end
	teleportCFrame(root.CFrame * CFrame.new(0, 0, 4), target.Name)
end, { Primary = true })

spectateToggle = Teleport:CreateToggle(T("spectate"), false, function(on)
	if not setSpectate(on) then
		spectateToggle:Set(false, true)
	elseif not on then
		log("Spectate <b>off</b>")
	end
end)

Teleport:CreateButton(T("refresh_players"), function()
	refreshPlayers(false)
end)

Teleport:CreateSection(T("sec_points"))
local NO_POINTS = T("no_points")
local CurrentPoints = {}

local pointDropdown = Teleport:CreateDropdown(T("point"), { NO_POINTS }, function(name)
	State.SelectedPoint = name
end)

refreshPoints = function(silent)
	CurrentPoints = getMapPoints()
	local names = {}
	for _, point in ipairs(CurrentPoints) do
		table.insert(names, point.Name)
	end
	if #names == 0 then
		names = { NO_POINTS }
	end
	pointDropdown:Refresh(names, true)
	State.SelectedPoint = pointDropdown.Value
	if not silent then
		if #CurrentPoints == 0 then
			warnLog("Map points: <b>none found</b> (RegularLobby.Spawns / map.Spawns missing)")
		else
			okLog("Map points: <b>" .. #CurrentPoints .. "</b> (lobby + current map)")
		end
	end
end

Teleport:CreateButton(T("refresh_points"), function()
	safe("Map points", refreshPoints, false)
end)

Teleport:CreateButton(T("tp_point"), function()
	for _, point in ipairs(CurrentPoints) do
		if point.Name == State.SelectedPoint then
			teleportPosition(point.Position, point.Name)
			return
		end
	end
	warnLog("Teleport: <b>no spawn point selected</b>")
end, { Primary = true })

Teleport:CreateButton(T("tp_lobby"), function()
	local points = getSpawnPoints(resolvePath(GameConfig.LobbySpawnsPath), "Lobby")
	if #points == 0 then
		warnLog("Lobby teleport: <b>RegularLobby.Spawns</b> not found")
		return
	end
	teleportPosition(points[math.random(1, #points)].Position, "lobby")
end)

Teleport:CreateSection(T("sec_saved"))
Teleport:CreateButton(T("save_pos"), function()
	local root = getRoot()
	if not root then
		warnLog("Save position: <b>no character</b>")
		return
	end
	State.SavedCFrame = root.CFrame
	local p = root.Position
	okLog(string.format("Position saved <b>(%.0f, %.0f, %.0f)</b>", p.X, p.Y, p.Z))
end)
Teleport:CreateButton(T("return_pos"), function()
	if not State.SavedCFrame then
		warnLog("Return: <b>no saved position</b>")
		return
	end
	teleportCFrame(State.SavedCFrame, "saved position")
end)

--------------------------------------------------------------------------
-- UI: Settings
--------------------------------------------------------------------------

local Settings = makeTab("Settings")
local unload -- forward

Settings:CreateSection(T("sec_interface"))

local currentLanguageName = Lang == "ru" and "Русский" or "English"
Settings:CreateDropdown(T("language"), LANGUAGES, function(name)
	local code = LANGUAGE_CODES[name]
	if not code or code == Lang then
		return
	end
	Persist.Values.language = code
	persistWriteNow()
	if type(genv.AeroReload) == "function" then
		log(T("lang_reload"))
		local reload = genv.AeroReload
		task.delay(0.3, function()
			unload()
			reload()
		end)
	else
		okLog(T("lang_restart"))
	end
end, currentLanguageName)

persist("accent", Settings:CreateDropdown(T("accent"), ACCENT_ORDER, saved("accent", function(name)
	local color = ACCENTS[name]
	if color then
		Window:SetAccent(color)
	end
end), "Amber"))

persist("keybind", Settings:CreateDropdown(T("key"), KEYBINDS, saved("keybind", function(name)
	local ok, keyCode = pcall(function()
		return Enum.KeyCode[name]
	end)
	if ok and keyCode then
		Window.Keybind = keyCode
	end
end), "Insert"))

if HasV2 then
	persist("ui_scale", Settings:CreateSlider(T("ui_scale"), 0.6, 1.3, 1, saved("ui_scale", function(value)
		Window:SetScale(value)
	end), { Increment = 0.05, Decimals = 2, Suffix = "×" }))
end

persist("fps", Settings:CreateToggle(T("fps"), true, saved("fps", function(on)
	Window:SetFpsVisible(on)
end)))

persist("console", Settings:CreateToggle(T("console"), false, saved("console", function(on)
	Library.LogToConsole = on
end)))

if HasV2 then
	Settings:CreateSection(T("sec_hud"))
	persist("hud_bar", Settings:CreateToggle(T("hud_bar"), true, saved("hud_bar", function(on)
		State.HudBar = on
		Watermark:SetVisible(on)
		if on then
			updateWatermark()
		end
	end), T("hud_bar_d")))

	persist("hud_feed", Settings:CreateToggle(T("hud_feed"), false, saved("hud_feed", function(on)
		Watermark:SetFeed(on)
	end), T("hud_feed_d")))

	local ALIGN_LABELS = { [T("align_center")] = "center", [T("align_left")] = "left", [T("align_right")] = "right" }
	persist("hud_align", Settings:CreateDropdown(T("hud_align"), { T("align_center"), T("align_left"), T("align_right") }, saved("hud_align", function(label)
		Watermark:SetAlign(ALIGN_LABELS[label] or "center")
	end), T("align_center")))

	Settings:CreateSection(T("sec_images"))

	local targetLabels, targetByLabel, keyByName = { T("img_all") }, { [T("img_all")] = "all" }, {}
	for _, key in ipairs(TAB_KEYS) do
		local labelText = T("tab_" .. string.lower(key))
		table.insert(targetLabels, labelText)
		targetByLabel[labelText] = string.lower(key)
		keyByName[string.lower(key)] = key
	end
	table.insert(targetLabels, T("img_background"))
	targetByLabel[T("img_background")] = "background"

	local imageTarget = "all"
	local imageInput

	local function reapplyImages(target)
		if target == "background" then
			applyBackground()
		elseif target == "all" then
			for _, key in ipairs(TAB_KEYS) do
				applyBanner(key)
			end
		elseif keyByName[target] then
			applyBanner(keyByName[target])
		end
	end

	local function applyImage()
		local source = string.match(imageInput.Value or "", "^%s*(.-)%s*$")
		if source == "" then
			warnLog("Image: <b>empty</b> · paste a URL, asset id or workspace file path")
			return
		end
		Persist.Values["img_" .. imageTarget] = source
		persistSaveSoon()
		log("Image → <b>" .. esc(imageTarget) .. "</b> · loading")
		reapplyImages(imageTarget)
	end

	local function resetImage()
		Persist.Values["img_" .. imageTarget] = nil
		persistSaveSoon()
		imageInput:Set("", true)
		log("Image → <b>" .. esc(imageTarget) .. "</b> · default")
		reapplyImages(imageTarget)
	end

	Settings:CreateDropdown(T("img_target"), targetLabels, function(labelText)
		imageTarget = targetByLabel[labelText] or "all"
		local current = Persist.Values["img_" .. imageTarget]
		imageInput:Set(type(current) == "string" and current or "", true)
	end, targetLabels[1])

	imageInput = Settings:CreateInput(T("img_source"), T("img_placeholder"), function(_, enterPressed)
		if enterPressed then
			applyImage()
		end
	end, { Default = type(Persist.Values.img_all) == "string" and Persist.Values.img_all or "" })

	addButtons(Settings, 2, {
		{ T("img_apply"), applyImage, { Primary = true } },
		{ T("img_reset"), resetImage },
	})

	persist("bg_opacity", Settings:CreateSlider(T("bg_opacity"), 0.05, 0.8, 0.25, saved("bg_opacity", function(value)
		State.BgOpacity = value
		if CurrentBackground then
			Window:SetBackground(CurrentBackground, value)
		end
	end), { Increment = 0.05, Decimals = 2 }))

	Settings:CreateLabel(T("img_hint"), { Mono = true })
end

Settings:CreateSection(T("sec_diag"))
Settings:CreateToggle(T("collect"), false, function(on)
	if on then
		safe("Collect", Collector.Start)
	else
		safe("Collect", Collector.Stop, true)
	end
end, T("collect_d"))

addButtons(Settings, 3, {
	{
		T("save_collect"),
		function()
			if not Collector.Active then
				warnLog("Collect: <b>not running</b> · enable recording first")
				return
			end
			safe("Collect", saveCollect, "manual")
		end,
	},
	{
		T("probe"),
		function()
			safe("Probe", probeRoleData)
		end,
	},
	{
		T("scan"),
		function()
			safe("Scan", scanStructure)
		end,
	},
})

Settings:CreateSection(T("sec_session"))
addButtons(Settings, 2, {
	{
		T("reset"),
		function()
			Window:Reset()
		end,
	},
	{
		T("unload"),
		function()
			unload()
		end,
		{ Danger = true },
	},
})

-- Apply saved values (validated per element type) and run their callbacks once.
local function applySavedSettings()
	for key, element in pairs(Persist.Elements) do
		local value = Persist.Values[key]
		local valid = false
		if element.Type == "Toggle" then
			valid = type(value) == "boolean"
		elseif element.Type == "Slider" then
			valid = type(value) == "number" and value == value
		elseif element.Type == "Dropdown" then
			valid = type(value) == "string" and table.find(element.Options, value) ~= nil
		end
		if valid and value ~= element.Value then
			element:Set(value, true)
			if element._callback then
				task.spawn(element._callback, element.Value)
			end
		end
	end
end

--------------------------------------------------------------------------
-- Remote event listeners (measured paths, args logged as-is)
--------------------------------------------------------------------------

local function listen(key, handler)
	local remote = resolvePath(GameConfig.Remotes[key])
	if not remote or not remote:IsA("RemoteEvent") then
		warnLog("Remote <b>" .. esc(key) .. "</b> not found")
		return
	end
	track(remote.OnClientEvent:Connect(function(...)
		if Unloaded then
			return
		end
		if Collector.Active then
			safe("Collect", Collector.OnEvent, key, ...)
		end
		if handler then
			safe(key, handler, ...)
		end
	end))
end

-- Arg formats below are measured (collect file, PlaceVersion 1467) unless noted.

local function clearRound(reason)
	RoleData.ByPlayer = {}
	RoleData.UpdatedAt = 0
	RoleData.Status = reason
	RoundInfo.Active = false
	RoundInfo.Length, RoundInfo.StartedAt, RoundInfo.CoinLimit = nil, nil, nil
end

listen("ShowRoleSelect", nil) -- collector only

-- arg1 = string game mode ("Classic")
listen("LoadingMap", function(mode)
	log("Loading map · mode <b>" .. esc(tostring(mode)) .. "</b>")
end)

-- arg1 = your role string, arg2/arg3 = nil, arg4 = boolean, arg5 = game mode
listen("RoleSelect", function(myRole)
	RoundInfo.Active = true
	log("Your role: <b>" .. esc(tostring(myRole)) .. "</b>")
	-- PlayerDataChanged with the new roles arrives just before RoleSelect and is skipped
	-- while no round is active, so pull the table right away.
	fetchRoleData()
end)

-- arg1 = round length in seconds (180), arg2 = player-data table
listen("RoundStart", function(length, data)
	RoundInfo.Active = true
	table.clear(Farm.Skip)
	Farm.FullHandled = false
	Farm.Collected = 0
	if type(length) == "number" and length > 0 and length < 3600 then
		RoundInfo.Length, RoundInfo.StartedAt = length, os.clock()
	end
	if type(data) == "table" then
		ingestRoleTable(data, "RoundStart")
	end
	log(string.format("Round <b>started</b> · %s s", RoundInfo.Length and tostring(RoundInfo.Length) or "?"))
	task.delay(2, function()
		if not Unloaded then
			safe("Map points", refreshPoints, true)
		end
	end)
end)

-- arg1 = { Coin = { CollectionLimit = 40, CollectedAmount = 0, CurrencyID = "Coins" } }
listen("CoinsStarted", function(info)
	local coin = type(info) == "table" and info.Coin
	local limit = type(coin) == "table" and tonumber(coin.CollectionLimit) or nil
	if limit and limit > 0 and limit < 10000 then
		RoundInfo.CoinLimit = limit
	end
	log("Coins <b>started</b>" .. (RoundInfo.CoinLimit and (" · limit " .. RoundInfo.CoinLimit) or ""))
end)

-- arg1 = player-data table (fires on role assignment, deaths, coin pickups)
listen("PlayerDataChanged", function(data)
	if type(data) == "table" then
		ingestRoleTable(data, "push")
	end
end)

-- arg1 = boolean, arg2 = winning side ("Innocent"), arg3 = reason ("Time"), arg5 = number
-- Seen: (false, "Innocent", "Time", nil, 4), (false, "Innocent", "MurdererDied", nil, 2),
--       (true, "Innocent", "MurdererDied", <Player>, 1). arg4 = the Player credited when arg1 is true
--       (it was the Hero in that round; meaning of arg1/arg5 not confirmed).
listen("VictoryScreen", function(flag, winner, reason, credited)
	local by = ""
	if flag == true and typeof(credited) == "Instance" and credited:IsA("Player") then
		by = " · by " .. esc(credited.Name)
	end
	log(string.format("Round <b>over</b> · winner %s · %s%s", esc(tostring(winner)), esc(tostring(reason)), by))
	clearRound("round over")
end)

-- Did not fire in the recorded round; kept for logging only.
listen("KillEvent", function(...)
	log("Event <b>KillEvent</b> · " .. summarizeArgs(...))
end)

-- Did not fire in the recorded round (it ended by time); kept as a second round-end signal.
listen("GameOver", function(...)
	log("Event <b>GameOver</b> · " .. summarizeArgs(...))
	clearRound("round over")
end)

--------------------------------------------------------------------------
-- Runtime loops
--------------------------------------------------------------------------

local espAccum, statusAccum, roleAccum, hudAccum = 0, 0, 0, 0
track(RunService.Heartbeat:Connect(function(dt)
	if Unloaded then
		return
	end
	safe("Movement", applyMovement)
	espAccum += dt
	if espAccum >= 0.2 then
		espAccum = 0
		safe("ESP", updateEsp)
		if State.AutoGrabGun then
			safe("Gun grab", tryGrabGun)
		end
	end
	statusAccum += dt
	if statusAccum >= 1 then
		statusAccum = 0
		safe("Status", updateStatus)
		safe("Alert", checkMurdererAlert)
		if updateFarmStatus then
			safe("Farm status", updateFarmStatus)
		end
	end
	hudAccum += dt
	if hudAccum >= 0.5 then
		hudAccum = 0
		safe("Top bar", updateWatermark)
	end
	roleAccum += dt
	if roleAccum >= GameConfig.RoleData.PollInterval then
		roleAccum = 0
		if State.ServerRoles then
			fetchRoleData()
		end
		if Collector.Active then
			safe("Collect", Collector.Poll)
		end
	end
end))

track(RunService.Stepped:Connect(function()
	if not State.Noclip and not Farm.Moving then
		return
	end
	local character = getCharacter()
	if not character then
		return
	end
	for _, inst in ipairs(character:GetDescendants()) do
		if inst:IsA("BasePart") and inst.CanCollide then
			NoclipSaved[inst] = true
			inst.CanCollide = false
		end
	end
end))

track(UserInputService.JumpRequest:Connect(function()
	if not State.InfiniteJump then
		return
	end
	local humanoid = getHumanoid()
	if humanoid and humanoid.Health > 0 then
		humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
	end
end))

track(Players.PlayerAdded:Connect(function(player)
	refreshPlayers(true)
	log("Player joined: <b>" .. esc(player.Name) .. "</b>")
end))

track(Players.PlayerRemoving:Connect(function(player)
	clearPlayerEsp(player)
	RoleData.ByPlayer[player] = nil
	task.defer(refreshPlayers, true)
	log("Player left: <b>" .. esc(player.Name) .. "</b>")
end))

track(LocalPlayer.CharacterAdded:Connect(function()
	table.clear(NoclipSaved)
	Original.WalkSpeed, Original.JumpPower, Original.UseJumpPower = nil, nil, nil
	if State.Spectate then
		task.defer(setSpectate, true)
	end
	log("Character <b>spawned</b>")
end))

--------------------------------------------------------------------------
-- Unload
--------------------------------------------------------------------------

unload = function()
	if Unloaded then
		return
	end
	pcall(Collector.Stop, true)
	State.AutoFarm, State.AutoGrabGun, State.AntiAFK, State.MurdererAlert = false, false, false, false
	Farm.Moving = false
	pcall(setSpeedEnabled, false)
	pcall(setJumpEnabled, false)
	pcall(setFovEnabled, false)
	State.InfiniteJump = false
	State.Noclip = false
	pcall(restoreNoclip)
	if State.Spectate then
		pcall(setSpectate, false)
	end
	if Original.CameraMode then
		pcall(function()
			LocalPlayer.CameraMode = Original.CameraMode
		end)
	end
	State.PlayerESP, State.CoinESP, State.BodyESP, State.GunESP = false, false, false, false
	pcall(clearAllEsp)

	Unloaded = true
	for _, connection in ipairs(Connections) do
		connection:Disconnect()
	end
	table.clear(Connections)
	if genv.AeroMM2Unload == unload then
		genv.AeroMM2Unload = nil
	end
	print("[AERO] Unloaded")
	Window:Destroy()
end
genv.AeroMM2Unload = unload

-- Injected mid-round: a loaded map means a round is running, so accept player data now.
RoundInfo.Active = findActiveMap() ~= nil
safe("Settings", applySavedSettings)
safe("Background", applyBackground)
safe("Status", updateStatus)
safe("Map points", refreshPoints, true)
fetchRoleData()
log(string.format("AERO <b>%s</b> online · DebugKit %s (%s)", AERO_VERSION, esc(tostring(Library.Version)), esc(LibrarySource)))
if game.PlaceVersion ~= GameConfig.PlaceVersion then
	warnLog(string.format(
		"MM2 updated (build <b>%d</b>, AERO tested on %d) · if something breaks, use Settings → Record a round and send the file",
		game.PlaceVersion,
		GameConfig.PlaceVersion
	))
end
