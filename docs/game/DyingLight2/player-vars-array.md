# Dying Light 2 — PlayerVarsArray discovery (dissect generator)

**Purpose:** Rebuild the **named offset map** for player configuration variables (`FloatPlayerVariable` / `PlayerVariables` field list) after a game update. That map feeds CE **dissect structures** and the `playerStat + offset` table rows.

**AOB method:** `skills/ce-aob-scan`  
**Live value base:** `player-variables.md` (`playerStat` bootstrap)  
**Related types:** `function-catalog.md`, `health-money.md`

---

## Two locations (do not confuse them)

| Location | What it is | How you get it | Use |
|----------|------------|----------------|-----|
| **A. Name/offset map** | Field **identity → offset** into the variables blob (registration) | PlayerVars AOB walker (`dl2_arrayscan_*`) | Structure like **`FloatPlayerVariable 20260801`**: names + offsets only |
| **B. Live `playerStat` object** | Runtime instance of that blob | Bootstrap / cluster locate → `RegisterSymbol(playerStat)` | `playerStat + offset` for each named field; optional richer dissect (1.90 / “1.92-style”) |

Typical workflow:

1. Run **generator** at (A) → versioned name map (`FloatPlayerVariable YYYYMMDD`).  
2. Locate **`playerStat`** (B) — separate step; map does not include the base.  
3. **Combine:** live value address = `playerStat + map[name].offset`.  
4. Optionally attach a **slot dissect** (expanded layout below) on `playerStat` for typed viewing.

CT may also contain older dumps: **`FloatPlayerVariable 1.82`**, **`FloatPlayerVariable 1.90`** (richer multi-element slots; offsets differ by build).

---

## Name map vs object dissect (critical)

```text
FloatPlayerVariable 20260801     =  catalog:  Name  →  offset
playerStat                       =  live base address of the blob
playerStat + offset              =  where that field’s data starts in memory
```

The arrayscan script is **only** responsible for the catalog. It does **not** invent `playerStat`.  
Once `playerStat` is known, table rows / discovery entries are filled as **base + catalog offset**.

### Why older CT structures look “wrong” per field

Historical dissects often **named the VALUE cell**, not the full **Entry** (header + value pair + tail):

| What was named | What the entry actually is |
|----------------|----------------------------|
| e.g. `AgressionPerHit` on a single float | One **slot** in the blob with multiple cells |
| Identity glued to “the float we freeze” | Not the whole record the engine uses |

If generation were fully programmatic from type + size, CE elements would more likely be **Entry-scoped** (header, actual, base, trailing fields) instead of a single named float.

### Dual float (and dual int): actual + base/config

Observed on **`FloatPlayerVariable 1.90`** (float-style slot; Aggression / Glide costs):

```text
… header …          (often vt=12 / 8 bytes just before the named value)
+0x00  float   NAMED     ← treated as the field identity in old CT
+0x04  float   (unnamed) ← second value: base / config / load default (same type)
+0x08  …       short / other tail fields
+0x0C  …
next entry header / next named value after a fixed stride (often 0x18 for float slots)
```

Concrete 1.90 Glide cost example:

```text
+0x23F0  header
+0x23F8  float  GlideStaminaCost          (actual)
+0x23FC  float  (pair)
+0x2400  …
+0x24C0  header
+0x24C8  float  GlideNitroStaminaCost     (actual)   CT name even embeds " - 0.25"
+0x24CC  float  (pair / base)
+0x24F0  header
+0x24F8  float  GlideNitroCooldown
+0x24FC  float  (pair)
```

So for a **float** field with config default `D`, at rest you often see:

```text
[playerStat + off + 0] = D   (or live actual)
[playerStat + off + 4] = D   (base/config twin)
```

**Byte toggles** and **integers** use the same *idea* (typed cells + pair / tail) but **different sizes and strides** — do not assume 0x18 for bools (1.90 `GlideNitroAvailable` is byte-sized in the expanded dump).

**Implication for scanning:** a single `0.25` is weak (many fields). A **pair** `0.25, 0.25` at `off` and `off+4`, plus **neighbor pairs** at catalog-relative gaps, is a real fingerprint.

### How this helps Glide → `playerStat`

Use **catalog offsets from `FloatPlayerVariable 20260801`** (not old 1.90 numbers alone) and **pair defaults** from CT names / known defaults:

| Name (20260801) | Offset | Known default hint (from old CT naming / docs) | Pair cells |
|-----------------|--------|-----------------------------------------------|------------|
| GlideStartStaminaCost | `+0x2820` | ~**0.34** (`… - 0.34` in 1.90) | `+2820`, `+2824` |
| GlideStaminaCost | `+0x2838` | ~**0.10** | `+2838`, `+283C` |
| GlideNitroStaminaCost | `+0x2920` | ~**0.25** | `+2920`, `+2924` |
| GlideNitroCooldown | `+0x2950` | (check 1.90 / live) | `+2950`, `+2954` |

Relative gaps (20260801):

```text
GlideStaminaCost      = GlideNitroStaminaCost - 0xE8
GlideStartStaminaCost = GlideNitroStaminaCost - 0x100
GlideNitroCooldown    = GlideNitroStaminaCost + 0x30
```

Locate procedure:

1. **Group scan** (preferred) — see [CE-GROUP-SCAN.md](../../CE-GROUP-SCAN.md):  
   `F:0.34 F:0.34 W:16 F:0.1 F:0.1 W:224 F:0.25 F:0.25`  
   then `playerStat = hit - 0x2820`.  
2. `RegisterSymbol(playerStat, base)` only after multi-field agreement.  
3. **Never** `F:0.25 F:0.25` alone (or any single-value pair) — thousands of hits.  
4. Do **not** use only **old** 1.90 offsets without the **current** catalog.

Agent rule: **retune the known walker + this layout model** — do not invent an all-vtSingle substitute map.

---

## Historical generator script (author workflow)

AOBs used over time (module `gamedll_ph_x64_rwdi.dll`):

| Build note | Pattern |
|------------|---------|
| old | `66 C7 85 60 42 00 00 80 01 48 89` |
| 1.13.0e | `66 C7 85 80 43 00 00 80 01 48 89` |
| (variant) | `C7 85 * * * 00 18 00 00 00 4C` |
| **1.14** | `C7 44 24 20 00 00 00 00 4C 8D 4C 24 20` |

### Logic (summary)

```text
address = AOBScanModuleUnique(gamedll, pattern_1_14)
createStructure('PlayerVarsArray')
seed element AnimGraph_BankName @ 0

loop getInfo(address):
  offset = readInteger(address + 4)          -- or +6 for alt encoding
  name   = string from disasm at address+0xD (fallback +0x13)
           → lea/mov target [abs] → readString
  addElement(offset, name)
  searchNext: scan forward for word 0x44C7 (or 0x84C7) within 0x500

second pass with 0x84C7 + getInfo2 (offset at +6)
addToGlobalStructureList()
```

**First field name historically:** `AnimGraph_BankName` (sanity check).

### Live check (2026-08-01, gamedll base `7FFA1FE20000`)

| Pattern | Result |
|---------|--------|
| 1.14 `C7 44 24 20 00 00 00 00 4C 8D 4C 24 20` | **9** process hits; **1** in gamedll: `7FFA20233CC7` |
| old / 1.13.0e exact | **0** hits |
| Wildcard `C7 85 ** ** ** 00 18 00 00 00 4C` | 4 hits (not all gamedll) |

At gamedll hit:

```text
mov [rsp+20], 0
lea r9, [rsp+20]
lea r8, [gamedll_data] → readString = "AnimGraph_BankName"   ✓
call …
```

So the **1.14 AOB still finds the registration prologue** on the June-2026-era binary.  
**Caveat:** instruction layout drifted — old `getInfo` (`offset = readInteger(addr+4)`, string at `+0xD`) does **not** decode every field without retuning parse offsets. Treat the script as a **template**: re-derive `getInfo` from sequential disasm of the first 2–3 fields, then walk `0x44C7` / `0x84C7` markers.

### Remote / agent port notes

- Prefer `aobscanmodule` / filter full `AOBScan` hits to **gamedll** range.  
- Multi-hit ranking: keep site that yields **`AnimGraph_BankName`** (or other known first field).  
- Generating 4k–20k structure elements via remote CE is **heavy** — prefer running the Lua generator **inside CE** once, then `stDump` / save CT.  
- After generate: rename structure e.g. `FloatPlayerVariable 20260614` (YYYYMMDD scheme).  
- Do **not** `stClone` entire 20k-element structs casually over remote.

---

## PDB / type hierarchy (names for this system)

From `gamedll` PDB strings + live RTTI-style names (2022 PDB ≠ 2026 RVAs; names still useful):

```text
PlayerVariables                          (constds field collection / dataset)
├── FloatPlayerVariable                  (bulk of CT offsets)
├── BoolPlayerVariable
├── StringPlayerVariable
└── HealthPlayerVariable<HealthFactors>

MenuDevPlayerVariables / ReloadPlayerVariables   [strings in 2026 gamedll]
```

Related but **not** the same blob:

```text
PlayerHealthModule → LifeHealth<HealthFactors>   (runtime HP)
InventoryMoney → Money @ +0x38                   (currency amount)
PlayerState → ptr FloatPlayerVariable @ +0xE8    (link toward vars)
PlayerDI_PH                                      (player entity-ish)
```

---

## Linking offsets to the address list

Example CT rows (after `playerStat` resolves):

| Offset (hex) | Name (from FPV 1.90 / 1.82) | Notes |
|--------------|----------------------------|--------|
| `2E38` | InfiniteStamina (bool-ish) | table toggle |
| `36C0` | MaxStamina | default ~0.8 |
| `3438` | **MaxHealth** | **config** max, not current HP |
| `2E78` / `2E90` | ItemsBuyFactor / ItemsSellFactor | economy multipliers (table money section) |
| `23E0`… | Glide* costs | defaults in field names |

**Current hit points** and **old-world money amount** are usually **not** plain fields in this config blob — see `health-money.md`.

---

## Retune checklist after a patch

1. Scan historical PlayerVars AOBs; filter **gamedll**.  
2. Confirm `AnimGraph_BankName` (or updated first string).  
3. Fix `getInfo` parse (offset imm + string lea).  
4. Regenerate structure → save as new versioned name (`FloatPlayerVariable YYYYMMDD`).  
5. Diff a few known offsets (MaxStamina, MaxHealth, Glide*) vs old structure.  
6. Retune **playerStat** data AOB separately (`ce-aob-scan` + player-variables skill).  
7. Update MEMORY tags to **YYYYMMDD** when verified.

---

## Method rule (do not re-litigate)

Host scripts under **`/mnt/r/`** (and extracts in this folder) show **how things worked**. After a patch:

1. **Retune that script** (AOB / imm position / LEA / search gap).  
2. **Do not** invent a parallel “flat all-float” or N×M remote scorer.  
3. Run the walker **once inside CE** (see remote note below).

Game docs exist so the **approach** is known; agents must follow it.

---

## Live regenerate (CE) — `FloatPlayerVariable 20260801`

### Script (not in git)

| | |
|--|--|
| Historical | `/mnt/r/dl2_arrayscan_1.14.txt` |
| **Retuned** | **`/mnt/r/dl2_arrayscan_20260801.lua`** |

Same pipeline as 1.14: `AOBScanModuleUnique` → walk `0x44C7` / `0x84C7` → `addElement(Offset, Name)` → `addToGlobalStructureList`.

| Decode constant | Historical 1.14 script | 20260801 retune |
|-----------------|------------------------|-----------------|
| AOB | `C7 44 24 20 00 00 00 00 4C 8D 4C 24 20` | unchanged (still hits) |
| `C7 44` offset | `readInteger(addr+4)` | unchanged |
| `C7 84` offset | `readInteger(addr+6)` | **`+7`** (`C7 84 24 disp32 imm32`) |
| Name LEA | `+0xD` then `+0x13` | `C7 84`: prefer **`+0x13` then `+0xD`** |
| Next `C7 84` gap | `0x500` | **`0x2000`** |
| Structure name | `PlayerVarsArray` | `FloatPlayerVariable 20260801` |
| Per-field `print` | yes | off (remote / large lists) |

### In CT now

| Item | Value |
|------|--------|
| **Structure** | **`FloatPlayerVariable 20260801`** |
| Elements | **2449** (seed + walk; same class of output as the host script) |
| Prior mistake | `FloatPlayerVariable 20260801-BROKEN` (flat all-`vtSingle` rewrite — keep only as warning label) |
| Still present | `FloatPlayerVariable 1.82` / `1.90` (older dumps; offsets differ) |

### Spot-check offsets (this build)

| Name | Offset |
|------|--------|
| AnimGraph_BankName | `+0` |
| AggresionPerHit | `+0x78` |
| GlideNitroStaminaCost | `+0x2920` |
| InfiniteStamina | `+0x32C8` |
| MaxHealth | `+0x38F8` |
| MaxStamina | `+0x3B98` |

### Mistake to avoid (postmortem)

Discarding the host walker and emitting every field as fixed 4-byte float was **wrong process**, not “required by new data.” Data organization is the same; only a few decode constants moved. **Always adjust the known script first.**

### Remote CE: one `runScript` / `runScriptSafe` (not 2400 prompts)

**Yes — upload/run the whole Lua body in a single command.** CE executes the loop in-process and builds all elements locally. The client only needs:

1. One short AOB check (optional), then  
2. **One** `runScriptSafe` with the full retuned script text  

Do **not** `readInteger` / disasm per field over TCP. Optional: paste the same file into CE’s Lua Engine on the host.

Pipe note: if the relay is line-oriented, strip `--` comments and send as one logical script payload (space-joined lines is fine for this file).

---

## Change log

| Date | Note |
|------|------|
| 2026-08-01 | Documented script, live 1.14 AOB → AnimGraph_BankName; two-location model; PDB type tree |
| 2026-08-01 | Wrong path: all-vtSingle map labeled `…20260801-BROKEN` |
| 2026-08-01 | Correct path: retuned `/mnt/r/dl2_arrayscan_20260801.lua` → CE struct `FloatPlayerVariable 20260801` (2449) |
| 2026-08-01 | Documented map vs playerStat instance; dual actual/base values; named-value vs full entry; Glide pair fingerprint |
| 2026-08-01 | Worked GroupScan method + two-heap disambiguation in player-variables.md |
| 2026-08-01 | Dissect expand script `/mnt/r/dl2_fpv_dissect_from_map_20260801.lua` → `FloatPlayerVariable 20260801 Dissect` (~12.5k elems) |
