-- Bypass made by AnthonyIsntHere
-- https://github.com/AnthonyIsntHere/anthonysrepository/blob/main/scripts/InstanceBypass.lua
if not getgenv().__InstanceBypassLoaded then
    getgenv().__InstanceBypassLoaded = true

    local ProtectedInstances = {}

    local _Instance = Instance.new
    local _tostring = tostring
    local Metatable, Metamethods

    local InstanceHook; InstanceHook = hookfunction(Instance.new, clonefunction(newcclosure(function(...)
        if checkcaller() then
            local NewInstance = InstanceHook(...)
            sethiddenproperty(NewInstance, "DefinesCapabilities", true)
            ProtectedInstances[NewInstance] = true

            if Metatable and Metamethods then
                Metatable.__namecall = Metamethods.__namecall
                Metatable.__index = Metamethods.__index
            end

            Metatable = getrawmetatable(NewInstance)
            Metamethods = {
                __namecall = Metatable.__namecall,
                __index = Metatable.__index
            }

            setreadonly(Metatable, false)
            Metatable.__namecall = clonefunction(function(self, ...)
                if not checkcaller() then
                    local Arguments = {...}
                    local Method = getnamecallmethod()

                    if ProtectedInstances[self] then
                        return task.wait(2^53 - 1)
                    end

                    if typeof(Method) == "string" and Method:lower():match("^findfirst") or Method:lower():match("^waitforchild") then
                        local Instance = Metamethods.__namecall(self, ...)

                        if Instance and ProtectedInstances[Instance] then
                            return task.wait(2^53 - 1)
                        end
                    end
                end

                return Metamethods.__namecall(self, ...)
            end)

            Metatable.__index = clonefunction(function(self, index)
                if not checkcaller() then
                    if typeof(index) == "string" and ((ProtectedInstances[self] and index:lower():match("^is")) or index:lower():match("^findfirst")) then
                        local IndexFunction = Metamethods.__index(self, index)

                        if typeof(IndexFunction) == "function" and not isfunctionhooked(IndexFunction) then
                            local IndexFunctionHook; IndexFunctionHook = hookfunction(IndexFunction, clonefunction(newcclosure(function(...)
                                local Arguments = {...}
                                restorefunction(IndexFunction)

                                local Instance = IndexFunction(self, Arguments[2])
                                if Instance and ProtectedInstances[Instance] or ProtectedInstances[self] then
                                    return task.wait(2^53 - 1)
                                end
                            end)))
                        end
                    end
                end

                if ProtectedInstances[self] and typeof(Metamethods.__index(self, index)) ~= "function" and not checkcaller() then
                    return task.wait(2^53 - 1)
                end

                return Metamethods.__index(self, index)
            end)

            return NewInstance
        end

        return InstanceHook(...)
    end)))

    local tostringHook; tostringHook = hookfunction(_tostring, clonefunction(newcclosure(function(...)
        if not checkcaller() then
            local Arguments = {...}
            local String = tostringHook(...)

            if ProtectedInstances[Arguments[1]] then
                return task.wait(2^53 - 1)
            end
        end

        return tostringHook(...)
    end)))

    local GetConstant = function(f, v)
        for _, Constant in next, debug.getconstants(f) do
            if not rawequal(Constant, v) then continue end
            return true
        end
        return false
    end

    for _, x in next, getreg() do
        local Function = type(x) == "thread" and coroutine.status(x) == "suspended" and debug.info(x, 1, "f")
        local ScriptInstance = Function and getfenv(Function) and typeof(getfenv(Function).script) == "Instance"

        if not Function or not ScriptInstance then continue end
        if GetConstant(Function, "WaitForChild") then
            task.cancel(x)
        end
    end

    local Actor = false
    for _, Thread in next, getactorthreads() do
        run_on_thread(Thread, [[
            if Attached then return end
            getgenv().Attached = true

            local RawMT = getrawmetatable(gethui())
            local PreviousNamecall = RawMT.__namecall
            local PreviousIndex = RawMT.__index

            local _tostring = tostring

            local tostringHook; tostringHook = hookfunction(_tostring, clonefunction(newcclosure(function(...)
                if not checkcaller() then
                    local Arguments = {...}
                    local String = tostringHook(...)

                    if Arguments[1] and typeof(Arguments[1]) == "Instance" and gethiddenproperty(Arguments[1], "DefinesCapabilities") then
                        return task.wait(2^53 - 1)
                    end
                end

                return tostringHook(...)
            end)))

            setreadonly(RawMT, false)
            RawMT.__namecall = clonefunction(function(self, ...)
                local Arguments = {...}
                local Method = getnamecallmethod()

                if not checkcaller() then
                    if typeof(self) == "Instance" and gethiddenproperty(self, "DefinesCapabilities") then
                        return task.wait(2^53 - 1)
                    end

                    if typeof(Method) == "string" and Method:lower():match("^findfirst") or Method:lower():match("^waitforchild") then
                        local Instance = PreviousNamecall(self, ...)

                        if Instance and typeof(Instance) == "Instance" and gethiddenproperty(Instance, "DefinesCapabilities") then
                            return task.wait(2^53 - 1)
                        end
                    end
                end

                return PreviousNamecall(self, ...)
            end)

            RawMT.__index = clonefunction(function(self, index)
                if not checkcaller() then
                    if typeof(index) == "string" and index ~= "DefinesCapabilities" then
                        if index:lower():match("^is") or index:lower():match("^findfirst") then
                            local IndexFunction = PreviousIndex(self, index)

                            if typeof(IndexFunction) == "function" then
                                if not isfunctionhooked(IndexFunction) then
                                    local IndexFunctionHook; IndexFunctionHook = hookfunction(IndexFunction, clonefunction(newcclosure(function(...)
                                        local Arguments = {...}
                                        restorefunction(IndexFunction)

                                        local Instance = IndexFunction(self, Arguments[2])
                                        if Instance or gethiddenproperty(self, "DefinesCapabilities") then
                                            return task.wait(2^53 - 1)
                                        end
                                    end)))
                                end
                            end
                        end

                        if gethiddenproperty(self, "DefinesCapabilities") and typeof(PreviousIndex(self, index)) ~= "function" then
                            return task.wait(2^53 - 1)
                        end
                    end
                end

                return PreviousIndex(self, index)
            end)
            setreadonly(RawMT, true)

            local GetConstant = function(f, v)
                for _, Constant in next, debug.getconstants(f) do
                    if not rawequal(Constant, v) then continue end
                    return true
                end
                return false
            end

            for _, x in next, getreg() do
                local Function = type(x) == "thread" and coroutine.status(x) == "suspended" and debug.info(x, 1, "f")
                local ScriptInstance = Function and getfenv(Function) and typeof(getfenv(Function).script) == "Instance"

                if not Function or not ScriptInstance then continue end
                if GetConstant(Function, "WaitForChild") then
                    task.cancel(x)
                end
            end
        ]])

        Actor = not Actor or true
    end
end

local cloneref = cloneref or function(obj) return obj end
local Players = cloneref(game:GetService("Players"))
local hui = gethui()

local module = {}
module.VERSION = "2.0.0"

local activeHighlights = {}
local uniqueCounter = 0

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

	highlight.Parent = hui

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
