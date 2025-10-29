local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

local LimbExtender = loadstring(game:HttpGet('https://raw.githubusercontent.com/AAPVdev/scripts/refs/heads/main/LimbExtender.lua'))()

local le = LimbExtender({
    LISTEN_FOR_INPUT = false, 
})

local limbExtenderData = getgenv().limbExtenderData

local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

local Messages = {
    "jejemon!",
    "i have the highest grades in math",
    "hi krislyn",
    "fucking shit up",
    "not my fault",
    "what the fuck",
    "arse anal",
    "what color is your executor?",
    "dont say cuss words",
    "california gurrls",
    "I HATE EXPLOITERS! 😡",
    "builderman is my dad",
    "plopyninja is my first account",
    "shawtyy"
}
local ChosenMessage = Messages[math.random(1, #Messages)]

local Window = Rayfield:CreateWindow({
    Name = "AXIOS",
    Icon = 107904589783906,
    LoadingTitle = "AXIOS",
    LoadingSubtitle = ChosenMessage,
    Theme = "Default",
    DisableRayfieldPrompts = true,
    ConfigurationSaving = {
        Enabled = true,
        FolderName = "LimbExtenderConfigs",
        FileName = "Configuration"
    },
})

local Settings = Window:CreateTab("Limbs", "scale-3d")
local Highlights = Window:CreateTab("Highlights", "eye")
local Target = Window:CreateTab("Target", "crosshair")
local Themes = Window:CreateTab("Themes", "palette")

local function createOption(params)
    local methodName = 'Create' .. params.method
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
                le:Set(params.flag, Value)
            end,
        })
    else
        warn("Method " .. methodName .. " not found in tab")
    end
end

local ModifyLimbs = Settings:CreateToggle({
    Name = "Modify Limbs",
    CurrentValue = false,
    Flag = "ModifyLimbs",
    Callback = function(Value)
        if Value then
            le:Start()
        else
            le:Stop()
        end
    end,
})

Settings:CreateDivider()

local UseHighlights = Highlights:CreateToggle({
    Name = "Use Highlights",
    CurrentValue = le:Get("USE_HIGHLIGHT"),
    Flag = "USE_HIGHLIGHT",
    Callback = function(Value)
        le:Set("USE_HIGHLIGHT", Value)
    end,
})

Highlights:CreateDivider()

local toggleSettings = {
    {
        method = "Toggle",
        name = "Team Check",
        flag = "TEAM_CHECK",
        tab = Settings,
        value = le:Get("TEAM_CHECK"),
    },
    {
        method = "Toggle",
        name = "ForceField Check",
        flag = "FORCEFIELD_CHECK",
        tab = Settings,
        value = le:Get("FORCEFIELD_CHECK"),
    },
    {
        method = "Toggle",
        name = "Limb Collisions",
        flag = "LIMB_CAN_COLLIDE",
        tab = Settings,
        value = le:Get("LIMB_CAN_COLLIDE"),
    },
    {
        method = "Slider",
        name = "Limb Transparency",
        flag = "LIMB_TRANSPARENCY",
        tab = Settings,
        range = {0, 1},
        increment = 0.1,
        value = le:Get("LIMB_TRANSPARENCY"),
    },
    {
        method = "Slider",
        name = "Limb Size",
        flag = "LIMB_SIZE",
        tab = Settings,
        range = {5, 50},
        increment = 0.5,
        value = le:Get("LIMB_SIZE"),
    },
    {
        method = "Dropdown",
        name = "Depth Mode",
        flag = "DEPTH_MODE",
        options = {"Occluded","AlwaysOnTop"},
        currentOption = {le:Get("DEPTH_MODE")},
        multipleOptions = false,
        tab = Highlights,
    },
    {
        method = "ColorPicker",
        name = "Outline Color",
        flag = "HIGHLIGHT_OUTLINE_COLOR",
        tab = Highlights,
        color = le:Get("HIGHLIGHT_OUTLINE_COLOR"),
    },
    {
        method = "ColorPicker",
        name = "Fill Color",
        flag = "HIGHLIGHT_FILL_COLOR",
        tab = Highlights,
        color = le:Get("HIGHLIGHT_FILL_COLOR"),
    },
    {
        method = "Slider",
        name = "Fill Transparency",
        flag = "HIGHLIGHT_FILL_TRANSPARENCY",
        tab = Highlights,
        range = {0, 1},
        increment = 0.1,
        value = le:Get("HIGHLIGHT_FILL_TRANSPARENCY"),
    },
    {
        method = "Slider",
        name = "Outline Transparency",
        flag = "HIGHLIGHT_OUTLINE_TRANSPARENCY",
        tab = Highlights,
        range = {0, 1},
        increment = 0.1,
        value = le:Get("HIGHLIGHT_OUTLINE_TRANSPARENCY"),
    },
}

for _, setting in pairs(toggleSettings) do
    createOption(setting)
    setting.tab:CreateDivider()
end

Settings:CreateKeybind({
    Name = "Toggle Keybind",
    CurrentKeybind = le:Get("TOGGLE"),
    HoldToInteract = false,
    Callback = function()
        if limbExtenderData and limbExtenderData.running then
            le:Stop()
            ModifyLimbs:Set(false)
        else
            le:Start()
            ModifyLimbs:Set(true)
        end
    end,
})

Highlights:CreateButton({
    Name = "Delete All Game Highlights",
    Callback = function()
        for _, v in ipairs(game:GetDescendants()) do
            if v:IsA("Highlight") and v.Parent.Name ~= "Limb Extender Highlights Folder" then
                v:Destroy()
            end
        end
    end,
})

local limbs = {}
local TargetLimb = Target:CreateDropdown({
    Name = "Target Limb",
    Options = {},
    CurrentOption = {le:Get("TARGET_LIMB")},
    MultipleOptions = false,
    Flag = "TARGET_LIMB",
    Callback = function(Options)
        le:Set("TARGET_LIMB", Options[1])
    end,
})

local function characterAdded(Character)
    local function addChild(child)
        if child:IsA("BasePart") and not table.find(limbs, child.Name) then
            table.insert(limbs, child.Name)
            table.sort(limbs)
            TargetLimb:Refresh(limbs)
        end
    end

    Character.ChildAdded:Connect(addChild)
    for _, child in ipairs(Character:GetChildren()) do
        addChild(child)
    end
end

LocalPlayer.CharacterAdded:Connect(characterAdded)
if LocalPlayer.Character then
    characterAdded(LocalPlayer.Character)
end

Rayfield:LoadConfiguration()
