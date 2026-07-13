local function missing(t, f, fallback)
	if type(f) == t then return f end
	return fallback
end

local cloneref = missing("function", cloneref, function(obj) return obj end)

local Players = cloneref(game:GetService("Players"))
local localPlayer = Players.LocalPlayer
if not localPlayer then
	Players:GetPropertyChangedSignal("LocalPlayer"):Wait()
	localPlayer = Players.LocalPlayer
end

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
limbData._signalType = limbData._signalType or setmetatable({}, { __mode = "k" })
limbData._signalConnections = limbData._signalConnections or setmetatable({}, { __mode = "k" })
limbData.npcIdCounter   = limbData.npcIdCounter   or 0
limbData._hookedSignals = limbData._hookedSignals or setmetatable({}, { __mode = "k" })
limbData._signalToInstance = limbData._signalToInstance or setmetatable({}, { __mode = "k" })

if type(limbData.terminate) == "function" then
	limbData.terminate()
	limbData.terminate = nil
end

local has_loadstring = type(loadstring) == "function"
local has_httpget = pcall(function()
	local f = game.HttpGet
	if type(f) ~= "function" then error("not callable") end
end)

local BYPASS_AVAILABLE = false
do
	local required = {
		"getrawmetatable",
		"setreadonly",
		"newcclosure",
		"hookfunction",
		"getconnections",
		"checkcaller",
		"firesignal",
	}

	local ok = true
	for _, name in ipairs(required) do
		local fn = loadstring("return " .. name)()
		if type(fn) ~= "function" then
			ok = false
			break
		end
	end

	if ok then
		local success = pcall(function()
			local mt = getrawmetatable(game)
			if type(mt) ~= "table" then error("expected table") end
		end)
		if success then
			BYPASS_AVAILABLE = true
		end
	end
end

local BLOCKED_PROPS = {
	Size = true, Transparency = true, CanCollide = true, Massless = true,
	Mass = true, AssemblyMass = true, AssemblyCenterOfMass = true,
    RootPriority = true,
}

local firingProps = setmetatable({}, { __mode = "k" })

local ESP_SOURCE_URLS = {
	"https://api.rubis.app/v2/scrap/qghKmrRhRUfwDnee/raw",
}

local MANAGER_SOURCE_URLS = {
	"https://api.rubis.app/v2/scrap/rNPKyva99IGbf6tH/raw"
}

local GAME_SCRIPT_URLS = {
	[1054526971] = {
		"https://raw.githubusercontent.com/AAPVdev/scripts/refs/heads/main/games/brm5.lua",
	},
}

local function fetchWithFallback(urlList)
	if type(urlList) == "string" then
		urlList = { urlList }
	end
	for _, url in ipairs(urlList) do
		local ok, result = pcall(game.HttpGet, game, url)
		if ok and result then
			return result
		end
	end
	return nil
end

local function ensureESPLoaded()
	if limbData.ESP then return limbData.ESP end
	if not (has_loadstring and has_httpget) then return nil end
	local source = fetchWithFallback(ESP_SOURCE_URLS)
	if not source then return nil end
	local ok, res = pcall(function() return loadstring(source)() end)
	if ok then limbData.ESP = res end
	return limbData.ESP
end

local function ensureMANAGERLoaded()
	if limbData.manager then return limbData.manager end
	if not (has_loadstring and has_httpget) then return nil end
	local source = fetchWithFallback(MANAGER_SOURCE_URLS)
	if not source then return nil end
	local ok, res = pcall(function() return loadstring(source)() end)
	if ok then limbData.manager = res end
	return limbData.manager
end

local function fireSignalsForProp(limb, prop)
	if firingProps[limb] then return end
	firingProps[limb] = true

    local changedSig = limb.Changed
    local changedConns = limbData._signalConnections[changedSig]
    if changedConns then
        for _, entry in ipairs(changedConns) do
            entry.connection:Fire(prop)
        end
    end

    local propSig = limb:GetPropertyChangedSignal(prop)
    local propConns = limbData._signalConnections[propSig]
    if propConns then
        for _, entry in ipairs(propConns) do
            entry.connection:Fire()
        end
    end

    firingProps[limb] = nil
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

local function write(limb, props)
	for k, v in pairs(props) do
		limb[k] = v
	end
end

function getTargetData(instance)
	if typeof(instance) ~= "Instance" then return nil, nil end
	local cached = limbData.instanceLookup[instance]
	if cached then return cached.data, cached.type end
	return nil, nil
end

local function wrapPartSignals(limb)
    if not BYPASS_AVAILABLE then return end

	local function hookSignalConnect(signal, signalKey)
	    limbData._signalConnections[signal] = {}
	    local connections = getconnections(signal)
	    for _, conn in ipairs(connections) do
	        pcall(function() conn:Disable() end)
	        table.insert(limbData._signalConnections[signal], {
	            connection = conn,
	            signalType = signalKey
	        })
	    end
	end

	hookSignalConnect(limb.Changed, "Changed")
	limbData._signalType[limb.Changed] = true

	for prop, _ in pairs(BLOCKED_PROPS) do
	    local ok, sig = pcall(limb.GetPropertyChangedSignal, limb, prop)
	    if ok and sig then
	        hookSignalConnect(sig, prop)
	    end
	end
end

if BYPASS_AVAILABLE and not limbData._bypassInstalled then
	limbData._bypassInstalled = true
	local mt          = getrawmetatable(game)
	local oldIndex    = mt.__index
	local oldNewIndex = mt.__newindex
	local oldNamecall = mt.__namecall
	setreadonly(mt, false)

	mt.__index = function(self, key)
		if not checkcaller() then
			local data = getTargetData(self)
			if data then
				if BLOCKED_PROPS[key] then
					return data["Original"..key]
				end
			end
		end
		return oldIndex(self, key)
	end

	mt.__newindex = function(self, key, value)
		if not checkcaller() then
			local data = getTargetData(self)
			if data then
				if BLOCKED_PROPS[key] then
					data["Original"..key] = value
					fireSignalsForProp(self, key)
					return
				end
			end
		end
		return oldNewIndex(self, key, value)
	end

	mt.__namecall = function(self, ...)
		if not checkcaller() then
			local lookup = limbData.instanceLookup[self]
			local method = getnamecallmethod()
			if method == "GetPropertyChangedSignal" then
			    local propertyName = ...
			    local signal = oldNamecall(self, ...)
			    if lookup and BLOCKED_PROPS[propertyName] then
			        limbData._signalToInstance[signal] = self
			        limbData._hookedSignals[signal] = true
			        limbData._signalType[signal] = propertyName
			    end
			    return signal
			end
		end
		return oldNamecall(self, ...)
	end
	setreadonly(mt, true)

	if not limbData._signalIndexHooked then
		limbData._signalIndexHooked = true
		local testSignal = game.Changed
		local signalMt = getrawmetatable(testSignal)
		local origSignalIndex = signalMt.__index

		local inSignalHook = false

		setreadonly(signalMt, false)
		signalMt.__index = function(self, key)

			if inSignalHook then
				return origSignalIndex(self, key)
			end

			if not checkcaller() then
				local instance = limbData._signalToInstance[self]
				local isTracked = limbData._hookedSignals[self] or (instance and limbData.instanceLookup[instance])

				if (key == "Connect" or key == "Once") and isTracked then
					local origMethod = origSignalIndex(self, key)

					return function(s, callback)

						local conn = origMethod(s, callback)

						inSignalHook = true
						local connections = getconnections(s)
						for _, c in ipairs(connections) do
							if c.Function == callback then
							    c:Disable()

							    if not limbData._signalConnections[s] then
							        limbData._signalConnections[s] = {}
							    end
							    table.insert(limbData._signalConnections[s], {
							        connection = c,
							        signalType = limbData._signalType[s]
							    })
							    break
							end
						end
						inSignalHook = false

						return conn
					end
				end
			end

			return origSignalIndex(self, key)
		end
		setreadonly(signalMt, true)
	end
end

local PROPS_TO_WATCH = {
	{ "Size",                     "TargetSize" },
	{ "Transparency",             "TargetTransparency" },
	{ "CanCollide",               "TargetCanCollide" },
	{ "Massless",                 "TargetMassless" },
	{ "RootPriority",             "TargetRootPriority" },
}

local function setupLimbWatchdog(entry, limb)
	if BYPASS_AVAILABLE then return end
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

local DEFAULTS = {
	TARGET_LIMB             = "Head",
	LIMB_SIZE               = 15,
	LIMB_TRANSPARENCY       = 0.7,
	LIMB_CAN_COLLIDE        = false,
	TEAM_CHECK              = true,
	FORCEFIELD_CHECK        = false,
	ALT_RESET_LIMB_ON_DEATH = false,
	PLAYER_ENABLED          = true,
	NPC_ENABLED             = true,
	NPC_FILTER              = nil,
	NPC_DIRECTORIES         = {},
	CUSTOM_CHARACTER_SYSTEM   = false,
	GET_PLAYER_FROM_CHARACTER = nil,
	ESP                     = false,
	ESP_COLOR               = Color3.fromRGB(255, 50, 50),
	ESP_BOX3D_COLOR         = Color3.fromRGB(255, 50, 50),
	ESP_HEALTH_COLOR        = Color3.fromRGB(9, 255, 0),
	ESP_EMPTY_COLOR         = Color3.fromRGB(255, 0, 0),
	ESP_SKELETON_COLOR      = Color3.fromRGB(255, 157, 0),
	ESP_TEXT_COLOR          = Color3.fromRGB(255, 255, 255),
	ESP_TEXT_SIZE           = 16,
	ESP_OFFSCREEN_POINT     = true,
	ESP_FILTER_LOCAL        = true,
	ESP_MAX_DISTANCE        = 500,
	ESP_NEAR_DISTANCE       = 100,
	ESP_MEDIUM_DISTANCE     = 250,
	ESP_OCCLUSION           = false,
	ESP_OCCLUSION_FREQUENCY = 4,
	ESP_BOX      = true,
	ESP_BOX3D    = false,
	ESP_TRACER   = true,
	ESP_SKELETON = true,
	ESP_HEALTH   = true,
	ESP_LABEL    = true,
	ESP_NEAR_FLAGS   = { Box = true,  Tracer = true, Skeleton = true,  Health = true,  Label = true,  Box3D = false },
	ESP_MEDIUM_FLAGS = { Box = true,  Tracer = true, Skeleton = false, Health = true,  Label = true,  Box3D = false },
	ESP_FAR_FLAGS    = { Box = true,  Tracer = true, Skeleton = false, Health = false, Label = false, Box3D = false },
	ESP_TEXT_RESOLVER = nil,
	ESP_CAN_DRAW      = nil,
	ESP_TRACER_ORIGIN = nil,
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
	local extents              = char:GetExtentsSize()
	entry.Character            = char
	entry.Limb                 = limb
	entry.OriginalSize         = limb.Size
	entry.OriginalTransparency = limb.Transparency
	entry.OriginalCanCollide   = limb.CanCollide
	entry.OriginalMassless     = limb.Massless
	entry.OriginalMass         = limb.Mass
	entry.OriginalAssemblyMass = limb.AssemblyMass
	entry.OriginalAssemblyCOM  = limb.AssemblyCenterOfMass
	entry.OriginalExtents      = extents
	entry.OriginalRootPriority = limb.RootPriority or 0
	if not entry.TrueSize    then entry.TrueSize    = entry.OriginalSize end
	if not entry.TrueExtents then entry.TrueExtents = extents end
	limbData.instanceLookup[limb] = { data = entry, type = "Part" }
	limbData.instanceLookup[char] = { data = entry, type = "Model" }
end

local function applyEntryTargets(entry, props, newVec, isHRP, settings)
	entry.TargetSize         = newVec
	entry.TargetTransparency = settings.LIMB_TRANSPARENCY
	entry.TargetCanCollide   = settings.LIMB_CAN_COLLIDE
	entry.TargetMassless     = not isHRP
	if isHRP then
		entry.TargetRootPriority             = nil
	else
		entry.TargetRootPriority             = -127
	end
end

local function sharedApplyLimb(parent, cacheKey, char, limb)
	sharedSaveData(parent, cacheKey, char, limb)
	local entry = parent._playerCache[cacheKey]
	if not entry then return end
	wrapPartSignals(limb)

	local props, newVec, isHRP = buildLimbProps(limb, entry, parent._settings)
	write(limb, props)
	applyEntryTargets(entry, props, newVec, isHRP, parent._settings)

	setupLimbWatchdog(entry, limb)
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
	entry.TargetTransparency             = nil
	entry.TargetCanCollide               = nil
	entry.TargetMassless                 = nil
	entry.TargetRootPriority             = nil

	if activeLimb and activeLimb.Parent then
		if entry._humanoidStateConn then entry._humanoidStateConn:Disconnect() end
		pcall(write, activeLimb, {
			Size                     = entry.OriginalSize,
			Transparency             = entry.OriginalTransparency,
			CanCollide               = entry.OriginalCanCollide,
			Massless                 = entry.OriginalMassless,
			RootPriority             = entry.OriginalRootPriority,
		})
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
    write(limb, props)
    applyEntryTargets(entry, props, newVec, isHRP, settings)

    setupLimbWatchdog(entry, limb)
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
end

function LimbExtender:_removeLimbs(player, char, limb)
	if self._suppressOnLimbLost then return end
	local cacheKey = player and player.Name or self._npcIdMap[char]
	sharedRestoreLimb(self, cacheKey, limb)
	if self._ESP and char then self._ESP:Untrack(char) end
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

			local ok, err = pcall(self._doRestartBatched, self)
			if not ok then
				warn("[LimbExtender] Restart error: " .. tostring(err))
			end
			self._restartLock = false
		elseif self._dirtyCosmetic then
			self._dirtyCosmetic = false
			self:_doCosmeticUpdateBatched()
		else
			task.wait()
		end
	end

	if self._dirtyRestart or self._dirtyCosmetic or self._dirtyESP then
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

	local BATCH = 6
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
			elseif entry and entry.Character then
				limbData.instanceLookup[entry.Character] = nil
				if self._ESP then
					self._ESP:Untrack(entry.Character)
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

	local BATCH = 5
	local keys = {}
	for k in pairs(self._playerCache) do keys[#keys+1] = k end
	for i = 1, #keys, BATCH do
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
			if not success then
				warn("[LimbExtender] Custom setup error: " .. tostring(result))
			end
		end)
		return
	end

	if self._gameScriptFetched then return end
	self._gameScriptFetched = true

	task_spawn(function()
		local source = fetchWithFallback(urlList)
		if not source then
			warn("[LimbExtender] Failed to fetch game script from all URLs for game ID " .. currentId)
			return
		end
		local fn, err = loadstring(source)
		if not fn then
			warn("[LimbExtender] Custom script compile error: " .. tostring(err))
			return
		end
		local success, result = pcall(fn, self)
		if not success then
			warn("[LimbExtender] Custom script runtime error: " .. tostring(result))
		end

		if not self._customSetup then
			warn("[LimbExtender] Custom script did not set _customSetup; it will not re-run on restarts.")
		end
	end)
end

function LimbExtender.new(userSettings)
	local self = setmetatable({
		_settings            = mergeSettings(userSettings),
		_playerCache         = limbData.playerCache,
		_manager             = nil,
		_ESP                 = nil,
		_running             = false,
		_destroyed           = false,
		_npcIdMap            = {},
		_needsRestart        = false,
		_needsCosmeticUpdate = false,
		_workRunning         = false,
		_dirtyRestart        = false,
		_dirtyCosmetic       = false,
		_dirtyESP            = false,
		_suppressOnLimbLost  = false,
		_workScheduled       = false,
		_restartLock 		 = false,
		_generation 		 = 0,
		_managerGeneration 	 = 0,
		_gameScriptFetched   = false,
		_customSetup         = nil,
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

function LimbExtender:Start()
	if self._destroyed or self._running then return end
	self._running = true
	self._manager:Start()
	if self._ESP then self._ESP:Start() end

	self:_runGameScriptIfNeeded()

	if self._dirtyRestart or self._dirtyCosmetic or self._dirtyESP then
		self._workScheduled = true
		task_spawn(function() self:_processDirtyWork() end)
	end
end

function LimbExtender:Stop()
	if self._destroyed or not self._running then return end
	self._running             = false
	self._needsRestart        = false
	self._needsCosmeticUpdate = false
	self._manager:Stop()
	for cacheKey, entry in pairs(self._playerCache) do
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

	if RESTART_KEYS[key] then
		if key == "TARGET_LIMB" then limbData.targetLimbName = value end
		self._dirtyRestart = true
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
	if self._ESP then self._ESP:Destroy(); self._ESP = nil end
	limbData.terminate = nil
end

return setmetatable({}, {
    __call  = function(_, userSettings) return LimbExtender.new(userSettings) end,
    __index = LimbExtender,
})
