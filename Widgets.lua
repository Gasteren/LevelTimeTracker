-- Widgets.lua: a small widget kit built from the classic Blizzard frame art (dialog borders, the header plate, panel
-- buttons, check boxes, skill bars, column tabs, character-frame tabs), like GuildLedger's. No external libraries.
local ADDON, ns = ...
local L, U = ns.L, ns.U

local W = {}
ns.W = W

local floor, max, min = math.floor, math.max, math.min

W.windows = {}
W.GOLD = { 1, 0.82, 0 }
W.XP = { 0.58, 0, 0.55 } -- the game's experience bar
W.RESTED = { 0, 0.39, 0.88 }

---------------------------------------------------------------------------
-- Sounds
---------------------------------------------------------------------------
local SOUNDS = {
	open = { "IG_MAINMENU_OPEN", 850 },
	close = { "IG_MAINMENU_CLOSE", 851 },
	tab = { "IG_CHARACTER_INFO_TAB", 841 },
	click = { "IG_MAINMENU_OPTION_CHECKBOX_ON", 856 },
	on = { "IG_MAINMENU_OPTION_CHECKBOX_ON", 856 },
	off = { "IG_MAINMENU_OPTION_CHECKBOX_OFF", 857 },
}

function W.Sound(kind)
	local s = SOUNDS[kind]
	if s then
		U.PlaySound(s[1], s[2])
	end
end

---------------------------------------------------------------------------
-- Backdrops
---------------------------------------------------------------------------
local FLAT = "Interface\\Tooltips\\UI-Tooltip-Background"

W.BD = {
	dark = {
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
		tile = true, tileSize = 32, edgeSize = 32,
		insets = { left = 11, right = 12, top = 12, bottom = 11 },
	},
	-- Windows of a theme with its own background: the classic dialog border around a flat colour.
	window = {
		bgFile = FLAT,
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
		tile = true, tileSize = 32, edgeSize = 32,
		insets = { left = 11, right = 12, top = 12, bottom = 11 },
	},
	box = {
		bgFile = FLAT,
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 16,
		insets = { left = 5, right = 5, top = 5, bottom = 5 },
	},
	slider = {
		bgFile = "Interface\\Buttons\\UI-SliderBar-Background",
		edgeFile = "Interface\\Buttons\\UI-SliderBar-Border",
		tile = true, tileSize = 8, edgeSize = 8,
		insets = { left = 3, right = 3, top = 6, bottom = 6 },
	},
}

local BD_COLOR = {
	box = { 0.1, 0.1, 0.1, 0.65, 0.4, 0.4, 0.4, 1 },
}

---------------------------------------------------------------------------
-- Themes
---------------------------------------------------------------------------
-- A theme recolours the classic art rather than replacing it. With metal set, window borders, the header plate, tabs,
-- column headers, check boxes, scroll bars and bar borders are greyed out and tinted; buttons only when the theme has
-- its own button colour. Text: label = the gold of the game's labels, title = window and box titles, selected = the
-- selected tab. accent = dividers and sort arrows, highlight = row highlights, bar = plain bars.
local GOLD = W.GOLD
local BLUE = { 0.26, 0.42, 1 }

W.THEME_ORDER = { "classic", "steel", "horde", "alliance" }
W.THEMES = {
	classic = {
		name = L["Classic"],
		desc = L["The game's own frames, as they are."],
		label = GOLD, title = GOLD, selected = { 1, 1, 1 }, accent = GOLD, highlight = { 1, 1, 1 }, bar = BLUE,
		box = BD_COLOR.box,
	},
	steel = {
		name = L["Steel"],
		desc = L["Black and steel with cyan."],
		metal = { 0.7, 0.76, 0.83 },
		buttons = { 0.62, 0.68, 0.76 },
		label = { 0.62, 0.77, 0.85 }, title = { 0.9, 0.93, 0.96 }, selected = { 0.22, 0.82, 1 },
		accent = { 0.22, 0.82, 1 }, highlight = { 0.35, 0.85, 1 },
		check = { 0.35, 0.9, 1 }, bar = { 0.15, 0.47, 0.62 },
		window = { 0.03, 0.037, 0.045, 0.96 },
		box = { 0.07, 0.085, 0.1, 0.92, 0.42, 0.47, 0.53, 1 },
	},
	horde = {
		name = L["Horde"],
		desc = L["Dark red iron with gold."],
		metal = { 0.92, 0.38, 0.27 },
		label = GOLD, title = GOLD, selected = { 1, 1, 1 }, accent = { 0.95, 0.4, 0.22 }, highlight = { 1, 0.6, 0.45 },
		bar = { 0.7, 0.18, 0.12 },
		window = { 0.08, 0.025, 0.02, 0.96 },
		box = { 0.13, 0.045, 0.035, 0.8, 0.6, 0.27, 0.2, 1 },
	},
	alliance = {
		name = L["Alliance"],
		desc = L["Blue steel with gold."],
		metal = { 0.52, 0.68, 1 },
		buttons = { 0.5, 0.64, 1 },
		label = GOLD, title = GOLD, selected = { 1, 1, 1 }, accent = { 0.45, 0.7, 1 }, highlight = { 0.55, 0.75, 1 },
		bar = { 0.2, 0.42, 0.9 },
		window = { 0.02, 0.035, 0.085, 0.96 },
		box = { 0.04, 0.065, 0.13, 0.8, 0.3, 0.42, 0.68, 1 },
	},
}

-- Copies of the game's gold fonts, so a theme recolours them without touching the game's own.
local FONTS = {
	LevelTimeTrackerFontNormal = { "GameFontNormal", "label" },
	LevelTimeTrackerFontNormalSmall = { "GameFontNormalSmall", "label" },
	LevelTimeTrackerFontNormalLarge = { "GameFontNormalLarge", "label" },
	LevelTimeTrackerFontNormalHuge = { "GameFontNormalHuge", "label" },
	LevelTimeTrackerFontTitle = { "GameFontNormal", "title" },
	LevelTimeTrackerFontTitleSmall = { "GameFontNormalSmall", "title" },
	LevelTimeTrackerFontSelectedSmall = { "GameFontHighlightSmall", "selected" },
}
for name, def in pairs(FONTS) do
	local font = CreateFont(name)
	font:CopyFontObject(_G[def[1]])
end

-- Everything a theme paints: object -> paint(object, theme).
local themed = setmetatable({}, { __mode = "k" })
W.themeId, W.theme = "classic", W.THEMES.classic

function W.Themed(obj, paint)
	themed[obj] = paint
	paint(obj, W.theme)
	return obj
end

-- Greys out a piece of classic art and colours it like the theme's metal; nil leaves the art as it is.
function W.Tint(tex, color)
	if not tex then
		return
	end
	tex:SetDesaturated(color ~= nil)
	if color then
		tex:SetVertexColor(color[1], color[2], color[3], 1)
	else
		tex:SetVertexColor(1, 1, 1, 1)
	end
end

local function paintArt(obj, th)
	for _, tex in ipairs(obj.art) do
		W.Tint(tex, th.metal)
	end
end

local function paintHighlight(hl, th)
	local c = th.highlight
	hl:SetVertexColor(c[1], c[2], c[3], 1)
end

local function paintArrowButton(b, th)
	W.Tint(b:GetNormalTexture(), th.metal)
	W.Tint(b:GetPushedTexture(), th.metal)
	W.Tint(b:GetDisabledTexture(), th.metal)
	W.Tint(b:GetHighlightTexture(), th.metal)
end

local function paintScrollBar(bar, th)
	W.Tint(bar:GetThumbTexture(), th.metal)
end

function W.ThemeScrollBar(bar)
	W.Themed(bar, paintScrollBar)
	if bar.ScrollUpButton then
		W.Themed(bar.ScrollUpButton, paintArrowButton)
	end
	if bar.ScrollDownButton then
		W.Themed(bar.ScrollDownButton, paintArrowButton)
	end
	return bar
end

local function paintCheck(cb, th)
	W.Tint(cb:GetNormalTexture(), th.metal)
	W.Tint(cb:GetPushedTexture(), th.metal)
	W.Tint(cb:GetHighlightTexture(), th.metal)
	W.Tint(cb:GetCheckedTexture(), th.check)
end

function W.ApplyTheme(id)
	local th = W.THEMES[id]
	if not th then
		id, th = "classic", W.THEMES.classic
	end
	W.themeId, W.theme = id, th
	for name, def in pairs(FONTS) do
		local c = th[def[2]]
		_G[name]:SetTextColor(c[1], c[2], c[3])
	end
	for obj, paint in pairs(themed) do
		ns.SafeCall(paint, obj, th)
	end
	ns:Fire("THEME_CHANGED", id)
end

function W.SetTheme(id)
	if not W.THEMES[id] then
		return false
	end
	ns.S.theme = id
	W.ApplyTheme(id)
	return true
end

local Theme = ns:NewModule("Theme")
function Theme:Init()
	W.ApplyTheme(ns.S.theme)
end

local EDGES = { "TopLeftCorner", "TopRightCorner", "BottomLeftCorner", "BottomRightCorner", "TopEdge", "BottomEdge",
	"LeftEdge", "RightEdge" }

local function paintBackdrop(f, th)
	local kind = f.bdKind
	local window = kind == "dark"
	if window and th.window then
		f:SetBackdrop(W.BD.window)
		local c = th.window
		f:SetBackdropColor(c[1], c[2], c[3], c[4])
	else
		f:SetBackdrop(W.BD[kind])
		local c = th[kind] or BD_COLOR[kind]
		if c then
			f:SetBackdropColor(c[1], c[2], c[3], c[4])
			f:SetBackdropBorderColor(c[5], c[6], c[7], c[8])
		else
			f:SetBackdropColor(1, 1, 1, 1)
			f:SetBackdropBorderColor(1, 1, 1, 1)
		end
	end
	if window then
		local m = th.metal
		if m then
			f:SetBackdropBorderColor(m[1], m[2], m[3], 1)
		end
		for _, piece in ipairs(EDGES) do
			W.Tint(f[piece], m)
		end
	end
end

function W.SetBackdrop(f, kind)
	if not f.SetBackdrop then
		Mixin(f, BackdropTemplateMixin)
		f:HookScript("OnSizeChanged", f.OnBackdropSizeChanged)
	end
	f.bdKind = W.BD[kind] and kind or "dark"
	W.Themed(f, paintBackdrop)
end

function W.Frame(parent, kind, name)
	local f = CreateFrame("Frame", name, parent, "BackdropTemplate")
	if kind then
		W.SetBackdrop(f, kind)
	end
	return f
end

-- Group box in the style of the old options panels: a small title above the border, a note on the right of it.
function W.Box(parent, title)
	local f = W.Frame(parent, "box")
	f.title = f:CreateFontString(nil, "ARTWORK", "LevelTimeTrackerFontTitleSmall")
	f.title:SetPoint("BOTTOMLEFT", f, "TOPLEFT", 6, 2)
	f.title:SetText(title or "")
	f.note = f:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	f.note:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", -6, 2)
	f.note:SetJustifyH("RIGHT")
	return f
end

---------------------------------------------------------------------------
-- Text, tooltips, dividers
---------------------------------------------------------------------------
function W.Label(parent, text, font, layer)
	local fs = parent:CreateFontString(nil, layer or "ARTWORK", font or "GameFontHighlightSmall")
	fs:SetJustifyH("LEFT")
	fs:SetText(text or "")
	return fs
end

-- A label that stays on one line: text that doesn't fit ends in "...".
function W.OneLine(fs)
	fs:SetWordWrap(false)
	fs:SetMaxLines(1)
	return fs
end

-- Wrapping paragraph with a fixed width.
function W.Text(parent, text, width, font)
	local fs = W.Label(parent, text, font or "GameFontHighlightSmall")
	fs:SetWidth(width)
	fs:SetJustifyV("TOP")
	fs:SetWordWrap(true)
	return fs
end

-- Height of one line in a font string's font. UI addons (ElvUI, EllesmereUI, ...) often make Blizzard's fonts bigger,
-- so rows measure their font instead of assuming its size.
function W.LineHeight(fs)
	local h = fs:GetLineHeight()
	if not h or h <= 0 then
		local _, size = fs:GetFont()
		h = tonumber(size) or 12
	end
	return math.ceil(h) + 1
end

local function paintDivider(t, th)
	local c = th.accent
	t:SetColorTexture(c[1], c[2], c[3], t.lineAlpha)
end

-- A thin line in the theme's accent colour.
function W.Divider(parent, alpha)
	local t = parent:CreateTexture(nil, "ARTWORK")
	t.lineAlpha = alpha or 0.25
	t:SetHeight(1)
	return W.Themed(t, paintDivider)
end

-- text: a string, or a function(owner) returning one (or a list of lines).
function W.ShowTip(owner, title, text, anchor)
	if not GameTooltip then
		return
	end
	if type(text) == "function" then
		text = text(owner)
	end
	GameTooltip:SetOwner(owner, anchor or "ANCHOR_RIGHT")
	local c = W.theme.title
	if title and title ~= "" then
		GameTooltip:SetText(title, c[1], c[2], c[3], 1, true)
	end
	if type(text) == "table" then
		for _, line in ipairs(text) do
			if type(line) == "table" then
				GameTooltip:AddDoubleLine(line[1], line[2], 1, 0.82, 0, 1, 1, 1)
			else
				GameTooltip:AddLine(line, 1, 1, 1, true)
			end
		end
	elseif text and text ~= "" then
		if title and title ~= "" then
			GameTooltip:AddLine(text, 1, 1, 1, true)
		else
			GameTooltip:SetText(text, 1, 1, 1, 1, true)
		end
	end
	GameTooltip:Show()
end

function W.HideTip()
	if GameTooltip then
		GameTooltip:Hide()
	end
end

-- A tooltip with the title and the text (nothing shows for a frame without text).
function W.AttachTooltip(frame, title, text, anchor)
	frame.tipTitle, frame.tipText = title, text
	frame:HookScript("OnEnter", function(self)
		if self.tipText then
			W.ShowTip(self, self.tipTitle, self.tipText, anchor)
		end
	end)
	frame:HookScript("OnLeave", W.HideTip)
end

---------------------------------------------------------------------------
-- Buttons
---------------------------------------------------------------------------
function W.FitButton(b, minWidth)
	local fs = b:GetFontString()
	local w = fs and fs:GetStringWidth() or 0
	b:SetWidth(max(minWidth or 60, floor(w + 30)))
end

-- The red panel button (and its hover glow); a theme with its own button colour greys it out and tints it.
local function paintButton(b, th)
	W.Tint(b.Left, th.buttons)
	W.Tint(b.Middle, th.buttons)
	W.Tint(b.Right, th.buttons)
	W.Tint(b:GetHighlightTexture(), th.buttons)
end

function W.Button(parent, text, width, onClick, tip)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetHeight(22)
	b:SetText(text or "")
	if width then
		b:SetWidth(width)
	else
		W.FitButton(b)
	end
	b:SetMotionScriptsWhileDisabled(true)
	W.Themed(b, paintButton)
	if onClick then
		b:SetScript("OnClick", function(self, mouse)
			W.Sound("click")
			onClick(self, mouse)
		end)
	end
	if tip then
		W.AttachTooltip(b, text, tip)
	end
	return b
end

-- A line of text that works as a button (the gold "All levels" link above a box).
function W.TextButton(parent, text, onClick, tip)
	local b = CreateFrame("Button", nil, parent)
	b:SetHeight(16)
	local fs = b:CreateFontString(nil, "ARTWORK", "LevelTimeTrackerFontNormalSmall")
	fs:SetPoint("RIGHT")
	fs:SetJustifyH("RIGHT")
	b:SetFontString(fs)
	b:SetNormalFontObject("LevelTimeTrackerFontNormalSmall")
	b:SetHighlightFontObject("GameFontHighlightSmall")
	b:SetText(text)
	b:SetWidth(floor(fs:GetStringWidth() + 4))
	b:SetScript("OnClick", function(self, mouse)
		W.Sound("click")
		onClick(self, mouse)
	end)
	if tip then
		W.AttachTooltip(b, text, tip)
	end
	return b
end

function W.CloseButton(frame, onClick)
	local b
	if U.TexExists("Interface\\Buttons\\UI-Panel-MinimizeButton-Up") then
		b = CreateFrame("Button", nil, frame)
		b:SetSize(32, 32)
		b:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
		b:SetPushedTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Down")
		b:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight", "ADD")
	else
		b = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	end
	b:SetPoint("TOPRIGHT", -5, -5)
	b:SetScript("OnClick", onClick or function()
		frame:Hide()
	end)
	return b
end

---------------------------------------------------------------------------
-- Check boxes and radio buttons
---------------------------------------------------------------------------
function W.Check(parent, label, tip, get, set)
	local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	cb:SetSize(24, 24)
	local text = cb.Text
	if not text then
		text = cb:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
		cb.Text = text
	end
	text:SetFontObject("GameFontHighlight")
	text:ClearAllPoints()
	text:SetPoint("LEFT", cb, "RIGHT", 1, 1)
	text:SetJustifyH("LEFT")
	cb.label = text
	cb.getter, cb.setter = get, set
	W.Themed(cb, paintCheck)

	function cb:SetLabel(t)
		self.label:SetText(t or "")
		self:SetHitRectInsets(0, -min(320, floor(self.label:GetStringWidth() + 6)), 0, 0)
	end

	function cb:Refresh()
		if self.getter then
			self:SetChecked(self.getter() and true or false)
		end
	end

	function cb:SetActive(on)
		self:SetEnabled(on)
		self.label:SetFontObject(on and "GameFontHighlight" or "GameFontDisable")
	end

	cb:SetLabel(label)
	cb:SetMotionScriptsWhileDisabled(true)
	cb:SetScript("OnClick", function(self)
		local on = self:GetChecked() and true or false
		W.Sound(on and "on" or "off")
		if self.setter then
			self.setter(on, self)
		end
	end)
	if tip then
		W.AttachTooltip(cb, label, tip)
	end
	cb:Refresh()
	return cb
end

-- One of a group: isOn() says whether it is the chosen one, choose() makes it so.
function W.Radio(parent, label, tip, isOn, choose)
	local rb = CreateFrame("CheckButton", nil, parent, "UIRadioButtonTemplate")
	rb:SetSize(16, 16)
	local text = rb.text
	if not text then
		text = rb:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
		rb.text = text
	end
	text:SetFontObject("GameFontHighlight")
	text:ClearAllPoints()
	text:SetPoint("LEFT", rb, "RIGHT", 5, 0)
	text:SetText(label or "")
	rb.label = text
	rb:SetHitRectInsets(0, -min(200, floor(text:GetStringWidth() + 8)), -3, -3)
	W.Themed(rb, paintCheck)

	function rb:Refresh()
		self:SetChecked(isOn() and true or false)
	end

	rb:SetScript("OnClick", function(self)
		W.Sound("on")
		choose(self)
		self:Refresh()
	end)
	if tip then
		W.AttachTooltip(rb, label, tip)
	end
	rb:Refresh()
	return rb
end

---------------------------------------------------------------------------
-- Slider (classic options slider)
---------------------------------------------------------------------------
function W.Slider(parent, label, minV, maxV, step, get, set, fmt, width)
	local s = CreateFrame("Slider", nil, parent, "BackdropTemplate")
	s:SetOrientation("HORIZONTAL")
	s:SetSize(width or 180, 17)
	s:SetHitRectInsets(0, 0, -10, -10)
	W.SetBackdrop(s, "slider")
	s:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
	local thumb = s:GetThumbTexture()
	if thumb then
		thumb:SetSize(32, 32)
	end
	s:SetMinMaxValues(minV, maxV)
	s:SetValueStep(step or 1)
	s:SetObeyStepOnDrag(true)
	s.getter, s.setter = get, set
	fmt = fmt or "%d"

	s.label = s:CreateFontString(nil, "ARTWORK", "LevelTimeTrackerFontNormalSmall")
	s.label:SetPoint("BOTTOM", s, "TOP", 0, 2)
	s.label:SetText(label or "")
	s.low = s:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	s.low:SetPoint("TOPLEFT", s, "BOTTOMLEFT", 2, 3)
	s.high = s:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	s.high:SetPoint("TOPRIGHT", s, "BOTTOMRIGHT", -2, 3)
	s.value = s:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	s.value:SetPoint("TOP", s, "BOTTOM", 0, 3)

	local function show(v)
		if type(fmt) == "function" then
			return fmt(v)
		end
		return string.format(fmt, v)
	end
	s.low:SetText(show(minV))
	s.high:SetText(show(maxV))

	local function snap(v)
		local st = step or 1
		v = floor((v - minV) / st + 0.5) * st + minV
		return U.Clamp(v, minV, maxV)
	end

	-- The value only reaches the setter when the mouse lets go (resizing a window while dragging would move the slider).
	s:SetScript("OnValueChanged", function(self, v)
		v = snap(v)
		self.value:SetText(show(v))
		if not self.updating then
			self.dirty = v
		end
	end)
	s:SetScript("OnMouseUp", function(self)
		local v = self.dirty
		self.dirty = nil
		if v ~= nil and self.setter and v ~= self.last then
			self.last = v
			self.setter(v)
		end
	end)
	s:EnableMouseWheel(true)
	s:SetScript("OnMouseWheel", function(self, delta)
		local v = snap(self:GetValue() + delta * (step or 1))
		self.updating = true
		self:SetValue(v)
		self.updating = false
		self.value:SetText(show(v))
		if self.setter and v ~= self.last then
			self.last = v
			self.setter(v)
		end
	end)

	function s:Refresh()
		if not self.getter then
			return
		end
		local v = self.getter() or minV
		self.updating = true
		self.last = v
		self:SetValue(v)
		self.value:SetText(show(v))
		self.updating = false
	end

	s:Refresh()
	return s
end

---------------------------------------------------------------------------
-- Skill bars (the character sheet's skill bar: metal border, coloured fill, text on it)
---------------------------------------------------------------------------
local BAR_FILL = "Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar"
local BAR_BORDER = "Interface\\PaperDollInfoFrame\\UI-Character-Skills-BarBorder"

local function paintBar(bar, th)
	for _, tex in ipairs(bar.art) do
		W.Tint(tex, th.metal)
	end
	if bar.plain then
		local c = th.bar or BLUE
		bar:SetColor(c[1], c[2], c[3])
	end
end

local function layoutExtra(bar)
	local extra = bar.extra
	if not extra:IsShown() then
		return
	end
	local lo, hi = bar:GetMinMaxValues()
	local span = hi - lo
	local w = bar:GetWidth() or 0
	local to = span > 0 and U.Clamp((bar:GetValue() - lo + (bar.extraAmount or 0)) / span, 0, 1) or 0
	extra:SetWidth(max(1, floor(w * to + 0.5)))
end

-- height: of the fill; the border sits 3 pixels outside it.
function W.Bar(parent, height)
	height = height or 13
	local bar = CreateFrame("StatusBar", nil, parent)
	bar:SetHeight(height)
	bar:SetStatusBarTexture(BAR_FILL)
	bar:GetStatusBarTexture():SetDrawLayer("BORDER", 1)
	bar:SetMinMaxValues(0, 1)
	bar:SetValue(0)
	bar.bg = bar:CreateTexture(nil, "BACKGROUND")
	bar.bg:SetAllPoints()

	-- Rested XP: a second fill reaching past the first one.
	bar.extra = bar:CreateTexture(nil, "BORDER", nil, 0)
	bar.extra:SetTexture(BAR_FILL)
	bar.extra:SetPoint("TOPLEFT")
	bar.extra:SetPoint("BOTTOMLEFT")
	bar.extra:Hide()

	local left = bar:CreateTexture(nil, "ARTWORK")
	left:SetTexture(BAR_BORDER)
	left:SetSize(9, height + 6)
	left:SetPoint("LEFT", -3, 0)
	left:SetTexCoord(0.007843, 0.043137, 0.193548, 0.774193)
	local right = bar:CreateTexture(nil, "ARTWORK")
	right:SetTexture(BAR_BORDER)
	right:SetSize(9, height + 6)
	right:SetPoint("RIGHT", 3, 0)
	right:SetTexCoord(0.043137, 0.007843, 0.193548, 0.774193)
	local mid = bar:CreateTexture(nil, "ARTWORK")
	mid:SetTexture(BAR_BORDER)
	mid:SetPoint("TOPLEFT", left, "TOPRIGHT")
	mid:SetPoint("BOTTOMRIGHT", right, "BOTTOMLEFT")
	mid:SetTexCoord(0.113726, 0.149020, 0.193548, 0.774193)
	bar.art = { left, right, mid }

	bar.value = bar:CreateFontString(nil, "OVERLAY", "TextStatusBarText")
	bar.value:SetPoint("RIGHT", -5, 0)
	bar.value:SetJustifyH("RIGHT")
	bar.label = bar:CreateFontString(nil, "OVERLAY", "TextStatusBarText")
	bar.label:SetPoint("LEFT", 5, 0)
	bar.label:SetPoint("RIGHT", bar.value, "LEFT", -6, 0)
	bar.label:SetJustifyH("LEFT")
	bar.label:SetWordWrap(false)

	function bar:SetColor(r, g, b)
		self:SetStatusBarColor(r, g, b)
		self.bg:SetColorTexture(r * 0.2, g * 0.2, b * 0.2, 0.85)
	end

	-- Bars without a colour of their own take the theme's bar colour.
	function bar:Set(label, value, maxValue, r, g, b, valueText)
		self.plain = r == nil
		if self.plain then
			local c = W.theme.bar or BLUE
			r, g, b = c[1], c[2], c[3]
		end
		self.label:SetText(label or "")
		self:SetMinMaxValues(0, max(1, maxValue or 1))
		self:SetValue(value or 0)
		self:SetColor(r, g, b)
		self.value:SetText(valueText or "")
		layoutExtra(self)
	end

	-- A second fill for `amount` more (rested XP), in its own colour; nil or 0 hides it.
	function bar:SetExtra(amount, r, g, b)
		self.extraAmount = amount
		if amount and amount > 0 then
			self.extra:SetVertexColor(r, g, b, 0.75)
			self.extra:Show()
			layoutExtra(self)
		else
			self.extra:Hide()
		end
	end

	bar:SetScript("OnSizeChanged", layoutExtra)
	return W.Themed(bar, paintBar)
end

-- A thin bar without a border: a level's time next to the longest one. It sizes its fill itself.
function W.PaceBar(parent, height)
	local bar = CreateFrame("StatusBar", nil, parent)
	bar:SetHeight(height or 6)
	bar:SetStatusBarTexture(BAR_FILL)
	bar:SetMinMaxValues(0, 1)
	bar:SetValue(0)
	bar.track = bar:CreateTexture(nil, "BACKGROUND")
	bar.track:SetAllPoints()
	bar.track:SetColorTexture(0, 0, 0, 0.35)

	-- value of longest, in the theme's bar colour unless r, g, b are given.
	function bar:SetPace(value, longest, r, g, b)
		if not r then
			local c = W.theme.bar or BLUE
			r, g, b = c[1], c[2], c[3]
		end
		self:SetMinMaxValues(0, max(1, longest or 1))
		self:SetValue(max(0, value or 0))
		self:SetStatusBarColor(r, g, b)
	end
	return bar
end

---------------------------------------------------------------------------
-- List with column headers, virtual rows and a classic scroll bar.
-- cols: { key, label, width | fill = true, get(item) -> text, r, g, b, sortValue(item), justify, tip, defaultDesc }
-- opts: { rowHeight, onClick(item, row, button), onEnter(item, row), selectKey(item), sortKey, sortDesc, empty,
--         decorate(row, item, list) }
---------------------------------------------------------------------------
local HEADER_TEX = "Interface\\FriendsFrame\\WhoFrame-ColumnTabs"
local SORT_ARROW = "Interface\\Buttons\\UI-SortArrow"

local List = {}

local function paintHeaderButton(b, th)
	paintArt(b, th)
	local a = th.accent
	W.Tint(b.arrow, th.metal and a)
end

local function listHeaderButton(list, col)
	local b = CreateFrame("Button", nil, list.header)
	b:SetHeight(24)
	local l = b:CreateTexture(nil, "BACKGROUND")
	l:SetTexture(HEADER_TEX)
	l:SetSize(5, 24)
	l:SetPoint("TOPLEFT")
	l:SetTexCoord(0, 0.078125, 0, 0.75)
	local r = b:CreateTexture(nil, "BACKGROUND")
	r:SetTexture(HEADER_TEX)
	r:SetSize(4, 24)
	r:SetPoint("TOPRIGHT")
	r:SetTexCoord(0.90625, 0.96875, 0, 0.75)
	local m = b:CreateTexture(nil, "BACKGROUND")
	m:SetTexture(HEADER_TEX)
	m:SetPoint("TOPLEFT", l, "TOPRIGHT")
	m:SetPoint("BOTTOMRIGHT", r, "BOTTOMLEFT")
	m:SetTexCoord(0.078125, 0.90625, 0, 0.75)
	local hl = b:CreateTexture(nil, "HIGHLIGHT")
	hl:SetTexture("Interface\\PaperDollInfoFrame\\UI-Character-Tab-Highlight")
	hl:SetBlendMode("ADD")
	hl:SetPoint("TOPLEFT", 2, 0)
	hl:SetPoint("BOTTOMRIGHT", -2, 0)
	b.art = { l, r, m }

	local fs = b:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	fs:SetPoint("LEFT", 8, 0)
	fs:SetJustifyH("LEFT")
	fs:SetWordWrap(false)
	fs:SetText(col.label or "")
	b.text = fs

	b.arrow = b:CreateTexture(nil, "ARTWORK")
	b.arrow:SetSize(9, 8)
	b.arrow:SetPoint("LEFT", fs, "RIGHT", 3, -2)
	b.arrow:SetTexture(SORT_ARROW)
	b.arrow:Hide()
	W.Themed(b, paintHeaderButton)

	b.col = col
	if col.sortValue then
		b:SetScript("OnClick", function()
			W.Sound("click")
			list:ToggleSort(col.key)
		end)
	else
		b:EnableMouse(col.tip ~= nil)
		hl:SetAlpha(0)
	end
	if col.tip then
		W.AttachTooltip(b, col.label, col.tip)
	end
	return b
end

local function rowClick(row, button)
	local list, item = row.list, row.item
	if not item then
		return
	end
	local opts = list.opts
	if opts.selectKey and button ~= "RightButton" then
		list.selected = opts.selectKey(item)
		list:Refresh()
	end
	if opts.onClick then
		opts.onClick(item, row, button)
	end
end

local function rowEnter(row)
	local list, item = row.list, row.item
	if item and list.opts.onEnter then
		list.opts.onEnter(item, row)
	end
end

local function makeRow(list, i)
	local row = CreateFrame("Button", nil, list.body)
	row:SetHeight(list.rowH)
	row:SetPoint("TOPLEFT", list.body, "TOPLEFT", 0, -(i - 1) * list.rowH)
	row:SetPoint("TOPRIGHT", list.body, "TOPRIGHT", 0, -(i - 1) * list.rowH)
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	local hl = row:CreateTexture(nil, "HIGHLIGHT")
	hl:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
	hl:SetBlendMode("ADD")
	hl:SetAllPoints()
	row:SetHighlightTexture(hl)
	W.Themed(hl, paintHighlight)
	row.list = list
	row.cells = {}
	for c, col in ipairs(list.cols) do
		local fs = row:CreateFontString(nil, "ARTWORK", col.font or "GameFontHighlightSmall")
		fs:SetJustifyH(col.justify or "LEFT")
		fs:SetWordWrap(false)
		fs.dr, fs.dg, fs.db = fs:GetTextColor()
		row.cells[c] = fs
	end
	row:SetScript("OnClick", rowClick)
	row:SetScript("OnEnter", rowEnter)
	row:SetScript("OnLeave", W.HideTip)
	list.rows[i] = row
	list:LayoutRow(row)
	return row
end

function List:ColumnLayout()
	local total = self.header:GetWidth()
	if not total or total <= 0 then
		total = self:GetWidth() - 32
	end
	local fixed, fills = 0, 0
	for _, col in ipairs(self.cols) do
		if col.fill then
			fills = fills + 1
		else
			fixed = fixed + (col.width or 60)
		end
	end
	local fillW = fills > 0 and max(40, floor((total - fixed) / fills)) or 0
	local x = 0
	self.colX, self.colW = self.colX or {}, self.colW or {}
	for c, col in ipairs(self.cols) do
		local w = col.fill and fillW or (col.width or 60)
		self.colX[c], self.colW[c] = x, w
		x = x + w
	end
	if self.headers then
		for c, b in ipairs(self.headers) do
			b:ClearAllPoints()
			b:SetPoint("TOPLEFT", self.header, "TOPLEFT", self.colX[c], 0)
			b:SetWidth(self.colW[c])
			b.text:SetWidth(max(10, self.colW[c] - 22))
		end
	end
	for _, row in ipairs(self.rows) do
		self:LayoutRow(row)
	end
end

function List:LayoutRow(row)
	if not self.colX then
		return
	end
	for c, fs in ipairs(row.cells) do
		fs:ClearAllPoints()
		fs:SetPoint("LEFT", row, "LEFT", self.colX[c] + 6, 0)
		fs:SetWidth(max(8, self.colW[c] - 10))
	end
	if row.item and self.opts.decorate then
		self.opts.decorate(row, row.item, self)
	end
end

-- Left edge and width of a column (by key) inside a row.
function List:Column(key)
	for c, col in ipairs(self.cols) do
		if col.key == key then
			return self.colX[c] or 0, self.colW[c] or 0
		end
	end
	return 0, 0
end

function List:UpdateRowCount()
	local h = self.body:GetHeight() or 0
	local n = max(0, floor(h / self.rowH))
	self.numRows = n
	for i = #self.rows + 1, n do
		makeRow(self, i)
	end
end

function List:UpdateSortArrows()
	if not self.headers then
		return
	end
	for _, b in ipairs(self.headers) do
		if b.col.key == self.sortKey and b.col.sortValue then
			b.arrow:Show()
			if self.sortDesc then
				b.arrow:SetTexCoord(0, 0.5625, 1, 0)
			else
				b.arrow:SetTexCoord(0, 0.5625, 0, 1)
			end
			b.text:SetFontObject("LevelTimeTrackerFontNormalSmall")
		else
			b.arrow:Hide()
			b.text:SetFontObject("GameFontHighlightSmall")
		end
	end
end

function List:Sort()
	local view = self.view
	wipe(view)
	for i, item in ipairs(self.data) do
		view[i] = item
	end
	local col
	for _, c in ipairs(self.cols) do
		if c.key == self.sortKey then
			col = c
			break
		end
	end
	if not col or not col.sortValue then
		return
	end
	local vals, order = {}, {}
	for i, item in ipairs(view) do
		vals[item] = col.sortValue(item)
		order[item] = i
	end
	local desc = self.sortDesc
	table.sort(view, function(a, b)
		local va, vb = vals[a], vals[b]
		if va ~= vb then
			if va == nil then
				return false
			elseif vb == nil then
				return true
			end
			if desc then
				return va > vb
			end
			return va < vb
		end
		return order[a] < order[b]
	end)
end

function List:ToggleSort(key)
	if self.sortKey == key then
		self.sortDesc = not self.sortDesc
	else
		self.sortKey = key
		self.sortDesc = false
		for _, c in ipairs(self.cols) do
			if c.key == key then
				self.sortDesc = c.defaultDesc and true or false
			end
		end
	end
	self:UpdateSortArrows()
	self:Sort()
	self:Refresh()
end

function List:SetData(data)
	self.data = data or {}
	self:Sort()
	self:Refresh()
end

function List:SetOffset(offset)
	local maxOff = max(0, #self.view - (self.numRows or 0))
	offset = U.Clamp(floor(offset + 0.5), 0, maxOff)
	if offset ~= self.offset then
		self.offset = offset
		self:Refresh()
	end
end

function List:Refresh()
	local view = self.view
	local n = #view
	local visible = self.numRows or 0
	local maxOff = max(0, n - visible)
	if self.offset > maxOff then
		self.offset = maxOff
	end
	local bar = self.bar
	self.updating = true
	bar:SetMinMaxValues(0, maxOff)
	bar:SetValue(self.offset)
	self.updating = false
	local thumb = bar:GetThumbTexture()
	if thumb then
		thumb:SetShown(maxOff > 0)
	end
	if bar.ScrollUpButton then
		bar.ScrollUpButton:SetEnabled(self.offset > 0)
		bar.ScrollDownButton:SetEnabled(self.offset < maxOff)
	end

	local selectKey, selected = self.opts.selectKey, self.selected
	for i, row in ipairs(self.rows) do
		local item = i <= visible and view[self.offset + i] or nil
		row.item = item
		if item then
			for c, col in ipairs(self.cols) do
				local fs = row.cells[c]
				local text, r, g, b = col.get(item)
				fs:SetText(text or "")
				if r then
					fs:SetTextColor(r, g, b)
				else
					fs:SetTextColor(fs.dr, fs.dg, fs.db)
				end
			end
			if selectKey and selected ~= nil and selectKey(item) == selected then
				row:LockHighlight()
			else
				row:UnlockHighlight()
			end
			if self.opts.decorate then
				self.opts.decorate(row, item, self)
			end
			row:Show()
		else
			row:Hide()
		end
	end
	self.emptyText:SetShown(n == 0)
end

function W.List(parent, cols, opts)
	opts = opts or {}
	local list = W.Frame(parent, "box")
	for k, v in pairs(List) do
		list[k] = v
	end
	list.cols, list.opts = cols, opts
	list.rowH = opts.rowHeight or 18
	list.data, list.view, list.rows = {}, {}, {}
	list.offset, list.numRows = 0, 0
	list.sortKey, list.sortDesc = opts.sortKey, opts.sortDesc and true or false

	local header = CreateFrame("Frame", nil, list)
	header:SetPoint("TOPLEFT", 6, -5)
	header:SetPoint("TOPRIGHT", -26, -5)
	header:SetHeight(24)
	list.header = header
	list.headers = {}
	for c, col in ipairs(cols) do
		list.headers[c] = listHeaderButton(list, col)
	end

	local body = CreateFrame("Frame", nil, list)
	body:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -1)
	body:SetPoint("BOTTOMRIGHT", -26, 6)
	body:EnableMouseWheel(true)
	list.body = body

	local bar = CreateFrame("Slider", nil, list, "UIPanelScrollBarTemplate")
	-- Replace the template's handler first: it scrolls its parent, which is not a ScrollFrame here.
	bar:SetScript("OnValueChanged", function(_, value)
		if not list.updating then
			list:SetOffset(value)
		end
	end)
	bar:SetPoint("TOPRIGHT", list, "TOPRIGHT", -6, -21)
	bar:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", -6, 21)
	bar:SetMinMaxValues(0, 0)
	bar:SetValueStep(1)
	bar:SetObeyStepOnDrag(true)
	bar.scrollStep = 3
	bar:SetValue(0)
	local track = bar:CreateTexture(nil, "BACKGROUND")
	track:SetAllPoints()
	track:SetColorTexture(0, 0, 0, 0.3)
	W.ThemeScrollBar(bar)
	list.bar = bar

	body:SetScript("OnMouseWheel", function(_, delta)
		list:SetOffset(list.offset - delta * 3)
	end)
	body:SetScript("OnSizeChanged", function()
		list:UpdateRowCount()
		list:Refresh()
	end)
	header:SetScript("OnSizeChanged", function()
		list:ColumnLayout()
	end)

	list.emptyText = body:CreateFontString(nil, "ARTWORK", "GameFontDisable")
	list.emptyText:SetPoint("TOP", 0, -30)
	list.emptyText:SetWidth(360)
	list.emptyText:SetText(opts.empty or L["Nothing to show."])
	list.emptyText:Hide()

	list:ColumnLayout()
	list:UpdateSortArrows()
	return list
end

---------------------------------------------------------------------------
-- Windows: the header plate, position memory and the UI size
---------------------------------------------------------------------------
function W.Header(frame, title)
	local h = CreateFrame("Frame", nil, frame)
	h:SetHeight(40)
	h:SetPoint("TOP", 0, 12)
	local tex = "Interface\\DialogFrame\\UI-DialogBox-Header"
	local l = h:CreateTexture(nil, "ARTWORK")
	l:SetTexture(tex)
	l:SetTexCoord(0.21, 0.31, 0, 0.63)
	l:SetPoint("TOPLEFT")
	l:SetPoint("BOTTOMLEFT")
	l:SetWidth(30)
	local r = h:CreateTexture(nil, "ARTWORK")
	r:SetTexture(tex)
	r:SetTexCoord(0.67, 0.77, 0, 0.63)
	r:SetPoint("TOPRIGHT")
	r:SetPoint("BOTTOMRIGHT")
	r:SetWidth(30)
	local m = h:CreateTexture(nil, "ARTWORK")
	m:SetTexture(tex)
	m:SetTexCoord(0.31, 0.67, 0, 0.63)
	m:SetPoint("TOPLEFT", l, "TOPRIGHT")
	m:SetPoint("BOTTOMRIGHT", r, "BOTTOMLEFT")
	h.art = { l, r, m }
	W.Themed(h, paintArt)
	h.text = h:CreateFontString(nil, "OVERLAY", "LevelTimeTrackerFontTitle")
	h.text:SetPoint("TOP", 0, -14)

	function h:SetTitle(t)
		self.text:SetText(t or "")
		self:SetWidth(max(160, floor(self.text:GetStringWidth() + 80)))
	end

	h:EnableMouse(true)
	h:RegisterForDrag("LeftButton")
	h:SetScript("OnDragStart", function()
		W.StartMoving(frame)
	end)
	h:SetScript("OnDragStop", function()
		W.StopMoving(frame)
	end)
	h:SetTitle(title)
	return h
end

function W.SavePos(f)
	local name = f:GetName()
	if not name or not ns.S then
		return
	end
	local point, _, relPoint, x, y = f:GetPoint(1)
	if not point then
		return
	end
	ns.S.pos[name] = { point = point, relPoint = relPoint, x = floor(x + 0.5), y = floor(y + 0.5) }
end

function W.RestorePos(f, point, relPoint, x, y)
	local name = f:GetName()
	local p = name and ns.S and ns.S.pos and ns.S.pos[name]
	f:ClearAllPoints()
	if p then
		f:SetPoint(p.point or "CENTER", UIParent, p.relPoint or "CENTER", p.x or 0, p.y or 0)
	else
		f:SetPoint(point or "CENTER", UIParent, relPoint or point or "CENTER", x or 0, y or 0)
	end
end

-- Returns whether the frame started moving (a locked one doesn't).
function W.StartMoving(f)
	if f.locked then
		return false
	end
	f.moving = true
	f:StartMoving()
	return true
end

function W.StopMoving(f)
	if not f.moving then
		return
	end
	f.moving = false
	f:StopMovingOrSizing()
	-- The game anchors a moved frame however it likes; keep it relative to the screen's centre (stays put at any size).
	local cx, cy = f:GetCenter()
	local ux, uy = UIParent:GetCenter()
	if cx and ux then
		local s = f:GetEffectiveScale() / UIParent:GetEffectiveScale()
		f:ClearAllPoints()
		f:SetPoint("CENTER", UIParent, "CENTER", cx - ux / s, cy - uy / s)
	end
	W.SavePos(f)
end

-- The UI size: the saved setting, but never bigger than the screen can hold (the window with its header and tabs).
function W.Scale()
	local s = U.Clamp(tonumber(ns.S and ns.S.scale) or 1, 0.7, 1.5)
	local w, h = UIParent:GetWidth(), UIParent:GetHeight()
	if w and h and w > 0 and h > 0 then
		local ui = ns.UI or {}
		s = min(s, w / ((ui.WIDTH or 720) + 40), h / ((ui.HEIGHT or 470) + 60))
	end
	return s
end

-- The UI size changed: every window keeps its centre where it is on the screen.
function W.ApplyScale()
	local s = W.Scale()
	for _, f in ipairs(W.windows) do
		local old = f:GetScale()
		if old ~= s then
			local point, rel, relPoint, x, y = f:GetPoint(1)
			f:SetScale(s)
			if point then
				f:ClearAllPoints()
				f:SetPoint(point, rel, relPoint, x * old / s, y * old / s)
				W.SavePos(f)
			end
		end
	end
end

-- Top-level window with the classic dialog border and header. Among the game's own windows (MEDIUM, like the bags and
-- the character window): the one opened or clicked last is in front.
-- opts: { strata, sound, noEscape }
function W.Window(name, title, width, height, opts)
	opts = opts or {}
	local f = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
	f:Hide()
	f:SetSize(width, height)
	f:SetFrameStrata(opts.strata or "MEDIUM")
	f:SetClampedToScreen(true)
	f:SetToplevel(true)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetDontSavePosition(true)
	f:SetScript("OnDragStart", W.StartMoving)
	f:SetScript("OnDragStop", W.StopMoving)
	W.SetBackdrop(f, "dark")
	f.header = W.Header(f, title)
	f:SetClampRectInsets(0, 0, 12, 0)
	f.close = W.CloseButton(f)
	if name and not opts.noEscape then
		table.insert(UISpecialFrames, name)
	end
	f:SetScript("OnShow", function(self)
		if opts.sound then
			W.Sound("open")
		end
		if self.onShown then
			self:onShown()
		end
	end)
	f:SetScript("OnHide", function(self)
		W.StopMoving(self)
		if opts.sound then
			W.Sound("close")
		end
		if self.onHidden then
			self:onHidden()
		end
	end)
	f:SetScale(W.Scale())
	W.windows[#W.windows + 1] = f
	W.RestorePos(f)
	return f
end

---------------------------------------------------------------------------
-- Bottom tabs (character-frame style), tucked under the window border.
---------------------------------------------------------------------------
local TAB_ACTIVE = "Interface\\PaperDollInfoFrame\\UI-Character-ActiveTab"
local TAB_INACTIVE = "Interface\\PaperDollInfoFrame\\UI-Character-InActiveTab"
W.TAB_TUCK = 6

local function tabPieces(t, file, atlasPrefix, height, top, bottom, y)
	local pieces = {}
	local useFile = U.TexExists(file)
	local coords = { { 0, 0.15625 }, { 0.15625, 0.84375 }, { 0.84375, 1 } }
	local atlases = { atlasPrefix .. "-left", "_" .. atlasPrefix .. "-center", atlasPrefix .. "-right" }
	for i = 1, 3 do
		local tex = t:CreateTexture(nil, "BACKGROUND")
		if useFile then
			tex:SetTexture(file)
			tex:SetTexCoord(coords[i][1], coords[i][2], top, bottom)
		else
			tex:SetAtlas(atlases[i])
		end
		tex:SetHeight(height)
		pieces[i] = tex
	end
	pieces[1]:SetWidth(20)
	pieces[3]:SetWidth(20)
	pieces[1]:SetPoint("TOPLEFT", 0, y)
	pieces[2]:SetPoint("LEFT", pieces[1], "RIGHT")
	pieces[3]:SetPoint("LEFT", pieces[2], "RIGHT")
	return pieces
end

function W.Tab(parent, text)
	local t = CreateFrame("Button", nil, parent)
	t:SetHeight(32)
	t.inactive = tabPieces(t, TAB_INACTIVE, "uiframe-tab", 32, 0, 1, -1)
	t.active = tabPieces(t, TAB_ACTIVE, "uiframe-activetab", 35, 0, 0.546875, 0)
	t.art = { t.inactive[1], t.inactive[2], t.inactive[3], t.active[1], t.active[2], t.active[3] }
	W.Themed(t, paintArt)
	local fs = t:CreateFontString(nil, "OVERLAY", "LevelTimeTrackerFontNormalSmall")
	fs:SetPoint("CENTER", 0, -2)
	t:SetFontString(fs)
	t:SetNormalFontObject("LevelTimeTrackerFontNormalSmall")
	t:SetHighlightFontObject("GameFontHighlightSmall")
	t:SetDisabledFontObject("LevelTimeTrackerFontSelectedSmall")
	local hlFile = U.TexExists("Interface\\PaperDollInfoFrame\\UI-Character-Tab-RealHighlight")
		and "Interface\\PaperDollInfoFrame\\UI-Character-Tab-RealHighlight"
		or "Interface\\PaperDollInfoFrame\\UI-Character-Tab-Highlight"
	local hl = t:CreateTexture(nil, "HIGHLIGHT")
	hl:SetTexture(hlFile)
	hl:SetBlendMode("ADD")
	hl:SetPoint("TOPLEFT", 3, -W.TAB_TUCK + 2)
	hl:SetPoint("BOTTOMRIGHT", -3, 0)
	t:SetText(text)

	function t:Resize()
		local w = max(40, floor(fs:GetStringWidth() or 0) + 12)
		for _, set in ipairs({ self.inactive, self.active }) do
			set[2]:SetWidth(w)
		end
		self:SetWidth(w + 40)
	end

	function t:SetSelected(on)
		for i = 1, 3 do
			self.inactive[i]:SetShown(not on)
			self.active[i]:SetShown(on)
		end
		self:SetEnabled(not on)
		fs:SetPoint("CENTER", 0, on and -3 or -2)
	end

	t:Resize()
	t:SetSelected(false)
	return t
end

-- Tabs sit one frame level below the window so its border overlaps them.
function W.TabBar(frame, defs, onSelect)
	local bar = { tabs = {}, byId = {}, frame = frame }
	local prev
	for i, def in ipairs(defs) do
		local t = W.Tab(frame, def.label)
		if t.SetFixedFrameLevel then
			t:SetFixedFrameLevel(true)
		end
		if i == 1 then
			t:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 12, W.TAB_TUCK)
		else
			t:SetPoint("LEFT", prev, "RIGHT", -15, 0)
		end
		t.id = def.id
		if def.tip then
			W.AttachTooltip(t, def.label, def.tip, "ANCHOR_BOTTOM")
		end
		t:SetScript("OnClick", function()
			W.Sound("tab")
			bar:Select(def.id)
		end)
		bar.tabs[i] = t
		bar.byId[def.id] = t
		prev = t
	end

	function bar:Relevel()
		local level = max(1, self.frame:GetFrameLevel() - 1)
		for _, t in ipairs(self.tabs) do
			t:SetFrameLevel(level)
		end
	end

	function bar:Select(id)
		if not self.byId[id] then
			id = self.tabs[1].id
		end
		self.selected = id
		for _, x in ipairs(self.tabs) do
			x:SetSelected(x.id == id)
		end
		if onSelect then
			onSelect(id)
		end
	end

	bar:Relevel()
	frame:SetClampRectInsets(0, 0, 12, -28)
	frame.tabs = bar
	return bar
end

-- A click on a window, or on anything in it, raises it (it is toplevel). Its tabs have a fixed level so that its border
-- is drawn over them; they follow on the next frame.
local function relevelTabs()
	for _, f in ipairs(W.windows) do
		if f.tabs and f:IsShown() then
			f.tabs:Relevel()
		end
	end
end

local Tabs = ns:NewModule("Tabs")
function Tabs:Enable()
	ns:RegisterEvent("GLOBAL_MOUSE_DOWN", function()
		for _, f in ipairs(W.windows) do
			if f.tabs and f:IsShown() then
				C_Timer.After(0, relevelTabs)
				return
			end
		end
	end)
end
