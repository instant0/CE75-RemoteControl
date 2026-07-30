---
name: ce-remote-scanning
description: Memory scanning and value searching techniques using Cheat Engine's remote Lua interface, including safe APIs, crash avoidance, and best practices.
---

# CE Remote Scanning

Use this skill when you need to scan memory, find values, or search for patterns in a game process via the CE remote.

## Connection

```python
from client import CERemote
ce = CERemote("host", 8000, timeout_seconds=60)
# Test:
print(ce.cmd("ping"))
# → pong
```

## Safe Commands (Native)

These are exposed as server commands and are safe from background threads:

| Command | Purpose |
|---------|---------|
| `ping` | Health check |
| `readBytes <addr> <size>` | Returns hex bytes |
| `readQword <addr>` | Returns decimal integer |
| `readDword <addr>` | Returns decimal integer |
| `readString <addr> <maxlen>` | Returns string |
| `writeBytes <addr> <hex>` | Write hex bytes |
| `AOBScan <pattern>` | Full-process AOB scan (returns tab-separated addresses) |
| `enumModules` | List loaded modules |
| `getAddress <name>` | Resolve symbol/module+offset |

## Dangerous APIs (AVOID)

These crash the CE relay or hang the server when called via `runScript`:

| API | Crash reason | Alternative |
|-----|-------------|-------------|
| `enumMemoryRegions()` | Protection flag strings corrupt output | Use `enumModules` for module bounds |
| `createMemScan()` / `Memscan_firstScan` | Not thread-safe, corrupts scan engine state | Use native `AOBScan` command |
| `varscan_firstScan()` / `varscan_*` | Same, manipulates UI scan state | Use `AOBScan` |
| `AOBScan` with string protection `"w"` | Parses garbage; use numeric bitmask | Omit protection or use `AOBScan(pattern, 2)` |
| `UEngine_findObjectStart()` | Crashes on disconnected object links | Don't use |
| `component_findComponentByName(obj, name)` | Only exists when game plugin is loaded | Wrap in `pcall` |
| `UEngine_getAllProperties(obj)` | Returns nil unless passed a **class pointer** | Pass `readQword(obj + 0x10)` not `obj` |

## Safe runScript Patterns

```lua
-- ALWAYS wrap in pcall:
local ok, result = pcall(readQword, addr)

-- ALWAYS guard against nil:
local val = readQword(addr) or 0

-- ALWAYS check before calling plugin functions:
if type(UEngine_getAllProperties) == "function" then
  local ok, r = pcall(UEngine_getAllProperties, classPtr)
end

-- ALWAYS bound loops (avoid infinite walks):
for i = 0, math.min(count - 1, 10000) do ... end

-- NEVER pass nil to string.format:
string.format("%X", val or 0)
```

## AOBScan Best Practices

```bash
# Native command (preferred):
AOBScan 12 BC 00 00           # scan for 4796 LE int32
AOBScan 12 BC                  # scan for 2-byte pattern

# Via runScript (when range needed):
# NOTE: start/stop params may be ignored! Only full-process is reliable.
# Use with caution and short timeout.
runScript local r=AOBScan("12 BC 00 00"); return r and r.Count or 0
```

**Known issues:**
- AOBScan on small values (< 65536) returns thousands of hits
- AOBScan range parameters (start, stop) are **ignored** in some CE versions
- AOBScan on writable memory with `AOBScan(pattern, "w")` may crash

## Value Scanning Strategy

When AOBScan is too noisy for small values:

1. **Scan as float**: 4796.0 = bytes `00 E0 95 45` in LE
2. **Scan as int64**: 4796 = `BC 12 00 00 00 00 00 00` (much more selective)
3. **Delta scan**: Change the value in-game (drop/pick up item), then do a changed-value scan
4. **Targeted scan**: Narrow to known module range via `getAddress` + `enumModules`
5. **Pointer scan**: Find what points to the value via pointer-scanning
6. **UE property walk**: Navigate the object model directly instead of scanning

## UObject Identification Pattern

```lua
-- Check if an address is a valid UObject:
local vtable = readQword(addr)
local cls = readQword(addr + 0x10)
-- UObjects have:
--   vtable in module range (0x7FXXXXXXXXXX)
--   non-nil class at +0x10
--   ObjectFlags at +0x08 (usually has RF_标记)
if vtable and vtable > 0x7F0000000000 and cls and cls > 0x10000 then
  local ok, name = pcall(UObject_getName, addr)
  local ok2, cn = pcall(UObject_getName, cls)
end
```

## Lua 5.1 Bitwise Workarounds

CE's Lua 5.1 lacks `&`, `|`, `<<`, `>>` operators:

```lua
-- Extract lower 32 bits:
local low = qword % 0x100000000

-- Extract upper 32 bits:
local high = math.floor(qword / 0x100000000)

-- Pack two 32-bit values into a qword:
local packed = high * 0x100000000 + low
```
