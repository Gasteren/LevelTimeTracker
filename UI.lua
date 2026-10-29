-- UI.lua: the Level Time Tracker window. A status line, the pages (Overview, Levels, Characters, Options) and the
-- character-frame tabs that switch between them.
local ADDON, ns = ...
local L, U, C, COLOR = ns.L, ns.U, ns.C, ns.COLOR
local W, Data = ns.W, ns.Data

local UI = {}
ns.UI = UI

local format = string.format

UI.ARROW = "\194\187" -- », between a level and the next (the game's fonts have no arrow)
UI.DOT = "\194\183" -- ·
UI.WIDTH, UI.HEIGHT = 720, 470

UI.pages = {}
UI.byId = {}
UI.panels = {}
UI.dirty = {}

local frame

-- def: { id, label, tip, order, create(panel), refresh(panel), tick(panel) (twice a second while shown) }
function UI.RegisterPage(def)
	UI.pages[#UI.pages + 1] = def
	UI.byId[def.id] = def
	table.sort(UI.pages, function(a, b)
		return (a.order or 99) < (b.order or 99)
	end)
	UI.dirty[def.id] = true
end

-- The character the Levels page shows (another one after a click on the Characters page).
function UI.ViewKey()
	local key = UI.viewKey
	if key and Data.Get(key) then
		return key
	end
	return ns.Tracker.key
end

function UI.ViewChar()
	return Data.Get(UI.ViewKey())
end

local STATUS_ICON = {
	green = "Interface\\FriendsFrame\\StatusIcon-Online",
	orange = "Interface\\FriendsFrame\\StatusIcon-Away",
	grey = "Interface\\FriendsFrame\\StatusIcon-Offline",
}

-- What the clock is doing, for the indicator next to the close button: text, colour, tooltip.
function UI.ClockState()
	local T = ns.Tracker
	if not T.char then
		return L["Starting..."], "grey"
	elseif T:AtMax() then
		return L["Max level"], "green", L["This character is at max level: there is nothing more to time."]
	elseif not T:Synced() then
		return L["Reading /played..."], "orange", L["Level Time Tracker asked the game for /played and waits for the answer. The time on this level shows as soon as it comes in."]
	elseif T:XPDisabled() then
		return L["Experience is off"], "orange", L["You turned off experience gain. The clock keeps running, as /played does."]
	end
	return format(L["Timing level %d"], T.level), "green", L["The time on this level counts like /played: all the time you are logged in on this character."]
end

function UI.UpdateStatus()
	if not frame then
		return
	end
	local chars, levels = Data.Total()
	local charText = format(chars == 1 and L["%s character"] or L["%s characters"], C(COLOR.white, chars))
	local levelText = format(levels == 1 and L["%s level timed"] or L["%s levels timed"], C(COLOR.white, levels))
	frame.status:SetText(charText .. "  " .. UI.DOT .. "  " .. levelText)
	local text, color, tip = UI.ClockState()
	local st = frame.state
	st.text:SetText(C(color == "orange" and COLOR.orange or color == "grey" and COLOR.grey or COLOR.green, text))
	st.icon:SetTexture(STATUS_ICON[color] or STATUS_ICON.grey)
	st.tip = tip
	st:SetWidth(math.ceil(st.text:GetStringWidth()) + 18)
end

local function refreshVisible()
	if not frame or not frame:IsShown() then
		return
	end
	UI.UpdateStatus()
	local id = UI.current
	local def, panel = UI.byId[id], UI.panels[id]
	if def and panel and UI.dirty[id] then
		UI.dirty[id] = false
		if def.refresh then
			ns.SafeCall(def.refresh, panel)
		end
	end
end

-- Marks a page (or all of them) as stale; the visible one is redrawn right after.
function UI.Refresh(id)
	if id then
		UI.dirty[id] = true
	else
		for k in pairs(UI.byId) do
			UI.dirty[k] = true
		end
	end
	if frame and frame:IsShown() then
		ns.Debounce("ui-refresh", 0.05, refreshVisible)
	end
end

local function selectPage(id)
	local def = UI.byId[id]
	if not def then
		return
	end
	if UI.current and UI.current ~= id then
		local old = UI.panels[UI.current]
		if old then
			old:Hide()
		end
	end
	UI.current = id
	ns.S.tab = id
	local panel = UI.panels[id]
	if not panel then
		panel = CreateFrame("Frame", nil, frame.content)
		panel:SetAllPoints()
		UI.panels[id] = panel
		ns.SafeCall(def.create, panel)
		UI.dirty[id] = true
	end
	panel:Show()
	UI.dirty[id] = false
	if def.refresh then
		ns.SafeCall(def.refresh, panel)
	end
end

local TICK = 0.5

local function build()
	frame = W.Window("LevelTimeTrackerFrame", ns.title, UI.WIDTH, UI.HEIGHT, { sound = true })
	frame.content = CreateFrame("Frame", nil, frame)
	frame.content:SetPoint("TOPLEFT", 14, -30)
	frame.content:SetPoint("BOTTOMRIGHT", -14, 14)

	frame.status = W.OneLine(W.Label(frame, "", "GameFontHighlightSmall"))
	frame.status:SetPoint("TOPLEFT", 20, -15)
	frame.status:SetWidth(220)

	local st = CreateFrame("Frame", nil, frame)
	st:SetSize(150, 16)
	st:SetPoint("TOPRIGHT", -40, -13)
	st.text = st:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	st.text:SetPoint("RIGHT")
	st.text:SetJustifyH("RIGHT")
	st.icon = st:CreateTexture(nil, "ARTWORK")
	st.icon:SetSize(14, 14)
	st.icon:SetPoint("RIGHT", st.text, "LEFT", -3, 0)
	st:EnableMouse(true)
	st:SetScript("OnEnter", function(self)
		if self.tip then
			W.ShowTip(self, L["The clock"], self.tip, "ANCHOR_BOTTOMLEFT")
		end
	end)
	st:SetScript("OnLeave", W.HideTip)
	frame.state = st

	local defs = {}
	for i, def in ipairs(UI.pages) do
		defs[i] = { id = def.id, label = def.label, tip = def.tip }
	end
	frame.tabs = W.TabBar(frame, defs, selectPage)

	local elapsed = 0
	frame:SetScript("OnUpdate", function(_, dt)
		elapsed = elapsed + dt
		if elapsed < TICK then
			return
		end
		elapsed = 0
		UI.UpdateStatus()
		local def, panel = UI.byId[UI.current], UI.panels[UI.current]
		if def and def.tick and panel and panel:IsShown() then
			ns.SafeCall(def.tick, panel)
		end
	end)

	function frame:onShown()
		self.tabs:Relevel()
		UI.Refresh()
	end
	return frame
end

function UI.Show(id)
	if not frame then
		build()
	end
	id = id or (frame:IsShown() and UI.current) or ns.S.tab
	if not UI.byId[id] then
		id = UI.pages[1].id
	end
	frame:Show()
	frame:Raise()
	frame.tabs:Relevel()
	frame.tabs:Select(id)
	UI.UpdateStatus()
	return UI.panels[id]
end

function UI.Hide()
	if frame then
		frame:Hide()
	end
end

function UI.Toggle(id)
	if frame and frame:IsShown() and (not id or id == UI.current) then
		frame:Hide()
	else
		UI.Show(id)
	end
end

-- Opens the Levels page on a character (nil: the one you play).
function UI.ShowLevels(key)
	UI.viewKey = key ~= ns.Tracker.key and key or nil
	UI.Refresh("levels")
	UI.Show("levels")
end

for _, message in ipairs({ "LEVEL_UP", "PLAYED", "DATA_CHANGED", "THEME_CHANGED" }) do
	ns:On(message, function()
		UI.Refresh()
	end)
end

-- Experience changes often (every kill): only the pages showing it are redrawn, and not more than once a second.
ns:On("XP", function()
	if frame and frame:IsShown() then
		UI.dirty.overview = true
		UI.dirty.characters = true
		ns.Debounce("ui-xp", 1, refreshVisible)
	end
end)

ns:On("SETTINGS_CHANGED", function(key)
	if key == "scale" then
		W.ApplyScale()
	end
	UI.Refresh()
end)

-- A little row of text: a gold label on the left and a value on the right (tip: a tooltip explaining it).
function UI.StatRow(parent, label, tip)
	local row = CreateFrame("Frame", nil, parent)
	row:SetHeight(18)
	row.label = W.OneLine(row:CreateFontString(nil, "ARTWORK", "LevelTimeTrackerFontNormalSmall"))
	row.label:SetPoint("LEFT")
	row.label:SetJustifyH("LEFT")
	row.label:SetText(label)
	row.value = W.OneLine(row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall"))
	row.value:SetPoint("RIGHT")
	row.value:SetPoint("LEFT", row.label, "RIGHT", 8, 0)
	row.value:SetJustifyH("RIGHT")
	row:EnableMouse(true)
	W.AttachTooltip(row, label, tip)

	-- A new label (and tooltip) for the row.
	function row:SetLabel(text, tipText)
		self.label:SetText(text)
		self.tipTitle, self.tipText = text, tipText
	end
	return row
end

-- Stacks rows in a box: each row spans the box (left and right padding), `pitch` apart, from `top`.
function UI.StackRows(box, rows, top, pitch, pad)
	pad = pad or 12
	for i, row in ipairs(rows) do
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", box, "TOPLEFT", pad, -(top + (i - 1) * pitch))
		row:SetPoint("TOPRIGHT", box, "TOPRIGHT", -pad, -(top + (i - 1) * pitch))
	end
end

-- Row spacing that leaves room for the small font as it really is (UI addons often make fonts bigger).
function UI.Pitch(fs, minimum)
	return math.max(minimum or 18, W.LineHeight(fs) + 6)
end
