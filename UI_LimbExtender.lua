getgenv().uiLE = getgenv().uiLE or {}
if getgenv().uiLE.loading then return end
getgenv().uiLE.loading = true

if getgenv().uiLE.uilibray    then getgenv().uiLE.uilibray:Destroy()    getgenv().uiLE.uilibray    = nil end
if getgenv().uiLE.gcontroller then getgenv().uiLE.gcontroller:Destroy() getgenv().uiLE.gcontroller = nil end

local LocalPlayer = game:GetService("Players").LocalPlayer

getgenv().uiLE.le = getgenv().uiLE.le
	or loadstring(game:HttpGet("https://raw.githubusercontent.com/AAPVdev/scripts/refs/heads/main/LimbExtender.lua"))()
local LimbExtender = getgenv().uiLE.le

getgenv().RAYFIELD_SECURE   = true
getgenv().RAYFIELD_ASSET_ID = 84895246331982
getgenv().uiLE.uilibray     = loadstring(game:HttpGet("https://sirius.menu/rayfield"))()
local Rayfield = getgenv().uiLE.uilibray

getgenv().uiLE.gcontroller = LimbExtender.new()
local ctrl = getgenv().uiLE.gcontroller

local function createToggle(tab, name, flag, default, cb)
	return tab:CreateToggle({ Name=name, CurrentValue=default, Flag=flag, Callback=cb })
end

local function createSlider(tab, name, flag, default, range, increment, suffix, cb)
	return tab:CreateSlider({ Name=name, CurrentValue=default, Flag=flag, Range=range, Increment=increment, Suffix=suffix or "", Callback=cb })
end

local function createDropdown(tab, name, flag, options, current, multi, cb)
	return tab:CreateDropdown({ Name=name, Options=options, CurrentOption=current, MultipleOptions=multi or false, Flag=flag, Callback=cb })
end

local function createColorPicker(tab, name, flag, default, cb)
	return tab:CreateColorPicker({ Name=name, Color=default, Flag=flag, Callback=cb })
end

local function ctrlToggle(tab, name, flag)
	return createToggle(tab, name, flag, ctrl:Get(flag), function(v) ctrl:Set(flag, v) end)
end

local function ctrlSlider(tab, name, flag, range, increment, suffix)
	return createSlider(tab, name, flag, ctrl:Get(flag), range, increment, suffix, function(v) ctrl:Set(flag, v) end)
end

local function ctrlColor(tab, name, key)
	return createColorPicker(tab, name, "ESPColor_"..key, ctrl:Get(key), function(v) ctrl:Set(key, v) end)
end

local function lodFlag(key, field, value)
	local t = ctrl:Get(key)
	if type(t) ~= "table" then return false end
	if value == nil then return t[field] end
	t[field] = value
	ctrl:Set(key, t)
end

local SUBTITLES = {
	"wtf update? in this economy?",
	"the chatgpt special",
	"racist meme rhetoric here",
	"we are not back ts gon update in the next 5 years",
}

local Window = Rayfield:CreateWindow({
	Name                   = "AXIOS",
	Icon                   = 107904589783906,
	LoadingTitle           = "AXIOS",
	LoadingSubtitle        = SUBTITLES[math.random(#SUBTITLES)],
	Theme                  = "Default",
	DisableRayfieldPrompts = true,
	ConfigurationSaving    = { Enabled=true, FolderName="LimbExtenderConfigs", FileName="Configuration" },
})

local Tabs = {
	Limbs  = Window:CreateTab("Limbs",  "scale-3d"),
	Sense  = Window:CreateTab("ESP",    "eye"),
	Target = Window:CreateTab("Target", "crosshair"),
	Themes = Window:CreateTab("Themes", "palette"),
}

Tabs.Limbs:CreateSection("General")
local modifyLimbsToggle = createToggle(Tabs.Limbs, "Modify Limbs", "ModifyLimbs", false, function(v) ctrl:Toggle(v) end)

Tabs.Limbs:CreateSection("Targets")
ctrlToggle(Tabs.Limbs, "Players", "PLAYER_ENABLED")
ctrlToggle(Tabs.Limbs, "NPCs",    "NPC_ENABLED")

Tabs.Limbs:CreateSection("Filters")
ctrlToggle(Tabs.Limbs, "Team Check",       "TEAM_CHECK")
ctrlToggle(Tabs.Limbs, "ForceField Check", "FORCEFIELD_CHECK")

Tabs.Limbs:CreateSection("Appearance")
ctrlToggle(Tabs.Limbs, "Limb Collisions",   "LIMB_CAN_COLLIDE")
ctrlSlider(Tabs.Limbs, "Limb Transparency", "LIMB_TRANSPARENCY", {0, 1},  0.1)
ctrlSlider(Tabs.Limbs, "Limb Size",         "LIMB_SIZE",         {5, 50}, 0.5)

Tabs.Limbs:CreateSection("Keybind")
Tabs.Limbs:CreateKeybind({
	Name           = "Toggle Keybind",
	CurrentKeybind = "L",
	HoldToInteract = false,
	Flag           = "ToggleKeybind",
	Callback       = function() modifyLimbsToggle:Set(not ctrl._running) end,
})

Tabs.Sense:CreateSection("General")
ctrlToggle(Tabs.Sense, "Enabled",             "ESP")
ctrlToggle(Tabs.Sense, "Filter Local Player", "ESP_FILTER_LOCAL")

Tabs.Sense:CreateSection("Elements")
for _, def in ipairs({
	{ name="2D Box",           key="ESP_BOX"             },
	{ name="3D Box",           key="ESP_BOX3D"           },
	{ name="Tracer",           key="ESP_TRACER"          },
	{ name="Skeleton",         key="ESP_SKELETON"        },
	{ name="Health Bar",       key="ESP_HEALTH"          },
	{ name="Label",            key="ESP_LABEL"           },
	{ name="Off-Screen Arrow", key="ESP_OFFSCREEN_POINT" },
}) do ctrlToggle(Tabs.Sense, def.name, def.key) end

Tabs.Sense:CreateSection("Colors")
for _, def in ipairs({
	{ name="Box / Tracer",   key="ESP_COLOR"          },
	{ name="3D Box",         key="ESP_BOX3D_COLOR"    },
	{ name="Skeleton",       key="ESP_SKELETON_COLOR" },
	{ name="Health (Full)",  key="ESP_HEALTH_COLOR"   },
	{ name="Health (Empty)", key="ESP_EMPTY_COLOR"    },
	{ name="Text",           key="ESP_TEXT_COLOR"     },
}) do ctrlColor(Tabs.Sense, def.name, def.key) end

Tabs.Sense:CreateSection("Text")
ctrlSlider(Tabs.Sense, "Text Size", "ESP_TEXT_SIZE", {8, 32}, 1, "px")

Tabs.Sense:CreateSection("Distance Thresholds")
Tabs.Sense:CreateParagraph({
	Title   = "Level of Detail (LOD)",
	Content = "Targets within Near Distance use the Near feature set. "
	        .. "Between Near and Medium uses the Medium set. "
	        .. "Beyond Medium up to Max Distance uses the Far set. "
	        .. "Configure each set in the sections below.",
})
for _, s in ipairs({
	{ name="Near Distance",   flag="ESP_NEAR_DISTANCE",   range={50,  500},  increment=10 },
	{ name="Medium Distance", flag="ESP_MEDIUM_DISTANCE", range={100, 1000}, increment=10 },
	{ name="Max Distance",    flag="ESP_MAX_DISTANCE",    range={100, 2000}, increment=50 },
}) do ctrlSlider(Tabs.Sense, s.name, s.flag, s.range, s.increment, "st") end

local LOD_FEATURES = {
	{ name="2D Box",     field="Box"      },
	{ name="3D Box",     field="Box3D"    },
	{ name="Tracer",     field="Tracer"   },
	{ name="Skeleton",   field="Skeleton" },
	{ name="Health Bar", field="Health"   },
	{ name="Label",      field="Label"    },
}
for _, tier in ipairs({
	{ section="Near Range Features",   key="ESP_NEAR_FLAGS"   },
	{ section="Medium Range Features", key="ESP_MEDIUM_FLAGS" },
	{ section="Far Range Features",    key="ESP_FAR_FLAGS"    },
}) do
	Tabs.Sense:CreateSection(tier.section)
	for _, feat in ipairs(LOD_FEATURES) do
		createToggle(Tabs.Sense, feat.name, tier.key.."_"..feat.field,
			lodFlag(tier.key, feat.field),
			function(v) lodFlag(tier.key, feat.field, v) end)
	end
end

Tabs.Sense:CreateSection("Performance")
ctrlToggle(Tabs.Sense, "Occlusion Checking",  "ESP_OCCLUSION")
ctrlSlider(Tabs.Sense, "Occlusion Frequency", "ESP_OCCLUSION_FREQUENCY", {1, 20}, 1, "frames")

local targetLimbDropdown = createDropdown(
	Tabs.Target, "Target Limb", "TARGET_LIMB",
	{}, { ctrl:Get("TARGET_LIMB") }, false,
	function(opts) ctrl:Set("TARGET_LIMB", opts[1]) end
)

createDropdown(
	Tabs.Themes, "Current Theme", "CurrentTheme",
	{ "Default","AmberGlow","Amethyst","Bloom","DarkBlue","Green","Light","Ocean","Serenity" },
	{ "Default" }, false,
	function(opts) Window:ModifyTheme(opts[1]) end
)

Rayfield:LoadConfiguration()

local limbNames = {}

local function addLimbIfNew(name)
	if not name or table.find(limbNames, name) then return end
	table.insert(limbNames, name)
	table.sort(limbNames)
	targetLimbDropdown:Refresh(limbNames)
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
