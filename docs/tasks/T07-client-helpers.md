# T07 — `client.py` helpers for table migration

| Field | Value |
|-------|--------|
| **ID** | T07 |
| **Status** | DONE |
| **Phase** | 3 — Agent surface |
| **Parent** | T02–T06 (server commands) |
| **Children** | T09, T10 |
| **Depends on** | T02 minimum; ideally T02–T06 complete |
| **Blocks** | Convenient agent use; T10 tests |

## Goal

Extend `client.py` so agents/scripts call migration features without hand-building command strings or hex chunking.

## Context

- Today: `CERemote.cmd(command: str) -> str | None`, one TCP connection per command.
- Timeouts: default 30s is **too low** for `alSetActive` / large dumps — need per-call timeout or constructor default override.
- Script transfer uses hex chunks (T04).

## Implementation requirements

### Constructor

```python
CERemote(host="localhost", port=8888, timeout=30)
# add:
# timeout still default 30 for back compat
# methods that need longer pass timeout= override
```

Add optional `timeout=` parameter to `cmd()`:

```python
def cmd(self, command, timeout=None):
    ...
```

### Helpers (map 1:1 to server)

| Method | Server command(s) |
|--------|-------------------|
| `table_status()` | `tableStatus` |
| `al_dump(offset=0, limit=500)` | `alDump` |
| `al_get(id)` | `alGet` |
| `al_resolve(id)` | `alResolve` |
| `al_set_desc(id, text)` | `alSetDesc` |
| `al_set_address(id, expr)` | `alSetAddress` |
| `al_set_offsets(id, offsets: list[int])` | `alSetOffsets` |
| `al_set_type(id, type_int)` | `alSetType` |
| `al_get_script(id) -> str` | multi `alGetScript` |
| `al_set_script(id, text: str)` | Begin/Chunk/Commit |
| `aa_check(id)` | `aaCheck` |
| `al_set_active(id, active: bool, timeout=120)` | `alSetActive` |
| `al_disable_soft(id)` | `alDisableSoft` |
| `st_dump()` | `stDump` |
| `st_get(name)` | `stGet` |
| `st_find(name)` | `stFind` |
| `st_clone(src, dst)` | `stClone` |
| `st_begin/end/upsert...` | as implemented |

### Parsing

- Lightweight: return **raw strings** from server (agents can parse TSV).
- Optional: `al_dump_parsed() -> list[dict]` if cheap — nice-to-have.

### Script chunking

```python
CHUNK = 8192  # bytes before hex expansion (~16k hex chars)
def al_set_script(self, id, text, timeout=60):
    data = text.encode("utf-8", errors="replace")
    self.cmd(f"alSetScriptBegin {id} {len(data)}", timeout=timeout)
    off = 0
    while off < len(data):
        part = data[off:off+CHUNK]
        hx = part.hex()  # or match server encoder
        self.cmd(f"alSetScriptChunk {id} {off} {hx}", timeout=timeout)
        off += len(part)
    return self.cmd(f"alSetScriptCommit {id}", timeout=timeout)
```

Match server hex format exactly (nibble casing).

### CLI

Optional interactive improvements:

```bash
python client.py --timeout 120 --cmd "alDump"
```

Document examples in module docstring.

## Acceptance criteria

- [x] All shipped server commands from T02–T06 have a helper **or** are intentionally listed as raw-`cmd` only in docstring.
- [x] `al_get_script` / `al_set_script` round-trip helpers (chunk + abort on failure).
- [x] `al_set_active(..., timeout=120)` uses extended timeout.
- [x] No dependency beyond stdlib (keep project constraint).
- [x] `python client.py --cmd ping` still works.

## Out of scope

- Full migration algorithm (T09 skill)
- Async/parallel connections
- Changing relay protocol

## Crash / hang awareness

| Risk | Mitigation |
|------|------------|
| Client timeout during Active | default 120 on that helper |
| Partial script upload | call `alSetScriptAbort` on exception path |

## Files

- `client.py`
- Optionally `helper/table_migrate_smoke.py` minimal (or leave to T10)

## Test

```bash
python -c "from client import CERemote; c=CERemote(timeout=60); print(c.cmd('ping'))"
# live:
# print(c.al_dump()[:500])
```
