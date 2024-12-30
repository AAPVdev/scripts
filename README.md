# 📜 Scripts  

## 🔹 Limb Extender (NO UI)  
Extend limbs without any graphical interface.  
```lua
local LimbExtender = loadstring(game:HttpGet('https://raw.githubusercontent.com/AAPVdev/scripts/refs/heads/main/LimbExtender.lua'))()

LimbExtender.TOGGLE = "K",
LimbExtender.TARGET_LIMB = "Head",
LimbExtender.LIMB_SIZE = 5,
LimbExtender.LIMB_TRANSPARENCY = 0.9,
LimbExtender.LIMB_CAN_COLLIDE = false,
LimbExtender.TEAM_CHECK = false,
LimbExtender.FORCEFIELD_CHECK = true,
LimbExtender.RESTORE_ORIGINAL_LIMB_ON_DEATH = false,
LimbExtender.ESP = false,
LimbExtender.USE_HIGHLIGHT = true,
LimbExtender.DEPTH_MODE = 2,
LimbExtender.HIGHLIGHT_FILL_COLOR = Color3.fromRGB(0, 255, 0),
LimbExtender.HIGHLIGHT_FILL_TRANSPARENCY = 0.5,
LimbExtender.HIGHLIGHT_OUTLINE_COLOR = Color3.fromRGB(255, 255, 255),
LimbExtender.HIGHLIGHT_OUTLINE_TRANSPARENCY = 0,

```

---

## 🔹 Limb Extender (WITH UI)  
Extend limbs with a user-friendly graphical interface.  
```lua
loadstring(game:HttpGet('https://raw.githubusercontent.com/AAPVdev/scripts/refs/heads/main/UI_LimbExtender.lua'))()
```
