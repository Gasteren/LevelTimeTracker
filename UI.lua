local UI = CreateFrame("Frame", "LTT_MainFrame", UIParent, "BackdropTemplate")
_G.LTT_UI = UI

-------------------------------------------------
-- LOCAL STATE
-------------------------------------------------
local compactMode = false

-------------------------------------------------
-- UI SETTINGS
-------------------------------------------------
local function GetUISettings()
    LevelTimeTrackerDB.ui = LevelTimeTrackerDB.ui or {}
    LevelTimeTrackerDB.ui.compact = LevelTimeTrackerDB.ui.compact or false
    return LevelTimeTrackerDB.ui
end

-------------------------------------------------
-- POSITION SAVE / RESTORE
-------------------------------------------------
local function SavePosition()
    local p, _, rp, x, y = UI:GetPoint()
    LevelTimeTrackerDB.ui.position = { p, rp, x, y }
end

local function RestorePosition()
    UI:ClearAllPoints()
    local pos = LevelTimeTrackerDB.ui.position
    if pos then
        UI:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    else
        UI:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
end

-------------------------------------------------
-- ESC CONTROL
-------------------------------------------------
local function AddESC()
    for _, f in ipairs(UISpecialFrames) do
        if f == "LTT_MainFrame" then return end
    end
    tinsert(UISpecialFrames, "LTT_MainFrame")
end

local function RemoveESC()
    for i, f in ipairs(UISpecialFrames) do
        if f == "LTT_MainFrame" then
            table.remove(UISpecialFrames, i)
            return
        end
    end
end

-------------------------------------------------
-- FRAME SETUP
-------------------------------------------------
UI:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    edgeSize = 16,
})
UI:SetMovable(true)
UI:EnableMouse(true)
UI:RegisterForDrag("LeftButton")
UI:SetScript("OnDragStart", UI.StartMoving)
UI:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    SavePosition()
end)
UI:Hide()

-------------------------------------------------
-- BUTTONS
-------------------------------------------------
UI.close = CreateFrame("Button", nil, UI, "UIPanelCloseButton")
UI.close:SetPoint("TOPRIGHT", -6, -6)

UI.compactBtn = CreateFrame("Button", nil, UI, "UIPanelButtonTemplate")
UI.compactBtn:SetSize(22, 22)
UI.compactBtn:SetPoint("RIGHT", UI.close, "LEFT", -4, 0)
UI.compactBtn:SetText("C")

-------------------------------------------------
-- CLASS COLOR
-------------------------------------------------
local _, class = UnitClass("player")
local c = RAID_CLASS_COLORS[class] or { r = .2, g = .6, b = 1 }

-------------------------------------------------
-- TITLE
-------------------------------------------------
UI.title = UI:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
UI.title:SetPoint("TOPLEFT", 16, -12)
UI.title:SetText("Level Time Tracker")

-------------------------------------------------
-- PROGRESS BAR
-------------------------------------------------
UI.bar = CreateFrame("StatusBar", nil, UI)
UI.bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
UI.bar:SetStatusBarColor(c.r, c.g, c.b)
UI.bar:SetMinMaxValues(0, 1)

UI.bar.bg = UI.bar:CreateTexture(nil, "BACKGROUND")
UI.bar.bg:SetAllPoints()
UI.bar.bg:SetColorTexture(.1, .1, .1, .8)

UI.progressIcon = UI:CreateTexture(nil, "ARTWORK")
UI.progressIcon:SetSize(18, 18)
UI.progressIcon:SetTexture("Interface\\Icons\\Ability_Hunter_Pathfinding")

UI.progressText = UI:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")

-------------------------------------------------
-- LIVE STATS
-------------------------------------------------
UI.timeIcon = UI:CreateTexture(nil, "ARTWORK")
UI.timeIcon:SetSize(16, 16)
UI.timeIcon:SetTexture("Interface\\Icons\\INV_Misc_PocketWatch_01")

UI.liveText = UI:CreateFontString(nil, "OVERLAY", "GameFontHighlight")

-------------------------------------------------
-- DETAILS
-------------------------------------------------
UI.scroll = CreateFrame("ScrollFrame", nil, UI, "UIPanelScrollFrameTemplate")
UI.content = CreateFrame("Frame", nil, UI.scroll)
UI.scroll:SetScrollChild(UI.content)
UI.content:SetWidth(600)
UI.rows = {}

-------------------------------------------------
-- HELPERS
-------------------------------------------------
local function GetOverallProgress(d)
    local span = d.maxLevel - d.startLevel
    if span <= 0 then return 0 end

    local completed = d.currentLevel - d.startLevel
    local xpFrac = UnitXPMax("player") > 0 and (UnitXP("player") / UnitXPMax("player")) or 0
    return math.min((completed + xpFrac) / span, 1)
end

-------------------------------------------------
-- LAYOUT
-------------------------------------------------
function UI:ApplyLayout()
    if compactMode then
        RemoveESC()
        UI:SetSize(420, 170)
        UI.scroll:Hide()
        UI.title:Hide()
        UI.compactBtn:SetText("F")
    else
        AddESC()
        UI:SetSize(660, 560)
        UI.scroll:Show()
        UI.title:Show()
        UI.compactBtn:SetText("C")

        UI.scroll:SetPoint("TOPLEFT", 30, -150)
        UI.scroll:SetPoint("BOTTOMRIGHT", -30, 30)
    end

    UI.bar:SetPoint("TOPLEFT", 30, compactMode and -30 or -56)
    UI.bar:SetSize(compactMode and 360 or 600, compactMode and 16 or 18)

    UI.progressIcon:SetPoint("RIGHT", UI.bar, "LEFT", -8, 0)
    UI.progressText:SetPoint("TOPLEFT", UI.bar, "BOTTOMLEFT", 0, -6)
    UI.timeIcon:SetPoint("LEFT", UI.progressText, "LEFT", 0, compactMode and -22 or -24)
    UI.liveText:SetPoint("LEFT", UI.timeIcon, "RIGHT", 6, 0)
end

-------------------------------------------------
-- COMPACT TOGGLE
-------------------------------------------------
UI.compactBtn:SetScript("OnClick", function()
    compactMode = not compactMode
    LevelTimeTrackerDB.ui.compact = compactMode
    UI:ApplyLayout()
    UI:Refresh()
end)

-------------------------------------------------
-- LIVE UPDATE
-------------------------------------------------
UI:SetScript("OnUpdate", function()
    if not UI:IsShown() then return end
    local d = LTT:GetCharData()
    if not d then return end

    UI.bar:SetValue(GetOverallProgress(d))

    UI.progressText:SetText(string.format(
        "Level %d / %d   Total Time: %s",
        d.currentLevel,
        d.maxLevel,
        SecondsToTime(d.totalTime or 0)
    ))

    local since = d._lastLevelTime and (GetTime() - d._lastLevelTime) or 0
    local gainedXP = math.max(UnitXP("player") - (d._lastLevelXP or 0), 0)
    local xph = (since > 0 and gainedXP > 0) and (gainedXP / since) * 3600 or 0

    UI.liveText:SetText(string.format(
        "Since last level: %s   XP/hour: %s",
        SecondsToTime(since),
        BreakUpLargeNumbers(math.floor(xph))
    ))
end)

-------------------------------------------------
-- REFRESH
-------------------------------------------------
function UI:Refresh()
    local d = LTT:GetCharData()
    if not d then return end

    for _, r in ipairs(UI.rows) do r:Hide() end
    wipe(UI.rows)

    if not compactMode then
        local y = -6
        local shown = false

        for lvl = d.currentLevel - 1, d.startLevel, -1 do
            local t = d.levelTimes[lvl]
            if t then
                local row = UI.content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                row:SetPoint("TOPLEFT", 4, y)
                row:SetText(string.format(
                    "Level %d -> %d : %s",
                    lvl, lvl + 1, SecondsToTime(t)
                ))
                y = y - 20
                table.insert(UI.rows, row)
                shown = true
            end
        end

        if not shown then
            local row = UI.content:CreateFontString(nil, "OVERLAY", "GameFontDisable")
            row:SetPoint("TOPLEFT", 4, y)
            row:SetText("XP-based tracking started recently. New data appears after your next level-up.")
            table.insert(UI.rows, row)
            y = y - 20
        end

        UI.content:SetHeight(-y + 10)
    end
end

-------------------------------------------------
-- INIT
-------------------------------------------------
UI:RegisterEvent("PLAYER_LOGIN")
UI:SetScript("OnEvent", function()
    compactMode = GetUISettings().compact
end)

-------------------------------------------------
-- SLASH
-------------------------------------------------
SLASH_LTT1 = "/ltt"
SlashCmdList["LTT"] = function()
    UI:ApplyLayout()
    if UI:IsShown() then
        UI:Hide()
    else
        RestorePosition()
        UI:Show()
        UI:Refresh()
    end
end
