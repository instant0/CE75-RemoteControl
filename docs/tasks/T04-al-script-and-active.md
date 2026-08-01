# T04 — AA scripts: chunked get/set + Active enable/disable

| Field | Value |
|-------|--------|
| **ID** | T04 |
| **Status** | DONE (see T04-RESULTS.md) |
| **Phase** | 1 — Address list scripts |
| **Parent** | T03 |
| **Children** | T09 (migration skill AA tier) |
| **Depends on** | T01, T02, T03 |
| **Blocks** | Full AOB rebind automation in T09 |

## Goal

Let the agent **read and replace** Auto Assembler script text on existing AA memrecs (AOB patterns, registersymbol, etc.), and **enable/disable** those entries safely enough for remote use—with chunking so large scripts do not blow the pipe buffer.

## Context

### CE API (`LuaMemoryRecord.pas`)

- `getScript`: returns text only if `AutoAssemblerData.script <> nil`.
- `setScript`: **no-op** if script is nil — cannot attach a script to a non-AA row merely by setting `.Script`.
- `Active = true`: runs enable / `autoassemble`; may `registersymbol` and trigger **reinterpret all addresses**.
- `disableWithoutExecute()`: deactivate without running [Disable] section (available on memrec).

### Remote constraints

- Single message soft max ~48 KiB.
- `Active=true` may open **modal error dialogs** → **deadlock** with `synchronize` if main thread blocks. Mitigations: `autoAssembleCheck` first; high client timeout; user can dismiss; document.
- Enabling injects into the **game** — agent/user risk.

## Commands to implement

### `alGetScript <id> [offset] [length]`

- Defaults: `offset=0`, `length=16384`.
- If not AA / no script: `ERROR: NOT_AA`.
- Response:

```text
OK ID=... TOTAL=... OFFSET=... LENGTH=... DATA=<hex>
```

- `DATA` is **hex encoding** of the UTF-8 (or CE raw) script bytes for the slice — avoids newline/command parsing issues. Reuse `bytes_to_hex` style from server.

### `alSetScriptBegin <id> <totalLen>`

- Validates memrec is AA with script object.
- Allocates staging in `_G._ue_script_stage[id] = { total=totalLen, buf={} or string parts }`.
- Caps `totalLen` (e.g. max **256 KiB**) → else ERROR.
- Response: `OK ID=... TOTAL=...`

### `alSetScriptChunk <id> <offset> <hexdata>`

- Writes chunk at byte offset into staging.
- Reject overlap policy: allow sparse until commit, or require sequential — **require sequential** for simplicity (`offset == received`).
- Response: `OK ID=... RECEIVED=... TOTAL=...`

### `alSetScriptCommit <id>`

- If `received ~= total` → ERROR.
- `mr.Script = assembledText` inside sync.
- Clear staging.
- Response: `OK ID=... SCRIPTLEN=...`

### `alSetScriptAbort <id>`

- Clear staging. `OK`

### `aaCheck <id>`

- `autoAssembleCheck(mr.Script, true, false)` inside sync.
- Response: `OK ID=...` or `ERROR: AACHECK: <msg>`

### `alSetActive <id> 0|1`

- `mr.Active = (v==1)` inside sync.
- On enable failure CE may still throw/dialog — wrap pcall; return ERROR if still not active when expecting on.
- Response: `OK ID=... ACTIVE=...`
- **Document** client timeout ≥ 120.

### `alDisableSoft <id>`

- `mr.disableWithoutExecute()` 
- Response: `OK ID=... ACTIVE=0` (best effort)

## Implementation notes

- Hex codec already in `ce_server.lua` (`bytes_to_hex`, `hex_to_table`) — extend for string↔hex if needed:

```lua
local function str_to_hex(s) ... end
local function hex_to_str(h) ... end
```

- Staging must not grow unbounded across sessions: abort on Begin for same id; clear on commit/abort.
- Log to CE console only command name + id, **not** full script.

## Acceptance criteria

- [ ] Round-trip: GetScript full (multi-chunk) → Begin/Chunk/Commit identical TOTAL and content.
- [ ] `alSetScript*` on non-AA → `ERROR: NOT_AA`.
- [ ] `aaCheck` returns false path without killing server.
- [ ] `alSetActive 0` on active row deactivates (when CE allows).
- [ ] Staging cleared after commit/abort; second commit without begin fails.
- [ ] help updated.

## Out of scope

- Automatically rewriting AOB bytes (agent-side)
- Breakpoint-based instance scripts (see BREAKPOINT_STRATEGY; not v1)
- Creating new AA memrecs from scratch with empty script object (research-hard; document if impossible without UI)

## Won’t work (document in help/skill)

| Case | Reality |
|------|---------|
| BP-only discovery scripts | No push BP events over pipe |
| Scripts that show input modals | Deadlock risk |
| setScript on non-AA | CE no-op |
| Guaranteed silent AA errors | Dialogs possible |

## Crash / hang awareness

| Risk | Mitigation |
|------|------------|
| synchronize + modal on bad AA | aaCheck first; timeout; soft disable recovery |
| Huge script one-shot | chunk only |
| Partial inject | alDisableSoft; user fix game/CE |
| Reinterpret storm enabling many scripts | Skill: enable one-by-one (T09) |

## Files

- `ce_server.lua`
- `client.py` optional helpers can wait for T07; server must be complete here

## Manual test

```bash
python client.py --timeout 120 --cmd "alGetScript <aaId> 0 16384"
# reassemble hex client-side; modify pattern; push chunks
python client.py --timeout 120 --cmd "aaCheck <aaId>"
python client.py --timeout 120 --cmd "alSetActive <aaId> 1"
python client.py --timeout 120 --cmd "alResolve <dependentId>"
```

## Depends on wire format stability

T07 will implement `al_get_script` / `al_set_script` using these exact commands.
