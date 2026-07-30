---
name: ue-stats-attributes
description: Find and modify health, mana, and other GAS (Gameplay Ability System) attribute values in UE games via remote CE.
---

# UE Stats & Attributes

Use this skill to find and modify character stats (HP, mana, etc.) via UE's Gameplay Ability System.

## Architecture

```
Character → CharState (+0x938) → AbilitySystemComponent, ASC (+0x378)
  → SpawnedAttributes TArray (+0x1090)
    [0] AttributeSet_Health    (+0x40: Health, +0x50: MaxHealth)
    [1] AttributeSet_Armor
    [3] AttributeSet_Mana      (+0x40: Mana, +0x50: MaxMana)
    ...
```

## FGameplayAttributeData Layout (CRITICAL)

Each attribute field has an 8-byte descriptor header, then:

```
+0x00: int64 descriptor pointer (8 bytes) — static address in module
+0x08: float CurrentValue  (4 bytes)  ← IMPORTANT: stored FIRST
+0x0C: float BaseValue     (4 bytes)
```

**CurrentValue is before BaseValue**, opposite of C++ struct declaration order.

## Reading Health/Mana

```lua
local ch = UEngine_findCharacter()
local cs = readQword(ch + 0x938)       -- CharState
local asc = readQword(cs + 0x378)      -- AbilitySystemComponent
local arrPtr = readQword(asc + 0x1090) -- SpawnedAttributes array
local arrCount = readInteger(asc + 0x1098)

-- Health = SpawnedAttributes[0]
local healthSet = readQword(arrPtr + 0 * 8)
local health = readFloat(healthSet + 0x40 + 0x08)  -- Health.CurrentValue
local maxHp = readFloat(healthSet + 0x50 + 0x08)   -- MaxHealth.CurrentValue

-- Mana = SpawnedAttributes[3]
local manaSet = readQword(arrPtr + 3 * 8)
local mana = readFloat(manaSet + 0x40 + 0x08)
local maxMana = readFloat(manaSet + 0x50 + 0x08)
```

## Writing (Healing)

Write to CurrentValue (+header offset +0x08), NOT BaseValue (+0x0C):

```lua
-- Set health to max
writeFloat(healthSet + 0x40 + 0x08, maxHp)
-- Or a specific value:
writeFloat(healthSet + 0x40 + 0x08, 460.0)
```

## Attribute Set Discovery

To find which attribute sets exist and their fields:

```python
lua = """
local ch = UEngine_findCharacter()
local cs = readQword(ch + 0x938)
local asc = readQword(cs + 0x378)
local ptr = readQword(asc + 0x1090)
local cnt = readInteger(asc + 0x1098)
local s = ""
for i = 0, cnt-1 do
  local set = readQword(ptr + i*8)
  local ok, n = pcall(UObject_getName, set)
  if ok then
    s = s .. "[" .. i .. "] " .. n .. " @ 0x" .. string.format("%X", set) .. "\\n"
  end
end
return s
"""
r = ce.cmd('runScript ' + lua.strip())
print(r)
```

## Warning

- The ASC spawns attribute sets lazily. All 14 sets were present in G1R, but counts vary per game.
- The `SpawnedAttributes` array offset (+0x1090) varies per UE version. Search for arrays of UObject pointers with vtable+0x10 → class name containing "AttributeSet".
- Always verify by reading the class name of each set to know which is which.
- `realloc` can move the SpawnedAttributes array pointer. Re-read it if the game loads new levels.
