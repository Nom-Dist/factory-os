local config=require("core.config")
local storage=require("core.storage")
local logger=require("core.logger")
local hardware=require("core.hardware")
local computer=require("computer")
local serialization=require("serialization")
local M={}
local function live()
  local s=package.loaded["factoryos.service"]
  return s and (s.running or (s.thread and s.thread:status()~="dead")),s
end
function M.main(args,root)
  local cmd=args[1] or "status"
  if cmd=="autostart-run" then
    if package.loaded["factoryos.autostart_once"] then return end
    package.loaded["factoryos.autostart_once"]=true
    local c=config.load()
    if c and c.autoStart and not live() then return M.main({"start","--foreground"},root) end
    return
  end
  if cmd=="autostart" then
    assert(not live(),"Stop FactoryOS before changing startup")
    local c=assert(config.load())
    if args[2] then
      assert(args[2]=="enable" or args[2]=="disable","autostart enable|disable")
      c.autoStart=args[2]=="enable"; assert(config.save(c))
    end
    require("core.autostart").ensure(c.autoStart)
    print("Foreground autostart: "..(c.autoStart and "ENABLED" or "DISABLED")); return
  end
  if cmd=="logs" then print(logger.read()); return end
  if cmd=="ae2" then
    assert(not live(),"Stop FactoryOS before AE2 diagnostics")
    local c=assert(config.load())
    assert(c.role=="server","Run AE2 diagnostics on the server computer")
    local count=tonumber(args[2] or "1")
    assert(count and count%1==0 and count>=1 and count<=60,"ae2 [samples: 1..60], interval 10 seconds")
    local ae=require("server.ae2").new(c)
    print("Read-only AE2 diagnostics; configured address: "..(c.ae2Address~="" and c.ae2Address or "automatic"))
    for _,candidate in ipairs(ae:candidates()) do print(candidate.kind.." "..candidate.address) end
    for i=1,count do
      local ok,why=pcall(ae.poll,ae)
      if not ok then ae:unavailable(why) end
      print("["..i.."/"..count.."] "..(ae.online and "ONLINE" or "OFFLINE").." / "..(ae.address or "no component")..
        " / powered="..(ae.powered==nil and "unknown" or tostring(ae.powered)))
      if not ae.online then print(ae.error) end
      if ae.powerError then print(ae.powerError) end
      if ae.energy.supported then print("Energy: "..ae.energy.stored.." / "..ae.energy.capacity.." AE") end
      if ae.cpuError and ae.cpuError~="" and ae.online then print(ae.cpuError) end
      if computer.freeMemory and computer.totalMemory then
        print("RAM free/total: "..math.floor(computer.freeMemory()/1024).." / "..math.floor(computer.totalMemory()/1024).." KiB")
      end
      if i<count then os.sleep(10) end
    end
    return
  end
  if cmd=="doctor" then
    print(hardware.describe())
    local c,err=config.load()
    if c then
      local h,e=hardware.check(c); print(h and ("Hardware OK; Internet "..tostring(h.internet)) or e)
      print("Local hardware inspection only; network and AE2 production not validated.")
    else print(err) end
    return
  end
  if cmd=="status" then
    local running,s=live()
    print(running and ("FactoryOS RUNNING / "..tostring(s.role).." / "..(s.online and "ONLINE" or "CONNECTING")) or "FactoryOS STOPPED")
    if s and s.error then print(s.error) end
    local c,err=config.load(); print(c and ("Configured role: "..c.role) or err)
    return
  end
  if cmd=="stop" or cmd=="restart" then
    local running,s=live()
    if running then
      s.stop=true; s.applyUpdate=nil
      local deadline=computer.uptime()+8
      repeat os.sleep(0.1) until not s.running or computer.uptime()>=deadline
      if s.running then error("Graceful stop timed out; update blocked. Check logs.") end
      print("FactoryOS stopped")
    else print("FactoryOS already stopped") end
    if cmd=="stop" then return end
    cmd="start"
  end
  if cmd=="config" then
    local c,err=config.load()
    if not c then error(err.." Re-run installer to configure.") end
    if not args[2] then
      print(serialization.serialize(c))
      print("Set: factoryos config KEY VALUE | allow ADDRESS main|side | deny ADDRESS")
      return
    end
    assert(not live(),"Stop FactoryOS before changing configuration")
    local k,v=args[2],args[3]
    if k=="allow" then assert(args[4]=="main" or args[4]=="side","role main|side required"); c.allowedClients[assert(v,"address required")]=args[4]
    elseif k=="deny" then c.allowedClients[assert(v,"address required")]=nil
    else
      assert(c[k]~=nil and k~="schema" and k~="allowedClients","Unknown/protected config field")
      assert(v~=nil,"value required")
      if type(c[k])=="number" then v=assert(tonumber(v),"number required")
      elseif type(c[k])=="boolean" then assert(v=="true" or v=="false","true|false required"); v=v=="true" end
      c[k]=v
    end
    assert(config.save(c))
    if k=="autoStart" then require("core.autostart").ensure(c.autoStart) end
    print("Configuration saved; restart to apply."); return
  end
  if cmd=="update" or cmd=="rollback" then
    assert(not live(),"Stop FactoryOS before updating; runtime must be idle")
    if cmd=="rollback" then require("core.updater").rollback(root); print("Rolled back. Reboot before starting.")
    else
      local c=assert(config.load())
      require("core.updater").install(args[2] or c.updateBase,c,root)
      print("Update staged and activated. Configuration preserved. Reboot before starting.")
    end
    return
  end
  if cmd=="start" then
    assert(not live(),"FactoryOS already running")
    local c,err=config.load(); assert(c,err)
    require("core.autostart").ensure(c.autoStart)
    if err then logger.log("WARN",err) end
    local hw,why=hardware.check(c); assert(hw,why)
    local s={running=false,stop=false,role=c.role}; package.loaded["factoryos.service"]=s
    if args[2]=="--foreground" then
      local ok,reason=require("core.runtime").run(c,s); assert(ok,reason)
    else
      print("Starting FactoryOS. Stop with factoryos stop. Foreground: start --foreground")
      local thread=require("thread")
      s.thread=thread.create(function() os.sleep(0.2); require("core.runtime").run(c,s) end)
      s.thread:detach()
    end
    return
  end
  error("Commands: start [--foreground], stop, restart, status, doctor, ae2 [samples], config, logs, update [HTTPS_BASE], rollback, autostart enable|disable")
end
return M
