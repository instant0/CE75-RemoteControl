# CE relay

Default: `192.168.176.1:8000`

## DO
- One command at a time; wait for response
- One `ping` when needed
- Prefer native cmds: `read*`, `AOBScan`, `GroupScan`, `al*`, `st*`
- Timeout ≥ 120 for enable / AOB / GroupScan / large st*
- `pcall` + nil guards + bounded loops in Lua
- `stEnsureSeed` if `stCount=0`
- AA: enable one script at a time; `aaCheck` first
- Use `client.py` / `./ce.sh` only (flock + denylist on `CERemote.cmd`)
- **Restart pipe server:** re-Execute `ce_server.lua` (v1.8.4+); or `shutdown` then re-run; **not** “close Lua console”

## Client guardrails (`client.py`)
- **Flock** `/tmp/ue-scan-ce-relay.client.lock` — second concurrent process waits (or `CE_RELAY_LOCK_NOWAIT=1` fails)
- **Denylist** in `runScript`/`runScriptSafe`: `createMemScan`, `varscan_*`, `enumMemoryRegions`
- **Pace** default `CE_RELAY_MIN_INTERVAL=0.15` s between commands (set `0` to disable)

## DON'T
- Parallel relay calls / thrash / reconnect spam
- Full-process / other-DLL scans — **gamedll + engine only** (see `scan-scope.md`)
- **Global AOB of common small ints** (100/1000/stack counts) — see `scan-scope.md` HARD RULE
- `enumMemoryRegions`, `createMemScan`, `varscan_*` from remote (client blocks in runScript*)
- `getStructure("Name")` — use `stFind` / `_ue_st_find_by_name`
- Mass `Active=true`
- Log full AA scripts
- Rename structure while `stBegin` open (`stEnd` first)
- Touch/delete `DO_NOT_DELETE_PLACEHOLDER`
- Blame “process frozen” for access-log (game still runs)
- Assume remote find-what-accesses works — user CE UI or ask
