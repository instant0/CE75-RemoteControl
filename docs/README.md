# Documentation

| Path | What it is |
|------|------------|
| [TABLE-MIGRATE.md](TABLE-MIGRATE.md) | How to rebind a loaded CE table over the remote |
| [NONGOALS-AND-HAZARDS.md](NONGOALS-AND-HAZARDS.md) | What we will not build + crash/hang catalogue |
| [CE75-INTEGRATION.md](CE75-INTEGRATION.md) | CE75 helpers vs raw al/st |
| [BREAKPOINT_STRATEGY.md](BREAKPOINT_STRATEGY.md) | Debugger / BP design notes |
| [UE-Memory-Patterns.md](UE-Memory-Patterns.md) | UE memory patterns |
| [CE-GROUP-SCAN.md](CE-GROUP-SCAN.md) | CE Grouped scan language (source-verified) + remote `GroupScan` + DL2 Glide example |
| [game/DyingLight2/](game/DyingLight2/) | **Extracted** DL2 knowledge (offsets, catalogs, scraps) |

## Rules

- **`docs/`** = documentation and game knowledge  
- **`skills/`** = reusable agent skills (how to operate CE remote), not research dumps  
- **Do not** commit full `.CT` files, host script piles, or temporary dumps — extract facts into `docs/game/<Title>/`  
- Completed migration **task** writeups (T00–T11) are obsolete once the feature works; they are not kept here  

Skills live under `skills/` (e.g. `ce-table-migrate`, `ce-aob-scan`, `ce-remote-scanning`).
