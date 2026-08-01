# Remote CE 7.5 Server — Solution Design

> **Historical design document — not the product contract.**
>
> What **shipped** is a `createThread` named-pipe server with memory I/O,
> `AOBScan`, **`GroupScan`** (main-thread), `runScript` / `runScriptSafe`, and
> full address-list / structure commands (`al*` / `st*`) via `synchronize`.
> See `README.md`, `docs/TABLE-MIGRATE.md`, and `ce_server.lua` (`getVersion`).
>
> What did **not** ship: remote breakpoint push, register streaming, or a full
> debugger protocol over TCP. That remains a non-goal for v1 — see
> `docs/BREAKPOINT_STRATEGY.md` and `docs/NONGOALS-AND-HAZARDS.md`.
>
> Prefer those docs and the live code over any “Option 1 recommended” language
> below. This file is kept for architecture rationale and CE source citations.

## Overview

Three solutions were explored during design. Option 1 described a complete
rewrite of `ce_server.lua` using CE's built-in `createThread` API to run the
pipe server in a background thread, **plus** a polling-model debugger
(breakpoints, register inspection, step control). Options 2 and 3 were
lighter-weight fallbacks.

The **background-thread pipe server** idea shipped; the **remote debugger**
portion of Option 1 did **not**.

All options are **pure Lua scripts** — no Pascal source changes, no recompilation,
no DLL plugins. Paste into CE's Lua Engine (Ctrl+L) and click Execute.

---

## Option 1: Full `createThread` server with debugger (design; debugger not shipped)

### Architecture

```
┌────────────────────────────────────────────────────────────────┐
│ Cheat Engine 7.5                                              │
│                                                                │
│  Main Thread (UI)        Background Thread (pipe server)       │
│  ┌──────────────────┐    ┌────────────────────────────────┐    │
│  │ createThread(fn) │───>│ while true:                    │    │
│  │ Lua Engine exits │    │   pipe.acceptConnection()      │    │
│  │ CE stays alive   │    │   while connected:             │    │
│  │ UI is responsive │    │     cmd = read_length_prefixed │    │
│  └──────────────────┘    │     resp = process_command(cmd)│    │
│                          │     write_length_prefixed(resp)│    │
│  Debugger Thread          └────────────────────────────────┘    │
│  ┌──────────────────┐                                           │
│  │ breakpoint       │   _G.bp_hit = true                        │
│  │ callback fires   │──> _G.bp_rip = ...                        │
│  │ sets globals     │   _G.bp_rax = ...                         │
│  │ returns 1 (break)│                                           │
│  └──────────────────┘                                           │
└────────────────────────────────────────────────────────────────┘
         │ Named pipe               │ TCP :8888
         └──────────────┬───────────┘
                        │
               ┌────────┴────────┐
               │ windows_relay.py│
               └────────┬────────┘
                        │ TCP :8888
               ┌────────┴────────┐
               │ client.py       │
               │ (WSL agent)     │
               └─────────────────┘
```

### How `createThread` eliminates the freeze

Source-verified at `LuaThread.pas:336-338`:

```pascal
function createNativeThread(L: PLua_State): integer; cdecl;
begin
  result:=createNativeThreadInternal(L, false);
end;
```

Registered as `createThread` at line 582:

```pascal
lua_register(LuaVM, 'createThread', createNativeThread);
```

The implementation (`createNativeThreadInternal`, line 215):

1. Stores the Lua function reference in the registry (`luaL_ref`)
2. Creates a thread-local coroutine via `lua_newthread(L)` (line 252)
3. Creates a `TCEThread` — a Delphi `TThread` descendant (line 275)
4. Calls `c.Start` which spawns a real OS thread (line 282)
5. Returns immediately — the Lua Engine script exits

The thread's `Execute` method (line 93):
- Pushes the stored function + thread object as arguments
- Calls `lua_pcall(L, 1+extraparamcount, 1, 0)` — the function runs on the
  background thread with its own coroutine
- When the function returns (or the pipe disconnects), the thread cleans up

`createThread` shares `_LuaVM` via `lua_newthread`, so the background thread
has **full access to ALL CE Lua functions**: `createPipe`, `readQword`,
`AOBScan`, `debug_setBreakpoint`, `autoAssemble`, `pause`, `unpause`, etc.

The pipe call chain: `readBytes` → `pipecontrol_readBytes` → `ReadFile` (Win32).
While blocked here, the background thread does not touch the Lua state. CE's
`_LuaCS` critical section (`LuaHandler.pas:40`) protects global table access
when both background and debugger threads need it.

CE's celua.txt line 2558 documents: *"All CE functions are threadsafe."*

### Thread safety analysis (source-verified)

| Thread | Lua state | What it does |
|---|---|---|
| Main | `Thread_LuaVM` (coroutine) | Nothing after `createThread` returns |
| Background | `Thread_LuaVM` (different coroutine) | Pipe I/O, memory reads/writes, AOBScan |
| Debugger | `Thread_LuaVM` (third coroutine) | Breakpoint callback, sets `_G` globals |

All three use different coroutines of the same `_LuaVM` (`LuaHandler.pas:194`):
```pascal
Thread_LuaVM:=lua_newthread(_luavm);
```

The global table is shared, but:
- **Background thread** blocks on `ReadFile` without touching Lua state between
  pipe operations. During `lua_pcall` (processing a command), it briefly uses
  the global table.
- **Debugger thread** callback (`LuaCaller.BreakpointEvent`, `LuaCaller.pas:1252`)
  calls `LUA_onBreakpoint` (`LuaHandler.pas:904`) which sets a few globals
  (`_G.RAX`, `_G.RBX`, etc.) and returns.
- Race window: background thread processing a command while debugger callback
  fires. Mitigation: the callback is ~10 Lua opcodes, and `_G` writes are
  single-assignment (no read-modify-write).

For the breakpoint polling model, the callback sets `_G.bp_hit = true` as its
last write. The background thread checks this flag at the start of each command.
If both threads write simultaneously, the worst case is a missed notification
(next command will catch it).

`createCriticalSection()` (`LuaThread.pas:590`) is available if we need a
Lua-side mutex, but CE's existing `_LuaCS` already protects registry access.

### Source-verified per-function thread safety

All 18 CE autorun scripts that use `createThread` rely solely on `synchronize()`,
guard variables, and `t.Terminated` — never `createCriticalSection` or
`createEvent`. Zero uses of those primitives exist in any shipped script.

#### Functions that marshal to main thread via `pluginsync` / `SendMessage`

These call `pluginsync(func, params)` → `SendMessage(mainform.handle,
wm_pluginsync, ...)` and are **safe from background thread** (the call blocks
until the main thread processes it). Source: `pluginexports.pas`.

| Function | Source | pluginsync target |
|---|---|---|
| `pause()` | `pluginexports.pas:1494-1497` | `ce_pause2` — clicks pause button |
| `unpause()` | `pluginexports.pas:1506-1509` | `ce_unpause2` — clicks unpause |
| `debugProcess()` | `pluginexports.pas:1527-1530` | `ce_debugProcess2` — enables debugger |
| `debug_continueFromBreakpoint()` | `pluginexports.pas:1611-1613` | `ce_debug_continueFromBreakpoint2` — continues/stepping |

Note: `debug_continueFromBreakpoint` in LuaHandler.pas:3943 calls
`ce_debug_continuefrombreakpoint(method)` which is the `pluginsync`-wrapped
plugin version.

`debug_setBreakpoint` (LuaHandler.pas:3873) does **not** use `pluginsync`. It
directly calls `debuggerthread.SetOnExecuteBreakpoint()` etc. at line 3856-3860.
The `MemoryBrowser.hexview.update` calls after it at lines 3862-3863 are VCL GUI
operations but are safely wrapped in `try-except` (line 3848 `try`, line 3866
`except`).

#### Functions that read/write `debuggerthread` directly (no UI marshaling)

These access `debuggerthread.CurrentThread` fields directly — safe from
background thread while the process is paused at a breakpoint.

| Function | Source | What it accesses |
|---|---|---|
| `debug_isBroken()` | `LuaHandler.pas:3734-3740` | `debuggerthread.CurrentThread.isHandled` |
| `debug_isStepping()` | `LuaHandler.pas:3742-3748` | `debuggerthread.CurrentThread.isSingleStepping` |
| `debug_getContext()` | `LuaHandler.pas:11040-11055` | `debuggerthread.CurrentThread.context` → sets `_G` globals |
| `debug_setContext()` | `LuaHandler.pas:11057-11073` | Reads `_G` globals → writes `debuggerthread.CurrentThread.context` |
| `debug_removeBreakpoint()` | `pluginexports.pas:1568-1586` | `debuggerthread.lockbplist` / `RemoveBreakpoint` (no pluginsync) |
| `debug_setBreakpoint()` | `LuaHandler.pas:3856-3860` | `debuggerthread.SetOnExecuteBreakpoint` (direct, no pluginsync) |

#### Pure CE API functions (no UI dependency, safe from background)

`readBytes`, `readQword`, `readInteger`, `writeBytes`, `writeQword`,
`AOBScan` (`LuaHandler.pas:4364` → `getaoblist`), `getAddressSafe`,
`enumModules`, `loadstring`, `pcall` — all safe.

### Breakpoint callback race condition (source-verified)

`TLuaCaller.BreakpointEvent` (`LuaCaller.pas:1252-1270`) fires on the
**debugger thread**. It calls `LUA_onBreakpoint` (`LuaHandler.pas:904-944`)
which:

1. Calls `LUA_SetCurrentContextState` (sets `_G.RAX`, `_G.RBX`, ..., `_G.THREADID`)
2. Calls the Lua callback function via `lua_pcall`
3. Calls `LUA_GetNewContextState` (reads modified globals back into context)

Race window: background thread processing a command while the breakpoint
callback fires. The callback is ~10-20 Lua opcodes that do single `_G`
assignments. Since the background thread reads `_G.bp_hit` only at command
boundaries (between pipe I/O), the race is:
- **Worst case**: background thread starts processing a command just as
  `bp_hit` is being set → misses this notification → next command catches it
- **No corruption risk**: all `_G` writes are single-assignment, no
  read-modify-write in callback

The callback receives `_G.THREADID` set by `LUA_SetCurrentContextState` at
`LuaHandler.pas:1153` (`lua_setglobal(luavm, 'THREADID')`).

### `createThread` patterns from CE autorun scripts (source-verified)

All 18 `createThread` call sites across CE's shipped autorun scripts follow a
small set of consistent patterns:

**1. Guard-variable pattern** (used in `monoscript.lua`,
`dotnetinfo.lua`, `java.lua`, `modulelistscan.lua`):
```lua
if serverThread == nil then
  serverThread = createThread(function(t)
    t.Name = 'ServerThread'
    -- ... work ...
    serverThread = nil  -- cleared when done
  end)
end
```
The guard prevents duplicate threads. The thread clears the guard on exit.

**2. Fire-and-forget** (`andtools.lua`, `ceshare/ceshare_processlistextention.lua`):
```lua
createThread(function(t)
  t.Name = 'Worker'
  -- ... work ...
  synchronize(function()
    -- ... UI update ...
  end)
end)
```
Return value not captured. Thread self-destructs via `FreeOnTerminate=true`
(default).

**3. Lifespan-controlled** (`dotnetsearch.lua`, `dotnetinfo.lua`):
```lua
local t = createThread(function(t)
  t.FreeOnTerminate(false)
  -- ... work ...
  if t.Terminated then return end
  synchronize(function()
    -- ... update UI ...
  end)
end)
```
Explicit `FreeOnTerminate(false)` for manual thread object lifetime.

**4. Named-function** (`monoscript.lua:819`):
```lua
monoSymbolEnum = createThread(monoIL2CPPSymbolEnum)
```
Passes a global function name string instead of an anonymous function.

**Synchronization mechanisms used (zero `createCriticalSection` usage):**
- `synchronize(function() ... end)` / `t.synchronize(function() ... end)` —
  marshals a callback to the main thread (most common pattern)
- `checkSynchronize(ms)` — processes pending synchronize calls from background
  (used in `modulelistscan.lua` for a busy-wait polling loop)
- `t.Terminated` — cooperative cancellation flag (checked before synchronize)
- `t.Name` — thread naming for debugging in `OutputDebugString`
- `t.FreeOnTerminate(true/false)` — auto-destruction control
- Guard variables + busy flags — `nil` checks for coordination
- `queue(function() ... end)` — main-thread queue (lighter than synchronize)
- `sleep(ms)` — polling delays

**Key takeaway for Option 1:** The server runs forever (until pipe disconnects),
so use a guard variable. No `synchronize()` is needed because the server does
no UI work. Use `t.Name` for debugging.

### Full command set

#### Memory read

| Command | Server action | CE function |
|---|---|---|
| `readBytes <hexaddr> <size>` | Returns hex bytes | `readBytes(addr, size, true)` |
| `readQword <hexaddr>` | Returns 16-digit hex | `readQword(addr)` |
| `readDword <hexaddr>` | Returns 8-digit hex | `readInteger(addr)` |
| `readWord <hexaddr>` | Returns 4-digit hex | `readSmallInteger(addr)` |
| `readByte <hexaddr>` | Returns 2-digit hex | `readByte(addr)` |
| `readPointer <hexaddr>` | Returns hex | `readPointer(addr)` |
| `readFloat <hexaddr>` | Returns float string | `readFloat(addr)` |
| `readDouble <hexaddr>` | Returns double string | `readDouble(addr)` |
| `readString <hexaddr> <maxlen>` | Returns string | `readString(addr, maxlen)` |
| `readBytesLocal ...` | Read CE process memory | `readBytesLocal(...)` |
| (all read variants have Local versions) | | |

#### Memory write

| Command | CE action |
|---|---|
| `writeBytes <hexaddr> <hex>` | `writeBytes(addr, bytes_table)` |
| `writeQword <hexaddr> <value>` | `writeQword(addr, value)` |
| `writeDword <hexaddr> <value>` | `writeInteger(addr, value)` |
| `writeWord <hexaddr> <value>` | `writeSmallInteger(addr, value)` |
| `writeByte <hexaddr> <value>` | `writeByte(addr, value)` |
| `writeFloat <hexaddr> <value>` | `writeFloat(addr, value)` |
| `writeDouble <hexaddr> <value>` | `writeDouble(addr, value)` |
| `writeString <hexaddr> <string>` | `writeString(addr, string)` |

#### Scanning & symbols

| Command | CE action |
|---|---|
| `aobScan <pattern> [prot]` | `AOBScan(pattern, prot)` → comma-sep hex |
| `aobScanModule <pattern> <mod>` | `AOBScanModule(pattern, mod)` |
| `resolveSymbol <name>` | `getAddressSafe(name)` |
| `enumModules` | `enumModules()` |
| `getModuleSize <name>` | `getModuleSize(name)` |

#### Process control

| Command | CE action |
|---|---|
| `pause` | `pause()` |
| `unpause` | `unpause()` |

#### Debugger (stateful)

| Command | CE action |
|---|---|
| `debugProcess` | `debugProcess()` |
| `setBreakpoint <addr> [trigger]` | `debug_setBreakpoint(addr, ..., callback)` |
| `removeBreakpoint <addr>` | `debug_removeBreakpoint(addr)` |
| `debugStatus` | Returns "idle", "waiting", "broken" |
| `getRegisters` | Returns all register globals as lines |
| `getRegister <name>` | Returns single register (RAX, RBX, ...) |
| `setRegister <name> <value>` | Modifies register, calls `debug_setContext()` |
| `continue` | `debug_continueFromBreakpoint(0)` — co_run |
| `stepInto` | `debug_continueFromBreakpoint(1)` — co_stepinto |
| `stepOver` | `debug_continueFromBreakpoint(2)` — co_stepover |
| `runTo <hexaddr>` | `TBD` — needs debuggerthread.runtill |
| `debugList` | `debug_getBreakpointList()` |

#### Script execution

| Command | CE action |
|---|---|
| `runScript <code>` | `loadstring` + `pcall`, returns tostring |
| `runScriptFile <path>` | `loadfile(path)` + `pcall`, returns tostring |

#### Utility

| Command | CE action |
|---|---|
| `ping` | Returns "pong" |
| `version` | Version string |
| `close` | Disconnects |

### Debugger state machine

```
  ┌──────────────────────────────────────────────────────────────┐
  │                                                              │
  │  debug_state = "idle"                                        │
  │    │                                                         │
  │    │ setBreakpoint addr                                      │
  │    v                                                         │
  │  debug_state = "waiting"   ◄──── continue / stepInto/Over   │
  │    │                                                         │
  │    │ (breakpoint fires on debugger thread)                   │
  │    v                                                         │
  │  debug_state = "broken"                                      │
  │    │                                                         │
  │    │ getRegisters / readMemory / setRegister                 │
  │    │ ... (client inspects/patches)                           │
  │    │                                                         │
  │    │ continue / stepInto / stepOver / runTo                  │
  │    └───── back to "waiting"                                  │
  │                                                              │
  │  removeBreakpoint addr → back to "idle" if no BPs left       │
  │                                                              │
  └──────────────────────────────────────────────────────────────┘
  ```

State transitions happen entirely in Lua globals. The background thread checks
`_G.debug_state` at the start of each command.

**Source-verified implementation notes:**

- `debug_isBroken()` (`LuaHandler.pas:3734`) reads
  `debuggerthread.CurrentThread.isHandled` — no `pluginsync`, safe from
  background thread.
- `debug_getContext()` (`LuaHandler.pas:11040`) reads
  `debuggerthread.CurrentThread.context` directly and calls
  `LUA_SetCurrentContextState` — no `pluginsync`, safe from background thread
  while paused.
- `debug_setContext()` (`LuaHandler.pas:11057`) calls
  `LUA_GetNewContextState(debuggerthread.CurrentThread.context)` — writes
  directly to the context struct, safe from background thread.
- `debug_continueFromBreakpoint()` (`LuaHandler.pas:3934`) calls
  `ce_debug_continueFromBreakpoint` which uses `pluginsync` →
  `SendMessage(mainform.handle, wm_pluginsync, ...)` — this works from
  background thread but blocks until main thread processes the message.
- `pause()` / `unpause()` / `debugProcess()` all use `pluginsync` — same
  pattern, safe from background.

**Breakpoint callback fires on debugger thread** (`LuaCaller.pas:1252`):
```pascal
function TLuaCaller.BreakpointEvent(bp: Pointer; context: pointer): boolean;
begin
  // ...
  result:=LUA_onBreakpoint(0, context, true);  // true = functionAlreadyPushed
end;
```
This calls `LUA_onBreakpoint` (`LuaHandler.pas:904`) which:
1. Calls `LUA_SetCurrentContextState` to set `_G` register globals
2. Calls the registered Lua callback via `lua_pcall`
3. Calls `LUA_GetNewContextState` to read modified globals back into CPU context

The callback parameters in `debug_setBreakpoint(addr, size, trigger, method, func)`:
- Position 5 can be a Lua function (on stack) or a string (global function name)
- `TLuaCaller` stores the function reference via `luaL_ref` into the registry
- On breakpoint hit, `PushFunction` retrieves it and `LUA_onBreakpoint` executes it

### Breakpoint callback design

```lua
function _bp_callback()
  _G.bp_hit = true
  _G.bp_state = "broken"
  _G.bp_threadid = _G.THREADID   -- set by LUA_SetCurrentContextState
  _G.bp_rip = _G.RIP
  -- All registers already set as globals by CE (RAX, RBX, ..., XMM0...)
  return 1   -- 1 = break, keep process paused
end
```

This callback is registered via `debug_setBreakpoint(addr, size, trigger,
method, _bp_callback)`. It fires on the debugger thread. `LUA_onBreakpoint`
(`LuaHandler.pas:904`) calls `LUA_SetCurrentContextState` first (sets all
register globals), then calls the callback. After the callback returns,
`LUA_GetNewContextState` reads modified globals back into the CPU context
(register modification works).

**Thread Safety:** The callback fires on the debugger thread (different
coroutine of same `_LuaVM`). The background thread may be processing a command
simultaneously. Since the callback only writes to `_G` globals (single
assignments) and the background thread only reads them at command boundaries
(blocked on pipe I/O between commands), the race window is:

| Thread | When | What it writes |
|---|---|---|
| Debugger callback | Breakpoint hit | `_G.bp_hit`, `_G.bp_state`, `_G.RAX`... (already set by `LUA_SetCurrentContextState`) |
| Background | Command start | Reads `_G.bp_hit` to check for pending breakpoint |

**Worst case:** Background thread starts processing a command just as the
callback sets `bp_hit` → next command will catch it. No corruption possible.

**Register modification works from callback:** `LUA_GetNewContextState` at
`LuaHandler.pas:936` reads modified `_G` values back into the CPU context
struct. So `setRegister RAX 1` from inside the callback (or via debug_getContext
followed by debug_setContext) will modify registers before the process
continues.

**Multiple breakpoints:** Each call to `debug_setBreakpoint` creates a new
`TLuaCaller` instance with its own stored function. Multiple callbacks can
coexist. Each callback independently sets `_G.bp_hit`, so the background thread
only sees the last one — sufficient for the polling model.

### Client workflow example

```
# Attach debugger
> debugProcess
OK

# Set breakpoint on function
> setBreakpoint 7FF6A1B2C000
OK

# Poll until hit
> debugStatus
waiting
> debugStatus
broken RIP=7FF6A1B2C000

# Inspect
> getRegisters
RAX=7FF6A1B2C000 RBX=0 RCX=...
> readQword RCX
7FF6...
> getRegister RSP
...

# Patch return value
> setRegister RAX 1

# Continue
> continue
OK

# Poll again
> debugStatus
waiting
```

### Protocol

Same as current: length-prefixed framing.

```
[4-byte LE length][N bytes of UTF-8 text command]
```

Response uses the same framing.

### Effort

~4-5 hours to rewrite `ce_server.lua`:
- Threading wrapper with `createThread`
- ~30 command handlers
- Debugger state machine with globals
- Breakpoint callback management
- AOBScan result serialization
- Error handling for background thread

### Implementation design: Option 1 server structure

#### Thread wrapper pattern (based on CE autorun conventions)

```lua
local serverThread

serverThread = createThread(function(t)
  t.Name = 'UEScanServer'

  local pipe = createPipe(PIPE_NAME, PIPE_BUFFER, PIPE_BUFFER)
  if not pipe or not pipe.valid then
    -- Can't show UI from background thread; write error to global
    _G._server_error = 'createPipe failed'
    return
  end

  _G.debug_state = 'idle'
  _G.bp_hit = false

  while not t.Terminated do
    pipe.acceptConnection()
    while pipe.connected and not t.Terminated do
      local cmd = read_length_prefixed(pipe)
      if not cmd then break end

      -- Check for pending breakpoint
      if _G.bp_hit then
        _G.bp_hit = false
        -- bp_state, bp_rip, bp_threadid already set by callback
      end

      local ok, resp = pcall(process_command, cmd)
      if ok then
        write_length_prefixed(pipe, resp)
      else
        write_length_prefixed(pipe, 'ERROR: ' .. tostring(resp))
      end

      if cmd == 'close' then break end
    end
  end

  pipe.destroy()
  serverThread = nil
end)
```

Key design decisions:
- `pcall` wraps every command dispatch → errors don't kill the server
- `t.Terminated` checked in both accept and command loops → clean shutdown
- `_G._server_error` stored globally (can't show dialog from background)
- Breakpoint flag checked every command cycle (polling model)

#### Command handler architecture

A single dispatch function with pattern matching (same as current server, but
expanded to ~30 handlers). Each handler returns a string response.

```lua
local function process_command(cmd)
  -- Utility
  if cmd == 'ping' then return 'pong' end
  if cmd == 'getVersion' then return VERSION end
  if cmd == 'close' then return 'BYE' end

  -- Breakpoint polling
  if cmd == 'debugStatus' then
    if _G.bp_hit then
      _G.bp_hit = false
      return string.format('broken RIP=%s THREADID=%d', _G.bp_rip, _G.bp_threadid)
    end
    return _G.debug_state or 'idle'
  end

  -- Dynamic dispatch via handler table
  local space_pos = cmd:find(' ')
  local verb = space_pos and cmd:sub(1, space_pos - 1) or cmd
  local args = space_pos and cmd:sub(space_pos + 1) or ''

  local handler = command_handlers[verb]
  if handler then
    return handler(args)
  end

  return 'ERROR: Unknown command: ' .. verb
end
```

A table `command_handlers` maps verb → function(args) → string response:

```lua
command_handlers = {
  readBytes = function(args)
    local addr, size = args:match('^(%x+) (%d+)$')
    if not addr then return 'ERROR: Usage: readBytes <hexaddr> <size>' end
    local bytes = readBytes(tonumber(addr, 16), tonumber(size), true)
    if bytes then return bytes_to_hex(bytes) end
    return 'ERROR: readBytes failed at ' .. addr
  end,
  -- ... all other handlers follow same pattern
}
```

#### Error handling strategy

| Failure mode | Handling |
|---|---|
| `createPipe` fails | Set `_G._server_error`, return from thread |
| `pipe.acceptConnection` fails | Loop back to retry |
| `readBytes` returns nil | Return `ERROR: readBytes failed at <addr>` |
| `writeBytes` returns 0 | Return `ERROR: writeBytes failed` |
| Unknown command | Return `ERROR: Unknown command: <verb>` |
| Lua runtime error in handler | Caught by `pcall` in main loop |
| Thread terminated by user | `t.Terminated` → clean break from loops |

#### AOBScan result serialization

`AOBScan()` returns a `TStringList` object (confirmed at
`LuaHandler.pas:4421-4426`). From Lua, this is a CE object with `.Text`,
`.Count`, and `[i]` accessors:

```lua
command_handlers.aobScan = function(args)
  local pattern, prot = args:match('^([^ ]+) ?(.*)$')
  if not pattern then return 'ERROR: Usage: aobScan <pattern> [prot]' end
  local list = AOBScan(pattern, prot)
  if not list then return 'ERROR: No results' end
  local result = list.Text  -- tab-separated hex addresses
  list.destroy()
  return result
end
```

#### Breakpoint management

`debug_setBreakpoint` stores the callback in the Lua registry (via
`luaL_ref`). The callback remains valid as long as the Lua state lives. Since
the background thread uses a coroutine of the main Lua state (`_LuaVM`), the
callback survives for the entire CE session.

```lua
-- Register the breakpoint callback globally (needed for named-function form)
_G._bp_callback = function()
  _G.bp_hit = true
  _G.bp_state = 'broken'
  return 1  -- 1 = break (stay paused)
end

-- Set breakpoint (named-function form, strings are easier from pipe input)
command_handlers.setBreakpoint = function(args)
  local addr = args:match('^(%x+)$')
  if not addr then return 'ERROR: Usage: setBreakpoint <hexaddr>' end
  debug_setBreakpoint(tonumber(addr, 16), '_bp_callback')
  _G.debug_state = 'waiting'
  return 'OK'
end
```

Note: The named-function form (`debug_setBreakpoint(addr, 'function_name')`)
is handled at `LuaHandler.pas:3788-3791` — `lc.luaroutine:=Lua_ToString(L,3)`.
The function is looked up by name from globals when the breakpoint fires.

#### Thread lifetime

The background thread runs until:
1. The pipe client disconnects (sends `close` or closes socket)
2. The user closes the Lua Engine tab in CE (terminates the Lua state)
3. An unrecoverable error in the pipe server

`createThread` with default `FreeOnTerminate=true` (TCEThread default in
`LuaThread.pas:279`: `c.FreeOnTerminate:=true`) means the thread object is
auto-freed when `Execute` returns.

---

## Option 2: Minimal `createThread` wrap (fallback)

### What it is

Take the existing `ce_server.lua` as-is and wrap the `main()` call in
`createThread`. No other changes.

### Code change

Replace the final `main()` call at the bottom of `ce_server.lua`:

```lua
-- Before: blocks main thread, CE UI freezes
-- main()

-- After: runs in background thread, CE UI stays responsive
createThread(function(t)
  t.Name = 'UEScanServer'
  main()
  -- When main() returns, thread terminates and self-destructs
end)
-- Lua Engine script exits immediately here
```

### What changes

| Before | After |
|---|---|
| CE UI freezes while server runs | CE UI stays responsive |
| Script blocks on `pipe.acceptConnection()` | Block happens in background thread |
| Must minimize CE and leave it | Can use CE normally while server runs |
| Can't stop server without closing CE | Can close Lua Engine tab to stop |

### What stays the same

- All existing commands work identically
- No new commands
- No debugger support
- Same protocol
- Same relay and client
- Same error handling (none — `main()` errors crash the thread silently)

### Pros and cons

- **Pro**: 10-minute change, zero risk, zero code changes to existing commands
- **Con**: No breakpoints, no registers, no stepping, no AOBScan, no
  float/double/typed commands
- The 53 existing investigation scripts still work via `runScript`, but
  register-dump scripts (30, register_dump) still require manual CE UI setup
- **Thread safety risk**: `main()` calls `error()` on pipe failure (`ce_server.lua:155`)
  which raises a Lua error in the `lua_pcall` at `TCEThread.execute` line 146.
  This is caught by the thread's error handler (prints to console) — the thread
  simply exits. Not a crash, but silent failure.

### Thread safety note

The existing `main()` function never touches CE UI or uses `synchronize()`.
All calls (`createPipe`, `readBytes`, `writeBytes`, `readQword`, `writeBytes`,
`getAddressSafe`, `enumModules`, `loadstring`/`pcall`) are safe from a
background thread per the source analysis above.

### Implementation findings (source-verified from CE 7.5)

**Source file:** `luapipeserver.pas` (line 71):
```pascal
pipe:=CreateNamedPipe(pchar('\\.\pipe\'+pipename), PIPE_ACCESS_DUPLEX,
  PIPE_TYPE_BYTE or PIPE_READMODE_BYTE or PIPE_WAIT, 1, inputsize, outputsize,
  INFINITE, @a);
```
- `nMaxInstances=1` — only one client can connect at a time.
- `PIPE_TYPE_BYTE | PIPE_READMODE_BYTE` — **byte mode**, not message mode.
  Each `ReadFile`/`WriteFile` operates on a raw byte stream with no message
  boundaries. The client must use a length-prefixed protocol (as our relay does).
- `PIPE_WAIT` — blocking mode. The relay must stay in blocking mode; the
  original bug was setting `PIPE_NOWAIT` via `SetNamedPipeHandleState`.

**Source file:** `luapipeserver.pas` (lines 38-46):
```pascal
function TLuaPipeServer.WaitForClientConnection;
begin
  fconnected:=ConnectNamedPipe(pipe, nil);
  if not fconnected then
    fconnected:=getlasterror()=ERROR_PIPE_CONNECTED;
  result:=fConnected;
end;
```
- `acceptConnection` calls `ConnectNamedPipe` **without** first calling
  `DisconnectNamedPipe`. After a client disconnects, `ConnectNamedPipe` on
  the same handle fails (the pipe is still in a "connected" state). The
  server enters a tight spin loop: `ConnectNamedPipe` → fail → `connected=false`
  → loop → `ConnectNamedPipe` → fail → ...
- The server can never accept new clients. The relay's `CreateFileW` succeeds
  (pipe handle is valid) but CE never reads from the new connection.

**Source file:** `luapipe.pas` (lines 350-411):
```pascal
fconnected:=fconnected and Readfile(pipe, bytes^, size, br, nil);
```
- Synchronous `ReadFile` (default, `foverlapped=false`). When the client
  disconnects, `ReadFile` returns FALSE → `fconnected=false` → the inner
  loop exits. But `CloseConnection` is NOT called for synchronous I/O errors
  — the handle remains open but unusable for reconnection.

**Required workaround:** Destroy the pipe after client disconnect and create
a new one. The current `ce_server.lua` does this by moving `createPipe`
inside the main loop:

```lua
while not t.Terminated do
  local pipe = createPipe(PIPE_NAME, PIPE_BUFFER, PIPE_BUFFER)
  if not pipe or not pipe.valid then
    sleep(1000)  -- retry if old instance not fully cleaned up
  else
    pipe.acceptConnection()
    while pipe.connected and not t.Terminated do
      -- handle commands
    end
    pipe.destroy()  -- close handle so new createPipe can succeed
  end
end
```

### Pipe mode compatibility

The relay opens the pipe with `CreateFileW` using `OPEN_EXISTING` and no
`FILE_FLAG_OVERLAPPED` — synchronous byte-mode access, matching CE's
`PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_WAIT`. The relay does **not**
call `SetNamedPipeHandleState` (the original code did, which put the pipe
into `PIPE_NOWAIT` mode and broke `ReadFile`).

Because the pipe is in byte mode, a length-prefixed protocol is required
to delimit messages. The protocol uses `[4-byte LE length][N bytes of text]`
framing, which the relay forwards verbatim between TCP and the pipe.

### Bug fixes in `windows_relay.py`

Three issues were found and fixed:

**1. Removed `SetNamedPipeHandleState(mode=1)`** — The original relay
called `SetNamedPipeHandleState` with `PIPE_NOWAIT` (mode=1), putting the
pipe into non-blocking mode. This caused `ReadFile` in `read_exact` to
return immediately with `ERROR_NO_DATA`, making the `pipe_to_tcp` thread
exit prematurely. Fix: removed the call entirely — the pipe stays in
blocking (synchronous) mode.

**2. Removed `WaitNamedPipeW` from `connect()`** — The original `connect()`
called `WaitNamedPipeW` with `NMPWAIT_USE_DEFAULT_WAIT` (30-second timeout)
before `CreateFileW`. If the pipe wasn't ready yet, this blocked the relay
for the full timeout on every retry attempt. Fix: simple `time.sleep(1)`
retry loop with `CreateFileW` directly — each attempt fails fast
(returning `ERROR_PIPE_BUSY` immediately) if the pipe isn't available.

**3. Changed `CancelIo` to `CancelIoEx` in `pipe.close()`** — This is the
root cause of the "second command hangs" bug. The relay uses two threads:
`tcp_to_pipe` (reads TCP → writes pipe) and `pipe_to_tcp` (reads pipe →
writes TCP). When the client disconnects:

1. `tcp_to_pipe`: `recv` returns empty → enters `finally` → calls
   `pipe.close()` → `CancelIo(handle)` → `CloseHandle(handle)`
2. `pipe_to_tcp`: still blocked on `ReadFile(handle)` waiting for CE data

`CancelIo` only cancels pending I/O for the **calling thread** — so
`pipe_to_tcp`'s `ReadFile` is NOT cancelled. `CloseHandle` decrements
the handle reference count, but `pipe_to_tcp`'s pending synchronous I/O
holds an additional kernel reference to the pipe object. The pipe enters a
**zombie state**: CE's `ReadFile` on the server side never sees a break
(because the kernel object still exists), so CE never destroys/recreates
the pipe. A new client's `CreateFileW` finds the existing but unusable
pipe and gets `ERROR_PIPE_BUSY`.

The fix: `CancelIoEx(handle, NULL)` cancels pending I/O across **all
threads** for the given handle. `pipe_to_tcp`'s `ReadFile` returns with
`ERROR_OPERATION_ABORTED`, `read_exact` returns `None`, `pipe_to_tcp`
exits cleanly. The pipe object is fully released, CE detects the
disconnection, destroys the pipe, and creates a new one ready for the
next client.

### Effort

~15 minutes. Edits to `ce_server.lua` and `windows_relay.py`:

### Script compatibility with remote interface

Of the 52 investigation scripts in the project tree, **51 work through the
remote interface** via `runScript`. Only `02_bp_inventory_path.lua` fails
entirely because it depends on CE's `debugger_onBreakpoint` callback and
per-breakpoint register globals (`RIP`, `RSP`, `RCX`) that don't exist in a
remote context. See `README.md`'s "Script Compatibility" section for details
and dependency requirements.

---

## Option 3: Built-in `TLuaServer` via auto-assembler (alternative)

### What it is

CE already includes a multi-threaded named pipe server (`lua_server.pas:592-622`).
`TLuaServer` listens on a pipe, spawns `TLuaServerHandler` threads per
connection. Each handler can execute Lua scripts synchronously or asynchronously.

The server is started from auto-assembler code (found at
`autoassemblercode.pas:1216-1218`):

```pascal
if luaserverExists('CELUASERVER'+inttostr(getcurrentprocessid))=false then
  tluaserver.create('CELUASERVER'+inttostr(getcurrentprocessid));
```

It's used by CE's auto-inject feature to provide a Lua callback channel from
injected code back into the CE process.

### Protocol

The built-in server uses a **binary protocol** (not text):

| Byte | Command |
|---|---|
| 1 | `ExecuteLuaScript(false)` — synchronize to main thread |
| 4 | `ExecuteLuaScript(true)` — async on handler thread |
| 2 | `ExecuteLuaScriptVar` — multiple return values |
| 3 | `ExecuteLuaFunction` — call by name or ref |

Parameters and return values are typed (nil, bool, int32, int64, double,
string). See `lua_server.pas:166-406` for the full binary format.

### Starting from Lua

`TLuaServer` is a Delphi class, not directly accessible from Lua. You'd need:

```lua
-- Auto-assembler script to start the server
autoAssemble([[
  luacall(openLuaServer('UEScanRemote'))
  CELUA_ServerName:
  db 'UEScanRemote',0
]])
```

Then write a separate Lua client that speaks the binary protocol to
`\\.\pipe\UEScanRemote`.

### Pros

- CE already handles threading
- Supports async execution (runs on handler thread without blocking main thread)
- Supports sync execution (marshals to main thread for GUI access)
- Binary protocol has proper type serialization

### Cons

- **Not a drop-in replacement** — the protocol is binary and different from our
  text-based protocol
- The built-in server expects the client to send scripts/functions, not
  text commands — we'd need a different client or an adapter
- `TLuaServer` only wraps scripts in a function call; it's not a general-purpose
  command dispatcher
- Starting it requires auto-assembler, not just Lua
- No direct access to set breakpoints or read registers through the server's
  interface

### Effort

~8-12 hours. Requires:
- Understanding the binary protocol (documented in `lua_server.pas`)
- Writing a new client/adapter that speaks the binary protocol
- The `windows_relay.py` would need to translate between our text commands and
  the binary protocol
- Testing the async execution path

---

## Summary comparison

| Feature | Option 1 (Full) | Option 2 (Minimal wrap) | Option 3 (Built-in) |
|---|---|---|---|
| CE UI responsive | Yes | Yes | Yes |
| Existing commands | All + new | All (unchanged) | Different protocol |
| Breakpoint polling | Yes | No | No |
| Registers/stepping | Yes | No | No |
| AOBScan | Yes | via runScript | via runScript |
| Float/double/typed | Dedicated commands | via runScript | via runScript |
| Effort | 4-5 hours | 10 minutes | 8-12 hours |
| Risk | Moderate | Minimal | High (protocol change) |
| Thread safety | Verified from source | Verified from source | Built-in |
