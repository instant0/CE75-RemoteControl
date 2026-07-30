---
name: ue-inventory-hacking
description: Find and modify inventory items (item counts, add/remove items) in UE games via remote CE, by navigating the inventory manager chain.
---

# UE Inventory Hacking

Use this skill to read and modify player inventory in UE games.

## Architecture (G1R Pattern)

```
Character
  +0x7B0 → CarryComponent (m_CarryComponent)
    +0x170 → DataModule_Container (m_DataModule_Container)
      +0x168 → InventoryManager
        +0x378 → ArrayBase (ptr at +0x378, count at +0x37C)
```

**Each entry is 0xB8 (184) bytes**, with this layout:

| Offset | Size | Field |
|--------|------|-------|
| +0x00  | 8    | Metadata / sequential index |
| +0x08  | 8    | **Pointer to item UObject** (use `UObject_getName` to identify) |
| +0x10  | 4    | **Item count** (lower 32 bits of qword) |
| +0x14  | 4    | Item type ID / hash (upper 32 bits — preserve when writing) |
| +0x18  | 8+   | Unused/zero in simple items |

## Finding the Inventory Chain

```python
import sys
sys.path.insert(0, '/path/to/remote')
from client import CERemote
ce = CERemote("host", 8000, 60)

lua = """
local ch = UEngine_findCharacter()
local carry = readQword(ch + 0x7B0)
local container = readQword(carry + 0x170)
local invMan = readQword(container + 0x168)

-- Verify by reading class names
local function name(ptr)
  local ok, n = pcall(UObject_getName, ptr)
  return ok and n or "nil"
end

local s = "Carry: " .. name(carry)
s = s .. "\\nContainer: " .. name(container)
s = s .. "\\nInvMan: " .. name(invMan)

local arrPtr = readQword(invMan + 0x378)
local arrCount = readInteger(invMan + 0x37C)
s = s .. "\\nArray: ptr=0x" .. string.format("%X", arrPtr or 0) .. " count=" .. (arrCount or 0)
return s
"""
r = ce.cmd('runScript ' + lua.strip())
print(r)
```

## Dumping All Items

```python
lua = """
local ch = UEngine_findCharacter()
local invMan = readQword(readQword(readQword(ch + 0x7B0) + 0x170) + 0x168)
local arrPtr = readQword(invMan + 0x378)
local arrCount = readInteger(invMan + 0x37C)

local s = ""
for i = 0, math.min(arrCount - 1, 200) do
  local base = arrPtr + i * 0xB8
  local itemPtr = readQword(base + 0x08)
  local count = (readQword(base + 0x10) or 0) % 0x100000000

  local name = "nil"
  if itemPtr and itemPtr > 0x10000 then
    local ok, n = pcall(UObject_getName, itemPtr)
    if ok then name = n end
  end

  if name ~= "nil" or count > 0 then
    s = s .. string.format("[%d] %s x%d\\n", i, name, count)
  end
end
return s
"""
r = ce.cmd('runScript ' + lua.strip())
print(r)
```

## Modifying an Item Count

```lua
-- Entry[N] at array, set count to newCount
local q = readQword(arrPtr + N * 0xB8 + 0x10)
local itemId = math.floor(q / 0x100000000)  -- preserve upper 32 bits
writeQword(arrPtr + N * 0xB8 + 0x10, itemId * 0x100000000 + newCount)
```

## Searching for a Specific Item

Search by name substring:

```python
lua = """
... (same chain as above) ...
local s = ""
for i = 0, arrCount - 1 do
  local base = arrPtr + i * 0xB8
  local itemPtr = readQword(base + 0x08)
  local count = (readQword(base + 0x10) or 0) % 0x100000000
  local name = "nil"
  if itemPtr and itemPtr > 0x10000 then
    local ok, n = pcall(UObject_getName, itemPtr)
    if ok then name = n end
  end
  if string.find(name, "Arrow") then
    s = s .. string.format("[%d] %s x%d\\n", i, name, count)
  end
end
return s
"""
```

## Security / Unknown Chains

When the offsets above don't match your target:

1. **Find Character** (use `ue-character-finding` skill)
2. **Dump sub-components at +0x780 to +0x950**, look for names containing: `Carry`, `Container`, `Inventory`, `Pouch`, `Backpack`, `Storage`
3. For each candidate component, walk its object references at round offsets (+0x160, +0x168, +0x170, +0x178)
4. Read class names of referenced objects to find data modules/managers
5. Look for TArray-style structures: a 16-byte region with a large-ish pointer and a sensible count (e.g., ptr in 0x20XXXXXXXXXX range, count < 10000)
6. Verify by reading item UObject names from the array

## Game-Specific Knowledge

### Gothic 1 Remake (UE5)
- Component names: `CarryComponent_C`, `DataModule_Container_C`, `InventoryManager_C`
- Item naming: `ItMi_` (misc), `ItAm_` (ammo), `ItAr_` (armor/scrolls), `ItFo_` (food), `ItMw_` (weapons)
- Array stride: 0xB8, count offset: +0x10 within entry
- 524 array slots total (many nil/unused at end)
