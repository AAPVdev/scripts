local extender = ...

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local localplayer = Players.LocalPlayer

local ReplicatorService
local getNil = function(name, class)
    for _, v in next, getnilinstances() do
        if v.ClassName == class and v.Name == name then
            return v
        end
    end
end
ReplicatorService = require(getNil("ReplicatorService", "ModuleScript"))

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
        for _, model in ipairs(Workspace.Model:GetChildren()) do
            registerIfPlayer(model)
        end

        local conn1 = Workspace.Model.ChildAdded:Connect(function(desc)
            registerIfPlayer(desc)
        end)
        table.insert(connections, conn1)

        local conn2 = Workspace.Model.ChildRemoved:Connect(function(desc)
            if not desc:IsA("Model") then return end
            local player = customGetPlayer(desc)
            if player then
                extender:UnregisterPlayerCharacter(player, desc)
            end
        end)
        table.insert(connections, conn2)
    end
end

setup()

extender._customSetup = setup
