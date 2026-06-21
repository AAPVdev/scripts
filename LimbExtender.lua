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

local type, typeof = type, typeof
local pcall = pcall
local pairs, ipairs = pairs, ipairs
local math_max = math.max
local math_min = math.min
local task_spawn = task.spawn
local task_wait = task.wait
local table_clear = table.clear
local table_insert = table.insert
local table_clone = table.clone
local Instance_new = Instance.new
local Vector3_new = Vector3.new
local PhysProps_new = PhysicalProperties.new
local CFrame_new = CFrame.new

limbData.playerCache    = limbData.playerCache    or {}
limbData.instanceLookup = limbData.instanceLookup or setmetatable({}, { __mode = "k" })
limbData.npcIdCounter   = limbData.npcIdCounter   or 0
limbData.fakeSignals     = limbData.fakeSignals     or setmetatable({}, { __mode = "k" })
limbData.partData        = limbData.partData        or setmetatable({}, { __mode = "k" })
limbData._wrappedParts   = limbData._wrappedParts   or setmetatable({}, { __mode = "k" })
limbData._hookedSignals  = limbData._hookedSignals  or setmetatable({}, { __mode = "k" })
limbData._migratedConns  = limbData._migratedConns  or setmetatable({}, { __mode = "k" })

limbData._hookedInstances = limbData._hookedInstances or setmetatable({}, { __mode = "k" })
limbData._originalMT      = limbData._originalMT      or setmetatable({}, { __mode = "k" })

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
    Size = true, Transparency = true, CanCollide = true, Massless = true,
    Mass = true, AssemblyMass = true, AssemblyCenterOfMass = true,
    CustomPhysicalProperties = true, CurrentPhysicalProperties = true, RootPriority = true,
}

local WRITTEN_PROPS = {
    "Size", "Transparency", "CanCollide", "Massless",
    "CustomPhysicalProperties", "RootPriority",
    "Mass", "AssemblyMass", "AssemblyCenterOfMass" 
}
local ESP_SOURCE_URL = "https://raw.githubusercontent.com/AAPVdev/scripts/refs/heads/main/esp/SIXSEVENESP.lua"
local MANAGER_SOURCE_URL = "https://raw.githubusercontent.com/AAPVdev/scripts/refs/heads/main/manager/manager.lua"

local function ensureESPLoaded()
    if limbData.ESP then return limbData.ESP end
    if not (has_loadstring and has_httpget) then return nil end
    local ok, res = pcall(function() return loadstring(game:HttpGet(ESP_SOURCE_URL))() end)
    if ok then limbData.ESP = res end
    return limbData.ESP
end

local function ensureMANAGERLoaded()
    if limbData.manager then return limbData.manager end
    if not (has_loadstring and has_httpget) then return nil end
    local ok, res = pcall(function() return loadstring(game:HttpGet(MANAGER_SOURCE_URL))() end)
    if ok then limbData.manager = res end
    return limbData.manager
end

local function fireSignalsForProp(limb, prop)
    firesignal(limb.Changed, prop)
    local sig = limb:GetPropertyChangedSignal(prop)
    firesignal(sig)
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
    local ratio = origVol / newVol
    local newDensity = math_max(0.01, origPhys.Density * ratio)
    return PhysProps_new(newDensity, origPhys.Friction, origPhys.Elasticity, origPhys.FrictionWeight, origPhys.ElasticityWeight)
end

limbData._isWriting = false

local function wrapPartSignals(limb)
    if limbData._wrappedParts[limb] then return end
    limbData._wrappedParts[limb] = true

    local function hookSignalConnect(signal, signalName)
        if limbData._hookedSignals[signal] then return end
        limbData._hookedSignals[signal] = true

        local origConnect = signal.Connect
        local function newConnect(self, callback)
            local wrapped = newcclosure(function(...)
                if not limbData._isWriting then
                    return callback(...)
                end
            end)
            return origConnect(self, wrapped)
        end
        origConnect = hookfunction(origConnect, newConnect)

        local connections = getconnections(signal)
        for _, conn in ipairs(connections) do
            local origCallback = conn.Function
            if origCallback and not limbData._migratedConns[conn] then
                local function wrappedCallback(...)
                    if not limbData._isWriting then
                        return origCallback(...)
                    end
                end
                origCallback = hookfunction(origCallback, wrappedCallback)
                limbData._migratedConns[conn] = true
            end
        end
    end

    hookSignalConnect(limb.Changed, ".Changed")

    for _, prop in ipairs(WRITTEN_PROPS) do
        local ok, sig = pcall(limb.GetPropertyChangedSignal, limb, prop)
        if ok and sig then
            hookSignalConnect(sig, "GPC:" .. prop)
        end
    end
end

local function hookPart(part)
    if limbData._hookedInstances[part] then return end
    local mt = getrawmetatable(part)
    setreadonly(mt, false)
    local oldIndex = mt.__index
    local oldNewIndex = mt.__newindex
    limbData._originalMT[part] = {__index = oldIndex, __newindex = oldNewIndex}
    mt.__index = function(self, key)
        if limbData._bypassHooks then return oldIndex(self, key) end
        if not checkcaller() then
            local entryData = limbData.instanceLookup[self]
            if entryData and entryData.type == "Part" and self == entryData.data.Limb and BLOCKED_PROPS[key] then
                if key == "Size" then return entryData.data.OriginalSize end
                if key == "Transparency" then return entryData.data.OriginalTransparency end
                if key == "CanCollide" then return entryData.data.OriginalCanCollide end
                if key == "Massless" then return entryData.data.OriginalMassless end
                if key == "Mass" then local density = entryData.data.OriginalDensity or getPartDensity(self); local size = entryData.data.OriginalSize; return density * (size.X * size.Y * size.Z) end
                if key == "AssemblyMass" then local density = entryData.data.OriginalDensity or getPartDensity(self); local size = entryData.data.OriginalSize; return density * (size.X * size.Y * size.Z) end
                if key == "AssemblyCenterOfMass" then local size = entryData.data.OriginalSize; return self.Position + Vector3_new(size.X * 0.001, size.Y * 0.001, size.Z * 0.001) end
                if key == "CustomPhysicalProperties" then return entryData.data.OriginalPhysProps end
                if key == "CurrentPhysicalProperties" then return entryData.data.OriginalPhysProps end
                if key == "RootPriority" then return entryData.data.OriginalRootPriority end
            end
        end
        return oldIndex(self, key)
    end
    mt.__newindex = function(self, key, value)
        if limbData._bypassHooks then return oldNewIndex(self, key, value) end
        local entryData = limbData.instanceLookup[self]
        if entryData and entryData.type == "Part" and self == entryData.data.Limb and BLOCKED_PROPS[key] then
            if key == "Size" then entryData.data.OriginalSize = value
            elseif key == "Transparency" then entryData.data.OriginalTransparency = value
            elseif key == "CanCollide" then entryData.data.OriginalCanCollide = value
            elseif key == "Massless" then entryData.data.OriginalMassless = value
            elseif key == "Mass" then entryData.data.OriginalMass = value
            elseif key == "AssemblyMass" then entryData.data.OriginalAssemblyMass = value
            elseif key == "AssemblyCenterOfMass" then entryData.data.OriginalAssemblyCOM = value
            elseif key == "CustomPhysicalProperties" then entryData.data.OriginalPhysProps = value
            elseif key == "RootPriority" then entryData.data.OriginalRootPriority = value
            end
            fireSignalsForProp(self, key)
            return
        end
        return oldNewIndex(self, key, value)
    end
    setreadonly(mt, true)
    limbData._hookedInstances[part] = true
end

local function hookModel(model)
    if limbData._hookedInstances[model] then return end
    local mt = getrawmetatable(model)
    setreadonly(mt, false)
    local oldIndex = mt.__index
    limbData._originalMT[model] = {__index = oldIndex, __newindex = mt.__newindex}
    mt.__index = function(self, key)
        if limbData._bypassHooks then return oldIndex(self, key) end
        if not checkcaller() then
            local entryData = limbData.instanceLookup[self]
            if entryData and entryData.type == "Model" and self == entryData.data.Character and key == "ExtentsSize" then
                return entryData.data.OriginalExtents
            end
        end
        return oldIndex(self, key)
    end
    
    setreadonly(mt, true)
    limbData._hookedInstances[model] = true
end

local function unhookInstance(instance)
    if not limbData._hookedInstances[instance] then return end
    local mt = getrawmetatable(instance)
    setreadonly(mt, false)
    local orig = limbData._originalMT[instance]
    if orig then
        mt.__index = orig.__index
        mt.__newindex = orig.__newindex
    end
    limbData._originalMT[instance] = nil
    limbData._hookedInstances[instance] = nil
    setreadonly(mt, true)
end

function getTargetData(instance)
    if typeof(instance) ~= "Instance" then return nil, nil end
    local cached = limbData.instanceLookup[instance]
    if cached then return cached.data, cached.type end
    for _, cache in pairs(limbData.playerCache) do
        if cache.Limb == instance then
            limbData.instanceLookup[instance] = { data = cache, type = "Part" }
            return cache, "Part"
        elseif cache.Character == instance then
            limbData.instanceLookup[instance] = { data = cache, type = "Model" }
            return cache, "Model"
        end
    end
    return nil, nil
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
    ESP_NEAR_FLAGS   = { Box = true, Tracer = true, Skeleton = true, Health = true, Label = true, Box3D = false },
    ESP_MEDIUM_FLAGS = { Box = true, Tracer = true, Skeleton = false, Health = true, Label = true, Box3D = false },
    ESP_FAR_FLAGS    = { Box = true, Tracer = true, Skeleton = false, Health = false, Label = false, Box3D = false },
    ESP_TEXT_RESOLVER = nil,
    ESP_CAN_DRAW      = nil,
    ESP_TRACER_ORIGIN = nil,
}

local function mergeSettings(user)
    local s = table_clone(DEFAULTS)
    if type(user) == "table" then for k, v in pairs(user) do s[k] = v end end
    if type(s.NPC_DIRECTORIES) == "table" then s.NPC_DIRECTORIES = table_clone(s.NPC_DIRECTORIES) else s.NPC_DIRECTORIES = {} end
    for _, key in ipairs({ "ESP_NEAR_FLAGS", "ESP_MEDIUM_FLAGS", "ESP_FAR_FLAGS" }) do
        if type(s[key]) == "table" then s[key] = table_clone(s[key]) end
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

    local managerModule = ensureMANAGERLoaded()
    if not managerModule then error("Failed to load manager module") end

    local function isLiveInstance(instance)
        return typeof(instance) == "Instance" and instance.Parent ~= nil
    end
    local Manager = managerModule.Manager

    local function sharedSaveData(parent, cacheKey, char, limb)
        local cache = parent._playerCache
        local entry = cache[cacheKey]
        if entry then
            if entry.Limb and entry.Limb ~= limb then limbData.instanceLookup[entry.Limb] = nil end
            if entry.Character and entry.Character ~= char then limbData.instanceLookup[entry.Character] = nil end
        else
            entry = {}
            cache[cacheKey] = entry
        end
        entry.Character = char
        entry.Limb = limb
        entry.OriginalSize = limb.Size
        entry.OriginalTransparency = limb.Transparency
        entry.OriginalCanCollide = limb.CanCollide
        entry.OriginalMassless = limb.Massless
        entry.OriginalMass = limb.Mass
        entry.OriginalAssemblyMass = limb.AssemblyMass
        entry.OriginalAssemblyCOM = limb.AssemblyCenterOfMass
        entry.OriginalExtents = char:GetExtentsSize()
        entry.OriginalPhysProps = limb.CustomPhysicalProperties or PhysProps_new(limb.Material)
        entry.OriginalRootPriority = limb.RootPriority or 0
        entry.OriginalDensity = getPartDensitySafe(limb)
        limbData.instanceLookup[limb] = { data = entry, type = "Part" }
        limbData.instanceLookup[char] = { data = entry, type = "Model" }
    end

    local function silentWrite(limb, props)
        limbData._isWriting = true
        limbData._bypassHooks = true
        for k, v in pairs(props) do
            pcall(function() limb[k] = v end)
        end
        limbData._bypassHooks = false
        limbData._isWriting = false
    end

    local function sharedApplyLimb(parent, cacheKey, char, limb)
        if not isLiveInstance(limb) or not limb.Parent then return end
        sharedSaveData(parent, cacheKey, char, limb)

        hookPart(limb)
        hookModel(char)

        wrapPartSignals(limb)

        local entry = parent._playerCache[cacheKey]
        if not entry then return end

        local settings = parent._settings
        local newVec = Vector3_new(settings.LIMB_SIZE, settings.LIMB_SIZE, settings.LIMB_SIZE)
        local trans = settings.LIMB_TRANSPARENCY
        local colide = settings.LIMB_CAN_COLLIDE
        local isHRP = (limb.Name == "HumanoidRootPart")
        local newPhys = isHRP and getAdjustedPhysicalProperties(limb, entry.OriginalSize, newVec) or nil
        local props = { Size = newVec, Transparency = trans, CanCollide = colide }
        if isHRP then
            props.Massless = false
            if newPhys then props.CustomPhysicalProperties = newPhys end
        else
            props.Massless = true
            props.RootPriority = -127
        end

        silentWrite(limb, props)

        if not colide then
            local humanoid = char:FindFirstChildOfClass("Humanoid")
            if humanoid then
                local function forceCollisions()
                    if not isLiveInstance(limb) or not limb.Parent then return end
                    silentWrite(limb, { CanCollide = false })
                end
                entry._humanoidStateConn = humanoid.StateChanged:Connect(forceCollisions)
                forceCollisions()
            end
        end
    end

    local function sharedRestoreLimb(parent, cacheKey, activeLimb)
        local cache = parent._playerCache
        local entry = cache[cacheKey]
        if not entry then return end
        if activeLimb and isLiveInstance(activeLimb) and activeLimb.Parent then
            if entry._humanoidStateConn then pcall(function() entry._humanoidStateConn:Disconnect() end) end
            local props = {
                Size = entry.OriginalSize,
                Transparency = entry.OriginalTransparency,
                CanCollide = entry.OriginalCanCollide,
                Massless = entry.OriginalMassless,
                CustomPhysicalProperties = entry.OriginalPhysProps,
                RootPriority = entry.OriginalRootPriority,
            }
            silentWrite(activeLimb, props)
        end
        if entry.Limb then
            unhookInstance(entry.Limb)
            limbData.instanceLookup[entry.Limb] = nil
        end
        if entry.Character then
            unhookInstance(entry.Character)
            limbData.instanceLookup[entry.Character] = nil
        end
        if activeLimb and activeLimb ~= entry.Limb then
            unhookInstance(activeLimb)
            limbData.instanceLookup[activeLimb] = nil
        end
        cache[cacheKey] = nil
    end

    local function reapplyCosmeticToEntry(entry, settings)
        local limb = entry.Limb
        if not isLiveInstance(limb) or not limb.Parent then return end
        if entry._humanoidStateConn then pcall(function() entry._humanoidStateConn:Disconnect() end) end
        local newVec = Vector3_new(settings.LIMB_SIZE, settings.LIMB_SIZE, settings.LIMB_SIZE)
        local trans = settings.LIMB_TRANSPARENCY
        local colide = settings.LIMB_CAN_COLLIDE
        local isHRP = (limb.Name == "HumanoidRootPart")
        local newPhys = isHRP and getAdjustedPhysicalProperties(limb, entry.OriginalSize, newVec) or nil
        local props = { Size = newVec, Transparency = trans, CanCollide = colide }
        if isHRP then
            props.Massless = false
            if newPhys then props.CustomPhysicalProperties = newPhys end
        else
            props.Massless = true
            props.RootPriority = -127
        end
        silentWrite(limb, props)

        if not colide then
            local humanoid = entry.Character and entry.Character:FindFirstChildOfClass("Humanoid")
            if humanoid then
                local function forceCollisions()
                    if not isLiveInstance(limb) or not limb.Parent then return end
                    silentWrite(limb, { CanCollide = false })
                end
                entry._humanoidStateConn = humanoid.StateChanged:Connect(forceCollisions)
                forceCollisions()
            end
        end
    end

    function self:_applyLimbs(player, char, limb)
        if not isLiveInstance(limb) or not limb.Parent then return end
        local cacheKey
        if player then cacheKey = player.Name
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
                task_spawn(function()
                    local attempts = 0
                    while not self._ESP:Track(char) and attempts < 30 do task_wait(0.1); attempts = attempts + 1 end
                end)
            end
        end
    end

    function self:_removeLimbs(player, char, limb)
        local cacheKey = player and player.Name or self._npcIdMap[char]
        sharedRestoreLimb(self, cacheKey, limb)
        if self._ESP and char then self._ESP:Untrack(char) end
        if not player then self._npcIdMap[char] = nil end
    end

    function self:_doRestart()
        if not self._running then return end
        self._suppressOnLimbLost = true
        self._manager:Stop()
        local cache = self._playerCache
        local keys = {}
        for k in pairs(cache) do table_insert(keys, k) end
        local BATCH_SIZE = 10
        for i = 1, #keys, BATCH_SIZE do
            if not self._running then break end
            local last = math_min(i + BATCH_SIZE - 1, #keys)
            for j = i, last do local key = keys[j]; local entry = cache[key]; if entry then sharedRestoreLimb(self, key, entry.Limb) end end
            task_wait()
        end
        self._suppressOnLimbLost = false
        table_clear(cache)
        if self._ESP then self._ESP:Stop() end
        if not self._running then return end
        self._manager:Start()
        if self._ESP then self._ESP:Start() end
    end

    function self:_doCosmeticUpdate()
        if not self._running then return end
        local BATCH_SIZE = 10
        local settings = self._settings
        local entries = {}
        for _, entry in pairs(self._playerCache) do if entry.Limb and entry.Character then table_insert(entries, entry) end end
        for i = 1, #entries, BATCH_SIZE do
            if self._needsRestart or not self._running then return end
            local last = math_min(i + BATCH_SIZE - 1, #entries)
            for j = i, last do reapplyCosmeticToEntry(entries[j], settings) end
            task_wait()
        end
    end

    function self:_processWork()
        while self._running and (self._needsRestart or self._needsCosmeticUpdate) do
            if self._needsRestart then self._needsRestart = false; self:_doRestart()
            elseif self._needsCosmeticUpdate then self._needsCosmeticUpdate = false; self:_doCosmeticUpdate() end
        end
        self._workRunning = false
    end

    self._manager = Manager.new({
        PLAYER_ENABLED = self._settings.PLAYER_ENABLED,
        NPC_ENABLED = self._settings.NPC_ENABLED,
        NPC_FILTER = self._settings.NPC_FILTER,
        NPC_DIRECTORIES = self._settings.NPC_DIRECTORIES,
        TARGET_LIMB = self._settings.TARGET_LIMB,
        TEAM_CHECK = self._settings.TEAM_CHECK,
        FORCEFIELD_CHECK = self._settings.FORCEFIELD_CHECK,
        DEATH_RESTORE = self._settings.ALT_RESET_LIMB_ON_DEATH,
        GET_LOCAL_TEAM = function() return localPlayer.Team end,
        ON_LIMB_READY = function(player, model, limb) self:_applyLimbs(player, model, limb) end,
        ON_LIMB_LOST = function(player, model, limb) self:_removeLimbs(player, model, limb) end,
    })

    if self._settings.ESP then
        local espModule = ensureESPLoaded()
        if espModule then self._ESP = espModule.new(self:_buildESPConfig()) else self._settings.ESP = false end
    end

    limbData.terminate = function() self:Destroy() end
    return self
end

function LimbExtender:_buildESPConfig()
    local s = self._settings
    local function applyToggles(flags)
        return {
            Box = s.ESP_BOX and flags.Box,
            Box3D = s.ESP_BOX3D and flags.Box3D,
            Tracer = s.ESP_TRACER and flags.Tracer,
            Skeleton = s.ESP_SKELETON and flags.Skeleton,
            Health = s.ESP_HEALTH and flags.Health,
            Label = s.ESP_LABEL and flags.Label,
        }
    end
    return {
        Color = s.ESP_COLOR,
        Box3DColor = s.ESP_BOX3D_COLOR,
        HealthColor = s.ESP_HEALTH_COLOR,
        EmptyColor = s.ESP_EMPTY_COLOR,
        SkeletonColor = s.ESP_SKELETON_COLOR,
        TextColor = s.ESP_TEXT_COLOR,
        TextSize = s.ESP_TEXT_SIZE,
        UseOffscreenPoint = s.ESP_OFFSCREEN_POINT,
        FilterLocalCharacter = s.ESP_FILTER_LOCAL,
        LOD = {
            MaxDistance = s.ESP_MAX_DISTANCE,
            NearDistance = s.ESP_NEAR_DISTANCE,
            MediumDistance = s.ESP_MEDIUM_DISTANCE,
            OcclusionEnabled = s.ESP_OCCLUSION,
            OcclusionFrequency = s.ESP_OCCLUSION_FREQUENCY,
        },
        Flags = {
            Near = applyToggles(s.ESP_NEAR_FLAGS),
            Medium = applyToggles(s.ESP_MEDIUM_FLAGS),
            Far = applyToggles(s.ESP_FAR_FLAGS),
        },
        TextResolver = s.ESP_TEXT_RESOLVER,
        CanDraw = s.ESP_CAN_DRAW,
        TracerOrigin = s.ESP_TRACER_ORIGIN,
    }
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
    for cacheKey, entry in pairs(self._playerCache) do sharedRestoreLimb(self, cacheKey, entry.Limb) end
    table_clear(self._playerCache)
    
    for instance in pairs(limbData._hookedInstances) do
        unhookInstance(instance)
    end
    if self._ESP then self._ESP:Stop() end
end

function LimbExtender:Toggle(state)
    if type(state) == "boolean" then if state then self:Start() else self:Stop() end
    else if self._running then self:Stop() else self:Start() end end
end

function LimbExtender:Restart()
    local wasRunning = self._running
    self:Stop()
    if wasRunning then self:Start() end
end

function LimbExtender:Set(key, value)
    local function mergeTables(target, source)
        for k, v in pairs(source) do
            if type(v) == "table" and type(target[k]) == "table" then mergeTables(target[k], v) else target[k] = v end
        end
    end
    local isLodKey = (key == "ESP_NEAR_FLAGS" or key == "ESP_MEDIUM_FLAGS" or key == "ESP_FAR_FLAGS")
    if isLodKey then
        if type(self._settings[key]) ~= "table" then self._settings[key] = {} end
        mergeTables(self._settings[key], value)
    else
        if self._settings[key] ~= value then self._settings[key] = value else return end
    end
    if key == "ESP" then
        if value then
            self.ESP = ensureESPLoaded()
            if self.ESP then
                if not self._ESP then
                    self._ESP = self.ESP.new(self:_buildESPConfig())
                    if self._running then
                        for _, entry in pairs(self._playerCache) do if entry.Character then self._ESP:Track(entry.Character) end end
                        self._ESP:Start()
                    end
                end
            else self._settings.ESP = false end
        else if self._ESP then self._ESP:Destroy(); self._ESP = nil end end
        return
    end
    if type(key) == "string" and key:sub(1,4) == "ESP_" then
        if self._ESP then
            self._ESP:SetOptions(self:_buildESPConfig())
            if key == "ESP_CAN_DRAW" then self._ESP.Config.CanDraw = value
            elseif key == "ESP_TEXT_RESOLVER" then self._ESP.Config.TextResolver = value
            elseif key == "ESP_TRACER_ORIGIN" then self._ESP.Config.TracerOrigin = value end
        end
        return
    end
    local RESTART_KEYS = { PLAYER_ENABLED = true, NPC_ENABLED = true, NPC_FILTER = true, TARGET_LIMB = true, TEAM_CHECK = true, FORCEFIELD_CHECK = true, ALT_RESET_LIMB_ON_DEATH = true, NPC_DIRECTORIES = true }
    local managerKey = key
    if key == "ALT_RESET_LIMB_ON_DEATH" then managerKey = "DEATH_RESTORE" end
    if RESTART_KEYS[key] then
        if key == "TARGET_LIMB" then limbData.targetLimbName = value end
        if key == "NPC_DIRECTORIES" then self._manager._settings.NPC_DIRECTORIES = value
        elseif key == "ALT_RESET_LIMB_ON_DEATH" then self._manager:Set("DEATH_RESTORE", value)
        else self._manager:Set(managerKey, value) end
        self._needsRestart = true
    else
        self._needsCosmeticUpdate = true
    end
    if self._running and not self._workRunning then
        self._workRunning = true
        task_spawn(function() task_wait(); self:_processWork() end)
    end
end

function LimbExtender:Get(key) return self._settings[key] end
function LimbExtender:AddDirectory(dir) self._manager:AddDirectory(dir) end
function LimbExtender:RemoveDirectory(dir) self._manager:RemoveDirectory(dir) end
function LimbExtender:GetDirectories() return self._manager:GetDirectories() end

function LimbExtender:Destroy()
    self:Stop()
    self._running = false
    self._needsRestart = false
    self._needsCosmeticUpdate = false
    self._destroyed = true
    
    for instance in pairs(limbData._hookedInstances) do
        unhookInstance(instance)
    end
    if self._ESP then self._ESP:Destroy(); self._ESP = nil end
    limbData.terminate = nil
    setmetatable(self, nil)
end

return setmetatable({}, {
    __call = function(_, userSettings) return LimbExtender.new(userSettings) end,
    __index = LimbExtender,
})
