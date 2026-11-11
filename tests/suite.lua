local passed=0
local function test(name,fn)
  local ok,err=xpcall(fn,debug.traceback)
  if not ok then error("FAIL: "..name.."\n"..tostring(err)) end
  passed=passed+1; print("  PASS "..name)
end
local function eq(a,b) assert(a==b,tostring(a).." ~= "..tostring(b)) end
local codec=require("core.codec")
local crypto=require("core.crypto")
test("SHA256 integrity vectors",function()
  eq(crypto.sha256(""),"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
  eq(crypto.sha256("abc"),"ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
  eq(crypto.sha256(string.rep("a",1000)),"41edece42d63e8d9bf515a9ba6932e1c20cbc9f5a5d134645adb5db1b9737ea3")
end)
test("Canonical codec and executable data rejection",function()
  local data={a="unicode: \195\167",b={1,true,false},c=-4.25}
  local decoded=assert(codec.decode(codec.encode(data)))
  eq(decoded.a,data.a); eq(decoded.b[2],true); eq(decoded.c,-4.25)
  eq(codec.encode({b=2,a=1}),codec.encode({a=1,b=2}))
  assert(not codec.decode("(function() while true do end end)()"))
  assert(not codec.decode("m2:s1:an1:1s1:an1:2"))
  assert(not codec.decode("s100:x"))
  assert(not codec.decode("tmore"))
  assert(not pcall(codec.encode,{fn=function() end}))
  local cycle={}; cycle.c=cycle; assert(not pcall(codec.encode,cycle))
end)

-- In-memory OpenOS filesystem; injected API errors model interrupted disk writes.
local files,dirs,failWrite,failRename,failFlush={}, {["/"]=true},nil,nil,nil
local fs={}
function fs.path(p) return p:match("^(.*)/[^/]*$") or "." end
function fs.makeDirectory(p)
  if fs.exists(p) then return nil,"file or directory with that name already exists" end
  dirs[p]=true; return true
end
function fs.exists(p) return files[p]~=nil or dirs[p] end
function fs.isDirectory(p) return dirs[p]==true end
function fs.size(p) return #(files[p] or "") end
function fs.get() return {spaceTotal=function() return 1024*1024 end,spaceUsed=function() return 0 end} end
function fs.remove(p)
  files[p]=nil; dirs[p]=nil
  for k in pairs(files) do if k:sub(1,#p+1)==p.."/" then files[k]=nil end end
  return true
end
function fs.rename(a,b)
  if failRename and b==failRename then return nil,"simulated rename failure" end
  if files[a]~=nil then files[b]=files[a]; files[a]=nil; return true end
  if dirs[a] then
    dirs[b]=true; dirs[a]=nil
    local moved={}
    for k,v in pairs(files) do if k:sub(1,#a+1)==a.."/" then moved[k]=v end end
    for k,v in pairs(moved) do files[b..k:sub(#a+1)]=v; files[k]=nil end
    return true
  end
  return nil,"missing "..a
end
function fs.concat(a,b) return (a.."/"..b):gsub("//+","/") end
local hostOpen=io.open
io.open=function(path,mode)
  if path:sub(1,#PROJECT_ROOT)==PROJECT_ROOT then return hostOpen(path,mode) end
  mode=mode or "r"
  if mode:match("^r") and files[path]==nil then return nil,"not found" end
  if mode:match("^w") then files[path]="" end
  local pos=1
  return {
    read=function(_,n)
      local data=files[path] or ""
      if n=="*a" then return data end
      if n=="*l" then return data:match("([^\n]*)") end
      if pos>#data then return nil end
      local s=data:sub(pos,pos+n-1); pos=pos+n; return s
    end,
    write=function(_,s)
      if failWrite and path==failWrite then return nil,"simulated write failure" end
      files[path]=(files[path] or "")..s; return true
    end,
    flush=function() if path==failFlush then return nil,"disk full during flush" end; return true end,
    close=function() end -- OpenOS filesystem close returns no values.
  }
end
local now=0
local components={}
local deviceInfo={}
local function callback(fn)
  -- Mirrors machine.lua componentCallback.__call from OC 1.8.3.
  return setmetatable({}, {__call=function(_,...) return fn(...) end})
end
local function proxyCallbacks(proxy)
  for name,fn in pairs(proxy) do if type(fn)=="function" then proxy[name]=callback(fn) end end
  return proxy
end
local component={}
function component.list(kind)
  local list={}; for a,p in pairs(components) do if not kind or p.type==kind then list[#list+1]=a end end
  table.sort(list)
  local i=0; return function() i=i+1; local a=list[i]; if a then return a,components[a].type end end
end
function component.proxy(address) return assert(components[address],"component removed") end
function component.isAvailable(kind) for _,p in pairs(components) do if p.type==kind then return true end end; return false end
package.preload.filesystem=function() return fs end
package.preload.component=function() return component end
package.preload.computer=function() return {uptime=function() return now end,getDeviceInfo=function() return deviceInfo end} end
local nonceCounter=0
local function nonce() nonceCounter=nonceCounter+1; return string.format("nonce-%032d",nonceCounter) end
package.preload.uuid=function() return {next=nonce} end
os.sleep=function() end
local storage=require("core.storage")
local config=require("core.config")
test("Atomic config save, backup recovery, invalid intervals",function()
  local c=config.defaults("server")
  assert(config.save(c)); c.poll=15; assert(config.save(c))
  files[config.path]="corrupt"
  local recovered,warning=config.load(); assert(recovered and warning); eq(recovered.poll,10)
  eq(files[config.path],"corrupt")
  assert(config.save(recovered)); eq(files[config.path..".corrupt"],"corrupt")
  assert(config.validate(storage.load(config.path..".bak")))
  c.heartbeat=0; assert(not config.validate(c)); c.heartbeat=5; c.port=0; assert(not config.validate(c))
  files["/atomic"]="old"; failWrite="/atomic.tmp"
  assert(not storage.atomic("/atomic","new")); eq(files["/atomic"],"old"); failWrite=nil
  failFlush="/atomic.tmp"
  assert(not storage.atomic("/atomic","new")); eq(files["/atomic"],"old"); failFlush=nil
end)
test("Legacy configuration migrates without a password and preserves modem pairing",function()
  local c=config.defaults("server")
  c.schema=1; c.key="previous-key"; c.allowedClients["legacy-client"]="main"; c.screen="saved-screen"
  files[config.path]=codec.encode(c)
  local migrated=assert(config.load())
  eq(migrated.schema,2); eq(migrated.key,nil); eq(migrated.screen,"saved-screen")
  eq(migrated.allowedClients["legacy-client"],"main")
  assert(config.save(migrated)); eq(storage.load(config.path).key,nil)
end)

local protocol=require("network.protocol")
local wire=require("network.modem")
local bus,drop={},false
local function modem(address,maxPacket)
  local opened=false
  local maxBytes=maxPacket or 8192
  deviceInfo[address]={capacity=tostring(maxBytes)}
  local m={address=address,type="modem",
    isWireless=function() return true end,isOpen=function() return opened end,
    open=function() opened=true; return true end,close=function() opened=false end,setStrength=function() end}
  local function push(target,port,magic,raw)
    assert(#magic+#raw+4<=maxBytes,"oversize packet")
    if not drop then bus[#bus+1]={from=address,to=target,port=port,magic=magic,raw=raw} end
    return true
  end
  m.send=push
  m.broadcast=function(port,magic,raw) return push(nil,port,magic,raw) end
  return proxyCallbacks(m)
end
test("OC 1.8.3 packet capacity without maxPacketSize and optional callback compatibility",function()
  local m=modem("capacity-address",2048)
  eq(m.maxPacketSize,nil); eq(type(m.send),"table")
  eq(wire.packetLimit(m),2048)
  -- The real metadata wins even if an optional callback is broken.
  m.maxPacketSize=callback(function() error("must not call when device info is present") end)
  eq(wire.packetLimit(m),2048)
  deviceInfo[m.address]=nil
  m.maxPacketSize=callback(function() return 8192 end)
  eq(wire.packetLimit(m),4096)
  m.maxPacketSize=nil
  local ok,err=pcall(wire.packetLimit,m)
  assert(not ok and tostring(err):find("getDeviceInfo",1,true))
  for _,invalid in ipairs({"garbage","0","-1","nan","inf","2048.5"}) do
    deviceInfo[m.address]={capacity=invalid}; assert(not pcall(wire.packetLimit,m))
  end
  deviceInfo[m.address]={capacity="512"}
  local small,reason=pcall(wire.packetLimit,m)
  assert(not small and tostring(reason):find("below 1024",1,true))
  deviceInfo[m.address]=nil
end)
local serverCfg=config.defaults("server")
serverCfg.allowedClients={["main-address"]="main",["side-address"]="side"}
local mainCfg=config.defaults("main")
local sideCfg=config.defaults("side")
local calls=0
local dispatchCounts={}
local function dispatch(command,args)
  calls=calls+1
  if command=="HEARTBEAT" then return {uptime=now,ae2={online=false}} end
  if command=="GET_AE2_STOCKS" then return {items=string.rep("x",10000)} end
  if command=="GET_SERVER_STATUS" then
    dispatchCounts[args.marker]=(dispatchCounts[args.marker] or 0)+1
    return {marker=args.marker}
  end
  return {}
end
local nodes={}
local function create(address,cfg)
  local n=protocol.new(cfg,modem(address),function() return now end,nonce,dispatch)
  nodes[address]=n; return n
end
local function step(seconds)
  local untilTime=now+seconds
  while now<untilTime do
    for _,n in pairs(nodes) do n:tick() end
    local frames=bus; bus={}
    for _,f in ipairs(frames) do
      for address,n in pairs(nodes) do
        if address~=f.from and (not f.to or address==f.to) then n:receive(address,f.from,f.port,f.magic,f.raw) end
      end
    end
    now=now+0.13
  end
end
local main,side,server
test("Client starts before server, discovery and three-node registration",function()
  main=create("main-address",mainCfg); side=create("side-address",sideCfg)
  step(7); eq(main.online,false); eq(side.online,false)
  server=create("server-address",serverCfg)
  step(8); assert(main.online and side.online)
  assert(server.clients["main-address"] and server.clients["side-address"])
end)
test("Fragmented response, packet budget and request correlation",function()
  local result
  assert(main:request("GET_AE2_STOCKS",{},function(data,err) assert(not err); result=data end))
  step(8); assert(result); eq(#result.items,10000)
end)
test("Side display ACL and craft commands fail closed",function()
  local err
  side:request("GET_AE2_STOCKS",{},function(_,e) err=e end)
  step(2); eq(err,"FORBIDDEN")
  local before=calls
  main:request("REQUEST_CRAFT",{amount=500},function(_,e) err=e end)
  step(2); eq(err,"UNSUPPORTED_COMMAND"); assert(calls-before<=2)
end)
test("Duplicate request executes once and mismatched ID reuse rejected",function()
  local observed=0
  -- Duplicate application requests share a request ID but have independent frame IDs.
  local id=main:request("GET_SERVER_STATUS",{marker="unique"},function(data) eq(data.marker,"unique"); observed=observed+1 end)
  local p=main.pending[id]
  local before=calls
  main.wire:send(main.server,{v=wire.VERSION,kind="REQUEST",boot=main.boot,target=main.serverBoot,id=id,body=p.data})
  step(2); eq(observed,1); eq(dispatchCounts.unique,1)
  -- Inspect cached fingerprint: both deliveries resulted in exactly one cache entry.
  local record=server.seen["main-address:"..id]; assert(record)
  local countBefore=calls
  main.wire:send(main.server,{v=wire.VERSION,kind="REQUEST",boot=main.boot,target=main.serverBoot,id=id,body={command="GET_SERVER_STATUS",args={marker="changed"}}})
  step(1); assert(calls-countBefore<=1); eq(dispatchCounts.changed,nil)
  eq(record.fingerprint,codec.encode(p.data))
end)
test("Legacy/malformed frames, wrong source, unlisted peer and stale boot ignored",function()
  local old=calls
  server:receive("server-address","attacker",34100,wire.MAGIC,"not data")
  local f={v=1,id="old",from="main-address",to="server-address",part=1,total=1,data="t"}
  server:receive("server-address","main-address",34100,"FactoryOS/1",codec.encode(f))
  f.v=wire.VERSION; f.from="wrong-address"
  server:receive("server-address","main-address",34100,wire.MAGIC,codec.encode(f))
  f.from="main-address"; f.part=0
  server:receive("server-address","main-address",34100,wire.MAGIC,codec.encode(f))
  main.wire:send("server-address",{v=wire.VERSION,kind="REQUEST",boot=main.boot,target="old-server-boot",id="replay",body={command="GET_SERVER_STATUS",args={}}})
  step(0.5); eq(calls,old)
end)
test("Link loss shows offline and recovers automatically",function()
  drop=true; step(21); assert(not main.online and not side.online)
  drop=false; step(12); assert(main.online and side.online)
end)
test("Client restart registers fresh boot; server restart reconnects",function()
  local oldBoot=main.boot; main:close(); main=create("main-address",mainCfg)
  step(7); assert(main.online); assert(main.boot~=oldBoot); eq(server.clients["main-address"].boot,main.boot)
  server:close(); server=create("server-address",serverCfg)
  step(32); assert(main.online and side.online); eq(main.serverBoot,server.boot)
end)
test("Reassembly bounds and expiration",function()
  local m=modem("receiver-address",1024)
  local cfg=config.defaults("main")
  local t=wire.new(m,cfg,function() return now end,nonce())
  local function frame(id)
    local f={v=wire.VERSION,id=id,from="server-address",to=m.address,part=1,total=64,data="x"}
    return codec.encode(f)
  end
  for i=1,20 do t:receive(m.address,"server-address",cfg.port,wire.MAGIC,frame("id"..i)) end
  local n=0; for _ in pairs(t.assemblies) do n=n+1 end; eq(n,8)
  now=now+26; t:tick(); eq(next(t.assemblies),nil)
  assert(not t:send("server-address",{blob=string.rep("x",65536)}))
end)

local function mockGpu(w,h)
  local writes=0
  local gpu={address="gpu-address",type="gpu"}
  gpu.bind=function() return true end
  gpu.maxResolution=function() return w,h end
  gpu.getResolution=function() return w,h end
  gpu.getForeground=function() return 0xffffff end
  gpu.getBackground=function() return 0 end
  gpu.getDepth=function() return 8 end
  gpu.fill=function() end
  gpu.setResolution=function(a,b) assert(a<=w and b<=h); return true end
  gpu.maxDepth=function() return 8 end
  gpu.setDepth=function() end
  gpu.setForeground=function() end
  gpu.setBackground=function() end
  gpu.set=function(x,y,s) assert(x>=1 and y>=1 and x+#s-1<=w and y<=h); writes=writes+1 end
  gpu.writes=function() return writes end
  return proxyCallbacks(gpu)
end
local hardware=require("core.hardware")
test("Missing GPU/screen/modem and ambiguous local components",function()
  components={}
  assert(not hardware.check(mainCfg))
  components.m=modem("m"); assert(not hardware.check(mainCfg))
  components.g=mockGpu(80,25); assert(not hardware.check(mainCfg))
  components.s={type="screen",address="s"}; assert(hardware.check(mainCfg))
  components.s2={type="screen",address="s2"}; assert(not hardware.check(mainCfg))
  mainCfg.screen="s"; assert(hardware.check(mainCfg)); mainCfg.screen=""
  components={}
end)
test("AE2 real-shaped stacks preserve metadata/NBT, disconnect clears stale data",function()
  local cfg=config.defaults("server")
  local ae=require("server.ae2").new(cfg)
  local p={address="me1",type="me_interface"}
  p.getItemsInNetwork=function() return {
    {name="mod:alloy",label="Alloy",damage=0,size=12,hasTag=false},
    {name="mod:alloy",label="Alloy",damage=1,size=3,hasTag=true},
    {name="mod:alloy",label="Alloy",damage=1,size=4,hasTag=true,tag="different"}}
  end
  p.getCpus=function() return {{name="CPU A",busy=true,storage=1024,coprocessors=1}} end
  p.getStoredPower=function() return 20 end; p.getMaxStoredPower=function() return 100 end
  proxyCallbacks(p); eq(type(p.getItemsInNetwork),"table")
  components={me1=p}; ae:poll(); assert(ae.online); eq(#ae.items,3); eq(ae.energy.unit,"AE")
  local stocks=ae:stocks({query="ALLOY",page=1}); eq(stocks.total,3)
  local ambiguous=0; for _,item in ipairs(ae.items) do if not item.identityComplete then ambiguous=ambiguous+1 end end; eq(ambiguous,1)
  eq(ae:jobs().existingJobDetails,"unsupported")
  p.getItemsInNetwork=callback(function() error("network disconnected") end)
  ae:poll(); assert(not ae.online); eq(#ae.items,0); assert(not ae.energy.supported)
  components={}; ae:poll(); assert(not ae.online)
end)
test("AE2 preserves native failure reasons, checks power and recovers without stale data",function()
  local cfg=config.defaults("server"); local ae=require("server.ae2").new(cfg)
  local reads=0; local powered=true; local failure=false
  local p={address="me-diagnostic",type="me_interface",
    isNetworkPowered=callback(function() return powered end),
    getItemsInNetwork=callback(function()
      reads=reads+1
      if failure then return nil,"no ae grid" end
      return {{name="minecraft:iron_ingot",size=8}}
    end)}
  components={[p.address]=p}; ae:poll(); assert(ae.online); eq(reads,1)
  failure=true; ae:poll(); assert(not ae.online); eq(ae.error,"getItemsInNetwork: no ae grid")
  eq(ae:summary().address,p.address); eq(#ae.items,0); assert(not ae:stocks({}))
  powered=false; ae:poll(); eq(reads,2); eq(ae:summary().powered,false)
  assert(ae.error:find("unpowered",1,true)); eq(#ae.cpus,0)
  powered=true; failure=false; ae:poll(); assert(ae.online); eq(#ae.items,1)
  assert(ae.cpuError:find("getCpus",1,true)); assert(not ae.energy.supported)
  cfg.ae2Enabled=false; ae:poll(); assert(not ae.online); eq(#ae.items,0); eq(ae.address,nil)
  components={}
end)
test("AE2 exact component selection, missing pinned address and transition reason logging",function()
  local cfg=config.defaults("server"); local time=0; local logs={}
  local server=require("server.main").new(cfg,function() return time end,function(_,s) logs[#logs+1]=s end)
  local function poll() server:tick(); time=time+cfg.poll end
  local p={address="me-a",type="me_interface",getItemsInNetwork=callback(function() return {} end)}
  components={[p.address]=p,["me-b"]={address="me-b",type="me_controller"}}
  local found=server.ae2:candidates(); eq(#found,2); eq(found[1].address,"me-a")
  poll(); assert(logs[1]:find("Multiple AE2 components",1,true)); poll(); eq(#logs,1)
  cfg.ae2Address="me-a"; poll(); assert(server.ae2.online); eq(#logs,2)
  p.getItemsInNetwork=callback(function() return nil,"grid removed" end)
  poll(); assert(logs[3]:find("getItemsInNetwork: grid removed",1,true)); poll(); eq(#logs,3)
  components["me-a"]=nil; poll(); assert(logs[4]:find("missing/offline: me-a",1,true)); eq(server.ae2.address,nil)
  components={}
end)
test("AE2 CLI samples at ten second intervals and reports exact failure",function()
  local oldPrint,oldSleep,oldLoad=print,os.sleep,config.load; local output={}; local waits=0
  package.preload.serialization=function() return {serialize=codec.encode} end
  local cfg=config.defaults("server"); config.load=function() return cfg end
  print=function(s) output[#output+1]=s end
  components={me={address="me",type="me_interface",getItemsInNetwork=callback(function() return {} end)}}
  os.sleep=function(seconds) eq(seconds,10); waits=waits+1; components={} end
  local ok,why=pcall(function() require("core.cli").main({"ae2","2"}) end)
  print=oldPrint; os.sleep=oldSleep; config.load=oldLoad
  assert(ok,why); eq(waits,1)
  local result=table.concat(output,"\n"); assert(result:find("[1/2] ONLINE",1,true))
  assert(result:find("[2/2] OFFLINE",1,true)); assert(result:find("Adapter component missing/offline",1,true))
end)
test("GPU bounds, role layouts, unchanged frame writes zero cells, screen-filtered touch",function()
  local Renderer=require("ui.renderer")
  local screens=require("ui.screens")
  for _,dim in ipairs({{160,50},{80,25},{50,16},{40,12}}) do
    for _,role in ipairs({"main","side","server"}) do
      local gpu=mockGpu(dim[1],dim[2]); local r=Renderer.new(gpu,{address="screen1"},role)
      local status={ae2={online=true,itemTypes=4},clients={},power={ae2={supported=true,stored=20,capacity=100,unit="AE"}}}
      local n={online=true,status=status}
      local state={tab=1,serverStatus=status}
      screens.draw(r,role,n,state); local writes=gpu.writes()
      screens.draw(r,role,n,state); eq(gpu.writes(),writes)
      for tab=1,9 do
        state.tab=tab; screens.draw(r,role,n,state)
        if role=="main" and tab==2 then state.editing=true; state.draft="alloy"; screens.draw(r,role,n,state); state.editing=false end
      end
      r:begin(); r:button(2,5,10,"test","id"); eq(r:touch("wrong",3,5),nil); eq(r:touch("screen1",3,5),"id")
    end
  end
end)

local updater=require("core.updater")
test("Server inventory sorts the entire result and filters craftables/favorite variants before paging",function()
  local ae=require("server.ae2").new(config.defaults("server"))
  ae.online=true
  for i=1,60 do ae.items[i]={name="example:item_"..i,label=string.format("Item %02d",i),damage=0,size=i*10,tag="",hasTag=false,identityComplete=true,isCraftable=i%2==0} end
  local data=assert(ae:stocks({page=1,sort="amount"}))
  eq(#data.items,24); eq(data.items[1].size,600); eq(data.items[24].size,370); eq(data.pages,3)
  local craft=assert(ae:stocks({page=1,filter="craftable"})); eq(craft.total,30); eq(craft.items[1].label,"Item 02")
  local id=require("core.items")
  local fav=assert(ae:stocks({page=1,filter="favorites",favoriteKeys={id.key(ae.items[59]),id.key(ae.items[60])},sort="amount"}))
  eq(fav.total,2); eq(fav.items[1].size,600); eq(fav.items[2].size,590)
  eq(ae:stocks({page=999}).page,3)
  eq(ae:stocks({query=".*"}).total,0)
  assert(not ae:stocks({filter="unknown"})); assert(not ae:stocks({sort="unknown"}))
  assert(not ae:stocks({filter="favorites",favoriteKeys={string.rep("x",1025)}}))
end)
local function displayFixture()
  local prefs=require("client.preferences")
  files[prefs.path]=nil; files[prefs.path..".bak"]=nil
  local displayTime=100
  local pending={}
  local net={online=true,lastSeen=100,status={ae2={online=true,itemTypes=60},power={ae2={supported=true,stored=750,capacity=1000}},clients={}}}
  function net:request(command,args,fn) pending[#pending+1]={command=command,args=args,callback=fn}; return "request"..#pending end
  local state=require("client.main_display").new(net,function() return displayTime end)
  local function take(command)
    for i,r in ipairs(pending) do if r.command==command then table.remove(pending,i); return r end end
    error("Missing request: "..command)
  end
  return net,state,pending,take,function(delta) displayTime=displayTime+delta end
end
local function stockPage(page)
  local rows={}
  for i=1,24 do rows[i]={name="example:item_"..i,label="Item "..i,damage=0,size=i*10,hasTag=false,tag="",identityComplete=true,isCraftable=true} end
  return {items=rows,page=page or 1,pages=3,total=60,filter="all",sort="name"}
end
test("Display search commits on Enter and stale asynchronous responses cannot replace a newer query",function()
  local net,state,pending,take,advance=displayFixture()
  state:tick(); eq(#pending,1)
  take("GET_CRAFTING_JOBS").callback({cpus={},error=""})
  state:touch("tab:2")
  local first=take("GET_AE2_STOCKS")
  state:touch("search"); state:touch("key:a"); state:touch("key:l"); state:paste("loy\n")
  eq(state.query,""); eq(state.draft,"alloy"); eq(#pending,1) -- CPU refresh only, no per-keystroke stock traffic.
  state:touch("tab:1"); eq(state.tab,2) -- modal blocks background actions.
  state:key(13,28); eq(state.query,"alloy"); eq(state.editing,false)
  local latest=take("GET_AE2_STOCKS"); eq(latest.args.query,"alloy")
  first.callback(stockPage(1)); eq(state.stocks,nil)
  latest.callback(stockPage(1)); eq(state.stocks.total,60); eq(state.loadingStocks,false)
  state:touch("search"); state:touch("key:x"); state:key(0,1)
  eq(state.query,"alloy"); eq(state.editing,false)
  advance(11); state:tick(); local poll=take("GET_AE2_STOCKS"); state:tick(); eq(state.loadingStocks,true)
  local remaining=#pending; state:tick(); eq(#pending,remaining)
  poll.callback(nil,"TIMEOUT"); eq(state.stocks,nil); eq(state.stockError,"TIMEOUT")
end)
test("Favorites persist per display, reject ambiguous NBT and roll back on disk failure",function()
  local net,state=displayFixture()
  local item=stockPage(1).items[1]
  state:toggleFavorite(item); assert(state:isFavorite(item))
  local reloaded=require("client.main_display").new(net,function() return 100 end)
  assert(reloaded:isFavorite(item))
  item.size=999; assert(reloaded:isFavorite(item)) -- quantity is not identity.
  local ambiguous={name="example:nbt",damage=0,hasTag=true,tag="",identityComplete=false,label="NBT"}
  state:toggleFavorite(ambiguous); assert(not state:isFavorite(ambiguous))
  local second=stockPage(1).items[2]
  failWrite=require("client.preferences").path..".tmp"
  state:toggleFavorite(second); assert(not state:isFavorite(second)); eq(state.message.kind,"warn")
  failWrite=nil
  for i=2,32 do state:toggleFavorite({name="example:favorite_"..i,label="Favorite "..i,damage=0,hasTag=false,tag=""}) end
  state:toggleFavorite(second); assert(not state:isFavorite(second)); eq(state.message.kind,"warn")
  state:toggleFavorite(item); assert(not state:isFavorite(item))
end)
test("Small display pagination visits every row and crosses server pages in both directions",function()
  local _,state,_,take=displayFixture()
  state:touch("tab:2"); take("GET_AE2_STOCKS").callback(stockPage(1))
  state.visibleRows=7
  for _,offset in ipairs({7,14,21}) do state:touch("next"); eq(state.rowOffset,offset) end
  state:touch("next"); eq(state.page,2); eq(state.rowOffset,0)
  take("GET_AE2_STOCKS").callback(stockPage(2))
  state:touch("prev"); eq(state.page,1)
  take("GET_AE2_STOCKS").callback(stockPage(1)); eq(state.rowOffset,21)
  state:touch("prev"); eq(state.rowOffset,14)
  state:touch("sort"); local sorted=take("GET_AE2_STOCKS"); eq(sorted.args.sort,"amount"); eq(sorted.args.page,1)
  local sortedData=stockPage(1); sortedData.sort="amount"; sorted.callback(sortedData)
  state:toggleFavorite(sortedData.items[1]); state:touch("filter:favorites")
  local filtered=take("GET_AE2_STOCKS"); eq(filtered.args.filter,"favorites"); eq(#filtered.args.favoriteKeys,1)
end)
test("Offline display clears cached stock/jobs and reconnects without accepting old replies",function()
  local net,state,_,take=displayFixture()
  state:tick(); local jobs=take("GET_CRAFTING_JOBS")
  state:touch("tab:2"); local stocks=take("GET_AE2_STOCKS")
  net.online=false; state:tick()
  stocks.callback(stockPage(1)); jobs.callback({cpus={}})
  eq(state.stocks,nil); eq(state.jobs,nil); eq(state.loadingStocks,false); eq(state.loadingJobs,false)
  net.online=true; state:tick()
  take("GET_AE2_STOCKS").callback(stockPage(1)); take("GET_CRAFTING_JOBS").callback({cpus={},error=""})
  assert(state.stocks and state.jobs)
end)
test("Main dashboard touch areas, modal keyboard and offline/AE2 stale-data suppression",function()
  local net,state=displayFixture()
  state.tab=2; state.stocks=stockPage(1); state.stocks.items[1].size=987654321; state.selected=state.stocks.items[1]
  local gpu=mockGpu(160,50); local r=require("ui.renderer").new(gpu,{address="main-screen"},"main")
  local screens=require("ui.screens")
  local function drawText()
    screens.draw(r,"main",net,state,function() return 100 end)
    local out={}; for _,row in ipairs(r.front) do out[#out+1]=table.concat(row.chars) end
    return table.concat(out,"\n")
  end
  assert(drawText():find("987,654,321",1,true))
  local nav
  for _,b in ipairs(r.buttons) do if b.id=="tab:1" then nav=b end end
  assert(nav and nav.h==3); eq(r:touch("main-screen",nav.x,nav.y+2),"tab:1")
  state:touch("search"); drawText(); eq(r:touch("main-screen",nav.x,nav.y+2),nil)
  local letter
  for _,b in ipairs(r.buttons) do assert(b.id:match("^key:")); if b.id=="key:a" then letter=b end end
  assert(letter); state:touch(r:touch("main-screen",letter.x,letter.y)); eq(state.draft,"a")
  state:touch("key:cancel"); net.online=false; assert(not drawText():find("987,654,321",1,true))
  net.online=true; net.status.ae2.online=false; assert(not drawText():find("987,654,321",1,true))
end)
local function release(version)
  local entries,payload={},{}
  for _,path in ipairs({"boot.lua","core/cli.lua","core/config.lua","core/runtime.lua","core/updater.lua"}) do
    local s="-- "..version.." "..path.."\nreturn {}\n"
    entries[#entries+1]={path=path,size=#s,sha256=crypto.sha256(s)}; payload["src/"..path]=s
  end
  local manifest={schema=1,release=version,files=entries}
  payload["manifest.dat"]=codec.encode(manifest)
  return payload,manifest
end
test("Staged install, interrupted/corrupt update and verified rollback",function()
  local payload=release("0.1.0-first")
  local function get(path) return assert(payload[path]) end
  local manifest=updater.stage(get); updater.activate(manifest)
  local active=files[updater.root.."/active"]
  payload=release("0.1.0-next"); payload["src/core/cli.lua"]="corrupt"
  assert(not pcall(updater.stage,get)); eq(files[updater.root.."/active"],active)
  payload=release("0.1.0-next")
  local downloads=0
  assert(not pcall(updater.stage,function(path) downloads=downloads+1; if downloads==3 then error("connection lost") end; return get(path) end))
  eq(files[updater.root.."/active"],active)
  manifest=updater.stage(get); updater.activate(manifest); assert(files[updater.root.."/active"]~=active)
  updater.rollback(); eq(files[updater.root.."/active"],active)
  assert(not pcall(updater.validate,{schema=1,release="../escape",files={}}))
  local _,bad=release("0.1.0-safe"); bad.files[1].path="../escape.lua"; assert(not pcall(updater.validate,bad))
end)
test("Missing Internet Card and unsafe URLs rejected before download",function()
  components={}
  assert(not pcall(updater.fetch,"https://example.com/file",100))
  assert(not pcall(updater.fetch,"http://example.com/file",100))
  assert(not pcall(updater.source,""))
end)
test("HTTP response handling, timeout, length limit and handle closure",function()
  local closed,mode=false,"ok"
  local internet={address="internet1",type="internet",isHttpEnabled=function() return true end}
  internet.request=function()
    local reads=0
    return {
      finishConnect=function() if mode=="timeout" then now=now+30; return false end; return true end,
      response=function() return mode=="404" and 404 or 200 end,
      read=function() reads=reads+1; if reads==1 then return "payload" end end,
      close=function() closed=true end
    }
  end
  components={internet1=internet}
  eq(updater.fetch("https://example.com/file",10),"payload"); assert(closed)
  for _,m in ipairs({"404","timeout","length"}) do
    mode=m; closed=false
    assert(not pcall(updater.fetch,"https://example.com/file",m=="length" and 2 or 10)); assert(closed)
  end
  components={}
end)
test("Generated installer has no password prompt and separates all input lines",function()
  local originalRead,originalWrite,originalPrint=io.read,io.write,print
  local readAnswer
  local term={read=function(options)
    eq(options.pwchar,nil); eq(options.dobreak,false)
    return readAnswer()
  end}
  package.preload.term=function() return term end
  local savedPreload=package.preload["core.config"]
  local code=READ_PROJECT_FILE(PROJECT_ROOT.."/dist/factoryos-offline.lua")
  for _,role in ipairs({"server","main","side"}) do
    files[config.path]=nil; files[config.path..".bak"]=nil
    components={}
    components["local-modem"]=modem("local-modem")
    components["gpu-address"]=mockGpu(160,50)
    components["screen-address"]={address="screen-address",type="screen"}
    local answers=role=="server" and {"1","main-address","side-address"} or {role=="main" and "2" or "3","server-address"}
    local index,awaitingNewline,newlines=0,false,0
    readAnswer=function()
      assert(not awaitingNewline,"Previous input was not followed by a newline")
      index=index+1; awaitingNewline=true
      return assert(answers[index],"Unexpected installer prompt (password prompt must not exist)").."\n"
    end
    io.read=function() error("Installer must reset the OpenOS cursor on every input") end
    io.write=function(s)
      if awaitingNewline then eq(s,"\n"); awaitingNewline=false; newlines=newlines+1 end
    end
    print=function() end
    -- OpenOS exposes package.loaded/path but no package.preload or searchers.
    -- Its native require must never be asked for bundled FactoryOS modules.
    local env=setmetatable({package={loaded={}},require=function(name)
      assert(not name:match("^core%."),"Bootstrap leaked into native OpenOS require")
      return require(name)
    end},{__index=_ENV})
    local ok,err=pcall(assert(load(code,"=offline-installer","t",env)))
    io.read=originalRead; io.write=originalWrite; print=originalPrint
    assert(ok,err)
    eq(index,#answers); eq(newlines,#answers); eq(awaitingNewline,false)
    local c=assert(config.load()); eq(c.role,role); eq(c.key,nil); eq(c.schema,2)
    assert(files["/bin/factoryos.lua"])
    local active=files[updater.root.."/active"]:match("([^\n]+)")
    assert(files[updater.root.."/releases/"..active.."/core/runtime.lua"])
    eq(package.preload["core.config"],savedPreload)
  end
end)
test("CLI service lifecycle uses detached thread and graceful stop; busy updates rejected",function()
  local events={},{}
  local threads={}
  local originalSleep=os.sleep
  os.sleep=function(dt)
    local _,isMain=coroutine.running()
    if not isMain then return coroutine.yield() end
    now=now+(dt or 0)
    for _,t in ipairs(threads) do
      if coroutine.status(t.co)~="dead" then local ok,err=coroutine.resume(t.co); assert(ok,err) end
    end
  end
  package.preload.thread=function() return {create=function(fn)
    local t={co=coroutine.create(fn)}
    function t:status() return coroutine.status(self.co)=="dead" and "dead" or "running" end
    function t:detach() self.detached=true; return self end
    threads[#threads+1]=t; return t
  end} end
  package.preload.event=function() return {pull=function(timeout)
    now=now+(timeout or 0)
    local _,isMain=coroutine.running()
    if not isMain then coroutine.yield() end
    return nil
  end} end
  package.preload.serialization=function() return {serialize=codec.encode} end
  local cli=require("core.cli")
  cli.main({"start"},updater.root)
  os.sleep(0.2); os.sleep(0.2)
  local service=package.loaded["factoryos.service"]
  assert(service.running and service.thread.detached)
  assert(not pcall(cli.main,{"update","https://example.com"},updater.root))
  assert(not pcall(cli.main,{"config","port","34000"},updater.root))
  cli.main({"stop"},updater.root); assert(not service.running); assert(not service.error,service.error)
  eq(service.thread:status(),"dead")
  os.sleep=originalSleep
end)
test("Foreground startup works with an empty allowlist and OC callable-table callbacks",function()
  local event=require("event")
  local originalPull=event.pull
  event.pull=function(timeout) now=now+(timeout or 0); return "interrupted" end
  local cli=require("core.cli")
  for _,role in ipairs({"server","main","side"}) do
    local cfg=config.defaults(role)
    assert(config.save(cfg)); eq(next(cfg.allowedClients),nil)
    eq(components["local-modem"].maxPacketSize,nil)
    local gpu=components["gpu-address"]
    local before=gpu.writes()
    cli.main({"start","--foreground"},updater.root)
    local service=package.loaded["factoryos.service"]
    eq(service.role,role); eq(service.running,false); eq(service.error,nil)
    assert(gpu.writes()>before,"Foreground panel was not drawn")
  end
  event.pull=originalPull
end)
test("Installed launcher recovers active.bak and preserves OpenOS core modules",function()
  local root=updater.root
  local active=files[root.."/active"]
  files[root.."/active.bak"]=active; files[root.."/active"]=nil
  local sentinel={}
  local env
  env=setmetatable({package={loaded={["core.full_filesystem"]=sentinel,["core.cli"]={old=true}},path="native"},
    require=function(name)
      eq(name,"core.cli")
      return {main=function(args,selectedRoot) eq(args[1],"status"); eq(selectedRoot,root); return "routed" end}
    end,
    loadfile=function(path) return assert(load(assert(files[path],path),path,"t",env)) end
  },{__index=_ENV})
  eq(assert(load(files["/bin/factoryos.lua"],"=installed-launcher","t",env))("status"),"routed")
  eq(env.package.loaded["core.full_filesystem"],sentinel)
  eq(env.package.loaded["core.cli"],nil)
  assert(env.package.path:find(active:match("([^\n]+)"),1,true))
  files[root.."/active"]=active
end)
test("Foreground autostart preserves user shell setup, is idempotent and runs once per boot",function()
  local startup=require("core.autostart")
  files[startup.path]="echo existing-user-command\n"
  startup.ensure(true); local installed=files[startup.path]
  assert(installed:sub(1,27)=="echo existing-user-command\n")
  startup.ensure(true); eq(files[startup.path],installed)
  local count=0
  local env=setmetatable({package={loaded={}},loadfile=function(path)
    eq(path,"/bin/factoryos.lua")
    return function(cmd,mode) eq(cmd,"start"); eq(mode,"--foreground"); count=count+1 end
  end},{__index=_ENV})
  local boot=assert(load(files[startup.launcher],"=startup","t",env))
  boot(); boot(); eq(count,1)
  startup.ensure(false); eq(files[startup.path],"echo existing-user-command\n")
  files[startup.path]="echo keep\n"..startup.first.."\npartial"
  assert(not pcall(startup.ensure,true)); eq(files[startup.path],"echo keep\n"..startup.first.."\npartial")
  files[startup.path]=""
end)
test("Legacy configuration enables foreground startup and periodic checks without losing addresses",function()
  local cfg=config.defaults("main")
  cfg.autoStart=nil; cfg.updateAutoCheck=nil; cfg.updateCheckInterval=nil; cfg.updateBase=""; cfg.screen="kept-screen"
  files[config.path]=codec.encode(cfg)
  local migrated=assert(config.load())
  eq(migrated.autoStart,true); eq(migrated.updateAutoCheck,true); eq(migrated.updateCheckInterval,900)
  eq(migrated.screen,"kept-screen"); assert(migrated.updateBase:match("^https://"))
  migrated.updateCheckInterval=0; assert(not config.validate(migrated))
end)

-- Cooperative worker scheduler. Update code is real Lua; HTTP/disk/modems remain mocks.
local savedThread,savedSleep=package.loaded.thread,os.sleep
package.loaded.thread={create=function(fn)
  local t={co=coroutine.create(fn),killed=false}
  function t:status() return self.killed and "dead" or coroutine.status(self.co)=="dead" and "dead" or "running" end
  function t:kill() self.killed=true end
  return t
end}
package.loaded["core.updates"]=nil
local Updates=require("core.updates")
os.sleep=function(delay)
  local _,mainThread=coroutine.running()
  if not mainThread then return coroutine.yield(delay or 0) end
  now=now+(delay or 0)
end
local sourceOriginal=updater.source
local httpPayload,httpReads,actor,corruptWire,disconnectWire,activeClient
local wake={}
updater.source=function()
  assert(actor=="server","Display attempted to use Internet instead of wireless")
  return function(path,limit)
    httpReads[path]=(httpReads[path] or 0)+1
    local data=assert(httpPayload[path],"HTTP connection lost")
    assert(#data<=limit); return data
  end
end
local function updatePayload(version)
  local payload,manifest=release(version)
  for _,file in ipairs(manifest.files) do
    if file.path=="core/cli.lua" then
      local s=string.rep("-- network transfer fixture\n",160).."return {}\n"
      payload["src/"..file.path]=s; file.size=#s; file.sha256=crypto.sha256(s)
    end
  end
  manifest.version="0.3.1"; payload["manifest.dat"]=codec.encode(manifest)
  return payload,manifest
end
local function setupUpdates(label,realNetwork)
  httpPayload=updatePayload(label.."-new"); httpReads={}; corruptWire=false; disconnectWire=false
  local cfgS=config.defaults("server"); cfgS.updateAutoCheck=false
  local cfgC=config.defaults("main"); local cfgD=config.defaults("side")
  local serverManager,clientManager,sideManager
  local serverNet,clientNet,sideNet
  local serverRoot,clientRoot,sideRoot="/test-updates/"..label.."/server","/test-updates/"..label.."/main","/test-updates/"..label.."/side"
  for _,root in ipairs({serverRoot,clientRoot,sideRoot}) do files[root.."/active"]=label.."-old\n" end
  if realNetwork then
    bus={}; nodes={}
    cfgS.allowedClients={["update-main"]="main",["update-side"]="side"}
    serverNet=protocol.new(cfgS,modem("update-server",1024),function() return now end,nonce,function(command,args)
      if command=="GET_UPDATE_INFO" or command=="GET_UPDATE_FILE" then return serverManager:serve(command,args) end
      return {update=serverManager:public()}
    end)
    clientNet=protocol.new(cfgC,modem("update-main",1024),function() return now end,nonce,function() return {} end)
    sideNet=protocol.new(cfgD,modem("update-side",1024),function() return now end,nonce,function() return {} end)
    nodes={["update-server"]=serverNet,["update-main"]=clientNet,["update-side"]=sideNet}
  else
    serverNet={online=true}
    local function request(self,command,args,fn)
      actor="server"
      local data,err=serverManager:serve(command,args)
      actor=nil
      if command=="GET_UPDATE_FILE" and corruptWire then data.data="!"..data.data:sub(2); corruptWire=false end
      if command=="GET_UPDATE_FILE" and disconnectWire then self.online=false end
      fn(data,err); return nonce()
    end
    clientNet={online=true,status={},request=request}; sideNet={online=true,status={},request=request}
  end
  local productionBusy=false
  serverManager=Updates.new(cfgS,serverNet,function() return now end,{}, {root=serverRoot,cacheRoot="/test-cache/"..label,isIdle=function() return not productionBusy,"CPU mesgul" end})
  clientManager=Updates.new(cfgC,clientNet,function() return now end,{}, {root=clientRoot})
  sideManager=Updates.new(cfgD,sideNet,function() return now end,{}, {root=sideRoot})
  local managers={serverManager,clientManager,sideManager}
  local function drive(done,seconds)
    local deadline=now+(seconds or 120)
    while not done() do
      assert(now<deadline,"Update scheduler timeout")
      for _,m in ipairs(managers) do
        local worker=m.worker
        if worker and worker:status()~="dead" and now>=(wake[worker.co] or 0) then
          actor=m==serverManager and "server" or "display"
          local ok,delay=coroutine.resume(worker.co); assert(ok,delay)
          wake[worker.co]=now+(tonumber(delay) or 0); actor=nil
        end
      end
      if realNetwork then step(0.13) else now=now+0.05 end
    end
  end
  return {server=serverManager,main=clientManager,side=sideManager,serverNet=serverNet,mainNet=clientNet,sideNet=sideNet,drive=drive,
    serverRoot=serverRoot,mainRoot=clientRoot,sideRoot=sideRoot,cfg=cfgS,busy=function(v) productionBusy=v end}
end
test("Periodic GitHub checks download metadata only and never activate an update",function()
  local t=setupUpdates("periodic")
  t.cfg.updateAutoCheck=true; now=t.server.nextCheck+1; t.server:tick()
  t.drive(function() return not t.server.busy end)
  eq(httpReads["manifest.dat"],1); eq(t.server.phase,"available"); eq(t.server.readyManifest,nil)
  eq(files[t.serverRoot.."/active"],"periodic-old\n")
  for path in pairs(httpReads) do eq(path,"manifest.dat") end
  t.server:tick(); eq(t.server.busy,false)
  now=t.server.nextCheck+1; t.server:tick(); t.drive(function() return not t.server.busy end)
  eq(httpReads["manifest.dat"],2); eq(t.server.readyManifest,nil)
end)
test("Displays stage verified updates over wireless without Internet or activating before shutdown",function()
  local t=setupUpdates("wireless")
  t.server:check(); t.drive(function() return not t.server.busy end)
  t.main:check(); t.drive(function() return not t.main.busy end)
  eq(t.main.phase,"available")
  t.main:apply(); t.drive(function() return not t.main.busy end)
  assert(t.main.readyManifest,t.main.message); eq(t.main.phase,"ready")
  eq(files[t.mainRoot.."/active"],"wireless-old\n"); eq(files[t.serverRoot.."/active"],"wireless-old\n")
  t.side:apply(); t.drive(function() return not t.side.busy end)
  assert(t.side.readyManifest,t.side.message)
  eq(httpReads["src/core/cli.lua"],1) -- Server cache shared by both displays.
  local mf=t.main.readyManifest
  for _,file in ipairs(mf.files) do eq(crypto.sha256(files[t.mainRoot.."/releases/"..mf.release.."/"..file.path]),file.sha256) end
  assert(not t.server:serve("GET_UPDATE_FILE",{release=mf.release,path="../config.dat",offset=0}))
  assert(not t.server:serve("GET_UPDATE_FILE",{release=mf.release,path="core/cli.lua",offset=-1}))
  assert(not t.server:serve("GET_UPDATE_FILE",{release="other",path="core/cli.lua",offset=0}))
end)
test("A corrupt wireless chunk fails integrity and keeps the installed release",function()
  local t=setupUpdates("corrupt")
  t.server:check(); t.drive(function() return not t.server.busy end)
  corruptWire=true; t.main:apply(); t.drive(function() return not t.main.busy end)
  eq(t.main.phase,"error"); eq(t.main.readyManifest,nil); eq(files[t.mainRoot.."/active"],"corrupt-old\n")
end)
test("Lost wireless connection and explicit cancellation preserve the previous release",function()
  local t=setupUpdates("disconnect")
  t.server:check(); t.drive(function() return not t.server.busy end)
  disconnectWire=true; t.main:apply(); t.drive(function() return not t.main.busy end)
  eq(t.main.phase,"error"); eq(t.main.readyManifest,nil); eq(files[t.mainRoot.."/active"],"disconnect-old\n")
  disconnectWire=false; t.mainNet.online=true; t.main:apply()
  t.drive(function() return t.main.total>0 end); t.main:close()
  eq(files[t.mainRoot.."/active"],"disconnect-old\n"); eq(t.main.readyManifest,nil); assert(t.main.closed)
end)
test("Busy production blocks apply and a late busy state cannot publish a ready manifest",function()
  local t=setupUpdates("busy")
  t.busy(true); t.server:apply(); t.drive(function() return not t.server.busy end)
  eq(t.server.phase,"error"); eq(t.server.readyManifest,nil); eq(next(httpReads),nil)
  t.busy(false); t.server:apply()
  t.drive(function() return t.server.progress>=3 end)
  t.busy(true); t.drive(function() return not t.server.busy end)
  eq(t.server.phase,"error"); eq(t.server.readyManifest,nil); eq(files[t.serverRoot.."/active"],"busy-old\n")
end)
test("Two displays update through the real protocol and 1024-byte packet budget",function()
  local t=setupUpdates("transport",true)
  t.drive(function() return t.mainNet.online and t.sideNet.online end,60)
  t.server:check(); t.drive(function() return not t.server.busy end)
  t.main:apply(); t.side:apply()
  t.drive(function() return not t.main.busy and not t.side.busy end,240)
  assert(t.main.readyManifest,t.main.message); assert(t.side.readyManifest,t.side.message)
  eq(files[t.mainRoot.."/active"],"transport-old\n"); eq(files[t.sideRoot.."/active"],"transport-old\n")
  local cached=0; for _ in pairs(t.serverNet.seen) do cached=cached+1 end; assert(cached<128)
  for _,entry in pairs(t.serverNet.seen) do assert(not entry.fingerprint:find("GET_UPDATE_FILE",1,true)) end
end)
test("Heartbeat advertises a newer release after a previous successful client check",function()
  local t=setupUpdates("newer")
  t.server:check(); t.drive(function() return not t.server.busy end)
  t.main:check(); t.drive(function() return not t.main.busy end)
  local old=t.main.manifest.release
  t.mainNet.status={update={release="next-release",version="0.4.0",canApply=true}}
  t.main.phase="current"; t.main:tick()
  eq(t.main.manifest,nil); eq(t.main.phase,"available"); eq(t.main:public().release,"next-release")
  assert(t.main:public().release~=old)
end)
test("Runtime closes modem and GUI before activating a verified release and rebooting",function()
  local payload,manifest=release("runtime-ready")
  updater.stage(function(path) return payload[path] end,updater.root,{quiet=true})
  local originalNew,originalActivate=Updates.new,updater.activate
  local computer=require("computer"); local originalShutdown=computer.shutdown
  local event=require("event"); local originalPull=event.pull
  local originalFill=components["gpu-address"].fill
  local savedActive=files[updater.root.."/active"]
  local service={stop=false}; local closed,filled,activated,rebooted=false,false,false,false
  Updates.new=function() return {phase="ready",busy=false,readyManifest=manifest,
    tick=function() end,public=function() return {phase="ready",busy=true} end,close=function() closed=true end} end
  components["gpu-address"].fill=callback(function() filled=true end)
  event.pull=function() return nil end
  updater.activate=function(m,root)
    assert(not service.running and closed and filled)
    assert(not components["local-modem"].isOpen(34100))
    originalActivate(m,root); activated=true
  end
  computer.shutdown=function(reboot) assert(reboot and activated and closed); rebooted=true end
  local ok,err=require("core.runtime").run(config.defaults("side"),service)
  assert(ok,err); assert(rebooted); eq(files[updater.root.."/active"],manifest.release.."\n")
  service={stop=false}; closed=false; filled=false; activated=false; rebooted=false
  event.pull=function() return "interrupted" end
  local stopped,why=require("core.runtime").run(config.defaults("side"),service)
  assert(stopped,why); eq(service.applyUpdate,nil); eq(rebooted,false)
  service={stop=false}; event.pull=function() return nil end
  updater.activate=function() error("activation rejected") end
  local failed,reason=require("core.runtime").run(config.defaults("side"),service)
  assert(not failed and tostring(reason):find("activation rejected",1,true)); eq(rebooted,false)
  Updates.new=originalNew; updater.activate=originalActivate; computer.shutdown=originalShutdown
  event.pull=originalPull; components["gpu-address"].fill=originalFill; files[updater.root.."/active"]=savedActive
end)
test("A hash-correct update with invalid Lua syntax is rejected before activation",function()
  local payload,manifest=release("invalid-syntax")
  local bad="function this is not valid Lua"
  payload["src/core/cli.lua"]=bad
  for _,f in ipairs(manifest.files) do if f.path=="core/cli.lua" then f.size=#bad; f.sha256=crypto.sha256(bad) end end
  payload["manifest.dat"]=codec.encode(manifest)
  local root="/test-updates/syntax"; files[root.."/active"]="previous\n"
  local ok,err=pcall(updater.stage,function(path) return payload[path] end,root,{quiet=true})
  assert(not ok and tostring(err):find("Invalid Lua source",1,true)); eq(files[root.."/active"],"previous\n")
end)
updater.source=sourceOriginal; os.sleep=savedSleep; package.loaded.thread=savedThread
print("TOTAL "..passed.." passed")
