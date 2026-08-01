# Dying Light 2 — Time / Weather research dump

**Status:** Live-verified inject site + named engine anchors (remote CE v1.8.1).  
**Verified:** 2026-08-01 (game package date noted ~2026-06-14; exact product version uncertain).  
**Process (session):** `DyingLightGame_x64_rwdi.exe`  
**Modules:** `gamedll_ph_x64_rwdi.dll` (inject), `engine_x64_rwdi.dll` (named TimeWeather APIs)  
**CT family:** 1.93-oriented trainer; freeze script author header Version **1.93b** (origin 2023-02-22, author `ins`)  
**Table IDs (this CT):** AA **193**, child EXPR **192** `[TIMESTRUCT]+5C`

**General AOB method:** `skills/ce-aob-scan` (this file is a **case study**, not the AOB skill).  
**API hierarchy lookup:** `function-catalog.md`  
**Modules:** `modules.md`

This dump records one feature so names, RVAs, and ranking signals are not lost.

---

## 1. Goal of the working cheat

**Freeze / control time of day** by capturing the gamedll object that owns a **normalized time float** and optionally writing it.

| Need | Mechanism |
|------|-----------|
| Find code that updates time each tick | AOB on `movss [rbx+5C], xmm0` + following load |
| Capture object | Hook saves **rbx** → symbol `TIMESTRUCT` |
| Freeze | Original store still runs, or UI freezes `[TIMESTRUCT]+5C` |
| Display / set | Child memrec float at `[TIMESTRUCT]+5C` |

CT note: day/night **visuals may not fully track** when only the float is forced (description says Day/Night visuals will not be affected).

---

## 2. CT script anatomy (ID 193)

### 2.1 Header comments (author intent)

```text
Game   : DyingLightGame_x64_rwdi.exe
Version: 1.93b
Date   : 2023-02-22
Author : ins
This script freezes time.

Secondary hint:
  gamedll_ph_x64_rwdi.dll+17B594B - movss xmm6,[rax+10]
  rax = daynightCycle, +10 example value ~0.39

Conversion:
  xmm0*24       → approximate hours
  xmm0*24*60    → approximate minutes
  (see cvttss2si / cvtdq2ps near inject)
```

**Use of secondary hint:** if primary AOB dies, scan for daynightCycle-style loads or re-find `+10` rate float near the same object family.

### 2.2 Enable / disable (logic — do not change casually)

```text
[ENABLE]
aobscanmodule(TIME, gamedll_ph_x64_rwdi.dll, F3 0F 11 43 5C F3 0F 10)
alloc(newmem,$1000,TIME)
alloc(TIMESTRUCT,8)
registersymbol(TIMESTRUCT)
...
newmem:
   mov [TIMESTRUCT],rbx
code:
   movss [rbx+5C],xmm0
   jmp return
TIME:
   jmp newmem
registersymbol(TIME)

[DISABLE]
TIME:
  db F3 0F 11 43 5C
unregistersymbol(TIME)
dealloc(newmem)
```

Pattern bytes:

| Bytes | Instruction (correct site) |
|-------|----------------------------|
| `F3 0F 11 43 5C` | `movss [rbx+5C], xmm0` |
| `F3 0F 10 …` | following `movss` load (script uses 3-byte prefix in AOB; full insn may be `F3 0F 10 4B 5C` = `movss xmm1,[rbx+5C]`) |

### 2.3 ORIGINAL CODE block — what to trust vs discard

The CT embeds a disasm snapshot labeled:

```text
INJECTION POINT: gamedll_ph_x64_rwdi.GuiGatherResources+8F3
```

**Discard the symbol name `GuiGatherResources`.** It is a stale CE debug/auto label from the author’s session, not a stable export for search.

**Trust the instruction sequence** (semantics):

```text
add eax,-04 / cmp eax,03 / ja …
movss xmm1,[rbx+80]  OR  [rbx+7C]  OR  [rbx+78]   ; speed/divisor by state
divss xmm0,xmm1
addss xmm0,[rbx+5C]
movss [rbx+5C],xmm0          ; <<< INJECT
movss xmm2,[rbx+5C]          ; (or xmm1 in live build — same idea)
comiss …
cvttss2si eax, xmm*
add [rbx+58], eax            ; day rollover
… subss / movss back to +5C
mov eax,[rbx+58]
```

Live disasm (one session) matched this chain at:

```text
…C12D  add eax,-04
…C130  cmp eax,03
…C133  ja …
…C135  movss xmm1,[rbx+80]
…
…C14B  divss xmm0,xmm1
…C14F  addss xmm0,[rbx+5C]
…C154  movss [rbx+5C],xmm0     ; INJECT / AOB head
…C159  movss xmm1,[rbx+5C]
…C16B  cvttss2si eax,xmm1
…C16F  add [rbx+58],eax
```

---

## 3. Live session map (example ASLR bases)

> Absolute addresses **move** every launch. Prefer **module+RVA** and **named symbols**.

| Item | Example absolute | Stable form |
|------|------------------|-------------|
| Inject `movss [rbx+5C],xmm0` | `7FFA210DC154` | `gamedll_ph_x64_rwdi.dll+12BC154` |
| Containing function start | `7FFA210DBF70` | `gamedll_ph_x64_rwdi.dll+12BBF70` |
| Call GetTimeWeatherSystem | `7FFA210DC0ED` | same function, earlier |
| Call FinishTimeWeatherInterpolation | `7FFA210DC0F6` | next IAT call |
| `ILevel::GetTimeWeatherSystem` | `7FFA24E56740` | **named** `engine_x64_rwdi.ILevel::GetTimeWeatherSystem` |
| `TimeWeather::CSystem::FinishTimeWeatherInterpolation` | `7FFA250373C0` | **named** |
| Engine module base (example) | `7FFA24330000` | `engine_x64_rwdi.dll+0` |
| `TIME` symbol (after enable) | alloc/hook site | CE symbol `TIME` |
| `TIMESTRUCT` storage | CE alloc | CE symbol `TIMESTRUCT` → holds object ptr |

### 3.1 Function prologue (anonymous gamedll)

```text
gamedll+12BBF70:
  push rbx
  push rsi
  sub rsp,58
  mov rbx, rcx          ; this
  mov rcx, [global]     ; singleton ~ gamedll data
  mov rax, [rcx]
  call [rax+840]        ; vcall
  ...
```

No demangled name via `getNameFromAddress` — only `gamedll+RVA`.

### 3.2 Call chain near time update (same function)

```text
…C0D5  mov rcx,[global]
…C0DC  mov rax,[rcx]
…C0DF  call [rax+840]                    ; vcall on singleton
…C0E5  test rax,rax
…C0EA  mov rcx,rax
…C0ED  call [iat] -> ILevel::GetTimeWeatherSystem
…C0F3  mov rcx,rax
…C0F6  call [iat] -> TimeWeather::CSystem::FinishTimeWeatherInterpolation
…C0FC  mov byte ptr [rbx+18], 1
…C100  jmp …C159                         ; skip frac path sometimes
… later branch lands in divisor/divss/addss/store +5C
```

**Multi-hit AOB rule:** prefer the hit inside a function that **calls these two engine names** (or still has the exact frac/day math if names strip).

---

## 4. TIMESTRUCT object layout (partial)

Observed while freeze script symbols were live:

| Offset | Type (obs.) | Role |
|--------|-------------|------|
| `+0x08` | int | Written from day (`mov [rbx+08], eax` after reading `+0x58`) |
| `+0x10` | float | Related time state / fractional component |
| `+0x14` | int | Phase / tag-like value (compared to 3 in paths) |
| `+0x18` | byte | Flag (set 0 at fn entry, 1 after weather interpolate path) |
| `+0x20` | float | Compared / copied with time-ish values |
| `+0x24` | float | Written from xmm8 in one path |
| `+0x50` | ptr? | Null check later in function |
| **`+0x58`** | **int** | **Day counter** (add from frac≥1 rollover) |
| **`+0x5C`** | **float** | **Time of day 0.0–1.0** ← freeze target |
| `+0x64`, `+0x6C` | | Written near weather path |
| `+0x78`, `+0x7C`, `+0x80` | float | Divisors / rates for time step (selected by `+0x14` band) |
| `+0x84` | float | Early comiss vs 0 |
| `+0x88` | float | Adjusted on one phase path |

**Live sample (session):** day=`19`, frac≈`0.822` at `+0x5C`.

Vtable of TIMESTRUCT object pointed into **gamedll** (not a free engine RTTI name on the object itself in this session).

---

## 5. Engine `TimeWeather` surface (named + strings)

### 5.1 Confirmed CE-resolvable symbols

```text
engine_x64_rwdi.ILevel::GetTimeWeatherSystem
engine_x64_rwdi.TimeWeather::CSystem::FinishTimeWeatherInterpolation
```

Many guessed names (`SetTime`, `Update`, `GetDayTime`, …) **did not** resolve — do not assume full PDB.

**Caution:** partial/fuzzy symbol match can return **wrong** functions (one probe for `SetDayTime` resolved to an unrelated `AK::WriteBytesCount::SetCount`). Always confirm with `getNameFromAddress(resolved)` before trusting.

### 5.2 ASCII strings (AOB `TimeWeather::`)

| String |
|--------|
| `TimeWeather::State` |
| `TimeWeather::FDayTimeTag::Dawn` |
| `TimeWeather::FDayTimeTag::Sunrise` |
| `TimeWeather::FDayTimeTag::Morning` |
| `TimeWeather::FDayTimeTag::Forenoon` |
| `TimeWeather::FDayTimeTag::Noon` |
| `TimeWeather::FDayTimeTag::Afternoon` |
| `TimeWeather::FDayTimeTag::Evening` |
| `TimeWeather::FDayTimeTag::Sunset` |
| `TimeWeather::FDayTimeTag::Dusk` |
| `TimeWeather::FDayTimeTag::Night` |
| `TimeWeather::CAsyncLoadTexture::StartAsyncLoad` |

Useful for:

- Confirming module still contains TimeWeather feature set after a patch  
- Cross-ref from string → code that selects day-part tags  
- Future weather-only cheats (not only time freeze)

---

## 6. AOB effectiveness playbook

### 6.1 Why “unique” lies

Comment: `// should be unique`. Live: **2 hits** for  
`F3 0F 11 43 5C F3 0F 10`.

Wrong hit: same byte pattern elsewhere (false positive).  
Right hit: matches ORIGINAL math + TimeWeather calls.

### 6.2 Ranking hits (ordered)

1. **Module:** must be `gamedll_ph_x64_rwdi.dll` (script uses `aobscanmodule`)  
2. **Exact insn at hit:** `movss [rbx+5C], xmm0` (or updated reg if compiler changes — then fix AOB)  
3. **Backward/forward disasm** matches divisor + `addss` + day `+0x58` rollover  
4. **Named calls** in same function: GetTimeWeatherSystem / FinishTimeWeatherInterpolation  
5. **Runtime:** enable → `TIMESTRUCT` → float in range and reacts to game clock when not frozen  

### 6.3 When AOB returns 0

| Strategy | Action |
|----------|--------|
| Shorten | `F3 0F 11 43 5C` alone (noisier) |
| Wildcard | If disp changes from `5C`, e.g. `F3 0F 11 43 **` only with strong validation |
| Anchor from engine | Resolve `ILevel::GetTimeWeatherSystem` → find gamedll callers → walk to store |
| String | Find code refs to `FDayTimeTag` / `TimeWeather::State` |
| Value scan | Scan float 0–1 that tracks time of day, then “what writes this” (debugger; limited over remote) |
| Secondary author hint | Re-find daynightCycle `+10` path from header comment |

### 6.4 Pattern quality tips (general + this game)

- Prefer **code** AOB in the **correct module** (`aobscanmodule`) over full-process  
- Include **1–2 following unique opcodes** when possible, but validate multi-hit  
- Capture **ORIGINAL CODE** every time you re-verify (labels optional; bytes mandatory)  
- Record **named nearby APIs** in the AA script comments for the next porter  
- Never trust CE auto function names from old builds (`GuiGatherResources`)  

---

## 7. Remote CE commands used successfully

```text
ping / getVersion / tableStatus
alGet 193 / alGet 192 / alGetScript 193
getAddress engine_x64_rwdi.ILevel::GetTimeWeatherSystem
getAddress TIME / TIMESTRUCT   (after enable)
runScriptSafe return getNameFromAddress(addr)
runScriptSafe sequential disassemble + getInstructionSize
runScriptSafe return getNameFromAddress(readQword(iat))
AOBScan 54 69 6D 65 57 65 61 74 68 65 72 3A 3A   ; "TimeWeather::"
readString <addr> 120
alSetDesc 193 [Cheat][<ver>] Time Related Cheats ...
```

Avoided / crash-prone: bulk unsafe reads, `enumMemoryRegions`, memscan from bg thread.

---

## 8. Version tagging (MEMORY description)

Table convention:

```text
[Cheat][<version>] Time Related Cheats (Expand) (Day/Night visuals will not be affected)
```

| When | Action |
|------|--------|
| AOB still works, no pattern edit | Keep existing version tag (e.g. `1.93`) — CT family still valid |
| Pattern retuned for a new product build | `alSetDesc` to the **user’s game version** string |
| Script body comments | Optional: bump Date / “Verified: &lt;date&gt;” inside AA header |

Child **192** description is instructional (0.0–1.0 mapping); usually leave unless UX change.

**Rename API:** `alSetDesc` / `ce.al_set_desc` — address-list **Description** (MEMORY tab), not `stSetName` (structures).

---

## 9. Future work (broken features / richer control)

1. Map **return value** of `GetTimeWeatherSystem` fields (engine `CSystem`) vs gamedll TIMESTRUCT  
2. Find **set-time** API (may be vtable on CSystem) for clean sets without fighting the update tick  
3. Weather state beyond time float (`TimeWeather::State`, interpolation finish/start)  
4. Fix Night XP / other time-adjacent AA with same anchor method  
5. Keep a **pattern history table** in this folder when AOB must change (like player-variables 1.42/1.82/1.90)

---

## 10. Script vs research — checklist for porters

| Check | Script | Research |
|-------|--------|----------|
| Module | gamedll | gamedll ✓ |
| AOB | `F3 0F 11 43 5C F3 0F 10` | still valid when freeze worked ✓ |
| Inject semantics | save rbx, store +5C | ✓ |
| Function name in comments | GuiGatherResources | **replace with engine call names + RVA** |
| Multi-hit | ignored | **must rank hits** |
| Child address | `[TIMESTRUCT]+5C` | ✓ frac 0–1 |
| Version MEMORY tag | [1.93] | update only when retuned / user version policy |

---

## 11. Change log

| Date | Note |
|------|------|
| 2026-08-01 | Initial dump: inject site, fn start RVA, engine names, strings, layout, AOB ranking; table ID 193/192 |
