local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

local Axios = {}

local Sense = loadstring(game:HttpGet('https://raw.githubusercontent.com/jensonhirst/Sirius/request/library/sense/source.lua'))()
local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()
local LimbExtender = loadstring(game:HttpGet('https://raw.githubusercontent.com/AAPVdev/scripts/refs/heads/main/LimbExtender.lua'))()

Axios.Config = {
    Theme = "Default",
    Sense = {
        team = { enemy = true, friendly = true },
        visuals = {
            box = { enabled = false, outline = true, fill = false },
            box3d = false,
            tracers = { enabled = false, outline = true, origin = "Bottom" },
            tags = { name = false, distance = false, health = false },
            healthBar = { enabled = false, outline = true },
            chams = { enabled = false, visibleOnly = false },
            offScreenArrow = { enabled = false, size = 15, radius = 150, outline = true },
            weapon = { enabled = false, outline = true }
        },
        colors = {
            friendly = { box = Color3.fromRGB(0,255,0), fill = Color3.fromRGB(0,150,0), chams = Color3.fromRGB(0,255,0) },
            enemy =    { box = Color3.fromRGB(255,0,0), fill = Color3.fromRGB(255,100,100), chams = Color3.fromRGB(255,0,0) }
        }
    },
    LimbExtender = {
        running = false,
        settings = {
            TEAM_CHECK = LimbExtender.TEAM_CHECK,
            FORCEFIELD_CHECK = LimbExtender.TEAM_CHECK,
            COLLISIONS = LimbExtender.LIMB_CAN_COLLIDE,
            TRANSPARENCY = LimbExtender.LIMB_TRANSPARENCY,
            SIZE = LimbExtender.LIMB_SIZE,
        },
        keybind = LimbExtender.TOGGLE
    }
}

function Axios:Init()
    Sense.teamSettings.enemy.enabled = self.Config.Sense.team.enemy
    Sense.teamSettings.friendly.enabled = self.Config.Sense.team.friendly
    Sense.Load()

    self:BuildGUI()
    LimbExtender.LISTEN_FOR_INPUT = false
    for flag, val in pairs(self.Config.LimbExtender.settings) do
        LimbExtender[flag] = val
    end
end

function Axios:BuildGUI()
    local Window = Rayfield:CreateWindow({
        Name = "AXIOS",
        Icon = 107904589783906,
        LoadingTitle = "AXIOS",
        LoadingSubtitle = "Welcome to AXIOS",
        Theme = self.Config.Theme,
        DisableRayfieldPrompts = true,
        ConfigurationSaving = { Enabled = true, FolderName = "AXIOSConfigs", FileName = "Config" }
    })

    local TabLimbs  = Window:CreateTab("Limbs", "scale-3d")
    local TabSense  = Window:CreateTab("Sense", "eye")
    local TabTarget = Window:CreateTab("Target", "crosshair")
    local TabTheme  = Window:CreateTab("Themes", "palette")

    TabSense:CreateSection("Team Settings")
    TabSense:CreateToggle({ Name = "Enable Enemy ESP", CurrentValue = self.Config.Sense.team.enemy, Flag = "ESPEnemy", Callback = function(v)
        Sense.teamSettings.enemy.enabled = v
    end })
    TabSense:CreateToggle({ Name = "Enable Friendly ESP", CurrentValue = self.Config.Sense.team.friendly, Flag = "ESPFriendly", Callback = function(v)
        Sense.teamSettings.friendly.enabled = v
    end })

    TabSense:CreateSection("Boxes")
    TabSense:CreateToggle({ Name = "Enable Boxes", CurrentValue = self.Config.Sense.visuals.box.enabled, Flag = "Boxes", Callback = function(v)
        self.Config.Sense.visuals.box.enabled = v; Sense.options.box = v
    end })
    TabSense:CreateToggle({ Name = "Fill Boxes", CurrentValue = self.Config.Sense.visuals.box.fill, Flag = "BoxFill", Callback = function(v)
        self.Config.Sense.visuals.box.fill = v; Sense.options.boxFill = v
    end })

    TabSense:CreateSection("Tracers")
    TabSense:CreateToggle({ Name = "Enable Tracers", CurrentValue = self.Config.Sense.visuals.tracers.enabled, Flag = "Tracers", Callback = function(v)
        self.Config.Sense.visuals.tracers.enabled = v; Sense.options.tracer = v
    end })
    TabSense:CreateDropdown({ Name = "Tracer Origin", Options = {"Bottom","Top","Mouse"}, CurrentOption = self.Config.Sense.visuals.tracers.origin, Flag = "TracerOrigin", Callback = function(opt)
        self.Config.Sense.visuals.tracers.origin = opt; Sense.options.tracerOrigin = opt
    end })

    TabSense:CreateColorPicker({ Name = "Friendly Color", Color = self.Config.Sense.colors.friendly.box, Flag = "FriendlyColor", Callback = function(c)
        self.Config.Sense.colors.friendly.box = c
        Sense.teamSettings.friendly.boxColor = {c,1}
    end })
    TabSense:CreateColorPicker({ Name = "Enemy Color", Color = self.Config.Sense.colors.enemy.box, Flag = "EnemyColor", Callback = function(c)
        self.Config.Sense.colors.enemy.box = c
        Sense.teamSettings.enemy.boxColor = {c,1}
    end })

    TabLimbs:CreateToggle({ Name = "Enable LimbExtender", CurrentValue = false, Flag = "ToggleLimbs", Callback = function(v)
        self.Config.LimbExtender.running = v
        LimbExtender.toggleState(v)
    end })
    TabLimbs:CreateDivider()
    TabLimbs:CreateToggle({ Name = "Team Check", CurrentValue = self.Config.LimbExtender.settings.TEAM_CHECK, Flag = "TeamCheck", Callback = function(v)
        self.Config.LimbExtender.settings.TEAM_CHECK = v; LimbExtender.TEAM_CHECK = v
    end })
    TabLimbs:CreateSlider({ Name = "Limb Size", Range = {5,50}, CurrentValue = self.Config.LimbExtender.settings.SIZE, Flag = "LimbSize", Callback = function(v)
        self.Config.LimbExtender.settings.SIZE = v; LimbExtender.LIMB_SIZE = v
    end })
    TabLimbs:CreateSlider({ Name = "Transparency", Range = {0,1}, Increment = 0.1, CurrentValue = self.Config.LimbExtender.settings.TRANSPARENCY, Flag = "LimbTransparency", Callback = function(v)
        self.Config.LimbExtender.settings.TRANSPARENCY = v; LimbExtender.LIMB_TRANSPARENCY = v
    end })
    TabLimbs:CreateKeybind({ Name = "Toggle Keybind", CurrentKeybind = self.Config.LimbExtender.keybind, Flag = "LimbKey", Callback = function()
        local newVal = not self.Config.LimbExtender.running
        self.Config.LimbExtender.running = newVal; LimbExtender.toggleState(newVal)
    end })

    local targetDropdown = TabTarget:CreateDropdown({ Name = "Target Limb", Options = {}, CurrentOption = {LimbExtender.TARGET_LIMB}, MultipleOptions = false, Flag = "TargetLimb", Callback = function(opt)
        LimbExtender.TARGET_LIMB = opt[1]
    end })
    LocalPlayer.CharacterAdded:Connect(function(char)
        for _, part in ipairs(char:GetChildren()) do
            if part:IsA("BasePart") then table.insert(Axios._limbList, part.Name) end
        end
        table.sort(Axios._limbList)
        targetDropdown:Refresh(Axios._limbList)
    end)

    TabTheme:CreateDropdown({ Name = "Theme", Options = {"Default", "AmberGlow", "Amethyst", "Bloom", "DarkBlue", "Green", "Light", "Ocean", "Serenity"}, CurrentOption = {self.Config.Theme}, MultipleOptions = false, Flag = "ThemeSelect", Callback = function(opt)
        self.Config.Theme = opt[1]; Window.ModifyTheme(opt[1])
    end })

    Rayfield:LoadConfiguration()
end

Axios._limbList = {}
Axios:Init()
