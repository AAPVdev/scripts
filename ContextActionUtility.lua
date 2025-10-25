--https://devforum.roblox.com/t/easy-mobile-buttons-contextactionutility/
local ContextActionUtility = {}

local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local Players = game:GetService("Players")

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")
local TouchGui
local TouchControlFrame
local JumpButton

local isMobile = UserInputService.TouchEnabled
if isMobile then
	TouchGui = PlayerGui:WaitForChild("TouchGui", 0.2)
	TouchControlFrame = TouchGui:WaitForChild("TouchControlFrame", 0.2)
	JumpButton = TouchControlFrame:WaitForChild("JumpButton", 0.2)
end

local Buttons = {}

local ButtonPositions = {
	[1] = UDim2.new(-0.4169, 0, 0.715, 0);
	[2] = UDim2.new(-0.165, 0, -0.165, 0);
	[3] = UDim2.new(0.715, 0, -0.4169, 0);
	[4] = UDim2.new(-1.1077, 0, -0.0396, 0);
	[5] = UDim2.new(-0.858, 0, -0.858, 0);
	[6] = UDim2.new(-0.0396, 0, -1.1077, 0);
}

local function GetNextSlot()
	local takenSlots = {}
	
	for actionName, buttonData in pairs(Buttons) do
		takenSlots[buttonData.Slot] = true
	end

	for i = 1, #ButtonPositions do
		if not takenSlots[i] then
			return i
		end
	end
	return nil
end

local function ConnectButton(actionName, functionToBind)
	local data = Buttons[actionName]
	local button = data.Button
	local connections = data.Connections or {}
	
	local function inputBeganHandler(inputObject)

		functionToBind(actionName, Enum.UserInputState.Begin, inputObject)
		button.ImageColor3 = button.BorderColor3
		local title = button:FindFirstChild("title")
		if title then
			title.TextColor3 = button.BorderColor3
		end
	end
	connections.Begin = button.InputBegan:Connect(inputBeganHandler)
	
	local function inputChangedHandler(inputObject)
		functionToBind(actionName, Enum.UserInputState.Change, inputObject)
	end
	connections.Changed = button.InputChanged:Connect(inputChangedHandler)
	
	local function inputEndedHandler(inputObject)
		functionToBind(actionName, Enum.UserInputState.End, inputObject)
		button.ImageColor3 = button.BackgroundColor3
		local title = button:FindFirstChild("title")
		if title then
			title.TextColor3 = button.BackgroundColor3
		end
	end
	connections.MenuOpened = GuiService.MenuOpened:Connect(inputEndedHandler)
	connections.End = button.InputEnded:Connect(inputEndedHandler)
	
	local function mouseLeaveHandler()
		button.ImageColor3 = button.BackgroundColor3
		local title = button:FindFirstChild("title")
		if title then
			title.TextColor3 = button.BackgroundColor3
		end
	end
	button.MouseLeave:Connect(mouseLeaveHandler)
end

local function DisconnectButton(actionName)
	local data = Buttons[actionName]
	if not data.Connections then return end
	for i, p in pairs(data.Connections) do
		if p then
			p:Disconnect()
		end
	end
	data.Connections = {}
end

local function newDefaultButton(actionName, slot)
	local newButton
	newButton = Instance.new("ImageButton")
	newButton.Name = actionName.."Button"
	newButton.BackgroundTransparency = 1
	newButton.Size = UDim2.new(0.8, 0, 0.8, 0)
	newButton.Image = "rbxassetid://5713982324"
	newButton.ImageTransparency = 0.5
	newButton.AnchorPoint = Vector2.new(0.5, 0.5)
	newButton.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	newButton.BorderColor3 = Color3.fromRGB(125, 125, 125)
	
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = newButton
	
	newButton.Position = ButtonPositions[slot]
	return newButton
end

local function BindButton(actionName, functionToBind)
	local button
	local slot
	local data = Buttons[actionName]
	if data then
		if data.Connections then
			DisconnectButton(actionName)
		end
		if data.Slot then
			slot = data.Slot
		else
			slot = GetNextSlot()
		end
		if data.Button then
			button = data.Button
			button.ImageColor3 = button.BackgroundColor3
			local title = button:FindFirstChild("title")
			if title then
				title.TextColor3 = button.BackgroundColor3
			end
		else
			button = newDefaultButton(actionName, slot)
		end
		
	else
		slot = GetNextSlot()
		button = newDefaultButton(actionName, slot)
	end
	
	button.Parent = JumpButton
	
	Buttons[actionName] = {["Name"] = actionName, ["Button"] = button, ["Slot"] = slot, ["Connections"] = {}}
	ConnectButton(actionName, functionToBind)
end

local function UnbindButton(actionName)
	local data = Buttons[actionName]
	if not data then return end
	DisconnectButton(actionName)
	if data.Button then
		data.Button:Destroy()
	end
	Buttons[actionName] = nil
end

local function DisableButton(actionName)
	local data = Buttons[actionName]
	DisconnectButton(actionName)

	local button = data.Button
	button.ImageColor3 = button.BackgroundColor3
	local title = button:FindFirstChild("title")
	if title then
		title.TextColor3 = button.BackgroundColor3
	end
end

local function FixDefaultJumpButton()
	local uiCorner = Instance.new("UICorner")
	uiCorner.CornerRadius = UDim.new(0.5, 0)
	uiCorner.Parent = JumpButton
end
FixDefaultJumpButton()

ContextActionUtility.Archivable = ContextActionService.Archivable
ContextActionUtility.ClassName = ContextActionService.ClassName
ContextActionUtility.Name = ContextActionService.Name
ContextActionUtility.Parent = ContextActionService.Parent

ContextActionUtility.LocalToolEquipped = ContextActionService.LocalToolEquipped
ContextActionUtility.LocalToolUnequipped = ContextActionService.LocalToolUnequipped

function ContextActionUtility:BindAction(actionName, functionToBind, createTouchButton, ...)
	ContextActionService:BindAction(actionName, functionToBind, false, ...)
	if createTouchButton and isMobile then
		BindButton(actionName, functionToBind)
	end
end

function ContextActionUtility:BindActionAtPriority(actionName, functionToBind, createTouchButton, priorityLevel, ...)
	ContextActionService:BindAction(actionName, functionToBind, false, priorityLevel, ...)
	if createTouchButton and isMobile then
		BindButton(actionName, functionToBind)
	end
end

function ContextActionUtility:UnbindAction(actionName)
	ContextActionService:UnbindAction(actionName)
	if isMobile then
		UnbindButton(actionName)
	end
end

function ContextActionUtility:DisableAction(actionName, effectList)
	ContextActionService:UnbindAction(actionName)
	if isMobile then
		DisableButton(actionName, effectList)
	end
end

function ContextActionUtility:SetTitle(actionName, title)
	local data = Buttons[actionName]
	if not data then return end
	if not title then
		title = actionName
	end
	local button = data.Button
	if not button then return end
	local textLabel = button:FindFirstChild("title")
	if not textLabel then
		textLabel = Instance.new("TextLabel")
		textLabel.Name = "title"
		textLabel.AnchorPoint = Vector2.new(0.5, 0.5)
		textLabel.Position = UDim2.new(0.5, 0, 0.5, 0)
		textLabel.BackgroundTransparency = 1
		textLabel.Size = UDim2.new(0.75, 0, 0.45, 0)
		textLabel.Font = Enum.Font.SourceSansBold
		textLabel.TextScaled = true
		textLabel.TextTransparency = 0.5
		textLabel.TextColor3 = Color3.new(255, 255, 255)
		textLabel.TextXAlignment = Enum.TextXAlignment.Center
		textLabel.TextYAlignment = Enum.TextYAlignment.Center
	end
	textLabel.Visible = true
	textLabel.Text = title
	textLabel.Parent = button
end

function ContextActionUtility:SetImage(actionName, image)
	local data = Buttons[actionName]
	if not data then return end
	data.Button.Image = image
end

function ContextActionUtility:SetPressedColor(actionName, color)
	local data = Buttons[actionName]
	if not data then return end
	local button = data.Button
	if not button then return end
	button.BorderColor3 = color
end

function ContextActionUtility:SetReleasedColor(actionName, color)
	local data = Buttons[actionName]
	if not data then return end
	local button = data.Button
	if not button then return end
	button.ImageColor3 = color
	button.BackgroundColor3 = color
	local title = button:FindFirstChild("title")
	if title then
		title.TextColor3 = color
	end
end

function ContextActionUtility:MakeButtonSquare(actionName)
	local data = Buttons[actionName]
	if not data then return end
	local button = data.Button
	if not button then return end
	
	local corner = button:FindFirstChildOfClass("UICorner")
	if corner then 
		corner.CornerRadius = UDim.new(0, 0)
	end
end

function ContextActionUtility:MakeButtonRound(actionName, amount)
	local data = Buttons[actionName]
	if not data then return end
	local button = data.Button
	if not button then return end
	
	local corner = button:FindFirstChildOfClass("UICorner")
	if not corner then 
		local corner = Instance.new("UICorner", button)
	end
	if not amount then
		amount = 0.5
	end
	corner.CornerRadius = UDim.new(amount, 0)
end


function ContextActionUtility:GetButton(actionName)
	local data = Buttons[actionName]
	if not data then return nil end
	return data.Button
end

return ContextActionUtility
