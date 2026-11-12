local T=...
local test,eq,callback=T.test,T.eq,T.callback
local Craft=require("server.crafting")
local storage=require("core.storage")
local config=require("core.config")
local counter=0
local owner="craft-main-address"
local function fixture()
  counter=counter+1
  local f={time=0,calls=0,cancels=0,phase="computing",path="/test-craft/"..counter..".dat"}
  f.item={name="mod:alloy",label="Test Alloy",damage=2,hasTag=false,tag="",isCraftable=true,identityComplete=true}
  f.cpus={{name="Assembly",busy=false,storage=8192},{name="Busy",busy=true,storage=1024}}
  f.handle={isDone=callback(function()
    if f.phase=="computing" then return nil,"computing" end
    if f.phase=="failed" then return false,"request failed (missing resources?)" end
    if f.phase=="disconnected" then error("lost link") end
    return f.phase=="done"
  end),isCanceled=callback(function()
    if f.phase=="computing" then return nil,"computing" end
    if f.phase=="failed" then return false,"request failed (missing resources?)" end
    if f.phase=="disconnected" then error("lost link") end
    return f.phase=="canceled"
  end),cancel=callback(function()
    f.cancels=f.cancels+1
    if f.phase=="computing" then return nil,"computing" end
    f.phase="canceled"; return true
  end)}
  f.recipe={getItemStack=callback(function() return f.item end),request=callback(function(...)
    local amount,power,cpu=...; f.argCount=select("#",...)
    f.calls=f.calls+1; f.amount=amount; f.power=power; f.cpu=cpu
    local journal=assert(storage.load(f.path)); eq(journal.orders[1].state,"submitting")
    eq(journal.high[owner],journal.orders[1].sequence)
    if f.onRequest then f.onRequest() end
    if f.throw then error("request reply lost") end
    return f.handle
  end)}
  f.p={address="craft-me",type="me_interface",getItemsInNetwork=callback(function() return {f.item} end),
    getCraftables=callback(function(filter) eq(filter.name,f.item.name); eq(filter.damage,f.item.damage); return f.recipes or {f.recipe} end),
    getCpus=callback(function() return f.cpus end)}
  f.ae={online=true,cpus=f.cpus,cpuError="",discover=function() return f.p end}
  f.clock=function() return f.time end
  f.system=Craft.new(f.ae,f.clock,nil,f.path)
  function f:quote() return assert(self.system:options(owner,{item=self.item})) end
  function f:args(q,amount,cpu) return {sequence=q.sequence,token=q.token,amount=amount or 64,cpu=cpu or ""} end
  function f:start(amount,cpu) local q=self:quote(); local args=self:args(q,amount,cpu); return self.system:start(owner,args),args end
  function f:tick(phase) if phase then self.phase=phase end; self.time=self.time+2; self.system:tick() end
  return f
end
test("Craft exact filtered recipe, durable submit and native asynchronous completion",function()
  local f=fixture(); local q=f:quote(); eq(f.calls,0); eq(#q.cpus,2)
  local r=assert(f.system:start(owner,f:args(q,64,"Assembly")))
  eq(f.calls,1); eq(f.amount,64); eq(f.power,true); eq(f.cpu,"Assembly"); eq(f.argCount,3); eq(r.state,"computing")
  f:tick(); eq(f.system:jobs().trackedJobs[1].state,"computing")
  f:tick("running"); eq(f.system:jobs().trackedJobs[1].state,"running")
  f:tick("done"); eq(f.system:jobs().trackedJobs[1].state,"done"); eq(f.system:busy(),false)
end)
test("Craft replay across new RPCs and reboot never submits the same sequence again",function()
  local f=fixture(); local r,args=f:start()
  eq(assert(f.system:start(owner,args)).id,r.id); eq(f.calls,1); eq(f.argCount,2)
  local changed=f:args(args,65); changed.token=args.token
  assert(not f.system:start(owner,changed)); eq(f.calls,1)
  f.system=Craft.new(f.ae,f.clock,nil,f.path)
  eq(assert(f.system:start(owner,args)).state,"unknown"); eq(f.calls,1)
  f.system.journal.orders={}; assert(storage.save(f.path,f.system.journal))
  f.system=Craft.new(f.ae,f.clock,nil,f.path)
  assert(not f.system:start(owner,args)); eq(f.calls,1)
end)
test("Craft active job bound and manual review archive never send another AE2 operation",function()
  local f=fixture(); local first
  for i=1,8 do local r=f:start(); first=first or r end
  eq(f.calls,8); local q=f:quote(); assert(not f.system:start(owner,f:args(q))); eq(f.calls,8)
  assert(not f.system:archive(owner,{id=first.id}))
  f:tick("disconnected")
  assert(f.system:archive(owner,{id=first.id})); eq(f.calls,8); eq(f.cancels,0)
  eq(assert(f.system:archive(owner,{id=first.id})).state,"reviewed")
  assert(not f.system:archive("another-main",{id=first.id}))
  f.phase="computing"; assert(f.system:start(owner,f:args(q))); eq(f.calls,9)
end)
test("Craft validation rejects ambiguous NBT, mismatched variants, duplicates and stale quotes",function()
  local f=fixture()
  assert(not f.system:options(owner,{item={name=f.item.name,damage=2,hasTag=true,tag=""}}))
  local q=f:quote(); f.time=61; assert(not f.system:start(owner,f:args(q))); eq(f.calls,0)
  q=f:quote(); for _,n in ipairs({0,-1,1.5,1000001,math.huge}) do assert(not f.system:start(owner,f:args(q,n))) end
  local args=f:args(q); args.token="wrong"; assert(not f.system:start(owner,args))
  f.recipes={f.recipe,f.recipe}; assert(not f.system:options(owner,{item=f.item}))
  f.recipes={{getItemStack=callback(function() return {name=f.item.name,damage=3} end)}}
  assert(not f.system:options(owner,{item=f.item})); eq(f.calls,0)
  f.recipes=nil; f.item.hasTag=true; f.item.tag="exact-tag"; q=f:quote()
  assert(f.system:start(owner,f:args(q,1))); eq(f.calls,1)
end)
test("Craft CPU is revalidated at submit, unknown or duplicate names never start",function()
  local f=fixture(); local q=f:quote()
  assert(not f.system:start(owner,f:args(q,1,"Busy")))
  assert(not f.system:start(owner,f:args(q,1,"missing")))
  f.cpus[1].busy=true; assert(not f.system:start(owner,f:args(q)))
  f.cpus={{name="Twin",busy=false},{name="Twin",busy=false}}
  assert(not f.system:start(owner,f:args(q,1,"Twin")))
  f.cpus={{name="With\nControl",busy=false}}
  assert(not f.system:start(owner,f:args(q,1,"With Control")))
  assert(f.system:start(owner,f:args(q,1))); eq(f.calls,1)
end)
test("Craft journal failure before or after native submission fails closed",function()
  local f=fixture(); local q=f:quote()
  T.setFailFlush(f.path..".tmp")
  local ok=f.system:start(owner,f:args(q)); T.setFailFlush(nil)
  assert(not ok); eq(f.calls,0); assert(f.system.blocked)
  eq(assert(f.system:start(owner,f:args(q))).state,"failed"); eq(f.calls,0)
  local g=fixture(); local quote=g:quote()
  g.onRequest=function() T.setFailFlush(g.path..".tmp") end
  local result=g.system:start(owner,g:args(quote)); T.setFailFlush(nil)
  assert(result); eq(g.calls,1); assert(g.system.blocked)
  g.system=Craft.new(g.ae,g.clock,nil,g.path)
  eq(g.system:jobs().trackedJobs[1].state,"unknown")
  assert(g.system:start(owner,g:args(quote))); eq(g.calls,1)
end)
test("Craft corrupt or missing primary journal never falls back to an older high-water mark",function()
  local f=fixture(); f:start()
  T.files[f.path..".bak"]=T.files[f.path]; T.files[f.path]="broken"
  local broken=Craft.new(f.ae,f.clock,nil,f.path); assert(broken.blocked)
  assert(not broken:options(owner,{item=f.item}))
  T.files[f.path]=nil; local missing=Craft.new(f.ae,f.clock,nil,f.path); assert(missing.blocked)
end)
test("Craft failed planning reports the native reason and lost submit reply stays unknown",function()
  local f=fixture(); f:start(); f:tick("failed")
  local job=f.system:jobs().trackedJobs[1]; eq(job.state,"failed"); assert(job.error:find("missing resources",1,true))
  eq(f.system:busy(),false)
  local g=fixture(); g.throw=true; local r,args=g:start()
  eq(r.state,"unknown"); assert(g.system:busy())
  assert(g.system:start(owner,args)); eq(g.calls,1)
end)
test("Craft cancel honors ownership, computing state and repeat cancellation",function()
  local f=fixture(); local r=f:start()
  assert(not f.system:cancel("another-main",{id=r.id})); eq(f.cancels,0)
  assert(not f.system:cancel(owner,{id=r.id})); eq(f.cancels,1)
  f:tick("running"); eq(assert(f.system:cancel(owner,{id=r.id})).state,"cancel_requested")
  eq(assert(f.system:cancel(owner,{id=r.id})).state,"cancel_requested"); eq(f.cancels,2)
  f:tick(); eq(f.system:jobs().trackedJobs[1].state,"canceled"); eq(f.system:busy(),false)
end)
test("Craft history is bounded and evicted order sequences remain non-replayable",function()
  local f=fixture(); local first
  for i=1,36 do local _,args=f:start(1); first=first or args; f:tick("done"); f.phase="computing" end
  eq(f.calls,36); eq(#f.system:jobs().trackedJobs,32)
  assert(not f.system:start(owner,first)); eq(f.calls,36)
  local rows=f.system:jobs().trackedJobs
  eq(rows[1].token,nil); eq(rows[1].product,nil); eq(rows[1].handle,nil)
end)
test("Craft transient status errors can recover without creating a new job",function()
  local f=fixture(); f:start(); f:tick("disconnected")
  eq(f.system:jobs().trackedJobs[1].state,"unknown")
  f:tick("running"); eq(f.system:jobs().trackedJobs[1].state,"running"); eq(f.calls,1)
end)
test("Craft server role checks and update lock cover computing jobs with idle CPU",function()
  local f=fixture(); T.setComponents({[f.p.address]=f.p})
  f.cpus[2].busy=false
  local server=require("server.main").new(config.defaults("server"),f.clock,function() end)
  server.ae2=f.ae; server.crafting=f.system
  local ctx={role="main",address=owner}
  assert(not server:dispatch("GET_CRAFT_OPTIONS",{item=f.item},{role="side",address=owner}))
  local q=assert(server:dispatch("GET_CRAFT_OPTIONS",{item=f.item},ctx))
  assert(server:dispatch("START_CRAFT",f:args(q),ctx)); assert(not server:canUpdate())
  f:tick("done"); assert(server:canUpdate())
  server.updates={busy=true}; assert(not server:dispatch("GET_CRAFT_OPTIONS",{item=f.item},ctx))
  T.setComponents({})
end)
test("Craft main display amount, CPU, modal and double-submit behavior",function()
  local net,state,_,take=T.displayFixture(); state.selected=T.stockPage(1).items[1]
  state:touch("craft:open"); local query=take("GET_CRAFT_OPTIONS"); eq(query.args.item.name,state.selected.name)
  query.callback({token="preview-token",sequence=1,label="Alloy",cpus={{name="A",busy=false},{name="B",busy=true}}})
  state:touch("tab:1"); assert(state.craft)
  state:touch("craft:preset:64"); state:touch("craft:cpu"); eq(state.craft.cpu,"A")
  state:touch("craft:submit"); state:touch("craft:submit")
  local request=take("START_CRAFT"); eq(request.args.amount,64); eq(request.args.cpu,"A")
  state:key(13,28); request.callback({id="order",state="computing"})
  assert(state.craft.pending); assert(state.craft.submitted); eq(state.craft.orderId,"order")
  local poll=take("GET_CRAFTING_JOBS")
  poll.callback({trackedJobs={{id="order",state="running"}}})
  eq(state.craft,nil); eq(state.tab,4)
end)

test("Craft immediately checks AE2 status, preserves raw planning failure and never replays the failed order",function()
  local f=fixture(); f.phase="failed"
  local r,args=f:start(); eq(r.state,"failed"); eq(r.error,"request failed (missing resources?)")
  eq(r.errorCode,"AE2_REJECTED"); assert(r.errorMessage:find("olabilir",1,true))
  eq(assert(storage.load(f.path)).orders[1].state,"failed"); eq(f.system:busy(),false)
  f.system=Craft.new(f.ae,f.clock,nil,f.path)
  eq(assert(f.system:start(owner,args)).state,"failed"); eq(f.calls,1)
end)

test("Craft planning errors stay in the main display window with safe duplicate and offline handling",function()
  local net,state,_,take=T.displayFixture(); state.selected=T.stockPage(1).items[1]
  state:beginCraft(); take("GET_CRAFT_OPTIONS").callback({token="q",sequence=1,cpus={}})
  state:craftTouch("submit"); take("START_CRAFT").callback(nil,"Uygun bos crafting CPU yok")
  assert(not state.craft.submitted); eq(state.craft.error,"Uygun bos crafting CPU yok")
  state:craftTouch("submit"); take("START_CRAFT").callback({id="checking",state="computing"})
  assert(state.craft.pending)
  take("GET_CRAFTING_JOBS").callback({trackedJobs={{id="other",state="failed",error="wrong job"},{id="checking",state="computing"}}})
  assert(state.craft.pending); eq(state.craft.error,nil)
  state.jobs={trackedJobs={{id="checking",state="failed",error="request failed (missing resources?)"}}}; state:syncCraft()
  assert(not state.craft.pending); assert(state.craft.finished); assert(state.craft.error:find("olabilir",1,true))
  eq(state.craft.rawError,"request failed (missing resources?)"); state:key(13,28); assert(state.craft.finished)
  state.craft.pending=true; state:craftDisconnected(); assert(state.craft.uncertain); state:key(13,28)
  assert(state.craft.submitted); assert(state.craft.error:find("tekrar gonderilmedi",1,true))
end)
test("Craft main display lost response, stale preview and invalid clipboard never resubmit",function()
  local net,state,_,take=T.displayFixture(); state.selected=T.stockPage(1).items[1]
  state:beginCraft(); local stale=take("GET_CRAFT_OPTIONS")
  state:craftTouch("close"); state:beginCraft(); stale.callback({token="old"}); eq(state.craft.preview,nil)
  take("GET_CRAFT_OPTIONS").callback({token="new",sequence=1,cpus={}})
  state:craftTouch("clear"); state:paste("-50"); eq(state.craft.amount,"")
  state:paste("64"); state:key(13,28)
  take("START_CRAFT").callback(nil,"TIMEOUT")
  assert(state.craft.uncertain); state:key(13,28); assert(state.craft.submitted)
  state:craftTouch("jobs"); eq(state.craft,nil); eq(state.tab,4); take("GET_CRAFTING_JOBS")
end)
test("Craft UI fits all display sizes and the modal exposes no background touch targets",function()
  local net,state=T.displayFixture(); state.context={modem=owner}
  state.jobs={cpus={{name="A",busy=false}},error="",trackedJobs={}}
  for i=1,32 do state.jobs.trackedJobs[i]={id=owner..":"..i,owner=owner,label="Alloy",amount=i,cpu="A",state="running",error=""} end
  for _,dim in ipairs({{40,12},{50,16},{80,25},{160,50}}) do
    local r=require("ui.renderer").new(T.mockGpu(dim[1],dim[2]),{address="craft-screen"},"main")
    state.tab=4; state.jobsPage=1; state.craft=nil
    require("ui.screens").draw(r,"main",net,state,function() return 100 end)
    state.craft={label="Alloy",amount="64",cpu="A",preview={token="x"},cpus={"","A"}}
    require("ui.screens").draw(r,"main",net,state,function() return 100 end)
    for _,b in ipairs(r.buttons) do assert(b.id:match("^craft:")); assert(b.y+b.h-1<=r.h) end
    local raw="request failed (missing resources?) "..string.rep("driver-detail ",15).."END42"
    state.craft={label="Alloy",amount="64",cpu="",submitted=true,finished=true,jobState="failed",error="Kaynak veya CPU sorunu olabilir",rawError=raw}
    local all=""
    require("ui.screens").draw(r,"main",net,state,function() return 100 end)
    local pages=state.craft.detailPages
    for page=1,pages do
      state.craft.detailPage=page; require("ui.screens").draw(r,"main",net,state,function() return 100 end)
      for _,row in ipairs(r.front) do all=all..table.concat(row.chars) end
      for _,b in ipairs(r.buttons) do assert(b.id:match("^craft:")); assert(b.y+b.h-1<=r.h) end
    end
    assert(all:find("END42",1,true),"Missing final detail at "..dim[1].."x"..dim[2])
    assert(all:find("missing",1,true) and all:find("resources?",1,true),"Missing native reason at "..dim[1].."x"..dim[2])
    state.craft=nil
  end
end)
test("Craft real 1024-byte protocol retries, side ACL and server reboot preserve one native submission",function()
  T.takeBus()
  local f=fixture(); local protocol=require("network.protocol")
  local serverAddress,sideAddress="craft-server-address","craft-side-address"
  local sc=config.defaults("server"); sc.allowedClients[owner]="main"; sc.allowedClients[sideAddress]="side"
  local mc=config.defaults("main"); mc.serverAddress=serverAddress
  local cc=config.defaults("side"); cc.serverAddress=serverAddress
  local function dispatch(command,args,client)
    if command=="HEARTBEAT" then return {ae2={online=true}} end
    if command=="GET_CRAFT_OPTIONS" then return f.system:options(client.address,args) end
    if command=="START_CRAFT" then return f.system:start(client.address,args) end
    if command=="GET_CRAFTING_JOBS" then return f.system:jobs() end
  end
  local nodes={}
  local function add(address,cfg,fn)
    nodes[address]=protocol.new(cfg,T.modem(address,1024),f.clock,T.nonce,fn)
    return nodes[address]
  end
  local server=add(serverAddress,sc,dispatch); local main=add(owner,mc); local side=add(sideAddress,cc)
  local dropping=false
  local function step(seconds)
    for _=1,math.floor(seconds*10) do
      f.time=f.time+0.1
      for _,node in pairs(nodes) do node:tick() end
      for _,packet in ipairs(T.takeBus()) do
        if not (dropping and packet.from==serverAddress and packet.to==owner) then
          if packet.to then
            local node=nodes[packet.to]; if node then node:receive(packet.to,packet.from,sc.port,packet.magic,packet.raw) end
          else for address,node in pairs(nodes) do if address~=packet.from then node:receive(address,packet.from,sc.port,packet.magic,packet.raw) end end end
        end
      end
    end
  end
  step(8); assert(main.online and side.online)
  local quote
  assert(main:request("GET_CRAFT_OPTIONS",{item=f.item},function(data,err) assert(not err,err); quote=data end))
  step(5); assert(quote)
  local args=f:args(quote); dropping=true
  assert(main:request("START_CRAFT",args,function() end)); step(10); eq(f.calls,1)
  dropping=false
  local response
  assert(main:request("START_CRAFT",args,function(data,err) assert(not err,err); response=data end))
  step(5); assert(response); eq(f.calls,1)
  local denied
  side:request("START_CRAFT",args,function(_,err) denied=err end); step(3); eq(denied,"FORBIDDEN"); eq(f.calls,1)
  server:close(); f.system=Craft.new(f.ae,f.clock,nil,f.path); server=add(serverAddress,sc,dispatch)
  step(27); assert(main.online)
  response=nil
  main:request("START_CRAFT",args,function(data,err) assert(not err,err); response=data end)
  step(5); eq(response.state,"unknown"); eq(f.calls,1)
  for _,node in pairs(nodes) do node:close() end
  T.takeBus()
end)
