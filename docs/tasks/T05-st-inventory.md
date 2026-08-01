# T05 — Structure inventory: `stDump`, `stGet`, `stFind`

| Field | Value |
|-------|--------|
| **ID** | T05 |
| **Status** | TODO |
| **Phase** | 2 — Dissect structures read path |
| **Parent** | T01 |
| **Children** | T06 |
| **Depends on** | T01 (T00 spike findings on structure API) |
| **Blocks** | T06, T09 structure validation steps |

## Goal

Expose read-only native commands for the **global dissect structure list** (saved with the cheat table): list all structures and dump elements for one structure by **name**.

## Context

### Dissect definition vs window

| Object | Needs live address? | Saved in .CT? |
|--------|---------------------|---------------|
| Global `Structure` (`getStructure(i)`) | **No** | Yes |
| `StructureFrm` open window | **Yes** (column base) | No |

Migration cares first about **definitions**. Open-window commands are T11 optional.

### Critical CE pitfall

`getStructure(i)` is **index only** (`LuaStructure.pas`). Passing a string name coerces to integer **0** and can destroy/wrong-edit the first structure (see UnrealEdit75 `CE75-DISSECT-CRASH.md` pattern). **Always** scan by `.Name`.

### APIs

- `getStructureCount()`, `getStructure(index)`
- Structure: `Name`, `Size`, `Count`, `Element[i]` / `getElement`, `getElementByOffset`
- Element: `Offset`, `Name`, `Vartype`, `Bytesize`, `ChildStruct`, `ChildStructStart`

## Commands to implement

### `stDump`

**Thread:** `sync_call`

```text
IDX\tNAME\tSIZE\tELEMS
0\tPlayerStats\t64\t12
...
```

Scrub names. If empty list: header only or `COUNT=0`.

### `stFind <name>`

```text
OK NAME=... IDX=... SIZE=... ELEMS=...
```

or `ERROR: NOT_FOUND`

### `stGet <name>`

```text
OK NAME=... SIZE=... ELEMS=...
IDX\tOFF\tNAME\tVTYPE\tBYTES\tCHILD\tCHILDSTART
0\t0\tvtable\t6\t8\t\t0
...
```

- `CHILD` = child structure **name** or empty.
- Use `pcall` when reading ChildStruct.
- Pagination if needed: `stGet <name> [elemOffset] [elemLimit]` — only if large structs exceed MAX_RESP.

## Implementation notes

Reuse `st_find_by_name` from T01.

```lua
local function st_dump_elements(s, elemOff, elemLimit)
  ...
end
```

## Acceptance criteria

- [ ] `stDump` lists all ~15–20 structures under size cap.
- [ ] `stFind` / `stGet` by exact name.
- [ ] No code path calls `getStructure(nameString)`.
- [ ] Missing name → NOT_FOUND; server remains healthy.
- [ ] help updated.

## Out of scope

- Clone / mutate (T06)
- StructureFrm (T11)
- RTTI / autoGuess fill (optional later; can crash or be slow)

## Crash / hang awareness

| Risk | Mitigation |
|------|------------|
| Index/name confusion | name scan only |
| ChildStruct nil | pcall |
| Empty global list | return COUNT=0; do not “fix” |

## Files

- `ce_server.lua`

## Manual test

```bash
python client.py --cmd "stDump"
python client.py --cmd "stFind PlayerStats"
python client.py --cmd "stGet PlayerStats"
```

## Migration note (for T09)

Structure definitions are portable templates. To **validate** against a new build, agent needs a live base address from a healthy memrec / UE helper, then `readQword(base+off)` compares — not part of T05 commands but document in skill.
