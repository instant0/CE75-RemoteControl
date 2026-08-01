# AOB code drift — signals for relocating inject sites

When a Cheat Engine `aobscanmodule` pattern dies after a game update, the inject site often still exists nearby in spirit: same math, same control flow, slightly different bytes. **Drift classification** turns “0 hits” into a deliberate search instead of random pattern shortening.

Game-agnostic. Worked DL2 cases live under private notes / `docs/game/DyingLight2/` extracts.  
Companion: [ce-aob-scan skill](../skills/ce-aob-scan/SKILL.md), [CE-TABLE-OFFLINE-EDIT.md](CE-TABLE-OFFLINE-EDIT.md).

---

## Version labels (do not conflate sources)

| Label source | Use for | Do **not** use for |
|--------------|---------|---------------------|
| **Game EXE** product/file version string (e.g. user-facing **1.28**) | CT tags `[Cheat][1.28]`, human “this table is for game 1.28” | Claiming a DLL/PDB match |
| **gamedll SHA-256** + PE `TimeDateStamp` | Offline AOB truth for *this binary* | Product marketing version by itself |
| **DLL embedded RSDS** (GUID, age, build-machine PDB *path*) | Proving whether a **matching** PDB exists; build forensics only | Product version (path segments like `patch28` are **not** the game version) |
| **On-disk `.pdb` file** | Name/type vocabulary *if* you treat it as **unmatched / historical** | Addresses, offsets, or “this is the 1.28 PDB” |

**Rule:** If the only version string you trust is on the **game EXE**, put **1.28** (or whatever it says) on CT descriptions — and still key offline work to **gamedll SHA**, not to “1.28” alone. Never infer game version from Hudson/CI folder names inside RSDS paths.

---

## ORIGINAL CODE dumps in AA scripts (high value)

Many CE inject scripts end with a `{ … }` comment block that pastes **Cheat Engine’s “ORIGINAL CODE - INJECTION POINT”** disasm from an older session. Treat that as a **shape template**, not live addresses:

| Extract from the dump | Why |
|----------------------|-----|
| Inject instruction(s) | What you hook / NOP |
| **±5–15 instructions** before/after | Island fingerprint for Path A/B search |
| Register **roles** (obj in rsi vs rdi vs rbx) | Expect D2 reg drift; search all reasonable bases |
| Field **displacements** that repeat (`+0x30` store, `+0x28` ptr) | Often more stable than the AOB’s full byte string |
| Second dump with another reg | Same algorithm, different compile — proves which parts are essential |

**Workflow when exact AOB is 0 hits:** (1) list stable ops from ORIGINAL dumps → (2) scan module for that island with reg/disp wildcards → (3) rank with control flow → (4) rebuild AOB from **current** bytes at the winner.  
Worked example: Unlimited buff time — old `mov rcx,[rsi+28]; subss` dead; island `subss xmm1,xmm7` + `movss [obj+30]` + `seta` unique at new RVA.

---

## Strings and RTTI — tools, not scraps (and not the first tool)

DLL **strings** and **MSVC RTTI** (`.?AV…` names) are a **separate recovery channel** when code-shape search fails or ranks poorly. They are **not** a substitute for AOB on a healthy island.

| When | Use strings / RTTI? | Role |
|------|---------------------|------|
| **D1/D2** — island still finds 1 strong hit | **Optional** | Confirm “we’re in a buff/time/inventory-ish area” only if you already have names |
| **D3/D4** — disp/global drift | **Rarely** | Code/RIP parse still primary |
| **D6** — island gone / multi-hit soup | **Yes — primary next step** | Name → `.rdata` hit → xref to code → re-derive inject |
| Struct field naming for CE dissect | **Yes (soft)** | Type names; still verify offsets live or from code |
| Unmatched **PDB** | Same as strings | Demangled vocabulary only; then search **current** DLL |

**What they give you**

- **Existence:** system still present (`DayNightCycle`, `GuiAmmo…`, buff/status type names).
- **Xref landing zones:** functions that reference the name — candidates to disasm for the store/sub you care about.
- **Disambiguation:** two similar `subss` sites — the one near `…Buff…` / inventory strings ranks higher.

**What they do not give you**

- A ready-made inject AOB (you still pattern the **code**).
- Correct field offsets without reading the code that uses them.
- Proof that a string’s RVA is an inject site (almost never).

**Practical order:** ORIGINAL dump island → wildcard/reg variants → **then** strings/RTTI/PDB-names → value/writer last.

---

## Is drift just “everything slid by +0x300”?

**Usually no.** A pure **RVA slide** (one insertion earlier in the image so every later address moves by the same Δ) is only one special case. Treat it as a **hypothesis to test**, not the default model.

| Kind | What happens | Symptom | Useful? |
|------|--------------|---------|---------|
| **Uniform slide (size shift)** | Bytes inserted/removed earlier; later **identical** code keeps the same relative layout | Many old AOBs still unique; `new_RVA ≈ old_RVA + Δ` with **same Δ** for several unrelated sites | Only if Δ is **consistent** across ≥3 independent sites |
| **Section growth / re-link** | `.text`/`.rdata` sizes change; functions reorder | RVAs jump by **different** amounts per site | Common across big game patches |
| **Local rewrite (our D2–D6)** | Compiler/regalloc/inlining changes **bytes** at the site | Exact AOB **0 hits**; island still findable | **Primary** model for CE ports |
| **Data-only move** | Globals/strings move; code shape stable | Code AOB OK; hardcoded `module+RVA` / GLOBAL dead | D4 / static address retune |

**How to test slide in 30 seconds**

```text
1. Take 3+ unrelated inject sites with known old_RVA and new_RVA (or old AOB still unique → new hit RVA)
2. Compute Δ_i = new_i - old_i
3. If all Δ_i equal (or equal within a few bytes of alignment) → slide hypothesis OK for *that* range
4. If Δ_i differ a lot → do NOT add a constant to the rest of the table; use AOB/island per entry
```

**Worked counterexample (DL2 gamedll under test vs historical CT dumps):**  
Arrows, buff tick, old time inject comment, and PlayerVariables global do **not** share one Δ (deltas range from tens of KB in `.data` to multi‑MB in `.text`). So this port is **not** “add 0xN to every offset.” Even when an AOB is unchanged (time island), the new RVA is not predicted by another feature’s slide.

**When slide *does* appear:** small hotfix builds, single inserted function early in a TU, or comparing two almost-identical builds. Still verify with AOB — never migrate a whole CT by `old+Δ` alone.

**Implication for agents:** do not spend time hunting a magic Δ first. Prefer AOB + ORIGINAL island. Only after several retunes show the **same** Δ, you may use slide as a **soft hint** for the next candidate (still confirm with pattern uniqueness).

---

## Why drift helps

Exact AOB failure modes differ:

| What broke | Typical symptom | Relocation strategy |
|------------|-----------------|---------------------|
| **Stable island** | Same multi-op pattern, **new RVA** only | Keep AOB; update notes/RVA |
| **Register / ModRM drift** | Core opcode same; one `lea`/`mov` reg changed | Wildcard reg nibble **or** rebuild AOB with new reg; require same **following** ops |
| **Disp / imm drift** | `+0x5C` → other; call rel32 changed | Wildcard disp/imm; keep opcode skeleton |
| **RIP-relative global drift** | Getter shape lives; `[rip+rel]` target RVA moved | AOB on **code**, parse new global (don’t hardcode old GLOBAL_RVA) |
| **Stack frame drift** | `[rsp+58]` → `[rsp+48]` in ORIGINAL dump | Don’t require stack offs in AOB; use them only as soft rank signals |
| **Uniform RVA slide** | Many sites share one `new-old` Δ; AOBs often still match | Optional soft hint only; still AOB-verify (see section above) |
| **Control-flow rewrite** | Pattern gone; function restructured | String/RTTI/named API → re-find site; higher risk |
| **Semantics gone** | Feature removed / inlined away | Stop; don’t force an inject |

Recording **which class** each retune was builds a **prior**: e.g. “this table’s gamedll often only changes volatile regs in lea” → try ModRM-adjacent variants before full redesign.

---

## Drift classes (taxonomy)

### D1 — Stable island (bytes unchanged)

- **Signal:** Full CT AOB still **unique** on new module.  
- **Action:** Keep pattern; note new RVA; retag game version if verified.  
- **Example (DL2 gamedll under test):** Time store `F3 0F 11 43 5C F3 0F 10 4B` still 1 hit (RVA moved vs old dumps).

### D2 — Register / ModRM drift (high-value signal)

- **Signal:** Inject opcode intact (`sub ebx,edi`, `movss [reg+disp],xmm`); **adjacent** instruction only changes register encoding.  
- **x64 tip:** `49 8D 4A 10` (`lea rcx,[r10+10]`) vs `49 8D 49 10` (`lea rcx,[r9+10]`) — same length, one ModRM byte.  
- **Action:**  
  1. Scan inject opcode + **wildcard** the drifted byte(s).  
  2. Rank hits by **ORIGINAL control-flow shape** (cmp/jcc → sub → lea → mov → call).  
  3. Prefer **unique** lengthened AOB with the new fixed reg if one hit.  
- **Example (DL2):** Special arrows — old `2B DF 49 8D 4A 10` → new `2B DF 49 8D 49 10` (r10→r9).

**Why this is a strong “correct place” signal:** Random `sub ebx,edi` sites are common; **sub + lea reg+0x10 + mov edx,ebx + call** is a much tighter fingerprint even when one reg changed.

### D3 — Displacement / immediate drift

- **Signal:** Opcodes match; `disp8`/`disp32` or imm changed (struct field shift).  
- **Action:** AOB with `??` on disp; **live** or struct proof for new field; don’t assume old `+0x5C`.

### D4 — RIP-relative / global slot drift

- **Signal:** Small getter still AOBs; data absolute RVA in comments is dead.  
- **Action:** Primary = code AOB; secondary = parse `mov reg,[rip+rel]` → new GLOBAL_RVA.  
- **Example (DL2):** PlayerVariables global `0x36015C8` → `0x3609310` with resilient getter AOB.

### D5 — Prologue / stack / call-clobber drift

- **Signal:** ORIGINAL dump’s `mov rdx,[rsp+58]` no longer matches; inject core still finds.  
- **Action:** Treat stack offsets as **weak** rank features only; never sole AOB.

### D6 — Hard rewrite

- **Signal:** No near variant of the island; 0 hits even with heavy wildcards.  
- **Action:** String/RTTI/PDB-*names*/sibling cheats; or value→writer. Expect new AOB from scratch.

---

## Using drift as ranking signals (multi-hit)

When you expand wildcards and get N candidates, score:

| Weight | Signal |
|--------|--------|
| High | Same **inject instruction** (what you NOP/hook) |
| High | Same **post-inject island** (next 2–4 ops, allowing reg/disp wildcards) |
| High | Same **pre-inject control flow** (cmp/jcc into the site, early-out path) |
| Medium | Same **field displ** on the hooked op (`[rbx+5C]`) if still plausible |
| Medium | Nearby **string/RTTI** for the feature (if any) |
| Low | Absolute RVA closeness to old dump (ASLR/rebuild makes this weak offline) |
| Low | Old CE auto-label function name in comments |
| Reject | Hits mid-instruction; wrong module; only bare 2-byte opcode |

**Document losers** (RVA + why rejected) so the next port doesn’t re-open them.

---

## Zero-hit playbook (ordered, drift-aware)

```text
1. Exact CT AOB on module .text
2. If 0: classify expected drift from ORIGINAL CODE
     - reg-heavy lea/mov near inject → try D2 variants / ModRM wildcards
     - only rel32/call differs → wildcard E8 ?? ?? ?? ??
     - only disp differs → wildcard disp
3. Lengthen with stable ops AFTER inject (often better than lengthening before)
4. Rank with control-flow shape (D2/D5), not first hit
5. If still 0: D6 — strings / RTTI / sibling / live access
6. Write AOB history: old → new, drift class, hit count, RVA, game EXE version tag
```

---

## What to record every retune (tracker row)

| Field | Example |
|-------|---------|
| CT description (human name) | Unlimited Special Arrows |
| Game EXE version tag | 1.28 |
| gamedll SHA (short) | 07e6693f… |
| Drift class | D2 register/ModRM |
| Old AOB | `2B DF 49 8D 4A 10` |
| New AOB | `2B DF 49 8D 49 10` |
| Hits old→new | 0 → 1 |
| Inject RVA (new) | `0xDC1450` |
| Old RVA (if known) | for Δ / slide tests |
| Δ = new−old | only meaningful if compared across sites |
| Signals that confirmed | sub+lea+0x10+mov edx; jg into site |
| PDB used? | names only / no / mismatched |
| Live | untested / works / fails |

Keep a **running table** per game+EXE version (private ok) so later cheats reuse priors (“expect D2 on this build family”).

### Confidence / sample size

| Samples (retunes with class filled) | What you may claim |
|-------------------------------------|--------------------|
| **1–3** | Anecdotes; try the same strategy next, don’t hard-wire it |
| **4–7** | Short **prior playbook** (ordered heuristics) for this SHA |
| **8–15** | Stable prior for *this* gamedll SHA: which classes dominate, what to try first |
| **Live confirms mixed in** | Only then claim “works in-game,” not just offline island match |

---

## Empirical note — DL2 EXE 1.28 offline port (multi-edit)

Worked against one gamedll (SHA prefix `07e6693f…`, PE stamp 2026-07-02) and a large TEST CT. Private per-site cards and the full retune log live outside this doc; **methods and priors** are public.

### What the sample shows

| Observation | Evidence shape |
|-------------|----------------|
| **D1 dominates survivors** | ~10 main-table injects: active multi-op AOB still **unique**; only RVA moved vs historical dumps |
| **Uniform slide rejected** | Independent sites have **different** `new_RVA − old_RVA` (code Δs span different megabyte ranges; PV `.data` Δ is tiny and unrelated) |
| **D2 is real but minority** | Arrows: inject `sub` kept, lea base **r10→r9**. Buff time: obj reg **rsi/rdi→rbx**, AOB rebuilt from ORIGINAL island |
| **D4 for globals** | PlayerVariables: hardcoded GLOBAL dead; getter AOB + parse RIP |
| **Soft drift beside D1** | Quest timer inject field stable; **related** source fields moved. Parkour inject field stable; nearby imm/state nibble changed |
| **False-positive uniqueness** | Unique **byte** hit can be **mid-instruction** (e.g. 32-bit pattern inside 64-bit `mov`/`cmp`). Always disasm from match address |
| **Cross-site links survive** | Sibling bounty helpers still call each other after relocate — good ranking signal, not a slide |

### Prior playbook for *this* build family (ordered)

```text
1. Active (uncommented) aobscanmodule on gamedll .text
2. Instruction-boundary check (reject mid-REX / mid-imm)
3. If 1 unique + island matches ORIGINAL → D1; retag; do not trust old RVA
4. If 0 hits → D2 reg/ModRM from ORIGINAL (same inject op + neighbors)
5. If 0 → island search (stable field + ops); rebuild AOB from winner
6. Stack [rsp+xx] in AOB → expect D3/D5; wildcard stack, keep object field
7. Hardcoded module+RVA / GLOBAL → D4; AOB code first
8. Multi-hit soup / no island → D6 strings/RTTI/sibling; or leave needs_aob_retune
9. Never migrate table as old_rva + constant
```

### What “DEAD AOB” usually means here (not “feature gone”)

On this port, DEAD active patterns still often have a **relocatable shape** (vendor price stack slot, durability store field, free-upgrade index load). Failure modes seen so far:

| Failure | Typical class | Next move |
|---------|---------------|-----------|
| Exact AOB 0; close variants exist | D2 / D3 | Rank islands; new AOB |
| Pair of ops no longer adjacent | rewrite / D6 | Longer ORIGINAL context or strings |
| Unique hit mid-instruction | analysis trap | Reject; find true boundary |
| Stack disp only wrong | D3/D5 | Wildcard `[rsp+??]` |
| Many similar loads | multi-hit | Control-flow + filters from cave |

**Live status** for retagged D1/D2 sites was still untested when this note was written — offline `likely_works` ≠ confirmed in-game.
| **8–12+** with mixed features + some live confirms | Priors trustworthy as **default first try**; still rank islands |
| Only successes, no fails | Bias — also log multi-hit losers and dead ends |

Until you have a true **D6** (island gone → strings/RTTI) and a pure **D3** (disp-only) example, do not treat those classes as “common on this game.”

---

## PDB vs current DLL (relationship rules)

| Question | Answer pattern |
|----------|----------------|
| Does on-disk PDB match this gamedll? | Compare DLL **RSDS GUID+Age** to PDB; if GUID not present / age mismatch → **not related** as a symbol DB |
| Can an **old unmatched** PDB help AOB retune? | **Sometimes for names only** (types, systems, demangled vocabulary) → search those strings on **current** DLL, then xref to code |
| Does it fix register drift (D2)? | **No** — drift is in machine code; PDB won’t give the new ModRM |
| Does it validate inject RVA? | **No** if unmatched — addresses are wrong |
| Does RSDS path `…patch28…` mean game 1.28? | **No** — product version comes from the **game EXE** only |

**Unmatched PDB still useful for:**

- Inventory of systems (`DayNightCycle`, `PlayerDI`, ammo/inventory type names, …)  
- Confirming a string still exists on the new DLL before xref work  
- Cross-checking public RTTI/function catalogs  

**Unmatched PDB not useful for:**

- “Go to this RVA”  
- Struct field offsets as truth  
- Claiming the special-arrows `sub ebx,edi` site by symbol without code proof  

---

## Related

- AOB workflow: `skills/ce-aob-scan`  
- Offline CT: [CE-TABLE-OFFLINE-EDIT.md](CE-TABLE-OFFLINE-EDIT.md)  
- Live migrate: [TABLE-MIGRATE.md](TABLE-MIGRATE.md)  
