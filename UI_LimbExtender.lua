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

getgenv().uiLE.uilibray = loadstring(game:HttpGet("https://sirius.menu/rayfield"))()
local Rayfield = getgenv().uiLE.uilibray

getgenv().uiLE.gcontroller = LimbExtender.new({
	LISTEN_FOR_INPUT = false,
	MOBILE_BUTTON = false,
})

local controller = getgenv().uiLE.gcontroller

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

local Sense = loadstring(game:HttpGet('https://sirius.menu/sense'))()
Sense.teamSettings.enemy.enabled = true
Sense.teamSettings.friendly.enabled = true

local function setBoth(settingName, value)
    if Sense and Sense.teamSettings then
        Sense.teamSettings.enemy[settingName] = value
        Sense.teamSettings.friendly[settingName] = value
    end
end

local function createControl(def)
    if not def or not def.type then return end

    local function applyPropsToTeams(value)
        if not def.props then return end
        local function wrapColor(c)
            if def.alpha ~= nil then
                return {c, def.alpha}
            end
            return c
        end

        if def.props.friendly then
            local target = Sense.teamSettings.friendly
            for _, propName in ipairs(def.props.friendly) do
                target[propName] = (def.type == "color") and wrapColor(value) or value
            end
        end
        if def.props.enemy then
            local target = Sense.teamSettings.enemy
            for _, propName in ipairs(def.props.enemy) do
                target[propName] = (def.type == "color") and wrapColor(value) or value
            end
        end
    end

    local function controlCallback(v)
        if def.setting then
            setBoth(def.setting, v)
        end
        applyPropsToTeams(v)
        if def.onChange then def.onChange(v) end
    end

    if def.type == "section" then
        Tabs.Sense:CreateSection(def.name or "")
        return
    elseif def.type == "label" then
        Tabs.Sense:CreateLabel(def.name or "")
        return
    elseif def.type == "toggle" then
        return Tabs.Sense:CreateToggle({ Name = def.name, CurrentValue = def.default or false, Flag = def.flag or "", Callback = controlCallback })
    elseif def.type == "color" then
        return Tabs.Sense:CreateColorPicker({ Name = def.name, Color = def.color or Color3.fromRGB(255,255,255), Flag = def.flag or "", Callback = controlCallback })
    elseif def.type == "dropdown" then
        return Tabs.Sense:CreateDropdown({ Name = def.name, Options = def.options or {}, CurrentOption = def.current, Flag = def.flag or "", Callback = controlCallback })
    elseif def.type == "slider" then
        return Tabs.Sense:CreateSlider({ Name = def.name, Range = def.range or {0,100}, CurrentValue = (def.default ~= nil and def.default) or ((def.range and def.range[1]) or 0), Increment = def.increment or 1, Suffix = def.suffix or "", Flag = def.flag or "", Callback = controlCallback })
    end
end

local function colorBoth(name, flag, propertiesList, defaultColor, alpha)
    return { type = "color", name = name, flag = flag, color = defaultColor, alpha = alpha or 1, props = { friendly = propertiesList, enemy = propertiesList } }
end
local function colorFriendly(name, flag, friendlyProps, defaultColor, alpha)
    return { type = "color", name = name, flag = flag, color = defaultColor, alpha = alpha or 1, props = { friendly = friendlyProps } }
end
local function colorEnemy(name, flag, enemyProps, defaultColor, alpha)
    return { type = "color", name = name, flag = flag, color = defaultColor, alpha = alpha or 1, props = { enemy = enemyProps } }
end
local function toggle(name, flag, setting, default)
    return { type = "toggle", name = name, flag = flag, setting = setting, default = default }
end
local function slider(name, flag, range, default, inc, setting)
    return { type = "slider", name = name, flag = flag, range = range, default = default, increment = inc, setting = setting }
end

local ui = {
    { type = "section", name = "Team Settings" },
    { type = "toggle", name = "Hide Team", flag = "HideTeam", default = false, onChange = function(v) Sense.teamSettings.friendly.enabled = not v end },

    colorBoth("Team Color",  "TeamColor", {"boxColor","box3dColor","offScreenArrowColor","tracerColor"}, Color3.fromRGB(0,255,0), 1),
    colorBoth("Enemy Color", "EnemyColor", {"boxColor","box3dColor","offScreenArrowColor","tracerColor"}, Color3.fromRGB(255,0,0), 1),

    { type = "section", name = "Box" },
    toggle("Enabled", "Boxes", "box", false),
    toggle("Outline", "BoxesOutlined", "boxOutline", true),
    toggle("Fill", "BoxesFilled", "boxFill", false),
    colorFriendly("Team Fill Color", "TeamFillColor", {"boxFillColor"}, Color3.fromRGB(0,255,0), 0.5),
    colorEnemy("Enemy Fill Color", "EnemyFillColor", {"boxFillColor"}, Color3.fromRGB(255,0,0), 0.5),
    toggle("3D Boxes", "3DBoxes", "box3d", false),

    { type = "section", name = "Health" },
    toggle("Enabled", "HealthBar", "healthBar", false),
    { type = "color", name = "Health Color", flag = "HealthColor", color = Color3.fromRGB(0,255,0), onChange = function(c) setBoth("healthyColor", c) end },
    { type = "color", name = "Dying Color", flag = "DyingColor", color = Color3.fromRGB(255,0,0), onChange = function(c) setBoth("dyingColor", c) end },
    toggle("Outline", "HBsOutlined", "healthBarOutline", true),

    { type = "section", name = "Tracer" },
    toggle("Enabled", "Tracers", "tracer", false),
    toggle("Outline", "TracersOutlined", "tracerOutline", true),
    { type = "dropdown", name = "Origin", flag = "TracerOrigin", options = {"Bottom","Top","Mouse"}, current = "Bottom", onChange = function(v) setBoth("tracerOrigin", v) end },

    { type = "section", name = "Tag" },
    toggle("Name", "Names", "name", false),
    toggle("Name Outlined", "NamesOutlined", "nameOutline", true),
    toggle("Distance", "Distances", "distance", false),
    toggle("Distance Outlined", "DistancesOutlined", "distanceOutline", true),
    toggle("Health", "Health", "healthText", false),
    toggle("Health Outlined", "HealthsOutlined", "healthOutline", true),

    { type = "section", name = "Chams" },
    toggle("Enabled", "Chams", "chams", false),
    toggle("Visible Only", "ChamsVisOnly", "chamsVisibleOnly", false),
    colorFriendly("Team Fill Color", "TeamFillColorChams", {"chamsFillColor"}, Color3.new(0.2,0.2,0.2), 0.5),
    colorFriendly("Team Outline Color", "TeamOutlineColorChams", {"chamsOutlineColor"}, Color3.new(0,1,0), 0),
    colorEnemy("Enemy Fill Color", "EnemyFillColorChams", {"chamsFillColor"}, Color3.new(0.2,0.2,0.2), 0.5),
    colorEnemy("Enemy Outline Color", "EnemyOutlineColorChams", {"chamsOutlineColor"}, Color3.new(1,0,0), 0),

    { type = "section", name = "Off Screen Arrow" },
    toggle("Enabled", "OSA", "offScreenArrow", false),
    slider("Size", "OSASize", {15,50}, 15, 1, "offScreenArrowSize"),
    slider("Radius", "OSARadius", {150,360}, 150, 1, "offScreenArrowRadius"),
    toggle("Outline", "OSAOutlined", "offScreenArrowOutline", true),

    { type = "section", name = "Weapon" },
    toggle("Enabled", "Weapons", "weapon", false),
    toggle("Outline", "WeaponOutlined", "weaponOutline", true),
}

for _, entry in ipairs(ui) do
    createControl(entry)
end

Sense.Load()
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

getgenv().uiLE.loading = false
