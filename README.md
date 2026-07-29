# Cheat Engine 7.5 Remote Control for OPENCODE/WSL

Bridge Cheat Engine 7.5's Lua scripting to TCP so an OPENCODE agent running in
WSL can inspect and manipulate game memory.

## Architecture

```
WSL (Agent)          Windows                  Cheat Engine
┌─────────┐  TCP    ┌──────────────┐  Named   ┌──────────────┐
│ client.py├───────>│windows_relay│───Pipe──>│ ce_server.lua │
│ (agent)  │ :8888  │ .py         │          │ (in CE)      │
└─────────┘         └──────────────┘          └──────────────┘
                                                    │
                                          ┌─────────┴─────────┐
                                          │ createThread      │
                                          │ Background thread │
                                          │ (CE UI responsive)│
                                          └───────────────────┘
```

The server runs in a background thread via CE's `createThread` API, keeping
CE's UI responsive. Each client connection gets its own pipe instance (CE
creates single-instance pipes; after a client disconnects, the pipe is
destroyed and a new one is created).

## Quick Start

### 1. Start the CE Lua server

In Cheat Engine, go to **Execute Lua Script** (`Ctrl+L`) and paste the contents
of `ce_server.lua`, then run it. You should see no errors (check CE's Lua
console).

**CE stays responsive** — the script uses `createThread` to run the pipe server
on a background thread. CE's UI remains usable while the server is running.

### 2. Start the Windows relay

Open a terminal **on Windows** (cmd, PowerShell, or from WSL via
`python.exe`) and run:

```
python windows_relay.py
```

Default: listens on `127.0.0.1:8888`, connects to `\\.\pipe\UEScanRemote`.

If connecting from a separate machine (or native Linux), bind to all interfaces:

```
python windows_relay.py --bind 0.0.0.0
```

**Important:** The relay opens the named pipe using synchronous I/O. Do
**not** call `SetNamedPipeHandleState` with `PIPE_NOWAIT` — the pipe must
stay in blocking mode for correct operation.

### 3. Test from WSL

```
python client.py
python client.py --cmd "ping"
python client.py --cmd "readQword 7FF6A1B2C000"
python client.py -i  # interactive shell
```

## Available Commands

| Command | Description |
|---|---|
| `ping` | Returns "pong" |
| `getVersion` | Server version string |
| `help` | List available commands |
| `readByte <hexaddr>` | Read 1 byte as hex |
| `readBytes <hexaddr> <size>` | Returns hex-encoded bytes |
| `readQword <hexaddr>` | Read 8 bytes as hex |
| `readDword <hexaddr>` | Read 4 bytes as hex |
| `readString <hexaddr> <maxlen>` | Read null-terminated string |
| `writeBytes <hexaddr> <hexbytes>` | Write hex bytes (e.g. `90 90`) |
| `getAddress <name>` | Resolve `module+offset` or symbol to hex address |
| `resolveSymbol <name>` | Alias for `getAddress` |
| `AOBScan <hexpattern> [prot]` | Array-of-byte scan, returns tab-separated addresses |
| `enumModules` | List loaded modules |
| `runScript <lua_code>` | Execute arbitrary CE Lua code |
| `close` | Disconnect |

Any CE Lua API not listed can be called via `runScript`.

## Prerequisites

### Windows side

| Requirement | Notes |
|---|---|
| **Cheat Engine 7.5** | Must be able to execute Lua scripts (Ctrl+L). |
| **Python 3.6+** (`python`) | Must be on PATH. Check with `python --version` in cmd. |
| **Named pipe access** | Standard users have it by default. No admin needed for the pipe itself. |
| **Port 8888 TCP** | Not opened by default (relay binds to 127.0.0.1). Only needed if using `--bind 0.0.0.0`. |

### WSL side

| Requirement | Notes |
|---|---|
| **Python 3.6+** (`python3`) | Pre-installed on Ubuntu/Debian WSL. Check with `python3 --version`. |
| **TCP to Windows host** | WSL2 forwards `localhost` to Windows automatically. WSL1 shares the Windows network stack. |

### Network communication

- **WSL2**: `localhost` (e.g., `localhost:8888`) is auto-forwarded to the
  Windows host. No special configuration needed.
- **WSL1**: Shares the Windows IP stack — `localhost` works directly.
- **Native Linux (dual boot)**: Use `--bind 0.0.0.0` on the relay and
  `--host <windows-ip>` on the client. May need to allow TCP port in
  Windows Defender Firewall.
- **Firewall**: If you change `--bind` to `0.0.0.0`, you may need to allow
  inbound TCP/8888 in Windows Defender Firewall.

## Starting Everything

### Option A: Manual

1. Open CE → `Ctrl+L` → paste `ce_server.lua` → Run
2. Windows terminal: `python windows_relay.py`
3. WSL: `python client.py --cmd "readQword 7FF6A1B2C000"`

### Option B: From WSL (start relay automatically)

```bash
powershell.exe -Command "Start-Process python -ArgumentList 'windows_relay.py' -WindowStyle Hidden"
```

### Option C: Persistent relay via Windows Task Scheduler

Create a task that runs `python C:\path\to\windows_relay.py` at startup.

## CE Lua API Reference

Every CE Lua function used in `ce_server.lua` was verified against the CE 7.5
source code at `/mnt/y/Lazarus/Projects/cheat-engine-7.5/Cheat Engine/`.

### Pipe API (luapipeserver.pas + luapipe.pas)

| Function | Source | Behavior |
|---|---|---|
| `createPipe(name, inSize, outSize)` | `luapipeserver.pas:121` | Returns a pipe object, or `nil` on failure. Creates a **single-instance** pipe (`nMaxInstances=1`). |
| `pipe.valid` | `luapipeserver.pas:25` | `true` if the handle is valid. |
| `pipe.acceptConnection()` | `luapipeserver.pas:115` | Blocks until a client connects (calls `ConnectNamedPipe`). Does **not** call `DisconnectNamedPipe` between reconnections. |
| `pipe.connected` | `luapipe.pas:64` | `false` when client disconnects. |
| `pipe.readBytes(size)` | `luapipe.pas:451` | Returns byte table (1-indexed), or `nil` on failure. Uses synchronous `ReadFile` by default (`foverlapped=false`). |
| `pipe.writeBytes(table, size)` | `luapipe.pas:413` | Writes bytes from table. Returns count or 0. |
| `pipe.writeString(str, incZero)` | `luapipe.pas:738` | Writes string; `incZero` appends null terminator. |
| `pipe.destroy()` | `luapipe.pas:80` (destructor) | Closes the pipe handle and frees resources. Explicitly needed before recreating (since `acceptConnection` can't reset without `DisconnectNamedPipe`). |

### Bitwise API (LuaBinary.pas)

| Function | Source | Behavior |
|---|---|---|
| `bShr(value, shift)` | `LuaBinary.pas:52` | Right-shift: `value >> shift`. |

### Standard Lua 5.1

Loaded via `luaL_openlibs` at `LuaHandler.pas:16185`. Available: base,
string, table, math, io, os, coroutine, package, debug.

Functions used: `string.char`, `string.byte`, `string.sub`, `string.format`,
`table.concat`, `ipairs`, `tonumber`, `tostring`, `pcall`, `loadstring`,
`error`.

### Thread API (LuaThread.pas)

| Function | Source | Behavior |
|---|---|---|
| `createThread(func)` | `LuaThread.pas:336-338` | Creates a background thread running `func(t)`. The thread gets its own coroutine of the main `_LuaVM`. The main script exits immediately. Used by `ce_server.lua` to keep CE UI responsive. |
| `t.Name` | `TCEThread` | Thread name for debugging (shown in `OutputDebugString`). |
| `t.Terminated` | `TCEThread` | Flag set by CE when the thread should stop (e.g., Lua Engine tab closed). Checked in server loops for clean shutdown. |
| `sleep(ms)` | Lua standard | Pauses the current thread. Used in retry loops. |

### Global CE Memory Functions (LuaHandler.pas)

#### readBytes(address, size, returnAsTable)

| | |
|---|---|
| **Source** | `LuaHandler.pas:16199`, impl `readBytesEx` lines 2508--2572 |
| **Success** | With `true` 3rd arg: table of bytes (1-indexed integers). |
| **Failure** | Returns `nil`. |

#### writeBytes(address, byte1, ...) / writeBytes(address, {table})

| | |
|---|---|
| **Source** | `LuaHandler.pas:16200`, impl `writeBytesEx` lines 2575--2652 |
| **Success** | Returns integer: bytes written. Server checks `n > 0`. |
| **Failure** | Returns 0. Note: 0 is truthy in Lua! |

#### readQword(address)

| | |
|---|---|
| **Source** | `LuaHandler.pas:16205`, impl `readQwordEx` lines 1983--2015 |
| **Success** | Returns 8-byte value as integer. |
| **Failure** | Returns `nil`. |

#### readInteger(address, signed)

| | |
|---|---|
| **Source** | `LuaHandler.pas:16204`, impl `readIntegerEx` lines 1930--1971 |
| **Success** | Returns 4-byte value as integer (unsigned by default). |
| **Failure** | Returns `nil`. |

#### readString(address, maxSize, useWideChar)

| | |
|---|---|
| **Source** | `LuaHandler.pas:16209`, impl `readStringEx` lines 2126--2199 |
| **Success** | Returns null-terminated string. |
| **Failure** | Returns `nil`. |

#### getAddressSafe(symbolOrAddress, local)

| | |
|---|---|
| **Source** | `LuaHandler.pas:16243`, impl lines 4493--4540 |
| **Success** | Returns resolved address as integer. |
| **Failure** | Returns `nil` (no Lua error). |

Prefer over `getAddress` which raises a Lua error on failure (crashes server).

#### enumModules(pid)

| | |
|---|---|
| **Source** | `LuaHandler.pas:16317`, impl lines 4753--4852 |
| **Success** | Returns table with `Name`, `Address`, `Is64Bit`, `PathToFile`. |
| **Failure** | Returns `nil` (e.g. no process attached). |

## Protocol

Length-prefixed binary framing:

```
[4-byte LE length][N bytes of UTF-8 text]
```

Responses use the same framing. Each `client.py` invocation opens a
fresh TCP connection (and consequently a fresh pipe connection), sends
one command, receives one response, and closes. Interactive mode (`-i`)
opens a new connection per command as well.

## Script Compatibility

The project contains ~52 Lua investigation scripts (in the parent directory).
Our remote interface can execute **51 of 52** via `runScript`:

| Status | Count | Details |
|--------|-------|---------|
| **Works via runScript** | 51 | Use only CE native APIs accessible from a `createThread` background thread (`readBytes`, `readQword`, `getAddress`, `AOBScan`, etc.) |
| **Completely fails** | 1 | `02_bp_inventory_path.lua` — relies on `debugger_onBreakpoint()` callback + `RIP`/`RSP`/`RCX` register globals that only exist during CE breakpoint events |

### Dependencies

- **~31 scripts** depend on `UEngine_findCharacter()` from `CE75.LUA` — this
  must be loaded into the CE Lua state first (execute via `runScript` or
  manually in CE's Lua Engine) before running dependent scripts
- **6 scripts** depend on `inventory_display_helper.lua` — must be loaded first
- **5 scripts** use `io.open()` for file output — works from background thread
- **AOBScan-based scripts** (14 scripts) may take 10-30s for full-process
  scans; ensure client timeout is sufficient (`--timeout 60`)

### CE APIs Available via runScript

Any CE Lua function accessible from a `createThread` context can be called
through `runScript`. This includes all functions verified safe from a
background thread per the source analysis in `SOLUTION.md`:

- **Memory**: `readByte`, `readBytes`, `readQword`, `readInteger`,
  `readSmallInteger`, `readPointer`, `readFloat`, `readDouble`,
  `readString`, `writeBytes`, `writeQword`, `writeInteger`,
  `writeSmallInteger`, `writeByte`, `writeFloat`, `writeDouble`,
  `writeString`
- **Scanning**: `AOBScan`, `createMemScan`, `createFoundList`
- **Symbols**: `getAddress`, `getAddressSafe`
- **Modules**: `enumModules`, `getModuleSize`
- **Process**: `openProcess`, `getOpenedProcessID`
- **Debugger** (limited): `pause`, `unpause`, `debugProcess` (all use
  `pluginsync`, work from background thread)
- **Windows**: `findWindow`, `sendMessage`, `getWindow`
- **Memory allocation**: `allocateMemory`, `virtualAllocEx`, `readString`,
  `writeString`
- **File I/O**: `io.open`, `io.write`, `io.close`

## Named Pipe Mode

CE's `createPipe` creates pipes with `PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_WAIT`
(verified from `luapipeserver.pas:71`). This is **byte mode**, not message mode:

- Each `ReadFile`/`WriteFile` operates on a raw byte stream
- No message boundaries — the client must use a length-prefixed protocol to know
  where responses end (which is what our relay does)
- `PIPE_WAIT` = blocking/synchronous I/O (the relay must stay in blocking mode)

Our relay does **not** call `SetNamedPipeHandleState` at all — it opens the
pipe with `CreateFileW` and defaults to byte mode, which matches CE's pipe
mode. This is correct for the length-prefixed protocol.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `Failed to create named pipe` | CE can't create `\\.\pipe\UEScanRemote` | Run CE as Administrator, or check no other instance owns the pipe. |
| No response from CE server | CE not running the Lua script, or relay not running | `python client.py --cmd "ping"` — expect "pong". |
| Connection refused (WSL) | Relay not started | Start `windows_relay.py` on Windows. |
| Connection refused (Windows) | Port conflict | Use `--port` to change port. Process list: `netstat -ano \| find :8888`. |
| CE freezes (only if running old synchronous `ce_server.lua`) | Old version called `main()` on main thread | Update to the current `ce_server.lua` which uses `createThread` for background execution. |
| Server responds to first command but hangs on reconnection | CE's `CreateNamedPipe` creates a single-instance pipe and `acceptConnection` doesn't call `DisconnectNamedPipe` before `ConnectNamedPipe` | Already fixed in current `ce_server.lua` — destroys and recreates the pipe per client. |
| No response from CE server after fresh start | CE running the Lua script but pipe not ready yet | Wait 1-2s after executing script, then retry. Relay retries pipe connection 10 times with 1s delays. |
| Timeout reading from pipe in relay | Client disconnected abruptly | No action needed — relay cleans up automatically. |
| CE server doesn't detect disconnection (pipe appears busy) | Pending `ReadFile` in relay's `pipe_to_tcp` thread holds kernel reference after `CloseHandle` | Fixed in relay — uses `CancelIoEx` to cancel pending I/O across all threads before closing the handle. |
| `python: command not found` (Windows) | Python not on PATH | Reinstall Python and check "Add Python to PATH". |
| WSL can't reach Windows | WSL2 network config | Use `ip route \| grep default` to get Windows host IP, then `python client.py --host <IP>`. |

## Security Considerations

- The relay binds to `127.0.0.1` by default — only local connections.
- No authentication or encryption. Anyone who can reach the TCP port can send
  arbitrary commands to CE.
- If you must access from another machine, use `--bind 0.0.0.0` and restrict
  with Windows Firewall or SSH tunneling.
- The `runScript` command allows arbitrary Lua execution in CE — equivalent
  to full memory read/write access to all attached processes.

## Requirements

- Cheat Engine 7.5
- **Windows**: Python 3.6+ (no extra packages, uses stdlib + ctypes only)
- **WSL/Linux**: Python 3.6+ (stdlib only)
