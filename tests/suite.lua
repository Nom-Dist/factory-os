local passed=0
local function test(name,fn)
  local ok,err=xpcall(fn,debug.traceback)
  if not ok then error("FAIL: "..name.."\n"..tostring(err)) end
  passed=passed+1; print("  PASS "..name)
end
local function eq(a,b) assert(a==b,tostring(a).." ~= "..tostring(b)) end
local codec=require("core.codec")
local crypto=require("core.crypto")
test("SHA256 and RFC4231 HMAC vectors",function()
  eq(crypto.sha256(""),"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
  eq(crypto.sha256("abc"),"ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
  eq(crypto.hmac(string.rep(string.char(11),20),"Hi There"),"b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7")
  eq(crypto.hmac(string.rep("x",100),"message"),"393355db8f0edbf0064ede0eed08a3ee53731f45398569d3c2c33edfebd5b52b")
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
package.preload.computer=function() return {uptime=function() return now end} end
local nonceCounter=0
local function nonce() nonceCounter=nonceCounter+1; return string.format("nonce-%032d",nonceCounter) end
package.preload.uuid=function() return {next=nonce} end
os.sleep=function() end
local storage=require("core.storage")
local config=require("core.config")
test("Atomic config save, backup recovery, invalid intervals",function()
  local c=config.defaults("server"); c.key=string.rep("k",32)
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

local protocol=require("network.protocol")
local wire=require("network.modem")
local bus,drop={},false
local function modem(address,maxPacket)
  local opened=false
  local m={address=address,type="modem",maxPacketSize=function() return maxPacket or 8192 end,
    isWireless=function() return true end,isOpen=function() return opened end,
    open=function() opened=true; return true end,close=function() opened=false end,setStrength=function() end}
  local function push(target,port,magic,raw)
    assert(#magic+#raw+4<=m.maxPacketSize(),"oversize packet")
    if not drop then bus[#bus+1]={from=address,to=target,port=port,magic=magic,raw=raw} end
    return true
  end
  m.send=push
  m.broadcast=function(port,magic,raw) return push(nil,port,magic,raw) end
  return m
end
local serverCfg=config.defaults("server"); serverCfg.key=string.rep("k",32)
serverCfg.allowedClients={["main-address"]="main",["side-address"]="side"}
local mainCfg=config.defaults("main"); mainCfg.key=serverCfg.key
local sideCfg=config.defaults("side"); sideCfg.key=serverCfg.key
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
  main.wire:send(main.server,{v=1,kind="REQUEST",boot=main.boot,target=main.serverBoot,id=id,body=p.data})
  step(2); eq(observed,1); eq(dispatchCounts.unique,1)
  -- Inspect cached fingerprint: both deliveries resulted in exactly one cache entry.
  local record=server.seen["main-address:"..id]; assert(record)
  local countBefore=calls
  main.wire:send(main.server,{v=1,kind="REQUEST",boot=main.boot,target=main.serverBoot,id=id,body={command="GET_SERVER_STATUS",args={marker="changed"}}})
  step(1); assert(calls-countBefore<=1); eq(dispatchCounts.changed,nil)
  eq(record.fingerprint,codec.encode(p.data))
end)
test("Bad MAC, unlisted peer, invalid chunks and stale boot ignored",function()
  local old=calls
  server:receive("server-address","attacker",34100,wire.MAGIC,"not data")
  local f={v=1,id="bad",from="main-address",to="server-address",part=1,total=1,data="t",mac=string.rep("0",64)}
  server:receive("server-address","main-address",34100,wire.MAGIC,codec.encode(f))
  main.wire:send("server-address",{v=1,kind="REQUEST",boot=main.boot,target="old-server-boot",id="replay",body={command="GET_SERVER_STATUS",args={}}})
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
  local cfg=config.defaults("main"); cfg.key=mainCfg.key
  local t=wire.new(m,cfg,function() return now end,nonce())
  local function frame(id)
    local f={v=1,id=id,from="server-address",to=m.address,part=1,total=64,data="x"}
    f.mac=crypto.hmac(cfg.key,codec.encode(f)); return codec.encode(f)
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
  return gpu
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
  components={me1=p}; ae:poll(); assert(ae.online); eq(#ae.items,3); eq(ae.energy.unit,"AE")
  local stocks=ae:stocks({query="ALLOY",page=1}); eq(stocks.total,3)
  local ambiguous=0; for _,item in ipairs(ae.items) do if not item.identityComplete then ambiguous=ambiguous+1 end end; eq(ambiguous,1)
  eq(ae:jobs().existingJobDetails,"unsupported")
  p.getItemsInNetwork=function() error("network disconnected") end
  ae:poll(); assert(not ae.online); eq(#ae.items,0); assert(not ae.energy.supported)
  components={}; ae:poll(); assert(not ae.online)
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
      for tab=1,7 do state.tab=tab; screens.draw(r,role,n,state) end
      r:begin(); r:button(2,5,10,"test","id"); eq(r:touch("wrong",3,5),nil); eq(r:touch("screen1",3,5),"id")
    end
  end
end)

local updater=require("core.updater")
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
test("Generated offline installer installs all three roles and restores module loaders",function()
  local originalRead,originalWrite,originalPrint=io.read,io.write,print
  local term={read=function(options) eq(options.pwchar,"*"); return string.rep("k",32).."\n" end}
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
    local index=0
    io.read=function() index=index+1; return assert(answers[index],"Unexpected installer prompt") end
    io.write=function() end; print=function() end
    -- OpenOS exposes package.loaded/path but no package.preload or searchers.
    -- Its native require must never be asked for bundled FactoryOS modules.
    local env=setmetatable({package={loaded={}},require=function(name)
      assert(not name:match("^core%."),"Bootstrap leaked into native OpenOS require")
      return require(name)
    end},{__index=_ENV})
    local ok,err=pcall(assert(load(code,"=offline-installer","t",env)))
    io.read=originalRead; io.write=originalWrite; print=originalPrint
    assert(ok,err)
    local c=assert(config.load()); eq(c.role,role); eq(c.key,string.rep("k",32))
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
print("TOTAL "..passed.." passed")
