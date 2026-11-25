local extender = ...

local Players     = game:GetService("Players")
local RunService  = game:GetService("RunService")
local localplayer = Players.LocalPlayer

local function getNil(name, class)
	for _, v in next, getnilinstances() do
		if v.ClassName == class and v.Name == name then
			return v
		end
	end
	return nil
end

local worS = getNil("WorldService", "ModuleScript")
local repS = getNil("ReplicatorService", "ModuleScript")
if not (worS and repS) then return end

local getId  = type(getthreadidentity) == "function" and getthreadidentity or nil
local setId  = type(setthreadidentity) == "function" and setthreadidentity or nil
local prevId = getId and getId() or nil

if setId then setId(2) end
local okW, WorldService      = pcall(require, worS)
local okR, ReplicatorService = pcall(require, repS)
if setId and prevId then setId(prevId) end

if not (okW and okR and WorldService and ReplicatorService) then return end

local connections      = {}
local worldConns       = {}
local registeredModels = setmetatable({}, { __mode = "k" })
local boundWorld       = nil

local function customGetPlayer(model)
	local cached = registeredModels[model]
	if cached then return cached end
	local actors = ReplicatorService.Actors
	if type(actors) ~= "table" then return nil end
	for _, actor in pairs(actors) do
		if actor.Character == model then
			return actor.Owner
		end
	end
	return nil
end

local function disconnectList(list)
	for i = 1, #list do
		list[i]:Disconnect()
	end
	table.clear(list)
end

local function registerIfPlayer(model)
	if not model or not model:IsA("Model") then return end
	local lp = localplayer or Players.LocalPlayer

	local player = customGetPlayer(model)
	if player and player ~= lp then
		registeredModels[model] = player
		extender:RegisterPlayerCharacter(player, model)
	else
		task.defer(function()
			if not model.Parent or not extender._running or extender._destroyed then return end
			local retryPlayer = customGetPlayer(model)
			if retryPlayer and retryPlayer ~= (localplayer or Players.LocalPlayer) then
				registeredModels[model] = retryPlayer
				extender:RegisterPlayerCharacter(retryPlayer, model)
			end
		end)
	end
end

local function bindActiveWorld(world)
	if world == boundWorld then return end
	disconnectList(worldConns)
	boundWorld = world
	if not world then return end

	for _, model in ipairs(world:GetChildren()) do
		registerIfPlayer(model)
	end

	worldConns[#worldConns + 1] = world.ChildAdded:Connect(registerIfPlayer)
	worldConns[#worldConns + 1] = world.ChildRemoved:Connect(function(child)
		if not child:IsA("Model") then return end
		local player = registeredModels[child] or customGetPlayer(child)
		registeredModels[child] = nil
		if player then
			extender:UnregisterPlayerCharacter(player, child)
		end
	end)
end

local function cleanup()
	disconnectList(worldConns)
	disconnectList(connections)
	table.clear(registeredModels)
	boundWorld = nil
end

local function setup()
	cleanup()

	extender:Set("CUSTOM_CHARACTER_SYSTEM", true)
	extender:Set("GET_PLAYER_FROM_CHARACTER", customGetPlayer)

	if not extender:Get("PLAYER_ENABLED") then return end

	bindActiveWorld(WorldService.ActiveWorld)

	local elapsed = 0
	connections[#connections + 1] = RunService.Heartbeat:Connect(function(dt)
		elapsed = elapsed + dt
		if elapsed < 0.5 then return end
		elapsed = 0
		if WorldService.ActiveWorld ~= boundWorld then
			bindActiveWorld(WorldService.ActiveWorld)
		end
	end)
end

extender._customSetup   = setup
extender._customCleanup = cleanup
setup()
