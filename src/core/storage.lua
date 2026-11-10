local fs = require("filesystem")
local codec = require("core.codec")
local M = {}
function M.mkdir(path)
  if fs.exists(path) then
    if fs.isDirectory(path) then return true end
    return nil,"Path is not a directory: "..path
  end
  return fs.makeDirectory(path)
end
function M.read(path, limit)
  local f, err=io.open(path,"rb"); if not f then return nil,err end
  local s=f:read((limit or 65536)+1); f:close()
  if not s then return "" end
  if #s>(limit or 65536) then return nil,"file too large: "..path end
  return s
end
function M.write(path,s)
  local made,why=M.mkdir(fs.path(path)); if not made then return nil,why end
  local f,err=io.open(path,"wb"); if not f then return nil,err end
  local ok,reason=f:write(s)
  -- OpenOS close returns no values; flush must be checked before closing.
  if ok and f.flush then ok,reason=f:flush() end
  local closed,closeErr=pcall(f.close,f)
  if not ok or not closed then return nil,reason or closeErr end
  return true
end
function M.atomic(path,s)
  local ok,err=M.write(path..".tmp",s); if not ok then return nil,err end
  if fs.exists(path) then
    if fs.exists(path..".bak") then assert(fs.remove(path..".bak")) end
    assert(fs.rename(path,path..".bak"))
  end
  ok,err=fs.rename(path..".tmp",path)
  if not ok and fs.exists(path..".bak") then fs.rename(path..".bak",path) end
  return ok,err
end
function M.load(path)
  local s,err=M.read(path); if not s then return nil,err end
  return codec.decode(s)
end
function M.save(path,value) return M.atomic(path,codec.encode(value)) end
return M
