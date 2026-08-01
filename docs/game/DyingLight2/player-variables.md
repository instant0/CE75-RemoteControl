# Dying Light 2 — PlayerVariables (live config vars)

**Canonical name:** **`PlayerVariables`** (game/PDB/container).  
**Legacy CT symbol:** `playerStat` / `playerStatAlt` — treat as old aliases for the **catalog base** of this object; new work should use **`PlayerVariables`**.

Use when porting or debugging table rows that are balancing/config floats (stamina, glide, HoldJump, buy/sell factors, etc.).

## Mental model (map + instance + dual values)

| Piece | Meaning |
|-------|---------|
| **`PlayerVariables`** | Live **aggregate** instance (config/balancing). Engine `this` + optional catalog origin at **`this+8`**. |
| **`FloatPlayerVariable YYYYMMDD`** | **Name → offset** catalog only (registration walk). See [player-vars-array.md](player-vars-array.md). |
| **Engine `this`** | Pointer game code uses. HoldJump = `[this+0x2F90]`. Outer RTTI at +0: **`StringPlayerVariable`**. |
| **Catalog base** | **`this + 8`** — origin for registration/map offsets (`HoldJump` map `+0x2F88`, etc.). |
| **Value address** | `PlayerVariables_catalog + catalog_offset` (= `this + 8 + off`) |
| **Slot types** | **`FloatPlayerVariable`**, **`BoolPlayerVariable`**, **`StringPlayerVariable`** (RTTI on cells / head) |
| **Float entry layout** | Often **actual** @+0, **base/config** @+4; stride often `0x18` |

**Do not** treat the name-map structure as a substitute for finding the live **`PlayerVariables`** instance.  
**Do not** use GroupScan / interior data AOB as the primary locator when a typed pointer chain exists (below).

Glide fingerprint / dual-value layout: **player-vars-array.md**.

---

## Game type identity (RTTI + strings, 2026-08-01)

**Goal:** locate the vars object the way the game names it (same class of solution as engine `GetTimeWeather*` / typed systems) — not only anonymous GroupScan / data AOB.

### Live instance (one attach; re-check after restart)

| | Address / note |
|--|----------------|
| Engine `this` (code base, RAX after getter) | `211C729B010` (example) |
| Catalog / CT `playerStat` | `this + 8` → e.g. `211C729B018` |
| gamedll base (same attach) | `7FFA1FE20000` |

### CE `getRTTIClassName` on live memory

| Location | RTTI class name |
|----------|-----------------|
| Engine object **`this` (+0)** | **`StringPlayerVariable`** |
| Float field slots (header = value−8), e.g. Aggresion, HoldJump, MaxStamina, Cable | **`FloatPlayerVariable`** |
| Byte/flag style slot (e.g. InfiniteStamina header) | **`BoolPlayerVariable`** |

Interpretation:

- The hooked base is **not** “a raw float array.” It is a **typed C++ layout**.
- **Front of object** reports **`StringPlayerVariable`** (first subobject / leading type).
- Cheat floats are **embedded `FloatPlayerVariable`** objects (vptr + actual + base twin + tail).
- Matches host/PDB hierarchy: **`PlayerVariables`** dataset composed of String / Float / Bool / Health variable types. See [player-vars-array.md](player-vars-array.md), [host-notes-extract.md](host-notes-extract.md).

### Shared type vtables (module-relative, this build)

| Type | vtable ≈ `gamedll+RVA` | Role |
|------|------------------------|------|
| `FloatPlayerVariable` | **`+0x26FE9C0`** | Per float slot header |
| Outer / string-leading object | **`+0x2758428`** | At engine `this+0` |
| `BoolPlayerVariable` | **`+0x2758448`** | Flag-style slots |

RVAs need re-check after gamedll update; resolve as `getAddress("gamedll_ph_x64_rwdi.dll")+RVA`.

### Type **name strings** in `gamedll` (AOB, few hits)

| String | ~Hits | Notes |
|--------|-------|--------|
| `FloatPlayerVariable` | 2 | RTTI / type info cluster |
| `BoolPlayerVariable` | 2 | same |
| `StringPlayerVariable` | 2 | same |
| `PlayerVariables` | 3 | container-level name (+ other refs) |

Example addresses that attach (`gamedll=7FFA1FE20000`):  
`FloatPlayerVariable` @ `7FFA230A1706`, `7FFA2314E304`;  
`PlayerVariables` @ `7FFA223230B8`, `7FFA2252D137`, `7FFA226690F6`.

**Do not** spam full-process string AOBs in a loop; these four names were enough to prove binary identity. Prefer module-limited scans or xrefs from these addresses.

### Naming: `PlayerVariables` vs RTTI pieces

| Name | Use |
|------|-----|
| **`PlayerVariables`** | **Canonical** name for the live aggregate we attach the table to (dataset / host notes / gamedll string). **Symbol for new work.** |
| **`StringPlayerVariable`** | RTTI at **engine `this+0`** (leading subobject type) — not a reason to rename the whole blob |
| **`FloatPlayerVariable` / `BoolPlayerVariable`** | RTTI of **individual slots** inside the aggregate |
| **`playerStat`** | **Legacy CT only** — same as catalog base of `PlayerVariables` |

### Accuracy ladder (preferred discovery)

| Rank | Method | Status (2026-08-01) |
|------|--------|---------------------|
| **1** | **Typed pointer chain** `PlayerState* → +0xBA8 → PlayerVariables this` (via static global or DI getter) | **Proved — preferred** |
| 2 | **`PlayerDI_PH` vtable +0x618** getter (returns same pointer) | **Proved** |
| 3 | Field access log / inject on consumers | Works; interim |
| 4 | GroupScan / interior data AOB | Research only |

---

## Most accurate / safe detection (proved 2026-08-01)

### Proven chain

```text
gamedll global  (RVA +0x36015C8 this build)
    →  pointer to PlayerState
PlayerState + 0xBA8
    →  PlayerVariables engine this
PlayerVariables catalog base
    →  engine this + 8
```

**Live check (same attach):**

| Step | Result |
|------|--------|
| Global `gamedll+0x36015C8` | → `211C3654E80` |
| RTTI of that pointer | **`PlayerState`** |
| `[PlayerState + 0xBA8]` | → `211C729B010` |
| RTTI @ that address | **`StringPlayerVariable`** (outer) |
| HoldJump `[this+0x2F90]` | 9.0 (edited); matches known field |
| Catalog base | `211C729B018` |

**Note:** Host notes mentioned **`PlayerState + 0xE8`** on older builds. On **this** build the live link is **`+0xBA8`**, not `+0xE8`. Always re-validate the offset after patches.

### How game code gets the same pointer (`PlayerDI_PH`)

`PlayerDI_PH` **vtable +0x618** (gamedll **RVA `+0xF74940`** this build):

```text
; RCX = PlayerDI_PH*
cmp  byte ptr [rcx+0x3790], 0
mov  rax, [gamedll_global]      ; PlayerState* (same global as above)
jne  use_rax                    ; if flag != 0, keep global
mov  rax, [rcx+0x6B0]           ; else alternate mid pointer
use_rax:
mov  rax, [rax+0xBA8]           ; → PlayerVariables engine this
ret
```

When `flag@DI+0x3790 != 0` (observed **1**): path is **global PlayerState* → +0xBA8**.  
`[DI+0x6B0]` was **0** on that attach (unused branch).

Callers (e.g. HoldJump `mulss`) do `call [rax+0x618]` with **RCX = PlayerDI_PH**, then use returned RAX as vars `this`.

### Recommended bootstrap (safe order)

**A. Preferred — static global + offset (no inject, no jump, no scan)**

```text
1. mb = getAddress("gamedll_ph_x64_rwdi.dll")
2. Resolve global slot:
   - Prefer: AOB the getter (below) and read its RIP-relative [rip+disp] target
   - Or this-build RVA: readQword(mb + 0x36015C8)   // re-AOB after patch
3. ps = readQword(global)                 // PlayerState*
4. assert getRTTIClassName(ps) ~ PlayerState (optional)
5. eng = readQword(ps + 0xBA8)            // PlayerVariables engine this
6. assert getRTTIClassName(eng) ~ StringPlayerVariable (optional)
7. sanity: readFloat(eng + 0x2F90) finite / known HoldJump-ish
8. registerSymbol("PlayerVariables", eng + 8)   // catalog base for map offsets
   // or register engine this if rows use engine offsets
```

**B. Unique code AOB on the getter (finds global after update)**

Module scan for function bytes (this build):

```text
80 B9 90 37 00 00 00    cmp byte ptr [rcx+0x3790],0
48 8B 05 ?? ?? ?? ??    mov rax,[rip+rel]     ; wildcard RIP
75 07                   jne +7
48 8B 81 B0 06 00 00    mov rax,[rcx+0x6B0]
48 8B 80 A8 0B 00 00    mov rax,[rax+0xBA8]
C3                      ret
```

- `aobscanmodule` → should be unique or rare.  
- Parse `mov rax,[rip+rel]` → **global address** (ASLR-safe).  
- Then same steps 3–8.  
- **No code cave required** for detection; inject only if you want to log calls.

**C. Interim — consumer inject** (HoldJump path, capture RAX after vcall)

Only if A/B fail after a patch. See older sections below.

### Sanity checks (do these; cheap)

| Check | Pass |
|-------|------|
| Mid RTTI | `PlayerState` |
| Eng RTTI | `StringPlayerVariable` (or still plausible vars head) |
| Float slot RTTI | `FloatPlayerVariable` at e.g. eng+0x2F88 header |
| Field sample | HoldJump / MaxStamina sensible |
| Two instances | Optional second blob exists; chain above is **live** path when flag uses global |

### Safety

| Do | Don't |
|----|--------|
| `aobscanmodule` on short getter | Full-process spam string AOB |
| `readQword` chain + RTTI pcall | `createMemScan` in remote `runScriptSafe` |
| Re-validate `+0xBA8` / global RVA after patch | Assume host `+0xE8` still valid |
| One light sanity float read | GroupScan as enable |

### Symbol / table migration

```text
registerSymbol("PlayerVariables", catalogBase)   // eng+8 for 20260801 map offsets
// Value rows: PlayerVariables+2F88  (or [holder]+off if pointer storage)
// Legacy: playerStat → same address; rename when convenient
```

---

## Table status audit (2026-08-01) — offsets, comments, bad values

### What was and was not done

| Change | Status |
|--------|--------|
| Bootstrap = **PlayerState+0xBA8** chain (no data AOB) | Script on enable AA updated |
| Symbol **`PlayerVariables`** (+ legacy `playerStat` alias on enable) | Yes |
| Rename Address EXPR **`playerStat` → `PlayerVariables`** | **Yes** (~100 rows) |
| Remap offsets to **FloatPlayerVariable 20260801** catalog | **Partial** — bulk name-match earlier (~40–50 rows); **not** a full verified pass |
| Update **Description comments** (old hex like `- 1080`, `- 2E38`) | **No — still stale** |
| Value types (byte vs float) vs catalog | **Not systematically fixed** |

### Why `InvisibleToEnemies` can show **192**

Not proof the **PlayerVariables base** is wrong (HoldJump / MaxStamina chain checks were coherent). More often:

1. **Stale offset** — row still at old CT offset (e.g. description says `1080`) while catalog moved; Address may still be `PlayerVariables+1080` if that row was **skipped** by name-match remap.  
2. **Wrong type** — flag is **`BoolPlayerVariable`** (byte); CE row as **4-byte float/int** reads neighboring payload → garbage like **192** (`0xC0`, often low byte of a float/vptr pattern).  
3. **Comment vs Address** — description still shows old defaults/offsets; ignore comments until rewritten from the map.

**Detection chain is still the preferred locator.** Bad single-row values ⇒ fix **that row’s offset + type** from **`FloatPlayerVariable 20260801`**, not abandon `PlayerState+0xBA8`.

### Required cleanup (when CE is healthy)

1. For each value row under the enable cheat: resolve name → **map offset**; set Address `PlayerVariables+<hex>`.  
2. Set **type** from slot kind (float vs byte/bool).  
3. Rewrite **Description** trailing hex to the **20260801** offset (or drop hex from comments).  
4. Spot-check: InvisibleToEnemies, InfiniteStamina, HoldJump, MaxStamina, Buy/Sell factors.

Until that pass: treat table as **partially ported**; do not trust every displayed value.

---

## Remote pipe / “server crash” notes (ops)

See **`skills/ce-remote-scanning`** — default model: **agent kills the server; reload restores it.**

| Symptom | Likely cause |
|---------|----------------|
| Server fine after user reload of `ce_server.lua` | Expected — stays up until broken |
| Relay: `Failed to connect to pipe` after earlier success | **Agent/command killed or hung** the Lua pipe thread — not “unavailable on restart” |
| CE: `EXEC done ok` + disconnect + new pipe | **Normal** session end — not a crash |
| CE: `EXEC start` without `done` | **That command** killed/hung the server |
| Connect fail until user reloads again | Server still dead/stuck — reload; fix the bad call, don’t spam reconnect |

**Health check:** one `ping` → `pong`. No pong ⇒ server is down (usually because we killed it).

---

## Next steps (remaining)

| Priority | Work |
|----------|------|
| **Done** | Name **`PlayerVariables`**; chain **PlayerState+0xBA8**; **PlayerDI_PH** vfunc **+0x618** |
| 1 | Wire CT bootstrap AA/Lua to chain **A** or **B** (drop data AOB / GroupScan enable) |
| 2 | After patch: re-AOB getter → new global; confirm **+0xBA8** |
| 3 | Optional: engine `GetLocalPlayer*` → `PlayerDI_PH` for full root (weather-style) |
| 4 | Rename table EXPRs `playerStat` → `PlayerVariables` when editing CT |

---

## Discovering the live base: “Find what accesses” (research path)

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
