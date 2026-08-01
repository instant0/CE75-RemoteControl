# Cheat Engine tables — offline `.CT` editing

How agents (and humans) safely edit **Cheat Engine cheat table XML** (`.CT`) on disk when not using the live remote `al*` / `st*` path.

**Preferred path remains live rebind** (`docs/TABLE-MIGRATE.md` + `skills/ce-table-migrate`): load the table in CE, mutate via remote, **user File → Save**.  
Use offline `.CT` edits when the user asks for it, CE is offline, or you are preparing a file for them to reload.

**Product note:** generating a *brand-new* full trainer table from scratch is still a non-goal. Surgical offline edits of an existing `.CT` are fine if validated.

---

## File shape (CE 7.x)

```xml
<?xml version="1.0" encoding="utf-8"?>
<CheatTable CheatEngineTableVersion="45">
  <CheatEntries>
    <CheatEntry>
      <ID>279</ID>
      <Description>"[Enable][1.28] …"</Description>
      <VariableType>Auto Assembler Script</VariableType>
      <AssemblerScript>…</AssemblerScript>
      <CheatEntries>   <!-- children / groups -->
        <CheatEntry>…</CheatEntry>
      </CheatEntries>
    </CheatEntry>
  </CheatEntries>
  <!-- optional: Structures, UserdefinedSymbols, Comments, … -->
</CheatTable>
```

| Piece | Role |
|-------|------|
| `ID` | Stable integer **within this table file** (not a global game ID). Prefer mutate by ID. |
| `Description` | UI label. Often wrapped in **extra quotes**: `"…text…"`. Version tags live here: `[Cheat][1.28]`, `[Enable][1.16.0]`. |
| `VariableType` | e.g. `Auto Assembler Script`, `Float`, `4 Bytes`, `Byte` |
| `Address` | Expression or static address for value rows (`PlayerVariables+2c8`, `gamedll+…`) |
| `AssemblerScript` | Full AA (and optional `{$lua}`) source for script rows |
| Nested `CheatEntries` | Tree / groups. **Do not** treat the first `</CheatEntry>` after a parent `ID` as the parent end if children exist — parse nesting or locate the specific child `ID` first |

Tables can be **large** (multi‑MB with big structure dumps). Prefer ID-targeted edits; avoid whole-file regexes that re-parse every script unless needed.

**Do not commit** full `.CT` files to this repo. Paths like `/mnt/r/*.CT` are host-local.

---

## Auto Assembler: comments and directives (critical)

CE AA has **two** comment styles and **brace directives**. Getting braces wrong **silently** turns the whole enable body into a comment — the checkbox appears to do nothing useful.

### 1. Multi-line comment: `{` … `}`

```text
{ Game   : DyingLightGame_x64_rwdi.exe
  Version: 1.28
  Date   : 2026-08-01
  Author : ins

  Free-form notes, historical RVAs, offline verification notes…
}
```

| Rule | Detail |
|------|--------|
| Open | A line/block starting with `{` that is **not** a `{$…}` directive |
| Close | Matching `}` on its own or at end of the comment block |
| **Must close before live code** | Put `}` **before** `[ENABLE]` / first real AA or `{$lua}` line |
| Nested `{`/`}` inside a comment | Avoid; simple scripts use one open at header and one open for trailing “ORIGINAL CODE” dump |
| Failure mode | Unclosed `{` → **everything after is comment**, including `aobscanmodule`, `alloc`, inject — script looks fine in XML but is inert in CE |

**Lesson learned (this project, 2026-08-01):** extending the header notes on Time Related Cheats (ID **193**) without re-closing `}` before `[ENABLE]` made the entire script a comment. Always re-balance after header edits.

Typical dual-comment layout in trainer scripts:

```text
{ header metadata and notes
}

[ENABLE]
… real code …

[DISABLE]
… restore …

{
// ORIGINAL CODE - disasm dump from some older CE session
// RVAs here are often stale; keep for human context only
}
```

### 2. Line comments: `//`

```text
//aobscanmodule(TIME,gamedll_ph_x64_rwdi.dll,…) // alternate pattern
aobscanmodule(TIME,gamedll_ph_x64_rwdi.dll,F3 0F 11 43 5C F3 0F 10 4B)
```

Safe for single lines. Prefer `//` for short annotations **inside** `[ENABLE]`/`[DISABLE]` so you never reopen `{`.

### 3. Directives: `{$lua}`, `{$asm}`, …

```text
{ header comment
}
{$lua}
if syntaxcheck then return end
-- bootstrap …
[ENABLE]
…
[DISABLE]
…
```

| Token | Meaning |
|-------|---------|
| `{$lua}` | Switch to Lua until `{$asm}` or section end (each `{$…}` form is a **paired** `{`…`}` on that token) |
| `{$asm}` | Back to assembler |
| Other `{$…}` | CE specials (see CE AA help) |

Brace **count** `{` vs `}` over the whole script is a useful sanity check, but:

- Count is **necessary, not sufficient** (wrong place for `}` still breaks).
- Prefer also checking: after stripping balanced `{…}` comment blocks (and treating same-line `{$…}` as closed), the remaining text still contains `[ENABLE]` and the real `aobscanmodule` / `registerSymbol` lines.

### Mandatory post-edit check (every AA touch)

```text
1. script.count('{') == script.count('}')
2. A '}' appears before the first [ENABLE] if the file starts with a header '{'
3. Strip balanced {…} comments → active body still has aobscan / alloc / registerSymbol as intended
4. Description version tag matches what you verified (only retag what you verified)
5. User reloads .CT in CE (or re-opens script editor) — do not assume CE hot-reloads disk
```

Python sketch:

```python
import re, html
from pathlib import Path

def aa_active_body(script: str) -> str:
    s = script
    # strip same-line {$...} first so they don't look like open comments
    s = re.sub(r'\{\$[^}]*\}', '', s)
    while True:
        n = re.sub(r'\{[^{}]*\}', '', s, count=1, flags=re.S)
        if n == s:
            break
        s = n
    return s

def check_aa(script: str) -> list[str]:
    errs = []
    if script.count('{') != script.count('}'):
        errs.append(f"brace imbalance {{={script.count('{')} }}={script.count('}')}")
    if re.match(r'\s*\{', script) and not re.search(r'\}\s*\n\s*(\[ENABLE\]|\{\$lua\})', script):
        errs.append("header '{' likely not closed before [ENABLE]/$lua}")
    body = aa_active_body(script)
    if '{' in body or '}' in body:
        errs.append("unclosed brace residue after strip")
    if '[ENABLE]' in script and 'aobscan' in script.lower() and 'aobscan' not in body.lower():
        # only if this entry is expected to AOB
        errs.append("aobscan only inside comments — script may be inert")
    return errs
```

---

## Editing by entry ID (recommended)

1. Prefer **stable `ID`**, not Description alone (descriptions change when retagging versions).
2. Locate `<ID>N</ID>` for a **leaf** entry, then take the nearest enclosing `<CheatEntry>…</CheatEntry>` that contains that ID as **its** ID (not a parent’s). For nested trees, walk from the ID line upward carefully or use an XML parser.
3. Edit only:
   - `<Description>…</Description>`
   - `<AssemblerScript>…</AssemblerScript>`
   - `<Address>…</Address>`
   - types / offsets if present  
   Leave hierarchy, hotkeys, and unrelated siblings alone unless asked.
4. Write UTF-8; keep XML well-formed (`&` → `&amp;` if you introduce bare ampersands; CE often stores scripts with raw `<` in comments — match the file’s existing escaping style).
5. **Version tags:** retag **only** entries you verified offline/live for the current game build. Do **not** bulk-replace `1.16` → `1.28` across the table.

### Description conventions (this DL2 table family)

| Pattern | Meaning |
|---------|---------|
| `[Enable][x.y] …` | Bootstrap / master enable |
| `[Cheat][x.y] …` | Feature script verified (or claimed) for that version |
| `[Cheat][YYYYMMDD] …` | Date-stamped rework without product version |
| Extra wrapping quotes | Common: `<Description>"[Cheat][1.28] …"</Description>` — preserve the inner `"` pair when rewriting |

Script header `Version:` lines are free text for humans; keep them consistent with Description when you retag.

---

## AA script anatomy (inject rows)

```text
{ optional header comment — MUST close }

[ENABLE]
aobscanmodule(NAME, module.dll, AA BB ?? CC)  // prefer unique module AOB
alloc(newmem,$1000,NAME)
…
NAME:
  jmp newmem
return:
registersymbol(NAME)   // and any helper symbols

[DISABLE]
NAME:
  db …                 // original bytes
unregistersymbol(NAME)
dealloc(newmem)

{ optional ORIGINAL CODE dump — MUST close }
```

| Practice | Why |
|----------|-----|
| Prefer `aobscanmodule` over hardcoded `module+RVA` | Survives ASLR and many recompiles |
| Keep ORIGINAL CODE as **comment only** | Old dump RVAs are often dead on current DLL |
| Record **verified** inject RVA / AOB hit in header notes | Offline lookup; still enable via AOB |
| One feature per script when possible | Easier `aaCheck` / live enable / rollback |
| `{$lua}` bootstraps | Used for PlayerVariables-style symbol registration; still needs balanced header `}` before `{$lua}` |

Lua-heavy enable (example pattern used for PlayerVariables bootstrap): header comment closed → `{$lua}` → enable logic → `[DISABLE]` unregister.

---

## Offline vs live workflow

| Situation | Prefer |
|-----------|--------|
| CE + game + remote up; rebind many rows | Live `al*` / `st*` (`TABLE-MIGRATE.md`) |
| User asked to edit the `.CT` on disk; CE offline | Offline XML edit + validation checklist |
| Prove AOB uniqueness | Offline bytes scan of `gamedll` **or** live `aobscanmodule` |
| Prove values / inject correctness | **Live** enable after world load |
| Persist work | User **File → Save** in CE **or** agent writes `.CT` then user **reloads** the file |

If the user already has the table open in CE, disk writes are **not** visible until reload (and CE may overwrite disk on save). Coordinate: either edit disk while CE closed / file not loaded, or use remote `al_set_script` on the live table.

---

## XML / tooling pitfalls

| Pitfall | Mitigation |
|---------|------------|
| Unclosed AA `{` comment | Brace check + active-body strip (above) |
| Nested `CheatEntry` and naive `find('</CheatEntry>')` | Parse by ID with nesting depth, or XML parser |
| Bulk version retag | Only retag verified IDs |
| `playerS` vs `PlayerVariables` in `Address` | Symbol must match what enable registers |
| Stale inject RVA in comments | Treat as history; enable must use AOB |
| Editing while CE has unsaved changes | User loses or overwrites agent edits |
| Huge structure blobs in same file | Don’t pretty-print / rewrite whole document; surgical replace |
| Regex over multi‑MB file | Target one ID block; set timeouts |
| Assuming Description is unique | Prefer ID; some labels can collide after edits |
| `getMemoryRecordByDescription("…")` inside scripts | If you change Description, update **every** string match in scripts that look up that label |

---

## This project: DL2 table touchpoints

| Item | Location / note |
|------|-----------------|
| Working CT (example) | `/mnt/r/DyingLIght2_ins-CE74-v2026-08-01-REAL-TEST.CT` (host; not in git) |
| gamedll for offline AOB | `/mnt/r/gamedll_ph_x64_rwdi.dll` + private lookup card |
| Private feature cards | `private/DyingLight2/cheats/` (gitignored) |
| Live rebind skill | `skills/ce-table-migrate` |
| DL2 work order | `skills/dl2-table-work` |
| AOB ranking | `skills/ce-aob-scan` |

When documenting a verified feature offline, keep **script ID**, **Description**, **AOB**, **module SHA**, and **open issues** in the private cheat card — then apply the CT edit and run the AA checklist above.

---

## Quick checklist before telling the user “table updated”

- [ ] Only intended `ID`s changed  
- [ ] AA braces balanced; header closed before `[ENABLE]` / `{$lua}`  
- [ ] Active body (comments stripped) still contains the real enable logic  
- [ ] Description version tag only where verified  
- [ ] Cross-references inside scripts (description lookups, symbol names) updated if labels/symbols changed  
- [ ] User told to **reload** `.CT` in CE if they edit on disk  
- [ ] Optional: note remaining pre-existing imbalances if you scanned the whole table  

---

## Related

- Live migrate: [TABLE-MIGRATE.md](TABLE-MIGRATE.md)  
- Hazards / non-goals: [NONGOALS-AND-HAZARDS.md](NONGOALS-AND-HAZARDS.md)  
- DL2 knowledge: [game/DyingLight2/INDEX.md](game/DyingLight2/INDEX.md)  
- Skill: `skills/ce-table-migrate/SKILL.md`  
