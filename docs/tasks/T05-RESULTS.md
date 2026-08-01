# T05 results — structure inventory

| Field | Value |
|-------|--------|
| **Status** | DONE (code landed; restart CE to load **v1.5**) |
| **Server version** | `ce-server v1.5 (CE 7.5 st-inventory)` |
| **File** | `ce_server.lua` |

## Commands shipped

| Command | Purpose |
|---------|---------|
| `stDump` | List all global dissect structures (index, name, size, element count) |
| `stFind <name>` | Lookup one structure by **exact** name |
| `stGet <name> [elemOff] [elemLimit]` | Dump elements; default `elemOff=0`, `elemLimit=500` |

### Wire examples

```text
COUNT=18
IDX	NAME	SIZE	ELEMS
0	PlayerStats	64	12
...

OK NAME=PlayerStats IDX=0 SIZE=64 ELEMS=12

OK NAME=PlayerStats IDX=0 SIZE=64 ELEMS=12 ELEMOFF=0 ELEMLIMIT=500
IDX	OFF	NAME	VTYPE	BYTES	CHILD	CHILDSTART
0	0	vtable	6	8		0
1	8	health	4	4		0
...

ERROR: NOT_FOUND: NoSuchStruct
ERROR: EMPTY_NAME
```

### `stGet` pagination

- Default window: **500** elements (`DEFAULT_ST_ELEM_LIMIT`).
- Explicit: `stGet BigStruct 0 200` then `stGet BigStruct 200 200`.
- Name resolution: try **full rest of line** as exact name first; if not found and rest ends with two integers, strip them and retry (supports names that contain spaces).

### Element columns

| Column | Source |
|--------|--------|
| `IDX` | Element index |
| `OFF` | `Offset` (hex) |
| `NAME` | Element name (truncated) |
| `VTYPE` | `Vartype` / `Type` |
| `BYTES` | `Bytesize` |
| `CHILD` | Child structure **name** (via pcall; empty if none) |
| `CHILDSTART` | `ChildStructStart` |

## Safety (critical)

1. **Never** `getStructure("name")` — CE coerces string → index **0** (wipe risk).
2. All lookups use `st_find_by_name` → `getStructure(i)` **index only**.
3. Exposed as `_G._ue_st_find_by_name` for `runScript` / advanced scripts.
4. Definitions only — no live base address required (open StructureFrm windows are T11).
5. Main thread only (`sync_call`).

## Not included

- Clone / rename / element upsert (T06)
- StructureFrm open-window commands (T11)
- RTTI / autoGuess fill

## Verify after CE restart

```bash
H=192.168.176.1; P=8000
python3 client.py --host $H --port $P --timeout 60 --cmd "getVersion"
# expect: ce-server v1.5 (CE 7.5 st-inventory)

python3 client.py --host $H --port $P --timeout 60 --cmd "stDump"
python3 client.py --host $H --port $P --timeout 60 --cmd "stFind PlayerStats"
# use a real name from stDump if PlayerStats is absent
python3 client.py --host $H --port $P --timeout 60 --cmd "stGet PlayerStats"
python3 client.py --host $H --port $P --timeout 60 --cmd "stFind ___no_such_struct___"
# expect ERROR: NOT_FOUND
python3 client.py --host $H --port $P --cmd "ping"
```

## Migration note

Structure definitions are portable templates. Validating fields against a new build needs a live base from a healthy memrec / UE helper, then `readQword(base+off)` — document further in T09 skill.

## Next

**T06** — structure clone + element upsert / begin-end update
