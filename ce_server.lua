local PIPE_NAME = "UEScanRemote"
local PIPE_BUFFER = 65536
local VERSION = "ce-server v1.8.3 (CE 7.5 groupscan)"
local MAX_RESP = 48000
local MAX_OFFSETS = 512
local MAX_SCRIPT_BYTES = 262144  -- 256 KiB staging cap
local DEFAULT_SCRIPT_CHUNK = 16384
local DEFAULT_ST_ELEM_LIMIT = 500
local MAX_ST_CLEAR_ELEMS = 50000
local MAX_AL_APPLY_OPS = 100
local MAX_AUDIT = 64
-- Ring buffer of recent command verbs (T11e); not a substitute for user save
if not _G._ue_audit then
  _G._ue_audit = {}
end
-- CE 7.5 empty global structure list → dissect TreeView "list index (0) out of bounds".
-- Always keep a tiny seed (UnrealEdit75 CE75-DISSECT-CRASH.md).
local ST_PLACEHOLDER_NAME = "DO_NOT_DELETE_PLACEHOLDER"
local ST_PLACEHOLDER_LEGACY = "UE_Seed"
local VT_BYTE = 0  -- CE vtByte
-- Track structures with open beginUpdate (agent-owned; warn on double begin)
if not _G._ue_st_updating then
  _G._ue_st_updating = {}
end
-- CE 7.5: vtAutoAssembler observed as Type=11 on DL2 tables (T00); also accept 8.
local VT_AUTO_ASSEMBLER_A = 11
local VT_AUTO_ASSEMBLER_B = 8

local HEX = "0123456789ABCDEF"

-- Staging for chunked script upload (T04). Key = tostring(memrec id).
if not _G._ue_script_stage then
  _G._ue_script_stage = {}
end

local function bytes_to_hex(t)
  local parts = {}
  for i = 1, #t do
    parts[#parts + 1] = string.sub(HEX, bShr(t[i], 4) + 1, bShr(t[i], 4) + 1)
    parts[#parts + 1] = string.sub(HEX, t[i] % 16 + 1, t[i] % 16 + 1)
  end
  return table.concat(parts)
end

local function hex_to_table(s)
  s = s:gsub("%s+", "")
  if #s % 2 ~= 0 then return nil end
  local t = {}
  for i = 1, #s, 2 do
    t[#t + 1] = tonumber(s:sub(i, i + 1), 16)
  end
  return t
end

local function str_to_hex(s)
  s = tostring(s or "")
  local parts = {}
  for i = 1, #s do
    local b = string.byte(s, i)
    parts[#parts + 1] = string.sub(HEX, bShr(b, 4) + 1, bShr(b, 4) + 1)
    parts[#parts + 1] = string.sub(HEX, b % 16 + 1, b % 16 + 1)
  end
  return table.concat(parts)
end

local function hex_to_str(h)
  local t = hex_to_table(h)
  if not t then return nil end
  local chars = {}
  for i = 1, #t do
    chars[i] = string.char(t[i])
  end
  return table.concat(chars)
end

local function stage_key(id)
  return tostring(id)
end

local function stage_clear(id)
  _G._ue_script_stage[stage_key(id)] = nil
end

local function stage_get(id)
  return _G._ue_script_stage[stage_key(id)]
end

-- Main-thread: true if memrec has AA script object with text access
local function mr_is_aa_script(mr)
  local ok, scr = pcall(function() return mr.Script end)
  if not ok then return false end
  -- Empty script string still counts as AA slot if Type is AA, but setScript
  -- only works when AutoAssemblerData.script ~= nil — non-nil Script property.
  if scr ~= nil then return true end
  local vt = mr.Type
  return vt == VT_AUTO_ASSEMBLER_A or vt == VT_AUTO_ASSEMBLER_B
end

local function scrub(s)
  s = tostring(s or "")
  return (s:gsub("[\r\n\t]", " "))
end

local function fit_response(s)
  s = tostring(s or "")
  if #s > MAX_RESP then
    return "ERROR: RESPONSE_TOO_LARGE: " .. tostring(#s)
  end
  return s
end

local function trunc_str(s, n)
  s = scrub(s)
  if #s > n then
    return s:sub(1, n)
  end
  return s
end

-- Run fn on CE main thread. Returns { ok=true, data=... } or { ok=false, err=... }.
-- Table/UI/AA work MUST use this (VCL is not safe from the pipe background thread).
local function sync_call(fn)
  local packed = synchronize(function()
    local ok, result = pcall(fn)
    if not ok then
      return { ok = false, err = tostring(result) }
    end
    return { ok = true, data = result }
  end)
  if type(packed) ~= "table" then
    return { ok = false, err = "synchronize returned non-table: " .. tostring(packed) }
  end
  return packed
end

local function ok_data(packed)
  if not packed or not packed.ok then
    local err = packed and packed.err or "unknown"
    return nil, "ERROR: SYNC: " .. tostring(err)
  end
  return packed.data
end

-- Main-thread only (call inside sync_call).
local function al_find_by_id(id)
  local al = getAddressList()
  if not al then return nil, nil end
  local mr = al.getMemoryRecordByID(id)
  return al, mr
end

-- Main-thread only. NEVER pass a name string to getStructure() — index only.
local function st_find_by_name(name)
  local n = getStructureCount()
  if not n then return nil, nil end
  for i = 0, n - 1 do
    local s = getStructure(i)
    if s and s.Name == name then
      return s, i
    end
  end
  return nil, nil
end

local function st_count()
  local n = 0
  pcall(function() n = getStructureCount() or 0 end)
  return n or 0
end

local function st_is_protected_name(name)
  name = tostring(name or "")
  return name == ST_PLACEHOLDER_NAME or name == ST_PLACEHOLDER_LEGACY
end

-- Main-thread: ensure at least one global structure exists (placeholder preferred).
-- Empty DissectedStructs list crashes CE dissect UI / callbacks (list index 0).
-- force_placeholder=true: create DO_NOT_DELETE_PLACEHOLDER even if other structs exist.
-- Returns: ok (bool), status ("present"|"legacy"|"has_structures"|"created"|"error:..."), count
local function st_ensure_seed(force_placeholder)
  if st_find_by_name(ST_PLACEHOLDER_NAME) then
    return true, "present", st_count()
  end
  if st_find_by_name(ST_PLACEHOLDER_LEGACY) then
    return true, "legacy", st_count()
  end
  local n = st_count()
  -- Any structure avoids the empty-list crash. Placeholder is still best practice.
  if n > 0 and not force_placeholder then
    return true, "has_structures", n
  end
  if type(createStructure) ~= "function" then
    return false, "error:NO_CREATESTRUCTURE", 0
  end
  local ok, err = pcall(function()
    local s = createStructure(ST_PLACEHOLDER_NAME)
    if not s then error("createStructure returned nil") end
    pcall(function() s.beginUpdate() end)
    local e = s.addElement()
    if e then
      pcall(function() e.Name = "_placeholder" end)
      pcall(function() e.Offset = 0 end)
      pcall(function() e.Vartype = VT_BYTE end)
    end
    pcall(function() s.endUpdate() end)
    -- Name after elements (CE UI refresh / DoFullStructChangeNotification)
    pcall(function() s.Name = ST_PLACEHOLDER_NAME end)
    s.addToGlobalStructureList()
  end)
  if not ok then
    return false, "error:" .. tostring(err), st_count()
  end
  return true, "created", st_count()
end

-- Main-thread: commit pending beginUpdate (CE "save" of in-memory definition).
-- Required before rename — renaming mid-edit is unsafe / fails in CE.
local function st_commit(s, name)
  name = name or (s and s.Name) or ""
  if s then
    -- Drain update counter (endUpdate is a no-op when not updating)
    for _ = 1, 8 do
      local updating = false
      pcall(function()
        if s.isUpdating then updating = s.isUpdating() end
      end)
      pcall(function() s.endUpdate() end)
      if not updating then break end
    end
  end
  if name and name ~= "" then
    _G._ue_st_updating[name] = nil
  end
end

-- Main-thread: rename only after commit. Refuse mid-beginUpdate and protected names.
local function st_set_name_safe(oldn, newn)
  if st_is_protected_name(oldn) then
    return "ERROR: PROTECTED: " .. scrub(oldn)
  end
  if st_is_protected_name(newn) then
    return "ERROR: PROTECTED: " .. scrub(newn)
  end
  local s = st_find_by_name(oldn)
  if not s then return "ERROR: NOT_FOUND: " .. scrub(oldn) end
  if oldn ~= newn and st_find_by_name(newn) then
    return "ERROR: EXISTS: " .. scrub(newn)
  end
  if _G._ue_st_updating[oldn] then
    return "ERROR: STILL_UPDATING: call stEnd before rename (commit structure first)"
  end
  -- Commit any CE-side update counter even if agent forgot stBegin tracking
  st_commit(s, oldn)
  pcall(function() s.Name = newn end)
  local check = st_find_by_name(newn)
  if not check then
    return "ERROR: RENAME_FAILED: " .. scrub(oldn) .. " -> " .. scrub(newn)
  end
  return string.format("OK OLD=%s NEW=%s COMMITTED=1", scrub(oldn), scrub(newn))
end

local function st_elem_count(s)
  local c = 0
  pcall(function() c = s.Count or 0 end)
  return c or 0
end

local function st_size_str(s)
  local sz = ""
  pcall(function()
    if s.Size ~= nil then sz = tostring(s.Size) end
  end)
  if sz == "" or sz == "nil" then sz = "?" end
  return sz
end

-- Main-thread: dump element lines for structure s
local function st_element_lines(s, elemOff, elemLimit)
  local n = st_elem_count(s)
  if elemOff < 0 then elemOff = 0 end
  if elemLimit < 1 then elemLimit = 1 end
  local lines = {}
  lines[#lines + 1] = "IDX\tOFF\tNAME\tVTYPE\tBYTES\tCHILD\tCHILDSTART"
  if elemOff >= n then
    return lines, n
  end
  local last = math.min(n, elemOff + elemLimit) - 1
  for j = elemOff, last do
    local e = nil
    pcall(function() e = s.Element[j] end)
    if not e then
      pcall(function() e = s.getElement(j) end)
    end
    if e then
      local off = 0
      local ename = ""
      local vt = -1
      local bsz = 0
      local child = ""
      local cstart = 0
      pcall(function() off = e.Offset or 0 end)
      pcall(function() ename = tostring(e.Name or "") end)
      pcall(function() vt = e.Vartype or e.Type or -1 end)
      pcall(function() bsz = e.Bytesize or 0 end)
      pcall(function()
        local cs = e.ChildStruct
        if cs and cs.Name then child = tostring(cs.Name) end
      end)
      pcall(function() cstart = e.ChildStructStart or 0 end)
      lines[#lines + 1] = string.format(
        "%d\t%X\t%s\t%s\t%s\t%s\t%s",
        j, off, trunc_str(ename, 80), tostring(vt), tostring(bsz),
        scrub(child), tostring(cstart))
    end
  end
  return lines, n
end

-- Split "a b" / "a -> b" / "a|b" into two names. Optional existCheck runs on main thread.
-- When existCheck=true, prefer longest left part that is an existing structure name.
local function st_split_two_names(rest, prefer_existing_src)
  rest = (rest or ""):match("^%s*(.-)%s*$") or ""
  if rest == "" then return nil, nil, "EMPTY" end
  local a, b = rest:match("^(.-)%s*%->%s*(.+)$")
  if not a then a, b = rest:match("^(.-)%s*|%s*(.+)$") end
  if a then
    a = a:match("^%s*(.-)%s*$") or a
    b = b:match("^%s*(.-)%s*$") or b
    if a == "" or b == "" then return nil, nil, "EMPTY" end
    return a, b, nil
  end
  local parts = {}
  for w in rest:gmatch("%S+") do parts[#parts + 1] = w end
  if #parts < 2 then return nil, nil, "NEED_TWO_NAMES" end
  if prefer_existing_src then
    for i = #parts - 1, 1, -1 do
      local src = table.concat(parts, " ", 1, i)
      local dst = table.concat(parts, " ", i + 1, #parts)
      if st_find_by_name(src) then return src, dst, nil end
    end
  end
  -- Fallback: last token is dst, rest is src
  local dst = parts[#parts]
  local src = table.concat(parts, " ", 1, #parts - 1)
  return src, dst, nil
end

-- Main-thread: element at exact Offset (not "at least" from getElementByOffset alone)
local function st_elem_at_offset(s, off)
  off = tonumber(off) or 0
  local e = nil
  pcall(function()
    if s.getElementByOffset then
      e = s.getElementByOffset(off)
    end
  end)
  if e then
    local eo = nil
    pcall(function() eo = e.Offset end)
    if eo ~= nil and tonumber(eo) == off then return e end
  end
  local n = st_elem_count(s)
  for j = 0, n - 1 do
    local ej = nil
    pcall(function() ej = s.Element[j] end)
    if not ej then pcall(function() ej = s.getElement(j) end) end
    if ej then
      local eo = nil
      pcall(function() eo = ej.Offset end)
      if eo ~= nil and tonumber(eo) == off then return ej end
    end
  end
  return nil
end

local function st_apply_elem_fields(e, ename, vtype, bsz, childName, cstart)
  if ename ~= nil then
    pcall(function() e.Name = tostring(ename) end)
  end
  if vtype ~= nil then
    pcall(function() e.Vartype = tonumber(vtype) end)
  end
  if bsz ~= nil and bsz >= 0 then
    pcall(function() e.Bytesize = tonumber(bsz) end)
  end
  if childName ~= nil then
    if childName == "" then
      pcall(function() e.ChildStruct = nil end)
    else
      local cs = st_find_by_name(childName)
      if not cs then return "ERROR: CHILD_NOT_FOUND: " .. scrub(childName) end
      pcall(function() e.ChildStruct = cs end)
    end
  end
  if cstart ~= nil then
    pcall(function() e.ChildStructStart = tonumber(cstart) or 0 end)
  end
  return nil
end

-- Main-thread: two-pass clone of structure definitions
local function st_clone_structure(srcName, dstName)
  if st_is_protected_name(dstName) then
    return "ERROR: PROTECTED: " .. scrub(dstName)
  end
  -- Empty global list crashes dissect; seed first (CE75-DISSECT-CRASH)
  local seed_ok, seed_st = st_ensure_seed()
  if not seed_ok then
    return "ERROR: SEED_FAILED: " .. scrub(tostring(seed_st))
  end
  local src = st_find_by_name(srcName)
  if not src then return "ERROR: NOT_FOUND: " .. scrub(srcName) end
  if st_find_by_name(dstName) then return "ERROR: EXISTS: " .. scrub(dstName) end
  if type(createStructure) ~= "function" then
    return "ERROR: NO_CREATESTRUCTURE"
  end
  -- Create with a temp name; set final Name only AFTER elements + endUpdate
  -- (CE: Name triggers full UI refresh; rename-while-editing is unsafe).
  local tick = 0
  pcall(function()
    if type(getTickCount) == "function" then tick = getTickCount() end
  end)
  if tick == 0 then pcall(function() tick = os.time() or 0 end) end
  local tmpName = "UE_CLONE_TMP_" .. tostring(tick) .. "_" .. tostring(st_count())
  if st_find_by_name(tmpName) then
    tmpName = tmpName .. "_x"
  end
  local dst = createStructure(tmpName)
  if not dst then return "ERROR: CREATE_FAILED: " .. scrub(dstName) end
  local added = false
  pcall(function()
    dst.addToGlobalStructureList()
    added = true
  end)
  if not added then
    pcall(function() if dst.destroy then dst.destroy() end end)
    st_ensure_seed()
    return "ERROR: ADD_GLOBAL_FAILED: " .. scrub(dstName)
  end

  local n = st_elem_count(src)
  local copied = 0
  local child_ok, child_fail = 0, 0
  local ok_copy, err_copy = pcall(function()
    pcall(function() dst.beginUpdate() end)
    for i = 0, n - 1 do
      local e = nil
      pcall(function() e = src.Element[i] end)
      if not e then pcall(function() e = src.getElement(i) end) end
      if e then
        local ne = dst.addElement()
        if ne then
          local off, ename, vt, bsz = 0, "", -1, nil
          pcall(function() off = e.Offset or 0 end)
          pcall(function() ename = tostring(e.Name or "") end)
          pcall(function() vt = e.Vartype or e.Type or -1 end)
          pcall(function() bsz = e.Bytesize end)
          pcall(function() ne.Offset = off end)
          pcall(function() ne.Name = ename end)
          pcall(function() ne.Vartype = vt end)
          if bsz ~= nil then pcall(function() ne.Bytesize = bsz end) end
          -- ChildStruct deferred to pass 2
          copied = copied + 1
        end
      end
    end
    pcall(function() dst.endUpdate() end)

    -- Pass 2: ChildStruct by name (same global name; clone children first if renaming family)
    pcall(function() dst.beginUpdate() end)
    for i = 0, n - 1 do
      local e = nil
      pcall(function() e = src.Element[i] end)
      if not e then pcall(function() e = src.getElement(i) end) end
      if e then
        local cname, cstart = nil, 0
        local has_child = false
        pcall(function()
          local cs = e.ChildStruct
          if cs and cs.Name then
            has_child = true
            cname = tostring(cs.Name)
          end
        end)
        pcall(function() cstart = e.ChildStructStart or 0 end)
        if has_child and cname and cname ~= "" then
          local ne = nil
          pcall(function() ne = dst.Element[i] end)
          if not ne then pcall(function() ne = dst.getElement(i) end) end
          local child = st_find_by_name(cname)
          if ne and child then
            local okc = pcall(function()
              ne.ChildStruct = child
              ne.ChildStructStart = cstart
            end)
            if okc then child_ok = child_ok + 1 else child_fail = child_fail + 1 end
          else
            child_fail = child_fail + 1
          end
        end
      end
    end
    pcall(function() dst.endUpdate() end)

    -- Commit then rename to final name (save-then-rename rule)
    st_commit(dst, tmpName)
    if st_find_by_name(dstName) then
      error("DEST_EXISTS_AFTER_FILL")
    end
    pcall(function() dst.Name = dstName end)
  end)

  if not ok_copy then
    pcall(function() dst.removeFromGlobalStructureList() end)
    pcall(function() if dst.destroy then dst.destroy() end end)
    st_ensure_seed()  -- never leave global list empty after rollback
    return "ERROR: CLONE_COPY: " .. scrub(tostring(err_copy))
  end

  local final = st_find_by_name(dstName)
  if not final then
    -- rename failed; leave tmp if present for recovery
    return "ERROR: RENAME_AFTER_CLONE: tmp=" .. scrub(tmpName) .. " wanted=" .. scrub(dstName)
  end

  local dst_n = st_elem_count(final)
  return string.format(
    "OK SRC=%s DST=%s ELEMS=%d COPIED=%d CHILD_OK=%d CHILD_FAIL=%d SEED=%s",
    scrub(srcName), scrub(dstName), dst_n, copied, child_ok, child_fail, scrub(tostring(seed_st)))
end

-- Main-thread: delete all elements (destroy Element[0] loop; CE has no clear())
local function st_clear_elements(s, name)
  name = name or ""
  pcall(function() if s and s.Name then name = tostring(s.Name) end end)
  if st_is_protected_name(name) then
    return "ERROR: PROTECTED: " .. scrub(name)
  end
  pcall(function() s.beginUpdate() end)
  local deleted = 0
  local guard = 0
  while guard < MAX_ST_CLEAR_ELEMS do
    local c = st_elem_count(s)
    if c <= 0 then break end
    local ok_del = false
    pcall(function()
      local e = s.Element[0]
      if e and e.destroy then
        e.destroy()
        ok_del = true
      end
    end)
    if not ok_del then
      pcall(function()
        local e = s.getElement and s.getElement(0)
        if e and e.destroy then
          e.destroy()
          ok_del = true
        end
      end)
    end
    if not ok_del then break end
    deleted = deleted + 1
    guard = guard + 1
  end
  st_commit(s, name)
  local left = st_elem_count(s)
  if left > 0 then
    return string.format(
      "ERROR: CLEAR_PARTIAL: deleted=%d left=%d", deleted, left)
  end
  return string.format("OK NAME=%s DELETED=%d ELEMS=0", scrub(tostring(s.Name or name)), deleted)
end

-- Main-thread only helpers for address-list inventory (T02)
local function mr_script_info(mr)
  local has, slen = 0, 0
  local ok, scr = pcall(function() return mr.Script end)
  if ok and scr and scr ~= "" then
    has = 1
    slen = #scr
  end
  return has, slen
end

local function mr_offsets_str(mr, sep)
  sep = sep or "+"
  local oc = mr.OffsetCount or 0
  if oc <= 0 then return "", 0 end
  local parts = {}
  for i = 0, oc - 1 do
    local off = 0
    pcall(function() off = mr.Offset[i] or 0 end)
    parts[#parts + 1] = string.format("%X", off)
  end
  return table.concat(parts, sep), oc
end

local function mr_parent_id(mr)
  local pid = -1
  pcall(function()
    local p = mr.Parent
    if p and p.ID then pid = p.ID end
  end)
  return pid
end

local function mr_cur_hex(mr)
  local cur = 0
  pcall(function() cur = mr.CurrentAddress or 0 end)
  if not cur then cur = 0 end
  return string.format("%X", cur)
end

local function mr_is_group(mr)
  local g = false
  pcall(function()
    if mr.IsGroupHeader or mr.IsAddressGroupHeader then g = true end
  end)
  return g
end

-- CLASS: AA | EXPR | POINTER | STATIC | GROUP | OTHER  (T00: EXPR is common on DL2)
local function mr_classify(mr, addr, offc, hasScript, typeNum)
  if mr_is_group(mr) then return "GROUP" end
  if hasScript == 1 or typeNum == VT_AUTO_ASSEMBLER_A or typeNum == VT_AUTO_ASSEMBLER_B then
    return "AA"
  end
  if offc and offc > 0 then return "POINTER" end
  addr = addr or ""
  if addr ~= "" then
    if string.find(addr, "+", 1, true) or string.find(addr, "[", 1, true) then
      return "EXPR"
    end
    return "STATIC"
  end
  return "OTHER"
end

local function mr_value_trunc(mr, n)
  n = n or 80
  local v = ""
  pcall(function() v = tostring(mr.Value or "") end)
  return trunc_str(v, n)
end

local function mr_readable_flag(mr)
  -- celua: IsReadable reliable after Value accessed at least once
  pcall(function() local _ = mr.Value end)
  local r = 0
  pcall(function()
    if mr.IsReadable then r = 1 end
  end)
  return r
end

-- Read offsets into 1-based Lua table for setAddress(expr, offs)
local function mr_get_offset_table(mr)
  local oc = mr.OffsetCount or 0
  local t = {}
  for i = 0, oc - 1 do
    local off = 0
    pcall(function() off = mr.Offset[i] or 0 end)
    t[i + 1] = off
  end
  return t, oc
end

-- CE setAddress clears offsets unless table passed; preserve when only base changes.
local function mr_set_address_preserve_offsets(mr, expr)
  expr = tostring(expr or "")
  local offs, oc = mr_get_offset_table(mr)
  local ok, err = pcall(function()
    if type(mr.setAddress) == "function" then
      if oc > 0 then
        mr.setAddress(expr, offs)
      else
        mr.setAddress(expr)
      end
    else
      mr.Address = expr
      if oc > 0 then
        mr.OffsetCount = oc
        for i = 1, oc do
          mr.Offset[i - 1] = offs[i]
        end
      end
    end
  end)
  return ok, err
end

-- Parse "10,2A0,8" or "10+2A0+8" or empty → table, or nil,"error"
local function parse_offset_list(s)
  s = tostring(s or ""):gsub("%s+", "")
  if s == "" or s == "-" then
    return {}, 0
  end
  s = s:gsub("%+", ",")
  local t = {}
  for part in string.gmatch(s, "[^,]+") do
    part = part:gsub("^0[xX]", "")
    if part == "" then
      return nil, "ERROR: BAD_OFFSET_TOKEN"
    end
    local n = tonumber(part, 16)
    if not n then
      return nil, "ERROR: BAD_OFFSET: " .. part
    end
    t[#t + 1] = n
  end
  if #t > MAX_OFFSETS then
    return nil, "ERROR: TOO_MANY_OFFSETS: " .. tostring(#t)
  end
  return t, #t
end

local function mr_set_offsets(mr, offs)
  local base = tostring(mr.Address or "")
  local ok, err = pcall(function()
    if type(mr.setAddress) == "function" then
      if #offs > 0 then
        mr.setAddress(base, offs)
      else
        mr.setAddress(base)
        mr.OffsetCount = 0
      end
    else
      mr.Address = base
      mr.OffsetCount = #offs
      for i = 1, #offs do
        mr.Offset[i - 1] = offs[i]
      end
    end
  end)
  return ok, err
end

local function audit_push(verb, detail, result)
  local a = _G._ue_audit
  if type(a) ~= "table" then
    _G._ue_audit = {}
    a = _G._ue_audit
  end
  local tick = 0
  pcall(function()
    if type(getTickCount) == "function" then tick = getTickCount() end
  end)
  local line = string.format(
    "%d\t%s\t%s\t%s",
    tick, scrub(verb or "?"), scrub(detail or ""), scrub(tostring(result or ""):sub(1, 80)))
  a[#a + 1] = line
  while #a > MAX_AUDIT do
    table.remove(a, 1)
  end
end

-- Preview of inbound command for CE Lua Engine console (crash forensics).
-- Last printed "EXEC start" before silence = the call that killed the server thread.
local function cmd_preview(cmd, max_len)
  max_len = max_len or 240
  local s = scrub(tostring(cmd or ""))
  -- Collapse huge hex payloads (script chunks, alApply) so console stays readable
  if #s > 80 and (s:find("hex=") or s:match("^alSetScriptChunk") or s:match("^runScript")) then
    local verb = s:match("^(%S+)") or "?"
    local rest = s:sub(#verb + 2)
    if #rest > 60 then rest = rest:sub(1, 60) .. "…[trunc]" end
    s = verb .. " " .. rest
  end
  if #s > max_len then
    s = s:sub(1, max_len) .. "…[len=" .. tostring(#tostring(cmd or "")) .. "]"
  end
  return s
end

-- Main-thread only: single alSet* op for alApply / shared handlers
local function al_op_set_desc(id, text)
  local al, mr = al_find_by_id(id)
  if not mr then return "ERROR: NOT_FOUND: " .. tostring(id) end
  local ok, err = pcall(function() mr.Description = text end)
  if not ok then return "ERROR: SET_DESC: " .. tostring(err) end
  return string.format("OK ID=%s DESC=%s", tostring(mr.ID or id), scrub(mr.Description or ""))
end

local function al_op_set_address(id, expr)
  expr = scrub(expr or "")
  if expr == "" then return "ERROR: EMPTY_ADDRESS" end
  local al, mr = al_find_by_id(id)
  if not mr then return "ERROR: NOT_FOUND: " .. tostring(id) end
  local ok, err = mr_set_address_preserve_offsets(mr, expr)
  if not ok then return "ERROR: SET_ADDRESS: " .. tostring(err) end
  local offs, oc = mr_offsets_str(mr, "+")
  return string.format(
    "OK ID=%s ADDR=%s OFFC=%d OFFS=%s CUR=%s",
    tostring(mr.ID or id), scrub(tostring(mr.Address or "")), oc, offs, mr_cur_hex(mr))
end

local function al_op_set_offsets(id, list)
  local offs, n_or_err = parse_offset_list(list)
  if not offs then return n_or_err end
  local al, mr = al_find_by_id(id)
  if not mr then return "ERROR: NOT_FOUND: " .. tostring(id) end
  local ok, err = mr_set_offsets(mr, offs)
  if not ok then return "ERROR: SET_OFFSETS: " .. tostring(err) end
  local offsStr, oc = mr_offsets_str(mr, ",")
  return string.format(
    "OK ID=%s OFFC=%d OFFS=%s CUR=%s ADDR=%s",
    tostring(mr.ID or id), oc, offsStr, mr_cur_hex(mr), scrub(tostring(mr.Address or "")))
end

local function al_op_set_type(id, tnum)
  local al, mr = al_find_by_id(id)
  if not mr then return "ERROR: NOT_FOUND: " .. tostring(id) end
  local ok, err = pcall(function() mr.Type = tnum end)
  if not ok then return "ERROR: SET_TYPE: " .. tostring(err) end
  return string.format("OK ID=%s TYPE=%s", tostring(mr.ID or id), tostring(mr.Type))
end

-- Main-thread: aaCheck body for one memrec
local function al_op_aa_check(id)
  local al, mr = al_find_by_id(id)
  if not mr then return "ERROR: NOT_FOUND: " .. tostring(id) end
  if not mr_is_aa_script(mr) then return "ERROR: NOT_AA: " .. tostring(id) end
  local ok, scr = pcall(function() return mr.Script end)
  if not ok or scr == nil or scr == "" then
    return "ERROR: AACHECK: empty script"
  end
  if type(autoAssembleCheck) ~= "function" then
    return "ERROR: AACHECK: autoAssembleCheck unavailable"
  end
  local okc, a, b = pcall(autoAssembleCheck, scr, true, false)
  if not okc then return "ERROR: AACHECK: " .. tostring(a) end
  if a == true or a == 1 then
    return string.format("OK ID=%s", tostring(mr.ID or id))
  end
  local msg = b or a or "failed"
  return "ERROR: AACHECK: " .. scrub(tostring(msg))
end

-- Main-thread: set Active; do_check=true runs aaCheck before enable (AA rows only)
local function al_op_set_active(id, want, do_check)
  local al, mr = al_find_by_id(id)
  if not mr then return "ERROR: NOT_FOUND: " .. tostring(id) end
  if want and do_check and mr_is_aa_script(mr) then
    local chk = al_op_aa_check(id)
    if tostring(chk):match("^ERROR:") then
      return "ERROR: SET_ACTIVE: " .. tostring(chk)
    end
  end
  local ok, err = pcall(function()
    mr.Active = want
  end)
  if not ok then return "ERROR: SET_ACTIVE: " .. tostring(err) end
  local act = 0
  pcall(function() if mr.Active then act = 1 end end)
  if want and act ~= 1 then
    return string.format(
      "ERROR: SET_ACTIVE: enable failed ID=%s ACTIVE=%d", tostring(mr.ID or id), act)
  end
  if (not want) and act ~= 0 then
    return string.format(
      "ERROR: SET_ACTIVE: disable failed ID=%s ACTIVE=%d", tostring(mr.ID or id), act)
  end
  local checked = (want and do_check) and 1 or 0
  return string.format(
    "OK ID=%s ACTIVE=%d CHECKED=%d", tostring(mr.ID or id), act, checked)
end

-- Main-thread: run one alApply line (setDesc/setAddress/setOffsets/setType)
local function al_apply_one_op(line)
  line = (line or ""):match("^%s*(.-)%s*$") or ""
  if line == "" then return "ERROR: EMPTY_OP" end
  local op = line:match("^(%S+)") or ""
  op = op:lower()
  if op == "setdesc" or op == "alsetdesc" then
    local id, text = line:match("^%S+%s+(%-?%d+)%s*(.*)$")
    if not id then return "ERROR: USAGE: setDesc <id> <text>" end
    return al_op_set_desc(tonumber(id), text or "")
  elseif op == "setaddress" or op == "alsetaddress" then
    local id, expr = line:match("^%S+%s+(%-?%d+)%s+(.+)$")
    if not id then return "ERROR: USAGE: setAddress <id> <expr>" end
    return al_op_set_address(tonumber(id), expr)
  elseif op == "setoffsets" or op == "alsetoffsets" then
    local id, list = line:match("^%S+%s+(%-?%d+)%s*(.*)$")
    if not id then return "ERROR: USAGE: setOffsets <id> <hex,hex>" end
    return al_op_set_offsets(tonumber(id), list or "")
  elseif op == "settype" or op == "alsettype" then
    local id, tnum = line:match("^%S+%s+(%-?%d+)%s+(%-?%d+)$")
    if not id then return "ERROR: USAGE: setType <id> <typeInt>" end
    return al_op_set_type(tonumber(id), tonumber(tnum))
  end
  return "ERROR: UNKNOWN_OP: " .. scrub(op)
end

local function run_script_body(code, safe)
  if not code or #code == 0 then return "ERROR: Empty script" end
  if safe then
    local low = code:lower()
    local banned = {
      "enummemoryregions", "creatememscan", "varscan_", "memscan_firstscan",
      "getstructure%(%s*['\"]",  -- getStructure("name") pattern
    }
    for i = 1, #banned do
      if low:find(banned[i]) then
        return "ERROR: RUNSCRIPT_SAFE: banned pattern: " .. banned[i]
      end
    end
  end
  local fn, err = loadstring("return " .. code)
  if fn then
    local ok, result = pcall(fn)
    if ok then
      return fit_response(tostring(result))
    else
      return "ERROR: " .. tostring(result)
    end
  else
    fn, err = loadstring(code)
    if fn then
      local ok, result = pcall(fn)
      if ok then
        return fit_response(tostring(result))
      else
        return "ERROR: " .. tostring(result)
      end
    else
      return "ERROR: Compile error: " .. tostring(err)
    end
  end
end

local function write_length_prefixed(pipe, msg)
  local len = #msg
  local len_bytes = string.char(len % 256, bShr(len, 8) % 256,
    bShr(len, 16) % 256, bShr(len, 24) % 256)
  pipe.writeBytes({len_bytes:byte(1, 4)}, 4)
  if len > 0 then
    pipe.writeString(msg, false)
  end
end

local function read_length_prefixed(pipe)
  local len_header = pipe.readBytes(4)
  if not len_header or #len_header < 4 then
    return nil
  end
  local len = len_header[1] + len_header[2] * 256 + len_header[3] * 65536 + len_header[4] * 16777216
  if len == 0 then return "" end
  local data = pipe.readBytes(len)
  if not data or #data < len then return nil end
  local chars = {}
  for i = 1, #data do
    chars[i] = string.char(data[i])
  end
  return table.concat(chars)
end

local function process_command(cmd)
  if cmd == "ping" then
    return "pong"
  elseif cmd == "help" then
    return table.concat({
      "ping", "getVersion", "help", "tableStatus", "debugSync",
      "alDump [offset] [limit]", "alGet <id>", "alResolve <id>",
      "alSetDesc <id> <text>", "alSetAddress <id> <expr>",
      "alSetOffsets <id> <hex,hex,...>", "alSetType <id> <typeInt>",
      "alGetScript <id> [off] [len]", "alSetScriptBegin <id> <totalLen>",
      "alSetScriptChunk <id> <off> <hex>", "alSetScriptCommit <id>", "alSetScriptAbort <id>",
      "aaCheck <id>", "alSetActive <id> 0|1 [nocheck]", "alDisableSoft <id>",
      "alApply stop=1 hex=<ops> OR alApply stop=1 op ;; op",
      "alAudit [n]", "symGet <name>", "symSet <name> <addr> [donotsave]",
      "stDump", "stFind <name>", "stGet <name> [elemOff] [elemLimit]",
      "stEnsureSeed", "stClone <src> <dst> (or src -> dst)",
      "stBegin <name>", "stEnd <name>",
      "stUpsertElem name/off/elem/vtype (prefer pipe form; see docs)",
      "stClearElements <name>", "stSetName <old> <new> (stEnd first)",
      "readByte <hexaddr>", "readBytes <hexaddr> <size>",
      "readQword <hexaddr>", "readDword <hexaddr>", "readString <hexaddr> <maxlen>",
      "writeBytes <hexaddr> <hex>",
      "getAddress <symbol>", "resolveSymbol <name>",
      "AOBScan <hexpattern with optional ** wildcards>",
      "GroupScan <group command string>  (CE vtGrouped; main-thread memscan)",
      "enumModules", "runScript <code>", "runScriptSafe <code>", "close"
    }, "|")
  elseif cmd == "getVersion" then
    return VERSION

  -- T01: foundation smoke — main-thread table/process snapshot
  elseif cmd == "tableStatus" then
    local packed = sync_call(function()
      local proc = tostring(process or "?")
      local pid = "?"
      if type(getOpenedProcessID) == "function" then
        local okp, p = pcall(getOpenedProcessID)
        if okp and p then pid = tostring(p) end
      end
      local alCount = 0
      local al = getAddressList()
      if al and al.Count then alCount = al.Count end
      local stCount = 0
      if type(getStructureCount) == "function" then
        local oks, sc = pcall(getStructureCount)
        if oks and sc then stCount = sc end
      end
      local seed = 0
      if st_find_by_name(ST_PLACEHOLDER_NAME) or st_find_by_name(ST_PLACEHOLDER_LEGACY) then
        seed = 1
      end
      local cev = "?"
      if type(getCEVersion) == "function" then
        local okv, v = pcall(getCEVersion)
        if okv and v then cev = tostring(v) end
      end
      return string.format(
        "OK process=%s pid=%s alCount=%d stCount=%d seed=%d ceVersion=%s server=%s",
        scrub(proc), scrub(pid), alCount, stCount, seed, scrub(cev), scrub(VERSION))
    end)
    local data, err = ok_data(packed)
    if not data then return err end
    return fit_response(data)

  -- T01: prove synchronize path returns without table dependency
  elseif cmd == "debugSync" then
    local packed = sync_call(function()
      return "OK mainthread=1"
    end)
    local data, err = ok_data(packed)
    if not data then return err end
    return data

  -- T01 negative test: sync_call surfaces errors without killing the server
  elseif cmd == "debugSyncError" then
    local packed = sync_call(function()
      error("deliberate sync error")
    end)
    local data, err = ok_data(packed)
    if not data then return err end
    return data

  -- T02: address list inventory (metadata only — no script bodies)
  -- alDump [offset] [limit]   defaults offset=0 limit=500
  elseif cmd == "alDump" or cmd:match("^alDump%s") then
    local off, lim = 0, 500
    local a1, a2 = cmd:match("^alDump%s+(%d+)%s+(%d+)$")
    if a1 then
      off = tonumber(a1) or 0
      lim = tonumber(a2) or 500
    else
      local aonly = cmd:match("^alDump%s+(%d+)$")
      if aonly then off = tonumber(aonly) or 0 end
    end
    if off < 0 then off = 0 end
    if lim < 1 then lim = 1 end
    if lim > 2000 then lim = 2000 end
    local packed = sync_call(function()
      local al = getAddressList()
      if not al then return "ERROR: NO_ADDRESSLIST" end
      local n = al.Count or 0
      local lines = {}
      lines[#lines + 1] = string.format("COUNT=%d OFFSET=%d LIMIT=%d", n, off, lim)
      lines[#lines + 1] = "ID\tIDX\tPID\tDESC\tTYPE\tACTIVE\tADDR\tOFFC\tOFFS\tCUR\tHASSCRIPT\tSCRIPTLEN\tCLASS"
      local last = math.min(n, off + lim) - 1
      if off < n then
        for i = off, last do
          local mr = al.getMemoryRecord(i)
          if mr then
            local sid = mr.ID or -1
            local desc = trunc_str(mr.Description or "", 100)
            local addr = trunc_str(tostring(mr.Address or ""), 80)
            local vt = mr.Type
            if vt == nil then vt = -1 end
            local act = 0
            pcall(function() if mr.Active then act = 1 end end)
            local offs, oc = mr_offsets_str(mr, "+")
            local has, slen = mr_script_info(mr)
            local class = mr_classify(mr, addr, oc, has, vt)
            local pid = mr_parent_id(mr)
            local cur = mr_cur_hex(mr)
            lines[#lines + 1] = string.format(
              "%s\t%d\t%d\t%s\t%s\t%d\t%s\t%d\t%s\t%s\t%d\t%d\t%s",
              tostring(sid), i, pid, desc, tostring(vt), act, addr, oc, offs, cur, has, slen, class)
          end
        end
      end
      return table.concat(lines, "\n")
    end)
    local data, err = ok_data(packed)
    if not data then return err end
    return fit_response(data)

  elseif cmd:match("^alGet%s+(%-?%d+)$") then
    local id = tonumber(cmd:match("^alGet%s+(%-?%d+)$"))
    local packed = sync_call(function()
      local al, mr = al_find_by_id(id)
      if not mr then return "ERROR: NOT_FOUND: " .. tostring(id) end
      local has, slen = mr_script_info(mr)
      local offs, oc = mr_offsets_str(mr, ",")
      local addr = scrub(tostring(mr.Address or ""))
      local vt = mr.Type
      if vt == nil then vt = -1 end
      local act = 0
      pcall(function() if mr.Active then act = 1 end end)
      local lines = {
        "OK",
        "ID=" .. tostring(mr.ID or id),
        "DESC=" .. scrub(mr.Description or ""),
        "TYPE=" .. tostring(vt),
        "ACTIVE=" .. tostring(act),
        "ADDR=" .. addr,
        "OFFC=" .. tostring(oc),
        "OFFS=" .. offs,
        "CUR=" .. mr_cur_hex(mr),
        "VALUE=" .. mr_value_trunc(mr, 80),
        "HASSCRIPT=" .. tostring(has),
        "SCRIPTLEN=" .. tostring(slen),
        "PARENT=" .. tostring(mr_parent_id(mr)),
        "CLASS=" .. mr_classify(mr, addr, oc, has, vt),
        "GROUP=" .. (mr_is_group(mr) and "1" or "0"),
      }
      return table.concat(lines, "\n")
    end)
    local data, err = ok_data(packed)
    if not data then return err end
    return fit_response(data)

  elseif cmd:match("^alResolve%s+(%-?%d+)$") then
    local id = tonumber(cmd:match("^alResolve%s+(%-?%d+)$"))
    local packed = sync_call(function()
      local al, mr = al_find_by_id(id)
      if not mr then return "ERROR: NOT_FOUND: " .. tostring(id) end
      local val = mr_value_trunc(mr, 80)
      local readable = mr_readable_flag(mr)
      local act = 0
      pcall(function() if mr.Active then act = 1 end end)
      local addr = scrub(tostring(mr.Address or ""))
      return string.format(
        "OK ID=%s CUR=%s READABLE=%d ACTIVE=%d VALUE=%s ADDR=%s",
        tostring(mr.ID or id), mr_cur_hex(mr), readable, act, val, addr)
    end)
    local data, err = ok_data(packed)
    if not data then return err end
    return fit_response(data)

  -- T03: address list mutations
  elseif cmd:match("^alSetDesc%s+(%-?%d+)%s*(.*)$") then
    local id, text = cmd:match("^alSetDesc%s+(%-?%d+)%s*(.*)$")
    id = tonumber(id)
    text = (text or ""):gsub("^\n", ""):gsub("\r", "")
    local packed = sync_call(function()
      return al_op_set_desc(id, text)
    end)
    local data, err = ok_data(packed)
    if not data then return err end
    return fit_response(data)

  elseif cmd:match("^alSetAddress%s+(%-?%d+)%s+(.+)$") then
    local id, expr = cmd:match("^alSetAddress%s+(%-?%d+)%s+(.+)$")
    id = tonumber(id)
    local packed = sync_call(function()
      return al_op_set_address(id, expr)
    end)
    local data, err = ok_data(packed)
    if not data then return err end
    return fit_response(data)

  elseif cmd:match("^alSetOffsets%s+(%-?%d+)%s*(.*)$") then
    local id, list = cmd:match("^alSetOffsets%s+(%-?%d+)%s*(.*)$")
    id = tonumber(id)
    list = list or ""
    local packed = sync_call(function()
      return al_op_set_offsets(id, list)
    end)
    local data, err = ok_data(packed)
    if not data then return err end
    return fit_response(data)

  elseif cmd:match("^alSetType%s+(%-?%d+)%s+(%-?%d+)$") then
    local id, tnum = cmd:match("^alSetType%s+(%-?%d+)%s+(%-?%d+)$")
    id = tonumber(id)
    tnum = tonumber(tnum)
    local packed = sync_call(function()
      return al_op_set_type(id, tnum)
    end)
    local data, err = ok_data(packed)
    if not data then return err end
    return fit_response(data)

  -- T11a: batch mutate in one synchronize
  -- alApply stop=1 hex=<hex of newline-separated ops>
  -- alApply stop=1 setDesc 1 a ;; setAddress 2 b
  elseif cmd:match("^alApply%s+") then
    local rest = cmd:match("^alApply%s+(.+)$") or ""
    rest = rest:match("^%s*(.-)%s*$") or rest
    local stop = true
    local ops_body = rest
    local stop_flag, after = rest:match("^stop=([01])%s+(.*)$")
    if stop_flag then
      stop = (stop_flag == "1")
      ops_body = after or ""
    end
    local hex_body = ops_body:match("^hex=([0-9A-Fa-f]+)$")
    local op_lines = {}
    if hex_body then
      local decoded = hex_to_str(hex_body)
      if not decoded then return "ERROR: BAD_HEX" end
      for line in (decoded .. "\n"):gmatch("(.-)\n") do
        line = line:match("^%s*(.-)%s*$") or line
        if line ~= "" then op_lines[#op_lines + 1] = line end
      end
    else
      -- split on " ;; "
      for part in (ops_body .. ";;"):gmatch("(.-)%s*;;%s*") do
        part = part:match("^%s*(.-)%s*$") or part
        if part ~= "" then op_lines[#op_lines + 1] = part end
      end
    end
    if #op_lines == 0 then
      return "ERROR: USAGE: alApply stop=1 hex=... OR alApply stop=1 op ;; op"
    end
    if #op_lines > MAX_AL_APPLY_OPS then
      return "ERROR: TOO_MANY_OPS: " .. tostring(#op_lines) .. " max=" .. tostring(MAX_AL_APPLY_OPS)
    end
    local packed = sync_call(function()
      local lines = {}
      local okc, failc = 0, 0
      for i = 1, #op_lines do
        local r = al_apply_one_op(op_lines[i])
        local is_err = tostring(r):match("^ERROR:")
        if is_err then
          failc = failc + 1
          lines[#lines + 1] = string.format("%d\tFAIL\t%s\t%s", i, scrub(op_lines[i]:sub(1, 60)), scrub(r))
          if stop then
            lines[#lines + 1] = string.format(
              "STOPPED ok=%d fail=%d at=%d", okc, failc, i)
            return table.concat(lines, "\n")
          end
        else
          okc = okc + 1
          lines[#lines + 1] = string.format("%d\tOK\t%s\t%s", i, scrub(op_lines[i]:sub(1, 60)), scrub(r))
        end
      end
      lines[#lines + 1] = string.format("DONE ok=%d fail=%d stop=%d", okc, failc, stop and 1 or 0)
      return table.concat(lines, "\n")
    end)
    local data, err = ok_data(packed)
    if not data then return err end
    return fit_response(data)

  elseif cmd == "alAudit" or cmd:match("^alAudit%s*$") or cmd:match("^alAudit%s+(%d+)$") then
    local n = tonumber(cmd:match("^alAudit%s+(%d+)$")) or 20
    if n < 1 then n = 1 end
    if n > MAX_AUDIT then n = MAX_AUDIT end
    local a = _G._ue_audit or {}
    local start = #a - n + 1
    if start < 1 then start = 1 end
    local lines = { string.format("COUNT=%d SHOW=%d", #a, math.min(n, #a)) }
    for i = start, #a do
      lines[#lines + 1] = a[i]
    end
    return fit_response(table.concat(lines, "\n"))

  -- T04: AA script chunk get/set + Active / aaCheck
  -- alGetScript <id> [offset] [length]
  elseif cmd:match("^alGetScript%s+(%-?%d+)") then
    local id = tonumber(cmd:match("^alGetScript%s+(%-?%d+)"))
    local off, len = 0, DEFAULT_SCRIPT_CHUNK
    local a1, a2 = cmd:match("^alGetScript%s+%-?%d+%s+(%d+)%s+(%d+)$")
    if a1 then
      off = tonumber(a1) or 0
      len = tonumber(a2) or DEFAULT_SCRIPT_CHUNK
    else
      local aonly = cmd:match("^alGetScript%s+%-?%d+%s+(%d+)$")
      if aonly then off = tonumber(aonly) or 0 end
    end
    if off < 0 then off = 0 end
    if len < 1 then len = 1 end
    if len > 32000 then len = 32000 end  -- hex doubles size; keep under MAX_RESP
    local packed = sync_call(function()
      local al, mr = al_find_by_id(id)
      if not mr then return { err = "ERROR: NOT_FOUND: " .. tostring(id) } end
      if not mr_is_aa_script(mr) then return { err = "ERROR: NOT_AA: " .. tostring(id) } end
      local ok, scr = pcall(function() return mr.Script end)
      if not ok or scr == nil then return { err = "ERROR: NOT_AA: " .. tostring(id) } end
      scr = tostring(scr)
      return { id = mr.ID or id, total = #scr, text = scr }
    end)
    local data, err = ok_data(packed)
    if not data then return err end
    if data.err then return data.err end
    local total = data.total or 0
    if off > total then off = total end
    local slice = string.sub(data.text or "", off + 1, off + len)
    local hx = str_to_hex(slice)
    local resp = string.format(
      "OK ID=%s TOTAL=%d OFFSET=%d LENGTH=%d DATA=%s",
      tostring(data.id), total, off, #slice, hx)
    return fit_response(resp)

  elseif cmd:match("^alSetScriptBegin%s+(%-?%d+)%s+(%d+)$") then
    local id, total = cmd:match("^alSetScriptBegin%s+(%-?%d+)%s+(%d+)$")
    id = tonumber(id)
    total = tonumber(total) or -1
    if total < 0 or total > MAX_SCRIPT_BYTES then
      return "ERROR: SCRIPT_TOO_LARGE: " .. tostring(total) .. " max=" .. tostring(MAX_SCRIPT_BYTES)
    end
    local packed = sync_call(function()
      local al, mr = al_find_by_id(id)
      if not mr then return "ERROR: NOT_FOUND: " .. tostring(id) end
      if not mr_is_aa_script(mr) then return "ERROR: NOT_AA: " .. tostring(id) end
      return "OK"
    end)
    local data, err = ok_data(packed)
    if not data then return err end
    if data:match("^ERROR:") then return data end
    _G._ue_script_stage[stage_key(id)] = { total = total, received = 0, buf = "" }
    return string.format("OK ID=%s TOTAL=%d", tostring(id), total)

  elseif cmd:match("^alSetScriptChunk%s+(%-?%d+)%s+(%d+)%s+([0-9A-Fa-f]+)$") then
    local id, off, hx = cmd:match("^alSetScriptChunk%s+(%-?%d+)%s+(%d+)%s+([0-9A-Fa-f]+)$")
    id = tonumber(id)
    off = tonumber(off) or -1
    local st = stage_get(id)
    if not st then return "ERROR: NO_STAGE: begin first" end
    if off ~= st.received then
      return string.format("ERROR: CHUNK_OFFSET: expected=%d got=%d", st.received, off)
    end
    local chunk = hex_to_str(hx)
    if not chunk then return "ERROR: BAD_HEX" end
    if st.received + #chunk > st.total then
      return "ERROR: CHUNK_OVERFLOW"
    end
    st.buf = st.buf .. chunk
    st.received = st.received + #chunk
    return string.format("OK ID=%s RECEIVED=%d TOTAL=%d", tostring(id), st.received, st.total)

  elseif cmd:match("^alSetScriptCommit%s+(%-?%d+)$") then
    local id = tonumber(cmd:match("^alSetScriptCommit%s+(%-?%d+)$"))
    local st = stage_get(id)
    if not st then return "ERROR: NO_STAGE: begin first" end
    if st.received ~= st.total then
      return string.format("ERROR: INCOMPLETE: received=%d total=%d", st.received, st.total)
    end
    local body = st.buf
    local packed = sync_call(function()
      local al, mr = al_find_by_id(id)
      if not mr then return "ERROR: NOT_FOUND: " .. tostring(id) end
      if not mr_is_aa_script(mr) then return "ERROR: NOT_AA: " .. tostring(id) end
      local ok, err = pcall(function()
        mr.Script = body
      end)
      if not ok then return "ERROR: SET_SCRIPT: " .. tostring(err) end
      local has, slen = mr_script_info(mr)
      if has == 0 and slen == 0 and #body > 0 then
        -- property may still report empty if not AA storage; report intended length
        return string.format("OK ID=%s SCRIPTLEN=%d WARN=verify", tostring(mr.ID or id), #body)
      end
      return string.format("OK ID=%s SCRIPTLEN=%d", tostring(mr.ID or id), slen > 0 and slen or #body)
    end)
    local data, err = ok_data(packed)
    stage_clear(id)
    if not data then return err end
    return data

  elseif cmd:match("^alSetScriptAbort%s+(%-?%d+)$") then
    local id = tonumber(cmd:match("^alSetScriptAbort%s+(%-?%d+)$"))
    stage_clear(id)
    return string.format("OK ID=%s ABORTED=1", tostring(id))

  elseif cmd:match("^aaCheck%s+(%-?%d+)$") then
    local id = tonumber(cmd:match("^aaCheck%s+(%-?%d+)$"))
    local packed = sync_call(function()
      return al_op_aa_check(id)
    end)
    local data, err = ok_data(packed)
    if not data then return err end
    return fit_response(data)

  -- alSetActive <id> 0|1 [nocheck]
  -- Enable defaults to aaCheck first (T11b); pass nocheck to skip (advanced / non-AA)
  elseif cmd:match("^alSetActive%s+(%-?%d+)%s+([01])") then
    local id, flag = cmd:match("^alSetActive%s+(%-?%d+)%s+([01])")
    id = tonumber(id)
    local want = (flag == "1")
    local nocheck = cmd:match("nocheck") ~= nil
    local do_check = want and (not nocheck)
    local packed = sync_call(function()
      return al_op_set_active(id, want, do_check)
    end)
    local data, err = ok_data(packed)
    if not data then return err end
    return data

  elseif cmd:match("^alDisableSoft%s+(%-?%d+)$") then
    local id = tonumber(cmd:match("^alDisableSoft%s+(%-?%d+)$"))
    local packed = sync_call(function()
      local al, mr = al_find_by_id(id)
      if not mr then return "ERROR: NOT_FOUND: " .. tostring(id) end
      local ok, err = pcall(function()
        if type(mr.disableWithoutExecute) == "function" then
          mr.disableWithoutExecute()
        elseif type(mr.DisableWithoutExecute) == "function" then
          mr.DisableWithoutExecute()
        else
          mr.Active = false
        end
      end)
      if not ok then return "ERROR: DISABLE_SOFT: " .. tostring(err) end
      local act = 0
      pcall(function() if mr.Active then act = 1 end end)
      return string.format("OK ID=%s ACTIVE=%d", tostring(mr.ID or id), act)
    end)
    local data, err = ok_data(packed)
    if not data then return err end
    return data

  -- T05: global dissect structure inventory (definitions; no live base required)
  elseif cmd == "stDump" or cmd:match("^stDump%s*$") then
    local packed = sync_call(function()
      local n = 0
      pcall(function() n = getStructureCount() or 0 end)
      local lines = {}
      lines[#lines + 1] = string.format("COUNT=%d", n)
      lines[#lines + 1] = "IDX\tNAME\tSIZE\tELEMS"
      if n > 0 then
        for i = 0, n - 1 do
          local s = getStructure(i)  -- index only
          if s then
            local name = "?"
            pcall(function() name = tostring(s.Name or "?") end)
            lines[#lines + 1] = string.format(
              "%d\t%s\t%s\t%d",
              i, trunc_str(name, 120), st_size_str(s), st_elem_count(s))
          end
        end
      end
      return table.concat(lines, "\n")
    end)
    local data, err = ok_data(packed)
    if not data then return err end
    return fit_response(data)

  elseif cmd:match("^stFind%s+(.+)$") then
    local name = cmd:match("^stFind%s+(.+)$")
    name = (name or ""):match("^%s*(.-)%s*$") or ""
    if name == "" then return "ERROR: EMPTY_NAME" end
    local packed = sync_call(function()
      local s, idx = st_find_by_name(name)
      if not s then return "ERROR: NOT_FOUND: " .. scrub(name) end
      return string.format(
        "OK NAME=%s IDX=%d SIZE=%s ELEMS=%d",
        scrub(tostring(s.Name or name)), idx, st_size_str(s), st_elem_count(s))
    end)
    local data, err = ok_data(packed)
    if not data then return err end
    return fit_response(data)

  -- stGet <name>  OR  stGet <name> <elemOff> <elemLimit>
  -- Prefer exact full string as name; if NOT_FOUND and rest ends with two ints, split for pagination.
  elseif cmd:match("^stGet%s+(.+)$") then
    local rest = cmd:match("^stGet%s+(.+)$") or ""
    rest = rest:match("^%s*(.-)%s*$") or rest
    if rest == "" then return "ERROR: EMPTY_NAME" end
    local packed = sync_call(function()
      local function try_name(nm, eoff, elim)
        local s, idx = st_find_by_name(nm)
        if not s then return nil end
        local lines, total = st_element_lines(s, eoff, elim)
        local hdr = string.format(
          "OK NAME=%s IDX=%d SIZE=%s ELEMS=%d ELEMOFF=%d ELEMLIMIT=%d",
          scrub(tostring(s.Name or nm)), idx or -1, st_size_str(s), total, eoff, elim)
        return hdr .. "\n" .. table.concat(lines, "\n")
      end
      local r = try_name(rest, 0, DEFAULT_ST_ELEM_LIMIT)
      if r then return r end
      local nm, a, b = rest:match("^(.-)%s+(%d+)%s+(%d+)$")
      if nm then
        nm = nm:match("^%s*(.-)%s*$") or nm
        if nm ~= "" then
          r = try_name(nm, tonumber(a) or 0, tonumber(b) or DEFAULT_ST_ELEM_LIMIT)
          if r then return r end
        end
      end
      return "ERROR: NOT_FOUND: " .. scrub(rest)
    end)
    local data, err = ok_data(packed)
    if not data then return err end
    return fit_response(data)

  -- T06/T06b: structure seed + clone / edit (empty-list crash + save-before-rename)
  elseif cmd == "stEnsureSeed" or cmd:match("^stEnsureSeed%s*$") then
    local packed = sync_call(function()
      local ok, st, n = st_ensure_seed(true)  -- force placeholder if missing
      if not ok then
        return "ERROR: SEED_FAILED: " .. scrub(tostring(st))
      end
      return string.format(
        "OK SEED=%s STATUS=%s stCount=%d NAME=%s",
        (st == "present" or st == "legacy" or st == "created") and "1" or "0",
        scrub(tostring(st)), n or st_count(), scrub(ST_PLACEHOLDER_NAME))
    end)
    local data, err = ok_data(packed)
    if not data then return err end
    return data

  elseif cmd:match("^stClone%s+(.+)$") then
    local rest = cmd:match("^stClone%s+(.+)$") or ""
    rest = rest:match("^%s*(.-)%s*$") or rest
    if rest == "" then return "ERROR: EMPTY_NAME" end
    local packed = sync_call(function()
      local src, dst, perr = st_split_two_names(rest, true)
      if perr == "EMPTY" or not src or not dst then
        return "ERROR: USAGE: stClone <src> <dst>  (or src -> dst / src|dst)"
      end
      if perr == "NEED_TWO_NAMES" then
        return "ERROR: USAGE: stClone <src> <dst>"
      end
      return st_clone_structure(src, dst)
    end)
    local data, err = ok_data(packed)
    if not data then return err end
    return fit_response(data)

  elseif cmd:match("^stBegin%s+(.+)$") then
    local name = (cmd:match("^stBegin%s+(.+)$") or ""):match("^%s*(.-)%s*$") or ""
    if name == "" then return "ERROR: EMPTY_NAME" end
    local packed = sync_call(function()
      if st_is_protected_name(name) then
        return "ERROR: PROTECTED: " .. scrub(name)
      end
      local s = st_find_by_name(name)
      if not s then return "ERROR: NOT_FOUND: " .. scrub(name) end
      local warn = ""
      if _G._ue_st_updating[name] then
        warn = " WARN=ALREADY_BEGIN"
      end
      pcall(function() s.beginUpdate() end)
      _G._ue_st_updating[name] = true
      return string.format("OK NAME=%s BEGIN=1%s", scrub(tostring(s.Name or name)), warn)
    end)
    local data, err = ok_data(packed)
    if not data then return err end
    return data

  elseif cmd:match("^stEnd%s+(.+)$") then
    local name = (cmd:match("^stEnd%s+(.+)$") or ""):match("^%s*(.-)%s*$") or ""
    if name == "" then return "ERROR: EMPTY_NAME" end
    local packed = sync_call(function()
      local s = st_find_by_name(name)
      if not s then return "ERROR: NOT_FOUND: " .. scrub(name) end
      local warn = ""
      if not _G._ue_st_updating[name] then
        warn = " WARN=NO_BEGIN"
      end
      st_commit(s, name)
      return string.format(
        "OK NAME=%s BEGIN=0 ELEMS=%d COMMITTED=1%s",
        scrub(tostring(s.Name or name)), st_elem_count(s), warn)
    end)
    local data, err = ok_data(packed)
    if not data then return err end
    return data

  -- stUpsertElem: preferred pipe form name|off|elemName|vtype|[bytes]|[child]|[cstart]
  -- Space form: <structName...> <offHex> <elemName> <vtypeInt> [byteSize] [childName] [childStart]
  elseif cmd:match("^stUpsertElem%s+(.+)$") then
    local rest = (cmd:match("^stUpsertElem%s+(.+)$") or ""):match("^%s*(.-)%s*$") or ""
    if rest == "" then return "ERROR: EMPTY" end
    local packed = sync_call(function()
      local sname, off, ename, vtype, bsz, child, cstart
      if rest:find("|", 1, true) then
        local fields = {}
        for part in (rest .. "|"):gmatch("(.-)|") do
          fields[#fields + 1] = part
        end
        -- allow trailing empties; need at least 4: name, off, elemName, vtype
        while #fields > 0 and fields[#fields] == "" and #fields > 4 do
          fields[#fields] = nil
        end
        if #fields < 4 then
          return "ERROR: USAGE: stUpsertElem name|off|elemName|vtype|[bytes]|[child]|[cstart]"
        end
        sname = fields[1]:match("^%s*(.-)%s*$") or fields[1]
        off = tonumber(fields[2]:gsub("^0[xX]", ""), 16) or tonumber(fields[2])
        ename = fields[3]
        vtype = tonumber(fields[4])
        if fields[5] and fields[5] ~= "" then bsz = tonumber(fields[5]) end
        if fields[6] ~= nil then child = fields[6] end
        if fields[7] and fields[7] ~= "" then cstart = tonumber(fields[7]) end
      else
        -- Longest existing structure name as prefix
        local parts = {}
        for w in rest:gmatch("%S+") do parts[#parts + 1] = w end
        if #parts < 4 then
          return "ERROR: USAGE: stUpsertElem name off elemName vtype [bytes [child [cstart]]]"
        end
        local found_i = nil
        for i = #parts - 3, 1, -1 do
          local cand = table.concat(parts, " ", 1, i)
          if st_find_by_name(cand) then found_i = i; break end
        end
        if not found_i then
          -- assume first token is name
          found_i = 1
        end
        sname = table.concat(parts, " ", 1, found_i)
        local tail = {}
        for i = found_i + 1, #parts do tail[#tail + 1] = parts[i] end
        if #tail < 3 then
          return "ERROR: USAGE: stUpsertElem name off elemName vtype ..."
        end
        off = tonumber(tail[1]:gsub("^0[xX]", ""), 16) or tonumber(tail[1])
        -- Remaining: elemName (possibly multi) then vtype int then optional
        -- Require vtype as last required: if #tail==3: name off ename vtype
        -- if more: last numeric tokens are cstart/bsz/vtype
        -- Simple: elemName is tail[2], vtype=tail[3], optional tail[4]=bsz, tail[5]=child, tail[6]=cstart
        ename = tail[2]
        vtype = tonumber(tail[3])
        if tail[4] then bsz = tonumber(tail[4]) end
        if tail[5] then child = tail[5] end
        if tail[6] then cstart = tonumber(tail[6]) end
      end
      if not sname or sname == "" then return "ERROR: EMPTY_NAME" end
      if off == nil then return "ERROR: BAD_OFFSET" end
      if vtype == nil then return "ERROR: BAD_VTYPE" end
      if st_is_protected_name(sname) then
        return "ERROR: PROTECTED: " .. scrub(sname)
      end
      -- Ensure global list never empty before mutating (dissect crash)
      st_ensure_seed(false)
      local s = st_find_by_name(sname)
      if not s then return "ERROR: NOT_FOUND: " .. scrub(sname) end
      local e = st_elem_at_offset(s, off)
      local action
      if e then
        action = "update"
      else
        e = s.addElement()
        if not e then return "ERROR: ADD_ELEMENT_FAILED" end
        pcall(function() e.Offset = off end)
        action = "insert"
      end
      local ferr = st_apply_elem_fields(e, ename, vtype, bsz, child, cstart)
      if ferr then return ferr end
      return string.format(
        "OK NAME=%s OFF=%X ACTION=%s VTYPE=%s",
        scrub(tostring(s.Name or sname)), off, action, tostring(vtype))
    end)
    local data, err = ok_data(packed)
    if not data then return err end
    return fit_response(data)

  elseif cmd:match("^stClearElements%s+(.+)$") then
    local name = (cmd:match("^stClearElements%s+(.+)$") or ""):match("^%s*(.-)%s*$") or ""
    if name == "" then return "ERROR: EMPTY_NAME" end
    local packed = sync_call(function()
      if st_is_protected_name(name) then
        return "ERROR: PROTECTED: " .. scrub(name)
      end
      local s = st_find_by_name(name)
      if not s then return "ERROR: NOT_FOUND: " .. scrub(name) end
      return st_clear_elements(s, name)
    end)
    local data, err = ok_data(packed)
    if not data then return err end
    return fit_response(data)

  elseif cmd:match("^stSetName%s+(.+)$") then
    local rest = (cmd:match("^stSetName%s+(.+)$") or ""):match("^%s*(.-)%s*$") or ""
    if rest == "" then return "ERROR: EMPTY_NAME" end
    local packed = sync_call(function()
      local oldn, newn, perr = st_split_two_names(rest, true)
      if not oldn or not newn then
        return "ERROR: USAGE: stSetName <old> <new>  (or old -> new / old|new)"
      end
      -- Require stEnd / commit before rename (cannot rename structure while editing)
      return st_set_name_safe(oldn, newn)
    end)
    local data, err = ok_data(packed)
    if not data then return err end
    return fit_response(data)

  elseif cmd:match("^readByte (%x+)$") then
    local ahex = cmd:match("^readByte (%x+)$")
    local addr = tonumber(ahex, 16)
    if not addr then return "ERROR: BAD_ADDR" end
    local ok, val = pcall(readByte, addr)
    if ok and val then
      return string.format("%02X", val)
    else
      return "ERROR: readByte failed at " .. string.format("%X", addr)
    end
  elseif cmd:match("^readBytes (%x+) (%d+)$") then
    -- CRITICAL: do not tonumber(match(...), 16) when match returns 2 values —
    -- the 2nd capture becomes tonumber's base → "base out of range" / CE range error.
    local ahex, szs = cmd:match("^readBytes (%x+) (%d+)$")
    local addr = tonumber(ahex, 16)
    local size = tonumber(szs)
    if not addr then return "ERROR: BAD_ADDR" end
    if not size or size < 1 then return "ERROR: BAD_SIZE" end
    if size > 4096 then size = 4096 end  -- hard cap; prevents huge native reads
    local ok, bytes = pcall(readBytes, addr, size, true)
    if ok and bytes then
      return fit_response(bytes_to_hex(bytes))
    else
      return "ERROR: Failed to read memory at " .. string.format("%X", addr)
    end
  elseif cmd:match("^writeBytes (%x+) ([0-9A-Fa-f%s]+)$") then
    local ahex, hex = cmd:match("^writeBytes (%x+) ([0-9A-Fa-f%s]+)$")
    local addr = tonumber(ahex, 16)
    if not addr then return "ERROR: BAD_ADDR" end
    local t = hex_to_table(hex)
    if not t or #t == 0 then
      return "ERROR: Invalid hex data"
    end
    if #t > 4096 then return "ERROR: WRITE_TOO_LARGE" end
    local ok, n = pcall(writeBytes, addr, t)
    if ok and n and n > 0 then
      return string.format("OK: Wrote %d bytes to %X", n, addr)
    else
      return "ERROR: writeBytes failed"
    end
  elseif cmd:match("^readQword (%x+)$") then
    local ahex = cmd:match("^readQword (%x+)$")
    local addr = tonumber(ahex, 16)
    if not addr then return "ERROR: BAD_ADDR" end
    local ok, val = pcall(readQword, addr)
    if ok and val then
      return string.format("%X", val)
    else
      return "ERROR: readQword failed at " .. string.format("%X", addr)
    end
  elseif cmd:match("^readDword (%x+)$") then
    local ahex = cmd:match("^readDword (%x+)$")
    local addr = tonumber(ahex, 16)
    if not addr then return "ERROR: BAD_ADDR" end
    local ok, val = pcall(readInteger, addr)
    if ok and val then
      return string.format("%X", val)
    else
      return "ERROR: readInteger failed at " .. string.format("%X", addr)
    end
  elseif cmd:match("^readString (%x+) (%d+)$") then
    local ahex, mxs = cmd:match("^readString (%x+) (%d+)$")
    local addr = tonumber(ahex, 16)
    local maxlen = tonumber(mxs)
    if not addr then return "ERROR: BAD_ADDR" end
    if not maxlen or maxlen < 1 then return "ERROR: BAD_SIZE" end
    if maxlen > 4096 then maxlen = 4096 end
    local ok, s = pcall(readString, addr, maxlen)
    if ok and s then
      return fit_response(s)
    else
      return "ERROR: readString failed"
    end
  elseif cmd:match("^getAddress (.+)$") then
    local name = cmd:match("^getAddress (.+)$")
    local addr = getAddressSafe(name)
    if addr then
      return string.format("%X", addr)
    else
      return "ERROR: Symbol not found: " .. name
    end
  elseif cmd:match("^resolveSymbol (.+)$") then
    local sym = cmd:match("^resolveSymbol (.+)$")
    local addr = getAddressSafe(sym)
    if addr then
      return string.format("%X", addr)
    else
      return "ERROR: Symbol not found: " .. sym
    end

  -- T11f: thin symbol helpers
  elseif cmd:match("^symGet%s+(.+)$") then
    local name = (cmd:match("^symGet%s+(.+)$") or ""):match("^%s*(.-)%s*$") or ""
    if name == "" then return "ERROR: EMPTY_NAME" end
    local addr = getAddressSafe(name)
    if addr and addr ~= 0 then
      return string.format("OK NAME=%s ADDR=%X", scrub(name), addr)
    end
    return "ERROR: NOT_FOUND: " .. scrub(name)

  elseif cmd:match("^symSet%s+(.+)$") then
    local rest = (cmd:match("^symSet%s+(.+)$") or ""):match("^%s*(.-)%s*$") or ""
    -- symSet <name> <addrHexOrExpr> [donotsave=0|1]
    local name, addrpart, dsave = rest:match("^(%S+)%s+(%S+)%s+(%d+)$")
    if not name then
      name, addrpart = rest:match("^(%S+)%s+(.+)$")
      dsave = "0"
    end
    if not name or not addrpart then
      return "ERROR: USAGE: symSet <name> <addrHexOrExpr> [donotsave]"
    end
    addrpart = addrpart:match("^%s*(.-)%s*$") or addrpart
    local donotsave = (tonumber(dsave) or 0) ~= 0
    local addr = tonumber(addrpart, 16)
    if not addr then
      addr = getAddressSafe(addrpart)
    end
    if not addr or addr == 0 then
      return "ERROR: BAD_ADDR: " .. scrub(addrpart)
    end
    if type(registerSymbol) ~= "function" then
      return "ERROR: registerSymbol unavailable"
    end
    local ok, err = pcall(function()
      -- CE: registerSymbol(name, address, donotsave optional)
      if donotsave then
        registerSymbol(name, addr, true)
      else
        registerSymbol(name, addr)
      end
    end)
    if not ok then return "ERROR: SYMSET: " .. tostring(err) end
    return string.format(
      "OK NAME=%s ADDR=%X DONOTSAVE=%d", scrub(name), addr, donotsave and 1 or 0)
  elseif cmd:match("^enumModules$") then
    local ok, list = pcall(enumModules)
    if not ok or not list then return "ERROR: No module list available" end
    local lines = {}
    local n = 0
    pcall(function()
      for i, m in ipairs(list) do
        if m and m.Address and m.Name then
          lines[#lines + 1] = string.format("%X:%s", m.Address, tostring(m.Name))
          n = n + 1
          if n >= 500 then break end
        end
      end
    end)
    return fit_response(table.concat(lines, "\n"))

  -- Allow CE wildcards: ** or * in pattern (T00: old regex rejected them as Unknown command)
  elseif cmd:match("^AOBScan%s+(.+)$") then
    local pattern = cmd:match("^AOBScan%s+(.+)$")
    pattern = pattern:match("^%s*(.-)%s*$") or pattern
    if pattern == "" then
      return "ERROR: Empty AOB pattern"
    end
    local ok, list = pcall(AOBScan, pattern)
    if not ok then
      return "ERROR: AOBScan exception: " .. scrub(tostring(list))
    end
    if not list then return "ERROR: AOBScan returned nothing" end
    local result = ""
    pcall(function() result = list.Text or "" end)
    pcall(function() list.destroy() end)
    if result == "" then return "ERROR: AOBScan returned nothing" end
    return fit_response(result)

  -- Grouped / structure scan (CE groupscancommandparser.pas). Runs on main
  -- thread: createMemScan from the pipe thread is unsafe (see skill).
  -- Hit address = start of the group block (first element). Cap returned hits.
  elseif cmd:match("^[Gg]roup[Ss]can%s+(.+)$") then
    local gscmd = cmd:match("^[Gg]roup[Ss]can%s+(.+)$")
    gscmd = (gscmd and gscmd:match("^%s*(.-)%s*$")) or ""
    if gscmd == "" then
      return "ERROR: USAGE: GroupScan <command>  e.g. F:0.34 F:0.34 W:16 F:0.1 F:0.1 W:224 F:0.25 F:0.25"
    end
    local maxHits = 200
    local packed = sync_call(function()
      if type(createMemScan) ~= "function" then
        error("createMemScan not available")
      end
      local ms = createMemScan()
      if not ms then error("createMemScan returned nil") end
      local fl = createFoundList(ms)
      -- soExactValue=1, vtGrouped=14, rtRounded=0, fsmAligned=1
      -- firstScan(scanOpt, vt, round, in1, in2, start, stop, prot, alignType, alignParam, hex, notBin, uni, case)
      ms.firstScan(1, 14, 0, gscmd, "", 0, 0x7FFFFFFFFFFFFFFF,
        "+W", 1, "4", false, true, false, false)
      if type(ms.waitTillDone) == "function" then
        ms.waitTillDone()
      end
      fl.initialize()
      local count = fl.Count or 0
      local lines = { "COUNT=" .. tostring(count) }
      local n = math.min(count, maxHits)
      for i = 0, n - 1 do
        local a = fl.Address[i]
        if a == nil and type(fl.getAddress) == "function" then
          a = fl.getAddress(i)
        end
        lines[#lines + 1] = tostring(a)
      end
      if count > maxHits then
        lines[#lines + 1] = string.format("TRUNCATED maxHits=%d", maxHits)
      end
      pcall(function() fl.deinitialize() end)
      pcall(function() fl.destroy() end)
      pcall(function() ms.destroy() end)
      return table.concat(lines, "\n")
    end)
    local data, err = ok_data(packed)
    if not data then return err end
    return fit_response(tostring(data))

  elseif cmd:match("^runScriptSafe%s+(.+)$") then
    local code = cmd:match("^runScriptSafe%s+(.+)$")
    return run_script_body(code, true)

  elseif cmd:match("^runScript (.+)$") then
    local code = cmd:match("^runScript (.+)$")
    return run_script_body(code, false)

  elseif cmd == "close" then
    return "BYE"
  end
  return "ERROR: Unknown command: " .. (cmd:match("^(%S+)") or "")
end

-- Expose helpers for later tasks / advanced runScript (optional)
_G._ue_sync_call = sync_call
_G._ue_al_find_by_id = al_find_by_id
_G._ue_st_find_by_name = st_find_by_name
_G._ue_st_clone_structure = st_clone_structure
_G._ue_st_ensure_seed = st_ensure_seed
_G._ue_st_set_name_safe = st_set_name_safe
_G._ue_ST_PLACEHOLDER_NAME = ST_PLACEHOLDER_NAME
_G._ue_scrub = scrub
_G._ue_fit_response = fit_response
_G._ue_MAX_RESP = MAX_RESP

-- Start server in background thread via createThread (CE UI stays responsive)
if _G._server_thread then
  print("UEScanServer is already running.")
  print("Close the Lua Engine tab to stop, then re-run to restart.")
else
  _G._server_thread = createThread(function(t)
    t.Name = "UEScanServer"

    print("[server] Background thread started " .. VERSION)
    while not t.Terminated do
      print("[server] Creating pipe instance...")
      local pipe = createPipe(PIPE_NAME, PIPE_BUFFER, PIPE_BUFFER)
      if not pipe or not pipe.valid then
        print("[server] createPipe FAILED, retrying in 1s")
        _G._server_error = "createPipe failed, retrying in 1s"
        sleep(1000)
      else
        print("[server] Pipe created, waiting for client...")
        _G._server_error = nil
        pipe.acceptConnection()
        print("[server] Client connected!")
        local seq = 0
        while pipe.connected and not t.Terminated do
          local cmd = read_length_prefixed(pipe)
          if not cmd then
            print("[server] Client disconnected (read returned nil)")
            break
          end
          seq = seq + 1
          local verb = cmd:match("^(%S+)") or cmd
          local preview = cmd_preview(cmd, 240)
          -- Print BEFORE executing. If the Lua thread dies mid-handler, the last
          -- console line is this EXEC start (not just the verb).
          print(string.format("[server] EXEC start #%d %s | %s", seq, verb, preview))
          local t0 = 0
          pcall(function()
            if type(getTickCount) == "function" then t0 = getTickCount() end
          end)
          local ok, resp = pcall(process_command, cmd)
          local t1 = t0
          pcall(function()
            if type(getTickCount) == "function" then t1 = getTickCount() end
          end)
          local ms = (t1 and t0) and (t1 - t0) or -1
          local out
          if ok then
            out = resp
            local out_preview = scrub(tostring(out or "")):gsub("[\r\n]+", " ")
            if #out_preview > 100 then out_preview = out_preview:sub(1, 100) .. "…" end
            print(string.format(
              "[server] EXEC done  #%d ok ms=%s out=%s",
              seq, tostring(ms), out_preview))
          else
            out = "ERROR: " .. tostring(resp)
            -- pcall caught a Lua error — server thread should survive
            print(string.format(
              "[server] EXEC fail  #%d ms=%s err=%s",
              seq, tostring(ms), scrub(tostring(resp)):sub(1, 200)))
          end
          pcall(function()
            audit_push(
              verb,
              preview:sub(1, 120),
              tostring(out):match("^(.-)[\r\n]") or tostring(out):sub(1, 80))
          end)
          local wok, werr = pcall(write_length_prefixed, pipe, out)
          if not wok then
            print("[server] WRITE fail #" .. tostring(seq) .. " " .. scrub(tostring(werr)))
            break
          end
          if cmd == "close" then break end
        end
        print("[server] Destroying pipe...")
        pipe.destroy()
        print("[server] Pipe destroyed")
      end
    end
    print("[server] Thread terminating")
    _G._server_thread = nil
  end)
end
