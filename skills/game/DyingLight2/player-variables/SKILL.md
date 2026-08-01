---
name: dl2-player-variables
description: Dying Light 2 playerStat / FloatPlayerVariable table patterns — bootstrap AOB history, EXPR address rows, modules, and how to retune after a game update via remote CE.
tags: [game, DyingLight2, DL2, ce, aob, playerStat]
---

# Dying Light 2 — Player variables table

Use when porting or debugging a CE table that uses **`playerStat`** / **`playerStatAlt`** symbols and dozens of `playerStat + offset` value rows (InfiniteStamina, glide, combat floats, etc.).

## Table shape (observed ~1.93-oriented CT)

| Piece | Role |
|-------|------|
| Bootstrap AA (TYPE=11) | Description like `[Cheat][1.93] Enable playervariables editing` |
| Enable path | `{$lua}` → `AOBScan(..., '+W-C')` → `RegisterSymbol(playerStat/Alt)` → sets own `.Address` |
| Value rows | **EXPR** addresses: `playerStat + 2e38`, not CE `Offset[]` chains |
| Group headers | “Expand on enable” / section labels |
| Other cheats | Separate `aobscanmodule(..., gamedll_ph_x64_rwdi.dll, ...)` inject scripts |

**Process / modules (example session):**

- `DyingLightGame_x64_rwdi.exe`
- Gameplay often in **`gamedll_ph_x64_rwdi.dll`** (inject AOBs)

## Bootstrap script pattern history

Comments inside the CT script:

| Build note | AOB head (writable, `+W-C`) |
|------------|------------------------------|
| 1.42 | `10 A0 96 ** ** ** ** 00 00 00 00 80 3E 00 00 80 3E ... 00 00 40 40` |
| 1.82 | `08 28 C7 ** ** ** ** 00 00 00 00 80 3E 00 00 80 3E ... 00 00 40 40` |
| 1.90 (active in CT) | `08 ** ** ** ** ** ** 00 00 00 00 80 3E 00 00 80 3E ... 00 00 40 40` |

Logic:

```text
hits = AOBScan(pattern, '+W-C')
playerX = hits[0]; playerY = hits[1]   -- expects ≥2 hits
playerStat = playerX + 1
playerStatAlt = playerY + 1
RegisterSymbol(...); patch bootstrap row Address
```

### Live check (T00 session)

On one attached build, **full historical patterns returned 0 hits**. Shared float core still exists widely:

```text
00 00 00 00 80 3E 00 00 80 3E 00 00 00 00 00 00 00 00   -- hundreds of hits
```

So: **the CT’s AOB is version-specific and was already stale for that process.** Retune before trusting enable.

## How this AOB was found historically (port method)

Not pure code-xref only:

1. Identify **stable field defaults** (floats/ints documented in the table: MaxStamina ~0.8, jump heights, glide costs, etc.).
2. Scan / filter memory for those constants (often near dual `1.0f` = `00 00 80 3E` blocks).
3. Walk **back to a stable header/signature** that still marks the player variables blob after a patch.
4. Encode that signature as AOB (`+W-C` if it lives in writable data).
5. Validate: enable bootstrap → `playerStat` resolves → sample offsets match expected defaults → freeze/toggles behave.

Offsets **inside** the blob also drift between versions; structure names like `FloatPlayerVariable 1.90` in the CT are hints, not guarantees.

## Remote workflow (no full al* API required)

```text
1. tableStatus / process check
2. AOBScan new candidate (v1.1+ accepts ** wildcards on native command)
3. For each hit: candidate = hit+1; readFloat/readInteger at known offs; score vs defaults
4. Patch bootstrap script pattern (T04) or temporary runScript RegisterSymbol for test
5. Only then enable bootstrap AA; verify getAddress playerStat
6. Spot-check EXPR rows (alResolve once T02 exists)
```

**Do not** enable inject AA scripts while retuning playerStat unless intended.

## Renaming the bootstrap entry

Safe for display, **dangerous for this CT’s self-lookup**:

```lua
addressList.getMemoryRecordByDescription('[Cheat][1.93] Enable playervariables editing')
```

If you rename the description, update that string inside the AA script in the same change.

## Dissect structures

CT may contain large dumps (`PlayerState`, `FloatPlayerVariable 1.xx` with **tens of thousands** of elements). Prefer validating a few named offsets over cloning entire mega-structs unless necessary.

## Related

- Spike notes: `docs/tasks/T00-RESULTS.md`
- CE remote foundation: `skills/ce-table-remote`
- Remote scanning safety: `skills/ce-remote-scanning`
