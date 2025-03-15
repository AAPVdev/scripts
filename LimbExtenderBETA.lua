local limbExtender = nil
getgenv().limbExtenderData = getgenv().limbExtenderData or {}

local players = game:GetService("Players")
local tweenService = game:GetService("TweenService")
local contentProvider = game:GetService("ContentProvider")

local localPlayer = players.LocalPlayer

local function run()
	local limbExtenderData = getgenv().limbExtenderData
	if limbExtenderData.running ~= nil then
		limbExtenderData.terminateOldProcess("FullKill")
	end

	local rawSettings = {
		TOGGLE = "K",
		TARGET_LIMB = "Head",
		LIMB_SIZE = 5,
		MOBILE_BUTTON = true,
		LIMB_TRANSPARENCY = 0.9,
		LIMB_CAN_COLLIDE = false,
		TEAM_CHECK = false,
		FORCEFIELD_CHECK = false,
		RESET_LIMB_ON_DEATH2 = false,
		USE_HIGHLIGHT = true,
		DEPTH_MODE = 2,
		HIGHLIGHT_FILL_COLOR = Color3.fromRGB(0, 255, 0),
		HIGHLIGHT_FILL_TRANSPARENCY = 0.5,
		HIGHLIGHT_OUTLINE_COLOR = Color3.fromRGB(255, 255, 255),
		HIGHLIGHT_OUTLINE_TRANSPARENCY = 0,
	}

	limbExtenderData.running = limbExtenderData.running or false
	limbExtenderData.CAU = limbExtenderData.CAU or loadstring(game:HttpGet('https://raw.githubusercontent.com/AAPVdev/scripts/refs/heads/main/ContextActionUtility.lua'))()
	limbExtenderData.playerTable = limbExtenderData.playerTable or {}
	limbExtenderData.limbs = limbExtenderData.limbs or {}

	local playerTable = limbExtenderData.playerTable
	local limbs = limbExtenderData.limbs
	local contextActionUtility = limbExtenderData.CAU

	local function getPlayers(func, includeLocalPlayer)
		for _, player in ipairs(players:GetPlayers()) do
			if includeLocalPlayer or player ~= localPlayer then
				func(player)
			end
		end
	end

	local function restoreLimbProperties(limb)
		local limbProperties = limbs[limb]
		local highlightInstance = limb:FindFirstChild("LimbHighlight")

		if not limbProperties then
			return
		end

		if highlightInstance then
			highlightInstance:Destroy()
		end

		limbs[limb] = nil

		limb.Size = limbProperties.Size
		limb.CanCollide = limbProperties.CanCollide
		limb.Transparency = limbProperties.Transparency
		limb.Massless = limbProperties.Massless
	end

	local function saveLimbProperties(limb)
		if limbs[limb] then
			restoreLimbProperties(limb)
		end

		limbs[limb] = {
			Size = limb.Size,
			Transparency = limb.Transparency,
			CanCollide = limb.CanCollide,
			Massless = limb.Massless
		}
	end

	local function modifyLimbProperties(limb)
		task.spawn(function()
			saveLimbProperties(limb)
			limb.Size = Vector3.new(rawSettings.LIMB_SIZE, rawSettings.LIMB_SIZE, rawSettings.LIMB_SIZE)
			limb.Transparency = rawSettings.LIMB_TRANSPARENCY
			limb.CanCollide = rawSettings.LIMB_CAN_COLLIDE
			limb.Massless = true

			local highlightInstance = limb:FindFirstChildWhichIsA("Highlight") or Instance.new("Highlight", limb)
			highlightInstance.Name = "LimbHighlight"
			highlightInstance.DepthMode = rawSettings.DEPTH_MODE == 1 and Enum.HighlightDepthMode.AlwaysOnTop or Enum.HighlightDepthMode.Occluded
			highlightInstance.FillColor = rawSettings.HIGHLIGHT_FILL_COLOR
			highlightInstance.FillTransparency = rawSettings.HIGHLIGHT_FILL_TRANSPARENCY
			highlightInstance.OutlineColor = rawSettings.HIGHLIGHT_OUTLINE_COLOR
			highlightInstance.OutlineTransparency = rawSettings.HIGHLIGHT_OUTLINE_TRANSPARENCY
			highlightInstance.Enabled = rawSettings.USE_HIGHLIGHT
		end)
	end

	local function removePlayerData(player)
		local playerData = playerTable[player.Name]
		if playerData then
			for _, connection in pairs(playerData) do
				if typeof(connection) == "RBXScriptConnection" then
					connection:Disconnect()
				end
			end

			playerTable[player.Name] = nil
		end
	end

	local function terminate(specialProcess)
		for key, connection in pairs(getgenv().limbExtenderData) do
			if typeof(connection) == "RBXScriptConnection" then
				connection:Disconnect()
				limbExtenderData[key] = nil
			end
		end

		getPlayers(removePlayerData, false)

		for limb, _ in pairs(limbExtenderData.limbs) do
			restoreLimbProperties(limb)
		end

		if specialProcess == "FullKill" then
			contextActionUtility:UnbindAction("LimbExtenderToggle")
		end
		if rawSettings.MOBILE_BUTTON then
			contextActionUtility:SetTitle("LimbExtenderToggle", "On")
		end
	end

	local function toggleState()
		limbExtenderData.running = not limbExtenderData.running

		if limbExtenderData.running then
			rawSettings.initiate()
		else
			terminate()
		end
	end

	function rawSettings.initiate()
		if not limbExtenderData.running then return end
		terminate()
		local function setupPlayer(player)
			local function characterAdded(character)
				if character then
					local targetLimb = character:WaitForChild(rawSettings.TARGET_LIMB, 0.5)
					local humanoid = character:WaitForChild("Humanoid", 0.5)
					local playerData = playerTable[player.Name]
					if playerData and targetLimb and humanoid and humanoid.Health > 0 then

						restoreLimbProperties(targetLimb)

						if (rawSettings.TEAM_CHECK and (localPlayer.Team == nil or player.Team ~= localPlayer.Team)) or not rawSettings.TEAM_CHECK then
							modifyLimbProperties(targetLimb)
						end

						playerData["characterRemoving"] = player.CharacterRemoving:Once(function()
							restoreLimbProperties(targetLimb)
						end)

						local connection = rawSettings.RESET_LIMB_ON_DEATH2 and humanoid.HealthChanged or humanoid.Died
						playerData["OnDeath"] = connection:Connect(function(health)
							if health and health <= 0 then
								restoreLimbProperties(targetLimb)
							end
						end)

						playerData["teamChanged"] = player:GetPropertyChangedSignal("Team"):Once(function()
							removePlayerData(player)
							setupPlayer(player)
						end)
					end
				end
			end

			playerTable[player.Name] = {}
			playerTable[player.Name]["characterAdded"] = player.CharacterAdded:Connect(characterAdded)

			characterAdded(player.Character)
		end

		getPlayers(setupPlayer, false)

		limbExtenderData.teamChanged = localPlayer:GetPropertyChangedSignal("Team"):Once(rawSettings.initiate)
		limbExtenderData.playerAdded = players.PlayerAdded:Connect(setupPlayer)
		limbExtenderData.playerRemoving = players.PlayerRemoving:Connect(removePlayerData)

		if rawSettings.MOBILE_BUTTON then
			contextActionUtility:SetTitle("LimbExtenderToggle", "Off")
		end
	end

	loadingScreen(2)
	loadingScreen = nil

	limbExtender = setmetatable({}, {
		__index = rawSettings,
		__newindex = function(_, key, value)
			if rawSettings[key] ~= value then
				rawSettings[key] = value
				if limbExtenderData.running then
					rawSettings.initiate()
				end
			end
		end
	})
	
	contextActionUtility:BindAction(
		"LimbExtenderToggle",
		function(_, inputState)
			if inputState == Enum.UserInputState.Begin then
				toggleState()
			end
		end,
		rawSettings.MOBILE_BUTTON,
		Enum.KeyCode[rawSettings.TOGGLE]
	)
	limbExtenderData.terminateOldProcess = terminate

	if limbExtenderData.running then
		rawSettings.initiate()
	elseif rawSettings.MOBILE_BUTTON then
		contextActionUtility:SetTitle("LimbExtenderToggle", "On")
	end
end

function loadingScreen(state)
	local limbExtenderData = getgenv().limbExtenderData

	if limbExtenderData.finishedLoading == false and state == 1 then return end
	limbExtenderData.finishedLoading = false

	local function animate(target, tweenInfo, properties)
		tweenService:Create(target, tweenInfo, properties):Play()
	end

	if not limbExtenderData.loadingScreen then
		local AAPVdev = Instance.new("ScreenGui")
		local Background = Instance.new("Frame")
		local RoundedCorners = Instance.new("UICorner")
		local Developer = Instance.new("TextLabel")
		local Gradient = Instance.new("UIGradient")
		local Logo = Instance.new("ImageLabel")
		local UIAspectRatioConstraint = Instance.new("UIAspectRatioConstraint")

		AAPVdev.Name = "AAPVdev"
		AAPVdev.Parent = localPlayer:WaitForChild("PlayerGui")
		AAPVdev.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

		Background.Name = "Background"
		Background.Parent = AAPVdev
		Background.AnchorPoint = Vector2.new(0.5, 0.5)
		Background.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		Background.BorderColor3 = Color3.fromRGB(0, 0, 0)
		Background.BorderSizePixel = 0
		Background.ClipsDescendants = true
		Background.Position = UDim2.new(0.499282628, 0, 0.498812348, 0)

		RoundedCorners.CornerRadius = UDim.new(0, 20)
		RoundedCorners.Name = "RoundedCorners"
		RoundedCorners.Parent = Background

		Developer.Name = "Developer"
		Developer.Parent = Background
		Developer.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		Developer.BackgroundTransparency = 1.000
		Developer.BorderColor3 = Color3.fromRGB(0, 0, 0)
		Developer.BorderSizePixel = 0
		Developer.Position = UDim2.new(0.25, 0, 0.665000021, 0)
		Developer.Size = UDim2.new(0.5, 0, 0.25, 0)
		Developer.Font = Enum.Font.Code
		Developer.Text = "AAPVdev"
		Developer.TextColor3 = Color3.fromRGB(255, 255, 255)
		Developer.TextScaled = true
		Developer.TextSize = 14.000
		Developer.TextWrapped = true

		Gradient.Color = ColorSequence.new{ColorSequenceKeypoint.new(0.00, Color3.fromRGB(255, 255, 255)), ColorSequenceKeypoint.new(1.00, Color3.fromRGB(0, 179, 255))}
		Gradient.Offset = Vector2.new(0, 1)
		Gradient.Rotation = 90
		Gradient.Name = "Gradient"
		Gradient.Parent = Background

		Logo.Name = "Logo"
		Logo.Parent = Background
		Logo.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		Logo.BackgroundTransparency = 1.000
		Logo.BorderColor3 = Color3.fromRGB(255, 255, 255)
		Logo.BorderSizePixel = 0
		Logo.Position = UDim2.new(0.333333343, 0, 0.165000007, 0)
		Logo.Size = UDim2.new(0.333333343, 0, 0.5, 0)
		Logo.Image = "http://www.roblox.com/asset/?id=107904589783906"
		Logo.ScaleType = Enum.ScaleType.Fit

		UIAspectRatioConstraint.Parent = Background
		UIAspectRatioConstraint.AspectRatio = 1.850

		local loadingScreenAssets = {
			AAPVdev = AAPVdev,
			Background = Background,
			RoundedCorners = RoundedCorners,
			Developer = Developer,
			Gradient = Gradient,
			Logo = Logo,
			UIAspectRatioConstraint = UIAspectRatioConstraint,
		}

		local assetsArray = {}
		for _, asset in pairs(loadingScreenAssets) do
			table.insert(assetsArray, asset)
		end
		contentProvider:PreloadAsync(assetsArray)
		assetsArray = nil

		limbExtenderData.loadingScreen = loadingScreenAssets
	end
	local loadingScreenAssets = limbExtenderData.loadingScreen
	loadingScreenAssets.Developer.Position = UDim2.new(0.25, 0, 0.665000021, 0)
	loadingScreenAssets.Logo.Position = UDim2.new(0.333333343, 0, 0.165000007, 0)
	if state == 1 then
		animate(loadingScreenAssets.Background, TweenInfo.new(1, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Size = UDim2.new(0.499, 0, 0.499, 0)})
		animate(loadingScreenAssets.Gradient, TweenInfo.new(1.5), {Offset = Vector2.new(0, -1)})
		task.wait(2)
		run()
	elseif state == 2 then
		animate(loadingScreenAssets.Developer, TweenInfo.new(0.5), {Position = UDim2.new(0.25, 0,1, 0)})
		animate(loadingScreenAssets.Logo, TweenInfo.new(0.5), {Position = UDim2.new(0.333, 0,-0.660, 0)})
		animate(loadingScreenAssets.Background, TweenInfo.new(1, Enum.EasingStyle.Back, Enum.EasingDirection.In), {Size = UDim2.new(0, 0, 0, 0)})
	end
	loadingScreenAssets = nil
	animate = nil
	limbExtenderData.finishedLoading = true
end

loadingScreen(1)
return limbExtender
