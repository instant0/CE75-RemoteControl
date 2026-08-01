# Dying Light 2 — modules

Session-observed layout (ASLR bases change every launch). Use **names**, not absolute addresses, for long-lived docs.

## Process

| Item | Typical name |
|------|----------------|
| Main exe | `DyingLightGame_x64_rwdi.exe` |

## Gameplay / engine split (important)

Techland builds often split:

| Module | Role for cheats |
|--------|-----------------|
| **`gamedll_ph_x64_rwdi.dll`** | Most **trainer inject sites**, gameplay object updates, anonymous functions (`getNameFromAddress` → `gamedll+RVA` only) |
| **`engine_x64_rwdi.dll`** | **Named** C++ APIs / RTTI-rich surface (`Module.Class::Method`), systems like TimeWeather, level interfaces |
| **`DyingLightGame_x64_rwdi.exe`** | Shell / glue; less often the inject target for this CT |

Other modules seen in attach (helpers / OS):  
`memdump_x64_rwdi.dll`, `logger_x64_rwdi.dll`, `filesystem_x64_rwdi.dll`, plus normal Windows DLLs.

## Practical rules

1. **Code AOB for this CT** → prefer `aobscanmodule(..., gamedll_ph_x64_rwdi.dll, …)` unless the script says otherwise.  
2. **Stable names for “AOB failed” recovery** → resolve first in **`engine_x64_rwdi`**, then find **gamedll callers**.  
3. **Data AOB** (player variables blob) → often full-process / writable scan (`+W-C` in Lua bootstrap), not always in gamedll code.  
4. Always `enumModules` after attach to confirm names (shipping suffixes `_x64_rwdi` can vary by build config).

## Example bases (one session only)

| Module | Example base |
|--------|----------------|
| `engine_x64_rwdi.dll` | `7FFA24330000` |
| `gamedll_ph_x64_rwdi.dll` | (derive from any `gamedll+RVA` hit) |

Do not hardcode these into AA scripts — use module-relative AOBs and CE symbols.
