local function missing(t, f, fallback)
	if type(f) == t then return f end
	return fallback
end

local cloneref    = missing("function", cloneref, function(obj) return obj end)
local checkcaller = type(checkcaller) == "function" and checkcaller or function() return true end

local Players          = cloneref(game:GetService("Players"))
local UserInputService = cloneref(game:GetService("UserInputService"))
local Workspace        = cloneref(game:GetService("Workspace"))

local localPlayer = Players.LocalPlayer
if not localPlayer then
	Players:GetPropertyChangedSignal("LocalPlayer"):Wait()
	localPlayer = Players.LocalPlayer
end

local type, typeof = type, typeof
local pcall, math_max = pcall, math.max

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
	table.clear(self._conns)
	table.clear(self._labels)
end

function ConnectionManager:Destroy()
	self:DisconnectAll()
	setmetatable(self, nil)
end

local DEFAULTS = {
	TOGGLE              = "L",
	TARGET_LIMB         = "Head",
	LIMB_SIZE           = 15,
	LIMB_TRANSPARENCY   = 0.5,
	LIMB_CAN_COLLIDE    = false,
	MOBILE_BUTTON       = false,
	LISTEN_FOR_INPUT    = true,
	TEAM_CHECK          = true,
	FORCEFIELD_CHECK    = false,
	RESET_LIMB_ON_DEATH = false,
	PLAYER_ENABLED      = true,
	NPC_ENABLED         = false,
	NPC_FILTER          = nil,
	NPC_DIRECTORIES     = {},
}

local function mergeSettings(user)
	local s = table.clone(DEFAULTS)
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
	limbData.dummyEvent = Instance.new("BindableEvent")
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

	if has_loadstring and has_httpget then
		loadstring(game:HttpGet("https://raw.githubusercontent.com/Pixeluted/adoniscries/main/Source.lua"))()
	end

	local function getTargetData(instance)
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

	local oldNewIndex
	oldNewIndex = hookmetamethod(game, "__newindex", newcclosure(function(self, key, value)
		if not checkcaller() then
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
		return oldNewIndex(self, key, value)
	end))

	local oldIndex
	oldIndex = hookmetamethod(game, "__index", newcclosure(function(self, key)
		if not checkcaller() then
			local data, instType = getTargetData(self)
			if data then
				if instType == "Part" then
					if key == "Size"                     then return data.OriginalSize         end
					if key == "Transparency"             then return data.OriginalTransparency  end
					if key == "CanCollide"               then return data.OriginalCanCollide    end
					if key == "Massless"                 then return data.OriginalMassless      end
					if key == "Mass"                     then return data.OriginalMass         end
					if key == "AssemblyMass"             then return data.OriginalAssemblyMass end
					if key == "AssemblyCenterOfMass"     then return data.OriginalAssemblyCOM  end
					if key == "CustomPhysicalProperties" then return data.OriginalPhysProps     end
					if key == "RootPriority"             then return data.OriginalRootPriority  end
				elseif instType == "Model" then
					if key == "ExtentsSize"              then return data.OriginalExtents       end
				elseif instType == "CharPart" then
					if key == "AssemblyMass"             then return data.OriginalAssemblyMass end
					if key == "AssemblyCenterOfMass"     then return data.OriginalAssemblyCOM  end
				end
			end
		end
		return oldIndex(self, key)
	end))

	local oldNamecall
	oldNamecall = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
		local method = getnamecallmethod()
		local args = {...}

		if not checkcaller() then
			local data, instType = getTargetData(self)

			if data then
				if instType == "Part" then
					if method == "GetMass" then return data.OriginalMass end
					if method == "GetConnectedParts" then
						return oldNamecall(self, ...)
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
						local cf, _ = oldNamecall(self, ...)
						return cf, data.OriginalExtents
					end
				end
			end
		end
		return oldNamecall(self, ...)
	end))
end

local function watchProperty(instance, prop, callback)
	if not instance then return end
	if not pcall(function() return instance[prop] end) then return end

	local lastVal = instance[prop]
	return instance:GetPropertyChangedSignal(prop):Connect(function()
		local ok, curVal = pcall(function() return instance[prop] end)
		if ok and curVal ~= lastVal then
			pcall(callback, instance)
			local ok2, newVal = pcall(function() return instance[prop] end)
			if ok2 then lastVal = newVal end
		end
	end)
end

local function proportionalSize(original, targetMax)
	local maxAxis = math_max(original.X, original.Y, original.Z)
	if maxAxis <= 0 then return Vector3.new(targetMax, targetMax, targetMax) end
	local scaled = original * (targetMax / maxAxis)
	return Vector3.new(math_max(0.05, scaled.X), math_max(0.05, scaled.Y), math_max(0.05, scaled.Z))
end

local function getAdjustedPhysicalProperties(limb, origSize, newSize)
	local origPhys = limb.CustomPhysicalProperties or PhysicalProperties.new(limb.Material)

	local origVol = origSize.X * origSize.Y * origSize.Z
	local newVol  = newSize.X  * newSize.Y  * newSize.Z
	if newVol <= 0 then newVol = 1 end

	local ratio      = origVol / newVol
	local newDensity = math_max(0.01, origPhys.Density * ratio)

	return PhysicalProperties.new(
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
					table.insert(preExistingConns, conn)
				end
			end)
		end

		local proxy = limbData.changedProxies[limb]
		if not proxy then
			local proxyBE  = Instance.new("BindableEvent")
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
			local fn
			pcall(function() fn = conn.Function end)
			if fn and fn ~= proxy.filterFn then
				pcall(function() conn:Disconnect() end)
				pcall(function() proxy.be.Event:Connect(fn) end)
			end
		end
		proxy.filter.enabled = true
	end
	local charParts = {}
	for _, part in ipairs(char:GetDescendants()) do
		if part:IsA("BasePart") and part ~= limb then
			limbData.instanceLookup[part] = { data = entry, type = "CharPart" }
			table.insert(charParts, part)
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

	local newVec = proportionalSize(entry.OriginalSize, cfg.LIMB_SIZE)
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
		entry.MasslessConn = watchProperty(limb, "Massless", function(l) l.Massless = true end)
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

	self.playerConns:Connect(player.CharacterAdded, function(c) self:_setupCharacter(c) end)
	self.playerConns:Connect(player:GetPropertyChangedSignal("Team"), function()
		if self._destroyed then return end
		if self._parent:_isTeam(self.player) then
			self:_restoreLimb()
		elseif self.player.Character then
			self:_setupCharacter(self.player.Character)
		end
	end)
	if player.Character then self:_setupCharacter(player.Character) end

	return self
end

function PlayerData:_restoreLimb()
	sharedRestoreLimb(self._parent, self._cacheKey, self._activeLimb)
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
			task.defer(function()
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
		return
	end

	if humanoid.Health <= 0 or self._destroyed then
		self.charConns:Connect(humanoid:GetPropertyChangedSignal("Health"), function()
			if humanoid.Health > 0 then retry() end
		end)
		self.charConns:Connect(char.ChildAdded, function(child)
			if child:IsA("Humanoid") then retry() end
		end)
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
		return
	end

	if not self._destroyed then
		self:_applyLimb(char, target)

		self.charConns:Connect(char.AncestryChanged, function()
			if not char:IsDescendantOf(game) then self:_restoreLimb() end
		end)

		self.charConns:Connect(humanoid.Died, function()
			if self._parent._settings.RESET_LIMB_ON_DEATH then self:_restoreLimb() end
		end)
	end
end

function PlayerData:Destroy()
	self._destroyed = true
	self:_restoreLimb()
	if self.charConns then self.charConns:Destroy() end
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
	return self
end

function NPCData:_restoreLimb()
	sharedRestoreLimb(self._parent, self._cacheKey, self._activeLimb)
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
			task.defer(function()
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
		return
	end

	if humanoid.Health <= 0 then
		self.charConns:Connect(humanoid:GetPropertyChangedSignal("Health"), function()
			if humanoid.Health > 0 then retry() end
		end)
		self.charConns:Connect(char.ChildAdded, function(child)
			if child:IsA("Humanoid") then retry() end
		end)
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
		return
	end

	if not self._destroyed then
		self:_applyLimb(char, target)

		self.charConns:Connect(char.AncestryChanged, function()
			if not char:IsDescendantOf(game) then self:_restoreLimb() end
		end)

		self.charConns:Connect(humanoid.Died, function()
			if self._parent._settings.RESET_LIMB_ON_DEATH then self:_restoreLimb() end
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
	local ok, result = pcall(function() return inst:IsDescendantOf(game) end)
	return ok and result
end

local function normalizeDirectoryPath(path)
	path = tostring(path or "")
	path = path:gsub("^%s+", ""):gsub("%s+$", "")

	path = path:gsub("^game:GetService%(%s*['\"]([^'\"]+)['\"]%s*%)", "%1")

	path = path:gsub("^game%.", "")

	if path:sub(1, 9):lower() == "workspace" then
		path = "Workspace" .. path:sub(10)
	end

	path = path:gsub(":%s*WaitForChild%(%s*['\"]([^'\"]+)['\"]%s*%)", ".%1")
	path = path:gsub(":%s*FindFirstChild%(%s*['\"]([^'\"]+)['\"]%s*%)", ".%1")

	path = path:gsub("%[%s*['\"]([^'\"]+)['\"]%s*%]", ".%1")

	path = path:gsub("%.+", ".")
	path = path:gsub("^%.", ""):gsub("%.$", "")

	return path
end

local function resolvePathAsync(path, timeoutPerPart)
	timeoutPerPart = timeoutPerPart or 5
	if type(path) ~= "string" or path == "" then return nil end

	path = normalizeDirectoryPath(path)

	local parts = string.split(path, ".")
	if #parts == 0 then return nil end

	local head = (parts[1] or ""):lower()
	local current

	if head == "game" then
		current = game
		table.remove(parts, 1)
	elseif head == "workspace" then
		current = Workspace
		table.remove(parts, 1)
	else
		local ok, service = pcall(function()
			return game:GetService(parts[1])
		end)
		if ok and service then
			current = service
			table.remove(parts, 1)
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
		_settings    = mergeSettings(userSettings),
		_playerCache = limbData.playerCache,
		_playerTable = {},
		_npcTable    = {},
		_connections = ConnectionManager.new(),
		_inputConn   = nil,
		_CAU         = nil,
		_running     = false,
		_destroyed   = false,
		_generation  = 0,
		_playerCharacters = {},
	}, LimbExtender)

	limbData.terminate = function() self:Destroy() end

	if self._settings.LISTEN_FOR_INPUT then
		if not limbData.CAU and has_loadstring and has_httpget then
			local ok, res = pcall(function()
				return loadstring(game:HttpGet("https://raw.githubusercontent.com/AAPVdev/modules/refs/heads/main/ContextActionUtility.lua"))()
			end)
			if ok then limbData.CAU = res end
		end

		self._CAU = limbData.CAU

		if self._CAU then
			self._CAU:BindAction("LimbExtenderToggle", function(_, inputState)
				if inputState == Enum.UserInputState.Begin then self:Toggle() end
			end, self._settings.MOBILE_BUTTON, Enum.KeyCode[self._settings.TOGGLE])
		else
			self._inputConn = UserInputService.InputBegan:Connect(function(input, processed)
				if not processed and input.KeyCode == Enum.KeyCode[self._settings.TOGGLE] then
					self:Toggle()
				end
			end)
		end
	end
	return self
end

function LimbExtender:_isTeam(player)
	if not self._settings.TEAM_CHECK then return false end
	local myTeam = localPlayer and localPlayer.Team
	return myTeam ~= nil and player.Team == myTeam
end

function LimbExtender:SetDirectories(dirs)
	if type(dirs) == "table" and #dirs > 0 then
		local valid = {}
		for _, d in ipairs(dirs) do
			if isLiveInstance(d) or type(d) == "string" then
				table.insert(valid, d)
			end
		end
		self._settings.NPC_DIRECTORIES = #valid > 0 and valid or nil
	else
		self._settings.NPC_DIRECTORIES = nil
	end
	self:Restart()
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
		table.insert(dirs, dir)
	end
	self:Restart()
end

function LimbExtender:RemoveDirectory(dir)
	local dirs = self._settings.NPC_DIRECTORIES
	if type(dirs) ~= "table" then return end
	for i, d in ipairs(dirs) do
		if d == dir then
			table.remove(dirs, i)
			if #dirs == 0 then self._settings.NPC_DIRECTORIES = nil end
			self:Restart()
			return
		end
	end
end

function LimbExtender:GetDirectories()
	local dirs = self._settings.NPC_DIRECTORIES
	if type(dirs) == "table" and #dirs > 0 then
		return table.clone(dirs)
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
			task.defer(function()
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
			task.defer(function()
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

	if self._settings.NPC_ENABLED then
		table.clear(self._playerCharacters)

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
		table.clear(self._playerCharacters)
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
				task.spawn(function()
					local resolved = resolvePathAsync(entry)
					if resolved and self._running and not self._destroyed and self._generation == gen then
						self:_activateDirectory(resolved, not hasUserDirs)
					end
				end)
			end
		end
	end

	if self._CAU and self._settings.MOBILE_BUTTON then
		self._CAU:SetTitle("LimbExtenderToggle", "Hitbox: ON")
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
	table.clear(self._playerTable)

	for _, nd in pairs(self._npcTable) do nd:Destroy() end
	table.clear(self._npcTable)

	table.clear(self._playerCharacters)

	if self._CAU and self._settings.MOBILE_BUTTON then
		self._CAU:SetTitle("LimbExtenderToggle", "Hitbox: OFF")
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
		self:Restart()
	end
end

function LimbExtender:Get(key)
	return self._settings[key]
end

function LimbExtender:Destroy()
	self:Stop()
	self._destroyed = true

	if self._inputConn then
		self._inputConn:Disconnect()
		self._inputConn = nil
	end
	if self._CAU then
		self._CAU:UnbindAction("LimbExtenderToggle")
	end
	limbData.terminate = nil
	setmetatable(self, nil)
end

return setmetatable({}, { __call = function(_, userSettings) return LimbExtender(userSettings) end, __index = LimbExtender, })
