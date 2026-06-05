local a = {}
a.cache = {}
a.load = function(b)
	if not a.cache[b] then
		a.cache[b] = a[b]()
	end
	return a.cache[b]
end

local abs   = math.abs
local clamp = math.clamp
local min   = math.min
local v2    = Vector2.new
local c3    = Color3.fromRGB
local ws    = workspace

local MAX_DIST_SQ  = 500 * 500
local LOD_NEAR_SQ  = 100 * 100
local LOD_MED_SQ   = 250 * 250

local OCCLUDE_FREQ = 4

local FLAGS_NEAR = { Box=true,  Tracer=true,  Skeleton=true,  Health=true,  Label=true  }
local FLAGS_MED  = { Box=true,  Tracer=true,  Skeleton=false, Health=true,  Label=true  }
local FLAGS_FAR  = { Box=true,  Tracer=true,  Skeleton=false, Health=false, Label=false }

do
	function a.b()
		local b = {Objects = {}}
		b.__index = b

		function b:GetDrawingObject(c, d)
			local e = self.Objects
			local f = e[c]
			if not f then
				f = {Objects = {}, Counter = 1}
				e[c] = f
			end
			local g, h = f.Counter, f.Objects
			local i = h[g]
			f.Counter += 1
			if not i then
				i = d(c)
				h[g] = i
			end
			return i
		end

		function b:CleanUp()
			for _, c in pairs(self.Objects) do
				local objs = c.Objects
				c.Counter = 1
				for i = 1, #objs do
					local l = objs[i]
					if l then l.Visible = false end
				end
			end
		end

		return b
	end

	function a.c()
		local b    = {Enabled = true, Jobs = {}}
		local rs   = game:GetService('RunService')
		local pool = a.load('b')
		local draw = nil

		function b:AddRenderJob(fn)
			table.insert(self.Jobs, fn)
		end

		function b:RenderStep()
			pool:CleanUp()
			draw:FlushCache()
			for _, fn in ipairs(self.Jobs) do
				pcall(fn)
			end
		end

		function b:BeginRenderJobs()
			draw = a.load('d')
			rs.PreRender:Connect(function()
				if self.Enabled then self:RenderStep() end
			end)
		end

		return b
	end

	local SKELETON_MAPS = {
		R15 = {
			{'Head','UpperTorso'}, {'UpperTorso','LowerTorso'},
			{'UpperTorso','LeftUpperArm'},  {'LeftUpperArm','LeftLowerArm'},   {'LeftLowerArm','LeftHand'},
			{'UpperTorso','RightUpperArm'}, {'RightUpperArm','RightLowerArm'}, {'RightLowerArm','RightHand'},
			{'LowerTorso','LeftUpperLeg'},  {'LeftUpperLeg','LeftLowerLeg'},   {'LeftLowerLeg','LeftFoot'},
			{'LowerTorso','RightUpperLeg'}, {'RightUpperLeg','RightLowerLeg'}, {'RightLowerLeg','RightFoot'},
		},
		R6 = {
			{'Head','Torso'},
			{'Torso','Left Arm'},  {'Torso','Right Arm'},
			{'Torso','Left Leg'},  {'Torso','Right Leg'},
		},
	}

	function a.d()
		local b            = {}
		local pool         = a.load('b')
		local uis          = game:GetService('UserInputService')
		local frameCache   = {}
		local camCache     = nil
		local modelMeta    = {}
		local drawCreators = {}

		local COLOR_BOX      = c3(94,  255, 0  )
		local COLOR_WHITE    = c3(255, 255, 255 )
		local COLOR_SKELETON = c3(255, 157, 0  )
		local COLOR_HP_FULL  = c3(9,   255, 0  )
		local COLOR_HP_EMPTY = c3(255, 0,   0  )

		function b:FlushCache()
			table.clear(frameCache)
			camCache = nil
		end

		function b:GetCamera()
			if not camCache then camCache = ws.CurrentCamera end
			return camCache
		end

		function b:GetObject(objType)
			local fn = drawCreators[objType]
			if not fn then
				fn = function() return Drawing.new(objType) end
				drawCreators[objType] = fn
			end
			return pool:GetDrawingObject(objType, fn)
		end

		function b:GetMousePosition()
			return uis:GetMouseLocation()
		end

		function b:GetMeta(model)
			local meta = modelMeta[model]
			if meta then return meta end

			local hum   = model:FindFirstChildOfClass('Humanoid')
			local map   = hum and SKELETON_MAPS[hum.RigType.Name]
			local bones = {}
			if map then
				for _, pair in ipairs(map) do
					local bA = model:FindFirstChild(pair[1])
					local bB = model:FindFirstChild(pair[2])
					if bA and bB then
						bones[#bones + 1] = {bA, bB}
					end
				end
			end

			meta = {
				hum       = hum,
				head      = model:FindFirstChild('Head'),
				bones     = bones,
				pts       = {false, false, false, false},
				rayParams = nil,
				occluded  = false,
				occludeAt = -OCCLUDE_FREQ,
			}
			modelMeta[model] = meta

			model.AncestryChanged:Connect(function()
				if not model:IsDescendantOf(ws) then
					modelMeta[model] = nil
				end
			end)

			return meta
		end

		function b:GetOffscreenPoint(pos)
			local cam = self:GetCamera()
			if not cam then return nil end
			local vp     = cam.ViewportSize
			local center = vp * 0.5
			local vec    = pos - cam.CFrame.Position
			if vec.Magnitude == 0 then return center end
			local dir  = vec.Unit
			local dx   = dir:Dot(cam.CFrame.RightVector)
			local dy   = dir:Dot(cam.CFrame.UpVector)
			local flat = v2(dx, -dy)
			if flat.Magnitude == 0 then return center end
			flat = flat.Unit
			local sx = flat.X ~= 0 and abs(center.X / flat.X) or math.huge
			local sy = flat.Y ~= 0 and abs(center.Y / flat.Y) or math.huge
			return center + flat * min(sx, sy)
		end

		function b:ToScreenPoint(pos, allowOffscreen)
			local cam = self:GetCamera()
			if not cam then return nil, false end
			if typeof(pos) == 'CFrame' then pos = pos.Position end
			local p, onScreen = cam:WorldToViewportPoint(pos)
			if not onScreen and allowOffscreen then
				local edge = self:GetOffscreenPoint(pos)
				if edge then return edge, false end
			end
			return v2(p.X, p.Y), onScreen
		end

		function b:Get2DBoxPoints(model, meta)
			local cached = frameCache[model]
			if cached ~= nil then return cached end

			local cam = self:GetCamera()
			if not cam then
				frameCache[model] = false
				return nil
			end

			local cframe, size
			if model:IsA('Model') then
				cframe, size = model:GetBoundingBox()
			else
				cframe, size = model.CFrame, model.Size
			end

			local cfPos         = cframe.Position
			local pos, onScreen = cam:WorldToViewportPoint(cfPos)
			if not onScreen or pos.Z <= 0 then
				frameCache[model] = false
				return nil
			end

			local halfH  = size.Y * 0.5
			local up     = cframe.UpVector
			local topRaw = cam:WorldToViewportPoint(cfPos + up * halfH)
			local botRaw = cam:WorldToViewportPoint(cfPos - up * halfH)
			if topRaw.Z <= 0 or botRaw.Z <= 0 then
				frameCache[model] = false
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
			frameCache[model] = pts
			return pts
		end

		function b:IsObstructedThrottled(pivot, ignoreList, meta, frame)
			if frame - meta.occludeAt < OCCLUDE_FREQ then
				return meta.occluded
			end
			meta.occludeAt = frame

			local cam = self:GetCamera()
			if not cam then
				meta.occluded = false
				return false
			end

			local dir  = pivot - cam.CFrame.Position
			local dist = dir.Magnitude
			if dist < 0.001 then
				meta.occluded = false
				return false
			end

			if not meta.rayParams then
				local rp = RaycastParams.new()
				rp.FilterType = Enum.RaycastFilterType.Exclude
				meta.rayParams = rp
			end
			meta.rayParams.FilterDescendantsInstances = ignoreList

			local result = ws:Raycast(cam.CFrame.Position, dir, meta.rayParams)
			local solid  = false
			if result then
				local hit = result.Instance
				solid = hit:IsA('BasePart') and hit.Transparency < 0.7
			end
			meta.occluded = solid
			return solid
		end

		function b:Draw2DBox(pts, opts)
			local color          = opts.Color or COLOR_BOX
			local tl, tr, bl, br = pts[1], pts[2], pts[3], pts[4]
			local top = self:GetObject('Line'); top.Color = color; top.From = tl; top.To = tr; top.Visible = true
			local bot = self:GetObject('Line'); bot.Color = color; bot.From = bl; bot.To = br; bot.Visible = true
			local lft = self:GetObject('Line'); lft.Color = color; lft.From = tl; lft.To = bl; lft.Visible = true
			local rgt = self:GetObject('Line'); rgt.Color = color; rgt.From = tr; rgt.To = br; rgt.Visible = true
		end

		function b:DrawTracer(model, pts, opts)
			local cam = self:GetCamera()
			if not cam then return end

			local target
			if pts then
				target = (pts[3] + pts[4]) * 0.5
			else
				local sp, onScr = self:ToScreenPoint(model:GetPivot().Position)
				if not onScr then return end
				target = sp
			end

			local vp = cam.ViewportSize
			local l  = self:GetObject('Line')
			l.Color   = opts.Color or COLOR_BOX
			l.From    = opts.Origin or v2(vp.X * 0.5, vp.Y - 10)
			l.To      = target
			l.Visible = true
		end

		function b:DrawSkeleton(opts, meta)
			local cam = self:GetCamera()
			if not cam then return end
			local color = opts.SkeletonColor or opts.Color or COLOR_SKELETON
			for _, pair in ipairs(meta.bones) do
				local partA, partB = pair[1], pair[2]
				if not partA.Parent or not partB.Parent then continue end
				local pA, okA = cam:WorldToViewportPoint(partA.Position)
				local pB, okB = cam:WorldToViewportPoint(partB.Position)
				if okA and okB then
					local line = self:GetObject('Line')
					line.From    = v2(pA.X, pA.Y)
					line.To      = v2(pB.X, pB.Y)
					line.Color   = color
					line.Visible = true
				end
			end
		end

		function b:DrawHealth(pts, opts, meta)
			local hum = meta.hum
			if not hum or hum.MaxHealth <= 0 then return end
			local tl, bl = pts[1], pts[3]
			local wX = bl.X - tl.X
			local wY = bl.Y - tl.Y
			if wX == 0 and wY == 0 then return end
			local nudge = v2(wY * 0.1, -wX * 0.1)
			local pct   = clamp(hum.Health / hum.MaxHealth, 0, 1)
			local tip   = tl:Lerp(bl, 1 - pct)
			if pct < 1 then
				local bg = self:GetObject('Line')
				bg.From    = tl - nudge
				bg.To      = bl - nudge
				bg.Color   = opts.EmptyColor or COLOR_HP_EMPTY
				bg.Visible = true
			end

			if pct > 0 then
				local bar = self:GetObject('Line')
				bar.From    = tip - nudge
				bar.To      = bl  - nudge
				bar.Color   = opts.HealthColor or COLOR_HP_FULL
				bar.Visible = true
			end
		end

		function b:DrawLabel(pts, opts)
			local size = opts.Size or 16
			local tl, tr = pts[1], pts[2]
			local cx      = (tl.X + tr.X) * 0.5
			local anchorY = tl.Y

			local t = self:GetObject('Text')
			t.Text     = opts.Text or '?'
			t.Color    = opts.Color or COLOR_WHITE
			t.Size     = size
			t.Center   = false
			t.Outline  = true
			t.Visible  = true
			t.Position = v2(cx - (t.TextBounds.X * 0.5), anchorY - size - 2)
		end

		function b:DrawModel(model, flags, opts, meta)
			local pts = self:Get2DBoxPoints(model, meta)

			if flags.Box    and pts then self:Draw2DBox(pts, opts) end
			if flags.Tracer          then self:DrawTracer(model, pts, opts) end
			if not pts then return end

			if flags.Skeleton then self:DrawSkeleton(opts, meta) end
			if flags.Health   then self:DrawHealth(pts, opts, meta) end
			if flags.Label    then self:DrawLabel(pts, opts) end  -- FIX 9 cont.
		end

		return b
	end
end

local Renderer = a.load('c')
local Draw     = a.load('d')

Renderer:BeginRenderJobs()

local Players = game:GetService('Players')
local LP      = Players.LocalPlayer

local targetFolder = workspace

local cachedModels = {}

local function addModel(child)
	if child:IsA('Model') then
		cachedModels[#cachedModels + 1] = child
	end
end

local function removeModel(child)
	for i = #cachedModels, 1, -1 do
		if cachedModels[i] == child then
			local n = #cachedModels
			cachedModels[i] = cachedModels[n]
			cachedModels[n] = nil
			return
		end
	end
end

for _, child in ipairs(targetFolder:GetChildren()) do addModel(child) end
targetFolder.ChildAdded:Connect(addModel)
targetFolder.ChildRemoved:Connect(removeModel)

local IGNORE_WITH_LP = {nil, nil}
local IGNORE_NO_LP   = {nil}

local OPTS = {
	Color         = c3(255, 50,  50),
	HealthColor   = c3(9,   255, 0 ),
	EmptyColor    = c3(255, 0,   0 ),
	SkeletonColor = c3(255, 157, 0 ),
	Size          = 16,
}

local frameCount = 0

Renderer:AddRenderJob(function()
	frameCount  += 1
	local lpChar = LP.Character
	OPTS.Origin  = Draw:GetMousePosition()

	local cam = Draw:GetCamera()
	if not cam then return end

	local camCF  = cam.CFrame
	local camPos = camCF.Position
	local camFwd = camCF.LookVector

	for _, model in ipairs(cachedModels) do
		if model == lpChar then continue end

		local pivot = model:GetPivot().Position

		local dx = pivot.X - camPos.X
		local dy = pivot.Y - camPos.Y
		local dz = pivot.Z - camPos.Z
		local distSq = dx*dx + dy*dy + dz*dz
		if distSq > MAX_DIST_SQ then continue end

		if camFwd.X*dx + camFwd.Y*dy + camFwd.Z*dz < 0 then continue end

		local flags
		if     distSq <= LOD_NEAR_SQ then flags = FLAGS_NEAR
		elseif distSq <= LOD_MED_SQ  then flags = FLAGS_MED
		else                               flags = FLAGS_FAR
		end

		local meta = Draw:GetMeta(model)

		local ignoreList
		if lpChar then
			IGNORE_WITH_LP[1] = lpChar
			IGNORE_WITH_LP[2] = model
			ignoreList = IGNORE_WITH_LP
		else
			IGNORE_NO_LP[1] = model
			ignoreList = IGNORE_NO_LP
		end

		if Draw:IsObstructedThrottled(pivot, ignoreList, meta, frameCount) then continue end

		OPTS.Text = model.Name
		Draw:DrawModel(model, flags, OPTS, meta)
	end
end)