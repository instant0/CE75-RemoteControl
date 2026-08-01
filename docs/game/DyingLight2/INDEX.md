# Dying Light 2 — knowledge index

**Root:** `docs/game/DyingLight2/`  
**Purpose:** Extracted information for agents and humans. Not raw CT/scripts for public dump.

**Related tools (skills, not game docs):** `skills/ce-aob-scan`, `skills/ce-remote-scanning`, `skills/ce-table-migrate`, …

**Version tags in CT MEMORY descriptions:** prefer `YYYYMMDD` when re-verified.

---

## Topic → file

| Topic | Open |
|-------|------|
| Modules (gamedll vs engine) | [modules.md](modules.md) |
| Named APIs / class hierarchy | [function-catalog.md](function-catalog.md) |
| playerStat / live config floats | [player-variables.md](player-variables.md) |
| playerStat bootstrap (code AOB / access log; not GroupScan primary) | [player-variables.md](player-variables.md) |
| Group scan (research multi-value only) | [../../CE-GROUP-SCAN.md](../../CE-GROUP-SCAN.md) |
| FloatPlayerVariable offset map generator | [player-vars-array.md](player-vars-array.md) |
| Current HP / money amount | [health-money.md](health-money.md) |
| **How to find live HP & money** | [FIND-LIVE-HEALTH-MONEY.md](FIND-LIVE-HEALTH-MONEY.md) |
| Host `/mnt/r` notes extract | [host-notes-extract.md](host-notes-extract.md) |
| Time of day / DayNightCycle / freeze | [time-weather.md](time-weather.md) |
| Dated investigation scraps | [scraps/](scraps/) |

---

## Quick facts

| Fact | Detail |
|------|--------|
| Process | `DyingLightGame_x64_rwdi.exe` |
| Most injects | `gamedll_ph_x64_rwdi.dll` |
| Named systems | often `engine_x64_rwdi.*` |
| Config floats | `playerStat` + offset (`FloatPlayerVariable` map) |
| Live HP | `LifeHealth+0x1C` via `PlayerHealthModule` |
| Money | `InventoryMoney+0x38` |
| Time frac | DayNightCycle / TIMESTRUCT `+0x5C` (not player entity) |
| **Live HP** | `LifeHealth+0x1C` (not playerStat) |
| **Live cash** | `InventoryMoney+0x38` |

---

## Workflow: investigation → scrap → doc

1. Investigate (CE, PDB names, disasm).  
2. Write a **scrap** under `scraps/YYYY-MM-DD-topic.md` if findings are reusable.  
3. Fold into the topic file above when stable.  
4. **Never** commit host CT dumps, full table binaries, or private script collections as a substitute for this tree.

---

## Offline host assets (not in repo)

Typical local paths (example): `/mnt/r` — DLLs, PDB, author notes. Use for offline work; extract **facts** into this docs tree only.
