# Table migration (address list + dissect structures)

Port a **loaded** Cheat Engine 7.5 cheat table to a new game build over the UEScan remote. The agent rebinds AOB/scripts, pointer/expression rows, and structure definitions in the live table; the **user saves** in CE when satisfied. There is no agent `saveTable` / offline CT rewrite pipeline.

Server: `ce_server.lua` (**v1.7+** recommended: seed + safe rename).  
Client: `client.py` helpers (`CERemote`).  
Playbook skill: `skills/ce-table-migrate/SKILL.md`.  
Implementer tasks: `docs/tasks/`.

## Goal

| In | Out |
|----|-----|
| Old working `.CT` loaded (~100 memrecs, ~15–20+ dissects) | Same table rebound for the **new** build |
| Process attached; remote + relay up | User **File → Save** when happy |

## Architecture

```text
WSL agent  --TCP-->  windows_relay  --pipe-->  ce_server.lua (createThread)
                                              │
                    al*/st*/Active/AA  ------►│ synchronize (main thread)
                    read*/AOBScan     ------►│ background thread OK
```

- **Main thread only** for address list, structures, `Active`, AA (`sync_call` / `synchronize`).
- Soft response cap **~48 KiB** (pipe buffer 65536). Use pagination / script chunks.
- Client timeout **≥ 120s** for `alSetActive`, large `AOBScan`, large `stClone`.

## Connection

```bash
# Lab example (adjust host/port)
H=192.168.176.1; P=8000
python3 client.py --host $H --port $P --timeout 120 --cmd "ping"
python3 client.py --host $H --port $P --timeout 120 --cmd "getVersion"
# expect: ce-server v1.7 (CE 7.5 st-safe) or newer
python3 client.py --host $H --port $P --timeout 120 --cmd "tableStatus"
```

```python
from client import CERemote
ce = CERemote("192.168.176.1", 8000, timeout=120)
print(ce.ping())
print(ce.table_status())  # process, alCount, stCount, seed=
print(ce.al_dump(limit=20)[:800])
```

## Recommended agent algorithm

```text
1. Preconditions: attach, load CT, ping, tableStatus (process name, alCount, stCount, seed)
2. If stCount==0 → stEnsureSeed (empty dissect list crashes CE)
3. Inventory: alDump → classify CLASS (AA / EXPR / POINTER / STATIC / GROUP)
4. Tier A — AA / scripts:
     - Identify bootstrap scripts (RegisterSymbol / aobscan)
     - al_get_script → edit AOB → al_set_script → aa_check
     - al_set_active(id, True, timeout=120) ONE at a time
     - al_resolve / getAddress on registered symbols
5. Tier B — EXPR / POINTER value rows:
     - Fix al_set_address / al_set_offsets; al_resolve; sample values
6. Tier C — STATIC if needed
7. Structures (optional / after bases exist):
     - stDump / stGet; validate with live base + readQword(base+off)
     - small drift → stBegin / stUpsertElem / stEnd
     - large risk → stClone then edit clone; stEnd before stSetName
8. User saves table in CE
```

Dependency order: **AA enable (symbols) → expression/pointer rows → structure validation**.

## Command reference

### Foundation

| Command | Example response |
|---------|------------------|
| `ping` | `pong` |
| `getVersion` | `ce-server v1.7 (CE 7.5 st-safe)` |
| `tableStatus` | `OK process=... pid=... alCount=n stCount=n seed=0\|1 ceVersion=... server=...` |
| `debugSync` | `OK mainthread=1` |

### Address list

| Command | Notes |
|---------|--------|
| `alDump [off] [lim]` | TSV inventory; default `0 500`; no script bodies |
| `alGet <id>` | One memrec detail |
| `alResolve <id>` | Live CUR / READABLE / VALUE |
| `alSetDesc <id> <text>` | Description (rest of line) |
| `alSetAddress <id> <expr>` | Expression; keeps Offset[] |
| `alSetOffsets <id> <hex,hex>` | Pointer chain; empty clears |
| `alSetType <id> <n>` | Type integer |
| `alGetScript <id> [off] [len]` | Script slice as `DATA=` hex |
| `alSetScriptBegin/Chunk/Commit/Abort` | Chunked replace (AA only) |
| `aaCheck <id>` | `autoAssembleCheck` before enable |
| `alSetActive <id> 0\|1 [nocheck]` | Enable/disable; **AA enable runs aaCheck** unless `nocheck` (timeout ≥120) |
| `alDisableSoft <id>` | Disable without [Disable] section |
| `alApply stop=1 hex=…` | Batch setDesc/setAddress/setOffsets/setType in **one** `sync_call` |
| `alAudit [n]` | Last N command verbs + short results (ring buffer) |
| `symGet` / `symSet` | `getAddressSafe` / `registerSymbol` |
| `runScriptSafe` | Like `runScript` but rejects `enumMemoryRegions` / memscan / `getStructure("…")` strings |

Client helpers: `al_dump`, `al_get`, `al_resolve`, `al_set_*`, `al_apply`, `al_get_script`, `al_set_script`, `aa_check`, `al_set_active`, `al_disable_soft`, `sym_get`/`sym_set`, `run_script_safe`.

#### Batch example

```python
ce.al_apply([
    "setAddress 90 playerStat + 2e38",
    "setAddress 91 playerStat + 2e90",
    "setOffsets 100 10,2A0,8",
], stop_on_error=True)
```

Raw: ops joined with newlines, hex-encoded: `alApply stop=1 hex=...` or `alApply stop=1 setAddress 90 a ;; setType 91 4`.

### Structures

| Command | Notes |
|---------|--------|
| `stDump` | List global definitions |
| `stFind <name>` | Exact name |
| `stGet <name> [elemOff] [elemLimit]` | Element TSV; default limit 500 |
| `stEnsureSeed` | Create `DO_NOT_DELETE_PLACEHOLDER` if missing |
| `stClone <src> -> <dst>` | Two-pass clone; auto-seed; rename after commit |
| `stBegin` / `stEnd <name>` | Batch update; **stEnd = commit** |
| `stUpsertElem name\|off\|elem\|vtype\|…` | Exact-offset insert/update |
| `stClearElements <name>` | Destroy elements (not placeholder) |
| `stSetName <old> -> <new>` | Only after `stEnd`; refuses mid-edit |

Client helpers: `st_dump`, `st_find`, `st_get`, `st_ensure_seed`, `st_clone`, `st_begin`, `st_end`, `st_upsert_elem`, `st_clear_elements`, `st_set_name`.

### Memory / scan (unchanged)

`read*`, `writeBytes`, `getAddress`, `AOBScan` (`**` wildcards), `enumModules`, `runScript`.

## Wire formats

### `alDump` columns

```text
COUNT=n OFFSET=o LIMIT=l
ID  IDX  PID  DESC  TYPE  ACTIVE  ADDR  OFFC  OFFS  CUR  HASSCRIPT  SCRIPTLEN  CLASS
```

| CLASS | Meaning |
|-------|---------|
| `AA` | Script / type 11 (or 8) |
| `EXPR` | Address has `+` or `[` (symbol expressions) |
| `POINTER` | `OffsetCount > 0` |
| `GROUP` | Group headers |
| `STATIC` | Plain address |
| `OTHER` | Residual |

### `stGet` columns

```text
OK NAME=... IDX=... SIZE=... ELEMS=... ELEMOFF=... ELEMLIMIT=...
IDX  OFF  NAME  VTYPE  BYTES  CHILD  CHILDSTART
```

### Script hex chunking

```text
alGetScript id 0 16384  → OK ... TOTAL=n OFFSET=0 LENGTH=m DATA=<hex>
# loop OFFSET += LENGTH until OFFSET >= TOTAL

alSetScriptBegin id totalLen
alSetScriptChunk id off hex   # off must equal bytes received so far
alSetScriptCommit id
```

Prefer `ce.al_get_script(id)` / `ce.al_set_script(id, text)`.

## Dissect definitions vs open windows

| Object | Needs live address? | In .CT? |
|--------|---------------------|---------|
| Global structure (`st*`) | **No** | Yes |
| StructureFrm open window | **Yes** (column base) | No |

Validate layouts with a healthy base (`alResolve` / symbol) then `readQword(base+offset)`. StructureFrm helpers are optional (T11).

## Critical CE rules (structures)

1. **Never** `getStructure("Name")` — coerces to index **0** (wipe risk). Use `stFind` / `_G._ue_st_find_by_name`.
2. **Empty global list** crashes dissect (`list index (0)`). Call `stEnsureSeed` if `stCount==0`.
3. **Commit before rename:** `stEnd` then `stSetName`. Mid-`stBegin` rename → `ERROR: STILL_UPDATING`.
4. Do not clear/rename `DO_NOT_DELETE_PLACEHOLDER` / `UE_Seed`.
5. Huge structs (~20k elems): prefer in-place upsert; clone works but is heavy (~2s+).

## What will NOT work

| Area | Why | Instead |
|------|-----|---------|
| Agent `saveTable` | Product non-goal | User saves in CE |
| `mr.Script` on non-AA rows | CE no-op without AA script object | Only edit existing AA |
| Breakpoint-only discovery over TCP | No BP event pipe in v1 | AA + registersymbol; see `BREAKPOINT_STRATEGY.md` |
| `getStructure("Name")` | Index 0 | Name scan |
| `enumMemoryRegions` / bg `createMemScan` | Crash / hang | Native `AOBScan`, `enumModules` |
| Guaranteed no AA modal | CE may dialog | `aaCheck`; user present; high timeout |
| Perfect automatic AA understanding | Semantic | Human handoff on multi-hit AOBs |

## Crash / hang catalogue (agent must respect)

| Hazard | Mitigation |
|--------|------------|
| Table ops without `synchronize` | Use only native `al*`/`st*` (server uses `sync_call`) |
| `synchronize` + modal dialog | Deadlock — `aaCheck` first; user dismisses; timeout ≥120 |
| Mass `Active=true` | Enable **one** bootstrap/inject at a time |
| Oversized dump (all scripts) | `alDump` metadata only; chunk scripts |
| Empty structure list | `stEnsureSeed` |
| Rename while editing | `stEnd` before `stSetName` |
| Client default 30s timeout | Pass `timeout=120` for Active/AOB/clone |
| Nested `synchronize` via `runScript` | Avoid; use native commands |
| Logging full scripts to CE console | Server logs verb only |

## Timeouts

| Operation | Suggested client timeout |
|-----------|---------------------------|
| `ping`, `alGet`, `stFind` | 30–60s |
| `alDump`, `stDump`, script get/set | 60s |
| `alSetActive`, `AOBScan`, large `stClone` | **120s+** |

```python
ce.al_set_active(78, True, timeout=120)
ce.aob_scan("48 8B ** ** ** ** 00", timeout=120)
ce.st_clone("Big", "Big_v2", timeout=120)
```

## DL2-oriented notes (from T00 spike)

- Many value rows are **EXPR** (`playerStat + 2e38`), not CE multi-offset pointers.
- Bootstrap AA (e.g. playervariables) must enable first so `RegisterSymbol` works.
- Prefer module AOBs (`gamedll_…`) from scripts over full-process wild scans when porting injects.
- Some structures are **huge** (20k+ elements); do not mass-clone them casually.

Game-specific skill: `skills/game/DyingLight2/player-variables/SKILL.md`.

## Client helper map

| Python | Server |
|--------|--------|
| `table_status()` | `tableStatus` |
| `al_dump` / `al_get` / `al_resolve` | `alDump` / `alGet` / `alResolve` |
| `al_set_desc/address/offsets/type` | `alSet*` |
| `al_get_script` / `al_set_script` | chunked script |
| `aa_check` / `al_set_active` / `al_disable_soft` | AA enable path |
| `st_*` | structure inventory/edit |
| `cmd("…")` | anything else |

## Related

- `docs/tasks/` — T00–T11 task docs and RESULTS  
- `docs/tasks/ISSUES-AND-NONGOALS.md` — shared risks  
- `skills/ce-table-remote/SKILL.md` — foundation  
- `skills/ce-table-migrate/SKILL.md` — agent playbook  
- `README.md` — full command list + dangerous APIs  
- `docs/CE75-INTEGRATION.md` — CE75 UE helpers vs raw al/st  
