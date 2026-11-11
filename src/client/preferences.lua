local storage=require("core.storage")
local fs=require("filesystem")
local M={path="/etc/factoryos/display.dat"}
function M.valid(p)
  if type(p)~="table" or p.schema~=1 or type(p.favorites)~="table" then return false end
  local count=0
  for key,label in pairs(p.favorites) do
    count=count+1
    if count>32 or type(key)~="string" or #key>1024 or type(label)~="string" or #label>160 then return false end
  end
  return true
end
function M.load()
  if not fs.exists(M.path) then return {schema=1,favorites={}} end
  local p=storage.load(M.path)
  if M.valid(p) then return p end
  local backup=storage.load(M.path..".bak")
  if M.valid(backup) then return backup,"Gorunum yedekten acildi" end
  return {schema=1,favorites={}},"Gorunum ayarlari okunamadi"
end
function M.save(p)
  assert(M.valid(p),"Invalid display preferences")
  return storage.save(M.path,p)
end
return M
