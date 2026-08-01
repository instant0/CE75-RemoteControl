# Non-goals, remote limits, and crash catalogue

Product constraints and CE hazards for remote table work.  
(Completed implementer task checklists were removed — the server works; keep lasting risks here.)

## Product non-goals (all tasks)

| Non-goal | Reason |
|----------|--------|
| Agent `saveTable` / `loadTable` pipeline | User saves when table works |
| Offline generation of a full new `.CT` file as primary engine | CE already holds scripts, hierarchy, structs; live rebind is correct model. **Surgical** offline `.CT` XML edits are allowed when requested — see [CE-TABLE-OFFLINE-EDIT.md](CE-TABLE-OFFLINE-EDIT.md) |
| Perfect automatic understanding of all AA scripts | Semantic / disassembly judgment |
| Implementing breakpoint push-over-TCP in v1 | See `docs/BREAKPOINT_STRATEGY.md` |
| Editing hotkeys, trainer forms, embedded table files | Out of migration path |

## What will NOT work (remote reality)

| Area | Why | What to do instead |
|------|-----|---------------------|
| BP-only instance discovery | Debugger events are not pulled by current pipe protocol | Manual BP / later poll design; AA+registersymbol scripts OK |
| `mr.Script = text` on non-AA rows | CE only sets if `AutoAssemblerData.script <> nil` | Only edit existing AA entries |
| `getStructure("Name")` | Index coercion → wrong struct / wipe risk | `stFind` / name scan |
| Native structure clone API | Does not exist | `stClone` element copy (T06) |
| `GetTableXMLAsText` from Lua | Not exposed in celua | `alDump` / `stDump` |
| Safe bg `createMemScan` / `varscan_*` | Scan engine / UI thread issues | Native `AOBScan`; targeted reads |
| `enumMemoryRegions` | Known crash/bad state | `enumModules` |
| Multi-return values via raw `runScript` | Server `tostring(result)` | Native packed text commands |
| Guaranteed no modal on AA failure | CE may dialog | `aaCheck`; user present; timeouts |
| Structure **definition** auto-bound to one address | Definitions are layouts only | Validate with separate live base; optional StructureFrm (T11) |

## Crash / hang / relay issues to program around

### A. Confirmed / documented in this repo

| Hazard | Effect | Required mitigation |
|--------|--------|---------------------|
| `enumMemoryRegions()` | Crash / bad state | Never call from server handlers or skill |
| `createMemScan` / `Memscan_firstScan` from server thread | Hang / corrupt scans | Ban; use native `AOBScan` |
| `varscan_*` | Same | Ban |
| `AOBScan(..., "w")` bad prot | Crash | Native AOB only or numeric prot |
| Long AOB via raw `runScript` | Timeout / stuck | Native `AOBScan` + high client timeout |
| Unbounded walks / nil in `string.format` | Error / hang | Caps; `or 0`; pcall |
| Missing plugin functions | Error | `type(fn)=="function"` |

### B. Table-migration specific

| Hazard | Effect | Required mitigation |
|--------|--------|---------------------|
| Address list / structure / `Active` from bg **without** `synchronize` | VCL crash / corruption | All `al*`/`st*`/`aaCheck`/`Active` via `sync_call` (T01) |
| `synchronize` + **modal dialog** on main thread | **Deadlock** (server waits forever) | `aaCheck` first; avoid modal scripts; client timeout; user can click through |
| Oversized response (all scripts in one dump) | Pipe/write failure / client hang | Metadata dump only; chunk scripts; MAX_RESP ~48k |
| Oversized request (full script one line) | Same | Chunked script set (T04) |
| `getStructure` with name string | Wrong index / mass wipe | Name-scan helper only |
| **Empty global structure list** | Dissect TreeView / callbacks: `list index (0) out of bounds` | Always keep ≥1 struct; `stEnsureSeed` → `DO_NOT_DELETE_PLACEHOLDER` (CE75-DISSECT-CRASH) |
| **Rename structure while editing** | Rename fails / UI corrupt mid-`beginUpdate` | `stEnd` (commit) **before** `stSetName`; clone uses temp name then renames after fill |
| Mass `Active=true` | Inject failures, reinterpret storms, freezes | One-by-one enables in skill |
| AA enable failure mid-inject | Game/CE unstable | Soft disable; don’t batch enables |
| Client timeout 30s default | False failures | 120s for Active/AOB paths |
| Nested `synchronize` | Undefined / hang | Only server sync_call; agents don’t call synchronize via runScript nested with server ops carelessly |
| Logging full scripts to CE console | UI freeze | Log command + id only |

### C. Relay / process lifecycle

| Hazard | Effect | Mitigation |
|--------|--------|------------|
| Client disconnect mid-command | Pipe destroy/recreate | Existing server loop; staging abort (T04) |
| Re-execute `ce_server.lua` while thread live | “already running” | Document restart: close Lua Engine tab |
| Game killed during AA | CE error | pcall; ping health check |

## CE API quick facts (for implementers)

```text
getAddressList() -> AddressList
  Count, getMemoryRecord(i), getMemoryRecordByID(id),
  getMemoryRecordByDescription(desc), createMemoryRecord()

MemoryRecord
  ID, Description, Address, OffsetCount, Offset[i], OffsetText[i],
  CurrentAddress, Type/VarType, Value, Active, Script (AA only),
  Parent, setAddress(expr[, offsetTable]), disableWithoutExecute()

getStructureCount() / getStructure(index)  -- INDEX ONLY
createStructure(name); addToGlobalStructureList()
beginUpdate/endUpdate; addElement(); Element fields...
-- Empty list crash: keep DO_NOT_DELETE_PLACEHOLDER (stEnsureSeed)
-- Rename only after endUpdate / stEnd (not mid-edit)

autoAssemble(text) / autoAssembleCheck(text, enable, targetself)
registerSymbol(name, address, donotsave?)
synchronize(fn, ...)
AOBScan(pattern) -> StringList (destroy after use)
```

## Size budget

| Item | Budget |
|------|--------|
| CE pipe buffer | 65536 |
| Soft max response | 48000 bytes |
| Script chunk payload | ~8–16 KiB raw per chunk before hex |

## Dependency reminder

```text
T00 spike
  → T01 sync/hardening
      → T02 al read → T03 al write → T04 script/active
      → T05 st read → T06 st clone/edit
  → T07 client → T09 skill
  → T08 docs (parallel)
  → T10 smoke
  → T11 optional
```

## Related repo docs

- `README.md` — architecture, dangerous APIs  
- `docs/BREAKPOINT_STRATEGY.md` — debugger limitations  
- `docs/CE75-INTEGRATION.md` — GEngine / inventory helpers  
- `SOLUTION.md` — createThread analysis  
- CE source under `/mnt/y/Lazarus/Projects/cheat-engine-7.5/Cheat Engine/`  
