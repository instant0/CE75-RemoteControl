# Docs first (before any memory dig)

**User asks for X → check existing docs → use structures/symbols as anchors → only then live reads.**  
**Never** open with a global / multi-GB process scan for a guess.

## DO
- Read `docs/game/`, `private/*/structures/` (graph, by-name, FIND-*), host notes, cheats — **first**
- State what is already known (path, offset, gap) before relay work
- Navigate from symbols/structures (DI → container → hub → item)
- Load skill **`docs-first`** on find/map/dig/inventory/money/token/HP tasks
- **AOB when it fits** (code fingerprints, gamedll/engine, rare patterns) — **after** docs/anchors, not as default first move

## DON'T
- Use AOB as **first** strategy every time (sometimes right, **not every time**, **not first**)
- Full-process AOB of common small ints when docs/graph should carry the dig
- Ignore host notes / by-name that already name the field (e.g. `InventoryItem+0x10`)
- Leave the known object graph mid-task for a random heap trawl
