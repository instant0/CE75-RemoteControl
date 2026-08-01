---
name: ce-table-migrate
description: Port a loaded Cheat Engine address list and dissect structures to a new game version via the remote CE server (al*/st* commands), including crash avoidance and dependency-ordered rebind.
tags: [ce, remote, table-migrate, aob, address-list, structure]
---

# CE table migrate (playbook)

Use when the user has an **old working `.CT` loaded** in CE 7.5, attached to a **new game build**, and wants the table rebound over the UEScan remote—without crashing CE or wiping dissect structures.

Full command reference: `docs/TABLE-MIGRATE.md`.  
Foundation (sync rules, seed/rename): `skills/ce-table-remote/SKILL.md`.  
UE layout finding: `ue-character-finding`, `ue-stats-attributes`, `ue-inventory-hacking`, `ce-remote-scanning`.

## When to use

- New game version / build; same trainer table concepts still apply  
- Remote `ce_server.lua` + relay up; agent can reach host:port  
- User will **save** the table in CE when done (agent does **not** `saveTable`)

## Preconditions checklist

1. CE attached to the correct process  
2. Cheat table **loaded** (address list + structures present)  
3. `ce_server.lua` running (**v1.8+** preferred: QoL batch/aaCheck-on-enable; v1.7+ for seed/rename)  
4. Relay listening; client host/port correct (lab often `192.168.176.1:8000`)  
5. Client **timeout ≥ 120** for enable / AOB / large clone  
6. `ping` → `pong`; `tableStatus` shows expected process + `alCount` / `stCount`

```python
from client import CERemote
ce = CERemote("192.168.176.1", 8000, timeout=120)
assert ce.ping() == "pong"
print(ce.get_version())
print(ce.table_status())
if "stCount=0" in (ce.table_status() or ""):
    print(ce.st_ensure_seed())
```

## Inventory

```python
raw = ce.al_dump(offset=0, limit=2000)
rows = ce.al_dump_parsed(limit=2000)  # optional dict rows
```

Build tiers from **CLASS** (and HASSCRIPT):

| Tier | CLASS / signal | Role |
|------|----------------|------|
| **A** | `AA` or HASSCRIPT | AOB / inject / `RegisterSymbol` bootstrap |
| **B** | `EXPR`, `POINTER` | Value rows depending on symbols or chains |
| **C** | `STATIC` | Module/static addresses |
| **D** | `GROUP` | Headers — skip value work |

**DL2-style tables:** majority of values are **EXPR** (`playerStat + off`), not CE multi-level `Offset[]`. Bootstrap AA must run before dependents resolve.

## Dependency order (do not reverse)

```text
1) stEnsureSeed if stCount==0
2) Tier A — fix/rebind AA scripts → aaCheck → enable ONE at a time → verify symbols
3) Tier B — fix EXPR/POINTER addresses → alResolve → sample values
4) Tier C — static if needed
5) Structures — validate/edit after live bases exist
6) User saves .CT in CE
```

## Tier A — AA / scripts

1. `al_get(id)` / inventory: find bootstrap (`RegisterSymbol`, `{$lua}`, primary AOB).  
2. `text = ce.al_get_script(id)`  
3. Update AOB / module name for the new build (prefer patterns from the script’s own comments / `aobscanmodule`).  
4. Optional: native `ce.aob_scan(pattern, timeout=120)` to validate hits **before** enable.  
5. `ce.al_set_script(id, text)` → `ce.aa_check(id)`  
6. `ce.al_set_active(id, True, timeout=120)` — **one** script; server also aaChecks AA rows unless `nocheck=True`  
7. `ce.get_address("symbol")` / `ce.al_resolve(dependent_id)` / `ce.sym_get("playerStat")`  
8. Only then enable next inject script  

**Prefer:** `aaCheck` before every enable.  
**Never:** mass-enable many AA rows.  
**If modal appears in CE:** user must dismiss; otherwise `synchronize` deadlocks the pipe.

Soft disable without running [Disable]: `ce.al_disable_soft(id)`.

## Tier B — EXPR / POINTER

1. `ce.al_resolve(id)` — CUR non-zero? VALUE sensible?  
2. Fix expression: `ce.al_set_address(id, "playerStat + 2e38")`  
3. Or offsets: `ce.al_set_offsets(id, [0x10, 0x2A0, 0x8])`  
4. Bulk fixes: `ce.al_apply(["setAddress 90 …", "setOffsets 91 10,20"], stop_on_error=True)`  
5. Re-resolve; do not assume CLASS=POINTER only when `OffsetCount>0`.

## Tier C — STATIC

Update module+offset or absolute addresses when needed; same `al_set_address` / resolve loop.

## Structures

Definitions are **templates** (no live base required to dump/edit). Validation needs a base address.

```python
ce.st_ensure_seed()
print(ce.st_dump()[:1500])
print(ce.st_get("PlayerStats", elem_off=0, elem_limit=50))
```

| Situation | Action |
|-----------|--------|
| Small field drift | `st_begin` → `st_upsert_elem` → **`st_end`** |
| Large uncertainty | `st_clone(src, dst)` then edit clone; user deletes old later |
| Rename | **`st_end` first**, then `st_set_name(old, new)` |
| Family rename | Clone **children first**, then parents (ChildStruct links by name) |
| ~20k-element dump structs | Prefer in-place upsert; avoid casual full clones |

```python
ce.st_begin("MyStruct_v2")
ce.st_upsert_elem("MyStruct_v2", 0x10, "Count", 4, byte_size=4)
ce.st_end("MyStruct_v2")          # commit
ce.st_set_name("MyStruct_v2", "MyStruct_new")  # only after end
```

Validate: resolve base from memrec/symbol → `read_qword` / `readQword` at `base+offset`.

**Never** call `getStructure("Name")` from `runScript`.

## Dissect definition vs form

| | Global `st*` definition | Open StructureFrm window |
|--|-------------------------|---------------------------|
| Live address | Not required | Required (column base) |
| Saved in .CT | Yes | No |
| Remote API | `st*` (shipped) | Optional T11 `sf*` |

## Banned APIs / patterns

| Avoid | Why |
|-------|-----|
| `enumMemoryRegions` | Crash / bad state |
| `createMemScan` / `varscan_*` from remote handlers | Hang / corrupt scan engine |
| `getStructure("Name")` | Index 0 wipe |
| Empty global structure list | Dissect list index (0) crash |
| Rename mid-`stBegin` | Must `stEnd` first |
| Mass `Active=true` | Inject storms / dialogs / deadlock risk |
| Dump all script bodies in one response | >48 KiB / freeze |
| Unbounded pointer walks in `runScript` | Hang / crash |
| Agent `saveTable` | User saves |

## Deadlock / crash programming

- Server already uses `synchronize` for table ops — **do not** nest long `runScript`+`synchronize` games.  
- AA failure may open a **modal** → pipe waits forever until user clicks.  
- Client timeout **120s+** on enable/AOB does not fix deadlock; it only fails the client.  
- Prefer native commands over giant `runScript` blobs.  
- Keep `DO_NOT_DELETE_PLACEHOLDER`; never clear/rename it.

## Human handoff criteria

Stop and ask the user when:

- AOB has **many** ambiguous hits and no reliable module filter  
- Script is **breakpoint-driven** or needs debugger events (not in remote v1)  
- Layout/semantics changed (fields reordered, not just offsets)  
- CE75 / game plugin expected but missing  
- Enable injects into multiplayer / anti-cheat sensitive contexts without explicit OK  
- Structure form UI state is corrupted and needs manual CE recovery  

## Out of scope

- Agent `saveTable` / offline full CT generation as primary path  
- Perfect automatic understanding of all AA scripts  
- Breakpoint push-over-TCP (see `docs/BREAKPOINT_STRATEGY.md`)  
- Hotkeys, trainer forms, embedded table files  

## Command cheat sheet

| Need | Command / helper |
|------|------------------|
| Health | `ping`, `table_status`, `get_version` |
| Inventory | `al_dump`, `al_get`, `al_resolve` |
| Mutate row | `al_set_desc/address/offsets/type`, `al_apply([...])` |
| Script | `al_get_script`, `al_set_script`, `aa_check` |
| Enable | `al_set_active(id, True, timeout=120)` (AA auto-aaCheck) |
| Structures | `st_ensure_seed`, `st_dump/get/find`, `st_clone`, `st_begin/end`, `st_upsert_elem`, `st_set_name` |
| Scan | `aob_scan`, `enum_modules` |
| Escape hatch | `cmd("…")`, `run_script` (careful) |

Details and wire formats: **`docs/TABLE-MIGRATE.md`**.

## Related

- Tasks: `docs/tasks/T00`–`T09`, `ISSUES-AND-NONGOALS.md`  
- Spike: `docs/tasks/T00-RESULTS.md`  
- Foundation skill: `ce-table-remote`  
- DL2 bootstrap: `game/DyingLight2/player-variables`  
