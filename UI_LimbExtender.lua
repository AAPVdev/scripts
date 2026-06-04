local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

getgenv().le = getgenv().le or loadstring(game:HttpGet("https://raw.githubusercontent.com/AAPVdev/scripts/refs/heads/main/LimbExtender.lua"))()
local LimbExtender = getgenv().le

getgenv().uilibray = getgenv().uilibray or loadstring(game:HttpGet("https://sirius.menu/rayfield"))()
local Rayfield = getgenv().uilibray

local controller = LimbExtender({
	LISTEN_FOR_INPUT = false,
	MOBILE_BUTTON = false,
})

local UI = {
	Name = "AXIOS",
	Icon = 107904589783906,
	LoadingTitle = "AXIOS",
	LoadingSubtitles = {
		"wtf update? in this economy?",
		"the chatgpt special",
		"racist meme rhetoric here",
		"we are not back ts gon update in the next 5 years",
	},
	Theme = "Default",
}

local function pickRandom(list)
	return list[math.random(1, #list)]
end

local Window = Rayfield:CreateWindow({
	Name = UI.Name,
	Icon = UI.Icon,
	LoadingTitle = UI.LoadingTitle,
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
	Sense = Window:CreateTab("Sense", "eye"),
	Target = Window:CreateTab("Target", "crosshair"),
	Themes = Window:CreateTab("Themes", "palette"),
}

local function createControl(tab, kind, props, callback)
	local methodName = "Create" .. kind
	local method = tab[methodName]

	if type(method) ~= "function" then
		warn(("Method %s not found on tab %s"):format(methodName, tostring(tab)))
		return nil
	end

	props = props or {}
	props.Callback = function(value)
		if callback then
			callback(value)
		end
	end

	return method(tab, props)
end

local function createToggle(tab, name, flag, defaultValue, callback)
	return createControl(tab, "Toggle", {
		Name = name,
		CurrentValue = defaultValue,
		Flag = flag,
	}, callback)
end

local function createSlider(tab, name, flag, defaultValue, range, increment, callback)
	return createControl(tab, "Slider", {
		Name = name,
		CurrentValue = defaultValue,
		Flag = flag,
		Range = range,
		Increment = increment,
	}, callback)
end

local function createDropdown(tab, name, flag, options, currentOption, multipleOptions, callback)
	return createControl(tab, "Dropdown", {
		Name = name,
		Options = options,
		CurrentOption = currentOption,
		MultipleOptions = multipleOptions,
		Flag = flag,
	}, callback)
end

local modifyLimbsToggle = createToggle(
	Tabs.Limbs,
	"Modify Limbs",
	"ModifyLimbs",
	false,
	function(value)
		controller:Toggle(value)
	end
)

Tabs.Limbs:CreateDivider()

local settingsList = {
	{
		kind = "Toggle",
		tab = Tabs.Limbs,
		name = "Players",
		flag = "PLAYER_ENABLED",
		default = controller:Get("PLAYER_ENABLED"),
	},
    {
		kind = "Toggle",
		tab = Tabs.Limbs,
		name = "NPCs",
		flag = "NPC_ENABLED",
		default = controller:Get("NPC_ENABLED"),
        dividerAfter = true,
	},
	{
		kind = "Toggle",
		tab = Tabs.Limbs,
		name = "Team Check",
		flag = "TEAM_CHECK",
		default = controller:Get("TEAM_CHECK"),
	},
	{
		kind = "Toggle",
		tab = Tabs.Limbs,
		name = "ForceField Check",
		flag = "FORCEFIELD_CHECK",
		default = controller:Get("FORCEFIELD_CHECK"),
	},
	{
		kind = "Toggle",
		tab = Tabs.Limbs,
		name = "Limb Collisions",
		flag = "LIMB_CAN_COLLIDE",
		default = controller:Get("LIMB_CAN_COLLIDE"),
		dividerAfter = true,
	},
	{
		kind = "Slider",
		tab = Tabs.Limbs,
		name = "Limb Transparency",
		flag = "LIMB_TRANSPARENCY",
		default = controller:Get("LIMB_TRANSPARENCY"),
		range = { 0, 1 },
		increment = 0.1,
	},
	{
		kind = "Slider",
		tab = Tabs.Limbs,
		name = "Limb Size",
		flag = "LIMB_SIZE",
		default = controller:Get("LIMB_SIZE"),
		range = { 5, 50 },
		increment = 0.5,
		dividerAfter = true,
	},
}

for _, setting in ipairs(settingsList) do
	if setting.kind == "Toggle" then
		createToggle(setting.tab, setting.name, setting.flag, setting.default, function(value)
			controller:Set(setting.flag, value)
		end)
	elseif setting.kind == "Slider" then
		createSlider(setting.tab, setting.name, setting.flag, setting.default, setting.range, setting.increment, function(value)
			controller:Set(setting.flag, value)
		end)
	end

	if setting.dividerAfter then
		setting.tab:CreateDivider()
	end
end

Tabs.Limbs:CreateKeybind({
	Name = "Toggle Keybind",
	CurrentKeybind = controller:Get("TOGGLE"),
	HoldToInteract = false,
	Flag = "ToggleKeybind",
	Callback = function()
		modifyLimbsToggle:Set(not controller._running)
	end,
})

local targetLimbDropdown = createDropdown(
	Tabs.Target,
	"Target Limb",
	"TARGET_LIMB",
	{},
	{ controller:Get("TARGET_LIMB") },
	false,
	function(options)
		controller:Set("TARGET_LIMB", options[1])
	end
)

Tabs.Themes:CreateDropdown({
	Name = "Current Theme",
	Options = { "Default", "AmberGlow", "Amethyst", "Bloom", "DarkBlue", "Green", "Light", "Ocean", "Serenity" },
	CurrentOption = { "Default" },
	MultipleOptions = false,
	Flag = "CurrentTheme",
	Callback = function(options)
		Window.ModifyTheme(options[1])
	end,
})

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

	local function onChildAdded(child)
		if child and child:IsA("BasePart") then
			addLimbIfNew(child.Name)
		end
	end

	character.ChildAdded:Connect(onChildAdded)

	for _, child in ipairs(character:GetChildren()) do
		onChildAdded(child)
	end
end

LocalPlayer.CharacterAdded:Connect(handleCharacter)

if LocalPlayer.Character then
	handleCharacter(LocalPlayer.Character)
end
