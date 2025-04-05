local Players = game:GetService("Players")

local le = loadstring(game:HttpGet('https://raw.githubusercontent.com/AAPVdev/scripts/refs/heads/main/LimbExtenderBETA.lua'))()
local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

local limbExtenderData = getgenv().limbExtenderData

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

local Window = Rayfield:CreateWindow({
    Name = "SERENE",
    Icon = "scroll-text",

    LoadingTitle = "Loading Rayfield UI",
    LoadingSubtitle = ChosenMessage,

    Theme = "DarkBlue",

    DisableRayfieldPrompts = true,
        
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

le.LISTEN_FOR_INPUT = false

local Settings = Window:CreateTab("Settings", "scale-3d")

local SettingsSection = Settings:CreateSection('Limb Extender Settings')

local function createOption(params)
    local methodName = 'Create' .. params.type  
    local method = params.tab[methodName]
    
    if type(method) == 'function' then
        method(params.tab, {
            Name = params.name,
            SectionParent = params.section,
            CurrentValue = params.value,
            Flag = params.flag,
            Callback = function(Value)
                le[params.flag] = Value
            end,
        })
    else
        warn("Method " .. methodName .. " not found in params.tab")
    end
end

local ModifyLimbs = Settings:CreateToggle({
    Name = "Modify Limbs",
    SectionParent = SettingsSection,
    CurrentValue = false,
    Flag = "ModifyLimbs",
    Callback = function()
        le.toggleState()
    end,
})

Settings:CreateDivider()

local toggleSettings = {
    {
        type = "Toggle",
        name = "Team Check",
        flag = "TEAM_CHECK",
        tab = Settings,
        section = SettingsSection,
        value = true
    },
    {
        type = "Toggle",
        name = "ForceField Check",
        flag = "FORCEFIELD_CHECK",
        tab = Settings,
        section = SettingsSection,
        value = true
    },
    {
        type = "Toggle",
        name = "Limb Collisions",
        flag = "LIMB_CAN_COLLIDE",
        tab = Settings,
        section = SettingsSection,
        value = false
    },
}

for _, setting in pairs(toggleSettings) do
    createOption(setting)
end

Settings:CreateSlider({
    SectionParent = SettingsSection,
    Name = "Limb Size",
    Range = {5, 50},
    Increment = 5,
    CurrentValue = 10,
    Flag = "LimbSize",
    Callback = function(Value)
        le.LIMB_SIZE = Value
    end,
})

Settings:CreateKeybind({
    Name = "Toggle Keybind",
    CurrentKeybind = le.TOGGLE,
    HoldToInteract = false,
    SectionParent = SettingsSection,
    Flag = "ToggleKeybind",
    Callback = function()
        ModifyLimbs:Set(not limbExtenderData.running)
    end,
})

Rayfield:LoadConfiguration()
