# Documentation

**Product entry:** [../README.md](../README.md) (quick start, command table, scope).  
**Canonical hazards / non-goals:** [NONGOALS-AND-HAZARDS.md](NONGOALS-AND-HAZARDS.md).  
**Server version history:** [CHANGELOG.md](CHANGELOG.md).

## Application (CE remote)

| Path | What it is |
|------|------------|
| [TABLE-MIGRATE.md](TABLE-MIGRATE.md) | Rebind a loaded CE table over the remote (`al*` / `st*`) |
| [CE-TABLE-OFFLINE-EDIT.md](CE-TABLE-OFFLINE-EDIT.md) | Offline `.CT` XML edits: AA `{…}` comments, ID surgery, validation |
| [AOB-CODE-DRIFT.md](AOB-CODE-DRIFT.md) | Code drift classes (reg/ModRM, RIP-global, …) for relocating AOBs |
| [NONGOALS-AND-HAZARDS.md](NONGOALS-AND-HAZARDS.md) | What we will not build + crash/hang catalogue |
| [CE-GROUP-SCAN.md](CE-GROUP-SCAN.md) | CE Grouped scan language + remote `GroupScan` (≥ v1.8.3) |
| [BREAKPOINT_STRATEGY.md](BREAKPOINT_STRATEGY.md) | Why remote BP push is not shipped |
| [CHANGELOG.md](CHANGELOG.md) | `ce_server` / protocol version notes |
| [CE75-INTEGRATION.md](CE75-INTEGRATION.md) | **UE / Gothic 1 Remake + CE75** helpers (not DL2) |
| [UE-Memory-Patterns.md](UE-Memory-Patterns.md) | **UE5** memory patterns (G1R-based; not DL2) |

Historical root design (debugger options, source citations): [../SOLUTION.md](../SOLUTION.md) — **not** the product contract.

## Game knowledge

| Path | What it is |
|------|------------|
| [game/DyingLight2/INDEX.md](game/DyingLight2/INDEX.md) | **DL2 start here** — status matrix + topics |
| [game/DyingLight2/](game/DyingLight2/) | Extracted DL2 offsets, catalogs, scraps |

No other `docs/game/<Title>/` trees yet. Do not apply `ue-*` skills to DL2 by default.

## Rules

- **`docs/`** = documentation and game knowledge  
- **`skills/`** = reusable agent skills (how to operate CE remote), not research dumps  
- **Do not** commit full `.CT` files, host script piles, or temporary dumps — extract facts into `docs/game/<Title>/`  
- Gitignored `helper/` and `logs/` are local only; promote distilled facts into docs  
- Completed one-off migration task writeups are obsolete once the feature works; keep lasting risks in NONGOALS  

Skills live under `skills/` (e.g. `ce-table-migrate`, `ce-aob-scan`, `ce-remote-scanning`, `dl2-table-work` for DL2 navigation only).
