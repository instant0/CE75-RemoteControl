# Dying Light 2 — extract from host notes (`/mnt/r`)

**Date re-mined:** 2026-08-01  
**Sources:** `DyingLight2-*.txt` / `*.notes.txt`, `d2-tablecheatvariables.lua`, `dl2_arrayscan_1.14.txt`, shop/tooltip CEA, PDB/DLL strings.  
**Not in repo:** raw host files stay on `/mnt/r` only.

These notes are **historical (mostly 2022–2023 builds)**. Offsets for inventory graph and LifeHealth fields have been **stable enough** across several versions in the author’s notes; always re-validate on the current attach.

---

## 1. Three different “player value” systems

| System | What it is | Live HP? | Live cash? |
|--------|------------|----------|------------|
| **A. `playerStat` / FloatPlayerVariable** | Config / balancing floats (MaxHealth, stamina, buy/sell factors) | **No** (MaxHealth config only) | **No** (pricing factors only) |
| **B. `PlayerHealthModule` → `LifeHealth`** | Runtime combat health | **Yes** | No |
| **C. `InventoryMoney` / inventory graph** | Currency + bags | No | **Yes** (int @ +0x38) |

Cheating “health” and “money” means **B** and **C**, not only retuning (A).

---

## 2. Money (old-world cash)

### Canonical field (confirmed many builds)

| Object | Offset | Type | Role |
|--------|--------|------|------|
| **`InventoryMoney`** | **`+0x38`** | int32 | **Cash amount** |
| InventoryMoney | `+0x18` | ptr | → **`PlayerDI_PH`** |
| InventoryMoney | `+0x80` | ptr | → **InventoryMain** |
| InventoryMoney | `+0x10` | ptr | → InventoryContainerDI (also noted) |

### Code that reads it constantly (vendor / UI)

From 1.83 / 1.90 notes (RCX = InventoryMoney):

```text
mov edx, [rcx+38]     ; 8B 51 38
jmp qword ptr [rax+D8]
…
mov eax, [rcx+38]     ; 8B 41 38
```

**Discovery signal:** “what accesses” your cash integer → prefer hits that are **`[reg+38]`** with **`this` looking like InventoryMoney** (backlink +0x18 to PlayerDI).

Write/spend path also uses `[reg+38]` (sub / mov store) — 1.83 notes.

### Inventory container map (under player)

**1.11.4** (debug / PlayerDI context):

```text
PlayerDI_PH + 0x560  →  InventoryContainerDI
  +0x38  InventoryMoney      ← money object (then Money @ object+0x38)
  +0x40  InventoryAmmo
  +0x48  InventoryCollectable
  +0x50  InventoryLooseItems
  +0x58  InventoryMain
  +0x60  InventoryItems
  +0x68  InventorySpecial
  +0x78  InventoryToken
```

**1.83 / 1.90** list the same **container field offsets** relative to `InventoryContainerDI` (Money/Ammo/…/Token).  
So path:

```text
PlayerDI_PH
  → +0x560 InventoryContainerDI   [validate per build]
    → +0x38 InventoryMoney*
      → +0x38 int cash
```

\*If `+0x560` drifts, still true: once you have **InventoryMoney\***, cash is **`+0x38`**.

### Item counts (not cash)

- **InventoryItem +0x10** = stack count (coins-as-item, trophies, craft mats) — used in crafting UI; **different** from InventoryMoney+0x38 cash pool.
- Tooltip/shop CEA (1.14): cost/compare AOBs on shop controller — **costs**, not wallet balance.

### Vendor resource currencies (re-confirmed 2026-08-02)

Vendor UI shows **cash** plus several **resource** amounts (e.g. 0, 1506, 1146, 1203, 82283) used to buy/upgrade. Those resources are **inventory stacks**, not `InventoryMoney+0x38`.

- **Field:** still **`+0x10`** on the stack object (access log: many `mov`/`cmp`/`add` with **`[reg+10]`**; upgrade path included).
- **How to find a live stack:** distinctive dword (high unique count) → spend → next scan decreased-by-N → one address → what-accesses. Do **not** full-process AOB common small counts.
- Live graph / RVAs: `private/DyingLight2/structures/INVENTORY-GRAPH-LIVE.md`.

### Access-log filters (money)

When “find what accesses” on cash (4-byte):

| Clue from notes | Meaning |
|-----------------|--------|
| RCX/RAX type **InventoryMoney** | Correct object |
| **R10 = 3** on some multi-value readers (1.90) | Author used as filter for money vs other currencies |
| RSI / R8 = **PlayerDI_PH** on related frames | Confirms local player inventory graph |

---

## 3. Health (current HP)

### Canonical fields (1.92 / 1.93.dmg — strongest)

| Object | Offset | Role |
|--------|--------|------|
| **`lifecs::PrivHealth::LifeHealth<HealthFactors>`** | **`+0x1C`** | **Real / current HP** (float) |
| same | **`+0x2C`, `+0x30`, `+0x34`** | Max HP (multiple copies / layers in CT + notes) |

### Module relationship (register dumps)

On player HP access frames:

| Reg | Type |
|-----|------|
| **RSI** | `PlayerHealthModule` |
| **RBX / R12 / R15** | `LifeHealth<…>` |
| **RBP** | `LifeCalculator::HealthContainer<…>` |

Observed spacing (1.11 / 1.92 samples):  
`LifeHealth ≈ PlayerHealthModule + 0x48` (e.g. `…B890` module → `…B8D8` LifeHealth).  
CT template also listed **`PlayerHealthModule+0x88`** → LifeHealth — **re-check both** on current build; prefer **RTTI name on the pointer** over a single offset.

### Damage write site (1.93.dmg)

Anonymous gamedll helper writing several floats:

```text
movss [rcx+0C], xmm1
movss [rcx+08], xmm1
movss [rcx+04], xmm1    ← often near “HP-ish” blob
ret
```

On enemy/player damage, **R12** frequently = **LifeHealth**; xmm0/1 = current HP, xmm6 = damage, xmm7 = prev/max depending on path.

**Player vs enemy:** same LifeHealth type; distinguish by:

- Taking intentional fall damage and watching **your** HUD number  
- Or walking back to **PlayerHealthModule** / **PlayerDI** from the object  
- Notes: fire damage set R10/R13/R14 patterns — optional filters only

### Config vs live (do not mix)

| Want | Location |
|------|----------|
| **HUD / combat current HP** | LifeHealth **+0x1C** |
| **MaxHealth balance default** | `playerStat + 0x3438` (FloatPlayerVariable) after bootstrap |

---

## 4. How author found PlayerDI / PlayerVariables

| Method | Evidence |
|--------|----------|
| **Invisible debug script** | 1.11.4: RAX=`FloatPlayerVariable`, RBX/RCX=`PlayerDI_PH` |
| **ItemDescWithContext** | 1.10.2: `RDI+0x130` → PlayerDI_PH |
| **InventoryMoney+0x18** | Always back to PlayerDI_PH in money notes |
| **PlayerState +0xE8** | `d2-tablecheatvariables.lua` builds rows: `playerState` → offset `0xE8` → PlayerVars / FPV |
| **Engine** | `IGame::GetLocalPlayerEntity`, `ILevel::GetIPlayerManager` (`DyingLight2-notes.txt`, engine strings) |

---

## 5. PlayerVars / structure generators (host scripts)

| File | Role |
|------|------|
| `dl2_arrayscan_1.14.txt` | AOB `C7 44 24 20 00 00 00 00 4C 8D 4C 24 20` → build named offset struct |
| `d2-tablecheatvariables.lua` | Older AOB; also shows **playerState+0xE8** and **+0x278** pointer styles historically |
| `dl2-scan.txt` | Older PlayerVars AOB variants |

These rebuild **names for (A)** config blob — **not** live HP/money bases.

---

## 6. Engine / PDB name anchors (still valid as search keys)

**Engine (strings in `engine_x64_rwdi.dll`):**

- `GetLocalPlayerEntity`
- `GetLocalPlayerId`
- `IPlayerManager`

**Gamedll / PDB:**

- `PlayerHealthModule`, `InventoryMoney`, `LifeHealth`, `PlayerDI_PH`, `PlayerState`
- `PlayerHealthModule::SetHealth`, `UpdateHealth`, `ReduceHealth`, `RestoreHealth`, …
- GUI: `money_icon`, `Cash_Cash`, `EGuiCurrencyType`
- Edit descriptor: `Current player health (0.0 - MaxHealth)`

---

## 7. Shop / tooltip CEA (1.14) — secondary

| Script | Use |
|--------|-----|
| ShopController AOB `… 39 83 40 01 00 00` | Shop object `+0x140` compare — **UI/shop state**, not wallet |
| Tooltip `mov eax,[rcx+130]` | Related shop/tooltip field |

Useful if shopping UI is open; **not** the primary wallet path.

---

## Change log

| Date | Note |
|------|------|
| 2026-08-01 | Re-mined `/mnt/r` notes into extracted KB; money +0x38, LifeHealth +0x1C, PlayerDI+0x560 inventory map, engine GetLocalPlayer* |
