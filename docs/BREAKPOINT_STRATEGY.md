# Breakpoint Handling Strategy for Remote CE Interface

## Problem

Script `02_bp_inventory_path.lua` (and any workflow requiring breakpoints)
cannot work through the current remote interface because CE's breakpoint
model is **event-driven** (a callback fires on the debugger thread when a
breakpoint is hit), but our TCP/pipe interface is **polling-based** (the
client sends a command, the server executes it, and returns a response).

There is no way for the server to spontaneously push a "breakpoint hit"
notification to the client over the existing pipe.

## CE Debugger Architecture (source-verified)

From `LuaThread.pas`, `LuaHandler.pas`, and `LuaCaller.pas`:

```
┌──────────────────────────────────────────────────────────────┐
│  CE Process                                                   │
│                                                                │
│  Main Thread      Debugger Thread      Lua Server Thread      │
│  ┌──────────┐     ┌──────────────┐     ┌──────────────────┐   │
│  │ CE UI    │     │ TDebugger    │     │ createThread     │   │
│  │          │     │              │     │  (pipe server)   │   │
│  │          │     │ breakpoint   │     │                  │   │
│  │          │     │ fires ───────┼──>  │ _G.bp_hit = true │   │
│  │          │     │ (callback)   │     │ (writes globals) │   │
│  └──────────┘     └──────────────┘     └──────────────────┘   │
└──────────────────────────────────────────────────────────────┘
```

### Key facts

1. **Breakpoint callbacks fire on the debugger thread** (`LuaCaller.pas:1252`):
   - `LUA_onBreakpoint` sets register globals (`_G.RAX`, `_G.RBX`, ..., `_G.THREADID`)
   - Calls the registered Lua callback function
   - Reads modified globals back into CPU context (register modification works)

2. **Three coroutines of the same `_LuaVM`** (`LuaHandler.pas:194`):
   - Main thread coroutine (CE UI)
   - Debugger thread coroutine (breakpoint callbacks)
   - Background thread coroutine (our pipe server)
   - All share the `_G` (global) table

3. **Thread safety**:
   - `debug_isBroken()` reads `debuggerthread.CurrentThread.isHandled` directly
   - `debug_getContext()` reads `debuggerthread.CurrentThread.context` directly
   - `debug_setContext()` writes to `debuggerthread.CurrentThread.context` directly
   - All safe from background thread while process is paused at breakpoint
   - `createCriticalSection()` available for Lua-side mutex if needed

4. **Breakpoint callback return value**:
   - Return `1` → break, keep process paused
   - Return `0` → continue execution immediately

## Approach 1: Polling (Recommended)

### How it works

The server registers a breakpoint callback that sets global flags, and the
client polls a `debugStatus` command to detect when a breakpoint fires.

```
Client                          Server (background thread)    Debugger Thread
──────                          ──────────────────────────    ──────────────
setBreakpoint 7FF... ────────>  debug_setBreakpoint(addr,     
                                "_bp_callback")               
                              <─── OK                         
                                                                 (breakpoint hit)
poll: debugStatus ──────────>  check _G.bp_hit                 _bp_callback fires
                              <─── "waiting"                      _G.bp_hit = true
poll: debugStatus ──────────>  check _G.bp_hit               
                              <─── "broken RIP=7FF..."
getRegisters ──────────────>  read _G.RAX, _G.RBX, ...      
                              <─── RAX=... RBX=...
continue ──────────────────>  debug_continueFromBreakpoint(0)
                              <─── OK
```

### Server-side implementation

#### Register a breakpoint callback

```lua
_G._bp_callback = function()
  _G.bp_hit = true
  _G.bp_state = "broken"
  _G.bp_rip = _G.RIP
  _G.bp_threadid = _G.THREADID
  return 1  -- break, keep paused
end
```

This must be loaded into the CE Lua state before setting breakpoints
(e.g. via `runScript` at startup).

#### Set breakpoint command

```
setBreakpoint <hexaddr> [trigger]
```

```lua
elseif cmd:match("^setBreakpoint (%x+)$") then
    local addr = tonumber(cmd:match("^setBreakpoint (%x+)$"), 16)
    debug_setBreakpoint(addr, "_bp_callback")
    _G.debug_state = "waiting"
    return "OK"
```

Available trigger values (from `LuaHandler.pas:3856-3860`):
- `0` or omitted → execute breakpoint (when instruction at addr runs)
- `1` → write access
- `2` → read/write access

#### Remove breakpoint command

```
removeBreakpoint <hexaddr>
```

```lua
elseif cmd:match("^removeBreakpoint (%x+)$") then
    local addr = tonumber(cmd:match("^removeBreakpoint (%x+)$"), 16)
    debug_removeBreakpoint(addr)
    return "OK"
```

#### Debug status polling command

```
debugStatus
```

```lua
elseif cmd == "debugStatus" then
    if _G.bp_hit then
        _G.bp_hit = false
        return string.format("broken RIP=%s THREADID=%d",
                             (_G.bp_rip or "?"), (_G.bp_threadid or 0))
    end
    return _G.debug_state or "idle"
```

#### Register inspection

```
getRegisters
getRegister <name>
setRegister <name> <value>
```

```lua
elseif cmd == "getRegisters" then
    local names = {"RAX","RBX","RCX","RDX","RDI","RSI","RSP","RBP","RIP",
                   "R8","R9","R10","R11","R12","R13","R14","R15"}
    local parts = {}
    for _, n in ipairs(names) do
        if _G[n] then
            parts[#parts + 1] = string.format("%s=%s", n,
                string.format("%X", _G[n]))
        end
    end
    return table.concat(parts, " ")
```

#### Continue / Step

```
continue
stepInto
stepOver
```

```lua
elseif cmd == "continue" then
    _G.debug_state = "waiting"
    debug_continueFromBreakpoint(0)  -- co_run
    return "OK"
elseif cmd == "stepInto" then
    _G.debug_state = "waiting"
    debug_continueFromBreakpoint(1)  -- co_stepinto
    return "OK"
elseif cmd == "stepOver" then
    _G.debug_state = "waiting"
    debug_continueFromBreakpoint(2)  -- co_stepover
    return "OK"
```

### Client-side workflow (for agents)

```python
# Set breakpoint
ce.cmd("setBreakpoint 7FF6A1B2C000")

# Wait for it to fire (poll with timeout)
import time
deadline = time.time() + 30
while time.time() < deadline:
    status = ce.cmd("debugStatus")
    if status.startswith("broken"):
        rip = status.split()[0].split("=")[1]
        print(f"Breakpoint hit at {rip}")
        break
    time.sleep(0.1)

# Read registers
regs = ce.cmd("getRegisters")
print(regs)

# Modify RAX
ce.cmd("setRegister RAX 1")

# Continue execution
ce.cmd("continue")
```

### Limitations of polling

| Issue | Impact | Mitigation |
|-------|--------|------------|
| Latency between breakpoint hit and detection | Up to 100ms (poll interval) | Reduce poll interval; acceptable for most use cases |
| TCP/pipe round-trip per poll | ~1ms LAN, higher over VPN | Use local relay; keep poll interval >= round-trip time |
| Missed breakpoints if `bp_hit` is overwritten | Next poll catches it | Add incrementing counter `bp_count` to detect missed events |
| Client must keep connection alive during polling | Each poll = new TCP connection | Use `-i` (interactive mode) for persistent connection |

## Approach 2: Blocking `waitForBreakpoint` Command

Instead of polling from the client, push the polling into the server. The
client sends one command that blocks until a breakpoint is hit (or a
timeout expires).

```
Client                          Server
──────                          ──────
waitForBreakpoint ────────────>  while not _G.bp_hit and elapsed < timeout:
                                   sleep(50)
                                return status
                             <─── "broken RIP=7FF..."
```

### Server-side implementation

```lua
elseif cmd:match("^waitForBreakpoint (%d+)$") then
    local timeout = tonumber(cmd:match("^waitForBreakpoint (%d+)$"))
    local start = os.clock()
    while not _G.bp_hit and (os.clock() - start) < timeout do
        sleep(50)
    end
    if _G.bp_hit then
        _G.bp_hit = false
        return string.format("broken RIP=%s THREADID=%d",
                             (_G.bp_rip or "?"), (_G.bp_threadid or 0))
    end
    return "timeout"
```

This is more convenient for the client:

```python
status = ce.cmd("waitForBreakpoint 30000")  # wait up to 30s
if status.startswith("broken"):
    rip = status.split()[0].split("=")[1]
    regs = ce.cmd("getRegisters")
```

### Important: TCP timeout must be longer than the wait

Since the command blocks the pipe for up to `timeout` seconds, the client's
socket timeout must be set higher:

```python
ce = CERemote("localhost", 8888, timeout=60)  # 60s for 30s wait
result = ce.cmd("waitForBreakpoint 30000")    # 30s wait
```

### Handling multiple breakpoints

A single breakpoint callback overwrites `_G.bp_hit` each time. To track
multiple hits between polls, use a counter:

```lua
_G._bp_callback = function()
  _G.bp_hit = true
  _G.bp_count = (_G.bp_count or 0) + 1
  _G.bp_rip = _G.RIP
  return 1
end
```

The server clears `_G.bp_hit` when reporting. If a second breakpoint fires
before the client reads it, `bp_count` reveals the miss.

## Approach 3: Two-Pipe Architecture (Future)

For true event-driven breakpoint notification, use a second named pipe:

```
┌─────────┐  cmd pipe    ┌──────────────┐  cmd pipe    ┌──────────────┐
│ client  │<────────────>│   relay      │<────────────>│ ce_server    │
│         │  event pipe  │              │  event pipe  │              │
│         │<────────────>│              │<────────────>│ (background) │
└─────────┘              └──────────────┘              └──────────────┘
                                                                  │
                                                          debugger thread
                                                          fires callback →
                                                          writes to event pipe
```

### How it works

1. CE server creates TWO pipe instances on different names
   (e.g. `UEScanRemote_Cmd` and `UEScanRemote_Event`)
2. Relay manages two concurrent pipe connections per client
3. Breakpoint callback writes event data to the event pipe
4. Relay forwards event data to a second TCP connection
5. Client has a background thread reading the event connection

### Advantages

- Zero latency breakpoint notification (no polling)
- Client can block on event socket with `select()` or async I/O
- Scales to high-frequency breakpoint events

### Disadvantages

- Significantly more complex relay (two concurrent pipe connections)
- CE's `createPipe` creates single-instance pipes — needs two `createThread`
  servers or careful lifecycle management
- The event pipe must NOT block the callback (write must succeed or fail fast)
- Relay must handle partial failures (event pipe down ≠ kill cmd pipe)

### Feasibility assessment

| Factor | Assessment |
|--------|------------|
| CE `createPipe` supports multiple instances | No — `nMaxInstances=1`, need two separate pipe names |
| Callback can write to a different pipe | Yes — callback is a Lua function, can call `createPipe` + `writeString` |
| Write must be non-blocking | No — `PIPE_WAIT` is blocking. Callback blocks debugger thread if pipe is full. Use `PIPE_NOWAIT` or buffer events. |
| Relay complexity | High — two concurrent TCP connections per client, must pair them |
| Client complexity | Medium — event listener thread per session |

## Approach 4: Shared Memory + Relay Polling

Instead of a second pipe, the breakpoint callback writes to a fixed memory
address. The relay polls that address via a secondary connection.

```
┌─────────┐              ┌──────────────┐              ┌──────────────┐
│ client  │<──TCP cmd───>│   relay      │<──pipe cmd──>│ ce_server    │
│         │              │              │              │              │
│         │              │  relay also  │              │ bp callback  │
│         │              │  polls a     │<─readBytes──│ writes to a  │
│         │              │  "event flag"│              │ fixed addr   │
│         │              │  memory addr │              │ in Notepad   │
└─────────┘              └──────────────┘              └──────────────┘
```

### How it works

1. Server allocates a byte in Notepad's memory via `allocateMemory(1)`
2. Breakpoint callback writes `0x01` to that address: `writeBytes(addr, {1})`
3. Relay periodically reads that address via a second command pipe
4. When flag is set, relay sends an out-of-band TCP message to client

### Why this is impractical

- Relay doesn't have CE context — it can't call `readBytes` on Notepad
- Would need another full CE pipe connection just for polling
- Same complexity as Approach 3, but worse latency

## Recommendation

Use **Approach 1 (Polling)** as the primary strategy, with **Approach 2
(blocking wait)** as an optimization.

### Implementation priority

| Phase | What | Effort |
|-------|------|--------|
| 1 | Add `setBreakpoint`, `removeBreakpoint`, `debugStatus` commands | ~30 min |
| 2 | Add `getRegisters`, `getRegister`, `setRegister` commands | ~20 min |
| 3 | Add `continue`, `stepInto`, `stepOver` commands | ~10 min |
| 4 | Add `waitForBreakpoint` blocking command | ~10 min |
| 5 | Client-side polling loop in `-i` mode | ~10 min |
| 6 | Two-pipe architecture (if polling latency is unacceptable) | ~4 hours |

### Migration path for `02_bp_inventory_path.lua`

The current script is a passive logger that fires on each breakpoint hit:

```lua
function debugger_onBreakpoint()
    if RIP ~= TARGET then return 1 end
    print(string.format("RSP=%X RCX=%X", RSP, RCX))
    ...
    return 1
end
```

To work remotely, this becomes a client-side loop:

```python
# Set breakpoint once
ce.cmd("setBreakpoint TARGET")
# Poll loop
last_rip = None
while True:
    status = ce.cmd("waitForBreakpoint 60000")
    if status == "timeout":
        continue
    regs = ce.cmd("getRegisters")
    if regs.startswith("RIP=" + TARGET):
        print(regs)  # original script's logic
```

The breakpoint logic (inspecting RSP, RCX, walking the stack) moves from
the Lua callback into the client, which can execute CE commands to read
memory at register values.
