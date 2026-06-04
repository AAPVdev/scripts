# LimbExtender.lua

A Roblox Lua module that manages **dynamic limb resizing** for selected player characters and NPC models.

It is designed as a reusable controller with a small public API:

- create a controller with custom settings
- start, stop, toggle, or restart it
- inspect and change settings at runtime
- manage NPC source directories

The module returns a callable table, so it can be used either as a constructor or through `:new()`.

---

## Overview

When running, the controller:

- targets a limb by name, defaulting to `Head`
- rescales that limb proportionally to a configured maximum size
- applies transparency and collision changes
- optionally watches for team membership, force fields, and death
- supports both player characters and NPC models
- tracks directory changes so NPCs added later are handled automatically

The module also keeps original values so it can restore the character cleanly when stopped or destroyed.

---

## Module export

The file returns a table with these entry points:

```lua
local LimbExtender = loadstring(game:HttpGet("https://raw.githubusercontent.com/AAPVdev/scripts/refs/heads/main/LimbExtender.lua")()

local controller1 = LimbExtender.new({
    LIMB_SIZE = 20,
})

local controller2 = LimbExtender({
    LIMB_SIZE = 20,
})
```

Both forms create a new controller instance.

---

## Requirements

This module expects a Roblox environment with the usual game services and several executor-style globals.

### Core Roblox APIs

- `game`
- `Instance`
- `Players`
- `UserInputService`
- `Workspace`
- `task`
- `Enum`
- `PhysicalProperties`

### Optional / runtime-specific globals

The module checks for and may use the following if present:

- `cloneref`
- `checkcaller`
- `newcclosure`
- `hookmetamethod`
- `getgenv`
- `loadstring`
- `game:HttpGet`

If optional helpers are unavailable, the module falls back where possible, but some features may not work in a plain Roblox environment.

---

## Installation

Place the module in your project and require it from your script.

```lua
local LimbExtender = loadstring(game:HttpGet("https://raw.githubusercontent.com/AAPVdev/scripts/refs/heads/main/LimbExtender.lua")()

local controller = LimbExtender.new():Start()
```

---

## Quick start

```lua
local LimbExtender = loadstring(game:HttpGet("https://raw.githubusercontent.com/AAPVdev/scripts/refs/heads/main/LimbExtender.lua")()

local controller = LimbExtender.new({
    TOGGLE = "L",
    TARGET_LIMB = "Head",
    LIMB_SIZE = 18,
    PLAYER_ENABLED = true,
    NPC_ENABLED = true,
})

controller:Start()
```

---

## Default settings

| Key | Default | Description |
| --- | --- | --- |
| `TOGGLE` | `"L"` | Keyboard key used to toggle the controller. |
| `TARGET_LIMB` | `"Head"` | Name of the part to resize. |
| `LIMB_SIZE` | `15` | Maximum size used for proportional resizing. |
| `LIMB_TRANSPARENCY` | `0.5` | Transparency applied to the target limb. |
| `LIMB_CAN_COLLIDE` | `false` | Collision state applied to the target limb. |
| `MOBILE_BUTTON` | `true` | Enables a mobile action button when supported. |
| `LISTEN_FOR_INPUT` | `true` | Binds keyboard/mobile input for toggling. |
| `TEAM_CHECK` | `false` | Skips players on the same team as the local player. |
| `FORCEFIELD_CHECK` | `true` | Waits for a force field to clear before applying. |
| `RESET_LIMB_ON_DEATH` | `false` | Restores the limb when the humanoid dies. |
| `PLAYER_ENABLED` | `true` | Enables player-character handling. |
| `NPC_ENABLED` | `false` | Enables NPC model handling. |
| `NPC_FILTER` | `nil` | Optional function used to accept or reject NPC models. |
| `NPC_DIRECTORIES` | `{}` | No default path, will scan the entire workspace. |

---

## Supported settings in detail

### `TOGGLE`
Key name from `Enum.KeyCode`, for example:

```lua
TOGGLE = "L"
TOGGLE = "F"
TOGGLE = "Q"
```

### `TARGET_LIMB`
The controller looks for a child with this exact name under each valid character model.

Common examples:

- `"Head"`
- `"HumanoidRootPart"`
- `"Torso"`
- `"UpperTorso"`

### `LIMB_SIZE`
This is not a direct absolute size for every axis. The module scales the original part **proportionally** so the part’s largest axis becomes this value, and the other axes are scaled by the same ratio.

### `LIMB_TRANSPARENCY`
Applied to the target limb while active.

### `LIMB_CAN_COLLIDE`
Applied to the target limb while active.

### `MOBILE_BUTTON`
When available, the controller attempts to bind a mobile action button labeled with the current toggle state.

### `LISTEN_FOR_INPUT`
If `true`, the module listens for input and binds the toggle key.

### `TEAM_CHECK`
When enabled, player characters on the same team as the local player are ignored.

### `FORCEFIELD_CHECK`
When enabled, the module waits until a character is not protected by a `ForceField` before applying changes.

### `RESET_LIMB_ON_DEATH`
If enabled, the active limb is restored when the humanoid dies.

### `PLAYER_ENABLED`
Enables processing of other player characters.

### `NPC_ENABLED`
Enables processing of NPC models discovered in the configured directories.

### `NPC_FILTER`
Optional callback:

```lua
NPC_FILTER = function(model)
    return true
end
```

This is called for each candidate NPC model. Return `true` to accept the model.

### `NPC_DIRECTORIES`
A table of directories to scan for NPC models.

Accepted values in the table:

- live `Instance` objects
- strings representing paths

Examples:

```lua
NPC_DIRECTORIES = { workspace.Misc.AI }
NPC_DIRECTORIES = { "Workspace.Misc.AI" }
NPC_DIRECTORIES = { "game:GetService('Workspace').Misc.AI" }
```

---

## Public API

## Constructor

### `LimbExtender.new(userSettings)`

Creates a new controller instance.

**Parameters**

- `userSettings` — optional table of settings to override the defaults

**Returns**

- a `LimbExtender` controller

**Behavior**

- merges `userSettings` into the defaults
- sets up shared runtime state
- installs input handling when enabled
- starts the controller immediately

---

## Lifecycle methods

### `:Start()`

Starts processing players and NPCs.

**Notes**

- does nothing if already running
- reuses the current settings
- binds tracking for players, NPCs, and directories

---

### `:Stop()`

Stops processing and restores tracked limbs.

**Notes**

- disconnects all active connections
- destroys tracked player and NPC controllers
- clears cached active characters
- does nothing if already stopped

---

### `:Toggle(state)`

Toggles the controller.

**Parameters**

- `state` — optional boolean  
  - `true` starts the controller
  - `false` stops the controller
  - omitted: flips the current state

**Examples**

```lua
controller:Toggle()
controller:Toggle(true)
controller:Toggle(false)
```

---

### `:Restart()`

Stops and starts again.

Useful after changing settings that affect runtime behavior.

---

### `:Destroy()`

Fully tears down the controller.

**Notes**

- stops the controller
- marks the instance as destroyed
- disconnects input bindings
- unbinds the mobile action
- removes the global terminate hook used by the module

After `Destroy()`, the instance should not be reused.

---

## Settings methods

### `:Set(key, value)`

Updates a setting and restarts the controller if the value changed.

**Parameters**

- `key` — setting name
- `value` — new setting value

**Example**

```lua
controller:Set("LIMB_SIZE", 22)
controller:Set("TARGET_LIMB", "HumanoidRootPart")
```

---

### `:Get(key)`

Returns the current value of a setting.

**Example**

```lua
local size = controller:Get("LIMB_SIZE")
```

---

## NPC directory methods

### `:SetDirectories(dirs)`

Replaces the current NPC directory list.

**Parameters**

- `dirs` — table of strings and/or live Instances

**Behavior**

- invalid entries are ignored
- if the resulting list is empty, NPC directories are cleared
- restarts the controller afterward

---

### `:AddDirectory(dir)`

Adds a single directory if it is valid and not already present.

**Parameters**

- `dir` — string path or live Instance

**Behavior**

- ignores duplicates
- restarts the controller afterward

---

### `:RemoveDirectory(dir)`

Removes a directory from the list.

**Parameters**

- `dir` — string path or live Instance

**Behavior**

- restarts the controller if a directory was removed
- clears NPC directories if the list becomes empty

---

### `:GetDirectories()`

Returns a copy of the current directory list.

**Return value**

- a table of directories

**Notes**

- if no custom directories are configured, this returns `{ Workspace }`

---

## Runtime behavior

### Player handling

When `PLAYER_ENABLED` is `true`, the controller tracks other players and applies the limb modification to matching characters.

It will skip a player if:

- the player is the local player
- `TEAM_CHECK` is enabled and the player is on the same team
- the character is missing a Humanoid
- the target limb is not present
- a `ForceField` is present and `FORCEFIELD_CHECK` is enabled

### NPC handling

When `NPC_ENABLED` is `true`, the controller scans the configured NPC directories and watches them for new descendants.

A model is treated as an NPC if:

- it is a `Model`
- it contains a `Humanoid`
- it is not already recognized as a player character
- `NPC_FILTER`, if provided, returns `true`

### Limb scaling

The module saves the original part data before modifying anything.

For the active limb it stores:

- size
- transparency
- collision state
- massless state
- mass
- physical properties
- root priority
- character extents

Then it applies the configured size and visibility options.

### Special handling for `HumanoidRootPart`

The root part gets special treatment so its physical properties stay more consistent after resizing.

Other limbs are made:

- `Massless = true`
- `RootPriority = -127`

### Restoration

When a controller stops, is destroyed, or a tracked character leaves the game, the original values are restored where possible.

---

## Input behavior

If input listening is enabled, the controller will:

- bind the toggle key from `TOGGLE`
- use a mobile action button if the runtime supports it
- fall back to `UserInputService.InputBegan` if the mobile helper is unavailable

---

## Example: player-only setup

```lua
local LimbExtender = loadstring(game:HttpGet("https://raw.githubusercontent.com/AAPVdev/scripts/refs/heads/main/LimbExtender.lua")()

local controller = LimbExtender.new({
    PLAYER_ENABLED = true,
    NPC_ENABLED = false,
    TARGET_LIMB = "Head",
    LIMB_SIZE = 16,
    TOGGLE = "G",
})
controller:Start()
```

---

## Example: NPC-only setup

```lua
local LimbExtender = loadstring(game:HttpGet("https://raw.githubusercontent.com/AAPVdev/scripts/refs/heads/main/LimbExtender.lua")()

local controller = LimbExtender.new({
    PLAYER_ENABLED = false,
    NPC_ENABLED = true,
    NPC_DIRECTORIES = {
        workspace.Misc.AI,
        "Workspace.Enemies",
    },
    NPC_FILTER = function(model)
        return model.Name ~= "Dummy"
    end,
})
controller:Start()
```

---

## Example: changing settings at runtime

```lua
controller:Set("LIMB_TRANSPARENCY", 0.35)
controller:Set("LIMB_SIZE", 24)
controller:Set("RESET_LIMB_ON_DEATH", true)
```

Changing a setting automatically restarts the controller when needed.

---

## Implementation notes

- The module uses a shared global cache so repeated constructions can reuse state.
- Connections are managed through an internal `ConnectionManager`.
- Directory strings are normalized and resolved asynchronously.
- NPC directory watching is live, so new models added later are handled automatically.
- Some runtime behavior relies on low-level metamethod hooks when the environment supports them.

---

## Practical caveats

- If the target limb name does not exist, nothing is modified.
- If the character is protected by a force field, processing may be delayed.
- If `PLAYER_ENABLED` is `false`, player characters are ignored entirely.
- If `NPC_ENABLED` is `false`, directory scanning does nothing.
- The module is stateful; creating multiple instances in the same session shares some global runtime data.

---

## Minimal example

```lua
local LimbExtender = loadstring(game:HttpGet("https://raw.githubusercontent.com/AAPVdev/scripts/refs/heads/main/LimbExtender.lua")()

local controller = LimbExtender.new({
    PLAYER_ENABLED = true,
    NPC_ENABLED = true,
})

-- later
controller:Toggle()
controller:Destroy()
```

---

## API summary

```lua
local controller = LimbExtender.new(settings)

controller:Start()
controller:Stop()
controller:Toggle([state])
controller:Restart()
controller:Set(key, value)
controller:Get(key)
controller:SetDirectories(dirs)
controller:AddDirectory(dir)
controller:RemoveDirectory(dir)
controller:GetDirectories()
controller:Destroy()
```
