local fs=require("filesystem")
local component=require("component")
local hardware=require("core.hardware")
local config=require("core.config")
local storage=require("core.storage")
local updater=require("core.updater")
local M={}
local function ask(label,default)
  io.write(label..(default and (" ["..default.."]") or "")..": ")
  io.stdout:flush()
  -- OpenOS cursor echo can retain password/newline options between reads.
  -- Create a fresh unmasked cursor and own the newline for every prompt.
  local line=require("term").read({dobreak=false})
  io.write("\n")
  assert(line,"Installation cancelled")
  line=line:gsub("[\r\n]+$","")
  if line=="" then return default or "" end
  return line
end
local function selectHardware(kind,configured)
  local value,err=hardware.select(kind,configured)
  if value then return value.address end
  print(err)
  local addresses={}
  for address in component.list(kind,true) do addresses[#addresses+1]=address; print(#addresses..". "..address) end
  assert(#addresses>0,"Required component missing: "..kind)
  return assert(addresses[tonumber(ask("Select "..kind))],"Invalid component selection")
end
function M.main(args,embedded)
  local service=package.loaded["factoryos.service"]
  assert(not service or (not service.running and (not service.thread or service.thread:status()=="dead")),"Stop FactoryOS before installing")
  print("=================================\n       FACTORY OS INSTALLER\n=================================")
  print("1. Factory Server\n2. Main Display (8x5)\n3. Side Display (4x5)")
  local role=({["1"]="server",["2"]="main",["3"]="side"})[ask("Select installation")]
  assert(role,"Select 1, 2 or 3")
  local old=config.load()
  local c=old or config.defaults(role)
  c.role=role
  c.modem=selectHardware("modem",c.modem)
  c.gpu=selectHardware("gpu",c.gpu)
  c.screen=selectHardware("screen",c.screen)
  print("Local modem: "..c.modem)
  print("No password required. Displays pair by modem address.")
  if role=="server" then
    if not component.isAvailable("internet") then print("Warning: Internet Card absent. Offline installation works; online updates unavailable.") end
    local main=ask("Main display modem address (blank = configure later)","")
    local side=ask("Side display modem address (blank = configure later)","")
    if main~="" then c.allowedClients[main]="main" end
    if side~="" then c.allowedClients[side]="side" end
  else c.serverAddress=ask("Server modem address (blank = automatic discovery)",c.serverAddress) end
  assert(config.validate(c))
  local hw,err=hardware.check(c); assert(hw,err)
  print("GPU/screen: "..hw.maxWidth.."x"..hw.maxHeight.." characters")
  print("Hardware OK. Runtime registration test: start server and both displays after setup.")
  local get
  if embedded then
    get=function(path,limit) local data=assert(embedded[path],"Missing offline file: "..path); assert(#data<=limit,"Offline file size limit"); return data end
  elseif args[1]=="--local" then
    local path=assert(args[2],"Usage: install.lua --local /mnt/DISK/factoryos")
    get=function(file,limit) return assert(storage.read(fs.concat(path,file),limit)) end
  else
    local base=args[1] or ask("Real HTTPS repository base URL",c.updateBase)
    c.updateBase=base; get=updater.source(base)
  end
  local manifest=updater.stage(get)
  assert(config.save(c))
  assert(storage.atomic("/bin/factoryos.lua",updater.launcher))
  updater.activate(manifest)
  -- Read back installed settings and selected release before declaring installation complete.
  assert(config.load())
  assert(storage.read(updater.root.."/active",100)==manifest.release.."\n")
  print("FactoryOS "..manifest.release.." installed as "..role)
  print("Start: factoryos start --foreground\nBackground: factoryos start\nInspect: factoryos status / doctor / logs")
  print("Stop: factoryos stop\nUpdate: factoryos stop, then factoryos update HTTPS_BASE\nRollback: factoryos rollback")
  print("Network and real AE2 behavior still require in-game acceptance tests (docs/testing.md).")
end
return M
