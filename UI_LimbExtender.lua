You said:
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

local Sense = loadstring(game:HttpGet('https://raw.githubusercontent.com/jensonhirst/Sirius/request/library/sense/source.lua'))()
local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()
local le = loadstring(game:HttpGet('https://raw.githubusercontent.com/AAPVdev/scripts/refs/heads/main/LimbExtender.lua'))()

le.LISTEN_FOR_INPUT = false
le.USE_HIGHLIGHT = false 

local limbs = {}

local limbExtenderData = getgenv().limbExtenderData

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
local SenseTab = Window:CreateTab("Sense")
local Target = Window:CreateTab("Target", "crosshair")
local Themes = Window:CreateTab("Themes", "palette")

Sense.teamSettings.enemy.enabled = true
Sense.teamSettings.friendly.enabled = true

local function changeSetting(name, value)
    for _, team in ipairs({'enemy', 'friendly'}) do
        Sense.teamSettings[team][name] = value
    end
end

local tabs = {
    ['Team Settings'] = {
        items = {
            {type = 'Toggle', name = 'Hide Team', default = false, flag = 'HideTeam', callback = function(x)
                Sense.teamSettings.friendly.enabled = not x
            end},
            {type = 'ColorPicker', name = 'Team Color', default = Color3.fromRGB(0,255,0), flag = 'TeamColor', callback = function(c)
                for _, prop in ipairs({'boxColor','box3dColor','offScreenArrowColor','tracerColor'}) do
                    Sense.teamSettings.friendly[prop] = {c,1}
                end
            end},
            {type = 'ColorPicker', name = 'Enemy Color', default = Color3.fromRGB(255,0,0), flag = 'EnemyColor', callback = function(c)
                for _, prop in ipairs({'boxColor','box3dColor','offScreenArrowColor','tracerColor'}) do
                    Sense.teamSettings.enemy[prop] = {c,1}
                end
            end},
        }
    },
    ['Box'] = {
        items = {
            {type='Toggle', name='Boxes Enabled', default=false, flag='Boxes', prop='box'},
            {type='Toggle', name='Boxes Outline', default=true, flag='BoxesOutlined', prop='boxOutline'},
            {type='Toggle', name='Boxes Fill', default=false, flag='BoxesFilled', prop='boxFill'},
            {type='ColorPicker', name='Team Fill Color', default=Color3.fromRGB(0,255,0), flag='TeamFillColor', team='friendly', prop='boxFillColor', alpha=0.5},
            {type='ColorPicker', name='Enemy Fill Color', default=Color3.fromRGB(255,0,0), flag='EnemyFillColor', team='enemy', prop='boxFillColor', alpha=0.5},
            {type='Toggle', name='3D Boxes', default=false, flag='3DBoxes', prop='box3d'},
        }
    },
    ['Health'] = {
        items = {
            {type='Toggle', name='HealthBar Enabled', default=false, flag='HealthBar', prop='healthBar'},
            {type='ColorPicker', name='Health Color', default=Color3.fromRGB(0,255,0), flag='HealthColor', prop='healthyColor'},
            {type='ColorPicker', name='Dying Color', default=Color3.fromRGB(255,0,0), flag='DyingColor', prop='dyingColor'},
            {type='Toggle', name='HealthBar Outline', default=true, flag='HBsOutlined', prop='healthBarOutline'},
        }
    },
    ['Tracer'] = {
        items = {
            {type='Toggle', name='Tracers Enabled', default=false, flag='Tracers', prop='tracer'},
            {type='Toggle', name='Tracers Outline', default=true, flag='TracersOutlined', prop='tracerOutline'},
            {type='Dropdown', name='Tracer Origin', options={'Bottom','Top','Mouse'}, default='Bottom', flag='TracerOrigin', prop='tracerOrigin'},
        }
    },
    ['Tag'] = {
        items = {
            {type='Toggle', name='Show Name', default=false, flag='Names', prop='name'},
            {type='Toggle', name='Name Outline', default=true, flag='NamesOutlined', prop='nameOutline'},
            {type='Toggle', name='Show Distance', default=false, flag='Distances', prop='distance'},
            {type='Toggle', name='Distance Outline', default=true, flag='DistancesOutlined', prop='distanceOutline'},
            {type='Toggle', name='Show Health Text', default=false, flag='Health', prop='healthText'},
            {type='Toggle', name='Health Text Outline', default=true, flag='HealthsOutlined', prop='healthOutline'},
        }
    },
    ['Chams'] = {
        items = {
            {type='Toggle', name='Chams Enabled', default=false, flag='Chams', prop='chams'},
            {type='Toggle', name='Chams Visible Only', default=false, flag='ChamsVisOnly', prop='chamsVisibleOnly'},
            {type='ColorPicker', name='Team Chams Fill', default=Color3.new(0.2,0.2,0.2), flag='TeamFillChams', team='friendly', prop='chamsFillColor', alpha=0.5},
            {type='ColorPicker', name='Team Chams Outline', default=Color3.new(0,1,0), flag='TeamOutlineChams', team='friendly', prop='chamsOutlineColor', alpha=0},
            {type='ColorPicker', name='Enemy Chams Fill', default=Color3.new(0.2,0.2,0.2), flag='EnemyFillChams', team='enemy', prop='chamsFillColor', alpha=0.5},
            {type='ColorPicker', name='Enemy Chams Outline', default=Color3.new(1,0,0), flag='EnemyOutlineChams', team='enemy', prop='chamsOutlineColor', alpha=0},
        }
    },
    ['Off Screen Arrow'] = {
        items = {
            {type='Toggle', name='Off Screen Arrow Enabled', default=false, flag='OSA', prop='offScreenArrow'},
            {type='Slider', name='Arrow Size', range={15,50}, default=15, flag='OSASize', prop='offScreenArrowSize'},
            {type='Slider', name='Arrow Radius', range={150,360}, default=150, flag='OSARadius', prop='offScreenArrowRadius'},
            {type='Toggle', name='Arrow Outline', default=true, flag='OSAOutlined', prop='offScreenArrowOutline'},
        }
    },
    ['Weapon'] = {
        items = {
            {type='Toggle', name='Weapon Enabled', default=false, flag='Weapons', prop='weapon'},
            {type='Toggle', name='Weapon Outline', default=true, flag='WeaponOutlined', prop='weaponOutline'},
        }
    }
}

for sectionName, sectionData in pairs(tabs) do
    SenseTab:CreateSection(sectionName)
    for _, item in ipairs(sectionData.items) do
        if item.type == 'Toggle' then
            SenseTab:CreateToggle({ Name = item.name, CurrentValue = item.default, Flag = item.flag,
                Callback = function(v) changeSetting(item.prop, v) end })
        elseif item.type == 'ColorPicker' then
            SenseTab:CreateColorPicker({ Name = item.name, Color = item.default, Flag = item.flag,
                Callback = function(c)
                    local a = item.alpha or 1
                    if item.team then
                        Sense.teamSettings[item.team][item.prop] = {c, a}
                    else
                        changeSetting(item.prop, {c, a})
                    end
                end
            })
        elseif item.type == 'Dropdown' then
            SenseTab:CreateDropdown({ Name = item.name, Options = item.options, CurrentOption = item.default, Flag = item.flag,
                Callback = function(opt) changeSetting(item.prop, opt) end })
        elseif item.type == 'Slider' then
            SenseTab:CreateSlider({ Name = item.name, Range = item.range, CurrentValue = item.default, Flag = item.flag,
                Callback = function(val) changeSetting(item.prop, val) end })
        end
    end
end

Sense.Load()

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
        method = "Toggle",
        name = "Team Check",
        flag = "TEAM_CHECK",
        tab = Settings,
        section = nil,
        value = le.TEAM_CHECK,
        createDivider = false,
    },
    {
        method = "Toggle",
        name = "ForceField Check",
        flag = "FORCEFIELD_CHECK",
        tab = Settings,
        section = nil,
        value = le.FORCEFIELD_CHECK,
        createDivider = false,
    },
    {
        method = "Toggle",
        name = "Limb Collisions",
        flag = "LIMB_CAN_COLLIDE",
        tab = Settings,
        section = nil,
        value = le.LIMB_CAN_COLLIDE,
        createDivider = true,
    },
    {
        method = "Slider",
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
        method = "Slider",
        name = "Limb Size",
        flag = "LIMB_SIZE",
        tab = Settings,
        range = {5, 50},
        increment = 5,
        section = nil,
        value = le.LIMB_SIZE,
        createDivider = true,
    },
}

for _, setting in pairs(toggleSettings) do
    createOption(setting)
    if setting.createDivider then
        setting.tab:CreateDivider()
    end
end

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

local TargetLimb = Target:CreateDropdown({
   Name = "Target Limb",
   Options = {},
   CurrentOption = {le.TARGET_LIMB},
   MultipleOptions = false,
   Flag = "TARGET_LIMB",
   Callback = function(Options)
		le.TARGET_LIMB = Options[1]
   end,
})

Themes:CreateDropdown({
   Name = "Current Theme",
   Options = {"Default", "AmberGlow", "Amethyst", "Bloom", "DarkBlue", "Green", "Light", "Ocean", "Serenity"},
   CurrentOption = {"Default"},
   MultipleOptions = false,
   Flag = "CurrentTheme",
   Callback = function(Options)
		Window.ModifyTheme(Options[1])
   end,
})

Rayfield:LoadConfiguration()

local function characterAdded(Character)
    local function onChildChanged(child)
        if not child:IsA("BasePart") then return end
        local index = table.find(limbs, child.Name)
        if not index then
            table.insert(limbs, child.Name)
			table.sort(limbs)
			TargetLimb:Refresh(limbs)
        end
    end

    Character.ChildAdded:Connect(function(child)
        onChildChanged(child)
    end)

	for _, child in ipairs(Character:GetChildren()) do
		onChildChanged(child)
	end
end

LocalPlayer.CharacterAdded:Connect(characterAdded)
if LocalPlayer.Character then
    characterAdded(LocalPlayer.Character)
end
