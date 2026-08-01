# Cheat Engine tables — offline `.CT` editing

How agents (and humans) safely edit **Cheat Engine cheat table XML** (`.CT`) on disk when not using the live remote `al*` / `st*` path.

**Preferred path remains live rebind** (`docs/TABLE-MIGRATE.md` + `skills/ce-table-migrate`): load the table in CE, mutate via remote, **user File → Save**.  
Use offline `.CT` edits when the user asks for it, CE is offline, or you are preparing a file for them to reload.

**Product note:** generating a *brand-new* full trainer table from scratch is still a non-goal. Surgical offline edits of an existing `.CT` are fine if validated.

---

## MANDATORY — offline `.CT` edits (do not skip)

`.CT` files are **XML**. CE will refuse to load a broken table. Agents have corrupted tables by ignoring this.

### AssemblerScript is XML text, not freeform

Content of `<AssemblerScript>…</AssemblerScript>` is **parsed as XML character data**. Any **raw** special character breaks the file:

| Character | In script must be | Example bug |
|-----------|-------------------|-------------|
| `<` | `&lt;` | Comment `<-` or `PS < 1` → **LINE N “invalid element name” / “Name starts with invalid character”** |
| `>` | `&gt;` | Arrows `->` in comments (CE often stores `-&gt;`) |
| `&` | `&amp;` | Bare `&` in text |

**Wrong advice (do not follow):** “CE allows raw `<` in script comments.” It does **not** in the XML file. If you see raw `<` in an old file, do not add more; match **escaped** style when writing.

**Before writing a script into a `.CT`:**

1. Escape the whole script body for XML (`&` → `&amp;`, then `<` → `&lt;`, `>` → `&gt;`), **or** ensure the source never contains raw `<>&`.
2. Prefer plain words in `{ header }` comments (`to` / `from`) so a missed escape is less lethal.
3. **Minimal replace:** only the one `<AssemblerScript>…</AssemblerScript>` for that entry ID. Never rewrite the whole multi‑MB table as a pretty-print.
4. **Validate before telling the user it is done:**
   ```bash
   xmllint --noout /path/to/file.CT
   # or: python -c "import xml.etree.ElementTree as ET; ET.parse(path)"
   ```
   Non‑zero / exception = **do not ship**; fix first.
5. **Backup before every write** (not only the first of a session). Each offline edit of the live TEST (or REAL) `.CT` must start with a full-file copy:

   ```bash
   # Pattern: <same-name>.CT.bak-before-<short-reason>-YYYYMMDD-HHMMSS
   cp -a "/mnt/r/DyingLIght2_ins-CE74-v2026-08-01-REAL-TEST.CT" \
     "/mnt/r/DyingLIght2_ins-CE74-v2026-08-01-REAL-TEST.CT.bak-before-<reason>-$(date +%Y%m%d-%H%M%S)"
   ```

   - One backup **per edit** (script change, address remap, Structures clear/regen, description tweak — anything that mutates the file).
   - Do **not** skip because “we already backed up earlier” or “the change is small.”
   - Reason slug should name the change (`ps-symbol`, `pv-addr-fix`, `structures-clear`, `playerstate-expand`, …).
   - Only after `cp` succeeds: write, then validate (`xmllint` / parse).

### Other non‑negotiables

| Rule | Why |
|------|-----|
| Preserve CRLF if the file uses CRLF | Some CE builds are picky; match the file |
| One symbol per address; no dual `registerSymbol` aliases | User requirement; avoids dead names |
| Unregister only symbols **this script** registers | No “cleanup” of unrelated names |
| Do not bulk-filter script lines by substring | e.g. stripping `playerStat` must not delete `playerState` |
| User reloads CT in CE after disk edit | In-memory table is not the file |
| Backup before **every** CT write | Rollback; intermediate states are not recoverable from git alone |

### Checklist (every offline CT edit)

```text
[ ] Backup .CT → .CT.bak-before-<reason>-YYYYMMDD-HHMMSS (this edit, not session-first only)
[ ] Edit only the requested region (AssemblerScript / Address / Structures / …)
[ ] No raw < > & in AssemblerScript text (escaped or avoided)
[ ] xmllint / ET.parse succeeds
[ ] ENABLE/DISABLE still balanced; symbols registered match unregisters (if script edit)
[ ] Tell user to reload CT if CE had it open
[ ] Name the backup path in the reply so the user can restore
```

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
  <UserdefinedSymbols/>
  <Structures StructVersion="2">
    <!-- dissect definitions — see § Structures / dissect XML below -->
  </Structures>
  <!-- DisassemblerComments, CheatCodes, … -->
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
| **`Structures`** | Global **dissect definitions** (Memory View structure list). Often **most of the file size** on large trainers. |

Tables can be **large** (multi‑MB with big structure dumps). Prefer ID-targeted edits; avoid whole-file regexes that re-parse every script unless needed.

**Do not commit** full `.CT` files to this repo. Paths like `/mnt/r/*.CT` are host-local.

---

## Structures / dissect XML (CE 7.5) — do not re-derive

**CE source (when you must verify a change):**  
`/mnt/y/Lazarus/Projects/cheat-engine-7.5/Cheat Engine/StructuresFrm2.pas`  
— `TDissectedStruct.WriteToXMLNode` / `createFromXMLNode`, `TStructelement` load/save, RLE.  
Also mentioned in [CE-GROUP-SCAN.md](CE-GROUP-SCAN.md) / [NONGOALS-AND-HAZARDS.md](NONGOALS-AND-HAZARDS.md).

**Agents should use this section first.** Only open CE source if CE version behavior differs or a field is missing here.

### Where they live

```text
CheatTable
  └── Structures  StructVersion="2"
        ├── Structure Name="…"   ← top-level global dissect (one list entry in CE)
        │     └── Elements
        │           ├── Element … />                    self-closing
        │           └── Element …>                      open
        │                 └── Structure Name="…"        ← nested / autocreated child layout
        │                       └── Elements …
        └── Structure Name="…"
```

- Parent tag is **`<Structures StructVersion="2">`** (plural), not a free-floating pile with no wrapper.  
- Top-level list members are **direct children** of that node. Nested `<Structure>` under an `<Element>` are **child layouts** (pointer targets / autocreate), not separate global list entries.  
- On big DL2 tables, **Structures ≈ most of the MB** (example: ~11.1 / ~11.5 MB). Address list is comparatively small.

### Attribute model (not child tags)

**Wrong** (common agent mistake):

```xml
<Structure>
  <Name>FloatPlayerVariable 1.90</Name>
  <Element>
    <Offset>8</Offset>
    <Description>AgressionPerHit</Description>
  </Element>
</Structure>
```

**Actual CE 7.5 shape:**

```xml
<Structures StructVersion="2">
  <Structure Name="FloatPlayerVariable 1.90"
             AutoFill="0" AutoCreate="1" DefaultHex="0" AutoDestroy="0"
             DoNotSaveLocal="0" RLECompression="1" AutoCreateStructsize="4096">
    <Elements>
      <Element Offset="0" Vartype="Pointer" Bytesize="8" OffsetHex="00000000"
               DisplayMethod="unsigned integer" />
      <Element Offset="8" Vartype="Float" Bytesize="4" OffsetHex="00000008"
               DisplayMethod="unsigned integer" Description="AgressionPerHit" />
      <Element Offset="12" Vartype="Float" Bytesize="4" OffsetHex="0000000C"
               DisplayMethod="unsigned integer" />
      <!-- anonymous pads may use RLECount — see below -->
      <Element Offset="16" Vartype="4 Bytes" Bytesize="4" OffsetHex="00000010"
               DisplayMethod="unsigned integer" RLECount="2" />
      <Element Offset="24" Vartype="Pointer" Bytesize="8" OffsetHex="00000018"
               DisplayMethod="unsigned integer">
        <Structure Name="Autocreated from 7FF9…" …>
          <Elements>…</Elements>
        </Structure>
      </Element>
    </Elements>
  </Structure>
</Structures>
```

| Attribute / node | Meaning |
|------------------|---------|
| `Structure/@Name` | Dissect list name (global or nested). **Identity for keep/retire.** |
| `RLECompression` | `"1"` / `"0"` — enable run-length compression on save |
| `AutoCreate` / `AutoCreateStructsize` / `AutoDestroy` / `AutoFill` / `DefaultHex` | CE dissect UI / pointer-follow options |
| `DoNotSaveLocal` | Local-only child; interacts with save rules |
| `Elements` | Container for this structure’s fields |
| `Element/@Offset` | Byte offset **decimal** in the struct |
| `Element/@OffsetHex` | Same offset as hex string (presentation; keep consistent if you emit) |
| `Element/@Vartype` | **String** type name as CE writes it: `Pointer`, `Float`, `Byte`, `4 Bytes`, `String`, `Double`, … (not only Lua `vt*` ints) |
| `Element/@Bytesize` | Size in bytes |
| `Element/@Description` | Field label (named fields). Empty/absent = anonymous pad or pointer without label |
| `Element/@DisplayMethod` | e.g. `unsigned integer` |
| `Element/@RLECount` | See RLE below |
| Nested `Structure` under `Element` | Child type for pointers (often `Autocreated from <addr>` or a global name) |

### RLE compression

When `RLECompression="1"`, CE **merges runs** of consecutive elements that share the same:

- `Bytesize`, `Name`/`Description`, `DisplayMethod`, background color  
- `VarType`  
- no child struct on either  
- **adjacent** offsets: `prev.Offset + prev.Bytesize == next.Offset`  

On write, one XML `Element` is emitted with **`RLECount = N`** (run length).  
On load, CE expands to **N** elements with offsets `base + bytesize * (j-1)`.

| Count | Meaning |
|-------|---------|
| **XML Element nodes** | Compressed rows in the file |
| **RLE-expanded** | What CE has in memory / what Memory View shows |

**Do not** treat “number of `<Element` tags” as the only size metric. A 9k-node / ~18k-expanded dissect is normal for old full FPV dumps.

### Parsing rules for tools / agents

1. Find `<Structures` … `>` then only **depth-aware** walk of top-level `<Structure Name=`.  
2. Match `</Structure>` with a **nesting depth** counter — nested autocreate structs nest `<Structure>` inside `<Element>`.  
3. Read **attributes**, not child `<Name>` / `<Offset>` tags (those are the wrong schema).  
4. Expand `RLECount` when comparing to live `stDump` / CE UI counts.  
5. **Delete / replace** only a full top-level `Structure` span (open → matching close at depth 0). Never regex-delete by name across the whole file (hits nested autocreate names).  
6. Before retiring a global structure, check whether another element **references** it as a child type / delay-loaded name (CE resolves child structs by name after load).

### Global list vs Memory View address

- Entries under `<Structures>` are **definitions** (layouts + names).  
- They are **not** automatically bound to a live base. User/agent assigns a base in Structure dissect UI, or uses address-list EXPR rows (`PlayerVariables+off`).  
- Empty global list can crash CE dissect UI — keep a seed / placeholder when wiping (see [NONGOALS-AND-HAZARDS.md](NONGOALS-AND-HAZARDS.md) / `stEnsureSeed`).

### Emitting a new dissect offline (allowed pattern)

Prefer **offline XML insert** for multi‑thousand-element maps/dissects over live `addElement` thrashing the relay.

1. Backup `.CT`.  
2. Build a top-level `<Structure Name="…">` fragment matching the attribute schema above.  
3. Insert as a **sibling** under `<Structures>` (before `</Structures>`).  
4. Use `RLECompression="1"` and emit `RLECount` for anonymous pad runs when possible.  
5. User **reloads** the file in CE (disk edit ≠ hot reload).  
6. Spot-check a few named offsets against a known live base.

### Size / inventory expectations (DL2 example)

| Kind | Typical shape |
|------|----------------|
| FPV **name map** (`FloatPlayerVariable YYYYMMDD`) | ~2–2.5k **named** elements, often all one `Vartype` (e.g. `Byte` placeholders at catalog offsets) — hundreds of KB |
| FPV **full Dissect** (1.90-style slots) | Many pointers + float pairs + pads; **MB-scale**; high RLE expansion |
| Older `PlayerVarsArray` | Earlier name map; may be incomplete vs current map |
| RTTI / autocreate dumps | Names like `PlayerState`, `…TypedFieldMeta<FloatPlayerVariable>`, `LifeHealth<…>` — useful for **type graph**, often duplicate versioned copies |

**Retire** obsolete multi‑MB FPV dissects only after a current map (+ new Dissect if needed) is present and name-diffed. Surgical block delete + backup.

### Related

- Live structure commands: [TABLE-MIGRATE.md](TABLE-MIGRATE.md) (`stDump`, `stFind`, never `getStructure("Name")`).  
- DL2 FPV workflow: [game/DyingLight2/player-vars-array.md](game/DyingLight2/player-vars-array.md).  
- Private offline plan (inventory / retire / emit): `private/DyingLight2/tools/pv-dissect/OFFLINE-STRUCTURE-PLAN.md` (host; not git).

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
4. Write UTF-8; **AssemblerScript must be XML-safe** — see **MANDATORY** above (`<` `>` `&` escaped). Run `xmllint --noout` after every script write.
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
| **Raw `<` in AssemblerScript** (e.g. `<-`) | **Breaks entire table load** — escape `&lt;` or reword; always `xmllint` after edit |
| Raw `>` / `&` in AssemblerScript | Use `&gt;` / `&amp;` (CE headers often use `-&gt;`) |
| Unclosed AA `{` comment | Brace check + active-body strip (above) |
| Nested `CheatEntry` and naive `find('</CheatEntry>')` | Parse by ID with nesting depth, or XML parser |
| Bulk version retag | Only retag verified IDs |
| Dual symbols for same address | Register **one** canonical name only |
| `playerS` / `playerStat` vs `PlayerVariables` | Use `PlayerVariables` only for catalog; no alias spam |
| Stale inject RVA in comments | Treat as history; enable must use AOB |
| Editing while CE has unsaved changes | User loses or overwrites agent edits |
| Huge structure blobs in same file | Don’t pretty-print / rewrite whole document; surgical replace |
| Regex / line filters over script source | Can delete legitimate lines (`playerState` vs `playerStat`); edit precisely |
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
