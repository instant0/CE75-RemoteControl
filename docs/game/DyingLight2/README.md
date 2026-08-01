# Dying Light 2 — game knowledge (docs)

**This folder is documentation:** extracted facts, layouts, symbols, and investigation notes useful when porting or debugging a CE table for DL2.

## What belongs here

| Yes | No |
|-----|-----|
| Distilled offsets, type names, module map | Full `.CT` tables |
| Confirmed AOB patterns + ranking rules | Raw dumps of `/mnt/r` scripts as “the product” |
| Engine/gamedll symbol catalogs | Private generators copied wholesale for public upload without intent |
| Session **scraps** (dated findings) | CE **skills** (those live under `skills/` and are game-agnostic tools) |

## What does **not** belong under `skills/`

Research notes, version dumps, and “feature writeups” are **not** skills.  
Skills teach **how to operate CE remote / AOB / table migrate** for any game.

## Layout

| Path | Content |
|------|---------|
| [INDEX.md](INDEX.md) | Start here — topic → file |
| `modules.md` | gamedll vs engine |
| `function-catalog.md` | Named APIs / type hierarchy |
| `player-variables.md` | `playerStat` bootstrap / EXPR rows |
| `player-vars-array.md` | FloatPlayerVariable name↔offset generator |
| `health-money.md` | LifeHealth / InventoryMoney |
| `time-weather.md` | DayNightCycle / TIMESTRUCT / freeze time |
| `scraps/` | Dated investigation notes (info bank) |

Offline host files (DLLs, PDB, original author notes, tables) stay on the host — **do not** commit them here.
