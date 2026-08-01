# T02 results — address list inventory

| Field | Value |
|-------|--------|
| **Status** | DONE (code landed; reload `ce_server.lua` to use) |
| **Server version** | `ce-server v1.2 (CE 7.5 al-inventory)` |
| **File** | `ce_server.lua` |

## Commands shipped

| Command | Response |
|---------|----------|
| `tableStatus` | (T01) process / alCount / stCount |
| `alDump [offset] [limit]` | TSV metadata; default `0 500`; limit cap 2000 |
| `alGet <id>` | Multi-line detail (no full script body) |
| `alResolve <id>` | Live CUR / READABLE / VALUE sample |

### `alDump` columns (stable for agents)

```text
COUNT=n OFFSET=o LIMIT=l
ID  IDX  PID  DESC  TYPE  ACTIVE  ADDR  OFFC  OFFS  CUR  HASSCRIPT  SCRIPTLEN  CLASS
```

Tab-separated data rows after the header line.

### `CLASS` heuristic (includes T00 EXPR)

| CLASS | Rule |
|-------|------|
| `GROUP` | IsGroupHeader / IsAddressGroupHeader |
| `AA` | HASSCRIPT or Type **11** or Type **8** |
| `POINTER` | OffsetCount &gt; 0 |
| `EXPR` | Address has `+` or `[` (symbol/expression form) |
| `STATIC` | Non-empty address otherwise |
| `OTHER` | Empty / residual |

### `alGet` keys

`OK`, `ID`, `DESC`, `TYPE`, `ACTIVE`, `ADDR`, `OFFC`, `OFFS`, `CUR`, `VALUE` (≤80), `HASSCRIPT`, `SCRIPTLEN`, `PARENT`, `CLASS`, `GROUP`

Missing id → `ERROR: NOT_FOUND: <id>`

### `alResolve`

```text
OK ID=... CUR=... READABLE=0|1 ACTIVE=0|1 VALUE=... ADDR=...
```

Touches `Value` before `IsReadable` (celua note).

## Not included

- Script body (T04)
- Mutations (T03)
- Structures (T05)

## Verify after CE reload

```bash
H=192.168.176.1; P=8000
python3 client.py --host $H --port $P --timeout 60 --cmd "getVersion"
# expect: ce-server v1.2 (CE 7.5 al-inventory)

python3 client.py --host $H --port $P --timeout 60 --cmd "alDump"
python3 client.py --host $H --port $P --timeout 60 --cmd "alDump 0 20"
python3 client.py --host $H --port $P --timeout 60 --cmd "alGet 78"
python3 client.py --host $H --port $P --timeout 60 --cmd "alResolve 90"
python3 client.py --host $H --port $P --timeout 60 --cmd "alGet 999999"
# expect NOT_FOUND
python3 client.py --host $H --port $P --timeout 30 --cmd "ping"
```

On DL2 table expect: COUNT≈93, CLASS mix of AA / EXPR / GROUP, ID 78 → AA with SCRIPTLEN≈1203.

## Next

**T03** — `alSetDesc`, `alSetAddress`, `alSetOffsets`, `alSetType`
