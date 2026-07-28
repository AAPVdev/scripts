getgenv().uiLE = getgenv().uiLE or {}
if getgenv().uiLE.loading then return end
getgenv().uiLE.loading = true

-- Load the limb extender engine (original)
getgenv().uiLE.le = getgenv().uiLE.le
    or loadstring(game:HttpGet("https://raw.githubusercontent.com/AAPVdev/scripts/refs/heads/main/LimbExtender.lua"))()

-- Clean up old controller
if getgenv().uiLE.gcontroller then
    pcall(function() getgenv().uiLE.gcontroller:Destroy() end)
    getgenv().uiLE.gcontroller = nil
end

-- Create new controller
getgenv().uiLE.gcontroller = getgenv().uiLE.le.new()
local ctrl = getgenv().uiLE.gcontroller

-- Clean up old UI
if getgenv().uiLE.uilibray then
    pcall(function() getgenv().uiLE.uilibray:Unload() end)
    getgenv().uiLE.uilibray = nil
end

local LocalPlayer = game:GetService("Players").LocalPlayer
local UserInputService = game:GetService("UserInputService")
local isPC = UserInputService:GetPlatform() == Enum.Platform.Windows or UserInputService:GetPlatform() == Enum.Platform.OSX

-- Load Gen2 Rayfield
getgenv().RAYFIELD_SECURE = true
getgenv().uiLE.uilibray = loadstring(game:HttpGet("https://sirius.menu/gen2"))()
local Rayfield = getgenv().uiLE.uilibray

-- LOD helper functions
local function getLodFlag(key, field)
    local t = ctrl:Get(key)
    return type(t) == "table" and t[field]
end

local function setLodFlag(key, field, value)
    local t = ctrl:Get(key)
    if type(t) ~= "table" then t = {} end
    t[field] = value
    ctrl:Set(key, t)
end

-- Safe element builder (no crashes for missing methods)
local function buildTab(tab, layout)
    for _, item in ipairs(layout) do
        local t = item.type

        if t == "section" then
            tab:CreateSection({ name = item.title })

        elseif t == "paragraph" then
            -- Fallback: Gen2 lacks paragraph; show as section if possible
            if tab.CreateParagraph then
                tab:CreateParagraph({ title = item.title, content = item.content })
            elseif tab.CreateLabel then
                tab:CreateLabel(item.title .. "\n" .. item.content)
            elseif tab.CreateSection then
                tab:CreateSection({ name = item.title })
            end

        elseif t == "toggle" then
            local saved = ctrl:Get(item.flag)
            tab:CreateToggle({
                name = item.name,
                flag = item.flag,
                currentValue = (saved ~= nil) and saved or false,
                callback = function(v) ctrl:Set(item.flag, v) end,
            })

        elseif t == "slider" then
            local minV = item.range[1]
            local cur = ctrl:Get(item.flag)
            if type(cur) ~= "number" then cur = minV end
            tab:CreateSlider({
                name = item.name,
                flag = item.flag,
                currentValue = cur,
                range = item.range,
                increment = item.increment,
                suffix = item.suffix or "",
                callback = function(v) ctrl:Set(item.flag, v) end,
            })

        elseif t == "color" then
            local cur = ctrl:Get(item.flag)
            if typeof(cur) ~= "Color3" then cur = Color3.fromRGB(255, 255, 255) end
            tab:CreateColorPicker({
                name = item.name,
                flag = item.flag,
                color = cur,
                callback = function(v) ctrl:Set(item.flag, v) end,
            })
        end
    end
end

-- Window
local Window = Rayfield:CreateWindow({
    name = "AXIOS",
    subtitle = "Limb Extender",
    theme = "default",
    configuration = {
        autoSave = true,
        autoLoad = true,
        fileName = "Configuration",
        customFolder = "LimbExtenderConfigs",
    },
})

-- Tabs (option 2)
local Tabs = {
    General    = Window:CreateTab({ name = "General" }),
    Targeting  = Window:CreateTab({ name = "Targeting" }),
    Appearance = Window:CreateTab({ name = "Appearance" }),
}
if isPC then
    Tabs.ESP = Window:CreateTab({ name = "ESP" })
end

-- ==================== GENERAL TAB ====================
Tabs.General:CreateSection({ name = "Master Control" })
local modifyLimbsToggle = Tabs.General:CreateToggle({
    name = "Modify Limbs",
    flag = "ModifyLimbs",
    currentValue = false,
    callback = function(v) ctrl:Toggle(v) end,
})
Tabs.General:CreateKeybind({
    name = "Toggle Keybind",
    currentKeybind = "L",
    holdToInteract = false,
    flag = "ToggleKeybind",
    callback = function()
        modifyLimbsToggle:Set(not ctrl._running)
    end,
})

Tabs.General:CreateSection({ name = "Theme" })
Tabs.General:CreateDropdown({
    name = "Current Theme",
    flag = "CurrentTheme",
    multipleOptions = false,
    options = { "default", "cobalt", "ember", "amethyst", "frost", "rose" },
    currentOption = "default",
    callback = function(theme) Window:ChangeTheme(theme) end,
})

-- ==================== TARGETING TAB ====================
buildTab(Tabs.Targeting, {
    { type = "section", title = "Target Selection" },
    { type = "toggle",  name = "Players",         flag = "PLAYER_ENABLED" },
    { type = "toggle",  name = "NPCs",            flag = "NPC_ENABLED" },
    { type = "toggle",  name = "Team Check",      flag = "TEAM_CHECK" },
    { type = "toggle",  name = "ForceField Check",flag = "FORCEFIELD_CHECK" },
})

Tabs.Targeting:CreateSection({ name = "Limb Focus" })
local targetLimbDropdown = Tabs.Targeting:CreateDropdown({
    name = "Target Limb",
    flag = "TARGET_LIMB",
    options = {},
    currentOption = ctrl:Get("TARGET_LIMB") or "Head",
    multipleOptions = false,
    callback = function(value) ctrl:Set("TARGET_LIMB", value) end,
})

-- ==================== APPEARANCE TAB ====================
buildTab(Tabs.Appearance, {
    { type = "section", title = "Limb Properties" },
    { type = "toggle",  name = "Limb Collisions",   flag = "LIMB_CAN_COLLIDE" },
    { type = "slider",  name = "Limb Transparency", flag = "LIMB_TRANSPARENCY", range = {0, 1},  increment = 0.1 },
    { type = "slider",  name = "Limb Size",         flag = "LIMB_SIZE",         range = {5, 50}, increment = 0.5 },

    { type = "section", title = "Proximity Shrink" },
    { type = "toggle",  name = "Shrink Enabled",    flag = "DYNAMIC_SCALE_ENABLED" },
    { type = "slider",  name = "Shrink Range",      flag = "DYNAMIC_SCALE_RANGE_MULT",  range = {0.2, 5}, increment = 0.1, suffix = "x" },
    { type = "slider",  name = "Update Rate",       flag = "DYNAMIC_SCALE_UPDATE_RATE", range = {5, 60}, increment = 1, suffix = "Hz" },
})

-- ==================== ESP TAB (PC only) ====================
if isPC then
    buildTab(Tabs.ESP, {
        { type = "section", title = "General" },
        { type = "toggle",  name = "Enabled",             flag = "ESP" },
        { type = "toggle",  name = "Filter Local Player", flag = "ESP_FILTER_LOCAL" },

        { type = "section", title = "Elements" },
        { type = "toggle",  name = "2D Box",           flag = "ESP_BOX" },
        { type = "toggle",  name = "3D Box",           flag = "ESP_BOX3D" },
        { type = "toggle",  name = "Tracer",           flag = "ESP_TRACER" },
        { type = "toggle",  name = "Skeleton",         flag = "ESP_SKELETON" },
        { type = "toggle",  name = "Health Bar",       flag = "ESP_HEALTH" },
        { type = "toggle",  name = "Label",            flag = "ESP_LABEL" },
        { type = "toggle",  name = "Off-Screen Arrow", flag = "ESP_OFFSCREEN_POINT" },

        { type = "section", title = "Colors" },
        { type = "color",   name = "Box / Tracer",   flag = "ESP_COLOR" },
        { type = "color",   name = "3D Box",         flag = "ESP_BOX3D_COLOR" },
        { type = "color",   name = "Skeleton",       flag = "ESP_SKELETON_COLOR" },
        { type = "color",   name = "Health (Full)",  flag = "ESP_HEALTH_COLOR" },
        { type = "color",   name = "Health (Empty)", flag = "ESP_EMPTY_COLOR" },
        { type = "color",   name = "Text",           flag = "ESP_TEXT_COLOR" },

        { type = "section", title = "Text" },
        { type = "slider",  name = "Text Size", flag = "ESP_TEXT_SIZE", range = {8, 32}, increment = 1, suffix = "px" },

        { type = "section", title = "Distance Thresholds" },
        { type = "paragraph", title = "Level of Detail (LOD)", content = "Targets within Near Distance use the Near feature set. Between Near and Medium uses the Medium set. Beyond Medium up to Max Distance uses the Far set. Configure each set in the sections below." },
        { type = "slider", name = "Near Distance",   flag = "ESP_NEAR_DISTANCE",   range = {50, 500},  increment = 10, suffix = "st" },
        { type = "slider", name = "Medium Distance", flag = "ESP_MEDIUM_DISTANCE", range = {100, 1000}, increment = 10, suffix = "st" },
        { type = "slider", name = "Max Distance",    flag = "ESP_MAX_DISTANCE",    range = {100, 2000}, increment = 50, suffix = "st" },
    })

    local LOD_TIERS = {
        { label = "Near Range Features",   key = "ESP_NEAR_FLAGS" },
        { label = "Medium Range Features", key = "ESP_MEDIUM_FLAGS" },
        { label = "Far Range Features",    key = "ESP_FAR_FLAGS" },
    }
    local LOD_FEATURES = {
        { name = "2D Box",     field = "Box" },
        { name = "3D Box",     field = "Box3D" },
        { name = "Tracer",     field = "Tracer" },
        { name = "Skeleton",   field = "Skeleton" },
        { name = "Health Bar", field = "Health" },
        { name = "Label",      field = "Label" },
    }

    for _, tier in ipairs(LOD_TIERS) do
        Tabs.ESP:CreateSection({ name = tier.label })
        for _, feature in ipairs(LOD_FEATURES) do
            local key, field = tier.key, feature.field
            Tabs.ESP:CreateToggle({
                name = feature.name,
                flag = key .. "_" .. field,
                currentValue = getLodFlag(key, field) == true,
                callback = function(v) setLodFlag(key, field, v) end,
            })
        end
    end

    buildTab(Tabs.ESP, {
        { type = "section", title = "Performance" },
        { type = "toggle",  name = "Occlusion Checking",  flag = "ESP_OCCLUSION" },
        { type = "slider",  name = "Occlusion Frequency", flag = "ESP_OCCLUSION_FREQUENCY", range = {1, 20}, increment = 1, suffix = "frames" },
    })
end

-- Load configuration (after UI creation to show saved values)
Window:Load()

-- ==================== LIMB SCANNING ====================
local scannedLimbs = {}
local limbPriority = {
    "Head", "HumanoidRootPart", "UpperTorso", "LowerTorso", "Torso",
    "LeftUpperArm", "LeftLowerArm", "LeftHand", "RightUpperArm", "RightLowerArm", "RightHand",
    "Left Arm", "Right Arm",
    "LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "RightUpperLeg", "RightLowerLeg", "RightFoot",
    "Left Leg", "Right Leg",
}

local function getLimbPriority(name)
    local lower = name:lower()
    for index, limb in ipairs(limbPriority) do
        if lower:find(limb:lower(), 1, true) then
            return index
        end
    end
    return math.huge
end

local function sortLimbs()
    table.sort(scannedLimbs, function(a, b)
        local prioA = getLimbPriority(a)
        local prioB = getLimbPriority(b)
        if prioA ~= prioB then return prioA < prioB end
        return a:lower() < b:lower()
    end)
end

local function registerLimb(name)
    if not name or table.find(scannedLimbs, name) then return end
    table.insert(scannedLimbs, name)
    sortLimbs()
    targetLimbDropdown:Refresh(scannedLimbs)
end

local function getPartPath(part, character)
    local path = part.Name
    local parent = part.Parent
    while parent and parent ~= character do
        path = parent.Name .. "." .. path
        parent = parent.Parent
    end
    return path
end

local function scanCharacter(character)
    if not character then return end
    table.clear(scannedLimbs)
    for _, desc in ipairs(character:GetDescendants()) do
        if desc:IsA("BasePart") then
            registerLimb(getPartPath(desc, character))
        end
    end
    character.DescendantAdded:Connect(function(desc)
        if desc:IsA("BasePart") then
            registerLimb(getPartPath(desc, character))
        end
    end)
end

LocalPlayer.CharacterAdded:Connect(scanCharacter)
if LocalPlayer.Character then scanCharacter(LocalPlayer.Character) end

getgenv().uiLE.loading = false
