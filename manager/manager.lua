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
local os_clock     = os.clock

local SCAN_FRAME_BUDGET = 0.002

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
	local ok, conn = pcall(signal.Connect, signal, fn)
	if not ok or not conn then return nil end
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
	DEATH_RESTORE        = false,
	DEATH_DETECT_METHOD  = "Died",
	GET_LOCAL_TEAM       = nil,
	ON_LIMB_READY        = nil,
	ON_LIMB_LOST         = nil,
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
		_model         = model,
		_onAvailable   = onAvailable,
		_onUnavailable = onUnavailable,

		_modelConns  = ConnectionManager.new(),
		_anchorConns = ConnectionManager.new(),

		_active    = false,
		_destroyed = false,
		_anchor    = nil,

		-- FIX 1: guard flags so _bindModelSignals never reconnects signals it
		-- already owns. Without these, every AncestryChanged -> _refresh() ->
		-- _bindModelSignals() would disconnect + reconnect all 4 signals.
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

	return nil
end

-- FIX 1: each signal group is bound exactly once for the lifetime of this
-- observer. Signals persist on the Lua object regardless of streaming state,
-- so there is never a need to reconnect them.
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
		if child.Name == "HumanoidRootPart" then self:_refresh() end
	end, "ChildAdded")

	self._modelConns:Connect(model.ChildRemoved, function(child)
		if self._destroyed then return end
		if child.Name == "HumanoidRootPart" then self:_refresh() end
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

	self:_bindModelSignals()

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

function LimbObserver:_onLimbFound(limb)
	self._limb  = limb
	self._ready = true

	self._conns:Connect(limb:GetPropertyChangedSignal("Parent"), function()
		if not limb:IsDescendantOf(self._model) then
			self:_limbRemoved()
		end
	end, "LimbStream")

	if self._manager._settings.DEATH_RESTORE then
		local humanoid = self._model:FindFirstChildOfClass("Humanoid")
		if humanoid then
			local method = self._manager._settings.DEATH_DETECT_METHOD
			if method == "Health" then
				self._conns:Connect(humanoid:GetPropertyChangedSignal("Health"), function()
					if humanoid.Health <= 0 then
						self:_notifyLost()
					end
				end, "DeathHealth")
			else
				self._conns:Connect(humanoid.Died, function()
					self:_notifyLost()
				end, "Died")
			end
		end
	end

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

	self.conns:Connect(player.CharacterAdded, function(char)
		self:_onCharacterAdded(char)
	end, "CharacterAdded")

	self.conns:Connect(player.CharacterRemoving, function(char)
		self:_onCharacterRemoving(char)
	end, "CharacterRemoving")

	self:_updateTeamSignal()

	if player.Character then
		self:_onCharacterAdded(player.Character)
	end

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

function Manager.new(userSettings)
	local self = setmetatable({
		_settings = mergeSettings(userSettings),

		_playerTable       = {},
		_npcSet            = {},
		_npcLimbObservers  = {},

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
	}, Manager)

	return self
end

function Manager:_onLimbReady(player, model, limb)
	local cb = self._settings.ON_LIMB_READY
	if type(cb) == "function" then pcall(cb, player, model, limb) end
end

function Manager:_onLimbLost(player, model, limb)
	local cb = self._settings.ON_LIMB_LOST
	if type(cb) == "function" then pcall(cb, player, model, limb) end
end

function Manager:_isValidNPC(model)
	if not model or not model:IsA("Model") then return false end
	if not model:FindFirstChildOfClass("Humanoid") then return false end
	if Players:GetPlayerFromCharacter(model) then return false end

	local filter = self._settings.NPC_FILTER
	if type(filter) == "function" then
		local ok, result = pcall(filter, model)
		if not ok or not result then return false end
	end
	return true
end

function Manager:_registerNPC(model, dir)
	if self._destroyed or not model then return end
	if not isLiveInstance(model) then return end
	-- FIX 3: removed dead IsA("Humanoid") branch — all call sites pass
	-- pre-filtered Models via isNPCCandidate so a Humanoid never arrives here.
	if self._npcSet[model] then return end
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
	if dir then
		self._npcDirOwners[model] = dir
	end
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
		local t = os_clock()
		for _, model in ipairs(candidates) do
			if not self._running or self._destroyed or self._generation ~= gen then
				return
			end

			self:_registerNPC(model, dir)

			if os_clock() - t >= SCAN_FRAME_BUDGET then
				task.wait()
				t = os_clock()
			end
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

	for model in pairs(self._npcSet) do
		if not self:_isValidNPC(model) then
			self:_unregisterNPC(model)
		end
	end

	local dirs = self._settings.NPC_DIRECTORIES
	local hasUserDirs = type(dirs) == "table" and #dirs > 0
	local entries = hasUserDirs and dirs or { Workspace }
	local useDescendants = not hasUserDirs

	for _, entry in ipairs(entries) do
		local instance = isLiveInstance(entry) and entry or self._stringDirMap[entry]
		if instance and isLiveInstance(instance) then
			local raw = useDescendants and instance:GetDescendants() or instance:GetChildren()
			for _, desc in ipairs(raw) do
				if isNPCCandidate(desc) then
					self:_registerNPC(desc, instance)
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
	task_spawn(function()
		local t = os_clock()
		for _, p in ipairs(snapshot) do
			if not self._running or self._destroyed or not self._playerConnsStarted then return end
			if p ~= localPlayer and not self._playerTable[p] then
				-- FIX 2: player may have left during the async scan; PlayerRemoving
				-- already fired but found no _playerTable entry, so without this
				-- guard we would create a PlayerData that is never cleaned up.
				if isLiveInstance(p) then
					self._playerTable[p] = PlayerData.new(self, p)
				end
			end
			if os_clock() - t >= SCAN_FRAME_BUDGET then
				task.wait()
				t = os_clock()
			end
		end
	end)
end

function Manager:_stopPlayerTracking()
	if not self._playerConnsStarted then return end
	self._playerConnsStarted = false

	if self._connections then
		self._connections:Disconnect("PlayerAdded")
		self._connections:Disconnect("PlayerRemoving")
	end

	for _, pd in pairs(self._playerTable) do pd:Destroy() end
	table_clear(self._playerTable)
end

function Manager:_startNPCTracking()
	if self._destroyed or not self._running or self._npcConnsStarted then return end
	self._npcConnsStarted = true
	self._npcConnections = ConnectionManager.new()

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
				if resolved and self._running and self._npcConnsStarted
					and not self._destroyed and self._generation == gen then
					self._stringDirMap[entry] = resolved
					self:_activateDirectory(resolved, not hasUserDirs)
				end
			end)
		end
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

	for _, observer in pairs(self._npcSet) do
		if observer then observer:Destroy() end
	end
	table_clear(self._npcSet)

	for _, limbObs in pairs(self._npcLimbObservers) do
		if limbObs then limbObs:Destroy() end
	end
	table_clear(self._npcLimbObservers)

	table_clear(self._dirUidMap)
	table_clear(self._stringDirMap)
	table_clear(self._npcDirOwners)
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

	if key == "TARGET_LIMB" or key == "TEAM_CHECK" or key == "FORCEFIELD_CHECK"
		or key == "DEATH_RESTORE" or key == "GET_LOCAL_TEAM" or key == "DEATH_DETECT_METHOD" then
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
		else
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
