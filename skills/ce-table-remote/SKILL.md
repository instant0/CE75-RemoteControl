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
print(ce.cmd("alSetDesc 81 note text"))   # v1.3+ mutate (use careful IDs)
print(ce.cmd("alSetAddress 90 playerStat + 2e38"))
print(ce.cmd("stDump"))                   # v1.5+ structure list
print(ce.cmd("stEnsureSeed"))             # v1.7+ empty-list crash guard
print(ce.cmd("stFind PlayerStats"))
print(ce.cmd("stGet PlayerStats"))        # elements; optional elemOff elemLimit
print(ce.cmd("stClone PlayerStats -> PlayerStats_v2"))  # v1.6+
print(ce.cmd("stBegin PlayerStats_v2"))
print(ce.cmd("stUpsertElem PlayerStats_v2|10|Count|4|4"))
print(ce.cmd("stEnd PlayerStats_v2"))     # commit BEFORE rename
print(ce.cmd("stSetName PlayerStats_v2 -> PlayerStats_new"))
```

Reload/restart CE after server upgrades. Expect **v1.7+** for dissect seed + safe rename; **v1.6+** structure edit/clone; **v1.5+** inventory; **v1.4+** AA scripts; **v1.3+** mutations; **v1.2+** address-list inventory.

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
| `alSetDesc / alSetAddress / alSetOffsets / alSetType` | Mutate loaded table (v1.3+) |
| `alGetScript` / `alSetScript*` / `aaCheck` / `alSetActive` | AA script + enable (v1.4+) |
| `stDump` / `stFind` / `stGet` | Global dissect structure inventory (v1.5+) |
| `stEnsureSeed` | Ensure `DO_NOT_DELETE_PLACEHOLDER` (v1.7+; empty-list crash) |
| `stClone` / `stBegin` / `stEnd` / `stUpsertElem` / `stClearElements` / `stSetName` | Structure clone + edit (v1.6+; rename rules v1.7+) |
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

## Renaming / rebinding entries

```text
alSetDesc <id> New description text
alSetAddress <id> playerStat + 2e38
alSetOffsets <id> 10,2A0,8
alSetType <id> 4
```

If any AA script uses `getMemoryRecordByDescription("exact old name")`, update that script (T04) when renaming.

## Dangerous / banned from remote handlers

| Avoid | Why |
|-------|-----|
| `enumMemoryRegions` | Crash / bad state |
| `createMemScan` / `varscan_*` from server thread | Hang / corrupt scan engine |
| `getStructure("Name")` | Coerces to index 0 — wipe risk |
| Empty structure list (0 dissects) | Dissect crash: list index (0) |
| Rename while `stBegin` open | Must `stEnd` first |
| Mass `Active=true` | Inject storms / dialogs |
| Logging full AA scripts | UI freeze; use verb + id only |
| `synchronize` while modal dialog open | Deadlock with pipe server |
| `alSetActive 1` without `aaCheck` | Avoidable enable failures |

### AA script protocol (v1.4+)

```text
alGetScript <id> [off] [len]     → DATA=hex of script bytes
alSetScriptBegin <id> <totalLen>
alSetScriptChunk <id> <off> <hex>   # off must equal bytes received so far
alSetScriptCommit <id>
aaCheck <id>
alSetActive <id> 1                  # timeout ≥ 120; user risk
alDisableSoft <id>
```

Non-AA rows → `ERROR: NOT_AA`. Prefer enable **one** bootstrap script at a time (e.g. DL2 playerStat), then `alResolve` dependents.

Prefer native `AOBScan` over long `runScript` scans. Client timeout **≥ 120s** for AA enable / large AOB.

### Structure inventory (v1.5+)

```text
stDump                              → COUNT=n + IDX/NAME/SIZE/ELEMS
stFind <exactName>                  → OK NAME=... IDX=... SIZE=... ELEMS=...
stGet <exactName> [elemOff] [limit] → header + element TSV (default limit 500)
```

Definitions only (saved with the `.CT`). No live base required. For large structs, page with `elemOff` / `elemLimit`.

### Structure clone / edit (v1.6+) + seed/rename safety (v1.7+)

```text
stEnsureSeed                        → create DO_NOT_DELETE_PLACEHOLDER if missing
stClone <src> -> <dst>              → seed first; fill under temp name; rename after commit
stBegin <name> / stEnd <name>       → batch beginUpdate/endUpdate (stEnd = commit)
stUpsertElem name|off|elem|vtype|[bytes]|[child]|[cstart]
stClearElements <name>              → destroy all elements (never the placeholder)
stSetName <old> -> <new>            → ERROR if still updating; call stEnd first
```

**Critical CE rules (from real crashes):**

1. **Never operate on an empty global structure list.** If the table has zero dissects, call `stEnsureSeed` first (or let `stClone` seed automatically). Empty list → dissect `list index (0) out of bounds`.
2. **Never delete/clear/rename** `DO_NOT_DELETE_PLACEHOLDER` (or legacy `UE_Seed`). Server returns `ERROR: PROTECTED`.
3. **Commit before rename:** finish all element edits → `stEnd` → only then `stSetName`. Renaming mid-edit is unsupported; server returns `ERROR: STILL_UPDATING`.
4. `stClone` creates under a temp name, fills, `endUpdate`s, then renames to the destination (save-then-rename).

Workflow:

```text
stEnsureSeed                        # if stCount==0 or first structure work of session
small drift  → stBegin / stUpsertElem / stEnd on original
large risk   → stClone Name -> Name_vNew, edit clone; user deletes old later
rename       → stEnd first, then stSetName
family rename → clone children first, then parents (pass-2 links by child name)
huge (~20k)  → prefer in-place upsert; clone works but ~2s+ and heavy
```

Timeout **≥ 120s** for large `stClone`. Do **not** remove structures from the global list from agents — remove in CE UI (and keep the placeholder).

**Never** call `getStructure("Name")` from `runScript` — use `_G._ue_st_find_by_name(name)` or the native commands. String args coerce to index 0 and can wipe the first structure.

Validating fields on a new game build needs a live base address from a healthy memrec, then `readQword(base+offset)` — not part of these inventory commands.

## Related

- Risks / non-goals: `docs/NONGOALS-AND-HAZARDS.md`
- Playbook: `skills/ce-table-migrate`
- Command ref: `docs/TABLE-MIGRATE.md`
- Scanning: `skills/ce-remote-scanning`

