# Scan scope — gamedll / engine only

**STICK TO SCANNING IN GAMEDLL/ENGINE AND STAY AWAY FROM THE REST.**

Everything useful so far lives in those two modules. Full-process / other-DLL scans are out of scope.

## DO
- Code/data AOB: **`gamedll_ph_x64_rwdi.dll`** or **`engine_x64_rwdi.dll`** only (`AOBScanModule` / module-bounded)
- Live objects: only follow pointers whose vtable (or proven global) is in **gamedll** or **engine**
- EXE: only if a specific proven slot lives there — not “scan everything”

## DON'T
- Full-process `AOBScan` / value scan / heap trawl for vtables, PS, or DI
- Scan or open other DLLs (CRT, DX, Steam, CE, system, …)
- `createMemScan` / `enumMemoryRegions` from the pipe for “find all instances”
