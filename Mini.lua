-- Mini.lua: the mini tracker. A small box with your level, the time on it, the time to the next level and the XP bar.
-- Click: the window. Right-click: options. Drag: move it (unless locked).
local ADDON, ns = ...
local L, U, C, COLOR = ns.L, ns.U, ns.C, ns.COLOR
local W, Data, UI = ns.W, ns.Data, ns.UI

local format, floor, max = string.format, math.floor, math.max

local Mini = ns:NewModule("Mini")

local WIDTH, HEIGHT = 228, 50
local TICK = 1

local frame

local function tip(self)
	local T = ns.Tracker
	local lines = {}
	if T:AtMax() then
		local played = T:Played()
		lines[#lines + 1] = { L["Max level"], tostring(T.level) }
		if played then
			lines[#lines + 1] = { L["Played in total"], U.DurationLong(played) }
		end
	else
		local cur, maxXP, rested, frac = T:XP()
		local levelTime, rate, eta = T:LevelTime(), T:Rate(), T:ETA()
		lines[#lines + 1] = { L["Time on this level"], levelTime and U.DurationLong(levelTime) or L["reading /played..."] }
		lines[#lines + 1] = { L["Experience"], format("%s / %s (%d%%)", U.Number(cur), U.Number(maxXP), floor(frac * 100)) }
		lines[#lines + 1] = { L["XP to go"], U.Number(max(0, maxXP - cur)) }
		if rested > 0 then
			lines[#lines + 1] = { L["Rested XP"], U.Number(rested) }
		end
		lines[#lines + 1] = { L["XP per hour"], rate and U.Short(rate) or "-" }
		lines[#lines + 1] = { L["Next level in"], eta and U.Duration(eta) or "-" }
		local c = T.char
		local prev = c and c.levels[T.level - 1]
		if Data.Timed(prev) then
			lines[#lines + 1] = { format(L["Level %d took"], T.level - 1), U.DurationLong(prev.t) }
		end
	end
	lines[#lines + 1] = " "
	lines[#lines + 1] = C(COLOR.grey, L["Click: open Level Time Tracker"])
	lines[#lines + 1] = C(COLOR.grey, L["Right-click: options"])
	if not ns.S.miniLocked then
		lines[#lines + 1] = C(COLOR.grey, L["Drag: move"])
	end
	W.ShowTip(self, format(L["Level %d"], T.level), lines, "ANCHOR_BOTTOM")
end

local function update()
	if not frame or not frame:IsShown() then
		return
	end
	local T = ns.Tracker
	frame.level:SetText(tostring(T.level))
	if T:AtMax() then
		local played = T:Played()
		frame.time:SetText(L["Max level"])
		frame.eta:SetText(played and C(COLOR.grey, U.Duration(played) .. " " .. L["played"]) or "")
		frame.bar:Set("", 1, 1, W.GOLD[1] * 0.8, W.GOLD[2] * 0.8, 0, "")
		frame.bar:SetExtra(nil)
		return
	end
	local levelTime = T:LevelTime()
	frame.time:SetText(levelTime and U.Duration(levelTime) or C(COLOR.grey, "..."))
	local eta = T:ETA()
	if T:XPDisabled() then
		frame.eta:SetText(C(COLOR.orange, L["XP off"]))
	else
		frame.eta:SetText(eta and C(COLOR.grey, format(L["%s to go"], U.Duration(eta))) or "")
	end
	local cur, maxXP, rested, frac = T:XP()
	frame.bar:Set("", cur, maxXP, W.XP[1], W.XP[2], W.XP[3], format("%d%%", floor(frac * 100)))
	frame.bar:SetExtra(rested, W.RESTED[1], W.RESTED[2], W.RESTED[3])
end

local function build()
	frame = W.Frame(UIParent, "box", "LevelTimeTrackerMini")
	frame:SetSize(WIDTH, HEIGHT)
	frame:SetFrameStrata("MEDIUM")
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetDontSavePosition(true)
	frame:SetScale(W.Scale())
	W.windows[#W.windows + 1] = frame
	W.RestorePos(frame, "TOP", "TOP", 0, -96)

	frame.level = frame:CreateFontString(nil, "ARTWORK", "LevelTimeTrackerFontNormalLarge")
	frame.level:SetPoint("TOPLEFT", 10, -8)
	frame.time = W.OneLine(frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight"))
	frame.time:SetPoint("LEFT", frame.level, "RIGHT", 8, 0)
	frame.time:SetJustifyH("LEFT")
	frame.eta = W.OneLine(frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall"))
	frame.eta:SetPoint("TOPRIGHT", -10, -10)
	frame.eta:SetJustifyH("RIGHT")
	frame.time:SetPoint("RIGHT", frame.eta, "LEFT", -6, 0)

	frame.bar = W.Bar(frame, 11)
	frame.bar:SetPoint("BOTTOMLEFT", 11, 9)
	frame.bar:SetPoint("BOTTOMRIGHT", -11, 9)

	frame:SetScript("OnDragStart", function(self)
		self.locked = ns.S.miniLocked
		self.dragged = W.StartMoving(self)
	end)
	frame:SetScript("OnDragStop", W.StopMoving)
	frame:SetScript("OnMouseUp", function(self, button)
		if self.dragged then
			self.dragged = false
			return
		end
		if button == "RightButton" then
			W.Sound("click")
			UI.Show("options")
		elseif button == "LeftButton" then
			UI.Toggle()
		end
	end)
	frame:SetScript("OnEnter", tip)
	frame:SetScript("OnLeave", W.HideTip)
	frame:SetScript("OnShow", update)

	local elapsed = 0
	frame:SetScript("OnUpdate", function(_, dt)
		elapsed = elapsed + dt
		if elapsed >= TICK then
			elapsed = 0
			update()
		end
	end)
	return frame
end

-- Whether the mini tracker should be on the screen now.
function Mini.Wanted()
	local S, T = ns.S, ns.Tracker
	if not S.mini or not T.char then
		return false
	end
	if T:AtMax() and not S.miniAtMax then
		return false
	end
	if S.miniHideCombat and InCombatLockdown and InCombatLockdown() then
		return false
	end
	if C_PetBattles and C_PetBattles.IsInBattle and C_PetBattles.IsInBattle() then
		return false
	end
	return true
end

function Mini.Update()
	local wanted = Mini.Wanted()
	if wanted and not frame then
		build()
	end
	if frame then
		frame:SetShown(wanted)
		if wanted then
			update()
		end
	end
end

function Mini.Toggle()
	ns.S.mini = not ns.S.mini
	ns:Fire("SETTINGS_CHANGED", "mini")
	if ns.S.mini and not Mini.Wanted() then
		ns.Print(ns.Tracker:AtMax() and L["The mini tracker is on, but hidden at max level (see Options)."]
			or L["The mini tracker is on, but hidden right now."])
	end
end

function Mini:Enable()
	Mini.Update()
	local function refresh()
		Mini.Update()
	end
	ns:RegisterEvent("PLAYER_REGEN_DISABLED", refresh)
	ns:RegisterEvent("PLAYER_REGEN_ENABLED", refresh)
	ns:RegisterEvent("PET_BATTLE_OPENING_START", refresh)
	ns:RegisterEvent("PET_BATTLE_CLOSE", refresh)
end

for _, message in ipairs({ "LEVEL_UP", "PLAYED", "XP", "SETTINGS_CHANGED", "THEME_CHANGED", "DATA_CHANGED" }) do
	ns:On(message, function()
		if ns.loggedIn then
			Mini.Update()
		end
	end)
end
