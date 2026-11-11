local fs=require("filesystem")
local storage=require("core.storage")
local M={path="/home/.shrc",first="# BEGIN FACTORYOS AUTOSTART",last="# END FACTORYOS AUTOSTART"}
M.launcher="/usr/lib/factoryos/autostart.lua"
M.script=[=[if package.loaded["factoryos.autostart_once"] then return end
package.loaded["factoryos.autostart_once"]=true
local ok,reason=pcall(function() return assert(loadfile("/bin/factoryos.lua"))("start","--foreground") end)
if not ok then io.stderr:write("FactoryOS startup failed: "..tostring(reason).."\n") end
]=]
function M.ensure(enabled)
  if enabled and storage.read(M.launcher)~=M.script then assert(storage.atomic(M.launcher,M.script)) end
  local original=""
  if fs.exists(M.path) then original=assert(storage.read(M.path,65536)) end
  local first=original:find(M.first,1,true)
  local last=original:find(M.last,1,true)
  assert((first==nil)==(last==nil) and (not first or last>first),"Incomplete FactoryOS .shrc block; original preserved")
  local text=original
  if first then
    local finish=last+#M.last
    if text:sub(finish,finish)=="\r" then finish=finish+1 end
    if text:sub(finish,finish)=="\n" then finish=finish+1 end
    text=text:sub(1,first-1)..text:sub(finish)
  end
  if enabled then
    if #text>0 and text:sub(-1)~="\n" then text=text.."\n" end
    text=text..M.first.."\n"..M.launcher.."\n"..M.last.."\n"
  end
  if text~=original then assert(storage.atomic(M.path,text)) end
  return true
end
return M
