# Cheat Engine Group Scan (source-verified, CE 7.5)

**CE source:** `/mnt/y/Lazarus/Projects/cheat-engine-7.5/Cheat Engine/`  
**Parser:** `groupscancommandparser.pas`  
**UI builder:** `frmgroupscanalgoritmgeneratorunit.pas`  
**Engine:** `memscan.pas` when `variableType = vtGrouped` (enum value **14** in `commontypedefs.pas`)

## What it is

A **group scan** finds places in memory where **several typed values appear at fixed relative positions** in one contiguous **block**. That is exactly how you locate a structure (e.g. Glide cost fields inside `playerStat`) when you know **multiple defaults and the gaps between them** — not a single float.

Hit address = **start of the block** = address of the **first** element in the command.

## Command language (from `TGroupscanCommandParser`)

Space-separated tokens. Type letter is case-insensitive (parser uppercases the command side).

| Token | Meaning |
|-------|---------|
| `1:N` | Byte = N |
| `2:N` | Word (2) = N |
| `4:N` | Dword = N |
| `8:N` | Qword = N |
| `F:x` | **Float** (4) = x |
| `D:x` | Double (8) = x |
| `P:…` | Pointer (size = process pointer size) |
| `S:'text'` / `SU:'text'` | String / unicode string |
| `W:count` | **Skip / wildcard** `count` **bytes** (padding between fields) |
| `C(Name):…` | Custom type |
| `* ` or empty value | Wildcard for that element (not allowed with out-of-order) |
| `FR:a-b` | Float **range** (suffix `R` on type); same idea for int types |
| `FP:…` | Mark element **picked** (address list); if none picked, **all** are picked |
| `BA:n` | Block alignment (default **4**) |
| `BS:n` | Block size (mainly with out-of-order) |
| `OOO:A` / `OOO:U` | Out-of-order scan (aligned / unaligned); **no wildcards** |

### Layout rule (important)

Elements are laid out **in order**. Each element’s offset from the block start is the **running sum of previous element sizes** (`calculatedBlocksize` in the parser).

There is **no** “absolute structure offset” field in the command. To bridge a gap between two known fields:

```text
F:0.25 W:16 F:0.1
```

means: float, then **skip 16 bytes**, then float.  
If the second field is 24 bytes after the first float’s start, skip = 24 − 4 = 20 only if a single float sits first — always compute:

```text
skip = (next_field_offset - prev_field_offset) - prev_field_size
```

or, for dual floats then a gap:

```text
skip = next_offset - (block_start_offset + bytes_consumed_so_far)
```

## Manual use in CE UI

1. Scan type / Value type: **Grouped**.  
2. Paste the **same command string** into the value box (or open the Group scan algorithm generator and fill rows; OK builds this string).  
3. First scan.  
4. Each result is the address of element 0.  
5. Derive structure base: `base = hit - catalog_offset_of_first_element`.

## Remote support (`ce_server` / client)

| Path | Support |
|------|---------|
| **`GroupScan <command>`** (ce-server **≥ v1.8.3**) | Yes — **main-thread** `createMemScan` + `vtGrouped` + `waitTillDone`, returns `COUNT=` + hex addresses (capped) |
| `runScriptSafe` + `createMemScan` | **Banned** (unsafe off main thread) |
| `runScript` + memscan | Possible but easy to hang/kill the server — prefer **`GroupScan`** |
| `AOBScan` only | Byte-pattern subset; use for simple consecutive floats, not full group language |

Python:

```python
from client import CERemote
ce = CERemote("192.168.176.1", 8000, timeout=180)
print(ce.group_scan("F:0.34 F:0.34 W:16 F:0.1 F:0.1 W:224 F:0.25 F:0.25"))
# hit = first field (GlideStartStaminaCost)
# PlayerVariables catalog base (legacy playerStat) = hit - 0x2820
```

**Reload `ce_server.lua` in CE** after pull so `getVersion` shows `v1.8.3`.

---

## Dying Light 2 — Glide group (example only)

**Prefer the typed locator first:** [game/DyingLight2/player-variables.md](game/DyingLight2/player-variables.md) (`PlayerState+0xBA8`). Use GroupScan when the chain breaks after a patch or for research.

Catalog offsets (name map) and **default hints** from older CT naming (`… - 0.34`, `… - 0.25`) + dual actual/base floats.  
Legacy CT symbol `playerStat` = **PlayerVariables catalog base** (`engine this + 8`):

| Field | Catalog offset | Default (hint) | Pair cells |
|-------|----------------|----------------|------------|
| GlideStartStaminaCost | `+0x2820` | **0.34** | `+0` / `+4` |
| GlideStaminaCost | `+0x2838` | **0.10** | `+0` / `+4` |
| GlideNitroStaminaCost | `+0x2920` | **0.25** | `+0` / `+4` |

Relative layout from **`+0x2820`** (block start = start cost actual):

```text
+0x0000  F  0.34   GlideStartStaminaCost actual
+0x0004  F  0.34   twin (base/config)
+0x0008  … skip 0x10 (16) bytes …
+0x0018  F  0.10   GlideStaminaCost actual   (+0x2838)
+0x001C  F  0.10   twin
+0x0020  … skip 0xE0 (224) bytes …
+0x0100  F  0.25   GlideNitroStaminaCost actual  (+0x2920)
+0x0104  F  0.25   twin
```

### Manual / remote group command (recommended)

```text
F:0.34 F:0.34 W:16 F:0.1 F:0.1 W:224 F:0.25 F:0.25
```

```text
playerStat_candidate = hit - 0x2820
```

You may get **more than one** heap block with full defaults plus a **DLL template**. Sanity-check unrelated fields (e.g. CableMaxLength / NightVisionPower); drop module hits. If **two** heap bases both look good, only **one** is the active player — disambiguate with a non-default live field or an in-game freeze test (see `player-variables.md` worked session).

### Do **not** use a nitro-only (or any single-field) pair

```text
F:0.25 F:0.25     ← FORBIDDEN as a locate
```

Two consecutive identical floats (especially common defaults like `0.25` / `0.1` / `1.0`) appear **thousands** of times. That is not a “weaker” fingerprint — it is **noise**. Always include **multiple distinct Glide (or other) fields and their gaps** (`W:…`) in one group command.

### If defaults were edited in-game

Replace the numbers with the live defaults, or use ranges, e.g.:

```text
FR:0.33-0.35 FR:0.33-0.35 W:16 FR:0.09-0.11 FR:0.09-0.11 W:224 FR:0.24-0.26 FR:0.24-0.26
```

### Related game docs

- [game/DyingLight2/player-vars-array.md](game/DyingLight2/player-vars-array.md) — name map vs `playerStat`, dual values  
- [game/DyingLight2/player-variables.md](game/DyingLight2/player-variables.md) — bootstrap / symbols  

---

## Agent rules

1. For DL2 **PlayerVariables**, prefer the typed **PlayerState+0xBA8** chain ([player-variables.md](game/DyingLight2/player-variables.md)) before GroupScan.  
2. Prefer **multi-field group** with real gaps (`W:…`) — never a single-value twin pair as a locate.  
3. Use **current catalog offsets** (`FloatPlayerVariable YYYYMMDD`), not only old 1.90 numbers.  
4. Remote: **`GroupScan`** command on main thread; do not ad-hoc `createMemScan` in `runScriptSafe`.  
5. Hit = **first element**; subtract that field’s catalog offset to get **PlayerVariables catalog base** (legacy name: `playerStat`).
