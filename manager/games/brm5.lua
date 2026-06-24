local extender = loadstring(game:HttpGet('https://raw.githubusercontent.com/AAPVdev/scripts/refs/heads/main/LimbExtender.lua'))()

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local getNil = function(name, class)
    for _, v in next, getnilinstances() do
        if v.ClassName == class and v.Name == name then
            return v
        end
    end
end
local ReplicatorService = require(getNil("ReplicatorService", "ModuleScript"))

local actorLookup = {}
local function rebuildLookup()
    table.clear(actorLookup)
    for uid, actor in ReplicatorService.Actors do
        if actor.Character then
            actorLookup[actor.Character] = actor
        end
    end
end
rebuildLookup()

local function customGetPlayer(model)
    local actor = actorLookup[model]
    if actor and actor.Owner then
        return actor.Owner
    end
    return nil
end

extender:Set("GET_PLAYER_FROM_CHARACTER", customGetPlayer)

local function registerIfPlayer(model)
    if not model:IsA("Model") then return end
    local player = customGetPlayer(model)
    if player then
        extender:RegisterPlayerCharacter(player, model)
    end
end

for _, model in ipairs(Workspace.Model:GetChildren()) do
    registerIfPlayer(model)
end

Workspace.Model.ChildAdded:Connect(function(desc)
    registerIfPlayer(desc)

Workspace.Model.ChildRemoved:Connect(function(desc)
    if not desc:IsA("Model") then return end
    local player = customGetPlayer(desc)
    if player then
        extender:UnregisterPlayerCharacter(player, desc)
    end
end)
