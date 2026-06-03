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
	-- Additional settings from the module's API
	{
		kind = "Toggle",
		tab = Tabs.Limbs,
		name = "Reset Limb On Death",
		flag = "RESET_LIMB_ON_DEATH",
		default = controller:Get("RESET_LIMB_ON_DEATH"),
	},
	{
		kind = "Toggle",
		tab = Tabs.Limbs,
		name = "Player Enabled",
		flag = "PLAYER_ENABLED",
		default = controller:Get("PLAYER_ENABLED"),
	},
	{
		kind = "Toggle",
		tab = Tabs.Limbs,
		name = "NPC Enabled",
		flag = "NPC_ENABLED",
		default = controller:Get("NPC_ENABLED"),
		dividerAfter = true,
	},
	{
		kind = "Toggle",
		tab = Tabs.Limbs,
		name = "Listen For Input",
		flag = "LISTEN_FOR_INPUT",
		default = controller:Get("LISTEN_FOR_INPUT"),
	},
	{
		kind = "Toggle",
		tab = Tabs.Limbs,
		name = "Mobile Button",
		flag = "MOBILE_BUTTON",
		default = controller:Get("MOBILE_BUTTON"),
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

-- Keybind (keeps the original toggle-behavior when pressed)
Tabs.Limbs:CreateKeybind({
	Name = "Toggle Keybind",
	CurrentKeybind = controller:Get("TOGGLE"),
	HoldToInteract = false,
	Flag = "ToggleKeybind",
	Callback = function()
		modifyLimbsToggle:Set(not controller._running)
	end,
})

-- Also provide a text input to explicitly set the toggle key (safer to reliably update controller settings)
local toggleKeyBox = Tabs.Limbs:CreateTextBox({
	Name = "Set Toggle Key",
	Placeholder = "Enter key name (e.g. L)",
	CurrentText = controller:Get("TOGGLE"),
	Flag = "ToggleKeyText",
		onFocusLost = function(entered)
			if entered and entered ~= "" then
				controller:Set("TOGGLE", entered)
			end
		end,
})

Tabs.Limbs:CreateDivider()

Tabs.Limbs:CreateButton({
	Name = "Start",
	Callback = function()
		controller:Start()
		modifyLimbsToggle:Set(true)
	end,
})

Tabs.Limbs:CreateButton({
	Name = "Stop",
	Callback = function()
		controller:Stop()
		modifyLimbsToggle:Set(false)
	end,
})

Tabs.Limbs:CreateButton({
	Name = "Restart",
	Callback = function()
		controller:Restart()
	end,
})

Tabs.Limbs:CreateButton({
	Name = "Destroy Controller",
	Callback = function()
		controller:Destroy()
		modifyLimbsToggle:Set(false)
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
		onChildAdded = onChildAdded
		onChildAdded(child)
	end
end

LocalPlayer.CharacterAdded:Connect(handleCharacter)

if LocalPlayer.Character then
	handleCharacter(LocalPlayer.Character)
end

-- NPC directories UI (uses controller's directory API)
local function pathForInstance(inst)
	if not inst then return tostring(inst) end
	local parts = {}
	local cur = inst
	while cur and cur ~= game do
		table.insert(parts, 1, cur.Name)
		cur = cur.Parent
	end
	if #parts == 0 then return tostring(inst) end

	-- try to find a readable service/entry point
	local prefix = ""
	if inst:IsDescendantOf(workspace) then
		prefix = "Workspace"
	elseif inst:IsDescendantOf(game:GetService("ReplicatedStorage")) then
		prefix = "ReplicatedStorage"
	elseif inst:IsDescendantOf(game:GetService("ServerStorage")) then
		prefix = "ServerStorage"
	elseif inst:IsDescendantOf(game:GetService("Players")) then
		prefix = "Players"
	else
		prefix = "game"
	end

	return prefix .. "." .. table.concat(parts, ".")
end

local function getDirectoriesAsStrings()
	local dirs = controller:GetDirectories()
	local out = {}
	for _, d in ipairs(dirs) do
		if typeof(d) == "Instance" then
			table.insert(out, pathForInstance(d))
		elseif type(d) == "string" then
			table.insert(out, d)
		else
			table.insert(out, tostring(d))
		end
	end
	return out
end

local dirDropdown
local function refreshDirDropdown()
	local options = getDirectoriesAsStrings()
	if dirDropdown then
		dirDropdown:Refresh(options)
	else
		dirDropdown = Tabs.Target:CreateDropdown({
			Name = "NPC Directories",
			Options = options,
			CurrentOption = (options[1] and { options[1] } or {}),
			MultipleOptions = false,
			Flag = "NPC_DIRECTORIES_DROPDOWN",
			Callback = function(opts) end,
		})
	end
end

refreshDirDropdown()

local dirInput = Tabs.Target:CreateTextBox({
	Name = "Add Directory (string path)",
	Placeholder = "e.g. Workspace.Misc.AI or game:GetService('Workspace').Misc.AI",
	CurrentText = "",
	Flag = "AddDirectoryText",
	onFocusLost = function(text)
		-- do nothing on focus lost; user should press Add
	end,
})

Tabs.Target:CreateButton({
	Name = "Add Directory",
	Callback = function()
		local txt = dirInput:GetValue() or ""
		if txt == "" then return end
		controller:AddDirectory(txt)
		task.wait(0.1)
		refreshDirDropdown()
	end,
})

Tabs.Target:CreateButton({
	Name = "Remove Selected Directory",
	Callback = function()
		local opts = dirDropdown and dirDropdown:GetValue() or nil
		local selected = opts and opts[1]
		if not selected then return end
		controller:RemoveDirectory(selected)
		task.wait(0.1)
		refreshDirDropdown()
	end,
})

Tabs.Target:CreateButton({
	Name = "Refresh Directories",
	Callback = function()
		refreshDirDropdown()
	end,
})

-- Simple NPC filter: substring match against model.Name
local filterInput = Tabs.Target:CreateTextBox({
	Name = "NPC Filter (name contains)",
	Placeholder = "leave blank for no filter",
	CurrentText = "",
	Flag = "NPCFilterText",
	onFocusLost = function(text)
		if text and text ~= "" then
			controller:Set("NPC_FILTER", function(model)
				local ok, res = pcall(function() return tostring(model.Name):find(text) end)
				return ok and res ~= nil
			end)
		else
			controller:Set("NPC_FILTER", nil)
		end
	end,
})

-- Helper to refresh limb list manually
Tabs.Target:CreateButton({
	Name = "Refresh Limb List",
	Callback = function()
		limbNames = {}
		if LocalPlayer.Character then
			for _, child in ipairs(LocalPlayer.Character:GetDescendants()) do
				if child:IsA("BasePart") then addLimbIfNew(child.Name) end
			end
		end
		refreshTargetLimbDropdown()
	end,
})

-- keep UI consistent with controller state on load
modifyLimbsToggle:Set(controller._running)

