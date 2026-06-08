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

local Players    = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

getgenv().uiLE.le = getgenv().uiLE.le
	or loadstring(game:HttpGet("https://raw.githubusercontent.com/AAPVdev/scripts/refs/heads/main/LimbExtender.lua"))()
local LimbExtender = getgenv().uiLE.le

getgenv().RAYFIELD_SECURE = true
getgenv().RAYFIELD_ASSET_ID = 84895246331982
getgenv().uiLE.uilibray = loadstring(game:HttpGet("https://sirius.menu/rayfield"))()
local Rayfield = getgenv().uiLE.uilibray

getgenv().uiLE.gcontroller = LimbExtender.new()

local controller = getgenv().uiLE.gcontroller

-- ── Window ─────────────────────────────────────────────────────────────────────

local UI = {
	Name    = "AXIOS",
	Icon    = 107904589783906,
	LoadingSubtitles = {
		"wtf update? in this economy?",
		"the chatgpt special",
		"racist meme rhetoric here",
		"we are not back ts gon update in the next 5 years",
	},
	Theme = "Default",
}

local function pickRandom(t)
	return t[math.random(1, #t)]
end

local Window = Rayfield:CreateWindow({
	Name                 = UI.Name,
	Icon                 = UI.Icon,
	LoadingTitle         = UI.Name,
	LoadingSubtitle      = pickRandom(UI.LoadingSubtitles),
	Theme                = UI.Theme,
	DisableRayfieldPrompts = true,
	ConfigurationSaving  = {
		Enabled    = true,
		FolderName = "LimbExtenderConfigs",
		FileName   = "Configuration",
	},
})

local Tabs = {
	Limbs  = Window:CreateTab("Limbs",  "scale-3d"),
	Sense  = Window:CreateTab("ESP",  "eye"),
	Target = Window:CreateTab("Target", "crosshair"),
	Themes = Window:CreateTab("Themes", "palette"),
}

-- ── Generic helpers ────────────────────────────────────────────────────────────

local function createToggle(tab, name, flag, default, cb)
	return tab:CreateToggle({
		Name         = name,
		CurrentValue = default,
		Flag         = flag,
		Callback     = cb or function() end,
	})
end

local function createSlider(tab, name, flag, default, range, increment, suffix, cb)
	return tab:CreateSlider({
		Name         = name,
		CurrentValue = default,
		Flag         = flag,
		Range        = range,
		Increment    = increment,
		Suffix       = suffix or "",
		Callback     = cb or function() end,
	})
end

local function createDropdown(tab, name, flag, options, current, multi, cb)
	return tab:CreateDropdown({
		Name            = name,
		Options         = options,
		CurrentOption   = current,
		MultipleOptions = multi,
		Flag            = flag,
		Callback        = cb or function() end,
	})
end

local function createColorPicker(tab, name, flag, default, cb)
	return tab:CreateColorPicker({
		Name     = name,
		Color    = default,
		Flag     = flag,
		Callback = cb or function() end,
	})
end

-- LOD flag table helpers (ESP_NEAR_FLAGS / ESP_MEDIUM_FLAGS / ESP_FAR_FLAGS are
-- plain tables stored in the controller settings, not flat scalars).
local function getLODFlag(settingKey, field)
	local t = controller:Get(settingKey)
	return type(t) == "table" and t[field] or false
end

local function setLODFlag(settingKey, field, value)
	local t = controller:Get(settingKey)
	if type(t) == "table" then
		t[field] = value
		controller:Set(settingKey, t)
	end
end

-- ── Limbs Tab ──────────────────────────────────────────────────────────────────

local modifyLimbsToggle = createToggle(
	Tabs.Limbs, "Modify Limbs", "ModifyLimbs", false,
	function(v) controller:Toggle(v) end
)

Tabs.Limbs:CreateDivider()

local limbSettings = {
	{ kind="Toggle", name="Players",          flag="PLAYER_ENABLED",  default=controller:Get("PLAYER_ENABLED") },
	{ kind="Toggle", name="NPCs",             flag="NPC_ENABLED",     default=controller:Get("NPC_ENABLED"),     dividerAfter=true },
	{ kind="Toggle", name="Team Check",       flag="TEAM_CHECK",      default=controller:Get("TEAM_CHECK") },
	{ kind="Toggle", name="ForceField Check", flag="FORCEFIELD_CHECK",default=controller:Get("FORCEFIELD_CHECK") },
	{ kind="Toggle", name="Limb Collisions",  flag="LIMB_CAN_COLLIDE",default=controller:Get("LIMB_CAN_COLLIDE"),dividerAfter=true },
	{ kind="Slider", name="Limb Transparency",flag="LIMB_TRANSPARENCY",default=controller:Get("LIMB_TRANSPARENCY"),range={0,1},   increment=0.1 },
	{ kind="Slider", name="Limb Size",        flag="LIMB_SIZE",       default=controller:Get("LIMB_SIZE"),       range={5,50},  increment=0.5, dividerAfter=true },
}

for _, s in ipairs(limbSettings) do
	if s.kind == "Toggle" then
		createToggle(Tabs.Limbs, s.name, s.flag, s.default, function(v) controller:Set(s.flag, v) end)
	elseif s.kind == "Slider" then
		createSlider(Tabs.Limbs, s.name, s.flag, s.default, s.range, s.increment, nil, function(v) controller:Set(s.flag, v) end)
	end
	if s.dividerAfter then Tabs.Limbs:CreateDivider() end
end

Tabs.Limbs:CreateKeybind({
	Name           = "Toggle Keybind",
	CurrentKeybind = "L",
	HoldToInteract = false,
	Flag           = "ToggleKeybind",
	Callback = function()
		modifyLimbsToggle:Set(not controller._running)
	end,
})

-- ── Sense Tab ──────────────────────────────────────────────────────────────────

-- ╔══════════════════════════════╗
-- ║  Hitbox ESP                  ║
-- ╚══════════════════════════════╝
Tabs.Sense:CreateSection("Hitbox ESP")

createToggle(Tabs.Sense, "Enabled", "ESPEnabled", controller:Get("ESP"),
	function(v) controller:Set("ESP", v) end)

createToggle(Tabs.Sense, "Filter Local Player", "ESP_FILTER_LOCAL",
	controller:Get("ESP_FILTER_LOCAL"),
	function(v) controller:Set("ESP_FILTER_LOCAL", v) end)

-- ╔══════════════════════════════╗
-- ║  Elements                    ║
-- ╚══════════════════════════════╝
Tabs.Sense:CreateSection("Elements")

local elementDefs = {
	{ name="2D Box",           key="ESP_BOX"             },
	{ name="3D Box",           key="ESP_BOX3D"           },
	{ name="Tracer",           key="ESP_TRACER"          },
	{ name="Skeleton",         key="ESP_SKELETON"        },
	{ name="Health Bar",       key="ESP_HEALTH"          },
	{ name="Label",            key="ESP_LABEL"           },
	{ name="Off-Screen Arrow", key="ESP_OFFSCREEN_POINT" },
}

for _, def in ipairs(elementDefs) do
	createToggle(Tabs.Sense, def.name, def.key, controller:Get(def.key),
		function(v) controller:Set(def.key, v) end)
end

-- ╔══════════════════════════════╗
-- ║  Colors                      ║
-- ╚══════════════════════════════╝
Tabs.Sense:CreateSection("Colors")

local colorDefs = {
	{ name="Box / Tracer",   key="ESP_COLOR"          },
	{ name="3D Box",         key="ESP_BOX3D_COLOR"    },
	{ name="Skeleton",       key="ESP_SKELETON_COLOR" },
	{ name="Health (Full)",  key="ESP_HEALTH_COLOR"   },
	{ name="Health (Empty)", key="ESP_EMPTY_COLOR"    },
	{ name="Text",           key="ESP_TEXT_COLOR"     },
}

for _, def in ipairs(colorDefs) do
	createColorPicker(Tabs.Sense, def.name, "ESPColor_"..def.key,
		controller:Get(def.key),
		function(v) controller:Set(def.key, v) end)
end

-- ╔══════════════════════════════╗
-- ║  Text                        ║
-- ╚══════════════════════════════╝
Tabs.Sense:CreateSection("Text")

createSlider(Tabs.Sense, "Text Size", "ESP_TEXT_SIZE",
	controller:Get("ESP_TEXT_SIZE"), {8, 32}, 1, "px",
	function(v) controller:Set("ESP_TEXT_SIZE", v) end)

-- ╔══════════════════════════════╗
-- ║  Distance Thresholds         ║
-- ╚══════════════════════════════╝
Tabs.Sense:CreateSection("Distance Thresholds")

Tabs.Sense:CreateParagraph({
	Title   = "Level of Detail (LOD)",
	Content = "Targets within Near Distance use the Near feature set. "
	        .. "Between Near and Medium uses the Medium set. "
	        .. "Beyond Medium up to Max Distance uses the Far set. "
	        .. "Configure each set in the sections below.",
})

createSlider(Tabs.Sense, "Near Distance", "ESP_NEAR_DISTANCE",
	controller:Get("ESP_NEAR_DISTANCE"), {50, 500}, 10, "st",
	function(v) controller:Set("ESP_NEAR_DISTANCE", v) end)

createSlider(Tabs.Sense, "Medium Distance", "ESP_MEDIUM_DISTANCE",
	controller:Get("ESP_MEDIUM_DISTANCE"), {100, 1000}, 10, "st",
	function(v) controller:Set("ESP_MEDIUM_DISTANCE", v) end)

createSlider(Tabs.Sense, "Max Distance", "ESP_MAX_DISTANCE",
	controller:Get("ESP_MAX_DISTANCE"), {100, 2000}, 50, "st",
	function(v) controller:Set("ESP_MAX_DISTANCE", v) end)

-- ╔══════════════════════════════╗
-- ║  LOD Feature Flags           ║
-- ╚══════════════════════════════╝
-- Each tier controls which elements are rendered for targets at that range.

local lodFeatures = {
	{ name="2D Box",     field="Box"      },
	{ name="3D Box",     field="Box3D"    },
	{ name="Tracer",     field="Tracer"   },
	{ name="Skeleton",   field="Skeleton" },
	{ name="Health Bar", field="Health"   },
	{ name="Label",      field="Label"    },
}

local lodTiers = {
	{ section="Near Range Features",   key="ESP_NEAR_FLAGS"   },
	{ section="Medium Range Features", key="ESP_MEDIUM_FLAGS" },
	{ section="Far Range Features",    key="ESP_FAR_FLAGS"    },
}

for _, tier in ipairs(lodTiers) do
	Tabs.Sense:CreateSection(tier.section)
	for _, feat in ipairs(lodFeatures) do
		local flagId = tier.key .. "_" .. feat.field
		createToggle(Tabs.Sense, feat.name, flagId,
			getLODFlag(tier.key, feat.field),
			function(v) setLODFlag(tier.key, feat.field, v) end)
	end
end

-- ╔══════════════════════════════╗
-- ║  Performance                 ║
-- ╚══════════════════════════════╝
Tabs.Sense:CreateSection("Performance")

createToggle(Tabs.Sense, "Occlusion Checking", "ESP_OCCLUSION",
	controller:Get("ESP_OCCLUSION"),
	function(v) controller:Set("ESP_OCCLUSION", v) end)

createSlider(Tabs.Sense, "Occlusion Frequency", "ESP_OCCLUSION_FREQUENCY",
	controller:Get("ESP_OCCLUSION_FREQUENCY"), {1, 20}, 1, "frames",
	function(v) controller:Set("ESP_OCCLUSION_FREQUENCY", v) end)

-- ── Target Tab ─────────────────────────────────────────────────────────────────

local targetLimbDropdown = createDropdown(
	Tabs.Target, "Target Limb", "TARGET_LIMB",
	{}, { controller:Get("TARGET_LIMB") }, false,
	function(opts) controller:Set("TARGET_LIMB", opts[1]) end
)

-- ── Themes Tab ─────────────────────────────────────────────────────────────────

createDropdown(
	Tabs.Themes, "Current Theme", "CurrentTheme",
	{ "Default","AmberGlow","Amethyst","Bloom","DarkBlue","Green","Light","Ocean","Serenity" },
	{ "Default" }, false,
	function(opts) Window.ModifyTheme(opts[1]) end
)

-- ── Config load & limb scanner ─────────────────────────────────────────────────

Rayfield:LoadConfiguration()

local limbNames = {}

local function refreshTargetLimbDropdown()
	table.sort(limbNames)
	targetLimbDropdown:Refresh(limbNames)
end

local function addLimbIfNew(name)
	if not name then return end
	if not table.find(limbNames, name) then
		table.insert(limbNames, name)
		refreshTargetLimbDropdown()
	end
end

local function handleCharacter(char)
	if not char then return end
	char.ChildAdded:Connect(function(child)
		if child:IsA("BasePart") then addLimbIfNew(child.Name) end
	end)
	for _, child in ipairs(char:GetChildren()) do
		if child:IsA("BasePart") then addLimbIfNew(child.Name) end
	end
end

LocalPlayer.CharacterAdded:Connect(handleCharacter)
if LocalPlayer.Character then handleCharacter(LocalPlayer.Character) end

getgenv().uiLE.loading = false
