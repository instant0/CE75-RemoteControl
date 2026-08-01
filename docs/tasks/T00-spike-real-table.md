# T00 — Spike: real table + remote CE APIs

| Field | Value |
|-------|--------|
| **ID** | T00 |
| **Status** | TODO |
| **Phase** | 0 — Spike |
| **Parent** | — (root) |
| **Children** | T01, T10 (optional) |
| **Depends on** | None |
| **Blocks** | T01–T09 (recommended gate) |

## Goal

Prove, on a **real** loaded table (~100 address entries, ~15–20 dissect structures), that the CE 7.5 Lua APIs we plan to wrap work over the **existing** remote (`runScript` + `synchronize`) without killing `ce_server.lua` or the relay.

Do **not** productize commands here. Capture findings that adjust later tasks.

## Context

- Remote architecture: WSL `client.py` → TCP → `windows_relay.py` → named pipe → `ce_server.lua` on `createThread` background thread.
- Table/UI objects are **not** proven safe from the background thread; CE documents `synchronize(fn)` for main-thread work.
- Product goal later: port table to a **new game build** by editing the **loaded** table; user saves.

## Preconditions

- [ ] CE 7.5 attached to target process (or at least table loaded).
- [ ] Working `.CT` loaded (the large one).
- [ ] `ce_server.lua` running, relay up, `ping` → `pong`.
- [ ] Client timeout available (`--timeout 120`).

## Work items

### 1. Main-thread dump of address list

Via `runScript` (escape hatch):

```lua
synchronize(function()
  local al = getAddressList()
  local n = al.Count
  local lines = {}
  local max = math.min(n, 200)
  for i = 0, max - 1 do
    local mr = al.getMemoryRecord(i)
    if mr then
      local desc = (mr.Description or ""):gsub("[\t\r\n]", " ")
      local addr = mr.Address or ""
      local vt = mr.Type or -1
      local act = mr.Active and 1 or 0
      local oc = mr.OffsetCount or 0
      local sid = mr.ID or -1
      local hasScript = 0
      local slen = 0
      local ok, scr = pcall(function() return mr.Script end)
      if ok and scr and scr ~= "" then hasScript = 1; slen = #scr end
      lines[#lines+1] = string.format("%d\t%d\t%s\t%s\t%d\t%d\t%d\t%d",
        sid, i, desc, tostring(addr):gsub("[\t\r\n]"," "), vt, act, oc, hasScript)
    end
  end
  return string.format("COUNT=%d\n%s", n, table.concat(lines, "\n"))
end)
```

**Record:** total count, response size bytes, time, any errors.

### 2. Script read size

- Pick one AA entry with `hasScript=1`.
- Measure `#mr.Script`.
- Confirm whether a single remote response can hold it (&lt;48 KiB target). If not, chunking (T04) is mandatory.

### 3. Pointer setAddress round-trip

CE behavior (`LuaMemoryRecord.pas`): `setAddress` **clears offsets** unless the offset table is passed as 2nd arg.

```lua
synchronize(function()
  local mr = getAddressList().getMemoryRecordByID(<id>)
  local base = mr.Address
  local offs = {}
  for i = 0, mr.OffsetCount - 1 do offs[i+1] = mr.Offset[i] end
  mr.setAddress(base, offs)  -- or property form if used
  return mr.OffsetCount
end)
```

**Record:** API form that works (`setAddress` vs `.Address` + `OffsetCount`/`Offset[]`).

### 4. Structure name lookup + clone feasibility

```lua
-- NEVER getStructure("MyName") -- coerces to index 0
local function findStruct(name)
  for i = 0, getStructureCount()-1 do
    local s = getStructure(i)
    if s and s.Name == name then return s, i end
  end
end
```

- Dump structure names + element counts.
- Manually clone one small structure: `createStructure`, copy elements, `addToGlobalStructureList`.
- **Record:** ChildStruct handling difficulty; element delete API presence/absence.

### 5. Active / AA enable risk

- Prefer **not** enabling a destructive inject script on a production save.
- If a harmless AA exists: `autoAssembleCheck` then `Active=true` inside `synchronize`.
- **Record:** modal dialogs? deadlock? time to return? failure string availability?

### 6. Crash-control negatives (do not leave enabled)

Confirm these remain banned (expect problems if run from bg without care):

- `enumMemoryRegions`
- `createMemScan` from server thread
- `AOBScan` with bad protection string `"w"`

## Deliverable

Write findings into this file section **Spike results** (or `docs/tasks/T00-RESULTS.md`):

| Probe | Result | Implication for later tasks |
|-------|--------|------------------------------|
| al dump size | | |
| max script len | | |
| setAddress API | | |
| st clone | | |
| Active enable | | |
| synchronize issues | | |

## Acceptance criteria

- [ ] `al`-style metadata dump for full table completes; server still `ping`s after.
- [ ] At least one script length measured; chunking decision documented.
- [ ] Pointer offset preservation method documented with working snippet.
- [ ] Structure find-by-name + one clone demonstrated or blocker filed.
- [ ] Enable path risk notes written (dialogs/deadlock/timeout).
- [ ] No permanent corruption of user’s table intent (revert experimental clone names if needed). **User** saves if they want; spike may leave temporary structs—document cleanup.

## Out of scope

- Native command implementation (T01+)
- Agent skill
- saveTable / loadTable automation

## Crash / hang awareness

| Risk | Mitigation in spike |
|------|---------------------|
| Response too large | Cap loop; metadata only first |
| synchronize + modal | Have user ready to dismiss; use short timeout tests |
| Wrong `getStructure` index | Name scan only |
| AA inject into game | Use safe script or skip enable |

## Files

- Notes only under `docs/tasks/` (this file or T00-RESULTS).
- May use ad-hoc `helper/spike_table_migrate.py` (optional; delete or keep as non-production).
