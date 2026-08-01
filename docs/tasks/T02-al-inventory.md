# T02 — Address list inventory: `alDump`, `alGet`, `alResolve`, `tableStatus`

| Field | Value |
|-------|--------|
| **ID** | T02 |
| **Status** | DONE (see T02-RESULTS.md) |
| **Phase** | 1 — Address list read path |
| **Parent** | T01 |
| **Children** | T03, T04 (consume dump shape) |
| **Depends on** | T01 |
| **Blocks** | T03, T04, T09 (skill assumes dump format) |

## Goal

Expose **read-only** native commands so an agent can inventory ~100 memory records without full script bodies (size-safe), then fetch detail / live resolve for one ID at a time.

## Context

- Product: version-port of loaded table; first step is **see** AA vs pointer vs static vs group.
- `runScript` returns `tostring(result)` only — native commands must pack multi-field rows as text.
- Do **not** include full `Script` text in `alDump` (can exceed 48 KiB across many AA entries).

## Commands to implement

### `tableStatus`

**Thread:** `sync_call`

**Response (single line or few lines):**

```text
OK process=<name> alCount=<n> stCount=<n> ceVersion=<ver>
```

Use `process` global, `getAddressList().Count`, `getStructureCount()`, `getCEVersion()` if available.

### `alDump`

**Thread:** `sync_call`

**Response:** header optional + TSV rows. Suggested columns:

| Col | Meaning |
|-----|---------|
| ID | MemoryRecord.ID |
| IDX | index in address list |
| PID | parent ID or -1 |
| DESC | scrubbed description |
| TYPE | numeric Type/VarType |
| ACTIVE | 0/1 |
| ADDR | interpretable Address string scrubbed |
| OFFC | OffsetCount |
| OFFS | offsets as `a+b+c` hex **or** empty if 0 (keep row short; long chains still ok) |
| CUR | CurrentAddress hex or 0 |
| HASSCRIPT | 0/1 |
| SCRIPTLEN | 0 or #Script |
| CLASS | heuristic: `AA` \| `POINTER` \| `STATIC` \| `GROUP` \| `OTHER` |

**CLASS heuristic (server-side):**

```text
if IsGroupHeader or IsAddressGroupHeader -> GROUP
elif HASSCRIPT or type is vtAutoAssembler (typically 8—confirm on install) -> AA
elif OFFC > 0 -> POINTER
elif ADDR non-empty -> STATIC
else OTHER
```

Confirm `vtAutoAssembler` numeric value from CE defines / spike (T00).

**Ordering:** index order `0 .. Count-1` is fine.

**Size:** metadata only; if still &gt; MAX_RESP, split later (`alDump fromIdx count`) — implement pagination if T00 showed overflow:

```text
alDump [offset] [limit]
```

Default `offset=0`, `limit=500`.

### `alGet <id>`

**Thread:** `sync_call`

Detail for one record:

```text
OK
ID=...
DESC=...
TYPE=...
ACTIVE=...
ADDR=...
OFFC=...
OFFS=hex,hex,...
CUR=...
VALUE=<truncated 80 chars>
HASSCRIPT=...
SCRIPTLEN=...
PARENT=...
```

If missing ID: `ERROR: NOT_FOUND: id`

### `alResolve <id>`

**Thread:** `sync_call`

Live check (touch Value so readability is meaningful per celua notes):

```text
OK ID=... CUR=... READABLE=0|1 ACTIVE=0|1 VALUE=<trunc> ADDR=<expr>
```

## Implementation notes

- Resolve memrec via `getMemoryRecordByID` inside sync.
- Parent: `mr.Parent` and `.ID` if non-nil.
- Offsets: `mr.Offset[i]` for `i=0..OffsetCount-1` (verify 0-based in CE Lua).
- Never throw on nil Parent/Script; use `pcall` when reading Script.

## Acceptance criteria

- [ ] `tableStatus` works with table loaded and with empty-ish list.
- [ ] `alDump` returns all entries for the real ~100-row table under MAX_RESP **or** pagination works.
- [ ] `CLASS` column populated with documented rules.
- [ ] `alGet` / `alResolve` for valid ID; `ERROR: NOT_FOUND` for bad ID.
- [ ] Server accepts `ping` after 50× `alResolve` spam.
- [ ] `help` lists new commands.

## Out of scope

- Mutations (T03)
- Script body (T04)
- Structures (T05)

## Crash / hang awareness

| Risk | Mitigation |
|------|------------|
| Giant dump | No script bodies; pagination |
| Value read on bad address | pcall; still return CUR |
| Description with tabs/newlines | scrub() |

## Files

- `ce_server.lua`
- Optionally note wire format in `docs/TABLE-MIGRATE.md` stub comment (full doc T08)

## Manual test

```bash
python client.py --timeout 60 --cmd "tableStatus"
python client.py --timeout 60 --cmd "alDump"
python client.py --timeout 60 --cmd "alGet 12"
python client.py --timeout 60 --cmd "alResolve 12"
```

## Agent-facing contract

Downstream skill (T09) will treat `alDump` TSV as stable. **Do not rename columns** after T09 without versioning (`alDump2` or `tableStatus` schema version field).
