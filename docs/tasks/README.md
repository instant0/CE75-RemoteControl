# Table migration — implementation tasks

Task documents for implementing **remote-safe address-list and dissect-structure editing** so agents can port a working CE 7.5 cheat table to a new game version.

## Goal (product)

| In | Out |
|----|-----|
| User loads old working `.CT` (~100 memrecs, ~15–20 dissect structs) and attaches to **new** game build | Same **loaded** table rebound: AOB/scripts, pointer chains, structure layouts |
| Remote CE server + agent | User **saves** in CE when satisfied (no agent save pipeline) |

## How to use these docs

- Each `Txx-*.md` is written to be **mostly standalone**: context, APIs, risks, acceptance criteria.
- **Depends on** / **Blocks** / **Parent** / **Children** link the graph.
- Do not start a task until its **Depends on** items are done (or explicitly waived).
- Prefer implementing in **ID order** within a phase.

## Dependency graph

```text
T00  Spike (real table)
 │
 ├── T01  sync_call + server hardening primitives
 │     │
 │     ├── T02  alDump / alGet / alResolve / tableStatus
 │     │     │
 │     │     ├── T03  alSet* (address, offsets, desc, type)
 │     │     │     │
 │     │     │     └── T04  al script chunk get/set + alSetActive / soft disable
 │     │     │
 │     │     └── T05  stDump / stGet / stFind
 │     │           │
 │     │           └── T06  stClone + element upsert / begin-end update
 │     │
 │     └── T07  client.py helpers
 │           │
 │           ├── T08  docs (README + TABLE-MIGRATE)
 │           └── T09  skill ce-table-migrate
 │
 └── T10  integration smoke tests (optional automation)
 │
 └── T11  hardening batch/aaCheck/sf* (optional v1.1)
```

## Phase map

| Phase | Tasks | Outcome |
|-------|-------|---------|
| 0 Spike | T00 | Prove CE APIs + remote constraints on real table |
| 1 Address list | T01–T04 | Full memrec inventory + edit + script + enable |
| 2 Structures | T05–T06 | Dissect dump/clone/edit |
| 3 Agent surface | T07–T09 | Python + docs + skill |
| 4 Quality | T10–T11 | Tests + optional polish |

## Critical constraints (all tasks)

1. **Main thread:** address list, structures, `Active`/AA → `synchronize` only.
2. **Payload cap:** keep request/response **&lt; ~48 KiB** (pipe buffer 65536).
3. **No** `getStructure("name")` — index only; name-scan helper required.
4. **No** `enumMemoryRegions`, bg `createMemScan`/`varscan_*`, bad AOB prot flags.
5. **No** agent `saveTable` requirement (user saves).
6. Client **timeout ≥ 120s** for enable/AOB paths.

## CE source references (local)

```
/mnt/y/Lazarus/Projects/cheat-engine-7.5/Cheat Engine/
  bin/celua.txt
  LuaMemoryRecord.pas
  LuaAddresslist.pas
  LuaStructure.pas
  LuaStructureFrm.pas
  LuaHandler.pas
```

## Repo touchpoints

| Path | Role |
|------|------|
| `ce_server.lua` | Native commands |
| `client.py` | Agent-facing helpers |
| `README.md` | Command list + crash table |
| `docs/TABLE-MIGRATE.md` | Workflow (T08) |
| `skills/ce-table-migrate/SKILL.md` | Agent playbook (T09) |
| `docs/tasks/*` | This task set |

## Status legend

Use in each task file header:

- `TODO` | `IN_PROGRESS` | `DONE` | `BLOCKED` | `WONT_DO`
