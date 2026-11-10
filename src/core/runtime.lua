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
  local net,view
  local oldW,oldH=hw.gpu.getResolution()
  local oldFg,oldBg=hw.gpu.getForeground(),hw.gpu.getBackground()
  local oldDepth=hw.gpu.getDepth()
  local function log(level,s) logger.log(level,s) end
  local function clock() return computer.uptime() end
  local function nonce() return uuid.next() end
  local ok,reason=xpcall(function()
    local server=cfg.role=="server" and require("server.main").new(cfg,clock,log) or nil
    net=protocol.new(cfg,hw.modem,clock,nonce,server and function(cmd,args) return server:dispatch(cmd,args) end,log)
    if server then server.clients=net.clients end
    local state=cfg.role=="main" and require("client.main_display").new(net,clock) or require("client.side_display").new()
    view=renderer.new(hw.gpu,hw.screen,cfg.role)
    local lastDraw=-math.huge
    service.running=true; service.started=clock(); service.role=cfg.role; service.error=nil
    logger.log("INFO","Started "..cfg.role.." on modem "..hw.modem.address)
    while not service.stop do
      net:tick()
      if server then server:tick(); state.serverStatus=server:status() else state:tick() end
      if clock()-lastDraw>=1 then
        screens.draw(view,cfg.role,net,state,clock)
        lastDraw=clock()
        service.online=cfg.role=="server" or net.online
      end
      local e={event.pull(0.12)}
      if e[1]=="modem_message" then
        -- Signal layout: name, local modem, remote modem, port, distance, payload...
        net:receive(e[2],e[3],e[4],e[6],e[7])
      elseif e[1]=="touch" then state:touch(view:touch(e[2],e[3],e[4])); lastDraw=-math.huge
      elseif e[1]=="key_down" and state.key then state:key(e[3],e[4]); lastDraw=-math.huge
      elseif e[1]=="interrupted" then service.stop=true end
    end
  end,debug.traceback)
  if net then pcall(net.close,net) end
  pcall(function()
    hw.gpu.setDepth(oldDepth); hw.gpu.setResolution(oldW,oldH)
    hw.gpu.setForeground(oldFg); hw.gpu.setBackground(oldBg); hw.gpu.fill(1,1,oldW,oldH," ")
  end)
  service.running=false
  if not ok then service.error=tostring(reason); logger.log("ERROR",reason) end
  logger.log("INFO","Stopped "..cfg.role)
  return ok,reason
end
return M
