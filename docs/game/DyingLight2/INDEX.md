# Dying Light 2 — knowledge index

**Root:** `docs/game/DyingLight2/`  
**Purpose:** Extracted facts for agents and humans. Not raw CT/scripts for public dump.  
**Start here** for any DL2 table or discovery work.

**Engine model:** Techland modules (`gamedll_ph_x64_rwdi.dll` / `engine_x64_rwdi.dll`) — **not** Unreal GEngine/GAS. Do **not** use `skills/ue-*` as the default path.

**Related tools (skills):** `skills/dl2-table-work` (this game’s work order), `skills/ce-aob-scan`, `skills/ce-remote-scanning`, `skills/ce-table-migrate`, `skills/ce-table-remote`.  
**Group scan language:** [../../CE-GROUP-SCAN.md](../../CE-GROUP-SCAN.md) (research multi-value locate only; prefer typed chains when proved).

**Version tags:** prefer `YYYYMMDD` in CT MEMORY descriptions when re-verified.

---

## Status matrix (read before treating offsets as “live”)

Confidence labels:

| Label | Meaning |
|-------|---------|
| **Proved** | Walked / RTTI-checked on a real attach (date in topic doc) |
| **CT/host layout** | Field offsets from trainer dissect or host notes; **base pointer** still needs discovery |
| **Strategy** | How-to only; live base not confirmed on current attach |
| **Historical** | Older build or host note; re-validate after patch |
| **Raw dump** | Bulk extract; search, don’t assume every line is current |

| Topic | Status | Primary doc | Notes |
|-------|--------|-------------|--------|
| Modules (gamedll vs engine) | **Proved** (pattern) | [modules.md](modules.md) | Bases ASLR; use names |
| **PlayerVariables** (config floats; legacy CT `playerStat`) | **Proved** locator | [player-variables.md](player-variables.md) | **PlayerState+0xBA8** (2026-08-01); recipe short; research → [player-variables-history.md](player-variables-history.md) |
| Float name → catalog offset map | **CT/host** + generator notes | [player-vars-array.md](player-vars-array.md) | Map ≠ live instance |
| Time freeze / DayNightCycle / TIMESTRUCT+0x5C | **Proved** inject site (session) | [time-weather.md](time-weather.md) | Visuals may not fully track float-only freeze |
| Live HP (`LifeHealth+0x1C`) | **CT/host layout** + **strategy** | [health-money.md](health-money.md), [FIND-LIVE-HEALTH-MONEY.md](FIND-LIVE-HEALTH-MONEY.md) | Field known; **live base not proved** on current attach |
| Live cash (`InventoryMoney+0x38`) | **CT/host layout** + **strategy** | same | Prefer money scan first |
| Named APIs / hierarchy | Curated extract | [function-catalog.md](function-catalog.md) | |
| RTTI / type name lists | **Raw dump** | [rtti-types-engine-gamedll.md](rtti-types-engine-gamedll.md) | Offline-oriented |
| Host `/mnt/r` notes | **Historical** + re-mined | [host-notes-extract.md](host-notes-extract.md) | e.g. old PS **+0xE8** vs current **+0xBA8** |
| Investigation scraps | Open / partial | [scraps/](scraps/) | Fold into topic files when stable |

### Offset confidence (common conflicts)

| Item | Prefer | Do not assume |
|------|--------|----------------|
| PlayerState → PlayerVariables | **+0xBA8** (proved 2026-08-01) | Host **+0xE8** without re-check |
| Catalog base for map offsets | Engine `this + 8` (legacy `playerStat`) | Confusing map-only structure with live instance |
| Current HP field | `LifeHealth + 0x1C` | Config MaxHealth on PlayerVariables as “HUD HP” |
| Module → LifeHealth ptr | Re-check **+0x48** and CT **+0x88**; trust RTTI on pointer | Single offset forever |
| Money field | `InventoryMoney + 0x38` | PlayerVariables pricing floats as wallet |

---

## Suggested work order (table / discovery)

1. Attach + remote `tableStatus` / `enumModules` — confirm process and module names ([modules.md](modules.md)).  
2. Rebind / find **PlayerVariables** via proved chain — [player-variables.md](player-variables.md) (not GroupScan-first).  
3. Port named config rows from catalog map — [player-vars-array.md](player-vars-array.md).  
4. Time feature if needed — [time-weather.md](time-weather.md) + `ce-aob-scan`.  
5. Live money then HP — [FIND-LIVE-HEALTH-MONEY.md](FIND-LIVE-HEALTH-MONEY.md); write results into [health-money.md](health-money.md) with YYYYMMDD.  
6. Table migration mechanics — `skills/ce-table-migrate` + [../../TABLE-MIGRATE.md](../../TABLE-MIGRATE.md).

---

## Topic → file

| Topic | Open |
|-------|------|
| Modules (gamedll vs engine) | [modules.md](modules.md) |
| Named APIs / class hierarchy | [function-catalog.md](function-catalog.md) |
| **PlayerVariables** (live config; was playerStat) | [player-variables.md](player-variables.md) |
| PlayerVariables research archive | [player-variables-history.md](player-variables-history.md) |
| Detect PlayerVariables (PlayerState+0xBA8 chain) | [player-variables.md](player-variables.md) § Do this first |
| FloatPlayerVariable offset map | [player-vars-array.md](player-vars-array.md) |
| Group scan (research multi-value only) | [../../CE-GROUP-SCAN.md](../../CE-GROUP-SCAN.md) |
| HP / money field layouts | [health-money.md](health-money.md) |
| **How to find live HP & money** | [FIND-LIVE-HEALTH-MONEY.md](FIND-LIVE-HEALTH-MONEY.md) |
| Host notes extract | [host-notes-extract.md](host-notes-extract.md) |
| Time of day / freeze | [time-weather.md](time-weather.md) |
| RTTI type lists (raw) | [rtti-types-engine-gamedll.md](rtti-types-engine-gamedll.md) |
| Folder rules | [README.md](README.md) |
| Dated scraps | [scraps/](scraps/) |

---

## Quick facts (stable names; bases change)

| Fact | Detail |
|------|--------|
| Process | `DyingLightGame_x64_rwdi.exe` |
| Most injects | `gamedll_ph_x64_rwdi.dll` |
| Named systems | often `engine_x64_rwdi.*` |
| Config floats | **PlayerVariables** catalog base + offset — locator [player-variables.md](player-variables.md) |
| Live HP field | `LifeHealth+0x1C` (not PlayerVariables) — **base TBD** until FIND-LIVE phases done |
| Live cash field | `InventoryMoney+0x38` — **base TBD** until FIND-LIVE phases done |
| Time frac | DayNightCycle / TIMESTRUCT `+0x5C` (not player entity) |

---

## Workflow: investigation → scrap → doc

1. Investigate (CE, PDB names, disasm).  
2. Write a **scrap** under `scraps/YYYY-MM-DD-topic.md` if findings are reusable.  
3. Fold into the topic file above when stable; update the **status matrix**.  
4. **Never** commit host CT dumps, full table binaries, or private script collections as a substitute for this tree.

---

## Offline host assets (not in repo)

Typical local paths (example): `/mnt/r` — DLLs, PDB, author notes. Use for offline work; extract **facts** into this docs tree only.  
Local CE helpers may exist in gitignored `helper/` at repo root — not part of the published knowledge set.
