if getgenv().IsProcessActive and type(getgenv().LimbExtenderGlobalData.LimbExtenderTerminateOldProcess) == "function" then
    getgenv().LimbExtenderGlobalData.LimbExtenderTerminateOldProcess("FullKill")
end

local rawSettings = {
    TOGGLE = "K",
    TARGET_LIMB = "Head",
    LIMB_SIZE = 5,
    LIMB_TRANSPARENCY = 0.9,
    LIMB_CAN_COLLIDE = false,
    TEAM_CHECK = true,
    FORCEFIELD_CHECK = true,
    RESTORE_ORIGINAL_LIMB_ON_DEATH = false,
    ESP = false,
    USE_HIGHLIGHT = true,
    DEPTH_MODE = 2,
    HIGHLIGHT_FILL_COLOR = Color3.fromRGB(0, 255, 0),
    HIGHLIGHT_FILL_TRANSPARENCY = 0.5,
    HIGHLIGHT_OUTLINE_COLOR = Color3.fromRGB(255, 255, 255),
    HIGHLIGHT_OUTLINE_TRANSPARENCY = 0,
}

getgenv().LimbExtenderGlobalData = getgenv().LimbExtenderGlobalData or {}
getgenv().LimbExtenderGlobalData.Sense = getgenv().LimbExtenderGlobalData.Sense or loadstring(game:HttpGet('https://sirius.menu/sense'))()
getgenv().LimbExtenderGlobalData.LimbsFolder = getgenv().LimbExtenderGlobalData.LimbsFolder or Instance.new("Folder")

local PlayersService = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local LocalPlayer = PlayersService.LocalPlayer
local LimbsFolder = getgenv().LimbExtenderGlobalData.LimbsFolder
local Sense = getgenv().LimbExtenderGlobalData.Sense

Sense.teamSettings.enemy.enabled = true
Sense.teamSettings.enemy.box = true
Sense.teamSettings.enemy.healthText = true

local function getPlayers(func)
    for _, player in pairs(PlayersService:GetPlayers()) do
        func(player)
    end
end

local function saveOriginalLimbProperties(limb)
    if not getgenv().LimbExtenderGlobalData[limb] then
        getgenv().LimbExtenderGlobalData[limb] = {Size = limb.Size, Transparency = limb.Transparency, CanCollide = limb.CanCollide, Massless = limb.Massless}
    end
end

local function restoreLimbProperties(character)
    local limb = character:FindFirstChild(rawSettings.TARGET_LIMB)
    local storedProperties = getgenv().LimbExtenderGlobalData[limb]


    if storedProperties then
        limb.Size, limb.Transparency, limb.CanCollide, limb.Massless = storedProperties.Size, storedProperties.Transparency, storedProperties.CanCollide, storedProperties.Massless
        getgenv().LimbExtenderGlobalData[limb] = nil
        local visualizer = LimbsFolder:FindFirstChild(limb.Parent.Name)
        if visualizer then visualizer:Destroy() end
    end

    if getgenv().LimbExtenderGlobalData.LastLimbName and getgenv().LimbExtenderGlobalData.LastLimbName ~= rawSettings.TARGET_LIMB then
        local lastLimb = character:FindFirstChild(getgenv().LimbExtenderGlobalData.LastLimbName)
        if lastLimb then
            local lastStoredProperties = getgenv().LimbExtenderGlobalData[lastLimb]
            if lastStoredProperties then
                lastLimb.Size, lastLimb.Transparency, lastLimb.CanCollide, lastLimb.Massless = lastStoredProperties.Size, lastStoredProperties.Transparency, lastStoredProperties.CanCollide, lastStoredProperties.Massless
                getgenv().LimbExtenderGlobalData[lastLimb] = nil
                local visualizer = LimbsFolder:FindFirstChild(lastLimb.Parent.Name)
                if visualizer then visualizer:Destroy() end
            end
        end
    end
end

local function applyLimbHighlight(limb)
    local highlightInstance = limb:FindFirstChild("LimbHighlight") or Instance.new("Highlight", limb)
    highlightInstance.Name = "LimbHighlight"
    highlightInstance.DepthMode = rawSettings.DEPTH_MODE == 1 and Enum.HighlightDepthMode.AlwaysOnTop or Enum.HighlightDepthMode.Occluded
    highlightInstance.FillColor = rawSettings.HIGHLIGHT_FILL_COLOR
    highlightInstance.FillTransparency = rawSettings.HIGHLIGHT_FILL_TRANSPARENCY
    highlightInstance.OutlineColor = rawSettings.HIGHLIGHT_OUTLINE_COLOR
    highlightInstance.OutlineTransparency = rawSettings.HIGHLIGHT_OUTLINE_TRANSPARENCY
end

local function createVisualizer(limb)
    if limb.Parent then 
        local visualizer = LimbsFolder:FindFirstChild(limb.Parent.Name) or Instance.new("Part")
        visualizer.Size = Vector3.new(rawSettings.LIMB_SIZE, rawSettings.LIMB_SIZE, rawSettings.LIMB_SIZE)
        visualizer.Transparency = rawSettings.LIMB_TRANSPARENCY
        visualizer.CanCollide = rawSettings.LIMB_CAN_COLLIDE
        visualizer.Anchored, visualizer.Massless = false, true
        visualizer.Name, visualizer.Color = limb.Parent.Name, limb.Color
        visualizer.CFrame = limb.CFrame
        visualizer.Parent = LimbsFolder

        local weld = visualizer:FindFirstChild("WeldConstraint") or Instance.new("WeldConstraint")
        weld.Part0, weld.Part1 = limb, visualizer
        weld.Parent = visualizer

        if rawSettings.USE_HIGHLIGHT then
            applyLimbHighlight(visualizer)
        end
    end
end

local function modifyTargetLimb(character)
    local limb = character:WaitForChild(rawSettings.TARGET_LIMB, 1)
    if limb then
        saveOriginalLimbProperties(limb)
        limb.Transparency, limb.CanCollide, limb.Size, limb.Massless = 1, false, Vector3.new(rawSettings.LIMB_SIZE, rawSettings.LIMB_SIZE, rawSettings.LIMB_SIZE), true
        createVisualizer(limb)
    end
end

local function processCharacterLimb(character)
    task.spawn(function()
        local alive = false
        local waited = 0
        while not character:FindFirstChild("Humanoid") and character:FindFirstChild(rawSettings.TARGET_LIMB) and waited <= 10 do 
            task.wait(0.1) 
            waited += 0.1 
        end
        if waited <= 10 then alive = true end

        if alive then
            if (rawSettings.TEAM_CHECK and (LocalPlayer.Team == nil or PlayersService:GetPlayerFromCharacter(character).Team ~= LocalPlayer.Team)) or not rawSettings.TEAM_CHECK then
                modifyTargetLimb(character)
            end

            local humanoid = character:WaitForChild("Humanoid")
            local connection = rawSettings.RESTORE_ORIGINAL_LIMB_ON_DEATH and humanoid.HealthChanged or humanoid.Died
            getgenv().LimbExtenderGlobalData[character.Name .. " OnDeath"] = connection:Connect(function(health)
                if health and health <= 0 then restoreLimbProperties(character) end
            end)
        end
    end)
end

local function onPlayerRemoved(player)
    if player.Character then restoreLimbProperties(player.Character) end
    if getgenv().LimbExtenderGlobalData[player] then
        for _, connection in pairs(getgenv().LimbExtenderGlobalData[player]) do 
            connection:Disconnect()
        end
        getgenv().LimbExtenderGlobalData[player] = nil
    end
end

local function LocalTransparencyModifier(part)
    getgenv().LimbExtenderGlobalData[part.Name .. " LocalTransparencyModifier"] = part:GetPropertyChangedSignal("LocalTransparencyModifier"):Connect(function()
        part.LocalTransparencyModifier = 0
    end)

    part.LocalTransparencyModifier = 0
end

local function playerHandler(player)
    onPlayerRemoved(player)
    getgenv().LimbExtenderGlobalData[player] = {}
    getgenv().LimbExtenderGlobalData[player]["CharacterAdded"] = player.CharacterAdded:Connect(function(character)
        if player == LocalPlayer then
            LimbsFolder.Parent = character
            getgenv().LimbExtenderGlobalData[player]["TeamChanged"] = player:GetPropertyChangedSignal("Team"):Connect(function()
                task.spawn(function()
                    getPlayers(playerHandler)
                end)
            end)
        else
            getgenv().LimbExtenderGlobalData[player]["TeamChanged"] = player:GetPropertyChangedSignal("Team"):Connect(function()
                playerHandler(player)
            end)

            if rawSettings.FORCEFIELD_CHECK then
                getgenv().LimbExtenderGlobalData[player]["ForceFieldAdded"] = character.ChildAdded:Connect(function(child)
                    if child:IsA("ForceField") then restoreLimbProperties(character) end
                end)
                getgenv().LimbExtenderGlobalData[player]["ForceFieldRemoved"] = character.ChildRemoved:Connect(function(child)
                    if child:IsA("ForceField") then processCharacterLimb(character) end
                end)
                restoreLimbProperties(character)
                processCharacterLimb(character)
            else
                restoreLimbProperties(character)
                processCharacterLimb(character)
            end
        end
    end)

    getgenv().LimbExtenderGlobalData[player]["CharacterRemoving"] = player.CharacterRemoving:Connect(function(character)
        if player == LocalPlayer then LimbsFolder.Parent = workspace else restoreLimbProperties(character) end
    end)

    if player.Character then
        if player == LocalPlayer then
            LimbsFolder.Parent = player.Character
        else
            processCharacterLimb(player.Character)
        end
    end
end

local function FolderProtection(child, parent)
    if not parent and child:IsA("Folder") then
        warn("LimbFolder was deleted! Recreating...")
        getgenv().LimbExtenderGlobalData.LimbsFolder = Instance.new("Folder")
        LimbsFolder = getgenv().LimbExtenderGlobalData.LimbsFolder
        startProcess()
    end
end

local function endProcess(specialProcess)
    for name, connection in pairs(getgenv().LimbExtenderGlobalData) do
        if typeof(connection) == "RBXScriptConnection" and name ~= "FolderProtection" then
            connection:Disconnect()
            getgenv().LimbExtenderGlobalData[name] = nil
        end
    end

    getPlayers(onPlayerRemoved)

    if Sense._hasLoaded then
        Sense.Unload()
    end

    if specialProcess == "DetectInput" then 
        getgenv().LimbExtenderGlobalData.InputBeganConnection = UserInputService.InputBegan:Connect(handleKeyInput)
    elseif specialProcess == "FullKill" then
        getgenv().LimbExtenderGlobalData = {}
        script:Destroy()
    end
end

local function startProcess()
    endProcess()
    getgenv().LimbExtenderGlobalData.LastLimbName = rawSettings.TARGET_LIMB
    getgenv().LimbExtenderGlobalData.LimbsFolderChildAdded = LimbsFolder.ChildAdded:Connect(LocalTransparencyModifier)
    getgenv().LimbExtenderGlobalData.InputBeganConnection = UserInputService.InputBegan:Connect(handleKeyInput)
    getgenv().LimbExtenderGlobalData.PlayerAddedConnection = PlayersService.PlayerAdded:Connect(playerHandler)
    getgenv().LimbExtenderGlobalData.PlayerRemovingConnection = PlayersService.PlayerRemoving:Connect(onPlayerRemoved)
    getgenv().LimbExtenderGlobalData.FolderProtection = LimbsFolder.AncestryChanged:Connect(FolderProtection)

    if rawSettings.ESP and not Sense._hasLoaded then
        Sense.Load()
    end

    getPlayers(playerHandler)
end

local LimbExtender = setmetatable({}, {
    __index = rawSettings,
    __newindex = function(_, key, value)
        if rawSettings[key] ~= value then
            rawSettings[key] = value
            if getgenv().LimbExtenderGlobalData.IsProcessActive then
                startProcess()
            end
        end
    end
})

function handleKeyInput(input, isProcessed)
    if isProcessed or input.KeyCode ~= Enum.KeyCode[rawSettings.TOGGLE] then return end
    getgenv().LimbExtenderGlobalData.IsProcessActive = not getgenv().LimbExtenderGlobalData.IsProcessActive
    if getgenv().LimbExtenderGlobalData.IsProcessActive then
        startProcess()
    else
        endProcess("DetectInput")
    end
end

if getgenv().LimbExtenderGlobalData.IsProcessActive == nil then
    getgenv().LimbExtenderGlobalData.IsProcessActive = false
end

if getgenv().LimbExtenderGlobalData.IsProcessActive then
    startProcess()
else
    endProcess("DetectInput")
end

getgenv().LimbExtenderGlobalData.LimbExtenderTerminateOldProcess = endProcess

for _, part in LimbsFolder:GetChildren() do
    LocalTransparencyModifier(part)
end

return LimbExtender
