# Dying Light 2 — game knowledge (docs)

**This folder is documentation:** extracted facts, layouts, symbols, and investigation notes useful when porting or debugging a CE table for DL2.

**Start here:** [INDEX.md](INDEX.md) — status matrix, work order, topic map.

## What belongs here

| Yes | No |
|-----|-----|
| Distilled offsets, type names, module map | Full `.CT` tables |
| Confirmed AOB patterns + ranking rules | Raw dumps of `/mnt/r` scripts as “the product” |
| Engine/gamedll symbol catalogs | Private generators copied wholesale without intent |
| Session **scraps** (dated findings) | CE **skills** (those live under `skills/` and are game-agnostic tools) |

## What does **not** belong under `skills/`

Research notes, version dumps, and feature writeups are **not** skills.  
Skills teach **how to operate CE remote / AOB / table migrate** for any game.

## Layout (files)

| Path | Content |
|------|---------|
| [INDEX.md](INDEX.md) | **Start here** — status, work order, topic → file |
| [modules.md](modules.md) | gamedll vs engine |
| [function-catalog.md](function-catalog.md) | Named APIs / type hierarchy (curated) |
| [player-variables.md](player-variables.md) | **PlayerVariables** (legacy CT: `playerStat`); proved locator |
| [player-variables-history.md](player-variables-history.md) | Long research notes (access log, GroupScan session, legacy AOB) |
| [player-vars-array.md](player-vars-array.md) | FloatPlayerVariable name↔offset map |
| [health-money.md](health-money.md) | LifeHealth / InventoryMoney field layouts |
| [FIND-LIVE-HEALTH-MONEY.md](FIND-LIVE-HEALTH-MONEY.md) | Strategy to find **live** HP & money bases |
| [time-weather.md](time-weather.md) | DayNightCycle / TIMESTRUCT / freeze time |
| [host-notes-extract.md](host-notes-extract.md) | Re-mined host notes (often historical) |
| [rtti-types-engine-gamedll.md](rtti-types-engine-gamedll.md) | Raw RTTI/type name extract |
| [scraps/](scraps/) | Dated investigation notes |

Offline host files (DLLs, PDB, original author notes, tables) stay on the host — **do not** commit them here.
