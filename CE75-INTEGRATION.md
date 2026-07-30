# Using CE75 Unreal Scripts with the Remote Tool

## Setup Order

1. **Attach CE to the game process** (G1R-Win64-Shipping.exe)
2. **Load CE75.LUA** — either via autorun or paste into Lua Engine (Ctrl+L) and Execute
3. **Load the G1R plugin** — if not auto-loaded, use the CE menu: `Unreal Engine → Load Game Plugin → Gothic 1 Remake`
4. Start the remote server (`ce_server.lua`) and relay as usual

CE75's discovery (GEngine, FName pool, property offsets, player chain) runs on autorun. The remote inherits everything.

## What CE75 Provides the Remote

### Symbols (resolve via `getAddress`)

| Command | Returns |
|---------|---------|
| `getAddress GEngine` | GEngine pointer |
| `getAddress GNames` | FNamePool base (if plugin loaded) |
| `getAddress G1R-Win64-Shipping.exe` | Module base |

### Functions (call via `runScript`)

| Command | Returns |
|---------|---------|
| `runScript return UEngine_findCharacter()` | Character pointer or nil |
| `runScript return UEngine_findLocalPlayer()` | Local player pointer |
| `runScript return UEngine_resolveFName(0xB19712)` | FName string |
| `runScript return UEngine.UObject.Class` | Property offset (any cached struct) |
| `runScript return UEngine_itemShortName("ItFo_Apple")` | `"Apple"` |
| `runScript return UEngine_itemPrettyName("ItFo_Apple")` | `"Apple (Food)"` |
| `runScript return UEngine_searchCharacterProperties()` | Print dump + found table |
| `runScript return UEngine.Inv.chain.carry` | Carry component pointer (G1R) |
| `runScript UEngine_addInventoryToAddressList()` | Refresh inventory (no return) |

CE 7.5 Lua returns `0x` hex values as decimal integers from `runScript`. Convert with `hex(result)` client-side if needed.

## Common Workflows

### Walk the player chain step by step

```
# resolve GEngine (installed as a symbol by CE75)
getAddress GEngine

# read GameInstance pointer (offset depends on UE version, CE75 caches it)
runScript return UEngine.UGameEngine or UEngine.UGameEngine

# get character in one call
runScript return string.format("%X", UEngine_findCharacter())
```

### Read inventory without CE75

Without CE75 loaded, you'd need the raw chain:

```
# GEngine → GameInstance → LocalPlayers → PC → Pawn
# all offsets must be known ahead of time
readQword GEngine+0x30   # (example, actual offset varies)
```

With CE75, `UEngine_findCharacter()` wraps this entire chain and handles variant offsets.

### Dump all character properties

```
runScript return UEngine_searchCharacterProperties()
runScript return UEngine_getAllProperties(readPointer(readPointer(getAddressSafe('GEngine') + UEngine.UGameEngine.GameInstance) + UEngine.UGameInstance.LocalPlayers) + UEngine.UObject.Class)
```

(Second example shows CE75's cached offsets — no manual offset hunting.)

## Plugin-Specific

The G1R plugin must be loaded via the CE menu (`Load Game Plugin → Gothic 1 Remake`) or by running:

```
runScript dofile([[Scripts/g1r/g1r-plugin.lua]])
```

After loading, these become available:

| Command | Returns |
|---------|---------|
| `runScript return UEngine_ensureGNames()` | GNames base or nil |
| `runScript return UEngine_classifyItemName("ItMw_Sword")` | `"Melee"` |
| `runScript UEngine_refreshInventoryAddressList(true)` | Refresh (no return) |
| `runScript return UEngine.Inv.chain` | Inventory chain table |

The display helper (`inventory_display_helper.lua`) is loaded on first "Lookup real item names" menu click or via `runScript UEngine_lookupRealItemNamesAsync()`.

## Caveats

- CE75's symbols (`GEngine`, etc.) are CE address list entries, not Lua globals. Resolve them via `getAddress`, not `runScript return GEngine`.
- `runScript` evaluates expressions with `loadstring("return " .. code)` first. For void functions, use the bare call and wrap in a return expression if you need output.
- AOB scans from `ce_server.lua` run on the remote's background thread, not on CE75's worker thread — the same CE Lua state, different call site.
- If CE75 is reloaded (re-executed), the GEngine symbol is re-registered and UEngine functions are redefined — no reconnect needed on the remote side.
