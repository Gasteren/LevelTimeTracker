-- Data.lua: the saved variables. Settings, and every character, under "Name-Realm" ("Name-Surname" on WoW: Forever):
--   name, surname (WoW: Forever's second name), realm, guid: who it is (see Data.Me)
--   levels[n] = { t = seconds spent on level n, at = when level n + 1 was reached (realm time),
--                 played = /played in total at that moment, zone = where, skipped = true (no time on it),
--                 legacy = true (recorded by Level Time Tracker 1.x, which only kept the time) }
local ADDON, ns = ...
local L, U = ns.L, ns.U

local Data = {}
ns.Data = Data

local floor, max, min, abs = math.floor, math.max, math.min, math.abs

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

---------------------------------------------------------------------------
-- Who is playing. Realm clients name a character "Name-Realm". WoW: Forever gives every character a two-part name,
-- unique in the region ("Drek Stone"): the second name takes the place of the realm. Forever's realm functions name a
-- server that many characters with the same first name share ("CAMWOWEU5Realm4PVP"), and since November 2026 they
-- answer "".
---------------------------------------------------------------------------
local function plainText(v)
	v = U.Plain(v)
	if type(v) == "string" then
		v = v:gsub("^%s+", ""):gsub("%s+$", "")
		if v ~= "" then
			return v
		end
	end
end

function Data.TwoPartNames()
	local enabled = RegionalUniqueNamesEnabled
	if type(enabled) ~= "function" then
		return false
	end
	local ok, on = pcall(enabled)
	return ok and U.Plain(on) == true
end

-- { name, surname (WoW: Forever's second name), realm, guid }, each nil when the game doesn't say.
function Data.Me()
	local name, second
	if UnitNameUnmodified then
		name, second = UnitNameUnmodified("player")
	end
	name, second = plainText(name), plainText(second)
	name = name or plainText((UnitName("player")))
	local realm = plainText(GetNormalizedRealmName and GetNormalizedRealmName())
		or plainText(GetRealmName and GetRealmName())
	realm = realm and (realm:gsub("%s", ""))
	local surname
	if Data.TwoPartNames() or not realm then
		surname = second
		if not surname and name then
			-- Both names in one string, "Drek Stone".
			local first, last = name:match("^(%S+)%s+(%S+)$")
			if first then
				name, surname = first, last
			end
		end
	end
	return { name = name, surname = surname, realm = realm, guid = plainText(UnitGUID and UnitGUID("player")) }
end

-- "Name-Realm", as Level Time Tracker 1.x keyed characters, or "Name-Surname" on WoW: Forever.
function Data.Key(me)
	me = me or Data.Me()
	local second = me.surname or me.realm
	if second then
		return (me.name or "?") .. "-" .. second
	end
	return me.guid or me.name or "?"
end

-- "Drek Stone" on WoW: Forever, otherwise the name.
function Data.FullName(c)
	if c.surname then
		return (c.name or "?") .. " " .. c.surname
	end
	return c.name or "?"
end

-- The realm shown next to the name (none for a two-part name).
function Data.Realm(c)
	return not c.surname and c.realm or ""
end

-- The character as lists and questions name it: "Drek Stone", or "Frost - Lightbringer".
function Data.Label(c)
	local realm = Data.Realm(c)
	if realm ~= "" then
		return Data.FullName(c) .. " - " .. realm
	end
	return Data.FullName(c)
end

-- The key of another record of this GUID: the same character, saved under an older name.
function Data.FindGUID(guid, except)
	for key, c in pairs(ns.db.chars) do
		if key ~= except and type(c) == "table" and c.guid == guid then
			return key
		end
	end
end

function Data.Rekey(from, to)
	local chars = ns.db.chars
	local c = chars[from]
	chars[from], chars[to] = nil, c
	c.key = to
	return c
end

-- Another character took the name of the record at `key` (renamed or deleted since): the record moves to the key of
-- its own GUID, where that character finds it again.
function Data.MoveAside(key)
	local chars = ns.db.chars
	local c = chars[key]
	local there = chars[c.guid]
	if type(there) == "table" and type(there.levels) == "table" then
		Data.Merge(there, c)
		chars[key] = nil
		return there
	end
	return Data.Rekey(key, c.guid)
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

---------------------------------------------------------------------------
-- One character, two records: after a rename, or when the game changed how it names characters (Level Time Tracker
-- 2.0.0 on WoW: Forever), the character was saved under a new key. The older record is joined back in.
---------------------------------------------------------------------------
-- Seconds the saved values may differ by (each one is rounded, and a level-up is timed on this computer).
local SAME_PLAYED = 5
-- In its first hour, a character's /played is too small a number to tell it from another one.
local MIN_PLAYED = 3600

local function num(v)
	return type(v) == "number" and v or nil
end

-- /played in total when the character reached `level`, as record c knows it. /played and the time on the level grow
-- together, so their difference is the same in every answer while the character is on that level.
function Data.PlayedAtLevel(c, level)
	local played, onLevel = num(c.played), num(c.levelPlayed)
	if c.level == level and played and onLevel then
		return played - onLevel
	end
	local e = c.levels[level]
	if type(e) == "table" and num(e.played) and num(e.t) then
		return e.played - e.t
	end
	local before = c.levels[level - 1]
	return type(before) == "table" and num(before.played) or nil
end

local function sameName(a, b)
	return type(a) == "string" and type(b) == "string" and a:lower() == b:lower()
end

-- Is `other` an earlier record of character c (whose /played is known)? The same GUID says so. A record saved before
-- characters had a GUID needs the same name and class, and the same /played, to the second, when it reached its last
-- level; /played can't shrink or grow faster than the clock since.
function Data.SameCharacter(c, other)
	if c.guid and other.guid then
		return c.guid == other.guid
	end
	if not sameName(c.name, other.name) or (c.class and other.class and c.class ~= other.class) then
		return false
	end
	local level = tonumber(other.level)
	if not level or not c.level or level > c.level then
		return false
	end
	local played, before = num(c.played), num(other.played)
	if played and before then
		local now, at = num(c.playedAt), num(other.playedAt)
		if before > played + SAME_PLAYED or (now and at and played - before > now - at + SAME_PLAYED) then
			return false
		end
	end
	local mine, theirs = Data.PlayedAtLevel(c, level), Data.PlayedAtLevel(other, level)
	return mine ~= nil and theirs ~= nil and theirs >= MIN_PLAYED and abs(mine - theirs) <= SAME_PLAYED
end

-- Adds what `from` knows to c: the levels c has no time for, and an earlier start.
function Data.Merge(c, from)
	for lvl, e in pairs(from.levels) do
		local mine = c.levels[lvl]
		if type(e) == "table" and (type(mine) ~= "table" or (not Data.Timed(mine) and Data.Timed(e))) then
			c.levels[lvl] = e
		end
	end
	local f, g = from.first, c.first
	if type(f) == "table" and f.level and not (type(g) == "table" and g.level and g.level <= f.level) then
		c.first = f
	end
	c.class, c.race, c.faction = c.class or from.class, c.race or from.race, c.faction or from.faction
end

-- Joins every earlier record of character c into c, and returns them.
function Data.JoinEarlier(c)
	local joined = {}
	local chars = ns.db.chars
	local again = true
	while again do
		again = false
		for key, other in pairs(chars) do
			if other ~= c and type(other) == "table" and type(other.levels) == "table" and Data.SameCharacter(c, other) then
				Data.Merge(c, other)
				chars[key] = nil
				joined[#joined + 1] = other
				-- What it brought may tie in another one (an older level).
				again = true
				break
			end
		end
	end
	return joined
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
