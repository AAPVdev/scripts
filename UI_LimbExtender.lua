local cloneref  = type(cloneref) == "function" and cloneref or function(obj) return obj end
local globalEnv = type(getgenv) == "function" and getgenv() or _G

globalEnv.uiLE = globalEnv.uiLE or {}
local uiLE = globalEnv.uiLE

if uiLE.loading then return end
uiLE.loading = true

local table_clear  = table.clear
local table_clone  = table.clone
local table_insert = table.insert
local table_remove = table.remove
local table_sort   = table.sort
local table_concat = table.concat
local table_find   = table.find
local task_spawn   = task.spawn
local task_defer   = task.defer
local task_wait    = task.wait
local math_clamp   = math.clamp
local math_random  = math.random
local math_huge    = math.huge

local function clearDropdownRefs()
	uiLE.targetLimbDropdown       = nil
	uiLE.whitelistTeamsDropdown   = nil
	uiLE.blacklistTeamsDropdown   = nil
	uiLE.whitelistPlayersDropdown = nil
	uiLE.blacklistPlayersDropdown = nil
end

local function destroyActiveUI()
	clearDropdownRefs()
	local oldActive = uiLE.ActiveUI
	local oldLib    = uiLE.uilibray
	uiLE.ActiveUI = nil
	uiLE.uilibray = nil
	if not oldActive then return end

	local w = oldActive.Window
	local v = oldActive.version
	if v == 1 and oldLib then
		pcall(function() oldLib:Destroy() end)
	elseif v == 2 and w then
		pcall(function() w:Unload() end)
	end
end

local okBoot, bootErr = pcall(function()
	local Players          = cloneref(game:GetService("Players"))
	local UserInputService = cloneref(game:GetService("UserInputService"))
	local HttpService      = cloneref(game:GetService("HttpService"))
	local TeamsService     = cloneref(game:GetService("Teams"))

	local cachedLocalPlayer = Players.LocalPlayer
	local function getLocalPlayer()
		if not cachedLocalPlayer then
			cachedLocalPlayer = Players.LocalPlayer
		end
		return cachedLocalPlayer
	end

	local CONFIG_FILE = "AXIOS_Config.json"

	local function normalizeVersion(s)
		if not s then return nil end
		return tostring(s):gsub("^%s+", ""):gsub("%s+$", ""):gsub("^v", "")
	end

	local function loadConfig()
		if type(uiLE._axiosConfig) == "table" then
			return uiLE._axiosConfig
		end
		local cfg = {}
		if isfile and readfile and isfile(CONFIG_FILE) then
			local ok, data = pcall(readfile, CONFIG_FILE)
			if ok and type(data) == "string" and data ~= "" then
				local ok2, tbl = pcall(HttpService.JSONDecode, HttpService, data)
				if ok2 and type(tbl) == "table" then
					cfg = tbl
				end
			end
		end
		uiLE._axiosConfig = cfg
		return cfg
	end

	local function saveConfig(tbl)
		if not (writefile and type(tbl) == "table") then return false end
		uiLE._axiosConfig = tbl
		local ok, json = pcall(HttpService.JSONEncode, HttpService, tbl)
		if not ok then return false end
		local ok2 = pcall(writefile, CONFIG_FILE, json)
		return ok2
	end

	local function persistSeenVersion(ver)
		if not ver then return end
		local norm = normalizeVersion(ver)
		local cfg  = loadConfig()
		if cfg.lastSeenVersion == norm then return end
		cfg.lastSeenVersion = norm
		saveConfig(cfg)
	end

	local function loadSeenVersion()
		local cfg = loadConfig()
		return normalizeVersion(cfg.lastSeenVersion)
	end

	local function saveUIVersion(version)
		local cfg = loadConfig()
		if cfg.uiVersion == version then return end
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

	local function fetchUrlList(urls)
		for i = 1, #urls do
			local ok, result = pcall(game.HttpGet, game, urls[i])
			if ok and type(result) == "string" and result ~= "" then
				return result
			end
		end
		return nil
	end

	local function compileLua(source)
		if type(source) ~= "string" or source == "" or type(loadstring) ~= "function" then
			return nil
		end
		local okCompile, fn = pcall(loadstring, source)
		return (okCompile and type(fn) == "function") and fn or nil
	end

	local function fetchLuaSource(urls)
		for i = 1, #urls do
			local ok, source = pcall(game.HttpGet, game, urls[i])
			if ok then
				local fn = compileLua(source)
				if fn then
					return source, fn
				end
			end
		end
		return nil, nil
	end

	local function compileAndRun(source)
		local fn = compileLua(source)
		if not fn then return nil end
		local okRun, result = pcall(fn)
		return okRun and result or nil
	end

	local function safeLoadString(urls)
		for i = 1, #urls do
			local okFetch, source = pcall(game.HttpGet, game, urls[i])
			if okFetch then
				local result = compileAndRun(source)
				if result then
					return result
				end
			end
		end
		return nil
	end

	local initialVersion       = loadUIVersion()
	local initialLibURL        = initialVersion == 1 and "https://sirius.menu/rayfield" or "https://sirius.menu/gen2"
	local prefetchedLibSources = {}

	local limbExtenderURLs = {
		"https://raw.githubusercontent.com/AAPVdev/scripts/refs/heads/main/LimbExtender.lua",
		"https://api.rubis.app/v2/scrap/DkwppyJ0KaQvou0r/raw",
	}
	local changelogURLs = {
		"https://raw.githubusercontent.com/AAPVdev/scripts/refs/heads/main/changelogs.json",
		"https://api.rubis.app/v2/scrap/5olUvAKK803Tl2js/raw",
	}

	do
		local caller  = coroutine.running()
		local pending = 0
		local yielded = false

		local function spawnFetch(fn)
			pending = pending + 1
			task_spawn(function()
				pcall(fn)
				pending = pending - 1
				if pending == 0 and yielded and caller then
					task_spawn(caller)
				end
			end)
		end

		if not uiLE.le then
			spawnFetch(function()
				uiLE.le = safeLoadString(limbExtenderURLs)
			end)
		end

		spawnFetch(function()
			local src = fetchLuaSource({ initialLibURL })
			if src then
				prefetchedLibSources[initialVersion] = src
			end
		end)

		if initialVersion == 2 and type(uiLE._cachedChangelogData) ~= "table" then
			spawnFetch(function()
				local content = fetchUrlList(changelogURLs)
				if content then
					local okDec, data = pcall(HttpService.JSONDecode, HttpService, content)
					if okDec and type(data) == "table" then
						uiLE._cachedChangelogData = data
					end
				end
			end)
		end

		if pending > 0 and caller then
			yielded = true
			coroutine.yield()
		end
	end

	if not uiLE.le then return end

	if type(uiLE._cleanupScanners) == "function" then
		pcall(uiLE._cleanupScanners)
		uiLE._cleanupScanners = nil
	end

	destroyActiveUI()

	if uiLE.gcontroller then
		pcall(function() uiLE.gcontroller:Destroy() end)
		uiLE.gcontroller = nil
	end

	local isPC = (function()
		local okPlat, platform = pcall(UserInputService.GetPlatform, UserInputService)
		if okPlat and platform then
			return platform == Enum.Platform.Windows
				or platform == Enum.Platform.OSX
				or platform == Enum.Platform.Linux
				or platform == Enum.Platform.UWP
		end
		return not UserInputService.TouchEnabled or UserInputService.KeyboardEnabled
	end)()

	local ctrl = uiLE.le.new(not isPC and { ESP = false } or nil)
	if not ctrl then return end
	uiLE.gcontroller = ctrl

	local function isControllerRunning()
		if type(ctrl.IsRunning) == "function" then
			return ctrl:IsRunning()
		end
		return ctrl._running == true
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

	local function safeRefreshDropdown(dropdown, list, fallbackItem)
		if not dropdown then return end
		local opts = (#list > 0) and list or { fallbackItem }
		pcall(function() dropdown:Refresh(opts) end)
	end

	local function mergeSavedStringsIntoOptions(baseList, listA, listB, placeholder)
		local out  = {}
		local seen = {}
		for i = 1, #baseList do
			local item = baseList[i]
			if type(item) == "string" and item ~= placeholder and not seen[item] then
				seen[item]    = true
				out[#out + 1] = item
			end
		end
		local function addExtras(list)
			if type(list) ~= "table" then return end
			for i = 1, #list do
				local item = list[i]
				if type(item) == "string" and item ~= "" and item ~= placeholder and not seen[item] then
					seen[item]    = true
					out[#out + 1] = item
				end
			end
		end
		addExtras(listA)
		addExtras(listB)
		if #out == 0 then
			out[1] = placeholder
		end
		return out
	end

	local function normalizeSingleSelection(sel)
		if type(sel) == "table" then
			local _, firstVal = next(sel)
			if type(sel[1]) == "string" then
				return sel[1]
			elseif type(firstVal) == "boolean" then
				for k, v in pairs(sel) do
					if v and type(k) == "string" then return k end
				end
				return nil
			end
			return sel[1]
		end
		return sel
	end

	local function normalizeMultiSelection(sel, placeholder)
		local out = {}
		if type(sel) == "table" then
			local isArray = (#sel > 0) or next(sel) == nil
			if isArray then
				for i = 1, #sel do
					local item = sel[i]
					if type(item) == "string" and item ~= placeholder then
						out[#out + 1] = item
					end
				end
			else
				for k, v in pairs(sel) do
					if v and type(k) == "string" and k ~= placeholder then
						out[#out + 1] = k
					end
				end
			end
		elseif type(sel) == "string" and sel ~= placeholder then
			out[1] = sel
		end
		return out
	end

	local NO_TEAMS_PLACEHOLDER   = "(no teams found)"
	local NO_PLAYERS_PLACEHOLDER = "(no players online)"

	local scannedLimbs      = {}
	local scannedLimbSet    = {}
	local limbPriorityCache = {}
	local limbLowerCache    = {}
	local limbRefreshQueued = false
	local lastScannedChar   = nil

	local limbPriority = {
		"Head", "HumanoidRootPart", "UpperTorso", "LowerTorso", "Torso",
		"LeftUpperArm", "LeftLowerArm", "LeftHand", "RightUpperArm", "RightLowerArm", "RightHand",
		"Left Arm", "Right Arm",
		"LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "RightUpperLeg", "RightLowerLeg", "RightFoot",
		"Left Leg", "Right Leg",
	}

	local limbPriorityLower = {}
	for i = 1, #limbPriority do
		limbPriorityLower[i] = limbPriority[i]:lower()
	end

	local function getLowerCached(str)
		local l = limbLowerCache[str]
		if not l then
			l = str:lower()
			limbLowerCache[str] = l
		end
		return l
	end

	local function getLimbPriority(name)
		local cached = limbPriorityCache[name]
		if cached then return cached end
		local lower = getLowerCached(name)
		for index = 1, #limbPriorityLower do
			if lower:find(limbPriorityLower[index], 1, true) then
				limbPriorityCache[name] = index
				return index
			end
		end
		limbPriorityCache[name] = math_huge
		return math_huge
	end

	local function limbComparator(a, b)
		local pa = getLimbPriority(a)
		local pb = getLimbPriority(b)
		if pa ~= pb then return pa < pb end
		return getLowerCached(a) < getLowerCached(b)
	end

	local function ciComparator(a, b)
		return getLowerCached(a) < getLowerCached(b)
	end

	local function isValidLimbPart(desc)
		return desc:IsA("BasePart")
			and not desc:FindFirstAncestorWhichIsA("Accoutrement")
			and not desc:FindFirstAncestorWhichIsA("Tool")
	end

	local function insertLimbName(name)
		if not name or scannedLimbSet[name] then return false end
		scannedLimbSet[name] = true
		scannedLimbs[#scannedLimbs + 1] = name
		return true
	end

	local function refreshLimbDropdownNow()
		limbRefreshQueued = false
		table_sort(scannedLimbs, limbComparator)
		local currentTarget = ctrl:Get("TARGET_LIMB")
		if type(currentTarget) == "string" and currentTarget ~= "" and not scannedLimbSet[currentTarget] then
			local withCurrent = table_clone(scannedLimbs)
			table_insert(withCurrent, 1, currentTarget)
			safeRefreshDropdown(uiLE.targetLimbDropdown, withCurrent, currentTarget)
			return
		end
		safeRefreshDropdown(uiLE.targetLimbDropdown, scannedLimbs, currentTarget or "Head")
	end

	local function scheduleLimbDropdownRefresh()
		if limbRefreshQueued then return end
		limbRefreshQueued = true
		task_defer(refreshLimbDropdownNow)
	end

	local function registerLimb(name)
		if insertLimbName(name) then
			scheduleLimbDropdownRefresh()
		end
	end

	local function getPartPath(part, character)
		local path   = part.Name
		local parent = part.Parent
		while parent and parent ~= character do
			path   = parent.Name .. "." .. path
			parent = parent.Parent
		end
		if parent ~= character then
			return nil
		end
		return path
	end

	local charAddedConn, charDescConn

	local function scanCharacter(character)
		if character and character == lastScannedChar and character.Parent ~= nil then
			return
		end
		if charDescConn then
			charDescConn:Disconnect()
			charDescConn = nil
		end
		lastScannedChar = character
		if not character then return end

		table_clear(scannedLimbs)
		table_clear(scannedLimbSet)
		local descs = character:GetDescendants()
		for i = 1, #descs do
			local desc = descs[i]
			if isValidLimbPart(desc) then
				insertLimbName(getPartPath(desc, character))
			end
		end
		refreshLimbDropdownNow()

		charDescConn = character.DescendantAdded:Connect(function(desc)
			if character.Parent and isValidLimbPart(desc) then
				registerLimb(getPartPath(desc, character))
			end
		end)
	end

	local function InitializeLimbScanning()
		if charAddedConn then
			charAddedConn:Disconnect()
			charAddedConn = nil
		end
		lastScannedChar = nil
		if type(ctrl.OnReferenceCharacterChanged) == "function" then
			charAddedConn = ctrl:OnReferenceCharacterChanged(scanCharacter)
			local current = ctrl:GetReferenceCharacter()
			if current then
				scanCharacter(current)
			end
		else
			local lp = getLocalPlayer()
			if lp then
				charAddedConn = lp.CharacterAdded:Connect(scanCharacter)
				if lp.Character then
					scanCharacter(lp.Character)
				end
			end
		end
	end

	local scannedTeams      = {}
	local scannedTeamSet    = {}
	local teamRefreshQueued = false

	local function refreshTeamDropdownsNow()
		teamRefreshQueued = false
		table_sort(scannedTeams, ciComparator)
		safeRefreshDropdown(uiLE.whitelistTeamsDropdown, scannedTeams, NO_TEAMS_PLACEHOLDER)
		safeRefreshDropdown(uiLE.blacklistTeamsDropdown, scannedTeams, NO_TEAMS_PLACEHOLDER)
	end

	local function scheduleTeamDropdownRefresh()
		if teamRefreshQueued then return end
		teamRefreshQueued = true
		task_defer(refreshTeamDropdownsNow)
	end

	local function registerTeam(name)
		if not name or scannedTeamSet[name] then return end
		scannedTeamSet[name] = true
		scannedTeams[#scannedTeams + 1] = name
		scheduleTeamDropdownRefresh()
	end

	local function unregisterTeam(name)
		if not name or not scannedTeamSet[name] then return end
		scannedTeamSet[name] = nil
		local idx = table_find(scannedTeams, name)
		if idx then
			table_remove(scannedTeams, idx)
			scheduleTeamDropdownRefresh()
		end
	end

	local function scanTeams()
		table_clear(scannedTeams)
		table_clear(scannedTeamSet)
		local children = TeamsService:GetChildren()
		for i = 1, #children do
			local team = children[i]
			if team:IsA("Team") and not scannedTeamSet[team.Name] then
				scannedTeamSet[team.Name] = true
				scannedTeams[#scannedTeams + 1] = team.Name
			end
		end
		refreshTeamDropdownsNow()
	end

	local teamsAddedConn, teamsRemovedConn
	local function InitializeTeamScanning()
		if teamsAddedConn then teamsAddedConn:Disconnect(); teamsAddedConn = nil end
		if teamsRemovedConn then teamsRemovedConn:Disconnect(); teamsRemovedConn = nil end
		scanTeams()
		teamsAddedConn = TeamsService.ChildAdded:Connect(function(child)
			if child:IsA("Team") then registerTeam(child.Name) end
		end)
		teamsRemovedConn = TeamsService.ChildRemoved:Connect(function(child)
			if child:IsA("Team") then unregisterTeam(child.Name) end
		end)
	end

	local scannedPlayers      = {}
	local nameToUserId        = {}
	local userIdToName        = {}
	local playerRefreshQueued = false

	local function refreshPlayerDropdownsNow()
		playerRefreshQueued = false
		table_sort(scannedPlayers, ciComparator)
		safeRefreshDropdown(uiLE.whitelistPlayersDropdown, scannedPlayers, NO_PLAYERS_PLACEHOLDER)
		safeRefreshDropdown(uiLE.blacklistPlayersDropdown, scannedPlayers, NO_PLAYERS_PLACEHOLDER)
	end

	local function schedulePlayerDropdownRefresh()
		if playerRefreshQueued then return end
		playerRefreshQueued = true
		task_defer(refreshPlayerDropdownsNow)
	end

	local function registerPlayer(player)
		if not player or not player:IsA("Player") then return end
		local name = player.Name
		if nameToUserId[name] then return end
		scannedPlayers[#scannedPlayers + 1] = name
		nameToUserId[name]          = player.UserId
		userIdToName[player.UserId] = name
		schedulePlayerDropdownRefresh()
	end

	local function unregisterPlayer(player)
		if not player or not player:IsA("Player") then return end
		local name = player.Name
		if not nameToUserId[name] then return end
		nameToUserId[name]          = nil
		userIdToName[player.UserId] = nil
		local idx = table_find(scannedPlayers, name)
		if idx then
			table_remove(scannedPlayers, idx)
			schedulePlayerDropdownRefresh()
		end
	end

	local function scanPlayers()
		table_clear(scannedPlayers)
		table_clear(nameToUserId)
		table_clear(userIdToName)
		local lp   = getLocalPlayer()
		local list = Players:GetPlayers()
		for i = 1, #list do
			local player = list[i]
			if player ~= lp and player:IsA("Player") then
				local name = player.Name
				if not nameToUserId[name] then
					scannedPlayers[#scannedPlayers + 1] = name
					nameToUserId[name]          = player.UserId
					userIdToName[player.UserId] = name
				end
			end
		end
		refreshPlayerDropdownsNow()
	end

	local playerAddedConn, playerRemovingConn
	local function InitializePlayerScanning()
		if playerAddedConn then playerAddedConn:Disconnect(); playerAddedConn = nil end
		if playerRemovingConn then playerRemovingConn:Disconnect(); playerRemovingConn = nil end
		scanPlayers()
		playerAddedConn = Players.PlayerAdded:Connect(function(player)
			if player ~= getLocalPlayer() then
				registerPlayer(player)
			end
		end)
		playerRemovingConn = Players.PlayerRemoving:Connect(function(player)
			unregisterPlayer(player)
		end)
	end

	uiLE._cleanupScanners = function()
		if charDescConn then charDescConn:Disconnect(); charDescConn = nil end
		if charAddedConn then charAddedConn:Disconnect(); charAddedConn = nil end
		if teamsAddedConn then teamsAddedConn:Disconnect(); teamsAddedConn = nil end
		if teamsRemovedConn then teamsRemovedConn:Disconnect(); teamsRemovedConn = nil end
		if playerAddedConn then playerAddedConn:Disconnect(); playerAddedConn = nil end
		if playerRemovingConn then playerRemovingConn:Disconnect(); playerRemovingConn = nil end
		lastScannedChar = nil
	end

	local function unloadAll()
		if type(uiLE._cleanupScanners) == "function" then
			pcall(uiLE._cleanupScanners)
			uiLE._cleanupScanners = nil
		end
		destroyActiveUI()
		if uiLE.gcontroller then
			pcall(function() uiLE.gcontroller:Destroy() end)
			uiLE.gcontroller = nil
		end
	end

	local function entriesToPlayerNames(entryList)
		if type(entryList) ~= "table" then return {} end
		local names = {}
		for i = 1, #entryList do
			local item = entryList[i]
			if type(item) == "number" then
				local name = userIdToName[item]
				if name then names[#names + 1] = name end
			elseif type(item) == "string" and item ~= NO_PLAYERS_PLACEHOLDER then
				names[#names + 1] = item
			end
		end
		return names
	end

	local BULLET = "\226\128\162 "

	globalEnv.ChangelogHelper = (function()
		local M          = {}
		local changelogs = {}
		local tabHandle  = nil

		local function buildBoxes(sections)
			local boxes = {}
			if not sections then return boxes end
			for sIdx = 1, #sections do
				local sec   = sections[sIdx]
				local items = sec.items
				local desc  = ""
				if items and #items > 0 then
					local parts = {}
					for i = 1, #items do
						parts[i] = BULLET .. items[i]
					end
					desc = table_concat(parts, "\n")
				end
				boxes[#boxes + 1] = { title = sec.title, description = desc }
			end
			return boxes
		end

		local function showPopup(window, entry)
			if not window or not entry then return end
			local content = nil
			if entry.highlights and #entry.highlights > 0 then
				content = "Highlights:\n" .. BULLET .. table_concat(entry.highlights, "\n" .. BULLET)
			end
			local popup = {
				title       = entry.version or "Changelog",
				subtitle    = entry.date,
				content     = content,
				boxes       = buildBoxes(entry.sections),
				dismissable = true,
				options     = {
					{ text = "Close", style = "primary" },
					{
						text     = "Copy notes",
						style    = "neutral",
						callback = function()
							if setclipboard then
								local lines = { "# " .. (entry.version or "Changelog") }
								if entry.date then
									lines[#lines + 1] = "_" .. entry.date .. "_"
									lines[#lines + 1] = ""
								end
								local highlights = entry.highlights
								if highlights then
									lines[#lines + 1] = "## Highlights"
									for i = 1, #highlights do
										lines[#lines + 1] = "- " .. highlights[i]
									end
									lines[#lines + 1] = ""
								end
								local sections = entry.sections
								if sections then
									for i = 1, #sections do
										local s = sections[i]
										lines[#lines + 1] = "## " .. s.title
										local items = s.items
										if items then
											for j = 1, #items do
												lines[#lines + 1] = "- " .. items[j]
											end
										end
										lines[#lines + 1] = ""
									end
								end
								setclipboard(table_concat(lines, "\n"))
							end
						end,
					},
				},
			}
			pcall(window.Popup, window, popup)
		end

		local function createChangelogTab(window)
			if tabHandle then return tabHandle end
			if not window then return nil end
			local t = window:CreateTab({ name = "Changelog" })
			t:CreateSection({ name = "Releases" })
			for i = 1, #changelogs do
				local entry = changelogs[i]
				local title = entry.version or ("Release " .. i)
				local descr = entry.date or ""
				t:CreateButton({
					name        = title,
					description = descr,
					callback    = function()
						showPopup(window, entry)
						persistSeenVersion(entry.version)
					end,
				})
			end
			tabHandle = t
			return t
		end

		M.add = function(entry)
			table_insert(changelogs, 1, entry or {})
			tabHandle = nil
		end

		M.reset = function()
			table_clear(changelogs)
			tabHandle = nil
		end

		M.register = function(window, opts)
			createChangelogTab(window)
			opts = opts or {}
			local latestRaw = changelogs[1] and changelogs[1].version
			if not latestRaw then return end
			local latest = normalizeVersion(latestRaw)
			local seen   = loadSeenVersion()

			local wantPopups = true
			if type(window.Get) == "function" then
				local okGet, gotVal = pcall(window.Get, window, "Changelog.ShowPopups")
				if okGet and gotVal ~= nil then
					wantPopups = gotVal
				end
			end

			local function parseFullSemver(v)
				if not v then return nil end
				local major, minor, patch = normalizeVersion(v):match("^(%d+)%.(%d+)%.?(%d*)$")
				return tonumber(major), tonumber(minor), tonumber(patch) or 0
			end

			local function significant(oldV, newV)
				if not newV then return false end
				if not oldV then return true end
				local o1, o2 = parseFullSemver(oldV)
				local n1, n2 = parseFullSemver(newV)
				if not (o1 and n1) then return true end
				if n1 > o1 then return true end
				if (n2 and o2) and n2 > o2 then return true end
				return false
			end

			if seen == latest then return end

			local entryToShow
			if seen == nil then
				local latestMajor, latestMinor = parseFullSemver(latest)
				for i = 1, #changelogs do
					local entry = changelogs[i]
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
						pcall(window.Toast, window, { title = "New update: " .. (entryToShow.version or latest), subtitle = (entryToShow.date or "") })
						task_spawn(function()
							task_wait(0.18)
							showPopup(window, entryToShow)
						end)
					else
						pcall(window.Toast, window, { title = "Updated to " .. (entryToShow.version or latest) })
					end
					persistSeenVersion(entryToShow.version)
				else
					pcall(window.Toast, window, { title = "Updated: " .. (entryToShow.version or latest) })
					persistSeenVersion(entryToShow.version)
				end
			end
		end

		M.list = function() return changelogs end
		return M
	end)()

	local function loadRemoteChangelogs()
		local cached = uiLE._cachedChangelogData
		if type(cached) == "table" then
			for i = #cached, 1, -1 do
				globalEnv.ChangelogHelper.add(cached[i])
			end
			return true
		end

		local content = fetchUrlList(changelogURLs)
		if content then
			local success, data = pcall(HttpService.JSONDecode, HttpService, content)
			if success and type(data) == "table" then
				uiLE._cachedChangelogData = data
				for i = #data, 1, -1 do
					globalEnv.ChangelogHelper.add(data[i])
				end
				return true
			end
		end
		return false
	end

	local uiBuilding = false

	local function BuildUI(version)
		if uiBuilding then return end
		uiBuilding = true

		local okBuild, buildErr = pcall(function()
			destroyActiveUI()

			saveUIVersion(version)
			uiLE.uiVersion = version

			globalEnv.RAYFIELD_SECURE   = true
			globalEnv.RAYFIELD_ASSET_ID = 84895246331982

			local libURL    = version == 1 and "https://sirius.menu/rayfield" or "https://sirius.menu/gen2"
			local cachedSrc = prefetchedLibSources[version]
			if cachedSrc then
				prefetchedLibSources[version] = nil
				uiLE.uilibray = compileAndRun(cachedSrc)
			else
				uiLE.uilibray = nil
			end
			if not uiLE.uilibray then
				uiLE.uilibray = safeLoadString({ libURL })
			end
			if not uiLE.uilibray then return end

			local Rayfield = uiLE.uilibray

			local LOADING_SUBTITLES = {
				"multiply by delta",
				"working for the cia",
				"shoutout serene fr",
				"avis was here",
				"seizure causing soap?",
				"skids skid from skids",
			}

			local Window
			if version == 1 then
				Window = Rayfield:CreateWindow({
					Name                   = "AXIOS",
					ScriptID               = "sid_k2rgzy25rkgy",
					LoadingTitle           = "AXIOS",
					LoadingSubtitle        = LOADING_SUBTITLES[math_random(#LOADING_SUBTITLES)],
					Theme                  = "Default",
					DisableRayfieldPrompts = true,
					ConfigurationSaving    = {
						Enabled    = true,
						FolderName = "LimbExtenderConfigs",
						FileName   = "Configuration",
					},
				})
			else
				Window = Rayfield:CreateWindow({
					name          = "AXIOS",
					subtitle      = LOADING_SUBTITLES[math_random(#LOADING_SUBTITLES)],
					theme         = "default",
					configuration = {
						autoSave     = true,
						autoLoad     = true,
						fileName     = "Configuration",
						customFolder = "LimbExtenderConfigs",
					},
				})
				uiLE.uilibray.Window = Window
			end

			uiLE.ActiveUI = { Window = Window, version = version }

			local function createTab(name)
				if version == 1 then
					return Window:CreateTab(name)
				end
				return Window:CreateTab({ name = name })
			end

			local function createSection(tab, title)
				if version == 1 then
					tab:CreateSection(title)
				else
					tab:CreateSection({ name = title })
				end
			end

			local function createToggle(tab, name, flag, default, customCallback)
				local saved = ctrl:Get(flag)
				local value = default == true
				if saved ~= nil then
					value = saved == true
				end
				local callbackFn = customCallback or function(v) ctrl:Set(flag, v) end
				if version == 1 then
					return tab:CreateToggle({
						Name         = name,
						Flag         = flag,
						CurrentValue = value,
						Callback     = callbackFn,
					})
				else
					return tab:CreateToggle({
						name     = name,
						flag     = flag,
						value    = value,
						callback = callbackFn,
					})
				end
			end

			local function createSlider(tab, name, flag, range, increment, suffix, default)
				local saved = ctrl:Get(flag)
				local value = saved
				if value == nil then
					value = default ~= nil and default or range[1]
				end
				if version == 1 then
					return tab:CreateSlider({
						Name         = name,
						Flag         = flag,
						CurrentValue = value,
						Range        = range,
						Increment    = increment,
						Suffix       = suffix or "",
						Callback     = function(v) ctrl:Set(flag, v) end,
					})
				else
					return tab:CreateSlider({
						name      = name,
						flag      = flag,
						value     = value,
						range     = range,
						increment = increment,
						suffix    = suffix or "",
						callback  = function(v) ctrl:Set(flag, v) end,
					})
				end
			end

			local function createColorPicker(tab, name, flag)
				local color = ctrl:Get(flag) or Color3.new(1, 1, 1)
				if version == 1 then
					return tab:CreateColorPicker({
						Name     = name,
						Flag     = flag,
						Color    = color,
						Callback = function(v) ctrl:Set(flag, v) end,
					})
				else
					return tab:CreateColorPicker({
						name     = name,
						flag     = flag,
						value    = color,
						callback = function(v) ctrl:Set(flag, v) end,
					})
				end
			end

			local function createKeybind(tab, name, flag, defaultKey, callback)
				if version == 1 then
					return tab:CreateKeybind({
						Name           = name,
						Flag           = flag,
						CurrentKeybind = defaultKey,
						HoldToInteract = false,
						Callback       = callback,
					})
				else
					return tab:CreateKeybind({
						name           = name,
						flag           = flag,
						value          = Enum.KeyCode[defaultKey] or Enum.KeyCode.L,
						holdToInteract = false,
						callback       = callback,
					})
				end
			end

			local function createDropdown(tab, name, flag, options, defaultOption, multi, callback, placeholder)
				if version == 1 then
					local currentOption = defaultOption and (multi and defaultOption or { defaultOption }) or {}
					return tab:CreateDropdown({
						Name            = name,
						Flag            = flag,
						Options         = options,
						CurrentOption   = currentOption,
						MultipleOptions = multi or false,
						Callback        = function(opts)
							if multi then
								callback(normalizeMultiSelection(opts, placeholder))
							else
								callback(normalizeSingleSelection(opts))
							end
						end,
					})
				else
					return tab:CreateDropdown({
						name        = name,
						flag        = flag,
						options     = options,
						value       = defaultOption,
						multiSelect = multi or false,
						callback    = function(selection)
							if multi then
								callback(normalizeMultiSelection(selection, placeholder))
							else
								callback(normalizeSingleSelection(selection))
							end
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
				elseif type(tab.CreateParagraph) == "function" then
					pcall(tab.CreateParagraph, tab, { name = title, content = content })
				end
			end

			local Tabs = {
				General    = createTab("General"),
				Targeting  = createTab("Targeting"),
				Appearance = createTab("Appearance"),
			}
			if isPC then
				Tabs.ESP = createTab("ESP")
			end

			createSection(Tabs.General, "Master Control")

			local modifyLimbsToggle = createToggle(
				Tabs.General,
				"Modify Limbs",
				"ModifyLimbs",
				isControllerRunning(),
				function(v)
					ctrl:Toggle(v == true)
				end
			)

			local function toggleLimbs()
				if uiBuilding then return end
				local nextState = not isControllerRunning()
				if modifyLimbsToggle then
					if type(modifyLimbsToggle.Set) == "function" then
						modifyLimbsToggle:Set(nextState)
					elseif type(modifyLimbsToggle.SetValue) == "function" then
						modifyLimbsToggle:SetValue(nextState)
					end
				end
				if isControllerRunning() ~= nextState then
					ctrl:Toggle(nextState)
				end
			end
			createKeybind(Tabs.General, "Toggle Keybind", "ToggleKeybind", "L", toggleLimbs)

			createSection(Tabs.General, "Interface")

			local themes, defaultTheme
			if version == 1 then
				themes       = { "Default", "AmberGlow", "Amethyst", "Bloom", "DarkBlue", "Green", "Light", "Ocean", "Serenity" }
				defaultTheme = "Default"
			else
				themes       = { "default", "cobalt", "ember", "amethyst", "frost", "rose" }
				defaultTheme = "default"
			end

			createDropdown(Tabs.General, "Current Theme", "CurrentTheme", themes, defaultTheme, false, function(selected)
				if type(selected) == "string" and selected ~= "" then
					if version == 1 then
						if type(Window.ModifyTheme) == "function" then
							pcall(Window.ModifyTheme, selected)
						end
					elseif type(Window.ChangeTheme) == "function" then
						pcall(Window.ChangeTheme, Window, selected)
					end
				end
			end)

			local switchLabel = version == 1 and "Switch to Gen2 UI" or "Switch to Gen1 UI"
			createButton(Tabs.General, switchLabel, function()
				BuildUI(version == 1 and 2 or 1)
			end)

			createButton(Tabs.General, "Unload AXIOS", unloadAll)

			createSection(Tabs.Targeting, "Target Selection")
			createToggle(Tabs.Targeting, "Players", "PLAYER_ENABLED", true)
			createToggle(Tabs.Targeting, "NPCs", "NPC_ENABLED", false)
			createToggle(Tabs.Targeting, "ForceField Check", "FORCEFIELD_CHECK", false)
			createToggle(Tabs.Targeting, "Ignore Dead Targets", "ALT_RESET_LIMB_ON_DEATH", true)

			local TEAM_MODES = {
				{ label = "None",           value = "none"      },
				{ label = "Different Team", value = "different" },
				{ label = "Same Team",      value = "same"      },
				{ label = "Whitelist",      value = "whitelist" },
				{ label = "Blacklist",      value = "blacklist" },
			}
			local teamModeOptions  = {}
			local teamOptionToMode = {}
			local savedTeamMode    = ctrl:Get("TEAM_MODE") or "none"
			local defaultTeamLabel = "None"
			for i = 1, #TEAM_MODES do
				local pair = TEAM_MODES[i]
				teamModeOptions[i]           = pair.label
				teamOptionToMode[pair.label] = pair.value
				if pair.value == savedTeamMode then
					defaultTeamLabel = pair.label
				end
			end

			createDropdown(Tabs.Targeting, "Team Filter", "TEAM_MODE", teamModeOptions, defaultTeamLabel, false, function(selected)
				ctrl:Set("TEAM_MODE", teamOptionToMode[selected] or "none")
			end)

			createSection(Tabs.Targeting, "Limb Focus")
			local currentTargetLimb = ctrl:Get("TARGET_LIMB") or "Head"
			local existingLimbs     = #scannedLimbs > 0 and table_clone(scannedLimbs) or { currentTargetLimb }
			if not scannedLimbSet[currentTargetLimb] and existingLimbs[1] ~= currentTargetLimb then
				table_insert(existingLimbs, 1, currentTargetLimb)
			end
			local targetLimbDropdown = createDropdown(Tabs.Targeting, "Target Limb", "TARGET_LIMB",
				existingLimbs, currentTargetLimb, false, function(selected)
					if type(selected) == "string" and selected ~= "" then
						ctrl:Set("TARGET_LIMB", selected)
					end
				end)
			uiLE.targetLimbDropdown = targetLimbDropdown

			createSection(Tabs.Targeting, "Team Lists")
			local savedTeamWhitelist = ctrl:Get("TEAM_WHITELIST") or {}
			local savedTeamBlacklist = ctrl:Get("TEAM_BLACKLIST") or {}
			local teamOptions        = mergeSavedStringsIntoOptions(
				scannedTeams, savedTeamWhitelist, savedTeamBlacklist, NO_TEAMS_PLACEHOLDER
			)

			uiLE.whitelistTeamsDropdown = createDropdown(Tabs.Targeting, "Whitelist Teams", "TEAM_WHITELIST_DROPDOWN",
				teamOptions, savedTeamWhitelist, true, function(selected)
					ctrl:Set("TEAM_WHITELIST", selected)
				end, NO_TEAMS_PLACEHOLDER)

			uiLE.blacklistTeamsDropdown = createDropdown(Tabs.Targeting, "Blacklist Teams", "TEAM_BLACKLIST_DROPDOWN",
				teamOptions, savedTeamBlacklist, true, function(selected)
					ctrl:Set("TEAM_BLACKLIST", selected)
				end, NO_TEAMS_PLACEHOLDER)

			createSection(Tabs.Targeting, "Player Lists")
			local savedPlayerWhitelistNames = entriesToPlayerNames(ctrl:Get("PLAYER_WHITELIST") or {})
			local savedPlayerBlacklistNames = entriesToPlayerNames(ctrl:Get("PLAYER_BLACKLIST") or {})
			local playerOptions             = mergeSavedStringsIntoOptions(
				scannedPlayers, savedPlayerWhitelistNames, savedPlayerBlacklistNames, NO_PLAYERS_PLACEHOLDER
			)

			local function buildUpdatedPlayerEntries(selectedNames, priorKey)
				local entries = {}
				local seenIds = {}
				for i = 1, #selectedNames do
					local name = selectedNames[i]
					local uid  = nameToUserId[name]
					if uid then
						if not seenIds[uid] then
							seenIds[uid] = true
							entries[#entries + 1] = uid
						end
					else
						entries[#entries + 1] = name
					end
				end
				local prior = ctrl:Get(priorKey)
				if type(prior) == "table" then
					for i = 1, #prior do
						local item = prior[i]
						if type(item) == "number" and not userIdToName[item] and not seenIds[item] then
							seenIds[item] = true
							entries[#entries + 1] = item
						end
					end
				end
				return entries
			end

			uiLE.whitelistPlayersDropdown = createDropdown(Tabs.Targeting, "Whitelist Players", "PLAYER_WHITELIST_DROPDOWN",
				playerOptions, savedPlayerWhitelistNames, true, function(selectedNames)
					ctrl:Set("PLAYER_WHITELIST", buildUpdatedPlayerEntries(selectedNames, "PLAYER_WHITELIST"))
				end, NO_PLAYERS_PLACEHOLDER)

			uiLE.blacklistPlayersDropdown = createDropdown(Tabs.Targeting, "Blacklist Players", "PLAYER_BLACKLIST_DROPDOWN",
				playerOptions, savedPlayerBlacklistNames, true, function(selectedNames)
					ctrl:Set("PLAYER_BLACKLIST", buildUpdatedPlayerEntries(selectedNames, "PLAYER_BLACKLIST"))
				end, NO_PLAYERS_PLACEHOLDER)

			createSection(Tabs.Appearance, "Limb Properties")
			createToggle(Tabs.Appearance, "Limb Collisions", "LIMB_CAN_COLLIDE", false)
			createSlider(Tabs.Appearance, "Limb Transparency", "LIMB_TRANSPARENCY", { 0, 1 }, 0.05, "", 0.7)
			createSlider(Tabs.Appearance, "Limb Size", "LIMB_SIZE", { 1, 30 }, 0.5, "", 15)

			createSection(Tabs.Appearance, "Chams")
			createToggle(Tabs.Appearance, "Chams Enabled", "CHAMS", false)
			createToggle(Tabs.Appearance, "Always On Top", "CHAMS_OCCLUSION", false)

			if version == 1 then
				createColorPicker(Tabs.Appearance, "Fill Color", "CHAMS_FILL_COLOR")
				createColorPicker(Tabs.Appearance, "Outline Color", "CHAMS_OUTLINE_COLOR")
				createSlider(Tabs.Appearance, "Fill Transparency", "CHAMS_FILL_TRANSPARENCY", { 0, 1 }, 0.05, "", 0.5)
				createSlider(Tabs.Appearance, "Outline Transparency", "CHAMS_OUTLINE_TRANSPARENCY", { 0, 1 }, 0.05, "", 0.5)
			else
				local savedFillColor      = ctrl:Get("CHAMS_FILL_COLOR") or Color3.fromRGB(255, 255, 0)
				local savedOutlineColor   = ctrl:Get("CHAMS_OUTLINE_COLOR") or Color3.fromRGB(255, 255, 255)
				local savedFillTrans      = ctrl:Get("CHAMS_FILL_TRANSPARENCY")
				local savedOutlineTrans   = ctrl:Get("CHAMS_OUTLINE_TRANSPARENCY")
				local defaultFillAlpha    = 1 - (savedFillTrans ~= nil and savedFillTrans or 0.5)
				local defaultOutlineAlpha = 1 - (savedOutlineTrans ~= nil and savedOutlineTrans or 0.5)

				Tabs.Appearance:CreateColorPicker({
					name     = "Fill Color",
					flag     = "CHAMS_FILL_COLOR",
					value    = savedFillColor,
					alpha    = defaultFillAlpha,
					callback = function(color, alpha)
						if typeof(color) == "Color3" then
							ctrl:Set("CHAMS_FILL_COLOR", color)
						end
						if type(alpha) == "number" then
							ctrl:Set("CHAMS_FILL_TRANSPARENCY", math_clamp(1 - alpha, 0, 1))
						end
					end,
				})

				Tabs.Appearance:CreateColorPicker({
					name     = "Outline Color",
					flag     = "CHAMS_OUTLINE_COLOR",
					value    = savedOutlineColor,
					alpha    = defaultOutlineAlpha,
					callback = function(color, alpha)
						if typeof(color) == "Color3" then
							ctrl:Set("CHAMS_OUTLINE_COLOR", color)
						end
						if type(alpha) == "number" then
							ctrl:Set("CHAMS_OUTLINE_TRANSPARENCY", math_clamp(1 - alpha, 0, 1))
						end
					end,
				})
			end

			createSection(Tabs.Appearance, "Proximity Shrink")
			createToggle(Tabs.Appearance, "Shrink Enabled", "DYNAMIC_SCALE_ENABLED", true)
			createSlider(Tabs.Appearance, "Shrink Range", "DYNAMIC_SCALE_RANGE_MULT", { 0.2, 5 }, 0.1, "x", 1.5)
			createSlider(Tabs.Appearance, "Update Rate", "DYNAMIC_SCALE_UPDATE_RATE", { 5, 60 }, 1, "Hz", 8)

			if isPC then
				createSection(Tabs.ESP, "General")
				createToggle(Tabs.ESP, "Enabled", "ESP", true)
				createToggle(Tabs.ESP, "Filter Local Player", "ESP_FILTER_LOCAL", true)

				createSection(Tabs.ESP, "Elements")
				createToggle(Tabs.ESP, "2D Box", "ESP_BOX", true)
				createToggle(Tabs.ESP, "3D Box", "ESP_BOX3D", false)
				createToggle(Tabs.ESP, "Tracer", "ESP_TRACER", true)
				createToggle(Tabs.ESP, "Skeleton", "ESP_SKELETON", true)
				createToggle(Tabs.ESP, "Health Bar", "ESP_HEALTH", true)
				createToggle(Tabs.ESP, "Label", "ESP_LABEL", true)
				createToggle(Tabs.ESP, "Distance Tag", "ESP_DISTANCE", false)
				createToggle(Tabs.ESP, "Off-Screen Arrow", "ESP_OFFSCREEN_POINT", true)

				local tracerOrigins = { "Bottom", "Center", "Mouse", "Top" }
				local savedOrigin   = ctrl:Get("ESP_TRACER_ORIGIN")
				local defaultOrigin = (type(savedOrigin) == "string" and table_find(tracerOrigins, savedOrigin)) and savedOrigin or "Bottom"
				createDropdown(Tabs.ESP, "Tracer Origin", "ESP_TRACER_ORIGIN", tracerOrigins, defaultOrigin, false, function(selected)
					if type(selected) == "string" and selected ~= "" then
						ctrl:Set("ESP_TRACER_ORIGIN", selected)
					end
				end)

				createSection(Tabs.ESP, "Colors")
				createColorPicker(Tabs.ESP, "Box / Tracer", "ESP_COLOR")
				createColorPicker(Tabs.ESP, "3D Box", "ESP_BOX3D_COLOR")
				createColorPicker(Tabs.ESP, "Skeleton", "ESP_SKELETON_COLOR")
				createColorPicker(Tabs.ESP, "Health (Full)", "ESP_HEALTH_COLOR")
				createColorPicker(Tabs.ESP, "Health (Empty)", "ESP_EMPTY_COLOR")
				createColorPicker(Tabs.ESP, "Text", "ESP_TEXT_COLOR")

				createSection(Tabs.ESP, "Text")
				createSlider(Tabs.ESP, "Text Size", "ESP_TEXT_SIZE", { 8, 32 }, 1, "px", 16)

				createSection(Tabs.ESP, "Distance Thresholds")
				createParagraph(Tabs.ESP, "Level of Detail (LOD)",
					"Targets within Near Distance use the Near feature set. " ..
					"Between Near and Medium uses the Medium set. " ..
					"Beyond Medium up to Max Distance uses the Far set. " ..
					"Configure each set in the sections below.")
				createSlider(Tabs.ESP, "Near Distance", "ESP_NEAR_DISTANCE", { 50, 500 }, 10, "st", 100)
				createSlider(Tabs.ESP, "Medium Distance", "ESP_MEDIUM_DISTANCE", { 100, 1000 }, 10, "st", 250)
				createSlider(Tabs.ESP, "Max Distance", "ESP_MAX_DISTANCE", { 100, 2000 }, 50, "st", 500)

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

				for i = 1, #LOD_TIERS do
					local tier = LOD_TIERS[i]
					createSection(Tabs.ESP, tier.label)
					for j = 1, #LOD_FEATURES do
						local feature    = LOD_FEATURES[j]
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
				createSlider(Tabs.ESP, "Occlusion Frequency", "ESP_OCCLUSION_FREQUENCY", { 1, 20 }, 1, "frames", 4)
			end

			if version == 1 then
				Rayfield:LoadConfiguration()
			else
				Window:Load()
				globalEnv.ChangelogHelper.reset()
				loadRemoteChangelogs()
				globalEnv.ChangelogHelper.register(Window, { showPopupOnUpdate = true })
			end
		end)

		uiBuilding = false
		if not okBuild then
			warn("[AXIOS UI] BuildUI failed: " .. tostring(buildErr))
		end
	end

	InitializeLimbScanning()
	InitializeTeamScanning()
	InitializePlayerScanning()

	BuildUI(initialVersion)
end)

uiLE.loading = false
if not okBoot then
	warn("[AXIOS UI] Initialization failed: " .. tostring(bootErr))
end
