local fs=require("filesystem")
local component=require("component")
local computer=require("computer")
local uuid=require("uuid")
local codec=require("core.codec")
local crypto=require("core.crypto")
local storage=require("core.storage")
local M={root="/usr/lib/factoryos"}
M.launcher=[=[local root="/usr/lib/factoryos"
local f=io.open(root.."/active","r") or io.open(root.."/active.bak","r")
assert(f,"FactoryOS not installed")
local v=f:read("*l"); f:close()
assert(v and v:match("^[%w%._%-]+$") and not v:find("..",1,true),"Invalid active release")
return assert(loadfile(root.."/releases/"..v.."/boot.lua"))(root,{...})
]=]
function M.validate(manifest)
  assert(type(manifest)=="table" and manifest.schema==1,"Invalid manifest schema")
  local v=manifest.release
  assert(type(v)=="string" and #v<=80 and v:match("^[%w%._%-]+$") and not v:find("..",1,true),"Invalid release")
  assert(type(manifest.files)=="table" and #manifest.files>0 and #manifest.files<=128,"Invalid file count")
  local paths,total={},0
  for _,file in ipairs(manifest.files) do
    assert(type(file)=="table" and type(file.path)=="string" and #file.path<=160,"Invalid file entry")
    local path=file.path
    assert(path:match("^[%w_/%-]+%.lua$") and path:sub(1,1)~="/" and not path:find("..",1,true) and not path:find("//",1,true),"Unsafe manifest path")
    assert(not paths[path],"Duplicate manifest path"); paths[path]=true
    assert(type(file.size)=="number" and file.size>=1 and file.size%1==0 and file.size<=65536,"Invalid file size")
    assert(type(file.sha256)=="string" and #file.sha256==64 and file.sha256:match("^[a-f0-9]+$"),"Invalid file hash")
    total=total+file.size
  end
  assert(total<=524288,"Release exceeds memory/disk budget")
  for _,required in ipairs({"boot.lua","core/cli.lua","core/config.lua","core/runtime.lua","core/updater.lua"}) do assert(paths[required],"Incomplete release: "..required) end
  return total
end
function M.fetch(url,limit)
  assert(type(url)=="string" and url:match("^https://[%w%.%-]+/[^%s]*$"),"Use an HTTPS source URL")
  local internet,err=require("core.hardware").select("internet","")
  assert(internet,"Internet Card required for download: "..tostring(err))
  assert(internet.isHttpEnabled(),"HTTP disabled in OpenComputers config")
  local handle,requestError=internet.request(url)
  assert(handle,"HTTP request failed: "..tostring(requestError))
  local deadline=computer.uptime()+25
  local ok,result=xpcall(function()
    while not handle.finishConnect() do
      assert(computer.uptime()<deadline,"HTTP connect timeout"); os.sleep(0.05)
    end
    local code=handle.response()
    assert(code==200,"HTTP status "..tostring(code).." for "..url)
    local chunks,bytes={},0
    while true do
      assert(computer.uptime()<deadline,"HTTP download timeout")
      local data,why=handle.read(4096)
      if data==nil then assert(not why,why); break end
      if #data==0 then os.sleep(0.05)
      else
        bytes=bytes+#data; assert(bytes<=limit,"Download size limit")
        chunks[#chunks+1]=data
      end
    end
    return table.concat(chunks)
  end,debug.traceback)
  handle.close()
  assert(ok,result)
  return result
end
function M.source(base)
  assert(type(base)=="string" and base~="","No update source configured. Supply a real HTTPS repository base or --local PATH.")
  base=base:gsub("/+$","")
  if base:match("^https://") then
    return function(path,limit) return M.fetch(base.."/"..path,limit) end
  end
  error("Updates require HTTPS; offline installer accepts --local PATH")
end
function M.stage(get,root)
  root=root or M.root
  local manifest=assert(codec.decode(get("manifest.dat",65536)),"Cannot decode manifest")
  local bytes=M.validate(manifest)
  assert(storage.mkdir(root.."/releases"))
  local proxy=fs.get(root)
  if proxy and proxy.spaceTotal and proxy.spaceUsed then
    assert(proxy.spaceTotal()-proxy.spaceUsed()>bytes+65536,"Insufficient disk space (old release retained)")
  end
  local release=root.."/releases/"..manifest.release
  local stage=root.."/releases/.stage-"..uuid.next()
  assert(storage.mkdir(stage))
  for i,file in ipairs(manifest.files) do
    io.write(string.format("[%02d/%02d] %s\n",i,#manifest.files,file.path))
    local data=get("src/"..file.path,file.size)
    assert(#data==file.size and crypto.equal(crypto.sha256(data),file.sha256),"Integrity failure: "..file.path)
    assert(storage.write(stage.."/"..file.path,data))
    os.sleep(0)
  end
  assert(storage.write(stage.."/manifest.dat",codec.encode(manifest)))
  if fs.exists(release) then
    -- Immutable existing release must match every downloaded file before reusing it.
    for _,file in ipairs(manifest.files) do
      local data=assert(storage.read(release.."/"..file.path,file.size))
      assert(#data==file.size and crypto.sha256(data)==file.sha256,"Existing release differs; publish a new release ID")
    end
    assert(fs.remove(stage))
  else assert(fs.rename(stage,release)) end
  return manifest
end
function M.activate(manifest,root)
  root=root or M.root
  local old=storage.read(root.."/active",100) or storage.read(root.."/active.bak",100)
  if old and old~=manifest.release.."\n" then assert(storage.atomic(root.."/previous",old)) end
  assert(storage.atomic(root.."/active",manifest.release.."\n"))
end
function M.install(base,cfg,root)
  root=root or M.root
  assert(cfg.role=="server" or component.isAvailable("internet"),"Display needs temporary Internet Card or offline reinstall")
  local manifest=M.stage(M.source(base),root)
  M.activate(manifest,root)
  return manifest
end
function M.rollback(root)
  root=root or M.root
  local previous=assert(storage.read(root.."/previous",100),"No previous release")
  local v=previous:match("^([%w%._%-]+)\n?$")
  assert(v and not v:find("..",1,true),"Invalid rollback pointer")
  local manifest=assert(storage.load(root.."/releases/"..v.."/manifest.dat"))
  M.validate(manifest)
  assert(manifest.release==v,"Rollback manifest mismatch")
  for _,f in ipairs(manifest.files) do
    local data=assert(storage.read(root.."/releases/"..v.."/"..f.path,f.size))
    assert(#data==f.size and crypto.sha256(data)==f.sha256,"Rollback integrity failure")
  end
  M.activate(manifest,root)
end
return M
