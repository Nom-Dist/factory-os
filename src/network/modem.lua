local codec=require("core.codec")
local M={MAGIC="FactoryOS/2",VERSION=2}
local function count(t) local n=0; for _ in pairs(t) do n=n+1 end; return n end
function M.new(modem,cfg,clock,nonce)
  local self={queue={},assemblies={},sequence=0,nextSend=0,modem=modem}
  local limit=math.min(modem.maxPacketSize(),4096)
  assert(limit>=1024,"Modem packet limit below 1024 bytes")
  local chunkSize=math.min(1800,math.floor((limit-600)/2))
  self.opened=not modem.isOpen(cfg.port)
  if self.opened then assert(modem.open(cfg.port),"Cannot open modem port") end
  modem.setStrength(cfg.strength)
  function self:send(address,message)
    local ok,data=pcall(codec.encode,message)
    if not ok then return nil,"encode limit" end
    local total=math.max(1,math.ceil(#data/chunkSize))
    if total>64 or #self.queue+total>256 then return nil,"send queue/size limit" end
    self.sequence=self.sequence+1
    local id=nonce..":"..self.sequence
    local frames={}
    for i=1,total do
      local f={v=M.VERSION,id=id,from=modem.address,to=address or "*",part=i,total=total,data=data:sub((i-1)*chunkSize+1,i*chunkSize)}
      local raw=codec.encode(f)
      if #raw+#M.MAGIC+4>limit then return nil,"packet limit" end
      frames[#frames+1]={address=address,raw=raw}
    end
    for _,f in ipairs(frames) do self.queue[#self.queue+1]=f end
    return true
  end
  function self:tick()
    local now=clock()
    if #self.queue>0 and now>=self.nextSend then
      local f=table.remove(self.queue,1)
      if f.address then modem.send(f.address,cfg.port,M.MAGIC,f.raw)
      else modem.broadcast(cfg.port,M.MAGIC,f.raw) end
      self.nextSend=now+0.12
    end
    for k,a in pairs(self.assemblies) do if now-a.started>25 then self.assemblies[k]=nil end end
  end
  function self:receive(localAddress,remote,port,magic,raw)
    if localAddress~=modem.address or port~=cfg.port or magic~=M.MAGIC or type(raw)~="string" or #raw+#M.MAGIC+4>limit then return end
    if cfg.role=="server" and not cfg.allowedClients[remote] then return end
    if cfg.role~="server" and cfg.serverAddress~="" and cfg.serverAddress~=remote then return end
    local f=codec.decode(raw)
    if type(f)~="table" or f.v~=M.VERSION or f.from~=remote or (f.to~=modem.address and f.to~="*") then return end
    if type(f.id)~="string" or #f.id>100 or type(f.data)~="string" or #f.data>chunkSize then return end
    if type(f.part)~="number" or type(f.total)~="number" or f.part%1~=0 or f.total%1~=0 or f.part<1 or f.part>f.total or f.total>64 then return end
    local key=remote..":"..f.id
    local a=self.assemblies[key]
    if not a then
      if count(self.assemblies)>=8 then return end
      a={started=clock(),total=f.total,parts={},received=0,bytes=0}; self.assemblies[key]=a
    end
    if a.total~=f.total then self.assemblies[key]=nil; return end
    if not a.parts[f.part] then
      a.parts[f.part]=f.data; a.received=a.received+1; a.bytes=a.bytes+#f.data
    elseif a.parts[f.part]~=f.data then self.assemblies[key]=nil; return end
    if a.bytes>65536 then self.assemblies[key]=nil; return end
    if a.received==a.total then
      self.assemblies[key]=nil
      local message=codec.decode(table.concat(a.parts))
      if type(message)=="table" then return message end
    end
  end
  function self:close()
    if self.opened then modem.close(cfg.port) end
    self.queue={}; self.assemblies={}
  end
  return self
end
return M
