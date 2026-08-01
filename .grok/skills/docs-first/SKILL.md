---
name: docs-first
description: >
  Mandatory research gate before any CE memory work: read existing project docs,
  host notes, by-name structures, inventory graphs, and CT symbols/structures first;
  only then navigate from known anchors. AOB is sometimes right (code fingerprints)
  but not every time and not as the first strategy. Use when the user asks to
  find/map/dig a value, offset, item, money, token, health, player, inventory, or
  "continue" structure work — or when tempted to AOBScan / full-process scan first.
  Slash: /docs-first.
---

# Docs first — then anchors — then memory

**Tattoo:** The user asks for something → **read what we already wrote** → use **structures/symbols as anchors** → only then live work.  
**Never** open with a global / full-process multi-GB scan for a guess.

## When this skill applies

Any request that involves finding, confirming, mapping, or cheating a **live game value or object** (money, tokens, stacks, HP, PlayerDI, inventory hubs, …).

## Mandatory order (do not skip)

### 1. Existing documentation (before any relay scan)

| Priority | Where |
|---------:|--------|
| 1 | `docs/game/<Game>/` — host notes, health-money, INDEX, function-catalog |
| 2 | `private/<Game>/structures/` — `INVENTORY-GRAPH-LIVE.md`, `FIND-*.md`, `by-name/<Type>.md` |
| 3 | `private/<Game>/cheats/`, `cea/` — known paths / scripts |
| 4 | `.grok/rules/` especially `scan-scope.md`, `relay.md`, `docs-first.md` |
| 5 | CT / symbols already in table (named structures, 279 symbols) |

**Output of this step:** what is already known — path, offset, RTTI name, open gaps.  
If host notes already say e.g. `InventoryItem+0x10` = stack count, **use that**.

### 2. Anchors — navigate the map you have

| Anchor type | Examples |
|-------------|----------|
| Symbols | `PlayerDI_PH`, `PlayerState`, globals from Start cheating |
| Structures | CT `InventoryMoney`, `InventoryContainerDI`, ChildStruct edges |
| Live graph docs | DI+0x470 → container → Money/Main/Token/… |

**Stay on the graph.** Each step: `readQword` / RTTI on a **child of a known object**.

### 3. Bounded live work

- Known field → find the **object**, read the field.
- Distinctive dword/integer value scan when the value is selective enough (e.g. unique money).
- One bounded script preferred over thrash.

### 4. AOB — sometimes right, never first by default

**AOB is a valid tool** for code fingerprints, script retune, multi-byte instruction patterns, gamedll/engine module AOB — when docs/anchors do not already give the path.

| Priority | Approach |
|---------:|----------|
| 1 | Docs / host notes / by-name |
| 2 | Symbols + structure graph |
| 3 | Distinctive value scan / delta on known region |
| 4 | **AOB** (code / **gamedll·engine only** / rare multi-byte) |

**Not every time. Not first.** Do not open a dig with AOB because it feels easy.

**Still never:** full-process AOB of a common small int (100 / 101 / 1000 / typical stacks) instead of graph navigation.

### 5. Document before the next dig

New fact → write it into the right file **before** the next scan/edit (`writing.md`).

## HARD DON'Ts

| DON'T | Why |
|-------|-----|
| AOB (or global scan) as **first** move when docs/anchors exist | Wrong order |
| Full-process AOB of common small ints | Noise, thrash, idiotic |
| Treat AOB as default for every “find X” | Anchors become pointless |
| Ignore host notes that already name the field | Waste; lose trust |

## DO checklist

```
[ ] Grep/read docs + by-name + graph for the topic
[ ] State what is already known (path / field / gap)
[ ] Resolve symbol or proven global
[ ] Walk only children of known nodes
[ ] Read known fields (e.g. Item+0x10, Money+0x38)
[ ] AOB only if still needed — code/module, not common counts
[ ] Document new edges before next action
```

## Related

- `.grok/rules/scan-scope.md`, `docs-first.md`, `relay.md`, `writing.md`
- `ce-remote-scanning` — after this gate  
- `ce-aob-scan` — **code** AOB methodology when step 4 applies  
