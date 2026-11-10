local storage=require("core.storage")
local fs=require("filesystem")
local M={path="/etc/factoryos/config.dat"}
function M.defaults(role)
  return {schema=1,role=role or "server",port=34100,strength=64,key="",serverAddress="",
    modem="",gpu="",screen="",allowedClients={},heartbeat=5,offlineAfter=18,poll=10,
    ae2Address="",ae2Enabled=true,updateBase=""}
end
function M.validate(c)
  if type(c)~="table" or c.schema~=1 then return nil,"invalid config schema" end
  if c.role~="server" and c.role~="main" and c.role~="side" then return nil,"invalid role" end
  for _,key in ipairs({"port","strength","heartbeat","offlineAfter","poll"}) do
    local n=c[key]; if type(n)~="number" or n~=n or n==math.huge then return nil,"invalid "..key end
  end
  if c.port%1~=0 or c.port<1 or c.port>65535 then return nil,"invalid port" end
  if c.strength<1 or c.strength>400 or c.heartbeat<2 or c.heartbeat>60 or c.offlineAfter<c.heartbeat*3 or c.offlineAfter>300 or c.poll<5 or c.poll>300 then return nil,"invalid intervals/strength" end
  if type(c.key)~="string" or #c.key<32 or #c.key>256 then return nil,"shared key must have 32..256 characters" end
  for _,k in ipairs({"serverAddress","modem","gpu","screen","ae2Address","updateBase"}) do
    if type(c[k])~="string" or #c[k]>512 then return nil,"invalid "..k end
  end
  if type(c.ae2Enabled)~="boolean" then return nil,"invalid feature flags" end
  if type(c.allowedClients)~="table" then return nil,"invalid client allowlist" end
  local count=0
  for address,role in pairs(c.allowedClients) do
    count=count+1
    if type(address)~="string" or #address<8 or #address>64 or (role~="main" and role~="side") then return nil,"invalid client entry" end
  end
  if count>16 then return nil,"at most 16 clients" end
  return true
end
function M.load()
  local c,err=storage.load(M.path)
  local valid,why=M.validate(c)
  if valid then return c end
  local backup=storage.load(M.path..".bak")
  if M.validate(backup) then return backup,"config invalid; using .bak (original preserved)" end
  return nil,"Config unavailable: "..tostring(err or why)..". Run factoryos config or restore config.dat.bak."
end
function M.save(c)
  local ok,err=M.validate(c); if not ok then return nil,err end
  if fs.exists(M.path) and not M.validate(storage.load(M.path)) and M.validate(storage.load(M.path..".bak")) then
    if fs.exists(M.path..".corrupt") then assert(fs.remove(M.path..".corrupt")) end
    assert(fs.rename(M.path,M.path..".corrupt"))
  end
  return storage.save(M.path,c)
end
return M
