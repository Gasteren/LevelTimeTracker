-- wow_mock.lua: the game API Level Time Tracker uses, Blizzard's templates, a player who gains XP and levels, the realm's
-- /played clock and the chat windows that print /played. Globals provided by the runner: ROOT, MOCK_FLAVOR.
dofile(ROOT .. "/tests/mock_widgets.lua")

-- "midnight" (Retail 12.1.5) or "forever" (WoW Forever 1.60.1): both run the same modern client and interface code;
-- they differ in max level (90 and 60) and in their XP curve.
MOCK.flavor = MOCK_FLAVOR or "midnight"
local FOREVER = MOCK.flavor == "forever"

local Widget, Methods = MOCK.Widget, MOCK.Methods

MOCK.api = {}
MOCK.apiRead = {}
MOCK.printed = {}
MOCK.chat = {}
MOCK.sounds = {}
MOCK.timers = {}
MOCK.popups = {}
MOCK.errors = {}
MOCK.texturesUsed = {}
MOCK.requests = 0
MOCK.chatPlayed = 0
local api = MOCK.api

-- Time: GetTime() (seconds since the computer started) and the realm's clock.
MOCK.now = 5000
MOCK.epoch = 1793000000 -- 2026-10-26
local START = MOCK.now
function MOCK.ServerTime()
	return MOCK.epoch + math.floor(MOCK.now - START)
end

-- Lua extras -----------------------------------------------------------------------------------------------------------
api.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
api.tinsert, api.tremove = table.insert, table.remove
api.time = function(t)
	if t then return os.time(t) end
	return MOCK.ServerTime()
end
api.date = function(fmt, t) return os.date(fmt, t or MOCK.ServerTime()) end
api.GetTime = function() return MOCK.now end
api.GetServerTime = function() return MOCK.ServerTime() end
api.geterrorhandler = function()
	return function(err) table.insert(MOCK.errors, tostring(err)) end
end
api.issecretvalue = function(v) return MOCK.secrets ~= nil and v ~= nil and MOCK.secrets[v] == true end
print = function(...)
	local parts = {}
	for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
	table.insert(MOCK.printed, table.concat(parts, " "))
end
api.Mixin = function(obj, ...)
	for i = 1, select("#", ...) do
		for k, v in pairs((select(i, ...))) do rawset(obj, k, v) end
	end
	return obj
end
api.BackdropTemplateMixin = MOCK.BackdropMixin
-- Post-hooks a global function, like the game's: the original runs first, then the hook, with the same arguments.
api.hooksecurefunc = function(name, hook)
	assert(type(name) == "string" and type(hook) == "function", "hooksecurefunc(name, hook)")
	local original = assert(rawget(_G, name) or api[name], "hooksecurefunc: no global " .. tostring(name))
	local wrapped = function(...)
		local results = { original(...) }
		hook(...)
		return unpack(results)
	end
	if rawget(_G, name) then
		rawset(_G, name, wrapped)
	else
		api[name] = wrapped
	end
end
api.C_Timer = {
	After = function(delay, fn)
		assert(type(delay) == "number" and type(fn) == "function", "C_Timer.After(delay, fn)")
		table.insert(MOCK.timers, { at = MOCK.now + delay, fn = fn })
	end,
}

-- Like the game after laying frames out: frames whose size changed get OnSizeChanged (lists make their rows then).
function MOCK.Layout()
	for _ = 1, 6 do
		local changed = false
		for _, f in ipairs(MOCK.frames) do
			local listens = f._scripts.OnSizeChanged or (f._hooks.OnSizeChanged and #f._hooks.OnSizeChanged > 0)
			if listens and Widget.Visible(f) then
				local r = Widget.Rect(f)
				if r then
					local s = Widget.Scale(f)
					local w, h = r.w / s, r.h / s
					local last = f._lastSize
					if not last or math.abs(last[1] - w) > 0.01 or math.abs(last[2] - h) > 0.01 then
						f._lastSize = { w, h }
						changed = true
						Widget.Fire(f, "OnSizeChanged", w, h)
					end
				end
			end
		end
		if not changed then
			return
		end
	end
end

-- Time passes: timers come due, frames are laid out and the visible frames' OnUpdate scripts run (every `step` s).
function MOCK.Advance(seconds, step)
	seconds = seconds or 0
	step = step or math.max(seconds, 0.001)
	local left = seconds
	repeat
		local dt = math.min(step, left)
		MOCK.now = MOCK.now + dt
		left = left - dt
		local guard = 0
		while true do
			local due, at
			for i, t in ipairs(MOCK.timers) do
				if t.at <= MOCK.now and (not at or t.at < at) then due, at = i, t.at end
			end
			if not due then break end
			local t = table.remove(MOCK.timers, due)
			t.fn()
			guard = guard + 1
			assert(guard < 1000, "timer loop")
		end
		MOCK.Layout()
		for _, f in ipairs(MOCK.frames) do
			local fn = f._scripts.OnUpdate
			if fn and Widget.Visible(f) then fn(f, dt) end
		end
	until left <= 0
end

-- Events in the order frames registered for them.
function MOCK.Fire(event, ...)
	assert(MOCK.KNOWN_EVENTS == nil or MOCK.KNOWN_EVENTS[event], "unknown event " .. tostring(event))
	for _, f in ipairs(MOCK.listeners) do
		if f._events[event] then
			Widget.Fire(f, "OnEvent", event, ...)
		end
	end
end

-- Textures, atlases, fonts -----------------------------------------------------------------------------------------------
local setTexture = Methods.Texture.SetTexture
Methods.Texture.SetTexture = function(self, file, ...)
	if type(file) == "string" and not file:find("^portrait:") and not MOCK.inTemplate then
		MOCK.texturesUsed[file] = true
	end
	return setTexture(self, file, ...)
end
MOCK.atlases = {
	["QuestSharing-Dialog-Portrait"] = { width = 64, height = 64, file = 3064322, left = 0.002, right = 0.127, top = 0.039, bottom = 0.539 },
	["uiframe-tab-left"] = { width = 32, height = 32 }, ["_uiframe-tab-center"] = { width = 32, height = 32 },
	["uiframe-tab-right"] = { width = 32, height = 32 }, ["uiframe-activetab-left"] = { width = 32, height = 35 },
	["_uiframe-activetab-center"] = { width = 32, height = 35 }, ["uiframe-activetab-right"] = { width = 32, height = 35 },
}
MOCK.atlasesUsed = {}
local setAtlas = Methods.Texture.SetAtlas
Methods.Texture.SetAtlas = function(self, atlas, ...)
	MOCK.atlasesUsed[atlas] = true
	return setAtlas(self, atlas, ...)
end
api.C_Texture = {
	GetAtlasInfo = function(name)
		local a = MOCK.atlases[name]
		if a then return { width = a.width, height = a.height, file = a.file } end
	end,
}
MOCK.missingFiles = {}
api.GetFileIDFromPath = function(path)
	if MOCK.missingFiles[path] then return nil end
	return 1
end

local FONTS = {
	GameFontNormal = { 1, 0.82, 0 }, GameFontNormalSmall = { 1, 0.82, 0 }, GameFontNormalLarge = { 1, 0.82, 0 },
	GameFontNormalHuge = { 1, 0.82, 0 }, GameFontHighlight = { 1, 1, 1 }, GameFontHighlightSmall = { 1, 1, 1 },
	GameFontHighlightLarge = { 1, 1, 1 }, GameFontHighlightHuge = { 1, 1, 1 }, GameFontDisable = { 0.5, 0.5, 0.5 },
	GameFontDisableSmall = { 0.5, 0.5, 0.5 }, TextStatusBarText = { 1, 1, 1 }, ChatFontNormal = { 1, 1, 1 },
}
for name, c in pairs(FONTS) do
	api[name] = MOCK.NewFont(name, c[1], c[2], c[3])
end
api.CreateFont = function(name)
	local font = MOCK.NewFont(name)
	if name then rawset(_G, name, font) end
	return font
end

api.SOUNDKIT = { IG_MAINMENU_OPEN = 850, IG_MAINMENU_CLOSE = 851, IG_CHARACTER_INFO_TAB = 841,
	IG_MAINMENU_OPTION_CHECKBOX_ON = 856, IG_MAINMENU_OPTION_CHECKBOX_OFF = 857 }
api.PlaySound = function(id) table.insert(MOCK.sounds, id) end

api.C_AddOns = {
	GetAddOnMetadata = function(addon, field)
		local f = assert(io.open(ROOT .. "/" .. addon .. ".toc", "r"))
		local text = f:read("*a")
		f:close()
		return text:match("## " .. field .. ":%s*([^\r\n]-)%s*[\r\n]")
	end,
}

-- The player -------------------------------------------------------------------------------------------------------------
MOCK.maxLevel = FOREVER and 60 or 90
function MOCK.XPFor(level)
	return FOREVER and (400 + level * 180) or (1000 + level * 250)
end
MOCK.player = {
	name = "Frost", realm = "Lightbringer", level = 12, xp = 0, rested = 0, class = "MAGE", className = "Mage",
	race = "Human", faction = "Alliance", zone = "Elwynn Forest", resting = false, xpDisabled = false,
}
MOCK.player.xpMax = MOCK.XPFor(MOCK.player.level)
-- The realm's /played: in total and on this level.
MOCK.played = { total = 5 * 3600, level = 900, at = MOCK.now }
function MOCK.Played()
	local p = MOCK.played
	local since = MOCK.now - p.at
	return p.total + since, p.level + since
end
MOCK.playedDelay = 0.4

local function player(unit) return unit == "player" end
api.UnitName = function(unit) if player(unit) then return MOCK.player.name end end
api.GetNormalizedRealmName = function() return MOCK.player.realm end
api.GetRealmName = function() return MOCK.player.realm end
api.UnitLevel = function(unit) if player(unit) then return MOCK.player.level end return 0 end
api.UnitXP = function(unit) assert(player(unit), "UnitXP for " .. tostring(unit)) return MOCK.player.xp end
api.UnitXPMax = function(unit) assert(player(unit), "UnitXPMax for " .. tostring(unit)) return MOCK.player.xpMax end
api.GetXPExhaustion = function() local r = MOCK.player.rested return r > 0 and r or nil end
api.IsXPUserDisabled = function() return MOCK.player.xpDisabled end
api.IsResting = function() return MOCK.player.resting end
api.UnitClass = function(unit) if player(unit) then return MOCK.player.className, MOCK.player.class, 8 end end
api.UnitRace = function(unit) if player(unit) then return MOCK.player.race, MOCK.player.race, 1 end end
api.UnitFactionGroup = function(unit) if player(unit) then return MOCK.player.faction, MOCK.player.faction end end
api.GetRealZoneText = function() return MOCK.player.zone end
api.GetMaxPlayerLevel = function() return MOCK.maxLevel end
api.GetMaxLevelForPlayerExpansion = function() return MOCK.maxLevel end
api.GameRulesUtil = { GetEffectiveMaxLevelForPlayer = function() return MOCK.maxLevel end }
api.InCombatLockdown = function() return MOCK.combat == true end
api.C_PetBattles = { IsInBattle = function() return MOCK.petBattle == true end }
api.SetPortraitTexture = function(texture, unit) texture:SetTexture("portrait:" .. unit) end
api.RequestTimePlayed = function()
	MOCK.requests = MOCK.requests + 1
	if MOCK.playedNoAnswer then return end
	api.C_Timer.After(MOCK.playedDelay, function()
		MOCK.Fire("TIME_PLAYED_MSG", MOCK.Played())
	end)
end

-- The player gains XP (and levels, in the order the game sends the events: MOCK.order = "levelFirst" or "xpFirst").
function MOCK.GainXP(amount)
	local p = MOCK.player
	local old = p.level
	p.xp = p.xp + amount
	local reached = {}
	while p.level < MOCK.maxLevel and p.xp >= p.xpMax do
		p.xp = p.xp - p.xpMax
		p.level = p.level + 1
		p.xpMax = MOCK.XPFor(p.level)
		reached[#reached + 1] = p.level
	end
	if #reached > 0 then
		-- The realm starts counting the new level.
		local total = MOCK.Played()
		MOCK.played = { total = total, level = 0, at = MOCK.now }
	end
	if p.level >= MOCK.maxLevel then
		p.xp, p.xpMax = 0, 0
	end
	local function levelEvents()
		if MOCK.oneLevelUpEvent and #reached > 0 then
			MOCK.Fire("PLAYER_LEVEL_UP", p.level)
		else
			for _, lvl in ipairs(reached) do
				MOCK.Fire("PLAYER_LEVEL_UP", lvl)
			end
		end
		if #reached > 0 and not MOCK.noLevelChanged then
			MOCK.Fire("PLAYER_LEVEL_CHANGED", old, p.level, true)
		end
	end
	if MOCK.order == "xpFirst" then
		MOCK.Fire("PLAYER_XP_UPDATE", "player")
		levelEvents()
	else
		levelEvents()
		MOCK.Fire("PLAYER_XP_UPDATE", "player")
	end
end

-- Enough XP to reach the next level exactly.
function MOCK.LevelUp()
	MOCK.GainXP(MOCK.player.xpMax - MOCK.player.xp)
end

-- Strings, classes, numbers ----------------------------------------------------------------------------------------------
YES, NO = "Yes", "No"
api.LOCALIZED_CLASS_NAMES_MALE = { MAGE = "Mage", WARRIOR = "Warrior", PRIEST = "Priest", ROGUE = "Rogue" }
api.RAID_CLASS_COLORS = {
	MAGE = { r = 0.25, g = 0.78, b = 0.92 }, WARRIOR = { r = 0.78, g = 0.61, b = 0.43 },
	PRIEST = { r = 1, g = 1, b = 1 }, ROGUE = { r = 1, g = 0.96, b = 0.41 },
}
api.C_ClassColor = { GetClassColor = function(class) return api.RAID_CLASS_COLORS[class] end }
api.CLASS_ICON_TCOORDS = {
	WARRIOR = { 0, 0.25, 0, 0.25 }, MAGE = { 0.25, 0.49609375, 0, 0.25 }, ROGUE = { 0.49609375, 0.7421875, 0, 0.25 },
	PRIEST = { 0.49609375, 0.7421875, 0.25, 0.5 },
}
api.BreakUpLargeNumbers = function(n)
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
	return out
end

-- Chat windows: they print /played when TIME_PLAYED_MSG reaches them (ChatFrameUtil.DisplayTimePlayed).
api.NUM_CHAT_WINDOWS = 10
api.CHAT_FRAMES = {}
Methods.ScrollingMessageFrame = setmetatable({}, { __index = Methods.Frame })
function Methods.ScrollingMessageFrame:AddMessage(text)
	table.insert(MOCK.chat, (MOCK.Plain(tostring(text))))
end
local function ChatFrame(i, systemMessages)
	local f = MOCK.Widget.NewFrame("Frame", nil, nil)
	f._kind = "ScrollingMessageFrame"
	rawset(_G, "ChatFrame" .. i, f)
	table.insert(api.CHAT_FRAMES, "ChatFrame" .. i)
	if systemMessages then
		f:RegisterEvent("TIME_PLAYED_MSG")
	end
	f:SetScript("OnEvent", function(self, event, total)
		if event == "TIME_PLAYED_MSG" then
			MOCK.chatPlayed = MOCK.chatPlayed + 1
			self:AddMessage("Total time played: " .. tostring(total))
		end
	end)
	return f
end
-- The game always has ten chat windows; three of these show system messages (and so /played).
for i = 1, 10 do ChatFrame(i, i <= 3) end
api.DEFAULT_CHAT_FRAME = rawget(_G, "ChatFrame1")

-- Templates (what the addon uses) ----------------------------------------------------------------------------------------
local Templates = MOCK.Templates
Templates.BackdropTemplate = function(f)
	api.Mixin(f, api.BackdropTemplateMixin)
end
Templates.UIPanelButtonTemplate = function(b)
	-- SecureUIPanelTemplates.xml (UIPanelButtonNoTooltipTemplate), identical in both games.
	local file = "Interface\\Buttons\\UI-Panel-Button-Up"
	b:SetSize(40, 22)
	b.Left = b:CreateTexture(nil, "BACKGROUND")
	b.Left:SetTexture(file)
	b.Left:SetTexCoord(0, 0.09375, 0, 0.6875)
	b.Left:SetPoint("TOPLEFT")
	b.Left:SetPoint("BOTTOMLEFT")
	b.Left:SetWidth(12)
	b.Right = b:CreateTexture(nil, "BACKGROUND")
	b.Right:SetTexture(file)
	b.Right:SetTexCoord(0.53125, 0.625, 0, 0.6875)
	b.Right:SetPoint("TOPRIGHT")
	b.Right:SetPoint("BOTTOMRIGHT")
	b.Right:SetWidth(12)
	b.Middle = b:CreateTexture(nil, "BACKGROUND")
	b.Middle:SetTexture(file)
	b.Middle:SetTexCoord(0.09375, 0.53125, 0, 0.6875)
	b.Middle:SetPoint("TOPLEFT", b.Left, "TOPRIGHT")
	b.Middle:SetPoint("BOTTOMRIGHT", b.Right, "BOTTOMLEFT")
	local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	fs:SetPoint("CENTER")
	b:SetFontString(fs)
	b.Text = fs
	b:SetNormalFontObject("GameFontNormal")
	b:SetHighlightFontObject("GameFontHighlight")
	b:SetDisabledFontObject("GameFontDisable")
	b:SetHighlightTexture("Interface\\Buttons\\UI-Panel-Button-Highlight", "ADD")
	b:GetHighlightTexture():SetTexCoord(0, 0.625, 0, 0.6875)
	b._template = "UIPanelButtonTemplate"
end
Templates.UIPanelCloseButton = function(b)
	b:SetSize(24, 24)
	b._template = "UIPanelCloseButton"
end
local function CheckArt(b)
	b:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
	b:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
	b:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight", "ADD")
	b:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
	b:SetDisabledCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check-Disabled")
end
Templates.UICheckButtonTemplate = function(b)
	b:SetSize(32, 32)
	CheckArt(b)
	b.Text = b:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	b.Text:SetPoint("LEFT", b, "RIGHT", -2, 0)
	b._template = "UICheckButtonTemplate"
end
Templates.UIRadioButtonTemplate = function(b)
	b:SetSize(16, 16)
	b:SetNormalTexture("Interface\\Buttons\\UI-RadioButton")
	b:GetNormalTexture():SetTexCoord(0, 0.25, 0, 1)
	b:SetHighlightTexture("Interface\\Buttons\\UI-RadioButton", "ADD")
	b:GetHighlightTexture():SetTexCoord(0.5, 0.75, 0, 1)
	b:SetCheckedTexture("Interface\\Buttons\\UI-RadioButton")
	b:GetCheckedTexture():SetTexCoord(0.25, 0.5, 0, 1)
	b.text = b:CreateFontString(nil, "BACKGROUND", "GameFontNormalSmall")
	b.text:SetPoint("LEFT", b, "RIGHT", 5, 0)
	b._template = "UIRadioButtonTemplate"
end
Templates.UIPanelScrollBarTemplate = function(s)
	s:SetWidth(16)
	s.ScrollUpButton = CreateFrame("Button", nil, s)
	s.ScrollUpButton:SetSize(18, 16)
	s.ScrollUpButton:SetPoint("BOTTOM", s, "TOP")
	s.ScrollUpButton:SetNormalTexture("Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Up")
	s.ScrollUpButton:SetPushedTexture("Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Down")
	s.ScrollUpButton:SetDisabledTexture("Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Disabled")
	s.ScrollUpButton:SetHighlightTexture("Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Highlight", "ADD")
	s.ScrollDownButton = CreateFrame("Button", nil, s)
	s.ScrollDownButton:SetSize(18, 16)
	s.ScrollDownButton:SetPoint("TOP", s, "BOTTOM")
	s.ScrollDownButton:SetNormalTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Up")
	s.ScrollDownButton:SetPushedTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Down")
	s.ScrollDownButton:SetDisabledTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Disabled")
	s.ScrollDownButton:SetHighlightTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Highlight", "ADD")
	s:SetThumbTexture("Interface\\Buttons\\UI-ScrollBar-Knob")
	s:GetThumbTexture():SetSize(18, 24)
	s:SetScript("OnValueChanged", function(self)
		error("UIPanelScrollBarTemplate's own OnValueChanged scrolls its parent, which must be a ScrollFrame")
	end)
end

-- UIParent, tooltip, windows, popups, settings -----------------------------------------------------------------------
UIParent = MOCK.Widget.NewFrame("Frame", "UIParent", nil)
UIParent._strata = "MEDIUM"
GameTooltip = CreateFrame("GameTooltip", "GameTooltip", UIParent)
GameTooltip:Hide()
GameTooltip._lines = {}

api.UISpecialFrames = {}
api.StaticPopupDialogs = {}
api.StaticPopup_Show = function(which, a1, a2, data)
	local dialog = assert(api.StaticPopupDialogs[which], "no popup " .. tostring(which))
	table.insert(MOCK.popups, { which = which, text = dialog.text:format(a1, a2), data = data })
end
function MOCK.AcceptPopup()
	local p = assert(table.remove(MOCK.popups), "no popup is showing")
	api.StaticPopupDialogs[p.which].OnAccept({}, p.data)
	return p
end
function MOCK.PressEscape()
	for _, name in ipairs(api.UISpecialFrames) do
		local f = rawget(_G, name)
		if f and f:IsShown() then f:Hide() end
	end
end
api.SlashCmdList = {}
api.HideUIPanel = function(frame) frame:Hide() end
api.SettingsPanel = CreateFrame("Frame", nil, UIParent)
api.SettingsPanel:Hide()
MOCK.settings = {}
api.Settings = {
	RegisterCanvasLayoutCategory = function(panel, name)
		MOCK.settings.panel, MOCK.settings.name = panel, name
		MOCK.settings.category = { GetID = function() return 42 end }
		return MOCK.settings.category
	end,
	RegisterAddOnCategory = function(category) MOCK.settings.registered = category end,
	OpenToCategory = function(id) MOCK.settings.opened = id end,
}
