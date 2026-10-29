-- Core.lua: Level Time Tracker's namespace, events, internal messages and small helpers.
local ADDON, ns = ...
LevelTimeTracker = ns

ns.name = ADDON
ns.title = "Level Time Tracker"

local function Metadata(field)
	local get = C_AddOns and C_AddOns.GetAddOnMetadata
	if get then
		local ok, value = pcall(get, ADDON, field)
		if ok and type(value) == "string" and value ~= "" then
			return value
		end
	end
end
ns.version = Metadata("Version") or "2.0.0"

ns.L = setmetatable({}, { __index = function(_, k) return k end })
local L = ns.L

local U = {}
ns.U = U

local floor, max, min, abs, format = math.floor, math.max, math.min, math.abs, string.format

ns.COLOR = {
	gold = "ffd100",
	white = "ffffff",
	grey = "9d9d9d",
	green = "40ff40",
	red = "ff5050",
	orange = "ff9a20",
	blue = "70b8ff",
	purple = "c080ff",
}

function ns.C(hex, text)
	return "|cff" .. hex .. tostring(text) .. "|r"
end

local PREFIX = "|cffffd100" .. ns.title .. ":|r "

function ns.Print(fmt, ...)
	local msg = select("#", ...) > 0 and format(fmt, ...) or tostring(fmt)
	local frame = DEFAULT_CHAT_FRAME
	if frame then
		frame:AddMessage(PREFIX .. msg)
	end
end

-- Seconds since 1970 on the realm's clock (dates of level-ups, "last seen").
function ns.Now()
	return GetServerTime and GetServerTime() or time()
end

local function report(err)
	local handler = geterrorhandler and geterrorhandler()
	if handler then
		handler(err)
	end
end

-- Runs fn; an error goes to the game's error handler (BugSack and friends) instead of stopping the caller.
function ns.SafeCall(fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok then
		report(err)
	end
	return ok, err
end

---------------------------------------------------------------------------
-- Game events: several handlers per event
---------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
ns.eventFrame = eventFrame
local handlers = {}

function ns:RegisterEvent(event, fn)
	local list = handlers[event]
	if not list then
		list = {}
		handlers[event] = list
		eventFrame:RegisterEvent(event)
	end
	for i = 1, #list do
		if list[i] == fn then
			return
		end
	end
	list[#list + 1] = fn
end

function ns:UnregisterEvent(event, fn)
	local list = handlers[event]
	if not list then
		return
	end
	for i = #list, 1, -1 do
		if list[i] == fn then
			table.remove(list, i)
		end
	end
	if #list == 0 then
		handlers[event] = nil
		eventFrame:UnregisterEvent(event)
	end
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
	local list = handlers[event]
	if not list then
		return
	end
	for i = 1, #list do
		ns.SafeCall(list[i], event, ...)
	end
end)

---------------------------------------------------------------------------
-- Internal messages between the parts of the addon
---------------------------------------------------------------------------
local callbacks = {}

function ns:On(message, fn)
	local list = callbacks[message]
	if not list then
		list = {}
		callbacks[message] = list
	end
	list[#list + 1] = fn
end

function ns:Fire(message, ...)
	local list = callbacks[message]
	if not list then
		return
	end
	for i = 1, #list do
		ns.SafeCall(list[i], ...)
	end
end

---------------------------------------------------------------------------
-- Modules: Init runs on ADDON_LOADED (saved variables ready), Enable on PLAYER_LOGIN.
---------------------------------------------------------------------------
ns.modules = {}

function ns:NewModule(name)
	local mod = { name = name }
	ns.modules[#ns.modules + 1] = mod
	ns[name] = mod
	return mod
end

-- Many requests for the same thing in a short time become one call.
local pending = {}
function ns.Debounce(key, delay, fn)
	if pending[key] then
		return
	end
	pending[key] = true
	C_Timer.After(delay, function()
		pending[key] = nil
		ns.SafeCall(fn)
	end)
end

ns:RegisterEvent("ADDON_LOADED", function(_, name)
	if name ~= ADDON then
		return
	end
	ns.Data.Init()
	for _, mod in ipairs(ns.modules) do
		if mod.Init then
			ns.SafeCall(mod.Init, mod)
		end
	end
end)

ns:RegisterEvent("PLAYER_LOGIN", function()
	ns.loggedIn = true
	for _, mod in ipairs(ns.modules) do
		if mod.Enable then
			ns.SafeCall(mod.Enable, mod)
		end
	end
end)

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
function U.Clamp(v, lo, hi)
	return max(lo, min(hi, v))
end

-- Midnight can hand addons "secret" values in restricted places; those are treated as unknown.
function U.Plain(v)
	if issecretvalue and issecretvalue(v) then
		return nil
	end
	return v
end

function U.Number(n)
	n = floor((n or 0) + 0.5)
	if BreakUpLargeNumbers then
		return BreakUpLargeNumbers(n)
	end
	local s = tostring(abs(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
	return (n < 0 and "-" or "") .. out
end

-- 950, 45.2k, 1.25M
function U.Short(n)
	n = n or 0
	if n >= 1000000 then
		return format("%.2fM", n / 1000000)
	elseif n >= 10000 then
		return format("%.1fk", n / 1000)
	end
	return U.Number(n)
end

local function parts(seconds)
	seconds = floor(max(0, seconds or 0) + 0.5)
	return floor(seconds / 86400), floor(seconds % 86400 / 3600), floor(seconds % 3600 / 60), seconds % 60
end

-- The two biggest units: 45s, 12m 05s, 2h 05m, 3d 4h.
function U.Duration(seconds)
	local d, h, m, s = parts(seconds)
	if d > 0 then
		return format(L["%dd %dh"], d, h)
	elseif h > 0 then
		return format(L["%dh %02dm"], h, m)
	elseif m > 0 then
		return format(L["%dm %02ds"], m, s)
	end
	return format(L["%ds"], s)
end

-- Down to the second (chat and tooltips): 2h 05m 09s, 3d 4h 12m.
function U.DurationLong(seconds)
	local d, h, m, s = parts(seconds)
	if d > 0 then
		return format(L["%dd %dh %02dm"], d, h, m)
	elseif h > 0 then
		return format(L["%dh %02dm %02ds"], h, m, s)
	elseif m > 0 then
		return format(L["%dm %02ds"], m, s)
	end
	return format(L["%ds"], s)
end

function U.Date(ts)
	return ts and date(L["%d %b %Y"], ts) or ""
end

function U.DateTime(ts)
	return ts and date(L["%d %b %Y, %H:%M"], ts) or ""
end

local function dayNumber(ts)
	local t = date("*t", ts)
	return floor(time({ year = t.year, month = t.month, day = t.day, hour = 12 }) / 86400)
end

-- Today, Yesterday, 4 days ago, 12 Oct 2026
function U.Ago(ts)
	if not ts then
		return L["Never"]
	end
	local days = dayNumber(ns.Now()) - dayNumber(ts)
	if days <= 0 then
		return L["Today"]
	elseif days == 1 then
		return L["Yesterday"]
	elseif days < 7 then
		return format(L["%d days ago"], days)
	end
	return U.Date(ts)
end

function U.ClassRGB(classFile)
	local c = classFile and ((C_ClassColor and C_ClassColor.GetClassColor and C_ClassColor.GetClassColor(classFile))
		or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]))
	if c then
		return c.r, c.g, c.b
	end
	return 1, 0.82, 0
end

function U.ClassHex(classFile)
	local r, g, b = U.ClassRGB(classFile)
	return format("%02x%02x%02x", floor(r * 255 + 0.5), floor(g * 255 + 0.5), floor(b * 255 + 0.5))
end

local CLASS_CIRCLES = "Interface\\TargetingFrame\\UI-Classes-Circles"

-- The class's round icon as a text escape (lists and tooltips).
function U.ClassIcon(classFile, size)
	local c = classFile and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classFile]
	if not c then
		return ""
	end
	size = size or 14
	return format("|T%s:%d:%d:0:0:256:256:%d:%d:%d:%d|t", CLASS_CIRCLES, size, size, c[1] * 256, c[2] * 256, c[3] * 256, c[4] * 256)
end

local texCache = {}
function U.TexExists(path)
	if texCache[path] == nil then
		local ok = true
		if GetFileIDFromPath then
			local success, id = pcall(GetFileIDFromPath, path)
			ok = success and id ~= nil and id ~= 0
		end
		texCache[path] = ok
	end
	return texCache[path]
end

function U.AtlasExists(name)
	if not (C_Texture and C_Texture.GetAtlasInfo) then
		return false
	end
	local ok, info = pcall(C_Texture.GetAtlasInfo, name)
	return ok and info ~= nil
end

function U.PlaySound(kitName, fallbackId)
	if not PlaySound then
		return
	end
	local id = (SOUNDKIT and SOUNDKIT[kitName]) or fallbackId
	if id then
		pcall(PlaySound, id)
	end
end
