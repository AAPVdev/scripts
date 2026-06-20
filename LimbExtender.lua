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

local function getAdjustedPhysicalProperties(limb, origSize, newSize)
    local origPhys = limb.CustomPhysicalProperties or PhysProps_new(limb.Material)
    local origVol = origSize.X * origSize.Y * origSize.Z
    local newVol  = newSize.X  * newSize.Y  * newSize.Z
    if newVol <= 0 then newVol = 1 end
    local ratio      = origVol / newVol
    local newDensity = math_max(0.01, origPhys.Density * ratio)
    return PhysProps_new(newDensity, origPhys.Friction, origPhys.Elasticity, origPhys.FrictionWeight, origPhys.ElasticityWeight)
end

-- Global metamethod hooks (on game)
if not limbData._spoofInstalled and has_newcclosure and has_hookmetamethod and has_checkcaller then
    limbData._spoofInstalled = true

    local _instanceLookup = limbData.instanceLookup
    local _playerCache    = limbData.playerCache
    local _fakeSignals     = limbData.fakeSignals
    limbData._bypassHooks = false

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

    local oldNewIndex = hookmetamethod(game, "__newindex", newcclosure(function(...)
        local self, key, value = ...
        if not checkcaller() and not limbData._bypassHooks then
            local data, instType = getTargetData(self)
            if data and instType == "Part" and self == data.Limb and BLOCKED_PROPS[key] then
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
                local sigs = _fakeSignals[self]
                if sigs then
                    if sigs["__Changed"] then sigs["__Changed"]:Fire(key) end
                    if sigs[key] then sigs[key]:Fire() end
                end
                return
            end
        end
        return oldNewIndex(...)
    end))

    local oldIndex = hookmetamethod(game, "__index", newcclosure(function(...)
        local self, key = ...
        if not checkcaller() and not limbData._bypassHooks then
            if key == "Changed" and typeof(self) == "Instance" and self:IsA("BasePart") and self.Name == (limbData.targetLimbName or "HumanoidRootPart") then
                return ensureFakeSignal(self, "__Changed").Event
            end

            local data, instType = getTargetData(self)
            if data then
                if instType == "Part" and self == data.Limb and BLOCKED_PROPS[key] then
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
                elseif instType == "Model" and self == data.Character then
                    if key == "ExtentsSize" then
                        return data.OriginalExtents
                    end
                end
            end
        end
        return oldIndex(...)
    end))

    local oldNamecall = hookmetamethod(game, "__namecall", newcclosure(function(...)
        local self = ...
        local method = getnamecallmethod()
        if not checkcaller() and not limbData._bypassHooks then
            local data, instType = getTargetData(self)
            if data then
                if instType == "Part" and self == data.Limb then
                    if method == "GetMass" then
                        local density = data.OriginalDensity or getPartDensity(self)
                        local size = data.OriginalSize
                        return density * (size.X * size.Y * size.Z)
                    end
                    if method == "GetPropertyChangedSignal" then
                        local prop = select(2, ...)
                        if BLOCKED_PROPS[prop] then
                            return ensureFakeSignal(self, prop).Event
                        end
                    end
                elseif instType == "Model" and self == data.Character then
                    if method == "GetExtentsSize" then
                        return data.OriginalExtents
                    end
                    if method == "GetBoundingBox" then
                        local cf = self:GetPrimaryPartCFrame()
                        return cf, data.OriginalExtents
                    end
                end
            end
        end
        return oldNamecall(...)
    end))
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

    limbData.instanceLookup[limb] = { data = entry, type = "Part" }
    limbData.instanceLookup[char] = { data = entry, type = "Model" }
end

local function sharedApplyLimb(parent, cacheKey, char, limb)
    if not limb or not limb.Parent then return end
    sharedSaveData(parent, cacheKey, char, limb)

    local entry = parent._playerCache[cacheKey]
    if not entry then return end
    local settings = parent._settings

    local newVec = Vector3_new(settings.LIMB_SIZE, settings.LIMB_SIZE, settings.LIMB_SIZE)
    local trans = settings.LIMB_TRANSPARENCY
    local colide = settings.LIMB_CAN_COLLIDE
    local isHRP = (limb.Name == "HumanoidRootPart")
    local newPhys = isHRP and getAdjustedPhysicalProperties(limb, entry.OriginalSize, newVec) or nil

    limb.Size = newVec
    limb.Transparency = trans
    limb.CanCollide = colide

    if isHRP then
        limb.Massless = false
        if newPhys then limb.CustomPhysicalProperties = newPhys end
    else
        limb.Massless = true
        limb.RootPriority = -127
    end

    local conn = limb.Changed:Connect(function(prop)
        if BLOCKED_PROPS[prop] then
            if prop == "Size" then limb.Size = newVec
            elseif prop == "Transparency" then limb.Transparency = trans
            elseif prop == "CanCollide" then limb.CanCollide = colide
            elseif prop == "Massless" then limb.Massless = isHRP and false or true
            elseif prop == "RootPriority" and not isHRP then limb.RootPriority = -127
            end
            if prop == "CustomPhysicalProperties" and isHRP and newPhys then
                limb.CustomPhysicalProperties = newPhys
            end
        end
    end)
    entry._internalChangedConn = conn

    -- Humanoid state change listener for forced collision off
    if not colide then
        local humanoid = char:FindFirstChildOfClass("Humanoid")
        if humanoid and not entry._humanoidStateConn then
            local function forceCollisions()
                if not isLiveInstance(limb) or not limb.Parent then return end
                limb.CanCollide = false
            end
            entry._humanoidStateConn = humanoid.StateChanged:Connect(forceCollisions)
            forceCollisions()
        end
    end

    return newVec
end

local function sharedRestoreLimb(parent, cacheKey, activeLimb)
    local cache = parent._playerCache
    local entry = cache[cacheKey]
    if not entry then return end

    if activeLimb and activeLimb.Parent then
        if entry._internalChangedConn then
            pcall(function() entry._internalChangedConn:Disconnect() end)
            entry._internalChangedConn = nil
        end
        if entry._humanoidStateConn then
            pcall(function() entry._humanoidStateConn:Disconnect() end)
            entry._humanoidStateConn = nil
        end
        limbData._bypassHooks = true
        pcall(function()
            activeLimb.Size                     = entry.OriginalSize
            activeLimb.Transparency             = entry.OriginalTransparency
            activeLimb.CanCollide               = entry.OriginalCanCollide
            activeLimb.Massless                 = entry.OriginalMassless
            activeLimb.CustomPhysicalProperties = entry.OriginalPhysProps
            activeLimb.RootPriority             = entry.OriginalRootPriority
        end)
        limbData._bypassHooks = false
    end

    if entry.Limb then limbData.instanceLookup[entry.Limb] = nil end
    if activeLimb and activeLimb ~= entry.Limb then limbData.instanceLookup[activeLimb] = nil end
    if entry.Character then limbData.instanceLookup[entry.Character] = nil end
    cache[cacheKey] = nil
end

local function reapplyCosmeticToEntry(entry, settings)
    local limb = entry.Limb
    if not limb or not limb.Parent then return end

    if entry._internalChangedConn then
        pcall(function() entry._internalChangedConn:Disconnect() end)
        entry._internalChangedConn = nil
    end
    if entry._humanoidStateConn then
        pcall(function() entry._humanoidStateConn:Disconnect() end)
        entry._humanoidStateConn = nil
    end

    local newVec = Vector3_new(settings.LIMB_SIZE, settings.LIMB_SIZE, settings.LIMB_SIZE)
    local trans = settings.LIMB_TRANSPARENCY
    local colide = settings.LIMB_CAN_COLLIDE
    local isHRP = (limb.Name == "HumanoidRootPart")
    local newPhys = isHRP and getAdjustedPhysicalProperties(limb, entry.OriginalSize, newVec) or nil

    limbData._bypassHooks = true
    limb.Size = newVec
    limb.Transparency = trans
    limb.CanCollide = colide
    if isHRP then
        limb.Massless = false
        if newPhys then limb.CustomPhysicalProperties = newPhys end
    else
        limb.Massless = true
        limb.RootPriority = -127
    end
    limbData._bypassHooks = false

    local conn = limb.Changed:Connect(function(prop)
        if BLOCKED_PROPS[prop] then
            if prop == "Size" then limb.Size = newVec
            elseif prop == "Transparency" then limb.Transparency = trans
            elseif prop == "CanCollide" then limb.CanCollide = colide
            elseif prop == "Massless" then limb.Massless = isHRP and false or true
            elseif prop == "RootPriority" and not isHRP then limb.RootPriority = -127
            end
            if prop == "CustomPhysicalProperties" and isHRP and newPhys then
                limb.CustomPhysicalProperties = newPhys
            end
        end
    end)
    entry._internalChangedConn = conn

    -- Re-attach humanoid state listener if collisions are still off
    if not colide then
        local humanoid = entry.Character and entry.Character:FindFirstChildOfClass("Humanoid")
        if humanoid and not entry._humanoidStateConn then
            local function forceCollisions()
                if not isLiveInstance(limb) or not limb.Parent then return end
                limb.CanCollide = false
            end
            entry._humanoidStateConn = humanoid.StateChanged:Connect(forceCollisions)
            forceCollisions()
        end
    end
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
        _suppressOnLimbLost = false,
        _needsRestart = false,
        _needsCosmeticUpdate = false,
        _workRunning = false,
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

    if self._settings.ESP then
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

function LimbExtender:_doRestart()
    if not self._running then return end

    self._suppressOnLimbLost = true
    self._manager:Stop()

    local cache = self._playerCache
    local keys = {}
    for k in pairs(cache) do
        table_insert(keys, k)
    end

    local BATCH_SIZE = 10
    for i = 1, #keys, BATCH_SIZE do
        if not self._running then break end
        local last = math_min(i + BATCH_SIZE - 1, #keys)
        for j = i, last do
            local key = keys[j]
            local entry = cache[key]
            if entry then
                sharedRestoreLimb(self, key, entry.Limb)
            end
        end
        task_wait()
    end

    self._suppressOnLimbLost = false
    table_clear(cache)

    if self._ESP then self._ESP:Stop() end

    if not self._running then return end

    self._manager:Start()
    if self._ESP then self._ESP:Start() end
end

function LimbExtender:_doCosmeticUpdate()
    if not self._running then return end
    local BATCH_SIZE = 10
    local settings = self._settings
    local entries = {}
    for _, entry in pairs(self._playerCache) do
        if entry.Limb and entry.Character then
            table_insert(entries, entry)
        end
    end

    for i = 1, #entries, BATCH_SIZE do
        if self._needsRestart or not self._running then return end
        local last = math_min(i + BATCH_SIZE - 1, #entries)
        for j = i, last do
            reapplyCosmeticToEntry(entries[j], settings)
        end
        task_wait()
    end
end

function LimbExtender:_processWork()
    while self._running and (self._needsRestart or self._needsCosmeticUpdate) do
        if self._needsRestart then
            self._needsRestart = false
            self:_doRestart()
        elseif self._needsCosmeticUpdate then
            self._needsCosmeticUpdate = false
            self:_doCosmeticUpdate()
        end
    end
    self._workRunning = false
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
    self._needsRestart = false
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
    local function mergeTables(target, source)
        for k, v in pairs(source) do
            if type(v) == "table" and type(target[k]) == "table" then
                mergeTables(target[k], v)
            else
                target[k] = v
            end
        end
    end

    local isLodKey = (key == "ESP_NEAR_FLAGS" or key == "ESP_MEDIUM_FLAGS" or key == "ESP_FAR_FLAGS")
    if isLodKey then
        if type(self._settings[key]) ~= "table" then
            self._settings[key] = {}
        end
        mergeTables(self._settings[key], value)
    else
        if self._settings[key] ~= value or isLodKey then
            self._settings[key] = value
        else
            return
        end
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

    local RESTART_KEYS = {
        PLAYER_ENABLED = true,
        NPC_ENABLED = true,
        NPC_FILTER = true,
        TARGET_LIMB = true,
        TEAM_CHECK = true,
        FORCEFIELD_CHECK = true,
        ALT_RESET_LIMB_ON_DEATH = true,
        NPC_DIRECTORIES = true,
    }

    local managerKey = key
    if key == "ALT_RESET_LIMB_ON_DEATH" then
        managerKey = "DEATH_RESTORE"
    end

    if RESTART_KEYS[key] then
        if key == "TARGET_LIMB" then
            limbData.targetLimbName = value
        end
        if key == "NPC_DIRECTORIES" then
            self._manager._settings.NPC_DIRECTORIES = value
        elseif key == "ALT_RESET_LIMB_ON_DEATH" then
            self._manager:Set("DEATH_RESTORE", value)
        else
            self._manager:Set(managerKey, value)
        end
        self._needsRestart = true
    else
        self._needsCosmeticUpdate = true
    end

    if self._running and not self._workRunning then
        self._workRunning = true
        task_spawn(function()
            task_wait()
            self:_processWork()
        end)
    end
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
    self._running = false
    self._needsRestart = false
    self._needsCosmeticUpdate = false
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
