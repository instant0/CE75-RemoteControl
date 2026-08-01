# T03 — Address list mutation: description, address, offsets, type

| Field | Value |
|-------|--------|
| **ID** | T03 |
| **Status** | DONE (see T03-RESULTS.md) |
| **Phase** | 1 — Address list write path |
| **Parent** | T02 |
| **Children** | T04 (enable path builds on sets) |
| **Depends on** | T01, T02 |
| **Blocks** | T04 (partially), T09 pointer rebind steps |

## Goal

Allow the agent to **correct** loaded memrecs for a new game version: interpretable address expressions, pointer offset chains, descriptions, and value types — without enabling AA scripts yet.

## Context

- Version port: many rows are `baseSymbol` + offsets; bases move; mid-chain offsets may drift.
- CE `memoryrecord_setAddress` (`LuaMemoryRecord.pas`):
  - Arg1: number → hex string, or string expression.
  - Sets `interpretableaddress`, `ReinterpretAddress`, **`offsetCount := 0`**, then optional arg2 table restores offsets (max **512**).
- Therefore **`alSetAddress` must re-apply offsets** when only the base expression changes (read-modify-write).

## Commands to implement

### `alSetDesc <id> <text...>`

- Rest of command line after id = description (allow spaces).
- Scrub or allow limited punctuation; reject empty id.
- Response: `OK ID=... DESC=...`

### `alSetAddress <id> <addrExpr>`

- `addrExpr` may be `GEngine`, `module+1A2B`, raw hex, etc. (no spaces, or use remainder of line).
- **Preserve existing offsets:** read OffsetCount/Offset[], then `setAddress(expr, offsetTable)` if API requires table; else set Address then restore Offset[].
- Response: `OK ID=... ADDR=... OFFC=... CUR=...`

### `alSetOffsets <id> <hexlist>`

- `hexlist` e.g. `10,2A0,8` or `0x10+0x2A0+0x8` — pick **one** format and document it. Recommended: comma-separated hex without `0x`: `10,2A0,8`.
- Empty list → `OFFC=0` (non-pointer).
- Cap count ≤ 512.
- Preserve base Address expression.
- Response: `OK ID=... OFFC=... OFFS=... CUR=...`

### `alSetType <id> <typeInt>`

- Sets `mr.Type` / `VarType` to integer enum.
- Document common values in help comment (from CE: vtByte=0 … vtAutoAssembler — verify on T00).
- Response: `OK ID=... TYPE=...`
- **Do not** use this to invent AA scripts (script ptr may be nil) — T04 handles scripts.

### Optional (nice): `alCreate`

Defer if time-boxed. If implemented:

```text
alCreate DESC=... ADDR=... TYPE=... [PARENT=id]
```

Return new `ID=`.

## Encoding / parsing

- Prefer fixed tokens; descriptions with spaces: `alSetDesc <id> <rest of line>`.
- Addresses: no tabs; scrub newlines from expr.

## Acceptance criteria

- [ ] Change description visible in CE UI after command.
- [ ] Change address expression; offsets unchanged when using `alSetAddress`.
- [ ] `alSetOffsets` updates chain; `alResolve` reflects new CurrentAddress when process attached and base valid.
- [ ] Invalid id → `ERROR: NOT_FOUND`.
- [ ] Too many offsets → `ERROR: TOO_MANY_OFFSETS`.
- [ ] All via `sync_call`; ping stable after 20 mutations.

## Out of scope

- Script body replace (T04)
- Active/enable (T04)
- Delete memrec (optional later)
- saveTable

## Crash / hang awareness

| Risk | Mitigation |
|------|------------|
| Forgetting offset re-apply | Unit test preserve OFFC |
| Bad type int | pcall; return ERROR |
| Main-thread only | sync_call |

## Files

- `ce_server.lua`
- Update `help` string

## Manual test

```bash
python client.py --cmd "alGet <id>"
python client.py --cmd "alSetDesc <id> Test rename"
python client.py --cmd "alSetAddress <id> GEngine"
python client.py --cmd "alSetOffsets <id> 30,0,0"   # example only
python client.py --cmd "alResolve <id>"
```

## Wire contract for agents

Pointer rebind sequence:

1. `alDump` → find POINTER rows  
2. Fix discovery/symbols (T04 / AOB)  
3. `alSetAddress` / `alSetOffsets`  
4. `alResolve` until READABLE=1 and VALUE sensible  
