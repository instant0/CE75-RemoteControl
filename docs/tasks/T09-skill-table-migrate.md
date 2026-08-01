# T09 — Agent skill: `ce-table-migrate`

| Field | Value |
|-------|--------|
| **ID** | T09 |
| **Status** | DONE |
| **Phase** | 3 — Agent surface |
| **Parent** | T07, T08 (helpers + docs) |
| **Children** | — |
| **Depends on** | T02–T07; T08 for links |
| **Blocks** | Agents following a standard playbook |

## Goal

Add a Grok/agent skill that teaches how to **port a loaded CE table to a new game version** using the remote commands—without crashing the server or corrupting dissect lists.

## Context

- Skills live under `remote/skills/<name>/SKILL.md` (and may be copied to `~/.agents/skills/`).
- Existing skills: `ce-remote-scanning`, `ue-character-finding`, `ue-inventory-hacking`, `ue-stats-attributes`.
- This skill is **orchestration + safety**, not UE-specific layout science (link those skills for finding bases).

## Deliverable

### Create `skills/ce-table-migrate/SKILL.md`

Front matter:

```yaml
---
name: ce-table-migrate
description: Port a loaded Cheat Engine address list and dissect structures to a new game version via the remote CE server (al*/st* commands), including crash avoidance and dependency-ordered rebind.
---
```

### Required sections

1. **When to use** — new game build, old CT loaded, remote up.  
2. **Preconditions checklist** — attach, load table, ping, timeout 120, process name matches.  
3. **Connection snippet** — `CERemote`, `table_status()`, `al_dump()`.  
4. **Inventory** — parse CLASS column; build tiers:
   - Tier A: AA / HASSCRIPT  
   - Tier B: POINTER  
   - Tier C: STATIC  
   - Tier D: GROUP (skip values)  
5. **Tier A procedure** — get script, extract AOB heuristics, native `AOBScan`, set script chunks, `aaCheck`, `alSetActive` one-by-one, resolve dependents.  
6. **Tier B procedure** — `alResolve`, fix address/offsets, verify VALUE.  
7. **Structures** — `stDump`/`stGet`; validate with live base; `stClone` vs in-place upsert rules.  
8. **Dissect address clarification** — definition vs form.  
9. **Banned APIs** — short table (enumMemoryRegions, bg memscan, getStructure(name), unbounded walks).  
10. **Deadlock / crash programming** — synchronize already in server; agent must not spam Active; not open modals; not dump all scripts at once.  
11. **Human handoff criteria** — multi AOB hits, BP scripts, CE75 missing, layout semantic change.  
12. **Out of scope** — agent saveTable; full offline CT rewrite; perfect AA intelligence.  
13. **Command cheat sheet** — one-liner table linking to TABLE-MIGRATE.md.

### Optional

- `skills/ce-table-migrate/examples.md` with fictional dump→fix narrative.
- Register in root `README.md` Agent Skills table (coordinate with T08).

## Acceptance criteria

- [x] Skill file exists with description usable for skill discovery.
- [x] Dependency order AA → pointers → structs is explicit.
- [x] Crash-avoidance section present.
- [x] Won’t-work / handoff section present.
- [x] README skills table lists `ce-table-migrate` (if T08 didn’t already).

## Out of scope

- Implementing server bugs fixed here
- Automatic AOB extraction perfection

## Files

- `skills/ce-table-migrate/SKILL.md`
- `README.md` (skills table row)
- Optionally symlink/copy note for `~/.agents/skills` (user environment; don’t assume)

## Test

Manual: agent (or human) follows skill against staging table using client helpers; no server crash over full `alDump` + one script read + one stGet.
