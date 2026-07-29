local URLS = {
    "https://raw.githubusercontent.com/AAPVdev/scripts/refs/heads/main/src/LimbExtender.lua",
}

if script and script.Parent then
    local srcFolder = script.Parent:FindFirstChild("src")
    local moduleScript = srcFolder and srcFolder:FindFirstChild("LimbExtender")
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

error("Failed to load LimbExtender source")
