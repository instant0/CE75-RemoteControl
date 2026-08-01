# T11 — Optional hardening (v1.1)

| Field | Value |
|-------|--------|
| **ID** | T11 |
| **Status** | TODO |
| **Phase** | 4 — Optional |
| **Parent** | T02–T06 baseline complete |
| **Children** | — |
| **Depends on** | T02–T06, preferably T09 real-world trial |
| **Blocks** | None |
| **Priority** | Do **after** first real N→N+1 attempt exposes pain |

## Goal

Add quality-of-life and safety features that are **not** required to start migrating tables, but reduce RTT, mistakes, and UI friction after v1 is in use.

## Candidate work items (each can be a mini-PR)

### T11a — `alApply` batch

**Problem:** 100 sequential TCP connections for offset fixes.

**Design:**

```text
alApply
<base64 or line-oriented ops>
END
```

Or single command with `;`-separated ops and strict size cap.

Each sub-op is existing alSet*; all inside **one** `sync_call` / one synchronize tick if possible.

**Risk:** One bad op mid-batch — define stop-vs-continue policy (`stopOnError=1` default).

### T11b — Stronger `aaCheck` + enable policy

- Return CE error string on failed Active.
- Optional `alSetActive <id> 1 nocheck=0` forcing aaCheck first server-side.

### T11c — StructureFrm helpers

```text
sfList
sfSetBase <formIndex> <colIndex> <addrText>
sfSetStruct <formIndex> <structName>
sfRefresh <formIndex>
```

**Thread:** sync.  
**Note:** Only affects **open** windows; definitions remain `st*`.

### T11d — Response pagination standard

If not done in T02/T05:

```text
alDump offset= limit=
stGet name= elemOffset= elemLimit=
```

### T11e — Audit log (optional)

Append-only in `_G` ring buffer:

```text
alAudit [n]
```

Lines: timestamp, cmd, id, result code.  
Helps debug agent runs; not a substitute for user save.

### T11f — `symGet` / `symSet`

Thin wrappers over `getAddressSafe` / `registerSymbol` for scripts that publish bases.

```text
symGet <name>
symSet <name> <addrHexOrExpr> [donotsave=0|1]
```

### T11g — Explicit refuse list in `runScript`

Before `loadstring`, reject source containing `enumMemoryRegions`, `createMemScan`, `varscan_` if easy (string match). **Optional** — can break legit advanced users; gate behind `runScriptSafe` vs raw `runScript`.

## Acceptance criteria (per sub-item)

- [ ] Documented in TABLE-MIGRATE.md when shipped.
- [ ] help updated.
- [ ] No regression on ping / alDump.
- [ ] Still no required agent saveTable.

## Out of scope for T11

- Full breakpoint polling system (separate project; see `BREAKPOINT_STRATEGY.md`)
- Offline CT XML rewriter
- MemScan productization from background thread

## Won’t work even in v1.1

| Area | Reason |
|------|--------|
| Arbitrary AA semantic rewrite | AI/heuristic limit |
| BP-driven discovery without new debug protocol | Architecture |
| Crash-proof modal AA errors | CE UI |

## Files

- `ce_server.lua`, `client.py`, `docs/TABLE-MIGRATE.md`, skill touch-up

## Recommendation

Ship T00–T09 first. Open T11 sub-items only from **pain notes** after one real table port.
