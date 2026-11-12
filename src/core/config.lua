local storage=require("core.storage")
local fs=require("filesystem")
local M={path="/etc/factoryos/config.dat"}
function M.defaults(role)
  return {schema=2,role=role or "server",port=34100,strength=64,serverAddress="",
    modem="",gpu="",screen="",allowedClients={},heartbeat=5,offlineAfter=18,poll=10,
    ae2Address="",ae2Enabled=true,updateBase="https://raw.githubusercontent.com/Nom-Dist/factory-os/main",
    autoStart=true,updateAutoCheck=true,updateCheckInterval=900,webEnabled=false,webControl=false,webUrl="",webToken="",webInterval=5}
end
function M.upgrade(c)
  if type(c)=="table" and (c.schema==1 or c.schema==2) then
    c.schema=2; c.key=nil
    if c.autoStart==nil then c.autoStart=true end
    if c.updateAutoCheck==nil then c.updateAutoCheck=true end
    if c.updateCheckInterval==nil then c.updateCheckInterval=900 end
    for _,key in ipairs({"webEnabled","webControl","webUrl","webToken","webInterval"}) do if c[key]==nil then c[key]=M.defaults()[key] end end
    if c.updateBase=="" then c.updateBase=M.defaults().updateBase end
  end
  return c
end
function M.validate(c)
  if type(c)~="table" or c.schema~=2 then return nil,"invalid config schema" end
  if c.role~="server" and c.role~="main" and c.role~="side" then return nil,"invalid role" end
  for _,key in ipairs({"port","strength","heartbeat","offlineAfter","poll"}) do
    local n=c[key]; if type(n)~="number" or n~=n or n==math.huge then return nil,"invalid "..key end
  end
  if c.port%1~=0 or c.port<1 or c.port>65535 then return nil,"invalid port" end
  if c.strength<1 or c.strength>400 or c.heartbeat<2 or c.heartbeat>60 or c.offlineAfter<c.heartbeat*3 or c.offlineAfter>300 or c.poll<5 or c.poll>300 then return nil,"invalid intervals/strength" end
  for _,k in ipairs({"serverAddress","modem","gpu","screen","ae2Address","updateBase"}) do
    if type(c[k])~="string" or #c[k]>512 then return nil,"invalid "..k end
  end
  if type(c.ae2Enabled)~="boolean" then return nil,"invalid feature flags" end
  if type(c.webEnabled)~="boolean" or type(c.webControl)~="boolean" or type(c.webUrl)~="string" or #c.webUrl>512 or
    type(c.webToken)~="string" or #c.webToken>128 or c.webToken:find("[^%w_%-]") or
    type(c.webInterval)~="number" or c.webInterval%1~=0 or c.webInterval<2 or c.webInterval>10 then return nil,"invalid web configuration" end
  if c.webEnabled then
    if c.role~="server" or #c.webToken<32 then return nil,"Web bridge requires server role and a 32+ character token" end
    local authority=c.webUrl:match("^ws://([^/]+)")
    local host,port
    if authority then host,port=authority:match("^([%w%.%-]+):(%d+)$"); host=host or authority:match("^([%w%.%-]+)$") end
    local ws=host and (not port or tonumber(port)>=1 and tonumber(port)<=65535) and not c.webUrl:find("[%s%c#]")
    if not c.webUrl:match("^https://[%w%.%-]+:?%d*/[^%s%c#]*$") and not ws then return nil,"Web URL must be HTTPS uplink or trusted-network ws://" end
  end
  if type(c.autoStart)~="boolean" or type(c.updateAutoCheck)~="boolean" then return nil,"invalid startup/update flags" end
  if type(c.updateCheckInterval)~="number" or c.updateCheckInterval%1~=0 or c.updateCheckInterval<60 or c.updateCheckInterval>86400 then return nil,"invalid update check interval" end
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
  c=M.upgrade(c)
  local valid,why=M.validate(c)
  if valid then return c end
  local backup=M.upgrade(storage.load(M.path..".bak"))
  if M.validate(backup) then return backup,"config invalid; using .bak (original preserved)" end
  return nil,"Config unavailable: "..tostring(err or why)..". Run factoryos config or restore config.dat.bak."
end
function M.save(c)
  c=M.upgrade(c)
  local ok,err=M.validate(c); if not ok then return nil,err end
  if fs.exists(M.path) and not M.validate(M.upgrade(storage.load(M.path))) and M.validate(M.upgrade(storage.load(M.path..".bak"))) then
    if fs.exists(M.path..".corrupt") then assert(fs.remove(M.path..".corrupt")) end
    assert(fs.rename(M.path,M.path..".corrupt"))
  end
  return storage.save(M.path,c)
end
return M
