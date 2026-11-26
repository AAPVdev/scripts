local cloneref  = type(cloneref) == "function" and cloneref or function(obj) return obj end
local globalEnv = type(getgenv) == "function" and getgenv() or _G

local Players    = cloneref(game:GetService("Players"))
local RunService = cloneref(game:GetService("RunService"))
local Workspace  = cloneref(game:GetService("Workspace"))

local table_clear    = table.clear
local table_clone    = table.clone
local math_max       = math.max
local math_min       = math.min
local math_floor     = math.floor
local math_ceil      = math.ceil
local math_sqrt      = math.sqrt
local math_clamp     = math.clamp
local task_spawn     = task.spawn
local task_defer     = task.defer
local task_wait      = task.wait
local os_clock       = os.clock
local string_find    = string.find
local string_match   = string.match
local string_lower   = string.lower
local Vector3_new    = Vector3.new
local Color3_fromRGB = Color3.fromRGB

local cachedLocalPlayer = Players.LocalPlayer
local function getLocalPlayer()
	if not cachedLocalPlayer then
		cachedLocalPlayer = Players.LocalPlayer
	end
	return cachedLocalPlayer
end

local limbData = globalEnv.limbExtenderData or {}
globalEnv.limbExtenderData = limbData

limbData.limbBlocked        = limbData.limbBlocked        or setmetatable({}, { __mode = "k" })
limbData.ownWatchCallbacks  = limbData.ownWatchCallbacks  or setmetatable({}, { __mode = "k" })
limbData._spoofReadKeys     = limbData._spoofReadKeys     or {}
limbData._spoofWriteKeys    = limbData._spoofWriteKeys    or {}
limbData._gameScriptSources = limbData._gameScriptSources or {}
limbData.chamsIdCounter     = limbData.chamsIdCounter     or 0
limbData._hooksV2Installed  = limbData._hooksV2Installed  or false

local function terminateExisting()
	if type(limbData.terminate) == "function" then
		pcall(limbData.terminate)
		limbData.terminate = nil
	end
end

local hasLoadstring               = type(loadstring) == "function"
local okHttp, httpGetFn           = pcall(function() return game.HttpGet end)
local hasHttpGet                  = okHttp and type(httpGetFn) == "function"
local okSig, rawGetPropChangedSig = pcall(function() return game.GetPropertyChangedSignal end)
local hasGetPropSig               = okSig and type(rawGetPropChangedSig) == "function"
local hasCheckcaller              = type(checkcaller) == "function"
local hasGetconnections           = type(getconnections) == "function"
local hasNewcclosure              = type(newcclosure) == "function"
local hasHookmetamethod           = type(hookmetamethod) == "function"
local hasGetrawmetatable          = type(getrawmetatable) == "function"
local hasSetreadonly              = type(setreadonly) == "function"

local hasOthHook, othHookFn, othUnhookFn = false, nil, nil
if type(oth) == "table" then
	local okH, hFn = pcall(function() return oth.hook end)
	if okH and type(hFn) == "function" then
		hasOthHook = true
		othHookFn  = hFn
	end
	local okU, uFn = pcall(function() return oth.unhook end)
	if okU and type(uFn) == "function" then
		othUnhookFn = uFn
	end
end

local executorName = string_lower(type(identifyexecutor) == "function" and identifyexecutor() or "")
local wrapC        = hasNewcclosure and newcclosure or function(f) return f end

local getIdentityFn = type(getthreadidentity) == "function" and getthreadidentity
	or (type(syn) == "table" and type(syn.get_thread_identity) == "function" and syn.get_thread_identity)
	or nil
local setIdentityFn = type(setthreadidentity) == "function" and setthreadidentity
	or (type(syn) == "table" and type(syn.set_thread_identity) == "function" and syn.set_thread_identity)
	or nil
local hasThreadIdentity = getIdentityFn ~= nil and setIdentityFn ~= nil
local executorIdentity  = nil
local fastIdentity      = false
if hasThreadIdentity then
	local okId, curId = pcall(getIdentityFn)
	if okId and type(curId) == "number" then
		executorIdentity = curId >= 6 and curId or 8
		if pcall(setIdentityFn, executorIdentity) then
			pcall(setIdentityFn, curId)
			fastIdentity = true
		end
	else
		executorIdentity = 8
	end
end

local function beginElevated()
	if not hasThreadIdentity then return nil end
	if fastIdentity then
		local curId = getIdentityFn()
		if type(curId) == "number" and curId < executorIdentity then
			setIdentityFn(executorIdentity)
			return curId
		end
		return nil
	end
	local okId, curId = pcall(getIdentityFn)
	if okId and type(curId) == "number" and curId < executorIdentity then
		if pcall(setIdentityFn, executorIdentity) then
			return curId
		end
	end
	return nil
end

local function endElevated(prevIdentity)
	if prevIdentity ~= nil then
		if fastIdentity then
			setIdentityFn(prevIdentity)
		else
			pcall(setIdentityFn, prevIdentity)
		end
	end
end

local BATCH_SIZE               = 64
local DYNAMIC_SLICE_SIZE       = 16
local SIZE_CHANGE_THRESHOLD_SQ = 0.25
local NON_HRP_ROOT_PRIORITY    = -127
local DIST_MAX_PAD             = 5
local DIST_MIN_FACTOR          = 0.1
local MIN_LIMB_AXIS            = 0.05
local LATE_SWEEP_DELAY         = 1
local ESP_RETRY_LIMIT          = 30
local ESP_RETRY_INTERVAL       = 0.1

local READ_SPECIAL_CHANGED  = 1
local READ_SPECIAL_PROP_SIG = 2
local READ_SPECIAL_COM      = 3

local ROOT_PART_NAMES = {
	"HumanoidRootPart",
	"Root",
	"UpperTorso",
	"Torso",
	"Head",
}

local LIMB_PROPS = {
	Size                 = { writable = true,  staticWatch = false, valType = "Vector3" },
	Transparency         = { writable = true,  staticWatch = true,  valType = "number"  },
	CanCollide           = { writable = true,  staticWatch = true,  valType = "boolean" },
	Massless             = { writable = true,  staticWatch = true,  valType = "boolean" },
	RootPriority         = { writable = true,  staticWatch = true,  valType = "int8"    },
	Mass                 = { writable = false, staticWatch = false },
	AssemblyMass         = { writable = false, staticWatch = false },
	CenterOfMass         = { writable = false, staticWatch = false },
	AssemblyCenterOfMass = { writable = false, staticWatch = false },
}

local PROP_ALIASES = {
	size                 = "Size",
	transparency         = "Transparency",
	canCollide           = "CanCollide",
	massless             = "Massless",
	rootPriority         = "RootPriority",
	mass                 = "Mass",
	assemblyMass         = "AssemblyMass",
	centerOfMass         = "CenterOfMass",
	assemblyCenterOfMass = "AssemblyCenterOfMass",
}

local CLAMPED_UNIT_KEYS = {
	LIMB_TRANSPARENCY          = true,
	CHAMS_FILL_TRANSPARENCY    = true,
	CHAMS_OUTLINE_TRANSPARENCY = true,
}

local ALL_BLOCKED_PROPS  = {}
local STATIC_WATCH_PROPS = {}
local spoofReadKeys      = limbData._spoofReadKeys
local spoofWriteKeys     = limbData._spoofWriteKeys

table_clear(spoofReadKeys)
table_clear(spoofWriteKeys)

for prop, info in pairs(LIMB_PROPS) do
	local origField = "Original" .. prop
	ALL_BLOCKED_PROPS[#ALL_BLOCKED_PROPS + 1] = prop
	spoofReadKeys[prop] = origField
	if info.writable then
		spoofWriteKeys[prop] = origField
	end
	if info.staticWatch then
		STATIC_WATCH_PROPS[#STATIC_WATCH_PROPS + 1] = { prop, "Target" .. prop }
	end
end

for alias, canon in pairs(PROP_ALIASES) do
	spoofReadKeys[alias] = spoofReadKeys[canon]
	if spoofWriteKeys[canon] then
		spoofWriteKeys[alias] = spoofWriteKeys[canon]
	end
end

spoofReadKeys.Changed                  = READ_SPECIAL_CHANGED
spoofReadKeys.changed                  = READ_SPECIAL_CHANGED
spoofReadKeys.GetPropertyChangedSignal = READ_SPECIAL_PROP_SIG
spoofReadKeys.getPropertyChangedSignal = READ_SPECIAL_PROP_SIG

if limbData._hooksV2DynamicCOM then
	spoofReadKeys.AssemblyCenterOfMass = READ_SPECIAL_COM
	spoofReadKeys.assemblyCenterOfMass = READ_SPECIAL_COM
end

local function normalizeSpoofKey(key)
	if type(key) == "string" and string_find(key, "\0", 1, true) then
		return string_match(key, "^([^\0]+)") or key
	end
	return key
end

local function isValidPropValue(canonProp, value)
	local info = LIMB_PROPS[canonProp]
	if not info then return false end
	local expected = info.valType
	if expected == "Vector3" then
		return typeof(value) == "Vector3"
	elseif expected == "boolean" then
		return type(value) == "boolean"
	elseif expected == "number" then
		return type(value) == "number" and value == value
	elseif expected == "int8" then
		return type(value) == "number" and value == value and value >= -127 and value <= 127
	end
	return false
end

local function sanitizePropValue(canonProp, value)
	if canonProp == "Size" then
		return Vector3_new(
			math_max(0.001, value.X),
			math_max(0.001, value.Y),
			math_max(0.001, value.Z)
		)
	elseif canonProp == "RootPriority" then
		return value >= 0 and math_floor(value) or math_ceil(value)
	end
	return value
end

local REMOTE_URLS = {
	ESP = {
		"https://raw.githubusercontent.com/AAPVdev/scripts/refs/heads/main/esp/SIXSEVENESP.lua",
		"https://api.rubis.app/v2/scrap/qghKmrRhRUfwDnee/raw",
	},
	CHAMS = {
		"https://raw.githubusercontent.com/AAPVdev/scripts/refs/heads/main/esp/chams.lua",
	},
	manager = {
		"https://raw.githubusercontent.com/AAPVdev/scripts/refs/heads/main/manager/manager.lua",
		"https://api.rubis.app/v2/scrap/HzetRxF1iap9sgRF/raw",
	},
}

local GAME_SCRIPT_URLS = {
	[1054526971] = {
		"https://raw.githubusercontent.com/AAPVdev/scripts/refs/heads/main/games/brm5.lua",
	},
}

local SCHEMA = {
	TARGET_LIMB                = { default = "Head",  kind = "manager",  manager = "TARGET_LIMB" },
	LIMB_SIZE                  = { default = 15,      kind = "cosmetic" },
	LIMB_TRANSPARENCY          = { default = 0.7,     kind = "cosmetic" },
	LIMB_CAN_COLLIDE           = { default = false,   kind = "cosmetic" },
	FORCEFIELD_CHECK           = { default = false,   kind = "manager",  manager = "FORCEFIELD_CHECK" },
	ALT_RESET_LIMB_ON_DEATH    = { default = true,    kind = "manager",  manager = "STOP_TRACKING_ON_DEATH" },
	PLAYER_ENABLED             = { default = true,    kind = "manager",  manager = "PLAYER_ENABLED" },
	NPC_ENABLED                = { default = false,   kind = "manager",  manager = "NPC_ENABLED" },
	NPC_FILTER                 = { default = nil,     kind = "manager",  manager = "NPC_FILTER" },
	NPC_DIRECTORIES            = { default = {},      kind = "manager",  manager = "NPC_DIRECTORIES" },
	CUSTOM_CHARACTER_SYSTEM    = { default = false,   kind = "manager",  manager = "CUSTOM_CHARACTER_SYSTEM" },
	GET_PLAYER_FROM_CHARACTER  = { default = nil,     kind = "manager",  manager = "GET_PLAYER_FROM_CHARACTER" },

	DYNAMIC_SCALE_ENABLED      = { default = true,    kind = "dynamic" },
	DYNAMIC_SCALE_RANGE_MULT   = { default = 1.5,     kind = "dynamic" },
	DYNAMIC_SCALE_UPDATE_RATE  = { default = 8,       kind = "dynamic" },

	TEAM_MODE                  = { default = "none",  kind = "manager",  manager = "TEAM_MODE" },
	TEAM_WHITELIST             = { default = nil,     kind = "manager",  manager = "TEAM_WHITELIST" },
	TEAM_BLACKLIST             = { default = nil,     kind = "manager",  manager = "TEAM_BLACKLIST" },
	TEAM_CUSTOM_CHECK          = { default = nil,     kind = "manager",  manager = "TEAM_CUSTOM_CHECK" },
	PLAYER_WHITELIST           = { default = nil,     kind = "manager",  manager = "PLAYER_WHITELIST" },
	PLAYER_BLACKLIST           = { default = nil,     kind = "manager",  manager = "PLAYER_BLACKLIST" },
	NAME_PATTERN               = { default = nil,     kind = "manager",  manager = "NAME_PATTERN" },
	DISPLAY_NAME_PATTERN       = { default = nil,     kind = "manager",  manager = "DISPLAY_NAME_PATTERN" },
	PLAYER_FILTER              = { default = nil,     kind = "manager",  manager = "PLAYER_FILTER" },

	ESP                        = { default = true,                            kind = "esp" },
	ESP_COLOR                  = { default = Color3_fromRGB(255, 50, 50),     kind = "esp" },
	ESP_BOX3D_COLOR            = { default = Color3_fromRGB(255, 50, 50),     kind = "esp" },
	ESP_HEALTH_COLOR           = { default = Color3_fromRGB(9, 255, 0),       kind = "esp" },
	ESP_EMPTY_COLOR            = { default = Color3_fromRGB(255, 0, 0),       kind = "esp" },
	ESP_SKELETON_COLOR         = { default = Color3_fromRGB(255, 157, 0),     kind = "esp" },
	ESP_TEXT_COLOR             = { default = Color3_fromRGB(255, 255, 255),   kind = "esp" },
	ESP_TEXT_SIZE              = { default = 16,                              kind = "esp" },
	ESP_OFFSCREEN_POINT        = { default = true,                            kind = "esp" },
	ESP_FILTER_LOCAL           = { default = true,                            kind = "esp" },
	ESP_MAX_DISTANCE           = { default = 500,                             kind = "esp" },
	ESP_NEAR_DISTANCE          = { default = 100,                             kind = "esp" },
	ESP_MEDIUM_DISTANCE        = { default = 250,                             kind = "esp" },
	ESP_OCCLUSION              = { default = false,                           kind = "esp" },
	ESP_OCCLUSION_FREQUENCY    = { default = 4,                               kind = "esp" },
	ESP_BOX                    = { default = true,                            kind = "esp" },
	ESP_BOX3D                  = { default = false,                           kind = "esp" },
	ESP_TRACER                 = { default = true,                            kind = "esp" },
	ESP_SKELETON               = { default = true,                            kind = "esp" },
	ESP_HEALTH                 = { default = true,                            kind = "esp" },
	ESP_LABEL                  = { default = true,                            kind = "esp" },
	ESP_DISTANCE               = { default = false,                           kind = "esp" },
	ESP_NEAR_FLAGS             = { default = { Box = true, Tracer = true, Skeleton = true,  Health = true,  Label = true,  Box3D = false }, kind = "esp", merge = true },
	ESP_MEDIUM_FLAGS           = { default = { Box = true, Tracer = true, Skeleton = false, Health = true,  Label = true,  Box3D = false }, kind = "esp", merge = true },
	ESP_FAR_FLAGS              = { default = { Box = true, Tracer = true, Skeleton = false, Health = false, Label = false, Box3D = false }, kind = "esp", merge = true },
	ESP_TEXT_RESOLVER          = { default = nil,                             kind = "esp" },
	ESP_CAN_DRAW               = { default = nil,                             kind = "esp" },
	ESP_TRACER_ORIGIN          = { default = nil,                             kind = "esp" },

	CHAMS                      = { default = false,                           kind = "chams" },
	CHAMS_FILL_COLOR           = { default = Color3_fromRGB(255, 255, 0),     kind = "chams" },
	CHAMS_OUTLINE_COLOR        = { default = Color3_fromRGB(255, 255, 255),   kind = "chams" },
	CHAMS_FILL_TRANSPARENCY    = { default = 0.5,                             kind = "chams" },
	CHAMS_OUTLINE_TRANSPARENCY = { default = 0.5,                             kind = "chams" },
	CHAMS_OCCLUSION            = { default = false,                           kind = "chams" },
}

local function cloneDeep(src, seen)
	if type(src) ~= "table" then return src end
	if seen and seen[src] then return seen[src] end
	seen = seen or {}
	local copy = table_clone(src)
	seen[src] = copy
	for k, v in pairs(copy) do
		if type(v) == "table" then
			copy[k] = cloneDeep(v, seen)
		end
	end
	return copy
end

local function isEmptyList(t)
	return t == nil or (type(t) == "table" and next(t) == nil)
end

local function tablesShallowEqual(a, b)
	if a == b then return true end
	if isEmptyList(a) and isEmptyList(b) then return true end
	if type(a) ~= "table" or type(b) ~= "table" then return false end
	local na = #a
	if na ~= #b then return false end
	for i = 1, na do
		if a[i] ~= b[i] then return false end
	end
	for k, v in pairs(a) do
		if b[k] ~= v then return false end
	end
	for k in pairs(b) do
		if a[k] == nil then return false end
	end
	return true
end

local function mergeSettings(user)
	local s = {}
	for key, meta in pairs(SCHEMA) do
		local def = meta.default
		if def ~= nil then
			s[key] = type(def) == "table" and cloneDeep(def) or def
		end
	end
	if type(user) ~= "table" then return s end
	for key, val in pairs(user) do
		local meta = SCHEMA[key]
		if meta then
			if meta.merge then
				if type(val) == "table" and type(s[key]) == "table" then
					for fk, fv in pairs(val) do
						s[key][fk] = fv
					end
				end
			elseif CLAMPED_UNIT_KEYS[key] and type(val) == "number" then
				s[key] = math_clamp(val, 0, 1)
			else
				s[key] = type(val) == "table" and cloneDeep(val) or val
			end
		end
	end
	return s
end

local function applyToggles(s, flags)
	if type(flags) ~= "table" then
		return { Box = false, Box3D = false, Tracer = false, Skeleton = false, Health = false, Label = false }
	end
	return {
		Box      = s.ESP_BOX      and flags.Box,
		Box3D    = s.ESP_BOX3D    and flags.Box3D,
		Tracer   = s.ESP_TRACER   and flags.Tracer,
		Skeleton = s.ESP_SKELETON and flags.Skeleton,
		Health   = s.ESP_HEALTH   and flags.Health,
		Label    = s.ESP_LABEL    and flags.Label,
	}
end

local function resolveSizeVector(sizeVal)
	if typeof(sizeVal) == "Vector3" then
		return Vector3_new(
			math_max(MIN_LIMB_AXIS, sizeVal.X),
			math_max(MIN_LIMB_AXIS, sizeVal.Y),
			math_max(MIN_LIMB_AXIS, sizeVal.Z)
		)
	end
	local n = math_max(MIN_LIMB_AXIS, tonumber(sizeVal) or 15)
	return Vector3_new(n, n, n)
end

local function resolveCharacterRoot(char)
	if not char or not char.Parent then return nil end
	local primary = char.PrimaryPart
	if primary and primary.Parent ~= nil and primary:IsA("BasePart") then
		return primary
	end
	for i = 1, #ROOT_PART_NAMES do
		local part = char:FindFirstChild(ROOT_PART_NAMES[i])
		if part and part:IsA("BasePart") then
			return part
		end
	end
	return char:FindFirstChildWhichIsA("BasePart", true)
end

local function resolveUpdateInterval(rate)
	local r = tonumber(rate)
	return (r and r > 0) and (1 / r) or 0.125
end

local function fetchSourceFromURLs(urlList)
	if not (hasLoadstring and hasHttpGet) then return nil end
	for i = 1, #urlList do
		local okFetch, source = pcall(httpGetFn, game, urlList[i])
		if okFetch and type(source) == "string" and source ~= "" then
			local okCompile, fn = pcall(loadstring, source)
			if okCompile and type(fn) == "function" then
				return source
			end
		end
	end
	return nil
end

local function tryLoadFromURLs(urlList, requireResult, ...)
	if not (hasLoadstring and hasHttpGet) then return false, nil end
	for i = 1, #urlList do
		local okFetch, source = pcall(httpGetFn, game, urlList[i])
		if okFetch and type(source) == "string" and source ~= "" then
			local okCompile, fn = pcall(loadstring, source)
			if okCompile and type(fn) == "function" then
				local okRun, result = pcall(fn, ...)
				if okRun and (not requireResult or result) then
					return true, result
				end
			end
		end
	end
	return false, nil
end

local loadingWaiters    = {}
local gameScriptSources = limbData._gameScriptSources

local function runSingleFlight(waitKey, workFn)
	local waiters = loadingWaiters[waitKey]
	if waiters then
		local co = coroutine.running()
		if co then
			waiters[#waiters + 1] = co
			coroutine.yield()
		end
		return
	end

	loadingWaiters[waitKey] = {}
	pcall(workFn)

	local queued = loadingWaiters[waitKey]
	loadingWaiters[waitKey] = nil
	if queued then
		for i = 1, #queued do
			task_spawn(queued[i])
		end
	end
end

local function ensureRemoteModule(cacheKey, skipSet)
	if limbData[cacheKey] then return limbData[cacheKey] end
	if skipSet and skipSet[cacheKey] then return nil end

	local urls = REMOTE_URLS[cacheKey]
	if not urls then return nil end

	runSingleFlight("mod:" .. cacheKey, function()
		if not limbData[cacheKey] then
			local ok, mod = tryLoadFromURLs(urls, true)
			if ok and mod then
				limbData[cacheKey] = mod
			end
		end
	end)

	return limbData[cacheKey]
end

local function ensureGameScriptSource(gameId, skipSet)
	if gameScriptSources[gameId] then return gameScriptSources[gameId] end
	if skipSet and skipSet[gameId] then return nil end

	local urls = GAME_SCRIPT_URLS[gameId]
	if not urls then return nil end

	runSingleFlight("game:" .. tostring(gameId), function()
		if not gameScriptSources[gameId] then
			local source = fetchSourceFromURLs(urls)
			if source then
				gameScriptSources[gameId] = source
			end
		end
	end)

	return gameScriptSources[gameId]
end

local function prefetchRemoteModules(s)
	local failedSet = {}
	local caller    = coroutine.running()
	local pending   = 0
	local yielded   = false

	local function spawnTask(fn)
		pending = pending + 1
		task_spawn(function()
			local pId = beginElevated()
			pcall(fn)
			endElevated(pId)
			pending = pending - 1
			if pending == 0 and yielded and caller then
				task_spawn(caller)
			end
		end)
	end

	if not limbData.manager then
		spawnTask(function()
			if not ensureRemoteModule("manager") then
				failedSet.manager = true
			end
		end)
	end
	if s.ESP and not limbData.ESP then
		spawnTask(function()
			if not ensureRemoteModule("ESP") then
				failedSet.ESP = true
			end
		end)
	end
	if s.CHAMS and not limbData.CHAMS then
		spawnTask(function()
			if not ensureRemoteModule("CHAMS") then
				failedSet.CHAMS = true
			end
		end)
	end

	local gameId = game.GameId
	if GAME_SCRIPT_URLS[gameId] and not gameScriptSources[gameId] then
		spawnTask(function()
			if not ensureGameScriptSource(gameId) then
				failedSet[gameId] = true
			end
		end)
	end

	if pending > 0 and caller then
		yielded = true
		coroutine.yield()
	end

	return failedSet
end

local function nextChamsSourceKey()
	limbData.chamsIdCounter = limbData.chamsIdCounter + 1
	return "LimbExtender_" .. limbData.chamsIdCounter
end

local function espTrackSafe(esp, char)
	local ok, tracked = pcall(esp.Track, esp, char)
	return ok and tracked == true
end

local limbBlocked       = limbData.limbBlocked
local ownWatchCallbacks = limbData.ownWatchCallbacks

local function getOrCreateSignalPair(data, key)
	local custom = data._customSignals
	local real   = data._realSignals
	if not custom then
		custom = {}
		real   = {}
		data._customSignals = custom
		data._realSignals   = real
	end
	local ev = custom[key]
	if not ev then
		local be    = Instance.new("BindableEvent")
		real[key]   = be
		ev          = be.Event
		custom[key] = ev
	end
	return ev, real[key]
end

local function getRealPropSig(entry, limb, prop)
	local propSigs = entry._realPropSigs
	if not propSigs then
		propSigs = {}
		entry._realPropSigs = propSigs
	end
	local sig = propSigs[prop]
	if not sig and hasGetPropSig then
		local ok, s = pcall(rawGetPropChangedSig, limb, prop)
		if ok and s then
			sig = s
			propSigs[prop] = s
		end
	end
	return sig
end

local function migrateSignalConnections(realSignal, signalKey, data)
	if not realSignal then return end
	local conns = getconnections(realSignal)
	if #conns == 0 then return end

	local migratedFns     = data._migratedFns
	local disabledConns   = data._disabledConns
	local disabledConnSet = data._disabledConnSet

	for i = 1, #conns do
		local conn = conns[i]
		if conn.Enabled then
			local fn = conn.Function
			if fn and not ownWatchCallbacks[fn] then
				if not migratedFns then
					migratedFns = setmetatable({}, { __mode = "k" })
					data._migratedFns = migratedFns
				end
				if not migratedFns[fn] then
					migratedFns[fn] = true
					local customEvent = getOrCreateSignalPair(data, signalKey)
					pcall(customEvent.Connect, customEvent, fn)
				end
				conn:Disable()
				if not disabledConnSet then
					disabledConnSet = setmetatable({}, { __mode = "k" })
					data._disabledConnSet = disabledConnSet
				end
				if not disabledConnSet[conn] then
					disabledConnSet[conn] = true
					if not disabledConns then
						disabledConns = {}
						data._disabledConns = disabledConns
					end
					disabledConns[#disabledConns + 1] = conn
				end
			end
		end
	end
end

local function sweepEntrySignals(entry, limb, propName, forceResweep)
	if not (hasGetconnections and limbData._hooksV2Installed and entry and limb) then return end

	if forceResweep or not entry._changedSwept then
		entry._changedSwept = true
		migrateSignalConnections(entry._realChangedSig, "Changed", entry)
	end

	local sweptProps = entry._sweptProps
	if not sweptProps then
		sweptProps = {}
		entry._sweptProps = sweptProps
	end

	if not propName then
		for i = 1, #ALL_BLOCKED_PROPS do
			local p = ALL_BLOCKED_PROPS[i]
			if forceResweep or not sweptProps[p] then
				sweptProps[p] = true
				migrateSignalConnections(getRealPropSig(entry, limb, p), p, entry)
			end
		end
	elseif spoofWriteKeys[propName] then
		local canon = PROP_ALIASES[propName] or propName
		if forceResweep or not sweptProps[canon] then
			sweptProps[canon] = true
			migrateSignalConnections(getRealPropSig(entry, limb, canon), canon, entry)
		end
	end
end

local function collectTempDisabled(realSignal, bucket)
	if not realSignal then return bucket end
	local conns = getconnections(realSignal)
	for i = 1, #conns do
		local conn = conns[i]
		if conn.Enabled then
			local fn = conn.Function
			if fn and not ownWatchCallbacks[fn] then
				conn:Disable()
				if not bucket then bucket = {} end
				bucket[#bucket + 1] = conn
			end
		end
	end
	return bucket
end

local function beginSuppressedWrite(entry, limb, propName)
	if not (hasGetconnections and entry and limb) then return nil end
	if limbData._hooksV2Installed then
		sweepEntrySignals(entry, limb, propName, false)
		return nil
	end

	local bucket = collectTempDisabled(entry._realChangedSig, nil)
	if not propName then
		for i = 1, #ALL_BLOCKED_PROPS do
			bucket = collectTempDisabled(getRealPropSig(entry, limb, ALL_BLOCKED_PROPS[i]), bucket)
		end
	elseif spoofWriteKeys[propName] then
		local canon = PROP_ALIASES[propName] or propName
		bucket = collectTempDisabled(getRealPropSig(entry, limb, canon), bucket)
	end
	return bucket
end

local function reenableBatch(list)
	for i = 1, #list do
		pcall(list[i].Enable, list[i])
	end
end

local function endSuppressedWrite(tempDisabled)
	if tempDisabled then
		task_defer(reenableBatch, tempDisabled)
	end
end

local function rawReadCFrame(limb)
	return limb.CFrame
end

local function capturePhysicsSnapshot(entry, limb)
	local origCOM                      = limb.AssemblyCenterOfMass
	entry.OriginalMass                 = limb.Mass
	entry.OriginalAssemblyMass         = limb.AssemblyMass
	entry.OriginalCenterOfMass         = limb.CenterOfMass or Vector3_new()
	entry.OriginalAssemblyCenterOfMass = origCOM
	entry.OriginalCOMOffset            = limb.CFrame:PointToObjectSpace(origCOM)
end

local function rawWriteSize(limb, value)
	limb.Size = value
end

local function rawWriteProp(limb, propName, value)
	limb[propName] = value
end

local function setLimbPropSuppressed(entry, limb, propName, value)
	local temp = beginSuppressedWrite(entry, limb, propName)
	entry._internalWrite = true
	if propName == "Size" then
		pcall(rawWriteSize, limb, value)
	else
		pcall(rawWriteProp, limb, propName, value)
	end
	entry._internalWrite = false
	endSuppressedWrite(temp)
end

local function runSuppressedMultiWrite(entry, limb, fn)
	local temp = beginSuppressedWrite(entry, limb, nil)
	entry._internalWrite = true
	pcall(fn, entry, limb)
	entry._internalWrite = false
	endSuppressedWrite(temp)
end

local function rawRestoreBody(entry, limb)
	if limb.Size ~= entry.OriginalSize then
		limb.Size = entry.OriginalSize
	end
	if limb.Transparency ~= entry.OriginalTransparency then
		limb.Transparency = entry.OriginalTransparency
	end
	if limb.CanCollide ~= entry.OriginalCanCollide then
		limb.CanCollide = entry.OriginalCanCollide
	end
	if entry.TargetMassless ~= nil and limb.Massless ~= entry.OriginalMassless then
		limb.Massless = entry.OriginalMassless
	end
	if entry.TargetRootPriority ~= nil and limb.RootPriority ~= entry.OriginalRootPriority then
		limb.RootPriority = entry.OriginalRootPriority
	end
end

local function restoreEntryRawProps(entry, limb)
	runSuppressedMultiWrite(entry, limb, rawRestoreBody)
end

local function reenableAndResweep(disabledConns, limb)
	local prevId = beginElevated()
	for i = 1, #disabledConns do
		pcall(disabledConns[i].Enable, disabledConns[i])
	end
	local activeEntry = limb and limbBlocked[limb]
	if activeEntry then
		sweepEntrySignals(activeEntry, limb, nil, true)
	end
	endElevated(prevId)
end

local function cleanupEntrySignals(entry, limb, limbAlive)
	local realSignals = entry._realSignals
	if realSignals then
		for _, be in pairs(realSignals) do
			be:Destroy()
		end
		entry._realSignals = nil
	end
	entry._customSignals   = nil
	entry._migratedFns     = nil
	entry._realChangedSig  = nil
	entry._realPropSigs    = nil
	entry._changedSwept    = nil
	entry._sweptProps      = nil
	entry._disabledConnSet = nil

	local disabledConns = entry._disabledConns
	entry._disabledConns = nil
	if disabledConns then
		if limbAlive then
			task_defer(reenableAndResweep, disabledConns, limb)
		else
			for i = 1, #disabledConns do
				pcall(disabledConns[i].Disconnect, disabledConns[i])
			end
		end
	end
end

local spoofedGetPropChangedSignal = hasGetPropSig and wrapC(function(inst, prop)
	local data = limbBlocked[inst]
	if data and not data._internalWrite and type(prop) == "string" and (not hasCheckcaller or not checkcaller()) then
		local clean = normalizeSpoofKey(prop)
		local canon = PROP_ALIASES[clean] or clean
		if LIMB_PROPS[canon] then
			local okSigObj, sig = pcall(getOrCreateSignalPair, data, canon)
			if okSigObj and sig then
				return sig
			end
		end
	end
	return rawGetPropChangedSig(inst, prop)
end) or nil

limbData._readSpoof = function(data, key, preTag)
	if data._internalWrite then
		return false, nil
	end
	local tag = preTag or spoofReadKeys[key]
	if not tag then
		local clean = normalizeSpoofKey(key)
		if clean ~= key then
			tag = spoofReadKeys[clean]
		end
	end
	if type(tag) == "string" then
		return true, data[tag]
	elseif tag == READ_SPECIAL_CHANGED then
		local okSigObj, sig = pcall(getOrCreateSignalPair, data, "Changed")
		if okSigObj and sig then
			return true, sig
		end
	elseif tag == READ_SPECIAL_PROP_SIG and spoofedGetPropChangedSignal then
		return true, spoofedGetPropChangedSignal
	elseif tag == READ_SPECIAL_COM then
		local limb   = data.Limb
		local offset = data.OriginalCOMOffset
		if limb and limb.Parent ~= nil and offset then
			data._internalWrite = true
			local okCF, cf = pcall(rawReadCFrame, limb)
			data._internalWrite = false
			if okCF and cf then
				return true, cf:PointToWorldSpace(offset)
			end
		end
		return true, data.OriginalAssemblyCenterOfMass
	end
	return false, nil
end

local function applySpoofedWriteSignals(limb, data, canon)
	sweepEntrySignals(data, limb, canon, false)
	local real = data._realSignals
	if real then
		local sig = real[canon]
		if sig then
			sig:Fire()
		end
		local changed = real.Changed
		if changed then
			changed:Fire(canon)
		end
	end
end

limbData._writeSpoof = function(limb, data, key, value)
	if data._internalWrite then
		return false
	end
	local clean = normalizeSpoofKey(key)
	local orig  = spoofWriteKeys[clean]
	if not orig then
		return false
	end
	local canon = PROP_ALIASES[clean] or clean
	if not isValidPropValue(canon, value) then
		return false
	end
	value = sanitizePropValue(canon, value)

	if (canon == "RootPriority" and data.TargetRootPriority == nil)
		or (canon == "Massless" and data.TargetMassless == nil) then
		data[orig] = value
		return false
	end
	if data[orig] == value then
		return true
	end
	data[orig] = value

	local prevId = beginElevated()
	pcall(applySpoofedWriteSignals, limb, data, canon)
	endElevated(prevId)
	return true
end

if hasCheckcaller and not limbData._hooksV2Installed then
	local originalIndex, originalNewIndex

	local function rawIndexHook(self, key)
		local data = limbBlocked[self]
		if data and not data._internalWrite and not checkcaller() then
			local tag = spoofReadKeys[key]
			if not tag then
				local clean = normalizeSpoofKey(key)
				if clean ~= key then
					tag = spoofReadKeys[clean]
				end
			end
			if tag then
				if type(tag) == "string" then
					return data[tag]
				end
				local readSpoof = limbData._readSpoof
				if readSpoof then
					local hit, val = readSpoof(data, key, tag)
					if hit then
						return val
					end
				end
			end
		end
		return originalIndex(self, key)
	end

	local function rawNewIndexHook(self, key, value)
		local data = limbBlocked[self]
		if data and not data._internalWrite and not checkcaller() then
			local clean = spoofWriteKeys[key] and key or normalizeSpoofKey(key)
			if spoofWriteKeys[clean] then
				local writeSpoof = limbData._writeSpoof
				if writeSpoof and writeSpoof(self, data, clean, value) then
					return
				end
			end
		end
		return originalNewIndex(self, key, value)
	end

	local idxClosure     = rawIndexHook
	local newIdxClosure  = rawNewIndexHook
	local indexHooked    = false
	local newIndexHooked = false

	if hasOthHook and hasGetrawmetatable and executorName ~= "potassium" then
		local mt = getrawmetatable(game)
		local okIdx, origIdx = pcall(othHookFn, mt.__index, idxClosure)
		if okIdx and origIdx then
			originalIndex = origIdx
			indexHooked   = true

			local okNew, origNew = pcall(othHookFn, mt.__newindex, newIdxClosure)
			if okNew and origNew then
				originalNewIndex = origNew
				newIndexHooked   = true
			elseif othUnhookFn then
				local okUn, unRes = pcall(othUnhookFn, mt.__index, idxClosure)
				if not okUn then
					okUn, unRes = pcall(othUnhookFn, mt.__index)
				end
				if okUn and unRes ~= false and mt.__index ~= idxClosure then
					indexHooked = false
				end
			end
		end
	end

	if not (indexHooked and newIndexHooked) and hasHookmetamethod then
		if not indexHooked then
			local okIdx, origIdx = pcall(hookmetamethod, game, "__index", idxClosure)
			if okIdx and origIdx then
				originalIndex = origIdx
				indexHooked   = true
			end
		end
		if indexHooked and not newIndexHooked then
			local okNew, origNew = pcall(hookmetamethod, game, "__newindex", newIdxClosure)
			if okNew and origNew then
				originalNewIndex = origNew
				newIndexHooked   = true
			end
		end
	end

	if not (indexHooked and newIndexHooked) and hasGetrawmetatable and hasSetreadonly then
		local mt = getrawmetatable(game)
		setreadonly(mt, false)
		if not indexHooked then
			originalIndex = mt.__index
			mt.__index    = idxClosure
			indexHooked   = true
		end
		if not newIndexHooked then
			originalNewIndex = mt.__newindex
			mt.__newindex    = newIdxClosure
			newIndexHooked   = true
		end
		setreadonly(mt, true)
	end

	if indexHooked and newIndexHooked then
		limbData._hooksV2Installed  = true
		limbData._hooksV2DynamicCOM = true
		spoofReadKeys.AssemblyCenterOfMass = READ_SPECIAL_COM
		spoofReadKeys.assemblyCenterOfMass = READ_SPECIAL_COM
	end
end

local function recalcEntryDistFields(entry, rangeMult)
	local radius = entry.LimbRadius
	if not radius then return end
	entry._maxDistSq  = (radius * rangeMult + DIST_MAX_PAD) ^ 2
	entry._minDistSq  = (radius * DIST_MIN_FACTOR) ^ 2
	local rangeSq     = entry._maxDistSq - entry._minDistSq
	entry._rangeInvSq = (rangeSq > 0) and (1 / rangeSq) or 0
end

local function applyEntryTargets(entry, newVec, isHRP, settings)
	entry.BaseTargetSize     = newVec
	entry.TargetSize         = newVec
	entry.TargetTransparency = settings.LIMB_TRANSPARENCY
	entry.TargetCanCollide   = settings.LIMB_CAN_COLLIDE
	if isHRP then
		entry.TargetMassless     = nil
		entry.TargetRootPriority = nil
	else
		entry.TargetMassless     = true
		entry.TargetRootPriority = NON_HRP_ROOT_PRIORITY
	end
	entry.LimbRadius = math_max(newVec.X, newVec.Y, newVec.Z) * 0.5
	recalcEntryDistFields(entry, settings.DYNAMIC_SCALE_RANGE_MULT or 1.0)
end

local function evalDynamicSize(entry, limbPos, localPos)
	local baseSize  = entry.BaseTargetSize
	local origSize  = entry.OriginalSize
	local maxDistSq = entry._maxDistSq
	if not baseSize or not origSize or not maxDistSq or not localPos then
		return baseSize, "max"
	end

	local diff   = limbPos - localPos
	local sqDist = diff:Dot(diff)
	if sqDist >= maxDistSq then
		return baseSize, "max"
	end

	local minDistSq  = entry._minDistSq
	local rangeInvSq = entry._rangeInvSq
	if not rangeInvSq or rangeInvSq <= 0 then
		return baseSize, "max"
	end
	if sqDist <= minDistSq then
		return origSize, "min"
	end

	local factor = math_sqrt(math_clamp((sqDist - minDistSq) * rangeInvSq, 0, 1))
	return origSize:Lerp(baseSize, factor), nil
end

local function writeLimbSize(entry, limb, targetSize, boundState)
	setLimbPropSuppressed(entry, limb, "Size", targetSize)
	entry.TargetSize   = targetSize
	entry._appliedSize = targetSize
	entry._scaleBound  = boundState
end

local function connectPropWatch(entry, limb, propName, targetField)
	local realSig = getRealPropSig(entry, limb, propName)
	if not realSig then return nil end
	local isSize = propName == "Size"
	local cb = function()
		if entry._internalWrite or not limb.Parent then return end
		local prevId = beginElevated()
		local target = entry[targetField]
		if target ~= nil and limb[propName] ~= target then
			setLimbPropSuppressed(entry, limb, propName, target)
			if isSize then
				entry._appliedSize = target
			end
		end
		endElevated(prevId)
	end
	ownWatchCallbacks[cb] = true
	return realSig:Connect(cb)
end

local function syncSizeWatchdog(entry, limb, dynamicEnabled)
	if entry._sizeWatchConn then
		entry._sizeWatchConn:Disconnect()
		entry._sizeWatchConn = nil
	end
	if dynamicEnabled or not limb or entry.TargetSize == nil then return end
	entry._sizeWatchConn = connectPropWatch(entry, limb, "Size", "TargetSize")
end

local function disconnectEntryWatchdogs(entry)
	if entry._sizeWatchConn then
		entry._sizeWatchConn:Disconnect()
		entry._sizeWatchConn = nil
	end
	local conns = entry._watchConns
	if conns then
		for i = 1, #conns do
			conns[i]:Disconnect()
		end
		entry._watchConns = nil
	end
end

local function setupLimbWatchdog(entry, limb, settings)
	if not entry or not limb then return end
	disconnectEntryWatchdogs(entry)

	local watchConns  = {}
	entry._watchConns = watchConns

	for i = 1, #STATIC_WATCH_PROPS do
		local pair = STATIC_WATCH_PROPS[i]
		local propName, targetField = pair[1], pair[2]
		if entry[targetField] ~= nil then
			local conn = connectPropWatch(entry, limb, propName, targetField)
			if conn then
				watchConns[#watchConns + 1] = conn
			end
		end
	end

	syncSizeWatchdog(entry, limb, settings.DYNAMIC_SCALE_ENABLED)
end

local LimbExtender = {}
LimbExtender.__index = LimbExtender

function LimbExtender:_saveEntryData(char, limb)
	local cache = self._playerCache
	local entry = cache[char]
	if entry then
		if entry.Limb == limb then
			return entry
		end
		local prevLimb = entry.Limb
		if prevLimb then
			disconnectEntryWatchdogs(entry)
			local prevAlive = prevLimb.Parent ~= nil
			if prevAlive then
				restoreEntryRawProps(entry, prevLimb)
			end
			limbBlocked[prevLimb] = nil
			cleanupEntrySignals(entry, prevLimb, prevAlive)
		end
		entry._appliedSize = nil
		entry._scaleBound  = nil
	else
		entry = {}
		cache[char] = entry
		self._cacheCount = self._cacheCount + 1
	end

	entry.Character            = char
	entry.Limb                 = limb
	entry.OriginalSize         = limb.Size
	entry.OriginalTransparency = limb.Transparency
	entry.OriginalCanCollide   = limb.CanCollide
	entry.OriginalMassless     = limb.Massless
	entry.OriginalRootPriority = limb.RootPriority

	if hasGetconnections then
		local okChanged, changedSig = pcall(function() return limb.Changed end)
		entry._realChangedSig = okChanged and changedSig or nil
	end

	if limbData._hooksV2Installed then
		pcall(capturePhysicsSnapshot, entry, limb)
	end
	limbBlocked[limb] = entry

	return entry
end

function LimbExtender:_syncESPLocalCharacter(char)
	if self._ESP and type(self._ESP.SetLocalCharacter) == "function" then
		pcall(self._ESP.SetLocalCharacter, self._ESP, char)
	end
end

function LimbExtender:_updateLocalCharacter()
	local char = nil
	if self._manager and type(self._manager.GetLocalCharacter) == "function" then
		local ok, mChar = pcall(self._manager.GetLocalCharacter, self._manager)
		if ok then char = mChar end
	end
	if not char then
		local custom = self._customLocalChar
		if custom and custom.Parent then
			char = custom
		else
			self._customLocalChar = nil
			local lp = getLocalPlayer()
			char = lp and lp.Character or nil
		end
	end

	self._localChar = char
	self._localHRP  = resolveCharacterRoot(char)
	self:_syncESPLocalCharacter(char)

	if char and (self._playerCache[char] or self._trackedTargets[char] ~= nil) then
		local prevId = beginElevated()
		self:_onTargetRemoved(char)
		endElevated(prevId)
	end
end

function LimbExtender:_getLocalPosition()
	local hrp = self._localHRP
	if hrp and hrp.Parent then
		return hrp.Position
	end
	local char = self._localChar
	if char and char.Parent then
		hrp = resolveCharacterRoot(char)
		self._localHRP = hrp
		if hrp and hrp.Parent then
			return hrp.Position
		end
	elseif self._customLocalChar then
		self._customLocalChar = nil
		self._localChar       = nil
	end
	local cam = Workspace.CurrentCamera
	return cam and cam.CFrame.Position or nil
end

local function rawApplyTargetsBody(entry, limb)
	if limb.Size ~= entry.TargetSize then
		limb.Size = entry.TargetSize
	end
	if limb.Transparency ~= entry.TargetTransparency then
		limb.Transparency = entry.TargetTransparency
	end
	if limb.CanCollide ~= entry.TargetCanCollide then
		limb.CanCollide = entry.TargetCanCollide
	end
	if entry.TargetMassless ~= nil and limb.Massless ~= entry.TargetMassless then
		limb.Massless = entry.TargetMassless
	end
	if entry.TargetRootPriority ~= nil and limb.RootPriority ~= entry.TargetRootPriority then
		limb.RootPriority = entry.TargetRootPriority
	end
end

function LimbExtender:_syncLimbProperties(entry, limb, resetWatchdogs, cachedLocalPos)
	local s      = self._settings
	local newVec = self._limbSizeVec
	local isHRP  = limb.Name == "HumanoidRootPart"

	applyEntryTargets(entry, newVec, isHRP, s)

	local appliedSize, boundState
	if s.DYNAMIC_SCALE_ENABLED then
		local localPos = cachedLocalPos or self:_getLocalPosition()
		appliedSize, boundState = evalDynamicSize(entry, limb.Position, localPos)
	else
		appliedSize, boundState = newVec, "max"
	end

	entry.TargetSize   = appliedSize
	entry._appliedSize = appliedSize
	entry._scaleBound  = boundState

	runSuppressedMultiWrite(entry, limb, rawApplyTargetsBody)

	if resetWatchdogs or not entry._watchConns then
		setupLimbWatchdog(entry, limb, s)
	end
end

function LimbExtender:_enqueueLateSweep(entry)
	self._lateSweepQueue[entry] = os_clock() + LATE_SWEEP_DELAY
	if self._lateSweepActive then return end
	self._lateSweepActive = true

	local runId = self._runId
	task_spawn(function()
		while self._running and not self._destroyed and self._runId == runId do
			local now       = os_clock()
			local processed = 0
			local nextDue   = nil

			local prevId = beginElevated()
			for item, dueAt in pairs(self._lateSweepQueue) do
				if now >= dueAt then
					self._lateSweepQueue[item] = nil
					local limb = item.Limb
					if limb and limb.Parent and self._playerCache[item.Character] == item then
						sweepEntrySignals(item, limb, nil, true)
					end
					processed = processed + 1
					if processed >= BATCH_SIZE then
						nextDue = now
						break
					end
				elseif not nextDue or dueAt < nextDue then
					nextDue = dueAt
				end
			end
			endElevated(prevId)

			if not nextDue and next(self._lateSweepQueue) == nil then
				break
			end
			if nextDue and nextDue > now then
				task_wait(nextDue - now)
			else
				task_wait()
			end
		end
		self._lateSweepActive = false
	end)
end

function LimbExtender:_enqueueESPRetry(char)
	if not char or self._espRetryQueue[char] then return end
	self._espRetryQueue[char] = 0
	if self._espRetryActive then return end
	self._espRetryActive = true

	local runId = self._runId
	task_spawn(function()
		while self._running and not self._destroyed and self._runId == runId and self._settings.ESP and self._ESP do
			if next(self._espRetryQueue) == nil then
				break
			end
			task_wait(ESP_RETRY_INTERVAL)
			if not (self._running and not self._destroyed and self._runId == runId and self._settings.ESP and self._ESP) then
				break
			end
			local prevId = beginElevated()
			for model, attempts in pairs(self._espRetryQueue) do
				if not model or not model.Parent or self._trackedTargets[model] == nil or self._deadTargets[model] then
					self._espRetryQueue[model] = nil
				elseif espTrackSafe(self._ESP, model) or attempts + 1 >= ESP_RETRY_LIMIT then
					self._espRetryQueue[model] = nil
				else
					self._espRetryQueue[model] = attempts + 1
				end
			end
			endElevated(prevId)
		end
		table_clear(self._espRetryQueue)
		self._espRetryActive = false
	end)
end

function LimbExtender:_attachVisuals(char)
	if self._deadTargets[char] then return end
	if self._settings.ESP and self._ESP then
		if not espTrackSafe(self._ESP, char) then
			self:_enqueueESPRetry(char)
		end
	end

	if self._settings.CHAMS and self._CHAMS then
		local cfg = self._cachedChamsConfig
		if not cfg then
			cfg = self:_buildChamsConfig()
			self._cachedChamsConfig = cfg
		end
		self._chamsActive = true
		pcall(self._CHAMS.addHighlight, char, self._chamsSourceKey, cfg)
	end
end

function LimbExtender:_detachVisuals(char)
	self._espRetryQueue[char] = nil
	if self._ESP then
		pcall(self._ESP.Untrack, self._ESP, char)
	end
	if self._CHAMS and self._chamsActive then
		pcall(self._CHAMS.removeHighlight, char, self._chamsSourceKey)
	end
end

function LimbExtender:_isLocalChar(char)
	local lp = getLocalPlayer()
	return char == self._localChar or char == self._customLocalChar or (lp and lp.Character == char)
end

function LimbExtender:_onTargetAdded(player, char)
	if not char or self:_isLocalChar(char) then return end
	local prevId = beginElevated()
	local wasDead = self._deadTargets[char]
	self._deadTargets[char] = nil
	if self._trackedTargets[char] == nil then
		self._trackedTargets[char] = player or false
		self:_attachVisuals(char)
	else
		if player then
			self._trackedTargets[char] = player
		end
		if wasDead then
			self:_attachVisuals(char)
		end
	end
	endElevated(prevId)
end

function LimbExtender:_onTargetRemoved(char)
	if not char then return end
	local prevId = beginElevated()
	self._trackedTargets[char] = nil
	self._deadTargets[char]    = nil
	self:_restoreLimb(char)
	self:_detachVisuals(char)
	endElevated(prevId)
end

function LimbExtender:_onTargetRevived(player, char)
	if not char or self:_isLocalChar(char) then return end
	local prevId = beginElevated()
	local wasDead = self._deadTargets[char]
	self._deadTargets[char] = nil
	if self._trackedTargets[char] == nil then
		self._trackedTargets[char] = player or false
		self:_attachVisuals(char)
	else
		if player then
			self._trackedTargets[char] = player
		end
		if wasDead then
			self:_attachVisuals(char)
		end
	end
	endElevated(prevId)
end

function LimbExtender:_applyLimb(char, limb)
	local entry = self:_saveEntryData(char, limb)
	if not entry then return end

	self:_syncLimbProperties(entry, limb, true)

	if hasGetconnections and limbData._hooksV2Installed then
		self:_enqueueLateSweep(entry)
	end
end

function LimbExtender:_restoreLimb(char, activeLimb)
	local cache = self._playerCache
	local entry = cache[char]
	if not entry then return end

	self._lateSweepQueue[entry] = nil

	disconnectEntryWatchdogs(entry)

	local targetLimb = activeLimb or entry.Limb
	local limbAlive  = targetLimb ~= nil and targetLimb.Parent ~= nil
	if limbAlive then
		restoreEntryRawProps(entry, targetLimb)
	end

	if targetLimb then
		limbBlocked[targetLimb] = nil
	end
	if entry.Limb and entry.Limb ~= targetLimb then
		limbBlocked[entry.Limb] = nil
	end

	cleanupEntrySignals(entry, targetLimb, limbAlive)

	cache[char] = nil
	if self._cacheCount > 0 then
		self._cacheCount = self._cacheCount - 1
	end
	table_clear(entry)
end

function LimbExtender:_applyLimbs(player, char, limb)
	if not char or not limb or self:_isLocalChar(char) then return end
	local prevId  = beginElevated()
	local wasDead = self._deadTargets[char]
	self._deadTargets[char] = nil
	if self._trackedTargets[char] == nil then
		self._trackedTargets[char] = player or false
		self:_attachVisuals(char)
	else
		if player then
			self._trackedTargets[char] = player
		end
		if wasDead then
			self:_attachVisuals(char)
		end
	end
	self:_applyLimb(char, limb)
	endElevated(prevId)
end

function LimbExtender:_removeLimbs(_, char, limb, fromDeath)
	if self._suppressOnLimbLost or not char then return end
	local prevId = beginElevated()
	self:_restoreLimb(char, limb)
	if fromDeath then
		self._deadTargets[char] = true
		self:_detachVisuals(char)
	elseif self._trackedTargets[char] == nil or not char.Parent then
		self._trackedTargets[char] = nil
		self._deadTargets[char]    = nil
		self:_detachVisuals(char)
	end
	endElevated(prevId)
end

function LimbExtender:_stopDynamicLoop()
	if self._dynamicScaleConn then
		self._dynamicScaleConn:Disconnect()
		self._dynamicScaleConn = nil
	end
	table_clear(self._scaleQueue)
	self._scaleCursor = 1
end

function LimbExtender:_stopAuxQueues()
	table_clear(self._lateSweepQueue)
	table_clear(self._espRetryQueue)
	self._lateSweepActive = false
	self._espRetryActive  = false
end

function LimbExtender:_syncESP(skipSet)
	local s = self._settings
	if s.ESP then
		local espModule = ensureRemoteModule("ESP", skipSet)
		if self._destroyed then return end
		if not s.ESP then
			if self._ESP then
				pcall(self._ESP.Destroy, self._ESP)
				self._ESP = nil
			end
			return
		end
		if espModule then
			if not self._ESP then
				self._ESP = espModule.new(self:_buildESPConfig())
				self:_syncESPLocalCharacter(self._localChar)
				if self._running then
					pcall(self._ESP.Start, self._ESP)
					for char in pairs(self._trackedTargets) do
						if not self._deadTargets[char] and not espTrackSafe(self._ESP, char) then
							self:_enqueueESPRetry(char)
						end
					end
				end
			else
				pcall(self._ESP.SetOptions, self._ESP, self:_buildESPConfig())
			end
		else
			s.ESP = false
		end
	elseif self._ESP then
		table_clear(self._espRetryQueue)
		pcall(self._ESP.Destroy, self._ESP)
		self._ESP = nil
	end
end

function LimbExtender:_syncChams(skipSet)
	local s = self._settings
	self._cachedChamsConfig = nil

	if s.CHAMS then
		local chamsModule = ensureRemoteModule("CHAMS", skipSet)
		if self._destroyed then return end
		if s.CHAMS then
			if chamsModule then
				self._CHAMS = chamsModule
				local config = self:_buildChamsConfig()
				self._cachedChamsConfig = config
				if self._running and next(self._trackedTargets) ~= nil then
					local wasActive = self._chamsActive
					self._chamsActive = true
					if wasActive and type(chamsModule.updateSource) == "function" and type(chamsModule.isHighlighted) == "function" then
						pcall(chamsModule.updateSource, self._chamsSourceKey, config)
						for char in pairs(self._trackedTargets) do
							if not self._deadTargets[char] and not chamsModule.isHighlighted(char, self._chamsSourceKey) then
								pcall(chamsModule.addHighlight, char, self._chamsSourceKey, config)
							end
						end
					else
						for char in pairs(self._trackedTargets) do
							if not self._deadTargets[char] then
								local okUpd, updated = pcall(chamsModule.updateHighlight, char, self._chamsSourceKey, config)
								if not (okUpd and updated) then
									pcall(chamsModule.addHighlight, char, self._chamsSourceKey, config)
								end
							end
						end
					end
				end
				return
			else
				s.CHAMS = false
			end
		end
	end

	if self._CHAMS and self._chamsActive then
		if type(self._CHAMS.removeSource) == "function" then
			pcall(self._CHAMS.removeSource, self._chamsSourceKey)
		else
			for char in pairs(self._trackedTargets) do
				pcall(self._CHAMS.removeHighlight, char, self._chamsSourceKey)
			end
		end
	end
	self._chamsActive = false
end

function LimbExtender:_teardownAllTargets()
	local cache = self._playerCache
	if self._cacheCount > 0 then
		local chars = {}
		for char in pairs(cache) do
			chars[#chars + 1] = char
		end
		for i = 1, #chars do
			local char  = chars[i]
			local entry = cache[char]
			if entry then
				self:_restoreLimb(char, entry.Limb)
			end
		end
		table_clear(cache)
		self._cacheCount = 0
	end

	table_clear(self._espRetryQueue)
	if self._ESP then
		if type(self._ESP.ClearCharacters) == "function" then
			pcall(self._ESP.ClearCharacters, self._ESP)
		else
			for char in pairs(self._trackedTargets) do
				pcall(self._ESP.Untrack, self._ESP, char)
			end
		end
	end
	if self._CHAMS and self._chamsActive then
		if type(self._CHAMS.removeSource) == "function" then
			pcall(self._CHAMS.removeSource, self._chamsSourceKey)
		else
			for char in pairs(self._trackedTargets) do
				pcall(self._CHAMS.removeHighlight, char, self._chamsSourceKey)
			end
		end
	end
	table_clear(self._trackedTargets)
	table_clear(self._deadTargets)
	self._chamsActive = false
end

function LimbExtender:_drainDirtyWork()
	while self._running and not self._destroyed and (self._dirtyESP or self._dirtyCHAMS or self._dirtyCosmetic) do
		if self._dirtyESP then
			self._dirtyESP = false
			self:_syncESP()
		end

		if self._dirtyCHAMS then
			self._dirtyCHAMS = false
			self:_syncChams()
		end

		if not self._running or self._destroyed then break end

		if self._dirtyCosmetic then
			self._dirtyCosmetic = false
			local ok, err = pcall(self._doCosmeticUpdateBatched, self)
			if not ok then
				warn("[LimbExtender] Cosmetic update failed: " .. tostring(err))
			end
		end
	end
end

function LimbExtender:_processDirtyWork()
	self._workScheduled = false
	if self._processingWork or not self._running or self._destroyed then return end
	self._processingWork = true
	local prevId = beginElevated()
	local ok, err = pcall(self._drainDirtyWork, self)
	endElevated(prevId)
	self._processingWork = false
	if not ok then
		warn("[LimbExtender] Worker failed: " .. tostring(err))
	end
end

function LimbExtender:_scheduleDirtyWork()
	if not self._running or self._destroyed or self._processingWork or self._workScheduled then return end
	self._workScheduled = true
	task_defer(self._processDirtyWork, self)
end

function LimbExtender:_doCosmeticUpdateBatched()
	if not self._running or self._destroyed or self._cacheCount == 0 then return end
	local runId   = self._runId
	local entries = {}
	for _, entry in pairs(self._playerCache) do
		if entry.Limb and entry.Character then
			entries[#entries + 1] = entry
		end
	end

	local dynamicEnabled = self._settings.DYNAMIC_SCALE_ENABLED
	for i = 1, #entries, BATCH_SIZE do
		if not self._running or self._destroyed or self._runId ~= runId or self._dirtyCosmetic then return end
		local localPos = dynamicEnabled and self:_getLocalPosition() or nil
		local last     = math_min(i + BATCH_SIZE - 1, #entries)
		for j = i, last do
			local entry = entries[j]
			local limb  = entry.Limb
			if limb and limb.Parent then
				self:_syncLimbProperties(entry, limb, false, localPos)
			end
		end
		if last < #entries then
			task_wait()
		end
	end
end

function LimbExtender:_initGameScript(skipSet)
	local gameId  = game.GameId
	local urlList = GAME_SCRIPT_URLS[gameId]
	if not urlList or self._gameScriptFetched or self._fetchingGameScript then return end
	self._fetchingGameScript = true

	task_spawn(function()
		local prevId = beginElevated()
		local source = ensureGameScriptSource(gameId, skipSet)
		local loaded = false
		if source and hasLoadstring and not self._destroyed then
			local okCompile, fn = pcall(loadstring, source)
			if okCompile and type(fn) == "function" then
				loaded = pcall(fn, self)
			end
		end
		endElevated(prevId)
		self._fetchingGameScript = false
		if loaded then
			self._gameScriptFetched = true
			if self._running and not self._destroyed and self._customSetup and not self._runningCustomSetup then
				self._runningCustomSetup = true
				local pId = beginElevated()
				pcall(self._customSetup, self)
				endElevated(pId)
				self._runningCustomSetup = false
			end
		end
	end)
end

function LimbExtender:_runGameScriptIfNeeded()
	local gameId  = game.GameId
	local urlList = GAME_SCRIPT_URLS[gameId]
	if not urlList then return end

	if self._customSetup then
		if self._runningCustomSetup or not self._running or self._destroyed then return end
		local runId = self._runId
		task_spawn(function()
			if not self._running or self._destroyed or self._runId ~= runId or self._runningCustomSetup then return end
			self._runningCustomSetup = true
			local prevId = beginElevated()
			pcall(self._customSetup, self)
			endElevated(prevId)
			self._runningCustomSetup = false
		end)
		return
	end

	self:_initGameScript()
end

function LimbExtender:_syncAllSizeWatchdogs(dynamicEnabled)
	for _, entry in pairs(self._playerCache) do
		local limb = entry.Limb
		if limb and limb.Parent then
			syncSizeWatchdog(entry, limb, dynamicEnabled)
		end
	end
end

function LimbExtender:_updateSingleDynamicScale(entry, localPos)
	local limb = entry.Limb
	if not limb or not limb.Parent or not entry._maxDistSq then return end

	local targetSize, boundState = evalDynamicSize(entry, limb.Position, localPos)
	if not targetSize then return end

	if boundState then
		if entry._scaleBound == boundState then return end
	else
		local currentSize = entry._appliedSize or limb.Size
		local delta       = currentSize - targetSize
		if delta:Dot(delta) <= SIZE_CHANGE_THRESHOLD_SQ then
			return
		end
	end

	writeLimbSize(entry, limb, targetSize, boundState)
end

function LimbExtender:_stepDynamicScale(dt)
	if not self._running or self._destroyed then return end
	local queue = self._scaleQueue
	if self._cacheCount == 0 then
		if #queue > 0 then
			table_clear(queue)
			self._scaleCursor = 1
		end
		return
	end

	local interval = self._dynamicInterval
	self._nextDynamicUpdate = self._nextDynamicUpdate + dt
	local total    = #queue
	local localPos = nil

	if total == 0 then
		if self._nextDynamicUpdate < interval then return end
		self._nextDynamicUpdate = interval > 0 and (self._nextDynamicUpdate % interval) or 0

		localPos = self:_getLocalPosition()
		if not localPos then return end

		if self._cacheCount <= DYNAMIC_SLICE_SIZE then
			local prevId = beginElevated()
			for _, entry in pairs(self._playerCache) do
				self:_updateSingleDynamicScale(entry, localPos)
			end
			endElevated(prevId)
			return
		end

		for _, entry in pairs(self._playerCache) do
			queue[#queue + 1] = entry
		end
		total = #queue
		if total == 0 then return end
		self._scaleCursor = 1
	else
		localPos = self:_getLocalPosition()
		if not localPos then
			table_clear(queue)
			self._scaleCursor = 1
			return
		end
	end

	local startIdx = self._scaleCursor
	local lastIdx  = math_min(startIdx + DYNAMIC_SLICE_SIZE - 1, total)

	local prevId = beginElevated()
	for i = startIdx, lastIdx do
		self:_updateSingleDynamicScale(queue[i], localPos)
	end
	endElevated(prevId)

	if lastIdx >= total then
		table_clear(queue)
		self._scaleCursor = 1
	else
		self._scaleCursor = lastIdx + 1
	end
end

function LimbExtender:_resolveTargetLabel(model)
	local cached = self._trackedTargets[model]
	if cached ~= nil then
		if cached ~= false and typeof(cached) == "Instance" then
			return cached.Name
		end
		return model.Name
	end
	if self._manager and type(self._manager.GetPlayerFromCharacter) == "function" then
		local ok, player = pcall(self._manager.GetPlayerFromCharacter, self._manager, model)
		if ok and player and typeof(player) == "Instance" then
			return player.Name
		end
	end
	return model.Name
end

function LimbExtender:_buildESPConfig()
	local s = self._settings
	local textResolver = s.ESP_TEXT_RESOLVER or self._defaultTextResolver
	return {
		Color                = s.ESP_COLOR,
		Box3DColor           = s.ESP_BOX3D_COLOR,
		HealthColor          = s.ESP_HEALTH_COLOR,
		EmptyColor           = s.ESP_EMPTY_COLOR,
		SkeletonColor        = s.ESP_SKELETON_COLOR,
		TextColor            = s.ESP_TEXT_COLOR,
		TextSize             = s.ESP_TEXT_SIZE,
		ShowDistance         = s.ESP_DISTANCE,
		UseOffscreenPoint    = s.ESP_OFFSCREEN_POINT,
		FilterLocalCharacter = s.ESP_FILTER_LOCAL,
		LOD = {
			MaxDistance        = s.ESP_MAX_DISTANCE,
			NearDistance       = s.ESP_NEAR_DISTANCE,
			MediumDistance     = s.ESP_MEDIUM_DISTANCE,
			OcclusionEnabled   = s.ESP_OCCLUSION,
			OcclusionFrequency = s.ESP_OCCLUSION_FREQUENCY,
		},
		Flags = {
			Near   = applyToggles(s, s.ESP_NEAR_FLAGS),
			Medium = applyToggles(s, s.ESP_MEDIUM_FLAGS),
			Far    = applyToggles(s, s.ESP_FAR_FLAGS),
		},
		TextResolver = textResolver,
		CanDraw      = s.ESP_CAN_DRAW,
		TracerOrigin = s.ESP_TRACER_ORIGIN,
	}
end

function LimbExtender:_buildChamsConfig()
	local s = self._settings
	return {
		FillColor           = s.CHAMS_FILL_COLOR,
		OutlineColor        = s.CHAMS_OUTLINE_COLOR,
		FillTransparency    = s.CHAMS_FILL_TRANSPARENCY,
		OutlineTransparency = s.CHAMS_OUTLINE_TRANSPARENCY,
		DepthMode           = s.CHAMS_OCCLUSION and "AlwaysOnTop" or "Occluded",
	}
end

function LimbExtender:_buildManagerConfig()
	local s   = self._settings
	local cfg = {
		ON_CHARACTER_ADDED    = function(player, model) self:_onTargetAdded(player, model) end,
		ON_CHARACTER_REMOVING = function(_, model) self:_onTargetRemoved(model) end,
		ON_NPC_ADDED          = function(model) self:_onTargetAdded(nil, model) end,
		ON_NPC_REMOVING       = function(model) self:_onTargetRemoved(model) end,
		ON_LIMB_READY         = function(player, model, limb) self:_applyLimbs(player, model, limb) end,
		ON_LIMB_LOST          = function(player, model, limb, fromDeath) self:_removeLimbs(player, model, limb, fromDeath) end,
		ON_TARGET_REVIVED     = function(player, model) self:_onTargetRevived(player, model) end,
	}
	for key, meta in pairs(SCHEMA) do
		if meta.manager then
			cfg[meta.manager] = s[key]
		end
	end
	return cfg
end

function LimbExtender:_syncDirectoriesFromManager()
	local ok, dirs = pcall(self._manager.GetDirectories, self._manager)
	if ok and type(dirs) == "table" then
		self._settings.NPC_DIRECTORIES = table_clone(dirs)
	end
end

function LimbExtender.new(userSettings)
	local prevId    = beginElevated()
	local settings  = mergeSettings(userSettings)
	local failedSet = prefetchRemoteModules(settings)
	if prevId == nil then
		prevId = beginElevated()
	else
		beginElevated()
	end

	local managerModule = ensureRemoteModule("manager", failedSet)
	if not managerModule or not managerModule.Manager then
		endElevated(prevId)
		return false
	end

	terminateExisting()

	local playerCache = {}
	limbData.playerCache    = playerCache
	limbData.targetLimbName = settings.TARGET_LIMB

	local fallbackRefBindable = nil

	local self = setmetatable({
		_settings            = settings,
		_limbSizeVec         = resolveSizeVector(settings.LIMB_SIZE),
		_dynamicInterval     = resolveUpdateInterval(settings.DYNAMIC_SCALE_UPDATE_RATE),
		_playerCache         = playerCache,
		_trackedTargets      = {},
		_deadTargets         = {},
		_cacheCount          = 0,
		_manager             = nil,
		_ESP                 = nil,
		_CHAMS               = nil,
		_chamsActive         = false,
		_cachedChamsConfig   = nil,
		_running             = false,
		_destroyed           = false,
		_runId               = 0,
		_dirtyCosmetic       = false,
		_dirtyESP            = false,
		_dirtyCHAMS          = false,
		_suppressOnLimbLost  = false,
		_processingWork      = false,
		_workScheduled       = false,
		_gameScriptFetched   = false,
		_fetchingGameScript  = false,
		_runningCustomSetup  = false,
		_customSetup         = nil,
		_customCleanup       = nil,
		_customDestroy       = nil,
		_dynamicScaleConn    = nil,
		_nextDynamicUpdate   = 0,
		_scaleQueue          = {},
		_scaleCursor         = 1,
		_lateSweepQueue      = {},
		_lateSweepActive     = false,
		_espRetryQueue       = {},
		_espRetryActive      = false,
		_customLocalChar     = nil,
		_sampleChar          = nil,
		_fallbackRefBindable = nil,
		_mgrRefConn          = nil,
		ReferenceCharacterChanged = nil,
		_localChar           = nil,
		_localHRP            = nil,
		_chamsSourceKey      = nextChamsSourceKey(),
		_defaultTextResolver = nil,
		_terminateFn         = nil,
	}, LimbExtender)

	self._defaultTextResolver = function(model)
		return self:_resolveTargetLabel(model)
	end

	local mgr = managerModule.Manager.new(self:_buildManagerConfig())
	self._manager = mgr

	if type(mgr.OnReferenceCharacterChanged) == "function" then
		self.ReferenceCharacterChanged = mgr.ReferenceCharacterChanged
		self._mgrRefConn = mgr:OnReferenceCharacterChanged(function()
			self:_updateLocalCharacter()
		end)
	else
		fallbackRefBindable = Instance.new("BindableEvent")
		self._fallbackRefBindable      = fallbackRefBindable
		self.ReferenceCharacterChanged = fallbackRefBindable.Event
	end

	self:_syncESP(failedSet)
	self:_syncChams(failedSet)
	self:_updateLocalCharacter()
	self:_initGameScript(failedSet)

	local terminateFn = function() self:Destroy() end
	self._terminateFn  = terminateFn
	limbData.terminate = terminateFn
	endElevated(prevId)
	return self
end

function LimbExtender:IsRunning()
	return self._running and not self._destroyed
end

function LimbExtender:SetLocalCharacter(model)
	if self._destroyed then return end
	if model ~= nil and (typeof(model) ~= "Instance" or not model.Parent) then
		model = nil
	end
	self._customLocalChar = model
	if self._manager and type(self._manager.SetLocalCharacter) == "function" then
		local prevId = beginElevated()
		pcall(self._manager.SetLocalCharacter, self._manager, model)
		endElevated(prevId)
	end
	self:_updateLocalCharacter()
	if self._fallbackRefBindable and model then
		self._fallbackRefBindable:Fire(model)
	end
end

function LimbExtender:GetLocalCharacter()
	if self._destroyed then return nil end
	local char = self._localChar
	if char and char.Parent then
		return char
	end
	self:_updateLocalCharacter()
	return self._localChar
end

function LimbExtender:SetSampleCharacter(model)
	if self._destroyed then return end
	if model ~= nil and (typeof(model) ~= "Instance" or not model.Parent) then
		model = nil
	end
	self._sampleChar = model
	if self._manager and type(self._manager.SetSampleCharacter) == "function" then
		local prevId = beginElevated()
		pcall(self._manager.SetSampleCharacter, self._manager, model)
		endElevated(prevId)
	elseif self._fallbackRefBindable and not self._localChar and model then
		self._fallbackRefBindable:Fire(model)
	end
end

function LimbExtender:GetReferenceCharacter()
	if self._destroyed then return nil end
	if self._manager and type(self._manager.GetReferenceCharacter) == "function" then
		local ok, ref = pcall(self._manager.GetReferenceCharacter, self._manager)
		if ok and ref and ref.Parent then
			return ref
		end
	end
	local localChar = self:GetLocalCharacter()
	if localChar and localChar.Parent then
		return localChar
	end
	if self._sampleChar and self._sampleChar.Parent then
		return self._sampleChar
	end
	for char in pairs(self._trackedTargets) do
		if char and char.Parent then
			return char
		end
	end
	return nil
end

function LimbExtender:OnReferenceCharacterChanged(callback)
	if self._destroyed or type(callback) ~= "function" then
		return nil
	end
	if self._manager and type(self._manager.OnReferenceCharacterChanged) == "function" then
		return self._manager:OnReferenceCharacterChanged(callback)
	end
	if self._fallbackRefBindable then
		return self._fallbackRefBindable.Event:Connect(callback)
	end
	return nil
end

LimbExtender.OnLocalCharacterChanged = LimbExtender.OnReferenceCharacterChanged

function LimbExtender:Start()
	if self._destroyed or self._running then return end
	local prevId  = beginElevated()
	self._running = true
	self._runId   = self._runId + 1
	self._dirtyCosmetic = false

	self:_updateLocalCharacter()

	self._manager:Start()
	if self._ESP and self._settings.ESP then
		pcall(self._ESP.Start, self._ESP)
	end

	if self._settings.DYNAMIC_SCALE_ENABLED and not self._dynamicScaleConn then
		self:SetDynamicScale(true)
	end

	self:_runGameScriptIfNeeded()

	if self._dirtyCosmetic or self._dirtyESP or self._dirtyCHAMS then
		self:_scheduleDirtyWork()
	end
	endElevated(prevId)
end

function LimbExtender:Stop()
	if self._destroyed or not self._running then return end
	self._running = false
	self._runId   = self._runId + 1

	local prevId = beginElevated()
	if type(self._customCleanup) == "function" then
		pcall(self._customCleanup, self)
	end

	self:_stopDynamicLoop()
	self:_stopAuxQueues()

	self._suppressOnLimbLost = true
	pcall(self._manager.Stop, self._manager)
	self._suppressOnLimbLost = false

	if self._ESP then
		pcall(self._ESP.Stop, self._ESP)
	end

	self:_teardownAllTargets()
	endElevated(prevId)
end

function LimbExtender:Toggle(state)
	if self._destroyed then return end
	if type(state) == "boolean" then
		if state then self:Start() else self:Stop() end
	else
		if self._running then self:Stop() else self:Start() end
	end
end

function LimbExtender:Restart()
	if self._destroyed then return end
	local wasRunning = self._running
	self:Stop()
	if wasRunning then self:Start() end
end

function LimbExtender:SetDynamicScale(enabled, rangeMult)
	if self._destroyed then return end
	local prevId = beginElevated()
	enabled = not not enabled

	local s           = self._settings
	local prevEnabled = s.DYNAMIC_SCALE_ENABLED
	s.DYNAMIC_SCALE_ENABLED = enabled
	if rangeMult ~= nil then
		s.DYNAMIC_SCALE_RANGE_MULT = tonumber(rangeMult) or s.DYNAMIC_SCALE_RANGE_MULT
	end

	self:_stopDynamicLoop()

	if enabled then
		local mult = s.DYNAMIC_SCALE_RANGE_MULT or 1.0
		for _, entry in pairs(self._playerCache) do
			recalcEntryDistFields(entry, mult)
		end
		if self._running then
			self._dynamicInterval   = resolveUpdateInterval(s.DYNAMIC_SCALE_UPDATE_RATE)
			self._nextDynamicUpdate = self._dynamicInterval
			self._dynamicScaleConn  = RunService.Heartbeat:Connect(function(dt)
				self:_stepDynamicScale(dt)
			end)
		end
	else
		for _, entry in pairs(self._playerCache) do
			local limb = entry.Limb
			local base = entry.BaseTargetSize
			if limb and limb.Parent and base then
				writeLimbSize(entry, limb, base, "max")
			end
			entry._maxDistSq  = nil
			entry._minDistSq  = nil
			entry._rangeInvSq = nil
		end
	end

	if enabled ~= prevEnabled then
		self:_syncAllSizeWatchdogs(enabled)
	end
	endElevated(prevId)
end

function LimbExtender:Set(key, value)
	if self._destroyed then return end
	local meta = SCHEMA[key]
	if not meta then return end

	local s = self._settings
	if key == "DYNAMIC_SCALE_ENABLED" then
		local boolVal = not not value
		if s.DYNAMIC_SCALE_ENABLED == boolVal then return end
		self:SetDynamicScale(boolVal)
		return
	end

	if key == "LIMB_SIZE" then
		local nextVec = resolveSizeVector(value)
		s[key] = value
		if nextVec == self._limbSizeVec then return end
		self._limbSizeVec   = nextVec
		self._dirtyCosmetic = true
		self:_scheduleDirtyWork()
		return
	end

	if CLAMPED_UNIT_KEYS[key] and type(value) == "number" then
		value = math_clamp(value, 0, 1)
	end

	if meta.merge then
		if type(value) ~= "table" then return end
		if type(s[key]) ~= "table" then s[key] = {} end
		local changed = false
		for k, v in pairs(value) do
			if s[key][k] ~= v then
				s[key][k] = v
				changed = true
			end
		end
		if not changed then return end
	elseif type(value) == "table" then
		if tablesShallowEqual(s[key], value) then return end
		s[key] = cloneDeep(value)
	else
		if s[key] == value then return end
		s[key] = value
	end

	local kind = meta.kind
	if kind == "manager" then
		if key == "TARGET_LIMB" then
			limbData.targetLimbName = value
		end
		local prevId = beginElevated()
		pcall(self._manager.Set, self._manager, meta.manager, s[key])
		if key == "ALT_RESET_LIMB_ON_DEATH" and not s[key] and next(self._deadTargets) ~= nil then
			local revived = {}
			for char in pairs(self._deadTargets) do
				revived[#revived + 1] = char
			end
			table_clear(self._deadTargets)
			if self._running then
				for i = 1, #revived do
					local char = revived[i]
					if self._trackedTargets[char] ~= nil and char.Parent then
						self:_attachVisuals(char)
					end
				end
			end
		end
		endElevated(prevId)
		return
	elseif kind == "dynamic" then
		if key == "DYNAMIC_SCALE_RANGE_MULT" then
			local mult = tonumber(value) or 1.0
			s[key] = mult
			if s.DYNAMIC_SCALE_ENABLED then
				for _, entry in pairs(self._playerCache) do
					recalcEntryDistFields(entry, mult)
				end
				self._nextDynamicUpdate = self._dynamicInterval
			end
		elseif key == "DYNAMIC_SCALE_UPDATE_RATE" then
			self._dynamicInterval = resolveUpdateInterval(value)
		end
		return
	elseif kind == "esp" then
		self._dirtyESP = true
	elseif kind == "chams" then
		self._dirtyCHAMS = true
	else
		self._dirtyCosmetic = true
	end

	self:_scheduleDirtyWork()
end

function LimbExtender:Get(key)
	local val = self._settings[key]
	return type(val) == "table" and cloneDeep(val) or val
end

function LimbExtender:AddDirectory(dir)
	if self._destroyed then return end
	local prevId = beginElevated()
	pcall(self._manager.AddDirectory, self._manager, dir)
	self:_syncDirectoriesFromManager()
	endElevated(prevId)
end

function LimbExtender:RemoveDirectory(dir)
	if self._destroyed then return end
	local prevId = beginElevated()
	pcall(self._manager.RemoveDirectory, self._manager, dir)
	self:_syncDirectoriesFromManager()
	endElevated(prevId)
end

function LimbExtender:GetDirectories()
	if self._destroyed then return {} end
	local prevId = beginElevated()
	local ok, dirs = pcall(self._manager.GetDirectories, self._manager)
	endElevated(prevId)
	return (ok and type(dirs) == "table") and table_clone(dirs) or {}
end

function LimbExtender:RegisterPlayerCharacter(player, model)
	if self._destroyed then return end
	local prevId = beginElevated()
	pcall(self._manager.RegisterPlayerCharacter, self._manager, player, model)
	endElevated(prevId)
end

function LimbExtender:UnregisterPlayerCharacter(player, model)
	if self._destroyed then return end
	local prevId = beginElevated()
	pcall(self._manager.UnregisterPlayerCharacter, self._manager, player, model)
	endElevated(prevId)
end

function LimbExtender:Destroy()
	if self._destroyed then return end
	self:Stop()
	self._destroyed = true

	local prevId = beginElevated()
	if type(self._customDestroy) == "function" then
		pcall(self._customDestroy, self)
	end
	if self._mgrRefConn then
		self._mgrRefConn:Disconnect()
		self._mgrRefConn = nil
	end
	if self._fallbackRefBindable then
		self._fallbackRefBindable:Destroy()
		self._fallbackRefBindable = nil
	end
	self.ReferenceCharacterChanged = nil

	if self._CHAMS and self._chamsActive and type(self._CHAMS.removeSource) == "function" then
		pcall(self._CHAMS.removeSource, self._chamsSourceKey)
	end
	self._cachedChamsConfig = nil
	self._CHAMS             = nil
	self._chamsActive       = false

	if self._ESP then
		pcall(self._ESP.Destroy, self._ESP)
		self._ESP = nil
	end

	if self._manager then
		if type(self._manager.Destroy) == "function" then
			pcall(self._manager.Destroy, self._manager)
		end
		self._manager = nil
	end

	if limbData.playerCache == self._playerCache then
		limbData.playerCache    = nil
		limbData.targetLimbName = nil
	end
	if limbData.terminate == self._terminateFn then
		limbData.terminate = nil
	end
	endElevated(prevId)
end

return setmetatable(LimbExtender, {
	__call = function(_, userSettings)
		return LimbExtender.new(userSettings)
	end,
})
