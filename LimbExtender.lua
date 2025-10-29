local Players = game:GetService("Players")
local localPlayer = Players.LocalPlayer
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DEFAULTS = {
	TOGGLE = "L",
	TARGET_LIMB = "HumanoidRootPart",
	LIMB_SIZE = 15,
	LIMB_TRANSPARENCY = 0.9,
	LIMB_CAN_COLLIDE = false,
	MOBILE_BUTTON = true,
	LISTEN_FOR_INPUT = true,
	TEAM_CHECK = true,
	FORCEFIELD_CHECK = true,
	RESET_LIMB_ON_DEATH2 = false,
	USE_HIGHLIGHT = true,
	DEPTH_MODE = "AlwaysOnTop",
	HIGHLIGHT_FILL_COLOR = Color3.fromRGB(0,140,140),
	HIGHLIGHT_FILL_TRANSPARENCY = 0.7,
	HIGHLIGHT_OUTLINE_COLOR = Color3.fromRGB(255,255,255),
	HIGHLIGHT_OUTLINE_TRANSPARENCY = 1,
}

local limbExtenderData = getgenv().limbExtenderData or {}
getgenv().limbExtenderData = limbExtenderData

if limbExtenderData.terminateOldProcess and type(limbExtenderData.terminateOldProcess) == "function" then
	if limbExtenderData.terminateOldProcess then
		limbExtenderData.terminateOldProcess("FullKill")
	end
	limbExtenderData.terminateOldProcess = nil
end

if not limbExtenderData.ConnectionManager then
	limbExtenderData.ConnectionManager = loadstring(game:HttpGet('https://raw.githubusercontent.com/AAPVdev/modules/refs/heads/main/ConnectionManager.lua'))()
	assert(type(limbExtenderData.ConnectionManager.new) == "function", "Invalid ConnectionManager module")
end

local ConnectionManager = limbExtenderData.ConnectionManager

if not limbExtenderData._indexBypassDone then
	limbExtenderData._indexBypassDone = true
	pcall(function()
		if type(getgc) ~= "function" then return end
		for _, obj in ipairs(getgc(true) or {}) do
			local ok, idx = pcall(function()
				return rawget(obj, "indexInstance")
			end)
			if ok and typeof(idx) == "table" and idx[1] == "kick" then
				for _, pair in pairs(obj) do
					if type(pair) == "table" and pair[2] then
						pair[2] = function() return false end
					end
				end
				break
			end
		end
	end)
end

local function mergeSettings(user)
	local s = {}
	for k,v in pairs(DEFAULTS) do s[k] = v end
	if user then
		for k,v in pairs(user) do s[k] = v end
	end
	return s
end

local function watchProperty(instance, prop, callback)
	if not instance or type(prop) ~= "string" or type(callback) ~= "function" then return nil end
	local signal = instance:GetPropertyChangedSignal(prop)
	if signal and type(signal.Connect) == "function" then
		return signal:Connect(function() callback(instance) end)
	end
	return nil
end

local function makeHighlight(settings)
	local hiFolder = Players:FindFirstChild("Limb Extender Highlights Folder")
	if not hiFolder then
		hiFolder = Instance.new("Folder")
		hiFolder.Name = "Limb Extender Highlights Folder"
		hiFolder.Parent = Players
	end
	local hi = Instance.new("Highlight")
	hi.Name = "LimbHighlight"

	if settings and settings.DEPTH_MODE and Enum.HighlightDepthMode[settings.DEPTH_MODE] then
		hi.DepthMode = Enum.HighlightDepthMode[settings.DEPTH_MODE]
	end
	if settings and settings.HIGHLIGHT_FILL_COLOR then hi.FillColor = settings.HIGHLIGHT_FILL_COLOR end
	if settings and settings.HIGHLIGHT_FILL_TRANSPARENCY then hi.FillTransparency = settings.HIGHLIGHT_FILL_TRANSPARENCY end
	if settings and settings.HIGHLIGHT_OUTLINE_COLOR then hi.OutlineColor = settings.HIGHLIGHT_OUTLINE_COLOR end
	if settings and settings.HIGHLIGHT_OUTLINE_TRANSPARENCY then hi.OutlineTransparency = settings.HIGHLIGHT_OUTLINE_TRANSPARENCY end
	hi.Enabled = true
	hi.Parent = hiFolder
	return hi
end

local PlayerData = {}
PlayerData.__index = PlayerData

function PlayerData.new(parent, player)
	local self = setmetatable({
		_parent = parent,
		player = player,
		conns = ConnectionManager.new(),
		highlight = nil,
		PartStreamable = nil,
		_charDelay = nil,
		_destroyed = false,
	}, PlayerData)

	if player and player.CharacterAdded and type(player.CharacterAdded.Connect) == "function" then
		self.conns:Connect(player.CharacterAdded, function(c) self:onCharacter(c) end, ("Player_%s_CharacterAdded"):format(player.Name))
	end
	local character = player and (player.Character or workspace:FindFirstChild(player.Name))
	self:onCharacter(character)
	return self
end

function PlayerData:saveLimbProperties(limb)
	local parent = self._parent
	if not limb then return end
	parent._limbStore[limb] = {
		OriginalSize = limb.Size,
		OriginalTransparency = limb.Transparency,
		OriginalCanCollide = limb.CanCollide,
		OriginalMassless = limb.Massless,
		SizeConnection = nil,
		CollisionConnection = nil,
	}
end

function PlayerData:restoreLimbProperties(limb)
	local parent = self._parent
	if not limb then return end
	local p = parent._limbStore[limb]
	if not p then return end
	if p.SizeConnection and typeof(p.SizeConnection) == "RBXScriptConnection" then p.SizeConnection:Disconnect() end
	if p.CollisionConnection and typeof(p.CollisionConnection) == "RBXScriptConnection" then p.CollisionConnection:Disconnect() end
	if limb and limb.Parent then
		limb.Size = p.OriginalSize
		limb.Transparency = p.OriginalTransparency
		limb.CanCollide = p.OriginalCanCollide
		limb.Massless = p.OriginalMassless
	end
	parent._limbStore[limb] = nil

	if limbExtenderData.limbs then limbExtenderData.limbs[limb] = nil end
end

function PlayerData:modifyLimbProperties(limb)
	local parent = self._parent
	if not limb then return end
	if parent._limbStore[limb] then return end
	self:saveLimbProperties(limb)

	local entry = parent._limbStore[limb]
	local sizeVal = parent._settings.LIMB_SIZE or DEFAULTS.LIMB_SIZE
	local newSize = Vector3.new(sizeVal, sizeVal, sizeVal)
	local canCollide = parent._settings.LIMB_CAN_COLLIDE

	entry.SizeConnection = watchProperty(limb, "Size", function(l)
		if l and l.Parent then l.Size = newSize end
	end)
	entry.CollisionConnection = watchProperty(limb, "CanCollide", function(l)
		if l and l.Parent then l.CanCollide = canCollide end
	end)

	if limb and limb.Parent then
		limb.Size = newSize
		limb.Transparency = parent._settings.LIMB_TRANSPARENCY
		limb.CanCollide = canCollide
		if parent._settings.TARGET_LIMB ~= "HumanoidRootPart" then
			limb.Massless = true
		end
	end

	if limbExtenderData.limbs then limbExtenderData.limbs[limb] = parent._limbStore[limb] end
end

local function installSizeSpoof(targetName, savedSize)
	pcall(function()
		if limbExtenderData._mtOverridden then
			limbExtenderData._spoofTarget = targetName
			limbExtenderData._spoofSavedSize = savedSize
			return true
		end

		if type(getrawmetatable) ~= "function" or type(setreadonly) ~= "function" then
			return false
		end

		local mt = getrawmetatable(game)
		if not mt or type(mt.__index) ~= "function" then return false end
		local oldIndex = mt.__index

		setreadonly(mt, false)
		mt.__index = function(self, key)
			local name = (self and self.Name) and self.Name or tostring(self)
			if key == "Size" and limbExtenderData._spoofTarget and name == limbExtenderData._spoofTarget then
				return limbExtenderData._spoofSavedSize
			end
			return oldIndex(self, key)
		end
		setreadonly(mt, true)

		limbExtenderData._mtOverridden = true
		limbExtenderData._originalIndex = oldIndex
		limbExtenderData._spoofTarget = targetName
		limbExtenderData._spoofSavedSize = savedSize
		return true
	end)
end

local function restoreOriginalMetatable()
	pcall(function()
		if not limbExtenderData._mtOverridden then return end
		if type(getrawmetatable) ~= "function" or type(setreadonly) ~= "function" then
			limbExtenderData._mtOverridden = nil
			limbExtenderData._originalIndex = nil
			limbExtenderData._spoofTarget = nil
			limbExtenderData._spoofSavedSize = nil
			return
		end
		local mt = getrawmetatable(game)
		if mt and limbExtenderData._originalIndex then
			setreadonly(mt, false)
			mt.__index = limbExtenderData._originalIndex
			setreadonly(mt, true)
		end
		limbExtenderData._mtOverridden = nil
		limbExtenderData._originalIndex = nil
		limbExtenderData._spoofTarget = nil
		limbExtenderData._spoofSavedSize = nil
	end)
end

function PlayerData:spoofSize(part)
	local parent = self._parent
	if not part then return end
	if limbExtenderData._spoofTarget == parent._settings.TARGET_LIMB then return end
	local saved = part.Size
	limbExtenderData._spoofTarget = parent._settings.TARGET_LIMB
	limbExtenderData._spoofSavedSize = saved
	installSizeSpoof(limbExtenderData._spoofTarget, saved)
end

function PlayerData:setupCharacter(char)
	local parent = self._parent
	if not char then return end

	if self.player and self.player.GetPropertyChangedSignal then
		local sig = self.player:GetPropertyChangedSignal("Team")
		if sig and type(sig.Connect) == "function" then
			self.conns:Connect(sig, function()
				if self._destroyed then return end
				self:Destroy()
				parent._playerTable[self.player.Name] = PlayerData.new(parent, self.player)
			end, ("Player_%s_TeamChanged"):format(self.player.Name))
		end
	end

	if parent:_isTeam(self.player) then return end

	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return end

	if self.PartStreamable and type(self.PartStreamable.Destroy) == "function" then
		self.PartStreamable:Destroy()
		self.PartStreamable = nil
	end

	if parent._Streamable and type(parent._Streamable.new) == "function" then
		self.PartStreamable = parent._Streamable.new(char, parent._settings.TARGET_LIMB)
		if self.PartStreamable and type(self.PartStreamable.Observe) == "function" then
			self.PartStreamable:Observe(function(part, trove)
				if self._destroyed then return end

				self:spoofSize(part)
				self:modifyLimbProperties(part)

				if parent._settings.USE_HIGHLIGHT then
					if not self.highlight then
						self.highlight = makeHighlight(parent._settings)
					end
					self.highlight.Adornee = part
				end

				if self.player and self.player.CharacterRemoving and type(self.player.CharacterRemoving.Connect) == "function" then
					self.conns:Connect(self.player.CharacterRemoving, function()
						self:restoreLimbProperties(part)
					end, ("Player_%s_CharacterRemoving_%s"):format(self.player.Name, tostring(part)))
				end

				local deathEvent = parent._settings.RESET_LIMB_ON_DEATH2 and humanoid.HealthChanged or humanoid.Died
				if deathEvent and type(deathEvent.Connect) == "function" then
					self.conns:Connect(deathEvent, function(hp)
						if not hp or hp <= 0 then self:restoreLimbProperties(part) end
					end, ("Player_%s_Death_%s"):format(self.player.Name, tostring(part)))
				end

				if trove and trove.Add and type(trove.Add) == "function" then
					self.conns:Add(function() self:restoreLimbProperties(part) end, ("Player_%s_TroveRestore_%s"):format(self.player.Name, tostring(part)))
				end
			end)
		end
	end
end

function PlayerData:onCharacter(char)
	if not char then return end
	if self._charDelay then task.cancel(self._charDelay); self._charDelay = nil end

	self._charDelay = task.delay(0.1, function()
		if self._destroyed then return end
		if not self.player.Character or self.player.Character ~= char then return end

		if self._parent._settings.FORCEFIELD_CHECK then
			local ff = char:FindFirstChildOfClass("ForceField")
			if ff then
				self.conns:Connect(ff.Destroying, function()
					self:setupCharacter(char)
				end, ("Player_%s_ForceField_%s"):format(self.player.Name, tostring(char)))
				return
			end
		end
		self:setupCharacter(char)
	end)
end

function PlayerData:Destroy()
	if self._destroyed then return end
	self._destroyed = true

	if self.conns then
		self.conns:DisconnectAll()
		if type(self.conns.Destroy) == "function" then self.conns:Destroy() end
		self.conns = nil
	end

	if self.highlight and type(self.highlight.Destroy) == "function" then self.highlight:Destroy(); self.highlight = nil end
	if self.PartStreamable and type(self.PartStreamable.Destroy) == "function" then self.PartStreamable:Destroy(); self.PartStreamable = nil end
	if self._charDelay and type(task.cancel) == "function" then task.cancel(self._charDelay); self._charDelay = nil end

	setmetatable(self, nil)
	for k in pairs(self) do self[k] = nil end
end

local LimbExtender = {}
LimbExtender.__index = LimbExtender

function LimbExtender.new(userSettings)
	local self = setmetatable({
		_settings = mergeSettings(userSettings),
		_playerTable = limbExtenderData.playerTable or {},
		_limbStore = limbExtenderData.limbs or {},
		_Streamable = limbExtenderData.Streamable,
		_CAU = limbExtenderData.CAU,
		_connections = ConnectionManager.new(),
		_running = limbExtenderData.running or false,
		_destroyed = false,
	}, LimbExtender)

	limbExtenderData.playerTable = self._playerTable
	limbExtenderData.limbs = self._limbStore
	limbExtenderData.Streamable = self._Streamable
	limbExtenderData.CAU = self._CAU
	limbExtenderData.running = self._running

	limbExtenderData.terminateOldProcess = function(reason)

		if type(self.Destroy) == "function" then self:Destroy() end
	end

	if self._settings.LISTEN_FOR_INPUT then
		self._CAU = loadstring(game:HttpGet('https://raw.githubusercontent.com/AAPVdev/modules/refs/heads/main/CAU.lua'))()
		limbExtenderData.CAU = self._CAU
	end

	self._Streamable = loadstring(game:HttpGet('https://raw.githubusercontent.com/AAPVdev/modules/refs/heads/main/Streamable.lua'))()
	limbExtenderData.Streamable = self._Streamable

	if self._settings.LISTEN_FOR_INPUT and self._CAU and type(self._CAU.BindAction) == "function" then
		self._CAU:BindAction(
			"LimbExtenderToggle",
			function(_, inputState)
				if inputState == Enum.UserInputState.Begin then
					self:Toggle()
				end
			end,
			self._settings.MOBILE_BUTTON,
			Enum.KeyCode[self._settings.TOGGLE]
		)
	end
	return self
end

function LimbExtender:_isTeam(player)
	return self._settings.TEAM_CHECK and localPlayer and localPlayer.Team ~= nil and player.Team == localPlayer.Team
end

function LimbExtender:Terminate(reason)

	for k,v in pairs(limbExtenderData) do
		if typeof(v) == "RBXScriptConnection" and v.Connected then v:Disconnect() end
	end

	for i, pd in pairs(limbExtenderData.playerTable or {}) do
		if pd and type(pd.Destroy) == "function" then pd:Destroy() end
		limbExtenderData.playerTable[i] = nil
	end
	self._playerTable = {}
	limbExtenderData.playerTable = {}

	for limb, props in pairs(limbExtenderData.limbs or {}) do
		if props.SizeConnection and typeof(props.SizeConnection) == "RBXScriptConnection" then props.SizeConnection:Disconnect() end
		if props.CollisionConnection and typeof(props.CollisionConnection) == "RBXScriptConnection" then props.CollisionConnection:Disconnect() end
		if props.OriginalSize and limb and limb.Parent then limb.Size = props.OriginalSize end
		if props.OriginalTransparency and limb and limb.Parent then limb.Transparency = props.OriginalTransparency end
		if props.OriginalCanCollide ~= nil and limb and limb.Parent then limb.CanCollide = props.OriginalCanCollide end
		if props.OriginalMassless ~= nil and limb and limb.Parent then limb.Massless = props.OriginalMassless end
		if self._limbStore then self._limbStore[limb] = nil end
		limbExtenderData.limbs[limb] = nil
	end

	restoreOriginalMetatable()

	if self._CAU and type(self._CAU.UnbindAction) == "function" then
		self._CAU:UnbindAction("LimbExtenderToggle")
	end

	if self._connections then
		self._connections:DisconnectAll()
		if type(self._connections.Destroy) == "function" then self._connections:Destroy() end
		self._connections = nil
	end
end

function LimbExtender:Start()
	self._connections = self._connections or ConnectionManager.new()
	
	if self._running then return end
	self._connections:DisconnectAll()
	self._running = true
	limbExtenderData.running = true

	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= localPlayer then
			if not self._playerTable[p.Name] then
				self._playerTable[p.Name] = PlayerData.new(self, p)
			end
		end
	end

	if localPlayer and localPlayer.GetPropertyChangedSignal then
		local sig = localPlayer:GetPropertyChangedSignal("Team")
		if sig and type(sig.Connect) == "function" then
			self._connections:Connect(sig, function() self:Restart() end, "LimbExtender_TeamChanged")
		end
	end

	self._connections:Connect(Players.PlayerAdded, function(p)
		if not self._playerTable[p.Name] then
			self._playerTable[p.Name] = PlayerData.new(self, p)
		end
	end, "LimbExtender_PlayerAdded")

	self._connections:Connect(Players.PlayerRemoving, function(p)
		local pd = self._playerTable[p.Name]
		if pd and type(pd.Destroy) == "function" then pd:Destroy() end
		self._playerTable[p.Name] = nil
	end, "LimbExtender_PlayerRemoving")

	if self._settings.MOBILE_BUTTON and self._settings.LISTEN_FOR_INPUT and self._CAU and type(self._CAU.SetTitle) == "function" then
		self._CAU:SetTitle("LimbExtenderToggle", "Off")
	end
end

function LimbExtender:Stop()
	if not self._running then return end
	self._running = false
	limbExtenderData.running = false

	if self._connections then
		self._connections:DisconnectAll()
		if type(self._connections.Destroy) == "function" then self._connections:Destroy() end
		self._connections = ConnectionManager.new()
	end

	for i, pd in pairs(self._playerTable) do
		if pd and type(pd.Destroy) == "function" then pd:Destroy() end
		self._playerTable[i] = nil
	end
	self._playerTable = {}
end

function LimbExtender:Toggle(state)
	local newState
	if type(state) == "boolean" then
		newState = not state
	else
		newState = self._running
	end

	self._running = newState
	limbExtenderData.running = self._running
	
	if self._running then self:Stop() else self:Start() end
end

function LimbExtender:Restart()
	local wasRunning = self._running
	self:Stop()
	if wasRunning then self:Start() end
end

function LimbExtender:Destroy()
	if self._destroyed then return end
	self._destroyed = true

	self:Stop()
	self:Terminate("FullKill")
	limbExtenderData.running = false
	limbExtenderData.terminateOldProcess = nil

	limbExtenderData.playerTable = nil
	limbExtenderData.limbs = nil
	limbExtenderData.Streamable = nil
	limbExtenderData.CAU = nil
end

function LimbExtender:Set(key, value)
	if self._settings[key] ~= value then
		self._settings[key] = value
		self:Restart()
	end
end

function LimbExtender:Get(key) return self._settings[key] end

return setmetatable({}, {
	__call = function(_, userSettings) return LimbExtender.new(userSettings) end,
	__index = LimbExtender,
})
