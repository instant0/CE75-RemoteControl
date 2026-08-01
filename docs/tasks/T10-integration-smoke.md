# T10 — Integration smoke tests / helper script

| Field | Value |
|-------|--------|
| **ID** | T10 |
| **Status** | TODO |
| **Phase** | 4 — Quality |
| **Parent** | T07 |
| **Children** | — |
| **Depends on** | T02–T07 (minimum T02+T01 for dry structure) |
| **Blocks** | None |

## Goal

Provide a **repeatable smoke script** that validates migration commands against a live CE session when available, and fails soft when CE is down (so CI without Windows CE doesn’t hard-break).

## Context

- Environment often: Linux/WSL agent + Windows CE — tests may be manual.
- Project prefers stdlib-only Python.
- Do not require destroying user table data: use disposable description suffix / clone name with timestamp.

## Deliverable

### `helper/smoke_table_migrate.py`

Behavior:

```text
--host --port --timeout
1. ping
2. tableStatus
3. alDump (print count / first 3 lines)
4. if --id N: alGet, alResolve
5. if --mutate-safe: alSetDesc id with temporary suffix then restore original
6. stDump (print count)
7. if --st-clone-src NAME: stClone to NAME_smoke_<ts>, stGet, optional leave clone (print name for user delete)
8. Exit 0 if required steps pass; exit 1 on ERROR
```

Flags:

| Flag | Default | Meaning |
|------|---------|---------|
| `--mutate-safe` | off | Allow desc restore test |
| `--st-clone-src` | none | Optional clone test |
| `--id` | none | Memrec id for get/resolve |

### Documentation

- Short “How to smoke test” in `docs/TABLE-MIGRATE.md` (T08 may add placeholder; finish here).

## Acceptance criteria

- [ ] Script runs against down server → clear connection error, exit ≠ 0.
- [ ] Script runs against live CE with table → prints counts, exit 0.
- [ ] Mutate-safe path restores description.
- [ ] Does not call banned APIs.
- [ ] No saveTable.

## Out of scope

- Full pytest suite in CI without CE
- Performance benchmarks

## Crash / hang awareness

| Risk | Mitigation |
|------|------------|
| Active enable in smoke | **Do not** enable AA in default smoke |
| Orphan clones | Unique names; print cleanup hint |

## Files

- `helper/smoke_table_migrate.py`
- `docs/TABLE-MIGRATE.md` (smoke section)

## Manual test

```bash
python helper/smoke_table_migrate.py --timeout 60
python helper/smoke_table_migrate.py --timeout 60 --id 5 --mutate-safe
```
