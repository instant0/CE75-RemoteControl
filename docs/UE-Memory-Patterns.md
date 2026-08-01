# Unreal Engine Memory Layout — Broad Patterns

> **Scope: UE5 patterns (research base: Gothic 1 Remake).**  
> Not applicable as a default map for Dying Light 2 (Techland `gamedll`/`engine`). DL2: [game/DyingLight2/INDEX.md](game/DyingLight2/INDEX.md).

A distilled reference of how UE games typically organize character, stats, and inventory data in memory, based on Gothic 1 Remake (UE5) research.

## 1. The Core Chain

Every UE game has an object hierarchy rooted at `GEngine`:

```
GEngine (singleton, registered as CE symbol)
  → GameInstance (persistent across levels)
    → LocalPlayers (TArray)
      [0] → LocalPlayer
        → PlayerController (owns input, camera, HUD)
          → Character / Pawn (the player-controlled actor)
```

**How to find Character:**
- With CE75 loaded: `UEngine_findCharacter()`
- Manually: `readQword(GEngine + GameInstanceOffset + LocalPlayersOffset + 0 + PlayerControllerOffset + CharacterOffset)`
- Offsets vary per UE version. UE5 G1R: GI +0x30, LP TArray +0x38, PC +0x10, Character +0x2F0

## 2. Sub-Components

The Character object has dozens of sub-components at offsets +0x700 through +0xA00. Each is a `UObject*` (TObjectPtr) pointing to a component. The typical layout:

```
Character
  +0x7B0: CarryComponent / InventoryComponent (inventory holder)
  +0x798: HealthBarComponent / StatusComponent
  +0x808: BloodComponent / DamageComponent
  +0x840: DataModule_BaseStats / AttributeComponent
  +0x938: CharState / CharacterState (often has AbilitySystemComponent)
```

**Discovery command:**
```lua
local ch = UEngine_findCharacter()
for off = 0x780, 0x960, 0x8 do
  local obj = readQword(ch + off)
  if obj and obj > 0x10000 then
    local cls = readQword(obj + 0x10)
    local ok, n = pcall(UObject_getName, cls)
    if ok then print(string.format("+0x%03X → %s", off, n)) end
  end
end
```

## 3. Gameplay Ability System (Stats)

GAS is UE's primary stats system. The layout:

```
CharacterState (e.g., CharState_C)
  +0x378: AbilitySystemComponent (ASC)
    +0x1090: SpawnedAttributes (TArray<UAttributeSet*>)
```

Each **AttributeSet** is a UObject subclass containing `FGameplayAttributeData` struct properties:

```
AttributeSet_Health:
  +0x40: Health       (FGameplayAttributeData)
  +0x50: MaxHealth    (FGameplayAttributeData)
  +0x60: DamageMultiplier
  +0x70: RecoveryRate

FGameplayAttributeData:
  +0x00: int64 Descriptor (static module address)
  +0x08: float CurrentValue  ← FIRST (NOT BaseValue!)
  +0x0C: float BaseValue
```

**G1R attribute sets discovered:**
[0] Health, [1] Armor, [2] LevelProgression, [3] Mana, [4] Movement,
[5] Dexterity, [6] Strength, [7] Oxygen, [8] Sleep, [9] Fatigue,
[10] Lockpicking, [11] Pickpocketing, [12] Alcohol, [13] Swampweed

## 4. Inventory System

### Component Chain

```
Character → CarryComponent
  → DataModule_Container (or InventoryManager)
    → InventoryManager / Item Array
```

### Entry Layout (G1R specifics)

The inventory is stored as a dense array of 0xB8-byte entries:

```
ArrayBase (+0x378):
  +0x378: ptr to entries
  +0x37C: count of entries

Each entry (0xB8 bytes):
  +0x00: metadata qword (sequential index)
  +0x08: item UObject pointer (name via UObject_getName)
  +0x10: item count (int32, lower 32 bits of qword)
  +0x14: item type hash (upper 32 bits)
  +0x18+: zeros/unused
```

### Finding Items

Items are identified by their UObject Name. Common prefixes in G1R:
- `ItMi_` — Misc items (Orenugget, Oldcoin, Smith_Iron...)
- `ItAm_` — Ammo (Arrow, Bolt)
- `ItFo_` — Food/plants
- `ItMw_` — Weapons (melee)
- `ItRw_` — Ranged weapons (bow)
- `ItAr_` — Armor/scrolls/runes
- `ItAt_` — Accessories/trophies
- `ItKe_` — Keys/quest items

## 5. UObject Memory Layout

Every UE object (4-byte aligned, typically 64-bit pointers):

```
+0x00: vtable pointer (in module range, e.g., 0x7FF6XXXXXXXX)
+0x08: ObjectFlags (bitmask: RF_ marked)
+0x10: ClassPrivate → UClass pointer
+0x18: NameIndex (int32, index into FName pool)
+0x1C: NameNumber (int32)
+0x20: Outer → Outer UObject
+0x28+: Class-specific data
```

**Verification:** An address is a UObject if `readQword(addr)` is in the module range AND `readQword(addr + 0x10)` is non-null.

**Getting the name:**
- With CE75: `UObject_getName(ptr)` → string like `"ItMi_Orenugget"`
- Manual: `UEngine_resolveFName(readInteger(ptr + 0x18))` → full name

## 6. TArray (Dynamic Array) Layout

```
+0x00: ptr to elements (allocated on heap)
+0x08: count (int32)
+0x0C: max  (int32)
```

If at the end of an object (inline storage), allocator may skip the pointer and store inline. Always check: if ptr is in the game's object range (0x20XXXXXXXXXX) and count is sensible, it's heap-allocated.

## 7. General Approach to Unknown Games

1. **Find GEngine** — symbol or scan for pointer-to-self pattern
2. **Walk to Character** — via GI → LP → PC → Character
3. **Dump Character's sub-components** — look for `CarryComponent`, `AttributeSet`, `Inventory`, `AbilitySystem`
4. **Find stats** — walk CharacterState → ASC → SpawnedAttributes
5. **Find inventory** — walk CarryComponent → DataModule_Container → InventoryManager → Array
6. **Verify** — read known item/stat values and cross-reference with in-game display

## 8. Value Scanning Limits

AOBScan in CE's background thread:
- Full-process only (range params ignored in many CE versions)
- Small values (< 65536) produce thousands of false hits
- Float scanning more selective for large numbers
- int64 scanning much more selective than int32
- Pointer scanning requires a known address to scan from
- Delta scans (changed/unchanged) require game interaction

## 9. Known Limitations

- TMap/TSet layouts vary per UE version and are hard to parse from raw memory
- Some inventory data uses serialized/packed formats not directly readable
- Some items are created lazily (nil pointers until first inventory open)
- `realloc` invalidates cached array pointers on level transitions
- Plugin-specific functions (G1R plugin) must be loaded to access advanced CE75 helpers
