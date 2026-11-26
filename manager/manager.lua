local cloneref = type(cloneref) == "function" and cloneref or function(obj) return obj end

local Players   = cloneref(game:GetService("Players"))
local Workspace = cloneref(game:GetService("Workspace"))

local table_clear  = table.clear
local table_remove = table.remove
local table_insert = table.insert
local table_clone  = table.clone
local task_spawn   = task.spawn
local task_defer   = task.defer
local task_wait    = task.wait
local string_split = string.split
local string_gsub  = string.gsub
local string_match = string.match
local math_max     = math.max
local os_clock     = os.clock

local cachedLocalPlayer = Players.LocalPlayer
local function getLocalPlayer()
	if not cachedLocalPlayer then
		cachedLocalPlayer = Players.LocalPlayer
	end
	return cachedLocalPlayer
end

local DEAD_STATE = Enum.HumanoidStateType.Dead

local ROOT_PART_NAMES = {
	"HumanoidRootPart",
	"Root",
	"UpperTorso",
	"Torso",
	"Head",
}

local function isLiveInstance(inst)
	return typeof(inst) == "Instance" and inst.Parent ~= nil and inst:IsDescendantOf(game)
end

local function resolveCharacterRoot(model)
	if not model or not model:IsA("Model") then return nil end
	local primary = model.PrimaryPart
	if primary and primary.Parent ~= nil and primary:IsA("BasePart") and primary:IsDescendantOf(model) then
		return primary
	end
	for i = 1, #ROOT_PART_NAMES do
		local part = model:FindFirstChild(ROOT_PART_NAMES[i])
		if part and part:IsA("BasePart") then
			return part
		end
	end
	return model:FindFirstChildWhichIsA("BasePart", true)
end

local function disconnectConn(conn)
	if conn and conn.Connected then
		conn:Disconnect()
	end
	return nil
end

local ConnectionManager = {}
ConnectionManager.__index = ConnectionManager

function ConnectionManager.new()
	return setmetatable({ _conns = {} }, ConnectionManager)
end

function ConnectionManager:_register(conn, label)
	local conns = self._conns
	if label ~= nil then
		local prev = conns[label]
		if prev and prev.Connected then
			prev:Disconnect()
		end
		conns[label] = conn
	else
		conns[conn] = conn
	end
end

function ConnectionManager:Connect(signal, fn, label)
	if not signal or not fn then return nil end
	local conn = signal:Connect(fn)
	self:_register(conn, label)
	return conn
end

function ConnectionManager:Disconnect(label)
	if label == nil then return end
	local conn = self._conns[label]
	if not conn then return end
	self._conns[label] = nil
	if conn.Connected then conn:Disconnect() end
end

function ConnectionManager:DisconnectAll()
	local conns = self._conns
	for _, conn in pairs(conns) do
		if conn.Connected then conn:Disconnect() end
	end
	table_clear(conns)
end

function ConnectionManager:Destroy()
	self:DisconnectAll()
end

local DEFAULTS = {
	PLAYER_ENABLED         = true,
	NPC_ENABLED            = false,
	NPC_FILTER             = nil,
	NPC_DIRECTORIES        = {},

	ON_CHARACTER_ADDED     = nil,
	ON_CHARACTER_REMOVING  = nil,
	ON_NPC_ADDED           = nil,
	ON_NPC_REMOVING        = nil,

	TARGET_LIMB            = nil,
	FORCEFIELD_CHECK       = false,
	STOP_TRACKING_ON_DEATH = true,
	DEATH_DETECT_METHOD    = "Health",
	ON_LIMB_READY          = nil,
	ON_LIMB_LOST           = nil,
	ON_TARGET_REVIVED      = nil,

	NPC_SPAWN_WAIT_TIMEOUT = 5,
	WARN_ON_CALLBACK_ERROR = true,
	ON_CALLBACK_ERROR      = nil,
	REQUIRE_ANCHOR         = true,

	GET_PLAYER_FROM_CHARACTER = nil,
	CUSTOM_CHARACTER_SYSTEM   = false,

	TEAM_MODE            = "none",
	TEAM_WHITELIST       = nil,
	TEAM_BLACKLIST       = nil,
	TEAM_CUSTOM_CHECK    = nil,
	PLAYER_WHITELIST     = nil,
	PLAYER_BLACKLIST     = nil,
	NAME_PATTERN         = nil,
	DISPLAY_NAME_PATTERN = nil,
	PLAYER_FILTER        = nil,
}

local FILTER_TABLE_KEYS = {
	TEAM_WHITELIST   = true,
	TEAM_BLACKLIST   = true,
	PLAYER_WHITELIST = true,
	PLAYER_BLACKLIST = true,
	NPC_DIRECTORIES  = true,
}

local function normalizeDirectoryPath(path)
	path = tostring(path or "")
	path = string_gsub(path, "^%s+", "")
	path = string_gsub(path, "%s+$", "")
	path = string_gsub(path, "^game:GetService%(%s*['\"]([^'\"]+)['\"]%s*%)", "%1")
	path = string_gsub(path, "^game%.", "")

	if path:sub(1, 9):lower() == "workspace" then
		local nextChar = path:sub(10, 10)
		if nextChar == "" or nextChar == "." or nextChar == ":" or nextChar == "[" then
			path = "Workspace" .. path:sub(10)
		end
	end

	path = string_gsub(path, ":%s*WaitForChild%(%s*['\"]([^'\"]+)['\"]%s*%)", ".%1")
	path = string_gsub(path, ":%s*FindFirstChild%(%s*['\"]([^'\"]+)['\"]%s*%)", ".%1")
	path = string_gsub(path, "%[%s*['\"]([^'\"]+)['\"]%s*%]", ".%1")
	path = string_gsub(path, "%.+", ".")
	path = string_gsub(path, "^%.", "")
	path = string_gsub(path, "%.$", "")

	return path
end

local function sanitizeDirectoryList(list)
	if type(list) ~= "table" then return {} end
	local out  = {}
	local seen = {}
	for i = 1, #list do
		local entry = list[i]
		if type(entry) == "string" then
			local norm = normalizeDirectoryPath(entry)
			if norm ~= "" and not seen[norm] then
				seen[norm]     = true
				out[#out + 1]  = norm
			end
		elseif typeof(entry) == "Instance" and not seen[entry] then
			seen[entry]   = true
			out[#out + 1] = entry
		end
	end
	return out
end

local function isEmptyList(t)
	return t == nil or (type(t) == "table" and #t == 0)
end

local function areListsEqual(a, b)
	if a == b then return true end
	if isEmptyList(a) and isEmptyList(b) then return true end
	if type(a) ~= "table" or type(b) ~= "table" then return false end
	local n = #a
	if n ~= #b then return false end
	for i = 1, n do
		if a[i] ~= b[i] then return false end
	end
	return true
end

local function mergeSettings(user)
	local s = table_clone(DEFAULTS)
	if type(user) == "table" then
		for k, v in pairs(user) do
			if k == "NPC_DIRECTORIES" then
				s[k] = sanitizeDirectoryList(v)
			elseif FILTER_TABLE_KEYS[k] and type(v) == "table" then
				s[k] = table_clone(v)
			else
				s[k] = v
			end
		end
	end

	if type(s.NPC_DIRECTORIES) ~= "table" then
		s.NPC_DIRECTORIES = {}
	elseif not (type(user) == "table" and type(user.NPC_DIRECTORIES) == "table") then
		s.NPC_DIRECTORIES = table_clone(s.NPC_DIRECTORIES)
	end

	return s
end

local function compilePlayerList(list)
	if type(list) ~= "table" or #list == 0 then return nil end
	local byId, byName, byInst = {}, {}, {}
	for i = 1, #list do
		local entry = list[i]
		local t = type(entry)
		if t == "number" then
			byId[entry] = true
		elseif t == "string" then
			byName[entry] = true
		elseif typeof(entry) == "Instance" and entry:IsA("Player") then
			byInst[entry] = true
		end
	end
	return { byId = byId, byName = byName, byInst = byInst }
end

local function compileTeamList(list)
	if type(list) ~= "table" or #list == 0 then return nil end
	local byName, byInst = {}, {}
	for i = 1, #list do
		local entry = list[i]
		if type(entry) == "string" then
			byName[entry] = true
		elseif typeof(entry) == "Instance" and entry:IsA("Team") then
			byInst[entry] = true
		end
	end
	return { byName = byName, byInst = byInst }
end

local function matchCompiledPlayer(compiled, player)
	return compiled.byInst[player] == true
		or compiled.byId[player.UserId] == true
		or compiled.byName[player.Name] == true
end

local function matchCompiledTeam(compiled, team)
	if not team then return false end
	return compiled.byInst[team] == true or compiled.byName[team.Name] == true
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
	local segs     = {}
	local stepKeys = {}
	local intKeys  = {}
	for seg in targetLimb:gmatch("[^%.]+") do
		local t = seg:match("^%s*(.-)%s*$")
		if t ~= "" then
			local idx = #segs + 1
			segs[idx]     = t
			stepKeys[idx] = "Step" .. idx
			intKeys[idx]  = "Int" .. idx
		end
	end
	if #segs == 0 then return nil end
	return { segs = segs, stepKeys = stepKeys, intKeys = intKeys }
end

local function splitNormalizedRoot(path)
	if type(path) ~= "string" or path == "" then return nil, nil, true end
	local norm = normalizeDirectoryPath(path)
	if norm == "" then return nil, nil, true end

	local parts = string_split(norm, ".")
	if #parts == 0 then return nil, nil, true end

	local rawHead = parts[1]
	local head    = rawHead:lower()
	local root

	if head == "game" then
		root = game
	elseif head == "workspace" then
		root = Workspace
	else
		local ok, svc = pcall(game.GetService, game, rawHead)
		if not ok or not svc then
			return nil, nil, true
		end
		root = cloneref(svc)
	end

	return root, parts, false
end

local function resolvePathAsync(path, timeoutPerPart)
	timeoutPerPart = timeoutPerPart or 5
	local current, parts = splitNormalizedRoot(path)
	if not current then return nil end

	for i = 2, #parts do
		local part = parts[i]
		if part ~= "" then
			local found = current:FindFirstChild(part)
			if not found then
				found = current:WaitForChild(part, timeoutPerPart)
			end
			if not found then return nil end
			current = found
		end
	end

	return current
end

local function resolvePathImmediate(path)
	local current, parts = splitNormalizedRoot(path)
	if not current then return nil end

	for i = 2, #parts do
		local part = parts[i]
		if part ~= "" then
			current = current:FindFirstChild(part)
			if not current then return nil end
		end
	end

	return current
end

local StreamObserver = {}
StreamObserver.__index = StreamObserver

function StreamObserver.new(model, onAvailable, onUnavailable, requireAnchor)
	local self = setmetatable({
		_model         = model,
		_onAvailable   = onAvailable,
		_onUnavailable = onUnavailable,
		_requireAnchor = requireAnchor ~= false,
		_active        = false,
		_destroyed     = false,
		_anchor        = nil,
		_ancestryConn  = nil,
		_anchorConn    = nil,
		_descAddedConn = nil,
		_primPartConn  = nil,
	}, StreamObserver)

	if typeof(model) == "Instance" then
		self._ancestryConn = model.AncestryChanged:Connect(function()
			if not self._destroyed then
				self:_refresh()
			end
		end)
	end

	self:_refresh()

	return self
end

function StreamObserver:IsActive()
	return not self._destroyed and self._active
end

function StreamObserver:SetRequireAnchor(requireAnchor)
	if self._destroyed then return end
	local req = requireAnchor ~= false
	if self._requireAnchor == req then return end
	self._requireAnchor = req
	self:_refresh()
end

function StreamObserver:_resolveAnchor()
	return resolveCharacterRoot(self._model)
end

function StreamObserver:_disconnectWaitSignals()
	self._descAddedConn = disconnectConn(self._descAddedConn)
	self._primPartConn  = disconnectConn(self._primPartConn)
end

function StreamObserver:_ensureWaitSignals()
	local model = self._model
	if not self._descAddedConn then
		self._descAddedConn = model.DescendantAdded:Connect(function(desc)
			if not self._destroyed and desc:IsA("BasePart") then
				self:_refresh()
			end
		end)
	end
	if not self._primPartConn then
		self._primPartConn = model:GetPropertyChangedSignal("PrimaryPart"):Connect(function()
			if not self._destroyed then
				self:_refresh()
			end
		end)
	end
end

function StreamObserver:_bindAnchor(anchor)
	if self._anchor == anchor then return end
	self._anchor     = anchor
	self._anchorConn = disconnectConn(self._anchorConn)
	if not anchor then return end

	self._anchorConn = anchor.AncestryChanged:Connect(function()
		if not self._destroyed then
			self:_refresh()
		end
	end)
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
		self:_disconnectWaitSignals()
		self:_setActive(false)
		return
	end

	if self._requireAnchor then
		local currentAnchor = self._anchor
		if currentAnchor and currentAnchor.Parent ~= nil and currentAnchor:IsDescendantOf(model) then
			self:_disconnectWaitSignals()
			self:_setActive(true)
			return
		end

		local anchor = self:_resolveAnchor()
		if anchor then
			self:_disconnectWaitSignals()
			self:_bindAnchor(anchor)
			self:_setActive(true)
		else
			self:_bindAnchor(nil)
			self:_ensureWaitSignals()
			self:_setActive(false)
		end
	else
		self:_bindAnchor(nil)
		self:_disconnectWaitSignals()
		self:_setActive(true)
	end
end

function StreamObserver:Destroy()
	if self._destroyed then return end
	self._destroyed = true

	self._ancestryConn  = disconnectConn(self._ancestryConn)
	self._anchorConn    = disconnectConn(self._anchorConn)
	self._descAddedConn = disconnectConn(self._descAddedConn)
	self._primPartConn  = disconnectConn(self._primPartConn)
	self._anchor        = nil

	if self._active then
		self._active = false
		local cb = self._onUnavailable
		if type(cb) == "function" then cb(self._model) end
	end
end

local function createStreamObserverSafe(model, label, onReady, onUnready, requireAnchor, assignFn)
	local ok, observerOrErr = pcall(StreamObserver.new, model, onReady, onUnready, requireAnchor)
	if ok then
		assignFn(observerOrErr)
	else
		warn(("[Manager] Failed to create StreamObserver for %s: %s"):format(tostring(label), tostring(observerOrErr)))
		task_defer(function()
			if not assignFn(nil, true) then return end
			local ok2, observerOrErr2 = pcall(StreamObserver.new, model, onReady, onUnready, requireAnchor)
			if ok2 then
				assignFn(observerOrErr2)
			else
				warn(("[Manager] Retry failed to create StreamObserver for %s: %s"):format(tostring(label), tostring(observerOrErr2)))
			end
		end)
	end
end

local LimbObserver = {}
LimbObserver.__index = LimbObserver

function LimbObserver.new(manager, model, playerObject)
	local self = setmetatable({
		_manager        = manager,
		_model          = model,
		_player         = playerObject,
		_ready          = false,
		_died           = false,
		_resolving      = false,
		_ffCount        = 0,
		_limb           = nil,
		_lifeConn       = nil,
		_conns          = ConnectionManager.new(),
		_destroyed      = false,
		_pathData       = nil,
		_deathMonitored = false,
	}, LimbObserver)

	self:_bindLifecycle()
	self:_start()
	return self
end

function LimbObserver:_clearPathConns()
	local pathData = self._pathData
	if not pathData then return end
	local stepKeys = pathData.stepKeys
	local intKeys  = pathData.intKeys
	local conns    = self._conns
	for i = 1, #stepKeys do
		conns:Disconnect(stepKeys[i])
		conns:Disconnect(intKeys[i])
	end
end

function LimbObserver:_findMatchingChild(container, name, isLeaf)
	local first = container:FindFirstChild(name)
	if not first then return nil end
	if not isLeaf or first:IsA("BasePart") then
		return first
	end
	local children = container:GetChildren()
	for i = 1, #children do
		local c = children[i]
		if c.Name == name and c:IsA("BasePart") then
			return c
		end
	end
	return nil
end

function LimbObserver:_resolveStep(container, pathData, depth)
	if self._destroyed or self._ready or self._died or self._ffCount > 0 then return end
	if not isLiveInstance(container) then return end

	local segs     = pathData.segs
	local stepKeys = pathData.stepKeys
	local intKeys  = pathData.intKeys
	local name     = segs[depth]
	local isLeaf   = depth == #segs
	local stepKey  = stepKeys[depth]

	local function proceed(child)
		if self._destroyed or self._ready or self._died or self._ffCount > 0 then return end

		if isLeaf then
			for i = 1, depth - 1 do
				self._conns:Disconnect(intKeys[i])
			end
			self:_onLimbFound(child)
		else
			self._conns:Connect(child.AncestryChanged, function()
				if self._destroyed then return end
				if child.Parent == nil or not child:IsDescendantOf(self._model) then
					for i = depth, #segs do
						self._conns:Disconnect(stepKeys[i])
						self._conns:Disconnect(intKeys[i])
					end
					if self._ready then
						self:_limbRemoved()
					elseif not self._died and self._ffCount <= 0 then
						self:_resolveStep(container, pathData, depth)
					end
				end
			end, intKeys[depth])

			self:_resolveStep(child, pathData, depth + 1)
		end
	end

	local existing = self:_findMatchingChild(container, name, isLeaf)
	if existing then
		proceed(existing)
	else
		self._conns:Connect(container.ChildAdded, function(child)
			if child.Name == name and (not isLeaf or child:IsA("BasePart")) then
				self._conns:Disconnect(stepKey)
				proceed(child)
			end
		end, stepKey)
	end
end

function LimbObserver:_bindLifecycle()
	if self._destroyed then return end
	local model = self._model
	if not isLiveInstance(model) then return end

	self._lifeConn = model.AncestryChanged:Connect(function()
		if self._destroyed then return end
		if not isLiveInstance(model) then
			self:_notifyLost(false)
		end
	end)
end

function LimbObserver:_evaluateForceFieldState()
	if self._destroyed or self._died then return end

	if self._ffCount <= 0 then
		if not self._ready and not self._resolving and self._pathData then
			self._resolving = true
			self:_resolveStep(self._model, self._pathData, 1)
		end
	else
		if self._resolving then
			self._resolving = false
			self:_clearPathConns()
		end
		if self._ready then
			self._ready = false
			local oldLimb = self._limb
			self._limb = nil
			self._conns:Disconnect("LimbStream")
			self:_clearPathConns()
			self._manager:_onLimbLost(self._player, self._model, oldLimb, false)
		end
	end
end

function LimbObserver:_start()
	if self._destroyed or self._ready or self._died then return end
	local model = self._model
	if not isLiveInstance(model) then
		self:_notifyLost(false)
		return
	end

	local pathData = self._manager._limbPath
	self._pathData = pathData
	if not pathData then return end

	local settings = self._manager._settings
	self._deathMonitored = false
	if settings.STOP_TRACKING_ON_DEATH then
		self:_monitorDeathEarly()
		if self._died or self._destroyed then return end
	end

	self._ffCount   = 0
	self._resolving = false

	if settings.FORCEFIELD_CHECK then
		local children = model:GetChildren()
		local count = 0
		for i = 1, #children do
			if children[i]:IsA("ForceField") then
				count = count + 1
			end
		end
		self._ffCount = count

		self._conns:Connect(model.ChildAdded, function(child)
			if not child:IsA("ForceField") then return end
			self._ffCount = self._ffCount + 1
			self:_evaluateForceFieldState()
		end, "ForceFieldAppeared")

		self._conns:Connect(model.ChildRemoved, function(child)
			if not child:IsA("ForceField") then return end
			self._ffCount = math_max(0, self._ffCount - 1)
			self:_evaluateForceFieldState()
		end, "ForceFieldWatcher")

		self:_evaluateForceFieldState()
		return
	end

	self._resolving = true
	self:_resolveStep(model, pathData, 1)
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

function LimbObserver:_connectReviveSignal(humanoid)
	if self._destroyed or not humanoid or not isLiveInstance(self._model) then return end
	local method = self._manager._settings.DEATH_DETECT_METHOD

	if method == "Health" then
		self._conns:Connect(humanoid:GetPropertyChangedSignal("Health"), function()
			if humanoid.Health > 0 then
				self:_onCharacterRevived()
			end
		end, "ReviveWatch")
	elseif humanoid.StateChanged then
		self._conns:Connect(humanoid.StateChanged, function(_, newState)
			if newState ~= DEAD_STATE and humanoid.Health > 0 then
				self:_onCharacterRevived()
			end
		end, "ReviveWatch")
	end
end

function LimbObserver:_connectDeathSignal(humanoid)
	if self._destroyed then return end
	local method = self._manager._settings.DEATH_DETECT_METHOD

	if method == "Health" then
		if humanoid.Health <= 0 then
			self:_onCharacterDied(humanoid)
			return
		end
		self._conns:Connect(humanoid:GetPropertyChangedSignal("Health"), function()
			if humanoid.Health <= 0 then
				self:_onCharacterDied(humanoid)
			end
		end, "DeathHealth")
	else
		local okState, curState = pcall(humanoid.GetState, humanoid)
		if okState and curState == DEAD_STATE then
			self:_onCharacterDied(humanoid)
			return
		end
		self._conns:Connect(humanoid.Died, function()
			self:_onCharacterDied(humanoid)
		end, "Died")
	end
end

function LimbObserver:_onCharacterDied(humanoid)
	if self._destroyed or self._died then return end
	self._died      = true
	self._resolving = false
	self:_notifyLost(true)
	if not self._destroyed and self._died and humanoid then
		self:_connectReviveSignal(humanoid)
	end
end

function LimbObserver:_onCharacterRevived()
	if self._destroyed or not self._died then return end
	self._conns:Disconnect("ReviveWatch")
	self._died           = false
	self._deathMonitored = false

	if not isLiveInstance(self._model) then return end
	self._manager:_onTargetRevived(self._player, self._model)
	if not self._destroyed then
		self:_start()
	end
end

function LimbObserver:_onLimbFound(limb)
	self._resolving = false
	self._limb      = limb
	self._ready     = true

	self._conns:Connect(limb.AncestryChanged, function()
		if self._destroyed then return end
		if limb.Parent == nil or not limb:IsDescendantOf(self._model) or not isLiveInstance(self._model) then
			self:_limbRemoved()
		end
	end, "LimbStream")

	self._manager:_onLimbReady(self._player, self._model, limb)
end

function LimbObserver:_limbRemoved()
	if self._destroyed or not self._ready then return end

	self._ready     = false
	self._resolving = false
	local oldLimb   = self._limb
	self._limb      = nil

	self._conns:Disconnect("LimbStream")
	self:_clearPathConns()

	self._manager:_onLimbLost(self._player, self._model, oldLimb, false)

	if not self._destroyed and not self._died and not self._ready and self._ffCount <= 0 then
		if isLiveInstance(self._model) and self._pathData then
			self._resolving = true
			self:_resolveStep(self._model, self._pathData, 1)
		end
	end
end

function LimbObserver:_notifyLost(fromDeath)
	if self._destroyed then return end

	local wasReady  = self._ready
	local oldLimb   = self._limb

	self._ready     = false
	self._resolving = false
	self._limb      = nil
	self._conns:DisconnectAll()

	if wasReady or fromDeath then
		self._manager:_onLimbLost(self._player, self._model, oldLimb, fromDeath == true)
	end
end

function LimbObserver:Refresh()
	if self._destroyed then return end

	local wasReady  = self._ready
	local oldLimb   = self._limb

	self._ready          = false
	self._died           = false
	self._resolving      = false
	self._ffCount        = 0
	self._deathMonitored = false
	self._limb           = nil
	self._conns:DisconnectAll()

	if wasReady then
		self._manager:_onLimbLost(self._player, self._model, oldLimb, false)
		if self._destroyed then return end
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

	self._ready     = false
	self._resolving = false
	self._limb      = nil
	self._lifeConn  = disconnectConn(self._lifeConn)
	self._conns:Destroy()

	if wasReady then
		manager:_onLimbLost(player, model, oldLimb, false)
	end
end

local PlayerData = {}
PlayerData.__index = PlayerData

function PlayerData.new(parent, player, initialChar)
	local self = setmetatable({
		_parent            = parent,
		player             = player,
		conns              = ConnectionManager.new(),
		_destroyed         = false,
		_character         = nil,
		_characterObserver = nil,
		_limbObserver      = nil,
		_ready             = false,
		_eligible          = false,
		_tracked           = false,
	}, PlayerData)

	self:_updateCharacterModeSignals()
	self:_updateTeamSignal()
	self._eligible = parent:_evaluatePlayerFilter(player)

	local char = initialChar
	if not char and not parent._settings.CUSTOM_CHARACTER_SYSTEM then
		char = player.Character
	end
	if char then
		self:_onCharacterAdded(char)
	end

	return self
end

function PlayerData:_updateCharacterModeSignals()
	if self._destroyed then return end
	if not self._parent._settings.CUSTOM_CHARACTER_SYSTEM then
		self.conns:Connect(self.player.CharacterAdded, function(char)
			self:_onCharacterAdded(char)
		end, "CharacterAdded")

		self.conns:Connect(self.player.CharacterRemoving, function(char)
			self:_onCharacterRemoving(char)
		end, "CharacterRemoving")

		self.conns:Connect(self.player:GetPropertyChangedSignal("Character"), function()
			if self._destroyed then return end
			local char = self.player.Character
			if char then
				if self._character ~= char then
					self:_onCharacterAdded(char)
				end
			elseif self._character ~= nil then
				self:_onCharacterRemoving(self._character)
			end
		end, "CharacterChanged")
	else
		self.conns:Disconnect("CharacterAdded")
		self.conns:Disconnect("CharacterRemoving")
		self.conns:Disconnect("CharacterChanged")
	end
end

function PlayerData:_updateTeamSignal()
	local s = self._parent._settings
	if s.TEAM_MODE ~= "none" then
		self.conns:Connect(self.player:GetPropertyChangedSignal("Team"), function()
			self:EvaluateFilter()
		end, "TeamChanged")
	else
		self.conns:Disconnect("TeamChanged")
	end
end

function PlayerData:_ensureCharacterObserver()
	if self._destroyed or self._characterObserver then return end
	local char = self._character
	if not char or typeof(char) ~= "Instance" or not char:IsA("Model") then return end

	local requireAnchor = self._parent._settings.REQUIRE_ANCHOR

	local function onReady()
		if self._destroyed or self._character ~= char then return end
		self._ready = true
		self:_updateTrackedState()
	end

	local function onUnready()
		if self._destroyed or self._character ~= char then return end
		self._ready = false
		self:_updateTrackedState()
	end

	createStreamObserverSafe(char, self.player.Name, onReady, onUnready, requireAnchor, function(obs, checkRetry)
		if checkRetry then
			return not self._destroyed and self._character == char and self._eligible and not self._characterObserver
		end
		self._characterObserver = obs
		return true
	end)
end

function PlayerData:EvaluateFilter()
	if self._destroyed then return end
	local eligible = self._parent:_evaluatePlayerFilter(self.player)
	self._eligible = eligible

	if eligible then
		if self._character and not self._characterObserver then
			self:_ensureCharacterObserver()
			return
		end
	else
		if self._characterObserver then
			self:_teardownCharacterObserver()
		end
	end

	self:_updateTrackedState()
end

function PlayerData:_updateTrackedState()
	if self._destroyed then return end
	local parent      = self._parent
	local char        = self._character
	local shouldTrack = self._ready and self._eligible and char ~= nil

	if shouldTrack and not self._tracked then
		self._tracked = true
		parent:_onTargetTracked(char)
		parent:_fireCallback("ON_CHARACTER_ADDED", parent._settings.ON_CHARACTER_ADDED, self.player, char)
		if not self._destroyed and self._tracked and parent._limbPath then
			self:_setupLimbTracking(char)
		end
	elseif not shouldTrack and self._tracked then
		self._tracked = false
		self:_teardownLimbTracking()
		if not self._destroyed then
			parent:_onTargetUntracked(char)
			parent:_fireCallback("ON_CHARACTER_REMOVING", parent._settings.ON_CHARACTER_REMOVING, self.player, char)
		end
	end
end

function PlayerData:_onCharacterAdded(char)
	if self._destroyed or typeof(char) ~= "Instance" or not char:IsA("Model") then return end

	self._parent:_unregisterNPC(char)

	if self._character == char then
		if self._eligible and not self._characterObserver then
			self:_ensureCharacterObserver()
		end
		return
	end

	if self._character ~= nil then
		self:_onCharacterRemoving(self._character)
		if self._destroyed then return end
	end

	self._character = char
	if self._eligible then
		self:_ensureCharacterObserver()
	end
end

function PlayerData:_teardownCharacterObserver()
	if self._characterObserver then
		local obs = self._characterObserver
		self._characterObserver = nil
		obs:Destroy()
	end
	self._ready = false
end

function PlayerData:_setupLimbTracking(char)
	if self._destroyed or not isLiveInstance(char) then return end
	self:_teardownLimbTracking()
	self._limbObserver = LimbObserver.new(self._parent, char, self.player)
end

function PlayerData:_teardownLimbTracking()
	if self._limbObserver then
		local obs = self._limbObserver
		self._limbObserver = nil
		obs:Destroy()
	end
end

function PlayerData:_onCharacterRemoving(char)
	if self._destroyed then return end
	if char ~= nil and self._character ~= char then return end
	local oldChar = self._character
	if not oldChar then return end

	self:_teardownCharacterObserver()
	self:_updateTrackedState()
	if self._character == oldChar then
		self._character = nil
	end
end

function PlayerData:Destroy()
	if self._destroyed then return end
	local wasTracked = self._tracked
	local oldChar    = self._character
	self._tracked    = false
	self._destroyed  = true

	self.conns:Destroy()
	self:_teardownLimbTracking()
	self:_teardownCharacterObserver()
	self._character = nil

	if wasTracked and oldChar then
		self._parent:_onTargetUntracked(oldChar)
		self._parent:_fireCallback("ON_CHARACTER_REMOVING", self._parent._settings.ON_CHARACTER_REMOVING, self.player, oldChar)
	end
end

local NPCData = {}
NPCData.__index = NPCData

function NPCData.new(manager, model, dir)
	local self = setmetatable({
		_manager      = manager,
		model         = model,
		_dir          = dir,
		_destroyed    = false,
		_observer     = nil,
		_limbObserver = nil,
		_ready        = false,
		_eligible     = false,
		_tracked      = false,
	}, NPCData)

	self:EvaluateFilter()

	return self
end

function NPCData:_setupObserver()
	if self._destroyed or self._observer then return end
	local manager       = self._manager
	local model         = self.model
	local requireAnchor = manager._settings.REQUIRE_ANCHOR

	local function onReady()
		if self._destroyed then return end
		self._ready = true
		self:_updateTrackedState()
	end

	local function onUnready()
		if self._destroyed then return end
		self._ready = false
		self:_updateTrackedState()
	end

	createStreamObserverSafe(model, "NPC " .. model.Name, onReady, onUnready, requireAnchor, function(obs, checkRetry)
		if checkRetry then
			return not self._destroyed and self._eligible and not self._observer
		end
		self._observer = obs
		return true
	end)
end

function NPCData:_teardownObserver()
	if self._observer then
		local obs = self._observer
		self._observer = nil
		obs:Destroy()
	end
	self._ready = false
end

function NPCData:EvaluateFilter()
	if self._destroyed then return end
	local filter   = self._manager._settings.NPC_FILTER
	local eligible = true
	if type(filter) == "function" then
		local ok, result = pcall(filter, self.model)
		eligible = (ok and result) and true or false
	end
	self._eligible = eligible

	if eligible then
		if not self._observer then
			self:_setupObserver()
			return
		end
	else
		if self._observer then
			self:_teardownObserver()
		end
	end

	self:_updateTrackedState()
end

function NPCData:_updateTrackedState()
	if self._destroyed then return end
	local manager     = self._manager
	local model       = self.model
	local shouldTrack = self._ready and self._eligible

	if shouldTrack and not self._tracked then
		self._tracked = true
		manager:_onTargetTracked(model)
		manager:_fireCallback("ON_NPC_ADDED", manager._settings.ON_NPC_ADDED, model)
		if not self._destroyed and self._tracked and manager._limbPath then
			self:_setupLimbTracking()
		end
	elseif not shouldTrack and self._tracked then
		self._tracked = false
		self:_teardownLimbTracking()
		if not self._destroyed then
			manager:_onTargetUntracked(model)
			manager:_fireCallback("ON_NPC_REMOVING", manager._settings.ON_NPC_REMOVING, model)
		end
	end
end

function NPCData:_setupLimbTracking()
	if self._destroyed or not isLiveInstance(self.model) then return end
	self:_teardownLimbTracking()
	self._limbObserver = LimbObserver.new(self._manager, self.model, nil)
end

function NPCData:_teardownLimbTracking()
	if self._limbObserver then
		local obs = self._limbObserver
		self._limbObserver = nil
		obs:Destroy()
	end
end

function NPCData:IsStructurallyValid()
	local manager = self._manager
	local model   = self.model
	if not isLiveInstance(model) or not model:IsA("Model") then return false end
	if model == manager:GetLocalCharacter() then return false end
	if not model:FindFirstChildOfClass("Humanoid") then return false end
	if manager:GetPlayerFromCharacter(model) then return false end
	return true
end

function NPCData:Destroy()
	if self._destroyed then return end
	local wasTracked = self._tracked
	local model      = self.model
	self._tracked    = false
	self._destroyed  = true

	self:_teardownLimbTracking()
	self:_teardownObserver()

	if wasTracked then
		self._manager:_onTargetUntracked(model)
		self._manager:_fireCallback("ON_NPC_REMOVING", self._manager._settings.ON_NPC_REMOVING, model)
	end
end

local Manager = {}
Manager.__index = Manager

function Manager:_fireCallback(name, cb, ...)
	if type(cb) ~= "function" then return true end
	local ok, err = pcall(cb, ...)
	if not ok then
		if self._settings.WARN_ON_CALLBACK_ERROR then
			warn(("[Manager] Error in %s callback: %s"):format(name, tostring(err)))
		end
		local errCb = self._settings.ON_CALLBACK_ERROR
		if type(errCb) == "function" then
			pcall(errCb, name, err)
		end
	end
	return ok
end

function Manager:_recompileFilters()
	local s = self._settings
	self._compiledPlayerWhitelist = compilePlayerList(s.PLAYER_WHITELIST)
	self._compiledPlayerBlacklist = compilePlayerList(s.PLAYER_BLACKLIST)
	self._compiledTeamWhitelist   = compileTeamList(s.TEAM_WHITELIST)
	self._compiledTeamBlacklist   = compileTeamList(s.TEAM_BLACKLIST)
end

function Manager:_evaluatePlayerFilter(player)
	local s = self._settings

	local wl = self._compiledPlayerWhitelist
	if wl then
		if not matchCompiledPlayer(wl, player) then
			return false
		end
	end

	local bl = self._compiledPlayerBlacklist
	if bl then
		if matchCompiledPlayer(bl, player) then
			return false
		end
	end

	if s.NAME_PATTERN then
		local ok, matched = pcall(string_match, player.Name, s.NAME_PATTERN)
		if not ok or not matched then return false end
	end
	if s.DISPLAY_NAME_PATTERN then
		local ok, matched = pcall(string_match, player.DisplayName, s.DISPLAY_NAME_PATTERN)
		if not ok or not matched then return false end
	end
	if s.PLAYER_FILTER then
		local ok, result = pcall(s.PLAYER_FILTER, player)
		if not ok or not result then return false end
	end

	local mode = s.TEAM_MODE
	if mode == "none" then
		return true
	end

	local lp        = getLocalPlayer()
	local localTeam = lp and lp.Team or nil
	local otherTeam = player.Team

	if mode == "same" then
		if localTeam == nil or otherTeam == nil then return false end
		return localTeam == otherTeam
	elseif mode == "different" then
		if localTeam then
			return otherTeam ~= localTeam
		end
		return true
	elseif mode == "whitelist" then
		local twl = self._compiledTeamWhitelist
		if not twl then return false end
		return matchCompiledTeam(twl, otherTeam)
	elseif mode == "blacklist" then
		local tbl = self._compiledTeamBlacklist
		if not tbl then return true end
		return not matchCompiledTeam(tbl, otherTeam)
	elseif mode == "custom" then
		local customCheck = s.TEAM_CUSTOM_CHECK
		if type(customCheck) == "function" then
			local ok, result = pcall(customCheck, localTeam, otherTeam)
			return (ok and result) and true or false
		end
		return false
	end

	return true
end

function Manager.new(userSettings)
	local settings    = mergeSettings(userSettings)
	local refBindable = Instance.new("BindableEvent")

	local self = setmetatable({
		_settings = settings,
		_limbPath = parseLimbPath(settings.TARGET_LIMB),

		_compiledPlayerWhitelist = nil,
		_compiledPlayerBlacklist = nil,
		_compiledTeamWhitelist   = nil,
		_compiledTeamBlacklist   = nil,

		_playerTable        = {},
		_customPlayerChars  = {},
		_customCharToPlayer = {},
		_npcSet             = {},

		_pendingWatchConns     = {},
		_pendingWatchDeadlines = {},
		_pendingWatchDirs      = {},
		_pendingSweepActive    = false,

		_connections    = nil,
		_npcConnections = nil,
		_localConns     = ConnectionManager.new(),

		_playerConnsStarted     = false,
		_npcConnsStarted        = false,
		_usingFallbackWorkspace = false,

		_running          = false,
		_destroyed        = false,
		_generation       = 0,
		_playerGeneration = 0,

		_dirIdCounter      = 0,
		_dirUidMap         = {},
		_dirRefCount       = {},
		_stringDirMap      = {},
		_stringWatchTokens = {},
		_npcDirOwners      = {},

		_customLocalChar    = nil,
		_sampleChar         = nil,
		_lastEmittedRefChar = nil,
		_refCharBindable    = refBindable,
		ReferenceCharacterChanged = refBindable.Event,
	}, Manager)

	self:_recompileFilters()
	self:_bindLocalPlayerSignals()

	return self
end

function Manager:IsRunning()
	return self._running and not self._destroyed
end

function Manager:GetPlayerFromCharacter(model)
	if not model then return nil end
	local customOwner = self._customCharToPlayer[model]
	if customOwner then
		if isLiveInstance(customOwner) then
			return customOwner
		end
		self._customCharToPlayer[model]      = nil
		self._customPlayerChars[customOwner] = nil
	end
	return getPlayerFromCharacter(self._settings, model)
end

function Manager:_emitReferenceCharIfChanged()
	if self._destroyed or not self._refCharBindable then return end
	local ref = self:GetReferenceCharacter()
	if ref and ref ~= self._lastEmittedRefChar then
		self._lastEmittedRefChar = ref
		self._refCharBindable:Fire(ref)
	elseif not ref then
		self._lastEmittedRefChar = nil
	end
end

function Manager:_onTargetTracked(model)
	if not model or self._destroyed then return end
	if not self:GetLocalCharacter() and not isLiveInstance(self._sampleChar) then
		self._sampleChar = model
		self:_emitReferenceCharIfChanged()
	end
end

function Manager:_onTargetUntracked(model)
	if not model or self._destroyed then return end
	if self._sampleChar == model or self._lastEmittedRefChar == model then
		if self._sampleChar == model then
			self._sampleChar = nil
		end
		self:_emitReferenceCharIfChanged()
	end
end

function Manager:_bindLocalPlayerSignals()
	if self._destroyed then return end
	local lp = getLocalPlayer()
	if lp then
		self._localConns:Disconnect("WaitLocalPlayer")

		local stalePd = self._playerTable[lp]
		if stalePd then
			self._playerTable[lp] = nil
			stalePd:Destroy()
		end

		if lp.Character then
			self:_unregisterNPC(lp.Character)
		end

		self._localConns:Connect(lp:GetPropertyChangedSignal("Character"), function()
			if self._destroyed then return end
			local c = lp.Character
			if c then
				self:_unregisterNPC(c)
			end
			self:_emitReferenceCharIfChanged()
		end, "LocalCharChanged")

		self:_emitReferenceCharIfChanged()
	else
		self._localConns:Connect(Players:GetPropertyChangedSignal("LocalPlayer"), function()
			if not self._destroyed then
				self:_bindLocalPlayerSignals()
				if self._running and self._playerConnsStarted then
					self:_bindLocalTeamSignal()
				end
			end
		end, "WaitLocalPlayer")
	end
end

function Manager:_bindLocalTeamSignal()
	if not self._connections then return end
	local lp = getLocalPlayer()
	if not lp then return end
	self._connections:Connect(lp:GetPropertyChangedSignal("Team"), function()
		if not self._running or self._destroyed then return end
		local mode = self._settings.TEAM_MODE
		if mode == "none" or mode == "whitelist" or mode == "blacklist" then return end
		for _, pd in pairs(self._playerTable) do
			if not self._running or self._destroyed then break end
			pd:EvaluateFilter()
		end
	end, "LocalTeamChanged")
end

function Manager:SetLocalCharacter(model)
	if self._destroyed then return end
	if model ~= nil and not isLiveInstance(model) then
		model = nil
	end
	if self._customLocalChar == model then return end
	self._customLocalChar = model

	if model then
		self:_unregisterNPC(model)
		local lp = getLocalPlayer()
		if lp and self._playerTable[lp] then
			local pd = self._playerTable[lp]
			self._playerTable[lp] = nil
			pd:Destroy()
		end
	end

	self:_emitReferenceCharIfChanged()
end

function Manager:GetLocalCharacter()
	if self._destroyed then return nil end
	local custom = self._customLocalChar
	if custom then
		if isLiveInstance(custom) then
			return custom
		end
		self._customLocalChar = nil
	end
	local lp = getLocalPlayer()
	local stdChar = lp and lp.Character or nil
	return isLiveInstance(stdChar) and stdChar or nil
end

function Manager:SetSampleCharacter(model)
	if self._destroyed then return end
	if model ~= nil and not isLiveInstance(model) then
		model = nil
	end
	self._sampleChar = model
	self:_emitReferenceCharIfChanged()
end

function Manager:GetReferenceCharacter()
	if self._destroyed then return nil end
	local localChar = self:GetLocalCharacter()
	if localChar then
		return localChar
	end
	if isLiveInstance(self._sampleChar) then
		return self._sampleChar
	end
	for _, char in pairs(self._customPlayerChars) do
		if isLiveInstance(char) then
			self._sampleChar = char
			return char
		end
	end
	for _, pd in pairs(self._playerTable) do
		if isLiveInstance(pd._character) then
			self._sampleChar = pd._character
			return pd._character
		end
	end
	for model in pairs(self._npcSet) do
		if isLiveInstance(model) then
			self._sampleChar = model
			return model
		end
	end
	return nil
end

function Manager:OnReferenceCharacterChanged(callback)
	if self._destroyed or type(callback) ~= "function" or not self._refCharBindable then
		return nil
	end
	return self._refCharBindable.Event:Connect(callback)
end

Manager.OnLocalCharacterChanged = Manager.OnReferenceCharacterChanged

function Manager:_onLimbReady(player, model, limb)
	local cb = self._settings.ON_LIMB_READY
	self:_fireCallback("ON_LIMB_READY", cb, player, model, limb)
end

function Manager:_onLimbLost(player, model, limb, fromDeath)
	local cb = self._settings.ON_LIMB_LOST
	self:_fireCallback("ON_LIMB_LOST", cb, player, model, limb, fromDeath == true)
end

function Manager:_onTargetRevived(player, model)
	local cb = self._settings.ON_TARGET_REVIVED
	self:_fireCallback("ON_TARGET_REVIVED", cb, player, model)
end

function Manager:_checkNPCStructural(model)
	if not model or not model:IsA("Model") then return false, false end
	if model == self:GetLocalCharacter() then return false, false end
	if self:GetPlayerFromCharacter(model) then return false, false end
	if not model:FindFirstChildOfClass("Humanoid") then return false, true end
	return true, false
end

function Manager:_registerNPC(model, dir)
	if self._destroyed or not model then return end
	if not isLiveInstance(model) then return end
	if self._npcSet[model] or self._pendingWatchConns[model] then return end

	local valid, missingHumanoid = self:_checkNPCStructural(model)
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
	if model == self:GetLocalCharacter() or self:GetPlayerFromCharacter(model) then return end

	local data = NPCData.new(self, model, dir)
	if self._destroyed or not self._running or not self._npcConnsStarted then
		data:Destroy()
		return
	end
	self._npcSet[model] = data
	if dir then
		self._npcDirOwners[model] = dir
	end
end

function Manager:_ensurePendingSweep()
	if self._pendingSweepActive then return end
	self._pendingSweepActive = true

	local gen = self._generation
	task_spawn(function()
		while self._running and self._npcConnsStarted and not self._destroyed and self._generation == gen do
			task_wait(0.5)
			if not (self._running and self._npcConnsStarted and not self._destroyed and self._generation == gen) then
				break
			end

			local now       = os_clock()
			local conns     = self._pendingWatchConns
			local deadlines = self._pendingWatchDeadlines
			local dirs      = self._pendingWatchDirs

			for model, exp in pairs(deadlines) do
				if now >= exp or not isLiveInstance(model) then
					local c = conns[model]
					conns[model]     = nil
					deadlines[model] = nil
					dirs[model]      = nil
					if c and c.Connected then
						c:Disconnect()
					end
				end
			end

			if next(deadlines) == nil then
				break
			end
		end
		self._pendingSweepActive = false
	end)
end

function Manager:_watchForHumanoid(model, dir)
	if self._pendingWatchConns[model] then return end
	local timeout = self._settings.NPC_SPAWN_WAIT_TIMEOUT or 5
	if timeout <= 0 then return end

	local gen = self._generation
	self._pendingWatchDeadlines[model] = os_clock() + timeout
	if dir then
		self._pendingWatchDirs[model] = dir
	end

	self._pendingWatchConns[model] = model.ChildAdded:Connect(function(child)
		if not child:IsA("Humanoid") then return end
		local savedDir = self._pendingWatchDirs[model] or dir
		self:_cancelPendingNPCWatch(model)
		if self._running and self._npcConnsStarted and not self._destroyed
			and self._generation == gen and isLiveInstance(model) then
			if not savedDir or self._dirUidMap[savedDir] ~= nil then
				self:_registerNPC(model, savedDir)
			end
		end
	end)

	self:_ensurePendingSweep()
end

function Manager:_cancelPendingNPCWatch(model)
	local conn = self._pendingWatchConns[model]
	if conn then
		self._pendingWatchConns[model] = nil
		if conn.Connected then conn:Disconnect() end
	end
	self._pendingWatchDeadlines[model] = nil
	self._pendingWatchDirs[model]      = nil
end

function Manager:_clearAllPendingNPCWatches()
	for _, conn in pairs(self._pendingWatchConns) do
		if conn.Connected then conn:Disconnect() end
	end
	table_clear(self._pendingWatchConns)
	table_clear(self._pendingWatchDeadlines)
	table_clear(self._pendingWatchDirs)
	self._pendingSweepActive = false
end

function Manager:_unregisterNPC(model)
	if not model then return end
	self:_cancelPendingNPCWatch(model)

	local data = self._npcSet[model]
	if data then
		self._npcSet[model]       = nil
		self._npcDirOwners[model] = nil
		data:Destroy()
	else
		self._npcDirOwners[model] = nil
	end
end

function Manager:_hasStringDir(entry)
	local dirs = self._settings.NPC_DIRECTORIES
	if type(dirs) ~= "table" then return false end
	for i = 1, #dirs do
		if dirs[i] == entry then return true end
	end
	return false
end

function Manager:_activateAndWatchStringDir(entry, resolved, gen, token)
	self._stringDirMap[entry] = resolved
	local uid = self:_activateDirectory(resolved, false)
	if uid and self._npcConnections then
		local rebound = false
		self._npcConnections:Connect(resolved.AncestryChanged, function()
			if rebound or self._destroyed or not self._running or not self._npcConnsStarted then return end
			if self._generation ~= gen or self._stringWatchTokens[entry] ~= token then return end
			if not isLiveInstance(resolved) then
				rebound = true
				if self._stringDirMap[entry] == resolved then
					self._stringDirMap[entry] = nil
				end
				self:_deactivateDirectoryInstance(resolved)
				if self:_hasStringDir(entry) then
					self:_bindStringDirectoryAsync(entry)
				end
			end
		end, uid .. "_StringDirAncestry_" .. tostring(token))
	end
end

function Manager:_bindStringDirectoryAsync(entry)
	local gen   = self._generation
	local token = {}
	self._stringWatchTokens[entry] = token

	task_spawn(function()
		while self._running and self._npcConnsStarted and not self._destroyed
			and self._generation == gen and self._stringWatchTokens[entry] == token
			and self:_hasStringDir(entry) do

			local root, _, fatal = splitNormalizedRoot(entry)
			if fatal or not root then
				if self._stringWatchTokens[entry] == token then
					self._stringWatchTokens[entry] = nil
				end
				return
			end

			local resolved = resolvePathAsync(entry, 5)
			if not (self._running and self._npcConnsStarted and not self._destroyed
				and self._generation == gen and self._stringWatchTokens[entry] == token
				and self:_hasStringDir(entry)) then
				return
			end

			if resolved and isLiveInstance(resolved) then
				self:_activateAndWatchStringDir(entry, resolved, gen, token)
				return
			end

			task_wait(1)
		end
	end)
end

function Manager:_bindDirectoryEntry(entry)
	if isLiveInstance(entry) then
		self:_activateDirectory(entry, false)
	elseif type(entry) == "string" then
		local immediate = resolvePathImmediate(entry)
		if immediate and isLiveInstance(immediate) then
			local token = {}
			self._stringWatchTokens[entry] = token
			self:_activateAndWatchStringDir(entry, immediate, self._generation, token)
		else
			self:_bindStringDirectoryAsync(entry)
		end
	end
end

function Manager:_activateDirectory(dir, useDescendants)
	if not dir or not self._npcConnections then return nil end

	local existingUid = self._dirUidMap[dir]
	if existingUid then
		self._dirRefCount[dir] = (self._dirRefCount[dir] or 1) + 1
		return existingUid
	end

	self._dirIdCounter = self._dirIdCounter + 1
	local uid = tostring(self._dirIdCounter)
	self._dirUidMap[dir]   = uid
	self._dirRefCount[dir] = 1

	local gen = self._generation

	if useDescendants then
		self._npcConnections:Connect(dir.DescendantAdded, function(desc)
			if not desc:IsA("Model") then return end
			task_defer(function()
				if self._running and self._npcConnsStarted
					and not self._destroyed
					and self._generation == gen
					and self._dirUidMap[dir] == uid then
					self:_registerNPC(desc, dir)
				end
			end)
		end, uid .. "_DescendantAdded")

		self._npcConnections:Connect(dir.DescendantRemoving, function(desc)
			if not desc:IsA("Model") then return end
			self:_unregisterNPC(desc)
		end, uid .. "_DescendantRemoving")
	else
		self._npcConnections:Connect(dir.ChildAdded, function(desc)
			if not desc:IsA("Model") then return end
			task_defer(function()
				if self._running and self._npcConnsStarted
					and not self._destroyed
					and self._generation == gen
					and self._dirUidMap[dir] == uid then
					self:_registerNPC(desc, dir)
				end
			end)
		end, uid .. "_ChildAdded")

		self._npcConnections:Connect(dir.ChildRemoved, function(desc)
			if not desc:IsA("Model") then return end
			self:_unregisterNPC(desc)
		end, uid .. "_ChildRemoved")
	end

	local raw = useDescendants and dir:GetDescendants() or dir:GetChildren()
	local candidates = {}
	for i = 1, #raw do
		local inst = raw[i]
		if inst:IsA("Model") then
			candidates[#candidates + 1] = inst
		end
	end

	if #candidates > 0 then
		task_spawn(function()
			local BUDGET_LIMIT = 600
			local budget       = 0
			local count        = #candidates

			for i = 1, count do
				if not self._running or self._destroyed or self._generation ~= gen or self._dirUidMap[dir] ~= uid then
					return
				end

				local cand   = candidates[i]
				local hadHum = cand.Parent ~= nil and cand:FindFirstChildOfClass("Humanoid") ~= nil
				self:_registerNPC(cand, dir)
				budget = budget + (hadHum and 10 or 1)

				if budget >= BUDGET_LIMIT and i < count then
					budget = 0
					task_wait()
				end
			end
		end)
	end

	return uid
end

function Manager:_deactivateDirectoryInstance(instance)
	if not instance then return end
	local uid = self._dirUidMap[instance]
	if not uid then return end

	local refs = (self._dirRefCount[instance] or 1) - 1
	if refs > 0 then
		self._dirRefCount[instance] = refs
		return
	end

	self._dirRefCount[instance] = nil
	self._dirUidMap[instance]   = nil

	if self._npcConnections then
		self._npcConnections:Disconnect(uid .. "_DescendantAdded")
		self._npcConnections:Disconnect(uid .. "_DescendantRemoving")
		self._npcConnections:Disconnect(uid .. "_ChildAdded")
		self._npcConnections:Disconnect(uid .. "_ChildRemoved")
	end

	local pendingModels = {}
	for model, owner in pairs(self._pendingWatchDirs) do
		if owner == instance then
			pendingModels[#pendingModels + 1] = model
		end
	end
	for i = 1, #pendingModels do
		self:_cancelPendingNPCWatch(pendingModels[i])
	end

	local toRemove = {}
	for model, owner in pairs(self._npcDirOwners) do
		if owner == instance then
			toRemove[#toRemove + 1] = model
		end
	end
	for i = 1, #toRemove do
		self:_unregisterNPC(toRemove[i])
	end
end

function Manager:_refreshAllLimbObservers()
	local hasTarget = self._limbPath ~= nil

	for _, pd in pairs(self._playerTable) do
		if self._destroyed or not self._running then return end
		if pd._tracked then
			if hasTarget then
				if pd._limbObserver then
					pd._limbObserver:Refresh()
				elseif pd._character then
					pd:_setupLimbTracking(pd._character)
				end
			else
				pd:_teardownLimbTracking()
			end
		end
	end

	for _, data in pairs(self._npcSet) do
		if self._destroyed or not self._running then return end
		if data._tracked then
			if hasTarget then
				if data._limbObserver then
					data._limbObserver:Refresh()
				else
					data:_setupLimbTracking()
				end
			else
				data:_teardownLimbTracking()
			end
		end
	end
end

function Manager:_refreshAllRequireAnchor()
	local req = self._settings.REQUIRE_ANCHOR ~= false

	for _, pd in pairs(self._playerTable) do
		if self._destroyed or not self._running then return end
		if pd._characterObserver then
			pd._characterObserver:SetRequireAnchor(req)
		end
	end

	for _, data in pairs(self._npcSet) do
		if self._destroyed or not self._running then return end
		if data._observer then
			data._observer:SetRequireAnchor(req)
		end
	end
end

function Manager:_rescanNPCFilter()
	if self._destroyed or not self._running or not self._npcConnsStarted then return end

	local snapshot = {}
	for model, data in pairs(self._npcSet) do
		snapshot[#snapshot + 1] = { model = model, data = data }
	end

	local gen = self._generation
	for i = 1, #snapshot do
		if not self._running or self._destroyed or not self._npcConnsStarted or self._generation ~= gen then
			return
		end
		local item  = snapshot[i]
		local model = item.model
		local data  = item.data
		if self._npcSet[model] == data then
			if not data:IsStructurallyValid() then
				self:_unregisterNPC(model)
			else
				data:EvaluateFilter()
			end
		end
	end
end

function Manager:_setCustomCharMapping(player, model)
	local prevModel = self._customPlayerChars[player]
	if prevModel and prevModel ~= model then
		if self._customCharToPlayer[prevModel] == player then
			self._customCharToPlayer[prevModel] = nil
		end
	end
	if model then
		local prevOwner = self._customCharToPlayer[model]
		if prevOwner and prevOwner ~= player then
			self._customPlayerChars[prevOwner] = nil
			local prevPd = self._playerTable[prevOwner]
			if prevPd then
				prevPd:_onCharacterRemoving(model)
			end
		end
		self._customPlayerChars[player] = model
		self._customCharToPlayer[model] = player
	else
		self._customPlayerChars[player] = nil
	end
end

function Manager:_applyStoredCustomCharacters()
	if not self._running or not self._settings.PLAYER_ENABLED then return end
	local lp = getLocalPlayer()
	for player, model in pairs(self._customPlayerChars) do
		if not isLiveInstance(player) or not isLiveInstance(model) then
			self._customPlayerChars[player] = nil
			if model and self._customCharToPlayer[model] == player then
				self._customCharToPlayer[model] = nil
			end
		elseif player ~= lp then
			local pd = self._playerTable[player]
			if not pd then
				pd = PlayerData.new(self, player, model)
				self._playerTable[player] = pd
			else
				pd:_onCharacterAdded(model)
			end
		end
	end
end

function Manager:_rescanCustomPlayers()
	if not self._running or not self._settings.CUSTOM_CHARACTER_SYSTEM then return end

	self:_applyStoredCustomCharacters()

	local getPlayer = self._settings.GET_PLAYER_FROM_CHARACTER
	if type(getPlayer) ~= "function" then return end

	local dirs        = self._settings.NPC_DIRECTORIES
	local hasUserDirs = type(dirs) == "table" and #dirs > 0
	if not hasUserDirs then return end

	for i = 1, #dirs do
		local entry    = dirs[i]
		local instance = isLiveInstance(entry) and entry or self._stringDirMap[entry]
		if not instance and type(entry) == "string" then
			instance = resolvePathImmediate(entry)
		end
		if instance and isLiveInstance(instance) then
			local children = instance:GetChildren()
			for j = 1, #children do
				local obj = children[j]
				if obj:IsA("Model") then
					local ok, player = pcall(getPlayer, obj)
					if ok and player then
						self:RegisterPlayerCharacter(player, obj)
					end
				end
			end
		end
	end
end

function Manager:_rescanPlayers()
	if self._destroyed or not self._running or not self._playerConnsStarted then return false end

	local changed  = false
	local isCustom = self._settings.CUSTOM_CHARACTER_SYSTEM
	local lp       = getLocalPlayer()
	local snapshot = Players:GetPlayers()

	for i = 1, #snapshot do
		if not self._running or self._destroyed or not self._playerConnsStarted then break end
		local p = snapshot[i]
		if p ~= lp and isLiveInstance(p) then
			local pd = self._playerTable[p]
			if not pd then
				local initChar = isCustom and self._customPlayerChars[p] or p.Character
				if initChar and not isLiveInstance(initChar) then initChar = nil end
				pd = PlayerData.new(self, p, initChar)
				self._playerTable[p] = pd
				changed = true
			else
				local wasTracked = pd._tracked
				if not isCustom and p.Character then
					pd:_onCharacterAdded(p.Character)
				elseif isCustom then
					local customChar = self._customPlayerChars[p]
					if customChar and isLiveInstance(customChar) then
						pd:_onCharacterAdded(customChar)
					end
				end
				pd:EvaluateFilter()
				if pd._tracked ~= wasTracked then
					changed = true
				end
			end
		end
	end
	return changed
end

function Manager:_startPlayerTracking()
	if self._destroyed or not self._running or self._playerConnsStarted then return end
	self._playerConnsStarted = true

	local pgen = self._playerGeneration

	self._connections:Connect(Players.PlayerAdded, function(p)
		if self._destroyed or not self._running or not self._playerConnsStarted then return end
		if p ~= getLocalPlayer() and not self._playerTable[p] then
			local isCustom = self._settings.CUSTOM_CHARACTER_SYSTEM
			local initChar = isCustom and self._customPlayerChars[p] or p.Character
			if initChar and not isLiveInstance(initChar) then initChar = nil end
			self._playerTable[p] = PlayerData.new(self, p, initChar)
		end
	end, "PlayerAdded")

	self._connections:Connect(Players.PlayerRemoving, function(p)
		self:_setCustomCharMapping(p, nil)
		local pd = self._playerTable[p]
		if pd then
			self._playerTable[p] = nil
			pd:Destroy()
		end
	end, "PlayerRemoving")

	self:_bindLocalTeamSignal()

	local snapshot = Players:GetPlayers()
	local isCustom = self._settings.CUSTOM_CHARACTER_SYSTEM
	local lp       = getLocalPlayer()

	for i = 1, #snapshot do
		if not self._running or self._destroyed or not self._playerConnsStarted then return end
		local p = snapshot[i]
		if p ~= lp and not self._playerTable[p] and isLiveInstance(p) then
			local initChar = isCustom and self._customPlayerChars[p] or p.Character
			if initChar and not isLiveInstance(initChar) then initChar = nil end
			self._playerTable[p] = PlayerData.new(self, p, initChar)
		end
	end

	if isCustom then
		self:_applyStoredCustomCharacters()
	end

	task_spawn(function()
		local stableCount = 0
		for _attempt = 1, 5 do
			task_wait(2)
			if self._destroyed or not self._running or not self._playerConnsStarted
				or self._playerGeneration ~= pgen then
				return
			end
			if self:_rescanPlayers() then
				stableCount = 0
			else
				stableCount = stableCount + 1
				if stableCount >= 2 then
					return
				end
			end
		end
	end)
end

function Manager:_startNPCTracking()
	if self._destroyed or not self._running or self._npcConnsStarted then return end
	self._npcConnsStarted = true
	self._npcConnections  = ConnectionManager.new()

	local dirs        = self._settings.NPC_DIRECTORIES
	local hasUserDirs = type(dirs) == "table" and #dirs > 0

	if not hasUserDirs then
		self._usingFallbackWorkspace = true
		self:_activateDirectory(Workspace, true)
		return
	end

	self._usingFallbackWorkspace = false
	for i = 1, #dirs do
		if not self._running or self._destroyed or not self._npcConnsStarted then return end
		self:_bindDirectoryEntry(dirs[i])
	end
end

function Manager:_stopPlayerTracking()
	if not self._playerConnsStarted then return end
	self._playerConnsStarted = false
	self._playerGeneration   = self._playerGeneration + 1

	if self._connections then
		self._connections:Disconnect("PlayerAdded")
		self._connections:Disconnect("PlayerRemoving")
		self._connections:Disconnect("LocalTeamChanged")
	end

	local toDestroy = {}
	for _, pd in pairs(self._playerTable) do
		toDestroy[#toDestroy + 1] = pd
	end
	table_clear(self._playerTable)

	for i = 1, #toDestroy do
		toDestroy[i]:Destroy()
	end
end

function Manager:_stopNPCTracking()
	if not self._npcConnsStarted then return end
	self._npcConnsStarted        = false
	self._usingFallbackWorkspace = false
	self._generation             = self._generation + 1

	if self._npcConnections then
		self._npcConnections:Destroy()
		self._npcConnections = nil
	end

	self:_clearAllPendingNPCWatches()

	local npcDataList = {}
	for _, data in pairs(self._npcSet) do
		if data then npcDataList[#npcDataList + 1] = data end
	end
	table_clear(self._npcSet)
	table_clear(self._dirUidMap)
	table_clear(self._dirRefCount)
	table_clear(self._stringDirMap)
	table_clear(self._stringWatchTokens)
	table_clear(self._npcDirOwners)

	for i = 1, #npcDataList do
		npcDataList[i]:Destroy()
	end
end

function Manager:Start()
	if self._destroyed or self._running then return end
	self._running     = true
	self._connections = ConnectionManager.new()

	if self._settings.PLAYER_ENABLED then
		self:_startPlayerTracking()
	end

	if self._settings.NPC_ENABLED and self._running and not self._destroyed then
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
	if self._destroyed then return end
	if type(state) == "boolean" then
		if state then self:Start() else self:Stop() end
	else
		if self._running then self:Stop() else self:Start() end
	end
end

function Manager:Restart()
	if self._destroyed then return end
	local wasRunning = self._running
	self:Stop()
	if wasRunning then self:Start() end
end

function Manager:AddDirectory(dir)
	if self._destroyed then return end
	if type(dir) == "string" then
		dir = normalizeDirectoryPath(dir)
		if dir == "" then return end
	elseif not isLiveInstance(dir) then
		return
	end

	local dirs = self._settings.NPC_DIRECTORIES
	if type(dirs) ~= "table" then
		dirs = {}
		self._settings.NPC_DIRECTORIES = dirs
	end

	for i = 1, #dirs do
		if dirs[i] == dir then return end
	end

	table_insert(dirs, dir)

	if self._running and self._settings.NPC_ENABLED and self._npcConnsStarted then
		if self._usingFallbackWorkspace then
			self._usingFallbackWorkspace = false
			self:_deactivateDirectoryInstance(Workspace)
		end
		self:_bindDirectoryEntry(dir)
	end
end

function Manager:RemoveDirectory(dir)
	if self._destroyed then return end
	if type(dir) == "string" then
		dir = normalizeDirectoryPath(dir)
		if dir == "" then return end
	end

	local dirs = self._settings.NPC_DIRECTORIES
	if type(dirs) ~= "table" then return end

	for i = 1, #dirs do
		if dirs[i] == dir then
			table_remove(dirs, i)

			if type(dir) == "string" then
				self._stringWatchTokens[dir] = nil
			end

			if self._running and self._settings.NPC_ENABLED and self._npcConnsStarted then
				local instance
				if isLiveInstance(dir) then
					instance = dir
				elseif type(dir) == "string" then
					instance = self._stringDirMap[dir]
					self._stringDirMap[dir] = nil
				end

				if instance then
					self:_deactivateDirectoryInstance(instance)
				end

				if #dirs == 0 and not self._usingFallbackWorkspace then
					self._usingFallbackWorkspace = true
					self:_activateDirectory(Workspace, true)
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
	if self._destroyed then return end

	if key == "NPC_DIRECTORIES" then
		local cleanDirs = sanitizeDirectoryList(value)
		if areListsEqual(self._settings[key], cleanDirs) then return end
		self._settings[key] = cleanDirs
	elseif FILTER_TABLE_KEYS[key] then
		local nextList = type(value) == "table" and table_clone(value) or nil
		if areListsEqual(self._settings[key], nextList) then return end
		self._settings[key] = nextList
	else
		if self._settings[key] == value then return end
		self._settings[key] = value
	end

	if key == "TARGET_LIMB" then
		self._limbPath = parseLimbPath(value)
		if self._running then
			self:_refreshAllLimbObservers()
		end
		return
	end

	if key == "FORCEFIELD_CHECK" or key == "STOP_TRACKING_ON_DEATH" or key == "DEATH_DETECT_METHOD" then
		if self._running then
			self:_refreshAllLimbObservers()
		end
		return
	end

	if key == "REQUIRE_ANCHOR" then
		if self._running then
			self:_refreshAllRequireAnchor()
		end
		return
	end

	if key == "CUSTOM_CHARACTER_SYSTEM" then
		if self._running and self._playerConnsStarted then
			for p, pd in pairs(self._playerTable) do
				if not self._running or self._destroyed then break end
				pd:_updateCharacterModeSignals()
				if not value then
					if p.Character then
						pd:_onCharacterAdded(p.Character)
					elseif pd._character then
						pd:_onCharacterRemoving(pd._character)
					end
				else
					local customChar = self._customPlayerChars[p]
					if customChar and isLiveInstance(customChar) then
						pd:_onCharacterAdded(customChar)
					elseif pd._character then
						pd:_onCharacterRemoving(pd._character)
					end
				end
			end
			if value then
				self:_rescanCustomPlayers()
			end
		end
		return
	end

	if key == "GET_PLAYER_FROM_CHARACTER" then
		if self._running and self._npcConnsStarted then
			self:_rescanNPCFilter()
		end
		if self._running and self._settings.CUSTOM_CHARACTER_SYSTEM and self._settings.PLAYER_ENABLED then
			self:_rescanCustomPlayers()
		end
		return
	end

	if key == "PLAYER_WHITELIST" or key == "PLAYER_BLACKLIST"
		or key == "TEAM_WHITELIST" or key == "TEAM_BLACKLIST" then
		self:_recompileFilters()
	end

	if key == "TEAM_MODE" and self._running then
		for _, pd in pairs(self._playerTable) do
			if not self._running or self._destroyed then break end
			pd:_updateTeamSignal()
		end
	end

	if key == "TEAM_MODE" or key == "TEAM_WHITELIST" or key == "TEAM_BLACKLIST"
		or key == "TEAM_CUSTOM_CHECK" or key == "NAME_PATTERN"
		or key == "DISPLAY_NAME_PATTERN" or key == "PLAYER_FILTER"
		or key == "PLAYER_WHITELIST" or key == "PLAYER_BLACKLIST" then
		if self._running then
			for _, pd in pairs(self._playerTable) do
				if not self._running or self._destroyed then break end
				pd:EvaluateFilter()
			end
		end
		return
	end

	if key == "NPC_FILTER" then
		self:_rescanNPCFilter()
		return
	end

	if key == "PLAYER_ENABLED" and self._running then
		if value then
			self:_startPlayerTracking()
			if self._settings.CUSTOM_CHARACTER_SYSTEM then
				self:_rescanCustomPlayers()
			end
		else
			self:_stopPlayerTracking()
		end
		return
	end

	if key == "NPC_ENABLED" and self._running then
		if value then
			self:_startNPCTracking()
		else
			self:_stopNPCTracking()
		end
		return
	end

	if key == "NPC_DIRECTORIES" and self._running and self._settings.NPC_ENABLED then
		self:_stopNPCTracking()
		self:_startNPCTracking()
	end
end

function Manager:Get(key)
	local val = self._settings[key]
	if FILTER_TABLE_KEYS[key] and type(val) == "table" then
		return table_clone(val)
	end
	return val
end

function Manager:RegisterPlayerCharacter(player, model)
	if self._destroyed then return end
	if not player or not model or typeof(model) ~= "Instance" or not model:IsA("Model") then return end

	if player == getLocalPlayer() then
		self:SetLocalCharacter(model)
		return
	end

	self:_unregisterNPC(model)
	self:_setCustomCharMapping(player, model)

	if not isLiveInstance(self._sampleChar) then
		self._sampleChar = model
		self:_emitReferenceCharIfChanged()
	end

	if not self._running or not self._settings.PLAYER_ENABLED then
		return
	end

	local pd = self._playerTable[player]
	if not pd then
		self._playerTable[player] = PlayerData.new(self, player, model)
	else
		pd:_onCharacterAdded(model)
	end
end

function Manager:UnregisterPlayerCharacter(player, model)
	if self._destroyed or not player then return end
	if model == nil or self._customPlayerChars[player] == model then
		self:_setCustomCharMapping(player, nil)
	end
	local pd = self._playerTable[player]
	if pd then
		pd:_onCharacterRemoving(model)
	end
end

function Manager:Destroy()
	if self._destroyed then return end
	self:Stop()
	self._destroyed = true

	self._localConns:Destroy()
	table_clear(self._customPlayerChars)
	table_clear(self._customCharToPlayer)
	self._customLocalChar    = nil
	self._sampleChar         = nil
	self._lastEmittedRefChar = nil

	if self._refCharBindable then
		self._refCharBindable:Destroy()
		self._refCharBindable          = nil
		self.ReferenceCharacterChanged = nil
	end
end

setmetatable(Manager, {
	__call = function(_, userSettings)
		return Manager.new(userSettings)
	end,
})

return {
	Manager                = Manager,
	ConnectionManager      = ConnectionManager,
	resolvePathAsync       = resolvePathAsync,
	normalizeDirectoryPath = normalizeDirectoryPath,
	isLiveInstance         = isLiveInstance,
}
