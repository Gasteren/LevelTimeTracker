-- test_main.lua: Level Time Tracker's tests. Each test runs in a fresh game (run_tests.py), once as World of Warcraft:
-- Midnight and once as World of Warcraft: Forever.
local KEY = "Frost-Lightbringer"

local function char()
	return NS.Tracker.char
end

local function tracker()
	return NS.Tracker
end

-- A saved character (the shape Level Time Tracker 2 saves).
local function savedChar(fields)
	local c = { name = "Frost", realm = "Lightbringer", class = "MAGE", race = "Human", level = MOCK.player.level, levels = {} }
	for k, v in pairs(fields or {}) do c[k] = v end
	return c
end

local function db(chars, settings)
	return { version = 2, settings = settings or { hello = "2.0.0" }, chars = chars or {} }
end

---------------------------------------------------------------------------
-- The clock
---------------------------------------------------------------------------
T("first login asks the game for /played without printing it in chat", function()
	Boot()
	Eq(MOCK.requests, 1, "one /played request")
	Ok(tracker():Synced(), "the answer came in")
	Eq(MOCK.chatPlayed, 0, "no chat window printed /played")
	Ok(ChatFrame1:IsEventRegistered("TIME_PLAYED_MSG"), "the chat window gets /played back")
	Ok(ChatFrame3:IsEventRegistered("TIME_PLAYED_MSG"), "every chat window gets it back")
	-- The player's own /played prints as usual.
	MOCK.Fire("TIME_PLAYED_MSG", MOCK.Played())
	Eq(MOCK.chatPlayed, 3, "the player's /played reaches the chat windows")
end)

T("another addon asking for /played at login doesn't make ours print", function()
	-- The other addon asks a moment before this one: its answer comes in a few frames before ours.
	Boot({ wait = 0, afterLogin = function()
		RequestTimePlayed()
		MOCK.Advance(0.05)
	end })
	MOCK.Advance(1, 0.01)
	Eq(MOCK.requests, 2, "the other addon's request and ours")
	Eq(MOCK.chatPlayed, 0, "neither answer printed")
	Ok(ChatFrame1:IsEventRegistered("TIME_PLAYED_MSG"), "the chat windows got /played back after the last answer")
	RequestTimePlayed()
	MOCK.Advance(1)
	Eq(MOCK.chatPlayed, 3, "the player's own /played prints")
end)

T("another addon asking for /played while ours is on its way", function()
	Boot({ wait = 0.1 })
	RequestTimePlayed()
	MOCK.Advance(0.35)
	Ok(tracker():Synced(), "our answer came in")
	Ok(not ChatFrame1:IsEventRegistered("TIME_PLAYED_MSG"), "still muted: one more answer to come")
	MOCK.Advance(0.2)
	Eq(MOCK.chatPlayed, 0, "neither answer printed")
	Ok(ChatFrame1:IsEventRegistered("TIME_PLAYED_MSG"), "unmuted after the last answer")
end)

T("the chat windows get /played back even if the realm never answers, and the addon asks again", function()
	MOCK.playedNoAnswer = true
	Boot({ wait = 0.5 })
	Ok(not ChatFrame1:IsEventRegistered("TIME_PLAYED_MSG"), "muted while waiting")
	MOCK.Advance(10)
	Ok(ChatFrame1:IsEventRegistered("TIME_PLAYED_MSG"), "unmuted after 10 seconds without an answer")
	MOCK.playedNoAnswer = false
	MOCK.Advance(10)
	Eq(MOCK.requests, 2, "asked a second time")
	MOCK.Advance(1)
	Ok(tracker():Synced(), "the second answer came in")
	Eq(MOCK.chatPlayed, 0, "still nothing printed")
	MOCK.Advance(1)
	Ok(ChatFrame1:IsEventRegistered("TIME_PLAYED_MSG"), "unmuted again")
end)

T("a level-up records the time on the level to the second, with the date, /played and zone", function()
	Boot()
	Chat()
	MOCK.Advance(1200)
	MOCK.LevelUp()
	local e = char().levels[12]
	Ok(e, "level 12 recorded")
	-- 900 s on the level at login (the realm's count) + 1 s of login + 1200 s.
	Eq(e.t, 2101, "time on level 12")
	Eq(e.played, 5 * 3600 + 1201, "/played when level 13 was reached")
	Eq(e.at, MOCK.ServerTime(), "date")
	Eq(e.zone, "Elwynn Forest", "zone")
	Eq(char().level, 13, "the character is level 13")
	Near(tracker():LevelTime(), 0, 0.01, "the clock starts again on level 13")
	MOCK.Advance(0.5)
	Has(Chat(), "Level Time Tracker: Level 13 in 35m 01s.", "chat line")
end)

T("the next level is compared with the one before", function()
	Boot()
	MOCK.Advance(1200)
	MOCK.LevelUp()
	MOCK.Advance(0.5)
	Chat()
	MOCK.Advance(999.5)
	MOCK.LevelUp()
	Eq(char().levels[13].t, 1000)
	MOCK.Advance(0.5)
	Has(Chat(), "Level 14 in 16m 40s, 18m 21s faster than the level before.")
	MOCK.Advance(1099.5)
	MOCK.LevelUp()
	MOCK.Advance(0.5)
	Has(Chat(), "Level 15 in 18m 20s, 1m 40s slower than the level before.")
	NS.S.compare = false
	MOCK.Advance(59.5)
	MOCK.LevelUp()
	MOCK.Advance(0.5)
	local line = Chat()
	Has(line, "Level 16 in 1m 00s.")
	HasNot(line, "than the level before")
	NS.S.announce = false
	MOCK.LevelUp()
	MOCK.Advance(0.5)
	Eq(Chat(), "", "nothing in chat with announcing off")
end)

T("PLAYER_LEVEL_UP and PLAYER_LEVEL_CHANGED for one level-up count once", function()
	Boot()
	Chat()
	MOCK.Advance(30)
	MOCK.LevelUp()
	MOCK.Advance(0.5)
	local _, count = Chat():gsub("Level 13", "")
	Eq(count, 1, "one chat line")
	Eq(tracker().session.levels, 1, "one level this session")
	MOCK.noLevelChanged = true
	MOCK.Advance(29.5)
	MOCK.LevelUp()
	Eq(char().levels[13].t, 30, "PLAYER_LEVEL_UP alone works")
	MOCK.noLevelChanged = false
	-- Only PLAYER_LEVEL_CHANGED (a level that arrives that way): still recorded.
	MOCK.Advance(40)
	local p = MOCK.player
	p.level = 15
	p.xp, p.xpMax = 0, MOCK.XPFor(15)
	MOCK.Fire("PLAYER_LEVEL_CHANGED", 14, 15, true)
	Eq(char().levels[14].t, 40, "PLAYER_LEVEL_CHANGED alone works")
	-- Level sync and the like (real == false) is not a level-up.
	MOCK.Fire("PLAYER_LEVEL_CHANGED", 15, 20, false)
	Eq(char().level, 15, "a scaled level is ignored")
end)

T("XP rolling over before the level-up event is counted once", function()
	MOCK.order = "xpFirst"
	Boot()
	local max12 = MOCK.player.xpMax
	MOCK.GainXP(max12 - 100)
	Eq(tracker().session.xp, max12 - 100)
	MOCK.Advance(60)
	MOCK.GainXP(300)
	Eq(char().level, 13)
	Eq(tracker().session.xp, max12 + 200, "the rest of level 12 and 200 into level 13")
	MOCK.GainXP(50)
	Eq(tracker().session.xp, max12 + 250, "no double count afterwards")
	Eq(char().levels[12].t, 961, "the level is timed too")
end)

T("XP after the level-up event is counted once", function()
	MOCK.order = "levelFirst"
	Boot()
	local max12 = MOCK.player.xpMax
	MOCK.GainXP(max12 - 100)
	MOCK.GainXP(300)
	MOCK.GainXP(50)
	Eq(tracker().session.xp, max12 + 250)
end)

T("several levels at once: the first is timed, the levels in between are skipped", function()
	Boot()
	Chat()
	MOCK.Advance(100)
	MOCK.GainXP(MOCK.XPFor(12) + MOCK.XPFor(13) + MOCK.XPFor(14) + 10)
	Eq(char().level, 15)
	Eq(char().levels[12].t, 1001, "level 12 timed")
	Ok(char().levels[13].skipped and char().levels[14].skipped, "13 and 14 skipped")
	Eq(tracker().session.levels, 3)
	MOCK.Advance(0.5)
	local line = Chat()
	Has(line, "Level 15 in 16m 41s (3 levels at once).", "one line for the three levels")
	HasNot(line, "Level 14")
end)

T("several levels at once in one PLAYER_LEVEL_UP", function()
	MOCK.oneLevelUpEvent = true
	MOCK.noLevelChanged = true
	Boot()
	MOCK.Advance(100)
	MOCK.GainXP(MOCK.XPFor(12) + MOCK.XPFor(13) + 10)
	Eq(char().level, 14)
	Eq(char().levels[12].t, 1001)
	Ok(char().levels[13].skipped, "13 skipped")
end)

T("a level-up before /played answered is timed from the /played totals", function()
	MOCK.playedDelay = 5
	-- Level 12 was reached at /played 17100 (18000 now, 900 of it on level 12).
	local c = savedChar({ level = 12, levels = { [11] = { t = 800, played = 17100 } } })
	Boot({ db = db({ [KEY] = c }), wait = 0.1 })
	Ok(not tracker():Synced(), "no answer yet")
	MOCK.Advance(1)
	MOCK.LevelUp()
	Eq(char().levels[12].t, nil, "not known yet")
	MOCK.Advance(5)
	Ok(tracker():Synced(), "answered")
	Near(char().levels[12].t, 901, 1, "filled in from the totals")
	Near(char().levels[12].played, 18001, 1)
end)

T("a fresh login asks /played again: time logged out never counts", function()
	-- Logged out a day ago with 100 s on the level; the realm says 900 s (it only counts time played).
	local c = savedChar({ played = 17000, levelPlayed = 100, playedAt = MOCK.ServerTime() - 86400 })
	Boot({ db = db({ [KEY] = c }) })
	Eq(MOCK.requests, 1)
	Near(tracker():LevelTime(), 901, 0.01, "the realm's count, not the saved one plus a day")
end)

T("a /reload continues the clock and the session without asking /played", function()
	local now = MOCK.ServerTime()
	local c = savedChar({ played = 17500, levelPlayed = 400, playedAt = now - 3,
		session = { xp = 1234, levels = 1, elapsed = 600, savedAt = now - 3 } })
	Boot({ db = db({ [KEY] = c }), reload = true })
	Eq(MOCK.requests, 0, "no /played request")
	Ok(tracker():Synced())
	Near(tracker():LevelTime(), 404, 0.01, "the saved time, the 3 s of the reload and 1 s since")
	Eq(tracker().session.xp, 1234, "session XP kept")
	Eq(tracker().session.levels, 1, "session levels kept")
	Near(tracker():SessionTime(), 604, 0.01, "session length kept")
	Eq(char().session, nil, "the saved session is used up")
end)

T("logging out saves the clock, the XP and the session", function()
	Boot()
	MOCK.GainXP(500)
	MOCK.Advance(100)
	local saved = Logout().chars[KEY]
	Near(saved.levelPlayed, 1001, 1)
	Near(saved.played, 18101, 1)
	Eq(saved.playedAt, MOCK.ServerTime())
	Eq(saved.xpCur, 500)
	Eq(saved.session.xp, 500)
	Near(saved.session.elapsed, 101, 1)
	Eq(saved.lastSeen, MOCK.ServerTime())
end)

T("a /reload long after logging out starts a new session and asks /played", function()
	local now = MOCK.ServerTime()
	local c = savedChar({ played = 17500, levelPlayed = 400, playedAt = now - 3600,
		session = { xp = 1234, levels = 1, elapsed = 600, savedAt = now - 3600 } })
	Boot({ db = db({ [KEY] = c }), reload = true })
	Eq(MOCK.requests, 1)
	Eq(tracker().session.xp, 0)
end)

T("XP per hour and the time to the next level", function()
	Boot()
	Eq(tracker():Rate(), nil, "nothing gained yet")
	MOCK.GainXP(1200)
	MOCK.Advance(50)
	Eq(tracker():Rate(), nil, "too early for a pace")
	MOCK.Advance(549)
	-- 1200 XP in the first 600 s of the session.
	Near(tracker():Rate(), 7200, 0.01, "XP per hour")
	local cur, maxXP = tracker():XP()
	Near(tracker():ETA(), (maxXP - cur) / 7200 * 3600, 0.01, "time to the next level")
end)

T("max level: nothing more to time", function()
	Boot({ player = { level = MOCK.maxLevel } })
	Ok(tracker():AtMax())
	Eq(tracker():ETA(), nil)
	MOCK.Fire("PLAYER_LEVEL_UP", MOCK.maxLevel + 1)
	Eq(char().level, MOCK.maxLevel + 1, "a higher cap later still records")
end)

T("max level from the game rules, with fallbacks", function()
	Boot()
	Eq(NS.Tracker.MaxLevel(), MOCK.maxLevel)
	MOCK.api.GameRulesUtil = nil
	Eq(NS.Tracker.MaxLevel(), MOCK.maxLevel, "GetMaxLevelForPlayerExpansion")
	MOCK.api.GetMaxLevelForPlayerExpansion = nil
	Eq(NS.Tracker.MaxLevel(), MOCK.maxLevel, "GetMaxPlayerLevel")
	MOCK.missingGlobals = {}
end)

T("experience turned off", function()
	Boot({ player = { xpDisabled = true } })
	Eq(tracker():ETA(), nil)
	NS.UI.Show("overview")
	Has(Text(NS.UI.panels.overview.this.rows[3].value), "experience is off")
	Has(Text(LevelTimeTrackerFrame.state.text), "Experience is off")
end)

T("a deleted character's name on a new character starts over", function()
	local old = savedChar({ class = "WARRIOR", level = 40, levels = { [30] = { t = 999 } }, played = 99999 })
	Boot({ db = db({ [KEY] = old }), player = { level = 1 } })
	Eq(next(char().levels), nil, "the old levels are gone")
	Eq(char().first.level, 1)
	Eq(char().class, "MAGE")
end)

T("secret values are treated as unknown", function()
	MOCK.secrets = { MAGE = true, Human = true }
	Boot()
	Eq(char().class, nil, "a secret class isn't stored")
	NS.UI.Show("overview")
	NS.UI.Show("characters")
	MOCK.Advance(1)
end)

---------------------------------------------------------------------------
-- Saved data
---------------------------------------------------------------------------
local function legacy()
	return {
		["Frost-Lightbringer"] = {
			_lastLevelXP = 0, totalTime = 1506.6, currentLevel = 12, _lastRecordedLevel = 12, _xpStarted = false,
			startLevel = 7, maxLevel = 80, _lastXP = 0,
			levelTimes = { [7] = 0, [8] = 67.115000000016, [9] = 291.07, [10] = -12, [11] = 692.82 },
		},
		["Alt-Draenor"] = { currentLevel = 35, maxLevel = 80, startLevel = 1, levelTimes = {}, totalTime = 0 },
		ui = { position = { "LEFT", "LEFT", 61.3, -60.1 }, compact = true },
		profile = {
			characters = {
				["Frost-Lightbringer"] = { currentLevel = 12, startLevel = 7, startedAt = 1768006186,
					levelTimes = { [7] = 206.2, [8] = 99 } },
				["Other-Kazzak"] = { expansion = "Dragonflight", currentLevel = 73, startLevel = 70, startedAt = 1768006495,
					levelTimes = { [70] = 246.9, [71] = 256.7, [72] = 0 }, maxLevel = 80 },
			},
		},
	}
end

T("Level Time Tracker 1.x data is kept", function()
	Boot({ db = legacy() })
	local saved = LevelTimeTrackerDB
	Eq(saved.version, 2)
	Eq(saved.ui, nil, "the old window settings are gone")
	Eq(saved.profile, nil)
	local c = saved.chars[KEY]
	Eq(c.levels[8].t, 67, "1.x time kept (rounded)")
	Ok(c.levels[8].legacy, "marked as 1.x")
	Eq(c.levels[9].t, 291)
	Eq(c.levels[10].t, nil, "a negative time is unknown")
	Ok(c.levels[10].legacy)
	Eq(c.levels[7].t, 206, "an untimed level takes the time the other 1.x table had")
	Eq(c.levels[11].t, 693)
	Eq(saved.chars["Alt-Draenor"].level, 35)
	Eq(saved.chars["Other-Kazzak"].levels[71].t, 257)
	Eq(saved.chars["Other-Kazzak"].first.at, 1768006495)
	Eq(saved.migratedFrom, 1)
	Chat()
	MOCK.Advance(6)
	Has(Chat(), "version 2.0.0 has a new look and now times your levels like /played does. Type /ltt to open it.")
	-- The 1.x levels show up as such.
	NS.UI.ShowLevels(nil)
	local list = NS.UI.panels.levels.list
	Ok(#list.view >= 5)
	MOCK.Advance(1)
end)

T("a new install says hello once", function()
	Boot()
	Chat()
	MOCK.Advance(6)
	Has(Chat(), "Level Time Tracker: timing your levels. Type /ltt to open it.")
	Eq(NS.S.hello, NS.version)
end)

T("broken saved variables don't stop the addon", function()
	Boot({ db = { version = 2, settings = "oops", chars = 5 } })
	Ok(type(LevelTimeTrackerDB.chars) == "table")
	Ok(LevelTimeTrackerDB.chars[KEY], "the character is recorded")
	Eq(NS.S.announce, true, "defaults")
end)

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------
local function playSomeLevels()
	local times = { 1200, 1000, 1500, 300, 2400 }
	for _, t in ipairs(times) do
		MOCK.GainXP(math.floor(MOCK.player.xpMax / 2))
		MOCK.Advance(t)
		MOCK.LevelUp()
	end
end

T("/ltt opens the window on the Overview and Escape closes it", function()
	Boot()
	SlashCmdList.LEVELTIMETRACKER("")
	local f = LevelTimeTrackerFrame
	Ok(f:IsShown(), "shown")
	Eq(NS.UI.current, "overview")
	Eq(Text(f.header.text), "Level Time Tracker")
	Has(Text(f.status), "1 character ")
	HasNot(Text(f.status), "1 characters")
	Has(Text(f.state.text), "Timing level 12")
	MOCK.PressEscape()
	Ok(not f:IsShown(), "Escape closes it")
	SlashCmdList.LEVELTIMETRACKER("")
	Ok(f:IsShown())
	SlashCmdList.LEVELTIMETRACKER("")
	Ok(not f:IsShown(), "/ltt again closes it")
end)

T("the Overview shows the banner, this level, the session, recent levels and records", function()
	Boot({ player = { rested = 800, resting = true } })
	playSomeLevels()
	MOCK.GainXP(500)
	MOCK.Advance(30)
	NS.UI.Show("overview")
	MOCK.Advance(1)
	local p = NS.UI.panels.overview
	local b = p.banner
	Eq(Text(b.name), "Frost")
	Eq(Text(b.sub), "Level 17 Human Mage")
	Has(Text(b.since), "Timing since level 12")
	Eq(b.portrait:GetTexture(), "portrait:player")
	Eq(Text(b.tiles[1].value), "17")
	Eq(Text(b.tiles[2].value), "31s", "time on level 17")
	Ok(Text(b.tiles[3].value) ~= "-", "time to the next level")
	Ok(Text(b.tiles[4].value) ~= "-", "XP per hour")
	Has(Text(p.this.title), "This level: 17 \194\187 18")
	Has(Text(p.this.bar.value), "500 / ")
	Has(Text(p.this.rows[1].value), "31s")
	Has(Text(p.this.rows[4].value), "800")
	Has(Text(p.this.rows[4].value), "resting")
	Ok(p.this.bar.extra:IsShown(), "rested XP on the bar")
	Eq(Text(p.session.rows[3].value), "5", "levels this session")
	local rows = p.recent.rows
	Eq(Text(rows[1].level), "16 \194\187 17")
	Eq(Text(rows[1].time), "40m 00s")
	Eq(Text(rows[1].date), "Today")
	Eq(Text(rows[2].time), "5m 00s")
	Ok(rows[1].bar:GetValue() > rows[2].bar:GetValue(), "the longer level has the longer bar")
	Ok(Rect(rows[1].bar:GetStatusBarTexture()).w > Rect(rows[2].bar:GetStatusBarTexture()).w, "drawn longer")
	Ok(not rows[6]:IsShown(), "only the levels there are")
	Ok(not p.recent.empty:IsShown())
	Has(Text(p.records.rows[1].value), "5m 00s")
	Has(Text(p.records.rows[1].value), "(level 15)")
	Has(Text(p.records.rows[2].value), "40m 00s")
	Has(Text(p.records.rows[4].value), "(5 levels)")
	Fire(rows[1], "OnEnter")
	Has(MOCK.TooltipText(), "Level 16 \194\187 17")
	Has(MOCK.TooltipText(), "Took | 40m 00s")
	Has(MOCK.TooltipText(), "Zone | Elwynn Forest")
	Fire(rows[1], "OnClick", "LeftButton")
	Eq(NS.UI.current, "levels", "a click on a recent level opens the Levels page")
end)

T("the Overview before any level and before /played answered", function()
	MOCK.playedDelay = 10
	Boot({ wait = 0.5 })
	NS.UI.Show("overview")
	MOCK.Advance(1)
	local p = NS.UI.panels.overview
	Has(Text(p.this.rows[1].value), "reading /played")
	Ok(p.recent.empty:IsShown(), "the empty note")
	Has(Text(LevelTimeTrackerFrame.state.text), "Reading /played")
	MOCK.Advance(10)
	HasNot(Text(p.this.rows[1].value), "reading")
end)

T("the Overview at max level", function()
	Boot({ player = { level = MOCK.maxLevel } })
	NS.UI.Show("overview")
	MOCK.Advance(1)
	local p = NS.UI.panels.overview
	Eq(Text(p.banner.tiles[1].label), "Max level")
	Eq(Text(p.banner.tiles[2].label), "Played")
	Has(Text(p.this.title), "Max level")
	Has(Text(LevelTimeTrackerFrame.state.text), "Max level")
end)

local function checkFits(scale)
	MOCK.fontScale = scale
	Boot()
	playSomeLevels()
	NS.UI.Show("overview")
	MOCK.Advance(1)
	local p = NS.UI.panels.overview
	local frame = LevelTimeTrackerFrame
	for _, box in ipairs({ p.banner, p.this, p.session, p.recent, p.records }) do
		Ok(Inside(box, frame.content, 0.5), "box inside the window")
		for i, row in ipairs(box.rows or {}) do
			if row:IsShown() then
				Ok(Inside(row, box, 0.5), ("row %d inside its box (font %d%%)"):format(i, scale * 100))
				for _, fs in ipairs({ row.label, row.value }) do
					if fs then
						Ok(Inside(fs, box, 0.5), ("text of row %d inside its box: %s"):format(i, Text(fs)))
					end
				end
			end
		end
	end
	for i, t in ipairs(p.banner.tiles) do
		Ok(Inside(t.value, p.banner, 0.5) and Inside(t.label, p.banner, 0.5), "banner tile " .. i .. " inside the banner")
	end
	Ok(Inside(p.banner.name, p.banner, 0.5) and Inside(p.banner.since, p.banner, 0.5), "banner text inside")
	local ring = Rect(p.banner.ring)
	local banner = Rect(p.banner)
	Ok(ring.b >= banner.b and ring.b + ring.h <= banner.b + banner.h, "the portrait ring fits the banner")
	for _, page in ipairs({ "levels", "characters", "options" }) do
		NS.UI.Show(page)
	end
	for _, tab in ipairs(frame.tabs.tabs) do
		Ok(Rect(tab).b < Rect(frame).b, "tabs under the window")
	end
end

T("the Overview fits at Blizzard's font sizes", function()
	checkFits(1)
end)

T("the Overview fits with fonts a UI addon made bigger", function()
	checkFits(1.2)
end)

T("the Levels page: every level, fastest green, slowest orange, sorting", function()
	Boot()
	playSomeLevels()
	NS.UI.ShowLevels(nil)
	MOCK.Advance(0.01)
	local p = NS.UI.panels.levels
	local list = p.list
	Eq(#list.view, 5)
	local first = list.rows[1]
	Eq(Text(first.cells[1]), "16 \194\187 17", "highest level first")
	Eq(Text(first.cells[2]), "40m 00s")
	local r, g = first.cells[2]:GetTextColor()
	Ok(r == 1 and g == 0.5, "slowest in orange")
	local fastest = list.rows[2]
	r, g = fastest.cells[2]:GetTextColor()
	Ok(r == 0.25 and g == 1, "fastest in green")
	Ok(first.pace:GetValue() > fastest.pace:GetValue(), "pace bars")
	Ok(Inside(first.pace, first, 0.5), "the pace bar sits in its row")
	Has(Text(first.cells[4]), ", ")
	Eq(Text(first.cells[6]), "Elwynn Forest")
	Has(Text(p.summary), "5 levels timed")
	Ok(not p.mine:IsShown(), "no back button on your own levels")
	-- Sort by time (longest first), then shortest first.
	list:ToggleSort("time")
	Eq(Text(list.rows[1].cells[2]), "40m 00s")
	list:ToggleSort("time")
	Eq(Text(list.rows[1].cells[2]), "5m 00s")
	Fire(list.rows[1], "OnEnter")
	Has(MOCK.TooltipText(), "Took | 5m 00s")
end)

T("the Characters page: click shows a character's levels, right-click forgets one (asking first)", function()
	local alt = savedChar({ name = "Alt", realm = "Draenor", class = "ROGUE", level = 30, lastSeen = MOCK.ServerTime() - 3 * 86400,
		played = 50000, levels = { [28] = { t = 1800, at = MOCK.ServerTime() - 4 * 86400 }, [29] = { t = 2400 } } })
	Boot({ db = db({ ["Alt-Draenor"] = alt }) })
	NS.UI.Show("characters")
	MOCK.Advance(0.01)
	local p = NS.UI.panels.characters
	local list = p.list
	Eq(#list.view, 2)
	Has(Text(p.summary), "2 characters, 2 still leveling")
	local mine, other = list.rows[1], list.rows[2]
	Has(Text(mine.cells[1]), "Frost")
	Has(Text(mine.cells[1]), "(you)")
	Eq(Text(mine.cells[6]), "Now")
	Has(Text(other.cells[1]), "Alt")
	Eq(Text(other.cells[3]), "1h 10m", "time leveling")
	Eq(Text(other.cells[6]), "3 days ago")
	Fire(other, "OnEnter")
	Has(MOCK.TooltipText(), "Right-click: forget this character")
	Fire(other, "OnClick", "LeftButton")
	Eq(NS.UI.current, "levels")
	Has(Text(NS.UI.panels.levels.name), "Alt")
	Ok(NS.UI.panels.levels.mine:IsShown(), "a way back to your own levels")
	NS.UI.panels.levels.mine:Click()
	Has(Text(NS.UI.panels.levels.name), "Frost")
	NS.UI.Show("characters")
	Fire(list.rows[1], "OnClick", "RightButton")
	Eq(#MOCK.popups, 0, "you can't forget yourself")
	Fire(list.rows[2], "OnClick", "RightButton")
	Eq(#MOCK.popups, 1, "asks first")
	Has(MOCK.popups[1].text, "Forget Alt - Draenor?")
	MOCK.AcceptPopup()
	Eq(LevelTimeTrackerDB.chars["Alt-Draenor"], nil, "forgotten")
	MOCK.Advance(1)
	Eq(#list.view, 1)
end)

T("Options: switches, the UI size and the look", function()
	Boot()
	NS.UI.Show("options")
	local p = NS.UI.panels.options
	local announce = p.controls[1]
	announce:Click()
	Eq(NS.S.announce, false)
	MOCK.Advance(1)
	Ok(not p.compare:IsEnabled(), "compare greyed out without announcing")
	Chat()
	MOCK.LevelUp()
	MOCK.Advance(0.5)
	Eq(Chat(), "", "no chat line")
	announce:Click()
	Eq(NS.S.announce, true)
	-- The UI size changes when the slider is let go.
	local slider
	for _, w in ipairs(p.controls) do
		if w.GetObjectType and w:GetObjectType() == "Slider" then slider = w end
	end
	slider:SetValue(120)
	Eq(LevelTimeTrackerFrame:GetScale(), 1, "not while dragging")
	MOCK.DragSlider(slider, 120)
	Eq(NS.S.scale, 1.2)
	Near(LevelTimeTrackerFrame:GetScale(), 1.2, 0.001, "the window")
	Near(LevelTimeTrackerMini:GetScale(), 1.2, 0.001, "the mini tracker")
	-- Themes repaint the classic art.
	local steel
	for _, w in ipairs(p.controls) do
		if w.label and Text(w.label) == "Steel" then steel = w end
	end
	steel:Click()
	Eq(NS.W.themeId, "steel")
	Eq(NS.S.theme, "steel")
	Ok(LevelTimeTrackerFrame.header.art[1]:IsDesaturated(), "the header plate in steel")
	Ok(steel:GetChecked(), "the radio button")
	for _, page in ipairs({ "overview", "levels", "characters" }) do
		NS.UI.Show(page)
	end
	Has(Text(p.version), "Version 2.0.0")
end)

T("every look paints every page", function()
	Boot()
	playSomeLevels()
	for _, id in ipairs(NS.W.THEME_ORDER) do
		NS.W.SetTheme(id)
		for _, page in ipairs({ "overview", "levels", "characters", "options" }) do
			NS.UI.Show(page)
			MOCK.Advance(0.6)
		end
	end
	Ok(not NS.W.SetTheme("nope"), "an unknown look")
	Eq(NS.W.themeId, "alliance", "the look stays as it was")
end)

T("reset asks first and starts timing again", function()
	Boot()
	playSomeLevels()
	SlashCmdList.LEVELTIMETRACKER("reset")
	Eq(#MOCK.popups, 1)
	Eq(next(char().levels) ~= nil, true, "nothing gone yet")
	Chat()
	MOCK.AcceptPopup()
	Eq(next(char().levels), nil)
	Eq(char().first.level, 17)
	Has(Chat(), "Timing starts again from level 17.")
end)

T("the page in the game's settings", function()
	Boot()
	Ok(MOCK.settings.registered, "registered under AddOns")
	Eq(MOCK.settings.name, "Level Time Tracker")
	local panel = MOCK.settings.panel
	panel:Show()
	Ok(panel.checks[1]:GetChecked(), "announce on")
	panel.checks[2]:Click()
	Eq(NS.S.mini, false)
	Ok(not LevelTimeTrackerMini:IsShown(), "the mini tracker went away")
	panel:OnDefault()
	Eq(NS.S.mini, true)
	Ok(LevelTimeTrackerMini:IsShown(), "back with the defaults")
	panel.open:Click()
	Ok(LevelTimeTrackerFrame:IsShown(), "the button opens the window")
end)

---------------------------------------------------------------------------
-- The mini tracker
---------------------------------------------------------------------------
T("the mini tracker: level, time, XP bar; click, right-click, drag", function()
	Boot({ player = { rested = 500 } })
	local mini = LevelTimeTrackerMini
	Ok(mini:IsShown(), "on by default")
	MOCK.GainXP(1000)
	MOCK.Advance(200)
	Eq(Text(mini.level), "12")
	Eq(Text(mini.time), "18m 21s")
	Has(Text(mini.bar.value), "%")
	Ok(mini.bar.extra:IsShown(), "rested XP")
	Fire(mini, "OnEnter")
	Has(MOCK.TooltipText(), "Time on this level | 18m 21s")
	Has(MOCK.TooltipText(), "Click: open Level Time Tracker")
	Fire(mini, "OnMouseUp", "LeftButton")
	Ok(LevelTimeTrackerFrame:IsShown(), "click opens the window")
	Fire(mini, "OnMouseUp", "LeftButton")
	Ok(not LevelTimeTrackerFrame:IsShown(), "and closes it")
	Fire(mini, "OnMouseUp", "RightButton")
	Eq(NS.UI.current, "options", "right-click: options")
	-- Dragging moves it and remembers where; the click that ends a drag doesn't toggle the window.
	NS.UI.Hide()
	Fire(mini, "OnDragStart")
	Ok(mini._moving, "moving")
	MOCK.dragTo = { 300, 600 }
	Fire(mini, "OnDragStop")
	Fire(mini, "OnMouseUp", "LeftButton")
	Ok(not LevelTimeTrackerFrame:IsShown(), "no toggle after a drag")
	local pos = NS.S.pos.LevelTimeTrackerMini
	Ok(pos and pos.point == "CENTER", "saved, relative to the centre of the screen")
	local r = Rect(mini)
	Near(r.l, 300, 1, "where it was dropped (left)")
	Near(r.b + r.h, 600, 1, "where it was dropped (top)")
	-- Locked: no drag, clicks still work.
	NS.S.miniLocked = true
	Fire(mini, "OnDragStart")
	Ok(not mini._moving, "locked")
	Fire(mini, "OnMouseUp", "LeftButton")
	Ok(LevelTimeTrackerFrame:IsShown(), "the click still works")
end)

T("the mini tracker goes away at max level, in combat (if wanted) and in pet battles", function()
	Boot()
	local mini = LevelTimeTrackerMini
	Ok(mini:IsShown())
	NS.S.miniHideCombat = true
	MOCK.combat = true
	MOCK.Fire("PLAYER_REGEN_DISABLED")
	Ok(not mini:IsShown(), "hidden in combat")
	MOCK.combat = false
	MOCK.Fire("PLAYER_REGEN_ENABLED")
	Ok(mini:IsShown(), "back after combat")
	MOCK.petBattle = true
	MOCK.Fire("PET_BATTLE_OPENING_START")
	Ok(not mini:IsShown(), "hidden in a pet battle")
	MOCK.petBattle = false
	MOCK.Fire("PET_BATTLE_CLOSE")
	Ok(mini:IsShown())
	-- Up to max level.
	MOCK.player.level = MOCK.maxLevel - 1
	MOCK.player.xpMax = MOCK.XPFor(MOCK.player.level)
	MOCK.Fire("PLAYER_LEVEL_UP", MOCK.maxLevel - 1)
	MOCK.LevelUp()
	Ok(not mini:IsShown(), "hidden at max level")
	NS.S.miniAtMax = true
	NS:Fire("SETTINGS_CHANGED", "miniAtMax")
	Ok(mini:IsShown(), "kept at max level when wanted")
	Eq(Text(mini.time), "Max level")
end)

---------------------------------------------------------------------------
-- Commands, compartment, key bindings
---------------------------------------------------------------------------
T("slash commands", function()
	Boot()
	local run = SlashCmdList.LEVELTIMETRACKER
	run("levels")
	Eq(NS.UI.current, "levels")
	run("chars")
	Eq(NS.UI.current, "characters")
	run("options")
	Eq(NS.UI.current, "options")
	run("OVERVIEW")
	Eq(NS.UI.current, "overview")
	run("mini")
	Eq(NS.S.mini, false)
	Ok(not LevelTimeTrackerMini:IsShown())
	run("mini")
	Ok(LevelTimeTrackerMini:IsShown())
	Chat()
	run("lock")
	Eq(NS.S.miniLocked, true)
	Has(Chat(), "Mini tracker locked.")
	MOCK.Advance(20)
	run("played")
	Eq(MOCK.requests, 2)
	MOCK.Advance(1)
	Eq(MOCK.chatPlayed, 3, "/ltt played shows /played in chat")
	run("help")
	local help = Chat()
	Has(help, "/ltt levels")
	Has(help, "/ltt reset")
	run("dance")
	Has(Chat(), "There's no command dance.")
end)

T("the addon compartment", function()
	Boot()
	LevelTimeTracker_OnAddonCompartmentClick(ADDON_NAME, "LeftButton")
	Ok(LevelTimeTrackerFrame:IsShown())
	LevelTimeTracker_OnAddonCompartmentClick(ADDON_NAME, "LeftButton")
	Ok(not LevelTimeTrackerFrame:IsShown())
	LevelTimeTracker_OnAddonCompartmentClick(ADDON_NAME, "RightButton")
	Eq(NS.S.mini, false)
	MOCK.Advance(100)
	LevelTimeTracker_OnAddonCompartmentEnter(ADDON_NAME, UIParent)
	Has(MOCK.TooltipText(), "Time on level 12 | 16m 41s")
	LevelTimeTracker_OnAddonCompartmentLeave(ADDON_NAME, UIParent)
	Ok(not GameTooltip:IsShown())
end)

T("the key bindings", function()
	Boot()
	local f = assert(io.open(ROOT .. "/Bindings.xml", "r"))
	local xml = f:read("*a")
	f:close()
	local ran = 0
	for name, body in xml:gmatch('<Binding name="([%w_]+)"[^>]*>(.-)</Binding>') do
		Ok(rawget(_G, "BINDING_NAME_" .. name), "a label for " .. name)
		assert(loadstring(body))()
		ran = ran + 1
	end
	Eq(ran, 2)
	Ok(LevelTimeTrackerFrame:IsShown(), "toggle binding")
	Eq(NS.S.mini, false, "mini tracker binding")
	Ok(rawget(_G, "BINDING_HEADER_LEVELTIMETRACKER"))
end)

T("the tabs stay under the window's border when a click raises it", function()
	Boot()
	NS.UI.Show()
	local f = LevelTimeTrackerFrame
	Eq(f:GetFrameStrata(), "MEDIUM", "among the game's own windows")
	Eq(f.tabs.tabs[1]:GetFrameLevel(), math.max(1, f:GetFrameLevel() - 1))
	f:SetFrameLevel(40) -- the game raised it
	MOCK.Fire("GLOBAL_MOUSE_DOWN", "LeftButton")
	MOCK.Advance(0.01)
	Eq(f.tabs.tabs[1]:GetFrameLevel(), 39, "tabs followed")
end)

T("the window remembers where it was and fits the screen at any UI size", function()
	Boot()
	NS.UI.Show()
	local f = LevelTimeTrackerFrame
	Fire(f, "OnDragStart")
	MOCK.dragTo = { 200, 700 }
	Fire(f, "OnDragStop")
	local pos = NS.S.pos.LevelTimeTrackerFrame
	Ok(pos, "saved")
	local before = Rect(f)
	NS.S.scale = 1.5
	NS:Fire("SETTINGS_CHANGED", "scale")
	local after = Rect(f)
	Near(after.l + after.w / 2, before.l + before.w / 2, 1, "the centre stays put")
	Ok(after.h + 18 + 28 <= MOCK.screen.height, "fits the screen with its header and tabs")
end)
