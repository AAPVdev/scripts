local URLS = {
    "https://raw.githubusercontent.com/AAPVdev/scripts/refs/heads/main/src/games/brm5.lua",
}

local args = { ... }
local unpack = table.unpack or unpack

for _, url in ipairs(URLS) do
    local okFetch, source = pcall(function()
        return game:HttpGet(url)
    end)
    if okFetch and source and source ~= "" then
        local fn = loadstring(source)
        if fn then
            local okRun, result = pcall(fn, unpack(args))
            if okRun then
                return result
            end
        end
    end
end

error("Failed to load brm5 source")
