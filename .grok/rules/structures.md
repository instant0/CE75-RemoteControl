# Structure files (by-name / CT)

## DO
- One file per RTTI / logical type
- Keep named offset text until verified
- Merge named claims from dups into canonical, then delete dup
- Name-only pad dumps → inventory line only, delete file
- FPV map: keep current only (`FloatPlayerVariable_20260801`)

## DON'T
- Keep `Type 2` / `1.15.2` dups after merge
- Auto-merge conflicting labels (list both as unverified)
- Treat catalog map as full object layout
