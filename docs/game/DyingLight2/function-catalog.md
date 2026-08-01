# Dying Light 2 — function / API catalog

**Purpose:** Lookup of **how systems are actually named and nested** so we can investigate what to call, hook, or walk when AOBs die or when designing new cheats.

**Not** an AOB tutorial — see `skills/ce-aob-scan`.  
**Not** complete — expand this file whenever a new symbol, string, or gamedll site is confirmed.

**Last extended:** 2026-08-01 (TimeWeather + level access path from freeze-time work).

---

## How to read this catalog

| Column / mark | Meaning |
|---------------|---------|
| **Resolved** | `getAddress` / `getNameFromAddress` returned this name on a live attach |
| **String only** | ASCII present in memory; code link may be incomplete |
| **Anonymous gamedll** | No demangled name; identified by RVA + behavior + callers |
| **Suspect** | Symbol query returned a hit but name looked wrong / fuzzy — re-check before use |

Resolve form used by CE:

```text
engine_x64_rwdi.Namespace::Class::Method
engine_x64_rwdi.ILevel::GetTimeWeatherSystem
```

Always confirm:

```lua
getNameFromAddress(getAddressSafe("engine_x64_rwdi....") or 0)
```

---

## Hierarchy overview (known)

```text
engine_x64_rwdi
├── ILevel
│   └── GetTimeWeatherSystem()  →  (TimeWeather system object)
└── TimeWeather
    ├── CSystem
    │   └── FinishTimeWeatherInterpolation()
    │   └── (many methods unknown — probe as needed)
    ├── State                          [string]
    ├── FDayTimeTag
    │   ├── Dawn | Sunrise | Morning | Forenoon | Noon
    │   ├── Afternoon | Evening | Sunset | Dusk | Night
    └── CAsyncLoadTexture
        └── StartAsyncLoad             [string / symbol-ish]

gamedll_ph_x64_rwdi
├── (anonymous) Day/night owner update   [freeze-time inject lives here]
│   ├── calls engine ILevel::GetTimeWeatherSystem
│   ├── calls engine TimeWeather::CSystem::FinishTimeWeatherInterpolation
│   └── writes this+0x5C time frac, this+0x58 day
├── PlayerVariables / FloatPlayerVariable init code  [PlayerVars AOB → dissect names]
├── player variables live blob           [data AOB / playerStat — see player-variables]
├── PlayerHealthModule / LifeHealth      [current HP — see health-money.md]
├── InventoryMoney                       [currency amount +0x38]
└── (many other inject sites in CT — not yet cataloged)

CE symbols (table runtime, not game exports)
├── TIME / TIMESTRUCT     — freeze-time AA
├── playerStat / playerStatAlt — bootstrap AA
└── NIGHTXPBONUS          — night XP cheat family
```

---

## `engine_x64_rwdi` — `ILevel`

| Symbol | Status | Notes |
|--------|--------|-------|
| `ILevel::GetTimeWeatherSystem` | **Resolved** | Returns object used with TimeWeather system; called from gamedll day/night update before frac store. Example abs (session): `7FFA24E56740`. |

**Investigation angles**

- Other `ILevel::Get*` / `ILevel::` methods may exist — probe by guessing is weak; prefer string/RTTI dumps or more IAT resolves from gamedll.  
- Once you have the return value of `GetTimeWeatherSystem`, dump vtable slots (careful) or find xrefs to map setters (time, weather preset, pause).

---

## `engine_x64_rwdi` — `TimeWeather`

### Namespace layout (from strings + one resolved method)

```text
TimeWeather::
  CSystem::
    FinishTimeWeatherInterpolation   [Resolved]
    … (Update / Set* / Get* — not yet confirmed)
  State                              [String]
  FDayTimeTag::
    Dawn, Sunrise, Morning, Forenoon, Noon,
    Afternoon, Evening, Sunset, Dusk, Night
  CAsyncLoadTexture::
    StartAsyncLoad                   [String]
```

### `TimeWeather::CSystem`

| Symbol | Status | Notes |
|--------|--------|-------|
| `TimeWeather::CSystem::FinishTimeWeatherInterpolation` | **Resolved** | Called from same gamedll function as time-frac write (after `GetTimeWeatherSystem`). Example abs: `7FFA250373C0`. |

**Probed, not confirmed (miss or wrong):**  
`Update`, `UpdateTime`, `Tick`, `SetTime`, `GetTime`, `AdvanceTime`, `BeginTimeWeatherInterpolation`, `StartTimeWeatherInterpolation`, `Interpolate`, `SetTimeWeather`, `GetTimeWeather`, `UpdateWeather`, `UpdateTimeWeather`, `Apply`, `Reset`, `SetPaused`, `IsPaused`, `GetDay`, `SetDay`, `GetHour`, `SetHour`, `GetTimeOfDayNormalized`, `SetTimeOfDayNormalized`, `GetNormalizedTime`, `SetNormalizedTime`, `Advance`, `Freeze`, `Unfreeze`, bare `TimeWeather::CSystem`.

**Suspect:** a query for `…::SetDayTime` once resolved to an unrelated `AK::WriteBytesCount::SetCount` — treat fuzzy matches as hostile.

**What we might obtain later**

- Clean **set time / set day** without fighting the gamedll tick  
- Weather preset / interpolation control  
- Pause clock without freezing a single float  

### `TimeWeather::FDayTimeTag`

| Tag string | Status |
|------------|--------|
| `TimeWeather::FDayTimeTag::Dawn` … `Night` (10 tags) | **String** |

Use for: day-part logic, UI, missions; xref → code that branches on time-of-day band.

### `TimeWeather::State`

| String | Status |
|--------|--------|
| `TimeWeather::State` | **String** |

Likely weather/time state machine id — good AOB-fail / feature discovery anchor.

### `TimeWeather::CAsyncLoadTexture`

| String | Status |
|--------|--------|
| `TimeWeather::CAsyncLoadTexture::StartAsyncLoad` | **String** |

Texture streaming for sky/weather; lower priority for freeze-time, useful for weather visual cheats.

---

## `gamedll_ph_x64_rwdi` — anonymous sites

Gamedll rarely demangles. Document **behavior + RVA (per build) + engine callees**.

### Day/night owner update (freeze-time inject)

| Field | Value |
|-------|--------|
| Status | **Anonymous** — confirmed by AOB + disasm + engine calls |
| Purpose | Advances normalized time frac; rolls day; talks to TimeWeather |
| Fn start RVA (one build) | `gamedll+12BBF70` |
| Inject RVA (one build) | `gamedll+12BC154` — `movss [rbx+5C], xmm0` |
| AOB (CT) | `F3 0F 11 43 5C F3 0F 10` (often **2** hits — rank!) |
| `this` (rbx) | Stored as CE `TIMESTRUCT` |
| Key fields | `+0x58` day int; `+0x5C` frac float 0..1; see `time-weather.md` |
| Engine callees | `ILevel::GetTimeWeatherSystem`; `TimeWeather::CSystem::FinishTimeWeatherInterpolation` |
| Stale CT label | `GuiGatherResources` — **discard** |

**CT row:** AA id **193**, child **192** `[TIMESTRUCT]+5C`.

### playerStat blob (bootstrap)

See `player-variables.md`. Not a named engine API; data signature AOB history 1.42 / 1.82 / 1.90.

### Other CT injects

Not yet mapped into this catalog. When porting another AA row, add a subsection here with: purpose, module, AOB, symbols registered, any resolved IAT names, child EXPR list.

---

## CE table runtime symbols (not game exports)

| Symbol | Producer | Consumers |
|--------|----------|-----------|
| `TIME` / `TIMESTRUCT` | Time Related AA | `[TIMESTRUCT]+5C` float row |
| `playerStat` / `playerStatAlt` | Enable playervariables AA | Dozens of `playerStat + off` rows |
| `NIGHTXPBONUS` | Night XP AA family | `[NIGHTXPBONUS]+5C` etc. |

---

## How to extend this catalog (procedure)

1. From a working or semi-working AA script, list every `call [iat]` / `call Module.X` in the function (disasm walk).  
2. `getNameFromAddress(readQword(iat))` — record **Resolved** rows.  
3. ASCII scan distinctive prefixes (`ClassName::`, feature name) — record **String** rows.  
4. For gamedll: record RVA relative to module, behavior, fields, CT ids.  
5. Never delete old RVAs without marking **superseded** — ASLR abs addresses can go; RVA may drift per build.  
6. Optional: group new namespaces under the tree at the top of this file.

### Remote helpers

```text
getAddress engine_x64_rwdi.ILevel::GetTimeWeatherSystem
AOBScan 54 69 6D 65 57 65 61 74 68 65 72 3A 3A    # "TimeWeather::"
readString <hit> 120
runScriptSafe return getNameFromAddress(readQword(0xIAT) or 0)
```

---

## Player / health / money (PDB + CT structures)

```text
PlayerVariables (constds / dataset)
├── FloatPlayerVariable          ← PlayerVarsArray generator; CT FloatPlayerVariable 1.82/1.90
├── BoolPlayerVariable
├── StringPlayerVariable
└── HealthPlayerVariable<HealthFactors>

PlayerHealthModule               [CT dissect]
└── → lifecs::PrivHealth::LifeHealth<HealthFactors>
        +0x1C Real HP
        +0x2C..+0x34 Max HP

InventoryMoney                   [CT dissect]
└── +0x38 Money

HumanHealthModule / BaseHealthModule / CreatureHealthModule / BeastHealthModule / CoHealth
SetPlayerHealthLogic / PlayerHealthWaitLogic
EGuiCurrencyType / GuiCurrency*
m_MaxHealth, m_AbsoluteMaxHealth, m_BonusMaxHealth   [gamedll strings]
```

Details and discovery order: **`health-money.md`**, **`player-vars-array.md`**.

---

## Open questions (investigate next)

1. Full `TimeWeather::CSystem` vtable / exported method list  
2. Object identity: is `TIMESTRUCT` (gamedll this) the same as `GetTimeWeatherSystem` return, a wrapper, or a parallel state object?  
3. `ILevel` other getters (player, inventory, quest…) for non-time cheats  
4. Map remaining CT AA scripts → catalog entries  
5. Confirm product version string for builds after 2026-06-14 package date  
6. Live instance path: PlayerDI_PH → HealthModule / InventoryMoney  
7. Retune PlayerVars `getInfo` parser for 1.14+ encoding; full structure regen  

---

## Change log

| Date | Change |
|------|--------|
| 2026-08-01 | Initial catalog from freeze-time investigation (ILevel, TimeWeather, gamedll day/night update, strings) |
| 2026-08-01 | PlayerVariables / health / InventoryMoney hierarchy; links to character + PlayerVars docs |
