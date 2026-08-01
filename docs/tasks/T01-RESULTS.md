# T01 results — `sync_call` + server hardening

| Field | Value |
|-------|--------|
| **Status** | DONE (code landed; live re-load required) |
| **Date** | 2026-08-01 |
| **Server version** | `ce-server v1.1 (CE 7.5 table-foundation)` |
| **Primary file** | `ce_server.lua` |

## What was implemented

| Item | Detail |
|------|--------|
| `sync_call(fn)` | Main-thread marshal via `synchronize` + inner `pcall` → `{ok,data\|err}` |
| `ok_data` | Converts pack to data or `ERROR: SYNC: ...` |
| `scrub` / `fit_response` | Strip control chars; refuse responses &gt; **48000** bytes |
| `al_find_by_id` | `getAddressList` + `getMemoryRecordByID` (main-thread only) |
| `st_find_by_name` | Index scan of `getStructure(i)` by `.Name` (**never** string→index) |
| `_G._ue_script_stage` | Reserved for T04 chunked script upload |
| Globals for later tasks | `_G._ue_sync_call`, `_ue_al_find_by_id`, `_ue_st_find_by_name`, `_ue_scrub`, `_ue_fit_response` |
| **`tableStatus`** | Live process/pid/alCount/stCount/ceVersion/server |
| **`debugSync`** | `OK mainthread=1` |
| **`debugSyncError`** | Deliberate error → `ERROR: SYNC: ...` without killing pipe loop |
| **AOBScan wildcards** | Pattern accepts `*` / `**` (T00 bug: old regex `[0-9A-Fa-f%s]+` rejected DL2 AOBs) |
| Version bump | `v1.0` → **`v1.1`** |
| help | Updated verb list |

## Out of scope (later tasks)

- `alDump` / mutations / scripts (T02–T04)
- Structure dump/clone (T05–T06)
- client.py helpers (T07)

## Live verification (after user reloads `ce_server.lua`)

Re-run server script in CE (close Lua Engine tab first if “already running”), then:

```bash
python3 client.py --host 192.168.176.1 --port 8000 --timeout 60 --cmd "getVersion"
# expect: ce-server v1.1 (CE 7.5 table-foundation)

python3 client.py --host 192.168.176.1 --port 8000 --timeout 60 --cmd "debugSync"
# expect: OK mainthread=1

python3 client.py --host 192.168.176.1 --port 8000 --timeout 60 --cmd "debugSyncError"
# expect: ERROR: SYNC: deliberate sync error

python3 client.py --host 192.168.176.1 --port 8000 --timeout 60 --cmd "tableStatus"
# expect: OK process=DyingLightGame... alCount=93 stCount=...

python3 client.py --host 192.168.176.1 --port 8000 --timeout 60 --cmd "ping"
# still pong after error command

# Wildcard AOB (was Unknown command on v1.0):
python3 client.py --host 192.168.176.1 --port 8000 --timeout 120 \
  --cmd "AOBScan 08 ** ** ** ** ** ** 00 00 00 00 80 3E 00 00 80 3E"
```

## Rename memory entries (product question)

**Yes — renaming is in scope for the table-edit path**, not as a separate feature:

| When | How |
|------|-----|
| After T03 | `alSetDesc <id> <new text>` |
| Today (runScript) | `synchronize(function() local mr=getAddressList().getMemoryRecordByID(78); mr.Description="..."; return mr.Description end)` |

Renaming **does not** retune AOBs; it only changes the display string. Scripts that look up by **exact description** (this DL2 table does: `getMemoryRecordByDescription('[Cheat][1.93] Enable playervariables editing')`) **must be updated in lockstep** if the description changes.

## Skills added

| Path | Tag |
|------|-----|
| `skills/ce-table-remote/SKILL.md` | CE remote table foundation |
| `skills/game/DyingLight2/player-variables/SKILL.md` | DL2 playerStat AOB / EXPR rows |

## Next

**T02** — `alDump` / `alGet` / `alResolve` using `sync_call` + `al_find_by_id`.
