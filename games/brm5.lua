local extender = ...
if type(extender) ~= "table" then return end

local cloneref = type(cloneref) == "function" and cloneref or function(obj) return obj end

local Players    = cloneref(game:GetService("Players"))
local RunService = cloneref(game:GetService("RunService"))

local table_clear = table.clear
local task_defer  = task.defer
local task_delay  = task.delay

local cachedLocalPlayer = Players.LocalPlayer
local function getLocalPlayer()
	if not cachedLocalPlayer then
		cachedLocalPlayer = Players.LocalPlayer
	end
	return cachedLocalPlayer
end

if type(getnilinstances) ~= "function" then return end

local worS, repS
local nilInstances = getnilinstances()
for i = 1, #nilInstances do
	local inst = nilInstances[i]
	if inst.ClassName == "ModuleScript" then
		local name = inst.Name
		if name == "WorldService" then
			worS = inst
			if repS then break end
		elseif name == "ReplicatorService" then
			repS = inst
			if worS then break end
		end
	end
end
if not (worS and repS) then return end

local getIdentityFn = type(getthreadidentity) == "function" and getthreadidentity
	or (type(syn) == "table" and type(syn.get_thread_identity) == "function" and syn.get_thread_identity)
	or nil
local setIdentityFn = type(setthreadidentity) == "function" and setthreadidentity
	or (type(syn) == "table" and type(syn.set_thread_identity) == "function" and syn.set_thread_identity)
	or nil

local prevIdentity = nil
if getIdentityFn then
	local okId, curId = pcall(getIdentityFn)
	if okId then prevIdentity = curId end
end

if setIdentityFn then pcall(setIdentityFn, 2) end
local okW, WorldService      = pcall(require, worS)
local okR, ReplicatorService = pcall(require, repS)
if setIdentityFn and prevIdentity ~= nil then pcall(setIdentityFn, prevIdentity) end

if not (okW and okR and WorldService and ReplicatorService) then return end

local POLL_INTERVAL     = 0.5
local ACTOR_RETRY_DELAY = 0.15

local pollConn         = nil
local worldConns       = {}
local ownerCache       = setmetatable({}, { __mode = "k" })
local registeredOwners = setmetatable({}, { __mode = "k" })
local playerModels     = setmetatable({}, { __mode = "kv" })
local boundWorld       = nil

local function isExtenderRunning()
	if type(extender.IsRunning) == "function" then
		return extender:IsRunning()
	end
	return extender._running == true and not extender._destroyed
end

local function disconnectList(list)
	for i = 1, #list do
		local conn = list[i]
		if conn and conn.Connected then
			conn:Disconnect()
		end
	end
	table_clear(list)
end

local function customGetPlayer(model)
	if not model then return nil end
	local cached = ownerCache[model]
	if cached and cached.Parent ~= nil then
		return cached
	end
	local actors = ReplicatorService.Actors
	if type(actors) ~= "table" then return nil end
	for _, actor in pairs(actors) do
		if actor.Character == model then
			local owner = actor.Owner
			if owner then
				ownerCache[model] = owner
			end
			return owner
		end
	end
	return nil
end

local function applyModelOwner(model, player)
	if not model or not player or extender._destroyed then return end

	local prevModel = playerModels[player]
	if prevModel and prevModel ~= model then
		if ownerCache[prevModel] == player then
			ownerCache[prevModel] = nil
		end
		if registeredOwners[prevModel] == player then
			registeredOwners[prevModel] = nil
		end
	end

	playerModels[player] = model
	ownerCache[model]    = player

	if registeredOwners[model] == player then return end
	registeredOwners[model] = player

	if player == getLocalPlayer() then
		extender:SetLocalCharacter(model)
	else
		if not extender:GetReferenceCharacter() then
			extender:SetSampleCharacter(model)
		end
		extender:RegisterPlayerCharacter(player, model)
	end
end

local function reconcileActors()
	local actors = ReplicatorService.Actors
	if type(actors) ~= "table" then return end
	for _, actor in pairs(actors) do
		local model = actor.Character
		local owner = actor.Owner
		if model and owner and model.Parent ~= nil then
			if registeredOwners[model] ~= owner then
				applyModelOwner(model, owner)
			else
				ownerCache[model] = owner
			end
		end
	end
end

local function handleModelAdded(model)
	if not model or not model:IsA("Model") or extender._destroyed then return end

	local player = customGetPlayer(model)
	if player then
		applyModelOwner(model, player)
		return
	end

	task_defer(function()
		if not model.Parent or extender._destroyed or registeredOwners[model] then return end
		local retryPlayer = customGetPlayer(model)
		if retryPlayer then
			applyModelOwner(model, retryPlayer)
		elseif task_delay then
			task_delay(ACTOR_RETRY_DELAY, function()
				if not model.Parent or extender._destroyed or registeredOwners[model] then return end
				local delayedPlayer = customGetPlayer(model)
				if delayedPlayer then
					applyModelOwner(model, delayedPlayer)
				end
			end)
		end
	end)
end

local function handleModelRemoved(child)
	if not child or not child:IsA("Model") then return end
	local player = registeredOwners[child] or ownerCache[child] or customGetPlayer(child)
	registeredOwners[child] = nil
	ownerCache[child]       = nil
	if player and playerModels[player] == child then
		playerModels[player] = nil
	end

	if extender._destroyed then return end
	if player == getLocalPlayer() then
		if extender:GetLocalCharacter() == child then
			extender:SetLocalCharacter(nil)
		end
	elseif player then
		extender:UnregisterPlayerCharacter(player, child)
	end
end

local function scanWorldChildren(world)
	if not world then return end
	local children = world:GetChildren()
	for i = 1, #children do
		handleModelAdded(children[i])
	end
end

local function bindActiveWorld(world)
	if world == boundWorld then return end
	disconnectList(worldConns)
	boundWorld = world
	if not world then
		extender:SetLocalCharacter(nil)
		return
	end

	scanWorldChildren(world)
	reconcileActors()

	worldConns[#worldConns + 1] = world.ChildAdded:Connect(handleModelAdded)
	worldConns[#worldConns + 1] = world.ChildRemoved:Connect(handleModelRemoved)
end

local function startPolling()
	if pollConn then return end
	local elapsed = 0
	pollConn = RunService.Heartbeat:Connect(function(dt)
		elapsed = elapsed + dt
		if elapsed < POLL_INTERVAL then return end
		elapsed = 0
		if extender._destroyed then return end

		local active = WorldService.ActiveWorld
		if active ~= boundWorld then
			bindActiveWorld(active)
		else
			reconcileActors()
		end
	end)
end

local function cleanup()
	if pollConn then
		pollConn:Disconnect()
		pollConn = nil
	end
	disconnectList(worldConns)
	table_clear(registeredOwners)
	boundWorld = nil
end

local function destroy()
	cleanup()
	table_clear(ownerCache)
	table_clear(playerModels)
end

local function setup()
	if extender._destroyed then return end
	extender:Set("CUSTOM_CHARACTER_SYSTEM", true)
	extender:Set("GET_PLAYER_FROM_CHARACTER", customGetPlayer)

	local world = WorldService.ActiveWorld
	if world ~= boundWorld then
		bindActiveWorld(world)
	else
		scanWorldChildren(world)
		reconcileActors()
	end
	startPolling()
end

extender:Set("CUSTOM_CHARACTER_SYSTEM", true)
extender:Set("GET_PLAYER_FROM_CHARACTER", customGetPlayer)
extender._customSetup   = setup
extender._customCleanup = cleanup
extender._customDestroy = destroy

if isExtenderRunning() then
	setup()
else
	scanWorldChildren(WorldService.ActiveWorld)
	reconcileActors()
end
