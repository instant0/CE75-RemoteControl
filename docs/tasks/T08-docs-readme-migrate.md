# T08 — Documentation: README + TABLE-MIGRATE

| Field | Value |
|-------|--------|
| **ID** | T08 |
| **Status** | DONE |
| **Phase** | 3 — Agent surface |
| **Parent** | T02–T06 (command set known) |
| **Children** | — |
| **Depends on** | T02–T06 ideally; can draft from plan earlier |
| **Blocks** | None (parallel with T07/T09) |

## Goal

Document the new remote capabilities for humans and agents: command reference, migration workflow, **what will not work**, and **crash/hang** programming rules.

## Deliverables

### 1. `docs/TABLE-MIGRATE.md` (new)

Must include:

1. **Goal** — port loaded table to new game version; user saves.  
2. **Architecture** — sync_call / main thread.  
3. **Command reference** — every `al*` / `st*` / `tableStatus` / `aaCheck` with request/response examples.  
4. **Wire formats** — TSV columns for `alDump` / `stGet`; script hex chunking.  
5. **Recommended agent algorithm** — dependency order: AA → enable → pointers → structures.  
6. **Dissect address note** — definitions need no address; validation does.  
7. **Won’t work table** — BP scripts, modals, non-AA setScript, getStructure(name), bg memscan, etc.  
8. **Crash/hang table** — copy expanded list from plan §4 + mitigations.  
9. **Timeout guidance** — 120s for Active/AOB.  
10. **Link** to `docs/tasks/` for implementers.

### 2. `README.md` updates

- Extend **Available Commands** table with new verbs (short descriptions).  
- New subsection **Table migration (address list & structures)** linking `docs/TABLE-MIGRATE.md`.  
- Expand **Dangerous APIs** with:
  - table ops without synchronize
  - synchronize + modal deadlock
  - getStructure(string)
  - oversized dump/script
  - mass `Active=true`
- Bump any version mention if server version bumped.

### 3. Cross-links

- `docs/CE75-INTEGRATION.md` — one paragraph: inventory helpers vs raw al/st commands.  
- `docs/tasks/README.md` — mark docs task; no change required if already linked.

## Acceptance criteria

- [x] `TABLE-MIGRATE.md` exists and matches **shipped** command names (update if impl drifted).
- [x] README command table includes new commands.
- [x] Crash section mentions deadlock and structure index bug.
- [x] Explicit: user saves table; agent does not need saveTable.

## Out of scope

- Skill file body (T09)
- Changing code behavior

## Files

- `docs/TABLE-MIGRATE.md` (create)
- `README.md` (edit)
- `docs/CE75-INTEGRATION.md` (small edit)

## Writing style

- Match existing README tone: tables, concrete commands, no fluff.
- Prefer copy-pasteable `python client.py --cmd "..."` examples.
