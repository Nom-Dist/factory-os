-- Host-only console behavior. GPU/event/filesystem surroundings are mocked.
local T=...
local test,eq=T.test,T.eq
local config=require("core.config")
local storage=require("core.storage")
local Console=require("client.server_console")
local function fixture()
  local f={cfg=config.defaults("server"),applied=0,allowed=true}
  f.state=Console.new(f.cfg,function() return 0 end,function(c)
    local saved=assert(storage.load(config.path)); eq(saved.webToken,c.webToken); eq(saved.webEnabled,c.webEnabled)
    f.applied=f.applied+1; f.candidate=c
  end,function() return f.allowed,f.allowed and nil or "Guncelleme suruyor" end)
  return f
end
test("Server menu persists URL/token before applying live connection and reuses saved token",function()
  local f=fixture(); f.state:touch("web:open"); assert(f.state.editing)
  f.state:paste("https://panel.example"); f.state:key(0,15); f.state:paste(string.rep("b",64)); f.state:touch("web:control")
  f.state:key(13,28); eq(f.applied,1); eq(f.cfg.webUrl,"https://panel.example/bridge/ingest"); eq(f.cfg.webControl,true)
  eq(f.state.draft.token,""); assert(f.state.tokenConfigured)
  f.state:close(); f.state:open(); eq(f.state.draft.token,""); f.state:save(false); eq(f.applied,2); eq(f.cfg.webToken,string.rep("b",64))
  f.state:touch("web:disconnect"); eq(f.applied,3); eq(f.cfg.webEnabled,false); eq(f.cfg.webControl,false)
end)
test("Server runtime F4 opens setup, ignores update keys while editing, and saves clipboard settings live",function()
  local event=require("event"); local Updates=require("core.updates")
  local originalPull,originalUpdates=event.pull,Updates.new; local touched=0
  Updates.new=function() return {phase="idle",busy=false,tick=function() end,public=function() return {} end,close=function() end,touch=function() touched=touched+1 end} end
  T.setComponents({["gpu-address"]=T.mockGpu(50,16),["console-screen"]={type="screen",address="console-screen"},["console-modem"]=T.modem("console-modem",1024)})
  local events={{"key_down","kbd",0,62},{"key_down","kbd",0,63},{"clipboard","kbd","https://panel.example"},
    {"key_down","kbd",0,15},{"clipboard","kbd",string.rep("d",64)},{"key_down","kbd",13,28},{"interrupted"}}
  event.pull=function() return table.unpack(table.remove(events,1) or {"interrupted"}) end
  local cfg=config.defaults("server"); cfg.ae2Enabled=false; cfg.updateAutoCheck=false
  local safe,ok,reason=pcall(require("core.runtime").run,cfg,{stop=false})
  event.pull=originalPull; Updates.new=originalUpdates; T.setComponents({}); T.takeBus()
  assert(safe and ok,tostring(reason or ok)); eq(touched,0); eq(cfg.webEnabled,true)
  eq(cfg.webUrl,"https://panel.example/bridge/ingest"); eq(cfg.webToken,string.rep("d",64))
end)
test("Server menu validation, update lock and disk flush failure keep the active connection",function()
  local f=fixture(); f.state:open(); f.state:paste("https://panel.example"); f.state:save(false); eq(f.applied,0)
  f.state:key(0,15); f.state:paste(string.rep("c",64)); f.allowed=false; f.state:save(false); eq(f.applied,0)
  f.allowed=true; T.setFailFlush(config.path..".tmp"); f.state:save(false); T.setFailFlush(nil)
  eq(f.applied,0); eq(f.cfg.webEnabled,false); eq(f.cfg.webUrl,""); eq(f.cfg.webToken,"")
  assert(f.state.error:find("diske",1,true))
  f.state:save(false); eq(f.applied,1)
end)
test("Server menu touch keyboard, clipboard, cancellation and field bounds preserve secrets",function()
  local f=fixture(); f.state:open(); f.state:touch("web:token"); assert(f.state.keyboard)
  f.state:touch("webkey:char:a"); f.state:touch("webkey:shift"); f.state:touch("webkey:char:b"); f.state:touch("webkey:char:-")
  eq(f.state.draft.token,"aB-"); f.state:key(0,14); eq(f.state.draft.token,"aB")
  f.state:paste("\n  "); eq(f.state.draft.token,"aB")
  f.state:paste("wrong token"); eq(f.state.draft.token,"aB")
  f.state:touch("webkey:clear"); f.state:paste(string.rep("x",129)); eq(f.state.draft.token,"")
  f.state:paste(string.rep("x",64)); f.state:key(0,1); assert(not f.state.keyboard); f.state:key(0,1)
  assert(not f.state.editing and not f.state.webMenu); eq(f.applied,0); eq(f.cfg.webToken,"")
end)
test("Server console and keyboard fit small screens and never render the connection token",function()
  local f=fixture(); local secret="NeverShowThisToken_123456789012345678901234567890"
  f.state.serverStatus={clients={},ae2={online=true}}; f.state.webStatus={phase="online"}
  for _,dim in ipairs({{40,12},{50,16}}) do
    local r=require("ui.renderer").new(T.mockGpu(dim[1],dim[2]),{address="console-screen"},"server")
    f.state:close(); require("ui.screens").draw(r,"server",{},f.state,function() return 0 end)
    local open=false; for _,b in ipairs(r.buttons) do if b.id=="web:open" then open=true end end; assert(open)
    f.state:open(); f.state.draft.token=secret
    f.state.message="Kaydedildi; baglanti kuruluyor"; f.state.webStatus={phase="offline",error="401: Tokeni kontrol edin"}
    for _,keyboard in ipairs({false,true}) do
      f.state.keyboard=keyboard; f.state.field="token"
      require("ui.screens").draw(r,"server",{},f.state,function() return 0 end)
      local visible=""; for _,row in ipairs(r.front) do visible=visible..table.concat(row.chars) end
      assert(not visible:find(secret,1,true)); assert(visible:find("***",1,true))
      if not keyboard then assert(visible:find("401: Tokeni",1,true)) end
      for _,b in ipairs(r.buttons) do assert(b.id:match(keyboard and "^webkey:" or "^web:")); assert(b.y+b.h-1<=r.h) end
    end
  end
end)
