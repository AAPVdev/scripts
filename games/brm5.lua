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
local connections = {}

local function rebuildLookup()
    table.clear(actorLookup)
    for uid, actor in ReplicatorService.Actors do
        if actor.Character then
            actorLookup[actor.Character] = actor
        end
    end
end

local function customGetPlayer(model)
    local actor = actorLookup[model]
    return actor and actor.Owner
end

local function registerIfPlayer(model)
    if not model:IsA("Model") then return end
    local player = customGetPlayer(model)
    if player and not player == localplayer then
        extender:RegisterPlayerCharacter(player, model)
    end
end

local function setup()
    for _, conn in ipairs(connections) do
        conn:Disconnect()
    end
    table.clear(connections)

    rebuildLookup()

    extender:Set("GET_PLAYER_FROM_CHARACTER", customGetPlayer)

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

setup()

extender._customSetup = setup
