-- Data.lua: the saved variables. Settings, and every character's levels:
--   levels[n] = { t = seconds spent on level n, at = when level n + 1 was reached (realm time),
--                 played = /played in total at that moment, zone = where, skipped = true (no time on it),
--                 legacy = true (recorded by Level Time Tracker 1.x, which only kept the time) }
local ADDON, ns = ...
local L, U = ns.L, ns.U

local Data = {}
ns.Data = Data

local floor, max, min = math.floor, math.max, math.min

Data.VERSION = 2

local DEFAULTS = {
	announce = true, -- a line in chat on every level-up
	compare = true, -- ... with how it compares to the level before
	mini = true, -- the mini tracker
	miniLocked = false,
	miniAtMax = false, -- keep the mini tracker at max level
	miniHideCombat = false,
	scale = 1,
	theme = "classic",
	tab = "overview",
}

local function copyDefaults(target, defaults)
	for k, v in pairs(defaults) do
		if target[k] == nil then
			target[k] = v
		end
	end
end

local function newChar(key)
	local name, realm = key:match("^([^%-]+)%-(.+)$")
	return { name = name or key, realm = realm or "", levels = {} }
end

-- Level Time Tracker 1.x kept one table per character ("Name-Realm" at the top, or under profile.characters in some
-- builds) with levelTimes[level] = seconds (0 when it didn't time the level) and a window table "ui".
local function importLegacy(chars, key, old)
	if type(key) ~= "string" or not key:find("-", 1, true) or type(old) ~= "table" then
		return false
	end
	if type(old.levelTimes) ~= "table" and not old.currentLevel then
		return false
	end
	local c = chars[key] or newChar(key)
	chars[key] = c
	local level = tonumber(old.currentLevel)
	if level and level > (c.level or 0) then
		c.level = floor(level)
	end
	local maxLevel = tonumber(old.maxLevel)
	if maxLevel and maxLevel > (c.maxLevel or 0) then
		c.maxLevel = floor(maxLevel)
	end
	for k, t in pairs(type(old.levelTimes) == "table" and old.levelTimes or {}) do
		local lvl = tonumber(k)
		t = tonumber(t)
		if lvl and lvl >= 1 and lvl < 1000 and lvl == floor(lvl) then
			local e = c.levels[lvl]
			-- Negative or absurd times came from a clock that didn't survive restarting the computer: unknown.
			if t and t >= 1 and t < 365 * 86400 then
				if not (e and e.t) then
					c.levels[lvl] = { t = floor(t + 0.5), legacy = true }
				end
			elseif not e then
				c.levels[lvl] = { legacy = true }
			end
		end
	end
	local started = tonumber(old.startedAt)
	local startLevel = tonumber(old.startLevel)
	if not c.first and (started or startLevel) then
		c.first = { level = startLevel and floor(startLevel) or nil, at = started }
	end
	return true
end

local function migrate(old)
	local db = { version = Data.VERSION, settings = {}, chars = {} }
	local imported = 0
	for key, value in pairs(old) do
		if key ~= "ui" and key ~= "profile" and importLegacy(db.chars, key, value) then
			imported = imported + 1
		end
	end
	local profile = type(old.profile) == "table" and old.profile.characters
	if type(profile) == "table" then
		for key, value in pairs(profile) do
			if importLegacy(db.chars, key, value) then
				imported = imported + 1
			end
		end
	end
	db.migratedFrom = 1
	db.migratedChars = imported
	return db
end

function Data.Init()
	local db = LevelTimeTrackerDB
	if type(db) ~= "table" then
		db = { version = Data.VERSION, settings = {}, chars = {} }
	elseif db.version == nil then
		db = migrate(db)
	end
	db.settings = type(db.settings) == "table" and db.settings or {}
	db.chars = type(db.chars) == "table" and db.chars or {}
	copyDefaults(db.settings, DEFAULTS)
	if type(db.settings.pos) ~= "table" then
		db.settings.pos = {}
	end
	db.version = Data.VERSION
	LevelTimeTrackerDB = db
	ns.db = db
	ns.S = db.settings
end

function Data.Defaults()
	return DEFAULTS
end

-- "Name-Realm", as Level Time Tracker 1.x keyed characters.
function Data.Key(name, realm)
	name = name or UnitName("player")
	realm = realm or (GetNormalizedRealmName and GetNormalizedRealmName()) or (GetRealmName and GetRealmName()) or "?"
	return name .. "-" .. (realm:gsub("%s", ""))
end

function Data.Get(key)
	return ns.db and ns.db.chars[key]
end

-- The character's record, made on first sight.
function Data.Ensure(key)
	local chars = ns.db.chars
	local c = chars[key]
	if not c then
		c = newChar(key)
		chars[key] = c
	end
	c.levels = type(c.levels) == "table" and c.levels or {}
	return c
end

function Data.Forget(key)
	if ns.db and ns.db.chars[key] then
		ns.db.chars[key] = nil
		ns:Fire("DATA_CHANGED", key)
		return true
	end
	return false
end

-- Every character, sorted: the most recently played first.
function Data.Characters()
	local list = {}
	for key, c in pairs(ns.db and ns.db.chars or {}) do
		c.key = key
		list[#list + 1] = c
	end
	table.sort(list, function(a, b)
		local la, lb = a.lastSeen or 0, b.lastSeen or 0
		if la ~= lb then
			return la > lb
		end
		return a.key < b.key
	end)
	return list
end

-- Levels as a list, highest first: { level, t, at, played, zone, skipped, legacy }.
function Data.Levels(c)
	local list = {}
	for lvl, e in pairs(c and c.levels or {}) do
		lvl = tonumber(lvl)
		if lvl and type(e) == "table" then
			list[#list + 1] = { level = lvl, t = e.t, at = e.at, played = e.played, zone = e.zone, skipped = e.skipped,
				legacy = e.legacy }
		end
	end
	table.sort(list, function(a, b)
		return a.level > b.level
	end)
	return list
end

-- A level that has a real time (not skipped, not untracked).
function Data.Timed(e)
	return e ~= nil and not e.skipped and e.t ~= nil and e.t > 0
end

-- count, total, average, fastest/slowest { level, t }, the highest timed level and how many levels have no time.
function Data.Stats(c)
	local s = { count = 0, total = 0, skipped = 0, untracked = 0 }
	for lvl, e in pairs(c and c.levels or {}) do
		lvl = tonumber(lvl)
		if lvl and type(e) == "table" then
			if Data.Timed(e) then
				s.count = s.count + 1
				s.total = s.total + e.t
				if not s.fastest or e.t < s.fastest.t or (e.t == s.fastest.t and lvl < s.fastest.level) then
					s.fastest = { level = lvl, t = e.t }
				end
				if not s.slowest or e.t > s.slowest.t or (e.t == s.slowest.t and lvl < s.slowest.level) then
					s.slowest = { level = lvl, t = e.t }
				end
				s.top = max(s.top or 0, lvl)
			elseif e.skipped then
				s.skipped = s.skipped + 1
			else
				s.untracked = s.untracked + 1
			end
		end
	end
	s.average = s.count > 0 and s.total / s.count or nil
	return s
end

-- How much longer (+) or shorter (-) level n took than level n - 1, when both have a time.
function Data.Change(c, level)
	local e, prev = c.levels[level], c.levels[level - 1]
	if Data.Timed(e) and Data.Timed(prev) then
		return e.t - prev.t
	end
end

-- /played in total when the character reached `level` (known when the level before it was recorded).
function Data.PlayedAt(c, level)
	local e = c.levels[level - 1]
	return e and e.played
end

function Data.Total()
	local chars, levels = 0, 0
	for _, c in pairs(ns.db and ns.db.chars or {}) do
		chars = chars + 1
		for _, e in pairs(c.levels or {}) do
			if Data.Timed(e) then
				levels = levels + 1
			end
		end
	end
	return chars, levels
end
