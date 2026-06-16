local function missing(t, f, fallback)
	if type(f) == t then return f end
	return fallback
end

local cloneref = missing("function", cloneref, function(obj) return obj end)
local has_checkcaller = type(checkcaller) == "function"
local checkcaller = has_checkcaller and checkcaller or function() return true end

local Players = cloneref(game:GetService("Players"))
local localPlayer = Players.LocalPlayer
if not localPlayer then
	Players:GetPropertyChangedSignal("LocalPlayer"):Wait()
	localPlayer = Players.LocalPlayer
end

local globalEnv = type(getgenv) == "function" and getgenv() or _G
local limbData = globalEnv.limbExtenderData or {}
globalEnv.limbExtenderData = limbData

limbData.BaseModule = limbData.BaseModule or loadstring(game:HttpGet('https://raw.githubusercontent.com/AAPVdev/scripts/refs/heads/main/manager/manager.lua'))()

local BaseModule = limbData.BaseModule 
local Manager = BaseModule.Manager
local ConnectionManager = BaseModule.ConnectionManager
local isLiveInstance = BaseModule.isLiveInstance

local type, typeof = type, typeof
local pcall = pcall
local pairs, ipairs = pairs, ipairs
local setmetatable = setmetatable
local math_max = math.max
local task_spawn = task.spawn
local task_defer = task.defer
local task_wait = task.wait
local table_clear = table.clear
local table_insert = table.insert
local table_remove = table.remove
local table_clone = table.clone
local Instance_new = Instance.new
local Vector3_new = Vector3.new
local PhysProps_new = PhysicalProperties.new

local function _safeGet(obj, key) return obj[key] end
local function _disconnect(conn) conn:Disconnect() end

limbData.playerCache    = limbData.playerCache    or {}
limbData.instanceLookup = limbData.instanceLookup or setmetatable({}, { __mode = "k" })
limbData.npcIdCounter   = limbData.npcIdCounter   or 0
limbData.changedProxies = limbData.changedProxies or setmetatable({}, { __mode = "k" })

if not limbData.dummyEvent then
	limbData.dummyEvent = Instance_new("BindableEvent")
end

if type(limbData.terminate) == "function" then
	limbData.terminate()
	limbData.terminate = nil
end

local has_newcclosure    = type(newcclosure)    == "function"
local has_hookmetamethod = type(hookmetamethod) == "function"
local has_loadstring     = type(loadstring)     == "function"
local has_httpget = pcall(function()
	local f = game.HttpGet
	if type(f) ~= "function" then error("not callable") end
end)

local BLOCKED_PROPS = {
	Size = true,
	Transparency = true,
	CanCollide = true,
	Massless = true,
	Mass = true,
	AssemblyMass = true,
	AssemblyCenterOfMass = true,
	CustomPhysicalProperties = true,
	CurrentPhysicalProperties = true,
	RootPriority = true,
}

local CONN_KEYS = { "SizeConn", "TransConn", "CollConn", "PhysConn", "MasslessConn", "RootPriorityConn" }

if not limbData._spoofInstalled and has_newcclosure and has_hookmetamethod and has_checkcaller then
	limbData._spoofInstalled = true

	local _instanceLookup = limbData.instanceLookup
	local _playerCache    = limbData.playerCache

	local function getTargetData(instance)
		if typeof(instance) ~= "Instance" then return nil, nil end
		local cached = _instanceLookup[instance]
		if cached then return cached.data, cached.type end

		for _, cache in pairs(_playerCache) do
			if cache.Limb == instance then
				_instanceLookup[instance] = { data = cache, type = "Part" }
				return cache, "Part"
			elseif cache.Character == instance then
				_instanceLookup[instance] = { data = cache, type = "Model" }
				return cache, "Model"
			end
		end
		return nil, nil
	end

	local oldNewIndex
	oldNewIndex = hookmetamethod(game, "__newindex", newcclosure(function(...)
		local self, key, value = ...
		if not checkcaller() then
			local data, instType = getTargetData(self)
			if data and instType == "Part" then
				if key == "Size"                     then data.OriginalSize         = value return end
				if key == "Transparency"             then data.OriginalTransparency  = value return end
				if key == "CanCollide"               then data.OriginalCanCollide    = value return end
				if key == "Massless"                 then data.OriginalMassless      = value return end
				if key == "Mass" or key == "AssemblyMass" or key == "AssemblyCenterOfMass" or key == "CurrentPhysicalProperties" then return end
				if key == "CustomPhysicalProperties" then data.OriginalPhysProps     = value return end
				if key == "RootPriority"             then data.OriginalRootPriority  = value return end
			end
		end
		return oldNewIndex(...)
	end))

	local oldIndex
	oldIndex = hookmetamethod(game, "__index", newcclosure(function(...)
		local self, key = ...
		if not checkcaller() then
			local data, instType = getTargetData(self)
			if data then
				if instType == "Part" then
					if key == "Size"                     then return data.OriginalSize         end
					if key == "Transparency"             then return data.OriginalTransparency  end
					if key == "CanCollide"               then return data.OriginalCanCollide    end
					if key == "Massless"                 then return data.OriginalMassless      end
					if key == "Mass"                     then return data.OriginalMass          end
					if key == "AssemblyMass"             then return data.OriginalAssemblyMass  end
					if key == "AssemblyCenterOfMass"     then return data.OriginalAssemblyCOM   end
					if key == "CustomPhysicalProperties" then return data.OriginalPhysProps     end
					if key == "CurrentPhysicalProperties" then return data.OriginalPhysProps    end
					if key == "RootPriority"             then return data.OriginalRootPriority  end
				elseif instType == "Model" then
					if key == "ExtentsSize"              then return data.OriginalExtents       end
				elseif instType == "CharPart" then
					if key == "AssemblyMass"             then return data.OriginalAssemblyMass  end
					if key == "AssemblyCenterOfMass"     then return data.OriginalAssemblyCOM   end
				end
			end
		end
		return oldIndex(...)
	end))

	local oldNamecall
	oldNamecall = hookmetamethod(game, "__namecall", newcclosure(function(...)
		local self = ...
		local method = getnamecallmethod()
		local args = {...}

		if not checkcaller() then
			local data, instType = getTargetData(self)

			if data then
				if instType == "Part" then
					if method == "GetMass" then return data.OriginalMass end
					if method == "GetPropertyChangedSignal" then
						local prop = args[2]
						if BLOCKED_PROPS[prop] then
							return limbData.dummyEvent.Event
						end
					end
				elseif instType == "Model" then
					if method == "GetExtentsSize" then return data.OriginalExtents end
					if method == "GetBoundingBox" then
						local cf, _ = oldNamecall(...)
						return cf, data.OriginalExtents
					end
				end
			end
		end
		return oldNamecall(...)
	end))
end

local ESP_SOURCE_URL = "https://raw.githubusercontent.com/AAPVdev/scripts/refs/heads/main/esp/SIXSEVENESP.lua"

local function ensureESPLoaded()
	if limbData.ESP then return limbData.ESP end
	if not (has_loadstring and has_httpget) then return nil end

	local ok, res = pcall(function()
		return loadstring(game:HttpGet(ESP_SOURCE_URL))()
	end)
	if ok then limbData.ESP = res end

	return limbData.ESP
end

local function watchProperty(instance, prop, callback)
	if not instance then return end
	if not pcall(_safeGet, instance, prop) then return end

	local lastVal = instance[prop]
	return instance:GetPropertyChangedSignal(prop):Connect(function()
		local ok, curVal = pcall(_safeGet, instance, prop)
		if ok and curVal ~= lastVal then
			pcall(callback, instance)
			local ok2, newVal = pcall(_safeGet, instance, prop)
			if ok2 then lastVal = newVal end
		end
	end)
end

local function getAdjustedPhysicalProperties(limb, origSize, newSize)
	local origPhys = limb.CustomPhysicalProperties or PhysProps_new(limb.Material)

	local origVol = origSize.X * origSize.Y * origSize.Z
	local newVol  = newSize.X  * newSize.Y  * newSize.Z
	if newVol <= 0 then newVol = 1 end

	local ratio      = origVol / newVol
	local newDensity = math_max(0.01, origPhys.Density * ratio)

	return PhysProps_new(
		newDensity,
		origPhys.Friction,
		origPhys.Elasticity,
		origPhys.FrictionWeight,
		origPhys.ElasticityWeight
	)
end

local function sharedSaveData(parent, cacheKey, char, limb)
	local cache = parent._playerCache
	local entry = cache[cacheKey]

	if entry then
		if entry.Limb and entry.Limb ~= limb then
			limbData.instanceLookup[entry.Limb] = nil
		end
		if entry.Character and entry.Character ~= char then
			limbData.instanceLookup[entry.Character] = nil
		end
		if entry._charParts then
			for _, part in ipairs(entry._charParts) do
				limbData.instanceLookup[part] = nil
			end
			entry._charParts = nil
		end
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
	entry.OriginalExtents      = char:GetExtentsSize()
	entry.OriginalPhysProps    = limb.CustomPhysicalProperties
	entry.OriginalRootPriority = limb.RootPriority

	limbData.instanceLookup[limb] = { data = entry, type = "Part"  }
	limbData.instanceLookup[char] = { data = entry, type = "Model" }

	do
		local realChanged = limb.Changed

		local preExistingConns = {}
		if type(getconnections) == "function" then
			pcall(function()
				for _, conn in ipairs(getconnections(realChanged)) do
					table_insert(preExistingConns, conn)
				end
			end)
		end

		local proxy = limbData.changedProxies[limb]
		if not proxy then
			local proxyBE  = Instance_new("BindableEvent")
			local filter   = { enabled = false }
			local filterFn = function(prop)
				if not filter.enabled or not BLOCKED_PROPS[prop] then
					proxyBE:Fire(prop)
				end
			end
			local filterConn = realChanged:Connect(filterFn)
			proxy = { event = proxyBE.Event, filter = filter, filterFn = filterFn, conn = filterConn, be = proxyBE }
			limbData.changedProxies[limb] = proxy
		end

		for _, conn in ipairs(preExistingConns) do
			local fnOk, fn = pcall(_safeGet, conn, "Function")
			if fnOk and fn and fn ~= proxy.filterFn then
				pcall(_disconnect, conn)
				pcall(function() proxy.be.Event:Connect(fn) end)
			end
		end
		proxy.filter.enabled = true
	end

	if type(getconnections) == "function" then
		if entry._gpcRedirects then
			for _, r in ipairs(entry._gpcRedirects) do
				if r.dummyConn and r.dummyConn.Connected then
					r.dummyConn:Disconnect()
				end
			end
		end

		local redirects = {}
		entry._gpcRedirects = redirects

		local dummyEventEvent = limbData.dummyEvent.Event
		for prop in pairs(BLOCKED_PROPS) do
			pcall(function()
				local realSig = limb:GetPropertyChangedSignal(prop)
				local existing = getconnections(realSig)
				for _, conn in ipairs(existing) do
					local fnOk, fn = pcall(_safeGet, conn, "Function")
					if fnOk and fn then
						pcall(_disconnect, conn)
						local ok, dummyConn = pcall(function()
							return dummyEventEvent:Connect(fn)
						end)
						table_insert(redirects, {
							prop      = prop,
							fn        = fn,
							dummyConn = ok and dummyConn or nil,
						})
					end
				end
			end)
		end
	end

	local charParts     = {}
	local charPartEntry = { data = entry, type = "CharPart" }
	for _, part in ipairs(char:GetDescendants()) do
		if part:IsA("BasePart") and part ~= limb then
			limbData.instanceLookup[part] = charPartEntry
			table_insert(charParts, part)
		end
	end
	entry._charParts = charParts
end

local function sharedRestoreLimb(parent, cacheKey, activeLimb)
	local cache = parent._playerCache
	local entry = cache[cacheKey]
	if not entry then return end

	for _, k in ipairs(CONN_KEYS) do
		if entry[k] and entry[k].Connected then entry[k]:Disconnect() end
		entry[k] = nil
	end

	if activeLimb and activeLimb.Parent then
		pcall(function()
			activeLimb.Size                     = entry.OriginalSize
			activeLimb.Transparency             = entry.OriginalTransparency
			activeLimb.CanCollide               = entry.OriginalCanCollide
			activeLimb.Massless                 = entry.OriginalMassless
			activeLimb.CustomPhysicalProperties = entry.OriginalPhysProps
			activeLimb.RootPriority             = entry.OriginalRootPriority
		end)
	end

	if entry._gpcRedirects and entry.Limb and entry.Limb.Parent then
		for _, r in ipairs(entry._gpcRedirects) do
			if r.dummyConn and r.dummyConn.Connected then
				r.dummyConn:Disconnect()
			end
			pcall(function()
				entry.Limb:GetPropertyChangedSignal(r.prop):Connect(r.fn)
			end)
		end
		entry._gpcRedirects = nil
	end

	if entry.Limb then limbData.instanceLookup[entry.Limb] = nil end
	if activeLimb and activeLimb ~= entry.Limb then
		limbData.instanceLookup[activeLimb] = nil
	end
	if entry.Character then limbData.instanceLookup[entry.Character] = nil end
	if entry._charParts then
		for _, part in ipairs(entry._charParts) do
			limbData.instanceLookup[part] = nil
		end
		entry._charParts = nil
	end

	local _cp = limbData.changedProxies[entry.Limb]
	if _cp then _cp.filter.enabled = false end
	if activeLimb and activeLimb ~= entry.Limb then
		local _cpActive = limbData.changedProxies[activeLimb]
		if _cpActive then _cpActive.filter.enabled = false end
	end

	cache[cacheKey] = nil
end

local function sharedApplyLimb(parent, cacheKey, char, limb)
	if not limb or not limb.Parent then return end

	sharedSaveData(parent, cacheKey, char, limb)
	local entry = parent._playerCache[cacheKey]
	if not entry then return end
	local cfg   = parent._settings

	for _, k in ipairs(CONN_KEYS) do
		if entry[k] and entry[k].Connected then entry[k]:Disconnect() end
		entry[k] = nil
	end

	local newVec = Vector3_new(cfg.LIMB_SIZE, cfg.LIMB_SIZE, cfg.LIMB_SIZE)
	local trans  = cfg.LIMB_TRANSPARENCY
	local colide = cfg.LIMB_CAN_COLLIDE
	local isHRP  = (limb.Name == "HumanoidRootPart")

	local newPhys = nil
	if isHRP then
		newPhys = getAdjustedPhysicalProperties(limb, entry.OriginalSize, newVec)
	end

	limb.Size         = newVec
	limb.Transparency = trans
	limb.CanCollide   = colide

	if isHRP then
		limb.Massless = false
		if newPhys then limb.CustomPhysicalProperties = newPhys end
	else
		limb.Massless     = true
		limb.RootPriority = -127
	end

	entry.SizeConn  = watchProperty(limb, "Size",         function(l) l.Size         = newVec end)
	entry.TransConn = watchProperty(limb, "Transparency", function(l) l.Transparency = trans  end)
	entry.CollConn  = watchProperty(limb, "CanCollide",   function(l) l.CanCollide   = colide end)

	if not isHRP then
		entry.MasslessConn     = watchProperty(limb, "Massless",     function(l) l.Massless     = true end)
		entry.RootPriorityConn = watchProperty(limb, "RootPriority", function(l) l.RootPriority = -127 end)
	else
		if newPhys then
			entry.PhysConn = watchProperty(limb, "CustomPhysicalProperties", function(l) l.CustomPhysicalProperties = newPhys end)
		end
	end

	return newVec
end

local LimbExtender = {}
LimbExtender.__index = LimbExtender

local DEFAULTS = {
	TARGET_LIMB             = "Head",
	LIMB_SIZE               = 15,
	LIMB_TRANSPARENCY       = 0.5,
	LIMB_CAN_COLLIDE        = false,
	TEAM_CHECK              = true,
	FORCEFIELD_CHECK        = false,
	ALT_RESET_LIMB_ON_DEATH = false,
	PLAYER_ENABLED          = true,
	NPC_ENABLED             = false,
	NPC_FILTER              = nil,
	NPC_DIRECTORIES         = {},
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

	ESP_NEAR_FLAGS   = { Box = true,  Tracer = true,  Skeleton = true,  Health = true,  Label = true,  Box3D = false },
	ESP_MEDIUM_FLAGS = { Box = true,  Tracer = true,  Skeleton = false, Health = true,  Label = true,  Box3D = false },
	ESP_FAR_FLAGS    = { Box = true,  Tracer = true,  Skeleton = false, Health = false, Label = false, Box3D = false },

	ESP_TEXT_RESOLVER = nil,
	ESP_CAN_DRAW      = nil,
	ESP_TRACER_ORIGIN = nil,
}

local function mergeSettings(user)
	local s = table_clone(DEFAULTS)
	if type(user) == "table" then
		for k, v in pairs(user) do s[k] = v end
	end

	if type(s.NPC_DIRECTORIES) == "table" then
		s.NPC_DIRECTORIES = table_clone(s.NPC_DIRECTORIES)
	else
		s.NPC_DIRECTORIES = {}
	end

	for _, key in ipairs({ "ESP_NEAR_FLAGS", "ESP_MEDIUM_FLAGS", "ESP_FAR_FLAGS" }) do
		if type(s[key]) == "table" then
			s[key] = table_clone(s[key])
		end
	end

	return s
end

function LimbExtender.new(userSettings)
	local self = setmetatable({
		_settings    = mergeSettings(userSettings),
		_playerCache = limbData.playerCache,
		_manager     = nil,
		_ESP         = nil,
		_running     = false,
		_destroyed   = false,
		_npcIdMap    = {},   
	}, LimbExtender)

	self._manager = Manager.new({
		PLAYER_ENABLED  = self._settings.PLAYER_ENABLED,
		NPC_ENABLED     = self._settings.NPC_ENABLED,
		NPC_FILTER      = self._settings.NPC_FILTER,
		NPC_DIRECTORIES = self._settings.NPC_DIRECTORIES,

		TARGET_LIMB         = self._settings.TARGET_LIMB,
		TEAM_CHECK          = self._settings.TEAM_CHECK,
		FORCEFIELD_CHECK    = self._settings.FORCEFIELD_CHECK,
		DEATH_RESTORE       = self._settings.ALT_RESET_LIMB_ON_DEATH,
		GET_LOCAL_TEAM      = function() return localPlayer.Team end,

		ON_LIMB_READY = function(player, model, limb)
			self:_applyLimbs(player, model, limb)
		end,
		ON_LIMB_LOST  = function(player, model, limb)
			self:_removeLimbs(player, model, limb)
		end,
	})

	if self._settings.ESP then
		self.ESP = ensureESPLoaded()
		if self.ESP then
			self._ESP = self.ESP.new(self:_buildESPConfig())
		else
			self._settings.ESP = false
		end
	end

	limbData.terminate = function() self:Destroy() end

	return self
end

function LimbExtender:_buildESPConfig()
	local s = self._settings

	local function applyToggles(flags)
		return {
			Box      = s.ESP_BOX      and flags.Box,
			Box3D    = s.ESP_BOX3D    and flags.Box3D,
			Tracer   = s.ESP_TRACER   and flags.Tracer,
			Skeleton = s.ESP_SKELETON and flags.Skeleton,
			Health   = s.ESP_HEALTH   and flags.Health,
			Label    = s.ESP_LABEL    and flags.Label,
		}
	end

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
			Near   = applyToggles(s.ESP_NEAR_FLAGS),
			Medium = applyToggles(s.ESP_MEDIUM_FLAGS),
			Far    = applyToggles(s.ESP_FAR_FLAGS),
		},
		TextResolver = s.ESP_TEXT_RESOLVER,
		CanDraw      = s.ESP_CAN_DRAW,
		TracerOrigin = s.ESP_TRACER_ORIGIN,
	}
end

function LimbExtender:_applyLimbs(player, char, limb)
	if not isLiveInstance(limb) or not limb.Parent then return end

	local cacheKey
	if player then
		cacheKey = player.Name
	else
		if not self._npcIdMap[char] then
			limbData.npcIdCounter = limbData.npcIdCounter + 1
			self._npcIdMap[char] = "__npc_" .. limbData.npcIdCounter
		end
		cacheKey = self._npcIdMap[char]
	end

	sharedApplyLimb(self, cacheKey, char, limb)
	if self._ESP then self._ESP:Track(char) end
end

function LimbExtender:_removeLimbs(player, char, limb)
	local cacheKey
	if player then
		cacheKey = player.Name
	else
		cacheKey = self._npcIdMap[char]
	end

	sharedRestoreLimb(self, cacheKey, limb)
	if self._ESP and char then self._ESP:Untrack(char) end
	if not player then
		self._npcIdMap[char] = nil
	end
end

function LimbExtender:Start()
	if self._destroyed or self._running then return end
	self._running = true
	self._manager:Start()
	if self._ESP then self._ESP:Start() end
end

function LimbExtender:Stop()
	if self._destroyed or not self._running then return end
	self._running = false
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
	if self._settings[key] == value then return end
	self._settings[key] = value

	local function mergeSettings(target, source)
		for k, v in pairs(source) do
			if type(v) == "table" and type(target[k]) == "table" then
				mergeSettings(target[k], v)
			else
				target[k] = v
			end
		end
	end

	if key == "ESP_NEAR_FLAGS" or key == "ESP_MEDIUM_FLAGS" or key == "ESP_FAR_FLAGS" then
		self._settings[key] = table_clone(DEFAULTS[key])
		mergeSettings(self._settings[key], value)
	end

	if type(key) == "string" and key:sub(1, 4) == "ESP_" then
		if self._ESP then
			self._ESP:SetOptions(self:_buildESPConfig())
			if key == "ESP_CAN_DRAW" then
				self._ESP.Config.CanDraw = value
			elseif key == "ESP_TEXT_RESOLVER" then
				self._ESP.Config.TextResolver = value
			elseif key == "ESP_TRACER_ORIGIN" then
				self._ESP.Config.TracerOrigin = value
			end
		end
		return
	end

	if key == "ESP" then
		if value then
			self.ESP = ensureESPLoaded()
			if self.ESP then
				if not self._ESP then
					self._ESP = self.ESP.new(self:_buildESPConfig())
					if self._running then
						for _, entry in pairs(self._playerCache) do
							if entry.Character then
								self._ESP:Track(entry.Character)
							end
						end
						self._ESP:Start()
					end
				end
			else
				self._settings.ESP = false
			end
		else
			if self._ESP then
				self._ESP:Destroy()
				self._ESP = nil
			end
		end
		return
	end

	local managerKey = key
	if key == "ALT_RESET_LIMB_ON_DEATH" then
		managerKey = "DEATH_RESTORE"
	end

	local managerCompatibleKeys = {
		PLAYER_ENABLED = true,
		NPC_ENABLED    = true,
		NPC_FILTER     = true,
		TARGET_LIMB    = true,
		TEAM_CHECK     = true,
		FORCEFIELD_CHECK = true,
		DEATH_RESTORE  = true,
	}
	if managerCompatibleKeys[managerKey] then
		self._manager:Set(managerKey, value)
	end

	if key == "NPC_DIRECTORIES" then
		self._manager._settings.NPC_DIRECTORIES = value
	end

	self:Restart()
end

function LimbExtender:Get(key)
	return self._settings[key]
end

function LimbExtender:AddDirectory(dir)
	self._manager:AddDirectory(dir)
end

function LimbExtender:RemoveDirectory(dir)
	self._manager:RemoveDirectory(dir)
end

function LimbExtender:GetDirectories()
	return self._manager:GetDirectories()
end

function LimbExtender:Destroy()
	self:Stop()
	self._destroyed = true
	if self._ESP then self._ESP:Destroy(); self._ESP = nil end
	limbData.terminate = nil
	setmetatable(self, nil)
end

return setmetatable({}, {
	__call = function(_, userSettings)
		return LimbExtender.new(userSettings)
	end,
	__index = LimbExtender,
})
