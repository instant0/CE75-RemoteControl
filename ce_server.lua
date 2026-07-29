local PIPE_NAME = "UEScanRemote"
local PIPE_BUFFER = 65536
local VERSION = "ce-server v1.0 (CE 7.5)"

local HEX = "0123456789ABCDEF"

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
    return [=[ping|getVersion|help|readByte <hexaddr>|readBytes <hexaddr> <size>|readQword <hexaddr>|readDword <hexaddr>|readString <hexaddr> <maxlen>|writeBytes <hexaddr> <hex>|getAddress <symbol>|resolveSymbol <name>|AOBScan <hexpattern> [prot]|enumModules|runScript <code>|close]=]
  elseif cmd == "getVersion" then
    return VERSION
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
      return bytes_to_hex(bytes)
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
      return s
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
    return table.concat(lines, "\n")
  elseif cmd:match("^AOBScan ([0-9A-Fa-f%s]+)$") then
    local pattern = cmd:match("^AOBScan ([0-9A-Fa-f%s]+)$")
    local list = AOBScan(pattern)
    if not list then return "ERROR: AOBScan returned nothing" end
    local result = list.Text
    list.destroy()
    return result
  elseif cmd:match("^runScript (.+)$") then
    local code = cmd:match("^runScript (.+)$")
    if code and #code > 0 then
      local fn, err = loadstring("return " .. code)
      if fn then
        local ok, result = pcall(fn)
        if ok then
          return tostring(result)
        else
          return "ERROR: " .. tostring(result)
        end
      else
        fn, err = loadstring(code)
        if fn then
          local ok, result = pcall(fn)
          if ok then
            return tostring(result)
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

-- Start server in background thread via createThread (CE UI stays responsive)
if _G._server_thread then
  print("UEScanServer is already running.")
  print("Close the Lua Engine tab to stop, then re-run to restart.")
else
  _G._server_thread = createThread(function(t)
    t.Name = "UEScanServer"

    print("[server] Background thread started")
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
