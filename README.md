# 📜 Scripts  

## 🔹 Limb Extender (NO UI)  
I would really only use this if rayfield gets detected. Not recommended for normal use.
```lua
getgenv().le = getgenv().le or loadstring(game.ReplicatedStorage:WaitForChild("RobustLimbExtender"))()

getgenv().le({
	TOGGLE = "L",
	TARGET_LIMB = "HumanoidRootPart",
	LIMB_SIZE = 15,
	LIMB_TRANSPARENCY = 0.9,
	LIMB_CAN_COLLIDE = false,
	MOBILE_BUTTON = true,
	LISTEN_FOR_INPUT = true,
	TEAM_CHECK = true,
	FORCEFIELD_CHECK = true,
	RESET_LIMB_ON_DEATH2 = false,
	USE_HIGHLIGHT = true,
	DEPTH_MODE = "AlwaysOnTop",
	HIGHLIGHT_FILL_COLOR = Color3.fromRGB(0,140,140),
	HIGHLIGHT_FILL_TRANSPARENCY = 0.7,
	HIGHLIGHT_OUTLINE_COLOR = Color3.fromRGB(255,255,255),
	HIGHLIGHT_OUTLINE_TRANSPARENCY = 1,
})

```

---

## 🔹 Limb Extender (WITH UI)  
Strongly reccomend you use this one.  
```lua
loadstring(game:HttpGet('https://raw.githubusercontent.com/AAPVdev/scripts/refs/heads/main/UI_LimbExtender.lua'))()
```
