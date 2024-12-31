--[[
Important Notice:
This script is not intended to be executed directly as raw source code.
To ensure proper functionality and avoid potential issues, please execute the script via a loadstring function.
Running the script in this manner helps maintain compatibility and ensures that dependencies and environmental setups are correctly handled.
]]

local LimbExtender = nil

local function main()
	if getgenv().IsProcessActive and type(getgenv().LimbExtenderGlobalData.LimbExtenderTerminateOldProcess) == "function" then
		getgenv().LimbExtenderGlobalData.LimbExtenderTerminateOldProcess("FullKill")
	end

	local rawSettings = {
		TOGGLE = "K",
		TARGET_LIMB = "Head",
		LIMB_SIZE = 10,
		LIMB_TRANSPARENCY = 0.9,
		LIMB_CAN_COLLIDE = false,
		TEAM_CHECK = false,
		FORCEFIELD_CHECK = true,
		RESTORE_ORIGINAL_LIMB_ON_DEATH = false,
		ESP = false,
		USE_HIGHLIGHT = true,
		DEPTH_MODE = 2,
		HIGHLIGHT_FILL_COLOR = Color3.fromRGB(0, 255, 0),
		HIGHLIGHT_FILL_TRANSPARENCY = 0.5,
		HIGHLIGHT_OUTLINE_COLOR = Color3.fromRGB(255, 255, 255),
		HIGHLIGHT_OUTLINE_TRANSPARENCY = 0,
	}

	getgenv().LimbExtenderGlobalData = getgenv().LimbExtenderGlobalData or {}
	getgenv().LimbExtenderGlobalData.Sense = getgenv().LimbExtenderGlobalData.Sense or loadstring(game:HttpGet('https://sirius.menu/sense'))()

	local PlayersService = game:GetService("Players")
	local UserInputService = game:GetService("UserInputService")
	local LocalPlayer = PlayersService.LocalPlayer
	local Sense = getgenv().LimbExtenderGlobalData.Sense

	Sense.teamSettings.enemy.enabled = true
	Sense.teamSettings.enemy.box = true
	Sense.teamSettings.enemy.healthText = true

	local function getPlayers(func)
		for _, player in pairs(PlayersService:GetPlayers()) do
			if player ~= LocalPlayer then
				func(player)
			end
		end
	end

	local function saveOriginalLimbProperties(limb)
		if not getgenv().LimbExtenderGlobalData[limb] then
			getgenv().LimbExtenderGlobalData[limb] = {Size = limb.Size, Transparency = limb.Transparency, CanCollide = limb.CanCollide, Massless = limb.Massless}
		end
	end

	local function restoreLimbProperties(character)
		local limb = character:FindFirstChild(rawSettings.TARGET_LIMB)
		local storedProperties = getgenv().LimbExtenderGlobalData[limb]

		if not limb then return end
		
		if storedProperties then
			limb.Size, limb.Transparency, limb.CanCollide, limb.Massless = storedProperties.Size, storedProperties.Transparency, storedProperties.CanCollide, storedProperties.Massless
			getgenv().LimbExtenderGlobalData[limb] = nil
		end

		local highlight = limb:FindFirstChildWhichIsA("Highlight")
		
		if highlight then
			highlight.Enabled = false
		end

		if getgenv().LimbExtenderGlobalData.LastLimbName and getgenv().LimbExtenderGlobalData.LastLimbName ~= rawSettings.TARGET_LIMB then
			local lastLimb = character:FindFirstChild(getgenv().LimbExtenderGlobalData.LastLimbName)
			if lastLimb then
				local lastStoredProperties = getgenv().LimbExtenderGlobalData[lastLimb]
				if lastStoredProperties then
					lastLimb.Size, lastLimb.Transparency, lastLimb.CanCollide, lastLimb.Massless = lastStoredProperties.Size, lastStoredProperties.Transparency, lastStoredProperties.CanCollide, lastStoredProperties.Massless
					getgenv().LimbExtenderGlobalData[lastLimb] = nil

					local highlight = lastLimb:FindFirstChildWhichIsA("Highlight")
		
					if highlight then
						highlight.Enabled = false
					end
				end
			end
		end
	end

	local function applyLimbHighlight(limb)
		local highlightInstance = limb:FindFirstChild("LimbHighlight") or Instance.new("Highlight", limb)
		highlightInstance.Name = "LimbHighlight"
		highlightInstance.DepthMode = rawSettings.DEPTH_MODE == 1 and Enum.HighlightDepthMode.AlwaysOnTop or Enum.HighlightDepthMode.Occluded
		highlightInstance.FillColor = rawSettings.HIGHLIGHT_FILL_COLOR
		highlightInstance.FillTransparency = rawSettings.HIGHLIGHT_FILL_TRANSPARENCY
		highlightInstance.OutlineColor = rawSettings.HIGHLIGHT_OUTLINE_COLOR
		highlightInstance.OutlineTransparency = rawSettings.HIGHLIGHT_OUTLINE_TRANSPARENCY
		highlightInstance.Enabled = true
	end

	local function modifyTargetLimb(character)
		local limb = character:WaitForChild(rawSettings.TARGET_LIMB, 1)
		local newSize = Vector3.new(rawSettings.LIMB_SIZE, rawSettings.LIMB_SIZE, rawSettings.LIMB_SIZE)
		if limb then
			saveOriginalLimbProperties(limb)
			limb.Transparency = rawSettings.LIMB_TRANSPARENCY
			limb.CanCollide = rawSettings.LIMB_CAN_COLLIDE
			limb.Size = newSize
			limb.Massless = true
			applyLimbHighlight(limb)
			getgenv().LimbExtenderGlobalData[character.Name]["SizeChanged"] = limb:GetPropertyChangedSignal("Size"):Once(function()
				if limb.Size ~= newSize then
					restoreLimbProperties(character)
                			modifyTargetLimb(character)
				end
            		end)
		end
	end

	local function processCharacterLimb(character)
		task.spawn(function()
			local waited = 0
			while not character:FindFirstChild("Humanoid") and character:FindFirstChild(rawSettings.TARGET_LIMB) and waited < 1 do 
				task.wait(0.1) 
				waited += 0.1 
			end
			if waited >= 1 then return end

			if (rawSettings.TEAM_CHECK and (LocalPlayer.Team == nil or PlayersService:GetPlayerFromCharacter(character).Team ~= LocalPlayer.Team)) or not rawSettings.TEAM_CHECK then
				modifyTargetLimb(character)
			end

			local humanoid = character:WaitForChild("Humanoid")
			local connection = rawSettings.RESTORE_ORIGINAL_LIMB_ON_DEATH and humanoid.HealthChanged or humanoid.Died
			getgenv().LimbExtenderGlobalData[character.Name]["OnDeath"] = connection:Connect(function(health)
				if health and health <= 0 then restoreLimbProperties(character) end
			end)
		end)
	end

	local function onPlayerRemoved(player)
		if getgenv().LimbExtenderGlobalData[player.Name] then
			for _, connection in pairs(getgenv().LimbExtenderGlobalData[player.Name]) do 
				connection:Disconnect()
			end
			getgenv().LimbExtenderGlobalData[player.Name] = nil
		end
		if player.Character then restoreLimbProperties(player.Character) end
	end

	local function playerHandler(player)
		onPlayerRemoved(player)
		getgenv().LimbExtenderGlobalData[player.Name] = {}
		getgenv().LimbExtenderGlobalData[player.Name]["CharacterAdded"] = player.CharacterAdded:Connect(function(character)
			getgenv().LimbExtenderGlobalData[player.Name]["TeamChanged"] = player:GetPropertyChangedSignal("Team"):Connect(function()
				playerHandler(player)
			end)

			if rawSettings.FORCEFIELD_CHECK then
				getgenv().LimbExtenderGlobalData[player.Name]["ForceFieldAdded"] = character.ChildAdded:Connect(function(child)
						if child:IsA("ForceField") then restoreLimbProperties(character) end
				end)
				getgenv().LimbExtenderGlobalData[player.Name]["ForceFieldRemoved"] = character.ChildRemoved:Connect(function(child)
					if child:IsA("ForceField") then processCharacterLimb(character) end
				end)
				restoreLimbProperties(character)
				processCharacterLimb(character)
			else
				restoreLimbProperties(character)
				processCharacterLimb(character)
			end
		end)

		getgenv().LimbExtenderGlobalData[player.Name]["CharacterRemoving"] = player.CharacterRemoving:Connect(function(character)
			restoreLimbProperties(character)
		end)

		if player.Character then
			processCharacterLimb(player.Character)
		end
	end

	local function handleKeyInput(input, isProcessed)
		if isProcessed or input.KeyCode ~= Enum.KeyCode[rawSettings.TOGGLE] then return end
		getgenv().LimbExtenderGlobalData.IsProcessActive = not getgenv().LimbExtenderGlobalData.IsProcessActive
		if getgenv().LimbExtenderGlobalData.IsProcessActive then
			rawSettings.startProcess()
		else
			rawSettings.endProcess("DetectInput")
		end
	end

	function rawSettings.endProcess(specialProcess)
		for name, connection in getgenv().LimbExtenderGlobalData do
			if typeof(connection) == "RBXScriptConnection" then
				connection:Disconnect()
				getgenv().LimbExtenderGlobalData[name] = nil
			end
		end

		getPlayers(onPlayerRemoved)

		if Sense._hasLoaded then
			Sense.Unload()
		end

		if specialProcess == "DetectInput" then 
			getgenv().LimbExtenderGlobalData.InputBeganConnection = UserInputService.InputBegan:Connect(handleKeyInput)
		elseif specialProcess == "FullKill" then
			getgenv().LimbExtenderGlobalData = {}
			script:Destroy()
		end
	end

	function rawSettings.startProcess()
		rawSettings.endProcess()
		getgenv().LimbExtenderGlobalData.LastLimbName = rawSettings.TARGET_LIMB
		getgenv().LimbExtenderGlobalData.InputBeganConnection = UserInputService.InputBegan:Connect(handleKeyInput)
		getgenv().LimbExtenderGlobalData.PlayerAddedConnection = PlayersService.PlayerAdded:Connect(playerHandler)
		getgenv().LimbExtenderGlobalData.PlayerRemovingConnection = PlayersService.PlayerRemoving:Connect(onPlayerRemoved)

		if rawSettings.ESP and not Sense._hasLoaded then
			Sense.Load()
		end
		
		getgenv().LimbExtenderGlobalData[LocalPlayer] = {}
		
		getgenv().LimbExtenderGlobalData[LocalPlayer]["TeamChanged"] = LocalPlayer:GetPropertyChangedSignal("Team"):Connect(function()
			task.spawn(function()
				getPlayers(playerHandler)
			end)
		end)

		getPlayers(playerHandler)
	end

	if getgenv().LimbExtenderGlobalData.IsProcessActive == nil then
		getgenv().LimbExtenderGlobalData.IsProcessActive = false
	end

	if getgenv().LimbExtenderGlobalData.IsProcessActive then
		rawSettings.startProcess()
	else
		rawSettings.endProcess("DetectInput")
	end

	getgenv().LimbExtenderGlobalData.LimbExtenderTerminateOldProcess =  rawSettings.endProcess
	
	LimbExtender = setmetatable({}, {
		__index = rawSettings,
		__newindex = function(_, key, value)
			if rawSettings[key] ~= value then
				rawSettings[key] = value
				if getgenv().LimbExtenderGlobalData.IsProcessActive then
					rawSettings.startProcess()
				end
			end
		end
	})
end

main()

return LimbExtender
