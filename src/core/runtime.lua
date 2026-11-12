local event=require("event")
local computer=require("computer")
local uuid=require("uuid")
local hardware=require("core.hardware")
local protocol=require("network.protocol")
local renderer=require("ui.renderer")
local screens=require("ui.screens")
local logger=require("core.logger")
local M={}
function M.run(cfg,service)
  local hw,err=hardware.check(cfg)
  if not hw then service.running=false; service.error=err; logger.log("ERROR",err); return nil,err end
  local net,view,updates,web
  local oldW,oldH=hw.gpu.getResolution()
  local oldFg,oldBg=hw.gpu.getForeground(),hw.gpu.getBackground()
  local oldDepth=hw.gpu.getDepth()
  local function log(level,s) logger.log(level,s) end
  local function clock() return computer.uptime() end
  local function nonce() return uuid.next() end
  local ok,reason=xpcall(function()
    local server=cfg.role=="server" and require("server.main").new(cfg,clock,log) or nil
    net=protocol.new(cfg,hw.modem,clock,nonce,server and function(cmd,args,client) return server:dispatch(cmd,args,client) end,log)
    if server then server.clients=net.clients end
    updates=require("core.updates").new(cfg,net,clock,service,{log=log,isIdle=server and function() return server:canUpdate() end or nil})
    if server then server.updates=updates end
    if server then web=require("server.web").new(cfg,server,clock,log); server.web=web end
    local function webCanApply()
      if updates.busy or updates.readyManifest then return nil,"Guncelleme suruyor; sonra deneyin" end
      return true
    end
    local function applyWeb(candidate)
      if web then web:close() end
      for _,key in ipairs({"webEnabled","webControl","webUrl","webToken","webInterval"}) do cfg[key]=candidate[key] end
      web=require("server.web").new(cfg,server,clock,log); server.web=web
    end
    local state=cfg.role=="server" and require("client.server_console").new(cfg,clock,applyWeb,webCanApply) or
      cfg.role=="main" and require("client.main_display").new(net,clock) or require("client.side_display").new()
    state.context={modem=hw.modem.address,screen=hw.screen.address,port=cfg.port,serverAddress=cfg.serverAddress,poll=cfg.poll}
    view=renderer.new(hw.gpu,hw.screen,cfg.role)
    local lastDraw=-math.huge
    service.running=true; service.started=clock(); service.role=cfg.role; service.error=nil
    logger.log("INFO","Started "..cfg.role.." on modem "..hw.modem.address)
    while not service.stop do
      net:tick()
      if server then server:tick(); state.serverStatus=server:status() else state:tick() end
      updates:tick(); state.update=updates:public()
      if web then web:tick(); state.webStatus=web:public() end
      if updates.readyManifest and not updates.busy and updates.phase=="ready" then service.applyUpdate=updates.readyManifest; service.stop=true end
      if clock()-lastDraw>=1 then
        screens.draw(view,cfg.role,net,state,clock)
        lastDraw=clock()
        service.online=cfg.role=="server" or net.online
      end
      local e={event.pull(0.12)}
      if e[1]=="modem_message" then
        -- Signal layout: name, local modem, remote modem, port, distance, payload...
        net:receive(e[2],e[3],e[4],e[6],e[7])
      elseif e[1]=="touch" then
        local id=view:touch(e[2],e[3],e[4])
        if id and id:match("^update:") then updates:touch(id) else state:touch(id) end
        lastDraw=-math.huge
      elseif e[1]=="key_down" then
        if cfg.role=="server" and not state.editing and e[4]==62 then state:touch("web:open")
        elseif not state.editing and not state.craft and not state.ruleEditor and e[4]==63 then updates:touch("update:check")
        elseif not state.editing and not state.craft and not state.ruleEditor and e[4]==64 then updates:touch("update:apply")
        elseif state.key then state:key(e[3],e[4]) end
        lastDraw=-math.huge
      elseif e[1]=="clipboard" and state.paste then state:paste(e[3]); lastDraw=-math.huge
      elseif e[1]=="interrupted" then service.stop=true; service.applyUpdate=nil end
    end
  end,debug.traceback)
  if updates then updates:close() end
  if web then web:close() end
  if net then pcall(net.close,net) end
  pcall(function()
    hw.gpu.setDepth(oldDepth); hw.gpu.setResolution(oldW,oldH)
    hw.gpu.setForeground(oldFg); hw.gpu.setBackground(oldBg); hw.gpu.fill(1,1,oldW,oldH," ")
  end)
  service.running=false
  if not ok then service.error=tostring(reason); logger.log("ERROR",reason) end
  logger.log("INFO","Stopped "..cfg.role)
  if ok and service.applyUpdate then
    local applied,why=pcall(function()
      require("core.autostart").ensure(cfg.autoStart)
      require("core.updater").activate(service.applyUpdate)
      logger.log("INFO","Activated "..service.applyUpdate.release.."; rebooting")
      computer.shutdown(true)
    end)
    if not applied then service.error=tostring(why); logger.log("ERROR",why); return nil,why end
  end
  return ok,reason
end
return M
