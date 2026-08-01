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

## DON'T
- Parallel relay calls / thrash / reconnect spam
- Full-process / other-DLL scans — **gamedll + engine only** (see `scan-scope.md`)
- `enumMemoryRegions`, `createMemScan`, `varscan_*` from remote
- `getStructure("Name")` — use `stFind` / `_ue_st_find_by_name`
- Mass `Active=true`
- Log full AA scripts
- Rename structure while `stBegin` open (`stEnd` first)
- Touch/delete `DO_NOT_DELETE_PLACEHOLDER`
- Blame “process frozen” for access-log (game still runs)
- Assume remote find-what-accesses works — user CE UI or ask
