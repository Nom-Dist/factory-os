-- Bounded, nonblocking RFC 6455 client over OC's plain TCP Internet Card API.
-- wss requires TLS, which this legacy TCP API does not expose. Use the HTTPS
-- uplink in server.web for public deployments, or a trusted-network ws relay.
local crypto=require("core.crypto")
local uuid=require("uuid")
local M={}
local alphabet="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
function M.base64(s)
  local out={}
  for i=1,#s,3 do
    local a,b,c=s:byte(i,i+2); local n=a*65536+(b or 0)*256+(c or 0)
    out[#out+1]=alphabet:sub(math.floor(n/262144)%64+1,math.floor(n/262144)%64+1)..alphabet:sub(math.floor(n/4096)%64+1,math.floor(n/4096)%64+1)..
      (b and alphabet:sub(math.floor(n/64)%64+1,math.floor(n/64)%64+1) or "=")..(c and alphabet:sub(n%64+1,n%64+1) or "=")
  end
  return table.concat(out)
end
function M.parse(url)
  if type(url)~="string" or #url>512 or url:find("[%s%c]") then return nil,"Gecersiz WebSocket adresi" end
  local authority,path=url:match("^ws://([^/]+)(/.*)$")
  if not authority then authority=url:match("^ws://([^/]+)$"); path="/" end
  if not authority then return nil,"TCP WebSocket icin ws://; TLS icin HTTPS uplink kullanin" end
  local host,port=authority:match("^([%w%.%-]+):(%d+)$")
  host=host or authority:match("^([%w%.%-]+)$"); port=tonumber(port) or 80
  if not host or port<1 or port>65535 then return nil,"Gecersiz WebSocket host/port" end
  return {host=host,port=port,path=path,authority=authority}
end
local function bytes()
  local hex=uuid.next():gsub("%-","")
  return (hex:gsub("..",function(v) return string.char(tonumber(v,16) or 0) end))
end
local function xor(a,b)
  local out,p=0,1
  for _=1,8 do if a%2~=b%2 then out=out+p end; a=math.floor(a/2); b=math.floor(b/2); p=p*2 end
  return out
end
function M.frame(payload,opcode,mask)
  assert(#payload<=65536,"WebSocket payload limit")
  mask=mask or bytes():sub(1,4); assert(#mask==4)
  local n=#payload; local head
  if n<126 then head=string.char(128+(opcode or 2),128+n)
  elseif n<65536 then head=string.char(128+(opcode or 2),254,math.floor(n/256),n%256)
  else head=string.char(128+(opcode or 2),255,0,0,0,0,0,1,0,0) end
  local out={}; for i=1,n do out[i]=string.char(xor(payload:byte(i),mask:byte((i-1)%4+1))) end
  return head..mask..table.concat(out)
end
function M.new(internet,url,token,clock)
  local target,err=M.parse(url); if not target then return nil,err end
  if token:find("[%c]") then return nil,"Gecersiz bridge anahtari" end
  local sock,why=internet.connect(target.host,target.port); if not sock then return nil,why end
  local key=M.base64(bytes()); local accepted=M.base64(crypto.sha1(key.."258EAFA5-E914-47DA-95CA-C5AB0DC85B11"))
  local self={socket=sock,phase="connecting",input="",output="",started=clock(),lastRead=clock()}
  function self:close() pcall(sock.close); self.phase="closed"; self.input=""; self.output="" end
  function self:send(data,opcode)
    if self.phase~="open" or #self.output>0 then return nil,"BUSY" end
    self.output=M.frame(data,opcode); self.pendingAt=clock(); return true
  end
  function self:tick(onMessage)
    if self.phase=="closed" then return nil,"CLOSED" end
    local ok,failure=pcall(function()
      if self.phase~="open" and clock()-self.started>15 then error("WebSocket handshake timeout") end
      if self.phase=="connecting" then
        if not sock.finishConnect() then return end
        self.output="GET "..target.path.." HTTP/1.1\r\nHost: "..target.authority.."\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: "..key..
          "\r\nSec-WebSocket-Version: 13\r\nAuthorization: Bearer "..token.."\r\n\r\n"
        self.phase="handshake"
      end
      if #self.output>0 then
        assert(not self.pendingAt or clock()-self.pendingAt<=15,"WebSocket write timeout")
        local n,reason=sock.write(self.output:sub(1,4096))
        if not n then error(reason or "WebSocket write failed") end
        self.output=self.output:sub(n+1)
        if #self.output==0 then self.pendingAt=nil end
      end
      local data,reason=sock.read(4096)
      if data==nil then error(reason or "WebSocket disconnected") end
      if #data>0 then self.input=self.input..data; self.lastRead=clock() end
      if #self.input>73728 then error("WebSocket input limit") end
      if clock()-self.lastRead>70 then error("WebSocket idle timeout") end
      if self.phase=="handshake" then
        local endAt=self.input:find("\r\n\r\n",1,true)
        if not endAt then assert(#self.input<=8192,"WebSocket header limit"); return end
        local header=self.input:sub(1,endAt+1); self.input=self.input:sub(endAt+4)
        assert(header:match("^HTTP/1%.[01] 101 "),"WebSocket upgrade rejected")
        local headers={}
        for name,value in header:gmatch("\r\n([^:%s]+):%s*([^\r\n]*)") do headers[name:lower()]=value end
        assert(headers["sec-websocket-accept"]==accepted and (headers.upgrade or ""):lower()=="websocket" and
          (headers.connection or ""):lower():find("upgrade",1,true),"WebSocket handshake invalid")
        self.phase="open"
      end
      local frames=0
      while self.phase=="open" and #self.input>=2 and frames<4 do
        local a,b=self.input:byte(1,2); local opcode=a%16; local n=b%128; local at=3
        assert(a>=128 and a<144 and b<128,"Fragmented/masked server frame unsupported")
        if n==126 then if #self.input<4 then return end; local x,y=self.input:byte(3,4); n=x*256+y; at=5
        elseif n==127 then error("WebSocket frame too large") end
        assert(n<=65535 and (opcode<8 or n<=125),"WebSocket frame limit")
        if #self.input<at+n-1 then return end
        local payload=self.input:sub(at,at+n-1); self.input=self.input:sub(at+n); frames=frames+1
        if opcode==8 then error("WebSocket closed by relay")
        elseif opcode==9 then assert(#self.output<66000,"WebSocket output limit"); self.output=self.output..M.frame(payload,10); self.pendingAt=self.pendingAt or clock()
        elseif opcode==1 or opcode==2 then onMessage(payload)
        elseif opcode~=10 then error("Unsupported WebSocket opcode") end
      end
    end)
    if not ok then self:close(); return nil,tostring(failure) end
    return true
  end
  return self
end
return M
