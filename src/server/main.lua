local ae2=require("server.ae2")
local energy=require("server.energy")
local machines=require("server.machines")
local M={}
function M.new(cfg,clock,log)
  local self={ae2=ae2.new(cfg),lastPoll=-math.huge,started=clock(),clients={}}
  self.crafting=require("server.crafting").new(self.ae2,clock,log)
  self.stock=require("server.stock").new(self.crafting,self.ae2,clock)
  function self:status()
    local clients={}
    for address,c in pairs(self.clients) do clients[#clients+1]={address=address,role=c.role,age=math.floor(clock()-c.lastSeen)} end
    return {version="0.6.1",uptime=math.floor(clock()-self.started),ae2=self.ae2:summary(),clients=clients,
      power=energy.status(self.ae2),automation=self.stock:enabled(),crafting=self.crafting.blocked and "blocked" or "manual",reactors="read_only_unsupported",
      update=self.updates and self.updates:public() or nil}
  end
  function self:canUpdate()
    if self.crafting:busy() then return false,"Aktif/belirsiz uretim emri var; isleri kontrol edin" end
    for _,cpu in ipairs(self.ae2.cpus or {}) do if cpu.busy then return false,"Uretim CPU'lari mesgul; sonra tekrar deneyin" end end
    return true
  end
  function self:dispatch(command,args,client)
    if command=="HEARTBEAT" or command=="GET_SERVER_STATUS" then return self:status() end
    if command=="GET_AE2_STOCKS" then return self.ae2:stocks(args) end
    if command=="GET_CRAFTING_JOBS" then return self.crafting:jobs() end
    if command=="GET_STOCK_RULES" or command=="SET_STOCK_RULE" then
      if not client or client.role~="main" or type(client.address)~="string" then return nil,"FORBIDDEN" end
      if command=="GET_STOCK_RULES" then return self.stock:list(args) end
      if self.updates and (self.updates.busy or self.updates.readyManifest) then return nil,"Guncelleme suruyor" end
      return self.stock:change(args)
    end
    if command=="GET_CRAFT_OPTIONS" or command=="START_CRAFT" or command=="CANCEL_CRAFT" or command=="ARCHIVE_CRAFT" then
      if not client or client.role~="main" or type(client.address)~="string" then return nil,"FORBIDDEN" end
      if self.updates and (self.updates.busy or self.updates.readyManifest) and (command=="GET_CRAFT_OPTIONS" or command=="START_CRAFT") then return nil,"Guncelleme suruyor; uretimi sonra deneyin" end
      if command=="GET_CRAFT_OPTIONS" then return self.crafting:options(client.address,args) end
      if command=="START_CRAFT" then return self.crafting:start(client.address,args) end
      return self.stock:controlJob(client.address,args,command=="ARCHIVE_CRAFT")
    end
    if command=="GET_POWER_STATUS" then return energy.status(self.ae2) end
    if command=="GET_MACHINE_STATUS" then return machines.status() end
    if (command=="GET_UPDATE_INFO" or command=="GET_UPDATE_FILE") and self.updates then return self.updates:serve(command,args) end
    return nil,"UNSUPPORTED_COMMAND"
  end
  function self:tick()
    self.crafting:tick()
    if clock()-self.lastPoll<cfg.poll then return end
    self.lastPoll=clock()
    local old=self.ae2.online; local oldError=self.ae2.error; local oldAddress=self.ae2.address
    local ok,err=pcall(self.ae2.poll,self.ae2)
    if not ok then
      self.ae2:unavailable(err)
    end
    if old~=self.ae2.online or oldError~=self.ae2.error or oldAddress~=self.ae2.address then
      log(self.ae2.online and "INFO" or "WARN","AE2 "..(self.ae2.online and "ONLINE" or "OFFLINE")..
        " ["..(self.ae2.address or "no component").."]"..(self.ae2.online and "" or (": "..self.ae2.error)))
    end
    self.stock:tick(self.updates and (self.updates.busy or self.updates.readyManifest))
  end
  return self
end
return M
