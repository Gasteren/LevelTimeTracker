-- Levels.lua: every level of a character (the one you play, or one picked on the Characters page).
local ADDON, ns = ...
local L, U, C, COLOR = ns.L, ns.U, ns.C, ns.COLOR
local W, Data, UI = ns.W, ns.Data, ns.UI

local format, floor, max = string.format, math.floor, math.max

local function timed(item)
	return Data.Timed(item) and item.t or nil
end

local COLUMNS = {
	{
		key = "level", label = L["Level"], width = 84, defaultDesc = true,
		get = function(item)
			return format("%d %s %d", item.level, UI.ARROW, item.level + 1), W.theme.label[1], W.theme.label[2], W.theme.label[3]
		end,
		sortValue = function(item)
			return item.level
		end,
	},
	{
		key = "time", label = L["Time"], width = 96, justify = "RIGHT", defaultDesc = true,
		tip = L["How long the level took, counted like /played."],
		get = function(item)
			if item.skipped then
				return L["skipped"], 0.6, 0.6, 0.6
			elseif not Data.Timed(item) then
				return L["not timed"], 0.6, 0.6, 0.6
			end
			local s = UI.levelStats
			if s and s.count > 2 and s.fastest and item.level == s.fastest.level then
				return U.Duration(item.t), 0.25, 1, 0.25
			elseif s and s.count > 2 and s.slowest and item.level == s.slowest.level then
				return U.Duration(item.t), 1, 0.5, 0.25
			end
			return U.Duration(item.t)
		end,
		sortValue = timed,
	},
	{
		key = "pace", label = L["Compared"], fill = true,
		tip = L["The bar is the level's time next to the slowest level shown. The fastest level is green, the slowest orange."],
		get = function()
			return ""
		end,
	},
	{
		key = "reached", label = L["Reached"], width = 124, defaultDesc = true,
		get = function(item)
			return item.at and U.DateTime(item.at) or "", 0.75, 0.75, 0.75
		end,
		sortValue = function(item)
			return item.at
		end,
	},
	{
		key = "played", label = L["/played"], width = 86, justify = "RIGHT", defaultDesc = true,
		tip = L["/played in total when the level was reached."],
		get = function(item)
			return item.played and U.Duration(item.played) or "", 0.75, 0.75, 0.75
		end,
		sortValue = function(item)
			return item.played
		end,
	},
	{
		key = "zone", label = L["Zone"], width = 142,
		get = function(item)
			return item.zone or "", 0.75, 0.75, 0.75
		end,
		sortValue = function(item)
			return item.zone
		end,
	},
}

-- The pace bar in the "Compared" column.
local function decorate(row, item, list)
	local bar = row.pace
	if not bar then
		bar = W.PaceBar(row, 8)
		row.pace = bar
	end
	local x, w = list:Column("pace")
	bar:ClearAllPoints()
	bar:SetPoint("LEFT", row, "LEFT", x + 8, 0)
	bar:SetWidth(max(1, w - 16))
	local s = UI.levelStats
	local longest = s and s.slowest and s.slowest.t or 0
	local t = Data.Timed(item) and item.t or 0
	if s and s.count > 2 and t > 0 and item.level == s.fastest.level then
		bar:SetPace(t, longest, 0.2, 0.75, 0.2)
	elseif s and s.count > 2 and t > 0 and item.level == s.slowest.level then
		bar:SetPace(t, longest, 0.9, 0.45, 0.1)
	else
		bar:SetPace(t, longest)
	end
end

local function create(panel)
	panel.name = W.OneLine(panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge"))
	panel.name:SetPoint("TOPLEFT", 4, -4)
	panel.name:SetJustifyH("LEFT")
	panel.summary = W.OneLine(W.Label(panel, "", "GameFontHighlightSmall"))
	panel.summary:SetPoint("TOPLEFT", panel.name, "BOTTOMLEFT", 0, -5)
	panel.summary:SetPoint("RIGHT", -170, 0)

	panel.mine = W.Button(panel, L["Back to my character"], nil, function()
		UI.ShowLevels(nil)
	end)
	panel.mine:SetPoint("TOPRIGHT", 0, -6)

	panel.list = W.List(panel, COLUMNS, {
		rowHeight = 18,
		sortKey = "level",
		sortDesc = true,
		decorate = decorate,
		empty = L["No levels yet. Every level-up from now on shows up here, with the time it took."],
		onEnter = function(item, row)
			UI.LevelTip(row, item, UI.ViewChar())
		end,
	})
	panel.list:SetPoint("TOPLEFT", 0, -46)
	panel.list:SetPoint("BOTTOMRIGHT", 0, 0)
end

local function refresh(panel)
	local c = UI.ViewChar()
	if not c then
		return
	end
	local mine = UI.ViewKey() == ns.Tracker.key
	panel.mine:SetShown(not mine)
	panel.name:SetText(format("%s %s", U.ClassIcon(c.class, 18), C(U.ClassHex(c.class), c.name or "?"))
		.. C(COLOR.grey, "  " .. (c.realm or "")))
	local s = Data.Stats(c)
	UI.levelStats = s
	local parts = { format(L["Level %d"], c.level or 0) }
	if s.count > 0 then
		parts[#parts + 1] = format(s.count == 1 and L["%d level timed"] or L["%d levels timed"], s.count)
		parts[#parts + 1] = format(L["%s in total"], U.Duration(s.total))
		parts[#parts + 1] = format(L["%s on average"], U.Duration(s.average))
	end
	if s.skipped > 0 then
		parts[#parts + 1] = format(L["%d skipped"], s.skipped)
	end
	panel.summary:SetText(table.concat(parts, "  " .. UI.DOT .. "  "))
	panel.list:SetData(Data.Levels(c))
end

UI.RegisterPage({
	id = "levels",
	label = L["Levels"],
	tip = L["Every level, with the time it took, when and where."],
	order = 2,
	create = create,
	refresh = refresh,
})
