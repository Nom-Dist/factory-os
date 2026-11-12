"""Render the real Lua GPU buffer with fixture data; these are NOT Minecraft screenshots."""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / ".tools"))
from PIL import Image, ImageDraw, ImageFont
from lupa import lua53

FIXTURE = r'''
local data={}
local labels={"Infused Alloy","Steel Ingot","Fluix Crystal","Logic Processor","Basic Control Circuit",
  "Diamond","Copper Ingot","Iron Ingot","Gold Ingot","Redstone","Silicon","Quartz Glass",
  "Enriched Alloy","Reinforced Alloy","Atomic Alloy","Obsidian","Osmium Ingot","Tin Ingot",
  "Lead Ingot","Certus Quartz Crystal","Calculation Processor","Engineering Processor","Glass","Cobblestone"}
local amounts={1250,81640,2840,512,840,425,28400,72100,9800,154200,3200,1280,750,360,190,4620,5100,16400,4700,8300,256,256,19200,1850000}
for i,label in ipairs(labels) do data[i]={name="example:item_"..i,label=label,damage=0,size=amounts[i],hasTag=false,tag="",identityComplete=true,isCraftable=i%4~=0} end
state={tab=1,page=1,rowOffset=0,visibleRows=24,query="",draft="",filter="all",sort="name",favorites={},
  stocks={items=data,page=1,pages=77,total=1834,truncated=false},stockReceivedAt=9997,
  jobs={cpus={{name="ASSEMBLY / 01",busy=true,storage=65536},{name="CHEMICAL / 02",busy=true,storage=262144},
    {name="GENERAL / 03",busy=false,storage=65536},{name="PROCESSORS / 04",busy=false,storage=131072}},error="",trackedJobs={
      {id="11111111-1111-4111-8111-111111111111:4",owner="11111111-1111-4111-8111-111111111111",label="Infused Alloy",amount=64,cpu="ASSEMBLY / 01",state="running",error=""},
      {id="11111111-1111-4111-8111-111111111111:3",owner="11111111-1111-4111-8111-111111111111",label="Logic Processor",amount=16,cpu="",state="computing",error=""},
      {id="11111111-1111-4111-8111-111111111111:2",owner="11111111-1111-4111-8111-111111111111",label="Fluix Crystal",amount=32,cpu="",state="failed",error="request failed (missing resources?)"},
      {id="11111111-1111-4111-8111-111111111111:1",owner="11111111-1111-4111-8111-111111111111",label="Steel Ingot",amount=128,cpu="GENERAL / 03",state="done",error=""}}},
  context={modem="11111111-1111-4111-8111-111111111111",screen="22222222-2222-4222-8222-222222222222",port=34100,poll=10}}
state.favorites[require("core.items").key(data[1])]=data[1].label
state.favorites[require("core.items").key(data[3])]=data[3].label
state.rules={page=1,pages=2,total=6,revision=8,paused=false,error="",rules={
  {id=1,item=data[1],label="Infused Alloy",minimum=2048,target=4096,stock=1250,inFlight=2846,enabled=true,state="URETIM BEKLENIYOR",retryIn=0,error=""},
  {id=2,item=data[5],label="Basic Control Circuit",minimum=1024,target=2048,stock=840,inFlight=0,enabled=true,state="TEKRAR BEKLENIYOR",retryIn=57,error="request failed (missing resources?)"},
  {id=3,item=data[3],label="Fluix Crystal",minimum=1024,target=4096,stock=2840,inFlight=0,enabled=true,state="STOK YETERLI",retryIn=0,error=""},
  {id=4,item=data[7],label="Copper Ingot",minimum=8192,target=16384,stock=28400,inFlight=0,enabled=false,state="KAPALI",retryIn=0,error=""}}}
state.update={phase="available",message="Sunucuda yeni surum hazir",currentRelease="0.6.2-ornek",version="0.6.3",release="0.6.3-ornek",available=true,busy=false,autoStart=true,automatic=true,interval=900,role="main",canApply=true}
net={online=true,lastSeen=9998,server="33333333-3333-4333-8333-333333333333",status={version="0.6.2",crafting="manual",automation=true,uptime=12587,
  ae2={online=true,itemTypes=1834,revision=45},power={ae2={supported=true,unit="AE",stored=782000,capacity=1000000,injection=129,usage=121}},
  clients={{role="main",address=state.context.modem,age=2},{role="side",address="44444444-4444-4444-8444-444444444444",age=1}}}}
'''


def rgb(number):
    return ((number >> 16) & 255, (number >> 8) & 255, number & 255)


def render(name, width, height, setup, role="main"):
    lua = lua53.LuaRuntime(unpack_returned_tuples=True)
    for path in (ROOT / "src").rglob("*.lua"):
        module = path.relative_to(ROOT / "src").with_suffix("").as_posix().replace("/", ".")
        lua.globals().package.preload[module] = lua.eval("function(s,n) return assert(load(s,n,'t')) end")(
            path.read_text(encoding="utf-8"), "@" + path.as_posix())
    lua.execute(FIXTURE)
    lua.globals().WIDTH, lua.globals().HEIGHT = width, height
    lua.globals().ROLE = role
    lua.execute('''
      local gpu={maxResolution=function() return WIDTH,HEIGHT end,setResolution=function() end,
        maxDepth=function() return 8 end,setDepth=function() end,setForeground=function() end,
        setBackground=function() end,set=function() end}
      renderer=require("ui.renderer").new(gpu,{address="preview-screen"},ROLE)
    ''')
    lua.execute(setup)
    lua.execute('require("ui.screens").draw(renderer,ROLE,net,state,function() return 10000 end)')
    cell_w, cell_h, caption_h = 9, 18, 30
    fonts = [Path("C:/Windows/Fonts/consola.ttf"), Path("/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf")]
    font = next((ImageFont.truetype(str(p), 14) for p in fonts if p.exists()), ImageFont.load_default())
    image = Image.new("RGB", (width*cell_w, height*cell_h+caption_h), "#0b1220")
    draw = ImageDraw.Draw(image)
    caption = "FACTORYOS / ORNEK VERI / GPU ONIZLEMESI" if width < 100 else "FACTORYOS / GELISTIRME ONIZLEMESI / ORNEK VERI / OYUN EKRAN GORUNTUSU DEGIL"
    draw.text((12, 7), caption, font=font, fill="#e6ba68")
    front = lua.globals().renderer.front
    for y in range(1, height+1):
        row = front[y]
        for x in range(1, width+1):
            left, top = (x-1)*cell_w, caption_h+(y-1)*cell_h
            draw.rectangle((left, top, left+cell_w-1, top+cell_h-1), fill=rgb(int(row.bg[x])))
            if row.chars[x] != " ":
                draw.text((left, top+1), row.chars[x], font=font, fill=rgb(int(row.fg[x])))
    output = ROOT / "docs" / "previews" / (name+".png")
    output.parent.mkdir(parents=True, exist_ok=True)
    image.save(output)
    print(output)


if __name__ == "__main__":
    render("main-overview", 160, 50, "")
    render("main-stocks", 160, 50, "state.tab=2; state.selected=state.stocks.items[1]")
    render("main-search", 160, 50, 'state.tab=2; state.editing=true; state.draft="alloy"')
    render("main-offline", 160, 50, "net.online=false; state.tab=2")
    render("main-compact", 80, 25, "state.tab=2")
    render("main-updates", 160, 50, "state.tab=9")
    render("main-update-progress", 160, 50, 'state.tab=9; state.update.phase="downloading"; state.update.busy=true; state.update.progress=14; state.update.total=30; state.update.file="ui/main_screen.lua"; state.update.message="Dosyalar kablosuz aliniyor"')
    render("side-updates", 80, 25, "", role="side")
    render("server-updates", 50, 16, 'state.serverStatus=net.status; state.update.role="server"', role="server")
    render("main-production", 160, 50, "state.tab=4")
    render("main-production-compact", 80, 25, "state.tab=4")
    render("main-production-small", 40, 12, "state.tab=4")
    modal = 'state.tab=2; state.craft={label="Infused Alloy / Meta: 0",amount="64",cpu="ASSEMBLY / 01",preview={token="example"},cpus={"","ASSEMBLY / 01"}}'
    render("main-craft", 160, 50, modal)
    render("main-craft-compact", 80, 25, modal)
    render("main-craft-small", 40, 12, modal)
    render("main-craft-uncertain", 160, 50, modal+'; state.craft.submitted=true; state.craft.uncertain=true; state.craft.error="Yanit yok. Emir tekrar gonderilmedi; isleri kontrol edin."')
    checking = modal+'; state.craft.submitted=true; state.craft.pending=true; state.craft.jobState="computing"'
    failure = modal+'; state.craft.submitted=true; state.craft.finished=true; state.craft.jobState="failed"; state.craft.error="AE2 isi baslatamadi. Kaynak eksigi veya uygun CPU/bellek sorunu olabilir. ME Terminal\\\'de kontrol edin."; state.craft.rawError="request failed (missing resources?)"'
    render("main-craft-checking", 160, 50, checking)
    render("main-craft-failed", 160, 50, failure)
    render("main-craft-failed-small", 40, 12, failure)
    render("main-craft-failed-small-details", 40, 12, failure+'; state.craft.detailPage=2')
    for name, width, height in (("main-stock-rules", 160, 50), ("main-stock-rules-compact", 80, 25), ("main-stock-rules-small", 40, 12), ("main-stock-rules-medium", 50, 16)):
        render(name, width, height, "state.tab=3")
    rule_modal = 'state.tab=3; state.ruleEditor={id=1,label="Infused Alloy / Meta: 0",minimum="2048",target="4096",field="minimum"}'
    render("main-stock-rule-editor", 160, 50, rule_modal)
    render("main-stock-rule-editor-compact", 80, 25, rule_modal)
    render("main-stock-rule-editor-small", 40, 12, rule_modal)
    web_menu = 'state.serverStatus=net.status; state.webMenu=true; state.editing=true; state.field="url"; state.webStatus={phase="online"}; state.draft={url="https://panel.factory.example",token=string.rep("a",64),control=true}'
    render("server-web-settings", 50, 16, web_menu, role="server")
    render("server-web-settings-small", 40, 12, web_menu, role="server")
    render("server-web-keyboard-small", 40, 12, web_menu+'; state.keyboard=true; state.field="token"', role="server")
