local function missing(t, f, fallback)
	if type(f) == t then return f end
	return fallback
end

local cloneref = missing("function", cloneref, function(obj) return obj end)

local Players = cloneref(game:GetService("Players"))
local Workspace = cloneref(game:GetService("Workspace"))

local localPlayer = Players.LocalPlayer
if not localPlayer then
	Players:GetPropertyChangedSignal("LocalPlayer"):Wait()
	localPlayer = Players.LocalPlayer
end

local table_clear = table.clear
local table_remove = table.remove
local table_insert = table.insert
local table_clone = table.clone
local task_spawn = task.spawn
local task_defer = task.defer
local string_split = string.split
local string_gsub = string.gsub

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
	PLAYER_ENABLED = true,
	NPC_ENABLED = false,
	NPC_FILTER = nil,
	NPC_DIRECTORIES = {},

	ON_CHARACTER_ADDED = nil,
	ON_CHARACTER_REMOVING = nil,
	ON_NPC_ADDED = nil,
	ON_NPC_REMOVING = nil,

	TARGET_LIMB = nil,
	TEAM_CHECK = false,
	FORCEFIELD_CHECK = false,
	DEATH_RESTORE = false,
	GET_LOCAL_TEAM = nil,
	ON_LIMB_READY = nil,
	ON_LIMB_LOST = nil,
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

	if not s.GET_LOCAL_TEAM then
		s.GET_LOCAL_TEAM = function() return localPlayer.Team end
	end

	return s
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

local function isLiveInstance(inst)
	if typeof(inst) ~= "Instance" then return false end
	local ok, result = pcall(inst.IsDescendantOf, inst, game)
	return ok and result
end

local StreamObserver = {}
StreamObserver.__index = StreamObserver

function StreamObserver.new(model, onAvailable, onUnavailable)
	local self = setmetatable({
		_model = model,
		_onAvailable = onAvailable,
		_onUnavailable = onUnavailable,

		_modelConns = ConnectionManager.new(),
		_anchorConns = ConnectionManager.new(),

		_active = false,
		_destroyed = false,
		_anchor = nil,
	}, StreamObserver)

	self:_bindModelSignals()
	self:_refresh()

	return self
end

function StreamObserver:_resolveAnchor()
	local model = self._model
	if not isLiveInstance(model) or not model:IsA("Model") then return nil end

	local root = model.PrimaryPart
	if not isLiveInstance(root) or not root:IsDescendantOf(model) then
		root = model:FindFirstChild("HumanoidRootPart")
	end

	if root and isLiveInstance(root) then return root end
	return nil
end

function StreamObserver:_bindModelSignals()
	if self._destroyed then return end
	local model = self._model
	if not isLiveInstance(model) then return end

	self._modelConns:Connect(model.AncestryChanged, function() self:_refresh() end, "AncestryChanged")
	self._modelConns:Connect(model.ChildAdded, function() self:_refresh() end, "ChildAdded")
	self._modelConns:Connect(model.ChildRemoved, function() self:_refresh() end, "ChildRemoved")
	self._modelConns:Connect(model:GetPropertyChangedSignal("PrimaryPart"), function() self:_refresh() end, "PrimaryPart")
end

function StreamObserver:_bindAnchor(anchor)
	self._anchor = anchor
	self._anchorConns:Destroy()
	self._anchorConns = ConnectionManager.new()

	if not anchor or not isLiveInstance(anchor) then return end

	self._anchorConns:Connect(anchor:GetPropertyChangedSignal("Parent"), function() self:_refresh() end, "Parent")
	self._anchorConns:Connect(anchor.AncestryChanged, function() self:_refresh() end, "AncestryChanged")
end

function StreamObserver:_setActive(active)
	if self._active == active then return end
	self._active = active

	local model = self._model
	if active then
		local cb = self._onAvailable
		if type(cb) == "function" then pcall(cb, model) end
	else
		local cb = self._onUnavailable
		if type(cb) == "function" then pcall(cb, model) end
	end
end

function StreamObserver:_refresh()
	if self._destroyed then return end

	local model = self._model
	if not isLiveInstance(model) then
		self:_bindAnchor(nil)
		self:_setActive(false)
		return
	end

	local anchor = self:_resolveAnchor()
	if anchor ~= self._anchor then self:_bindAnchor(anchor) end

	local available = anchor ~= nil and isLiveInstance(anchor) and isLiveInstance(model)
	self:_setActive(available)
end

function StreamObserver:Destroy()
	if self._destroyed then return end
	self._destroyed = true

	if self._active then
		self._active = false
		local cb = self._onUnavailable
		if type(cb) == "function" then pcall(cb, self._model) end
	end

	self._anchorConns:Destroy()
	self._modelConns:Destroy()

	setmetatable(self, nil)
end

local LimbObserver = {}
LimbObserver.__index = LimbObserver

function LimbObserver.new(manager, model, playerObject)
	local self = setmetatable({
		_manager = manager,
		_model = model,
		_player = playerObject,
		_ready = false,
		_limb = nil,
		_conns = ConnectionManager.new(),
		_forcefieldWatcher = nil,
		_deathConn = nil,
	}, LimbObserver)

	self:_start()
	return self
end

function LimbObserver:_start()
	if not isLiveInstance(self._model) then
		self:_notifyLost()
		return
	end

	local function tryResolve()
		if self._ready then return end
		if self._player and self._manager._settings.TEAM_CHECK then
			local myTeam = self._manager._settings.GET_LOCAL_TEAM()
			if myTeam and self._player.Team == myTeam then return end
		end

		if self._manager._settings.FORCEFIELD_CHECK then
			local ff = self._model:FindFirstChildOfClass("ForceField")
			if ff then
				if not self._forcefieldWatcher then
					self._forcefieldWatcher = ff.AncestryChanged:Connect(function()
						if not ff:IsDescendantOf(self._model) then
							self._forcefieldWatcher:Disconnect()
							self._forcefieldWatcher = nil
							tryResolve()
						end
					end)
				end
				return
			end
		end

		local limb = self._model:FindFirstChild(self._manager._settings.TARGET_LIMB)
		if limb and limb:IsA("BasePart") then
			self:_onLimbFound(limb)
		else
			self._conns:Connect(self._model.ChildAdded, function(child)
				if child.Name == self._manager._settings.TARGET_LIMB and child:IsA("BasePart") then
					self._conns:DisconnectAll()
					tryResolve()
				end
			end, "WaitLimb")
		end
	end

	self._conns:Connect(self._model.AncestryChanged, function()
		if not isLiveInstance(self._model) then
			self:_notifyLost()
		end
	end)

	tryResolve()
end

function LimbObserver:_onLimbFound(limb)
	self._limb = limb
	self._ready = true

	self._conns:Connect(limb.AncestryChanged, function()
		if not limb:IsDescendantOf(self._model) then
			self:_limbRemoved()
		end
	end, "LimbStream")

	if self._manager._settings.DEATH_RESTORE then
		local humanoid = self._model:FindFirstChildOfClass("Humanoid")
		if humanoid then
			self._conns:Connect(humanoid.Died, function()
				self:_notifyLost()
			end)
		end
	end

	local player = self._player
	self._manager:_onLimbReady(player, self._model, limb)
end

function LimbObserver:_limbRemoved()
	self._ready = false
	local oldLimb = self._limb
	self._limb = nil
	self._manager:_onLimbLost(self._player, self._model, oldLimb)

	self._conns:DisconnectAll()
	self:_start()
end

function LimbObserver:_notifyLost()
	self._ready = false
	local oldLimb = self._limb
	self._limb = nil
	self._manager:_onLimbLost(self._player, self._model, oldLimb)
	self._conns:Destroy()
end

function LimbObserver:Destroy()
	self._conns:Destroy()
	self._ready = false
	self._limb = nil
end

local PlayerData = {}
PlayerData.__index = PlayerData

function PlayerData.new(parent, player)
	local self = setmetatable({
		_parent = parent,
		player = player,
		conns = ConnectionManager.new(),
		_destroyed = false,
		_characterObserver = nil,
		_limbObserver = nil,
	}, PlayerData)

	self.conns:Connect(player.CharacterAdded, function(char)
		self:_onCharacterAdded(char)
	end, "CharacterAdded")

	self.conns:Connect(player.CharacterRemoving, function(char)
		self:_onCharacterRemoving(char)
	end, "CharacterRemoving")

	if self._parent._settings.TARGET_LIMB and self._parent._settings.TEAM_CHECK then
		self.conns:Connect(player:GetPropertyChangedSignal("Team"), function()
			if self._limbObserver then
				self._limbObserver:Destroy()
				self._limbObserver = nil
			end
			if self._character and isLiveInstance(self._character) then
				self:_setupLimbTracking(self._character)
			end
		end)
	end

	if player.Character then
		self:_onCharacterAdded(player.Character)
	end

	return self
end

function PlayerData:_setupLimbTracking(char)
	if self._destroyed or not isLiveInstance(char) then return end
	if self._limbObserver then
		self._limbObserver:Destroy()
	end
	self._limbObserver = LimbObserver.new(self._parent, char, self.player)
end

function PlayerData:_onCharacterAdded(char)
	if self._destroyed or not isLiveInstance(char) or not char:IsA("Model") then return end

	if self._characterObserver then
		self._characterObserver:Destroy()
		self._characterObserver = nil
	end

	self._character = char

	local parent = self._parent
	self._characterObserver = StreamObserver.new(char, function(model)
		if self._destroyed then return end
		local cb = parent._settings.ON_CHARACTER_ADDED
		if type(cb) == "function" then pcall(cb, self.player, model) end
		if parent._settings.TARGET_LIMB then
			self:_setupLimbTracking(model)
		end
	end, function(model)
		if self._destroyed then return end
		local cb = parent._settings.ON_CHARACTER_REMOVING
		if type(cb) == "function" then pcall(cb, self.player, model) end
		if self._limbObserver then
			self._limbObserver:Destroy()
			self._limbObserver = nil
		end
	end)
end

function PlayerData:_onCharacterRemoving(char)
	if self._destroyed then return end

	if self._characterObserver then
		self._characterObserver:Destroy()
		self._characterObserver = nil
	end

	if self._limbObserver then
		self._limbObserver:Destroy()
		self._limbObserver = nil
	end

	if self._character == char then
		self._character = nil
	end
end

function PlayerData:Destroy()
	self._destroyed = true

	if self._characterObserver then
		self._characterObserver:Destroy()
		self._characterObserver = nil
	end
	if self._limbObserver then
		self._limbObserver:Destroy()
		self._limbObserver = nil
	end

	self.conns:Destroy()
	setmetatable(self, nil)
end

local Manager = {}
Manager.__index = Manager

function Manager.new(userSettings)
	local self = setmetatable({
		_settings = mergeSettings(userSettings),
		_playerTable = {},
		_npcSet = {},
		_npcLimbObservers = {},
		_connections = nil,
		_running = false,
		_destroyed = false,
		_generation = 0,
	}, Manager)

	return self
end

function Manager:_onLimbReady(player, model, limb)
	local cb = self._settings.ON_LIMB_READY
	if type(cb) == "function" then
		pcall(cb, player, model, limb)
	end
end

function Manager:_onLimbLost(player, model, limb)
	local cb = self._settings.ON_LIMB_LOST
	if type(cb) == "function" then
		pcall(cb, player, model, limb)
	end
end

function Manager:_isValidNPC(model)
	if not model or not model:IsA("Model") then return false end
	if not model:FindFirstChildOfClass("Humanoid") then return false end

	local filter = self._settings.NPC_FILTER
	if type(filter) == "function" then
		local ok, result = pcall(filter, model)
		if not ok or not result then return false end
	end
	return true
end

function Manager:_registerNPC(model)
	if self._destroyed or not model then return end
	if model:IsA("Humanoid") then model = model.Parent end
	if not model or self._npcSet[model] then return end
	if not self:_isValidNPC(model) then return end

	local observer = StreamObserver.new(model,
		function(npcModel)
			if self._destroyed then return end
			local cb = self._settings.ON_NPC_ADDED
			if type(cb) == "function" then pcall(cb, npcModel) end
			if self._settings.TARGET_LIMB and not self._npcLimbObservers[npcModel] then
				self._npcLimbObservers[npcModel] = LimbObserver.new(self, npcModel, nil)
			end
		end,
		function(npcModel)
			if self._destroyed then return end
			local cb = self._settings.ON_NPC_REMOVING
			if type(cb) == "function" then pcall(cb, npcModel) end
			local limbObs = self._npcLimbObservers[npcModel]
			if limbObs then
				limbObs:Destroy()
				self._npcLimbObservers[npcModel] = nil
			end
		end
	)
	self._npcSet[model] = observer
end

function Manager:_unregisterNPC(model)
	local observer = self._npcSet[model]
	if observer then
		observer:Destroy()
		self._npcSet[model] = nil
	end
	local limbObs = self._npcLimbObservers[model]
	if limbObs then
		limbObs:Destroy()
		self._npcLimbObservers[model] = nil
	end
end

function Manager:_activateDirectory(dir, useDescendants)
	self:_registerNPC(dir)
	local children = useDescendants and dir:GetDescendants() or dir:GetChildren()
	for _, desc in ipairs(children) do
		self:_registerNPC(desc)
	end

	if useDescendants then
		self._connections:Connect(dir.DescendantAdded, function(desc)
			task_defer(function()
				if self._running and not self._destroyed then self:_registerNPC(desc) end
			end)
		end, tostring(dir) .. "_DescendantAdded")
		self._connections:Connect(dir.DescendantRemoving, function(desc)
			self:_unregisterNPC(desc)
		end, tostring(dir) .. "_DescendantRemoving")
	else
		self._connections:Connect(dir.ChildAdded, function(desc)
			task_defer(function()
				if self._running and not self._destroyed then self:_registerNPC(desc) end
			end)
		end, tostring(dir) .. "_ChildAdded")
		self._connections:Connect(dir.ChildRemoved, function(desc)
			self:_unregisterNPC(desc)
		end, tostring(dir) .. "_ChildRemoved")
	end
end

function Manager:Start()
	if self._destroyed or self._running then return end
	self._running = true
	self._connections = ConnectionManager.new()

	if self._settings.PLAYER_ENABLED then
		self._connections:Connect(Players.PlayerAdded, function(p)
			if p ~= localPlayer then
				self._playerTable[p] = PlayerData.new(self, p)
			end
		end, "PlayerAdded")
		self._connections:Connect(Players.PlayerRemoving, function(p)
			local pd = self._playerTable[p]
			if pd then
				pd:Destroy()
				self._playerTable[p] = nil
			end
		end, "PlayerRemoving")

		for _, p in ipairs(Players:GetPlayers()) do
			if p ~= localPlayer and not self._playerTable[p] then
				self._playerTable[p] = PlayerData.new(self, p)
			end
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

function Manager:Stop()
	if self._destroyed or not self._running then return end
	self._running = false
	self._generation = self._generation + 1

	if self._connections then
		self._connections:Destroy()
		self._connections = nil
	end

	for _, pd in pairs(self._playerTable) do pd:Destroy() end
	table_clear(self._playerTable)

	for _, observer in pairs(self._npcSet) do
		if observer then observer:Destroy() end
	end
	table_clear(self._npcSet)

	for _, limbObs in pairs(self._npcLimbObservers) do
		if limbObs then limbObs:Destroy() end
	end
	table_clear(self._npcLimbObservers)
end

function Manager:Toggle(state)
	if type(state) == "boolean" then
		if state then self:Start() else self:Stop() end
	else
		if self._running then self:Stop() else self:Start() end
	end
end

function Manager:Restart()
	local wasRunning = self._running
	self:Stop()
	if wasRunning then self:Start() end
end

function Manager:AddDirectory(dir)
	if self._destroyed then return end
	if not isLiveInstance(dir) and type(dir) ~= "string" then return end

	local dirs = self._settings.NPC_DIRECTORIES
	if type(dirs) ~= "table" then
		dirs = {}
		self._settings.NPC_DIRECTORIES = dirs
	end

	for _, d in ipairs(dirs) do
		if d == dir then return end
	end

	table_insert(dirs, dir)
	self:Restart()
end

function Manager:RemoveDirectory(dir)
	if self._destroyed then return end

	local dirs = self._settings.NPC_DIRECTORIES
	if type(dirs) ~= "table" then return end

	for i, d in ipairs(dirs) do
		if d == dir then
			table_remove(dirs, i)
			self:Restart()
			return
		end
	end
end

function Manager:GetDirectories()
	local dirs = self._settings.NPC_DIRECTORIES
	if type(dirs) ~= "table" then return {} end
	return table_clone(dirs)
end

function Manager:Set(key, value)
	self._settings[key] = value
end

function Manager:Get(key)
	return self._settings[key]
end

function Manager:Destroy()
	self:Stop()
	self._destroyed = true
	setmetatable(self, nil)
end

return {
	Manager = Manager,
	ConnectionManager = ConnectionManager,
	resolvePathAsync = resolvePathAsync,
	normalizeDirectoryPath = normalizeDirectoryPath,
	isLiveInstance = isLiveInstance,
}
