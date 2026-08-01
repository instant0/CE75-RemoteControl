# T04 results — AA scripts + Active

| Field | Value |
|-------|--------|
| **Status** | DONE (code landed; restart CE to load **v1.4**) |
| **Server version** | `ce-server v1.4 (CE 7.5 al-script)` |
| **File** | `ce_server.lua` |

## Commands shipped

| Command | Purpose |
|---------|---------|
| `alGetScript <id> [off] [len]` | Script slice as hex; default off=0 len=16384; len cap 32000 |
| `alSetScriptBegin <id> <totalLen>` | Start staging (max 262144 bytes); requires AA |
| `alSetScriptChunk <id> <off> <hex>` | Sequential only (`off == received`) |
| `alSetScriptCommit <id>` | Apply `mr.Script = body`; clear stage |
| `alSetScriptAbort <id>` | Drop stage |
| `aaCheck <id>` | `autoAssembleCheck(script, true, false)` |
| `alSetActive <id> 0\|1` | Enable/disable (may inject / dialog risk) |
| `alDisableSoft <id>` | `disableWithoutExecute` when available |

### Wire examples

```text
OK ID=78 TOTAL=1203 OFFSET=0 LENGTH=1203 DATA=7b246c75617d...
OK ID=78 TOTAL=1203
OK ID=78 RECEIVED=512 TOTAL=1203
OK ID=78 SCRIPTLEN=1203
OK ID=78
OK ID=78 ACTIVE=0
ERROR: NOT_AA: 90
ERROR: NO_STAGE: begin first
ERROR: CHUNK_OFFSET: expected=0 got=10
ERROR: AACHECK: ...
ERROR: SET_ACTIVE: enable failed ...
```

### Safety notes (agents)

1. Prefer **`aaCheck` before `alSetActive 1`**.
2. Client timeout **≥ 120s** for enable.
3. Modal AA errors can **deadlock** `synchronize` — user must dismiss dialogs.
4. Do **not** enable many inject scripts at once.
5. `setScript` only works on existing AA rows (`ERROR: NOT_AA` otherwise).
6. Staging is **sequential**; abort/restart on failure.
7. Server log prints command verb only — not script bodies.

## Round-trip recipe (agent)

```text
alGetScript id 0 16384  → decode DATA hex → full text (loop if TOTAL > LENGTH)
# edit AOB pattern in text
alSetScriptBegin id #text
for each 8k chunk: alSetScriptChunk id offset hex(chunk)
alSetScriptCommit id
aaCheck id
# only if intentional:
alSetActive id 1
alResolve dependentId
```

## Not included

- Creating brand-new AA memrecs without script object
- Breakpoint-driven scripts
- Automatic AOB rewrite logic

## Verify after CE restart

```bash
H=192.168.176.1; P=8000
python3 client.py --host $H --port $P --timeout 120 --cmd "getVersion"
# expect: ce-server v1.4 (CE 7.5 al-script)

python3 client.py --host $H --port $P --timeout 120 --cmd "alGetScript 78 0 200"
python3 client.py --host $H --port $P --timeout 120 --cmd "aaCheck 78"
# Do NOT mass-enable inject scripts in smoke tests
python3 client.py --host $H --port $P --timeout 120 --cmd "alSetActive 78 0"
python3 client.py --host $H --port $P --timeout 60 --cmd "alGetScript 90"
# expect NOT_AA for pure value row
python3 client.py --host $H --port $P --cmd "ping"
```

## Next

**T05** — structure inventory (`stDump` / `stGet` / `stFind`)
