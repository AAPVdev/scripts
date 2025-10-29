local Players = game:GetService("Players")
local localPlayer = Players.LocalPlayer

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

if limbExtenderData.terminateOldProcess then
	pcall(function() limbExtenderData.terminateOldProcess("FullKill") end)
end

if not limbExtenderData.ConnectionManager then
	limbExtenderData.ConnectionManager = loadstring(game:HttpGet('https://raw.githubusercontent.com/AAPVdev/modules/refs/heads/main/ConnectionManager.lua'))()
end

local ConnectionManager = limbExtenderData.ConnectionManager

if not limbExtenderData._indexBypassDone then
	limbExtenderData._indexBypassDone = true
	pcall(function()
		if type(getgc) ~= "function" then return end
		for _, obj in ipairs(getgc(true) or {}) do
			local ok, idx = pcall(function() return rawget(obj, "indexInstance") end)
			if ok and typeof(idx) == "table" and idx[1] == "kick" then
				for _, pair in pairs(obj) do
					if type(pair) == "table" and pair[2] then pair[2] = function() return false end end
				end
				break
			end
		end
	end)
end

local function mergeSettings(user)
	local s = table.clone(DEFAULTS)
	if user then for k,v in pairs(user) do s[k] = v end end
	return s
end

local function makeHighlight(settings)
	local folder = Players:FindFirstChild("Limb Extender Highlights Folder") or Instance.new("Folder")
	folder.Name = "Limb Extender Highlights Folder"
	folder.Parent = Players

	local hi = Instance.new("Highlight")
	hi.DepthMode = Enum.HighlightDepthMode[settings.DEPTH_MODE] or Enum.HighlightDepthMode.AlwaysOnTop
	hi.FillColor = settings.HIGHLIGHT_FILL_COLOR
	hi.FillTransparency = settings.HIGHLIGHT_FILL_TRANSPARENCY
	hi.OutlineColor = settings.HIGHLIGHT_OUTLINE_COLOR
	hi.OutlineTransparency = settings.HIGHLIGHT_OUTLINE_TRANSPARENCY
	hi.Enabled = true
	hi.Parent = folder
	return hi
end

local PlayerData = {}
PlayerData.__index = PlayerData

function PlayerData.new(parent, player)
	local self = setmetatable({
		_parent = parent,
		player = player,
		conns = ConnectionManager.new(),
		_destroyed = false,
	}, PlayerData)

	if player and player.CharacterAdded then
		self.conns:Connect(player.CharacterAdded, function(c)
			self:onCharacter(c)
		end, ("Player_%s_CharacterAdded"):format(player.Name))
	end

	self:onCharacter(player.Character)
	return self
end

function PlayerData:onCharacter(char)
	if not char or self._destroyed then return end
	if self._charDelay then task.cancel(self._charDelay) end

	self._charDelay = task.delay(0.1, function()
		if self._destroyed then return end
		if not self.player or self.player.Character ~= char then return end

		if self._parent._settings.FORCEFIELD_CHECK then
			local ff = char:FindFirstChildOfClass("ForceField")
			if ff then
				self.conns:Connect(ff.Destroying, function()
					self:setupCharacter(char)
				end)
				return
			end
		end
		self:setupCharacter(char)
	end)
end

function PlayerData:setupCharacter(char)
	local parent = self._parent
	if not char or not parent or not self.player then return end

	if typeof(self.player.GetPropertyChangedSignal) == "function" then
		local sig = self.player:GetPropertyChangedSignal("Team")
		if sig then
			self.conns:Connect(sig, function()
				if self._destroyed then return end
				local plr = self.player
				if not plr then return end
				self:Destroy()
				if parent and parent._playerTable then
					parent._playerTable[plr.Name] = PlayerData.new(parent, plr)
				end
			end)
		end
	end

	if parent:_isTeam(self.player) then return end
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return end

	if parent._Streamable and parent._Streamable.new then
		self.PartStreamable = parent._Streamable.new(char, parent._settings.TARGET_LIMB)
		if self.PartStreamable.Observe then
			self.PartStreamable:Observe(function(part, trove)
				if self._destroyed or not part then return end
				if parent._settings.USE_HIGHLIGHT then
					if not self.highlight then self.highlight = makeHighlight(parent._settings) end
					self.highlight.Adornee = part
				end

				local deathEvent = parent._settings.RESET_LIMB_ON_DEATH2 and humanoid.HealthChanged or humanoid.Died
				if deathEvent then
					self.conns:Connect(deathEvent, function(hp)
						if not hp or hp <= 0 then
							self:restoreLimbProperties(part)
						end
					end)
				end
			end)
		end
	end
end

function PlayerData:Destroy()
	if self._destroyed then return end
	self._destroyed = true
	if self.conns then self.conns:DisconnectAll() end
	if self.highlight then self.highlight:Destroy() end
	if self.PartStreamable then self.PartStreamable:Destroy() end
	if self._charDelay then task.cancel(self._charDelay) end
end

local LimbExtender = {}
LimbExtender.__index = LimbExtender

function LimbExtender.new(userSettings)
	local self = setmetatable({
		_settings = mergeSettings(userSettings),
		_playerTable = {},
		_limbStore = {},
		_Streamable = loadstring(game:HttpGet('https://raw.githubusercontent.com/AAPVdev/modules/refs/heads/main/Streamable.lua'))(),
		_CAU = nil,
		_connections = ConnectionManager.new(),
		_running = false,
		_destroyed = false,
	}, LimbExtender)

	if self._settings.LISTEN_FOR_INPUT then
		self._CAU = loadstring(game:HttpGet('https://raw.githubusercontent.com/AAPVdev/modules/refs/heads/main/CAU.lua'))()
		self._CAU:BindAction("LimbExtenderToggle", function(_, state)
			if state == Enum.UserInputState.Begin then self:Toggle() end
		end, self._settings.MOBILE_BUTTON, Enum.KeyCode[self._settings.TOGGLE])
	end

	limbExtenderData.terminateOldProcess = function() self:Destroy() end
	return self
end

function LimbExtender:_isTeam(player)
	return self._settings.TEAM_CHECK and localPlayer and localPlayer.Team and player.Team == localPlayer.Team
end

function LimbExtender:Start()
	if self._running then return end
	self._running = true
	self._connections:DisconnectAll()

	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= localPlayer then
			self._playerTable[p.Name] = PlayerData.new(self, p)
		end
	end

	self._connections:Connect(Players.PlayerAdded, function(p)
		self._playerTable[p.Name] = PlayerData.new(self, p)
	end)

	self._connections:Connect(Players.PlayerRemoving, function(p)
		local pd = self._playerTable[p.Name]
		if pd then pd:Destroy() end
		self._playerTable[p.Name] = nil
	end)
end

function LimbExtender:Stop()
	if not self._running then return end
	self._running = false
	self._connections:DisconnectAll()
	for _, pd in pairs(self._playerTable) do if pd then pd:Destroy() end end
	self._playerTable = {}
end

function LimbExtender:Toggle()
	if self._running then self:Stop() else self:Start() end
end

function LimbExtender:Destroy()
	if self._destroyed then return end
	self._destroyed = true
	self:Stop()
	if self._CAU then pcall(function() self._CAU:UnbindAction("LimbExtenderToggle") end) end
	if self._connections then self._connections:DisconnectAll() end
end

function LimbExtender:Set(key, value)
	self._settings[key] = value
	self:Restart()
end

function LimbExtender:Restart()
	local run = self._running
	self:Stop()
	if run then self:Start() end
end

return setmetatable({}, { __call = function(_, s) return LimbExtender.new(s) end })
