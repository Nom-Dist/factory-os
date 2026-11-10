-- Bounded data-only wire format. Never evaluates Lua, including in config files.
local M = {}
local function finite(n) return n == n and n ~= math.huge and n ~= -math.huge end
function M.encode(value)
  local seen, nodes = {}, 0
  local function enc(v, depth)
    nodes = nodes + 1
    assert(nodes <= 16000 and depth <= 12, "data complexity limit")
    local t = type(v)
    if t == "nil" then return "z" end
    if t == "boolean" then return v and "t" or "f" end
    if t == "string" then return "s" .. #v .. ":" .. v end
    if t == "number" then
      assert(finite(v), "non-finite number")
      local s = string.format("%.17g", v)
      return "n" .. #s .. ":" .. s
    end
    assert(t == "table" and not getmetatable(v) and not seen[v], "unsupported data")
    seen[v] = true
    local keys, out = {}, {}
    for k in pairs(v) do
      assert(type(k) == "string" or (type(k) == "number" and finite(k)), "invalid key")
      keys[#keys + 1] = {key=k, wire=enc(k, depth+1)}
    end
    table.sort(keys, function(a,b) return a.wire < b.wire end)
    out[1] = "m" .. #keys .. ":"
    for _, k in ipairs(keys) do
      out[#out+1], out[#out+2] = k.wire, enc(v[k.key], depth+1)
    end
    seen[v] = nil
    return table.concat(out)
  end
  local s = enc(value, 0)
  assert(#s <= 65536, "data size limit")
  return s
end
function M.decode(s)
  if type(s) ~= "string" or #s > 65536 then return nil, "data size limit" end
  local pos, nodes = 1, 0
  local function length()
    local colon = s:find(":", pos, true)
    assert(colon and colon-pos <= 6, "bad length")
    local digits = s:sub(pos, colon-1)
    assert(digits:match("^%d+$"), "bad length")
    pos = colon+1
    local n = tonumber(digits)
    assert(n <= 65536, "length limit")
    return n
  end
  local function dec(depth)
    nodes = nodes+1
    assert(nodes <= 16000 and depth <= 12, "data complexity limit")
    local tag = s:sub(pos,pos); pos = pos+1
    if tag == "z" then return nil end
    if tag == "t" then return true end
    if tag == "f" then return false end
    if tag == "s" or tag == "n" then
      local n = length()
      assert(pos+n-1 <= #s, "truncated value")
      local v = s:sub(pos,pos+n-1); pos = pos+n
      if tag == "s" then return v end
      assert(v:match("^[%d%.%+%-eE]+$"), "bad number")
      local number = tonumber(v)
      assert(number and finite(number), "bad number")
      return number
    end
    assert(tag == "m", "invalid tag")
    local count, result = length(), {}
    assert(count <= 4000, "table size limit")
    for _ = 1, count do
      local k = dec(depth+1)
      assert(type(k) == "string" or type(k) == "number", "invalid key")
      assert(result[k] == nil, "duplicate key")
      local v = dec(depth+1)
      assert(v ~= nil, "nil table value")
      result[k] = v
    end
    return result
  end
  local ok, result = pcall(dec, 0)
  if not ok then return nil, tostring(result) end
  if pos ~= #s+1 then return nil, "trailing data" end
  return result
end
return M
