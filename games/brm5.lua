local extender = ...

local Players = game:GetService("Players")
local localplayer = Players.LocalPlayer

local getNil = function(name, class)
    for _, v in next, getnilinstances() do
        if v.ClassName == class and v.Name == name then
            return v
        end
    end
end

local worS = getNil("WorldService", "ModuleScript")
local repS = getNil("ReplicatorService", "ModuleScript")

setthreadidentity(2)

local WorldService = require(worS)
local ReplicatorService = require(repS)

local function customGetPlayer(model)
    for _, actor in pairs(ReplicatorService.Actors) do
        if actor.Character == model then
            return actor.Owner
        end
    end
    return nil
end

local connections = {}

local function registerIfPlayer(model)
    if not model:IsA("Model") then return end

    local player = customGetPlayer(model)
    if player and player ~= localplayer then
        extender:RegisterPlayerCharacter(player, model)
    else
        task.defer(function()
            if model.Parent then
                local retryPlayer = customGetPlayer(model)
                if retryPlayer and retryPlayer ~= localplayer then
                    extender:RegisterPlayerCharacter(retryPlayer, model)
                end
            end
        end)
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
        for _, model in ipairs(WorldService.ActiveWorld:GetChildren()) do
            registerIfPlayer(model)
        end

        local conn1 = WorldService.ActiveWorld.ChildAdded:Connect(function(child)
            registerIfPlayer(child)
        end)
        table.insert(connections, conn1)

        local conn2 = WorldService.ActiveWorld.ChildRemoved:Connect(function(child)
            if not child:IsA("Model") then return end
            local player = customGetPlayer(child)
            if player then
                extender:UnregisterPlayerCharacter(player, child)
            end
        end)
        table.insert(connections, conn2)
    end
end

setup()
extender._customSetup = setup
