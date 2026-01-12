local addonName = ...
local LTT = {}
_G.LTT = LTT

-------------------------------------------------
-- SAVED VARIABLES
-------------------------------------------------
LevelTimeTrackerDB = LevelTimeTrackerDB or {}

-------------------------------------------------
-- INTERNAL FRAME
-------------------------------------------------
local frame = CreateFrame("Frame")

-------------------------------------------------
-- CHARACTER KEY
-------------------------------------------------
local function GetCharKey()
    local name = UnitName("player")
    local realm = GetNormalizedRealmName() or GetRealmName() or "Unknown"
    return name .. "-" .. realm
end

-------------------------------------------------
-- GET / INIT CHARACTER DATA
-------------------------------------------------
function LTT:GetCharData()
    local key = GetCharKey()

    if not LevelTimeTrackerDB[key] then
        LevelTimeTrackerDB[key] = {
            startLevel = 1,
            currentLevel = UnitLevel("player"),
            maxLevel = GetMaxPlayerLevel(), -- initial value

            levelTimes = {},
            totalTime = 0,

            -- Timing state
            _xpStarted = false,
            _lastLevelTime = nil,   -- persistent
            _lastLevelXP = 0,       -- session baseline
            _lastXP = UnitXP("player"),
            _lastRecordedLevel = UnitLevel("player"),
        }
    end

    local d = LevelTimeTrackerDB[key]

    -- ALWAYS keep these dynamic
    d.currentLevel = UnitLevel("player")
    d.maxLevel = GetMaxPlayerLevel()   -- Instead of using a static number like 80, i grab max level for future xpacks.

    -- Auto-heal startLevel
    local lowest
    for lvl in pairs(d.levelTimes) do
        if not lowest or lvl < lowest then
            lowest = lvl
        end
    end
    d.startLevel = lowest or d.startLevel or 1

    return d
end


-------------------------------------------------
-- EVENTS
-------------------------------------------------
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_XP_UPDATE")
frame:RegisterEvent("PLAYER_LEVEL_UP")

frame:SetScript("OnEvent", function(_, event, ...)
    local d = LTT:GetCharData()
    if not d then return end

    -------------------------------------------------
    -- LOGIN / RELOAD
    -- Reset XP/hour baseline ONLY
    -------------------------------------------------
    if event == "PLAYER_LOGIN" then
        d._lastXP = UnitXP("player")
        d._lastRecordedLevel = UnitLevel("player")
        d._lastLevelXP = UnitXP("player") -- session reset
        return
    end

    -------------------------------------------------
    -- XP UPDATE (START TIMER IF NEEDED)
    -------------------------------------------------
    if event == "PLAYER_XP_UPDATE" then
        local xp = UnitXP("player")
        local prev = d._lastXP or 0

        if not d._xpStarted and xp > prev then
            d._xpStarted = true
            d._lastLevelTime = d._lastLevelTime or GetTime()
        end

        d._lastXP = xp
        return
    end

    -------------------------------------------------
    -- LEVEL UP (MULTI-LEVEL SAFE + CHAT)
    -------------------------------------------------
    if event == "PLAYER_LEVEL_UP" then
        local newLevel = ...
        local now = GetTime()
        local prevLevel = d._lastRecordedLevel or (newLevel - 1)

        -- Handle skipped levels
        if newLevel - prevLevel > 1 then
            for lvl = prevLevel + 1, newLevel - 1 do
                d.levelTimes[lvl] = d.levelTimes[lvl] or 0
                print(string.format(
                    "|cff33ccff[LTT]|r Level %d -> %d took %s",
                    lvl, lvl + 1, SecondsToTime(0)
                ))
            end
        end

        -- Record real level time
        if d._xpStarted and d._lastLevelTime then
            local duration = now - d._lastLevelTime
            d.levelTimes[newLevel - 1] = duration
            d.totalTime = d.totalTime + duration

            print(string.format(
                "|cff33ccff[LTT]|r Level %d -> %d took %s",
                newLevel - 1, newLevel, SecondsToTime(duration)
            ))
        else
            d.levelTimes[newLevel - 1] = d.levelTimes[newLevel - 1] or 0
            print(string.format(
                "|cff33ccff[LTT]|r Level %d -> %d took %s",
                newLevel - 1, newLevel, SecondsToTime(0)
            ))
        end

        -- Reset for next level (KEEP XP/hour baseline)
        d.currentLevel = newLevel
        d._lastRecordedLevel = newLevel
        d._xpStarted = false
        d._lastLevelTime = nil
        d._lastXP = UnitXP("player")

        if LTT_UI and LTT_UI.Refresh then
            LTT_UI:Refresh()
        end
    end
end)
