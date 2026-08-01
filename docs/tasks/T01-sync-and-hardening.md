# T01 — `sync_call` primitive + server hardening

| Field | Value |
|-------|--------|
| **ID** | T01 |
| **Status** | DONE (see T01-RESULTS.md) |
| **Phase** | 1 — Foundation |
| **Parent** | T00 (recommended) |
| **Children** | T02, T05 (via shared helpers) |
| **Depends on** | T00 preferred; can start with T00 knowledge |
| **Blocks** | T02–T06 |

## Goal

Add reusable server-side primitives in `ce_server.lua` so all future address-list and structure commands:

1. Run table/UI/AA work on the **main thread** via `synchronize`.
2. Never take down the pipe server loop on Lua errors.
3. Enforce **response size** limits.
4. Share helpers: find memrec by ID, find structure by name, safe string scrubbing.

## Context

- `ce_server.lua` runs inside `createThread` (background). CE: “All CE functions are threadsafe” is **not** sufficient for VCL address list / structure list mutations—CE75 and autorun scripts use `synchronize` for UI.
- `process_command` is already wrapped in `pcall` at the accept loop; handlers must still be defensive.
- `PIPE_BUFFER = 65536` — treat **48 KiB** as soft max for a single response body.
- Version string today: `ce-server v1.0 (CE 7.5)` → bump when shipping any of T02+.

## Implementation requirements

### 1. `sync_call(fn) -> table`

Pattern (adjust to CE Lua 5.1 realities):

```lua
local MAX_RESP = 48000

local function sync_call(fn)
  local packed = synchronize(function()
    local ok, result = pcall(fn)
    if not ok then
      return { ok = false, err = tostring(result) }
    end
    return { ok = true, data = result }
  end)
  -- synchronize failure / nil
  if type(packed) ~= "table" then
    return { ok = false, err = "synchronize returned non-table" }
  end
  return packed
end

local function ok_data(packed)
  if not packed.ok then
    return nil, "ERROR: SYNC: " .. tostring(packed.err)
  end
  return packed.data
end
```

**Note:** Nested `pcall` inside `synchronize` avoids main-thread errors killing the sync callback opaquely.

### 2. Response helpers

```lua
local function scrub(s)
  s = tostring(s or "")
  return (s:gsub("[\r\n\t]", " "))
end

local function fit_response(s)
  s = tostring(s or "")
  if #s > MAX_RESP then
    return "ERROR: RESPONSE_TOO_LARGE: " .. tostring(#s)
  end
  return s
end
```

### 3. Lookup helpers (main-thread only; call only inside `sync_call`)

```lua
local function al_find_by_id(id)
  local al = getAddressList()
  local mr = al.getMemoryRecordByID(id)
  return al, mr
end

local function st_find_by_name(name)
  local n = getStructureCount()
  for i = 0, n - 1 do
    local s = getStructure(i)  -- INDEX only
    if s and s.Name == name then return s, i end
  end
  return nil, nil
end
```

### 4. Command registration style

- Keep existing commands unchanged in behavior.
- New commands added in later tasks call `sync_call`.
- Update `help` string incrementally per task **or** once in T08; minimum: document in code comments in T01.

### 5. Script staging table (prepare for T04)

```lua
if not _G._ue_script_stage then _G._ue_script_stage = {} end
-- id -> { total=N, parts={}, received=0 }
```

No public commands yet; just ensure `_G` namespace is reserved.

## Acceptance criteria

- [ ] `sync_call` used by at least one smoke command **or** unit-tested via temporary `debugSync` command that returns `ok` from main thread (remove or keep as `tableStatus` precursor).
- [ ] Suggested smoke: `tableStatus` early version:

  `process\talCount\tstCount` via sync.

  If preferred, defer full `tableStatus` to T02 but still land `sync_call` + helpers.

- [ ] Helpers do not call `getStructure` with a string name.
- [ ] `MAX_RESP` / `fit_response` exist and are used by any new response path introduced here.
- [ ] Background loop still serves `ping` after a deliberate error inside `sync_call` fn.

## Out of scope

- Full `alDump` (T02)
- Script chunk protocol (T04)
- Structure clone (T06)

## Crash / hang awareness

| Risk | Mitigation |
|------|------------|
| `synchronize` while main thread in modal dialog | Document; client timeouts; avoid enabling AA here |
| Error in sync callback | Inner `pcall` → `{ok=false,err=...}` |
| Helper used from bg without sync | Code comment: “main thread only” |

## Files to modify

- `ce_server.lua` (primary)

## Tests

```bash
python client.py --cmd "ping"
# if debug/tableStatus added:
python client.py --cmd "tableStatus"
# force error path if you add debugSyncError:
# still ping after
```

## References

- CE: `celua.txt` → `synchronize`, `getAddressList`, `getStructureCount`
- Repo: `README.md` Dangerous APIs; `SOLUTION.md` createThread notes
- Plan: foundation for all table ops
