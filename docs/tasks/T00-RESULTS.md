# T00 spike results — Dying Light 2 table

| Field | Value |
|-------|--------|
| **Date** | 2026-08-01 |
| **Endpoint** | `192.168.176.1:8000` |
| **Process** | `DyingLightGame_x64_rwdi.exe` pid=2024 |
| **Server** | `ce-server v1.0 (CE 7.5)` |
| **Status** | Spike complete — go for T01 with noted adjustments |

## Connectivity

| Check | Result |
|-------|--------|
| `ping` | `pong` |
| `getVersion` | `ce-server v1.0 (CE 7.5)` |
| Client defaults | Must use `--host 192.168.176.1 --port 8000` (not localhost:8888) |

## Address list inventory

| Metric | Value |
|--------|--------|
| `al.Count` | **93** |
| TYPE=11 (AA / script entries) | **16** (approx; matched AA heuristic) |
| TYPE=4 (float values etc.) | present (e.g. NightXP, many player floats) |
| TYPE=0 | notes / headers / some values |
| TYPE=2 | present (e.g. raw addresses) |
| `OffsetCount > 0` (true CE pointer chains) | **~0** on this table |
| Expression addresses (`playerStat + off`, `[SYM]+off`) | **majority of value rows** |
| Group-like / separator rows | ~19 |
| Largest script (`SCRIPTMAX`) | **3229** bytes (ID **9**, AOB Inject Ammo) |
| Full metadata dump size | **~7.1 KiB** (well under 48 KiB) |
| Dump latency (`synchronize`) | **~0.03–1.1 s** per call (varies) |

### Critical classification fix (for T02 / T09)

This table does **not** use CE multi-level `Offset[]` pointers for player vars.

It uses **interpretable address strings**:

```text
playerStat + 2e38
playerStat+2e90+18
[TIMESTRUCT]+5C
[NIGHTXPBONUS]+5C
```

So `CLASS=POINTER` must **not** be only `OffsetCount > 0`. Add:

| CLASS | Rule |
|-------|------|
| `AA` | `Type==11` and/or non-empty `Script` |
| `EXPR` | Address contains `+` or `[` symbol form (and not AA) |
| `GROUP` | group header / empty type notes |
| `STATIC` | plain hex / module address |
| `POINTER` | `OffsetCount > 0` (rare here) |

### Playervariables bootstrap (user-provided + verified)

| Field | Value |
|-------|--------|
| Description | `[Cheat][1.93] Enable playervariables editing` |
| ID | **78** |
| Type | **11** |
| Script length | **1203** |
| Active (at spike) | **false** |
| Role | `{$lua}` enable: AOBScan → `RegisterSymbol(playerStat/Alt)` → sets **this row’s** `.Address` |

Script pattern history (version comments inside AA):

```text
-- 1.42  10 A0 96 ** ... 00 00 40 40  (+W-C)
-- 1.82  08 28 C7 ** ... 00 00 40 40
-- 1.90  08 ** ** ** ** ** ** 00 00 00 00 80 3E ... 00 00 40 40
```

**Symbols at spike (script disabled):**

```text
getAddress playerStat     → ERROR: Symbol not found
getAddress playerStatAlt  → ERROR: Symbol not found
getAddress TIMESTRUCT     → ERROR: Symbol not found
getAddress NIGHTXPBONUS   → ERROR: Symbol not found
```

Dependent rows (e.g. ID 90 `playerStat + 2e38`) report **`CurrentAddress=0`** until the enabler is activated. That is expected.

**Migration implication:** Tier-0 is “enable / rebind bootstrap AA scripts that `RegisterSymbol`”, not individual float offsets.

### Script read path

| Probe | Result |
|-------|--------|
| `mr.Script` via `synchronize` + `runScript` | Works for TYPE=11 |
| Max script 3229 B | **Single response OK**; chunking still good for safety but not mandatory for this table |
| Example content | Classic AA `aobscanmodule` injects + one `{$lua}` bootstrap |

### setAddress / expression preserve

| Probe | Result |
|-------|--------|
| ID 90 `playerStat + 2e38`, OFFC=0 | `setAddress` / `.Address =` **preserves** expression string |
| `CurrentAddress` while symbol missing | **0** |
| Classic offset-table preserve | N/A on this table (no OFFC chains observed) |

**T03 note:** Prefer setting `.Address` string for EXPR rows; offset-table path still required for true pointer memrecs on other tables.

### getMemoryRecordByDescription

Works: exact description of ID 78 resolves correctly. Useful for scripts that self-patch by description (as this table already does).

## Structures (dissect)

| Metric | Value |
|--------|--------|
| `getStructureCount()` | **41** before clone → **42** after spike clone |
| Name lookup by scan | Works (`PlayerState`, `FloatPlayerVariable 1.90`) |
| `getStructure(i)` index-only | Confirmed usage; never pass name string |

### Size / element counts (important)

| Structure | Count (elements) | Notes |
|-----------|------------------|--------|
| `PlayerState` | **21185** | Huge auto-style layout; many empty names |
| `FloatPlayerVariable 1.90` | **20835** | Same class of “full dump” struct |
| Spike clone `T00_SPIKE_FloatPV` | **20835** | Clone **succeeded** in ~2 s |
| Many inventory/story structs | smaller | Named fields present |

**T06 implications:**

- `stClone` **works** via `createStructure` + element copy + `addToGlobalStructureList`.
- Cloning **20k-element** structs is viable but heavy; agent should warn / prefer in-place edit for huge structs.
- `Size` property returned **nil** in one probe — use `Count` + last offset, don’t assume `Size`.
- ChildStruct present (e.g. “Autocreated from …”).

### Leftover from spike (user may delete)

In CE structure list: **`T00_SPIKE_FloatPV`** (clone of FloatPlayerVariable 1.90). Safe to remove manually if unwanted. Not removed by spike (avoid destructive global ops).

## AOB / modules

| Probe | Result |
|-------|--------|
| Native `AOBScan` of float pair pattern `00 00 00 00 80 3E 00 00 80 3E ...` | **~521 hits**, **~12.5 s** |
| Game modules of interest | `DyingLightGame_x64_rwdi.exe`, **`gamedll_ph_x64_rwdi.dll`** (AA scripts target this) |
| Module count | 174 |

**T09 / AOB strategy:** Prefer `aobscanmodule(..., gamedll_ph_x64_rwdi.dll, ...)` patterns from scripts over full-process wild scans. Bootstrap Lua uses full `AOBScan` with `+W-C` and expects **≥2 hits** (`[0]` and `[1]`).

**Not tested in spike (intentionally):**

- `alSetActive` / enabling AA inject scripts (game side effects)
- `autoAssembleCheck`
- Modal deadlock on failed AA
- `AOBScan` with protection string `+W-C` via remote (Lua AA uses it; native server command may differ)

## Server stability

| After | Result |
|-------|--------|
| Many `runScript`+`synchronize` calls | Still **`ping` → pong** |
| 20k-element structure clone | Survived |
| 12 s AOBScan | Survived |

No relay/server crash observed during this session.

## What works for the plan (confirmed)

| Capability | Status |
|------------|--------|
| `synchronize` + `getAddressList` dump | OK |
| Read AA `Script` text | OK |
| Write `.Address` expression | OK (smoke re-set same value) |
| `getMemoryRecordByID` / `ByDescription` | OK |
| Structure name scan + element read | OK |
| Structure clone (large) | OK |
| Native AOBScan / enumModules | OK |
| Symbol resolve before enable | Expected fail until bootstrap runs |

## Adjustments to later tasks

| Task | Adjustment from this spike |
|------|----------------------------|
| **T02** | CLASS needs `EXPR`; Type **11** = AA; dump 93 rows ~7KB OK; pagination optional |
| **T03** | EXPR address string is primary; document `playerStat+off` style |
| **T04** | Max script ~3KB here; chunking still recommended; **enable order** critical for RegisterSymbol |
| **T05/T06** | Expect **40+** structs; some **>20k elements**; clone cost ~2s; warn on huge clone |
| **T07** | Default examples: host `192.168.176.1` port `8000` in docs if that’s the lab setup |
| **T09** | DL2 playbook: (1) rebind bootstrap Lua AOB for new build (2) enable ID 78 (3) verify `playerStat` (4) fix `aobscanmodule` scripts against `gamedll_ph_x64_rwdi.dll` (5) structs optional/huge |

## Sample dependency graph (this table)

```text
[ID 78] Enable playervariables editing  {$lua} AOB → RegisterSymbol(playerStat)
        │
        ├── playerStat + *   (dozens of floats/toggles)   CUR valid only after enable
        └── (optional) bugfix ID 173 if wrong AOB hit

[Other TYPE=11] Unlimited Accessories, Free crafting, AOB Inject Ammo, ...
        └── each self-contained aobscanmodule(INJECT, gamedll_ph_x64_rwdi.dll, ...)

[Symbols TIMESTRUCT / NIGHTXPBONUS]
        └── set by other enable scripts (not present until those run)
```

## Recommended next step

Proceed to **T01** (`sync_call` + helpers), using this file as the acceptance baseline table shape.
