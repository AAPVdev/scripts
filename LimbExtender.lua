local function missing(t, f, fallback)
	if type(f) == t then return f end
	return fallback
end

local cloneref    = missing("function", cloneref, function(obj) return obj end)
local checkcaller = type(checkcaller) == "function" and checkcaller or function() return true end

local Players   = cloneref(game:GetService("Players"))
local Workspace = cloneref(game:GetService("Workspace"))

local localPlayer = Players.LocalPlayer
if not localPlayer then
	Players:GetPropertyChangedSignal("LocalPlayer"):Wait()
	localPlayer = Players.LocalPlayer
end

local type, typeof            = type, typeof
local pcall                   = pcall
local pairs, ipairs           = pairs, ipairs
local tostring, setmetatable  = tostring, setmetatable
local math_max                = math.max
local task_spawn              = task.spawn
local task_defer              = task.defer
local task_wait               = task.wait
local task_delay              = task.delay   
local table_clear             = table.clear
local table_insert            = table.insert
local table_remove            = table.remove
local table_clone             = table.clone
local string_split            = string.split
local string_gsub             = string.gsub
local Instance_new            = Instance.new
local Vector3_new             = Vector3.new
local PhysProps_new           = PhysicalProperties.new

local function _safeGet(obj, key) return obj[key] end
local function _disconnect(conn) conn:Disconnect() end

local ConnectionManager = {}
ConnectionManager.__index = ConnectionManager

function ConnectionManager.new()
	return setmetatable({ _conns = {}, _labels = {} }, ConnectionManager)
end

function ConnectionManager:_register(conn, label)
	if label then
		local prev = self._labels[label]
		if prev then
			if prev.Connected then prev:Disconnect() end
			self._conns[prev] = nil
		end
		self._labels[label] = conn
	end
	self._conns[conn] = true
end

function ConnectionManager:Connect(signal, fn, label)
	if not signal or not fn then return nil end
	local conn = signal:Connect(fn)
	self:_register(conn, label)
	return conn
end

function ConnectionManager:Prune()
	for conn in pairs(self._conns) do
		if not conn.Connected then self._conns[conn] = nil end
	end
end

function ConnectionManager:DisconnectAll()
	for conn in pairs(self._conns) do
		if conn.Connected then conn:Disconnect() end
	end
	table_clear(self._conns)
	table_clear(self._labels)
end

function ConnectionManager:Destroy()
	self:DisconnectAll()
	setmetatable(self, nil)
end

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
	return s
end

local globalEnv = type(getgenv) == "function" and getgenv() or _G
local limbData = globalEnv.limbExtenderData or {}
globalEnv.limbExtenderData = limbData

limbData.playerCache    = limbData.playerCache    or {}
limbData.instanceLookup = limbData.instanceLookup or setmetatable({}, { __mode = "k" })
limbData.npcIdCounter   = limbData.npcIdCounter   or 0

if not limbData.dummyEvent then
	limbData.dummyEvent = Instance_new("BindableEvent")
end

limbData.changedProxies = limbData.changedProxies or setmetatable({}, { __mode = "k" })

if type(limbData.terminate) == "function" then
	limbData.terminate()
	limbData.terminate = nil
end

local CONN_KEYS = { "SizeConn", "TransConn", "CollConn", "PhysConn", "MasslessConn", "RootPriorityConn" }
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

local has_newcclosure    = type(newcclosure)    == "function"
local has_hookmetamethod = type(hookmetamethod) == "function"
local has_loadstring     = type(loadstring)     == "function"
local has_httpget = pcall(function()
	local f = game.HttpGet
	if type(f) ~= "function" then error("not callable") end
end)

if not limbData._spoofInstalled and has_newcclosure and has_hookmetamethod then
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
		if not checkcaller() then
			local self, key, value = ...
			local data, instType = getTargetData(self)
					
			if data and instType == "Part" then
				if key == "Size"                     then data.OriginalSize         = value return end
				if key == "Transparency"             then data.OriginalTransparency  = value return end
				if key == "CanCollide"               then data.OriginalCanCollide    = value return end
				if key == "Massless"                 then data.OriginalMassless      = value return end
				if key == "Mass" or key == "AssemblyMass" or key == "AssemblyCenterOfMass" then return end
				if key == "CustomPhysicalProperties" then data.OriginalPhysProps     = value return end
				if key == "RootPriority"             then data.OriginalRootPriority  = value return end
			end
		end
		return oldNewIndex(...)
	end))

	local oldIndex
	oldIndex = hookmetamethod(game, "__index", newcclosure(function(...)
		if not checkcaller() then
			local self, key = ...
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
		local method = getnamecallmethod()
		local args = {...}
		local self = args[1]
				
		if not checkcaller() then
			local data, instType = getTargetData(self)

			if data then
				if instType == "Part" then
					if method == "GetMass" then return data.OriginalMass end
					if method == "GetConnectedParts" then
						return oldNamecall(...)
					end
					if method == "GetPropertyChangedSignal" then
						local prop = args[1]
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

local PlayerData = {}
PlayerData.__index = PlayerData

function PlayerData.new(parent, player)
	local self = setmetatable({
		_parent     = parent,
		player      = player,
		_cacheKey   = player.Name,
		playerConns = ConnectionManager.new(),
		charConns   = ConnectionManager.new(),
		_activeLimb = nil,
		_destroyed  = false,
	}, PlayerData)

	self.playerConns:Connect(player.CharacterAdded,    function(c) self:_setupCharacter(c) end)
	self.playerConns:Connect(player.CharacterRemoving, function(c) self:_restoreLimb(c)    end)

	self.playerConns:Connect(player:GetPropertyChangedSignal("Team"), function()
		if self._destroyed then return end
		if self._parent:_isTeam(self.player) then
			self:_restoreLimb()
		elseif self.player.Character then
			self:_setupCharacter(self.player.Character)
		end
	end)
	if player.Character then self:_setupCharacter(player.Character) end

	task_spawn(function()
		while not self._destroyed do
			task_wait(2)
			if self._destroyed then break end
			if not self._activeLimb and not self._parent:_isTeam(self.player) then
				local char = self.player and self.player.Character
				if char and char:IsDescendantOf(game) then
					local target = char:FindFirstChild(self._parent._settings.TARGET_LIMB)
					if target and target:IsDescendantOf(char) then
						pcall(function() self:_setupCharacter(char) end)
					end
				end
			end
		end
	end)

	return self
end

function PlayerData:_restoreLimb()
	local char = self._activeLimb and self._activeLimb.Parent
	sharedRestoreLimb(self._parent, self._cacheKey, self._activeLimb)
	if self._parent._ESP and char then
		self._parent._ESP:Untrack(char)
	end
	self._activeLimb = nil
end

function PlayerData:_applyLimb(char, limb)
	if self._destroyed then return end
	sharedApplyLimb(self._parent, self._cacheKey, char, limb)
	self._activeLimb = limb
end

function PlayerData:_setupCharacter(char)
	if self._parent:_isTeam(self.player) or self._destroyed or not char then return end

	self.charConns:DisconnectAll()

	local function retry()
		if not self._destroyed and char:IsDescendantOf(game) then
			task_defer(function()
				if not self._destroyed and char:IsDescendantOf(game) then
					self:_setupCharacter(char)
				end
			end)
		end
	end

	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		self.charConns:Connect(char.ChildAdded, function(child)
			if child:IsA("Humanoid") then retry() end
		end)
		self.charConns:Connect(char.AncestryChanged, function()
			if not char:IsDescendantOf(game) then self:_restoreLimb() end
		end)
		if char:FindFirstChildOfClass("Humanoid") then retry() end
		return
	end

	if humanoid.Health <= 0 or self._destroyed then
		self.charConns:Connect(humanoid:GetPropertyChangedSignal("Health"), function()
			if humanoid.Health > 0 then retry() end
		end)
		self.charConns:Connect(char.ChildAdded, function(child)
			if child:IsA("Humanoid") then retry() end
		end)
		if not self._destroyed and humanoid.Health > 0 then retry() end
		return
	end

	if self._parent._settings.FORCEFIELD_CHECK then
		local function onFFAppeared(ff)
			self:_restoreLimb()
			self.charConns:Connect(ff.AncestryChanged, function()
				if not ff:IsDescendantOf(char) then retry() end
			end)
		end

		self.charConns:Connect(char.ChildAdded, function(child)
			if child:IsA("ForceField") then onFFAppeared(child) end
		end, "FFChildWatch")

		local ff = char:FindFirstChildOfClass("ForceField")
		if ff then
			onFFAppeared(ff)
			return
		end
	end

	local target = char:FindFirstChild(self._parent._settings.TARGET_LIMB)
	if not target then
		self.charConns:Connect(char.ChildAdded, function(child)
			if child.Name == self._parent._settings.TARGET_LIMB then retry() end
		end)
		self.charConns:Connect(char.AncestryChanged, function()
			if not char:IsDescendantOf(game) then self:_restoreLimb() end
		end)
		if char:FindFirstChild(self._parent._settings.TARGET_LIMB) then retry() end
		return
	end

	if not self._destroyed then
		pcall(function() self:_applyLimb(char, target) end)
		if self._parent._ESP then
			self._parent._ESP:Track(char)
		end

		self.charConns:Connect(char.AncestryChanged, function()
			if not char:IsDescendantOf(game) then self:_restoreLimb() end
		end)

		self.charConns:Connect(target.AncestryChanged, function()
			if target:IsDescendantOf(char) then return end
			sharedRestoreLimb(self._parent, self._cacheKey, self._activeLimb)
			if self._parent._ESP then
				self._parent._ESP:Untrack(char)
			end
			self._activeLimb = nil
			self.charConns:Connect(char.ChildAdded, function(child)
				if child.Name == self._parent._settings.TARGET_LIMB then
					task_defer(function()
						if not self._destroyed and char:IsDescendantOf(game) then
							self:_setupCharacter(char)
						end
					end)
				end
			end, "LimbRespawn")
		end, "LimbStream")

		local deathEvent
		if self._parent._settings.ALT_RESET_LIMB_ON_DEATH then
			deathEvent = humanoid.HealthChanged
		else
			deathEvent = humanoid.Died
		end

		self.charConns:Connect(deathEvent, function()
			if humanoid.Health <= 0 then
				self:_restoreLimb()
			end
		end)
	end
end

function PlayerData:Destroy()
	self._destroyed = true
	self:_restoreLimb()
	if self.charConns   then self.charConns:Destroy()   end
	if self.playerConns then self.playerConns:Destroy() end
	setmetatable(self, nil)
end

local NPCData = {}
NPCData.__index = NPCData

function NPCData.new(parent, char)
	limbData.npcIdCounter = limbData.npcIdCounter + 1
	local self = setmetatable({
		_parent     = parent,
		char        = char,
		_cacheKey   = "__npc_" .. limbData.npcIdCounter,
		charConns   = ConnectionManager.new(),
		_activeLimb = nil,
		_destroyed  = false,
	}, NPCData)

	self:_setup()

	task_spawn(function()
		while not self._destroyed do
			task_wait(2)
			if self._destroyed then break end
			if not self._activeLimb then
				local char = self.char
				if char and char:IsDescendantOf(game) then
					local target = char:FindFirstChild(self._parent._settings.TARGET_LIMB)
					if target and target:IsDescendantOf(char) then
						pcall(function() self:_setup() end)
					end
				end
			end
		end
	end)

	return self
end

function NPCData:_restoreLimb()
	local char = self._activeLimb and self._activeLimb.Parent
	sharedRestoreLimb(self._parent, self._cacheKey, self._activeLimb)
	if self._parent._ESP and char then
		self._parent._ESP:Untrack(char)
	end
	self._activeLimb = nil
end

function NPCData:_applyLimb(char, limb)
	if self._destroyed then return end
	sharedApplyLimb(self._parent, self._cacheKey, char, limb)
	self._activeLimb = limb
end

function NPCData:_setup()
	if self._destroyed then return end
	local char = self.char

	self.charConns:DisconnectAll()
	if not char:IsDescendantOf(game) then return end

	local function retry()
		if not self._destroyed and char:IsDescendantOf(game) then
			task_defer(function()
				if not self._destroyed and char:IsDescendantOf(game) then
					self:_setup()
				end
			end)
		end
	end

	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		self.charConns:Connect(char.ChildAdded, function(child)
			if child:IsA("Humanoid") then retry() end
		end)
		if char:FindFirstChildOfClass("Humanoid") then retry() end
		return
	end

	if humanoid.Health <= 0 then
		self.charConns:Connect(humanoid:GetPropertyChangedSignal("Health"), function()
			if humanoid.Health > 0 then retry() end
		end)
		self.charConns:Connect(char.ChildAdded, function(child)
			if child:IsA("Humanoid") then retry() end
		end)
		if humanoid.Health > 0 then retry() end
		return
	end

	if self._parent._settings.FORCEFIELD_CHECK then
		local ff = char:FindFirstChildOfClass("ForceField")
		if ff then
			self.charConns:Connect(ff.Destroying, function() retry() end)
			return
		end
		self.charConns:Connect(char.ChildAdded, function(child)
			if child:IsA("ForceField") then
				self:_restoreLimb()
				self.charConns:Connect(child.Destroying, function() retry() end)
			end
		end)
	end

	local target = char:FindFirstChild(self._parent._settings.TARGET_LIMB)
	if not target then
		self.charConns:Connect(char.ChildAdded, function(child)
			if child.Name == self._parent._settings.TARGET_LIMB then retry() end
		end)
		if char:FindFirstChild(self._parent._settings.TARGET_LIMB) then retry() end
		return
	end

	if not self._destroyed then
		self:_applyLimb(char, target)

		if self._parent._ESP then
			self._parent._ESP:Track(char)
		end

		self.charConns:Connect(char.AncestryChanged, function()
			if not char:IsDescendantOf(game) then self:_restoreLimb() end
		end)

		self.charConns:Connect(target.AncestryChanged, function()
			if target:IsDescendantOf(char) then return end
			sharedRestoreLimb(self._parent, self._cacheKey, self._activeLimb)
			if self._parent._ESP then
				self._parent._ESP:Untrack(char)
			end
			self._activeLimb = nil
			self.charConns:Connect(char.ChildAdded, function(child)
				if child.Name == self._parent._settings.TARGET_LIMB then
					task_defer(function()
						if not self._destroyed and char:IsDescendantOf(game) then
							self:_setup()
						end
					end)
				end
			end, "LimbRespawn")
		end, "LimbStream")

		local deathEvent
		if self._parent._settings.ALT_RESET_LIMB_ON_DEATH then
			deathEvent = humanoid.HealthChanged
		else
			deathEvent = humanoid.Died
		end

		self.charConns:Connect(deathEvent, function()
			if humanoid.Health <= 0 then
				self:_restoreLimb()
			end
		end)
	end
end

function NPCData:Destroy()
	self._destroyed = true
	self:_restoreLimb()
	if self.charConns then self.charConns:Destroy() end
	setmetatable(self, nil)
end

local function isLiveInstance(inst)
	if typeof(inst) ~= "Instance" then return false end
	local ok, result = pcall(inst.IsDescendantOf, inst, game)
	return ok and result
end

local function normalizeDirectoryPath(path)
	path = tostring(path or "")
	path = string_gsub(path, "^%s+", "")
	path = string_gsub(path, "%s+$", "")
	path = string_gsub(path, "^game:GetService%(%s*['\"]([^'\"]+)['\"]%s*%)", "%1")
	path = string_gsub(path, "^game%.", "")

	if path:sub(1, 9):lower() == "workspace" then
		path = "Workspace" .. path:sub(10)
	end

	path = string_gsub(path, ":%s*WaitForChild%(%s*['\"]([^'\"]+)['\"]%s*%)", ".%1")
	path = string_gsub(path, ":%s*FindFirstChild%(%s*['\"]([^'\"]+)['\"]%s*%)", ".%1")
	path = string_gsub(path, "%[%s*['\"]([^'\"]+)['\"]%s*%]", ".%1")
	path = string_gsub(path, "%.+", ".")
	path = string_gsub(path, "^%.", "")
	path = string_gsub(path, "%.$", "")

	return path
end

local function resolvePathAsync(path, timeoutPerPart)
	timeoutPerPart = timeoutPerPart or 5
	if type(path) ~= "string" or path == "" then return nil end

	path = normalizeDirectoryPath(path)

	local parts = string_split(path, ".")
	if #parts == 0 then return nil end

	local head = (parts[1] or ""):lower()
	local current

	if head == "game" then
		current = game
		table_remove(parts, 1)
	elseif head == "workspace" then
		current = Workspace
		table_remove(parts, 1)
	else
		
		local ok, service = pcall(game.GetService, game, parts[1])
		if ok and service then
			current = service
			table_remove(parts, 1)
		else
			current = Workspace
		end
	end

	for _, part in ipairs(parts) do
		if part ~= "" then
			current = current:WaitForChild(part, timeoutPerPart)
			if not current then return nil end
		end
	end

	return current
end

local LimbExtender = {}
LimbExtender.__index = LimbExtender

function LimbExtender.new(userSettings)
	local self = setmetatable({
		_settings         = mergeSettings(userSettings),
		_playerCache      = limbData.playerCache,
		_playerTable      = {},
		_npcTable         = {},
		_connections      = ConnectionManager.new(),
		_ESP              = nil,
		_running          = false,
		_destroyed        = false,
		_generation       = 0,
		_playerCharacters = {},
	}, LimbExtender)

	limbData.terminate = function() self:Destroy() end

	if has_loadstring and has_httpget then
		if self._settings.ESP then
			if not limbData.ESP then
				local ok, res = pcall(function()
					return loadstring(game:HttpGet("https://raw.githubusercontent.com/AAPVdev/scripts/refs/heads/main/esp/SIXSEVENESP.lua"))()
				end)
				if ok then limbData.ESP = res end
			end
			self.ESP = limbData.ESP
			if self.ESP then
				self._ESP = self.ESP.new(self:_buildESPConfig())
			end
		end
	end

	return self
end

function LimbExtender:_isTeam(player)
	if not self._settings.TEAM_CHECK then return false end
	local myTeam = localPlayer and localPlayer.Team
	return myTeam ~= nil and player.Team == myTeam
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

function LimbExtender:AddDirectory(dir)
	if not isLiveInstance(dir) and type(dir) ~= "string" then return end
	local dirs = self._settings.NPC_DIRECTORIES
	if type(dirs) ~= "table" then
		self._settings.NPC_DIRECTORIES = { dir }
	else
		for _, d in ipairs(dirs) do
			if d == dir then return end
		end
		table_insert(dirs, dir)
	end
	self:Restart()
end

function LimbExtender:RemoveDirectory(dir)
	local dirs = self._settings.NPC_DIRECTORIES
	if type(dirs) ~= "table" then return end
	for i, d in ipairs(dirs) do
		if d == dir then
			table_remove(dirs, i)
			if #dirs == 0 then self._settings.NPC_DIRECTORIES = nil end
			self:Restart()
			return
		end
	end
end

function LimbExtender:GetDirectories()
	local dirs = self._settings.NPC_DIRECTORIES
	if type(dirs) == "table" and #dirs > 0 then
		return table_clone(dirs)
	end
	return {}
end

function LimbExtender:_isValidNPC(model)
	if not model:IsA("Model") then return false end
	if self._playerCharacters[model] then return false end

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then return false end

	local filter = self._settings.NPC_FILTER
	if type(filter) == "function" then
		local ok, result = pcall(filter, model)
		if not ok or not result then return false end
	end

	return true
end

function LimbExtender:_registerNPC(model)
	if self._destroyed then return end
	if model and model:IsA("Humanoid") then model = model.Parent end
	if not model or not model:IsA("Model") then return end
	if self._npcTable[model] then return end
	if self:_isValidNPC(model) then
		self._npcTable[model] = NPCData.new(self, model)
	end
end

function LimbExtender:_activateDirectory(dir, useDescendants)
	self:_registerNPC(dir)
	local children = useDescendants and dir:GetDescendants() or dir:GetChildren()
	for _, desc in ipairs(children) do
		self:_registerNPC(desc)
	end
	if useDescendants then
		self._connections:Connect(dir.DescendantAdded, function(desc)
			task_defer(function()
				if self._running and not self._destroyed then
					self:_registerNPC(desc)
				end
			end)
		end)
		self._connections:Connect(dir.DescendantRemoving, function(desc)
			local nd = self._npcTable[desc]
			if nd then nd:Destroy(); self._npcTable[desc] = nil end
		end)
	else
		self._connections:Connect(dir.ChildAdded, function(desc)
			task_defer(function()
				if self._running and not self._destroyed then
					self:_registerNPC(desc)
				end
			end)
		end)
		self._connections:Connect(dir.ChildRemoved, function(desc)
			local nd = self._npcTable[desc]
			if nd then nd:Destroy(); self._npcTable[desc] = nil end
		end)
	end
end

function LimbExtender:Start()
	if self._destroyed or self._running then return end
	self._running = true

	if not self._connections then
		self._connections = ConnectionManager.new()
	end

	if self._ESP then
		self._ESP:Start()
	end

	if self._settings.NPC_ENABLED then
		table_clear(self._playerCharacters)

		local function trackPlayer(p)
			if p.Character then self._playerCharacters[p.Character] = true end
			self._connections:Connect(p.CharacterAdded, function(char)
				self._playerCharacters[char] = true
				local nd = self._npcTable[char]
				if nd then nd:Destroy(); self._npcTable[char] = nil end
			end)
			self._connections:Connect(p.CharacterRemoving, function(char)
				self._playerCharacters[char] = nil
			end)
		end

		for _, p in ipairs(Players:GetPlayers()) do
			trackPlayer(p)
		end

		self._connections:Connect(Players.PlayerAdded, function(p)
			trackPlayer(p)
		end)

		self._connections:Connect(Players.PlayerRemoving, function(p)
			if p.Character then self._playerCharacters[p.Character] = nil end
		end)
	else
		table_clear(self._playerCharacters)
	end

	if self._settings.PLAYER_ENABLED then
		self._connections:Connect(Players.PlayerAdded, function(p)
			if p ~= localPlayer then self._playerTable[p.Name] = PlayerData.new(self, p) end
		end)
		self._connections:Connect(Players.PlayerRemoving, function(p)
			if self._playerTable[p.Name] then
				self._playerTable[p.Name]:Destroy()
				self._playerTable[p.Name] = nil
			end
		end)

		for _, p in ipairs(Players:GetPlayers()) do
			if p ~= localPlayer then self._playerTable[p.Name] = PlayerData.new(self, p) end
		end

		if self._settings.TEAM_CHECK then
			self._connections:Connect(localPlayer:GetPropertyChangedSignal("Team"), function()
				if self._destroyed then return end
				for _, pd in pairs(self._playerTable) do
					if pd._destroyed then continue end
					if self:_isTeam(pd.player) then
						pd:_restoreLimb()
					elseif pd.player.Character then
						pd:_setupCharacter(pd.player.Character)
					end
				end
			end)
		end
	end

	if self._settings.NPC_ENABLED then
		local dirs = self._settings.NPC_DIRECTORIES
		local hasUserDirs = type(dirs) == "table" and #dirs > 0
		local entries = hasUserDirs and dirs or { Workspace }

		for _, entry in ipairs(entries) do
			if isLiveInstance(entry) then
				self:_activateDirectory(entry, not hasUserDirs)
			elseif type(entry) == "string" then
				local gen = self._generation
				task_spawn(function()
					local resolved = resolvePathAsync(entry)
					if resolved and self._running and not self._destroyed and self._generation == gen then
						self:_activateDirectory(resolved, not hasUserDirs)
					end
				end)
			end
		end
	end
end

function LimbExtender:Stop()
	if self._destroyed or not self._running then return end
	self._running = false
	self._generation = self._generation + 1

	if self._connections then
		self._connections:Destroy()
		self._connections = nil
	end

	for _, pd in pairs(self._playerTable) do pd:Destroy() end
	table_clear(self._playerTable)

	for _, nd in pairs(self._npcTable) do nd:Destroy() end
	table_clear(self._npcTable)

	table_clear(self._playerCharacters)

	if self._ESP then
		self._ESP:Stop()
	end
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
	if self._settings[key] ~= value then
		self._settings[key] = value

		if key == "ESP" then
			if value then
				if not limbData.ESP and has_loadstring and has_httpget then
					local ok, res = pcall(function()
						return loadstring(game:HttpGet(
							"https://raw.githubusercontent.com/AAPVdev/scripts/refs/heads/main/esp/SIXSEVENESP.lua"
						))()
					end)
					if ok then limbData.ESP = res end
				end
				self.ESP = limbData.ESP
				if self.ESP and not self._ESP then
					self._ESP = self.ESP.new(self:_buildESPConfig())
					if self._running then self._ESP:Start() end
				end
			else
				if self._ESP then
					self._ESP:Destroy()
					self._ESP = nil
				end
			end

		elseif self._ESP and type(key) == "string" and key:sub(1, 4) == "ESP_" then
			self._ESP:SetOptions(self:_buildESPConfig())

			if key == "ESP_CAN_DRAW" then
				self._ESP.Config.CanDraw = value
			elseif key == "ESP_TEXT_RESOLVER" then
				self._ESP.Config.TextResolver = value
			elseif key == "ESP_TRACER_ORIGIN" then
				self._ESP.Config.TracerOrigin = value
			end
		end
		self:Restart()
	end
end

function LimbExtender:Get(key)
	return self._settings[key]
end

function LimbExtender:Destroy()
	self:Stop()
	self._destroyed = true

	if self._connections then
		self._connections:Destroy()
		self._connections = nil
	end

	if self._ESP then
		self._ESP:Destroy()
		self._ESP = nil
	end
	limbData.terminate = nil
	setmetatable(self, nil)
end

return setmetatable({}, { __call = function(_, userSettings) return LimbExtender.new(userSettings) end, __index = LimbExtender })
