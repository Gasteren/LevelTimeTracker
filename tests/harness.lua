-- harness.lua: the mock game, Level Time Tracker loaded in .toc order, and a tiny test framework.
-- Globals provided by the runner: ROOT (repo root, forward slashes), MOCK_FLAVOR, KNOWN_EVENTS (or nil).
MOCK = {}
if KNOWN_EVENTS then
	MOCK.KNOWN_EVENTS = {}
	for _, event in ipairs(KNOWN_EVENTS) do MOCK.KNOWN_EVENTS[event] = true end
end

dofile(ROOT .. "/tests/wow_mock.lua")

ADDON_NAME = "LevelTimeTracker"

function TocFiles()
	local files = {}
	local toc = assert(io.open(ROOT .. "/LevelTimeTracker.toc", "r"))
	for line in toc:lines() do
		local file = line:match("^%s*([%w_]+%.lua)%s*$")
		if file then
			files[#files + 1] = file
		end
	end
	toc:close()
	return files
end

-- Starts the game: saved variables, the addon's files, ADDON_LOADED, PLAYER_LOGIN, PLAYER_ENTERING_WORLD.
-- opts: { db = saved variables, player = { ... }, reload = true (a /reload), wait = seconds to let pass (1),
--         afterLogin = function run between PLAYER_LOGIN and PLAYER_ENTERING_WORLD (another addon's turn) }
function Boot(opts)
	opts = opts or {}
	for k, v in pairs(opts.player or {}) do
		MOCK.player[k] = v
	end
	if opts.player and opts.player.level and not opts.player.xpMax then
		MOCK.player.xpMax = MOCK.player.level >= MOCK.maxLevel and 0 or MOCK.XPFor(MOCK.player.level)
	end
	rawset(_G, "LevelTimeTrackerDB", opts.db)
	local ns = {}
	rawset(_G, "NS", ns)
	for _, file in ipairs(TocFiles()) do
		local chunk = assert(loadfile(ROOT .. "/" .. file))
		chunk(ADDON_NAME, ns)
	end
	MOCK.Fire("ADDON_LOADED", "SomeOtherAddon")
	MOCK.Fire("ADDON_LOADED", ADDON_NAME)
	MOCK.Fire("PLAYER_LOGIN")
	if opts.afterLogin then
		opts.afterLogin()
	end
	MOCK.Fire("PLAYER_ENTERING_WORLD", not opts.reload, opts.reload and true or false)
	MOCK.Advance(opts.wait or 1)
	return ns
end

-- The game saves and the player logs out (PLAYER_LOGOUT), as before a /reload; returns the saved variables.
function Logout()
	MOCK.Fire("PLAYER_LOGOUT")
	return rawget(_G, "LevelTimeTrackerDB")
end

-- Tiny test framework ---------------------------------------------------------------------------------------------------
local tests = {}
-- T(name, fn) runs in both games; T(name, fn, "midnight") or T(name, fn, "forever") in that one only.
function T(name, fn, only)
	tests[#tests + 1] = { name = name, fn = fn, only = only }
end
function Eq(actual, expected, label)
	if actual ~= expected then
		error(("%s\n      expected: %s\n      actual:   %s"):format(label or "values differ", tostring(expected), tostring(actual)), 2)
	end
end
function Near(actual, expected, tolerance, label)
	if type(actual) ~= "number" or math.abs(actual - expected) > (tolerance or 1) then
		error(("%s\n      expected: %s (+-%s)\n      actual:   %s"):format(label or "values differ", tostring(expected), tostring(tolerance or 1), tostring(actual)), 2)
	end
end
function Ok(value, label)
	if not value then
		error(label or "expected a true value", 2)
	end
end
function Has(text, needle, label)
	if type(text) ~= "string" or not text:find(needle, 1, true) then
		error(("%s\n      missing: %s\n      in:      %s"):format(label or "substring missing", needle, tostring(text)), 2)
	end
end
function HasNot(text, needle, label)
	if type(text) == "string" and text:find(needle, 1, true) then
		error(("%s\n      unexpected: %s\n      in:         %s"):format(label or "unexpected substring", needle, text), 2)
	end
end
function Fire(frame, script, ...)
	MOCK.Widget.Fire(frame, script, ...)
end
-- Everything printed in chat since the last call, as one string.
local chatSeen = 0
function Chat()
	local lines = {}
	for i = chatSeen + 1, #MOCK.chat do
		lines[#lines + 1] = MOCK.chat[i]
	end
	chatSeen = #MOCK.chat
	return table.concat(lines, "\n")
end
-- Visible text of a font string (colour codes removed).
function Text(fs)
	return MOCK.Plain(fs:GetText())
end
function Rect(region)
	return MOCK.Widget.Rect(region)
end
-- a lies inside b (with `slack` pixels to spare).
function Inside(a, b, slack)
	local ra, rb = Rect(a), Rect(b)
	if not ra or not rb then return false end
	slack = slack or 0
	return ra.l >= rb.l - slack and ra.b >= rb.b - slack and ra.l + ra.w <= rb.l + rb.w + slack and ra.b + ra.h <= rb.b + rb.h + slack
end

function TestNames()
	local names = {}
	for _, t in ipairs(tests) do
		if not t.only or t.only == MOCK.flavor then
			names[#names + 1] = t.name
		end
	end
	return names
end

-- Runs one test (each test gets a fresh game). Returns ok, message.
function RunOne(name)
	for _, t in ipairs(tests) do
		if t.name == name then
			local ok, err = pcall(t.fn)
			if ok and #MOCK.errors > 0 then
				ok, err = false, "Level Time Tracker raised an error: " .. MOCK.errors[1]
			end
			if ok then
				local missing, stray = {}, {}
				for k in pairs(MOCK.missingGlobals) do missing[#missing + 1] = tostring(k) end
				for k in pairs(MOCK.strayGlobals) do stray[#stray + 1] = tostring(k) end
				table.sort(missing)
				table.sort(stray)
				if #missing > 0 then
					ok, err = false, "read undefined globals: " .. table.concat(missing, ", ")
				elseif #stray > 0 then
					ok, err = false, "wrote globals: " .. table.concat(stray, ", ")
				end
			end
			return ok, err and tostring(err):gsub("[\128-\255]", "?") or nil
		end
	end
	return false, "no such test"
end

-- Names of everything the run touched, for the API check in run_tests.py.
function UsedApi()
	local function list(t)
		local out = {}
		for k in pairs(t) do out[#out + 1] = k end
		table.sort(out)
		return table.concat(out, "\n")
	end
	return list(MOCK.used), list(MOCK.apiRead), list(MOCK.templatesUsed), list(MOCK.texturesUsed), list(MOCK.atlasesUsed)
end

-- From here on, reading a global the game doesn't have (a typo) or writing one the addon doesn't own fails the test.
-- Game API reads are recorded for the API check (run_tests.py).
local ADDON_GLOBALS = {
	LevelTimeTracker = true, LevelTimeTrackerDB = true, SLASH_LEVELTIMETRACKER1 = true, SLASH_LEVELTIMETRACKER2 = true,
	BINDING_HEADER_LEVELTIMETRACKER = true, BINDING_NAME_LEVELTIMETRACKER_TOGGLE = true,
	BINDING_NAME_LEVELTIMETRACKER_MINI = true, LevelTimeTracker_OnAddonCompartmentClick = true,
	LevelTimeTracker_OnAddonCompartmentEnter = true, LevelTimeTracker_OnAddonCompartmentLeave = true,
}
-- Saved variables are nil until the game loads them; the addon may read them first.
local OPTIONAL = { LevelTimeTrackerDB = true }
MOCK.missingGlobals = {}
MOCK.strayGlobals = {}
setmetatable(_G, {
	__index = function(_, key)
		local api = MOCK.api[key]
		if api ~= nil then
			MOCK.apiRead[key] = true
			return api
		end
		if not OPTIONAL[key] then
			MOCK.missingGlobals[key] = true
		end
		return nil
	end,
	__newindex = function(t, key, value)
		if not ADDON_GLOBALS[key] then
			MOCK.strayGlobals[key] = true
		end
		rawset(t, key, value)
	end,
})
