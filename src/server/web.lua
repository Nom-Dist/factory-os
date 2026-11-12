local codec=require("core.codec")
local hardware=require("core.hardware")
local websocket=require("network.websocket")
local uuid=require("uuid")
local M={owner="@factoryos-web"}
local reads={GET_CRAFT_OPTIONS=true,GET_STOCK_RULES=true,GET_AE2_STOCKS=true,GET_CRAFTING_JOBS=true}
local writes={START_CRAFT=true,CANCEL_CRAFT=true,ARCHIVE_CRAFT=true,SET_STOCK_RULE=true}
function M.new(cfg,server,clock,log)
  local self={phase=cfg.webEnabled and "waiting" or "disabled",lastSend=-math.huge,nextTry=0,backoff=2,queue={},seen={},boot=uuid.next()}
  local http,ws
  local function close()
    if ws then ws:close(); ws=nil end
    if http then pcall(http.handle.close); http=nil end
  end
  local function fail(reason)
    close(); self.phase="offline"; self.error=reason; self.nextTry=clock()+self.backoff; self.backoff=math.min(60,self.backoff*2)
    log("WARN","Web bridge offline; yeniden denenecek") -- Never log URL credentials/payloads.
  end
  local function enqueue(message)
    if #self.queue>=8 then return nil,"Web response queue full" end
    self.queue[#self.queue+1]=codec.encode(message); return true
  end
  local function receive(raw)
    local message=codec.decode(raw)
    if type(message)~="table" or message.kind~="command" or type(message.id)~="string" or #message.id>64 or
      type(message.args)~="table" or not (reads[message.command] or writes[message.command]) then return end
    -- RPCs are never replayed automatically after a link loss. START_CRAFT's
    -- durable sequence is still authoritative across relay/process reboots.
    if self.seen[message.id] then return end
    if #self.queue>=8 then return end
    local count=0; for _ in pairs(self.seen) do count=count+1 end
    if count>=128 then enqueue({kind="reply",id=message.id,ok=false,error="BUSY",data={}}); return end
    local ok,result,err
    if writes[message.command] and not cfg.webControl then ok=true; err="WEB_CONTROL_DISABLED"
    else ok,result,err=pcall(server.dispatch,server,message.command,message.args,{role="main",address=M.owner}) end
    local reply={kind="reply",id=message.id,ok=ok and err==nil,data=ok and result or {},error=ok and (err or "") or "INTERNAL_ERROR"}
    self.seen[message.id]=clock(); enqueue(reply)
  end
  local function telemetry()
    local rules={}
    for page=1,4 do
      local result=server.stock:list({page=page})
      for _,r in ipairs(result.rules) do
        rules[#rules+1]={id=r.id,label=r.label,minimum=r.minimum,target=r.target,enabled=r.enabled,stock=r.stock,inFlight=r.inFlight,state=r.state,error=r.error,retryIn=r.retryIn}
      end
      if page>=result.pages then break end
    end
    return codec.encode({kind="telemetry",boot=self.boot,controlEnabled=cfg.webControl,status=server:status(),
      jobs=server.crafting:jobs(),rules=rules,rulesRevision=server.crafting.journal.automation.revision,
      paused=server.crafting.journal.automation.paused})
  end
  function self:public()
    local reason=(self.error or ""):gsub("^.-:%d+: ","")
    local code=reason:match("HTTP uplink rejected: (%d+)")
    if code=="401" then reason="401: Token ve panel ayarlarini kontrol edin"
    elseif code then reason="Panel HTTP hatasi: "..code end
    return {enabled=cfg.webEnabled,control=cfg.webControl,phase=self.phase,error=reason}
  end
  function self:close() close(); self.phase="closed"; self.queue={} end
  function self:tick()
    if not cfg.webEnabled or clock()<self.nextTry then return end
    for id,at in pairs(self.seen) do if clock()-at>120 then self.seen[id]=nil end end
    local ok,err=pcall(function()
      if http then
        if clock()-http.started>15 then error("HTTP uplink timeout") end
        if not http.connected then
          if not http.handle.finishConnect() then return end
          local code=http.handle.response(); assert(code==200,"HTTP uplink rejected: "..tostring(code)); http.connected=true
        end
        local chunk,reason=http.handle.read(4096)
        if chunk==nil then
          assert(not reason,reason); local raw=table.concat(http.chunks); http.handle.close(); http=nil
          self.phase="online"; self.error=nil; self.backoff=2; receive(raw)
        elseif #chunk>0 then http.bytes=http.bytes+#chunk; assert(http.bytes<=16384,"HTTP response limit"); http.chunks[#http.chunks+1]=chunk end
        return
      end
      if cfg.webUrl:match("^ws://") then
        if not ws then
          local internet=assert(hardware.select("internet","")); assert(internet.isTcpEnabled(),"TCP disabled")
          ws=assert(websocket.new(internet,cfg.webUrl,cfg.webToken,clock)); self.phase="connecting"
        end
        local alive,why=ws:tick(receive); assert(alive,why)
        if ws.phase~="open" then return end
        self.phase="online"; self.error=nil; self.backoff=2
        if #ws.output>0 then return end
      end
      if #self.queue==0 and clock()-self.lastSend>=cfg.webInterval then self.queue[1]=telemetry(); self.lastSend=clock() end
      if #self.queue==0 then return end
      local data=table.remove(self.queue,1)
      if ws then assert(ws:send(data))
      else
        local internet=assert(hardware.select("internet","")); assert(internet.isHttpEnabled(),"HTTP disabled")
        local handle=assert(internet.request(cfg.webUrl,data,{["Content-Type"]="application/x-factoryos",["Authorization"]="Bearer "..cfg.webToken}))
        http={handle=handle,started=clock(),chunks={},bytes=0}; self.phase="sending"
      end
    end)
    if not ok then fail(tostring(err):sub(1,240)) end
  end
  return self
end
return M
