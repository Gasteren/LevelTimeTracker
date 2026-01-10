local Graph = CreateFrame("Frame", nil, LTT_MainFrame)
_G.LTT_Graph = Graph

Graph:SetSize(480, 90)
Graph:SetPoint("BOTTOM", 0, 20)

Graph.bars = {}

function Graph:Draw()
    local charData = LTT:GetCharData()
    if not charData then return end

    for _, bar in ipairs(self.bars) do bar:Hide() end
    wipe(self.bars)

    local times = {}
    local maxTime = 1

    for level = charData.startLevel, charData.currentLevel - 1 do
        local t = charData.levelTimes[level]
        if t then
            table.insert(times, t)
            maxTime = math.max(maxTime, t)
        end
    end

    local x = 0
    for _, t in ipairs(times) do
        local bar = CreateFrame("StatusBar", nil, self)
        bar:SetSize(14, (t / maxTime) * 80)
        bar:SetPoint("BOTTOMLEFT", x, 0)
        bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
        bar:SetStatusBarColor(0.2, 0.6, 1)

        x = x + 16
        table.insert(self.bars, bar)
    end
end
