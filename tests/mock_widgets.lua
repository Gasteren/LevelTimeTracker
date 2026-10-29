-- mock_widgets.lua: a small, strict model of WoW's widget system for the tests.
-- Unknown methods raise an error (so a typo can't pass), every method the addon calls is recorded (MOCK.used) so the
-- runner can check it against Blizzard's API documentation for both games, and anchors are resolved into rectangles
-- so the layout can be checked (and rendered with the game's textures by the dev renderer).
MOCK = MOCK or {}
MOCK.used = {}
MOCK.frames = {}
MOCK.screen = { width = 1366, height = 768 }

local Methods = {}
local Widget = {}

local function Kind(obj)
	return rawget(obj, "_kind")
end

local mt = {
	__index = function(obj, key)
		local kind = Kind(obj)
		local m = Methods[kind] and Methods[kind][key]
		if m then
			MOCK.used[kind .. ":" .. key] = true
			return m
		end
		if type(key) == "string" and key:match("^[A-Z]") then
			error(("%s has no method or field %s"):format(kind, key), 2)
		end
		return nil
	end,
}

local function Inherit(kind, parentKind)
	Methods[kind] = setmetatable({}, { __index = Methods[parentKind] })
end

-- Fonts: Blizzard's sizes unless a test plays a UI addon that makes them bigger (MOCK.fontScale). A letter is about
-- 0.55 of the font size wide, as in the game.
local FONT_SIZES = {
	GameFontNormalHuge = 20, GameFontHighlightHuge = 20, GameFontNormalLarge = 16, GameFontHighlightLarge = 16,
	ChatFontNormal = 14, TextStatusBarText = 10,
}
local function FontName(font)
	if type(font) == "table" then
		return rawget(font, "_name") or rawget(font, "_copyOf") or "GameFontNormal"
	end
	return font or "GameFontNormal"
end
local function BaseFont(name)
	local font = rawget(_G, name) or (MOCK.api and MOCK.api[name])
	local seen = 0
	while type(font) == "table" and rawget(font, "_copyOf") and seen < 5 do
		name = rawget(font, "_copyOf")
		font = rawget(_G, name) or (MOCK.api and MOCK.api[name])
		seen = seen + 1
	end
	return name
end
local function FontHeight(font)
	local name = BaseFont(FontName(font))
	local size = FONT_SIZES[name] or ((name or ""):find("Small") and 10) or 12
	return size * (MOCK.fontScale or 1)
end
MOCK.FontHeight = FontHeight
local function Plain(text)
	return (text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "WW")
end
local function TextWidth(fs)
	return #Plain(fs._text) * FontHeight(fs._font) * 0.55
end
MOCK.Plain = Plain

-- Region (textures, font strings, frames) ------------------------------------------------------------------------------
Methods.Region = {}
local R = Methods.Region

function R:GetObjectType() return self._kind end
function R:IsObjectType(t) return self._kind == t or (t == "Frame" and self._isFrame) or t == "Region" end
function R:GetName() return self._name end
function R:GetParent() return self._parent end
function R:SetSize(w, h) self._w, self._h = w, h end
function R:SetWidth(w) self._w = w end
function R:SetHeight(h) self._h = h end
function R:GetSize() return self:GetWidth(), self:GetHeight() end
function R:GetWidth()
	if self._w and self._w > 0 then return self._w end
	local rect = Widget.Rect(self)
	return rect and rect.w / Widget.Scale(self) or 0
end
function R:GetHeight()
	if self._h and self._h > 0 then return self._h end
	local rect = Widget.Rect(self)
	return rect and rect.h / Widget.Scale(self) or 0
end
function R:ClearAllPoints() self._points = {} end
function R:SetPoint(point, a, b, c, d)
	local rel, relPoint, x, y = self._parent, point, 0, 0
	if type(a) == "number" then
		x, y = a, b or 0
	elseif a ~= nil then
		rel = type(a) == "string" and _G[a] or a
		if type(b) == "number" then
			x, y = b, c or 0
		else
			relPoint = b or point
			x, y = c or 0, d or 0
		end
	end
	assert(Widget.POINTS[point], "bad anchor point " .. tostring(point))
	assert(Widget.POINTS[relPoint], "bad relative point " .. tostring(relPoint))
	assert(type(x) == "number" and type(y) == "number", "SetPoint offsets must be numbers")
	assert(rel ~= self, "a region can't be anchored to itself")
	for i, p in ipairs(self._points) do
		if p[1] == point then
			table.remove(self._points, i)
			break
		end
	end
	table.insert(self._points, { point, rel, relPoint, x, y })
end
function R:SetAllPoints(rel)
	rel = rel or self._parent
	self:ClearAllPoints()
	self:SetPoint("TOPLEFT", rel, "TOPLEFT", 0, 0)
	self:SetPoint("BOTTOMRIGHT", rel, "BOTTOMRIGHT", 0, 0)
end
function R:GetNumPoints() return #self._points end
function R:GetPoint(i)
	local p = self._points[i or 1]
	if p then return p[1], p[2], p[3], p[4], p[5] end
end
function R:Show() Widget.SetShown(self, true) end
function R:Hide() Widget.SetShown(self, false) end
function R:SetShown(shown) Widget.SetShown(self, not not shown) end
function R:IsShown() return self._shown end
function R:IsVisible() return Widget.Visible(self) end
function R:SetAlpha(a) self._alpha = a end
function R:GetAlpha() return self._alpha end
function R:GetEffectiveScale() return Widget.Scale(self) end
local function Edge(self, which)
	local rect = Widget.Rect(self)
	if not rect then return nil end
	local s = Widget.Scale(self)
	if which == "left" then return rect.l / s elseif which == "right" then return (rect.l + rect.w) / s
	elseif which == "bottom" then return rect.b / s else return (rect.b + rect.h) / s end
end
function R:GetLeft() return Edge(self, "left") end
function R:GetRight() return Edge(self, "right") end
function R:GetTop() return Edge(self, "top") end
function R:GetBottom() return Edge(self, "bottom") end
function R:GetCenter()
	local rect = Widget.Rect(self)
	if not rect then return nil end
	local s = Widget.Scale(self)
	return (rect.l + rect.w / 2) / s, (rect.b + rect.h / 2) / s
end

-- Textures and font strings ---------------------------------------------------------------------------------------------
Inherit("Texture", "Region")
local T = Methods.Texture
function T:SetTexture(file, wrapH, wrapV)
	self._texture, self._color, self._atlas = file, nil, nil
	self._wrap = (wrapH == true or wrapH == "REPEAT") or nil
end
function T:GetTexture() return self._texture end
function T:SetColorTexture(r, g, b, a) self._color, self._texture, self._atlas = { r, g, b, a or 1 }, nil, nil end
function T:SetTexCoord(...) self._coords = { ... } end
function T:SetVertexColor(r, g, b, a) self._vertex = { r, g, b, a or 1 } end
function T:GetVertexColor() local v = self._vertex or { 1, 1, 1, 1 } return v[1], v[2], v[3], v[4] end
function T:SetDesaturated(on) self._desaturated = not not on end
function T:IsDesaturated() return self._desaturated == true end
function T:SetBlendMode(mode) self._blend = mode end
function T:SetDrawLayer(layer, sub) self._layer, self._sublevel = layer, sub or 0 end
function T:SetGradient(orientation, minColor, maxColor) self._gradient = { orientation, minColor, maxColor } end
function T:SetAtlas(atlas, useAtlasSize)
	assert(MOCK.atlases[atlas], "unknown atlas " .. tostring(atlas))
	self._atlas, self._texture, self._color = atlas, nil, nil
	if useAtlasSize then
		self:SetSize(MOCK.atlases[atlas].width, MOCK.atlases[atlas].height)
	end
end

Inherit("FontString", "Region")
local FS = Methods.FontString
function FS:SetText(text) self._text = text ~= nil and tostring(text) or "" end
function FS:GetText() return self._text end
function FS:SetFormattedText(fmt, ...) self._text = fmt:format(...) end
function FS:SetTextColor(r, g, b, a) self._textColor = { r, g, b, a or 1 } end
function FS:GetTextColor()
	local c = self._textColor
	if not c and type(self._font) == "string" then
		local font = rawget(_G, self._font) or MOCK.api[self._font]
		c = font and rawget(font, "_color")
	end
	c = c or { 1, 1, 1, 1 }
	return c[1], c[2], c[3], c[4]
end
function FS:SetJustifyH(j) self._justifyH = j end
function FS:SetJustifyV(j) self._justifyV = j end
function FS:SetFontObject(font)
	assert(type(font) == "table" or rawget(_G, font) or MOCK.api[font], "unknown font object " .. tostring(font))
	self._font = FontName(font)
end
function FS:GetFontObject() return self._font end
function FS:SetWordWrap(wrap) self._wrap = wrap end
function FS:SetNonSpaceWrap(wrap) self._nonSpaceWrap = wrap end
function FS:SetMaxLines(n) self._maxLines = n end
function FS:GetStringWidth() return TextWidth(self) end
function FS:GetUnboundedStringWidth() return TextWidth(self) end
function FS:GetStringHeight() local r = Widget.Rect(self) return r and r.h or FontHeight(self._font) end
function FS:GetFont() return "Fonts\\FRIZQT__.TTF", FontHeight(self._font), "" end
function FS:GetLineHeight() return FontHeight(self._font) end
function FS:GetSpacing() return 0 end
function FS:IsTruncated()
	local r = Widget.Rect(self)
	return r ~= nil and TextWidth(self) * Widget.Scale(self) > r.w + 0.5 and self._wrap == false
end

-- Font objects (CreateFont and the game's fonts) ------------------------------------------------------------------------
Methods.Font = {}
local FO = Methods.Font
function FO:CopyFontObject(other)
	self._copyOf = FontName(other)
	local c = type(other) == "table" and rawget(other, "_color")
	if c then self._color = { c[1], c[2], c[3], c[4] } end
end
function FO:SetTextColor(r, g, b, a) self._color = { r, g, b, a or 1 } end
function FO:GetTextColor() local c = self._color or { 1, 1, 1, 1 } return c[1], c[2], c[3], c[4] end
function FO:GetFont() return "Fonts\\FRIZQT__.TTF", FontHeight(self._name), "" end
function FO:GetName() return self._name end

function MOCK.NewFont(name, r, g, b)
	return setmetatable({ _kind = "Font", _name = name, _color = r and { r, g, b, 1 } or nil }, mt)
end

-- Frames ----------------------------------------------------------------------------------------------------------------
Inherit("Frame", "Region")
local F = Methods.Frame
function F:CreateTexture(name, layer, template, sublevel)
	return Widget.NewRegion("Texture", self, name, layer or "ARTWORK", sublevel or 0)
end
function F:CreateFontString(name, layer, font)
	if font then
		assert(rawget(_G, font) or MOCK.api[font], "unknown font object " .. tostring(font))
	end
	local fs = Widget.NewRegion("FontString", self, name, layer or "ARTWORK", 0)
	fs._font = font
	fs._text = ""
	return fs
end
function F:SetScript(event, fn) self._scripts[event] = fn end
function F:GetScript(event) return self._scripts[event] end
function F:HookScript(event, fn)
	self._hooks[event] = self._hooks[event] or {}
	table.insert(self._hooks[event], fn)
end
function F:HasScript(event) return true end
-- Each frame is once in the dispatch list (MOCK.Fire), however often it registers.
local listed = setmetatable({}, { __mode = "k" })
function F:RegisterEvent(event)
	assert(MOCK.KNOWN_EVENTS == nil or MOCK.KNOWN_EVENTS[event], "unknown event " .. tostring(event))
	self._events[event] = true
	if not listed[self] then
		listed[self] = true
		table.insert(MOCK.listeners, self)
	end
end
function F:UnregisterEvent(event) self._events[event] = nil end
function F:IsEventRegistered(event) return self._events[event] == true end
function F:SetParent(parent)
	self._parent = parent
	if parent then table.insert(parent._children, self) end
end
function F:GetChildren()
	local list = {}
	for _, child in ipairs(self._children) do
		if child._parent == self then list[#list + 1] = child end
	end
	return unpack(list)
end
function F:GetRegions() return unpack(self._regions) end
function F:SetFrameStrata(strata) self._strata = strata end
function F:GetFrameStrata() return self._strata end
function F:SetFrameLevel(level) self._level = level end
function F:GetFrameLevel() return self._level end
function F:SetFixedFrameLevel(on) self._fixedLevel = on end
function F:SetToplevel(on) self._toplevel = on end
function F:Raise() self._raised = (self._raised or 0) + 1 end
function F:SetClampedToScreen(on) self._clamped = on end
function F:SetClampRectInsets(l, r, t, b) self._clampInsets = { l, r, t, b } end
function F:SetMovable(on) self._movable = on end
function F:IsMovable() return self._movable == true end
function F:EnableMouse(on) self._mouse = not not on end
function F:IsMouseEnabled() return self._mouse end
function F:EnableMouseWheel(on) self._wheel = on end
function F:RegisterForDrag(...) self._drag = { ... } end
function F:SetDontSavePosition(on) self._dontSave = on end
function F:StartMoving()
	assert(self._movable, "StartMoving on a frame that isn't movable")
	self._moving = true
end
function F:StopMovingOrSizing()
	self._moving = false
	-- Like the game: a moved frame ends up anchored by its top left corner to the screen's bottom left.
	if MOCK.dragTo then
		local x, y = MOCK.dragTo[1], MOCK.dragTo[2]
		MOCK.dragTo = nil
		local s = Widget.Scale(self)
		self:ClearAllPoints()
		self:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / s, y / s)
	end
end
function F:SetScale(s) self._scale = s end
function F:GetScale() return self._scale end
function F:SetID(id) self._id = id end
function F:GetID() return self._id or 0 end
function F:IsMouseOver() return false end
function F:SetHitRectInsets(l, r, t, b) self._hitInsets = { l, r, t, b } end
function F:SetClipsChildren(on) self._clips = on end

-- BackdropTemplate: the nine pieces Blizzard's Backdrop.lua makes, with its texture coordinates (Blizzard_SharedXML).
local coordStart = 0.0625
local coordEnd = 1 - coordStart
local UVS = {
	TopLeftCorner = { 0.5078125, coordStart, 0.5078125, coordEnd, 0.6171875, coordStart, 0.6171875, coordEnd },
	TopRightCorner = { 0.6328125, coordStart, 0.6328125, coordEnd, 0.7421875, coordStart, 0.7421875, coordEnd },
	BottomLeftCorner = { 0.7578125, coordStart, 0.7578125, coordEnd, 0.8671875, coordStart, 0.8671875, coordEnd },
	BottomRightCorner = { 0.8828125, coordStart, 0.8828125, coordEnd, 0.9921875, coordStart, 0.9921875, coordEnd },
	TopEdge = { 0.2578125, "rx", 0.3671875, "rx", 0.2578125, coordStart, 0.3671875, coordStart },
	BottomEdge = { 0.3828125, "rx", 0.4921875, "rx", 0.3828125, coordStart, 0.4921875, coordStart },
	LeftEdge = { 0.0078125, coordStart, 0.0078125, "ry", 0.1171875, coordStart, 0.1171875, "ry" },
	RightEdge = { 0.1328125, coordStart, 0.1328125, "ry", 0.2421875, coordStart, 0.2421875, "ry" },
	Center = { 0, 0, 0, "ry", "rx", 0, "rx", "ry" },
}
MOCK.BACKDROP_UVS = UVS
local PIECES = { "TopLeftCorner", "TopRightCorner", "BottomLeftCorner", "BottomRightCorner", "TopEdge", "BottomEdge",
	"LeftEdge", "RightEdge", "Center" }

local Backdrop = {}
function Backdrop:SetBackdrop(info)
	assert(type(info) == "table", "SetBackdrop needs a table")
	self.backdropInfo = info
	local e = info.edgeSize or 39
	local pieces = {}
	for _, name in ipairs(PIECES) do
		local t = rawget(self, name)
		if not t then
			t = self:CreateTexture(nil, name == "Center" and "BACKGROUND" or "BORDER")
			rawset(self, name, t)
		end
		pieces[name] = t
		t:ClearAllPoints()
		t._backdropPiece = name
	end
	local function edge(t)
		if info.edgeFile then
			t:SetTexture(info.edgeFile, info.tileEdge ~= false, info.tileEdge ~= false)
		else
			t:SetTexture(nil)
		end
	end
	pieces.TopLeftCorner:SetPoint("TOPLEFT", self, "TOPLEFT")
	pieces.TopRightCorner:SetPoint("TOPRIGHT", self, "TOPRIGHT")
	pieces.BottomLeftCorner:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT")
	pieces.BottomRightCorner:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT")
	for _, name in ipairs({ "TopLeftCorner", "TopRightCorner", "BottomLeftCorner", "BottomRightCorner" }) do
		pieces[name]:SetSize(e, e)
		edge(pieces[name])
	end
	pieces.TopEdge:SetPoint("TOPLEFT", pieces.TopLeftCorner, "TOPRIGHT")
	pieces.TopEdge:SetPoint("BOTTOMRIGHT", pieces.TopRightCorner, "BOTTOMLEFT")
	pieces.BottomEdge:SetPoint("TOPLEFT", pieces.BottomLeftCorner, "TOPRIGHT")
	pieces.BottomEdge:SetPoint("BOTTOMRIGHT", pieces.BottomRightCorner, "BOTTOMLEFT")
	pieces.LeftEdge:SetPoint("TOPLEFT", pieces.TopLeftCorner, "BOTTOMLEFT")
	pieces.LeftEdge:SetPoint("BOTTOMRIGHT", pieces.BottomLeftCorner, "TOPRIGHT")
	pieces.RightEdge:SetPoint("TOPLEFT", pieces.TopRightCorner, "BOTTOMLEFT")
	pieces.RightEdge:SetPoint("BOTTOMRIGHT", pieces.BottomRightCorner, "TOPRIGHT")
	for _, name in ipairs({ "TopEdge", "BottomEdge", "LeftEdge", "RightEdge" }) do
		edge(pieces[name])
	end
	local ins = info.insets or {}
	pieces.Center:SetPoint("TOPLEFT", self, "TOPLEFT", ins.left or 0, -(ins.top or 0))
	pieces.Center:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", -(ins.right or 0), ins.bottom or 0)
	pieces.Center:SetTexture(info.bgFile, info.tile, info.tile)
	pieces.Center._tileSize = info.tile and (info.tileSize or e) or nil
	for name, t in pairs(pieces) do
		t._uvs = UVS[name]
		t._edgeSize = e
		t:SetVertexColor(1, 1, 1, 1)
	end
end
function Backdrop:SetBackdropColor(r, g, b, a)
	assert(self.backdropInfo, "SetBackdropColor before SetBackdrop")
	rawget(self, "Center"):SetVertexColor(r, g, b, a or 1)
end
function Backdrop:SetBackdropBorderColor(r, g, b, a)
	assert(self.backdropInfo, "SetBackdropBorderColor before SetBackdrop")
	for _, name in ipairs(PIECES) do
		if name ~= "Center" then rawget(self, name):SetVertexColor(r, g, b, a or 1) end
	end
end
function Backdrop:OnBackdropSizeChanged() end
MOCK.BackdropMixin = Backdrop

Inherit("Button", "Frame")
local B = Methods.Button
function B:SetText(text)
	local label = rawget(self, "_fontString")
	if label then label:SetText(text) end
	self._text = text
end
function B:GetText() return self._text end
function B:SetFontString(fs) self._fontString = fs end
function B:GetFontString() return rawget(self, "_fontString") end
function B:SetNormalFontObject(font)
	self._normalFont = font
	local fs = rawget(self, "_fontString")
	if fs and self._enabled ~= false then fs:SetFontObject(font) end
end
function B:SetHighlightFontObject(font) self._highlightFont = font end
function B:SetDisabledFontObject(font) self._disabledFont = font end
function B:Enable() self:SetEnabled(true) end
function B:Disable() self:SetEnabled(false) end
function B:SetEnabled(on)
	self._enabled = not not on
	local fs = rawget(self, "_fontString")
	if fs then
		local font = self._enabled and self._normalFont or self._disabledFont
		if font then fs:SetFontObject(font) end
	end
end
function B:IsEnabled() return self._enabled ~= false end
function B:SetMotionScriptsWhileDisabled(on) self._motionWhileDisabled = on end
function B:Click(button)
	if self._enabled == false then return end
	Widget.Fire(self, "OnClick", button or "LeftButton", false)
end
function B:RegisterForClicks(...) self._clicks = { ... } end
function B:LockHighlight() self._locked = true end
function B:UnlockHighlight() self._locked = false end
local function ButtonTexture(self, key, file, blend, layer)
	local t = rawget(self, key)
	if type(file) == "table" then
		t = file
	else
		if not t then
			t = self:CreateTexture(nil, layer or "ARTWORK")
			t:SetAllPoints(self)
		end
		t:SetTexture(file)
	end
	rawset(self, key, t)
	t._blend = blend
	return t
end
function B:SetNormalTexture(file) ButtonTexture(self, "_normal", file) end
function B:SetPushedTexture(file) ButtonTexture(self, "_pushed", file)._pushedOnly = true end
function B:SetDisabledTexture(file) ButtonTexture(self, "_disabled", file)._disabledOnly = true end
function B:SetHighlightTexture(file, blend) ButtonTexture(self, "_highlight", file, blend, "HIGHLIGHT") end
function B:GetNormalTexture() return rawget(self, "_normal") end
function B:GetPushedTexture() return rawget(self, "_pushed") end
function B:GetDisabledTexture() return rawget(self, "_disabled") end
function B:GetHighlightTexture() return rawget(self, "_highlight") end
function B:GetButtonState() return self._state or "NORMAL" end

Inherit("CheckButton", "Button")
local CB = Methods.CheckButton
function CB:SetChecked(on)
	self._checked = not not on
	local t = rawget(self, "_checkedTex")
	if t then t._hiddenByState = not self._checked end
end
function CB:GetChecked() return self._checked == true end
function CB:SetCheckedTexture(file)
	local t = ButtonTexture(self, "_checkedTex", file, nil, "OVERLAY")
	t._hiddenByState = not self._checked
end
function CB:GetCheckedTexture() return rawget(self, "_checkedTex") end
function CB:SetDisabledCheckedTexture(file) ButtonTexture(self, "_disabledChecked", file)._disabledOnly = true end
function CB:Click(button)
	if self._enabled == false then return end
	self:SetChecked(not self._checked)
	Widget.Fire(self, "OnClick", button or "LeftButton", false)
end

Inherit("StatusBar", "Frame")
local SB = Methods.StatusBar
function SB:SetStatusBarTexture(file)
	local t = rawget(self, "_fill")
	if not t then
		t = self:CreateTexture(nil, "ARTWORK")
		t:SetPoint("TOPLEFT")
		t:SetPoint("BOTTOMLEFT")
		t._fillOf = self
		rawset(self, "_fill", t)
	end
	t:SetTexture(file)
end
function SB:GetStatusBarTexture() return rawget(self, "_fill") end
function SB:SetMinMaxValues(lo, hi)
	assert(type(lo) == "number" and type(hi) == "number" and hi >= lo, "bad status bar range")
	self._min, self._max = lo, hi
end
function SB:GetMinMaxValues() return self._min or 0, self._max or 1 end
function SB:SetValue(v)
	assert(type(v) == "number" and v == v, "bad status bar value")
	self._value = v
end
function SB:GetValue() return self._value or 0 end
function SB:SetStatusBarColor(r, g, b, a)
	local t = rawget(self, "_fill")
	if t then t:SetVertexColor(r, g, b, a) end
	self._barColor = { r, g, b, a or 1 }
end

Inherit("Slider", "Frame")
local SL = Methods.Slider
function SL:SetOrientation(o) self._orientation = o end
function SL:SetMinMaxValues(lo, hi) self._min, self._max = lo, hi end
function SL:GetMinMaxValues() return self._min or 0, self._max or 0 end
function SL:SetValueStep(step) self._step = step end
function SL:SetObeyStepOnDrag(on) self._obey = on end
function SL:SetValue(v)
	local lo, hi = self._min or 0, self._max or 0
	v = math.max(lo, math.min(hi, v))
	local changed = v ~= self._value
	self._value = v
	if changed then Widget.Fire(self, "OnValueChanged", v, false) end
end
function SL:GetValue() return self._value or 0 end
function SL:SetThumbTexture(file)
	local t = rawget(self, "_thumb")
	if not t then
		t = self:CreateTexture(nil, "OVERLAY")
		t._thumbOf = self
		rawset(self, "_thumb", t)
	end
	t:SetTexture(file)
end
function SL:GetThumbTexture() return rawget(self, "_thumb") end
function SL:Enable() self._enabled = true end
function SL:Disable() self._enabled = false end
function SL:SetEnabled(on) self._enabled = not not on end
function SL:IsEnabled() return self._enabled ~= false end
-- The player drags the slider to `v` and lets go.
function MOCK.DragSlider(slider, v)
	slider:SetValue(v)
	Widget.Fire(slider, "OnMouseUp", "LeftButton")
end

Inherit("GameTooltip", "Frame")
local GT = Methods.GameTooltip
function GT:SetOwner(owner, anchor) self._owner = owner; self._lines = {} end
function GT:SetText(text) self._lines = { tostring(text) } end
function GT:AddLine(text) table.insert(self._lines, tostring(text)) end
function GT:AddDoubleLine(left, right) table.insert(self._lines, tostring(left) .. " | " .. tostring(right)) end
function GT:ClearLines() self._lines = {} end
function GT:IsOwned(owner) return self._owner == owner and self._shown end
function GT:NumLines() return #self._lines end
function MOCK.TooltipText()
	return table.concat(GameTooltip._lines or {}, "\n")
end

-- Widget internals --------------------------------------------------------------------------------------------------------
Widget.POINTS = {
	TOPLEFT = { 0, 1 }, TOP = { 0.5, 1 }, TOPRIGHT = { 1, 1 }, LEFT = { 0, 0.5 }, CENTER = { 0.5, 0.5 },
	RIGHT = { 1, 0.5 }, BOTTOMLEFT = { 0, 0 }, BOTTOM = { 0.5, 0 }, BOTTOMRIGHT = { 1, 0 },
}

local FRAME_KINDS = {
	Frame = true, Button = true, CheckButton = true, StatusBar = true, Slider = true, GameTooltip = true,
}

function Widget.NewRegion(kind, parent, name, layer, sublevel)
	local r = setmetatable({ _kind = kind, _name = name, _parent = parent, _points = {}, _shown = true, _alpha = 1,
		_layer = layer, _sublevel = sublevel or 0 }, mt)
	table.insert(parent._regions, r)
	if name then rawset(_G, (name:gsub("%$parent", parent._name or "")), r) end
	return r
end

function Widget.NewFrame(kind, name, parent)
	assert(FRAME_KINDS[kind], "CreateFrame: unknown frame type " .. tostring(kind))
	local f = setmetatable({ _kind = kind, _name = name, _parent = parent, _points = {}, _shown = true, _alpha = 1,
		_scale = 1, _scripts = {}, _hooks = {}, _events = {}, _children = {}, _regions = {}, _isFrame = true,
		_strata = parent and parent._strata or "MEDIUM", _level = parent and (parent._level + 1) or 0, _mouse = false }, mt)
	if parent then table.insert(parent._children, f) end
	if name then rawset(_G, name, f) end
	table.insert(MOCK.frames, f)
	return f
end

function Widget.Fire(frame, script, ...)
	local fn = frame._scripts and frame._scripts[script]
	if fn then fn(frame, ...) end
	for _, hook in ipairs(frame._hooks and frame._hooks[script] or {}) do hook(frame, ...) end
end

function Widget.Visible(obj)
	while obj do
		if not obj._shown then return false end
		obj = obj._parent
	end
	return true
end

local function Notify(frame, visible)
	if not frame._isFrame then return end
	Widget.Fire(frame, visible and "OnShow" or "OnHide")
	for _, child in ipairs(frame._children) do
		if child._parent == frame and child._shown then Notify(child, visible) end
	end
end

function Widget.SetShown(obj, shown)
	local before = Widget.Visible(obj)
	obj._shown = shown
	local after = Widget.Visible(obj)
	if before ~= after then Notify(obj, after) end
end

function Widget.Scale(obj)
	local s = 1
	while obj do
		if obj._scale then s = s * obj._scale end
		obj = obj._parent
	end
	return s
end

-- Resolves anchors into a screen rectangle { l, b, w, h } (bottom-left origin, screen pixels).
function Widget.Rect(obj, depth)
	depth = (depth or 0) + 1
	assert(depth < 80, "anchor loop")
	if obj == UIParent then
		return { l = 0, b = 0, w = MOCK.screen.width, h = MOCK.screen.height }
	end
	local fillOf = rawget(obj, "_fillOf")
	if fillOf then
		-- A status bar's fill is as wide as the bar times the value's share of the range.
		local br = Widget.Rect(fillOf, depth)
		if not br then return nil end
		local lo, hi = fillOf:GetMinMaxValues()
		local frac = hi > lo and math.max(0, math.min(1, (fillOf:GetValue() - lo) / (hi - lo))) or 0
		return { l = br.l, b = br.b, w = br.w * frac, h = br.h }
	end
	local thumbOf = rawget(obj, "_thumbOf")
	if thumbOf then
		-- A slider's thumb sits where the value is.
		local sr = Widget.Rect(thumbOf, depth)
		if not sr then return nil end
		local lo, hi = thumbOf:GetMinMaxValues()
		local frac = hi > lo and (thumbOf:GetValue() - lo) / (hi - lo) or 0
		local s = Widget.Scale(obj)
		local w, h = (obj._w or 32) * s, (obj._h or 32) * s
		return { l = sr.l + sr.w * frac - w / 2, b = sr.b + sr.h / 2 - h / 2, w = w, h = h }
	end
	if #obj._points == 0 then return nil end
	local scale = Widget.Scale(obj)
	local h, v = {}, {}
	for _, p in ipairs(obj._points) do
		local point, rel, relPoint, x, y = p[1], p[2], p[3], p[4], p[5]
		local rr = rel and Widget.Rect(rel, depth)
		if not rr then return nil end
		local fr = Widget.POINTS[relPoint]
		local px = rr.l + rr.w * fr[1] + x * scale
		local py = rr.b + rr.h * fr[2] + y * scale
		local own = Widget.POINTS[point]
		h[own[1]] = px
		v[own[2]] = py
	end
	local w = (obj._w and obj._w > 0) and obj._w * scale or nil
	local ht = (obj._h and obj._h > 0) and obj._h * scale or nil
	if obj._kind == "FontString" then
		-- Like the game: a font string without a set size is as big as its text, wrapped to its width when it has one.
		local boxWidth = w or ((h[0] and h[1]) and (h[1] - h[0])) or nil
		local textWidth = TextWidth(obj) * scale
		w = w or textWidth
		if not ht then
			local lines = 1
			if boxWidth and boxWidth > 0 and obj._wrap ~= false then
				lines = math.max(1, math.ceil(textWidth / boxWidth - 1e-9))
			end
			if obj._maxLines and obj._maxLines > 0 then
				lines = math.min(lines, obj._maxLines)
			end
			ht = lines * FontHeight(obj._font) * scale
		end
	end
	local l
	if h[0] and h[1] then l, w = h[0], h[1] - h[0]
	elseif w and h[0] then l = h[0]
	elseif w and h[1] then l = h[1] - w
	elseif w and h[0.5] then l = h[0.5] - w / 2
	else return nil end
	local b
	if v[0] and v[1] then b, ht = v[0], v[1] - v[0]
	elseif ht and v[0] then b = v[0]
	elseif ht and v[1] then b = v[1] - ht
	elseif ht and v[0.5] then b = v[0.5] - ht / 2
	else return nil end
	return { l = l, b = b, w = w, h = ht }
end

MOCK.Widget = Widget
MOCK.Methods = Methods
MOCK.Templates = {}
MOCK.listeners = {}
MOCK.templatesUsed = {}

function CreateFrame(kind, name, parent, templates)
	local f = Widget.NewFrame(kind, name, parent)
	if templates then
		for template in tostring(templates):gmatch("[^,%s]+") do
			local apply = MOCK.Templates[template]
			assert(apply, "CreateFrame: unknown template " .. template)
			MOCK.templatesUsed[template] = true
			MOCK.inTemplate = true
			apply(f)
			MOCK.inTemplate = false
		end
	end
	return f
end
