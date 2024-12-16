local Players = game:GetService("Players")

local he = loadstring(game:HttpGet('https://raw.githubusercontent.com/AAPVdev/scripts/refs/heads/main/HeadExtender.lua'))()

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

local function createToggle(params)
    params.tab:CreateToggle({
        Name = params.name,
        SectionParent = params.section,
        CurrentValue = params.value,
        Flag = params.flag,
        Callback = function(Value)
            he[params.flag] = Value
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
            he.startProcess()
             getgenv().LimbExtenderGlobalData.InputBeganConnection:Disconnect()
        else
            he.endProcess()
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

for _, setting in pairs(toggleSettings) do
    createToggle(setting)
end

Limb_Extender:CreateSlider({
    SectionParent = SettingsSection,
    Name = "Limb Size",
    Range = {5, 50},
    Increment = 5,
    CurrentValue = 10,
    Flag = "LimbSize",
    Callback = function(Value)
        he.LIMB_SIZE = Value
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

getgenv().LimbExtenderGlobalData.InputBeganConnection:Disconnect()
Rayfield:LoadConfiguration()
