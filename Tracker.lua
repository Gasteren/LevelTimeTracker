-- Tracker.lua: times the levels. At login the game is asked for /played (time played in total and on this level, which
-- the realm keeps); from then on the clock runs here, so every level-up is timed to the second, the level you were on
-- when you installed the addon is timed in full, and time spent logged out never counts.
local ADDON, ns = ...
local L, U, C, COLOR = ns.L, ns.U, ns.C, ns.COLOR
local Data = ns.Data

local Tracker = ns:NewModule("Tracker")

local floor, max, min, abs, format = math.floor, math.max, math.min, math.abs, string.format

-- How long after logging out a /reload still continues the session (XP per hour) and the clock.
local RELOAD_GRACE = 300
-- XP per hour needs this much of the session first (a quest turned in right after login is not a pace).
local MIN_RATE_TIME = 120
-- Two level-ups closer together than this are one jump: the level in between was skipped.
local SAME_MOMENT = 2

Tracker.level = 0
Tracker.session = { start = 0, xp = 0, levels = 0 }
Tracker.xp = { cur = 0, max = 0, level = 0 }

local function readXP()
	local cur = tonumber(U.Plain(UnitXP("player"))) or 0
	local maxXP = tonumber(U.Plain(UnitXPMax("player"))) or 0
	return cur, maxXP
end

function Tracker.MaxLevel()
	if GameRulesUtil and GameRulesUtil.GetEffectiveMaxLevelForPlayer then
		local ok, v = pcall(GameRulesUtil.GetEffectiveMaxLevelForPlayer)
		if ok and type(v) == "number" and v > 0 then
			return v
		end
	end
	local fns = { GetMaxLevelForPlayerExpansion or false, GetMaxPlayerLevel or false }
	for i = 1, #fns do
		if fns[i] then
			local ok, v = pcall(fns[i])
			if ok and type(v) == "number" and v > 0 then
				return v
			end
		end
	end
	return 60
end

function Tracker:AtMax()
	return self.level >= Tracker.MaxLevel()
end

function Tracker:XPDisabled()
	return IsXPUserDisabled ~= nil and IsXPUserDisabled() and true or false
end

---------------------------------------------------------------------------
-- /played. The game prints the answer in chat; when we ask, the chat windows don't get it.
---------------------------------------------------------------------------
local muted = {}
-- Answers still to come for the /played requests made so far, by any addon or the /played command: the chat windows
-- stay muted until every answer that may arrive while they are muted has arrived (or 10 seconds have passed).
local outstanding = 0

if hooksecurefunc and RequestTimePlayed then
	hooksecurefunc("RequestTimePlayed", function()
		outstanding = outstanding + 1
	end)
end

local function restoreChat()
	Tracker.muting = false
	outstanding = 0
	for i = #muted, 1, -1 do
		local frame = muted[i]
		muted[i] = nil
		if not frame:IsEventRegistered("TIME_PLAYED_MSG") then
			frame:RegisterEvent("TIME_PLAYED_MSG")
		end
	end
end

local function muteChat()
	local seen = {}
	local function mute(frame)
		if type(frame) == "table" and not seen[frame] and frame.IsEventRegistered and frame:IsEventRegistered("TIME_PLAYED_MSG") then
			seen[frame] = true
			frame:UnregisterEvent("TIME_PLAYED_MSG")
			muted[#muted + 1] = frame
		end
	end
	for _, name in ipairs(type(CHAT_FRAMES) == "table" and CHAT_FRAMES or {}) do
		mute(_G[name])
	end
	for i = 1, NUM_CHAT_WINDOWS or 10 do
		mute(_G["ChatFrame" .. i])
	end
end

-- loud: the game prints the answer as for /played (the /ltt played command).
function Tracker:RequestPlayed(loud)
	if not RequestTimePlayed then
		return false
	end
	local t = GetTime()
	if not loud and self.lastRequest and t - self.lastRequest < 10 then
		return false
	end
	self.lastRequest = t
	if loud then
		restoreChat()
	elseif not self.muting then
		muteChat()
		self.muting = #muted > 0
		-- Never leave the chat deaf to /played, even if the answer doesn't come.
		C_Timer.After(10, function()
			if Tracker.muting then
				restoreChat()
			end
		end)
	end
	RequestTimePlayed()
	return true
end

function Tracker:SetSync(total, levelTime)
	self.sync = { total = total, level = levelTime, at = GetTime() }
	local c = self.char
	c.played, c.levelPlayed, c.playedAt = floor(total + 0.5), floor(levelTime + 0.5), ns.Now()
	ns:Fire("PLAYED")
end

function Tracker:OnPlayed(total, levelTime)
	total, levelTime = tonumber(U.Plain(total)), tonumber(U.Plain(levelTime))
	outstanding = max(0, outstanding - 1)
	if self.muting and outstanding == 0 then
		-- The chat windows get the event back after this one has passed them by.
		C_Timer.After(0, restoreChat)
	end
	if not total or not levelTime or not self.char then
		return
	end
	-- A level-up before the first /played answer: /played at that moment is the total minus the time on the new level,
	-- and the level took the difference to /played when it was reached.
	local lvl = self.pending
	if lvl then
		self.pending = nil
		local e = self.char.levels[lvl]
		if e and not e.t then
			local ding = total - levelTime
			e.played = floor(ding + 0.5)
			local reached = Data.PlayedAt(self.char, lvl)
			if reached and ding - reached >= SAME_MOMENT then
				e.t = floor(ding - reached + 0.5)
			end
		end
	end
	self:SetSync(total, levelTime)
end

-- Seconds played on this level (nil until /played answered).
function Tracker:LevelTime()
	local s = self.sync
	if s then
		return s.level + (GetTime() - s.at)
	end
end

-- Seconds played in total: live once /played answered, the last known total before that.
function Tracker:Played()
	local s = self.sync
	if s then
		return s.total + (GetTime() - s.at)
	end
	return self.char and self.char.played
end

function Tracker:Synced()
	return self.sync ~= nil
end

---------------------------------------------------------------------------
-- Experience and the session
---------------------------------------------------------------------------
-- cur, max, rested XP, fraction of the level done
function Tracker:XP()
	local cur, maxXP = readXP()
	local rested = tonumber(U.Plain(GetXPExhaustion and GetXPExhaustion())) or 0
	return cur, maxXP, rested, maxXP > 0 and min(1, cur / maxXP) or 0
end

function Tracker:SessionTime()
	return max(0, GetTime() - self.session.start)
end

-- XP per hour this session (nil while there is too little to go on).
function Tracker:Rate()
	local t = self:SessionTime()
	if t < MIN_RATE_TIME or self.session.xp <= 0 then
		return nil
	end
	return self.session.xp / t * 3600
end

-- Seconds to the next level at this session's pace.
function Tracker:ETA()
	if self:AtMax() or self:XPDisabled() then
		return nil
	end
	local rate = self:Rate()
	local cur, maxXP = readXP()
	if not rate or maxXP <= 0 then
		return nil
	end
	return max(0, maxXP - cur) / rate * 3600
end

function Tracker:OnXP()
	if not self.char then
		return
	end
	local unitLevel = tonumber(U.Plain(UnitLevel("player")))
	if unitLevel and unitLevel > self.level then
		self:LevelReached(unitLevel)
	end
	local cur, maxXP = readXP()
	local s = self.xp
	local gained
	if self.level > s.level then
		-- Levelled since the last reading: the rest of the old level, then the new one's XP.
		gained = max(0, s.max - s.cur) + cur
		s.level = self.level
	elseif cur < s.cur then
		-- The XP rolled over before the level-up event came in.
		gained = max(0, s.max - s.cur) + cur
		s.level = self.level + 1
	else
		gained = cur - s.cur
	end
	if gained > 0 then
		self.session.xp = self.session.xp + gained
	end
	s.cur, s.max = cur, maxXP
	self.char.xpCur, self.char.xpMax = cur, maxXP
	ns:Fire("XP")
end

---------------------------------------------------------------------------
-- Level-ups
---------------------------------------------------------------------------
-- old: the level the time is for (the first of the levels gained), new: the level reached.
function Tracker:Announce(old, new)
	if not ns.S.announce then
		return
	end
	local c = self.char
	local e = c.levels[old]
	local msg, ending
	if Data.Timed(e) then
		local took = C(COLOR.white, U.DurationLong(e.t))
		local diff = ns.S.compare and new - old == 1 and Data.Change(c, old)
		if diff and abs(diff) >= 1 then
			local how = diff < 0 and C(COLOR.green, format(L["%s faster"], U.DurationLong(-diff)))
				or C(COLOR.red, format(L["%s slower"], U.DurationLong(diff)))
			msg = format(L["Level %d in %s, %s than the level before"], new, took, how)
		else
			msg = format(L["Level %d in %s"], new, took)
		end
		ending = "."
	else
		msg, ending = format(L["Level %d"], new), "!"
	end
	if new - old > 1 then
		msg = msg .. " " .. format(L["(%d levels at once)"], new - old)
	end
	msg = msg .. ending
	if new >= Tracker.MaxLevel() then
		local played = self:Played()
		msg = msg .. " " .. (played and format(L["That's max level, after %s played."], C(COLOR.white, U.DurationLong(played)))
			or L["That's max level!"])
	end
	ns.Print(msg)
end

-- The game sends one event per level: levels gained together get one line in chat.
function Tracker:QueueAnnounce(old, new)
	local q = self.queued
	if q then
		q.to = new
		return
	end
	self.queued = { from = old, to = new }
	C_Timer.After(0.3, function()
		local pendingLine = Tracker.queued
		Tracker.queued = nil
		if pendingLine then
			Tracker:Announce(pendingLine.from, pendingLine.to)
		end
	end)
end

function Tracker:LevelReached(newLevel)
	newLevel = tonumber(newLevel)
	local old = self.level
	local c = self.char
	if not c or not newLevel or newLevel <= old or old <= 0 then
		return
	end
	local t, stamp = GetTime(), ns.Now()
	local zone = U.Plain(GetRealZoneText and GetRealZoneText())
	if zone == "" then
		zone = nil
	end
	local played, spent
	if self.sync then
		local since = t - self.sync.at
		played = floor(self.sync.total + since + 0.5)
		spent = self.sync.level + since
	end
	local e = { at = stamp, played = played, zone = zone }
	if spent and spent < SAME_MOMENT and self.lastLevelUp and t - self.lastLevelUp < SAME_MOMENT then
		e.t, e.skipped = 0, true
	elseif spent then
		e.t = max(1, floor(spent + 0.5))
	end
	c.levels[old] = e
	for lvl = old + 1, newLevel - 1 do
		c.levels[lvl] = { t = 0, skipped = true, at = stamp, played = played, zone = zone }
	end
	self.level = newLevel
	self.lastLevelUp = t
	c.level = newLevel
	c.maxLevel = Tracker.MaxLevel()
	if self.sync then
		self.sync = { total = played, level = 0, at = t }
		c.played, c.levelPlayed, c.playedAt = played, 0, stamp
	elseif not e.skipped then
		self.pending = old
	end
	self.session.levels = self.session.levels + (newLevel - old)
	self:QueueAnnounce(old, newLevel)
	ns:Fire("LEVEL_UP", newLevel, old)
end

---------------------------------------------------------------------------
-- Login, reload, logout
---------------------------------------------------------------------------
function Tracker:Enable()
	local key = Data.Key()
	local c = Data.Ensure(key)
	local level = tonumber(U.Plain(UnitLevel("player"))) or 1
	local _, classFile = UnitClass("player")
	classFile = U.Plain(classFile)
	-- A new character with the name of a deleted one starts over.
	if c.level and (level < c.level or (c.class and classFile and c.class ~= classFile)) then
		c.levels, c.first, c.played, c.levelPlayed, c.playedAt, c.session = {}, nil, nil, nil, nil, nil
	end
	c.key = key
	c.name = U.Plain(UnitName("player")) or c.name
	c.class = classFile or c.class
	c.race = U.Plain((UnitRace("player"))) or c.race
	c.faction = U.Plain((UnitFactionGroup("player"))) or c.faction
	c.level = level
	c.maxLevel = Tracker.MaxLevel()
	c.first = c.first or { level = level, at = ns.Now() }
	c.lastSeen = ns.Now()
	self.key, self.char, self.level = key, c, level
	local cur, maxXP = readXP()
	self.xp = { cur = cur, max = maxXP, level = level }
	c.xpCur, c.xpMax = cur, maxXP
	self.session = { start = GetTime(), xp = 0, levels = 0 }

	ns:RegisterEvent("PLAYER_ENTERING_WORLD", function(_, isInitialLogin, isReloadingUi)
		Tracker:OnEnteringWorld(isInitialLogin, isReloadingUi)
	end)
	ns:RegisterEvent("TIME_PLAYED_MSG", function(_, total, levelTime)
		Tracker:OnPlayed(total, levelTime)
	end)
	ns:RegisterEvent("PLAYER_LEVEL_UP", function(_, newLevel)
		Tracker:LevelReached(U.Plain(newLevel))
	end)
	ns:RegisterEvent("PLAYER_LEVEL_CHANGED", function(_, _, newLevel, real)
		if real ~= false then
			Tracker:LevelReached(U.Plain(newLevel))
		end
	end)
	ns:RegisterEvent("PLAYER_XP_UPDATE", function(_, unit)
		if unit == nil or unit == "player" then
			Tracker:OnXP()
		end
	end)
	local function changed()
		ns:Fire("XP")
	end
	ns:RegisterEvent("UPDATE_EXHAUSTION", changed)
	ns:RegisterEvent("PLAYER_UPDATE_RESTING", changed)
	ns:RegisterEvent("ENABLE_XP_GAIN", changed)
	ns:RegisterEvent("DISABLE_XP_GAIN", changed)
	ns:RegisterEvent("PLAYER_LOGOUT", function()
		Tracker:OnLogout()
	end)
end

function Tracker:OnEnteringWorld(_, isReloadingUi)
	if self.entered then
		return
	end
	self.entered = true
	local c = self.char
	local t = ns.Now()
	local saved = c.session
	c.session = nil
	if isReloadingUi and type(saved) == "table" and saved.savedAt and t - saved.savedAt < RELOAD_GRACE then
		local away = max(0, t - saved.savedAt)
		self.session = { start = GetTime() - (saved.elapsed or 0) - away, xp = saved.xp or 0, levels = saved.levels or 0 }
	end
	if isReloadingUi and c.playedAt and c.played and c.levelPlayed and t - c.playedAt < RELOAD_GRACE then
		local away = max(0, t - c.playedAt)
		self:SetSync(c.played + away, c.levelPlayed + away)
	else
		self:RequestPlayed()
		-- One more try when the realm didn't answer.
		C_Timer.After(20, function()
			if not Tracker.sync then
				Tracker.lastRequest = nil
				Tracker:RequestPlayed()
			end
		end)
	end
end

function Tracker:OnLogout()
	local c = self.char
	if not c then
		return
	end
	local stamp = ns.Now()
	c.lastSeen = stamp
	if self.sync then
		c.played, c.levelPlayed, c.playedAt = floor(self:Played() + 0.5), floor(self:LevelTime() + 0.5), stamp
	end
	c.xpCur, c.xpMax = readXP()
	c.session = { xp = self.session.xp, levels = self.session.levels, elapsed = floor(self:SessionTime() + 0.5),
		savedAt = stamp }
end
