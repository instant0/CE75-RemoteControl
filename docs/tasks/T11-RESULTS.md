# T11 results — QoL hardening (partial)

| Field | Value |
|-------|--------|
| **Status** | PARTIAL — high-value / low-risk items shipped as **v1.8** |
| **Server** | `ce-server v1.8 (CE 7.5 qol)` |

## Decision rule used

Ship features that clearly help agents **unless** implementation risk could brick the pipe/server or invite mass data wipe. Do **not** require a failed port first for safe QoL.

## Shipped

| ID | Feature | Notes |
|----|---------|--------|
| **T11a** | `alApply` | One `sync_call`; `stop=1` default; hex or `;;` ops; max 100 ops |
| **T11b** | Safer enable | `alSetActive id 1` runs **aaCheck** for AA rows; `nocheck` to skip |
| **T11d** | Pagination | Already in T02/T05 (`alDump`/`stGet` offsets) — no change |
| **T11e** | `alAudit [n]` | Ring buffer of last 64 verb + short result |
| **T11f** | `symGet` / `symSet` | Thin symbol resolve/register |
| **T11g** | `runScriptSafe` | Optional filter; **raw `runScript` unchanged** |

## Deferred (higher risk / situational)

| ID | Feature | Why deferred |
|----|---------|--------------|
| **T11c** | StructureFrm `sf*` | Open windows only; VCL/UI risk; definitions already via `st*` |

## Client

`CERemote.al_apply`, `al_audit`, `sym_get`/`sym_set`, `al_set_active(..., nocheck=)`, `run_script_safe`.

## Verify after CE restart

```bash
python3 client.py --host $H --port $P --timeout 60 --cmd "getVersion"
# expect v1.8
python3 client.py --host $H --port $P --cmd "alAudit 5"
```
