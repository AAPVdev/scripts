local URLS = {
    "https://raw.githubusercontent.com/AAPVdev/scripts/refs/heads/main/src/manager/manager.lua",
}

if script and script.Parent and script.Parent.Parent then
    local srcRoot = script.Parent.Parent:FindFirstChild("src")
    local managerFolder = srcRoot and srcRoot:FindFirstChild("manager")
    local moduleScript = managerFolder and managerFolder:FindFirstChild("manager")
    if moduleScript then
        return require(moduleScript)
    end
end

for _, url in ipairs(URLS) do
    local okFetch, source = pcall(function()
        return game:HttpGet(url)
    end)
    if okFetch and source and source ~= "" then
        local fn = loadstring(source)
        if fn then
            local okRun, result = pcall(fn)
            if okRun then
                return result
            end
        end
    end
end

error("Failed to load manager source")
