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
local math_min = math.min
local task_spawn = task.spawn
local task_wait = task.wait
local table_clear = table.clear
local table_insert = table.insert
local table_clone = table.clone
local Instance_new = Instance.new
local Vector3_new = Vector3.new
local Vector3_zero = Vector3_new()
local PhysProps_new = PhysicalProperties.new
local CFrame_new = CFrame.new

local function _safeGet(obj, key) return obj[key] end
local function _disconnect(conn) conn:Disconnect() end

limbData.playerCache    = limbData.playerCache    or {}
limbData.instanceLookup = limbData.instanceLookup or setmetatable({}, { __mode = "k" })
limbData.npcIdCounter   = limbData.npcIdCounter   or 0
limbData.fakeSignals     = limbData.fakeSignals     or setmetatable({}, { __mode = "k" })
limbData.spoofedConns    = limbData.spoofedConns    or setmetatable({}, { __mode = "k" })
limbData.partData        = limbData.partData        or setmetatable({}, { __mode = "k" })

if type(limbData.terminate) == "function" then
	limbData.terminate()
	limbData.terminate = nil
end

local has_newcclosure    = type(newcclosure)    == "function"
local has_hookmetamethod = type(hookmetamethod) == "function"
local has_loadstring     = type(loadstring)     == "function"
local has_hookfunction   = type(hookfunction)   == "function"
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

local function ensureFakeSignal(part, prop)
	local sigs = limbData.fakeSignals[part]
	if not sigs then
		sigs = {}
		limbData.fakeSignals[part] = sigs
	end
	if not sigs[prop] then
		sigs[prop] = Instance_new("BindableEvent")
	end
	return sigs[prop]
end

if not limbData._spoofInstalled and has_newcclosure and has_hookmetamethod and has_checkcaller then
	limbData._spoofInstalled = true

	local _instanceLookup = limbData.instanceLookup
	local _playerCache    = limbData.playerCache
	local _fakeSignals     = limbData.fakeSignals
	local _spoofedConns    = limbData.spoofedConns
	local _partData        = limbData.partData

	limbData._bypassHooks = false

	local sampleConn = Instance_new("BindableEvent").Event:Connect(function() end)
	local connMeta = debug.getmetatable(sampleConn)
	sampleConn:Disconnect()
	local oldConnIndex = connMeta.__index

	local spoofedConnectedProxy = {}
	do
		local dummy = function() end
		setmetatable(spoofedConnectedProxy, {
			__index = function(_, k) return dummy end,
			__tostring = function() return "true" end,
			__call = function() end,
		})
	end

	local function connIndexHook(self, key)
		if key == "Connected" and _spoofedConns[self] then
			return spoofedConnectedProxy
		end
		return oldConnIndex(self, key)
	end
	setreadonly(connMeta, false)
	connMeta.__index = connIndexHook
	setreadonly(connMeta, true)

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

	local function getPartDensity(part)
		local phys = part.CustomPhysicalProperties
		if phys then return phys.Density end
		return PhysProps_new(part.Material).Density
	end

	local function computePartMass(part, entry)
		local pd = entry._partData and entry._partData[part]
		if not pd then return part.Mass end
		if pd.massless then return 0 end
		local size = pd.size
		local density = pd.density
		return density * (size.X * size.Y * size.Z)
	end

	local function computeExtentsSize(char, entry)
		local minVec = Vector3_new(math.huge, math.huge, math.huge)
		local maxVec = Vector3_new(-math.huge, -math.huge, -math.huge)
		local function expand(part, size)
			local cf = part.CFrame
			local half = size * 0.5
			local corners = {
				cf * Vector3_new( half.X,  half.Y,  half.Z),
				cf * Vector3_new( half.X,  half.Y, -half.Z),
				cf * Vector3_new( half.X, -half.Y,  half.Z),
				cf * Vector3_new( half.X, -half.Y, -half.Z),
				cf * Vector3_new(-half.X,  half.Y,  half.Z),
				cf * Vector3_new(-half.X,  half.Y, -half.Z),
				cf * Vector3_new(-half.X, -half.Y,  half.Z),
				cf * Vector3_new(-half.X, -half.Y, -half.Z),
			}
			for _, corner in ipairs(corners) do
				minVec = Vector3_new(math_min(minVec.X, corner.X), math_min(minVec.Y, corner.Y), math_min(minVec.Z, corner.Z))
				maxVec = Vector3_new(math_max(maxVec.X, corner.X), math_max(maxVec.Y, corner.Y), math_max(maxVec.Z, corner.Z))
			end
		end
		for _, part in ipairs(char:GetDescendants()) do
			if part:IsA("BasePart") then
				local size
				if part == entry.Limb then
					size = entry.OriginalSize
				elseif entry._partData and entry._partData[part] then
					size = entry._partData[part].size
				else
					size = part.Size
				end
				expand(part, size)
			end
		end
		return Vector3_new(maxVec.X - minVec.X, maxVec.Y - minVec.Y, maxVec.Z - minVec.Z)
	end

	local oldNewIndex
	oldNewIndex = hookmetamethod(game, "__newindex", newcclosure(function(...)
		local self, key, value = ...
		if not checkcaller() then
			local data, instType = getTargetData(self)
			if data and instType == "Part" and BLOCKED_PROPS[key] then
				if key == "Size" then data.OriginalSize = value
				elseif key == "Transparency" then data.OriginalTransparency = value
				elseif key == "CanCollide" then data.OriginalCanCollide = value
				elseif key == "Massless" then data.OriginalMassless = value
				elseif key == "Mass" then data.OriginalMass = value
				elseif key == "AssemblyMass" then data.OriginalAssemblyMass = value
				elseif key == "AssemblyCenterOfMass" then data.OriginalAssemblyCOM = value
				elseif key == "CustomPhysicalProperties" then data.OriginalPhysProps = value
				elseif key == "RootPriority" then data.OriginalRootPriority = value
				end

				local changedFake = _fakeSignals[self] and _fakeSignals[self]["__Changed"]
				if changedFake then changedFake:Fire(key) end

				local propFake = _fakeSignals[self] and _fakeSignals[self][key]
				if propFake then propFake:Fire() end

				return
			elseif data and instType == "CharPart" and key == "Massless" then
				local pd = data._partData and data._partData[self]
				if pd then
					pd.massless = value
				end
				local changedFake = _fakeSignals[data.Limb] and _fakeSignals[data.Limb]["__Changed"]
				if changedFake then changedFake:Fire(key) end
				return
			end
		end
		return oldNewIndex(...)
	end))

	local oldIndex
	oldIndex = hookmetamethod(game, "__index", newcclosure(function(...)
		local self, key = ...
		if not checkcaller() then
			if limbData._bypassHooks then return oldIndex(...) end

			if key == "Changed" and typeof(self) == "Instance" and self:IsA("BasePart") and self.Name == (limbData.targetLimbName or "HumanoidRootPart") then
				return ensureFakeSignal(self, "__Changed").Event
			end

			local data, instType = getTargetData(self)
			if data then
				if instType == "Part" and BLOCKED_PROPS[key] then
					if key == "Size"                     then return data.OriginalSize         end
					if key == "Transparency"             then return data.OriginalTransparency  end
					if key == "CanCollide"               then return data.OriginalCanCollide    end
					if key == "Massless"                 then return data.OriginalMassless      end
					if key == "Mass"                     then
						local density = data.OriginalDensity or getPartDensity(self)
						local size = data.OriginalSize
						return density * (size.X * size.Y * size.Z)
					end
					if key == "AssemblyMass"             then
						local density = data.OriginalDensity or getPartDensity(self)
						local size = data.OriginalSize
						return density * (size.X * size.Y * size.Z)
					end
					if key == "AssemblyCenterOfMass"     then
						local size = data.OriginalSize
						return self.Position + Vector3_new(size.X * 0.001, size.Y * 0.001, size.Z * 0.001)
					end
					if key == "CustomPhysicalProperties" then return data.OriginalPhysProps     end
					if key == "CurrentPhysicalProperties" then return data.OriginalPhysProps    end
					if key == "RootPriority"             then return data.OriginalRootPriority  end
				elseif instType == "Model" then
					if key == "ExtentsSize" then
						return computeExtentsSize(self, data)
					end
				elseif instType == "CharPart" then
					if key == "AssemblyMass" then
						return computePartMass(self, data)
					end
					if key == "AssemblyCenterOfMass" then
						return self.Position
					end
				end
			end
		end
		return oldIndex(...)
	end))

	local oldNamecall
	oldNamecall = hookmetamethod(game, "__namecall", newcclosure(function(...)
		local self = ...
		local method = getnamecallmethod()

		if not checkcaller() then
			if limbData._bypassHooks then return oldNamecall(...) end

			local data, instType = getTargetData(self)
			if data then
				if instType == "Part" then
					if method == "GetMass" then
						local density = data.OriginalDensity or getPartDensity(self)
						local size = data.OriginalSize
						return density * (size.X * size.Y * size.Z)
					end
				elseif instType == "Model" then
					if method == "GetExtentsSize" then
						return computeExtentsSize(self, data)
					end
					if method == "GetBoundingBox" then
						local extents = computeExtentsSize(self, data)
						local cf = self:GetPrimaryPartCFrame()
						return cf, extents
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

local function getAdjustedPhysicalProperties(limb, origSize, newSize)
	local origPhys = limb.CustomPhysicalProperties or PhysProps_new(limb.Material)
	local origVol = origSize.X * origSize.Y * origSize.Z
	local newVol  = newSize.X  * newSize.Y  * newSize.Z
	if newVol <= 0 then newVol = 1 end
	local ratio      = origVol / newVol
	local newDensity = math_max(0.01, origPhys.Density * ratio)
	return PhysProps_new(newDensity, origPhys.Friction, origPhys.Elasticity, origPhys.FrictionWeight, origPhys.ElasticityWeight)
end

limbData.neutralizedCallbacks = limbData.neutralizedCallbacks or setmetatable({}, { __mode = "k" })

local function neutralizeRealListeners(part)
    if type(getconnections) ~= "function" then return end
    if type(hookfunction) ~= "function" then return end

    limbData._bypassHooks = true

    pcall(function()
        local realChanged = part.Changed
        for _, conn in ipairs(getconnections(realChanged)) do
            local fn = conn.Function
            if fn and not limbData.neutralizedCallbacks[fn] then
                local orig = hookfunction(fn, function() end)
                limbData.neutralizedCallbacks[fn] = orig
            end
        end
    end)

    for prop in pairs(BLOCKED_PROPS) do
        pcall(function()
            local realSig = part:GetPropertyChangedSignal(prop)
            for _, conn in ipairs(getconnections(realSig)) do
                local fn = conn.Function
                if fn and not limbData.neutralizedCallbacks[fn] then
                    local orig = hookfunction(fn, function() end)
                    limbData.neutralizedCallbacks[fn] = orig
                end
            end
        end)
    end

    limbData._bypassHooks = false
end

local function getPartDensitySafe(part)
	local ok, phys = pcall(function() return part.CustomPhysicalProperties end)
	if ok and phys then return phys.Density end
	local ok2, mat = pcall(function() return part.Material end)
	if ok2 then
		local ok3, props = pcall(PhysProps_new, mat)
		if ok3 and props then return props.Density end
	end
	return 1 
end

local function perPartHookGetPropertyChangedSignal(limb)
	if not has_hookfunction then return end
	local originalGPS = limb.GetPropertyChangedSignal
	hookfunction(limb, "GetPropertyChangedSignal", function(_, prop)
		if BLOCKED_PROPS[prop] then
			return ensureFakeSignal(limb, prop).Event
		end
		return originalGPS(limb, prop)
	end)
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
		if entry._partData then
			for part, _ in pairs(entry._partData) do
				limbData.partData[part] = nil
			end
			entry._partData = nil
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
	entry.OriginalPhysProps    = limb.CustomPhysicalProperties or PhysProps_new(limb.Material)
	entry.OriginalRootPriority = limb.RootPriority or 0
	entry.OriginalDensity      = getPartDensitySafe(limb)

	limbData.instanceLookup[limb] = { data = entry, type = "Part"  }
	limbData.instanceLookup[char] = { data = entry, type = "Model" }

	entry._partData = {}
	local charParts     = {}
	local charPartEntry = { data = entry, type = "CharPart" }
	for _, part in ipairs(char:GetDescendants()) do
		if part:IsA("BasePart") then
			if part ~= limb then
				limbData.instanceLookup[part] = charPartEntry
				table_insert(charParts, part)
			end
			entry._partData[part] = {
				size = part.Size,
				density = getPartDensitySafe(part),
				massless = part.Massless,
			}
			limbData.partData[part] = entry._partData[part]
		end
	end
	entry._charParts = charParts

	perPartHookGetPropertyChangedSignal(limb)
	neutralizeRealListeners(limb)
end

local function sharedRestoreLimb(parent, cacheKey, activeLimb)
	local cache = parent._playerCache
	local entry = cache[cacheKey]
	if not entry then return end

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

	if entry._internalChangedConn then
		pcall(function() entry._internalChangedConn:Disconnect() end)
		entry._internalChangedConn = nil
	end

	if limbData.neutralizedCallbacks then
		for fn, orig in pairs(limbData.neutralizedCallbacks) do
			pcall(function()
				hookfunction(fn, orig)
				limbData.neutralizedCallbacks[fn] = nil
			end)
		end
	end

	if activeLimb then
		limbData.fakeSignals[activeLimb] = nil
	end

	if entry._partData then
		for part, _ in pairs(entry._partData) do
			limbData.partData[part] = nil
			limbData.instanceLookup[part] = nil
		end
		entry._partData = nil
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
	cache[cacheKey] = nil
end

local function sharedApplyLimb(parent, cacheKey, char, limb)
	if not limb or not limb.Parent then return end

	local ok, err = pcall(sharedSaveData, parent, cacheKey, char, limb)

	local entry = parent._playerCache[cacheKey]
	if not entry then return end   
	local cfg   = parent._settings

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

	local conn = limb.Changed:Connect(function(prop)
		if BLOCKED_PROPS[prop] then
			if prop == "Size" then
				limb.Size = newVec
			elseif prop == "Transparency" then
				limb.Transparency = trans
			elseif prop == "CanCollide" then
				limb.CanCollide = colide
			elseif prop == "Massless" then
				limb.Massless = isHRP and false or true
			elseif prop == "RootPriority" and not isHRP then
				limb.RootPriority = -127
			end
			if prop == "CustomPhysicalProperties" and isHRP and newPhys then
				limb.CustomPhysicalProperties = newPhys
			end
		end
	end)
	entry._internalChangedConn = conn

	return newVec
end

local LimbExtender = {}
LimbExtender.__index = LimbExtender

local DEFAULTS = {
	TARGET_LIMB             = "HumanoidRootPart",
	LIMB_SIZE               = 15,
	LIMB_TRANSPARENCY       = 0.5,
	LIMB_CAN_COLLIDE        = false,
	TEAM_CHECK              = true,
	FORCEFIELD_CHECK        = false,
	ALT_RESET_LIMB_ON_DEATH = false,
	PLAYER_ENABLED          = true,
	NPC_ENABLED             = true,
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

	limbData.targetLimbName = self._settings.TARGET_LIMB

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

	if self._ESP then
		local tracked = self._ESP:Track(char)
		if not tracked then
			task.spawn(function()
				local attempts = 0
				while not self._ESP:Track(char) and attempts < 30 do
					task.wait(0.1)
					attempts = attempts + 1
				end
			end)
		end
	end
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

    local isLodKey = (key == "ESP_NEAR_FLAGS" or key == "ESP_MEDIUM_FLAGS" or key == "ESP_FAR_FLAGS")
    if self._settings[key] == value and not isLodKey then return end

    local function mergeSettings(target, source)
        for k, v in pairs(source) do
            if type(v) == "table" and type(target[k]) == "table" then
                mergeSettings(target[k], v)
            else
                target[k] = v
            end
        end
    end

    if isLodKey then
        if type(self._settings[key]) ~= "table" then
            self._settings[key] = {}
        end
        mergeSettings(self._settings[key], value)
    else
        self._settings[key] = value
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
