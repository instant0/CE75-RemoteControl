# Dying Light 2 — PlayerVarsArray discovery (dissect generator)

**Purpose:** Rebuild the **named offset map** for player configuration variables (`FloatPlayerVariable` / `PlayerVariables` field list) after a game update. That map feeds CE **dissect structures** and the `playerStat + offset` table rows.

**AOB method:** `skills/ce-aob-scan`  
**Live value base:** `player-variables.md` (`playerStat` bootstrap)  
**Related types:** `function-catalog.md`, `health-money.md`

---

## Two locations (do not confuse them)

| Location | What it is | How you get it | Use |
|----------|------------|----------------|-----|
| **A. Definition / init code** | Code that registers each field: **name string + offset** into the variables blob | **PlayerVars AOB** + walk `mov`/`lea` chain (script below) | Build **dissect** (`FloatPlayerVariable x.yy`, historically `PlayerVarsArray`) with correct **names + offsets** |
| **B. Live values blob** | Runtime instance of those floats/bools | **`playerStat` / `playerStatAlt`** via writable AOB bootstrap (id 78) | Read/write actual numbers; EXPR rows `playerStat + off` |

Typical workflow:

1. Run **generator** at (A) → global structure with thousands of named elements.  
2. Enable **bootstrap** at (B) → `playerStat` points at live data.  
3. Open dissect on `playerStat` (or attach structure) → see **values with names**.  
4. Promote interesting offsets into address-list EXPR rows.

CT already contains versioned dumps: **`FloatPlayerVariable 1.82`**, **`FloatPlayerVariable 1.90`** (and group “[Cheat][1.42] FloatPlayerVariable…”).

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

## Change log

| Date | Note |
|------|------|
| 2026-08-01 | Documented script, live 1.14 AOB → AnimGraph_BankName; two-location model; PDB type tree |
