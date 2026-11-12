local T=...
local test,eq,callback=T.test,T.eq,T.callback
local crypto=require("core.crypto")
local W=require("network.websocket")
local codec=require("core.codec")
test("Web SHA1 and RFC6455 masking/accept vectors work on both Lua architectures",function()
  local function hex(s) return (s:gsub(".",function(c) return string.format("%02x",c:byte()) end)) end
  eq(hex(crypto.sha1("")),"da39a3ee5e6b4b0d3255bfef95601890afd80709")
  eq(hex(crypto.sha1("abc")),"a9993e364706816aba3e25717850c26c9cd0d89d")
  eq(W.base64(crypto.sha1("dGhlIHNhbXBsZSBub25jZQ==258EAFA5-E914-47DA-95CA-C5AB0DC85B11")),"s3pPLMBiTxaQ9kYGzzhZRbK+xOo=")
  eq(hex(W.frame("Hello",1,string.char(0x37,0xfa,0x21,0x3d))),"818537fa213d7f9f4d5158")
  eq(W.parse("ws://example.org:8080/bridge/device").port,8080)
  assert(not W.parse("wss://example.org/")); assert(not W.parse("ws://example.org:0/"))
end)
test("Web legacy config migration defaults off and validates role, URL and secrets",function()
  local config=require("core.config"); local c=config.defaults("server")
  c.webEnabled=nil; c.webControl=nil; c.webUrl=nil; c.webToken=nil; c.webInterval=nil
  c=config.upgrade(c); eq(c.webEnabled,false); eq(c.webControl,false); assert(config.validate(c))
  c.webEnabled=true; assert(not config.validate(c)); c.webToken=string.rep("a",32); c.webUrl="https://panel.example/bridge/ingest"; assert(config.validate(c))
  c.webUrl="wss://panel.example/bridge/device"; assert(not config.validate(c))
  c.webUrl="ws://127.0.0.1:3000/bridge/device"; assert(config.validate(c))
  c.webUrl="ws://localhost:99999/bridge/device"; assert(not config.validate(c))
  c.webUrl="https://panel.example/bridge/ingest"; c.role="main"; assert(not config.validate(c))
end)
test("Web nonblocking handshake handles partial writes, verifies accept and answers ping",function()
  local f={time=0,written="",input="",closed=false}
  local sock={finishConnect=callback(function() return true end),close=callback(function() f.closed=true end)}
  sock.write=callback(function(data)
    local n=math.min(7,#data); f.written=f.written..data:sub(1,n)
    if not f.upgraded and f.written:find("\r\n\r\n",1,true) then
      local key=f.written:match("Sec%-WebSocket%-Key: ([^\r]+)")
      f.input="HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: "..
        W.base64(crypto.sha1(key.."258EAFA5-E914-47DA-95CA-C5AB0DC85B11")).."\r\n\r\n"; f.upgraded=true
    end
    return n
  end)
  sock.read=callback(function(n) local s=f.input:sub(1,math.min(11,n)); f.input=f.input:sub(#s+1); return s end)
  local ws=assert(W.new({connect=callback(function() return sock end)},"ws://local/bridge/device",string.rep("a",32),function() return f.time end))
  for i=1,100 do f.time=i/100; assert(ws:tick(function() end)) end
  eq(ws.phase,"open"); f.input=string.char(0x89,2).."hi"; assert(ws:tick(function() end)); assert(#ws.output>0)
  local message; f.input=string.char(0x82,3).."abc"; assert(ws:tick(function(s) message=s end)); eq(message,"abc")
  f.input=string.char(0x82,128).."bad"; assert(not ws:tick(function() end)); assert(f.closed)
end)
test("Web HTTP uplink permits only bounded commands, honors control flag and never repeats IDs",function()
  local cfg=require("core.config").defaults("server"); cfg.webEnabled=true; cfg.webUrl="https://panel.example/bridge/ingest"; cfg.webToken=string.rep("b",32)
  local incoming={kind="command",id="same-command",command="START_CRAFT",args={amount=1}}; local sent={}; local called=0; local now=0
  local internet={type="internet",address="web-internet",isHttpEnabled=callback(function() return true end),request=callback(function(url,body,headers)
    eq(url,cfg.webUrl); eq(headers.Authorization,"Bearer "..cfg.webToken); sent[#sent+1]=assert(codec.decode(body))
    local data=codec.encode(incoming); local read=false
    return {finishConnect=callback(function() return true end),response=callback(function() return 200 end),close=callback(function() end),
      read=callback(function() if not read then read=true; return data end end)}
  end)}
  local server={stock={list=function() return {rules={},pages=1} end},crafting={journal={automation={revision=0,paused=false}},jobs=function() return {cpus={},trackedJobs={}} end},
    status=function() return {ae2={online=true}} end,dispatch=function(_,command,args,client) called=called+1; eq(command,"START_CRAFT"); eq(client.address,"@factoryos-web"); return {state="computing"} end}
  T.setComponents({[internet.address]=internet})
  local web=require("server.web").new(cfg,server,function() return now end,function() end)
  for i=1,30 do now=now+0.2; web:tick() end
  eq(called,0); local denied=false
  for _,s in ipairs(sent) do if s.kind=="reply" then eq(s.error,"WEB_CONTROL_DISABLED"); denied=true end end
  assert(denied)
  cfg.webControl=true; incoming.id="next-command"
  for i=1,70 do now=now+0.2; web:tick() end
  eq(called,1)
  incoming.id="forbidden"; incoming.command="GET_UPDATE_FILE"
  for i=1,40 do now=now+0.2; web:tick() end
  eq(called,1); web:close(); eq(web.phase,"closed"); T.setComponents({})
end)
