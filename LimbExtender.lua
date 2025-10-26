local success, response = pcall(getgenv)
local env = _G

if success then
	env = getgenv()
end

local rawSettings = {
	TOGGLE = "L",
	TARGET_LIMB = "Head",
	LIMB_SIZE = 15,
	LIMB_TRANSPARENCY = 0.9,
	LIMB_CAN_COLLIDE = false,
	MOBILE_BUTTON = true,
	LISTEN_FOR_INPUT = true,
	TEAM_CHECK = false,
	FORCEFIELD_CHECK = true,
	RESET_LIMB_ON_DEATH2 = false,
	USE_HIGHLIGHT = true,
	DEPTH_MODE = "AlwaysOnTop",
	HIGHLIGHT_FILL_COLOR = Color3.fromRGB(0,140,140),
	HIGHLIGHT_FILL_TRANSPARENCY = 0.7,
	HIGHLIGHT_OUTLINE_COLOR = Color3.fromRGB(255,255,255),
	HIGHLIGHT_OUTLINE_TRANSPARENCY = 1,
}

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local localPlayer = Players.LocalPlayer

local limbExtenderData = env.limbExtenderData or {}
env.limbExtenderData = limbExtenderData

local function indexBypass()
	if limbExtenderData.indexBypass then return end
	limbExtenderData.indexBypass = true
	pcall(function()
		for _, obj in ipairs(getgc(true)) do
			local idx = rawget(obj, "indexInstance")
			if typeof(idx) == "table" and idx[1] == "kick" then
				for _, pair in pairs(obj) do
					pair[2] = function() return false end
				end
				break
			end
		end
	end)
end


if limbExtenderData.terminateOldProcess then
	limbExtenderData.terminateOldProcess("FullKill")
	limbExtenderData.terminateOldProcess = nil
else
	indexBypass()
	limbExtenderData.HighlightPool = (RS:WaitForChild("HighlightPool", 0.05) and require(RS.HighlightPool)) or loadstring(game:HttpGet("https://raw.githubusercontent.com/AAPVdev/modules/refs/heads/main/HighlightPool.lua"))()
	limbExtenderData.HighlightPool = limbExtenderData.HighlightPool.new()
end

limbExtenderData.running = limbExtenderData.running or false
limbExtenderData.CAU = limbExtenderData.CAU or (RS:WaitForChild("CAU", 0.05) and require(RS.CAU)) or loadstring(game:HttpGet("https://raw.githubusercontent.com/AAPVdev/modules/refs/heads/main/ContextActionUtility.lua"))()
limbExtenderData.Streamable = limbExtenderData.Streamable or (RS:WaitForChild("Streamable", 0.05) and require(RS.Streamable)) or loadstring(game:HttpGet("https://raw.githubusercontent.com/AAPVdev/modules/refs/heads/main/Streamable.lua"))()

if not limbExtenderData.Trove then
	local ok, mod
	if RS:FindFirstChild("Trove") then
		ok = true
		mod = require(RS.Trove)
	else
		ok = pcall(function()
			mod = loadstring(game:HttpGet("https://raw.githubusercontent.com/Sleitnick/RbxUtil/refs/heads/main/modules/trove/init.luau"))()
		end)
	end
	if ok and mod then
		limbExtenderData.Trove = mod
	else

		limbExtenderData.Trove = {}
		function limbExtenderData.Trove.new()
			local self = { _items = {} }
			self.Add = function(_, item)
				table.insert(self._items, item)
				return item
			end
			self.Add = function(self, item)
				table.insert(self._items, item)
				return item
			end
			self.Destroy = function(self)
				for i = #self._items, 1, -1 do
					local item = self._items[i]
					if type(item) == "function" then
						pcall(item)
					elseif typeof(item) == "RBXScriptConnection" then
						pcall(function() item:Disconnect() end)
					elseif type(item) == "userdata" and item.Destroy then
						pcall(function() item:Destroy() end)
					end
				end
				self._items = {}
			end
			return self
		end
	end
end


limbExtenderData.RootTrove = limbExtenderData.RootTrove or limbExtenderData.Trove.new()

limbExtenderData.playerTable = limbExtenderData.playerTable or {}
limbExtenderData.limbs = limbExtenderData.limbs or {}

local Streamable = limbExtenderData.Streamable
local CAU = limbExtenderData.CAU
local HighlightPool = limbExtenderData.HighlightPool
local Trove = limbExtenderData.Trove

local function watchProperty(instance, prop, callback)
	return instance:GetPropertyChangedSignal(prop):Connect(function()
		callback(instance)
	end)
end

local function saveLimbProperties(limb)
	limbExtenderData.limbs[limb] = {
		OriginalSize = limb.Size,
		OriginalTransparency = limb.Transparency,
		OriginalCanCollide = limb.CanCollide,
		OriginalMassless = limb.Massless,
	}
end

local function restoreLimbProperties(limb, partTrove)
	local p = limbExtenderData.limbs[limb]
	if not p then return end

	partTrove:Clean()

	pcall(function()
		limb.Size = p.OriginalSize
		limb.Transparency = p.OriginalTransparency
		limb.CanCollide = p.OriginalCanCollide
		limb.Massless = p.OriginalMassless
	end)
	limbExtenderData.limbs[limb] = nil
end

local function modifyLimbProperties(limb, partTrove)
	saveLimbProperties(limb)
	local newSize = Vector3.new(rawSettings.LIMB_SIZE, rawSettings.LIMB_SIZE, rawSettings.LIMB_SIZE)
	local canCollide = rawSettings.LIMB_CAN_COLLIDE


	if partTrove then
		partTrove:Add(limb:GetPropertyChangedSignal("Size"):Connect(function()
			limb.Size = newSize
		end))
		partTrove:Add(limb:GetPropertyChangedSignal("CanCollide"):Connect(function()
			limb.CanCollide = canCollide
		end))
	end


	limb.Size = newSize
	limb.Transparency = rawSettings.LIMB_TRANSPARENCY
	limb.CanCollide = canCollide
	if rawSettings.TARGET_LIMB ~= "HumanoidRootPart" then
		limb.Massless = true
	end
end

local function spoofSize(part)
	if limbExtenderData[rawSettings.TARGET_LIMB] then return end
	limbExtenderData[rawSettings.TARGET_LIMB] = true
	pcall(function()
		local mt = getrawmetatable(game)
		local saved = part.Size
		setreadonly(mt, false)
		local old = mt.__index
		mt.__index = function(self, key)
			if tostring(self) == rawSettings.TARGET_LIMB and key == "Size" then
				return saved
			end
			return old(self, key)
		end
		setreadonly(mt, true)
	end)
end

local function getHighlight()
	local hi = HighlightPool:Get()
	hi.Name = "LimbHighlight"
	hi.DepthMode = Enum.HighlightDepthMode[rawSettings.DEPTH_MODE]
	hi.FillColor = rawSettings.HIGHLIGHT_FILL_COLOR
	hi.FillTransparency = rawSettings.HIGHLIGHT_FILL_TRANSPARENCY
	hi.OutlineColor = rawSettings.HIGHLIGHT_OUTLINE_COLOR
	hi.OutlineTransparency = rawSettings.HIGHLIGHT_OUTLINE_TRANSPARENCY
	hi.Enabled = true
	return hi
end

local function isTeam(player)
	return rawSettings.TEAM_CHECK and localPlayer.Team ~= nil and player.Team == localPlayer.Team
end

local PlayerData = {}
PlayerData.__index = PlayerData

function PlayerData.new(player)
	local self = setmetatable({
		player = player,
		trove = Trove.new(),
		highlight = nil,
		PartStreamable = nil,
	}, PlayerData)

	self.trove:Add(player.CharacterAdded:Connect(function(c) self:onCharacter(c) end))

	local character = player.Character or workspace:FindFirstChild(player.Name)
	self:onCharacter(character)
	return self
end

function PlayerData:setupCharacter(char)
	self.trove:Add(self.player:GetPropertyChangedSignal("Team"):Connect(function()
		self:Destroy()
		limbExtenderData.playerTable[self.player.Name] = PlayerData.new(self.player)
	end))

	if isTeam(self.player) then return end

	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return end

	if self.PartStreamable then
		self.PartStreamable:Destroy()
		self.PartStreamable = nil
	end

	self.PartStreamable = Streamable.new(char, rawSettings.TARGET_LIMB)
	self.trove:Add(self.PartStreamable)

	self.PartStreamable:Observe(function(part, partTrove)
		spoofSize(part)
		modifyLimbProperties(part, partTrove)

		if rawSettings.USE_HIGHLIGHT then
			if not self.highlight then
				self.highlight = getHighlight()
			end
			self.highlight.Adornee = part
			self.highlight.Parent = self.player
		end

		partTrove:Add(self.player.CharacterRemoving:Connect(function()
			restoreLimbProperties(part, partTrove)
		end))

		if humanoid then
			local deathEvent = rawSettings.RESET_LIMB_ON_DEATH2 and humanoid.HealthChanged or humanoid.Died
			partTrove:Add(deathEvent:Connect(function(hp)
				if not hp or hp <= 0 then
					restoreLimbProperties(part,partTrove)
				end
			end))
		end

		partTrove:Add(function()
			restoreLimbProperties(part, partTrove)
			if self.highlight then
				HighlightPool:Return(self.highlight)
				self.highlight = nil
			end
		end)
	end)
end

function PlayerData:onCharacter(char)
	if not char then return end
	task.spawn(function()
		if rawSettings.FORCEFIELD_CHECK then
			local ff = char:WaitForChild("ForceField", .3)
			if ff then
				self.trove:Add(ff.Destroying:Connect(function()
					self:setupCharacter(char)
				end))
				return
			end
		end
		self:setupCharacter(char)
	end)
end

function PlayerData:Destroy()
	if self.trove then
		self.trove:Destroy()
		self.trove = nil
	end

	if self.highlight then
		pcall(function() HighlightPool:Return(self.highlight) end)
		self.highlight = nil
	end

	if self.PartStreamable then
		pcall(function() self.PartStreamable:Destroy() end)
		self.PartStreamable = nil
	end
end

local function onPlayerAdded(player)
	if game:GetService("RunService"):IsStudio() or player ~= localPlayer then
		limbExtenderData.playerTable[player.Name] = PlayerData.new(player)
	end
end

local function onPlayerRemoving(player)
	local pd = limbExtenderData.playerTable[player.Name]
	if pd then
		pd:Destroy()
		limbExtenderData.playerTable[player.Name] = nil
	end
end

local function terminate(reason)

	for _, pd in pairs(limbExtenderData.playerTable) do
		pd:Destroy()
	end
	limbExtenderData.playerTable = {}


	if limbExtenderData.RootTrove then
		if reason == "FullKill" then
			limbExtenderData.RootTrove:Destroy()
			limbExtenderData.RootTrove = nil
		else
			if limbExtenderData.RootTrove and limbExtenderData.RootTrove.Clean then
				limbExtenderData.RootTrove:Clean()
			else
				limbExtenderData.RootTrove:Destroy()
			end

			limbExtenderData.RootTrove = limbExtenderData.RootTrove or Trove.new()
		end
	end


	for limb in pairs(limbExtenderData.limbs) do
		restoreLimbProperties(limb)
	end

	if reason == "FullKill" or not rawSettings.LISTEN_FOR_INPUT then
		pcall(function() limbExtenderData.CAU:UnbindAction("LimbExtenderToggle") end)
	elseif rawSettings.MOBILE_BUTTON then
		pcall(function() CAU:SetTitle("LimbExtenderToggle", "On") end)
	end
end

local function initiate()

	terminate()
	if not limbExtenderData.running then return end


	limbExtenderData.RootTrove = limbExtenderData.RootTrove or Trove.new()

	for _, p in ipairs(Players:GetPlayers()) do
		onPlayerAdded(p)
	end


	limbExtenderData.RootTrove:Add(localPlayer:GetPropertyChangedSignal("Team"):Connect(initiate))
	limbExtenderData.RootTrove:Add(Players.PlayerAdded:Connect(onPlayerAdded))
	limbExtenderData.RootTrove:Add(Players.PlayerRemoving:Connect(onPlayerRemoving))

	if rawSettings.MOBILE_BUTTON and rawSettings.LISTEN_FOR_INPUT then
		CAU:SetTitle("LimbExtenderToggle", "Off")
	end
end

function rawSettings.toggleState(state)
	limbExtenderData.running = (state == nil and not limbExtenderData.running) or state
	if limbExtenderData.running then
		initiate()
	else
		terminate()
	end
end


if rawSettings.LISTEN_FOR_INPUT then

	pcall(function()
		limbExtenderData.CAU:UnbindAction("LimbExtenderToggle")
	end)

	local bindConn = CAU:BindAction(
		"LimbExtenderToggle",
		function(_, inputState)
			if inputState == Enum.UserInputState.Begin then
				rawSettings.toggleState()
			end
		end,
		rawSettings.MOBILE_BUTTON,
		Enum.KeyCode[rawSettings.TOGGLE]
	)


	if bindConn then
		limbExtenderData.RootTrove:Add(bindConn)
	else

		if rawSettings.MOBILE_BUTTON then
			CAU:SetTitle("LimbExtenderToggle", "On")
		end
	end
end


limbExtenderData.terminateOldProcess = terminate


if limbExtenderData.running then
	initiate()
elseif rawSettings.MOBILE_BUTTON and rawSettings.LISTEN_FOR_INPUT then
	CAU:SetTitle("LimbExtenderToggle", "On")
end

return setmetatable({}, {
	__index = rawSettings,
	__newindex = function(_, key, value)
		if rawSettings[key] ~= value then
			rawSettings[key] = value
			initiate()
		end
	end,
})
