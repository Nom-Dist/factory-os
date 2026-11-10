local fs=require("filesystem")
local computer=require("computer")
local storage=require("core.storage")
local M={path="/var/log/factoryos.log"}
function M.log(level,message)
  -- Never pass raw network frames/configs (they can contain credentials).
  pcall(function()
    fs.makeDirectory("/var/log")
    if fs.size(M.path)>65536 then
      if fs.exists(M.path..".1") then fs.remove(M.path..".1") end
      assert(fs.rename(M.path,M.path..".1"))
    end
    local f=assert(io.open(M.path,"a"))
    f:write(string.format("[%8.1f] %-5s %s\n",computer.uptime(),level,tostring(message):gsub("[\r\n]"," "):sub(1,500)))
    f:close()
  end)
end
function M.read() return storage.read(M.path,131072) or "No logs." end
return M
