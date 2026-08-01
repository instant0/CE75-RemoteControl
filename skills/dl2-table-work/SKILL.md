---
name: dl2-table-work
description: Navigate Dying Light 2 CE table rebind and discovery over remote CE — work order only; offsets and proofs live in docs/game/DyingLight2/.
tags: [dl2, dying-light-2, ce, remote, table-migrate]
---

# Dying Light 2 — table / discovery work order

Use when the loaded game is **Dying Light 2** and the agent must rebind a CT, find config vars, time, or live HP/money over the UEScan remote.

**This skill does not store offsets.** Open the docs. Do **not** load `ue-character-finding` / `ue-stats-attributes` / `ue-inventory-hacking` as the default path (those are Unreal/G1R).

## Read first

| Doc | Why |
|-----|-----|
| `docs/game/DyingLight2/INDEX.md` | Status matrix, confidence, topic map |
| `docs/game/DyingLight2/modules.md` | gamedll vs engine |
| `skills/ce-table-migrate` | How to use `al*` / `st*` safely |
| `docs/CE-TABLE-OFFLINE-EDIT.md` | Offline `.CT` XML / AA `{…}` comment rules |
| `docs/AOB-CODE-DRIFT.md` | Drift classes for relocating AOBs after patches |
| `skills/ce-remote-scanning` | Crash avoidance, timeouts |
| `skills/ce-aob-scan` | AOB retune ranking |

## Preconditions

1. CE attached to `DyingLightGame_x64_rwdi.exe` (or current shipping name).  
2. `ce_server.lua` loaded; `getVersion` ≥ **v1.7** (prefer **v1.8.3+** for `GroupScan`).  
3. Relay + client reachable; timeout **≥ 120** for enable/AOB/GroupScan.  
4. `ping` → `pong`; `tableStatus` shows expected process.  
5. If `stCount=0` → `stEnsureSeed` before structure work.

## Work order (do not reverse casually)

```text
1) enumModules / tableStatus — confirm gamedll + engine module names
2) PlayerVariables (config floats) — proved locator in player-variables.md
     PlayerState+0xBA8 → engine this; catalog = this+8
     Symbol: PlayerVariables (legacy alias playerStat)
     NOT GroupScan-first; NOT ue-* GEngine chain
3) Remap EXPR rows from FloatPlayerVariable YYYYMMDD catalog
     (player-vars-array.md) — fix type (byte vs float) on bools
4) Time / weather inject if needed — time-weather.md + ce-aob-scan
5) Live money then HP — FIND-LIVE-HEALTH-MONEY.md strategy
     Field layouts: health-money.md (bases may still be TBD)
6) Other inject AA — one at a time (ce-table-migrate Tier A)
7) User saves .CT in CE
```

## Preferred tools

| Need | Use |
|------|-----|
| Table mutate | `al_*` / `st_*` via `ce-table-migrate` |
| Code inject retune | `ce-aob-scan` + `aobscanmodule` on **gamedll** |
| Multi-float research locate | Native **`GroupScan`** (`docs/CE-GROUP-SCAN.md`) — fallback only for PlayerVariables |
| Safe reads | Native `read*` / `getAddress` / `symGet` |
| Banned | `createMemScan` / `varscan_*` / `enumMemoryRegions` from remote; mass `Active=true` |

## Confidence rules

- Treat INDEX **status matrix** as truth: **proved** vs **CT/host layout** vs **strategy**.  
- Do not report live HP/cash as “found” until FIND-LIVE phases produce bases on **this** attach.  
- Host **PlayerState+0xE8** is historical; current prove is **+0xBA8**.  
- Absolute addresses in docs are session examples only (ASLR).

## Hand off to humans when

- Getter AOB / global RVA died after patch and chain re-proof is needed  
- Access log / “find what accesses” required (not remote)  
- Multiplayer / anti-cheat sensitive enables without explicit OK  
- Modal AA failure in CE (user must dismiss)

## Related paths

- Knowledge root: `docs/game/DyingLight2/`  
- Recipe: `docs/game/DyingLight2/player-variables.md`  
- History/research: `docs/game/DyingLight2/player-variables-history.md`  
- Hazards: `docs/NONGOALS-AND-HAZARDS.md`  
- Table commands: `docs/TABLE-MIGRATE.md`  
