getgenv().uiLE = getgenv().uiLE or {}
if getgenv().uiLE.loading then return end
getgenv().uiLE.loading = true

local function fetchUrlList(urls)
    for _, url in ipairs(urls) do
        local ok, result = pcall(function() return game:HttpGet(url) end)
        if ok and result and result ~= "" then return result end
    end
    return nil
end

local function tryLoadFromURL(url)
    local content = fetchUrlList({url})
    if not content then return nil end
    local func = loadstring(content)
    if not func then return nil end
    local ok, result = pcall(func)
    if not ok then return nil end
    return result
end

local function safeLoadString(urls)
    for _, url in ipairs(urls) do
        local result = tryLoadFromURL(url)
        if result then return result end
    end
    return nil
end

local limbExtenderURLs = {
    "https://raw.githubusercontent.com/AAPVdev/scripts/refs/heads/main/LimbExtender.lua",
    "https://api.rubis.app/v2/scrap/DkwppyJ0KaQvou0r/raw"
}
getgenv().uiLE.le = getgenv().uiLE.le or safeLoadString(limbExtenderURLs)
if not getgenv().uiLE.le then getgenv().uiLE.loading = false; return end

if getgenv().uiLE.gcontroller then
    getgenv().uiLE.gcontroller:Destroy()
    getgenv().uiLE.gcontroller = nil
end
getgenv().uiLE.gcontroller = getgenv().uiLE.le.new()
local ctrl = getgenv().uiLE.gcontroller

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local UserInputService = game:GetService("UserInputService")
local isPC = UserInputService:GetPlatform() == Enum.Platform.Windows or UserInputService:GetPlatform() == Enum.Platform.OSX

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

getgenv().uiLE.targetLimbDropdown = nil
getgenv().uiLE.whitelistTeamsDropdown = nil
getgenv().uiLE.blacklistTeamsDropdown = nil
getgenv().uiLE.whitelistPlayersDropdown = nil
getgenv().uiLE.blacklistPlayersDropdown = nil

local scannedLimbs = {}
local limbPriority = {
    "Head","HumanoidRootPart","UpperTorso","LowerTorso","Torso",
    "LeftUpperArm","LeftLowerArm","LeftHand","RightUpperArm","RightLowerArm","RightHand",
    "Left Arm","Right Arm",
    "LeftUpperLeg","LeftLowerLeg","LeftFoot","RightUpperLeg","RightLowerLeg","RightFoot",
    "Left Leg","Right Leg",
}

local function getLimbPriority(name)
    local lower = name:lower()
    for index, limb in ipairs(limbPriority) do
        if lower:find(limb:lower(), 1, true) then return index end
    end
    return math.huge
end

local function sortLimbs()
    table.sort(scannedLimbs, function(a, b)
        local pa = getLimbPriority(a)
        local pb = getLimbPriority(b)
        if pa ~= pb then return pa < pb end
        return a:lower() < b:lower()
    end)
end

local function registerLimb(name)
    if not name or table.find(scannedLimbs, name) then return end
    table.insert(scannedLimbs, name)
    sortLimbs()
    if getgenv().uiLE.targetLimbDropdown then
        getgenv().uiLE.targetLimbDropdown:Refresh(scannedLimbs)
    end
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
end

local charAddedConn
local function InitializeLimbScanning()
    if charAddedConn then charAddedConn:Disconnect() end
    charAddedConn = LocalPlayer.CharacterAdded:Connect(function(character)
        scanCharacter(character)
        character.DescendantAdded:Connect(function(desc)
            if desc:IsA("BasePart") then registerLimb(getPartPath(desc, character)) end
        end)
    end)
    if LocalPlayer.Character then
        scanCharacter(LocalPlayer.Character)
        LocalPlayer.Character.DescendantAdded:Connect(function(desc)
            if desc:IsA("BasePart") then registerLimb(getPartPath(desc, LocalPlayer.Character)) end
        end)
    end
end

local scannedTeams = {}

local function sortTeams()
    table.sort(scannedTeams, function(a, b) return a:lower() < b:lower() end)
end

local function registerTeam(name)
    if not name or table.find(scannedTeams, name) then return end
    table.insert(scannedTeams, name)
    sortTeams()
    if getgenv().uiLE.whitelistTeamsDropdown then
        getgenv().uiLE.whitelistTeamsDropdown:Refresh(scannedTeams)
    end
    if getgenv().uiLE.blacklistTeamsDropdown then
        getgenv().uiLE.blacklistTeamsDropdown:Refresh(scannedTeams)
    end
end

local function unregisterTeam(name)
    local idx = table.find(scannedTeams, name)
    if idx then
        table.remove(scannedTeams, idx)
        if getgenv().uiLE.whitelistTeamsDropdown then
            getgenv().uiLE.whitelistTeamsDropdown:Refresh(scannedTeams)
        end
        if getgenv().uiLE.blacklistTeamsDropdown then
            getgenv().uiLE.blacklistTeamsDropdown:Refresh(scannedTeams)
        end
    end
end

local function scanTeams()
    table.clear(scannedTeams)
    local teamsService = game:GetService("Teams")
    for _, team in ipairs(teamsService:GetChildren()) do
        if team:IsA("Team") then
            registerTeam(team.Name)
        end
    end
end

local teamsConn
local function InitializeTeamScanning()
    if teamsConn then teamsConn:Disconnect() end
    local teamsService = game:GetService("Teams")
    scanTeams()
    teamsConn = teamsService.ChildAdded:Connect(function(child)
        if child:IsA("Team") then registerTeam(child.Name) end
    end)
    teamsService.ChildRemoved:Connect(function(child)
        if child:IsA("Team") then unregisterTeam(child.Name) end
    end)
end

local scannedPlayers = {}
local nameToUserId = {}
local userIdToName = {}

local function sortPlayers()
    table.sort(scannedPlayers, function(a, b) return a:lower() < b:lower() end)
end

local function registerPlayer(player)
    if not player or not player:IsA("Player") then return end
    local name = player.Name
    if table.find(scannedPlayers, name) then return end
    table.insert(scannedPlayers, name)
    nameToUserId[name] = player.UserId
    userIdToName[player.UserId] = name
    sortPlayers()
    if getgenv().uiLE.whitelistPlayersDropdown then
        getgenv().uiLE.whitelistPlayersDropdown:Refresh(scannedPlayers)
    end
    if getgenv().uiLE.blacklistPlayersDropdown then
        getgenv().uiLE.blacklistPlayersDropdown:Refresh(scannedPlayers)
    end
end

local function unregisterPlayer(player)
    if not player or not player:IsA("Player") then return end
    local name = player.Name
    local idx = table.find(scannedPlayers, name)
    if idx then
        table.remove(scannedPlayers, idx)
        nameToUserId[name] = nil
        userIdToName[player.UserId] = nil
        if getgenv().uiLE.whitelistPlayersDropdown then
            getgenv().uiLE.whitelistPlayersDropdown:Refresh(scannedPlayers)
        end
        if getgenv().uiLE.blacklistPlayersDropdown then
            getgenv().uiLE.blacklistPlayersDropdown:Refresh(scannedPlayers)
        end
    end
end

local function scanPlayers()
    table.clear(scannedPlayers)
    table.clear(nameToUserId)
    table.clear(userIdToName)
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            registerPlayer(player)
        end
    end
end

local playerAddedConn, playerRemovingConn
local function InitializePlayerScanning()
    if playerAddedConn then playerAddedConn:Disconnect() end
    if playerRemovingConn then playerRemovingConn:Disconnect() end
    scanPlayers()
    playerAddedConn = Players.PlayerAdded:Connect(function(player)
        if player ~= LocalPlayer then registerPlayer(player) end
    end)
    playerRemovingConn = Players.PlayerRemoving:Connect(function(player)
        unregisterPlayer(player)
    end)
end

local function userIdArrayToNames(userIdArray)
    if type(userIdArray) ~= "table" then return {} end
    local names = {}
    for _, uid in ipairs(userIdArray) do
        local name = userIdToName[uid]
        if name then table.insert(names, name) end
    end
    return names
end

local function normalizeVersion(s)
    if not s then return nil end
    return tostring(s):gsub("^%s+", ""):gsub("%s+$", ""):gsub("^v", "")
end

local CONFIG_FILE = "AXIOS_Config.json"
local HttpService = game:GetService("HttpService")

local function loadConfig()
    if not (isfile and readfile) then return {} end
    if not isfile(CONFIG_FILE) then return {} end
    local ok, data = pcall(function() return readfile(CONFIG_FILE) end)
    if not ok or not data then return {} end
    local ok2, tbl = pcall(function() return HttpService:JSONDecode(data) end)
    if ok2 and type(tbl) == "table" then return tbl end
    return {}
end

local function saveConfig(tbl)
    if not (writefile and type(tbl) == "table") then return false end
    local ok, json = pcall(function() return HttpService:JSONEncode(tbl) end)
    if not ok then return false end
    local ok2 = pcall(function() writefile(CONFIG_FILE, json) end)
    return ok2
end

local function persist_seen_version(ver)
    if not ver then return end
    local norm = normalizeVersion(ver)
    local cfg = loadConfig()
    cfg.lastSeenVersion = norm
    saveConfig(cfg)
end

local function load_seen_from_file()
    local cfg = loadConfig()
    return normalizeVersion(cfg.lastSeenVersion)
end

local function saveUIVersion(version)
    local cfg = loadConfig()
    cfg.uiVersion = version
    saveConfig(cfg)
end

local function loadUIVersion()
    local cfg = loadConfig()
    if cfg.uiVersion == 1 or cfg.uiVersion == 2 then
        return cfg.uiVersion
    end
    return 2
end

getgenv().ChangelogHelper = getgenv().ChangelogHelper or (function()
    local M = {}
    local changelogs = {}
    local tabHandle

    local function buildBoxes(sections)
        local boxes = {}
        for _, sec in ipairs(sections or {}) do
            local desc = ""
            for i, it in ipairs(sec.items or {}) do
                desc = desc .. "• " .. it .. (i < #sec.items and "\n" or "")
            end
            table.insert(boxes, { title = sec.title, description = desc })
        end
        return boxes
    end

    local function showPopup(window, entry)
        if not window or not entry then return end
        local content = nil
        if entry.highlights and #entry.highlights > 0 then content = "Highlights:\n" .. table.concat(entry.highlights, "\n• ") end
        local popup = {
            title = entry.version or "Changelog",
            subtitle = entry.date,
            content = content,
            boxes = buildBoxes(entry.sections),
            options = {
                { text = "Close", style = "primary" },
                { text = "Copy notes", style = "neutral", callback = function()
                    if setclipboard then
                        local md = "# " .. (entry.version or "Changelog") .. "\n"
                        if entry.date then md = md .. "_"..entry.date.."_\n\n" end
                        if entry.highlights then
                            md = md .. "## Highlights\n"
                            for _, h in ipairs(entry.highlights) do md = md .. "- " .. h .. "\n" end
                            md = md .. "\n"
                        end
                        for _, s in ipairs(entry.sections or {}) do
                            md = md .. "## " .. s.title .. "\n"
                            for _, it in ipairs(s.items or {}) do md = md .. "- " .. it .. "\n" end
                            md = md .. "\n"
                        end
                        setclipboard(md)
                    end
                end },
            },
            dismissable = true,
        }
        window:Popup(popup)
    end

    local function createTab(window)
        if tabHandle then return tabHandle end
        if not window then return nil end
        local t = window:CreateTab({ name = "Changelog" })
        t:CreateSection({ name = "Releases" })
        for i, entry in ipairs(changelogs) do
            local title = entry.version or ("Release " .. i)
            local descr = entry.date or ""
            t:CreateButton({
                name = title,
                description = descr,
                callback = function()
                    showPopup(window, entry)
                    persist_seen_version(entry.version)
                end,
            })
        end
        tabHandle = t
        return t
    end

    M.add = function(entry)
        table.insert(changelogs, 1, entry or {})
        tabHandle = nil
    end

    M.reset = function()
        table.clear(changelogs)
        tabHandle = nil
    end

    M.register = function(window, opts)
        createTab(window)
        opts = opts or {}
        local latestRaw = changelogs[1] and changelogs[1].version
        if not latestRaw then return end
        local latest = normalizeVersion(latestRaw)
        local seen = load_seen_from_file()
        local wantPopups = window:Get("Changelog.ShowPopups")
        if wantPopups == nil then wantPopups = true end

        local function parseFullSemver(v)
            if not v then return nil end
            local major, minor, patch = v:match("^(%d+)%.(%d+)%.?(%d*)$")
            return tonumber(major), tonumber(minor), tonumber(patch) or 0
        end

        local function significant(oldV, newV)
            if not newV then return false end
            if not oldV then return true end
            local o1,o2 = parseFullSemver(oldV) 
            local n1,n2 = parseFullSemver(newV) 
            if not (o1 and n1) then return true end
            if n1 > o1 then return true end
            if (n2 and o2) and n2 > o2 then return true end
            return false
        end

        if seen == latest then return end

        local entryToShow
        if seen == nil then
            local latestMajor, latestMinor, latestPatch = parseFullSemver(latest)
            for i, entry in ipairs(changelogs) do
                local major, minor, patch = parseFullSemver(entry.version)
                if major == latestMajor and minor == latestMinor and patch == 0 then
                    entryToShow = entry
                    break
                end
            end
            entryToShow = entryToShow or changelogs[1]
        else
            entryToShow = changelogs[1]
        end

        if entryToShow then
            if significant(seen, entryToShow.version) and wantPopups and opts.showPopupOnUpdate ~= false then
                local shouldNotify = true
                if entryToShow.notify ~= nil then shouldNotify = entryToShow.notify end
                if shouldNotify then
                    window:Toast({ title = "New update: " .. (entryToShow.version or latest), subtitle = (entryToShow.date or "") })
                    task.spawn(function()
                        task.wait(0.18)
                        showPopup(window, entryToShow)
                    end)
                else
                    window:Toast({ title = "Updated to " .. (entryToShow.version or latest) })
                end
                persist_seen_version(entryToShow.version)
            else
                window:Toast({ title = "Updated: " .. (entryToShow.version or latest) })
                persist_seen_version(entryToShow.version)
            end
        end
    end

    M.list = function() return changelogs end
    return M
end)()

local function loadRemoteChangelogs()
    local changelogURLs = {
        "https://raw.githubusercontent.com/AAPVdev/scripts/refs/heads/main/changelogs.json",
        "https://api.rubis.app/v2/scrap/btATRjMxQttd1sy8/raw"
    }
    for _, url in ipairs(changelogURLs) do
        local content = fetchUrlList({url})
        if content then
            local success, data = pcall(function() return game:GetService("HttpService"):JSONDecode(content) end)
            if success and type(data) == "table" then
                for i = #data, 1, -1 do
                    getgenv().ChangelogHelper.add(data[i])
                end
                return true
            end
        end
    end
    return false
end

local function BuildUI(version)
    local oldActive = getgenv().uiLE.ActiveUI
    if oldActive then
        local w = oldActive.Window
        local v = oldActive.version
        if v == 1 then
            getgenv().uiLE.uilibray:Destroy()
        elseif v == 2 then
            w:Unload()
        end
        getgenv().uiLE.ActiveUI = nil
    end

    saveUIVersion(version)
    getgenv().uiLE.uiVersion = version

    getgenv().RAYFIELD_SECURE = true
    getgenv().RAYFIELD_ASSET_ID = 84895246331982

    local libURL = version == 1 and "https://sirius.menu/rayfield" or "https://sirius.menu/gen2"
    getgenv().uiLE.uilibray = safeLoadString({libURL})
    if not getgenv().uiLE.uilibray then getgenv().uiLE.loading = false; return end

    local Rayfield = getgenv().uiLE.uilibray

    local LOADING_SUBTITLES = {
        "multiply by delta",
        "working for the cia",
        "shoutout serene fr",
        "avis was here",
        "seizure causing soap?",
        "skids skid from skids"
    }

    local Window
    if version == 1 then
        Window = Rayfield:CreateWindow({
            Name = "AXIOS",
            ScriptID = "sid_k2rgzy25rkgy",
            LoadingTitle = "AXIOS",
            LoadingSubtitle = LOADING_SUBTITLES[math.random(#LOADING_SUBTITLES)],
            Theme = "Default",
            DisableRayfieldPrompts = true,
            ConfigurationSaving = {
                Enabled = true,
                FolderName = "LimbExtenderConfigs",
                FileName = "Configuration",
            },
        })
    else
        Window = Rayfield:CreateWindow({
            name = "AXIOS",
            subtitle = LOADING_SUBTITLES[math.random(#LOADING_SUBTITLES)],
            theme = "default",
            configuration = {
                autoSave = true,
                autoLoad = true,
                fileName = "Configuration",
                customFolder = "LimbExtenderConfigs",
            },
        })
        getgenv().uiLE.uilibray.Window = Window
    end

    getgenv().uiLE.ActiveUI = {Window = Window, version = version}

    local function createSection(tab, title)
        if version == 1 then tab:CreateSection(title) else tab:CreateSection({ name = title }) end
    end

    local function createToggle(tab, name, flag, default, customCallback)
        default = default or false
        local saved = ctrl:Get(flag)
        local value = saved ~= nil and saved or default
        local callbackFn = customCallback or function(v) ctrl:Set(flag, v) end
        if version == 1 then
            return tab:CreateToggle({
                Name = name, Flag = flag, CurrentValue = value,
                Callback = function(v)
                    callbackFn(v)
                    ctrl:Set(flag, v)
                end,
            })
        else
            return tab:CreateToggle({
                name = name, flag = flag, value = value,
                callback = function(v)
                    callbackFn(v)
                    ctrl:Set(flag, v)
                end,
            })
        end
    end

    local function createSlider(tab, name, flag, range, increment, suffix, default)
        default = default or range[1]
        local saved = ctrl:Get(flag)
        local value = saved ~= nil and saved or default
        if version == 1 then
            return tab:CreateSlider({
                Name = name, Flag = flag, CurrentValue = value,
                Range = range, Increment = increment, Suffix = suffix or "",
                Callback = function(v) ctrl:Set(flag, v) end,
            })
        else
            return tab:CreateSlider({
                name = name, flag = flag, value = value,
                range = range, increment = increment, suffix = suffix or "",
                callback = function(v) ctrl:Set(flag, v) end,
            })
        end
    end

    local function createColorPicker(tab, name, flag)
        local saved = ctrl:Get(flag)
        local color = saved or Color3.new(1, 1, 1)
        if version == 1 then
            return tab:CreateColorPicker({
                Name = name, Flag = flag, Color = color,
                Callback = function(v) ctrl:Set(flag, v) end,
            })
        else
            return tab:CreateColorPicker({
                name = name, flag = flag, value = color,
                callback = function(v) ctrl:Set(flag, v) end,
            })
        end
    end

    local function createKeybind(tab, name, flag, defaultKey, callback)
        if version == 1 then
            return tab:CreateKeybind({
                Name = name, Flag = flag, CurrentKeybind = defaultKey,
                HoldToInteract = false, Callback = callback,
            })
        else
            return tab:CreateKeybind({
                name = name, flag = flag, value = Enum.KeyCode[defaultKey] or Enum.KeyCode.L,
                holdToInteract = false, callback = callback,
                onChanged = function(newKey) ctrl:Set(flag, newKey) end,
            })
        end
    end

    local function createDropdown(tab, name, flag, options, defaultOption, multi, callback)
        if version == 1 then
            local currentOption = defaultOption and (multi and defaultOption or {defaultOption}) or {}
            return tab:CreateDropdown({
                Name = name, Flag = flag, Options = options,
                CurrentOption = currentOption, MultipleOptions = multi or false,
                Callback = function(opts)
                    if multi then callback(opts) else callback(opts[1]) end
                end,
            })
        else
            return tab:CreateDropdown({
                name = name, flag = flag, options = options,
                value = defaultOption, multiSelect = multi or false,
                callback = function(selection)
                    callback(selection)
                end,
            })
        end
    end

    local function createButton(tab, name, callback)
        if version == 1 then
            return tab:CreateButton({ Name = name, Callback = callback })
        else
            return tab:CreateButton({ name = name, callback = callback })
        end
    end

    local function createParagraph(tab, title, content)
        if version == 1 then
            tab:CreateParagraph({ Title = title, Content = content })
        end
    end

    local Tabs = {
        General    = version == 1 and Window:CreateTab("General")  or Window:CreateTab({ name = "General" }),
        Targeting  = version == 1 and Window:CreateTab("Targeting") or Window:CreateTab({ name = "Targeting" }),
        Appearance = version == 1 and Window:CreateTab("Appearance")   or Window:CreateTab({ name = "Appearance" }),
    }
    if isPC then
        Tabs.ESP = version == 1 and Window:CreateTab("ESP") or Window:CreateTab({ name = "ESP" })
    end

    createSection(Tabs.General, "Master Control")

    local flagModify = "ModifyLimbs"
    local modifySaved = ctrl:Get(flagModify)
    local modifyVal = modifySaved ~= nil and modifySaved or false

    local modifyLimbsToggle
    if version == 1 then
        modifyLimbsToggle = Tabs.General:CreateToggle({
            Name = "Modify Limbs",
            Flag = flagModify,
            CurrentValue = modifyVal,
            Callback = function(v)
                ctrl:Set(flagModify, v)
                ctrl:Toggle(v)
            end,
        })
    else
        modifyLimbsToggle = Tabs.General:CreateToggle({
            name = "Modify Limbs",
            flag = flagModify,
            value = modifyVal,
            callback = function(v)
                ctrl:Set(flagModify, v)
                ctrl:Toggle(v)
            end,
        })
    end

    local function toggleLimbs()
        modifyLimbsToggle:Set(not ctrl._running)
    end
    createKeybind(Tabs.General, "Toggle Keybind", "ToggleKeybind", "L", toggleLimbs)

    createSection(Tabs.General, "Theme")

    local themes, defaultTheme
    if version == 1 then
        themes = { "Default", "AmberGlow", "Amethyst", "Bloom", "DarkBlue", "Green", "Light", "Ocean", "Serenity" }
        defaultTheme = "Default"
    else
        themes = { "default", "cobalt", "ember", "amethyst", "frost", "rose" }
        defaultTheme = "default"
    end

    createDropdown(Tabs.General, "Current Theme", "CurrentTheme", themes, defaultTheme, false, function(selected)
        if selected then
            if version == 1 then Window.ModifyTheme(selected) else Window:ChangeTheme(selected) end
        end
    end)

    local switchLabel = version == 1 and "Switch to Gen2 UI" or "Switch to Gen1 UI"
    createButton(Tabs.General, switchLabel, function()
        local newVersion = version == 1 and 2 or 1
        BuildUI(newVersion)
    end)

    createSection(Tabs.Targeting, "Target Selection")
    createToggle(Tabs.Targeting, "Players", "PLAYER_ENABLED", true)
    createToggle(Tabs.Targeting, "NPCs", "NPC_ENABLED", false)
    createToggle(Tabs.Targeting, "ForceField Check", "FORCEFIELD_CHECK", false)

    local teamModeOptions = {"None", "Different Team", "Whitelist", "Blacklist"}
    local teamModeValues = {"none", "different", "whitelist", "blacklist"}
    local savedTeamMode = ctrl:Get("TEAM_MODE") or "none"
    local defaultTeamOption = "None"
    for i, v in ipairs(teamModeValues) do
        if v == savedTeamMode then defaultTeamOption = teamModeOptions[i]; break end
    end
    createDropdown(Tabs.Targeting, "Team Filter", "TEAM_MODE", teamModeOptions, defaultTeamOption, false, function(selected)
        local mode = "none"
        for i, opt in ipairs(teamModeOptions) do
            if opt == selected then mode = teamModeValues[i]; break end
        end
        ctrl:Set("TEAM_MODE", mode)
    end)

    createSection(Tabs.Targeting, "Limb Focus")
    local existingLimbs = #scannedLimbs > 0 and table.clone(scannedLimbs) or {"Head"}
    local targetLimbDropdown = createDropdown(Tabs.Targeting, "Target Limb", "TARGET_LIMB",
        existingLimbs, ctrl:Get("TARGET_LIMB") or "Head", false, function(selected)
            if type(selected) == "table" then selected = selected[1] end
            ctrl:Set("TARGET_LIMB", selected)
        end)
    getgenv().uiLE.targetLimbDropdown = targetLimbDropdown

    createSection(Tabs.Targeting, "Team Lists")
    local savedTeamWhitelist = ctrl:Get("TEAM_WHITELIST") or {}
    local savedTeamBlacklist = ctrl:Get("TEAM_BLACKLIST") or {}
    local teamOptions = #scannedTeams > 0 and table.clone(scannedTeams) or {"(no teams found)"}

    local whitelistTeamsCallback = function(selected)
        ctrl:Set("TEAM_WHITELIST", type(selected) == "table" and selected or {selected})
    end
    local whitelistTeamsDropdown = createDropdown(Tabs.Targeting, "Whitelist Teams", "TEAM_WHITELIST_DROPDOWN",
        teamOptions, savedTeamWhitelist, true, whitelistTeamsCallback)
    getgenv().uiLE.whitelistTeamsDropdown = whitelistTeamsDropdown
    whitelistTeamsCallback(savedTeamWhitelist)

    local blacklistTeamsCallback = function(selected)
        ctrl:Set("TEAM_BLACKLIST", type(selected) == "table" and selected or {selected})
    end
    local blacklistTeamsDropdown = createDropdown(Tabs.Targeting, "Blacklist Teams", "TEAM_BLACKLIST_DROPDOWN",
        teamOptions, savedTeamBlacklist, true, blacklistTeamsCallback)
    getgenv().uiLE.blacklistTeamsDropdown = blacklistTeamsDropdown
    blacklistTeamsCallback(savedTeamBlacklist)

    createSection(Tabs.Targeting, "Player Lists")
    local savedPlayerWhitelistUserIds = ctrl:Get("PLAYER_WHITELIST") or {}
    local savedPlayerBlacklistUserIds = ctrl:Get("PLAYER_BLACKLIST") or {}
    local savedPlayerWhitelistNames = userIdArrayToNames(savedPlayerWhitelistUserIds)
    local savedPlayerBlacklistNames = userIdArrayToNames(savedPlayerBlacklistUserIds)
    local playerOptions = #scannedPlayers > 0 and table.clone(scannedPlayers) or {"(no players online)"}

    local whitelistPlayersCallback = function(selectedNames)
        local userIds = {}
        if type(selectedNames) == "table" then
            for _, name in ipairs(selectedNames) do
                local uid = nameToUserId[name]
                if uid then table.insert(userIds, uid) end
            end
        end
        ctrl:Set("PLAYER_WHITELIST", userIds)
    end
    local whitelistPlayersDropdown = createDropdown(Tabs.Targeting, "Whitelist Players", "PLAYER_WHITELIST_DROPDOWN",
        playerOptions, savedPlayerWhitelistNames, true, whitelistPlayersCallback)
    getgenv().uiLE.whitelistPlayersDropdown = whitelistPlayersDropdown
    whitelistPlayersCallback(savedPlayerWhitelistNames)

    local blacklistPlayersCallback = function(selectedNames)
        local userIds = {}
        if type(selectedNames) == "table" then
            for _, name in ipairs(selectedNames) do
                local uid = nameToUserId[name]
                if uid then table.insert(userIds, uid) end
            end
        end
        ctrl:Set("PLAYER_BLACKLIST", userIds)
    end
    local blacklistPlayersDropdown = createDropdown(Tabs.Targeting, "Blacklist Players", "PLAYER_BLACKLIST_DROPDOWN",
        playerOptions, savedPlayerBlacklistNames, true, blacklistPlayersCallback)
    getgenv().uiLE.blacklistPlayersDropdown = blacklistPlayersDropdown
    blacklistPlayersCallback(savedPlayerBlacklistNames)

    createSection(Tabs.Appearance, "Limb Properties")
    createToggle(Tabs.Appearance, "Limb Collisions", "LIMB_CAN_COLLIDE", false)
    createSlider(Tabs.Appearance, "Limb Transparency", "LIMB_TRANSPARENCY", {0, 1}, 0.1, "", 0)
    createSlider(Tabs.Appearance, "Limb Size", "LIMB_SIZE", {5, 50}, 0.5, "", 5)

    createSection(Tabs.Appearance, "Chams")
    createToggle(Tabs.Appearance, "Chams Enabled", "CHAMS", false)
    createToggle(Tabs.Appearance, "Always On Top", "CHAMS_OCCLUSION", false)

    if version == 1 then
        createColorPicker(Tabs.Appearance, "Fill Color", "CHAMS_FILL_COLOR")
        createColorPicker(Tabs.Appearance, "Outline Color", "CHAMS_OUTLINE_COLOR")
        createSlider(Tabs.Appearance, "Fill Transparency", "CHAMS_FILL_TRANSPARENCY", {0, 1}, 0.05, "", 0.5)
        createSlider(Tabs.Appearance, "Outline Transparency", "CHAMS_OUTLINE_TRANSPARENCY", {0, 1}, 0.05, "", 0.5)
    else
        local savedFillTrans = ctrl:Get("CHAMS_FILL_TRANSPARENCY")
        local savedOutlineTrans = ctrl:Get("CHAMS_OUTLINE_TRANSPARENCY")
        local defaultFillAlpha = 1 - (savedFillTrans ~= nil and savedFillTrans or 0.5)
        local defaultOutlineAlpha = 1 - (savedOutlineTrans ~= nil and savedOutlineTrans or 0.5)

        Tabs.Appearance:CreateColorPicker({
            name = "Fill Color",
            flag = "CHAMS_FILL_COLOR",
            alpha = defaultFillAlpha,
            callback = function(color, alpha)
                ctrl:Set("CHAMS_FILL_COLOR", color)
                ctrl:Set("CHAMS_FILL_TRANSPARENCY", 1 - alpha)
            end,
        })

        Tabs.Appearance:CreateColorPicker({
            name = "Outline Color",
            flag = "CHAMS_OUTLINE_COLOR",
            alpha = defaultOutlineAlpha,
            callback = function(color, alpha)
                ctrl:Set("CHAMS_OUTLINE_COLOR", color)
                ctrl:Set("CHAMS_OUTLINE_TRANSPARENCY", 1 - alpha)
            end,
        })
    end

    createSection(Tabs.Appearance, "Proximity Shrink")
    createToggle(Tabs.Appearance, "Shrink Enabled", "DYNAMIC_SCALE_ENABLED", false)
    createSlider(Tabs.Appearance, "Shrink Range", "DYNAMIC_SCALE_RANGE_MULT", {0.2, 5}, 0.1, "x", 1)
    createSlider(Tabs.Appearance, "Update Rate", "DYNAMIC_SCALE_UPDATE_RATE", {5, 60}, 1, "Hz", 30)

    if isPC then
        createSection(Tabs.ESP, "General")
        createToggle(Tabs.ESP, "Enabled", "ESP", false)
        createToggle(Tabs.ESP, "Filter Local Player", "ESP_FILTER_LOCAL", false)

        createSection(Tabs.ESP, "Elements")
        createToggle(Tabs.ESP, "2D Box", "ESP_BOX", false)
        createToggle(Tabs.ESP, "3D Box", "ESP_BOX3D", false)
        createToggle(Tabs.ESP, "Tracer", "ESP_TRACER", false)
        createToggle(Tabs.ESP, "Skeleton", "ESP_SKELETON", false)
        createToggle(Tabs.ESP, "Health Bar", "ESP_HEALTH", false)
        createToggle(Tabs.ESP, "Label", "ESP_LABEL", false)
        createToggle(Tabs.ESP, "Off-Screen Arrow", "ESP_OFFSCREEN_POINT", false)

        createSection(Tabs.ESP, "Colors")
        createColorPicker(Tabs.ESP, "Box / Tracer", "ESP_COLOR")
        createColorPicker(Tabs.ESP, "3D Box", "ESP_BOX3D_COLOR")
        createColorPicker(Tabs.ESP, "Skeleton", "ESP_SKELETON_COLOR")
        createColorPicker(Tabs.ESP, "Health (Full)", "ESP_HEALTH_COLOR")
        createColorPicker(Tabs.ESP, "Health (Empty)", "ESP_EMPTY_COLOR")
        createColorPicker(Tabs.ESP, "Text", "ESP_TEXT_COLOR")

        createSection(Tabs.ESP, "Text")
        createSlider(Tabs.ESP, "Text Size", "ESP_TEXT_SIZE", {8, 32}, 1, "px", 13)

        createSection(Tabs.ESP, "Distance Thresholds")
        createParagraph(Tabs.ESP, "Level of Detail (LOD)",
            "Targets within Near Distance use the Near feature set. " ..
            "Between Near and Medium uses the Medium set. " ..
            "Beyond Medium up to Max Distance uses the Far set. " ..
            "Configure each set in the sections below.")
        createSlider(Tabs.ESP, "Near Distance", "ESP_NEAR_DISTANCE", {50, 500}, 10, "st", 100)
        createSlider(Tabs.ESP, "Medium Distance", "ESP_MEDIUM_DISTANCE", {100, 1000}, 10, "st", 250)
        createSlider(Tabs.ESP, "Max Distance", "ESP_MAX_DISTANCE", {100, 2000}, 50, "st", 1000)

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
            createSection(Tabs.ESP, tier.label)
            for _, feature in ipairs(LOD_FEATURES) do
                local key, field = tier.key, feature.field
                createToggle(
                    Tabs.ESP,
                    feature.name,
                    key .. "_" .. field,
                    getLodFlag(key, field) == true,
                    function(v)
                        setLodFlag(key, field, v)
                    end
                )
            end
        end

        createSection(Tabs.ESP, "Performance")
        createToggle(Tabs.ESP, "Occlusion Checking", "ESP_OCCLUSION", false)
        createSlider(Tabs.ESP, "Occlusion Frequency", "ESP_OCCLUSION_FREQUENCY", {1, 20}, 1, "frames", 5)
    end

    if version == 1 then
        Rayfield:LoadConfiguration()
    else
        Window:Load()
        getgenv().ChangelogHelper.reset()
        loadRemoteChangelogs()
        getgenv().ChangelogHelper.register(Window, { showPopupOnUpdate = true })
    end

    if not isPC then
        ctrl:Set("ESP", false)
        ctrl:Set("ESP_BOX", false)
        ctrl:Set("ESP_BOX3D", false)
        ctrl:Set("ESP_TRACER", false)
        ctrl:Set("ESP_SKELETON", false)
        ctrl:Set("ESP_HEALTH", false)
        ctrl:Set("ESP_LABEL", false)
        ctrl:Set("ESP_OFFSCREEN_POINT", false)
        ctrl:Set("ESP_OCCLUSION", false)
        for _, tier in ipairs({"ESP_NEAR_FLAGS", "ESP_MEDIUM_FLAGS", "ESP_FAR_FLAGS"}) do
            ctrl:Set(tier, {})
        end
    end
end

InitializeLimbScanning()
InitializeTeamScanning()
InitializePlayerScanning()

local initialVersion = loadUIVersion()
BuildUI(initialVersion)
getgenv().uiLE.loading = false
