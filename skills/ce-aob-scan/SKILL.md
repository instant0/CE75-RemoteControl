---
name: ce-aob-scan
description: Robust array-of-bytes (AOB) methodology for any Cheat Engine table entry via remote CE — code injects, data/bootstrap scans, multi-hit ranking, zero-hit recovery, pattern quality, and post-verify version tagging. Game-agnostic; use game folders only for anchors and worked examples.
tags: [ce, aob, aobscan, remote, inject, pattern, table-migrate]
---

# CE AOB scan (robust, any entry)

Use this skill whenever you need to **find, re-find, or retune** an AOB for a loaded CE table entry — freeze scripts, injects, `{$lua}` bootstraps, static signatures, or string anchors. **Not game-specific.**

| Related | Role |
|---------|------|
| `ce-remote-scanning` | Safe remote APIs, value scan, crash avoidance |
| `ce-table-migrate` | Full table port order (AA → EXPR → structs) |
| `ce-table-remote` | al*/st* foundation, rename rules |
| `game/<Title>/…` | Named APIs, modules, feature case studies |

## Why AOBs break

| Cause | Symptom |
|-------|---------|
| Compiler / patch rewrote code | 0 hits or wrong site |
| Immediate/disp changed (`+5C` → other) | 0 hits on tight pattern |
| Same opcode sequence elsewhere | **2+ hits**, wrong enable |
| Wrong module | Hits in another DLL / none in target |
| Data layout drift (bootstrap) | Hits but wrong object / bad child values |
| Stale CE labels in ORIGINAL CODE | Porter searches a function that never existed |

CT comments like `// should be unique` are **not** guarantees after updates.

---

## AOB classes (pick the right playbook)

| Class | Typical AA / CT shape | What you pattern |
|-------|----------------------|------------------|
| **A. Code inject** | `aobscanmodule` + `alloc` + `jmp` / cave | Instruction bytes at hook site |
| **B. Data / bootstrap** | `{$lua}` `AOBScan(..., '+W-C')` + `RegisterSymbol` | Writable blob header / constants |
| **C. String / RTTI anchor** | Rarely the inject itself | ASCII/UTF-16 name → xref → code |
| **D. Struct / defaults** | Comments + value rows | Known floats/ints near each other |

Same ranking ideas apply; **validation** differs (code: disasm+symbols; data: field samples).

---

## End-to-end workflow (any AA entry)

```text
1. Inventory     alDump / alGet <id>  → CLASS=AA? SCRIPTLEN? parent/children
2. Harvest       al_get_script(id)    → pattern, module, ORIGINAL CODE, author hints
3. Baseline scan aobscanmodule / AOBScan → count hits, module of each
4. Rank hits     disasm + named calls + string proximity + runtime checks
5. Retune        if 0 or all bad: shorten / wildcard / alternate class (C/D) / named API
6. Write back    al_set_script (new pattern + refreshed ORIGINAL + anchors in comments)
7. aaCheck       then enable ONE id (timeout ≥ 120)
8. Validate      symbols, child EXPR, expected value behavior
9. Version tag   alSetDesc [Cheat][<ver>] … only after step 8 succeeds
10. User saves   .CT in CE (agent does not saveTable)
```

**Never** mass-enable many AA rows while retuning.

---

## Step 1–2: Harvest the script (gold)

From `al_get_script(id)` extract:

| Field | Why |
|-------|-----|
| `aobscanmodule(SYM, module.dll, bytes)` or Lua `AOBScan(pat, prot)` | Primary pattern + scope |
| `[ENABLE]` / `[DISABLE]` restore bytes | Must stay consistent with inject length |
| `registersymbol` / `alloc` names | What children depend on |
| **ORIGINAL CODE** block | Opcode sequence for ranking (ignore stale *names*) |
| Header hints | Secondary RVAs, “rax = Foo”, default values, version history |
| Child memrecs | Expected address expr (`[SYM]+off`, `playerStat + 2e38`) |

**Rule:** Trust **bytes and register roles** in ORIGINAL CODE. Treat function names like `SomeGuiThing+8F3` as **optional hints only** — they often come from an old CE auto-label and can be completely wrong on the next build.

---

## Step 3: Scan effectively

### Prefer module scope

```text
# In AA (best for injects):
aobscanmodule(INJECT, gamedll_ph_x64_rwdi.dll, AA BB CC ...)

# Native remote discovery:
AOBScan AA BB CC ** DD
enumModules   → filter hits into [base, base+size)
```

### Pattern crafting

| Technique | When |
|-----------|------|
| Full unique sequence (8–16+ bytes) | Stable sites; still verify multi-hit |
| Include following opcode | Disambiguate identical stores |
| `**` wildcards | Changed immediates, RIP-rel displacements, call offsets |
| Short core + rank | When long pattern dies after patch |
| Avoid 2-byte-only code AOB | Thousands of false hits |

**Data/bootstrap:** prefer distinctive constant runs (repeated `1.0f`, headers). Protection `+W-C` only when the blob is writable; wrong protection flags can crash or return garbage — prefer native `AOBScan` command over risky Lua protection strings.

### Timeouts / safety

- Client **≥ 120s** for large AOBs  
- Prefer native `AOBScan` over huge `runScript` scans  
- Avoid `enumMemoryRegions` / `createMemScan` / `varscan_*` from the pipe thread  
- Cap analysis loops; pcall reads  

---

## Step 4: Rank hits (never first-hit wins)

Score each candidate. Higher score wins; require a minimum bar before enable.

| Signal | Code inject | Data bootstrap |
|--------|-------------|----------------|
| **Module** | Must match script module (or updated module name) | Writable region / expected module |
| **Exact disasm at hit** | Matches inject instruction | N/A — check surrounding constants |
| **Context window ±0x40–0x100** | Matches ORIGINAL math/control flow shape | Neighbor defaults match CT docs |
| **Named APIs nearby** | `call` / IAT resolves to known `Module.Class::Method` | Rare; sometimes vtable in module |
| **Strings nearby / same fn** | Feature strings (`…::State`, tag names) | N/A |
| **Runtime** | Enable → symbol set; children resolve; value type/range/behavior | Same for registered bases |

### Disasm ranking (remote-safe sketch)

```lua
-- runScriptSafe: sequential disasm from hit (or hit-0x40)
local a=0xHIT; local out={};
for i=1,32 do out[#out+1]=disassemble(a); a=a+getInstructionSize(a); end
return table.concat(out,' || ')
```

Resolve indirect calls:

```lua
-- after seeing: call qword ptr [IAT]
return getNameFromAddress(readQword(0xIAT) or 0)
```

`getNameFromAddress` on many gameplay modules returns only `module+RVA`. **Engine/export-rich modules** often demangle — use those as anchors.

### Multi-hit decision rule

```text
if hits == 0: go to "Zero-hit recovery"
if hits == 1: still disasm once (confirm not mid-instruction noise)
if hits >= 2: rank; enable only the winner; document losers in comments
```

---

## Step 5: Zero-hit recovery (AOB failed)

Ordered fallbacks — stop when you can rebuild a pattern that ranks cleanly.

1. **Shorten** to the inject opcode only; re-rank heavily (noisy).  
2. **Wildcard** changed fields (disp8/32, imm, RIP-rel) one at a time.  
3. **Named API anchor**  
   - `getAddress Module.Class::Method`  
   - Find call sites / xrefs (disasm scan, string → code, or known IAT)  
   - Walk to the store/load you care about  
   - Re-derive AOB from **new** bytes  
4. **String / debug anchor**  
   - `AOBScan` unique ASCII (`FeatureName::`, error strings, tag enums)  
   - Move from data ref to code that uses it  
5. **Value → writer**  
   - Find live value (float/int) that matches the cheat’s semantics  
   - Debugger “what writes” (limited over remote TCP — hand off if needed)  
6. **Author secondary hints** in the old script header (other RVAs, related loads)  
7. **Sibling cheats** in the same CT that still work — shared modules, similar ORIGINAL style  

After recovery: write **pattern history** into the AA header (date, old bytes, new bytes, how you ranked).

---

## Step 6–8: Write, check, validate

```python
ce.al_set_script(id, new_text)
ce.aa_check(id)                          # or al_set_active runs aaCheck on AA
ce.al_set_active(id, True, timeout=120)  # ONE script
ce.get_address("SYMBOL")                 # or sym_get
ce.al_resolve(child_id)                  # EXPR children
# sample values: readFloat / al_get value fields
```

Validation checklist:

- [ ] `aaCheck` OK  
- [ ] Enable without modal hang (user dismisses dialogs)  
- [ ] Expected symbols resolve  
- [ ] Dependent rows resolve / sensible values  
- [ ] Toggle/freeze/behavior matches cheat purpose  
- [ ] Disable restores cleanly if tested  

On failure: `al_disable_soft` / disable, do **not** leave half-broken hooks without noting it.

---

## Step 9: Version the MEMORY description

Many trainers use:

```text
[Cheat][<version>] <Title…>
```

```python
ce.al_set_desc(id, "[Cheat][1.93] My Cheat Title…")
```

| Situation | Action |
|-----------|--------|
| Pattern unchanged, still verified | Keep existing version tag **or** set to the game/build the user tracks |
| Pattern retuned | Update tag to the **verified** game version string (user’s scheme) |
| Exact product version unknown | Prefer honest notes in AA header (`Game build ~YYYY-MM-DD, product ver uncertain`) over inventing a tag |

**Caveat:** if the AA script does `getMemoryRecordByDescription('…old…')`, update that string in the script in the **same** change.

Address-list rename = `alSetDesc`. Structure rename = `stSetName` after `stEnd` — different API.

Also refresh AA header fields when you verify:

```text
Date   : <today>
Verified: <today> — AOB OK on <process> / notes
```

---

## Pattern quality cheatsheet

| Good | Bad |
|------|-----|
| Module-scoped inject AOB | Full-process 3-byte code pattern alone |
| ORIGINAL bytes + named anchors in comments | Only absolute addresses |
| Multi-hit ranking recorded | “First result” |
| Child validation after enable | Assume enable == correct site |
| Wildcard only drifted fields | `**` everywhere |
| History table of patterns per game ver | Overwrite with no history |

---

## Worked examples (not the skill body)

| Example | Where | Class |
|---------|-------|-------|
| DL2 freeze time inject + multi-hit + engine names | `game/DyingLight2/time-weather/` | A code inject |
| DL2 playerStat writable bootstrap | `game/DyingLight2/player-variables/` | B data |
| DL2 module / API hierarchy lookup | `game/DyingLight2/FUNCTION-CATALOG.md` | C/D anchors |

When porting **any** other CT row: stay in **this** skill; open a game folder only for **anchors and semantics**.

---

## Remote command cheat sheet

| Need | Command / helper |
|------|------------------|
| Script in/out | `al_get_script` / `al_set_script` |
| Scan | `AOBScan <pat>`, AA `aobscanmodule` |
| Modules | `enumModules` |
| Symbol | `getAddress`, `sym_get` / `sym_set` |
| Name at PC | `runScriptSafe return getNameFromAddress(a)` |
| Disasm walk | `disassemble` + `getInstructionSize` |
| IAT name | `getNameFromAddress(readQword(iat))` |
| Strings | `AOBScan` hex of ASCII; `readString` |
| Rename row | `alSetDesc` / `al_set_desc` |
| Enable | `aaCheck` → `alSetActive` timeout ≥ 120 |

---

## Stop and ask the user when

- Hits stay ambiguous after ranking  
- Enable requires breakpoints / UI debugger events  
- Cheat is multiplayer / AC sensitive without explicit OK  
- Semantics changed (not just bytes) — e.g. feature removed  
- Exact game version tag required for MEMORY and user did not specify  
