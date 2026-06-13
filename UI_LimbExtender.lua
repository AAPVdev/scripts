getgenv().uiLE = getgenv().uiLE or {}
if getgenv().uiLE.loading then return end
getgenv().uiLE.loading = true

getgenv().uiLE.le = getgenv().uiLE.le
    or loadstring(game:HttpGet("https://raw.githubusercontent.com/AAPVdev/scripts/refs/heads/main/LimbExtender.lua"))()

if getgenv().uiLE.gcontroller then getgenv().uiLE.gcontroller:Destroy(); getgenv().uiLE.gcontroller = nil end

getgenv().uiLE.gcontroller = getgenv().uiLE.le.new()
local ctrl = getgenv().uiLE.gcontroller

if getgenv().uiLE.uilibray    then getgenv().uiLE.uilibray:Destroy();    getgenv().uiLE.uilibray    = nil end

local LocalPlayer = game:GetService("Players").LocalPlayer

getgenv().RAYFIELD_SECURE   = true
getgenv().RAYFIELD_ASSET_ID = 84895246331982
getgenv().uiLE.uilibray     = loadstring(game:HttpGet("https://sirius.menu/rayfield"))()

local Rayfield = getgenv().uiLE.uilibray

local function getLodFlag(key, field)
    local t = ctrl:Get(key)
    return type(t) == "table" and t[field]
end

local function setLodFlag(key, field, value)
    local t = ctrl:Get(key)
    if type(t) ~= "table" then return end
    t[field] = value
    ctrl:Set(key, t)
end

local function buildTab(tab, layout)
    for _, item in ipairs(layout) do
        local t = item.type

        if t == "section" then
            tab:CreateSection(item.title)

        elseif t == "paragraph" then
            tab:CreateParagraph({ Title = item.title, Content = item.content })

        elseif t == "toggle" then
            tab:CreateToggle({
                Name         = item.name,
                Flag         = item.flag,
                CurrentValue = ctrl:Get(item.flag),
                Callback     = function(v) ctrl:Set(item.flag, v) end,
            })

        elseif t == "slider" then
            tab:CreateSlider({
                Name         = item.name,
                Flag         = item.flag,
                CurrentValue = ctrl:Get(item.flag),
                Range        = item.range,
                Increment    = item.increment,
                Suffix       = item.suffix or "",
                Callback     = function(v) ctrl:Set(item.flag, v) end,
            })

        elseif t == "color" then
            tab:CreateColorPicker({
                Name     = item.name,
                Flag     = "ESPColor_" .. item.flag,
                Color    = ctrl:Get(item.flag),
                Callback = function(v) ctrl:Set(item.flag, v) end,
            })
        end
    end
end

local LOADING_SUBTITLES = {
    "wtf update? in this economy?",
    "the chatgpt special",
    "racist meme rhetoric here",
    "we are not back ts gon update in the next 5 years",
}

local Window = Rayfield:CreateWindow({
    Name                   = "AXIOS",
    Icon                   = 107904589783906,
    LoadingTitle           = "AXIOS",
    LoadingSubtitle        = LOADING_SUBTITLES[math.random(#LOADING_SUBTITLES)],
    Theme                  = "Default",
    DisableRayfieldPrompts = true,
    ConfigurationSaving    = {
        Enabled    = true,
        FolderName = "LimbExtenderConfigs",
        FileName   = "Configuration",
    },
})

local Tabs = {
    Limbs  = Window:CreateTab("Limbs",  "scale-3d"),
    ESP    = Window:CreateTab("ESP",    "eye"),
    Target = Window:CreateTab("Target", "crosshair"),
    Themes = Window:CreateTab("Themes", "palette"),
}

Tabs.Limbs:CreateSection("General")

local modifyLimbsToggle = Tabs.Limbs:CreateToggle({
    Name         = "Modify Limbs",
    Flag         = "ModifyLimbs",
    CurrentValue = false,
    Callback     = function(v) ctrl:Toggle(v) end,
})

buildTab(Tabs.Limbs, {
    { type = "section", title = "Targets" },
    { type = "toggle",  name = "Players", flag = "PLAYER_ENABLED" },
    { type = "toggle",  name = "NPCs",    flag = "NPC_ENABLED"    },

    { type = "section", title = "Filters" },
    { type = "toggle",  name = "Team Check",       flag = "TEAM_CHECK"       },
    { type = "toggle",  name = "ForceField Check", flag = "FORCEFIELD_CHECK" },

    { type = "section", title = "Appearance" },
    { type = "toggle",  name = "Limb Collisions",   flag = "LIMB_CAN_COLLIDE"                                          },
    { type = "slider",  name = "Limb Transparency", flag = "LIMB_TRANSPARENCY", range = {0,  1},  increment = 0.1      },
    { type = "slider",  name = "Limb Size",         flag = "LIMB_SIZE",         range = {5, 50},  increment = 0.5      },

    { type = "section", title = "Keybind" },
})

Tabs.Limbs:CreateKeybind({
    Name           = "Toggle Keybind",
    CurrentKeybind = "L",
    HoldToInteract = false,
    Flag           = "ToggleKeybind",
    Callback       = function() modifyLimbsToggle:Set(not ctrl._running) end,
})

buildTab(Tabs.ESP, {
    { type = "section", title = "General" },
    { type = "toggle",  name = "Enabled",             flag = "ESP"              },
    { type = "toggle",  name = "Filter Local Player", flag = "ESP_FILTER_LOCAL" },

    { type = "section", title = "Elements" },
    { type = "toggle",  name = "2D Box",           flag = "ESP_BOX"             },
    { type = "toggle",  name = "3D Box",           flag = "ESP_BOX3D"           },
    { type = "toggle",  name = "Tracer",           flag = "ESP_TRACER"          },
    { type = "toggle",  name = "Skeleton",         flag = "ESP_SKELETON"        },
    { type = "toggle",  name = "Health Bar",       flag = "ESP_HEALTH"          },
    { type = "toggle",  name = "Label",            flag = "ESP_LABEL"           },
    { type = "toggle",  name = "Off-Screen Arrow", flag = "ESP_OFFSCREEN_POINT" },

    { type = "section", title = "Colors" },
    { type = "color",   name = "Box / Tracer",   flag = "ESP_COLOR"          },
    { type = "color",   name = "3D Box",         flag = "ESP_BOX3D_COLOR"    },
    { type = "color",   name = "Skeleton",       flag = "ESP_SKELETON_COLOR" },
    { type = "color",   name = "Health (Full)",  flag = "ESP_HEALTH_COLOR"   },
    { type = "color",   name = "Health (Empty)", flag = "ESP_EMPTY_COLOR"    },
    { type = "color",   name = "Text",           flag = "ESP_TEXT_COLOR"     },

    { type = "section", title = "Text" },
    { type = "slider",  name = "Text Size", flag = "ESP_TEXT_SIZE", range = {8, 32}, increment = 1, suffix = "px" },

    { type = "section", title = "Distance Thresholds" },
    {
        type    = "paragraph",
        title   = "Level of Detail (LOD)",
        content = "Targets within Near Distance use the Near feature set. "
               .. "Between Near and Medium uses the Medium set. "
               .. "Beyond Medium up to Max Distance uses the Far set. "
               .. "Configure each set in the sections below.",
    },
    { type = "slider", name = "Near Distance",   flag = "ESP_NEAR_DISTANCE",   range = {50,  500},  increment = 10, suffix = "st" },
    { type = "slider", name = "Medium Distance", flag = "ESP_MEDIUM_DISTANCE", range = {100, 1000}, increment = 10, suffix = "st" },
    { type = "slider", name = "Max Distance",    flag = "ESP_MAX_DISTANCE",    range = {100, 2000}, increment = 50, suffix = "st" },
})

local LOD_TIERS = {
    { label = "Near Range Features",   key = "ESP_NEAR_FLAGS"   },
    { label = "Medium Range Features", key = "ESP_MEDIUM_FLAGS" },
    { label = "Far Range Features",    key = "ESP_FAR_FLAGS"    },
}

local LOD_FEATURES = {
    { name = "2D Box",     field = "Box"      },
    { name = "3D Box",     field = "Box3D"    },
    { name = "Tracer",     field = "Tracer"   },
    { name = "Skeleton",   field = "Skeleton" },
    { name = "Health Bar", field = "Health"   },
    { name = "Label",      field = "Label"    },
}

for _, tier in ipairs(LOD_TIERS) do
    Tabs.ESP:CreateSection(tier.label)
    for _, feature in ipairs(LOD_FEATURES) do
        local key, field = tier.key, feature.field
        Tabs.ESP:CreateToggle({
            Name         = feature.name,
            Flag         = key .. "_" .. field,
            CurrentValue = getLodFlag(key, field),
            Callback     = function(v) setLodFlag(key, field, v) end,
        })
    end
end

buildTab(Tabs.ESP, {
    { type = "section", title = "Performance" },
    { type = "toggle",  name = "Occlusion Checking",  flag = "ESP_OCCLUSION"                                                },
    { type = "slider",  name = "Occlusion Frequency", flag = "ESP_OCCLUSION_FREQUENCY", range = {1, 20}, increment = 1, suffix = "frames" },
})

local targetLimbDropdown = Tabs.Target:CreateDropdown({
    Name            = "Target Limb",
    Flag            = "TARGET_LIMB",
    Options         = {},
    CurrentOption   = { ctrl:Get("TARGET_LIMB") },
    MultipleOptions = false,
    Callback        = function(opts) ctrl:Set("TARGET_LIMB", opts[1]) end,
})

local THEMES = {
    "Default", "AmberGlow", "Amethyst", "Bloom",
    "DarkBlue", "Green", "Light", "Ocean", "Serenity",
}

Tabs.Themes:CreateDropdown({
    Name            = "Current Theme",
    Flag            = "CurrentTheme",
    MultipleOptions = false,
    Options         = THEMES,
    CurrentOption   = { "Default" },
    Callback        = function(opts) Window.ModifyTheme(opts[1]) end,
})

Rayfield:LoadConfiguration()

local scannedLimbs = {}

local function registerLimb(name)
    if not name or table.find(scannedLimbs, name) then return end
    table.insert(scannedLimbs, name)
    table.sort(scannedLimbs)
    targetLimbDropdown:Refresh(scannedLimbs)
end

local function scanCharacter(character)
    if not character then return end
    character.ChildAdded:Connect(function(child)
        if child:IsA("BasePart") then registerLimb(child.Name) end
    end)
    for _, child in ipairs(character:GetChildren()) do
        if child:IsA("BasePart") then registerLimb(child.Name) end
    end
end

LocalPlayer.CharacterAdded:Connect(scanCharacter)
if LocalPlayer.Character then scanCharacter(LocalPlayer.Character) end

getgenv().uiLE.loading = false
