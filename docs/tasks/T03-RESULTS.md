# T03 results — address list mutation

| Field | Value |
|-------|--------|
| **Status** | DONE (code landed; restart CE to load **v1.3**) |
| **Server version** | `ce-server v1.3 (CE 7.5 al-mutate)` |
| **File** | `ce_server.lua` |

## Commands shipped

| Command | Behavior |
|---------|----------|
| `alSetDesc <id> <text...>` | Set Description (rest of line; spaces OK) |
| `alSetAddress <id> <expr>` | Set interpretable address; **preserves** existing Offset[] |
| `alSetOffsets <id> <list>` | Set pointer offsets; preserve base Address |
| `alSetType <id> <typeInt>` | Set Type/VarType integer |

### Offset list format

- Preferred: comma-separated hex: `10,2A0,8`
- Also accepted: `10+2A0+8`
- Optional `0x` prefix stripped
- Empty list / omit tokens after id: clear offsets (`OFFC=0`)
- Max **512** offsets → else `ERROR: TOO_MANY_OFFSETS`

### Responses

```text
OK ID=... DESC=...
OK ID=... ADDR=... OFFC=... OFFS=... CUR=...
OK ID=... OFFC=... OFFS=... CUR=... ADDR=...
OK ID=... TYPE=...
ERROR: NOT_FOUND: <id>
ERROR: EMPTY_ADDRESS
ERROR: BAD_OFFSET: ...
ERROR: TOO_MANY_OFFSETS: n
```

### Type integers (observed / common)

| Value | Typical use |
|-------|-------------|
| 0 | Byte / notes |
| 2 | Dword-ish |
| 4 | Float (DL2 value rows) |
| 11 (or 8) | Auto Assembler — do **not** use alSetType to invent AA; use T04 scripts |

## Implementation notes

- All mutations via `sync_call` (main thread).
- `setAddress` path re-applies offset table so base-only updates do not wipe chains.
- EXPR rows (`playerStat + off`) use address string only; offsets usually stay 0.

## Not included

- Script body / Active (T04)
- alCreate / delete
- saveTable

## Verify after CE restart

Use a **disposable** row or restore after test (avoid renaming bootstrap if scripts match by description).

```bash
H=192.168.176.1; P=8000
python3 client.py --host $H --port $P --timeout 60 --cmd "getVersion"
# expect: ce-server v1.3 (CE 7.5 al-mutate)

# Safe-ish: rename a note-style GROUP row if you know a spare ID, then restore
python3 client.py --host $H --port $P --cmd "alGet 81"
python3 client.py --host $H --port $P --cmd "alSetDesc 81 TEMP T03 test note"
python3 client.py --host $H --port $P --cmd "alGet 81"
# restore original text from alGet before test

python3 client.py --host $H --port $P --cmd "alGet 90"
python3 client.py --host $H --port $P --cmd "alSetAddress 90 playerStat + 2e38"
python3 client.py --host $H --port $P --cmd "alGet 90"

python3 client.py --host $H --port $P --cmd "alSetOffsets 999999 10,20"
# NOT_FOUND

python3 client.py --host $H --port $P --cmd "ping"
```

## Next

**T04** — chunked script get/set + `alSetActive` / `aaCheck`
