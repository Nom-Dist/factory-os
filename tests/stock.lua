-- Deterministic host regressions using the existing verified OC callback shapes.
-- This is not Android/ARTEMIS or real Minecraft acceptance testing.
local T=...
local test,eq,callback=T.test,T.eq,T.callback
local Craft=require("server.crafting")
local Stock=require("server.stock")
local storage=require("core.storage")
local count=0
local function fixture()
  count=count+1
  local f={time=0,calls=0,phase="computing",path="/test-stock/"..count..".dat"}
  f.item={name="mod:alloy",label="Test Alloy",damage=2,size=10,hasTag=false,tag="",identityComplete=true,isCraftable=true}
  f.cpus={{name="Assembly",busy=false,storage=8192}}
  f.handle={isDone=callback(function()
    if f.phase=="computing" then return nil,"computing" end
    if f.phase=="failed" then return false,"missing resources" end
    return f.phase=="done"
  end),isCanceled=callback(function()
    if f.phase=="computing" then return nil,"computing" end
    if f.phase=="failed" then return false,"missing resources" end
    return f.phase=="canceled"
  end),cancel=callback(function()
    if f.phase=="computing" then return nil,"computing" end
    f.phase="canceled"; return true
  end)}
  f.recipe={getItemStack=callback(function() return f.item end),request=callback(function(...)
    eq(select("#",...),2); local amount,power=...; eq(power,true)
    local j=assert(storage.load(f.path)); local order=j.orders[1]
    eq(order.state,"submitting"); eq(j.high[Stock.owner],order.sequence)
    eq(order.ruleId,j.automation.rules[1].id); assert(j.automation.rules[1].enabled)
    f.calls=f.calls+1; f.amount=amount
    if f.afterRequest then f.afterRequest() end
    if f.throw then error("reply lost") end
    return f.handle
  end)}
  f.p={address="stock-me",getCraftables=callback(function() return f.recipes or {f.recipe} end),
    getCpus=callback(function() return f.liveCpus or f.cpus end)}
  f.ae={online=true,address="stock-me",items={f.item},cpus=f.cpus,cpuError="",revision=1,
    discover=function() return f.p end}
  f.clock=function() return f.time end
  f.craft=Craft.new(f.ae,f.clock,nil,f.path); f.stock=Stock.new(f.craft,f.ae,f.clock)
  function f:change(args)
    args.revision=args.revision or self.craft.journal.automation.revision
    return self.stock:change(args)
  end
  function f:add(minimum,target)
    return assert(self:change({action="save",item=self.item,minimum=minimum or 64,target=target or 256})).rules[1]
  end
  function f:enable() return assert(self:change({action="enable",id=self.rule.id,enabled=true})) end
  function f:advance(seconds,refresh,updating)
    self.time=self.time+seconds; self.craft:tick()
    if refresh~=false then self.ae.revision=self.ae.revision+1 end
    self.stock:tick(updating)
  end
  f.rule=f:add()
  return f
end
test("Stock defaults disabled, crosses minimum once and durably requests only target deficit",function()
  local f=fixture(); f:advance(60); eq(f.calls,0)
  f:enable(); f.item.size=64; f:advance(30); eq(f.calls,0)
  f.item.size=63; f:advance(30); eq(f.calls,1); eq(f.amount,193)
  f:advance(300); eq(f.calls,1); eq(f.stock:list({}).rules[1].inFlight,193)
  f.phase="done"; f.item.size=256; f:advance(2); f:advance(30); eq(f.calls,1)
  f.item.size=1; f.phase="computing"; f:advance(30); eq(f.calls,2); eq(f.amount,255)
end)
test("Stock validation, variant deduplication, revision replay and edits disarm persistently",function()
  local f=fixture(); local original=f.craft.journal.automation.revision
  for _,args in ipairs({{minimum=0,target=64},{minimum=65,target=64},{minimum=1,target=1000001},{minimum=1.5,target=64}}) do
    args.action="save"; args.item=f.item; assert(not f:change(args))
  end
  assert(not f:change({action="save",item=f.item,minimum=1,target=2}))
  f:enable(); assert(not f:change({action="pause",paused=true,revision=original}))
  assert(not f:change({action="pause",paused="yes"}))
  assert(f:change({action="save",id=f.rule.id,minimum=8,target=32}))
  eq(f.craft.journal.automation.rules[1].enabled,false)
  local restored=Craft.new(f.ae,f.clock,nil,f.path); eq(restored.blocked,nil)
  eq(restored.journal.automation.rules[1].target,32); eq(restored.journal.automation.rules[1].enabled,false)
  local bad=storage.load(f.path); bad.automation.rules[1].target=0; assert(storage.save(f.path,bad))
  assert(Craft.new(f.ae,f.clock,nil,f.path).blocked)
end)
test("Stock waits for complete inventory, pinned network, fresh CPU and update worker",function()
  local f=fixture(); f:enable(); f.ae.truncated=true; f:advance(40); eq(f.calls,0)
  f.ae.truncated=false; f.ae.address="other"; f:advance(40); eq(f.calls,0)
  f.ae.address=f.p.address; f.ae.online=false; f:advance(40); eq(f.calls,0)
  f.ae.online=true; f.cpus[1].busy=true; f:advance(40); eq(f.calls,0)
  f.cpus[1].busy=false; f:advance(40,true,true); eq(f.calls,0)
  f.liveCpus={{name="External",busy=true},{name="Free",busy=false}}
  f:advance(40); eq(f.calls,0)
  f.liveCpus=nil; f:advance(60); eq(f.calls,1)
end)
test("Stock missing complete inventory row means zero, unknown variant is never substituted",function()
  local f=fixture(); f:enable(); f.ae.items={}; f:advance(30); eq(f.amount,256)
  local g=fixture(); g:enable(); g.item.hasTag=true; g.item.tag=""; g.item.identityComplete=false
  g:advance(30); eq(g.calls,0)
  local h=fixture(); h:enable(); h.recipes={h.recipe,h.recipe}; h:advance(30); eq(h.calls,0)
  local k=fixture(); k:enable()
  k.ae.items={{name=k.item.name,damage=k.item.damage,size=10,hasTag=true,identityComplete=false}}
  k:advance(30); eq(k.calls,0); eq(k.stock:list({}).rules[1].stock,nil)
end)
test("Stock retry backoff follows native planning failure and never loops on every poll",function()
  local f=fixture(); f:enable(); f:advance(30); eq(f.calls,1)
  f.phase="failed"; f:advance(2); eq(f.stock:list({}).rules[1].retryIn,60)
  f:advance(59); eq(f.calls,1)
  f.phase="computing"; f:advance(1); eq(f.calls,2)
  f.phase="failed"; f:advance(2); eq(f.stock:list({}).rules[1].retryIn,120)
  f:advance(119); eq(f.calls,2); f:advance(1); eq(f.calls,3)
end)
test("Stock completion requires a newer inventory revision before replenishing again",function()
  local f=fixture(); f:enable(); f:advance(30); f.phase="done"; f:advance(2,false)
  f:advance(100,false); eq(f.calls,1)
  f.phase="computing"; f:advance(1,true); eq(f.calls,2)
end)
test("Stock reboot or lost submission reply blocks all retries until reviewed and reenabled",function()
  for _,lost in ipairs({false,true}) do
    local f=fixture(); f.throw=lost; f:enable(); f:advance(30); eq(f.calls,1)
    f.craft=Craft.new(f.ae,f.clock,nil,f.path); f.stock=Stock.new(f.craft,f.ae,f.clock)
    f:advance(600); eq(f.calls,1); eq(f.stock:list({}).rules[1].state,"ME KONTROLU GEREKLI")
    local job=f.craft:jobs().trackedJobs[1]
    assert(not f:change({action="delete",id=f.rule.id}))
    assert(f.stock:controlJob("another-main",{id=job.id},true))
    eq(f.stock:list({}).rules[1].enabled,false); f:advance(600); eq(f.calls,1)
    f.throw=false; f:enable(); f:advance(30); eq(f.calls,2)
  end
end)
test("Stock cancel first disarms even when native cancel is computing; pause survives reboot",function()
  local f=fixture(); f:enable(); f:advance(30)
  local job=f.craft:jobs().trackedJobs[1]
  assert(not f.stock:controlJob("main",{id=job.id},false))
  eq(f.stock:list({}).rules[1].enabled,false)
  local disk=assert(storage.load(f.path)); eq(disk.automation.rules[1].enabled,false)
  f.phase="running"; f:advance(2); assert(f.stock:controlJob("main",{id=job.id},false))
  f:advance(600); eq(f.calls,1)
  f:enable(); assert(f.stock:controlJob("main",{id=job.id},false))
  eq(f.stock:list({}).rules[1].enabled,true) -- A repeated old cancel cannot disarm a newly enabled rule.
  assert(f:change({action="pause",paused=true})); f:enable()
  local restored=Craft.new(f.ae,f.clock,nil,f.path); local s=Stock.new(restored,f.ae,f.clock)
  eq(s:enabled(),false); eq(s:list({}).paused,true)
end)
test("Stock disk errors before and after native submission fail closed",function()
  local f=fixture(); f:enable(); T.setFailFlush(f.path..".tmp")
  f:advance(30); eq(f.calls,0); assert(f.craft.blocked); T.setFailFlush(nil)
  local g=fixture(); g:enable(); g.afterRequest=function() T.setFailFlush(g.path..".tmp") end
  g:advance(30); eq(g.calls,1); assert(g.craft.blocked); T.setFailFlush(nil)
  g:advance(600); eq(g.calls,1)
  g.craft=Craft.new(g.ae,g.clock,nil,g.path); g.stock=Stock.new(g.craft,g.ae,g.clock)
  g:advance(600); eq(g.calls,1)
end)
test("Stock manual active orders and all external busy CPUs defer automatic replenishment",function()
  local f=fixture(); f:enable()
  local q=assert(f.craft:options("manual-main",{item=f.item}))
  -- Fixture's durability assertion expects an automated order; temporarily inspect manually.
  local native=f.recipe.request
  f.recipe.request=callback(function() return f.handle end)
  assert(f.craft:start("manual-main",{token=q.token,sequence=q.sequence,amount=100,cpu=""}))
  f.recipe.request=native
  f:advance(60); eq(f.calls,0); eq(f.stock:list({}).rules[1].inFlight,100)
  f.phase="done"; f.item.size=110; f:advance(2); eq(f.calls,0)
end)
test("Stock main-only commands and update gate are enforced at dispatcher and wire ACL",function()
  local config=require("core.config"); local server=require("server.main").new(config.defaults("server"),function() return 0 end,function() end)
  local messages=require("network.messages")
  for _,command in ipairs({"GET_STOCK_RULES","SET_STOCK_RULE"}) do
    assert(not messages.authorize("side",command)); assert(messages.authorize("main",command))
    assert(not server:dispatch(command,{}, {role="side",address="side"}))
  end
  server.updates={busy=true}; assert(not server:dispatch("SET_STOCK_RULE",{action="pause",paused=true,revision=0},{role="main",address="main"}))
end)
test("Stock rule cap, paging, pause, deletion and monotonic IDs survive reload",function()
  local f=fixture()
  for i=2,16 do
    f.item.name="mod:item_"..i
    assert(f:change({action="save",item=f.item,minimum=1,target=2}))
  end
  f.item.name="mod:overflow"; assert(not f:change({action="save",item=f.item,minimum=1,target=2}))
  local page=f.stock:list({page=4}); eq(page.total,16); eq(#page.rules,4); eq(page.rules[4].id,16)
  assert(f:change({action="delete",id=1})); assert(f:change({action="save",item=f.item,minimum=1,target=2}))
  eq(f.craft.journal.automation.rules[16].id,17)
  assert(f:change({action="pause",paused=true}))
  local restored=Craft.new(f.ae,f.clock,nil,f.path); eq(restored.blocked,nil)
  local s=Stock.new(restored,f.ae,f.clock); eq(s:list({page=4}).rules[4].id,17); eq(s:list({}).paused,true)
end)
test("Stock display editor validates numbers, isolates touches and never resubmits lost mutations",function()
  local net,state,_,take=T.displayFixture(); state.selected=T.stockPage(1).items[1]
  state:touch("rule:open"); assert(state.ruleEditor)
  take("GET_STOCK_RULES").callback({rules={},page=1,pages=1,revision=4,paused=false,error=""})
  state:touch("tab:1"); assert(state.ruleEditor)
  state:touch("ruleedit:minimum"); state:touch("ruleedit:clear"); state:paste("16")
  state:key(0,15); state:touch("ruleedit:clear"); state:paste("64")
  state:key(13,28); state:key(13,28)
  local request=take("SET_STOCK_RULE"); eq(request.args.minimum,16); eq(request.args.target,64); eq(request.args.revision,4)
  request.callback(nil,"TIMEOUT"); state:key(13,28); assert(state.ruleEditor.submitted)
  take("GET_STOCK_RULES").callback({rules={},page=1,pages=1,revision=5,paused=false,error=""})
  state:touch("ruleedit:close"); eq(state.ruleEditor,nil)
end)
test("Stock rules and modal render within four display sizes with isolated input",function()
  local net,state=T.displayFixture(); local f=fixture(); state.rules=f.stock:list({}); state.tab=3
  for _,dim in ipairs({{40,12},{50,16},{80,25},{160,50}}) do
    local r=require("ui.renderer").new(T.mockGpu(dim[1],dim[2]),{address="stock-screen"},"main")
    require("ui.screens").draw(r,"main",net,state,function() return 100 end)
    local enable=false
    for _,b in ipairs(r.buttons) do if b.id=="rule:enable:1" then enable=true end end
    assert(enable)
    state.ruleEditor={label="Alloy",minimum="16",target="64",field="target"}
    require("ui.screens").draw(r,"main",net,state,function() return 100 end)
    for _,b in ipairs(r.buttons) do assert(b.id:match("^ruleedit:")); assert(b.y+b.h-1<=r.h) end
    state.ruleEditor=nil
  end
end)
test("Stock mutation over real 1024-byte wireless protocol is durable after response loss and reboot",function()
  T.takeBus()
  local f=fixture(); local config=require("core.config"); local protocol=require("network.protocol")
  local sc=config.defaults("server"); local mc=config.defaults("main"); local cc=config.defaults("side")
  local sa,ma,ca="stock-server","stock-main","stock-side"
  sc.allowedClients[ma]="main"; sc.allowedClients[ca]="side"; mc.serverAddress=sa; cc.serverAddress=sa
  local nodes={}; local dropping=false
  local function dispatch(command,args)
    if command=="HEARTBEAT" then return {ae2={online=true}} end
    if command=="GET_STOCK_RULES" then return f.stock:list(args) end
    if command=="SET_STOCK_RULE" then return f.stock:change(args) end
  end
  local function add(address,cfg,fn)
    local node=protocol.new(cfg,T.modem(address,1024),f.clock,T.nonce,fn); nodes[address]=node; return node
  end
  local server=add(sa,sc,dispatch); local main=add(ma,mc); local side=add(ca,cc)
  local function step(seconds)
    for _=1,seconds*10 do
      f.time=f.time+0.1
      for _,node in pairs(nodes) do node:tick() end
      for _,p in ipairs(T.takeBus()) do
        if not (dropping and p.from==sa and p.to==ma) then
          if p.to then if nodes[p.to] then nodes[p.to]:receive(p.to,p.from,sc.port,p.magic,p.raw) end
          else for address,node in pairs(nodes) do if address~=p.from then node:receive(address,p.from,sc.port,p.magic,p.raw) end end end
        end
      end
    end
  end
  step(8); assert(main.online and side.online)
  local args={action="enable",id=f.rule.id,enabled=true,revision=f.craft.journal.automation.revision}
  dropping=true; assert(main:request("SET_STOCK_RULE",args,function() end)); step(10)
  eq(f.craft.journal.automation.revision,args.revision+1); eq(f.calls,0)
  dropping=false; local err
  main:request("SET_STOCK_RULE",args,function(_,why) err=why end); step(4)
  assert(err); eq(f.craft.journal.automation.revision,args.revision+1)
  local denied; side:request("GET_STOCK_RULES",{},function(_,why) denied=why end); step(3); eq(denied,"FORBIDDEN")
  server:close(); f.craft=Craft.new(f.ae,f.clock,nil,f.path); f.stock=Stock.new(f.craft,f.ae,f.clock); server=add(sa,sc,dispatch)
  step(27); assert(main.online)
  local response; main:request("GET_STOCK_RULES",{},function(data,why) assert(not why,why); response=data end); step(4)
  assert(response.rules[1].enabled); eq(response.revision,args.revision+1); eq(f.calls,0)
  f:advance(30); eq(f.calls,1)
  for _,node in pairs(nodes) do node:close() end
  T.takeBus()
end)
