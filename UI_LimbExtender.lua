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

local Settings = Window:CreateTab("Limbs", "scale-3d")
local Highlights = Window:CreateTab("Highlights", "eye")

local function createOption(params)
    local methodName = 'Create' .. params.type  
    local method = params.tab[methodName]
    
    if type(method) == 'function' then
        method(params.tab, {
            Name = params.name,
            SectionParent = params.section,
            CurrentValue = params.value,
            Flag = params.flag,
            Options = params.options,
            CurrentOption = params.currentOption,
            MultipleOptions = params.multipleOptions,
            Range = params.range,
            Color = params.color,
            Increment = params.increment,
            Callback = function(Value)
                if params.multipleOptions == false then
                    Value = Value[1]
                end
                le[params.flag] = Value
            end,
        })
    else
        warn("Method " .. methodName .. " not found in params.tab")
    end
end

local ModifyLimbs = Settings:CreateToggle({
    Name = "Modify Limbs",
    SectionParent = nil,
    CurrentValue = false,
    Flag = "ModifyLimbs",
    Callback = function(Value)
        le.toggleState(Value)
    end,
})

Settings:CreateDivider()

local toggleSettings = {
    {
        type = "Toggle",
        name = "Team Check",
        flag = "TEAM_CHECK",
        tab = Settings,
        section = nil,
        value = le.TEAM_CHECK,
        createDivider = false,
    },
    {
        type = "Toggle",
        name = "ForceField Check",
        flag = "FORCEFIELD_CHECK",
        tab = Settings,
        section = nil,
        value = le.FORCEFIELD_CHECK,
        createDivider = false,
    },
    {
        type = "Toggle",
        name = "Limb Collisions",
        flag = "LIMB_CAN_COLLIDE",
        tab = Settings,
        section = nil,
        value = le.LIMB_CAN_COLLIDE,
        createDivider = false,
    },
    {
        type = "Slider",
        name = "Limb Transparency",
        flag = "LIMB_TRANSPARENCY",
        tab = Settings,
        range = {0, 1},
        increment = 0.1,
        section = nil,
        value = le.LIMB_TRANSPARENCY,
        createDivider = false,
    },
    {
        type = "Toggle",
        name = "Use Highlights",
        flag = "USE_HIGHLIGHT",
        tab = Highlights,
        section = nil,
        value = le.USE_HIGHLIGHT,
        createDivider = true,
    },
    {
        type = "Dropdown",
        name = "Depth Mode",
        flag = "DEPTH_MODE",
        options = {"Occluded","AlwaysOnTop"},
        currentOption = {le.DEPTH_MODE},
        multipleOptions = false,
        tab = Highlights,
        section = nil,
        createDivider = false,
    },
    {
        type = "ColorPicker",
        name = "Outline Color",
        flag = "HIGHLIGHT_OUTLINE_COLOR",
        tab = Highlights,
        section = nil,
        color = le.HIGHLIGHT_OUTLINE_COLOR,
        createDivider = false,
    },
    {
        type = "ColorPicker",
        name = "Fill Color",
        flag = "HIGHLIGHT_FILL_COLOR",
        tab = Highlights,
        section = nil,
        color = le.HIGHLIGHT_FILL_COLOR,
        createDivider = false,
    },
    {
        type = "Slider",
        name = "Fill Transparency",
        flag = "HIGHLIGHT_FILL_TRANSPARENCY",
        tab = Highlights,
        range = {0, 1},
        increment = 0.1,
        section = nil,
        value = le.HIGHLIGHT_FILL_TRANSPARENCY,
        createDivider = false,
    },
    {
        type = "Slider",
        name = "Outline Transparency",
        flag = "HIGHLIGHT_OUTLINE_TRANSPARENCY",
        tab = Highlights,
        range = {0, 1},
        increment = 0.1,
        section = nil,
        value = le.HIGHLIGHT_OUTLINE_TRANSPARENCY,
        createDivider = false,
    },
}

for _, setting in pairs(toggleSettings) do
    createOption(setting)
    if setting.createDivider then
        setting.tab:CreateDivider()
    end
end

Settings:CreateSlider({
    SectionParent = nil,
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
    SectionParent = nil,
    Flag = "ToggleKeybind",
    Callback = function()
        ModifyLimbs:Set(not limbExtenderData.running)
    end,
})

Rayfield:LoadConfiguration()
