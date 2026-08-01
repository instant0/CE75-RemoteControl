# Offline .CT edit

## DO
- Backup every write: `*.CT.bak-before-<reason>-YYYYMMDD-HHMMSS`
- Escape AssemblerScript: `<` `>` `&` → `&lt;` `&gt;` `&amp;`
- Surgical edit only (one entry / one structure block)
- **Structures + AA scripts: edit the `.CT` file on disk** (then user reloads)
- `xmllint --noout file.CT` (or ET.parse) before done
- Preserve CRLF if file has CRLF
- Tell user to reload CT in CE
- Name the backup path in the reply

## DON'T
- **Live `st*` / `alSetScript` / pipe structure mutations to “build” CT content** (crashes relay/CE until server is solid)
- Raw `<>&` in script text
- Rewrite/pretty-print whole multi-MB CT
- Bulk substring-filter scripts (can delete `playerState` when targeting `playerStat`)
- Dual `registerSymbol` aliases for same address
- Unregister symbols this script did not register
- Skip backup because “small change” or “already backed up”
