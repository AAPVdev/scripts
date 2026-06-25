local extender = ...

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local localplayer = Players.LocalPlayer

local getNil = function(name, class)
    for _, v in next, getnilinstances() do
        if v.ClassName == class and v.Name == name then
            return v
        end
    end
end

local ReplicatorService = require(getNil("ReplicatorService", "ModuleScript"))

local actorLookup = {}

for uid, actor in ReplicatorService.Actors do
    if actor.Character then
        actorLookup[actor.Character] = actor
    end
end

local realActors = ReplicatorService.Actors
local proxy = setmetatable({}, {
    __index = realActors,
    __newindex = function(_, uid, actor)
        
        local oldActor = rawget(realActors, uid)
        if oldActor and oldActor.Character then
            actorLookup[oldActor.Character] = nil
        end
        realActors[uid] = actor
        if actor and actor.Character then
            actorLookup[actor.Character] = actor
        end
    end,
    __pairs = function() return pairs(realActors) end,
    __len = function() return #realActors end,
})
ReplicatorService.Actors = proxy

local function customGetPlayer(model)
    local actor = actorLookup[model]
    return actor and actor.Owner
end

local connections = {}

local function registerIfPlayer(model)
    if not model:IsA("Model") then return end
    local player = customGetPlayer(model)
    if player and player ~= localplayer then
        extender:RegisterPlayerCharacter(player, model)
    end
end

local function setup()
    
    for _, conn in ipairs(connections) do
        conn:Disconnect()
    end
    table.clear(connections)

    extender:Set("CUSTOM_CHARACTER_SYSTEM", true)
    extender:Set("GET_PLAYER_FROM_CHARACTER", customGetPlayer)

    if extender:Get("PLAYER_ENABLED") then

    local characterFolder
    while not characterFolder do
        for uid, actor in ReplicatorService.Actors do
            if actor.Character and actor.Character.Parent then
                characterFolder = actor.Character.Parent
                break
            end
        end
        task.wait(0.5)
    end
    
    for _, model in ipairs(characterFolder:GetChildren()) do
        registerIfPlayer(model)
    end
    
    characterFolder.ChildAdded:Connect(function(child)
        registerIfPlayer(child)
    end)
    
    characterFolder.ChildRemoved:Connect(function(child)
        if not child:IsA("Model") then return end
        local player = customGetPlayer(child)
        if player then
            extender:UnregisterPlayerCharacter(player, child)
        end
    end)
end

setup()
extender._customSetup = setup
