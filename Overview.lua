-- Overview.lua: the first page. The character's banner, this level, this session, the recent levels and records.
local ADDON, ns = ...
local L, U, C, COLOR = ns.L, ns.U, ns.C, ns.COLOR
local W, Data, UI = ns.W, ns.Data, ns.UI

local format, floor, max, min = string.format, math.floor, math.max, math.min

local BANNER_H = 96
local GAP = 22 -- between boxes (their titles sit in the gap)
local LEFT_W = 330
local THIS_H = 150
local RECENT_H = 182
local RECENT_ROWS = 8
local PORTRAIT = 58
local RING = "QuestSharing-Dialog-Portrait"
local CLASS_CIRCLES = "Interface\\TargetingFrame\\UI-Classes-Circles"

local function dash()
	return C(COLOR.grey, "-")
end

-- A big number with a small gold label under it.
local function tile(parent, label)
	local f = CreateFrame("Frame", nil, parent)
	f:SetSize(92, 40)
	f.value = W.OneLine(f:CreateFontString(nil, "ARTWORK", "GameFontHighlightLarge"))
	f.value:SetPoint("TOP")
	f.value:SetWidth(92)
	f.label = W.OneLine(f:CreateFontString(nil, "ARTWORK", "LevelTimeTrackerFontNormalSmall"))
	f.label:SetPoint("TOP", f.value, "BOTTOM", 0, -4)
	f.label:SetWidth(96)
	f.label:SetText(label)
	f:EnableMouse(true)
	f:SetScript("OnEnter", function(self)
		if self.tip then
			W.ShowTip(self, self.label:GetText(), self.tip)
		end
	end)
	f:SetScript("OnLeave", W.HideTip)
	return f
end

local function buildBanner(panel)
	local b = W.Box(panel)
	b:SetPoint("TOPLEFT", 0, -2)
	b:SetPoint("TOPRIGHT", 0, -2)
	b:SetHeight(BANNER_H)

	b.portrait = b:CreateTexture(nil, "ARTWORK")
	b.portrait:SetSize(PORTRAIT, PORTRAIT)
	b.portrait:SetPoint("LEFT", 22, 0)
	b.ring = b:CreateTexture(nil, "OVERLAY")
	b.ring:SetPoint("CENTER", b.portrait, "CENTER")
	if U.AtlasExists(RING) then
		b.ring:SetAtlas(RING)
		b.ring:SetSize(floor(PORTRAIT * 64 / 50 + 0.5), floor(PORTRAIT * 64 / 50 + 0.5))
	else
		b.ring:SetTexture("Interface\\Common\\RingBorder")
		b.ring:SetSize(PORTRAIT + 16, PORTRAIT + 16)
	end
	W.Themed(b.ring, function(ring, th)
		W.Tint(ring, th.metal)
	end)

	b.name = W.OneLine(b:CreateFontString(nil, "ARTWORK", "GameFontNormalHuge"))
	b.name:SetPoint("TOPLEFT", b.portrait, "TOPRIGHT", 18, 2)
	b.name:SetJustifyH("LEFT")
	b.sub = W.OneLine(W.Label(b, "", "GameFontHighlightSmall"))
	b.sub:SetPoint("TOPLEFT", b.name, "BOTTOMLEFT", 0, -6)
	b.since = W.OneLine(W.Label(b, "", "GameFontDisableSmall"))
	b.since:SetPoint("TOPLEFT", b.sub, "BOTTOMLEFT", 0, -5)

	b.tiles = { tile(b, L["Level"]), tile(b, L["This level"]), tile(b, L["Next level in"]), tile(b, L["XP per hour"]) }
	local prev
	for i = #b.tiles, 1, -1 do
		local t = b.tiles[i]
		if prev then
			t:SetPoint("RIGHT", prev, "LEFT", -4, 0)
		else
			t:SetPoint("RIGHT", b, "RIGHT", -14, -2)
		end
		prev = t
	end
	for _, fs in ipairs({ b.name, b.sub, b.since }) do
		fs:SetPoint("RIGHT", b.tiles[1], "LEFT", -10, 0)
	end
	return b
end

local function buildThisLevel(panel)
	local box = W.Box(panel, L["This level"])
	box:SetPoint("TOPLEFT", 0, -(2 + BANNER_H + GAP))
	box:SetSize(LEFT_W, THIS_H)
	box.bar = W.Bar(box, 15)
	box.bar:SetPoint("TOPLEFT", 14, -16)
	box.bar:SetPoint("TOPRIGHT", -14, -16)
	box.bar:EnableMouse(true)
	box.bar:SetScript("OnEnter", function(self)
		local T = ns.Tracker
		local cur, maxXP, rested = T:XP()
		local lines = {
			{ L["Experience"], format("%s / %s", U.Number(cur), U.Number(maxXP)) },
			{ L["Rested XP"], rested > 0 and U.Number(rested) or L["none"] },
		}
		W.ShowTip(self, format(L["Level %d"], T.level), lines)
	end)
	box.bar:SetScript("OnLeave", W.HideTip)
	box.rows = {}
	for i = 1, 5 do
		box.rows[i] = UI.StatRow(box, "")
	end
	return box
end

-- The rows of the "This level" box while leveling, and at max level: label (%d: the level), tooltip.
local LEVELING_ROWS = {
	{ L["Time on this level"], L["Counted like /played: all the time you are logged in on this character since you reached this level."] },
	{ L["XP to go"] },
	{ L["Next level in"], L["At the pace of this session (the XP per hour)."] },
	{ L["Rested XP"], L["Rested XP doubles the XP from kills until it runs out. You gain it while resting in an inn or a city."] },
	{ L["Reached level %d"] },
}
local MAX_ROWS = {
	{ L["Reached level %d"] },
	{ L["/played then"], L["/played in total when the character reached max level."] },
	{ L["Levels timed"] },
	{ L["Calendar time"], L["Real time from the start of timing to max level, logged out included."] },
}

local function setRows(box, defs, level)
	for i, row in ipairs(box.rows) do
		local def = defs[i]
		row:SetShown(def ~= nil)
		if def then
			row:SetLabel(format(def[1], level), def[2])
		end
	end
end

local function buildSession(panel, top)
	local box = W.Box(panel, L["This session"])
	box:SetPoint("TOPLEFT", 0, -top)
	box:SetPoint("BOTTOMLEFT", 0, 0)
	box:SetWidth(LEFT_W)
	box.rows = {
		UI.StatRow(box, L["Session length"], L["Since you logged in (a /reload doesn't start a new session)."]),
		UI.StatRow(box, L["XP gained"]),
		UI.StatRow(box, L["Levels gained"]),
		UI.StatRow(box, L["XP per hour"], L["The XP of this session, per hour of it."]),
		UI.StatRow(box, L["Played in total"], L["All the time on this character, as /played says."]),
	}
	return box
end

local function recentRow(box)
	local row = CreateFrame("Button", nil, box)
	row:SetHeight(20)
	local hl = row:CreateTexture(nil, "HIGHLIGHT")
	hl:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
	hl:SetBlendMode("ADD")
	hl:SetAllPoints()
	row.level = W.OneLine(row:CreateFontString(nil, "ARTWORK", "LevelTimeTrackerFontNormalSmall"))
	row.level:SetPoint("LEFT", 4, 0)
	row.level:SetWidth(58)
	row.level:SetJustifyH("LEFT")
	row.date = W.OneLine(row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall"))
	row.date:SetPoint("RIGHT", -4, 0)
	row.date:SetWidth(72)
	row.date:SetJustifyH("RIGHT")
	row.time = W.OneLine(row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall"))
	row.time:SetPoint("RIGHT", row.date, "LEFT", -6, 0)
	row.time:SetWidth(74)
	row.time:SetJustifyH("RIGHT")
	row.bar = W.PaceBar(row, 6)
	row.bar:SetPoint("LEFT", row.level, "RIGHT", 4, 0)
	row.bar:SetPoint("RIGHT", row.time, "LEFT", -8, 0)
	row:SetScript("OnEnter", function(self)
		if self.item then
			UI.LevelTip(self, self.item, self.char)
		end
	end)
	row:SetScript("OnLeave", W.HideTip)
	row:SetScript("OnClick", function()
		W.Sound("click")
		UI.ShowLevels(nil)
	end)
	return row
end

local function buildRecent(panel)
	local box = W.Box(panel, L["Recent levels"])
	box:SetPoint("TOPLEFT", LEFT_W + 12, -(2 + BANNER_H + GAP))
	box:SetPoint("TOPRIGHT", 0, -(2 + BANNER_H + GAP))
	box:SetHeight(RECENT_H)
	box.all = W.TextButton(box, L["All levels"], function()
		UI.ShowLevels(nil)
	end, L["Every level of this character, with dates, zones and /played."])
	box.all:SetPoint("BOTTOMRIGHT", box, "TOPRIGHT", -6, 0)
	box.rows = {}
	for i = 1, RECENT_ROWS do
		local row = recentRow(box)
		row:SetPoint("TOPLEFT", 8, -8 - (i - 1) * 21)
		row:SetPoint("TOPRIGHT", -8, -8 - (i - 1) * 21)
		box.rows[i] = row
	end
	box.empty = W.Text(box, L["No levels timed yet. Your next level-up shows up here, with the time it took."], 300, "GameFontDisableSmall")
	box.empty:SetPoint("TOP", 0, -40)
	box.empty:SetJustifyH("CENTER")
	return box
end

local function buildRecords(panel, top)
	local box = W.Box(panel, L["Records"])
	box:SetPoint("TOPLEFT", LEFT_W + 12, -top)
	box:SetPoint("BOTTOMRIGHT", 0, 0)
	box.rows = {
		UI.StatRow(box, L["Fastest level"]),
		UI.StatRow(box, L["Slowest level"]),
		UI.StatRow(box, L["Average level"], L["The average of the levels with a time (levels skipped at once don't count)."]),
		UI.StatRow(box, L["Time spent leveling"], L["All timed levels together."]),
	}
	return box
end

-- A level's tooltip (Overview and Levels pages). item: an entry of Data.Levels.
function UI.LevelTip(owner, item, c)
	local title = format(L["Level %d %s %d"], item.level, UI.ARROW, item.level + 1)
	local lines = {}
	if item.skipped then
		lines[#lines + 1] = L["Skipped: you gained more than one level at once."]
	elseif item.t and item.t > 0 then
		lines[#lines + 1] = { L["Took"], U.DurationLong(item.t) }
		local diff = c and Data.Change(c, item.level)
		if diff and diff ~= 0 then
			lines[#lines + 1] = { L["Compared with the level before"], diff < 0 and C(COLOR.green, "-" .. U.DurationLong(-diff))
				or C(COLOR.red, "+" .. U.DurationLong(diff)) }
		end
	else
		lines[#lines + 1] = L["Not timed: the clock wasn't running when this level ended."]
	end
	if item.at then
		lines[#lines + 1] = { format(L["Reached level %d"], item.level + 1), U.DateTime(item.at) }
	end
	if item.played then
		lines[#lines + 1] = { L["/played then"], U.DurationLong(item.played) }
	end
	if item.zone then
		lines[#lines + 1] = { L["Zone"], item.zone }
	end
	if item.legacy then
		lines[#lines + 1] = C(COLOR.grey, L["Timed by Level Time Tracker 1.x, which didn't keep dates or zones."])
	end
	W.ShowTip(owner, title, lines)
end

local function create(panel)
	panel.banner = buildBanner(panel)
	panel.this = buildThisLevel(panel)
	local sessionTop = 2 + BANNER_H + GAP + THIS_H + GAP
	panel.session = buildSession(panel, sessionTop)
	panel.recent = buildRecent(panel)
	panel.records = buildRecords(panel, 2 + BANNER_H + GAP + RECENT_H + GAP)

	local pitch = UI.Pitch(panel.this.rows[1].value, 19)
	UI.StackRows(panel.this, panel.this.rows, 42, pitch)
	UI.StackRows(panel.session, panel.session.rows, 12, pitch)
	UI.StackRows(panel.records, panel.records.rows, 10, pitch)
end

-- The parts that change by the second.
local function tick(panel)
	local T = ns.Tracker
	local c = T.char
	if not c then
		return
	end
	local b = panel.banner
	local atMax = T:AtMax()
	local levelTime = T:LevelTime()
	local rate, eta = T:Rate(), T:ETA()
	local played = T:Played()
	if atMax then
		b.tiles[2].value:SetText(played and U.Duration(played) or dash())
	else
		b.tiles[2].value:SetText(levelTime and U.Duration(levelTime) or dash())
		b.tiles[3].value:SetText(eta and U.Duration(eta) or dash())
		b.tiles[4].value:SetText(rate and U.Short(rate) or dash())
	end

	local this = panel.this.rows
	if not atMax then
		this[1].value:SetText(levelTime and U.DurationLong(levelTime) or C(COLOR.grey, L["reading /played..."]))
		if T:XPDisabled() then
			this[3].value:SetText(C(COLOR.orange, L["experience is off"]))
		elseif eta then
			this[3].value:SetText(format(L["about %s"], U.Duration(eta)))
		else
			this[3].value:SetText(C(COLOR.grey, L["after a few minutes of play"]))
		end
	end

	local s = T.session
	local rows = panel.session.rows
	rows[1].value:SetText(U.Duration(T:SessionTime()))
	rows[2].value:SetText(U.Number(s.xp))
	rows[3].value:SetText(tostring(s.levels))
	rows[4].value:SetText(rate and U.Short(rate) or dash())
	rows[5].value:SetText(played and U.DurationLong(played) or dash())
end

local function refreshBanner(panel)
	local T = ns.Tracker
	local c = T.char
	local b = panel.banner
	if SetPortraitTexture then
		SetPortraitTexture(b.portrait, "player")
	end
	b.portrait:SetTexCoord(0, 1, 0, 1)
	b.name:SetText(c.name or "")
	b.name:SetTextColor(U.ClassRGB(c.class))
	local className = c.class and LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[c.class] or ""
	b.sub:SetText(format(L["Level %d %s %s"], T.level, c.race or "", className))
	local first = c.first or {}
	if first.at and first.level then
		b.since:SetText(format(L["Timing since level %d, %s"], first.level, U.Date(first.at)))
	elseif first.level then
		b.since:SetText(format(L["Timing since level %d"], first.level))
	else
		b.since:SetText("")
	end

	local maxLevel = ns.Tracker.MaxLevel()
	b.tiles[1].value:SetText(tostring(T.level))
	b.tiles[1].tip = format(L["Max level is %d."], maxLevel)
	if T:AtMax() then
		local stats = Data.Stats(c)
		b.tiles[1].label:SetText(L["Max level"])
		b.tiles[2].label:SetText(L["Played"])
		b.tiles[2].tip = L["All the time on this character, as /played says."]
		b.tiles[3].label:SetText(L["Time leveling"])
		b.tiles[3].value:SetText(stats.count > 0 and U.Duration(stats.total) or dash())
		b.tiles[3].tip = L["All timed levels together."]
		b.tiles[4].label:SetText(L["Average level"])
		b.tiles[4].value:SetText(stats.average and U.Duration(stats.average) or dash())
		b.tiles[4].tip = nil
	else
		b.tiles[1].label:SetText(L["Level"])
		b.tiles[2].label:SetText(L["This level"])
		b.tiles[2].tip = L["Counted like /played: all the time you are logged in on this character since you reached this level."]
		b.tiles[3].label:SetText(L["Next level in"])
		b.tiles[3].tip = L["At the pace of this session (the XP per hour)."]
		b.tiles[4].label:SetText(L["XP per hour"])
		b.tiles[4].tip = L["The XP of this session, per hour of it."]
	end
end

local function refreshThisLevel(panel)
	local T = ns.Tracker
	local box = panel.this
	local c = T.char
	local cur, maxXP, rested, frac = T:XP()
	local reached = c.levels[T.level - 1]
	local reachedText = reached and reached.at and U.DateTime(reached.at) or C(COLOR.grey, L["before timing began"])
	if T:AtMax() then
		setRows(box, MAX_ROWS, T.level)
		box.title:SetText(L["Max level"])
		box.bar:Set(L["Max level"], 1, 1, W.GOLD[1] * 0.8, W.GOLD[2] * 0.8, 0, "")
		box.bar:SetExtra(nil)
		local stats = Data.Stats(c)
		box.rows[1].value:SetText(reachedText)
		box.rows[2].value:SetText(reached and reached.played and U.DurationLong(reached.played) or dash())
		box.rows[3].value:SetText(format(L["%d of %d"], stats.count, max(1, T.level - 1)))
		local first = c.first
		local span = reached and reached.at and first and first.at and reached.at - first.at
		box.rows[4].value:SetText(span and span > 0 and U.Duration(span) or dash())
	else
		setRows(box, LEVELING_ROWS, T.level)
		box.rows[5].value:SetText(reachedText)
		box.title:SetText(format(L["This level: %d %s %d"], T.level, UI.ARROW, T.level + 1))
		box.bar:Set(format("%d%%", floor(frac * 100)), cur, maxXP, W.XP[1], W.XP[2], W.XP[3],
			format("%s / %s", U.Number(cur), U.Number(maxXP)))
		box.bar:SetExtra(rested, W.RESTED[1], W.RESTED[2], W.RESTED[3])
		box.rows[2].value:SetText(U.Number(max(0, maxXP - cur)))
		local text = rested > 0 and U.Number(rested) or C(COLOR.grey, L["none"])
		if IsResting and IsResting() then
			text = text .. C(COLOR.grey, " (" .. L["resting"] .. ")")
		end
		box.rows[4].value:SetText(text)
	end
end

local function refreshRecent(panel)
	local c = ns.Tracker.char
	local box = panel.recent
	local list = Data.Levels(c)
	local longest = 0
	for i = 1, min(RECENT_ROWS, #list) do
		if Data.Timed(list[i]) then
			longest = max(longest, list[i].t)
		end
	end
	for i, row in ipairs(box.rows) do
		local item = list[i]
		row.item, row.char = item, c
		if item then
			row.level:SetText(format("%d %s %d", item.level, UI.ARROW, item.level + 1))
			if item.skipped then
				row.time:SetText(C(COLOR.grey, L["skipped"]))
			elseif Data.Timed(item) then
				row.time:SetText(U.Duration(item.t))
			else
				row.time:SetText(C(COLOR.grey, L["not timed"]))
			end
			row.date:SetText(item.at and U.Ago(item.at) or "")
			row.bar:SetPace(Data.Timed(item) and item.t or 0, longest)
			row:Show()
		else
			row:Hide()
		end
	end
	box.empty:SetShown(#list == 0)
	box.all:SetShown(#list > 0)
end

local function refreshRecords(panel)
	local c = ns.Tracker.char
	local s = Data.Stats(c)
	local rows = panel.records.rows
	local function level(e)
		return C(COLOR.grey, format(L["(level %d)"], e.level))
	end
	rows[1].value:SetText(s.fastest and (U.DurationLong(s.fastest.t) .. " " .. level(s.fastest)) or dash())
	rows[2].value:SetText(s.slowest and (U.DurationLong(s.slowest.t) .. " " .. level(s.slowest)) or dash())
	rows[3].value:SetText(s.average and U.DurationLong(s.average) or dash())
	rows[4].value:SetText(s.count > 0 and (U.DurationLong(s.total) .. " " .. C(COLOR.grey, format(s.count == 1 and L["(%d level)"] or L["(%d levels)"], s.count))) or dash())
end

local function refresh(panel)
	if not ns.Tracker.char then
		return
	end
	refreshBanner(panel)
	refreshThisLevel(panel)
	refreshRecent(panel)
	refreshRecords(panel)
	tick(panel)
end

UI.RegisterPage({
	id = "overview",
	label = L["Overview"],
	order = 1,
	create = create,
	refresh = refresh,
	tick = tick,
})
