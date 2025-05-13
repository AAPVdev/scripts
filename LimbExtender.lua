local rawSettings = {
    TOGGLE = "L",
    TARGET_LIMB = "HumanoidRootPart",
    LIMB_SIZE = 15,
    MOBILE_BUTTON = true,
    LIMB_TRANSPARENCY = 0.9,
    LIMB_CAN_COLLIDE = false,
    TEAM_CHECK = true,
    FORCEFIELD_CHECK = true,
    RESET_LIMB_ON_DEATH2 = false,
    USE_HIGHLIGHT = true,
    DEPTH_MODE = "AlwaysOnTop",
    HIGHLIGHT_FILL_COLOR = Color3.fromRGB(0, 140, 140),
    HIGHLIGHT_FILL_TRANSPARENCY = 0.7,
    HIGHLIGHT_OUTLINE_COLOR = Color3.fromRGB(255, 255, 255),
    HIGHLIGHT_OUTLINE_TRANSPARENCY = 1,
    LISTEN_FOR_INPUT = true
}

getgenv().limbExtenderData = getgenv().limbExtenderData or {}
local limbExtenderData = getgenv().limbExtenderData
local limbExtender = nil

if limbExtenderData.running ~= nil then
    limbExtenderData.terminateOldProcess("FullKill")
end

local players = game:GetService("Players")
local tweenService = game:GetService("TweenService")
local contentProvider = game:GetService("ContentProvider")

local localPlayer = players.LocalPlayer

limbExtenderData.running = limbExtenderData.running or false
limbExtenderData.CAU = limbExtenderData.CAU or loadstring(game:HttpGet('https://raw.githubusercontent.com/AAPVdev/scripts/refs/heads/main/ContextActionUtility.lua'))()
    -- or require(script.Parent.ContextActionUtility)

limbExtenderData.playerTable = limbExtenderData.playerTable or {}
limbExtenderData.limbs = limbExtenderData.limbs or {}

local playerTable = limbExtenderData.playerTable
local limbs = limbExtenderData.limbs
local contextActionUtility = limbExtenderData.CAU

local function getPlayers(func, includeLocalPlayer)
    for _, player in ipairs(players:GetPlayers()) do
        if includeLocalPlayer or player ~= localPlayer then
            func(player)
        end
    end
end

local function restoreLimbProperties(limb)
    local limbProperties = limbs[limb]
    if not limbProperties then return end

    limbProperties.SizeChanged:Disconnect()
    limbProperties.CollisionChanged:Disconnect()

    if playerTable[limb.Parent] and playerTable[limb.Parent.Name] and playerTable[limb.Parent.Name]["highlight"] then
        playerTable[limb.Parent.Name]["highlight"].Parent = nil
    end

    limbs[limb] = nil

    limb.Size = limbProperties.Size
    limb.CanCollide = limbProperties.CanCollide
    limb.Transparency = limbProperties.Transparency
    limb.Massless = limbProperties.Massless
end

local function saveLimbProperties(limb)
    if limbs[limb] then
        restoreLimbProperties(limb)
    end

    limbs[limb] = {
        Size = limb.Size,
        Transparency = limb.Transparency,
        CanCollide = limb.CanCollide,
        Massless = limb.Massless
    }
end

local function modifyLimbProperties(limb)
    saveLimbProperties(limb)

    local newSize = Vector3.new(
        rawSettings.LIMB_SIZE,
        rawSettings.LIMB_SIZE,
        rawSettings.LIMB_SIZE
    )

    limbs[limb].SizeChanged = limb:GetPropertyChangedSignal("Size"):Connect(function()
        limb.Size = newSize
    end)

    limbs[limb].CollisionChanged = limb:GetPropertyChangedSignal("CanCollide"):Connect(function()
        limb.CanCollide = rawSettings.LIMB_CAN_COLLIDE
    end)

    limb.Size = newSize
    limb.Transparency = rawSettings.LIMB_TRANSPARENCY
    limb.CanCollide = rawSettings.LIMB_CAN_COLLIDE

    if rawSettings.TARGET_LIMB ~= "HumanoidRootPart" then
        limb.Massless = true
    end
end

local function removePlayerData(player)
    local playerData = playerTable[player.Name]
    if playerData then
        for _, connection in pairs(playerData) do
            if typeof(connection) == "RBXScriptConnection" then
                connection:Disconnect()
            end
        end
        if playerData["highlight"] then
            playerData["highlight"]:Destroy()
        end
        playerTable[player.Name] = nil
    end
end

local function terminate(specialProcess)
    for key, connection in pairs(getgenv().limbExtenderData) do
        if typeof(connection) == "RBXScriptConnection" then
            connection:Disconnect()
            limbExtenderData[key] = nil
        end
    end

    getPlayers(removePlayerData, false)

    for limb, _ in pairs(limbExtenderData.limbs) do
        restoreLimbProperties(limb)
    end

    if specialProcess == "FullKill" then
        contextActionUtility:UnbindAction("LimbExtenderToggle")
    else
        if not rawSettings.LISTEN_FOR_INPUT then
            contextActionUtility:UnbindAction("LimbExtenderToggle")
        elseif rawSettings.MOBILE_BUTTON then
            contextActionUtility:SetTitle("LimbExtenderToggle", "On")
        end
    end
end

local function initiate()
    terminate()

    if not limbExtenderData.running then
        return
    end

    local function setupPlayer(player)
        local function characterAdded(character)
            if character then
                local playerData = playerTable[player.Name]
                if playerData then
                    playerData["teamChanged"] = player:GetPropertyChangedSignal("Team"):Once(function()
                        removePlayerData(player)
                        setupPlayer(player)
                    end)

                    local humanoid = character:WaitForChild("Humanoid", 0.2)
                    local targetLimb = character:WaitForChild(rawSettings.TARGET_LIMB, 0.2)

                    if targetLimb == nil or humanoid == nil then
                        for _, child in ipairs(character:GetDescendants()) do
                            if child.Name == "Humanoid" then
                                child = humanoid
                            elseif child.Name == rawSettings.TARGET_LIMB then
                                child = targetLimb
                            end
                        end
                    end

                    if targetLimb and humanoid then
                        if not limbExtenderData[targetLimb.Name] then
                            pcall(function()
                                local name = targetLimb.Name
                                local mt = getrawmetatable(game)
                                setreadonly(mt, false)
                                local old = mt.__index
                                mt.__index = function(Self, Key)
                                    if tostring(Self) == name and tostring(Key) == "Size" then
                                        return targetLimb.Size
                                    end
                                    return old(Self, Key)
                                end
                                setreadonly(mt, true)
                                limbExtenderData[targetLimb.Name] = true
                            end)
                        end

                        if humanoid.Health > 0 then
                            if (rawSettings.TEAM_CHECK and (localPlayer.Team == nil or player.Team ~= localPlayer.Team)) or not rawSettings.TEAM_CHECK then
                                modifyLimbProperties(targetLimb)
                            end

                            if rawSettings.USE_HIGHLIGHT then
                                playerData["highlight"] = Instance.new("Highlight")
                                local highlightInstance = playerData["highlight"]
                                highlightInstance.Name = "LimbHighlight"
                                highlightInstance.DepthMode = Enum.HighlightDepthMode[rawSettings.DEPTH_MODE]
                                highlightInstance.FillColor = rawSettings.HIGHLIGHT_FILL_COLOR
                                highlightInstance.FillTransparency = rawSettings.HIGHLIGHT_FILL_TRANSPARENCY
                                highlightInstance.OutlineColor = rawSettings.HIGHLIGHT_OUTLINE_COLOR
                                highlightInstance.OutlineTransparency = rawSettings.HIGHLIGHT_OUTLINE_TRANSPARENCY
                                highlightInstance.Enabled = true
                                highlightInstance.Parent = targetLimb
                            end

                            playerData["characterRemoving"] = player.CharacterRemoving:Once(function()
                                restoreLimbProperties(targetLimb)
                            end)

                            local connection = rawSettings.RESET_LIMB_ON_DEATH2 and humanoid.HealthChanged or humanoid.Died
                            playerData["OnDeath"] = connection:Connect(function(health)
                                if health and health <= 0 then
                                    restoreLimbProperties(targetLimb)
                                end
                            end)
                        end
                    end
                end
            end
        end
        
        if not limbExtenderData["indexBypass"] then 
            --https://github.com/yamiyothegoat/Adonis-Oops-All-False   
            local targetTable
            
            for _, gcItem in ipairs(getgc(true)) do
                if typeof(gcItem) ~= "table" then
                    continue
                end
            
                local indexTable = rawget(gcItem, "indexInstance")
                if indexTable and typeof(indexTable) == "table" then
                    local methodName = indexTable[1] or ""
                    if methodName == "kick" then
                        targetTable = gcItem
                        break
                    end
                end
            end
            
            if targetTable then
                for key, fnPair in pairs(targetTable) do
                    fnPair[2] = function()
                        return false
                    end
                end
            end
            
            return targetTable
            limbExtenderData["indexBypass"] = true
        end

        playerTable[player.Name] = {}
        playerTable[player.Name]["characterAdded"] = player.CharacterAdded:Connect(characterAdded)
        characterAdded(player.Character)
    end

    getPlayers(setupPlayer, false)

    limbExtenderData.teamChanged = localPlayer:GetPropertyChangedSignal("Team"):Once(initiate)
    limbExtenderData.playerAdded = players.PlayerAdded:Connect(setupPlayer)
    limbExtenderData.playerRemoving = players.PlayerRemoving:Connect(removePlayerData)

    if rawSettings.MOBILE_BUTTON and rawSettings.LISTEN_FOR_INPUT then
        contextActionUtility:SetTitle("LimbExtenderToggle", "Off")
    end
end

function rawSettings.toggleState(state)
    local newState = (state == nil) and (not limbExtenderData.running) or state
    limbExtenderData.running = newState

    if newState then
        initiate()
    else
        terminate()
    end
end

limbExtender = setmetatable({}, {
    __index = rawSettings,
    __newindex = function(_, key, value)
        if rawSettings[key] ~= value then
            rawSettings[key] = value
            initiate()
        end
    end
})

if rawSettings.LISTEN_FOR_INPUT then
    contextActionUtility:BindAction(
        "LimbExtenderToggle",
        function(_, inputState)
            if inputState == Enum.UserInputState.Begin then
                rawSettings.toggleState()
            end
        end,
        rawSettings.MOBILE_BUTTON,
        Enum.KeyCode[rawSettings.TOGGLE]
    )
end

limbExtenderData.terminateOldProcess = terminate

if limbExtenderData.running then
    initiate()
elseif rawSettings.MOBILE_BUTTON and rawSettings.LISTEN_FOR_INPUT then
    contextActionUtility:SetTitle("LimbExtenderToggle", "On")
end

return limbExtender
