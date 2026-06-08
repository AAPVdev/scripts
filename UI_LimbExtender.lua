getgenv().uiLE = getgenv().uiLE or {}

if getgenv().uiLE.loading then
	return
end

getgenv().uiLE.loading = true

if getgenv().uiLE.uilibray then
	getgenv().uiLE.uilibray:Destroy()
	getgenv().uiLE.uilibray = nil
end

if getgenv().uiLE.gcontroller then
	getgenv().uiLE.gcontroller:Destroy()
	getgenv().uiLE.gcontroller = nil
end

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

getgenv().uiLE.le = getgenv().uiLE.le or loadstring(game:HttpGet("https://raw.githubusercontent.com/AAPVdev/scripts/refs/heads/main/LimbExtender.lua"))()
local LimbExtender = getgenv().uiLE.le

getgenv().RAYFIELD_SECURE = true
getgenv().RAYFIELD_ASSET_ID = 84895246331982
getgenv().uiLE.uilibray = loadstring(game:HttpGet("https://sirius.menu/rayfield"))()
local Rayfield = getgenv().uiLE.uilibray

getgenv().uiLE.gcontroller = LimbExtender.new()

local controller = getgenv().uiLE.gcontroller

local UI = {
	Name = "AXIOS",
	Icon = 107904589783906,
	Theme = "Default",
	LoadingSubtitles = {
		"wtf update? in this economy?",
		"the chatgpt special",
		"racist meme rhetoric here",
		"we are not back ts gon update in the next 5 years",
	},
}

local function pickRandom(items)
	return items[math.random(1, #items)]
end

local function createToggle(tab, name, flag, defaultValue, callback)
	return tab:CreateToggle({
		Name = name,
		CurrentValue = defaultValue,
		Flag = flag,
		Callback = callback or function() end,
	})
end

local function createSlider(tab, name, flag, defaultValue, range, increment, suffix, callback)
	return tab:CreateSlider({
		Name = name,
		CurrentValue = defaultValue,
		Flag = flag,
		Range = range,
		Increment = increment,
		Suffix = suffix or "",
		Callback = callback or function() end,
	})
end

local function createDropdown(tab, name, flag, options, currentOption, multi, callback)
	return tab:CreateDropdown({
		Name = name,
		Options = options,
		CurrentOption = currentOption,
		MultipleOptions = multi,
		Flag = flag,
		Callback = callback or function() end,
	})
end

local function createColorPicker(tab, name, flag, defaultColor, callback)
	return tab:CreateColorPicker({
		Name = name,
		Color = defaultColor,
		Flag = flag,
		Callback = callback or function() end,
	})
end

local function bindToggle(tab, label, uiFlag, controllerKey)
	createToggle(tab, label, uiFlag, controller:Get(controllerKey), function(value)
		controller:Set(controllerKey, value)
	end)
end

local function bindSlider(tab, label, uiFlag, controllerKey, range, increment, suffix)
	createSlider(tab, label, uiFlag, controller:Get(controllerKey), range, increment, suffix, function(value)
		controller:Set(controllerKey, value)
	end)
end

local function bindColor(tab, label, uiFlag, controllerKey)
	createColorPicker(tab, label, uiFlag, controller:Get(controllerKey), function(value)
		controller:Set(controllerKey, value)
	end)
end

local function bindDropdown(tab, label, uiFlag, currentValue, options, callback)
	return createDropdown(tab, label, uiFlag, options, { currentValue }, false, callback)
end

local function getLODFlag(settingKey, field)
	local value = controller:Get(settingKey)
	return type(value) == "table" and value[field] or false
end

local function setLODFlag(settingKey, field, value)
	local current = controller:Get(settingKey)
	if type(current) == "table" then
		current[field] = value
		controller:Set(settingKey, current)
	end
end

local Window = Rayfield:CreateWindow({
	Name = UI.Name,
	Icon = UI.Icon,
	LoadingTitle = UI.Name,
	LoadingSubtitle = pickRandom(UI.LoadingSubtitles),
	Theme = UI.Theme,
	DisableRayfieldPrompts = true,
	ConfigurationSaving = {
		Enabled = true,
		FolderName = "LimbExtenderConfigs",
		FileName = "Configuration",
	},
})

local Tabs = {
	Limbs = Window:CreateTab("Limbs", "scale-3d"),
	Sense = Window:CreateTab("ESP", "eye"),
	Target = Window:CreateTab("Target", "crosshair"),
	Themes = Window:CreateTab("Themes", "palette"),
}

local modifyLimbsToggle = createToggle(Tabs.Limbs, "Modify Limbs", "ModifyLimbs", false, function(value)
	controller:Toggle(value)
end)

Tabs.Limbs:CreateDivider()

local limbSettings = {
	{ kind = "Toggle", label = "Players", flag = "PLAYER_ENABLED", controllerKey = "PLAYER_ENABLED" },
	{ kind = "Toggle", label = "NPCs", flag = "NPC_ENABLED", controllerKey = "NPC_ENABLED", dividerAfter = true },
	{ kind = "Toggle", label = "Team Check", flag = "TEAM_CHECK", controllerKey = "TEAM_CHECK" },
	{ kind = "Toggle", label = "ForceField Check", flag = "FORCEFIELD_CHECK", controllerKey = "FORCEFIELD_CHECK" },
	{ kind = "Toggle", label = "Limb Collisions", flag = "LIMB_CAN_COLLIDE", controllerKey = "LIMB_CAN_COLLIDE", dividerAfter = true },
	{ kind = "Slider", label = "Limb Transparency", flag = "LIMB_TRANSPARENCY", controllerKey = "LIMB_TRANSPARENCY", range = { 0, 1 }, increment = 0.1 },
	{ kind = "Slider", label = "Limb Size", flag = "LIMB_SIZE", controllerKey = "LIMB_SIZE", range = { 5, 50 }, increment = 0.5, dividerAfter = true },
}

for _, setting in ipairs(limbSettings) do
	if setting.kind == "Toggle" then
		bindToggle(Tabs.Limbs, setting.label, setting.flag, setting.controllerKey)
	else
		bindSlider(Tabs.Limbs, setting.label, setting.flag, setting.controllerKey, setting.range, setting.increment, nil)
	end

	if setting.dividerAfter then
		Tabs.Limbs:CreateDivider()
	end
end

Tabs.Limbs:CreateKeybind({
	Name = "Toggle Keybind",
	CurrentKeybind = "L",
	HoldToInteract = false,
	Flag = "ToggleKeybind",
	Callback = function()
		modifyLimbsToggle:Set(not controller._running)
	end,
})

Tabs.Sense:CreateSection("Hitbox ESP")

bindToggle(Tabs.Sense, "Enabled", "ESPEnabled", "ESP")
bindToggle(Tabs.Sense, "Filter Local Player", "ESP_FILTER_LOCAL", "ESP_FILTER_LOCAL")

Tabs.Sense:CreateSection("Elements")

local espElements = {
	{ label = "2D Box", flag = "ESP_BOX" },
	{ label = "3D Box", flag = "ESP_BOX3D" },
	{ label = "Tracer", flag = "ESP_TRACER" },
	{ label = "Skeleton", flag = "ESP_SKELETON" },
	{ label = "Health Bar", flag = "ESP_HEALTH" },
	{ label = "Label", flag = "ESP_LABEL" },
	{ label = "Off-Screen Arrow", flag = "ESP_OFFSCREEN_POINT" },
}

for _, item in ipairs(espElements) do
	bindToggle(Tabs.Sense, item.label, item.flag, item.flag)
end

Tabs.Sense:CreateSection("Colors")

local espColors = {
	{ label = "Box / Tracer", key = "ESP_COLOR" },
	{ label = "3D Box", key = "ESP_BOX3D_COLOR" },
	{ label = "Skeleton", key = "ESP_SKELETON_COLOR" },
	{ label = "Health (Full)", key = "ESP_HEALTH_COLOR" },
	{ label = "Health (Empty)", key = "ESP_EMPTY_COLOR" },
	{ label = "Text", key = "ESP_TEXT_COLOR" },
}

for _, item in ipairs(espColors) do
	bindColor(Tabs.Sense, item.label, "ESPColor_" .. item.key, item.key)
end

Tabs.Sense:CreateSection("Text")
bindSlider(Tabs.Sense, "Text Size", "ESP_TEXT_SIZE", "ESP_TEXT_SIZE", { 8, 32 }, 1, "px")

Tabs.Sense:CreateSection("Distance Thresholds")

Tabs.Sense:CreateParagraph({
	Title = "Level of Detail (LOD)",
	Content = "Targets within Near Distance use the Near feature set. "
		.. "Between Near and Medium uses the Medium set. "
		.. "Beyond Medium up to Max Distance uses the Far set. "
		.. "Configure each set in the sections below.",
})

bindSlider(Tabs.Sense, "Near Distance", "ESP_NEAR_DISTANCE", "ESP_NEAR_DISTANCE", { 50, 500 }, 10, "st")
bindSlider(Tabs.Sense, "Medium Distance", "ESP_MEDIUM_DISTANCE", "ESP_MEDIUM_DISTANCE", { 100, 1000 }, 10, "st")
bindSlider(Tabs.Sense, "Max Distance", "ESP_MAX_DISTANCE", "ESP_MAX_DISTANCE", { 100, 2000 }, 50, "st")

local lodFeatures = {
	{ label = "2D Box", field = "Box" },
	{ label = "3D Box", field = "Box3D" },
	{ label = "Tracer", field = "Tracer" },
	{ label = "Skeleton", field = "Skeleton" },
	{ label = "Health Bar", field = "Health" },
	{ label = "Label", field = "Label" },
}

local lodTiers = {
	{ section = "Near Range Features", key = "ESP_NEAR_FLAGS" },
	{ section = "Medium Range Features", key = "ESP_MEDIUM_FLAGS" },
	{ section = "Far Range Features", key = "ESP_FAR_FLAGS" },
}

for _, tier in ipairs(lodTiers) do
	Tabs.Sense:CreateSection(tier.section)
	for _, feature in ipairs(lodFeatures) do
		local flagId = tier.key .. "_" .. feature.field
		createToggle(Tabs.Sense, feature.label, flagId, getLODFlag(tier.key, feature.field), function(value)
			setLODFlag(tier.key, feature.field, value)
		end)
	end
end

Tabs.Sense:CreateSection("Performance")

bindToggle(Tabs.Sense, "Occlusion Checking", "ESP_OCCLUSION", "ESP_OCCLUSION")
bindSlider(Tabs.Sense, "Occlusion Frequency", "ESP_OCCLUSION_FREQUENCY", "ESP_OCCLUSION_FREQUENCY", { 1, 20 }, 1, "frames")

local targetLimbDropdown = bindDropdown(Tabs.Target, "Target Limb", "TARGET_LIMB", controller:Get("TARGET_LIMB"), {}, function(options)
	controller:Set("TARGET_LIMB", options[1])
end)

createDropdown(Tabs.Themes, "Current Theme", "CurrentTheme", { "Default", "AmberGlow", "Amethyst", "Bloom", "DarkBlue", "Green", "Light", "Ocean", "Serenity" }, { "Default" }, false, function(options)
	Window.ModifyTheme(options[1])
end)

Rayfield:LoadConfiguration()

local limbNames = {}

local function refreshTargetLimbDropdown()
	table.sort(limbNames)
	targetLimbDropdown:Refresh(limbNames)
end

local function addLimbIfNew(name)
	if not name then
		return
	end

	if not table.find(limbNames, name) then
		table.insert(limbNames, name)
		refreshTargetLimbDropdown()
	end
end

local function handleCharacter(character)
	if not character then
		return
	end

	character.ChildAdded:Connect(function(child)
		if child:IsA("BasePart") then
			addLimbIfNew(child.Name)
		end
	end)

	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("BasePart") then
			addLimbIfNew(child.Name)
		end
	end
end

LocalPlayer.CharacterAdded:Connect(handleCharacter)

if LocalPlayer.Character then
	handleCharacter(LocalPlayer.Character)
end

getgenv().uiLE.loading = false
