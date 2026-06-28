local function missing(t, f, fallback)
	if type(f) == t then return f end
	return fallback
end

local cloneref = missing("function", cloneref, function(obj) return obj end)

local Players   = cloneref(game:GetService("Players"))
local Workspace = cloneref(game:GetService("Workspace"))

local localPlayer = Players.LocalPlayer
if not localPlayer then
	Players:GetPropertyChangedSignal("LocalPlayer"):Wait()
	localPlayer = Players.LocalPlayer
end

local table_clear  = table.clear
local table_remove = table.remove
local table_insert = table.insert
local table_clone  = table.clone
local task_spawn   = task.spawn
local task_defer   = task.defer
local string_split = string.split
local string_gsub  = string.gsub
local math_min	   = math.min
local os_clock     = os.clock

local function isNPCCandidate(inst)
	return typeof(inst) == "Instance" and inst:IsA("Model")
end

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

function ConnectionManager:Disconnect(label)
	local conn = self._labels[label]
	if not conn then return end
	if conn.Connected then conn:Disconnect() end
	self._conns[conn] = nil
	self._labels[label] = nil
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
end

local DEFAULTS = {
	PLAYER_ENABLED       = true,
	NPC_ENABLED          = false,
	NPC_FILTER           = nil,
	NPC_DIRECTORIES      = {},

	ON_CHARACTER_ADDED   = nil,
	ON_CHARACTER_REMOVING= nil,
	ON_NPC_ADDED         = nil,
	ON_NPC_REMOVING      = nil,

	TARGET_LIMB          = nil,
	TEAM_CHECK           = false,
	FORCEFIELD_CHECK     = false,
	STOP_TRACKING_ON_DEATH = true,
	DEATH_DETECT_METHOD  = "Health",
	GET_LOCAL_TEAM       = nil,
	ON_LIMB_READY        = nil,
	ON_LIMB_LOST         = nil,

	NPC_SPAWN_WAIT_TIMEOUT = 5,

	WARN_ON_CALLBACK_ERROR = true,

	ON_CALLBACK_ERROR = nil,

	REQUIRE_ANCHOR = true,

	GET_PLAYER_FROM_CHARACTER = nil,
	CUSTOM_CHARACTER_SYSTEM = false,
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

local function getPlayerFromCharacter(settings, model)
	local custom = settings.GET_PLAYER_FROM_CHARACTER
	if custom then
		local ok, result = pcall(custom, model)
		if ok and result ~= nil then return result end
		return nil
	end
	return Players:GetPlayerFromCharacter(model)
end

local function parseLimbPath(targetLimb)
	if type(targetLimb) ~= "string" or targetLimb == "" then return nil end
	local segs = {}
	for seg in targetLimb:gmatch("[^%.]+") do
		local t = seg:match("^%s*(.-)%s*$")
		if t ~= "" then segs[#segs + 1] = t end
	end
	return #segs > 0 and segs or nil
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

	local head = parts[1]:lower()
	local current

	if head == "game" then
		current = game
		table_remove(parts, 1)
	elseif head == "workspace" then
		current = Workspace
		table_remove(parts, 1)
	else
		current = game:GetService(parts[1])
		table_remove(parts, 1)
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
	return inst:IsDescendantOf(game)
end

local StreamObserver = {}
StreamObserver.__index = StreamObserver

function StreamObserver.new(model, onAvailable, onUnavailable, requireAnchor)
	local self = setmetatable({
		_model         = model,
		_onAvailable   = onAvailable,
		_onUnavailable = onUnavailable,

		_requireAnchor = requireAnchor ~= false,

		_modelConns  = ConnectionManager.new(),
		_anchorConns = ConnectionManager.new(),

		_active    = false,
		_destroyed = false,
		_anchor    = nil,

		_ancestryBound     = false,
		_childSignalsBound = false,
	}, StreamObserver)

	self:_bindModelSignals()
	self:_refresh()

	return self
end

function StreamObserver:IsActive()
	return not self._destroyed and self._active
end

function StreamObserver:_resolveAnchor()
	local model = self._model
	if not isLiveInstance(model) or not model:IsA("Model") then return nil end

	local root = model.PrimaryPart
	if isLiveInstance(root) then return root end

	root = model:FindFirstChild("HumanoidRootPart")
	if root and isLiveInstance(root) then return root end

	root = model:FindFirstChildWhichIsA("BasePart")
	if root and isLiveInstance(root) then return root end

	return nil
end

function StreamObserver:_bindModelSignals()
	if self._destroyed then return end
	local model = self._model
	if typeof(model) ~= "Instance" then return end

	if not self._ancestryBound then
		self._modelConns:Connect(model.AncestryChanged, function()
			if self._destroyed then return end
			self:_refresh()
		end, "AncestryChanged")
		self._ancestryBound = true
	end

	if self._childSignalsBound or not isLiveInstance(model) then return end

	self._modelConns:Connect(model.ChildAdded, function(child)
		if self._destroyed then return end

		if child.Name == "HumanoidRootPart" or child:IsA("BasePart") then
			self:_refresh()
		end
	end, "ChildAdded")

	self._modelConns:Connect(model.ChildRemoved, function(child)
		if self._destroyed then return end
		if child.Name == "HumanoidRootPart" or child:IsA("BasePart") then
			self:_refresh()
		end
	end, "ChildRemoved")

	self._modelConns:Connect(model:GetPropertyChangedSignal("PrimaryPart"), function()
		if self._destroyed then return end
		self:_refresh()
	end, "PrimaryPart")

	self._childSignalsBound = true
end

function StreamObserver:_bindAnchor(anchor)
	self._anchor = anchor
	self._anchorConns:DisconnectAll()
	if not anchor or not isLiveInstance(anchor) then return end

	self._anchorConns:Connect(anchor:GetPropertyChangedSignal("Parent"), function()
		if self._destroyed then return end
		self:_refresh()
	end, "AnchorParent")
end

function StreamObserver:_setActive(active)
	if self._active == active then return end
	self._active = active

	local model = self._model
	if active then
		local cb = self._onAvailable
		if type(cb) == "function" then cb(model) end
	else
		local cb = self._onUnavailable
		if type(cb) == "function" then cb(model) end
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

	self:_bindModelSignals()

	if self._requireAnchor then
		local anchor = self:_resolveAnchor()
		if anchor ~= self._anchor then self:_bindAnchor(anchor) end
		local available = anchor ~= nil and isLiveInstance(anchor) and isLiveInstance(model)
		self:_setActive(available)
	else
		self:_bindAnchor(nil)
		self:_setActive(true)
	end
end

function StreamObserver:Destroy()
	if self._destroyed then return end
	self._destroyed = true

	if self._active then
		self._active = false
		local cb = self._onUnavailable
		if type(cb) == "function" then cb(self._model) end
	end

	self._anchorConns:Destroy()
	self._modelConns:Destroy()
end

local LimbObserver = {}
LimbObserver.__index = LimbObserver

function LimbObserver.new(manager, model, playerObject)
	local self = setmetatable({
		_manager   = manager,
		_model     = model,
		_player    = playerObject,
		_ready     = false,
		_limb      = nil,
		_lifeConns = ConnectionManager.new(),
		_conns     = ConnectionManager.new(),
		_destroyed = false,
		_segments  = nil,
		_deathMonitored = false,
	}, LimbObserver)

	self:_bindLifecycle()
	self:_start()
	return self
end

function LimbObserver:_clearPathConns()
	local segs = self._segments
	if not segs then return end
	for i = 1, #segs do
		self._conns:Disconnect("Step" .. i)
		self._conns:Disconnect("Int"  .. i)
	end
end

function LimbObserver:_resolveStep(container, segs, depth)
	if self._destroyed or self._ready then return end
	if not isLiveInstance(container) then return end

	local name    = segs[depth]
	local isLeaf  = depth == #segs
	local stepKey = "Step" .. depth

	local function proceed(child)
		if self._destroyed or self._ready then return end

		if isLeaf then
			if child:IsA("BasePart") then
				for i = 1, depth - 1 do
					self._conns:Disconnect("Int" .. i)
				end
				self:_onLimbFound(child)
			end
		else
			self._conns:Connect(child:GetPropertyChangedSignal("Parent"), function()
				if self._destroyed then return end
				if not child:IsDescendantOf(self._model) then
					for i = depth, #segs do
						self._conns:Disconnect("Step" .. i)
						self._conns:Disconnect("Int"  .. i)
					end
					if self._ready then
						self:_limbRemoved()
					else
						self:_resolveStep(container, segs, depth)
					end
				end
			end, "Int" .. depth)

			self:_resolveStep(child, segs, depth + 1)
		end
	end

	local existing = container:FindFirstChild(name)
	if existing then
		proceed(existing)
	else
		self._conns:Connect(container.ChildAdded, function(child)
			if child.Name == name then
				self._conns:Disconnect(stepKey)
				proceed(child)
			end
		end, stepKey)
	end
end

function LimbObserver:_bindLifecycle()
	if self._destroyed then return end
	if not isLiveInstance(self._model) then return end

	self._lifeConns:Connect(self._model.AncestryChanged, function()
		if self._destroyed then return end
		if not isLiveInstance(self._model) then
			self:_notifyLost()
		end
	end, "AncestryChanged")
end

function LimbObserver:_start()
	if self._destroyed or self._ready then return end
	if not isLiveInstance(self._model) then
		self:_notifyLost()
		return
	end

	local targetLimb = self._manager._settings.TARGET_LIMB
	self._segments = parseLimbPath(targetLimb)
	if not self._segments then return end

	if self._manager._settings.STOP_TRACKING_ON_DEATH then
		self:_monitorDeathEarly()
	end

	if self._player and self._manager._settings.TEAM_CHECK then
		local getTeam = self._manager._settings.GET_LOCAL_TEAM
		if type(getTeam) == "function" then
			local ok, myTeam = pcall(getTeam)
			if ok and myTeam and self._player.Team == myTeam then return end
		end
	end

	local function beginResolve()
		self:_resolveStep(self._model, self._segments, 1)
	end

	local function watchForceField(ff)
		self:_clearPathConns()
		self._conns:Connect(ff.AncestryChanged, function()
			if not ff:IsDescendantOf(self._model) then
				self._conns:Disconnect("ForceFieldWatcher")
				beginResolve()
			end
		end, "ForceFieldWatcher")
	end

	if self._manager._settings.FORCEFIELD_CHECK then
		local existing = self._model:FindFirstChildOfClass("ForceField")
		if existing then
			watchForceField(existing)
			return
		end
		self._conns:Connect(self._model.ChildAdded, function(child)
			if child:IsA("ForceField") then
				watchForceField(child)
			end
		end, "ForceFieldAppeared")
	end

	beginResolve()
end

function LimbObserver:_monitorDeathEarly()
	if self._destroyed or self._deathMonitored then return end
	self._deathMonitored = true

	local humanoid = self._model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		self:_connectDeathSignal(humanoid)
	else
		self._conns:Connect(self._model.ChildAdded, function(child)
			if child:IsA("Humanoid") then
				self._conns:Disconnect("WaitForHumanoid")
				self:_connectDeathSignal(child)
			end
		end, "WaitForHumanoid")
	end
end

function LimbObserver:_connectDeathSignal(humanoid)
	if self._destroyed then return end
	local method = self._manager._settings.DEATH_DETECT_METHOD

	if method == "Health" then
		self._conns:Connect(humanoid:GetPropertyChangedSignal("Health"), function()
			if humanoid.Health <= 0 then
				self:_onCharacterDied()
			end
		end, "DeathHealth")
	else
		self._conns:Connect(humanoid.Died, function()
			self:_onCharacterDied()
		end, "Died")
	end
end

function LimbObserver:_onCharacterDied()
	if self._destroyed then return end
	self:_notifyLost()
end

function LimbObserver:_onLimbFound(limb)
	self._limb  = limb
	self._ready = true

	self._conns:Connect(limb:GetPropertyChangedSignal("Parent"), function()
		if not limb:IsDescendantOf(self._model) then
			self:_limbRemoved()
		end
	end, "LimbStream")

	local player = self._player
	self._manager:_onLimbReady(player, self._model, limb)
end

function LimbObserver:_limbRemoved()
	if self._destroyed or not self._ready then return end

	self._ready = false
	local oldLimb = self._limb
	self._limb = nil

	self._conns:DisconnectAll()
	self._manager:_onLimbLost(self._player, self._model, oldLimb)
	self:_start()
end

function LimbObserver:_notifyLost()
	if self._destroyed then return end

	local wasReady = self._ready
	local oldLimb  = self._limb

	self._ready = false
	self._limb  = nil
	self._conns:DisconnectAll()

	if wasReady then
		self._manager:_onLimbLost(self._player, self._model, oldLimb)
	end
end

function LimbObserver:Refresh()
	if self._destroyed then return end

	local wasReady = self._ready
	local oldLimb  = self._limb

	self._ready = false
	self._limb  = nil
	self._conns:DisconnectAll()

	if wasReady then
		self._manager:_onLimbLost(self._player, self._model, oldLimb)
	end

	self:_start()
end

function LimbObserver:Destroy()
	if self._destroyed then return end
	self._destroyed = true

	local manager  = self._manager
	local player   = self._player
	local model    = self._model
	local wasReady = self._ready
	local oldLimb  = self._limb

	self._ready = false
	self._limb  = nil
	self._conns:Destroy()
	self._lifeConns:Destroy()

	if wasReady then
		manager:_onLimbLost(player, model, oldLimb)
	end
end

local PlayerData = {}
PlayerData.__index = PlayerData

function PlayerData.new(parent, player)
	local self = setmetatable({
		_parent            = parent,
		player             = player,
		conns              = ConnectionManager.new(),
		_destroyed         = false,
		_character         = nil,
		_characterObserver = nil,
		_limbObserver      = nil,
	}, PlayerData)

	if not parent._settings.CUSTOM_CHARACTER_SYSTEM then
		self.conns:Connect(player.CharacterAdded, function(char)
			self:_onCharacterAdded(char)
		end, "CharacterAdded")

		self.conns:Connect(player.CharacterRemoving, function(char)
			self:_onCharacterRemoving(char)
		end, "CharacterRemoving")

		if player.Character then
			self:_onCharacterAdded(player.Character)
		end
	end

	self.conns:Connect(player:GetPropertyChangedSignal("Character"), function()
		local char = player.Character
		if char and self._character ~= char and not self._destroyed then
			self:_onCharacterAdded(char)
		end
	end, "CharacterChanged")

	self:_updateTeamSignal()

	return self
end

function PlayerData:_updateTeamSignal()
	local s = self._parent._settings
	if s.TARGET_LIMB ~= nil and s.TEAM_CHECK then
		self.conns:Connect(self.player:GetPropertyChangedSignal("Team"), function()
			if self._limbObserver then
				self._limbObserver:Refresh()
			end
		end, "TeamChanged")
	else
		self.conns:Disconnect("TeamChanged")
	end
end

function PlayerData:_setupLimbTracking(char)
	if self._destroyed or not isLiveInstance(char) then return end
	if self._limbObserver then
		self._limbObserver:Destroy()
	end
	self._limbObserver = LimbObserver.new(self._parent, char, self.player)
end

function PlayerData:_ensureLimbTracking()
	if self._destroyed then return end
	if self._limbObserver then
		self._limbObserver:Refresh()
		return
	end
	if self._characterObserver and self._characterObserver:IsActive() then
		local char = self._character
		if char and isLiveInstance(char) then
			self:_setupLimbTracking(char)
		end
	end
end

function PlayerData:_teardownLimbTracking()
	if self._limbObserver then
		self._limbObserver:Destroy()
		self._limbObserver = nil
	end
end

function PlayerData:_onCharacterAdded(char)
	if self._destroyed or typeof(char) ~= "Instance" or not char:IsA("Model") then return end

	if self._characterObserver then
		self._characterObserver:Destroy()
		self._characterObserver = nil
	end

	self._character = char

	local parent = self._parent
	local ok, err = pcall(function()
		self._characterObserver = StreamObserver.new(char, function(model)
			if self._destroyed then return end
			parent:_fireCallback("ON_CHARACTER_ADDED", parent._settings.ON_CHARACTER_ADDED, self.player, model)
			if parent._settings.TARGET_LIMB then
				self:_setupLimbTracking(model)
			end
		end, function(model)
			if self._destroyed then return end
			parent:_fireCallback("ON_CHARACTER_REMOVING", parent._settings.ON_CHARACTER_REMOVING, self.player, model)
			if self._limbObserver then
				self._limbObserver:Destroy()
				self._limbObserver = nil
			end
		end, parent._settings.REQUIRE_ANCHOR)
	end)
	if not ok then
		warn("Failed to create StreamObserver:", err)
		task.defer(function()
			if self._destroyed or self._character ~= char then return end
			self._characterObserver = StreamObserver.new(char, function(model)
				if self._destroyed then return end
				parent:_fireCallback("ON_CHARACTER_ADDED", parent._settings.ON_CHARACTER_ADDED, self.player, model)
				if parent._settings.TARGET_LIMB then
					self:_setupLimbTracking(model)
				end
			end, function(model)
				if self._destroyed then return end
				parent:_fireCallback("ON_CHARACTER_REMOVING", parent._settings.ON_CHARACTER_REMOVING, self.player, model)
				if self._limbObserver then
					self._limbObserver:Destroy()
					self._limbObserver = nil
				end
			end, parent._settings.REQUIRE_ANCHOR)
		end)
	end
end

function PlayerData:_onCharacterRemoving(char)
	if self._destroyed then return end
	if self._character ~= char then return end

	if self._characterObserver then
		self._characterObserver:Destroy()
		self._characterObserver = nil
	end

	if self._limbObserver then
		self._limbObserver:Destroy()
		self._limbObserver = nil
	end

	self._character = nil
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
end

local Manager = {}
Manager.__index = Manager

function Manager:_fireCallback(name, cb, ...)
	if type(cb) ~= "function" then return true end
	local ok, err = pcall(cb, ...)
	if not ok then
		if self._settings.WARN_ON_CALLBACK_ERROR then
			warn(("[NPCTracker] Error in %s callback: %s"):format(name, tostring(err)))
		end
		local errCb = self._settings.ON_CALLBACK_ERROR
		if type(errCb) == "function" then
			pcall(errCb, name, err)
		end
	end
	return ok
end

function Manager.new(userSettings)
	local self = setmetatable({
		_settings = mergeSettings(userSettings),

		_playerTable       = {},
		_npcSet            = {},
		_npcLimbObservers  = {},
		_pendingNPCWatchers = {},

		_connections    = nil,
		_npcConnections = nil,

		_playerConnsStarted = false,
		_npcConnsStarted    = false,

		_running   = false,
		_destroyed = false,
		_generation = 0,

		_dirIdCounter = 0,
		_dirUidMap    = {},
		_stringDirMap = {},
		_npcDirOwners = {},

		_pendingPlayerRegistrations = {},
	}, Manager)

	return self
end

function Manager:_onLimbReady(player, model, limb)
	local cb = self._settings.ON_LIMB_READY
	self:_fireCallback("ON_LIMB_READY", cb, player, model, limb)
end

function Manager:_onLimbLost(player, model, limb)
	local obs = self._npcLimbObservers[model]
	if obs then
		obs:Destroy()
		self._npcLimbObservers[model] = nil
	end

	self._deadModels = self._deadModels or {}
	self._deadModels[model] = true

	local cb = self._settings.ON_LIMB_LOST
	self:_fireCallback("ON_LIMB_LOST", cb, player, model, limb)
end

function Manager:_isValidNPC(model)
	if not model or not model:IsA("Model") then return false end
	if not model:FindFirstChildOfClass("Humanoid") then return false end
	if getPlayerFromCharacter(self._settings, model) then return false end

	local filter = self._settings.NPC_FILTER
	if type(filter) == "function" then
		local ok, result = pcall(filter, model)
		if not ok or not result then return false end
	end
	return true
end

function Manager:_checkNPCValidity(model)
	if not model or not model:IsA("Model") then return false, false end
	if not model:FindFirstChildOfClass("Humanoid") then return false, true end
	if getPlayerFromCharacter(self._settings, model) then return false, false end

	local filter = self._settings.NPC_FILTER
	if type(filter) == "function" then
		local ok, result = pcall(filter, model)
		if not ok or not result then return false, false end
	end
	return true, false
end

function Manager:_registerNPC(model, dir)
	if self._destroyed or not model then return end
	if not isLiveInstance(model) then return end

	if self._npcSet[model] then return end
	if self._pendingNPCWatchers[model] then return end

	local valid, missingHumanoid = self:_checkNPCValidity(model)
	if not valid then
		if missingHumanoid then
			self:_watchForHumanoid(model, dir)
		end
		return
	end

	self:_finishRegisterNPC(model, dir)
end

function Manager:_finishRegisterNPC(model, dir)
	if self._destroyed or not isLiveInstance(model) then return end
	if self._npcSet[model] then return end

	local requireAnchor = self._settings.REQUIRE_ANCHOR
	local observer = StreamObserver.new(model,
		function(npcModel)
			if self._destroyed then return end
			self:_fireCallback("ON_NPC_ADDED", self._settings.ON_NPC_ADDED, npcModel)
			if self._settings.TARGET_LIMB and not self._npcLimbObservers[npcModel] then
				self._npcLimbObservers[npcModel] = LimbObserver.new(self, npcModel, nil)
			end
		end,
		function(npcModel)
			if self._destroyed then return end
			self:_fireCallback("ON_NPC_REMOVING", self._settings.ON_NPC_REMOVING, npcModel)
			local limbObs = self._npcLimbObservers[npcModel]
			if limbObs then
				limbObs:Destroy()
				self._npcLimbObservers[npcModel] = nil
			end
		end,
		requireAnchor
	)
	self._npcSet[model] = observer
	if dir then
		self._npcDirOwners[model] = dir
	end
end

function Manager:_watchForHumanoid(model, dir)
	if self._pendingNPCWatchers[model] then return end

	local gen   = self._generation
	local conns = ConnectionManager.new()
	local state = { cancelled = false, conns = conns }
	self._pendingNPCWatchers[model] = state

	local function cleanup()
		state.cancelled = true
		conns:Destroy()
		if self._pendingNPCWatchers[model] == state then
			self._pendingNPCWatchers[model] = nil
		end
	end

	conns:Connect(model.AncestryChanged, function()
		if state.cancelled then return end
		if not isLiveInstance(model) then
			cleanup()
		end
	end, "PendingAncestry")

	task_spawn(function()
		local deadline = os_clock() + (self._settings.NPC_SPAWN_WAIT_TIMEOUT or 15)

		while not state.cancelled do
			if self._destroyed or not self._running or not self._npcConnsStarted
				or self._generation ~= gen or not isLiveInstance(model) then
				cleanup()
				return
			end

			if os_clock() >= deadline then
				cleanup()
				return
			end

			local humanoid = model:WaitForChild("Humanoid", 1)

			if state.cancelled then
				return
			end

			if humanoid then
				cleanup()
				if self._running and self._npcConnsStarted and not self._destroyed
					and self._generation == gen and isLiveInstance(model) then
					self:_registerNPC(model, dir)
				end
				return
			end
		end
	end)
end

function Manager:_cancelPendingNPCWatch(model)
	local state = self._pendingNPCWatchers[model]
	if not state then return end
	state.cancelled = true
	state.conns:Destroy()
	self._pendingNPCWatchers[model] = nil
end

function Manager:_unregisterNPC(model)
	self:_cancelPendingNPCWatch(model)

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
	self._npcDirOwners[model] = nil
end

function Manager:_activateDirectory(dir, useDescendants)
	self._dirIdCounter = self._dirIdCounter + 1
	local uid = tostring(self._dirIdCounter)
	self._dirUidMap[dir] = uid

	if useDescendants then
		self._npcConnections:Connect(dir.DescendantAdded, function(desc)
			if not isNPCCandidate(desc) then return end
			local gen = self._generation
			task_defer(function()
				if self._running and self._npcConnsStarted
					and not self._destroyed
					and self._generation == gen then
					self:_registerNPC(desc, dir)
				end
			end)
		end, uid .. "_DescendantAdded")

		self._npcConnections:Connect(dir.DescendantRemoving, function(desc)
			if not isNPCCandidate(desc) then return end
			self:_unregisterNPC(desc)
		end, uid .. "_DescendantRemoving")
	else
		self._npcConnections:Connect(dir.ChildAdded, function(desc)
			if not isNPCCandidate(desc) then return end
			local gen = self._generation
			task_defer(function()
				if self._running and self._npcConnsStarted
					and not self._destroyed
					and self._generation == gen then
					self:_registerNPC(desc, dir)
				end
			end)
		end, uid .. "_ChildAdded")

		self._npcConnections:Connect(dir.ChildRemoved, function(desc)
			if not isNPCCandidate(desc) then return end
			self:_unregisterNPC(desc)
		end, uid .. "_ChildRemoved")
	end

	local raw = useDescendants and dir:GetDescendants() or dir:GetChildren()

	local candidates = {}
	for _, inst in ipairs(raw) do
		if isNPCCandidate(inst) then
			candidates[#candidates + 1] = inst
		end
	end

	local gen = self._generation
	task_spawn(function()
		local BATCH = 6
		for i = 1, #candidates, BATCH do
			if not self._running or self._destroyed or self._generation ~= gen then
				return
			end
			local last = math_min(i + BATCH - 1, #candidates)
			for j = i, last do
				self:_registerNPC(candidates[j], dir)
			end
			task.wait()
		end
	end)
end

function Manager:_refreshAllLimbObservers()
	local hasTarget = self._settings.TARGET_LIMB ~= nil

	for _, pd in pairs(self._playerTable) do
		if hasTarget then
			pd:_ensureLimbTracking()
		else
			pd:_teardownLimbTracking()
		end
	end

	for model, streamObs in pairs(self._npcSet) do
		if hasTarget then
			local limbObs = self._npcLimbObservers[model]
			if limbObs then
				limbObs:Refresh()
			elseif streamObs:IsActive() then
				self._npcLimbObservers[model] = LimbObserver.new(self, model, nil)
			end
		else
			local limbObs = self._npcLimbObservers[model]
			if limbObs then
				limbObs:Destroy()
				self._npcLimbObservers[model] = nil
			end
		end
	end
end

function Manager:_rescanNPCFilter()
	if self._destroyed or not self._running or not self._npcConnsStarted then return end

	local gen = self._generation
	task_spawn(function()
		local toRemove = {}
		for model in pairs(self._npcSet) do
			if not self._running or self._destroyed or self._generation ~= gen then return end
			if not self:_isValidNPC(model) then
				toRemove[#toRemove + 1] = model
			end
		end

		local BATCH = 6
		for i = 1, #toRemove, BATCH do
			if not self._running or self._destroyed or self._generation ~= gen then return end
			local last = math_min(i + BATCH - 1, #toRemove)
			for j = i, last do
				self:_unregisterNPC(toRemove[j])
			end
			task.wait()
		end

		local dirs = self._settings.NPC_DIRECTORIES
		local hasUserDirs = type(dirs) == "table" and #dirs > 0
		local entries = hasUserDirs and dirs or { Workspace }
		local useDescendants = not hasUserDirs

		for _, entry in ipairs(entries) do
			if not self._running or self._destroyed or self._generation ~= gen then return end
			local instance = isLiveInstance(entry) and entry or self._stringDirMap[entry]
			if instance and isLiveInstance(instance) then
				local raw = useDescendants and instance:GetDescendants() or instance:GetChildren()
				local candidates = {}
				for _, desc in ipairs(raw) do
					if isNPCCandidate(desc) then
						candidates[#candidates + 1] = desc
					end
				end
				for i = 1, #candidates, BATCH do
					if not self._running or self._destroyed or self._generation ~= gen then return end
					local last = math_min(i + BATCH - 1, #candidates)
					for j = i, last do
						self:_registerNPC(candidates[j], instance)
					end
					task.wait()
				end
			end
			task.wait()
		end
	end)
end

function Manager:_rescanCustomPlayers()
	if not self._running then return end
	if not self._settings.CUSTOM_CHARACTER_SYSTEM then return end

	local dirs = self._settings.NPC_DIRECTORIES
	local hasUserDirs = type(dirs) == "table" and #dirs > 0
	local entries = hasUserDirs and dirs or { Workspace }

	local getPlayer = self._settings.GET_PLAYER_FROM_CHARACTER
	if type(getPlayer) ~= "function" then return end

	for _, entry in ipairs(entries) do
		local instance = isLiveInstance(entry) and entry or self._stringDirMap[entry]
		if instance and isLiveInstance(instance) then
			local raw = (not hasUserDirs) and instance:GetDescendants() or instance:GetChildren()
			for _, obj in ipairs(raw) do
				if isNPCCandidate(obj) then
					local player = getPlayer(obj)
					if player then
						self:RegisterPlayerCharacter(player, obj)
					end
				end
			end
		end
	end
end

function Manager:_startPlayerTracking()
	if self._destroyed or not self._running or self._playerConnsStarted then return end
	self._playerConnsStarted = true

	self._connections:Connect(Players.PlayerAdded, function(p)
		if p ~= localPlayer and not self._playerTable[p] then
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

	local snapshot = Players:GetPlayers()
	local gen = self._generation

	local BATCH = 6
	for i = 1, #snapshot, BATCH do
		if not self._running or self._destroyed or self._playerConnsStarted == false then return end
		local last = math_min(i + BATCH - 1, #snapshot)
		for j = i, last do
			local p = snapshot[j]
			if p ~= localPlayer and not self._playerTable[p] then
				if isLiveInstance(p) then
					self._playerTable[p] = PlayerData.new(self, p)
				end
			end
		end
		task.wait()
	end
end

function Manager:_startNPCTracking()
	if self._destroyed or not self._running or self._npcConnsStarted then return end
	self._npcConnsStarted = true
	self._npcConnections = ConnectionManager.new()

	local dirs = self._settings.NPC_DIRECTORIES
	local hasUserDirs = type(dirs) == "table" and #dirs > 0
	local entries = hasUserDirs and dirs or { Workspace }

	local gen = self._generation
	for _, entry in ipairs(entries) do
		if not self._running or self._destroyed or self._generation ~= gen then return end

		if isLiveInstance(entry) then
			self:_activateDirectory(entry, not hasUserDirs)
		elseif type(entry) == "string" then
			local resolved = resolvePathAsync(entry)
			if resolved and self._running and self._npcConnsStarted
				and not self._destroyed and self._generation == gen then
				self._stringDirMap[entry] = resolved
				self:_activateDirectory(resolved, not hasUserDirs)
			end
		end
		task.wait()
	end
end

function Manager:_stopPlayerTracking()
	if not self._playerConnsStarted then return end
	self._playerConnsStarted = false

	if self._connections then
		self._connections:Disconnect("PlayerAdded")
		self._connections:Disconnect("PlayerRemoving")
	end

	local BATCH = 6
	local toDestroy = {}
	for _, pd in pairs(self._playerTable) do
		toDestroy[#toDestroy + 1] = pd
	end
	table_clear(self._playerTable)

	local gen = self._generation 

	for i = 1, #toDestroy, BATCH do
		if self._destroyed or self._generation ~= gen then return end
		local last = math_min(i + BATCH - 1, #toDestroy)
		for j = i, last do
			toDestroy[j]:Destroy()
		end
		task.wait()
	end
end

function Manager:_stopNPCTracking()
	if not self._npcConnsStarted then return end
	self._npcConnsStarted = false
	self._generation = self._generation + 1
	
	if self._npcConnections then
		self._npcConnections:Destroy()
		self._npcConnections = nil
	end

	local BATCH = 6

	local npcObservers = {}
	for _, observer in pairs(self._npcSet) do
		if observer then npcObservers[#npcObservers + 1] = observer end
	end
	table_clear(self._npcSet)

	local limbObservers = {}
	for _, limbObs in pairs(self._npcLimbObservers) do
		if limbObs then limbObservers[#limbObservers + 1] = limbObs end
	end
	table_clear(self._npcLimbObservers)

	for model in pairs(self._pendingNPCWatchers) do
		self:_cancelPendingNPCWatch(model)
	end
	table_clear(self._pendingNPCWatchers)

	table_clear(self._dirUidMap)
	table_clear(self._stringDirMap)
	table_clear(self._npcDirOwners)

	local gen = self._generation

	for i = 1, #npcObservers, BATCH do
		if self._destroyed or self._generation ~= gen then return end
		local last = math_min(i + BATCH - 1, #npcObservers)
		for j = i, last do
			npcObservers[j]:Destroy()
		end
		task.wait()
	end
	for i = 1, #limbObservers, BATCH do
		if self._destroyed or self._generation ~= gen then return end
		local last = math_min(i + BATCH - 1, #limbObservers)
		for j = i, last do
			limbObservers[j]:Destroy()
		end
		task.wait()
	end
end

function Manager:Start()
	if self._destroyed or self._running then return end
	self._running = true
	self._connections = ConnectionManager.new()

	if self._settings.PLAYER_ENABLED then
		self:_startPlayerTracking()
	end

	if self._settings.NPC_ENABLED then
		self:_startNPCTracking()
	end

	for _, entry in ipairs(self._pendingPlayerRegistrations) do
		self:RegisterPlayerCharacter(entry.player, entry.model)
	end
	table_clear(self._pendingPlayerRegistrations)
end

function Manager:Stop()
	if self._destroyed or not self._running then return end
	self._running = false

	self:_stopNPCTracking()
	self:_stopPlayerTracking()

	if self._connections then
		self._connections:Destroy()
		self._connections = nil
	end
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

	if self._running and self._settings.NPC_ENABLED then
		if isLiveInstance(dir) then
			self:_activateDirectory(dir, false)
		elseif type(dir) == "string" then
			local gen = self._generation
			task_spawn(function()
				local resolved = resolvePathAsync(dir)
				if resolved and self._running and self._npcConnsStarted
					and not self._destroyed and self._generation == gen then
					self._stringDirMap[dir] = resolved
					self:_activateDirectory(resolved, false)
				end
			end)
		end
	end
end

function Manager:RemoveDirectory(dir)
	if self._destroyed then return end

	local dirs = self._settings.NPC_DIRECTORIES
	if type(dirs) ~= "table" then return end

	for i, d in ipairs(dirs) do
		if d == dir then
			table_remove(dirs, i)

			if self._running and self._settings.NPC_ENABLED then
				local instance
				if isLiveInstance(dir) then
					instance = dir
				elseif type(dir) == "string" then
					instance = self._stringDirMap[dir]
				end

				if instance and self._dirUidMap[instance] then
					local uid = self._dirUidMap[instance]

					self._npcConnections:Disconnect(uid .. "_DescendantAdded")
					self._npcConnections:Disconnect(uid .. "_DescendantRemoving")
					self._npcConnections:Disconnect(uid .. "_ChildAdded")
					self._npcConnections:Disconnect(uid .. "_ChildRemoved")

					for model, _ in pairs(self._npcSet) do
						if self._npcDirOwners[model] == instance then
							self:_unregisterNPC(model)
						end
					end

					self._dirUidMap[instance] = nil
					if type(dir) == "string" then
						self._stringDirMap[dir] = nil
					end
				end
			end
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
	if self._settings[key] == value then return end
	self._settings[key] = value

	if key == "GET_PLAYER_FROM_CHARACTER" then
		if self._running and self._npcConnsStarted then
			self:_rescanNPCFilter()
		end
		return
	end

	if key == "TARGET_LIMB" or key == "TEAM_CHECK" or key == "FORCEFIELD_CHECK"
		or key == "STOP_TRACKING_ON_DEATH" or key == "GET_LOCAL_TEAM" or key == "DEATH_DETECT_METHOD" then
		if self._running then
			self:_refreshAllLimbObservers()
		end
	end

	if (key == "TARGET_LIMB" or key == "TEAM_CHECK") and self._running then
		for _, pd in pairs(self._playerTable) do
			pd:_updateTeamSignal()
		end
	end

	if key == "NPC_FILTER" then
		self:_rescanNPCFilter()
	end

	if key == "PLAYER_ENABLED" and self._running then
		if value then
			self:_startPlayerTracking()
			if self._settings.CUSTOM_CHARACTER_SYSTEM then
				self:_rescanCustomPlayers()
			end
		else
			for player, pd in pairs(self._playerTable) do
				if pd._character then
					pd:_onCharacterRemoving(pd._character)
				end
			end
			self:_stopPlayerTracking()
		end
	end

	if key == "NPC_ENABLED" and self._running then
		if value then
			self:_startNPCTracking()
		else
			self:_stopNPCTracking()
		end
	end

	if key == "NPC_DIRECTORIES" and self._running and self._settings.NPC_ENABLED then
		self:_stopNPCTracking()
		self:_startNPCTracking()
	end
end

function Manager:Get(key)
	return self._settings[key]
end

function Manager:RegisterPlayerCharacter(player, model)
	if self._destroyed then return end
	if not player or not model then return end
	if not model:IsA("Model") then return end

	if not self._settings.PLAYER_ENABLED then return end

	if not self._running then
		table_insert(self._pendingPlayerRegistrations, { player = player, model = model })
		return
	end

	local pd = self._playerTable[player]
	if not pd then
		pd = PlayerData.new(self, player)
		self._playerTable[player] = pd
	end
	pd:_onCharacterAdded(model)
end

function Manager:UnregisterPlayerCharacter(player, model)
	if self._destroyed then return end
	local pd = self._playerTable[player]
	if pd then
		pd:_onCharacterRemoving(model)
	end
end

function Manager:Destroy()
	self:Stop()
	self._destroyed = true
end

return {
	Manager              = Manager,
	ConnectionManager    = ConnectionManager,
	resolvePathAsync     = resolvePathAsync,
	normalizeDirectoryPath = normalizeDirectoryPath,
	isLiveInstance       = isLiveInstance,
}
