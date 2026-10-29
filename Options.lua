-- Options.lua: the Options page of the window, and a page in the game's settings (Esc > Options > AddOns).
local ADDON, ns = ...
local L, U, C, COLOR = ns.L, ns.U, ns.C, ns.COLOR
local W, Data, UI = ns.W, ns.Data, ns.UI

local format = string.format

local Options = ns:NewModule("Options")

local function changed(key)
	ns:Fire("SETTINGS_CHANGED", key)
end

local function setting(key)
	return function()
		return ns.S[key]
	end, function(on)
		ns.S[key] = on
		changed(key)
	end
end

local function header(parent, text, x, y)
	local fs = parent:CreateFontString(nil, "ARTWORK", "LevelTimeTrackerFontNormal")
	fs:SetPoint("TOPLEFT", x, y)
	fs:SetJustifyH("LEFT")
	fs:SetText(text)
	local line = W.Divider(parent, 0.3)
	line:SetPoint("TOPLEFT", fs, "BOTTOMLEFT", 0, -3)
	line:SetWidth(320)
	return fs
end

StaticPopupDialogs["LEVELTIMETRACKER_RESET"] = {
	text = L["Reset %s? Level Time Tracker deletes every level time it kept for this character and starts timing again from this level."],
	button1 = YES or "Yes",
	button2 = NO or "No",
	OnAccept = function()
		Options.ResetCharacter()
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	showAlert = true,
	preferredIndex = 3,
}

function Options.ResetCharacter()
	local T = ns.Tracker
	local c = T.char
	if not c then
		return
	end
	c.levels = {}
	c.first = { level = T.level, at = ns.Now() }
	ns:Fire("DATA_CHANGED", T.key)
	ns.Print(L["Every level time of this character is gone. Timing starts again from level %d."], T.level)
end

function Options.ConfirmReset()
	local c = ns.Tracker.char
	if c then
		StaticPopup_Show("LEVELTIMETRACKER_RESET", c.name or "?")
	end
end

local function create(panel)
	panel.controls = {}
	local function add(widget)
		panel.controls[#panel.controls + 1] = widget
		return widget
	end
	local x1, x2 = 8, 360
	local y = -6

	header(panel, L["Chat"], x1, y)
	local get, set = setting("announce")
	add(W.Check(panel, L["Tell me in chat when I level up"], L["A line in chat with the time the level took."], get, set))
		:SetPoint("TOPLEFT", x1, y - 22)
	get, set = setting("compare")
	panel.compare = add(W.Check(panel, L["Compare with the level before"], L["Adds how much faster or slower the level was than the one before it."], get, set))
	panel.compare:SetPoint("TOPLEFT", x1 + 18, y - 48)

	y = -100
	header(panel, L["Mini tracker"], x1, y)
	get, set = setting("mini")
	add(W.Check(panel, L["Show the mini tracker"], L["A small bar with your level, the time on it and the time to the next level. Click it to open this window."], get, set))
		:SetPoint("TOPLEFT", x1, y - 22)
	get, set = setting("miniLocked")
	add(W.Check(panel, L["Lock its position"], L["The mini tracker can't be dragged while this is on."], get, set))
		:SetPoint("TOPLEFT", x1 + 18, y - 48)
	get, set = setting("miniAtMax")
	add(W.Check(panel, L["Keep it at max level"], L["Without this, the mini tracker goes away once a character reaches max level."], get, set))
		:SetPoint("TOPLEFT", x1 + 18, y - 74)
	get, set = setting("miniHideCombat")
	add(W.Check(panel, L["Hide it in combat"], nil, get, set))
		:SetPoint("TOPLEFT", x1 + 18, y - 100)

	y = -6
	header(panel, L["Window"], x2, y)
	local slider = add(W.Slider(panel, L["UI size"], 70, 150, 5, function()
		return math.floor(W.Scale() * 100 + 0.5)
	end, function(v)
		ns.S.scale = v / 100
		changed("scale")
	end, "%d%%", 220))
	slider:SetPoint("TOPLEFT", x2 + 40, y - 46)

	local themeLabel = panel:CreateFontString(nil, "ARTWORK", "LevelTimeTrackerFontNormalSmall")
	themeLabel:SetPoint("TOPLEFT", x2, y - 92)
	themeLabel:SetJustifyH("LEFT")
	themeLabel:SetText(L["Look"])
	for i, id in ipairs(W.THEME_ORDER) do
		local th = W.THEMES[id]
		local rb = add(W.Radio(panel, th.name, th.desc, function()
			return W.themeId == id
		end, function()
			W.SetTheme(id)
			for _, w in ipairs(panel.controls) do
				if w.Refresh then
					w:Refresh()
				end
			end
		end))
		rb:SetPoint("TOPLEFT", x2 + 4 + ((i - 1) % 2) * 150, y - 110 - math.floor((i - 1) / 2) * 24)
	end

	y = -200
	header(panel, L["Data"], x2, y)
	panel.reset = W.Button(panel, L["Reset this character"], nil, Options.ConfirmReset,
		L["Deletes the level times of the character you are playing (asks first)."])
	panel.reset:SetPoint("TOPLEFT", x2, y - 26)
	panel.about = W.Text(panel, L["Level Time Tracker keeps the level times of all your characters on this account. The window and the mini tracker can also have keys of their own: see the game's key bindings, under AddOns."], 320, "GameFontHighlightSmall")
	panel.about:SetPoint("TOPLEFT", x2, y - 60)

	-- The slash commands, for reference.
	local box = W.Box(panel, L["Commands"])
	box:SetPoint("TOPLEFT", x1, -262)
	box:SetPoint("BOTTOMLEFT", x1, 0)
	box:SetWidth(330)
	box.rows = {}
	for i, cmd in ipairs(ns.COMMANDS or {}) do
		local row = CreateFrame("Frame", nil, box)
		row:SetHeight(18)
		row:SetPoint("TOPLEFT", 12, -10 - (i - 1) * 18)
		row:SetPoint("TOPRIGHT", -12, -10 - (i - 1) * 18)
		row.cmd = W.Label(row, cmd[1] ~= "" and ("/ltt " .. cmd[1]) or "/ltt", "GameFontHighlightSmall")
		row.cmd:SetPoint("LEFT")
		row.text = W.OneLine(W.Label(row, cmd[2], "GameFontDisableSmall"))
		row.text:SetPoint("LEFT", 84, 0)
		row.text:SetPoint("RIGHT")
		box.rows[i] = row
	end
	panel.commands = box

	panel.version = W.Label(panel, "", "GameFontDisableSmall")
	panel.version:SetPoint("BOTTOMRIGHT", -6, 4)
	panel.version:SetJustifyH("RIGHT")
end

local function refresh(panel)
	for _, w in ipairs(panel.controls) do
		if w.Refresh then
			w:Refresh()
		end
	end
	panel.compare:SetActive(ns.S.announce)
	panel.version:SetText(format(L["Version %s"], ns.version))
end

UI.RegisterPage({
	id = "options",
	label = L["Options"],
	order = 4,
	create = create,
	refresh = refresh,
})

---------------------------------------------------------------------------
-- The page in the game's settings: the main switches and a way into the window.
---------------------------------------------------------------------------
local blizz

local function buildBlizz()
	blizz = CreateFrame("Frame")
	blizz:Hide()
	local title = W.Label(blizz, ns.title, "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 16, -16)
	local version = W.Label(blizz, C(COLOR.grey, ns.version), "GameFontHighlightSmall")
	version:SetPoint("BOTTOMLEFT", title, "BOTTOMRIGHT", 6, 1)
	local text = W.Text(blizz, L["See how long every level takes, on every character. Type /ltt to open the window; everything else is on its Options page."], 520)
	text:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
	blizz.checks = {}
	local get, set = setting("announce")
	blizz.checks[1] = W.Check(blizz, L["Tell me in chat when I level up"], nil, get, set)
	blizz.checks[1]:SetPoint("TOPLEFT", 14, -84)
	get, set = setting("mini")
	blizz.checks[2] = W.Check(blizz, L["Show the mini tracker"], nil, get, set)
	blizz.checks[2]:SetPoint("TOPLEFT", 14, -110)
	blizz.open = W.Button(blizz, L["Open Level Time Tracker"], nil, function()
		if SettingsPanel and SettingsPanel:IsShown() and HideUIPanel then
			HideUIPanel(SettingsPanel)
		end
		UI.Show("overview")
	end)
	blizz.open:SetPoint("TOPLEFT", 18, -146)
	local function refreshBlizz()
		for _, cb in ipairs(blizz.checks) do
			cb:Refresh()
		end
	end
	blizz:SetScript("OnShow", refreshBlizz)
	function blizz:OnRefresh()
		refreshBlizz()
	end
	function blizz:OnDefault()
		local defaults = Data.Defaults()
		ns.S.announce, ns.S.mini = defaults.announce, defaults.mini
		changed("announce")
		changed("mini")
		refreshBlizz()
	end
	function blizz:OnCommit() end
	return blizz
end

function Options:Init()
	if blizz or not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then
		return
	end
	buildBlizz()
	local ok, category = pcall(Settings.RegisterCanvasLayoutCategory, blizz, ns.title)
	if ok and category then
		pcall(Settings.RegisterAddOnCategory, category)
	end
end

ns:On("SETTINGS_CHANGED", function()
	if blizz and blizz:IsShown() then
		blizz:OnRefresh()
	end
end)
