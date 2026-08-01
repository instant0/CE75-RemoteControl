local PIPE_NAME = "UEScanRemote"
local PIPE_BUFFER = 65536
local VERSION = "ce-server v1.2 (CE 7.5 al-inventory)"
local MAX_RESP = 48000
-- CE 7.5: vtAutoAssembler observed as Type=11 on DL2 tables (T00); also accept 8.
local VT_AUTO_ASSEMBLER_A = 11
local VT_AUTO_ASSEMBLER_B = 8

local HEX = "0123456789ABCDEF"

-- Staging for future script chunk upload (T04); reserved namespace.
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
      "readByte <hexaddr>", "readBytes <hexaddr> <size>",
      "readQword <hexaddr>", "readDword <hexaddr>", "readString <hexaddr> <maxlen>",
      "writeBytes <hexaddr> <hex>",
      "getAddress <symbol>", "resolveSymbol <name>",
      "AOBScan <hexpattern with optional ** wildcards>",
      "enumModules", "runScript <code>", "close"
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
      local cev = "?"
      if type(getCEVersion) == "function" then
        local okv, v = pcall(getCEVersion)
        if okv and v then cev = tostring(v) end
      end
      return string.format(
        "OK process=%s pid=%s alCount=%d stCount=%d ceVersion=%s server=%s",
        scrub(proc), scrub(pid), alCount, stCount, scrub(cev), scrub(VERSION))
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

  elseif cmd:match("^readByte (%x+)$") then
    local addr = tonumber(cmd:match("^readByte (%x+)$"), 16)
    local val = readByte(addr)
    if val then
      return string.format("%02X", val)
    else
      return "ERROR: readByte failed at " .. string.format("%X", addr)
    end
  elseif cmd:match("^readBytes (%x+) (%d+)$") then
    local addr = tonumber(cmd:match("^readBytes (%x+) (%d+)$"), 16)
    local size = tonumber(cmd:match("^readBytes (%x+) (%d+)$"))
    local bytes = readBytes(addr, size, true)
    if bytes then
      return fit_response(bytes_to_hex(bytes))
    else
      return "ERROR: Failed to read memory at " .. string.format("%X", addr)
    end
  elseif cmd:match("^writeBytes (%x+) ([0-9A-Fa-f%s]+)$") then
    local addr = tonumber(cmd:match("^writeBytes (%x+) ([0-9A-Fa-f%s]+)$"), 16)
    local hex = cmd:match("^writeBytes (%x+) ([0-9A-Fa-f%s]+)$")
    local t = hex_to_table(hex)
    if not t or #t == 0 then
      return "ERROR: Invalid hex data"
    end
    local n = writeBytes(addr, t)
    if n and n > 0 then
      return string.format("OK: Wrote %d bytes to %X", n, addr)
    else
      return "ERROR: writeBytes failed"
    end
  elseif cmd:match("^readQword (%x+)$") then
    local addr = tonumber(cmd:match("^readQword (%x+)$"), 16)
    local val = readQword(addr)
    if val then
      return string.format("%X", val)
    else
      return "ERROR: readQword failed at " .. string.format("%X", addr)
    end
  elseif cmd:match("^readDword (%x+)$") then
    local addr = tonumber(cmd:match("^readDword (%x+)$"), 16)
    local val = readInteger(addr)
    if val then
      return string.format("%X", val)
    else
      return "ERROR: readInteger failed at " .. string.format("%X", addr)
    end
  elseif cmd:match("^readString (%x+) (%d+)$") then
    local addr = tonumber(cmd:match("^readString (%x+) (%d+)$"), 16)
    local maxlen = tonumber(cmd:match("^readString (%x+) (%d+)$"))
    local s = readString(addr, maxlen)
    if s then
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
  elseif cmd:match("^enumModules$") then
    local list = enumModules()
    if not list then return "ERROR: No module list available" end
    local lines = {}
    for i, m in ipairs(list) do
      lines[#lines + 1] = string.format("%X:%s", m.Address, m.Name)
    end
    return fit_response(table.concat(lines, "\n"))

  -- Allow CE wildcards: ** or * in pattern (T00: old regex rejected them as Unknown command)
  elseif cmd:match("^AOBScan%s+(.+)$") then
    local pattern = cmd:match("^AOBScan%s+(.+)$")
    pattern = pattern:match("^%s*(.-)%s*$") or pattern
    if pattern == "" then
      return "ERROR: Empty AOB pattern"
    end
    local list = AOBScan(pattern)
    if not list then return "ERROR: AOBScan returned nothing" end
    local result = list.Text
    list.destroy()
    return fit_response(result)

  elseif cmd:match("^runScript (.+)$") then
    local code = cmd:match("^runScript (.+)$")
    if code and #code > 0 then
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
          return "ERROR: Compile error: " .. err
        end
      end
    end
    return "ERROR: Empty script"
  elseif cmd == "close" then
    return "BYE"
  end
  return "ERROR: Unknown command: " .. (cmd:match("^(%S+)") or "")
end

-- Expose helpers for later tasks / advanced runScript (optional)
_G._ue_sync_call = sync_call
_G._ue_al_find_by_id = al_find_by_id
_G._ue_st_find_by_name = st_find_by_name
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
        while pipe.connected and not t.Terminated do
          local cmd = read_length_prefixed(pipe)
          if not cmd then
            print("[server] Client disconnected (read returned nil)")
            break
          end
          -- Log verb only (never full AA scripts)
          print("[server] Received: " .. (cmd:match("^(%S+)") or cmd))
          local ok, resp = pcall(process_command, cmd)
          write_length_prefixed(pipe, ok and resp or "ERROR: " .. tostring(resp))
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
