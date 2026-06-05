# SIXSEVENESP.lua

A strict character-only overlay module for Roblox character rigs.

## Overview

`SIXSEVENESP` is a client-side renderer/controller that tracks only valid character models and draws:
- 2D boxes
- tracers
- skeleton lines
- health bars
- labels

It is designed around a configurable API so you can control what gets drawn, how targets are selected, and how the module behaves at different distances.

---

## Installation

```lua
local SIXSEVENESP = require(path.To.SIXSEVENESP)
```

---

## Constructor

### `SIXSEVENESP.new(config?)`

Creates a new overlay controller.

#### Parameters
- `config` *(table, optional)*: Configuration overrides.

#### Returns
- `SIXSEVENESP` instance

#### Example
```lua
local esp = SIXSEVENESP.new({
    Enabled = true,
    Color = Color3.fromRGB(255, 50, 50),
})
```

---

## Static Helpers

### `SIXSEVENESP.IsCharacterModel(model)`

Checks whether a model qualifies as a valid character rig.

A valid character must:
- be a `Model`
- contain a `Humanoid`
- have `HumanoidRootPart`
- have `Head`
- use `R6` or `R15`

#### Returns
- `true` if valid
- `false` otherwise

---

## Instance Methods

### `:SetOptions(options)`

Updates the current configuration.

#### Parameters
- `options` *(table)*: Partial config table to merge into the current config.

#### Example
```lua
esp:SetOptions({
    Enabled = false,
    TextSize = 18,
})
```

---

### `:Track(model)`

Adds a character model to the tracked set.

#### Parameters
- `model` *(Model)*: Character model to track.

#### Returns
- `true, nil` on success
- `false, reason` if the model is invalid

#### Example
```lua
esp:Track(workspace.NPC)
```

---

### `:Untrack(model)`

Removes a model from tracking.

#### Parameters
- `model` *(Model)*

#### Example
```lua
esp:Untrack(workspace.NPC)
```

---

### `:SetCharacters(list)`

Replaces the tracked set with a new list.

#### Parameters
- `list` *(array<Model>)*

#### Example
```lua
esp:SetCharacters({
    workspace.NPC1,
    workspace.NPC2,
})
```

---

### `:ClearCharacters()`

Clears all tracked models.

#### Example
```lua
esp:ClearCharacters()
```

---

### `:GetCamera()`

Returns the cached current camera.

#### Returns
- `Camera | nil`

---

### `:FlushCache()`

Clears per-frame caches and camera cache.

Useful if you want to force the module to refresh all computed screen-space data immediately.

---

### `:GetMeta(model)`

Returns or creates metadata for a tracked model.

#### Returns
- metadata table or `nil`

#### Metadata fields
- `hum`
- `head`
- `bones`
- `pts`
- `rayParams`
- `occluded`
- `occludeAt`

---

### `:GetObject(kind)`

Returns a pooled Drawing object of the requested kind.

#### Parameters
- `kind` *(string)*: Drawing object type such as `"Line"` or `"Text"`.

#### Returns
- pooled drawing object

---

### `:Get2DBoxPoints(model, meta)`

Computes the 2D corner points of the target’s bounding box.

#### Returns
- `table | nil`

---

### `:GetOffscreenPoint(pos)`

Projects a world position to the viewport edge when the target is off-screen.

#### Returns
- `Vector2 | nil`

---

### `:ToScreenPoint(pos, allowOffscreen)`

Converts a world position to screen space.

#### Parameters
- `pos` *(Vector3 | CFrame)*
- `allowOffscreen` *(boolean)*

#### Returns
- `Vector2 | nil`
- `boolean` indicating whether the point is on-screen

---

### `:IsObstructedThrottled(pivot, ignoreList, meta, frame)`

Performs throttled line-of-sight occlusion testing.

#### Parameters
- `pivot` *(Vector3)*
- `ignoreList` *(array<Instance>)*
- `meta` *(table)*
- `frame` *(number)*

#### Returns
- `true` if obstructed
- `false` otherwise

---

### `:Draw2DBox(pts, opts)`

Draws a box from 2D points.

#### Parameters
- `pts` *(array<Vector2>)*: Points returned by `Get2DBoxPoints`
- `opts` *(table)*: Drawing options

---

### `:DrawTracer(model, pts, opts)`

Draws a line from the tracer origin to the target.

#### Parameters
- `model` *(Model)*
- `pts` *(array<Vector2> | nil)*
- `opts` *(table)*

---

### `:DrawSkeleton(opts, meta)`

Draws skeleton lines using the model metadata.

#### Parameters
- `opts` *(table)*
- `meta` *(table)*

---

### `:DrawHealth(pts, opts, meta)`

Draws a health bar based on humanoid health.

#### Parameters
- `pts` *(array<Vector2>)*`
- `opts` *(table)*
- `meta` *(table)*

---

### `:DrawLabel(pts, opts)`

Draws a text label above the target.

#### Parameters
- `pts` *(array<Vector2>)*`
- `opts` *(table)*

---

### `:DrawModel(model, flags, opts, meta)`

High-level draw entry point used internally by the render loop.

#### Parameters
- `model` *(Model)*
- `flags` *(table)*
- `opts` *(table)*
- `meta` *(table)*

---

### `:GetLODFlags(distSq)`

Returns the correct flag set for a squared distance.

#### Returns
- one of:
  - `Config.Flags.Near`
  - `Config.Flags.Medium`
  - `Config.Flags.Far`

---

### `:RenderStep()`

Runs one full render pass.

This:
- clears frame caches
- resets pooled draw objects
- processes all tracked models
- draws any visible targets

Normally called automatically after `:Start()`.

---

### `:Start()`

Starts the render loop.

#### Example
```lua
esp:Start()
```

---

### `:Stop()`

Stops the render loop and disconnects internal connections.

---

### `:Destroy()`

Stops the loop and frees internal state.

---

## Configuration

### Base Options

| Key | Type | Default | Description |
|---|---|---:|---|
| `Enabled` | boolean | `true` | Master enable switch |
| `Color` | Color3 | red | Main drawing color |
| `HealthColor` | Color3 | green | Filled health bar color |
| `EmptyColor` | Color3 | red | Empty health bar color |
| `SkeletonColor` | Color3 | orange | Skeleton line color |
| `TextColor` | Color3 | white | Label color |
| `TextSize` | number | `16` | Label font size |
| `TracerOrigin` | Vector2 or function | `nil` | Custom tracer origin |
| `UseOffscreenPoint` | boolean | `true` | Edge-project off-screen targets |
| `FilterLocalCharacter` | boolean | `true` | Skip the local player character |
| `AutoUntrackMissing` | boolean | `true` | Remove destroyed/missing models automatically |
| `LOD` | table | see below | Distance thresholds |
| `Flags` | table | see below | What to draw at each distance tier |
| `SkeletonMaps` | table | see below | Rig bone mapping |
| `CanDraw` | function | `nil` | Optional per-model draw filter |
| `TextResolver` | function | returns `model.Name` | Custom label text |

---

### LOD Table

| Key | Default | Description |
|---|---:|---|
| `MaxDistance` | `500` | Maximum draw distance |
| `NearDistance` | `100` | Near-tier threshold |
| `MediumDistance` | `250` | Medium-tier threshold |
| `OcclusionFrequency` | `4` | How often occlusion checks run |

---

### Flags Table

Each distance tier is a flag table with these keys:

- `Box`
- `Tracer`
- `Skeleton`
- `Health`
- `Label`

#### Default behavior

**Near**
```lua
{ Box = true, Tracer = true, Skeleton = true, Health = true, Label = true }
```

**Medium**
```lua
{ Box = true, Tracer = true, Skeleton = false, Health = true, Label = true }
```

**Far**
```lua
{ Box = true, Tracer = true, Skeleton = false, Health = false, Label = false }
```

---

### SkeletonMaps

Default bone maps are provided for:
- `R15`
- `R6`

You can replace them or extend them with your own rig layouts.

Example:
```lua
SkeletonMaps = {
    R15 = {
        {"Head", "UpperTorso"},
    },
    R6 = {
        {"Head", "Torso"},
    }
}
```

---

## Events and Internal Behavior

The module does not expose custom RBXScriptSignal events. Instead, it behaves like a controller:

- call `:Track()` or `:SetCharacters()`
- call `:Start()`
- let `:RenderStep()` process the tracked characters every frame
- call `:Stop()` or `:Destroy()` when done

Each tracked model also gets internal metadata cached automatically.

---

## Minimal Example

```lua
local SIXSEVENESP = require(path.To.SIXSEVENESP)

local overlay = SIXSEVENESP.new()
overlay:Track(workspace.NPC)
overlay:Start()
```

---

## Custom Example

```lua
local SIXSEVENESP = require(path.To.SIXSEVENESP)

local overlay = SIXSEVENESP.new({
    Enabled = true,
    Color = Color3.fromRGB(255, 70, 70),
    TextSize = 18,
    CanDraw = function(model)
        return model.Name ~= "IgnoreMe"
    end,
    TextResolver = function(model, meta)
        return model.Name .. " [" .. math.floor(meta.hum.Health) .. "]"
    end,
    TracerOrigin = function()
        local cam = workspace.CurrentCamera
        if not cam then
            return Vector2.new(0, 0)
        end
        local vp = cam.ViewportSize
        return Vector2.new(vp.X * 0.5, vp.Y - 20)
    end,
})

overlay:SetCharacters({
    workspace.NPC1,
    workspace.NPC2,
})

overlay:Start()
```

---

## Notes

- This module only accepts valid character models.
- Non-character `Model` instances are rejected by `:Track()`.
- The module is designed for client-side rendering logic.
- The drawing backend assumes `Drawing.new(...)` is available in the environment.

## Suggested Extension Points

If you want to expand the API later, good additions would be:
- `:SetTargetFolder(folder)`
- `:AddCharacter(model)`
- `:RemoveCharacter(model)`
- `:SetTheme(theme)`
- `:SetVisibilityFilter(fn)`
- `:OnModelBecameInvalid(fn)`
