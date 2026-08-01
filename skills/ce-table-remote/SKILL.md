---
name: ce-table-remote
description: Foundation for remote Cheat Engine address-list and structure work via ce_server.lua — sync_call, main-thread rules, response limits, AOB wildcards, and crash avoidance when agents edit loaded tables.
tags: [ce, remote, address-list, structure, table-migrate]
---

# CE table remote (foundation)

Use when working with the **loaded cheat table** (address list + dissect structures) over the UEScan remote, or when implementing `al*` / `st*` commands.

## Connection

```python
from client import CERemote
ce = CERemote("192.168.176.1", 8000, timeout=120)  # lab defaults; adjust host/port
print(ce.cmd("ping"))
print(ce.cmd("getVersion"))   # expect v1.1+ for table foundation
print(ce.cmd("tableStatus"))
print(ce.cmd("alDump"))           # v1.2+ TSV inventory
print(ce.cmd("alGet 78"))         # one record by ID
print(ce.cmd("alResolve 90"))     # live resolve
```

Reload `ce_server.lua` in CE after upgrades (close Lua Engine tab if “already running”). Expect **v1.2+** for `alDump` / `alGet` / `alResolve`.

## Architecture rule

| Thread | Safe for |
|--------|----------|
| Pipe server (`createThread` bg) | `read*`, `write*`, native `AOBScan`, `enumModules`, pure math |
| **Main thread** via `synchronize` / server `sync_call` | `getAddressList`, MemoryRecord fields, structures, `Active`/AA |

Never mutate the address list or global structures from the background thread without `sync_call` / `synchronize`.

## Server helpers (v1.1+)

| Mechanism | Purpose |
|-----------|---------|
| `tableStatus` | process, pid, alCount, stCount |
| `debugSync` / `debugSyncError` | Prove main-thread path; error isolation |
| `alDump [off] [lim]` | Full inventory TSV (metadata only) |
| `alGet <id>` | Detail without full script text |
| `alResolve <id>` | CUR / READABLE / VALUE |
| `AOBScan <pattern>` | Supports `**` wildcards (fixed in v1.1) |
| `_G._ue_sync_call(fn)` | Same sync primitive from advanced scripts |
| `_G._ue_st_find_by_name(name)` | Safe structure lookup (**not** `getStructure(name)`) |
| `_G._ue_al_find_by_id(id)` | Memrec by ID |

Responses larger than **~48 KiB** return `ERROR: RESPONSE_TOO_LARGE`.

## Classification of address-list rows (from real tables)

| CLASS | Meaning |
|-------|---------|
| `AA` | Type often **11**; has AutoAssembler / `{$lua}` script |
| `EXPR` | Address is interpretable text: `playerStat + 2e38`, `[SYM]+5C` (OffsetCount may be 0) |
| `POINTER` | CE multi-offset `Offset[]` chain |
| `GROUP` | Headers / notes |
| `STATIC` | Plain / module address |

Do **not** assume “pointer” means `OffsetCount > 0` only — many trainers use **EXPR** strings after a bootstrap script registers a symbol.

## Renaming entries

```lua
-- via runScript until alSetDesc (T03) ships:
synchronize(function()
  local mr = getAddressList().getMemoryRecordByID(id)
  mr.Description = "New name"
  return mr.Description
end)
```

If any AA script uses `getMemoryRecordByDescription("exact old name")`, update that script when renaming.

## Dangerous / banned from remote handlers

| Avoid | Why |
|-------|-----|
| `enumMemoryRegions` | Crash / bad state |
| `createMemScan` / `varscan_*` from server thread | Hang / corrupt scan engine |
| `getStructure("Name")` | Coerces to index 0 — wipe risk |
| Mass `Active=true` | Inject storms / dialogs |
| Logging full AA scripts | UI freeze; use verb + id only |
| `synchronize` while modal dialog open | Deadlock with pipe server |

Prefer native `AOBScan` over long `runScript` scans. Client timeout **≥ 120s** for AA enable / large AOB.

## Related

- Tasks: `docs/tasks/T01-*.md`, `docs/tasks/ISSUES-AND-NONGOALS.md`
- Spike: `docs/tasks/T00-RESULTS.md`
- Scanning: `skills/ce-remote-scanning`
