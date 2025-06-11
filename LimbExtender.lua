local rawSettings = {
	TOGGLE = "L",
	TARGET_LIMB = "Head",
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

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local localPlayer = Players.LocalPlayer

local global = RunService:IsStudio() and _G or getgenv()

local limbExtenderData = global.limbExtenderData or {}
global.limbExtenderData = limbExtenderData

local Settings = {}
Settings.__index = Settings
function Settings.new(raw)
	local self = setmetatable({ data = raw, onChange = nil }, Settings)
	return self
end

function Settings:__index(key)
	if Settings[key] then return Settings[key] end
	return self.data[key]
end

function Settings:__newindex(key, value)
	if self.data[key] ~= value then
		self.data[key] = value
		if self.onChange then self.onChange(key, value) end
	end
end

local LimbData = {}
LimbData.__index = LimbData
function LimbData.new(limb, settings)
	local self = setmetatable({ limb = limb, settings = settings, conns = {} }, LimbData)
	self:save()
	self:modify()
	return self
end

function LimbData:save()
	self.original = {
		Size = self.limb.Size,
		Transparency = self.limb.Transparency,
		CanCollide = self.limb.CanCollide,
		Massless = self.limb.Massless,
	}
end

function LimbData:modify()
	local newSize = Vector3.new(self.settings.LIMB_SIZE, self.settings.LIMB_SIZE, self.settings.LIMB_SIZE)
	table.insert(self.conns, self.limb:GetPropertyChangedSignal("Size"):Connect(function() self.limb.Size = newSize end))
	table.insert(self.conns, self.limb:GetPropertyChangedSignal("CanCollide"):Connect(function() self.limb.CanCollide = self.settings.LIMB_CAN_COLLIDE end))
	self.limb.Size = newSize
	self.limb.Transparency = self.settings.LIMB_TRANSPARENCY
	self.limb.CanCollide = self.settings.LIMB_CAN_COLLIDE
	if self.settings.TARGET_LIMB ~= "HumanoidRootPart" then
		self.limb.Massless = true
	end
end

function LimbData:restore()
	for _, conn in ipairs(self.conns) do if typeof(conn) == "RBXScriptConnection" then conn:Disconnect() end end
	local o = self.original
	self.limb.Size = o.Size
	self.limb.Transparency = o.Transparency
	self.limb.CanCollide = o.CanCollide
	self.limb.Massless = o.Massless
end

local PlayerData = {}
PlayerData.__index = PlayerData
function PlayerData.new(player, extender)
	local self = setmetatable({
		player = player,
		extender = extender,
		conns = {},
		highlight = nil,
		streamable = nil,
	}, PlayerData)
	table.insert(self.conns, player.CharacterAdded:Connect(function(c) self:onCharacter(c) end))
	local char = player.Character or workspace:FindFirstChild(player.Name)
	self:onCharacter(char)
	return self
end

function PlayerData:onCharacter(char)
	if not char then return end
	if self.extender.settings.FORCEFIELD_CHECK and char:FindFirstChildOfClass("ForceField") then
		table.insert(self.conns, char.ChildRemoved:Once(function(child)
			if child:IsA("ForceField") then self:onCharacter(char) end
		end))
		return
	end
	self:setupCharacter(char)
end

function PlayerData:setupCharacter(char)

	table.insert(self.conns, self.player:GetPropertyChangedSignal("Team"):Once(function()
		self:Destroy()
		self.extender:onPlayerAdded(self.player)
	end))

	task.spawn(function()
		local humanoid = char:WaitForChild("Humanoid", 1)
		if not humanoid or humanoid.Health <= 0 then return end

		if self.streamable then self.streamable:Destroy() end
		self.streamable = self.extender.settings.Streamable.new(char, self.extender.settings.TARGET_LIMB)
		self.streamable:Observe(function(part, trove)

			self.extender:spoofSize(part)

			local ld = LimbData.new(part, self.extender.settings)
			self.extender.limbs[part] = ld

			if self.extender.settings.USE_HIGHLIGHT then
				if not self.highlight then self.highlight = self.extender:makeHighlight() end
				self.highlight.Adornee = part
			end

			table.insert(self.conns, self.player.CharacterRemoving:Once(function()
				ld:restore()
			end))

			if self.extender.settings.RESET_LIMB_ON_DEATH2 then
				table.insert(self.conns, humanoid.HealthChanged:Connect(function(h) if h <= 0 then ld:restore() end end))
			else
				table.insert(self.conns, humanoid.Died:Connect(function() ld:restore() end))
			end

			trove:Add(function() ld:restore() end)
		end)
	end)
end

function PlayerData:Destroy()
	for _, c in ipairs(self.conns) do if typeof(c) == "RBXScriptConnection" then c:Disconnect() end end
	if self.highlight then self.highlight:Destroy() end
	if self.streamable then self.streamable:Destroy() end
end

local LimbExtender = {}
LimbExtender.__index = LimbExtender
function LimbExtender.new(settings)
	local self = setmetatable({
		settings = settings,
		players = {},
		limbs = {},
		running = false,
	}, LimbExtender)
	settings.onChange = function() self:restart() end
	return self
end

function LimbExtender:start()
	if self.running then return end
	self.running = true
	self:terminate()
	self:indexBypass()
	self:bindInputToggle()
	self:initPlayers()
	self.playerAddedConn = Players.PlayerAdded:Connect(function(p) self:onPlayerAdded(p) end)
	self.playerRemovingConn = Players.PlayerRemoving:Connect(function(p) self:onPlayerRemoving(p) end)
end

function LimbExtender:terminate(full)
	if self.playerAddedConn then self.playerAddedConn:Disconnect() end
	if self.playerRemovingConn then self.playerRemovingConn:Disconnect() end

	for _, pd in pairs(self.players) do pd:Destroy() end
	self.players = {}

	for limb, ld in pairs(self.limbs) do ld:restore() end
	self.limbs = {}

	if full or not self.settings.LISTEN_FOR_INPUT then
		self.settings.CAU:UnbindAction("LimbExtenderToggle")
	elseif self.settings.MOBILE_BUTTON then
		self.settings.CAU:SetTitle("LimbExtenderToggle", "On")
	end
end

function LimbExtender:restart()
	if self.running then self:terminate() self:start() end
end

function LimbExtender:initPlayers()
	for _, p in ipairs(Players:GetPlayers()) do 
		if p ~= localPlayer then self:onPlayerAdded(p) end
	end
end

function LimbExtender:onPlayerAdded(player)
	self.players[player.Name] = PlayerData.new(player, self)
end

function LimbExtender:onPlayerRemoving(player)
	local pd = self.players[player.Name]
	if pd then pd:Destroy() self.players[player.Name] = nil end
end

function LimbExtender:indexBypass()
	if limbExtenderData.indexBypass then return end
	limbExtenderData.indexBypass = true
	pcall(function()
		for _, obj in ipairs(getgc(true)) do
			local idx = rawget(obj, "indexInstance")
			if typeof(idx) == "table" and idx[1] == "kick" then
				for _, pair in pairs(obj) do pair[2] = function() return false end end
				break
			end
		end
	end)
end

function LimbExtender:spoofSize(part)
	if limbExtenderData[self.settings.TARGET_LIMB] then return end
	limbExtenderData[self.settings.TARGET_LIMB] = true
	pcall(function()
		local mt = getrawmetatable(game)
		local saved = part.Size
		setreadonly(mt, false)
		local old = mt.__index
		mt.__index = function(selfObj, key)
			if tostring(selfObj) == self.settings.TARGET_LIMB and key == "Size" then return saved end
			return old(selfObj, key)
		end
		setreadonly(mt, true)
	end)
end

function LimbExtender:bindInputToggle()
	if not self.settings.LISTEN_FOR_INPUT then return end
	self.settings.InputBind = self.settings.CAU:BindAction(
		"LimbExtenderToggle",
		function(_, state) if state == Enum.UserInputState.Begin then self:toggle() end end,
		self.settings.MOBILE_BUTTON,
		Enum.KeyCode[self.settings.TOGGLE]
	)
end

function LimbExtender:toggle()
	if self.running then self:terminate() self.running = false
	else self:start() end
end

function LimbExtender:makeHighlight()
	local hiFolder = Players:FindFirstChild("Limb Extender Highlights Folder") or Instance.new("Folder")
	hiFolder.Name = "Limb Extender Highlights Folder"
	hiFolder.Parent = Players
	local hi = Instance.new("Highlight")
	hi.Name = "LimbHighlight"
	hi.DepthMode = Enum.HighlightDepthMode[self.settings.DEPTH_MODE]
	hi.FillColor = self.settings.HIGHLIGHT_FILL_COLOR
	hi.FillTransparency = self.settings.HIGHLIGHT_FILL_TRANSPARENCY
	hi.OutlineColor = self.settings.HIGHLIGHT_OUTLINE_COLOR
	hi.OutlineTransparency = self.settings.HIGHLIGHT_OUTLINE_TRANSPARENCY
	hi.Parent = hiFolder
	hi.Enabled = true
	return hi
end

limbExtenderData.CAU = limbExtenderData.CAU or RunService:IsStudio() and require(game:GetService("ReplicatedStorage"):WaitForChild("Modules"):WaitForChild("ContextActionUtility")) or loadstring(game:HttpGet("https://raw.githubusercontent.com/AAPVdev/scripts/refs/heads/main/ContextActionUtility.lua"))
limbExtenderData.Streamable = limbExtenderData.Streamable or RunService:IsStudio() and require(game:GetService("ReplicatedStorage"):WaitForChild("Modules"):WaitForChild("Streamable")) or loadstring(game:HttpGet("https://raw.githubusercontent.com/AAPVdev/scripts/refs/heads/main/Streamable.lua"))

local settings = Settings.new(rawSettings)
settings.Streamable = limbExtenderData.Streamable
settings.CAU = limbExtenderData.CAU

local extender = LimbExtender.new(settings)
if rawSettings.LISTEN_FOR_INPUT then extender:bindInputToggle() end

limbExtenderData.terminateOldProcess = function(reason) extender:terminate(reason == "FullKill") end
if rawSettings.LISTEN_FOR_INPUT and extender.running then extender:start() end

return extender
