local cloneref = type(cloneref) == "function" and cloneref or function(obj) return obj end

local CoreGui   = cloneref(game:GetService("CoreGui"))
local Workspace = cloneref(game:GetService("Workspace"))

local table_clear = table.clear

local MAX_POOL_SIZE = 32

local cachedContainer     = nil
local cachedFromGethui    = false
local function getHighlightContainer()
	if cachedContainer then
		if cachedFromGethui or cachedContainer.Parent ~= nil then
			return cachedContainer
		end
		cachedContainer = nil
	end
	if type(gethui) == "function" then
		local ok, container = pcall(gethui)
		if ok and container then
			cachedContainer  = container
			cachedFromGethui = true
			return container
		end
	end
	cachedContainer  = CoreGui
	cachedFromGethui = false
	return CoreGui
end

local Chams   = {}
Chams.VERSION = "2.4.0"

local activeHighlights = {}
local highlightPool    = {}
local uniqueCounter    = 0
local orderCounter     = 0

Chams.defaults = {
	FillColor           = Color3.fromRGB(255, 255, 0),
	OutlineColor        = Color3.new(1, 1, 1),
	FillTransparency    = 0.5,
	OutlineTransparency = 0.5,
}

local KNOWN_HIGHLIGHT_PROPS = {
	FillColor           = true,
	OutlineColor        = true,
	FillTransparency    = true,
	OutlineTransparency = true,
	DepthMode           = true,
	Enabled             = true,
	Adornee             = true,
}

local function rawSetHighlightProp(highlight, prop, value)
	if highlight[prop] ~= value then
		highlight[prop] = value
	end
end

local function applyProperties(highlight, properties)
	if type(properties) ~= "table" then
		warn("[Chams] properties must be a table, got " .. typeof(properties))
		return
	end
	for prop, value in pairs(properties) do
		if KNOWN_HIGHLIGHT_PROPS[prop] then
			if highlight[prop] ~= value then
				highlight[prop] = value
			end
		else
			local ok, err = pcall(rawSetHighlightProp, highlight, prop, value)
			if not ok then
				warn(("[Chams] failed to set property '%s': %s"):format(tostring(prop), tostring(err)))
			end
		end
	end
end

local function acquireHighlight(name, character, properties)
	local highlight = nil
	while #highlightPool > 0 do
		local candidate = highlightPool[#highlightPool]
		highlightPool[#highlightPool] = nil
		if candidate and candidate.Parent ~= nil then
			highlight = candidate
			break
		end
	end

	if not highlight then
		highlight         = Instance.new("Highlight")
		highlight.Enabled = false
		highlight.Parent  = getHighlightContainer()
	else
		highlight.Enabled = false
	end

	highlight.Name    = name
	highlight.Adornee = character

	local defs = Chams.defaults
	for prop, defVal in pairs(defs) do
		local val = (properties and properties[prop] ~= nil) and properties[prop] or defVal
		if highlight[prop] ~= val then
			highlight[prop] = val
		end
	end

	if type(properties) == "table" then
		for prop, val in pairs(properties) do
			if defs[prop] == nil then
				if KNOWN_HIGHLIGHT_PROPS[prop] then
					if highlight[prop] ~= val then
						highlight[prop] = val
					end
				else
					pcall(rawSetHighlightProp, highlight, prop, val)
				end
			end
		end
	end

	return highlight
end

local function releaseHighlight(highlight)
	if not highlight then return end
	if #highlightPool < MAX_POOL_SIZE and highlight.Parent ~= nil then
		highlight.Enabled = false
		highlight.Adornee = nil
		highlightPool[#highlightPool + 1] = highlight
	else
		pcall(highlight.Destroy, highlight)
	end
end

local function disconnectList(conns)
	if not conns then return end
	for i = 1, #conns do
		local conn = conns[i]
		if conn and conn.Connected then
			conn:Disconnect()
		end
	end
end

local function getUniqueId()
	uniqueCounter = uniqueCounter + 1
	return "id" .. uniqueCounter
end

local function nextOrder()
	orderCounter = orderCounter + 1
	return orderCounter
end

local function getBestSource(sources)
	local best = nil
	for _, source in pairs(sources) do
		if not source.suppressed then
			if not best
				or source.priority > best.priority
				or (source.priority == best.priority and source.order > best.order) then
				best = source
			end
		end
	end
	return best
end

local function recomputeVisibility(character)
	local data = activeHighlights[character]
	if not data then return end

	local bestSource = getBestSource(data.sources)
	for _, source in pairs(data.sources) do
		local shouldEnable = (source == bestSource)
		if source.highlight.Enabled ~= shouldEnable then
			source.highlight.Enabled = shouldEnable
		end
	end
end

local function watchCharacter(character)
	local conns = {}
	if character.Destroying then
		conns[#conns + 1] = character.Destroying:Connect(function()
			Chams.removeAllHighlights(character)
		end)
	end
	conns[#conns + 1] = character.AncestryChanged:Connect(function()
		if not character.Parent or not character:IsDescendantOf(Workspace) then
			Chams.removeAllHighlights(character)
		end
	end)
	return conns
end

function Chams.addHighlight(character, sourceKey, properties, priority)
	if typeof(character) ~= "Instance" or not character:IsA("Model") then
		warn("[Chams] Expected a Model")
		return nil
	end
	if type(sourceKey) ~= "string" then
		warn("[Chams] addHighlight requires a sourceKey string")
		return nil
	end
	if not character.Parent or not character:IsDescendantOf(Workspace) then
		return nil
	end

	local data = activeHighlights[character]
	if not data then
		data = {
			sources     = {},
			connections = watchCharacter(character),
		}
		activeHighlights[character] = data
	end

	local existing  = data.sources[sourceKey]
	local highlight = existing and existing.highlight or nil

	if not highlight or not highlight.Parent then
		if highlight then
			pcall(highlight.Destroy, highlight)
		end
		local hName = "Highlight_" .. character.Name .. "_" .. sourceKey .. "_" .. getUniqueId()
		highlight = acquireHighlight(hName, character, properties)
	else
		if highlight.Adornee ~= character then
			highlight.Adornee = character
		end
		if properties then
			applyProperties(highlight, properties)
		end
	end

	if existing then
		existing.highlight  = highlight
		existing.suppressed = false
		existing.order      = nextOrder()
		if priority ~= nil then
			existing.priority = priority
		end
	else
		data.sources[sourceKey] = {
			highlight  = highlight,
			priority   = priority or 0,
			order      = nextOrder(),
			suppressed = false,
		}
	end

	recomputeVisibility(character)
	return highlight
end

function Chams.removeHighlight(character, sourceKey)
	if type(sourceKey) ~= "string" then
		warn("[Chams] removeHighlight requires a sourceKey string - did you mean removeAllHighlights?")
		return
	end

	local data = activeHighlights[character]
	if not data then return end

	local source = data.sources[sourceKey]
	if not source then return end

	releaseHighlight(source.highlight)
	data.sources[sourceKey] = nil

	if next(data.sources) == nil then
		disconnectList(data.connections)
		activeHighlights[character] = nil
	else
		recomputeVisibility(character)
	end
end

function Chams.removeAllHighlights(character)
	local data = activeHighlights[character]
	if not data then return end

	for _, source in pairs(data.sources) do
		releaseHighlight(source.highlight)
	end
	table_clear(data.sources)

	disconnectList(data.connections)
	activeHighlights[character] = nil
end

function Chams.getHighlight(character, sourceKey)
	local data = activeHighlights[character]
	if not data then return nil end
	local source = data.sources[sourceKey]
	return source and source.highlight or nil
end

function Chams.isHighlighted(character, sourceKey)
	local data = activeHighlights[character]
	if not data then return false end
	if sourceKey == nil then
		return next(data.sources) ~= nil
	end
	return data.sources[sourceKey] ~= nil
end

function Chams.updateHighlight(character, sourceKey, properties)
	local data = activeHighlights[character]
	if not data then return false end
	local source = data.sources[sourceKey]
	if not source then return false end
	applyProperties(source.highlight, properties)
	return true
end

function Chams.updateSource(sourceKey, properties)
	if type(sourceKey) ~= "string" or type(properties) ~= "table" then return 0 end
	local count = 0
	for _, data in pairs(activeHighlights) do
		local source = data.sources[sourceKey]
		if source then
			applyProperties(source.highlight, properties)
			count = count + 1
		end
	end
	return count
end

function Chams.removeSource(sourceKey)
	if type(sourceKey) ~= "string" then return 0 end
	local targets = {}
	for character, data in pairs(activeHighlights) do
		if data.sources[sourceKey] then
			targets[#targets + 1] = character
		end
	end
	for i = 1, #targets do
		Chams.removeHighlight(targets[i], sourceKey)
	end
	return #targets
end

function Chams.setEnabled(character, sourceKey, enabled)
	local data = activeHighlights[character]
	if not data then return false end
	local source = data.sources[sourceKey]
	if not source then return false end
	source.suppressed = not enabled
	recomputeVisibility(character)
	return true
end

function Chams.allHighlights()
	return coroutine.wrap(function()
		for character, data in pairs(activeHighlights) do
			local bestSource = getBestSource(data.sources)
			if bestSource then
				coroutine.yield(character, bestSource.highlight)
			end
		end
	end)
end

function Chams.allSources()
	return coroutine.wrap(function()
		for character, data in pairs(activeHighlights) do
			for sourceKey, source in pairs(data.sources) do
				coroutine.yield(character, sourceKey, source.highlight)
			end
		end
	end)
end

function Chams.clearAllHighlights()
	local characters = {}
	for character in pairs(activeHighlights) do
		characters[#characters + 1] = character
	end
	for i = 1, #characters do
		Chams.removeAllHighlights(characters[i])
	end
end

function Chams.Destroy()
	Chams.clearAllHighlights()
	for i = #highlightPool, 1, -1 do
		local highlight = highlightPool[i]
		highlightPool[i] = nil
		if highlight then
			pcall(highlight.Destroy, highlight)
		end
	end
end

return Chams
