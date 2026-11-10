local transport=require("network.modem")
local messages=require("network.messages")
local codec=require("core.codec")
local M={}
local function size(t) local n=0; for _ in pairs(t) do n=n+1 end; return n end
function M.new(cfg,modem,clock,nonce,dispatch,log)
  local self={boot=nonce(),clients={},pending={},seen={},offers={},online=false,lastSeen=0,lastHello=-math.huge,lastHeartbeat=-math.huge,sequence=0}
  self.wire=transport.new(modem,cfg,clock,self.boot)
  log=log or function() end
  local function send(address,kind,body,target,id)
    self.sequence=self.sequence+1
    return self.wire:send(address,{v=transport.VERSION,kind=kind,body=body or {},boot=self.boot,target=target or "",id=id or (self.boot..":"..self.sequence)})
  end
  local function offline(reason)
    if self.online then log("WARN","Server OFFLINE: "..reason) end
    self.online=false; self.server=nil; self.serverBoot=nil
    local pending=self.pending; self.pending={}
    for _,p in pairs(pending) do if p.callback then p.callback(nil,"OFFLINE") end end
  end
  function self:request(command,body,callback)
    if not self.online then return nil,"OFFLINE" end
    if size(self.pending)>=8 then return nil,"pending limit" end
    self.sequence=self.sequence+1
    local id=self.boot..":"..self.sequence
    local data={command=command,args=body or {}}
    local ok,err=send(self.server,"REQUEST",data,self.serverBoot,id)
    if not ok then return nil,err end
    self.pending[id]={data=data,sent=clock(),attempts=1,callback=callback}
    return id
  end
  function self:receive(localAddress,remote,port,magic,raw)
    local m=self.wire:receive(localAddress,remote,port,magic,raw)
    if not m or m.v~=transport.VERSION or type(m.kind)~="string" or type(m.body)~="table" or type(m.boot)~="string" or #m.boot<8 or #m.boot>64 or type(m.id)~="string" or #m.id>100 then return end
    local now=clock()
    if cfg.role=="server" then
      local role=cfg.allowedClients[remote]
      if not role then return end
      if m.kind=="HELLO" then
        if type(m.body.nonce)~="string" or #m.body.nonce>64 then return end
        local offer=self.offers[remote]
        if offer and now-offer.created<2 then return end
        offer={boot=m.boot,nonce=m.body.nonce,challenge=nonce(),created=now}
        self.offers[remote]=offer
        send(remote,"OFFER",{nonce=offer.nonce,challenge=offer.challenge},m.boot)
        return
      end
      if m.target~=self.boot then return end
      if m.kind=="REGISTER_CLIENT" then
        local o=self.offers[remote]
        if not o or now-o.created>15 or o.boot~=m.boot or o.challenge~=m.body.challenge then return end
        self.offers[remote]=nil
        self.clients[remote]={role=role,boot=m.boot,lastSeen=now}
        log("INFO","Registered "..role.." "..remote)
        send(remote,"REGISTERED",{role=role},m.boot)
        return
      end
      local c=self.clients[remote]
      if not c or c.boot~=m.boot or m.kind~="REQUEST" or now-c.lastSeen>cfg.offlineAfter then return end
      c.lastSeen=now
      local key=remote..":"..m.id
      local fingerprint=codec.encode(m.body)
      local old=self.seen[key]
      if old then
        if old.fingerprint==fingerprint then send(remote,"RESPONSE",old.body,m.boot,m.id) end
        return
      end
      -- Cache never evicts an unexpired request: refuse additional work under load.
      if size(self.seen)>=128 then return end
      local allowed,err=messages.authorize(c.role,m.body.command)
      local value
      if allowed and type(m.body.args)=="table" then
        local ok,result,why=pcall(dispatch,m.body.command,m.body.args,c)
        if ok then value,err=result,why else err="INTERNAL_ERROR"; log("ERROR",result) end
      elseif allowed then err="INVALID_ARGUMENTS" end
      local body={ok=err==nil,data=value or {},error=err or ""}
      self.seen[key]={body=body,at=now,fingerprint=fingerprint}
      send(remote,"RESPONSE",body,m.boot,m.id)
    else
      if m.target~=self.boot then return end
      if m.kind=="OFFER" and not self.online and m.body.nonce==self.helloNonce and type(m.body.challenge)=="string" then
        self.candidate=remote; self.candidateBoot=m.boot
        send(remote,"REGISTER_CLIENT",{challenge=m.body.challenge},m.boot)
        return
      end
      if m.kind=="REGISTERED" and remote==self.candidate and m.boot==self.candidateBoot and m.body.role==cfg.role then
        self.server=remote; self.serverBoot=m.boot; self.online=true; self.lastSeen=now
        self.lastHeartbeat=-math.huge; self.candidate=nil
        log("INFO","Server ONLINE "..remote)
        return
      end
      if not self.online or remote~=self.server or m.boot~=self.serverBoot or m.kind~="RESPONSE" then return end
      local p=self.pending[m.id]
      if not p or type(m.body.ok)~="boolean" then return end
      self.pending[m.id]=nil; self.lastSeen=now
      if p.callback then
        if m.body.ok then p.callback(m.body.data,nil) else p.callback(nil,m.body.error) end
      end
    end
  end
  function self:tick()
    local now=clock()
    self.wire:tick()
    for k,v in pairs(self.seen) do if now-v.at>60 then self.seen[k]=nil end end
    for k,v in pairs(self.offers) do if now-v.created>15 then self.offers[k]=nil end end
    for k,c in pairs(self.clients) do
      if now-c.lastSeen>cfg.offlineAfter then self.clients[k]=nil; log("WARN","Client OFFLINE "..k) end
    end
    if cfg.role=="server" then return end
    if self.online and now-self.lastSeen>=cfg.offlineAfter then offline("heartbeat timeout") end
    if not self.online and now-self.lastHello>=cfg.heartbeat then
      self.helloNonce=nonce(); self.lastHello=now
      send(cfg.serverAddress~="" and cfg.serverAddress or nil,"HELLO",{nonce=self.helloNonce})
    end
    if self.online and now-self.lastHeartbeat>=cfg.heartbeat then
      self.lastHeartbeat=now
      self:request("HEARTBEAT",{},function(data) if data then self.status=data end end)
    end
    for id,p in pairs(self.pending) do
      if now-p.sent>=4 then
        if p.attempts>=3 then
          self.pending[id]=nil
          if p.callback then p.callback(nil,"TIMEOUT") end
        else
          local ok=send(self.server,"REQUEST",p.data,self.serverBoot,id)
          if ok then p.attempts=p.attempts+1; p.sent=now end
        end
      end
    end
  end
  function self:close() self.wire:close(); self.online=false end
  return self
end
return M
