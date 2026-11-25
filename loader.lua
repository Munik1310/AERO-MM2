--[[
	AERO // MM2 — loader
	loadstring(game:HttpGet("https://raw.githubusercontent.com/Munik1310/AERO-MM2/main/loader.lua"))()

	This file lives on the main branch and points at one tagged release, so a release
	never changes under players' feet. To ship a new version: tag it, then bump VERSION here.
]]

local VERSION = "1.2.0"
local BASE_URL = "https://raw.githubusercontent.com/Munik1310/AERO-MM2/v" .. VERSION
local MM2_PLACE_ID = 142823291

if not game:IsLoaded() then
	game.Loaded:Wait()
end

if game.PlaceId ~= MM2_PLACE_ID then
	warn(string.format("[AERO] Murder Mystery 2 only (PlaceId %d). Current PlaceId: %d", MM2_PLACE_ID, game.PlaceId))
	return
end

if typeof(loadstring) ~= "function" then
	warn("[AERO] Your executor does not support loadstring")
	return
end

local function run()
	local ok, source = pcall(game.HttpGet, game, BASE_URL .. "/main.lua")
	if not ok or type(source) ~= "string" or #source < 1000 then
		warn("[AERO] Download failed: " .. tostring(source))
		return
	end
	local chunk, compileErr = loadstring(source)
	if not chunk then
		warn("[AERO] Compile error: " .. tostring(compileErr))
		return
	end
	local okRun, runErr = pcall(chunk)
	if not okRun then
		warn("[AERO] Runtime error: " .. tostring(runErr))
	end
end

-- Used by Settings → Language to restart the script in place.
local genv = (typeof(getgenv) == "function" and getgenv()) or _G
genv.AeroReload = run

run()
