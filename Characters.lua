-- Characters.lua: every character on this account that Level Time Tracker has seen.
local ADDON, ns = ...
local L, U, C, COLOR = ns.L, ns.U, ns.C, ns.COLOR
local W, Data, UI = ns.W, ns.Data, ns.UI

local format, floor = string.format, math.floor

local stats = {}

local function statsOf(c)
	local s = stats[c]
	if not s then
		s = Data.Stats(c)
		stats[c] = s
	end
	return s
end

local COLUMNS = {
	{
		key = "name", label = L["Character"], fill = true,
		get = function(c)
			local you = c.key == ns.Tracker.key and C(COLOR.grey, " " .. L["(you)"]) or ""
			return format("%s %s%s  %s", U.ClassIcon(c.class, 14), C(U.ClassHex(c.class), c.name or "?"), you, C(COLOR.grey, c.realm or ""))
		end,
		sortValue = function(c)
			return (c.name or ""):lower() .. "-" .. (c.realm or ""):lower()
		end,
	},
	{
		key = "level", label = L["Level"], width = 86, defaultDesc = true,
		get = function(c)
			local level = c.level or 0
			if c.maxLevel and level >= c.maxLevel then
				return tostring(level), 0.25, 1, 0.25
			end
			local pct = (c.xpMax or 0) > 0 and floor((c.xpCur or 0) / c.xpMax * 100) or nil
			return pct and format("%d %s", level, C(COLOR.grey, format("(%d%%)", pct))) or tostring(level)
		end,
		sortValue = function(c)
			local frac = (c.xpMax or 0) > 0 and (c.xpCur or 0) / c.xpMax or 0
			return (c.level or 0) + frac * 0.99
		end,
	},
	{
		key = "leveling", label = L["Time leveling"], width = 112, justify = "RIGHT", defaultDesc = true,
		tip = L["All timed levels together."],
		get = function(c)
			local s = statsOf(c)
			return s.count > 0 and U.Duration(s.total) or C(COLOR.grey, "-")
		end,
		sortValue = function(c)
			return statsOf(c).total
		end,
	},
	{
		key = "average", label = L["Average level"], width = 104, justify = "RIGHT", defaultDesc = true,
		get = function(c)
			local s = statsOf(c)
			return s.average and U.Duration(s.average) or C(COLOR.grey, "-")
		end,
		sortValue = function(c)
			return statsOf(c).average
		end,
	},
	{
		key = "played", label = L["/played"], width = 92, justify = "RIGHT", defaultDesc = true,
		tip = L["/played in total, as it was when you last played the character."],
		get = function(c)
			local played = c.key == ns.Tracker.key and ns.Tracker:Played() or c.played
			return played and U.Duration(played) or C(COLOR.grey, "-")
		end,
		sortValue = function(c)
			return c.played
		end,
	},
	{
		key = "seen", label = L["Last played"], width = 104, defaultDesc = true,
		get = function(c)
			if c.key == ns.Tracker.key then
				return L["Now"], 0.25, 1, 0.25
			end
			return U.Ago(c.lastSeen), 0.75, 0.75, 0.75
		end,
		sortValue = function(c)
			return c.key == ns.Tracker.key and math.huge or (c.lastSeen or 0)
		end,
	},
}

StaticPopupDialogs["LEVELTIMETRACKER_FORGET"] = {
	text = L["Forget %s? Level Time Tracker deletes every level time it kept for this character."],
	button1 = YES or "Yes",
	button2 = NO or "No",
	OnAccept = function(_, key)
		Data.Forget(key)
		if UI.viewKey == key then
			UI.viewKey = nil
		end
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	showAlert = true,
	preferredIndex = 3,
}

local function charTip(c, row)
	local s = statsOf(c)
	local lines = {
		{ L["Level"], tostring(c.level or "?") },
	}
	if s.count > 0 then
		lines[#lines + 1] = { L["Levels timed"], tostring(s.count) }
		lines[#lines + 1] = { L["Time leveling"], U.DurationLong(s.total) }
		lines[#lines + 1] = { L["Fastest level"], format("%s (%d)", U.Duration(s.fastest.t), s.fastest.level) }
		lines[#lines + 1] = { L["Slowest level"], format("%s (%d)", U.Duration(s.slowest.t), s.slowest.level) }
	end
	if c.first and c.first.level then
		lines[#lines + 1] = { L["Timing since level"], tostring(c.first.level) }
	end
	lines[#lines + 1] = " "
	lines[#lines + 1] = C(COLOR.grey, L["Click: show the levels"])
	if c.key ~= ns.Tracker.key then
		lines[#lines + 1] = C(COLOR.grey, L["Right-click: forget this character"])
	end
	W.ShowTip(row, C(U.ClassHex(c.class), (c.name or "?") .. " - " .. (c.realm or "")), lines)
end

local function create(panel)
	panel.title = W.OneLine(panel:CreateFontString(nil, "ARTWORK", "LevelTimeTrackerFontNormalLarge"))
	panel.title:SetPoint("TOPLEFT", 4, -4)
	panel.title:SetText(L["Characters on this account"])
	panel.summary = W.OneLine(W.Label(panel, "", "GameFontHighlightSmall"))
	panel.summary:SetPoint("TOPLEFT", panel.title, "BOTTOMLEFT", 0, -5)
	panel.hint = W.Label(panel, L["Click a character to see its levels. Right-click to forget one."], "GameFontDisableSmall")
	panel.hint:SetPoint("BOTTOMRIGHT", panel, "TOPRIGHT", -4, -38)
	panel.hint:SetJustifyH("RIGHT")

	panel.list = W.List(panel, COLUMNS, {
		rowHeight = 20,
		sortKey = "seen",
		sortDesc = true,
		selectKey = function(c)
			return c.key
		end,
		empty = L["No characters yet."],
		onEnter = charTip,
		onClick = function(c, _, button)
			if button == "RightButton" then
				if c.key ~= ns.Tracker.key then
					StaticPopup_Show("LEVELTIMETRACKER_FORGET", (c.name or "?") .. " - " .. (c.realm or ""), nil, c.key)
				end
				return
			end
			UI.ShowLevels(c.key)
		end,
	})
	panel.list:SetPoint("TOPLEFT", 0, -46)
	panel.list:SetPoint("BOTTOMRIGHT", 0, 0)
end

local function refresh(panel)
	wipe(stats)
	local list = Data.Characters()
	local leveling, total = 0, 0
	for _, c in ipairs(list) do
		total = total + 1
		if not (c.maxLevel and (c.level or 0) >= c.maxLevel) then
			leveling = leveling + 1
		end
	end
	panel.summary:SetText(format(L["%d characters, %d still leveling"], total, leveling))
	panel.list.selected = UI.ViewKey()
	panel.list:SetData(list)
end

UI.RegisterPage({
	id = "characters",
	label = L["Characters"],
	tip = L["All your characters: level, time spent leveling and /played."],
	order = 3,
	create = create,
	refresh = refresh,
})
