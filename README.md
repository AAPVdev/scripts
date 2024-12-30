# 📜 Scripts  

## 🔹 Limb Extender (NO UI)  
Extend limbs without any graphical interface.  
```lua
local Settings = {
		TOGGLE = "K",
		TARGET_LIMB = "Head",
		LIMB_SIZE = 5,
		LIMB_TRANSPARENCY = 0.9,
		LIMB_CAN_COLLIDE = false,
		TEAM_CHECK = false,
		FORCEFIELD_CHECK = true,
		RESTORE_ORIGINAL_LIMB_ON_DEATH = false,
		ESP = false,
		USE_HIGHLIGHT = true,
		DEPTH_MODE = 2,
		HIGHLIGHT_FILL_COLOR = Color3.fromRGB(0, 255, 0),
		HIGHLIGHT_FILL_TRANSPARENCY = 0.5,
		HIGHLIGHT_OUTLINE_COLOR = Color3.fromRGB(255, 255, 255),
		HIGHLIGHT_OUTLINE_TRANSPARENCY = 0,
	}
local LimbExtender = loadstring(game:HttpGet('https://raw.githubusercontent.com/AAPVdev/scripts/refs/heads/main/LimbExtender.lua'))()
```

---

## 🔹 Limb Extender (WITH UI)  
Extend limbs with a user-friendly graphical interface.  
```lua
loadstring(game:HttpGet('https://raw.githubusercontent.com/AAPVdev/scripts/refs/heads/main/UI_LimbExtender.lua'))()
```
