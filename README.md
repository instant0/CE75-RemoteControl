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

![Project Screenshot](assets/ue-scan.png)

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
| `tableStatus` | Process, pid, address-list count, structure count (main thread) |
| `debugSync` | Smoke-test main-thread `synchronize` path |
| `alDump [offset] [limit]` | Address-list inventory TSV (no script bodies); CLASS=AA/EXPR/… |
| `alGet <id>` | One memrec detail (metadata + value sample) |
| `alResolve <id>` | Live CurrentAddress / readable / value |
| `alSetDesc <id> <text>` | Rename/set description |
| `alSetAddress <id> <expr>` | Set address expression (keeps offsets) |
| `alSetOffsets <id> <hex,hex>` | Set pointer offset chain |
| `alSetType <id> <n>` | Set variable type integer |
| `alGetScript <id> [off] [len]` | AA script slice as hex |
| `alSetScriptBegin/Chunk/Commit/Abort` | Chunked AA script replace |
| `aaCheck <id>` | Syntax-check AA script |
| `alSetActive <id> 0\|1 [nocheck]` | Enable/disable (AA enable runs aaCheck unless `nocheck`) |
| `alDisableSoft <id>` | Disable without running [Disable] section |
| `alApply stop=1 hex=…` | Batch setDesc/setAddress/setOffsets/setType (one sync) |
| `alAudit [n]` | Recent command audit ring buffer |
| `symGet` / `symSet` | Resolve / registerSymbol helpers |
| `runScriptSafe <code>` | runScript with banned-API string filter |
| `stDump` | List global dissect structures (name/size/elems) |
| `stFind <name>` | Find structure by exact name |
| `stGet <name> [elemOff] [elemLimit]` | Dump structure elements (default limit 500) |
| `stEnsureSeed` | Ensure `DO_NOT_DELETE_PLACEHOLDER` exists (empty-list crash guard) |
| `stClone <src> <dst>` | Clone structure definition (`src -> dst` / `src\|dst` OK) |
| `stBegin` / `stEnd <name>` | Batch `beginUpdate` / `endUpdate` (commit before rename) |
| `stUpsertElem …` | Insert/update element at offset (prefer `name\|off\|…` form) |
| `stClearElements <name>` | Destroy all elements on a structure (not the placeholder) |
| `stSetName <old> <new>` | Rename **after** `stEnd` (refuses mid-edit) |
| `readByte <hexaddr>` | Read 1 byte as hex |
| `readBytes <hexaddr> <size>` | Returns hex-encoded bytes |
| `readQword <hexaddr>` | Read 8 bytes as hex |
| `readDword <hexaddr>` | Read 4 bytes as hex |
| `readString <hexaddr> <maxlen>` | Read null-terminated string |
| `writeBytes <hexaddr> <hexbytes>` | Write hex bytes (e.g. `90 90`) |
| `getAddress <name>` | Resolve `module+offset` or symbol to hex address |
| `resolveSymbol <name>` | Alias for `getAddress` |
| `AOBScan <hexpattern>` | Array-of-byte scan (`**` wildcards allowed in v1.1+), returns addresses |
| `enumModules` | List loaded modules |
| `runScript <lua_code>` | Execute arbitrary CE Lua code |
| `close` | Disconnect |

Any CE Lua API not listed can be called via `runScript`.

## Table migration (address list & structures)

Port a **loaded** `.CT` to a new game build over this remote: rebind AOBs/scripts, expression/pointer rows, and dissect definitions. The **user saves** in CE when satisfied (no agent `saveTable` pipeline).

| Resource | Role |
|----------|------|
| `docs/TABLE-MIGRATE.md` | Full command reference, wire formats, algorithm, crash rules |
| `skills/ce-table-migrate/SKILL.md` | Agent playbook (AA → enable → pointers → structs) |
| `skills/ce-table-remote/SKILL.md` | Foundation: `sync_call`, seed, rename-after-commit |
| `client.py` | `CERemote` helpers (`al_*`, `st_*`, script chunking, per-call timeout) |

```python
from client import CERemote
ce = CERemote("192.168.176.1", 8000, timeout=120)
print(ce.table_status())
print(ce.al_dump(limit=20)[:500])
ce.st_ensure_seed()  # if stCount was 0 — empty dissect list crashes CE
```

**Order:** fix/enable bootstrap AA (symbols) → fix EXPR/POINTER rows → validate structures.  
**Timeouts:** use **≥ 120s** for `alSetActive`, large `AOBScan`, large `stClone`.  
**Structures:** `stEnd` before `stSetName`; never `getStructure("name")`; keep `DO_NOT_DELETE_PLACEHOLDER`.

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
| Relay: cannot connect to pipe after it worked | Lua pipe thread **killed/hung by a prior client command** (not “cold start flaky”) | Reload `ce_server.lua`. Relay does **not** retry pipe open — one attempt, then fail. |
| Timeout reading from pipe in relay | Client disconnected abruptly | No action needed — relay cleans up automatically. |
| CE server doesn't detect disconnection (pipe appears busy) | Pending `ReadFile` in relay's `pipe_to_tcp` thread holds kernel reference after `CloseHandle` | Fixed in relay — uses `CancelIoEx` to cancel pending I/O across all threads before closing the handle. |
| `python: command not found` (Windows) | Python not on PATH | Reinstall Python and check "Add Python to PATH". |
| WSL can't reach Windows | WSL2 network config | Use `ip route \| grep default` to get Windows host IP, then `python client.py --host <IP>`. |

### Dangerous APIs (crash CE/relay)

These CE Lua functions frequently crash the relay or CE itself when called from the background thread. **Avoid them:**

| Function | Why it crashes | Safe alternative |
|---|---|---|
| `enumMemoryRegions()` | Returns protection-flag strings that crash the output parser; leaves CE in bad state | Use `enumModules()` for module bounds, or scan via `AOBScan` on known ranges |
| `createMemScan()` / `Memscan_firstScan` | CE's scan engine is not thread-safe; interleaves with background thread state | Use the native `AOBScan` command instead — stable and proven |
| `varscan_firstScan()` / `varscan_*` | Same issue as `createMemScan`; manipulates UI scan state | Use `AOBScan` |
| `AOBScan(..., "w", ...)` with string protection flag | Protection flags must be numeric bitmask or 3-char `"rwx"` format; `"w"` alone parses as garbage | Use `AOBScan(..., 2, ...)` (2=write) or omit protection flag entirely |
| `AOBScan` over >10MB range (via `runScript`) | Remote scan is slow; timeout/reset will leave server in bad state | Use the **native** `AOBScan` command instead: `AOBScan BC 12 00 00` — server handles it safely with `list.Text` + `list.destroy()` |
| `UEngine_findObjectStart()` | Iterates disconnected object links; crashes with bitwise error on nil | Don't use; scan for known values instead |
| `UEngine_getAllProperties(obj)` | Returns nil (not a table) unless passed a **class pointer** | Pass readQword(obj + 0x10) (the Class) instead of the object itself |
| `UEngine_findObjectStart()` | Iterates disconnected object links; crashes with bitwise error on nil | Don't use; scan for known values via `AOBScan` instead |
| `component_findComponentByName(obj, name)` | Only exists if G1R game plugin is loaded; crashes when absent | Wrap in `pcall` or load the plugin first |
| `enumModules()` property access (via `runScript`) | Module table keys are `Address` (uppercase), not `address`; accessing a nil field in `string.format` can crash | Use the native `enumModules` command (returns tab-separated text); or check key names first |
| `getStructure("Name")` (string arg) | Coerces to index **0** — can wipe/edit the first structure | Use native `stFind` / `stGet` or `_G._ue_st_find_by_name(name)` (index scan only) |
| Empty global structure list (0 dissects) | Dissect UI/callbacks: `list index (0) out of bounds` | `stEnsureSeed` / keep `DO_NOT_DELETE_PLACEHOLDER`; never empty the list |
| Rename structure while still editing (`beginUpdate`) | Rename fails or UI inconsistency | Always `stEnd` first, then `stSetName`; clones rename only after fill+commit |
| Address list / structures / `Active` without main-thread sync | VCL crash / corruption | Use native `al*`/`st*` only (server uses `synchronize`) |
| `synchronize` + CE modal dialog (failed AA) | **Deadlock** — pipe waits forever | `aaCheck` first; user present to dismiss; client timeout ≥120 |
| Mass `Active=true` | Inject storms, reinterpret storms, freezes | Enable **one** bootstrap/inject at a time |
| Dumping all AA scripts in one response | >48 KiB / hang | `alDump` metadata only; chunk with `alGetScript` / `al_get_script` |

## Making `runScript` calls safe

When you must use `runScript` (no native command exists), follow these rules:

| Rule | Why | Example |
|---|---|---|
| Always wrap in `pcall` | CE functions can throw Lua errors that kill the background thread | `local ok, r = pcall(readQword, addr)` |
| Never iterate unbounded loops | A nil pointer in a linked-list walk crashes the thread | Set a max iteration limit (e.g., `i < 100000`) |
| Guard against nil in `string.format` | `format("%X", nil)` errors instead of producing "nil" | `local v = val or 0` before formatting |
| Prefer native commands over raw CE API | Server wrapper handles cleanup (e.g., `list.destroy()`) | Use `AOBScan` not `runScript AOBScan(...)` |
| Check if a function exists before calling | Plugin functions may not be loaded | `if type(UEngine_getAllProperties) == "function" then ... end` |
| Verify object type before treating as UObject | A nil or non-UObject pointer has no Class at +0x10 | Check `readQword(addr + 0x10)` is non-zero before using |

## Security Considerations

- The relay binds to `127.0.0.1` by default — only local connections.
- No authentication or encryption. Anyone who can reach the TCP port can send
  arbitrary commands to CE.
- If you must access from another machine, use `--bind 0.0.0.0` and restrict
  with Windows Firewall or SSH tunneling.
- The `runScript` command allows arbitrary Lua execution in CE — equivalent
  to full memory read/write access to all attached processes.

## Agent Skills

The following skills are available for automated UE game memory hacking:

| Skill | Purpose |
|-------|---------|
| `ue-character-finding` | Locate the player character via GEngine chain or CE75 helpers |
| `ue-stats-attributes` | Find/modify health, mana, and GAS attribute values |
| `ue-inventory-hacking` | Read/modify inventory item counts |
| `ce-remote-scanning` | Memory scanning best practices and crash avoidance |
| `ce-table-remote` | Address-list/structure remote foundation (`sync_call`, seed, rename-after-commit) |
| `ce-table-migrate` | Port loaded CT to new game build (AA → enable → pointers → structs) |
| `game/DyingLight2/player-variables` | DL2 `playerStat` bootstrap AOB / EXPR row porting |

Load with: `skill ue-character-finding` (or path under `skills/`)

## Broad Reference

See `UE-Memory-Patterns.md` for a distilled guide to UE memory layout patterns
applicable across different games and UE versions.

## Disclaimer

Cheat Engine is a product of Eric "Dark Byte" Heijnen
(https://cheatengine.org). This project is an independent, third-party
remote-control interface that happens to communicate with Cheat Engine's
Lua scripting system. It has not been endorsed, reviewed, or approved by
Eric Heijnen or any Cheat Engine contributors, and is not affiliated with
the Cheat Engine project in any official capacity.

## Requirements

- Cheat Engine 7.5
- **Windows**: Python 3.6+ (no extra packages, uses stdlib + ctypes only)
- **WSL/Linux**: Python 3.6+ (stdlib only)
