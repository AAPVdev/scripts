local function missing(t, f, fallback)
	if type(f) == t then return f end
	return fallback
end

local cloneref = missing("function", cloneref, function(obj) return obj end)

local Players = cloneref(game:GetService("Players"))
local localPlayer = Players.LocalPlayer

local globalEnv = type(getgenv) == "function" and getgenv() or _G
local limbData = globalEnv.limbExtenderData or {}
globalEnv.limbExtenderData = limbData

local type, typeof = type, typeof
local pcall = pcall
local pairs, ipairs = pairs, ipairs
local math_min = math.min
local task_spawn = task.spawn
local task_wait = task.wait
local table_clear = table.clear
local table_insert = table.insert
local table_clone = table.clone
local Vector3_new = Vector3.new

limbData.playerCache    = limbData.playerCache    or {}
limbData.instanceLookup = limbData.instanceLookup or setmetatable({}, { __mode = "k" })
limbData.npcIdCounter   = limbData.npcIdCounter   or 0
limbData.limbBlocked    = limbData.limbBlocked    or setmetatable({}, { __mode = "k" })
limbData.chamsIdCounter = limbData.chamsIdCounter or 0

if type(limbData.terminate) == "function" then
	limbData.terminate()
	limbData.terminate = nil
end

local has_loadstring = type(loadstring) == "function"
local has_httpget = pcall(function()
	local f = game.HttpGet
	if type(f) ~= "function" then error("not callable") end
end)

local BLOCKED_PROPS = {
	Size = true, Transparency = true, CanCollide = true, Massless = true,
	Mass = true, AssemblyMass = true, AssemblyCenterOfMass = true,
	RootPriority = true,
}

local ORIGINAL_FIELDS = {}
for prop in pairs(BLOCKED_PROPS) do
	ORIGINAL_FIELDS[prop] = "Original" .. prop
end

local ESP_SOURCE_URLS = {
	"https://raw.githubusercontent.com/AAPVdev/scripts/refs/heads/main/esp/SIXSEVENESP.lua",
	"https://api.rubis.app/v2/scrap/qghKmrRhRUfwDnee/raw",
}

local CHAMS_SOURCE_URLS = {
	"https://raw.githubusercontent.com/AAPVdev/scripts/refs/heads/main/esp/chams.lua",
}

local MANAGER_SOURCE_URLS = {
	"https://raw.githubusercontent.com/AAPVdev/scripts/refs/heads/main/manager/manager.lua",
	"https://api.rubis.app/v2/scrap/rNPKyva99IGbf6tH/raw"
}

local GAME_SCRIPT_URLS = {
	[1054526971] = {
		"https://raw.githubusercontent.com/AAPVdev/scripts/refs/heads/main/games/brm5.lua",
	},
}

local function fetchSingle(url)
	local ok, result = pcall(game.HttpGet, game, url)
	if ok and result and result ~= "" then
		return result
	end
	return nil
end

local function tryLoadModuleFromURLs(urlList)
	for _, url in ipairs(urlList) do
		local source = fetchSingle(url)
		if source then
			local fn, err = loadstring(source)
			if fn then
				local ok, mod = pcall(fn)
				if ok and mod then
					return mod
				end
			end
		end
	end
	return nil
end

local function tryLoadCustomScriptFromURLs(urlList, self)
	for _, url in ipairs(urlList) do
		local source = fetchSingle(url)
		if source then
			local fn, err = loadstring(source)
			if fn then
				local success, result = pcall(fn, self)
				if success then
					return result
				end
			end
		end
	end
	return nil
end

local function ensureESPLoaded()
	if limbData.ESP then return limbData.ESP end
	if not (has_loadstring and has_httpget) then return nil end
	local mod = tryLoadModuleFromURLs(ESP_SOURCE_URLS)
	if mod then limbData.ESP = mod end
	return limbData.ESP
end

local function ensureCHAMSLoaded()
	if limbData.CHAMS then return limbData.CHAMS end
	if not (has_loadstring and has_httpget) then return nil end
	local mod = tryLoadModuleFromURLs(CHAMS_SOURCE_URLS)
	if mod then limbData.CHAMS = mod end
	return limbData.CHAMS
end

local function ensureMANAGERLoaded()
	if limbData.manager then return limbData.manager end
	if not (has_loadstring and has_httpget) then return nil end
	local mod = tryLoadModuleFromURLs(MANAGER_SOURCE_URLS)
	if mod then limbData.manager = mod end
	return limbData.manager
end

local RESTART_KEYS = {
	PLAYER_ENABLED          = true,
	NPC_ENABLED             = true,
	NPC_FILTER              = true,
	TARGET_LIMB             = true,
	TEAM_CHECK              = true,
	FORCEFIELD_CHECK        = true,
	ALT_RESET_LIMB_ON_DEATH = true,
	NPC_DIRECTORIES         = true,
}

local function applyToggles(s, flags)
	return {
		Box      = s.ESP_BOX      and flags.Box,
		Box3D    = s.ESP_BOX3D    and flags.Box3D,
		Tracer   = s.ESP_TRACER   and flags.Tracer,
		Skeleton = s.ESP_SKELETON and flags.Skeleton,
		Health   = s.ESP_HEALTH   and flags.Health,
		Label    = s.ESP_LABEL    and flags.Label,
	}
end

local function buildLimbProps(limb, entry, settings)
	local newVec = Vector3_new(settings.LIMB_SIZE, settings.LIMB_SIZE, settings.LIMB_SIZE)
	local isHRP  = limb.Name == "HumanoidRootPart"
	local props  = {
		Size         = newVec,
		Transparency = settings.LIMB_TRANSPARENCY,
		CanCollide   = settings.LIMB_CAN_COLLIDE,
		Massless     = not isHRP,
	}
	if isHRP then
		props.Massless = false
	else
		props.RootPriority = -127
	end
	return props, newVec, isHRP
end

local hooksInstalled = false

local has_checkcaller, has_getnamecallmethod, has_getconnections = false, false, false
local has_hookmetamethod, has_newcclosure, has_getrawmetatable, has_setreadonly = false, false, false, false
local has_debug_upvalues, has_debug_setupvalue, has_newproxy = false, false, false

do
	local function check(name)
		local ok, fn = pcall(function() return loadstring("return " .. name)() end)
		return ok and type(fn) == "function"
	end
	has_checkcaller = check("checkcaller")
	has_getnamecallmethod = check("getnamecallmethod")
	has_getconnections = check("getconnections")
	has_hookmetamethod = check("hookmetamethod")
	has_newcclosure = check("newcclosure")
	has_getrawmetatable = check("getrawmetatable")
	has_setreadonly = check("setreadonly")
	has_debug_upvalues = check("debug.getupvalues")
	has_debug_setupvalue = check("debug.setupvalue")
	has_newproxy = check("newproxy")
end

if has_checkcaller and ((has_hookmetamethod and has_newcclosure) or (has_getrawmetatable and has_setreadonly)) and not hooksInstalled then

	local blockedProps = BLOCKED_PROPS
	local blockedPropsOriginal = BLOCKED_PROPS
	local instanceLookup = limbData.instanceLookup
	local limbBlocked = limbData.limbBlocked
	local Instance_new = Instance.new
	local getnamecallmethod = has_getnamecallmethod and getnamecallmethod or nil
	local getconnections = has_getconnections and getconnections or nil

	local originalIndex, originalNewIndex, originalNamecall

	local function hookedIndex(...)
		local self, key = ...
		if not limbBlocked[self] then return originalIndex(...) end
		if not checkcaller() then
			local cached = instanceLookup[self]
			local data = cached and cached.data
			if data then
				local orig = ORIGINAL_FIELDS[key]
				if orig then
					return data[orig]
				end
				if key == "Changed" and data._customSignals then
					return data._customSignals.Changed
				end
			end
		end
		return originalIndex(...)
	end

	local function hookedNewIndex(...)
		local self, key, value = ...
		if not limbBlocked[self] then return originalNewIndex(...) end
		if not checkcaller() then
			local cached = instanceLookup[self]
			local data = cached and cached.data
			if data then
				local orig = ORIGINAL_FIELDS[key]
				if orig then
					data[orig] = value
					local real = data._realSignals
					if real then
						local sig = real[key]
						if sig then
							sig:Fire(value)
						end
						local changed = real.Changed
						if changed then
							changed:Fire(key, value)
						end
					end
					return
				end
			end
		end
		return originalNewIndex(...)
	end

	local function hookedNamecall(...)
		local self, prop = ...
		if not limbBlocked[self] then return originalNamecall(...) end
		if not checkcaller() then
			local method = getnamecallmethod()
			if method == "GetPropertyChangedSignal" then
				local cached = instanceLookup[self]
				local data = cached and cached.data
				if data and ORIGINAL_FIELDS[prop] then
					local custom = data._customSignals
					if custom and custom[prop] then
						return custom[prop]
					end
				end
			end
		end
		return originalNamecall(...)
	end

	local function scrubUpvalues(fn)
		if not (has_debug_upvalues and has_debug_setupvalue and has_newproxy) then return end
		if type(fn) ~= "function" then return end
		local upvals = debug.getupvalues(fn)
		for i, val in ipairs(upvals) do
			if type(val) == "table" and val ~= blockedPropsOriginal then
				local proxy = newproxy(true)
				local proxyMt = getmetatable(proxy)
				proxyMt.__index = val
				proxyMt.__newindex = function(_, k, v) val[k] = v return end
				proxyMt.__pairs = function() return pairs(val) end
				local valMt = getmetatable(val)
				if valMt and valMt.__call then
					proxyMt.__call = function(_, ...) return val(...) end
				end
				debug.setupvalue(fn, i, proxy)
			end
		end
	end

	local function isNewcclosureDetected()
		if not (has_hookmetamethod and has_newcclosure) then
			return nil
		end

		local function probeInSpawn()
			local result = nil
			local done = false
			task.spawn(function()
				local capturedFunction = nil
				xpcall(function()
					return game.AAAAAAA
				end, function()
					capturedFunction = debug.info(2, "f")
				end)

				local overflow = false
				if capturedFunction then
					local recursiveCaller
					recursiveCaller = function(depth)
						if depth < 19995 then
							recursiveCaller(depth + 1)
						else
							capturedFunction(workspace, "Name")
						end
					end
					local ok, err = pcall(recursiveCaller, 1)
					overflow = not ok and type(err) == "string" and err:find("stack overflow")
				else
					overflow = true
				end

				result = { captured = capturedFunction, overflow = overflow }
				done = true
			end)
			repeat task.wait() until done
			return result
		end

		local base = probeInSpawn()
		if base.overflow then
			return false
		end

		local orig
		orig = hookmetamethod(game, "__index", newcclosure(function(...)
			return orig(...)
		end))
		local hookProbe = probeInSpawn()
		hookmetamethod(game, "__index", orig)

		if hookProbe.overflow then
			return true
		else
			return false
		end
	end

	local useNewcclosure = true
	if has_hookmetamethod and has_newcclosure then
		local detected = isNewcclosureDetected()
		useNewcclosure = (detected == false)
	end

	if true then
		local idx = newcclosure(hookedIndex)
		local nidx = newcclosure(hookedNewIndex)
		local nm = has_getnamecallmethod and newcclosure(hookedNamecall) or nil

		originalIndex    = hookmetamethod(game, "__index",    idx)
		originalNewIndex = hookmetamethod(game, "__newindex", nidx)
		if nm then
			originalNamecall = hookmetamethod(game, "__namecall", nm)
		end

		hooksInstalled = true
	elseif has_getrawmetatable and has_setreadonly then
		local mt = getrawmetatable(game)
		setreadonly(mt, false)

		originalIndex    = mt.__index
		originalNewIndex = mt.__newindex
		mt.__index = hookedIndex
		mt.__newindex = hookedNewIndex

		if has_getnamecallmethod then
			originalNamecall = mt.__namecall
			mt.__namecall = hookedNamecall
		end

		setreadonly(mt, true)

		scrubUpvalues(hookedIndex)
		scrubUpvalues(hookedNewIndex)
		if has_getnamecallmethod then
			scrubUpvalues(hookedNamecall)
		end
		scrubUpvalues(getData)

		hooksInstalled = true
	end

	if has_getconnections then
		local createCustomSignals
		createCustomSignals = function(limb)
			local cached = instanceLookup[limb]
			local data = cached and cached.data
			if not data or data._customSignals then return end

			local custom = {}
			local real = {}

			real.Changed = Instance_new("BindableEvent")
			custom.Changed = real.Changed.Event

			for prop, _ in pairs(blockedPropsOriginal) do
				real[prop] = Instance_new("BindableEvent")
				custom[prop] = real[prop].Event
			end

			data._customSignals = custom
			data._realSignals = real

			local function migrateSignal(realSignal, newSignal)
				local connections = getconnections(realSignal)
				for _, conn in ipairs(connections) do
					local func = conn.Function
					if func then
						newSignal:Connect(func)
					end
					conn:Disable()
				end
			end

			migrateSignal(limb.Changed, custom.Changed)

			for prop, _ in pairs(blockedPropsOriginal) do
				local ok, sig = pcall(limb.GetPropertyChangedSignal, limb, prop)
				if ok and sig then
					migrateSignal(sig, custom[prop])
				end
			end

			limbBlocked[limb] = true
		end

		limbData._createCustomSignals = createCustomSignals
	end
end

local function createCustomSignals(limb)
	if limbData._createCustomSignals then
		limbData._createCustomSignals(limb)
	end
end

local function removeCustomSignals(limb)
	limbData.limbBlocked[limb] = nil
end

local PROPS_TO_WATCH = {
	{ "Size",                     "TargetSize" },
	{ "Transparency",             "TargetTransparency" },
	{ "CanCollide",               "TargetCanCollide" },
	{ "Massless",                 "TargetMassless" },
	{ "RootPriority",             "TargetRootPriority" },
}

local function setupLimbWatchdog(entry, limb, settings)
	if not entry or not limb then return end

	if entry._watchConns then
		for _, conn in ipairs(entry._watchConns) do
			conn:Disconnect()
		end
		entry._watchConns = nil
	end
	entry._watchConns = {}

	for _, pair in ipairs(PROPS_TO_WATCH) do
		local propName, targetField = pair[1], pair[2]
		local target = entry[targetField]
		if target ~= nil then
			local conn = limb:GetPropertyChangedSignal(propName):Connect(function()
				if entry._watchingRevert then return end
				local current = limb[propName]
				if current ~= target then
					entry._watchingRevert = true
					limb[propName] = target
					entry._watchingRevert = false
				end
			end)
			table_insert(entry._watchConns, conn)
		end
	end
end

local LimbExtender = {}
LimbExtender.__index = LimbExtender

local function nextChamsSourceKey()
	limbData.chamsIdCounter = limbData.chamsIdCounter + 1
	return "LimbExtender_" .. limbData.chamsIdCounter
end

local DEFAULTS = {
	TARGET_LIMB             	= "Head",
	LIMB_SIZE               	= 15,
	LIMB_TRANSPARENCY       	= 0.7,
	LIMB_CAN_COLLIDE        	= false,
	TEAM_CHECK              	= true,
	FORCEFIELD_CHECK        	= false,
	ALT_RESET_LIMB_ON_DEATH 	= false,
	PLAYER_ENABLED          	= true,
	NPC_ENABLED             	= true,
	NPC_FILTER              	= nil,
	NPC_DIRECTORIES         	= {},
	CUSTOM_CHARACTER_SYSTEM   	= false,
	GET_PLAYER_FROM_CHARACTER 	= nil,
	ESP                     	= true,
	ESP_COLOR               	= Color3.fromRGB(255, 50, 50),
	ESP_BOX3D_COLOR         	= Color3.fromRGB(255, 50, 50),
	ESP_HEALTH_COLOR        	= Color3.fromRGB(9, 255, 0),
	ESP_EMPTY_COLOR         	= Color3.fromRGB(255, 0, 0),
	ESP_SKELETON_COLOR      	= Color3.fromRGB(255, 157, 0),
	ESP_TEXT_COLOR          	= Color3.fromRGB(255, 255, 255),
	ESP_TEXT_SIZE           	= 16,
	ESP_OFFSCREEN_POINT     	= true,
	ESP_FILTER_LOCAL        	= true,
	ESP_MAX_DISTANCE        	= 500,
	ESP_NEAR_DISTANCE       	= 100,
	ESP_MEDIUM_DISTANCE     	= 250,
	ESP_OCCLUSION           	= false,
	ESP_OCCLUSION_FREQUENCY 	= 4,
	ESP_BOX     				= true,
	ESP_BOX3D   				= false,
	ESP_TRACER   				= true,
	ESP_SKELETON 				= true,
	ESP_HEALTH   				= true,
	ESP_LABEL    				= true,
	ESP_NEAR_FLAGS   			= { Box = true,  Tracer = true, Skeleton = true,  Health = true,  Label = true,  Box3D = false },
	ESP_MEDIUM_FLAGS 			= { Box = true,  Tracer = true, Skeleton = false, Health = true,  Label = true,  Box3D = false },
	ESP_FAR_FLAGS    			= { Box = true,  Tracer = true, Skeleton = false, Health = false, Label = false, Box3D = false },
	ESP_TEXT_RESOLVER 			= nil,
	ESP_CAN_DRAW      			= nil,
	ESP_TRACER_ORIGIN 			= nil,
	CHAMS                     	= false,
	CHAMS_FILL_COLOR          	= Color3.fromRGB(255, 255, 0),
	CHAMS_OUTLINE_COLOR       	= Color3.fromRGB(255, 255, 255),
	CHAMS_FILL_TRANSPARENCY   	= 0.5,
	CHAMS_OUTLINE_TRANSPARENCY	= 0.5,
	CHAMS_OCCLUSION 		  	= false,
	DYNAMIC_SCALE_ENABLED     	= true,
	DYNAMIC_SCALE_RANGE_MULT  	= 1.5,
	DYNAMIC_SCALE_UPDATE_RATE 	= 15,
}

local function mergeSettings(user)
	local s = table_clone(DEFAULTS)
	if type(user) ~= "table" then return s end
	for k, v in pairs(user) do
		if type(v) == "table" and type(s[k]) == "table" then
			s[k] = table_clone(v)
		else
			s[k] = v
		end
	end
	return s
end

local function sharedSaveData(parent, cacheKey, char, limb)
	local cache = parent._playerCache
	local entry = cache[cacheKey]
	if entry then
		if entry.Limb      and entry.Limb      ~= limb then limbData.instanceLookup[entry.Limb]      = nil end
		if entry.Character and entry.Character ~= char then limbData.instanceLookup[entry.Character] = nil end
	else
		entry = {}
		cache[cacheKey] = entry
	end
	entry.Character            = char
	entry.Limb                 = limb
	entry.OriginalSize         = limb.Size
	entry.OriginalTransparency = limb.Transparency
	entry.OriginalCanCollide   = limb.CanCollide
	entry.OriginalMassless     = limb.Massless
	entry.OriginalMass         = limb.Mass
	entry.OriginalAssemblyMass = limb.AssemblyMass
	entry.OriginalAssemblyCOM  = limb.AssemblyCenterOfMass
	entry.OriginalRootPriority = limb.RootPriority or 0
	if not entry.TrueSize    then entry.TrueSize    = entry.OriginalSize end
	limbData.instanceLookup[limb] = { data = entry, type = "Part" }
	limbData.instanceLookup[char] = { data = entry, type = "Model" }
end

local function applyEntryTargets(entry, props, newVec, isHRP, settings)
	entry.BaseTargetSize    = newVec
	entry.TargetSize         = newVec
	entry.TargetTransparency = settings.LIMB_TRANSPARENCY
	entry.TargetCanCollide   = settings.LIMB_CAN_COLLIDE
	entry.TargetMassless     = not isHRP
	if isHRP then
		entry.TargetRootPriority = nil
	else
		entry.TargetRootPriority = -127
	end
	local size = newVec
	local radius = math.max(size.X, size.Y, size.Z) / 2
	entry.LimbRadius = radius
	local rangeMult = settings.DYNAMIC_SCALE_RANGE_MULT or 1.0
	entry._maxDistSq = (radius * rangeMult + 5) ^ 2
	entry._minDistSq = (radius * 0.1) ^ 2
	local rangeSq = entry._maxDistSq - entry._minDistSq
	entry._rangeInvSq = (rangeSq > 0) and (1 / rangeSq) or 0
end

local function sharedApplyLimb(parent, cacheKey, char, limb)
	sharedSaveData(parent, cacheKey, char, limb)
	local entry = parent._playerCache[cacheKey]
	if not entry then return end
	if hooksInstalled then
		createCustomSignals(limb)
	end

	local props, newVec, isHRP = buildLimbProps(limb, entry, parent._settings)
	limb.Size         = props.Size
	limb.Transparency = props.Transparency
	limb.CanCollide   = props.CanCollide
	limb.Massless     = props.Massless
	if props.RootPriority ~= nil then
		limb.RootPriority = props.RootPriority
	end

	applyEntryTargets(entry, props, newVec, isHRP, parent._settings)

	setupLimbWatchdog(entry, limb, parent._settings)
end

local function sharedRestoreLimb(parent, cacheKey, activeLimb)
	local cache = parent._playerCache
	local entry = cache[cacheKey]
	if not entry then return end

	if entry._watchConns then
		for _, conn in ipairs(entry._watchConns) do
			conn:Disconnect()
		end
		entry._watchConns = nil
	end

	entry.TargetSize                     = nil
	entry.BaseTargetSize                 = nil
	entry.TargetTransparency             = nil
	entry.TargetCanCollide               = nil
	entry.TargetMassless                 = nil
	entry.TargetRootPriority             = nil
	entry.LimbRadius                     = nil
	entry._maxDistSq = nil
	entry._minDistSq = nil
	entry._rangeInvSq = nil

	if activeLimb and activeLimb.Parent then
		if entry._humanoidStateConn then entry._humanoidStateConn:Disconnect() end
		removeCustomSignals(activeLimb)
		activeLimb.Size         = entry.OriginalSize
		activeLimb.Transparency = entry.OriginalTransparency
		activeLimb.CanCollide   = entry.OriginalCanCollide
		activeLimb.Massless     = entry.OriginalMassless
		activeLimb.RootPriority = entry.OriginalRootPriority
	end

	if entry._realSignals then
		for _, be in pairs(entry._realSignals) do
			be:Destroy()
		end
		entry._realSignals = nil
	end

	if entry.Limb then limbData.instanceLookup[entry.Limb] = nil end
	if activeLimb and activeLimb ~= entry.Limb then limbData.instanceLookup[activeLimb] = nil end
	if entry.Character then limbData.instanceLookup[entry.Character] = nil end
	cache[cacheKey] = nil
end

local function reapplyCosmeticToEntry(entry, settings)
	local limb = entry.Limb

	if entry._watchConns then
		for _, conn in ipairs(entry._watchConns) do
			conn:Disconnect()
		end
		entry._watchConns = nil
	end

	local props, newVec, isHRP = buildLimbProps(limb, entry, settings)
	limb.Size         = props.Size
	limb.Transparency = props.Transparency
	limb.CanCollide   = props.CanCollide
	limb.Massless     = props.Massless
	if props.RootPriority ~= nil then
		limb.RootPriority = props.RootPriority
	end

	applyEntryTargets(entry, props, newVec, isHRP, settings)

	setupLimbWatchdog(entry, limb, settings)
end

function LimbExtender:_applyLimbs(player, char, limb)
	local cacheKey
	if player then
		cacheKey = player.Name
	else
		if not self._npcIdMap[char] then
			limbData.npcIdCounter  = limbData.npcIdCounter + 1
			self._npcIdMap[char]   = "__npc_" .. limbData.npcIdCounter
		end
		cacheKey = self._npcIdMap[char]
	end
	sharedApplyLimb(self, cacheKey, char, limb)
	if self._settings.ESP and self._ESP then
		local tracked = self._ESP:Track(char)
		if not tracked then
			task_spawn(function()
				local attempts = 0
				while not self._ESP:Track(char) and attempts < 30 do
					task_wait(0.1)
					attempts = attempts + 1
				end
			end)
		end
	end
	if self._settings.CHAMS and self._CHAMS then
		self._CHAMS.addHighlight(char, self._chamsSourceKey, self:_buildChamsConfig())
	end
end

function LimbExtender:_removeLimbs(player, char, limb)
	if self._suppressOnLimbLost then return end
	local cacheKey = player and player.Name or self._npcIdMap[char]
	sharedRestoreLimb(self, cacheKey, limb)
	if self._ESP and char then self._ESP:Untrack(char) end
	if self._CHAMS and char then self._CHAMS.removeHighlight(char, self._chamsSourceKey) end
	if not player then self._npcIdMap[char] = nil end
end

function LimbExtender:_processDirtyWork()
	self._workScheduled = false
	if not self._running then return end

	local s = self._settings

	if self._dirtyESP then
		self._dirtyESP = false
		if s.ESP then
			local espModule = ensureESPLoaded()
			if espModule then
				if not self._ESP then
					self._ESP = espModule.new(self:_buildESPConfig())
					if self._running then
						self._ESP:Start()
						for _, entry in pairs(self._playerCache) do
							if entry.Character then self._ESP:Track(entry.Character) end
						end
					end

				else
					self._ESP:SetOptions(self:_buildESPConfig())
				end
			else
				s.ESP = false
			end
		else
			if self._ESP then self._ESP:Destroy(); self._ESP = nil end
		end
	end

	if self._dirtyCHAMS then
		self._dirtyCHAMS = false
		if s.CHAMS then
			local chamsModule = ensureCHAMSLoaded()
			if chamsModule then
				self._CHAMS = chamsModule
				local config = self:_buildChamsConfig()
				for _, entry in pairs(self._playerCache) do
					if entry.Character then
						local updated = chamsModule.updateHighlight(entry.Character, self._chamsSourceKey, config)
						if not updated then
							chamsModule.addHighlight(entry.Character, self._chamsSourceKey, config)
						end
					end
				end
			else
				s.CHAMS = false
			end
		else
			if self._CHAMS then
				for _, entry in pairs(self._playerCache) do
					if entry.Character then
						self._CHAMS.removeHighlight(entry.Character, self._chamsSourceKey)
					end
				end
			end
		end
	end

	while self._dirtyRestart or self._dirtyCosmetic do
		if self._dirtyRestart and not self._restartLock then
			self._restartLock = true
			self._dirtyRestart = false
			self._dirtyCosmetic = false

			for key in pairs(RESTART_KEYS) do
				if s[key] ~= nil then
					if key == "ALT_RESET_LIMB_ON_DEATH" then
						self._manager:Set("DEATH_RESTORE", s[key])
					elseif key == "NPC_DIRECTORIES" then
						self._manager._settings.NPC_DIRECTORIES = s[key]
					else
						self._manager._settings[key] = s[key]
					end
				end
			end

			self:_doRestartBatched()
			self._restartLock = false
		elseif self._dirtyCosmetic then
			self._dirtyCosmetic = false
			self:_doCosmeticUpdateBatched()
		else
			task.wait()
		end
	end

	if self._dirtyRestart or self._dirtyCosmetic or self._dirtyESP or self._dirtyCHAMS then
		self._workScheduled = true
		task_spawn(function() self:_processDirtyWork() end)
	end
end

function LimbExtender:_doRestartBatched()
	if not self._running then return end
	self._suppressOnLimbLost = true
	self._manager:Stop()

	local cache = self._playerCache
	local keys = {}
	for k in pairs(cache) do table_insert(keys, k) end

	local BATCH = 10
	for i = 1, #keys, BATCH do
		if not self._running then break end
		local last = math_min(i + BATCH - 1, #keys)
		for j = i, last do
			local entry = cache[keys[j]]
			if entry and entry.Limb then
				sharedRestoreLimb(self, keys[j], entry.Limb)
				if self._ESP and entry.Character then
					self._ESP:Untrack(entry.Character)
				end
				if self._CHAMS and entry.Character then
					self._CHAMS.removeHighlight(entry.Character, self._chamsSourceKey)
				end
			elseif entry and entry.Character then
				limbData.instanceLookup[entry.Character] = nil
				if self._ESP then
					self._ESP:Untrack(entry.Character)
				end
				if self._CHAMS then
					self._CHAMS.removeHighlight(entry.Character, self._chamsSourceKey)
				end
				cache[keys[j]] = nil
			end
		end
		task_wait()
	end

	self._suppressOnLimbLost = false
	table_clear(cache)

	if self._ESP then self._ESP:Stop() end
	if not self._running then return end

	self._generation = self._generation + 1
	self._managerGeneration = self._generation
	self._manager:Start()
	if self._ESP then self._ESP:Start() end
	self:_runGameScriptIfNeeded()
end

function LimbExtender:_doCosmeticUpdateBatched()
	if not self._running then return end
	local s = self._settings
	local entries = {}
	for _, entry in pairs(self._playerCache) do
		if entry.Limb and entry.Character then
			table_insert(entries, entry)
		end
	end

	local BATCH = 10
	for i = 1, #entries, BATCH do
		if self._dirtyRestart or not self._running then return end
		local last = math_min(i + BATCH - 1, #entries)
		for j = i, last do
			reapplyCosmeticToEntry(entries[j], s)
		end
		task_wait()
	end
end

function LimbExtender:_runGameScriptIfNeeded()
	local currentId = game.GameId
	local urlList = GAME_SCRIPT_URLS[currentId]
	if not urlList then return end

	if self._customSetup then
		task_spawn(function()
			local success, result = pcall(self._customSetup)
		end)
		return
	end

	if self._gameScriptFetched then return end
	self._gameScriptFetched = true

	task_spawn(function()
		tryLoadCustomScriptFromURLs(urlList, self)
	end)
end

function LimbExtender:_reapplyWatchdogs()
	local s = self._settings
	for _, entry in pairs(self._playerCache) do
		if entry.Limb then
			setupLimbWatchdog(entry, entry.Limb, s)
		end
	end
end

local function recalcEntryDistFields(entry, rangeMult)
	if not entry.LimbRadius then return end
	local radius = entry.LimbRadius
	entry._maxDistSq = (radius * rangeMult + 5) ^ 2
	entry._minDistSq = (radius * 0.1) ^ 2
	local rangeSq = entry._maxDistSq - entry._minDistSq
	entry._rangeInvSq = (rangeSq > 0) and (1 / rangeSq) or 0
end

function LimbExtender:SetDynamicScale(enabled, rangeMult)
	local s = self._settings
	s.DYNAMIC_SCALE_ENABLED = enabled
	if rangeMult ~= nil then
		s.DYNAMIC_SCALE_RANGE_MULT = rangeMult
	end

	if self._dynamicScaleConn then
		self._dynamicScaleConn:Disconnect()
		self._dynamicScaleConn = nil
	end

	self._dynKeys = nil
	self._dynNextIndex = 1

	if enabled then
		self._nextDynamicUpdate = 0
		local interval = 1 / (s.DYNAMIC_SCALE_UPDATE_RATE or 15)
		self._dynamicScaleConn = game:GetService("RunService").Heartbeat:Connect(function(deltaTime)
			self._nextDynamicUpdate = self._nextDynamicUpdate + deltaTime
			if self._nextDynamicUpdate >= interval then
				self._nextDynamicUpdate = self._nextDynamicUpdate - interval
				self:_updateDynamicScales()
			end
		end)
		local currentRangeMult = s.DYNAMIC_SCALE_RANGE_MULT or 1.0
		for _, entry in pairs(self._playerCache) do
			recalcEntryDistFields(entry, currentRangeMult)
		end
	else
		for _, entry in pairs(self._playerCache) do
			if entry.Limb and entry.BaseTargetSize then
				entry.TargetSize = entry.BaseTargetSize
				entry.Limb.Size = entry.BaseTargetSize
			end
			entry._maxDistSq = nil
			entry._minDistSq = nil
			entry._rangeInvSq = nil
		end
	end

	self:_reapplyWatchdogs()
end

function LimbExtender:_updateSingleDynamicScale(entry, localPos)
	local limb = entry.Limb
	if not limb or not limb.Parent or not entry.OriginalSize or not entry.BaseTargetSize then return end
	local maxDistSq = entry._maxDistSq
	if not maxDistSq then return end

	local diff = limb.Position - localPos
	local sqDist = diff:Dot(diff)

	if sqDist > maxDistSq then
		if entry.TargetSize ~= entry.BaseTargetSize then
			entry.TargetSize = entry.BaseTargetSize
			entry._watchingRevert = true
			limb.Size = entry.BaseTargetSize
			entry._watchingRevert = false
		end
		return
	end

	local minDistSq = entry._minDistSq
	if minDistSq and maxDistSq == minDistSq then return end
	local rangeInvSq = entry._rangeInvSq
	if not rangeInvSq or rangeInvSq <= 0 then
		local dynamicSize = entry.BaseTargetSize
		if (limb.Size - dynamicSize):Dot(limb.Size - dynamicSize) > 0.0025 then
			entry.TargetSize = dynamicSize
			entry._watchingRevert = true
			limb.Size = dynamicSize
			entry._watchingRevert = false
		end
		return
	end

	local factor = math.sqrt(math.clamp((sqDist - minDistSq) * rangeInvSq, 0, 1))
	local dynamicSize = entry.OriginalSize:Lerp(entry.BaseTargetSize, factor)

	if (limb.Size - dynamicSize):Dot(limb.Size - dynamicSize) > 0.0025 then
		entry.TargetSize = dynamicSize
		entry._watchingRevert = true
		limb.Size = dynamicSize
		entry._watchingRevert = false
	end
end

function LimbExtender:_updateDynamicScales()
	if not self._running then return end
	local localHRP = self._localHRP
	if not localHRP then self:_updateLocalCharacter(); return end

	local localPos = localHRP.Position
	local cache = self._playerCache
	local batchSize = 20

	if not self._dynKeys then
		self._dynKeys = {}
		for k in pairs(cache) do
			table_insert(self._dynKeys, k)
		end
		self._dynNextIndex = 1
	end

	local processed = 0
	while processed < batchSize and self._dynNextIndex <= #self._dynKeys do
		local key = self._dynKeys[self._dynNextIndex]
		local entry = cache[key]
		if entry then
			self:_updateSingleDynamicScale(entry, localPos)
		end
		self._dynNextIndex = self._dynNextIndex + 1
		processed = processed + 1
	end

	if self._dynNextIndex > #self._dynKeys then
		self._dynKeys = nil
		self._dynNextIndex = 1
	end

	if processed == 0 then
		self._dynKeys = nil
		self._dynNextIndex = 1
	end
end

function LimbExtender:_updateLocalCharacter()
	local char = localPlayer.Character
	self._localChar = char
	if char then
		self._localHRP = char:FindFirstChild("HumanoidRootPart")
	else
		self._localHRP = nil
	end
end

function LimbExtender.new(userSettings)
	local self = setmetatable({
		_settings            = mergeSettings(userSettings),
		_playerCache         = limbData.playerCache,
		_manager             = nil,
		_ESP                 = nil,
		_CHAMS               = nil,
		_running             = false,
		_destroyed           = false,
		_npcIdMap            = {},
		_needsRestart        = false,
		_needsCosmeticUpdate = false,
		_workRunning         = false,
		_dirtyRestart        = false,
		_dirtyCosmetic       = false,
		_dirtyESP            = false,
		_dirtyCHAMS          = false,
		_suppressOnLimbLost  = false,
		_workScheduled       = false,
		_restartLock         = false,
		_generation          = 0,
		_managerGeneration   = 0,
		_gameScriptFetched   = false,
		_customSetup         = nil,
		_dynamicScaleConn    = nil,
		_nextDynamicUpdate   = 0,
		_localChar           = nil,
		_localHRP            = nil,
		_dynKeys             = nil,
		_dynNextIndex        = 1,
		_chamsSourceKey      = nextChamsSourceKey(),
	}, LimbExtender)

	limbData.targetLimbName = self._settings.TARGET_LIMB

	local managerModule = ensureMANAGERLoaded()
	if not managerModule then return false end

	local Manager = managerModule.Manager

	self._manager = Manager.new({
		PLAYER_ENABLED   = self._settings.PLAYER_ENABLED,
		NPC_ENABLED      = self._settings.NPC_ENABLED,
		NPC_FILTER       = self._settings.NPC_FILTER,
		NPC_DIRECTORIES  = self._settings.NPC_DIRECTORIES,
		TARGET_LIMB      = self._settings.TARGET_LIMB,
		TEAM_CHECK       = self._settings.TEAM_CHECK,
		FORCEFIELD_CHECK = self._settings.FORCEFIELD_CHECK,
		DEATH_RESTORE    = self._settings.ALT_RESET_LIMB_ON_DEATH,
		GET_LOCAL_TEAM   = function() return localPlayer.Team end,
		ON_LIMB_READY    = function(player, model, limb) self:_applyLimbs(player, model, limb) end,
		ON_LIMB_LOST     = function(player, model, limb)
			self:_removeLimbs(player, model, limb)
		end,
	})

	if self._settings.ESP then
		local espModule = ensureESPLoaded()
		if espModule then
			self._ESP = espModule.new(self:_buildESPConfig())
		else
			self._settings.ESP = false
		end
	end

	if self._settings.CHAMS then
		local chamsModule = ensureCHAMSLoaded()
		if chamsModule then
			self._CHAMS = chamsModule
		else
			self._settings.CHAMS = false
		end
	end

	self:_updateLocalCharacter()
	localPlayer:GetPropertyChangedSignal("Character"):Connect(function()
		self:_updateLocalCharacter()
	end)

	if self._settings.DYNAMIC_SCALE_ENABLED then
		self:SetDynamicScale(true)
	end

	limbData.terminate = function() self:Destroy() end
	return self
end

function LimbExtender:_buildESPConfig()
	local s = self._settings
	return {
		Color                = s.ESP_COLOR,
		Box3DColor           = s.ESP_BOX3D_COLOR,
		HealthColor          = s.ESP_HEALTH_COLOR,
		EmptyColor           = s.ESP_EMPTY_COLOR,
		SkeletonColor        = s.ESP_SKELETON_COLOR,
		TextColor            = s.ESP_TEXT_COLOR,
		TextSize             = s.ESP_TEXT_SIZE,
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
		TextResolver = s.ESP_TEXT_RESOLVER,
		CanDraw      = s.ESP_CAN_DRAW,
		TracerOrigin = s.ESP_TRACER_ORIGIN,
	}
end

function LimbExtender:_buildChamsConfig()
    local s = self._settings
    return {
        FillColor = s.CHAMS_FILL_COLOR,
        OutlineColor = s.CHAMS_OUTLINE_COLOR,
        FillTransparency = s.CHAMS_FILL_TRANSPARENCY,
        OutlineTransparency = s.CHAMS_OUTLINE_TRANSPARENCY,
        DepthMode = s.CHAMS_OCCLUSION and "AlwaysOnTop" or "Occluded",
    }
end

function LimbExtender:Start()
	if self._destroyed or self._running then return end
	self._running = true
	self._manager:Start()
	if self._ESP then self._ESP:Start() end

	if self._settings.DYNAMIC_SCALE_ENABLED and not self._dynamicScaleConn then
		self:SetDynamicScale(true)
	end

	self:_runGameScriptIfNeeded()

	if self._dirtyRestart or self._dirtyCosmetic or self._dirtyESP or self._dirtyCHAMS then
		self._workScheduled = true
		task_spawn(function() self:_processDirtyWork() end)
	end
end

function LimbExtender:Stop()
	if self._destroyed or not self._running then return end
	self._running             = false
	self._needsRestart        = false
	self._needsCosmeticUpdate = false

	if self._dynamicScaleConn then
		self._dynamicScaleConn:Disconnect()
		self._dynamicScaleConn = nil
	end

	self._dynKeys = nil
	self._dynNextIndex = 1

	self._manager:Stop()
	for cacheKey, entry in pairs(self._playerCache) do
		if self._CHAMS and entry.Character then
			self._CHAMS.removeHighlight(entry.Character, self._chamsSourceKey)
		end
		sharedRestoreLimb(self, cacheKey, entry.Limb)
	end
	table_clear(self._playerCache)
	if self._ESP then self._ESP:Stop() end
end

function LimbExtender:Toggle(state)
	if type(state) == "boolean" then
		if state then self:Start() else self:Stop() end
	else
		if self._running then self:Stop() else self:Start() end
	end
end

function LimbExtender:Restart()
	local wasRunning = self._running
	self:Stop()
	if wasRunning then self:Start() end
end

function LimbExtender:Set(key, value)
	local s = self._settings

	if key == "ESP_NEAR_FLAGS" or key == "ESP_MEDIUM_FLAGS" or key == "ESP_FAR_FLAGS" then
		if type(s[key]) ~= "table" then s[key] = {} end
		if type(value) == "table" then
			for k, v in pairs(value) do s[key][k] = v end
		else
			s[key] = value
		end
	else
		if s[key] == value then return end
		s[key] = value
	end

	if key == "GET_PLAYER_FROM_CHARACTER" or key == "CUSTOM_CHARACTER_SYSTEM" then
		if self._manager then
			self._manager:Set(key, value)
		end
		return
	end

	if key == "DYNAMIC_SCALE_ENABLED" then
		self:SetDynamicScale(value)
		return
	elseif key == "DYNAMIC_SCALE_RANGE_MULT" then
		s.DYNAMIC_SCALE_RANGE_MULT = value
		if s.DYNAMIC_SCALE_ENABLED then
			local rangeMult = value or 1.0
			for _, entry in pairs(self._playerCache) do
				recalcEntryDistFields(entry, rangeMult)
			end
		end
		return
	elseif key == "DYNAMIC_SCALE_UPDATE_RATE" then
		s.DYNAMIC_SCALE_UPDATE_RATE = value
		if s.DYNAMIC_SCALE_ENABLED then
			self:SetDynamicScale(true)
		end
		return
	end

	local isCHAMSKey = key == "CHAMS" or (type(key) == "string" and key:sub(1,6) == "CHAMS_")

	if RESTART_KEYS[key] then
		if key == "TARGET_LIMB" then limbData.targetLimbName = value end
		self._dirtyRestart = true
	elseif isCHAMSKey then
		self._dirtyCHAMS = true
	else
		self._dirtyCosmetic = true
	end

	if key == "ESP" or (type(key) == "string" and key:sub(1,4) == "ESP_") then
		self._dirtyESP = true
	end

	if self._running and not self._workScheduled then
		self._workScheduled = true
		task_spawn(function()
			self:_processDirtyWork()
		end)
	end
end

function LimbExtender:Get(key) return self._settings[key] end
function LimbExtender:AddDirectory(dir) self._manager:AddDirectory(dir) end
function LimbExtender:RemoveDirectory(dir) self._manager:RemoveDirectory(dir) end
function LimbExtender:GetDirectories() return self._manager:GetDirectories() end

function LimbExtender:RegisterPlayerCharacter(player, model)
	if self._manager then
		self._manager:RegisterPlayerCharacter(player, model)
	end
end

function LimbExtender:UnregisterPlayerCharacter(player, model)
	if self._manager then
		self._manager:UnregisterPlayerCharacter(player, model)
	end
end

function LimbExtender:Destroy()
	self:Stop()
	self._destroyed = true
	if self._CHAMS then
		for _, entry in pairs(self._playerCache) do
			if entry.Character then
				self._CHAMS.removeHighlight(entry.Character, self._chamsSourceKey)
			end
		end
	end
	if self._ESP then self._ESP:Destroy(); self._ESP = nil end
	limbData.terminate = nil
end

return setmetatable({}, {
	__call  = function(_, userSettings) return LimbExtender.new(userSettings) end,
	__index = LimbExtender,
})
