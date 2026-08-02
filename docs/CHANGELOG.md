# Changelog (CE remote server / protocol)

Versions are reported by `getVersion` from `ce_server.lua`.  
Reload the Lua script in CE after updating the file.

| Version | Highlights |
|---------|------------|
| **v1.8.3** | Native **`GroupScan`** (main-thread `vtGrouped` memscan); version string notes groupscan. See [CE-GROUP-SCAN.md](CE-GROUP-SCAN.md). |
| **v1.7+** | Structure seed (`stEnsureSeed` / `DO_NOT_DELETE_PLACEHOLDER`), safe rename (`stEnd` before `stSetName`), table migration hardening. |
| **v1.8.4** | **Restartable pipe server:** re-Execute `ce_server.lua` stops old thread (`terminate` + destroy `_server_pipe` to unblock `acceptConnection`/`ReadFile`), then starts fresh. Commands `shutdown`/`stop`. Closing Lua console alone never stopped the server (native `createThread`). |
| **relay** | **Timed pipe I/O:** `windows_relay.py` uses overlapped Read/Write + WaitForSingleObject (`--timeout`, default 300s). Avoids infinite hang / unkillable-feeling cmd when CE dies mid-command. Accept loop uses 1s timeout so Ctrl+C works. |
| **v1.1+** | `AOBScan` optional `**` wildcards. |
| Earlier | Background `createThread` pipe server; length-prefixed protocol; memory read/write; `runScript`; address-list and structure command families. |

Client: `client.py` (`CERemote`) — helpers for `al_*`, `st_*`, `aob_scan`, `group_scan`, optional session log (`CE_SESSION_LOG` / `--session-log`).  
Relay: `windows_relay.py` — default `127.0.0.1:8888` → `\\.\pipe\UEScanRemote`.

If this table lags the code, trust `getVersion` and the `help` command over this file, then update this changelog.
