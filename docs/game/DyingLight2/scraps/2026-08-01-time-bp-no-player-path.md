# Scrap: Time access registers do not lead to player

| Field | Value |
|-------|--------|
| **Date** | 2026-08-01 |
| **Status** | open (summary also in time-weather.md / function-catalog) |
| **Question** | From registers on the time-of-day update, can we walk to player structure? PDB? |

## Registers (user snapshot)

```text
RAX = 0000000000000013          # day-related small int (e.g. 19)
RBX = 00000211C41261D0          # this = DayNightCycle (same object 193 captures as TIMESTRUCT)
RCX = 00000211C412622C          # RBX+0x5C = &time frac float
RIP = 00007FFA210DC184          # gamedll day/night update family
```

**CE symbol `TIMESTRUCT`:** only valid while **cheat 193** is enabled (hook stores RBX). Not from 279. Not a free root.

## Conclusion

- **No path to `PlayerDI_PH` from this frame.** World clock object, not entity hub.  
- PDB: `DayNightCycle` separate from `PlayerDI` / `PlayerHealthModule` / `PlayerState`.  
- Player entry: `IGame::GetLocalPlayerEntity` or player-side access logging (inventory/health/FloatPlayerVariable).  
- Do not fold TIMESTRUCT into Start cheating unless clock is intentionally a permanent session symbol.

## Server note (same session)

Lua **server thread** died after a client call (last unanswered: `getAddress gamedll…`). Not “value BP stopped CE” — access logging does not freeze the process. See `skills/ce-remote-scanning` (EXEC log / session log).
