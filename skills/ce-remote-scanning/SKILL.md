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

## Breakpoints vs “find what accesses” (do not confuse)

Cheat Engine has **different** mechanisms. Agents often wrongly assume any “breakpoint” freezes the process and that a hung remote server is “because the game is stopped.” That is often **false**.

| Mechanism | UI / concept | Stops the process? | What you get |
|-----------|--------------|--------------------|--------------|
| **Value / access logging** | “**Find out what accesses this address**” / “Show which code reads or writes to this value” (CE **value breakpoints** / page-guard style access tracing) | **No** — hit is **logged** and execution **continues** | Code addresses that touched the value; optional register snapshot in the log, process keeps running |
| **Software / hardware breakpoint** | Debugger BP on instruction or DR0–DR3 data BP configured to **break** | **Yes** (unless you script continue) | Full stop; registers valid for that pause; step / continue needed |
| **Conditional BP (scripted)** | e.g. break only when `RDI == 0x3F` | Stops **only** when condition matches; otherwise continues | Same as stop BP when it hits |

**Implications for remote CE work:**

1. **User “put a breakpoint on the time function” via value-access find** → game is **still running**. Do **not** blame remote timeouts on “process frozen.”
2. **True stop BPs** are a different tool; only those make “continue first” or “registers only valid while paused” advice correct.
3. Register dumps the user pastes from an **access log** may be from a **past hit** while the process moved on — heap pointers can be stale by the time we `readQword`.
4. Remote Lua **does not** currently expose a full debugger UI. Do not assume `debug_setBreakpoint` / `debugger_onBreakpoint` from the pipe without an explicit design (see `SOLUTION.md` for stop-BP architecture; not the default scanning path).

**When the remote server hangs:** prefer “bad/heavy CE API,” wrong-thread call, or **Lua server thread death** mid-handler — **not** “value BP stopped CE.” CE itself often keeps running; only the pipe server dies.

### Diagnosing a dead server (what killed it?)

The relay used to log only the **verb** (`Received: getAddress`). If the handler hard-crashed CE’s Lua thread, the CE console showed nothing useful.

**CE Lua Engine (server ≥ v1.8.2):**

```text
[server] EXEC start #N <verb> | <preview of full command>
[server] EXEC done  #N ok ms=… out=…
```

If the thread dies, **the last line is usually `EXEC start`** for the bad call — no matching `EXEC done`.

**Client session log (optional):**

```bash
export CE_SESSION_LOG=1   # → remote/logs/ce-session.log
# or: export CE_SESSION_LOG=/tmp/ce-session.log
python3 client.py --cmd "ping"
```

Each line: `timestamp  #seq  REQ|RSP|ERR  payload`. Last `REQ` without `RSP` = what the client sent when the server died.

Hard crashes that kill the thread **bypass** `pcall` (native CE fault) — logging before execute is the forensic hook, not “catching” the crash.

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
- CT comments that say “should be unique” are **often wrong** after patches — plan for multi-hit ranking

## Code / table AOB (any entry)

**Full methodology:** **`skills/ce-aob-scan`** (harvest → scan → multi-hit rank → zero-hit recovery → verify → `alSetDesc`).

This file stays focused on **safe remote APIs** and value scanning. Do not fork per-game AOB skills; put game anchors under `skills/game/<Title>/`.

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
