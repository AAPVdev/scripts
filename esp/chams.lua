local hui = gethui()

local module = {}
module.VERSION = "2.0.0"

local activeHighlights = {}
local uniqueCounter = 0
local container = hui  

module.defaults = {
	FillColor = Color3.fromRGB(255, 255, 0),
	OutlineColor = Color3.new(1, 1, 1),
	FillTransparency = 0.5,
	OutlineTransparency = 0.5,
}

local function applyProperties(highlight, properties)
	if typeof(properties) ~= "table" then
		warn("CharacterHighlighter: properties must be a table, got " .. typeof(properties))
		return
	end
	for prop, value in pairs(properties) do
		local ok, err = pcall(function()
			highlight[prop] = value
		end)
		if not ok then
			warn(("CharacterHighlighter: failed to set property '%s' - %s"):format(prop, tostring(err)))
		end
	end
end

local function getUniqueId()
	uniqueCounter = uniqueCounter + 1
	return "id" .. uniqueCounter
end

local function recomputeVisibility(character)
	local data = activeHighlights[character]
	if not data then return end

	local bestSource = nil
	for _, source in pairs(data.sources) do
		source.highlight.Enabled = false
		if not source.suppressed and (not bestSource or source.priority > bestSource.priority) then
			bestSource = source
		end
	end

	if bestSource then
		bestSource.highlight.Enabled = true
	end
end

local function watchCharacter(character)
	local destroyingConnection = character.Destroying:Connect(function()
		module.removeAllHighlights(character)
	end)
	local ancestryConnection = character.AncestryChanged:Connect(function()
		if not character:IsDescendantOf(game) then
			module.removeAllHighlights(character)
		end
	end)
	return { destroyingConnection, ancestryConnection }
end

function module.addHighlight(character, sourceKey, properties, priority)
	if typeof(character) ~= "Instance" or not character:IsA("Model") then
		warn("CharacterHighlighter: Expected a Model")
		return nil
	end
	if typeof(sourceKey) ~= "string" then
		warn("CharacterHighlighter: addHighlight requires a sourceKey string")
		return nil
	end

	local data = activeHighlights[character]
	if not data then
		data = {
			sources = {},
			connections = watchCharacter(character),
		}
		activeHighlights[character] = data
	end

	local existing = data.sources[sourceKey]
	if existing then
		existing.highlight:Destroy()
	end

	local highlight = Instance.new("Highlight")
	highlight.Name = "Highlight_" .. character.Name .. "_" .. sourceKey .. "_" .. getUniqueId()
	highlight.Adornee = character
	highlight.Enabled = false

	applyProperties(highlight, module.defaults)
	if properties then
		applyProperties(highlight, properties)
	end

	highlight.Parent = container  

	data.sources[sourceKey] = {
		highlight = highlight,
		priority = priority or 0,
		suppressed = false,
	}

	recomputeVisibility(character)

	return highlight
end

function module.removeHighlight(character, sourceKey)
	if typeof(sourceKey) ~= "string" then
		warn("CharacterHighlighter: removeHighlight requires a sourceKey string - did you mean removeAllHighlights?")
		return
	end

	local data = activeHighlights[character]
	if not data then return end

	local source = data.sources[sourceKey]
	if not source then return end

	source.highlight:Destroy()
	data.sources[sourceKey] = nil

	if next(data.sources) == nil then
		for _, connection in ipairs(data.connections) do
			connection:Disconnect()
		end
		activeHighlights[character] = nil
	else
		recomputeVisibility(character)
	end
end

function module.removeAllHighlights(character)
	local data = activeHighlights[character]
	if not data then return end

	local sourceKeys = {}
	for sourceKey in pairs(data.sources) do
		table.insert(sourceKeys, sourceKey)
	end
	for _, sourceKey in ipairs(sourceKeys) do
		module.removeHighlight(character, sourceKey)
	end
end

function module.getHighlight(character, sourceKey)
	local data = activeHighlights[character]
	if not data then return nil end
	local source = data.sources[sourceKey]
	return source and source.highlight or nil
end

function module.isHighlighted(character, sourceKey)
	local data = activeHighlights[character]
	if not data then return false end
	if sourceKey == nil then
		return next(data.sources) ~= nil
	end
	return data.sources[sourceKey] ~= nil
end

function module.updateHighlight(character, sourceKey, properties)
	local data = activeHighlights[character]
	if not data then return false end
	local source = data.sources[sourceKey]
	if not source then return false end
	applyProperties(source.highlight, properties)
	return true
end

function module.setEnabled(character, sourceKey, enabled)
	local data = activeHighlights[character]
	if not data then return false end
	local source = data.sources[sourceKey]
	if not source then return false end
	source.suppressed = not enabled
	recomputeVisibility(character)
	return true
end

function module.allHighlights()
	return coroutine.wrap(function()
		for character, data in pairs(activeHighlights) do
			local bestSource = nil
			for _, source in pairs(data.sources) do
				if not source.suppressed and (not bestSource or source.priority > bestSource.priority) then
					bestSource = source
				end
			end
			if bestSource then
				coroutine.yield(character, bestSource.highlight)
			end
		end
	end)
end

function module.allSources()
	return coroutine.wrap(function()
		for character, data in pairs(activeHighlights) do
			for sourceKey, source in pairs(data.sources) do
				coroutine.yield(character, sourceKey, source.highlight)
			end
		end
	end)
end

function module.clearAllHighlights()
	for character in pairs(activeHighlights) do
		module.removeAllHighlights(character)
	end
end

return module
