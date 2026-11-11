local C=require("ui.renderer").colors
local W=require("ui.widgets")
local F=require("ui.format")
local identity=require("core.items")
local M={tabs={"ANA PANEL","AE2 DEPOSU","STOK HEDEFLERI","URETIM","ENERJI","MAKINELER","ALARMLAR","AYARLAR","GUNCELLEMELER"}}
local function time(clock) return type(clock)=="function" and clock() or 0 end
local function favorite(state,item)
  local key=identity.key(item)
  return key and (state.favorites or {})[key]~=nil
end
local function age(now,stamp) return type(stamp)=="number" and math.max(0,math.floor(now-stamp)) or nil end
local function cpuState(net,state)
  if not net.online or not (net.status or {}).ae2 or not net.status.ae2.online or not state.jobs or state.jobsError or (state.jobs.error and state.jobs.error~="") then return nil end
  local busy=0
  for _,cpu in ipairs(state.jobs.cpus or {}) do if cpu.busy then busy=busy+1 end end
  return busy,#(state.jobs.cpus or {})
end
function M.layout(r)
  local nav=r.w>=110 and 22 or r.w>=70 and r.h>=24 and 18 or 0
  local x=nav>0 and nav+4 or 2
  local rail=r.w>=130 and r.h>=32 and 30 or 0
  local y=nav>0 and 6 or 7
  return {nav=nav,x=x,y=y,w=r.w-x-rail-(rail>0 and 3 or 0),bottom=r.h-2,rail=rail,railX=r.w-rail}
end
function M.alerts(net,state)
  local result={}
  local function add(title,detail,color) result[#result+1]={title=title,detail=detail,color=color} end
  local status=net.status or {}; local ae=status.ae2 or {}
  if not net.online then add("SUNUCUYA ULASILAMIYOR","Baglanti otomatik olarak yeniden denenecek.",C.bad)
  elseif not ae.online then add("AE2 BAGLANTISI YOK",ae.error or "Adapter ve ME agini kontrol edin.",C.warn)
  else
    local e=(status.power or {}).ae2 or {}
    if e.supported and (e.capacity or 0)>0 and e.stored/e.capacity<0.15 then add("AE2 ENERJISI DUSUK",F.percent(e.stored,e.capacity).." doluluk / "..F.compact(e.stored).." AE",C.warn) end
    if ae.truncated then add("ENVANTER SINIRI","Yalnizca ilk 2000 varyant listeleniyor.",C.warn) end
    if state.stockError then add("DEPO VERISI ALINAMADI",state.stockError,C.warn) end
    if state.jobsError or state.jobs and state.jobs.error and state.jobs.error~="" then add("CPU VERISI ALINAMADI",state.jobsError or state.jobs.error,C.warn) end
  end
  return result
end
local function header(r,net,state,now)
  r:fill(1,1,r.w,4,C.panel); r:fill(1,1,r.w,1,C.accent)
  r:text(3,2,"FACTORY / OS",C.accent,C.panel)
  if r.w>=100 then r:text(23,2,"FABRIKA KONTROL MERKEZI",C.muted,C.panel) end
  local ae=(net.status or {}).ae2 or {}
  local start=r.w>=100 and r.w-43 or r.w-25
  W.text(r,start,2,r.w>=100 and 21 or 12,"SRV "..(net.online and "ONLINE" or "OFFLINE"),net.online and C.good or C.bad)
  W.text(r,r.w-12,2,12,"AE2 "..(not net.online and "--" or ae.online and "ONLINE" or "OFFLINE"),not net.online and C.muted or ae.online and C.good or C.warn)
  W.text(r,3,4,math.max(1,r.w-29),"DISPLAY 01 / "..(M.tabs[state.tab or 1] or M.tabs[1]),C.text)
  if r.w>=70 then W.text(r,r.w-25,4,24,"SON YANIT  "..(net.online and tostring(age(now,net.lastSeen) or 0).." sn" or "--"),C.muted,nil,"right") end
end
local function navigation(r,l,state)
  if l.nav==0 then
    r:button(2,5,8,"< MENU","tabprev")
    W.text(r,11,5,r.w-21,M.tabs[state.tab or 1],C.accent,C.bg)
    r:button(r.w-9,5,9,"MENU >","tabnext"); return
  end
  W.panel(r,2,6,l.nav,r.h-7,"KONTROL PANELI")
  local height=r.h>=42 and 3 or 1
  local step=height+1
  local top=r.h>=42 and 9 or 7
  for i,label in ipairs(M.tabs) do
    if r.h<42 then label=({"PANEL","DEPO","STOK HEDEF","URETIM","ENERJI","MAKINELER","ALARMLAR","AYARLAR","GUNCELLEME"})[i] end
    if i==9 and (state.update or {}).available then label=label.." *" end
    local y=top+(i-1)*step
    r:button(3,y,l.nav-2,string.format("%02d ",i)..label,"tab:"..i,state.tab==i,height)
  end
  if r.h>=32 then r:button(3,r.h-4,l.nav-2,"VERIYI YENILE","refresh",false,r.h>=42 and 2 or 1) end
end
local function rail(r,l,net,state,now,alerts)
  if l.rail==0 then return end
  local x,w=l.railX,l.rail
  W.panel(r,x,6,w,8,"AG DURUMU")
  W.text(r,x+2,8,w-4,"SUNUCU",C.muted)
  W.text(r,x+11,8,w-13,net.online and "BAGLI" or "OFFLINE",net.online and C.good or C.bad,nil,"right")
  W.text(r,x+2,10,w-4,"AE2 AGI",C.muted)
  local ae=(net.status or {}).ae2 or {}
  W.text(r,x+11,10,w-13,not net.online and "--" or ae.online and "AKTIF" or "BAGLANTI YOK",not net.online and C.muted or ae.online and C.good or C.warn,nil,"right")
  W.text(r,x+2,12,w-4,"Son yanit: "..(net.online and (age(now,net.lastSeen) or 0).." sn" or "--"),C.muted)
  local selected=state.tab==2 and state.selected and net.online and ae.online and not state.stockError and state.selected
  W.panel(r,x,16,w,15,selected and "SECILI URUN" or "URETIM OZETI")
  if selected and net.online then
    W.wrap(r,x+2,18,w-4,2,selected.label,C.text)
    W.text(r,x+2,20,w-4,selected.name,C.muted)
    W.text(r,x+2,21,w-4,"Stok: "..F.integer(selected.size),C.accent)
    W.text(r,x+2,23,w-4,"Meta: "..tostring(selected.damage)..(selected.hasTag and " | NBT var" or " | NBT yok"),C.muted)
    W.text(r,x+2,25,w-4,selected.isCraftable and "Tarif: mevcut" or "Tarif: yok",selected.isCraftable and C.good or C.muted)
    local complete=identity.key(selected)~=nil
    if not complete then W.text(r,x+2,27,w-4,"NBT kimligi belirsiz",C.warn) end
    r:button(x+2,28,w-4,favorite(state,selected) and "FAVORIDEN KALDIR" or "FAVORIYE EKLE","favorite:selected",favorite(state,selected),2,complete)
  else
    local busy,total=cpuState(net,state)
    W.text(r,x+2,18,w-4,"MESGUL / TOPLAM CPU",C.muted)
    W.text(r,x+2,20,w-4,busy and busy.." / "..total or "-- / --",busy and C.accent or C.muted)
    W.text(r,x+2,23,w-4,"Crafting kontrolu: pasif",C.muted)
    W.wrap(r,x+2,25,w-4,3,"CPU dolulugu izlenir. Is ayrintilari henuz okunmuyor.",C.muted)
    r:button(x+2,29,w-4,"CPU'LARI GOR","tab:4")
  end
  W.panel(r,x,33,w,math.max(1,l.bottom-32),"SISTEM UYARILARI / "..#alerts)
  if #alerts==0 then
    W.text(r,x+2,36,w-4,"AKTIF UYARI YOK",C.good)
    W.wrap(r,x+2,39,w-4,3,"Baglanti ve enerji durumlari duzenli izleniyor.",C.muted)
  else
    for i,a in ipairs(alerts) do
      local y=35+(i-1)*5
      if y+2>l.bottom then break end
      W.text(r,x+2,y,w-4,a.title,a.color)
      W.wrap(r,x+2,y+1,w-4,3,a.detail,C.muted)
    end
  end
end
local function offline(r,l,net)
  W.panel(r,l.x,l.y,l.w,l.bottom-l.y+1,"BAGLANTI BEKLENIYOR")
  W.text(r,l.x+2,l.y+2,l.w-4,"SUNUCU OFFLINE",C.bad)
  W.wrap(r,l.x+2,l.y+4,l.w-4,3,"Baglanti geri geldiginde panel otomatik yenilenecek. Son alinan stok ve enerji degerleri guncel olarak gosterilmiyor.",C.muted)
  if l.bottom-l.y>=12 then
    W.text(r,l.x+2,l.y+10,l.w-4,"Modem adreslerini ve kablosuz menzili kontrol edin.",C.muted)
    r:button(l.x+2,l.y+13,math.min(22,l.w-4),"BAGLANTI AYARLARI","tab:8",false,2)
  end
end
local function overview(r,l,net,state)
  local status=net.status or {}; local ae=status.ae2 or {}; local e=(status.power or {}).ae2 or {}
  if l.bottom-l.y<24 or l.w<60 then
    W.panel(r,l.x,l.y,l.w,l.bottom-l.y+1,"FABRIKA OZETI")
    W.text(r,l.x+1,l.y+2,l.w-2,"AE2: "..(ae.online and "AKTIF" or "BAGLANTI YOK"),ae.online and C.good or C.warn)
    W.text(r,l.x+1,l.y+4,l.w-2,"Varyant: "..(ae.online and F.integer(ae.itemTypes) or "--"),C.accent)
    if l.y+6<=l.bottom then W.text(r,l.x+1,l.y+6,l.w-2,"Enerji: "..(ae.online and e.supported and F.percent(e.stored,e.capacity) or "--"),C.muted) end
    if l.y+9<=l.bottom then r:button(l.x+1,l.y+9,math.min(19,l.w-2),"DEPOYU AC","tab:2",false,2) end
    return
  end
  local card=math.floor((l.w-4)/3)
  local busy,total=cpuState(net,state)
  W.metric(r,l.x,l.y,card,"AE2 / ESYA VARYANTI",ae.online and F.compact(ae.itemTypes) or "--",ae.truncated and "2000 varyant siniri" or "depolama envanteri",ae.online and C.accent or C.muted)
  W.metric(r,l.x+card+2,l.y,card,"URETIM / CPU",busy and busy.." / "..total or "-- / --","mesgul / toplam CPU",busy and C.blue or C.muted)
  W.metric(r,l.x+card*2+4,l.y,l.w-card*2-4,"AE2 / ENERJI",ae.online and e.supported and F.percent(e.stored,e.capacity) or "--",ae.online and e.supported and F.compact(e.stored).." AE depolandi" or "enerji bilgisi bekleniyor",ae.online and e.supported and C.good or C.muted)
  local middle=l.y+10
  W.panel(r,l.x,middle,l.w,14,"FABRIKA GENEL DURUMU")
  local function row(y,label,value,color)
    W.text(r,l.x+2,y,l.w-28,label,C.muted)
    W.text(r,l.x+l.w-26,y,24,value,color,nil,"right")
  end
  row(middle+3,"AE2 DEPOLAMA",ae.online and "CEVRIMICI" or "BAGLANTI YOK",ae.online and C.good or C.warn)
  row(middle+5,"OTOMATIK STOK","SONRAKI ASAMA",C.muted)
  row(middle+7,"CRAFTING KONTROLU","IZLEME MODU",C.blue)
  local button=math.floor((l.w-6)/2)
  r:button(l.x+2,middle+10,button,"AE2 DEPOSUNU AC","tab:2",true,2)
  r:button(l.x+button+4,middle+10,l.w-button-6,"URETIM CPU'LARI","tab:4",false,2)
  local y=middle+16
  W.panel(r,l.x,y,l.w,l.bottom-y+1,"BAGLI PANELLER")
  W.text(r,l.x+2,y+2,math.floor(l.w/2)-2,"ROL",C.muted)
  W.text(r,l.x+math.floor(l.w/2),y+2,15,"DURUM",C.muted)
  W.text(r,l.x+l.w-18,y+2,16,"SON HABER",C.muted,nil,"right")
  local clients=status.clients or {}
  if #clients==0 then W.text(r,l.x+2,y+4,l.w-4,"Panel listesi bir sonraki durum paketinde yenilenir.",C.muted) end
  for i,c in ipairs(clients) do
    local rowY=y+3+i*2
    if rowY>l.bottom-2 then break end
    W.text(r,l.x+2,rowY,math.floor(l.w/2)-2,c.role=="main" and "ANA EKRAN / 01" or c.role=="side" and "YAN EKRAN / 02" or c.role,C.text)
    W.text(r,l.x+math.floor(l.w/2),rowY,15,"BAGLI",C.good)
    W.text(r,l.x+l.w-18,rowY,16,(c.age or 0).." sn",C.muted,nil,"right")
  end
  if l.bottom-y>=14 then
    W.text(r,l.x+2,y+11,math.floor(l.w/2)-2,"SUNUCU CALISMA SURESI",C.muted)
    W.text(r,l.x+2,y+13,math.floor(l.w/2)-2,F.duration(status.uptime),C.accent)
    W.text(r,l.x+math.floor(l.w/2),y+11,math.floor(l.w/2)-2,"SUNUCU SURUMU",C.muted)
    W.text(r,l.x+math.floor(l.w/2),y+13,math.floor(l.w/2)-2,"v"..(status.version or "--"),C.text)
  end
end
local function stockRows(r,l,state,start,visible,small)
  local stocks=state.stocks
  state.visibleRows=visible
  local rows=stocks and stocks.items or {}
  for i=1,visible do
    local index=i+(state.rowOffset or 0); local item=rows[index]
    if item then
      local y=start+i-1
      local bg=state.selected==item and C.selected or i%2==0 and C.stripe or C.panel
      r:fill(l.x+1,y,l.w-2,1,bg)
      local star=favorite(state,item) and "*" or "+"
      r:text(l.x+2,y,identity.key(item) and star or "?",favorite(state,item) and C.warn or C.muted,bg)
      r:hotspot(l.x+1,y,3,1,"favorite:"..index)
      if small then
        W.text(r,l.x+5,y,math.max(1,l.w-18),item.label,C.text,bg)
        W.text(r,l.x+l.w-12,y,10,F.compact(item.size),C.accent,bg,"right")
      else
        W.text(r,l.x+5,y,l.w-35,item.label,C.text,bg)
        W.text(r,l.x+l.w-29,y,7,tostring(item.damage)..(item.hasTag and " NBT" or ""),C.muted,bg)
        W.text(r,l.x+l.w-21,y,12,F.integer(item.size),C.accent,bg,"right")
        W.text(r,l.x+l.w-8,y,6,item.isCraftable and "VAR" or "--",item.isCraftable and C.good or C.muted,bg,"right")
      end
      r:hotspot(l.x+4,y,l.w-6,1,"item:"..index)
    end
  end
end
local function pager(r,l,state,y,height)
  local data=state.stocks or {items={},page=1,pages=1,total=0}
  local offset=state.rowOffset or 0
  local before=data.page>1 or offset>0
  local after=data.page<data.pages or offset+(state.visibleRows or 24)<#data.items
  r:button(l.x+1,y,8,"< ONCE","prev",false,height,before and not state.loadingStocks)
  r:button(l.x+l.w-10,y,9,"SONRA >","next",false,height,after and not state.loadingStocks)
  local first=data.total>0 and (data.page-1)*24+offset+1 or 0
  local last=math.min(data.total,(data.page-1)*24+offset+(state.visibleRows or 24))
  W.text(r,l.x+11,y,math.max(0,l.w-23),first.."-"..last.." / "..F.integer(data.total),C.muted)
end
local function stocks(r,l,net,state,now)
  local small=r.h<24
  if small then
    W.panel(r,l.x,l.y,l.w,l.bottom-l.y+1,"DEPO / "..(state.loadingStocks and "YUKLENIYOR" or state.query or ""))
    local visible=math.max(1,l.bottom-l.y-2)
    local ae=(net.status or {}).ae2 or {}
    if not ae.online then W.text(r,l.x+1,l.y+1,l.w-2,"AE2 baglantisi yok",C.warn)
    elseif not state.stockError then stockRows(r,l,state,l.y+1,visible,true) end
    r:button(l.x,l.bottom,8,"< ONCE","prev")
    r:button(l.x+9,l.bottom,8,"SONRA >","next")
    r:button(l.x+l.w-10,l.bottom,10,"ARA","search",false,1,net.online)
    if state.stockError then W.text(r,l.x+1,l.y+1,l.w-2,state.stockError,C.warn) end
    return
  end
  local short=r.h<36
  local inputY=l.y+(short and 1 or 2)
  local filterY=l.y+(short and 3 or 4)
  W.panel(r,l.x,l.y,l.w,short and 5 or 7,"AE2 / ENVANTER")
  r:fill(l.x+2,inputY,math.max(1,l.w-25),1,C.bg)
  W.text(r,l.x+3,inputY,math.max(1,l.w-27),state.query~="" and state.query or "Urun adi veya mod kimligi ara...",state.query~="" and C.text or C.muted,C.bg)
  r:hotspot(l.x+2,inputY,math.max(1,l.w-25),1,"search")
  r:button(l.x+l.w-21,inputY,9,"ARA","search",true)
  r:button(l.x+l.w-11,inputY,9,"TEMIZLE","clear",false,1,state.query~="")
  r:button(l.x+2,filterY,7,"TUM","filter:all",state.filter=="all")
  r:button(l.x+10,filterY,9,"TARIFLI","filter:craftable",state.filter=="craftable")
  r:button(l.x+20,filterY,10,"FAVORILER","filter:favorites",state.filter=="favorites")
  if l.w>=47 then r:button(l.x+l.w-16,filterY,14,state.sort=="amount" and "MIKTAR v" or "AD A-Z","sort") end
  local y=l.y+(short and 6 or 9)
  W.panel(r,l.x,y,l.w,l.bottom-y+1,"DEPO KAYITLARI")
  local large=l.w>=70
  local headings=y+(short and 1 or 2)
  W.text(r,l.x+2,headings,l.w-4,large and "*  URUN / VARYANT" or "*  URUN",C.muted)
  if large then W.text(r,l.x+l.w-29,headings,7,"META",C.muted); W.text(r,l.x+l.w-21,headings,12,"MIKTAR",C.muted,nil,"right"); W.text(r,l.x+l.w-8,headings,6,"TARIF",C.muted,nil,"right") end
  local start=y+(short and 2 or 4)
  local visible=math.max(1,math.min(24,l.bottom-start-(short and 2 or 3)))
  state.visibleRows=visible
  local ae=(net.status or {}).ae2 or {}
  if not ae.online then W.wrap(r,l.x+2,start,l.w-4,3,"AE2 baglantisi yok. Adapter ve aktif ME agini kontrol edin.",C.warn)
  elseif state.stockError then W.wrap(r,l.x+2,start,l.w-4,3,state.stockError,C.warn)
  elseif state.loadingStocks and not state.stocks then W.text(r,l.x+2,start,l.w-4,"ENVANTER ALINIYOR...",C.accent)
  elseif not state.stocks then W.text(r,l.x+2,start,l.w-4,"Veri bekleniyor...",C.muted)
  elseif state.stocks.total==0 then W.text(r,l.x+2,start,l.w-4,state.filter=="favorites" and "Henuz favori yok. Urun satirindaki + isaretine dokunun." or "Bu aramada urun bulunamadi.",C.muted)
  else stockRows(r,l,state,start,visible,not large) end
  pager(r,l,state,l.bottom-(short and 1 or 2),short and 1 or 2)
  if state.stocks and state.stocks.truncated then W.text(r,l.x+2,l.bottom,l.w-4,"2000 VARYANT SINIRI / LISTE KISITLI",C.warn)
  elseif state.stockReceivedAt then W.text(r,l.x+2,l.bottom,l.w-4,"Guncelleme: "..(age(now,state.stockReceivedAt) or 0).." sn once | + favori / satir detay",C.muted) end
end
local function content(r,l,net,state,alerts)
  local tab=state.tab
  W.panel(r,l.x,l.y,l.w,l.bottom-l.y+1,M.tabs[tab] or "PANEL")
  local function line(offset,text,color) if l.y+offset<=l.bottom then W.text(r,l.x+2,l.y+offset,l.w-4,text,color) end end
  if tab==3 then
    line(3,"OTOMATIK STOK / SONRAKI ASAMA",C.accent)
    W.wrap(r,l.x+2,l.y+6,l.w-4,5,"Hedef stok belirleme ve otomatik crafting henuz etkin degil. Once AE2 uretim API'si gercek malzemelerle dogrulanacak.",C.muted)
    if l.y+14<l.bottom then r:button(l.x+2,l.y+14,math.min(24,l.w-4),"STOKLARI INCELE","tab:2",true,2) end
  elseif tab==4 then
    line(2,"CRAFTING CPU / SALT OKUNUR",C.blue)
    line(4,state.jobsError or "CPU dolulugu gosterilir; mevcut is ayrintilari okunmaz.",state.jobsError and C.warn or C.muted)
    local busy,total=cpuState(net,state)
    if not busy then line(7,"CPU verisi bekleniyor veya AE2 bagli degil.",C.muted)
    elseif total==0 then line(7,"AE2 aginda crafting CPU bulunamadi.",C.warn)
    else
      for i,cpu in ipairs(state.jobs.cpus or {}) do
        local y=l.y+6+i*2
        if y>=l.bottom-4 then break end
        W.text(r,l.x+2,y,math.max(1,l.w-27),cpu.name~="" and cpu.name or "Isimsiz CPU "..i,C.text)
        W.text(r,l.x+l.w-24,y,11,F.compact(cpu.storage).." B",C.muted)
        W.text(r,l.x+l.w-12,y,10,cpu.busy and "MESGUL" or "BOSTA",cpu.busy and C.blue or C.good,nil,"right")
      end
    end
    if l.bottom-l.y>=8 then line(l.bottom-l.y-1,"UZAKTAN URETIM BASLATMA / PASIF",C.muted) end
  elseif tab==5 then
    local ae=(net.status or {}).ae2 or {}; local e=((net.status or {}).power or {}).ae2 or {}
    line(3,"AE2 AG ENERJISI",C.accent)
    if ae.online and e.supported then
      line(6,F.integer(e.stored).." / "..F.integer(e.capacity).." AE",C.text)
      if l.y+8<=l.bottom then r:bar(l.x+2,l.y+8,l.w-4,(e.capacity or 0)>0 and e.stored/e.capacity or 0) end
      line(10,"Doluluk: "..F.percent(e.stored,e.capacity),C.accent)
      line(13,"Giris: "..F.compact(e.injection).." AE/t | Tuketim: "..F.compact(e.usage).." AE/t",C.muted)
    else line(6,"AE2 enerji bilgisi kullanilamiyor.",C.muted) end
    line(18,"RF/FE depolari ve reaktor suruculeri henuz eklenmedi.",C.muted)
  elseif tab==6 then
    line(3,"MAKINE SURUCULERI BEKLENIYOR",C.blue)
    W.wrap(r,l.x+2,l.y+6,l.w-4,5,"Mekanism makineleri ve diger uretim hatlari gercek Adapter metotlari dogrulandikca eklenecek. Bu surum makine acma/kapama komutu gondermez.",C.muted)
  elseif tab==7 then
    if #alerts==0 then line(3,"AKTIF UYARI YOK",C.good) end
    for i,a in ipairs(alerts) do
      local y=l.y+2+(i-1)*6
      if y>l.bottom-2 then break end
      W.text(r,l.x+2,y,l.w-4,a.title,a.color)
      W.wrap(r,l.x+2,y+2,l.w-4,3,a.detail,C.muted)
    end
  elseif tab==8 then
    local c=state.context or {}
    local details={{"YEREL MODEM",c.modem},{"SUNUCU MODEMI",net.server or c.serverAddress},{"EKRAN",c.screen},
      {"COZUNURLUK",r.w.." x "..r.h.." karakter"},{"AG PORTU",c.port or 34100},{"AE2 YENILEME",(c.poll or 10).." sn"}}
    for i,pair in ipairs(details) do
      local y=l.y+2+(i-1)*4
      if y+1>l.bottom then break end
      W.text(r,l.x+2,y,l.w-4,pair[1],C.muted)
      W.text(r,l.x+2,y+1,l.w-4,pair[2] and pair[2]~="" and pair[2] or "Otomatik kesif / bilinmiyor",C.text)
    end
    if l.bottom-l.y>29 then r:button(l.x+2,l.y+28,math.min(30,l.w-4),"YAZILIM / GUNCELLEMELER","tab:9",false,2) end
  end
end
local function keyboard(r,l,state)
  if not state.editing then return end
  -- Modal hit testing: touches never fall through to navigation or inventory.
  r.buttons={}
  local width=math.min(86,r.w-4,l.w)
  local tall=r.h>=24
  local height=tall and 16 or 10
  local x=l.x+math.floor((l.w-width)/2)
  local y=tall and math.max(5,math.floor((r.h-height)/2)) or 2
  r:fill(l.x,l.y,l.w,l.bottom-l.y+1,C.bg)
  W.panel(r,x,y,width,height,"URUN ARA / DOKUNMATIK KLAVYE")
  r:fill(x+1,y+1,width-2,1,C.bg)
  W.text(r,x+2,y+1,width-12,(state.draft or "").."_",C.text,C.bg)
  r:button(x+width-9,y+1,8,"TEMIZLE","key:clear")
  local rows={"1234567890","qwertyuiop","asdfghjkl","zxcvbnm_-:"}
  local cell=math.max(3,math.floor((width-2)/10))
  for row,letters in ipairs(rows) do
    local left=x+math.floor((width-cell*#letters)/2)
    for i=1,#letters do
      local char=letters:sub(i,i)
      r:button(left+(i-1)*cell,y+(tall and 3 or 2)+(row-1)*(tall and 2 or 1),cell-1,char,"key:"..char,false,tall and 2 or 1)
    end
  end
  local buttons={{"SIL","back"},{"BOSLUK","space"},{"IPTAL","cancel"},{"ARA","apply"}}
  local button=math.floor((width-5)/4)
  for i,b in ipairs(buttons) do r:button(x+1+(i-1)*(button+1),y+height-3,button,b[1],"key:"..b[2],i==4,tall and 2 or 1) end
end
function M.draw(r,net,state,clock)
  local now=time(clock); local l=M.layout(r); local alerts=M.alerts(net,state)
  r:begin(); header(r,net,state,now); navigation(r,l,state)
  if not net.online and state.tab~=8 and state.tab~=7 and state.tab~=9 then offline(r,l,net)
  elseif state.tab==1 then overview(r,l,net,state)
  elseif state.tab==2 then stocks(r,l,net,state,now)
  elseif state.tab==9 then require("ui.updates").draw(r,l.x,l.y,l.w,l.bottom-l.y+1,state.update)
  else content(r,l,net,state,alerts) end
  rail(r,l,net,state,now,alerts)
  r:fill(1,r.h,r.w,1,C.raised)
  local notice=state.message and now-state.message.at<6 and state.message
  W.text(r,2,r.h,r.w-2,notice and notice.text or state.editing and "Arama: dokun / yaz | Enter: ara | Esc: iptal" or "DISPLAY 01 / v0.3.2 | "..((state.update or {}).available and "GUNCELLEME VAR" or net.online and "CANLI IZLEME" or "YENIDEN BAGLANIYOR"),notice and notice.kind=="warn" and C.warn or C.muted,C.raised)
  keyboard(r,l,state)
  r:flush()
end
return M
