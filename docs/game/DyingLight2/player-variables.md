# Dying Light 2 — Player variables (playerStat)

Use when porting or debugging a CE table that uses **`playerStat`** / **`playerStatAlt`** symbols and dozens of `playerStat + offset` value rows (InfiniteStamina, glide, combat floats, etc.).

## Mental model (map + instance + dual values)

| Piece | Meaning |
|-------|---------|
| **`FloatPlayerVariable YYYYMMDD`** | **Name → offset** catalog only (registration walk). See [player-vars-array.md](player-vars-array.md). |
| **`playerStat` / `playerStatAlt`** | **Catalog live base** = registration origin (table EXPRs). On this build = **engine `this` + 8**. |
| **Engine object `this`** | Register from access log (e.g. RAX on HoldJump readers); **`[this]`** is module vtable; field e.g. HoldJump = `[this+0x2F90]`. |
| **Value address** | `playerStat + catalog_offset` (= `this + catalog_offset + 8`) |
| **Float/int entry** | Often **two** same-type cells: **actual** at `+0`, **base/config** at `+4`, then tail; next float entry commonly **+0x18** from named value in older expanded dissects. |
| **Expanded 1.90-style dissect** | Optional view of the **object** (headers, pairs, bytes). Old tables often **named only the value float**, not the whole entry — so layout can look “incomplete” even when offsets work for cheats. |

**Do not** treat the name-map structure as a substitute for finding `playerStat`.  
**Do not** treat a single default float (e.g. one `0.25`) as unique — use **value pairs + Glide (or other) multi-field gaps** from the current catalog.

Glide fingerprint detail and dual-value layout: **player-vars-array.md** (sections *Name map vs object dissect* and *How this helps Glide*).

---

## Discovering the live base: “Find what accesses” (preferred research path)

Once **any** field address is known (e.g. HoldJumpHeight after a GroupScan or a freeze test), use CE’s **access log** (not a freezing code BP) to recover the **object pointer the game uses**.

### What to click in CE

1. Memory View / address list → address of the **value** (e.g. HoldJumpHeight actual float).  
2. **Find out what accesses this address** (value access / page-guard style logging).  
3. Play briefly (jump, move) so readers fire.  
4. **Stop** the logger when a few unique code sites appear (often 2–5 is enough).  
5. Open each hit: note **instruction**, **base register**, **displacement**, and full **register dump**.

This does **not** freeze the game. Hits are logged while execution continues. Cancel when you have enough rows.

### Remote CE status (today)

| Capability | Remote (`ce_server` / `CERemote`) |
|------------|-------------------------------------|
| Read/write, `AOBScan`, `GroupScan`, symbols, table `al*` | Yes |
| “Find what accesses” / access log start-stop | **No** — UI/debugger path only for now |
| Freezing instruction BP + register snapshot API | **No** (not exposed) |

So: **you** run access logging in CE UI; paste hits here (or into docs). Remote can then parse RAX/offsets, register symbols, AOB the code RVAs, and update the table.

### Session proof (HoldJumpHeight, 2026-08-01)

Value watched: catalog HoldJump at `playerStat+0x2F88` → e.g. `211C729DFA0`.

Three gamedll sites (access log; game kept running):

| RIP (example) | gamedll RVA | Instruction | Meaning |
|---------------|-------------|-------------|---------|
| `…C0018F` | `+0xDE018F` | `mulss xmm7,[rax+0x2F90]` | scale by HoldJump |
| `…C31220` | `+0xE11220` | `mulss xmm6,[rax+0x2F90]` | scale by HoldJump |
| `…31307F` | `+0x14F307F` | `comiss xmm6,[rax+0x2F90]` | compare vs HoldJump |

**Every hit:** `RAX = 211C729B010` while catalog `playerStat` was `211C729B018`.

| Relation | Formula (this build) |
|----------|----------------------|
| Engine object (`this` / vars root in code) | **`RAX`** |
| Catalog / registration base (our table `0000`) | **`RAX + 8`** |
| HoldJump actual | `[RAX + 0x2F90]` = `[catalog + 0x2F88]` |
| Outer type pointer at engine `0000` | `readQword(RAX) = gamedll+0x2758428` (module vtable; this attach) |

So the **code base is 8 bytes before** the registration-map origin we call `playerStat`. The game indexes fields as **`[object + engine_off]`**; the name map’s offsets match **`object + 8 + catalog_off`** (i.e. catalog_off = engine_off − 8 for this layout).

`RCX` was shared across hits (`21300E59480`) — likely a **caller/player-side object**, not the variables blob. Spot checks of historical `+0xE8` on that RCX did **not** equal `RAX`/`playerStat` on this attach; treat as a lead for a future pointer chain, not a proven path yet.

### How this finds “0000” better than float defaults alone

1. **Recover object pointer** — any field access with a fixed displacement gives **`base_reg`** (here `RAX`) = **engine `0000`**.  
2. **vtable at `[RAX]`** — real module pointer; candidate signature for the **variables object type** (still may appear elsewhere; combine with size/field checks).  
3. **Hard-coded displacements in code** — e.g. `+0x2F90` HoldJump this build. After a patch, re-run access log on the new value address; new displacement → new catalog map if needed.  
4. **Generic vs special readers** — several sites using the **same** `[rax+disp]` means “object + field offset” readers (not one unique “god function” only). Still excellent for:
   - AOB of the instruction bytes (module-relative) once known  
   - Confirming base register  
   - Xref / “who loads RAX before this” for a **static pointer path** (globals, PlayerDI, etc.)

**Bootstrap direction (research → table):**

```text
known field value addr
  → Find what accesses (UI)  [measure hit counts; do not guess “cold”]
  → open coldest code site; disasm upward
  → find unique CODE AOB (or unique DATA at object start — rare)
  → at runtime: any register that holds the base (RAX/RCX/R13/…) is fine
  → RegisterSymbol(playerStat, base_or_basePlus8) to match table convention
```

### Bootstrap policy (what we want / do not want)

| Method | Role |
|--------|------|
| **Code AOB** (`aobscanmodule` in gamedll) + read a register / return value that is the base | **Preferred** for enable script |
| **Unique data signature at object start** (header only — not “every float element”) | Preferred **if** it exists and stays unique across ASLR |
| **GroupScan / multi-float defaults** | Research-only fallback when you have **no** address yet. **Not** the product bootstrap |
| Old data AOB (`08 **…** 80 3E 80 3E` + `hit+1`) | **Dead** on this build (ASLR / layout); was field-shaped, not a real object ID |

Table symbol may be **engine base** or **catalog base (engine+8)** — either is fine if **all EXPRs agree**. Any register is fine as the source: the goal is a **unique, stable place that yields the address**, not that the AOB address *is* the blob.

### Register symbols (catalog convention, this session)

```lua
-- engine this from access log / code hook
local eng = 0x211C729B010
registerSymbol("playerStat", eng + 8, true)   -- catalog 0000
-- HoldJumpHeight value = eng + 0x2F90  ==  playerStat + 0x2F88
```

---

## Code path: HoldJump `mulss` and where the base comes from

Site (module text; labels from CE — verify RVA against current `gamedll` base):

**`gamedll_ph_x64_rwdi.dll.text+E10220`** — `mulss xmm6,[rax+0x2F90]`  
(Often among the **lower** access counts vs `comiss` on the same field; **count hits**, do not assume opcode type.)

### Critical sequence (disasm paste, 2026-08-01)

```text
…+E101F5  movss  xmm0,[rbx]
…+E101F9  mov    rcx,[rdi+08]          ; RCX = some owner object (+8 from RDI)
…+E101FD  movaps xmm6,xmm0
…+E10200  minss  xmm6,xmm8
…+E10205  subss  xmm0,xmm6
…+E10209  movss  [rbx],xmm0
…+E1020D  mov    rax,[rcx]             ; RAX = *vtable* of RCX
…+E10210  call   qword ptr [rax+618]   ; virtual call, this = RCX
…+E10216  mov    edx,[gamedll.data+37D9C]
…+E1021C  mov    rcx,[rdi+08]          ; reload owner
…+E10220  mulss  xmm6,[rax+0x2F90]     ; RAX = vars base (HoldJump)
…+E10228  addss  xmm7,xmm6
```

**How RAX becomes `playerStat` (engine):**

On Win64, **`call` returns in RAX**. Immediately after `call [rax+0x618]`, the next use of RAX for `[rax+0x2F90]` means:

> **The virtual method at vtable offset `+0x618` of object `RCX` returns the player-variables object pointer in RAX.**

So the `mulss` line does **not** load the base from a global; the **vcall return value** is the base. That is still a perfectly good discovery mechanism:

```text
RDI  →  [RDI+8] = RCX (owner)
RCX  →  vcall +0x618
RAX  →  engine playerStat (this attach: …B010)
catalog table base = RAX+8 if using 20260801 map offsets
```

Nearby **module globals** (`mov edx,[gamedll.data+37D9C]`, counters at `+3725ED0`) are excellent **AOB glue** (distinctive RIP-relative immediates) even though they are not the vars pointer themselves.

### CE auto AOB result (this site, 2026-08-01)

CE AOB injection template chose:

| Item | Value |
|------|--------|
| Inject at | `gamedll….text+E10216` — **first insn after** `call [rax+618]` |
| AOB | `8B 15 80 FB 37 02` (`mov edx,[rip+rel32]` → data+37D9C) |
| CE comment | `// should be unique` |

**Placement is correct** for capturing the base: at inject entry, **RAX is still the vcall return** (engine vars pointer). Original template only re-executes `mov edx,…` and **never saves RAX** — useless for `playerStat` until patched.

**AOB caveats:**

- Bytes `80 FB 37 02` are the **RIP-relative displacement** for this instruction address. Stable for **this gamedll build** under ASLR (RIP-rel is module-local), **breaks when the DLL is recompiled / layout shifts**.
- A similar `mov edx,[data+37D9C]` appears earlier in the same function with a **different** disp (`D7 FB 37 02` at `+E101BF`) — so the full 6-byte AOB can still be unique; **verify** `aobscanmodule` → **1 hit** after every patch.
- Prefer optional longer AOB (include `call [rax+618]` / `mulss … 90 2F 00 00`) if the 6-byte form ever collides.

**Working bootstrap** (replaces old data `AOBScan` + `hit+1`). Full script for the AA entry — see below in-repo form; jump once after enable so RAX is captured.

Notes:

- Inject at post-vcall `mov edx,[data+37D9C]` (CE AOB `8B 15 80 FB 37 02`).  
- Cave saves engine base (RAX), writes catalog base (RAX+8) into a holder, restores RAX, runs original `mov edx`.  
- Lua timer promotes holder → `registerSymbol(playerStat, …)` so existing **`playerStat+off`** EXPRs keep working.  
- `playerStatAlt` is not filled by this path (live jump only).

---

## How Cheat Engine finds a “unique” AOB (source: CE 7.5)

Implementation: **`GetUniqueAOB`** in `frmautoinjectunit.pas` (AOB injection template).

### Algorithm (what CE actually does)

1. Take the **injection instruction** only; build an exact byte string of that instruction’s length.  
2. **FirstScan** that AOB inside the **module** (or whole process if no module).  
3. If **exactly one** hit → done (`resultOffset = 0`).  
4. If **many** hits: read **only ±20 bytes** around the address (plus the instruction length).  
5. Disassemble that window; mark bytes that look **relocatable** (RIP-relative, etc.) as wildcards `**` via `GetMaskFlags`.  
6. Grow the pattern **forward/back within that ±20 window** until **exactly one** match among the first-scan hits.  
7. If still not unique → **`ERROR: Could not find unique AOB`**.

### What that means for us

| CE says | Actual meaning |
|---------|----------------|
| “No unique AOB” on bare `mulss xmm6,[rax+2F90]` | Within **±20 bytes** + auto-masking, CE could not isolate one hit. **Not** “no unique signature exists in the whole function.” |
| Auto template fails | Look **elsewhere in the function**, lengthen **manually**, or change inject point to a rarer instruction sequence. |

### Can we do better than CE auto?

**Yes.** Manual AOBs routinely beat `GetUniqueAOB` because we can:

1. **Widen far beyond ±20** — include the `call [rax+618]`, both `mov rcx,[rdi+08]`, `minss`/`subss` block, `jae` above, etc.  
2. **`aobscanmodule(name, gamedll_ph_x64_rwdi.dll, bytes)`** — restrict to one module (huge uniqueness win vs full process).  
3. **Wildcard only true fixups** — keep distinctive opcodes + the **`90 2F 00 00`** displacement if still unique in-module; mask only the 4-byte RIP-relocs on `mov edx,[rip+…]`.  
4. **Pick a better inject address** — e.g. the **`call qword ptr [rax+618]`** line or the two-instruction pair `call` + `mulss`, not the `mulss` alone.  
5. **Accept 2–N hits** and rank (rare for enable; OK for research) — CE auto requires **1**.

So: auto-fail ⇒ **do not give up on code AOB**; expand or re-anchor. Give up only if **even a long module-local pattern** collides (then try another function, or data header, or pointer chain).

### Practical AOB building checklist

```text
1. aobscanmodule, not full-process, for gamedll code
2. Start from a multi-instruction island (call + mulss + cmp), not one float op
3. Wildcard RIP-relative disp32 only (?? ?? ?? ?? after 8B 15 / 89 05 / etc.)
4. Verify: scan → Count == 1 (or 2 if you intentionally want live+alt paths)
5. At runtime: capture whatever register holds the base (here post-vcall RAX)
6. Do not require the AOB address itself to equal playerStat
```

### Data-side unique signature (alternate)

Prefer **object start** only if something unique sits there (vtable **plus** layout that is not shared by thousands of slots). Shared float-slot type vptrs are **not** unique alone. Old CT data AOBs matched **interior float pairs**, not a clean object ID — that is why they rot under ASLR.

---

## Hit-count note (do not invent “cold”)

Measured on one HoldJump access-log session (same period):

| Site | Approx hits | Note |
|------|-------------|------|
| `comiss [rax+0x2F90]` | highest (~151) | Not “cold” despite being a compare |
| `mulss xmm7,[rax+0x2F90]` | mid (~73) | |
| `mulss xmm6,[rax+0x2F90]` (`+E10220`) | lowest (~15, ~per jump) | Prefer for research BP / hook |

Always **measure**; opcode intuition was wrong once already.

---

## Table shape (observed ~1.93-oriented CT)

| Piece | Role |
|-------|------|
| Bootstrap AA (TYPE=11) | Description like `[Cheat][1.93] Enable playervariables editing` |
| Enable path | `{$lua}` → `AOBScan(..., '+W-C')` → `RegisterSymbol(playerStat/Alt)` → sets own `.Address` |
| Value rows | **EXPR** addresses: `playerStat + 2e38`, not CE `Offset[]` chains |
| Group headers | “Expand on enable” / section labels |
| Other cheats | Separate `aobscanmodule(..., gamedll_ph_x64_rwdi.dll, ...)` inject scripts |

**Process / modules (example session):**

- `DyingLightGame_x64_rwdi.exe`
- Gameplay often in **`gamedll_ph_x64_rwdi.dll`** (inject AOBs)

## Bootstrap script pattern history

Comments inside the CT script:

| Build note | AOB head (writable, `+W-C`) |
|------------|------------------------------|
| 1.42 | `10 A0 96 ** ** ** ** 00 00 00 00 80 3E 00 00 80 3E ... 00 00 40 40` |
| 1.82 | `08 28 C7 ** ** ** ** 00 00 00 00 80 3E 00 00 80 3E ... 00 00 40 40` |
| 1.90 (active in CT) | `08 ** ** ** ** ** ** 00 00 00 00 80 3E 00 00 80 3E ... 00 00 40 40` |

Logic (legacy — **do not port as-is**):

```text
hits = AOBScan(pattern, '+W-C')
playerX = hits[0]; playerY = hits[1]   -- expects ≥2 hits
playerStat = playerX + 1
playerStatAlt = playerY + 1
RegisterSymbol(...); patch bootstrap row Address
```

**Retune target:** code AOB + post-vcall **RAX** (or unique object-start data). Not GroupScan primary; not this `hit+1` data pattern. See sections above.

### Live check (T00 session)

On one attached build, **full historical patterns returned 0 hits**. Shared float core still exists widely:

```text
00 00 00 00 80 3E 00 00 80 3E 00 00 00 00 00 00 00 00   -- hundreds of hits
```

So: **the CT’s AOB is version-specific and was already stale for that process.** Retune before trusting enable.

---

## Fast retune: locate `playerStat` (Glide multi-value group)

When the header AOB dies, **do not** brute-score every float with per-offset remote reads.

**Preferred:** CE **Grouped** scan of **several** Glide defaults at catalog-relative positions (actual + base twin).  
Full CE language + remote command: **[docs/CE-GROUP-SCAN.md](../../CE-GROUP-SCAN.md)** (source: `groupscancommandparser.pas`).

### Catalog offsets (`FloatPlayerVariable 20260801`)

| Field | Offset | Default hint | Twin at |
|-------|--------|--------------|---------|
| GlideStartStaminaCost | `+0x2820` | 0.34 | `+4` |
| GlideStaminaCost | `+0x2838` | 0.10 | `+4` |
| GlideNitroStaminaCost | `+0x2920` | 0.25 | `+4` |

### Manual / remote group command

```text
F:0.34 F:0.34 W:16 F:0.1 F:0.1 W:224 F:0.25 F:0.25
```

```text
playerStat = hit - 0x2820
```

- CE UI: Value type **Grouped**, paste command.  
- Remote (server ≥ v1.8.3): `GroupScan F:0.34 F:0.34 W:16 F:0.1 F:0.1 W:224 F:0.25 F:0.25`  
- Expect ~2 bases (`playerStat` / `playerStatAlt`).

### What not to do

- Scan **one** float, or **only** `F:0.25 F:0.25` (or any single-field twin pair) — thousands of hits; not a locate  
- N×M remote reads over TCP  
- Use **old** 1.90 offsets only without checking the current catalog  
- `createMemScan` inside `runScriptSafe` (banned; use **`GroupScan`** command)  

---

## Worked session: GroupScan → two heap hits → one live base (20260801)

### Method (keep this)

1. **Catalog** — `FloatPlayerVariable 20260801` (registration name → offset).  
2. **GroupScan** (multi-field Glide, dual actual/base floats + `W:` gaps):

   ```text
   F:0.34 F:0.34 W:16 F:0.1 F:0.1 W:224 F:0.25 F:0.25
   ```

   Hit = address of **GlideStartStaminaCost** actual (`+0x2820`).  
3. **Candidate base** — `playerStat? = hit - 0x2820`.  
4. **Reject noise** — many hits only almost-match Glide; require clean defaults (or known live values) at Glide offsets **and** spot-check **unrelated** catalog fields (e.g. CableMaxLength, NightVisionPower, SurvivorSenseRange) for sensible numbers, not garbage floats.  
5. **Reject DLL hit** — `gamedll_ph_x64_rwdi.dll+…` with the same defaults is a **static template**, not the live instance.  
6. **When two good heap bases remain** — both can look like full default blobs; **only one** is the active player instance. Disambiguate by fields that **diverge from default** on a living character (e.g. MaxStamina actual ≠ base twin), or by freeze/change test in-game on a known row. Do **not** assume both are equally “playerStat”.  
7. **Use** — `RegisterSymbol(playerStat, base)`; value addrs = `base + catalog_offset`.

### Session results (example attach)

| Group hit | Base (`hit-0x2820`) | Role |
|-----------|---------------------|------|
| `211C729D838` | **`211C729B018`** | **Likely live** — MaxStamina actual **5.2**, base twin **0.8** |
| `211C72BFAF8` | **`211C72BD2D8`** | Second full blob — MaxStamina still **0.8/0.8** (alt / inactive / defaults copy) |
| `gamedll+366E378` | (module) | Static defaults — ignore for live edits |
| other heap hits | — | Failed Cable/NV/Sense sanity |

Spot-checks on **good** bases (both): CableMaxLength **50/50**, NightVisionPower **0.5/0.5**, SurvivorSenseRange **60/60**, Glide **0.34/0.10/0.25** pairs.

| Field | Offset | Addr on live candidate `…9B018` | Addr on other `…BD2D8` | Value (both) |
|-------|--------|----------------------------------|-------------------------|--------------|
| HoldJumpHeight | `+0x2F88` | **`211C729DFA0`** | **`211C72C0260`** | **4.85 / 4.85** |

Confirm live base: freeze/change **HoldJumpHeight** or **MaxStamina** in-game on one address and see which affects the player.

**Confirmed live base (user-tested):** `0x211C729B018`  
(Old partial dissect starting at Aggresion as first *value* used `base+0x70` = header of Aggresion slot; named Aggresion remains at `base+0x78`.)

---

## Expanded dissect from name map (1.90-style)

| Piece | Role |
|-------|------|
| `FloatPlayerVariable 20260801` | Flat **name → offset** (registration) |
| `FloatPlayerVariable 20260801 Dissect` | Multi-element slots like 1.90 (header + actual + base twin + tail) |
| Generator (not in git) | `/mnt/r/dl2_fpv_dissect_from_map_20260801.lua` — **one** CE Lua run |

**Slot rules** (gaps from sorted map: mostly `0x18` float, `0x10` byte):

| Gap to next field | Expansion at catalog `off` |
|-------------------|----------------------------|
| `0x18` (float) | `ptr @ off-8`, **float named @ off**, float twin `@ off+4`, word, word |
| `0x10` (byte) | `ptr @ off-8`, **byte named @ off**, pad bytes, word |

Live checks on `0x211C729B018` after generate: Aggresion 0.25/0.25, HoldJumpHeight 4.85/4.85, GlideNitro 0.25/0.25, MaxStamina 5.2/0.8, CableMaxLength 50/50.

Open Memory View on `playerStat` and assign structure **`FloatPlayerVariable 20260801 Dissect`**.  

## How this AOB was found historically (port method)

Not pure code-xref only:

1. Identify **stable field defaults** (floats/ints documented in the table: MaxStamina ~0.8, jump heights, glide costs, etc.).
2. Scan / filter memory for those constants (often near dual `1.0f` = `00 00 80 3E` blocks).
3. Walk **back to a stable header/signature** that still marks the player variables blob after a patch.
4. Encode that signature as AOB (`+W-C` if it lives in writable data).
5. Validate: enable bootstrap → `playerStat` resolves → sample offsets match expected defaults → freeze/toggles behave.

Offsets **inside** the blob also drift between versions; structure names like `FloatPlayerVariable 1.90` in the CT are hints, not guarantees.

## Remote workflow (v1.4+ al* commands)

```text
1. tableStatus / alDump — find bootstrap ID (often CLASS=AA, desc contains playervariables)
2. alGetScript <id> — read {$lua} AOB pattern
3. AOBScan new candidate (** wildcards OK on native command)
4. Score hits: playerStat = hit+1; read known offsets vs defaults
5. alSetScript* — write updated pattern into bootstrap script
6. aaCheck <id>
7. alSetActive <id> 1  (timeout ≥120; only this bootstrap first)
8. getAddress playerStat / alResolve on EXPR children
9. alSetActive other inject AA only if intentional
```

**Do not** enable inject AA scripts while retuning playerStat unless intended.

## Renaming the bootstrap entry

Safe for display, **dangerous for this CT’s self-lookup**:

```lua
addressList.getMemoryRecordByDescription('[Cheat][1.93] Enable playervariables editing')
```

If you rename the description, update that string inside the AA script in the same change.

## Dissect structures

CT may contain large dumps (`PlayerState`, `FloatPlayerVariable 1.xx` with **tens of thousands** of elements). Prefer validating a few named offsets over cloning entire mega-structs unless necessary.

**Regenerating the name/offset map** (definition site, not live blob): see **`player-vars-array.md`** (historical Lua generator + 1.14 AOB still hits `AnimGraph_BankName`).

**Current HP / money amount** are mostly **not** in this blob — see **`health-money.md`** (`LifeHealth+0x1C`, `InventoryMoney+0x38`). Config **MaxHealth** is `playerStat + 0x3438` once bootstrap works.

## Related

- CE remote foundation: `skills/ce-table-remote`
- **AOB method (any entry):** `skills/ce-aob-scan`
- Remote scanning safety: `skills/ce-remote-scanning`
- DL2 modules + API catalog: `modules.md`, `function-catalog.md`
- PlayerVarsArray generator: `player-vars-array.md`
- HP & money: `health-money.md`
- Time / weather: `time-weather.md`
