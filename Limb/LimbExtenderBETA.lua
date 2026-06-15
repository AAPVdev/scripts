local globalEnv = type(getgenv) == "function" and getgenv() or _G
local limbData = globalEnv.limbExtenderData or {}
globalEnv.limbExtenderData = limbData

limbData.BaseModule = limbData.BaseModule or loadstring(game:HttpGet('https://raw.githubusercontent.com/AAPVdev/scripts/refs/heads/main/manager/manager.lua'))()

local BaseModule = limbData.BaseModule
local Manager = BaseModule.Manager
local ConnectionManager = BaseModule.ConnectionManager
local isLiveInstance = BaseModule.isLiveInstance

local type, typeof = type, typeof
local pcall = pcall
local table_clear = table.clear
local table_clone = table.clone
local Instance_new = Instance.new
local Vector3_new = Vector3.new
local PhysProps_new = PhysicalProperties.new
local math_max = math.max
local task_spawn = task.spawn

local function missing(t, f, fallback)
	if type(f) == t then return f end
	return fallback
end

local cloneref = missing("function", cloneref, function(obj) return obj end)
local Players = cloneref(game:GetService("Players"))

local localPlayer = Players.LocalPlayer
if not localPlayer then
	Players:GetPropertyChangedSignal("LocalPlayer"):Wait()
	localPlayer = Players.LocalPlayer
end

limbData.playerCache    = limbData.playerCache or {}
limbData.instanceLookup = limbData.instanceLookup or setmetatable({}, { __mode = "k" })
limbData.npcIdCounter   = limbData.npcIdCounter or 0
limbData.changedProxies = limbData.changedProxies or setmetatable({}, { __mode = "k" })

if not limbData.dummyEvent then
	limbData.dummyEvent = Instance_new("BindableEvent")
end

if type(limbData.terminate) == "function" then
	limbData.terminate()
	limbData.terminate = nil
end

local has_checkcaller = type(checkcaller) == "function"
local checkcaller = has_checkcaller and checkcaller or function() return true end
local has_newcclosure = type(newcclosure) == "function"
local has_hookmetamethod = type(hookmetamethod) == "function"
local has_loadstring = type(loadstring) == "function"
local has_httpget = pcall(function()
	if type(game.HttpGet) ~= "function" then error("no") end
end)

local BLOCKED_PROPS = { ... } 

if not limbData._spoofInstalled and has_newcclosure and has_hookmetamethod and has_checkcaller then
	limbData._spoofInstalled = true
	
end

local ESP_SOURCE_URL = "https://raw.githubusercontent.com/AAPVdev/scripts/refs/heads/main/esp/SIXSEVENESP.lua"
local function ensureESPLoaded()
	if limbData.ESP then return limbData.ESP end
	if not (has_loadstring and has_httpget) then return nil end
	local ok, res = pcall(function()
		return loadstring(game:HttpGet(ESP_SOURCE_URL))()
	end)
	if ok then limbData.ESP = res end
	return limbData.ESP
end

local function sharedSaveData(...) ... end
local function sharedApplyLimb(...) ... end
local function sharedRestoreLimb(...) ... end

local LimbExtender = {}
LimbExtender.__index = LimbExtender

local DEFAULTS = {
	TARGET_LIMB = "Head",
	LIMB_SIZE = 15,
	LIMB_TRANSPARENCY = 0.5,
	LIMB_CAN_COLLIDE = false,
	TEAM_CHECK = true,
	FORCEFIELD_CHECK = false,
	ALT_RESET_LIMB_ON_DEATH = false,
	PLAYER_ENABLED = true,
	NPC_ENABLED = false,
	NPC_FILTER = nil,
	NPC_DIRECTORIES = {},

	ESP = false,
	ESP_COLOR = Color3.fromRGB(255, 50, 50),
	
}
local function mergeSettings(user) ... end  

function LimbExtender.new(userSettings)
	local self = setmetatable({
		_settings = mergeSettings(userSettings),
		_playerCache = limbData.playerCache,
		_manager = nil,
		_ESP = nil,
		_running = false,
		_destroyed = false,
		_npcIdMap = {},  
	}, LimbExtender)

	self._manager = Manager.new({
		PLAYER_ENABLED = self._settings.PLAYER_ENABLED,
		NPC_ENABLED = self._settings.NPC_ENABLED,
		NPC_FILTER = self._settings.NPC_FILTER,
		NPC_DIRECTORIES = self._settings.NPC_DIRECTORIES,

		TARGET_LIMB = self._settings.TARGET_LIMB,
		TEAM_CHECK = self._settings.TEAM_CHECK,
		FORCEFIELD_CHECK = self._settings.FORCEFIELD_CHECK,
		DEATH_RESTORE = self._settings.ALT_RESET_LIMB_ON_DEATH,
		GET_LOCAL_TEAM = function() return localPlayer.Team end,

		ON_LIMB_READY = function(player, model, limb)
			self:_applyLimbs(player, model, limb)
		end,
		ON_LIMB_LOST = function(player, model, limb)
			self:_removeLimbs(player, model, limb)
		end,
	})

	if self._settings.ESP then
		self.ESP = ensureESPLoaded()
		if self.ESP then
			self._ESP = self.ESP.new(self:_buildESPConfig())
		else
			self._settings.ESP = false
		end
	end

	limbData.terminate = function() self:Destroy() end
	return self
end

function LimbExtender:_buildESPConfig() ... end 

function LimbExtender:_applyLimbs(player, char, limb)
	if not isLiveInstance(limb) or not limb.Parent then return end
	local cacheKey
	if player then
		cacheKey = player.Name
	else
		
		if not self._npcIdMap[char] then
			limbData.npcIdCounter = limbData.npcIdCounter + 1
			self._npcIdMap[char] = "__npc_" .. limbData.npcIdCounter
		end
		cacheKey = self._npcIdMap[char]
	end

	sharedApplyLimb(self, cacheKey, char, limb)
	if self._ESP then self._ESP:Track(char) end
end

function LimbExtender:_removeLimbs(player, char, limb)
	local cacheKey
	if player then
		cacheKey = player.Name
	else
		cacheKey = self._npcIdMap[char]
	end

	sharedRestoreLimb(self, cacheKey, limb)
	if self._ESP and char then self._ESP:Untrack(char) end
	if not player then
		self._npcIdMap[char] = nil
	end
end

function LimbExtender:Start()
	if self._destroyed or self._running then return end
	self._running = true
	self._manager:Start()
	if self._ESP then self._ESP:Start() end
end

function LimbExtender:Stop()
	if self._destroyed or not self._running then return end
	self._running = false
	self._manager:Stop()

	for cacheKey, entry in pairs(self._playerCache) do
		sharedRestoreLimb(self, cacheKey, entry.Limb)
	end
	table_clear(self._playerCache)

	if self._ESP then self._ESP:Stop() end
end

function LimbExtender:Toggle(state) ... end  
function LimbExtender:Restart() ... end
function LimbExtender:Set(key, value) ... end 
function LimbExtender:Get(key) return self._settings[key] end
function LimbExtender:AddDirectory(dir) self._manager:AddDirectory(dir) end
function LimbExtender:RemoveDirectory(dir) self._manager:RemoveDirectory(dir) end
function LimbExtender:GetDirectories() return self._manager:GetDirectories() end

function LimbExtender:Destroy()
	self:Stop()
	self._destroyed = true
	if self._ESP then self._ESP:Destroy(); self._ESP = nil end
	limbData.terminate = nil
	setmetatable(self, nil)
end

return setmetatable({}, {
	__call = function(_, userSettings) return LimbExtender.new(userSettings) end,
	__index = LimbExtender,
})
