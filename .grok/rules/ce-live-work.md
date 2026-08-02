# CE live work — labels, dig order, stop thrash

**Tattoo:** Chat is not durable. Rules + docs files are. When user corrects a habit, fix the rule **in this folder** before the next dig.

## DO
- **Primary site name** = what CE shows live: `module+RVA` or full VA (e.g. `gamedll_ph_x64_rwdi.dll+CC6FA5`, `7FF…`)
- **AOB** = primary identity for cheats / retune (module-bounded, gamedll/engine only)
- **Offline PE / bare RVA** = footnote only (“same bytes offline ≈ 0x…”) — never the headline or the only label in a reply
- User hands you a live hit → use **their** module+addr/VA as the name for that site this session
- User asks “what do I need” / regs / access → **full register map first**, then conclusion
- User finds READ/WRITE/code → **write docs same turn** (`docs/game/…`, cheat card) before more probes
- Durable docs: RTTI, offsets, AOB, reg roles, cave pattern — **not** one-session heap pointers or “type this recipe”
- User says STOP / enough → stop probes; document or answer only

## DON'T
- Lead with bare offline RVA as if it were the debug target (`WRITE (0xCC6FA5)` alone)
- Re-derive “truth” from offline PE when user already gave live module+address
- Prefer ephemeral XP/object addresses in markdown as if they survive attach
- Call other hits “trash” when they hold the same live values (say specificity only)
- Half-answer regs, then dig more without the table
- Leave verified access paths only in chat
- “One more probe” after STOP, or after the fact is already in docs

## Dig order (again — non-negotiable)
1. docs / structures / symbols  
2. anchors / graph / GroupScan when layout known  
3. distinctive value work only if needed  
4. AOB last, module-bounded  

Never open with global/common-int AOB or “scan 60300” when GroupScan/docs already name the path.

## After user correction
1. Acknowledge the rule broken  
2. **Edit `.grok/rules/` or the right doc** same turn  
3. Then continue work  

No “I’ll remember” without a file change.
