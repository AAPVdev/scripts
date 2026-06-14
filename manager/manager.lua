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
	PLAYER_ENABLED  = true,
	NPC_ENABLED     = false,
	NPC_FILTER      = nil,
	NPC_DIRECTORIES = {},

	ON_CHARACTER_ADDED    = nil,
	ON_CHARACTER_REMOVING = nil,
	ON_NPC_ADDED          = nil,
	ON_NPC_REMOVING       = nil,
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

local PlayerData = {}
PlayerData.__index = PlayerData

function PlayerData.new(parent, player)
	local self = setmetatable({
		_parent    = parent,
		player     = player,
		conns      = ConnectionManager.new(),
		_destroyed = false,
	}, PlayerData)

	self.conns:Connect(player.CharacterAdded, function(char)
		self:_onCharacterAdded(char)
	end)
	self.conns:Connect(player.CharacterRemoving, function(char)
		self:_onCharacterRemoving(char)
	end)

	if player.Character then
		self:_onCharacterAdded(player.Character)
	end

	return self
end

function PlayerData:_onCharacterAdded(char)
	if self._destroyed then return end
	local cb = self._parent._settings.ON_CHARACTER_ADDED
	if type(cb) == "function" then
		pcall(cb, self.player, char)
	end
end

function PlayerData:_onCharacterRemoving(char)
	if self._destroyed then return end
	local cb = self._parent._settings.ON_CHARACTER_REMOVING
	if type(cb) == "function" then
		pcall(cb, self.player, char)
	end
end

function PlayerData:Destroy()
	self._destroyed = true
	if self.player.Character then
		self:_onCharacterRemoving(self.player.Character)
	end
	self.conns:Destroy()
	setmetatable(self, nil)
end

local Manager = {}
Manager.__index = Manager

function Manager.new(userSettings)
	return setmetatable({
		_settings    = mergeSettings(userSettings),
		_playerTable = {},
		_npcSet      = {},
		_connections = nil,
		_running     = false,
		_destroyed   = false,
		_generation  = 0,
	}, Manager)
end

function Manager:_isValidNPC(model)
	if not model:IsA("Model") then return false end
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

	if self:_isValidNPC(model) then
		self._npcSet[model] = true
		local cb = self._settings.ON_NPC_ADDED
		if type(cb) == "function" then pcall(cb, model) end
	end
end

function Manager:_unregisterNPC(model)
	if self._npcSet[model] then
		self._npcSet[model] = nil
		local cb = self._settings.ON_NPC_REMOVING
		if type(cb) == "function" then pcall(cb, model) end
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
				if self._running and not self._destroyed then
					self:_registerNPC(desc)
				end
			end)
		end)
		self._connections:Connect(dir.DescendantRemoving, function(desc)
			self:_unregisterNPC(desc)
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
			self:_unregisterNPC(desc)
		end)
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
		end)

		self._connections:Connect(Players.PlayerRemoving, function(p)
			local pd = self._playerTable[p]
			if pd then
				pd:Destroy()
				self._playerTable[p] = nil
			end
		end)

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

	local npcRemoving = self._settings.ON_NPC_REMOVING
	if type(npcRemoving) == "function" then
		for model in pairs(self._npcSet) do
			pcall(npcRemoving, model)
		end
	end
	table_clear(self._npcSet)
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

local module = setmetatable({}, {
	__call  = function(_, userSettings) return Manager.new(userSettings) end,
	__index = Manager,
})

module.ConnectionManager        = ConnectionManager
module.resolvePathAsync         = resolvePathAsync
module.normalizeDirectoryPath   = normalizeDirectoryPath
module.isLiveInstance           = isLiveInstance

return module
