local ae2=require("server.ae2")
local energy=require("server.energy")
local machines=require("server.machines")
local M={}
function M.new(cfg,clock,log)
  local self={ae2=ae2.new(cfg),lastPoll=-math.huge,started=clock(),clients={}}
  function self:status()
    local clients={}
    for address,c in pairs(self.clients) do clients[#clients+1]={address=address,role=c.role,age=math.floor(clock()-c.lastSeen)} end
    return {version="0.3.0",uptime=math.floor(clock()-self.started),ae2=self.ae2:summary(),clients=clients,
      power=energy.status(self.ae2),automation=false,crafting="disabled_pending_ingame_validation",reactors="read_only_unsupported",
      update=self.updates and self.updates:public() or nil}
  end
  function self:canUpdate()
    for _,cpu in ipairs(self.ae2.cpus or {}) do if cpu.busy then return false,"Uretim CPU'lari mesgul; sonra tekrar deneyin" end end
    return true
  end
  function self:dispatch(command,args)
    if command=="HEARTBEAT" or command=="GET_SERVER_STATUS" then return self:status() end
    if command=="GET_AE2_STOCKS" then return self.ae2:stocks(args) end
    if command=="GET_CRAFTING_JOBS" then return self.ae2:jobs() end
    if command=="GET_POWER_STATUS" then return energy.status(self.ae2) end
    if command=="GET_MACHINE_STATUS" then return machines.status() end
    if (command=="GET_UPDATE_INFO" or command=="GET_UPDATE_FILE") and self.updates then return self.updates:serve(command,args) end
    return nil,"UNSUPPORTED_COMMAND"
  end
  function self:tick()
    if clock()-self.lastPoll<cfg.poll then return end
    self.lastPoll=clock()
    local old=self.ae2.online
    local ok,err=pcall(self.ae2.poll,self.ae2)
    if not ok then
      self.ae2.online=false; self.ae2.error=tostring(err); self.ae2.items={}; self.ae2.cpus={}
      self.ae2.energy={supported=false,unit="AE"}; log("ERROR",err)
    end
    if old~=self.ae2.online then log(self.ae2.online and "INFO" or "WARN","AE2 "..(self.ae2.online and "ONLINE" or "OFFLINE")) end
  end
  return self
end
return M
