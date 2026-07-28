getgenv().uiLE = getgenv().uiLE or {}
if getgenv().uiLE.loading then return end
getgenv().uiLE.loading = true

local function fetchUrlList(urls)
    for _, url in ipairs(urls) do
        local ok, result = pcall(function() return game:HttpGet(url) end)
        if ok and result and result ~= "" then
            return result
        end
    end
    return nil, "All URLs failed"
end

local function tryLoadFromURL(url)
    local content, _ = fetchUrlList({url})
    if not content then
        return nil, "fetch failed"
    end
    local func, loadErr = loadstring(content)
    if not func then
        return nil, "compile failed: " .. tostring(loadErr)
    end
    local ok, result = pcall(func)
    if not ok then
        return nil, "execution failed: " .. tostring(result)
    end
    return result
end

local function safeLoadString(urls)
    for _, url in ipairs(urls) do
        local result, err = tryLoadFromURL(url)
        if result then
            return result
        end
    end
    return nil
end

local function normalizeVersion(s)
    if not s then return nil end
    return tostring(s):gsub("^%s+", ""):gsub("%s+$", ""):gsub("^v", "")
end

local SEEN_FILENAME = "AXIOS_LastSeenVersion.txt"
local function file_write_safe(name, contents)
    if writefile then
        pcall(function() writefile(name, contents) end)
        return true
    end
    return false
end
local function file_read_safe(name)
    if isfile and isfile(name) and readfile then
        local ok, data = pcall(function() return readfile(name) end)
        if ok and data then return data end
    end
    return nil
end

local function persist_seen_version(ver)
    if not ver then return end
    local norm = normalizeVersion(ver)
    pcall(function() file_write_safe(SEEN_FILENAME, norm) end)
end

local function load_seen_from_file()
    local raw = file_read_safe(SEEN_FILENAME)
    if raw and raw ~= "" then
        return normalizeVersion(raw)
    end
    return nil
end

local limbExtenderURLs = {
    "https://raw.githubusercontent.com/AAPVdev/scripts/main/LimbExtender.lua",
    "https://api.rubis.app/v2/scrap/BASPm347G6urjvnO/raw"
}
getgenv().uiLE.le = getgenv().uiLE.le or nil
if not getgenv().uiLE.le then
    local le, leErr = safeLoadString(limbExtenderURLs)
    if not le then
        getgenv().uiLE.loading = false
        return
    end
    getgenv().uiLE.le = le
end

if getgenv().uiLE.gcontroller then
    pcall(function()
        if getgenv().uiLE.gcontroller.Destroy then
            getgenv().uiLE.gcontroller:Destroy()
        end
    end)
    getgenv().uiLE.gcontroller = nil
end

local ok, newCtrl = pcall(function() return getgenv().uiLE.le.new() end)
if not ok or not newCtrl then
    getgenv().uiLE.loading = false
    return
end
getgenv().uiLE.gcontroller = newCtrl
local ctrl = getgenv().uiLE.gcontroller

if getgenv().uiLE.uilibray then
    pcall(function()
        if getgenv().uiLE.uilibray.Window then
            getgenv().uiLE.uilibray.Window:Unload()
        end
    end)
    getgenv().uiLE.uilibray = nil
end

local rayfieldURLs = {
    "https://sirius.menu/gen2",
}
getgenv().RAYFIELD_SECURE = true
local rayfieldLib = safeLoadString(rayfieldURLs)
if not rayfieldLib then
    getgenv().uiLE.loading = false
    return
end
getgenv().uiLE.uilibray = rayfieldLib
local Rayfield = getgenv().uiLE.uilibray

local Players = cloneref(game:GetService("Players"))
local LocalPlayer = Players.LocalPlayer
local UserInputService = cloneref(game:GetService("UserInputService"))
local isPC = (UserInputService:GetPlatform() == Enum.Platform.Windows) or (UserInputService:GetPlatform() == Enum.Platform.OSX)

local scannedLimbs = {}
local limbPriority = {
    "Head","HumanoidRootPart","UpperTorso","LowerTorso","Torso",
    "LeftUpperArm","LeftLowerArm","LeftHand","RightUpperArm","RightLowerArm","RightHand",
    "Left Arm","Right Arm",
    "LeftUpperLeg","LeftLowerLeg","LeftFoot","RightUpperLeg","RightLowerLeg","RightFoot",
    "Left Leg","Right Leg",
}
local function getLimbPriority(name)
    if not name or type(name) ~= "string" then return math.huge end
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
        local pa = getLimbPriority(a)
        local pb = getLimbPriority(b)
        if pa ~= pb then return pa < pb end
        return a:lower() < b:lower()
    end)
end

local refreshTimer
local function debounceRefreshDropdown(dropdown)
    if refreshTimer then return end
    refreshTimer = task.delay(0.06, function()
        refreshTimer = nil
        if dropdown and dropdown.Refresh then
            local copy = {}
            for i, v in ipairs(scannedLimbs) do copy[i] = v end
            pcall(function() dropdown:Refresh(copy) end)
        end
    end)
end

local function registerLimb(name, dropdown)
    if not name or table.find(scannedLimbs, name) then return end
    table.insert(scannedLimbs, name)
    sortLimbs()
    debounceRefreshDropdown(dropdown)
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

local charDescConn, charRemovingConn
local function disconnectCharConns()
    if charDescConn then
        pcall(function() charDescConn:Disconnect() end)
        charDescConn = nil
    end
    if charRemovingConn then
        pcall(function() charRemovingConn:Disconnect() end)
        charRemovingConn = nil
    end
end

local function scanCharacter(character, dropdown)
    if not character then return end
    disconnectCharConns()
    table.clear(scannedLimbs)
    for _, desc in ipairs(character:GetDescendants()) do
        if desc:IsA("BasePart") then
            registerLimb(getPartPath(desc, character), dropdown)
        end
    end
    charDescConn = character.DescendantAdded:Connect(function(desc)
        if desc:IsA("BasePart") then
            registerLimb(getPartPath(desc, character), dropdown)
        end
    end)
    charRemovingConn = character.AncestryChanged:Connect(function(_, parent)
        if not parent then
            disconnectCharConns()
        end
    end)
end

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

local function buildTab(tab, layout)
    for _, item in ipairs(layout) do
        local t = item.type
        if t == "section" then
            if tab.CreateSection then tab:CreateSection({ name = item.title }) end
        elseif t == "paragraph" then
            if tab.CreateParagraph then
                tab:CreateParagraph({ title = item.title, content = item.content })
            elseif tab.CreateLabel then
                tab:CreateLabel(item.title .. "\n" .. item.content)
            elseif tab.CreateSection then
                tab:CreateSection({ name = item.title })
            end
        elseif t == "toggle" then
            local saved = ctrl:Get(item.flag)
            if tab.CreateToggle then
                tab:CreateToggle({
                    name = item.name,
                    flag = item.flag,
                    value = (saved ~= nil) and saved or false,
                    callback = function(v) pcall(function() ctrl:Set(item.flag, v) end) end,
                })
            end
        elseif t == "slider" then
            local minV = (item.range and item.range[1]) or 0
            local cur = ctrl:Get(item.flag)
            if type(cur) ~= "number" then cur = minV end
            if tab.CreateSlider then
                tab:CreateSlider({
                    name = item.name,
                    flag = item.flag,
                    value = cur,
                    range = item.range,
                    increment = item.increment,
                    suffix = item.suffix or "",
                    callback = function(v) pcall(function() ctrl:Set(item.flag, v) end) end,
                })
            end
        elseif t == "color" then
            local cur = ctrl:Get(item.flag)
            if typeof(cur) == "Color3" then
                cur = { color = cur, alpha = 1 }
            elseif type(cur) ~= "table" then
                cur = { color = Color3.fromRGB(255,255,255), alpha = 1 }
            end
            if tab.CreateColorPicker then
                tab:CreateColorPicker({
                    name = item.name,
                    flag = item.flag,
                    value = cur,
                    callback = function(v) pcall(function() ctrl:Set(item.flag, v) end) end,
                })
            end
        end
    end
end

local function cleanup()
    disconnectCharConns()
    if ctrl then
        pcall(function()
            if ctrl.Stop then pcall(function() ctrl:Stop() end) end
            if ctrl.Destroy then pcall(function() ctrl:Destroy() end) end
        end)
    end
    if getgenv().uiLE and getgenv().uiLE.uilibray then
        pcall(function() if getgenv().uiLE.uilibray.Window then getgenv().uiLE.Window:Unload() end end)
        getgenv().uiLE.uilibray = nil
    end
    if getgenv().uiLE then getgenv().uiLE.gcontroller = nil end
    if getgenv().uiLE then getgenv().uiLE.loading = false end
end
getgenv().uiLE.cleanup = cleanup

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

getgenv().uiLE.uilibray.Window = Window

print(Window.Unload)

local Tabs = {
    General    = Window:CreateTab({ name = "General" }),
    Targeting  = Window:CreateTab({ name = "Targeting" }),
    Appearance = Window:CreateTab({ name = "Appearance" }),
}
if isPC then Tabs.ESP = Window:CreateTab({ name = "ESP" }) end

if Tabs.General and Tabs.General.CreateSection then Tabs.General:CreateSection({ name = "Master Control" }) end
local modifyLimbsToggle
if Tabs.General and Tabs.General.CreateToggle then
    modifyLimbsToggle = Tabs.General:CreateToggle({
        name = "Modify Limbs",
        flag = "ModifyLimbs",
        value = false,
        callback = function(v) pcall(function() ctrl:Toggle(v) end) end,
    })
end
if Tabs.General and Tabs.General.CreateKeybind then
    Tabs.General:CreateKeybind({
        name = "Toggle Keybind",
        flag = "ToggleKeybind",
        value = Enum.KeyCode.L,
        holdToInteract = false,
        callback = function()
            if modifyLimbsToggle and modifyLimbsToggle.Set then
                local ok, running = pcall(function() return ctrl._running end)
                local newState = not (running == true)
                pcall(function() modifyLimbsToggle:Set(newState) end)
                pcall(function() if ctrl.Toggle then ctrl:Toggle(newState) end end)
            end
        end,
        onChanged = function(newKey) pcall(function() ctrl:Set("ToggleKeybind", newKey) end) end,
    })
end
if Tabs.General and Tabs.General.CreateSection then Tabs.General:CreateSection({ name = "Theme" }) end
if Tabs.General and Tabs.General.CreateDropdown then
    Tabs.General:CreateDropdown({
        name = "Current Theme",
        flag = "CurrentTheme",
        multiSelect = false,
        options = { "default", "cobalt", "ember", "amethyst", "frost", "rose" },
        value = "default",
        callback = function(theme) pcall(function() Window:ChangeTheme(theme) end) end,
    })
end

buildTab(Tabs.Targeting, {
    { type = "section", title = "Target Selection" },
    { type = "toggle", name = "Players", flag = "PLAYER_ENABLED" },
    { type = "toggle", name = "NPCs", flag = "NPC_ENABLED" },
    { type = "toggle", name = "Team Check", flag = "TEAM_CHECK" },
    { type = "toggle", name = "ForceField Check", flag = "FORCEFIELD_CHECK" },
})
if Tabs.Targeting and Tabs.Targeting.CreateSection then Tabs.Targeting:CreateSection({ name = "Limb Focus" }) end
local targetLimbDropdown
if Tabs.Targeting and Tabs.Targeting.CreateDropdown then
    targetLimbDropdown = Tabs.Targeting:CreateDropdown({
        name = "Target Limb",
        flag = "TARGET_LIMB",
        options = {},
        value = ctrl:Get("TARGET_LIMB") or "Head",
        multiSelect = false,
        callback = function(selection)
            local chosen = selection
            if type(selection) == "table" then chosen = selection[1] end
            pcall(function() ctrl:Set("TARGET_LIMB", chosen) end)
        end,
    })
end

buildTab(Tabs.Appearance, {
    { type = "section", title = "Limb Properties" },
    { type = "toggle", name = "Limb Collisions", flag = "LIMB_CAN_COLLIDE" },
    { type = "slider", name = "Limb Transparency", flag = "LIMB_TRANSPARENCY", range = {0,1}, increment = 0.1 },
    { type = "slider", name = "Limb Size", flag = "LIMB_SIZE", range = {5,50}, increment = 0.5 },
    { type = "section", title = "Proximity Shrink" },
    { type = "toggle", name = "Shrink Enabled", flag = "DYNAMIC_SCALE_ENABLED" },
    { type = "slider", name = "Shrink Range", flag = "DYNAMIC_SCALE_RANGE_MULT", range = {0.2,5}, increment = 0.1, suffix = "x" },
    { type = "slider", name = "Update Rate", flag = "DYNAMIC_SCALE_UPDATE_RATE", range = {5,60}, increment = 1, suffix = "Hz" },
})

if isPC and Tabs.ESP then
    buildTab(Tabs.ESP, {
        { type = "section", title = "General" },
        { type = "toggle", name = "Enabled", flag = "ESP" },
        { type = "toggle", name = "Filter Local Player", flag = "ESP_FILTER_LOCAL" },
        { type = "section", title = "Elements" },
        { type = "toggle", name = "2D Box", flag = "ESP_BOX" },
        { type = "toggle", name = "3D Box", flag = "ESP_BOX3D" },
        { type = "toggle", name = "Tracer", flag = "ESP_TRACER" },
        { type = "toggle", name = "Skeleton", flag = "ESP_SKELETON" },
        { type = "toggle", name = "Health Bar", flag = "ESP_HEALTH" },
        { type = "toggle", name = "Label", flag = "ESP_LABEL" },
        { type = "toggle", name = "Off-Screen Arrow", flag = "ESP_OFFSCREEN_POINT" },
        { type = "section", title = "Colors" },
        { type = "color", name = "Box / Tracer", flag = "ESP_COLOR" },
        { type = "color", name = "3D Box", flag = "ESP_BOX3D_COLOR" },
        { type = "color", name = "Skeleton", flag = "ESP_SKELETON_COLOR" },
        { type = "color", name = "Health (Full)", flag = "ESP_HEALTH_COLOR" },
        { type = "color", name = "Health (Empty)", flag = "ESP_EMPTY_COLOR" },
        { type = "color", name = "Text", flag = "ESP_TEXT_COLOR" },
        { type = "section", title = "Text" },
        { type = "slider", name = "Text Size", flag = "ESP_TEXT_SIZE", range = {8,32}, increment = 1, suffix = "px" },
        { type = "section", title = "Distance Thresholds" },
        { type = "paragraph", title = "Level of Detail (LOD)", content = "Targets within Near Distance use the Near set; between Near and Medium uses Medium; beyond uses Far." },
        { type = "slider", name = "Near Distance", flag = "ESP_NEAR_DISTANCE", range = {50,500}, increment = 10, suffix = "st" },
        { type = "slider", name = "Medium Distance", flag = "ESP_MEDIUM_DISTANCE", range = {100,1000}, increment = 10, suffix = "st" },
        { type = "slider", name = "Max Distance", flag = "ESP_MAX_DISTANCE", range = {100,2000}, increment = 50, suffix = "st" },
    })
    local LOD_TIERS = {
        { label = "Near Range Features", key = "ESP_NEAR_FLAGS" },
        { label = "Medium Range Features", key = "ESP_MEDIUM_FLAGS" },
        { label = "Far Range Features", key = "ESP_FAR_FLAGS" },
    }
    local LOD_FEATURES = {
        { name = "2D Box", field = "Box" },
        { name = "3D Box", field = "Box3D" },
        { name = "Tracer", field = "Tracer" },
        { name = "Skeleton", field = "Skeleton" },
        { name = "Health Bar", field = "Health" },
        { name = "Label", field = "Label" },
    }
    for _, tier in ipairs(LOD_TIERS) do
        Tabs.ESP:CreateSection({ name = tier.label })
        for _, feature in ipairs(LOD_FEATURES) do
            local key, field = tier.key, feature.field
            Tabs.ESP:CreateToggle({
                name = feature.name,
                flag = key .. "_" .. field,
                value = getLodFlag(key, field) == true,
                callback = function(v) setLodFlag(key, field, v) end,
            })
        end
    end
    buildTab(Tabs.ESP, {
        { type = "section", title = "Performance" },
        { type = "toggle", name = "Occlusion Checking", flag = "ESP_OCCLUSION" },
        { type = "slider", name = "Occlusion Frequency", flag = "ESP_OCCLUSION_FREQUENCY", range = {1,20}, increment = 1, suffix = "frames" },
    })
end

LocalPlayer.CharacterAdded:Connect(function(ch) scanCharacter(ch, targetLimbDropdown) end)
if LocalPlayer.Character then scanCharacter(LocalPlayer.Character, targetLimbDropdown) end
pcall(function() Window:Load() end)

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
                    pcall(function()
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
                    end)
                end },
            },
            dismissable = true,
        }
        pcall(function() window:Popup(popup) end)
    end

    local function createTab(window)
        if tabHandle then return tabHandle end
        if not window then return nil end
        local t = window:CreateTab({ name = "Changelog"})
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
    end

    M.add = function(entry)
        table.insert(changelogs, 1, entry or {})
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

        local function parseSemver(v)
            if not v then return nil, nil end
            local a,b = v:match("^(%d+)%.(%d+)")
            return tonumber(a), tonumber(b)
        end
        local function significant(oldV, newV)
            if not newV then return false end
            if not oldV then return true end
            local o1,o2 = parseSemver(oldV)
            local n1,n2 = parseSemver(newV)
            if not (o1 and n1) then return true end
            if n1 > o1 then return true end
            if (n2 and o2) and n2 > o2 then return true end
            return false
        end

        if seen == latest then
            return
        end

        if significant(seen, latest) and wantPopups and opts.showPopupOnUpdate ~= false then
            local latestEntry = changelogs[1]
            local shouldNotify = true
            if latestEntry.notify ~= nil then
                shouldNotify = latestEntry.notify
            end

            if shouldNotify then
                pcall(function() window:Toast({ title = "New update: " .. (latestEntry.version or latest), subtitle = (latestEntry.date or "") }) end)
                task.spawn(function()
                    task.wait(0.18)
                    showPopup(window, latestEntry)
                end)
            else
                pcall(function() window:Toast({ title = "Updated to " .. (latestEntry.version or latest) }) end)
            end
            persist_seen_version(latestEntry.version)
        else
            pcall(function() window:Toast({ title = "Updated: " .. (changelogs[1].version or latest) }) end)
            persist_seen_version(changelogs[1].version)
        end
    end

    M.list = function() return changelogs end
    return M
end)()

local changelogURLs = {
    "https://raw.githubusercontent.com/AAPVdev/scripts/refs/heads/main/changelogs.json",
    "https://api.rubis.app/v2/scrap/btATRjMxQttd1sy8/raw"
}
local function loadRemoteChangelogs()
    for _, url in ipairs(changelogURLs) do
        local content, _ = fetchUrlList({url})
        if content then
            local success, data = pcall(function()
                return game:GetService("HttpService"):JSONDecode(content)
            end)
            if success and type(data) == "table" then
                for _, entry in ipairs(data) do
                    getgenv().ChangelogHelper.add(entry)
                end
                return true
            end
        end
    end
    return false
end

loadRemoteChangelogs()
getgenv().ChangelogHelper.register(Window, { showPopupOnUpdate = true })

getgenv().uiLE.loading = false
