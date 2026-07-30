---
name: ue-character-finding
description: Find the player character object in any Unreal Engine game via remote CE, using either CE75 helpers or manual GEngine chain walking.
---

# UE Character Finding

Use this skill when you need to locate the player character/pawn in a UE game.

## Prerequisites

- CE attached to game process
- `ce_server.lua` running
- `windows_relay.py` running
- Client connected

## Method 1: UEngine_findCharacter() (CE75 loaded)

If CE75.LUA is loaded in CE, this one-liner works:

```python
import sys
sys.path.insert(0, '/path/to/remote')
from client import CERemote
ce = CERemote("host", 8000, 60)
r = ce.cmd('runScript return UEngine_findCharacter()')
print(r)  # decimal address, convert with hex(int(r))
```

## Method 2: Manual GEngine chain (no CE75)

When CE75 is not available, walk the chain manually:

```python
lua = """
local ge = getAddressSafe("GEngine")
local gi = readQword(ge + 0x30)  -- GameInstance offset may vary
local lpArr = readQword(gi + 0x38)  -- LocalPlayers TArray ptr
local lp = readQword(lpArr)  -- LocalPlayers[0]
local pc = readQword(lp + 0x10)  -- PlayerController
local ch = readQword(pc + 0x2F0)  -- Character/Pawn
return string.format("%X", ch)
"""
r = ce.cmd('runScript ' + lua.strip())
```

**Critical:** Offsets for GI, LP, PC, Character vary per UE version and per game. When in doubt:
1. Dump class properties: `runScript return UEngine_getAllProperties(readQword(addr + 0x10))`
2. Look for known property names: `GameInstance`, `LocalPlayers`, `PlayerController`, `Character`, `Pawn`
3. Check inherited properties (walk `SuperStruct` chain)

## Method 3: Dump all sub-components

Once you have the Character address, dump component classes to find inventory/stats holders:

```lua
local ch = UEngine_findCharacter()
local s = ""
for off = 0x790, 0x950, 0x8 do
  local obj = readQword(ch + off)
  if obj and obj > 0x10000 then
    local cls = readQword(obj + 0x10)
    local ok, cn = pcall(UObject_getName, cls)
    if ok then s = s .. string.format("  +0x%03X: %s\\n", off, cn) end
  end
end
return s
```

Common component offsets in G1R (UE5):
| +0x7B0 | CarryComponent (inventory) |
| +0x798 | HealthBarComponent |
| +0x808 | BloodComponent |
| +0x840 | DataModule_BaseStats (→ CharacterDefinition) |
| +0x938 | CharState (→ AbilitySystemComponent +0x378) |
