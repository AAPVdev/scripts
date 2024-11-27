if getgenv().IsProcessActive and type(getgenv().LimbExtenderGlobalData.LimbExtenderTerminateOldProcess) == "function" then
    getgenv().LimbExtenderGlobalData.LimbExtenderTerminateOldProcess("FullKill")
end

local defaultSettings = {
    TARGET_LIMB = "Head",
    LIMB_SIZE = 10,
    LIMB_TRANSPARENCY = 0.9,
    LIMB_CAN_COLLIDE = false,
    TEAM_CHECK = true,
    FORCEFIELD_CHECK = true,
    RESTORE_ORIGINAL_LIMB_ON_DEATH = true,
    ESP = false,
    USE_HIGHLIGHT = true,
    DEPTH_MODE = 2,
    HIGHLIGHT_FILL_COLOR = Color3.fromRGB(0, 255, 0),
    HIGHLIGHT_FILL_TRANSPARENCY = 0.5,
    HIGHLIGHT_OUTLINE_COLOR = Color3.fromRGB(255, 255, 255),
    HIGHLIGHT_OUTLINE_TRANSPARENCY = 0,
}

getgenv().LimbExtenderSettings = setmetatable(getgenv().LimbExtenderSettings or {}, {__index = defaultSettings})
getgenv().LimbExtenderGlobalData = getgenv().LimbExtenderGlobalData or {}
getgenv().LimbExtenderGlobalData.Sense = getgenv().LimbExtenderGlobalData.Sense or loadstring(game:HttpGet('https://sirius.menu/sense'))()
getgenv().LimbExtenderGlobalData.LimbsFolder = getgenv().LimbExtenderGlobalData.LimbsFolder or Instance.new("Folder")

local Settings = getgenv().LimbExtenderSettings
local PlayersService = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local LocalPlayer = PlayersService.LocalPlayer
local LimbsFolder = getgenv().LimbExtenderGlobalData.LimbsFolder
local Sense = getgenv().LimbExtenderGlobalData.Sense

Sense.teamSettings.enemy.enabled = true
Sense.teamSettings.enemy.box = true
Sense.teamSettings.enemy.healthText = true

local function saveOriginalLimbProperties(limb)
    if not getgenv().LimbExtenderGlobalData[limb] then
        getgenv().LimbExtenderGlobalData[limb] = {Size = limb.Size, Transparency = limb.Transparency, CanCollide = limb.CanCollide, Massless = limb.Massless}
    end
end

local function restoreLimbProperties(character)
    local limb = character:FindFirstChild(Settings.TARGET_LIMB)
    local storedProperties = getgenv().LimbExtenderGlobalData[limb]

    if storedProperties then
        limb.Size, limb.Transparency, limb.CanCollide, limb.Massless = storedProperties.Size, storedProperties.Transparency, storedProperties.CanCollide, storedProperties.Massless
        getgenv().LimbExtenderGlobalData[limb] = nil
        local visualizer = LimbsFolder:FindFirstChild(limb.Parent.Name)
        if visualizer then visualizer:Destroy() end
    end

    if getgenv().LimbExtenderGlobalData.LastLimbName and getgenv().LimbExtenderGlobalData.LastLimbName ~= Settings.TARGET_LIMB then
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
    highlightInstance.DepthMode = Settings.DEPTH_MODE == 1 and Enum.HighlightDepthMode.AlwaysOnTop or Enum.HighlightDepthMode.Occluded
    highlightInstance.FillColor = Settings.HIGHLIGHT_FILL_COLOR
    highlightInstance.FillTransparency = Settings.HIGHLIGHT_FILL_TRANSPARENCY
    highlightInstance.OutlineColor = Settings.HIGHLIGHT_OUTLINE_COLOR
    highlightInstance.OutlineTransparency = Settings.HIGHLIGHT_OUTLINE_TRANSPARENCY
end

local function createVisualizer(limb)
    if limb.Parent then 
        local visualizer = LimbsFolder:FindFirstChild(limb.Parent.Name) or Instance.new("Part")
        visualizer.Size = Vector3.new(Settings.LIMB_SIZE, Settings.LIMB_SIZE, Settings.LIMB_SIZE)
        visualizer.Transparency = Settings.LIMB_TRANSPARENCY
        visualizer.CanCollide = Settings.LIMB_CAN_COLLIDE
        visualizer.Anchored, visualizer.Massless = false, true
        visualizer.Name, visualizer.Color = limb.Parent.Name, limb.Color
        visualizer.CFrame = limb.CFrame
        visualizer.Parent = LimbsFolder

        local weld = visualizer:FindFirstChild("WeldConstraint") or Instance.new("WeldConstraint")
        weld.Part0, weld.Part1 = limb, visualizer
        weld.Parent = visualizer

        if Settings.USE_HIGHLIGHT then
            applyLimbHighlight(visualizer)
        end
    end
end

local function modifyTargetLimb(character)
    local limb = character:WaitForChild(Settings.TARGET_LIMB, 1)
    if limb then
        saveOriginalLimbProperties(limb)
        limb.Transparency, limb.CanCollide, limb.Size, limb.Massless = 1, false, Vector3.new(Settings.LIMB_SIZE, Settings.LIMB_SIZE, Settings.LIMB_SIZE), true
        createVisualizer(limb)
    end
end

local function processCharacterLimb(character)
    task.spawn(function()
        local alive = false
        local waited = 0
        while not character:FindFirstChild("Humanoid") and character:FindFirstChild(Settings.TARGET_LIMB) and waited <= 5 do 
            task.wait(0.1) 
            waited += 0.1 
        end
        if waited < 5 then alive = true end

        if alive then
            if (Settings.TEAM_CHECK and (LocalPlayer.Team == nil or PlayersService:GetPlayerFromCharacter(character).Team ~= LocalPlayer.Team)) or not Settings.TEAM_CHECK then
                modifyTargetLimb(character)
            end

            local humanoid = character:WaitForChild("Humanoid")
            local connection = Settings.RESTORE_ORIGINAL_LIMB_ON_DEATH and humanoid.HealthChanged or humanoid.Died
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

local function endProcess(specialProcess)
    for name, connection in pairs(getgenv().LimbExtenderGlobalData) do
        if typeof(connection) == "RBXScriptConnection" and name ~= "FolderProtection" then
            connection:Disconnect()
            getgenv().LimbExtenderGlobalData[name] = nil
        end
    end

    for _, player in pairs(PlayersService:GetPlayers()) do
        onPlayerRemoved(player)
    end

    if Sense._hasLoaded then
        Sense.Unload()
    end

    if specialProcess == "FullKill" then
        getgenv().LimbExtenderGlobalData.FolderProtection:Disconnect()
        getgenv().LimbExtenderGlobalData = {}
        script:Destroy()
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
                    for _, Player in pairs(PlayersService:GetPlayers()) do
                        playerHandler(Player)
                    end
                end)
            end)
        else
            getgenv().LimbExtenderGlobalData[player]["TeamChanged"] = player:GetPropertyChangedSignal("Team"):Connect(function()
                playerHandler(player)
            end)

            if Settings.FORCEFIELD_CHECK then
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
        warn("LimbFolder was deleted! Recreating. --Avis LimbExtender")
        getgenv().LimbExtenderGlobalData.LimbsFolder = Instance.new("Folder")
        LimbsFolder = getgenv().LimbExtenderGlobalData.LimbsFolder
        startProcess()
    end
end

function startProcess()
    endProcess()
    getgenv().LimbExtenderGlobalData.LastLimbName = Settings.TARGET_LIMB
    getgenv().LimbExtenderGlobalData.LimbsFolderChildAdded = LimbsFolder.ChildAdded:Connect(LocalTransparencyModifier)
    getgenv().LimbExtenderGlobalData.PlayerAddedConnection = PlayersService.PlayerAdded:Connect(playerHandler)
    getgenv().LimbExtenderGlobalData.PlayerRemovingConnection = PlayersService.PlayerRemoving:Connect(onPlayerRemoved)
    getgenv().LimbExtenderGlobalData.FolderProtection = LimbsFolder.AncestryChanged:Connect(FolderProtection)

    if Settings.ESP and not Sense._hasLoaded then
        Sense.Load()
    end

    for _, player in pairs(PlayersService:GetPlayers()) do
        playerHandler(player)
    end
end

if getgenv().LimbExtenderGlobalData.IsProcessActive then
    startProcess()
else
    endProcess()
end

if getgenv().LimbExtenderGlobalData.IsProcessActive == nil then
    getgenv().LimbExtenderGlobalData.IsProcessActive = false
end

getgenv().LimbExtenderGlobalData.LimbExtenderTerminateOldProcess = endProcess

for _, part in LimbsFolder:GetChildren() do
    LocalTransparencyModifier(part)
end

local Messages = {
    "fucking shit up",
    "i love you ❤",
    "prolapsed anus",
    "is it joever?",
    "im banned",
    "my penis has warts",
    "california gurrls",
    "I HATE EXPLOITERS! 😡",
    "builderman is my dad",
    "im on that good kush",
    "big NERD 🤓"
}

local ChosenMessage = Messages[math.random(1, #Messages)]

local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()
local Window = Rayfield:CreateWindow({
    Name = "AAPVdev's Limb Extender",
    Icon = "scroll-text",

    LoadingTitle = "Loading AAPVdev's Limb Extender",
    LoadingSubtitle = ChosenMessage,

    Theme = "DarkBlue",

    ConfigurationSaving = {
        Enabled = true,
        FolderName = "LimbExtenderConfigs",
        FileName = "Configuration"
    },
    KeySystem = false,
    KeySettings = {
        Title = "",
        Subtitle = "",
        Note = "",
        FileName = "",
        SaveKey = false,
        GrabKeyFromSite = false,
        Key = {""}
    }
})


local Limb_Extender = Window:CreateTab("Limb Extender", "scale-3d")
local Visual = Window:CreateTab("Visual", "eye")

local SettingsSection = Limb_Extender:CreateSection('Limb Extender Settings')

local function updatePlayers()
    if getgenv().LimbExtenderGlobalData.IsProcessActive then
        for _, player in pairs(PlayersService:GetPlayers()) do
            playerHandler(player)
        end
    end
end

local function createToggle(params, callback)
    params.tab:CreateToggle({
        Name = params.name,
        SectionParent = params.section,
        CurrentValue = params.value,
        Flag = params.flag,
        Callback = function(Value)
            getgenv().LimbExtenderSettings[params.flag] = Value
            callback(Value)
        end,
    })
end

local ModifyLimbs = Limb_Extender:CreateToggle({
    Name = "Modify Limbs",
    SectionParent = SettingsSection,
    CurrentValue = false,
    Flag = "ModifyLimbs",
    Callback = function(Value)
        getgenv().LimbExtenderGlobalData.IsProcessActive = Value
        if Value then
            startProcess()
        else
            endProcess()
        end
    end,
})

Limb_Extender:CreateDivider()

local toggleSettings = {
    {
        name = "Team Check",
        flag = "TEAM_CHECK",
        tab = Limb_Extender,
        section = SettingsSection,
        value = true
    },
    {
        name = "ForceField Check",
        flag = "FORCEFIELD_CHECK",
        tab = Limb_Extender,
        section = SettingsSection,
        value = true
    },
    {
        name = "Limb Collisions",
        flag = "LIMB_CAN_COLLIDE",
        tab = Limb_Extender,
        section = SettingsSection,
        value = false
    },
    {
        name = "Restore Original Limb on Death", 
        flag = "RESTORE_ORIGINAL_LIMB_ON_DEATH",
        tab = Limb_Extender, 
        section = SettingsSection,
        value = true
    },
    {
        name = "ESP", 
        flag = "ESP",
        tab = Visual, 
        section = nil,
        value = false
    },
}

for _, setting in ipairs(toggleSettings) do
    if setting.name == "ESP" then
        createToggle(setting, function()
            if getgenv().LimbExtenderGlobalData.IsProcessActive then
                startProcess()
            end
        end)
    else
        createToggle(setting, function(Value)
            updatePlayers()
        end)
    end
end

Limb_Extender:CreateSlider({
    SectionParent = SettingsSection,
    Name = "Limb Size",
    Range = {5, 50},
    Increment = 5,
    CurrentValue = 10,
    Flag = "LimbSize",
    Callback = function(Value)
        getgenv().LimbExtenderSettings.LIMB_SIZE = Value
        updatePlayers()
    end,
})

Limb_Extender:CreateKeybind({
    Name = "Toggle Keybind",
    CurrentKeybind = "Q",
    HoldToInteract = false,
    SectionParent = SettingsSection,
    Flag = "ToggleKeybind",
    Callback = function()
        ModifyLimbs:Set(not getgenv().LimbExtenderGlobalData.IsProcessActive)
    end,
})

Rayfield:LoadConfiguration()