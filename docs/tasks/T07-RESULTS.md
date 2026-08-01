# T07 results — client helpers

| Field | Value |
|-------|--------|
| **Status** | DONE |
| **File** | `client.py` |

## Shipped

- `CERemote.cmd(..., timeout=None)` per-call timeout override  
- Helpers for T02–T06: `table_status`, `al_*`, `st_*`, `aa_check`, `aob_scan`, …  
- `al_get_script` / `al_set_script` with hex chunking + abort on failure  
- `al_set_active(..., timeout=120)` default  
- Optional `al_dump_parsed()`  
- CLI `--timeout` unchanged (default 30 for back compat)

## Next

T08/T09 docs+skill (done in same batch). Live smoke = T10.
