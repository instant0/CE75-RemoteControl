# T06 results — structure clone and element edit

| Field | Value |
|-------|--------|
| **Status** | DONE (code landed; restart CE to load **v1.7** for seed/rename safety) |
| **Server version** | `ce-server v1.7 (CE 7.5 st-safe)` (was v1.6 st-edit) |
| **File** | `ce_server.lua` |

## Commands shipped

| Command | Purpose |
|---------|---------|
| `stEnsureSeed` | Ensure `DO_NOT_DELETE_PLACEHOLDER` exists (empty-list crash guard) |
| `stClone <src> <dst>` | Deep-copy definition to a new global name (two-pass ChildStruct) |
| `stBegin <name>` | `beginUpdate` (batch edits) |
| `stEnd <name>` | `endUpdate` / **commit** (required before rename) |
| `stUpsertElem …` | Insert or update element at exact offset |
| `stClearElements <name>` | Destroy all elements (in-place empty; not placeholder) |
| `stSetName <old> <new>` | Rename only after commit; refuses mid-edit + protected names |

### Dissect safety (v1.7)

| Rule | Behavior |
|------|----------|
| Empty global structure list | CE crash (`list index (0) out of bounds`) — `stEnsureSeed` / auto-seed on `stClone` |
| Placeholder | `DO_NOT_DELETE_PLACEHOLDER` (legacy `UE_Seed` accepted); never clear/rename/edit |
| Clone naming | Create under `UE_CLONE_TMP_*`, fill + `endUpdate`, **then** rename to dst |
| Rename mid-edit | `ERROR: STILL_UPDATING: call stEnd before rename` |
| `tableStatus` | Includes `seed=0|1` |

### Name splitting (`stClone` / `stSetName`)

Supported forms (first match wins):

1. `src -> dst` or `old -> new`
2. `src|dst` (pipe)
3. Space-separated: longest **existing** left prefix as `src`/`old`, remainder as destination

Examples:

```text
stClone PlayerStats PlayerStats_v2
stClone FloatPlayerVariable 1.90 -> FloatPlayerVariable 1.99
stSetName PlayerStats_v2 -> PlayerStats_new
```

### `stClone` algorithm

1. Reject missing source / existing destination.
2. `createStructure(dst)` + `addToGlobalStructureList()`.
3. Pass 1 under `beginUpdate`/`endUpdate`: copy Offset, Name, Vartype, Bytesize (no ChildStruct).
4. Pass 2: for each source element with ChildStruct, resolve **same child name** via name-scan and set ChildStruct + ChildStructStart.
5. On hard copy failure: `removeFromGlobalStructureList` on the incomplete destination (source untouched).

Response:

```text
OK SRC=... DST=... ELEMS=... COPIED=... CHILD_OK=... CHILD_FAIL=...
```

**Limitation:** pass-2 links by **unchanged child names**. When renaming a family, clone children first, then parents (or accept CHILD_FAIL and `stUpsertElem` with child name).

**Size note:** T00 cloned ~20k elements in ~2 s. Prefer in-place upsert for huge structs when only a few fields change. Client timeout **≥ 120s** for large clones.

### `stUpsertElem`

**Preferred (spaces OK in names):**

```text
stUpsertElem name|offsetHex|elemName|vtypeInt|[byteSize]|[childName]|[childStart]
```

Empty `childName` clears ChildStruct. Omit optional fields to leave them unset on insert / unchanged on update (except required name/off/elemName/vtype).

**Simple space form** (single-token names):

```text
stUpsertElem StructName 10 Count 4
stUpsertElem StructName 10 Count 4 4
stUpsertElem StructName 10 ptr 6 8 ChildStruct 0
```

Offset match is **exact** (linear scan if `getElementByOffset` returns a non-equal “at least” hit).

```text
OK NAME=... OFF=10 ACTION=insert|update VTYPE=4
ERROR: CHILD_NOT_FOUND: ...
ERROR: NOT_FOUND: ...
```

### `stBegin` / `stEnd`

Tracks open begins in `_G._ue_st_updating[name]`.

```text
OK NAME=... BEGIN=1
OK NAME=... BEGIN=1 WARN=ALREADY_BEGIN
OK NAME=... BEGIN=0 ELEMS=n
OK NAME=... BEGIN=0 ELEMS=n WARN=NO_BEGIN
```

Agent should always pair begin/end for multi-upsert batches.

### `stClearElements`

Deletes elements by repeatedly `Element[0].destroy()` under begin/end (CE has no structure clear). Cap **50000** iterations.

```text
OK NAME=... DELETED=n ELEMS=0
ERROR: CLEAR_PARTIAL: deleted=n left=m
```

**Prefer** clone + edit when uncertain; clear is destructive to that definition.

### `stSetName`

```text
OK OLD=... NEW=... COMMITTED=1
ERROR: STILL_UPDATING: call stEnd before rename (commit structure first)
ERROR: PROTECTED: DO_NOT_DELETE_PLACEHOLDER
ERROR: EXISTS: ...
ERROR: NOT_FOUND: ...
```

### `stEnsureSeed`

```text
OK SEED=1 STATUS=created|present|legacy stCount=n NAME=DO_NOT_DELETE_PLACEHOLDER
```

## Not included

| Item | Reason |
|------|--------|
| `stRemoveFromGlobal` | Easy wipe of user work; delete in CE UI if needed |
| `stCloneMap` (child rename map) | Out of scope; clone children first |
| StructureFrm base address | T11 |
| autoGuess / fillFromDotNet | UE tables; can hang/crash |

## Safety

1. **Never** `getStructure("name")` — index only via `st_find_by_name`.
2. Failed clone does not delete source; incomplete dst rolled back when copy throws.
3. Main thread only (`sync_call`).
4. `_G._ue_st_clone_structure` / `_G._ue_st_find_by_name` for advanced `runScript`.

## Verify after CE restart

```bash
H=192.168.176.1; P=8000
python3 client.py --host $H --port $P --timeout 120 --cmd "getVersion"
# expect: ce-server v1.6 (CE 7.5 st-edit)

python3 client.py --host $H --port $P --timeout 120 --cmd "stDump"
# pick a SMALL structure name from dump, e.g. not the 20k-element ones
SRC='SomeSmallStruct'   # replace
DST="${SRC}_t06"

python3 client.py --host $H --port $P --timeout 120 --cmd "stClone $SRC -> $DST"
python3 client.py --host $H --port $P --timeout 60 --cmd "stGet $DST 0 20"
python3 client.py --host $H --port $P --timeout 60 --cmd "stBegin $DST"
python3 client.py --host $H --port $P --timeout 60 --cmd "stUpsertElem ${DST}|10|T06Test|4|4"
python3 client.py --host $H --port $P --timeout 60 --cmd "stEnd $DST"
python3 client.py --host $H --port $P --timeout 60 --cmd "stFind $DST"
# cleanup optional: leave clone for user to delete, or stClearElements + manual remove in CE
python3 client.py --host $H --port $P --cmd "ping"
```

**Do not** smoke-test clear/clone on production-named structs you care about without cloning first.

## Agent workflow

```text
validate elements at live base
if small drift  -> stBegin / stUpsertElem / stEnd on original
if large risk   -> stClone Name -> Name_vNew, edit clone, user deletes old later
family rename   -> clone children first, then parents
```

## Next

**T07** — client.py helpers for al*/st*
