# Dying Light 2 — Character entry points: HP & money

**Status:** CT dissect + PDB/DLL names + **re-mined host notes** (`/mnt/r`, 2026-08-01).  
**Not yet on current attach:** proven live base for LifeHealth / InventoryMoney (need Phase 1–2 in strategy doc).

**Related:** [FIND-LIVE-HEALTH-MONEY.md](FIND-LIVE-HEALTH-MONEY.md) (how to find them), [host-notes-extract.md](host-notes-extract.md), `player-vars-array.md`, `player-variables.md`, `function-catalog.md`

---

## Host-note corrections / additions (2026-08-01)

| Finding | Detail |
|---------|--------|
| Money reader | `mov r32,[rcx+38]` with RCX=`InventoryMoney` (1.83/1.90); jmp `[rax+D8]` nearby |
| Inventory map | `PlayerDI_PH+0x560` → container; container `+38` Money … `+78` Token (1.11.4) |
| LifeHealth vs module | Live dumps often show LifeHealth ≈ **PlayerHealthModule+0x48** (also try CT **+0x88**) |
| PlayerDI from money | `InventoryMoney+0x18` → PlayerDI_PH |
| Engine entry | `IGame::GetLocalPlayerEntity`, `ILevel::GetIPlayerManager` |

---

## Short answers

| Want | Where it lives | How to get there |
|------|----------------|------------------|
| **Config “MaxHealth”** (default/cap parameters) | `FloatPlayerVariable` / live **`playerStat + 0x3438`** | PlayerVars dissect + playerStat bootstrap |
| **Current hit points (Real HP)** | **`lifecs::PrivHealth::LifeHealth` + 0x1C** | Via **`PlayerHealthModule`** → LifeHealth ptrs, or entity chain |
| **Max HP (runtime)** | LifeHealth **+0x2C / +0x30 / +0x34** (labeled Max HP in CT dump) | Same module |
| **Money (old-world cash amount)** | **`InventoryMoney` + 0x38** field **Money** | Inventory / PlayerDI chain — not the playerStat float blob |
| **Shop pricing** | `playerStat + 0x2E78` BuyFactor, `+ 0x2E90` SellFactor | Already in CT under Money group |

“Old world money” in DL2 is inventory **currency** (`InventoryMoney`, `EGuiCurrencyType`, GUI `money_icon` / `&Cash_Cash_N&`), not a `FloatPlayerVariable` named OldWorldMoney in the dumps we searched.

---

## Architecture (character-related)

```text
PlayerDI_PH                          [dissect in CT]
├── … components …
├── → PlayerHealthModule             [dissect]
│     +0x08  → PlayerDI_PH
│     +0x88  → LifeHealth<HealthFactors>   (and more LifeHealth ptrs @ +178,+268,+358)
│              +0x1C  Real HP          ← current hit points (CT label)
│              +0x2C  Max HP
│              +0x30  Max HP
│              +0x34  Max HP
│              +0x08 / +0x18  type markers (A0000 player/mob notes in CT)
│
├── → Inventory* / InventoryMoney    [dissect InventoryMoney]
│              +0x10  → InventoryContainerDI
│              +0x18  → PlayerDI_PH
│              +0x38  Money            ← currency amount (CT label)
│              +0x80  → InventoryMain
│
PlayerState
└── +0xE8 → FloatPlayerVariable      (config/defaults blob type)

PlayerVariables (dataset / constds)   [PDB]
├── FloatPlayerVariable              ← huge named offset map (PlayerVarsArray gen)
├── BoolPlayerVariable
├── StringPlayerVariable
└── HealthPlayerVariable<HealthFactors>

HumanHealthModule / BaseHealthModule / CoHealth / BeastHealthModule / CreatureHealthModule  [PDB]
SetPlayerHealthLogic / PlayerHealthWaitLogic   [story/script]
```

### PDB / DLL name anchors (investigation)

| Name | Source | Use |
|------|--------|-----|
| `PlayerVariables`, `FloatPlayerVariable`, `HealthPlayerVariable` | PDB + gamedll RTTI strings | Config vars system |
| `m_MaxHealth`, `m_AbsoluteMaxHealth`, `m_BonusMaxHealth`, `m_LockedMaxHealthPercent` | 2026 gamedll strings | Runtime health fields (module/replication) |
| `f:EDIT;c:Health;d:Current player health (0.0 - MaxHealth)` | gamedll | Confirms editable current HP concept |
| `Initialization of MaxHealth in PlayerHealthModule` | gamedll | Ties MaxHealth init to **PlayerHealthModule** |
| `EGuiCurrencyType`, `GuiCurrencyTooltip`, `InventoryMoney` | PDB / CT | Currency UI + inventory money object |
| `MenuDevPlayerVariables`, `ReloadPlayerVariables` | gamedll | Dev reload path for vars |

---

## FloatPlayerVariable offsets (config — from CT struct 1.82 / 1.90)

Useful health-adjacent **defaults** (not current HP):

| Offset | Name |
|--------|------|
| `0x3438` | **MaxHealth** |
| `0x3408` | LowHealthEffectThreshold (~0.95) |
| `0x29D8`–`0x2A68` | HealthCritical* |
| `0x2A98`–`0x2AD8` | HealthRegeneration* |
| `0x2AC0` | MaxAutoRegenHealthPercent |
| `0x2B8` | AfterDeathHealthFactor |
| `0x2D0` | AfterDeathHealthRegenTime |
| `0x1DA0` | FinisherKnockdownEnemyMaxHealth |

Economy (table already uses):

| Offset | Name | CT use |
|--------|------|--------|
| `0x2E78` | ItemsBuyFactor | cheap buys |
| `0x2E90` | ItemsSellFactor | gold reward |

Require live **`playerStat`** to sample.

---

## What blocks live HP/money reads right now

1. **`playerStat` not registered** — bootstrap id 78 AOB (`1.90` pattern) was already **0 hits** on prior attaches; must retune data AOB (`player-variables` + `ce-aob-scan`).  
2. **No automatic base** for `PlayerHealthModule` / `InventoryMoney` in the address list — only **structure templates**. Need either:
   - pointer path from a known player object (`PlayerDI_PH`, `PlayerState`, GUI data), or  
   - “what accesses / instance” scan once a candidate is found, or  
   - CE structure dissect with a manually set address after finding one instance.  
3. **2022 gamedll PDB** does not give trustworthy RVAs for 2026-06-14 DLLs — names only.

---

## Recommended discovery order (next sessions)

### Path 1 — Config vars + economy (table style)

1. Retune **playerStat** bootstrap (writable AOB / defaults).  
2. Validate `playerStat+3438` (MaxHealth config), stamina defaults, buy/sell factors.  
3. Optionally regenerate **PlayerVarsArray** with 1.14 AOB + fixed parser → new `FloatPlayerVariable YYYYMMDD`.

### Path 2 — Current HP (gameplay)

1. Find **PlayerDI_PH** or **PlayerHealthModule** instance (AOB on module methods, GUI health bar, damage breakpoint, or PDB-guided string → code).  
2. Read `module+0x88` → LifeHealth; sample **+0x1C** while taking damage / healing.  
3. Confirm Max at **+0x2C..+0x34** vs HUD.  
4. Add EXPR/pointer memrecs once base is stable; document chain in this file.

### Path 3 — Money amount

1. Find **InventoryMoney** or **InventoryMain** from player inventory open / buy UI.  
2. Read **`+0x38` Money**; change in-game cash; confirm.  
3. Cross-check with `EGuiCurrencyType` / quartermaster UI if multi-currency.

### Path 4 — Full object dump

1. Prefer **regenerated FloatPlayerVariable** (names+offsets) + live `playerStat` for the **config object**.  
2. For **entity health/inventory**, use CT templates `PlayerHealthModule`, `LifeHealth`, `InventoryMoney`, `PlayerDI_PH` with a **correct base address** — do not expect one `playerStat` pointer to be the whole character.

---

## CT assets already present (structure list)

| Structure | Elems (approx) | Relevance |
|-----------|----------------|-----------|
| FloatPlayerVariable 1.82 / 1.90 | 4k / 20k | Named config offsets |
| PlayerState | 21k | Links toward FPV |
| PlayerHealthModule | 1k | HP module |
| lifecs::PrivHealth::LifeHealth\<HealthFactors\> | 1k | **Real HP / Max HP** |
| InventoryMoney | 644 | **Money @ +0x38** |
| InventoryMain / InventoryItem / Token… | various | Inventory graph |
| PlayerDI_PH / CGuiPlayerData | ~1k | Player / GUI hubs |
| DayNightCycle | 754 | Time (other feature) |

---

## Change log

| Date | Note |
|------|------|
| 2026-08-01 | Mapped HP vs config MaxHealth; InventoryMoney+0x38; FPV offsets; PDB class list; blocked on playerStat + instance bases |
| 2026-08-01 | Host re-mine: strategy doc + host-notes-extract; module+0x48 LifeHealth note; engine GetLocalPlayer* |
