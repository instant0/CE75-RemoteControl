# Dying Light 2

## DO
- Offsets/proofs: `docs/game/DyingLight2/` (not skills)
- PlayerVariables: `PlayerState+0xBA8` → host; catalog = host+8; symbol `PlayerVariables`
- Float rows: `PlayerVariables+<map hex>`; map = `FloatPlayerVariable_20260801`
- Twin `+4` only if live test needs it — not mass +4
- Structures: one per RTTI name; slim named fields only
- RTTI name: `getRTTIClassName(object)`
- CE source: `/mnt/y/Lazarus/Projects/cheat-engine-7.5/Cheat Engine`

## DON'T
- Use UE skills (GEngine) as default DL2 path
- GroupScan-first for PlayerVariables
- Trust old pad dissects / version dups as truth
- `playerStat` dual-register
- Report live HP/cash found until base proved this attach
- Pad-flood CE Structures back into CT
- Scan outside **gamedll / engine** (see `scan-scope.md`)
