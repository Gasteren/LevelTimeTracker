-- Slash.lua: /ltt, the addon compartment (the minimap's list of addons) and the key bindings.
local ADDON, ns = ...
local L, U, C, COLOR = ns.L, ns.U, ns.C, ns.COLOR
local UI = ns.UI

local format = string.format

-- For Bindings.xml.
function ns.Toggle(page)
	UI.Toggle(page)
end

function ns.ToggleMini()
	ns.Mini.Toggle()
end

local COMMANDS = {
	{ "", L["open or close the window"] },
	{ "levels", L["every level of this character"] },
	{ "chars", L["all your characters"] },
	{ "options", L["the options"] },
	{ "mini", L["show or hide the mini tracker"] },
	{ "lock", L["lock or unlock the mini tracker"] },
	{ "played", L["ask the game for /played again (and show it)"] },
	{ "reset", L["delete this character's level times (asks first)"] },
}
ns.COMMANDS = COMMANDS

local function help()
	ns.Print(L["commands:"])
	for _, c in ipairs(COMMANDS) do
		local cmd = c[1] ~= "" and ("/ltt " .. c[1]) or "/ltt"
		DEFAULT_CHAT_FRAME:AddMessage(format("   %s  %s", C(COLOR.white, cmd), c[2]))
	end
end

local ACTIONS = {
	[""] = function()
		UI.Toggle()
	end,
	overview = function()
		UI.Show("overview")
	end,
	levels = function()
		UI.ShowLevels(nil)
	end,
	chars = function()
		UI.Show("characters")
	end,
	options = function()
		UI.Show("options")
	end,
	mini = function()
		ns.Mini.Toggle()
	end,
	lock = function()
		ns.S.miniLocked = not ns.S.miniLocked
		ns:Fire("SETTINGS_CHANGED", "miniLocked")
		ns.Print(ns.S.miniLocked and L["Mini tracker locked."] or L["Mini tracker unlocked: drag it where you like."])
	end,
	played = function()
		if not ns.Tracker:RequestPlayed(true) then
			ns.Print(L["The game can't be asked for /played right now."])
		end
	end,
	reset = function()
		ns.Options.ConfirmReset()
	end,
	help = help,
}
ACTIONS.level, ACTIONS.characters, ACTIONS.alts = ACTIONS.levels, ACTIONS.chars, ACTIONS.chars
ACTIONS.config, ACTIONS.settings, ACTIONS.opt = ACTIONS.options, ACTIONS.options, ACTIONS.options
ACTIONS.sync, ACTIONS["?"] = ACTIONS.played, help

SLASH_LEVELTIMETRACKER1 = "/ltt"
SLASH_LEVELTIMETRACKER2 = "/leveltimetracker"
SlashCmdList.LEVELTIMETRACKER = function(msg)
	local cmd = (msg or ""):lower():match("^%s*(%S*)") or ""
	local action = ACTIONS[cmd]
	if action then
		action()
	else
		ns.Print(L["There's no command %s."], C(COLOR.white, cmd))
		help()
	end
end

---------------------------------------------------------------------------
-- Addon compartment
---------------------------------------------------------------------------
function LevelTimeTracker_OnAddonCompartmentClick(_, button)
	if button == "RightButton" then
		ns.Mini.Toggle()
	else
		UI.Toggle()
	end
end

function LevelTimeTracker_OnAddonCompartmentEnter(_, frame)
	if not GameTooltip then
		return
	end
	local T = ns.Tracker
	GameTooltip:SetOwner(frame or UIParent, "ANCHOR_LEFT")
	GameTooltip:AddLine(ns.title, 1, 0.82, 0)
	if T.char then
		if T:AtMax() then
			GameTooltip:AddDoubleLine(L["Max level"], tostring(T.level), 1, 1, 1, 1, 1, 1)
		else
			local t, eta = T:LevelTime(), T:ETA()
			GameTooltip:AddDoubleLine(format(L["Time on level %d"], T.level), t and U.Duration(t) or "...", 1, 1, 1, 1, 1, 1)
			if eta then
				GameTooltip:AddDoubleLine(L["Next level in"], U.Duration(eta), 1, 1, 1, 1, 1, 1)
			end
		end
	end
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine(L["Click: open the window"], 0.6, 0.6, 0.6)
	GameTooltip:AddLine(L["Right-click: show or hide the mini tracker"], 0.6, 0.6, 0.6)
	GameTooltip:Show()
end

function LevelTimeTracker_OnAddonCompartmentLeave()
	if GameTooltip then
		GameTooltip:Hide()
	end
end

-- Key binding labels (Bindings.xml).
BINDING_HEADER_LEVELTIMETRACKER = ns.title
BINDING_NAME_LEVELTIMETRACKER_TOGGLE = L["Open or close the window"]
BINDING_NAME_LEVELTIMETRACKER_MINI = L["Show or hide the mini tracker"]

-- One line in chat the first time this version runs, so players updating from 1.x know where things went.
local Hello = ns:NewModule("Hello")
function Hello:Enable()
	if ns.S.hello == ns.version then
		return
	end
	local updated = ns.db.migratedFrom ~= nil
	ns.S.hello = ns.version
	C_Timer.After(6, function()
		if updated then
			ns.Print(L["version %s has a new look and now times your levels like /played does. Type %s to open it."],
				ns.version, C(COLOR.white, "/ltt"))
		else
			ns.Print(L["timing your levels. Type %s to open it."], C(COLOR.white, "/ltt"))
		end
	end)
end
