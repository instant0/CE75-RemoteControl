# T06 — Structure clone and element edit

| Field | Value |
|-------|--------|
| **ID** | T06 |
| **Status** | DONE (see T06-RESULTS.md) |
| **Phase** | 2 — Dissect structures write path |
| **Parent** | T05 |
| **Children** | T09 structure port steps |
| **Depends on** | T01, T05 |
| **Blocks** | T09 structure half of migration |

## Goal

Support safe porting of ~15–20 dissect definitions:

1. **Clone** an existing structure to a new name (preferred when unsure).
2. **Edit** elements (upsert by offset, clear/rebuild, begin/end update).
3. Never wipe the entire global list; never `getStructure("string")`.

## Context

- No CE API `structure:clone()`. Implement element copy.
- `createStructure(name)` then `addToGlobalStructureList()`.
- `beginUpdate` / `endUpdate` for batch speed.
- ChildStruct is an object reference: **two-pass clone** when children exist.
- Product rule: if in-place edit is risky → clone `Name` → `Name_vNew` → fix clone; user deletes old later.
- Definitions do **not** require a process address; validation is agent-side with memory reads.

## Commands to implement

### `stClone <srcName> <dstName>`

**Algorithm:**

```text
1. src = find(srcName); if not src ERROR NOT_FOUND
2. if find(dstName) ERROR EXISTS
3. dst = createStructure(dstName); dst.addToGlobalStructureList()
4. dst.beginUpdate()
5. for i = 0 .. src.Count-1:
     e = src.getElement(i)
     ne = dst.addElement()
     ne.Offset = e.Offset
     ne.Name = e.Name
     ne.Vartype = e.Vartype
     if bytesize writable: ne.Bytesize = e.Bytesize
     -- skip ChildStruct in pass 1
6. dst.endUpdate()
7. Pass 2: for each element index where src had ChildStruct:
     resolve child by ChildStruct.Name (same name in global list)
     set ne.ChildStruct, ne.ChildStructStart
8. Return OK SRC=... DST=... ELEMS=...
```

**Batch rename note:** If cloning a whole family to new names, agent should clone children first, then parents (or pass-2 map). Document limitation: pass-2 uses **same child name** unless extended later with `stCloneMap` (out of scope unless easy).

### `stBegin <name>` / `stEnd <name>`

- `beginUpdate` / `endUpdate` on found structure.
- ERROR if not found.
- Unbalanced begin is agent error; optional `_G._ue_st_updating[name]=true` warn on second begin.

### `stUpsertElem <name> <offsetHex> <elemName> <vtypeInt> [byteSize] [childName] [childStart]`

- Find element by offset (`getElementByOffset` careful: CE returns element where offset is **at least** requested — verify equality).
- If exact offset exists: update fields.
- Else `addElement()` and set fields.
- `childName` empty = no child.
- Must run under begin/end for multi-updates when agent batches (agent responsibility).

Response: `OK NAME=... OFF=... ACTION=insert|update`

### `stClearElements <name>`

**Problem:** CE may not expose “delete all elements” cleanly.

**Options (pick during impl using T00 findings):**

A. If element destroy exists: delete from end to start.  
B. Else: create empty temp, swap names, remove old from global list (dangerous).  
C. Else: document `stClearElements` as “clone empty + agent uses new name” only.

**Minimum viable:** document and implement the safest option that works in spike. Prefer A or “rebuild via clone empty structure + rename” only with explicit `stReplaceFromClone` flow.

If clear is too dangerous for v1:

- Implement `stClone` + `stUpsertElem` only.
- Mark `stClearElements` as WONT_DO with alternative: clone to new name and only add needed elems (start from full clone then overwrite).

### `stSetName <oldName> <newName>`

- Rename if `newName` free.
- Response `OK`

### Optional: `stRemoveFromGlobal <name>`

**Default: do not implement in v1** (easy to wipe user’s work). If implemented, require exact name match and refuse known placeholder names (`DO_NOT_DELETE_PLACEHOLDER`, `UE_Seed`).

## Acceptance criteria

- [x] `stClone` produces independent structure visible in CE structure list with matching element count/offsets/names/types for non-child fields.
- [x] ChildStruct links preserved when child names still exist.
- [x] `stUpsertElem` can fix one offset’s name/type.
- [x] Failed clone does not delete source.
- [x] No string passed to `getStructure`.
- [x] help updated.

## Out of scope

- autoGuess / fillFromDotNet (game is UE, not .NET)
- Open StructureFrm base address (T11)
- Automatic layout discovery from UE reflection (separate skills)

## Crash / hang awareness

| Risk | Mitigation |
|------|------------|
| Wiping global list | No mass delete; no getStructure(name) |
| Partial clone on error | pcall; leave dst incomplete but named `_PARTIAL`? better rollback: removeFromGlobal if add failed mid-way only if safe |
| Child cycles | Cap pass-2; pcall |
| beginUpdate without end | skill tells agent to always end; server stEnd |

## Files

- `ce_server.lua`

## Manual test

```bash
python client.py --cmd "stGet MyStruct"
python client.py --cmd "stClone MyStruct MyStruct_v2"
python client.py --cmd "stGet MyStruct_v2"
python client.py --cmd "stBegin MyStruct_v2"
python client.py --cmd "stUpsertElem MyStruct_v2 10 Count 4"
python client.py --cmd "stEnd MyStruct_v2"
```

## Agent workflow (T09)

```text
validate elements at live base
if small drift -> stBegin/Upsert/End on original
if large uncertainty -> stClone then edit clone
```
