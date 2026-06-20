local SIXSEVENESP = {}
SIXSEVENESP.__index = SIXSEVENESP

local function missing(t, f, fallback)
	if type(f) == t then return f end
	return fallback
end

local cloneref    = missing("function", cloneref, function(obj) return obj end)

local RunService        = cloneref(game:GetService("RunService"))
local UserInputService  = cloneref(game:GetService("UserInputService"))
local Players           = cloneref(game:GetService("Players"))
local Workspace         = cloneref(game:GetService("Workspace"))

local lp     = Players.LocalPlayer
local lpChar = lp and lp.Character
if lp then
	lp.CharacterAdded:Connect(function(c)    lpChar = c   end)
	lp.CharacterRemoving:Connect(function()  lpChar = nil end)
end

local abs   = math.abs
local clamp = math.clamp
local min   = math.min

local huge  = math.huge
local v2    = Vector2.new
local c3    = Color3.fromRGB

local VERTICES = {
	Vector3.new(-1, -1, -1),
	Vector3.new(-1,  1, -1),
	Vector3.new(-1,  1,  1),
	Vector3.new(-1, -1,  1),
	Vector3.new( 1, -1, -1),
	Vector3.new( 1,  1, -1),
	Vector3.new( 1,  1,  1),
	Vector3.new( 1, -1,  1),
}

local DEFAULT_LOD = {
	MaxDistance        = 500,
	NearDistance       = 100,
	MediumDistance     = 250,
	OcclusionEnabled   = true,
	OcclusionFrequency = 4,
}

local DEFAULT_FLAGS = {
	Near   = { Box = true,  Tracer = true,  Skeleton = true,  Health = true,  Label = true,  Box3D = false },
	Medium = { Box = true,  Tracer = true,  Skeleton = false, Health = true,  Label = true,  Box3D = false },
	Far    = { Box = true,  Tracer = true,  Skeleton = false, Health = false, Label = false, Box3D = false },
}

local DEFAULT_SKELETON_MAPS = {
	R15 = {
		{ "Head", "UpperTorso" }, { "UpperTorso", "LowerTorso" },
		{ "UpperTorso", "LeftUpperArm" },  { "LeftUpperArm", "LeftLowerArm" },   { "LeftLowerArm", "LeftHand" },
		{ "UpperTorso", "RightUpperArm" }, { "RightUpperArm", "RightLowerArm" }, { "RightLowerArm", "RightHand" },
		{ "LowerTorso", "LeftUpperLeg" },  { "LeftUpperLeg", "LeftLowerLeg" },   { "LeftLowerLeg", "LeftFoot" },
		{ "LowerTorso", "RightUpperLeg" }, { "RightUpperLeg", "RightLowerLeg" }, { "RightLowerLeg", "RightFoot" },
	},
	R6 = {
		{ "Head", "Torso" },
		{ "Torso", "Left Arm" }, { "Torso", "Right Arm" },
		{ "Torso", "Left Leg" }, { "Torso", "Right Leg" },
	},
}

local DEFAULT_OPTIONS = {
	Enabled               = true,
	Color                 = c3(255, 50, 50),
	Box3DColor            = c3(255, 50, 50),
	HealthColor           = c3(9, 255, 0),
	EmptyColor            = c3(255, 0, 0),
	SkeletonColor         = c3(255, 157, 0),
	TextColor             = c3(255, 255, 255),
	TextSize              = 16,
	UseOffscreenPoint     = true,
	FilterLocalCharacter  = true,
	AutoUntrackMissing    = true,

	LOD          = DEFAULT_LOD,
	Flags        = DEFAULT_FLAGS,
	SkeletonMaps = DEFAULT_SKELETON_MAPS,

	CanDraw = nil,

	MaxInitPerFrame             = 10,   
	MaxOcclusionChecksPerFrame  = 5,    

	TextResolver = function(model, meta)
		return model.Name
	end,
}

local function cloneTable(src)
	local dst = {}
	for k, v in pairs(src) do
		if type(v) == "table" then
			dst[k] = cloneTable(v)
		else
			dst[k] = v
		end
	end
	return dst
end

local function mergeDeep(dst, src)
	for k, v in pairs(src) do
		if type(v) == "table" and type(dst[k]) == "table" then
			mergeDeep(dst[k], v)
		else
			dst[k] = v
		end
	end
	return dst
end

local function newPool()
	local self = { Objects = {} }

	function self:GetDrawingObject(kind, ctor)
		local bucket = self.Objects[kind]
		if not bucket then
			bucket = { Objects = {}, Counter = 1, PrevHighWater = 0 }
			self.Objects[kind] = bucket
		end

		local idx = bucket.Counter
		bucket.Counter += 1

		local obj = bucket.Objects[idx]
		if not obj then
			obj = ctor(kind)
			bucket.Objects[idx] = obj
		end

		return obj
	end

	function self:BeginFrame()
		for _, bucket in pairs(self.Objects) do
			bucket.PrevHighWater = bucket.Counter - 1
			bucket.Counter = 1
		end
	end

	function self:EndFrame()
		for _, bucket in pairs(self.Objects) do
			local used = bucket.Counter - 1
			local prev = bucket.PrevHighWater
			for i = used + 1, prev do
				local obj = bucket.Objects[i]
				if obj then
					obj.Visible = false
				end
			end
		end
	end

	function self:Reset()
		for _, bucket in pairs(self.Objects) do
			bucket.Counter = 1
			bucket.PrevHighWater = 0
			for i = 1, #bucket.Objects do
				local obj = bucket.Objects[i]
				if obj then
					obj.Visible = false
				end
			end
		end
	end

	return self
end

function SIXSEVENESP.IsCharacterModel(model)
	if typeof(model) ~= "Instance" or not model:IsA("Model") then
		return false
	end

	local hum = model:FindFirstChildOfClass("Humanoid")
	if not hum then
		return false
	end

	if hum.RigType ~= Enum.HumanoidRigType.R6 and hum.RigType ~= Enum.HumanoidRigType.R15 then
		return false
	end

	if not model:FindFirstChild("HumanoidRootPart") then
		return false
	end

	if not model:FindFirstChild("Head") then
		return false
	end

	return true
end

function SIXSEVENESP.new(config)
	local self = setmetatable({}, SIXSEVENESP)

	self.Config = cloneTable(DEFAULT_OPTIONS)
	if config then
		mergeDeep(self.Config, config)
	end

	self.Enabled       = self.Config.Enabled ~= false
	self._tracked      = {}
	self._meta         = {}
	self._frameCache   = {}

	self._bboxCache    = {}
	self._camCache     = nil
	self._pool         = newPool()
	self._connections  = {}
	self._running      = false
	self._frameCount   = 0

	self._initDoneThisFrame = 0
	self._occlusionDoneThisFrame = 0

	return self
end

function SIXSEVENESP:SetOptions(options)
	if not options then return end
	mergeDeep(self.Config, options)
	self.Enabled = self.Config.Enabled ~= false
end

function SIXSEVENESP:GetCamera()
	if not self._camCache then
		self._camCache = Workspace.CurrentCamera
	end
	return self._camCache
end

function SIXSEVENESP:FlushCache()
	table.clear(self._frameCache)
	table.clear(self._bboxCache)
	self._camCache = nil
end

function SIXSEVENESP:GetObject(kind)
	return self._pool:GetDrawingObject(kind, function() return Drawing.new(kind) end)
end

function SIXSEVENESP:GetMousePosition()
	return UserInputService:GetMouseLocation()
end

function SIXSEVENESP:Track(model)
	if not self.IsCharacterModel(model) then
		return false, "Model is not a valid character rig"
	end
	self._tracked[model] = true
	return true
end

function SIXSEVENESP:Untrack(model)
	local meta = self._meta[model]
	if meta and meta._ancestryConn then
		meta._ancestryConn:Disconnect()
		meta._ancestryConn = nil
	end
	self._tracked[model]    = nil
	self._meta[model]       = nil
	self._frameCache[model] = nil
	self._bboxCache[model]  = nil
end

function SIXSEVENESP:ClearCharacters()
	for _, meta in pairs(self._meta) do
		if meta._ancestryConn then
			meta._ancestryConn:Disconnect()
		end
	end
	table.clear(self._tracked)
	table.clear(self._meta)
	table.clear(self._frameCache)
	table.clear(self._bboxCache)
end

function SIXSEVENESP:SetCharacters(list)
	self:ClearCharacters()
	for _, model in ipairs(list or {}) do
		self:Track(model)
	end
end

function SIXSEVENESP:GetMeta(model)
	local meta = self._meta[model]
	if meta then
		return meta
	end

	local hum = model:FindFirstChildOfClass("Humanoid")
	if not hum then
		return nil
	end

	local rigName = hum.RigType.Name
	local map     = self.Config.SkeletonMaps[rigName]
	local bones   = {}

	if map then
		for _, pair in ipairs(map) do
			local a = model:FindFirstChild(pair[1])
			local b = model:FindFirstChild(pair[2])
			if a and b then
				bones[#bones + 1] = { a, b }
			end
		end
	end

	meta = {
		hum       = hum,
		head      = model:FindFirstChild("Head"),
		bones     = bones,
		pts       = { false, false, false, false },
		occluded  = false,
		
		occludeAt = -self.Config.LOD.OcclusionFrequency + math.random(0, self.Config.LOD.OcclusionFrequency - 1),

		ignoreList = {},

		opts = {
			Color         = false,
			Box3DColor    = false,
			HealthColor   = false,
			EmptyColor    = false,
			SkeletonColor = false,
			TextColor     = false,
			Size          = 0,
			Text          = "",
		},

		pivot = Vector3.new(),
		
		_cachedBBox = nil,
	}

	self._meta[model] = meta

	meta._ancestryConn = model.AncestryChanged:Connect(function()
		if self.Config.AutoUntrackMissing and not model:IsDescendantOf(Workspace) then
			self:Untrack(model)
		end
	end)

	local cf, sz = model:GetBoundingBox()
	if cf then
		meta._cachedBBox = {cf, sz}
	end

	return meta
end

function SIXSEVENESP:GetOffscreenPoint(pos)
	local cam = self:GetCamera()
	if not cam then return nil end

	local vp     = cam.ViewportSize
	local center = vp * 0.5
	local vec    = pos - cam.CFrame.Position
	if vec.Magnitude == 0 then
		return center
	end

	local dir = vec.Unit
	local dx  = dir:Dot(cam.CFrame.RightVector)
	local dy  = dir:Dot(cam.CFrame.UpVector)
	local flat = v2(dx, -dy)
	if flat.Magnitude == 0 then
		return center
	end

	flat = flat.Unit

	local sx = flat.X ~= 0 and abs(center.X / flat.X) or huge
	local sy = flat.Y ~= 0 and abs(center.Y / flat.Y) or huge
	return center + flat * min(sx, sy)
end

function SIXSEVENESP:ToScreenPoint(pos, allowOffscreen)
	local cam = self:GetCamera()
	if not cam then return nil, false end

	if typeof(pos) == "CFrame" then
		pos = pos.Position
	end

	local p, onScreen = cam:WorldToViewportPoint(pos)
	if not onScreen and allowOffscreen and self.Config.UseOffscreenPoint then
		local edge = self:GetOffscreenPoint(pos)
		if edge then
			return edge, false
		end
	end

	return v2(p.X, p.Y), onScreen
end

function SIXSEVENESP:GetModelBBox(model)
	
	local meta = self._meta[model]
	if meta and meta._cachedBBox then
		return meta._cachedBBox[1], meta._cachedBBox[2]
	end

	local cframe, size = model:GetBoundingBox()
	if meta then
		meta._cachedBBox = {cframe, size}
	end
	return cframe, size
end

function SIXSEVENESP:Get2DBoxPoints(model, meta)
	local cached = self._frameCache[model]
	if cached ~= nil then
		return cached
	end

	local cam = self:GetCamera()
	if not cam then
		self._frameCache[model] = false
		return nil
	end

	local cframe, size = self:GetModelBBox(model)
	local cfPos = cframe.Position

	local pos, onScreen = cam:WorldToViewportPoint(cfPos)
	if not onScreen or pos.Z <= 0 then
		self._frameCache[model] = false
		return nil
	end

	local halfH  = size.Y * 0.5
	local up     = cframe.UpVector
	local topRaw = cam:WorldToViewportPoint(cfPos + up * halfH)
	local botRaw = cam:WorldToViewportPoint(cfPos - up * halfH)

	if topRaw.Z <= 0 or botRaw.Z <= 0 then
		self._frameCache[model] = false
		return nil
	end

	local height = abs(topRaw.Y - botRaw.Y)
	local hw, hh = height * 0.325, height * 0.5
	local cx, cy = pos.X, pos.Y

	local pts = meta.pts
	pts[1] = v2(cx - hw, cy - hh)
	pts[2] = v2(cx + hw, cy - hh)
	pts[3] = v2(cx - hw, cy + hh)
	pts[4] = v2(cx + hw, cy + hh)

	self._frameCache[model] = pts
	return pts
end

function SIXSEVENESP:Get3DBoxCorners(model)
	local cam = self:GetCamera()
	if not cam then return nil end

	local cframe, size = self:GetModelBBox(model)
	local corners    = {}
	local valid      = {}
	local anyVisible = false

	for i = 1, #VERTICES do
		local localOffset = size * 0.5 * VERTICES[i]
		local worldPos    = cframe:PointToWorldSpace(localOffset)
		local screen, onScreen = cam:WorldToViewportPoint(worldPos)
		local ok             = onScreen and screen.Z > 0
		corners[i]           = v2(screen.X, screen.Y)
		valid[i]             = ok
		if ok then anyVisible = true end
	end

	if not anyVisible then return nil end
	return corners, valid
end

function SIXSEVENESP:IsObstructedThrottled(pivot, ignoreList, meta, frame)
	if self.Config.LOD.OcclusionEnabled == false then
		meta.occluded = false
		return false
	end
	local freq = self.Config.LOD.OcclusionFrequency
	if frame - meta.occludeAt < freq then
		return meta.occluded
	end

	if self._occlusionDoneThisFrame >= self.Config.MaxOcclusionChecksPerFrame then
		return meta.occluded   
	end

	meta.occludeAt = frame
	self._occlusionDoneThisFrame = self._occlusionDoneThisFrame + 1

	local cam = self:GetCamera()
	if not cam then
		meta.occluded = false
		return false
	end

	local dir = pivot - cam.CFrame.Position
	if dir.Magnitude < 0.001 then
		meta.occluded = false
		return false
	end

	if not meta.rayParams then
		local rp = RaycastParams.new()
		rp.FilterType = Enum.RaycastFilterType.Exclude
		meta.rayParams = rp
	end
	meta.rayParams.FilterDescendantsInstances = ignoreList

	local result = Workspace:Raycast(cam.CFrame.Position, dir, meta.rayParams)

	local solid = false
	if result and result.Instance then
		local hit = result.Instance
		solid = hit:IsA("BasePart") and hit.Transparency < 0.7
	end

	meta.occluded = solid
	return solid
end

function SIXSEVENESP:Draw2DBox(pts, opts)
	local color        = opts.Color or self.Config.Color
	local tl, tr, bl, br = pts[1], pts[2], pts[3], pts[4]

	local top     = self:GetObject("Line")
	top.Color     = color
	top.From      = tl
	top.To        = tr
	top.Visible   = true

	local bot     = self:GetObject("Line")
	bot.Color     = color
	bot.From      = bl
	bot.To        = br
	bot.Visible   = true

	local lft     = self:GetObject("Line")
	lft.Color     = color
	lft.From      = tl
	lft.To        = bl
	lft.Visible   = true

	local rgt     = self:GetObject("Line")
	rgt.Color     = color
	rgt.From      = tr
	rgt.To        = br
	rgt.Visible   = true
end

function SIXSEVENESP:Draw3DBox(corners, valid, opts)
	local color = opts.Box3DColor or opts.Color or self.Config.Box3DColor

	for i = 1, 4 do
		local iNext     = i == 4 and 1 or i + 1
		local iBack     = i == 4 and 5 or i + 5
		local iBackNext = i == 4 and 8 or i + 4

		if valid[i] and valid[iNext] then
			local line1   = self:GetObject("Line")
			line1.From    = corners[i]
			line1.To      = corners[iNext]
			line1.Color   = color
			line1.Visible = true
		end

		if valid[iNext] and valid[iBack] then
			local line2   = self:GetObject("Line")
			line2.From    = corners[iNext]
			line2.To      = corners[iBack]
			line2.Color   = color
			line2.Visible = true
		end

		if valid[iBack] and valid[iBackNext] then
			local line3   = self:GetObject("Line")
			line3.From    = corners[iBack]
			line3.To      = corners[iBackNext]
			line3.Color   = color
			line3.Visible = true
		end
	end
end

function SIXSEVENESP:DrawTracer(model, pts, opts)
	local cam = self:GetCamera()
	if not cam then return end

	local target
	if pts then
		target = (pts[3] + pts[4]) * 0.5
	else
		local sp, onScr = self:ToScreenPoint(opts.Pivot, true)
		if not sp then return end
		target = sp
	end

	local tracerOrigin = opts.TracerOrigin
	local origin
	if type(tracerOrigin) == "function" then
		origin = tracerOrigin()
	elseif tracerOrigin ~= nil then
		origin = tracerOrigin
	else
		local vp = cam.ViewportSize
		origin = v2(vp.X * 0.5, vp.Y - 10)
	end

	local l     = self:GetObject("Line")
	l.Color     = opts.Color or self.Config.Color
	l.From      = origin
	l.To        = target
	l.Visible   = true
end

function SIXSEVENESP:DrawSkeleton(opts, meta)
	local cam = self:GetCamera()
	if not cam then return end

	local color = opts.SkeletonColor or opts.Color or self.Config.SkeletonColor
	for _, pair in ipairs(meta.bones) do
		local partA, partB = pair[1], pair[2]
		if not partA.Parent or not partB.Parent then
			continue
		end

		local pA, okA = cam:WorldToViewportPoint(partA.Position)
		local pB, okB = cam:WorldToViewportPoint(partB.Position)
		local inFront = pA.Z > 0 and pB.Z > 0
		if inFront and (okA or okB) then
			local line   = self:GetObject("Line")
			line.From    = v2(pA.X, pA.Y)
			line.To      = v2(pB.X, pB.Y)
			line.Color   = color
			line.Visible = true
		end
	end
end

function SIXSEVENESP:DrawHealth(pts, opts, meta)
	local hum = meta.hum
	if not hum or hum.MaxHealth <= 0 then return end

	local tl, bl = pts[1], pts[3]
	local wY = bl.Y - tl.Y
	if wY == 0 then return end

	local nudge = v2(wY * 0.1, 0)
	local pct   = clamp(hum.Health / hum.MaxHealth, 0, 1)
	local tip   = tl:Lerp(bl, 1 - pct)

	if pct < 1 then
		local bg    = self:GetObject("Line")
		bg.From     = tl - nudge
		bg.To       = bl - nudge
		bg.Color    = opts.EmptyColor or self.Config.EmptyColor
		bg.Visible  = true
	end

	if pct > 0 then
		local bar   = self:GetObject("Line")
		bar.From    = tip - nudge
		bar.To      = bl - nudge
		bar.Color   = opts.HealthColor or self.Config.HealthColor
		bar.Visible = true
	end
end

function SIXSEVENESP:DrawLabel(pts, opts)
	local size   = opts.Size or self.Config.TextSize
	local tl, tr = pts[1], pts[2]
	local cx     = (tl.X + tr.X) * 0.5
	local anchorY = tl.Y

	local t     = self:GetObject("Text")
	t.Text      = opts.Text or "?"
	t.Color     = opts.TextColor or self.Config.TextColor
	t.Size      = size
	t.Center    = true
	t.Outline   = true
	t.Visible   = true
	t.Position  = v2(cx, anchorY - size - 2)
end

function SIXSEVENESP:DrawModel(model, flags, opts, meta)
	local pts = self:Get2DBoxPoints(model, meta)

	if flags.Box and pts then
		self:Draw2DBox(pts, opts)
	end

	if flags.Box3D then
		local corners, valid = self:Get3DBoxCorners(model)
		if corners then
			self:Draw3DBox(corners, valid, opts)
		end
	end

	if flags.Tracer then
		self:DrawTracer(model, pts, opts)
	end

	if not pts then return end

	if flags.Skeleton then
		self:DrawSkeleton(opts, meta)
	end

	if flags.Health then
		self:DrawHealth(pts, opts, meta)
	end

	if flags.Label then
		self:DrawLabel(pts, opts)
	end
end

function SIXSEVENESP:GetLODFlags(distSq, nearDistSq, mediumDistSq)
	local flags = self.Config.Flags

	if distSq <= nearDistSq then
		return flags.Near
	elseif distSq <= mediumDistSq then
		return flags.Medium
	else
		return flags.Far
	end
end

function SIXSEVENESP:RenderStep()
	self._frameCount += 1

	self._pool:BeginFrame()
	self:FlushCache()

	self._initDoneThisFrame = 0
	self._occlusionDoneThisFrame = 0

	local cam = self:GetCamera()
	if not cam then
		self._pool:EndFrame()
		return
	end

	local camCF  = cam.CFrame
	local camPos = camCF.Position

	local lod          = self.Config.LOD
	local maxDistSq    = lod.MaxDistance    * lod.MaxDistance
	local nearDistSq   = lod.NearDistance   * lod.NearDistance
	local mediumDistSq = lod.MediumDistance * lod.MediumDistance

	local toUntrack = {}

	for model in pairs(self._tracked) do
		if not model or not model.Parent then
			if self.Config.AutoUntrackMissing then
				toUntrack[#toUntrack + 1] = model
			end
			continue
		end

		if self._meta[model] then
			continue
		end

		if self._initDoneThisFrame >= self.Config.MaxInitPerFrame then
			break
		end

		if not model:FindFirstChildOfClass("Humanoid") or not model:FindFirstChild("HumanoidRootPart") then
			continue
		end

		self:GetMeta(model)
		self._initDoneThisFrame = self._initDoneThisFrame + 1
	end

	for model in pairs(self._tracked) do
		if not model or not model.Parent then
			
			continue
		end

		local meta = self._meta[model]
		if not meta then
			
			continue
		end

		if self.Config.FilterLocalCharacter and model == lpChar then
			continue
		end

		if not model:FindFirstChildOfClass("Humanoid")
			or not model:FindFirstChild("HumanoidRootPart") then
			continue
		end

		if self.Config.CanDraw then
			local ok = self.Config.CanDraw(model)
			if ok == false then
				continue
			end
		end

		local pivot = model:GetPivot().Position

		local dx    = pivot.X - camPos.X
		local dy    = pivot.Y - camPos.Y
		local dz    = pivot.Z - camPos.Z
		local distSq = dx * dx + dy * dy + dz * dz

		if distSq > maxDistSq then
			continue
		end

		local flags = self:GetLODFlags(distSq, nearDistSq, mediumDistSq)

		meta.pivot = pivot

		local ignoreList = meta.ignoreList
		if lpChar then
			ignoreList[1] = lpChar
			ignoreList[2] = model
		else
			ignoreList[1] = model
			ignoreList[2] = nil
		end

		if self:IsObstructedThrottled(pivot, ignoreList, meta, self._frameCount) then
			continue
		end

		local cfg  = self.Config
		local opts = meta.opts
		opts.Color         = cfg.Color
		opts.Box3DColor    = cfg.Box3DColor
		opts.HealthColor   = cfg.HealthColor
		opts.EmptyColor    = cfg.EmptyColor
		opts.SkeletonColor = cfg.SkeletonColor
		opts.TextColor     = cfg.TextColor
		opts.Size          = cfg.TextSize
		opts.Text          = cfg.TextResolver(model, meta)
		opts.TracerOrigin  = cfg.TracerOrigin
		opts.Pivot         = pivot

		self:DrawModel(model, flags, opts, meta)
	end

	for _, m in ipairs(toUntrack) do
		self:Untrack(m)
	end

	self._pool:EndFrame()
end

function SIXSEVENESP:Start()
	if self._running then return end
	self._running = true

	self._connections.Render = RunService.PreRender:Connect(function()
		if self.Enabled then
			self:RenderStep()
		end
	end)
end

function SIXSEVENESP:Stop()
	self._running = false
	for _, conn in pairs(self._connections) do
		if conn then conn:Disconnect() end
	end
	table.clear(self._connections)
	self._pool:Reset()
end

function SIXSEVENESP:Destroy()
	self:Stop()
	self:ClearCharacters()

	for _, bucket in pairs(self._pool.Objects) do
		for _, obj in ipairs(bucket.Objects) do
			if obj then obj:Remove() end
		end
	end
end

return SIXSEVENESP
