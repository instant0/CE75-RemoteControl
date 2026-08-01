# Strategy: find **live** Health and Money (current build)

**Goal:** Addresses (or stable CE symbols) for:

1. **Current player HP** (what the HUD shows / combat uses)  
2. **Old-world money** (wallet cash integer)

**Not the goal:** Only re-enabling `playerStat` config floats (useful, but **not** live HP/cash).

**Related:** [host-notes-extract.md](host-notes-extract.md), [health-money.md](health-money.md), [player-variables.md](player-variables.md)

---

## Mental model (start here)

```text
                    ┌─────────────────────────────┐
                    │  PlayerDI_PH  (entity hub)  │
                    └─────────────┬───────────────┘
              ┌───────────────────┼───────────────────┐
              ▼                   ▼                   ▼
     PlayerHealthModule    InventoryContainer    PlayerState
              │              (+0x560 hist.)         +0xE8
              ▼                   │                   ▼
         LifeHealth          InventoryMoney    FloatPlayerVariable
         +0x1C = HP          +0x38 = CASH       (config only)
```

| Want | Object | Offset | Type |
|------|--------|--------|------|
| **Live HP** | `LifeHealth<HealthFactors>` | **+0x1C** | float |
| **Max HP (runtime)** | same | **+0x2C / +0x30 / +0x34** | float |
| **Cash** | `InventoryMoney` | **+0x38** | int32 |
| Config MaxHealth | `playerStat` | **+0x3438** | float (optional later) |

---

## Recommended order of operations

Do **money first** (4-byte int, constant UI readers, clear `+0x38` pattern).  
Then **HP** (float, shared type with enemies — needs care).  
Then optional **hub** (PlayerDI) and **playerStat** config.

---

## Phase 1 — Live money (primary)

### 1A. Classic CE value path (fastest with HUD)

1. Note on-screen **cash** (exact integer).  
2. CE: 4-byte scan → that value.  
3. Spend or earn a little → **next scan** decreased/increased.  
4. Narrow to a few candidates.  
5. **Find out what accesses this address** (value access log — does **not** stop the process).  
6. Prefer code that looks like:

   ```text
   mov r32, [reg+38]     ; 8B ?? 38
   ```

   with `reg` = base of the money object.

7. In the access log / register snapshot:

   - Treat **that base** as **`InventoryMoney`**.  
   - Check **`[base+0x18]`** → should look like a heap object (PlayerDI).  
   - Confirm **`[base+0x38]`** is your cash and tracks spend.

8. CE: add address `InventoryMoney+38`, or AA that does `registersymbol(InvMoney)` on first hit.

### 1B. Code AOB path (good for remote / repeatable)

Historical reader (gamedll):

```text
8B 51 38                 mov edx,[rcx+38]
48 FF A0 D8 00 00 00     jmp qword ptr [rax+000000D8]
```

or nearby:

```text
8B 41 38                 mov eax,[rcx+38]
```

1. `aobscanmodule` on `gamedll_ph_x64_rwdi.dll` for a unique enough slice of that reader.  
2. Multi-hit: rank by disasm (vtable jmp after load).  
3. Inject or BP/access on that site: **RCX = InventoryMoney** when reading **your** wallet (open inventory / vendor if needed).  
4. `registersymbol(InvMoney)`; child `[InvMoney]+38`.

### 1C. From PlayerDI (if you already have hub)

Historical:

```text
PlayerDI_PH + 0x560 → InventoryContainerDI
InventoryContainerDI + 0x38 → InventoryMoney*
InventoryMoney + 0x38 → cash
```

1. Obtain PlayerDI (Phase 3).  
2. Read pointer chain; if `+0x560` fails, pointer-scan for **InventoryMoney** from known cash or reverse from Phase 1A base.

### Validation checklist (money)

- [ ] Value matches HUD cash  
- [ ] Changes on purchase / quest reward  
- [ ] Object has sensible pointers at +0x18 / +0x80  
- [ ] Not an InventoryItem stack at +0x10 (craft mat counts)

---

## Phase 2 — Live current HP

### 2A. Value path (player only)

1. Note HUD HP (float or “looks like float”).  
2. Scan **float** → take **light damage** (fall) → next scan / decreased.  
3. Heal or regen → increased.  
4. **What accesses / what writes** this address.  
5. Prefer bases CE labels (or RTTI) as **`LifeHealth`** / `lifecs::PrivHealth::…`.  
6. Confirm:

   | Offset | Expect |
   |--------|--------|
   | **+0x1C** | Current HP (tracks damage) |
   | **+0x2C..+0x34** | Max ≈ full health bar |

7. Reject candidates that:

   - Stay at max while you take damage  
   - Are **playerStat+3438** (config max, doesn’t drop with damage)  
   - Belong to the **enemy** you just hit (damage someone else, ensure your HUD number is the one that moved)

### 2B. Damage-code path (from 1.93 notes)

Find gamedll code similar to:

```text
movss [rcx+0C], xmm1
movss [rcx+08], xmm1
movss [rcx+04], xmm1
ret
```

or any `movss` store into LifeHealth range while **you** take damage.

On hit frames, notes often had **R12 = LifeHealth**. Capture that pointer → HP at **+0x1C**.

### 2C. From PlayerHealthModule

If you have module base (dissect / access log):

1. Dump pointers at **+0x48** and **+0x88** (both seen in history/CT).  
2. For each pointer, check RTTI / vtable in gamedll and floats at +0x1C.  
3. Keep the one that tracks **your** damage.

### Validation checklist (HP)

- [ ] Drops when you take damage  
- [ ] Rises when healing / regen  
- [ ] Max fields consistent with full bar  
- [ ] Freezing +0x1C (optional test) affects survival / HUD as expected  
- [ ] Not confused with enemy LifeHealth

---

## Phase 3 — Player hub (unlocks both graphs)

Any one of these is enough:

| Method | How |
|--------|-----|
| **A. From money** | `InventoryMoney+0x18` → PlayerDI_PH |
| **B. From item UI** | Access item use/tooltip; notes: `ItemDescWithContext+0x130` → PlayerDI |
| **C. Engine** | Resolve `engine_x64_rwdi.IGame::GetLocalPlayerEntity` (and/or `ILevel::GetIPlayerManager`); find callers or call carefully from CE Lua if safe |
| **D. Debug / FPV** | Historical: invisible debug → RAX FloatPlayerVariable, RCX PlayerDI; or PlayerState+0xE8 → FPV |

Once PlayerDI is known:

- Walk inventory container for money (Phase 1C)  
- Walk health module for LifeHealth (Phase 2C)  
- Optional: PlayerState → FPV for config

---

## Phase 4 — Config blob (`playerStat`) — optional

Only after or in parallel if you want MaxHealth **defaults**, buy/sell factors, stamina cheats:

1. Retune writable AOB bootstrap (see [player-variables.md](player-variables.md)).  
2. Or: from PlayerState+0xE8 / FPV instance once hub is known.  
3. **Do not** stop the HP/money hunt just because playerStat is stale.

---

## Remote / agent workflow (this repo)

| Step | Who | Tool |
|------|-----|------|
| Value scan + access log | User in CE UI | “Find what accesses” (continues; does not freeze) |
| Paste register snapshot / base addresses | User | Chat |
| AOB money reader / confirm `+0x38` | Agent | `AOBScan`, `readInteger`, `runScriptSafe` light reads |
| Register symbols / table rows | Agent | `symSet`, `alSetAddress`, `alSetDesc` |
| Heavy pointer scans | Prefer CE UI | Avoid server-killing scripts |

Server hygiene: log `EXEC start` (v1.8.2+); client `CE_SESSION_LOG=1`; no huge unguarded walks.

---

## Failure modes (known)

| Symptom | Likely cause |
|---------|----------------|
| Money scan hits item counts | Looking at InventoryItem+0x10 not InventoryMoney+0x38 |
| HP freezes but bar moves | Wrong float (display copy / lag) |
| HP is always full | Config MaxHealth or wrong entity |
| Access log spam | Normal for money UI — filter `+0x38` / InventoryMoney |
| Time BP registers | DayNightCycle — **not** player (see scraps) |
| Server dies mid-command | Bad CE API / script — not value BP |

---

## Success criteria (done)

1. **Symbol or address** for InventoryMoney (or cash field) verified against HUD.  
2. **Symbol or address** for player LifeHealth+0x1C verified against damage.  
3. Documented in [health-money.md](health-money.md) with **build date / YYYYMMDD** and how found.  
4. Optional: PlayerDI base + chain offsets for this build.

---

## Change log

| Date | Note |
|------|------|
| 2026-08-01 | Strategy written from host-note re-mine + existing CT/PDB KB |
