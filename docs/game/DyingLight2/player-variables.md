# Dying Light 2 — PlayerVariables (live config vars)

**Status (2026-08-01):** locator **proved** — `PlayerState + 0xBA8` → engine `this`; catalog base = `this + 8`.  
See [INDEX.md](INDEX.md) status matrix.  
**Canonical name:** **`PlayerVariables`**.  
**Legacy CT symbols:** `playerStat` / `playerStatAlt` = **catalog base** (`engine this + 8`). Prefer `PlayerVariables` for new work.

**Use for:** balancing/config floats (stamina, glide, HoldJump, buy/sell factors, …).  
**Not for:** live combat HP or wallet cash → [health-money.md](health-money.md).

**Long session notes / failed AOB / access-log detail:** [player-variables-history.md](player-variables-history.md).

---

## Do this first (bootstrap recipe)

### Proven chain

```text
gamedll global  (RVA +0x36015C8 this build — re-find after patch)
    →  PlayerState*
PlayerState + 0xBA8
    →  PlayerVariables engine this
engine this + 8
    →  catalog base  (== legacy playerStat; map offsets apply here)
```

**A. Preferred — getter AOB + parse RIP-rel global (survives normal recompiles)**

Do **not** hardcode `gamedll+0x……` as the primary enable path. RVAs move every patch; the **instruction shape** of the small getter usually does not.

```text
1. aobscanmodule(gamedll, GETTER_AOB)   // unique body below
2. global = hit + 14 + s32(hit+10)      // parse mov rax,[rip+disp]
3. ps  = readQword(global)              // PlayerState*
4. eng = readQword(ps + 0xBA8)          // PlayerVariables engine this
5. sanity: RTTI / HoldJump float optional
6. registerSymbol("PlayerVariables", eng + 8)   // catalog base
```

**Getter AOB** (`aobscanmodule` on `gamedll_ph_x64_rwdi.dll`):

```text
80 B9 90 37 00 00 00 48 8B 05 ?? ?? ?? ?? 75 07 48 8B 81 B0 06 00 00 48 8B 80 A8 0B 00 00 C3
```

```text
+0  cmp [rcx+0x3790],0
+7  mov rax,[rip+disp]     <- static PlayerState**; ?? ?? ?? ?? is the reloc
+14 jne
    mov rax,[rcx+0x6B0]
    mov rax,[rax+0xBA8]
    ret
```

**B. Hardcoded GLOBAL_RVA** — snapshot for **one** binary only (emergency fallback). Re-derive from AOB after each patch if used alone.

**C. Fallback research:** access log / inject / GroupScan — [player-variables-history.md](player-variables-history.md), [../../CE-GROUP-SCAN.md](../../CE-GROUP-SCAN.md).

Per-build checksums / CT script: gitignored `private/DyingLight2/` (not public git).

### Sanity (cheap)

| Check | Pass |
|-------|------|
| Mid RTTI | `PlayerState` |
| Eng RTTI | `StringPlayerVariable` (outer at engine `this`) |
| Float slot RTTI | `FloatPlayerVariable` at e.g. eng+0x2F88 header |
| Sample field | HoldJump / MaxStamina sensible |

### Safety

| Do | Don't |
|----|--------|
| Module-limited getter AOB | Full-process string spam |
| Re-validate `+0xBA8` after patch | Assume host **`+0xE8`** still valid |
| One light float sanity read | GroupScan as product enable |
| Fix bad **rows** (offset/type) | Abandon chain because one EXPR shows garbage |

Host notes’ **PlayerState+0xE8** is **historical**; this build uses **+0xBA8**.

---

## Mental model

| Piece | Meaning |
|-------|---------|
| **`PlayerVariables`** | Live aggregate (config/balancing) |
| **Engine `this`** | Pointer game code uses; HoldJump = `[this+0x2F90]`; RTTI at +0: **`StringPlayerVariable`** |
| **Catalog base** | **`this + 8`** — origin for registration/map offsets (legacy `playerStat`) |
| **Value address** | `catalog + map_offset` (= `this + 8 + off`) |
| **`FloatPlayerVariable YYYYMMDD`** | Name → offset **catalog only** — [player-vars-array.md](player-vars-array.md) |
| **Float slot** | Often actual @+0, base/config @+4; stride often `0x18` |
| **Bool slot** | Byte-style; wrong CE type → garbage (e.g. “192”) |

Do **not** treat the name-map structure as the live instance.  
Do **not** use GroupScan as primary locator when the typed chain works.

### Accuracy ladder

| Rank | Method | Status |
|------|--------|--------|
| **1** | `PlayerState* → +0xBA8 → this` | **Proved — preferred** |
| 2 | `PlayerDI_PH` vtable **+0x618** getter (same pointer) | Proved |
| 3 | Field access log / inject on consumers | Research |
| 4 | GroupScan / interior data AOB | Research only |

### PlayerDI getter (same pointer)

`PlayerDI_PH` vtable +0x618 (gamedll RVA **`+0xF74940`** this build): load PlayerState* (global or alt), then `[rax+0xBA8]` → engine `this`.  
Callers: `call [rax+0x618]` with RCX = PlayerDI_PH; RAX = vars `this`.

---

## Type identity (compact)

| Location | RTTI |
|----------|------|
| Engine `this` (+0) | `StringPlayerVariable` (leading subobject) |
| Float field headers | `FloatPlayerVariable` |
| Flag slots | `BoolPlayerVariable` |

Shared vtables (module RVA, **this build only** — re-check after patch):

| Type | ≈ gamedll+RVA |
|------|----------------|
| `FloatPlayerVariable` | `+0x26FE9C0` |
| Outer / string-leading | `+0x2758428` |
| `BoolPlayerVariable` | `+0x2758448` |

Name strings in gamedll (`FloatPlayerVariable`, `PlayerVariables`, …) exist for offline identity — prefer module-limited scans, not full-process loops.

---

## Table migration notes

| Item | Guidance |
|------|----------|
| Symbols | `PlayerVariables` = catalog base; keep `playerStat` alias until all EXPRs renamed |
| Value rows | `PlayerVariables+<catalog hex>` (or legacy `playerStat+…`) |
| Map | Remap from **`FloatPlayerVariable 20260801`** — [player-vars-array.md](player-vars-array.md) |
| Types | Bools as **byte**, not float — fixes garbage like InvisibleToEnemies **192** |
| Descriptions | Many comments still show **stale** hex; trust map + Address, not old `- 1080` text |
| Enable | Prefer chain A/B in bootstrap AA; drop dead `+W-C` data AOB / `hit+1` |

### Partial port status (2026-08-01)

| Change | Status |
|--------|--------|
| Bootstrap chain PlayerState+0xBA8 | Script path updated (verify on load) |
| Symbol `PlayerVariables` (+ legacy alias) | Yes |
| EXPR rename `playerStat` → `PlayerVariables` | ~100 rows |
| Full offset remap to 20260801 | **Partial** |
| Description comment rewrite | **Not done** |
| Systematic type fix (byte vs float) | **Not done** |

Until cleanup: treat table as **partially ported**. Bad single-row values ⇒ fix that row’s offset/type from the map, not the locator chain.

### Remote workflow (short)

```text
1. tableStatus / alDump — find bootstrap AA (playervariables)
2. Prefer rewrite enable to chain A/B (not data AOB)
3. aaCheck → alSetActive (timeout ≥120) — this bootstrap only
4. getAddress PlayerVariables / playerStat; spot-check HoldJump, MaxStamina
5. Remap / type-fix EXPR rows from catalog; do not mass-enable injects
```

### Ops

Server dies after bad agent commands → reload `ce_server.lua`. Health: `ping` → `pong`. Details: `skills/ce-remote-scanning`.

---

## Next steps

| Priority | Work |
|----------|------|
| Done | Name + proved **+0xBA8** chain + DI vfunc |
| 1 | Keep CT bootstrap on chain A/B (no data AOB enable) |
| 2 | After patch: re-AOB getter → new global; confirm **+0xBA8** |
| 3 | Finish EXPR offset/type/comment pass from 20260801 map |
| 4 | Live HP/money — separate track ([FIND-LIVE-HEALTH-MONEY.md](FIND-LIVE-HEALTH-MONEY.md)) |

---

## Related

| Doc / skill | Role |
|-------------|------|
| [player-variables-history.md](player-variables-history.md) | Access log, HoldJump disasm, CE unique AOB, GroupScan session, legacy data AOB |
| [player-vars-array.md](player-vars-array.md) | Catalog generator / dual floats / Glide gaps |
| [../../CE-GROUP-SCAN.md](../../CE-GROUP-SCAN.md) | GroupScan language (research fallback) |
| [modules.md](modules.md), [function-catalog.md](function-catalog.md) | Modules / names |
| [health-money.md](health-money.md) | Not this blob |
| `skills/dl2-table-work` | DL2 work order (thin) |
| `skills/ce-table-migrate`, `ce-aob-scan`, `ce-remote-scanning` | How to operate remote |
