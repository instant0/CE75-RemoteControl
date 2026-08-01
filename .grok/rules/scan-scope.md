# Scan scope — gamedll / engine only

**STICK TO SCANNING IN GAMEDLL/ENGINE AND STAY AWAY FROM THE REST.**

Everything useful so far lives in those two modules. Full-process / other-DLL scans are out of scope.

## HARD RULE — AOB order + value / count hunts (tattoo)

**AOB is sometimes the right tool** (code patterns, script retune, gamedll/engine fingerprints).  
**Not every time. Not the first strategy.**  
Order: **docs → anchors/graph → selective value work → AOB if still needed.**

**NEVER** full-process AOB or global scan for a **common small integer** (e.g. 100, 101, 1000, typical stacks). That is idiotic: noise, thrash, relay death.

| Allowed | Forbidden |
|---------|-----------|
| Dword/integer **value scan** for a **distinctive** live value (e.g. money **47628145**) | Global AOB of a single small dword like `65 00 00 00` (101) |
| Graph walk from known objects; read known fields (`InventoryItem+0x10`) | Carpet-scan the whole process for stack counts |
| Code AOB in **gamedll/engine only** when path not already known | Opening every dig with full-process AOB |

If the field is already known (**`InventoryItem+0x10`** = stack count), **find the object via the inventory graph** — do not re-hunt the number globally.

## DO
- Code/data AOB: **`gamedll_ph_x64_rwdi.dll`** or **`engine_x64_rwdi.dll`** only (`AOBScanModule` / module-bounded) — **after** docs/anchors when needed
- Live objects: only follow pointers whose vtable (or proven global) is in **gamedll** or **engine**
- EXE: only if a specific proven slot lives there — not “scan everything”
- Distinctive money/HP-style values: dword/integer scan OK when selective enough

## DON'T
- Full-process `AOBScan` / value scan / heap trawl for vtables, PS, or DI
- AOB as **default first** move on every find task
- **Global single-value AOB for common counts** (100 / 1000 / 101 / typical stacks) — **NEVER**
- Scan or open other DLLs (CRT, DX, Steam, CE, system, …)
- `createMemScan` / `enumMemoryRegions` from the pipe for “find all instances”
