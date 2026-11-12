local C=require("ui.renderer").colors
local W=require("ui.widgets")
local F=require("ui.format")
local M={}
local labels={submitting="GONDERILIYOR",computing="HESAPLANIYOR",running="CALISIYOR",done="TAMAMLANDI",
  canceled="IPTAL EDILDI",cancel_requested="IPTAL BEKLENIYOR",failed="HATA",unknown="DURUMU BILINMIYOR",reviewed="ELLE ARSIVLENDI"}
function M.jobs(r,l,state,net)
  W.panel(r,l.x,l.y,l.w,l.bottom-l.y+1,"URETIM / EMIRLER VE CPU")
  local tiny=l.bottom-l.y<8; local compact=l.bottom-l.y<22
  local jobs=state.jobs or {}; local cpus=jobs.cpus or {}; local busy=0
  for _,cpu in ipairs(cpus) do if cpu.busy then busy=busy+1 end end
  if not tiny then W.text(r,l.x+1,l.y+2,l.w-2,state.jobsError or ("CPU: "..busy.." / "..#cpus.." mesgul | "..(jobs.error~="" and jobs.error or "AE2 otomatik CPU secimi")),C.muted) end
  local start=l.y+(tiny and 1 or compact and 4 or 8)
  if not compact then
    local names={}
    for i=1,math.min(3,#cpus) do names[#names+1]=(cpus[i].name~="" and cpus[i].name or "Isimsiz CPU")..(cpus[i].busy and " [MESGUL]" or " [BOS]") end
    W.wrap(r,l.x+2,l.y+4,l.w-4,2,table.concat(names," | "),C.blue)
    W.text(r,l.x+2,l.y+6,l.w-4,"Yalnizca FactoryOS'tan verilen emirler izlenir.",C.muted)
  end
  local rows=jobs.trackedJobs or {}; local step=compact and 3 or 5
  local count=math.max(1,math.floor((l.bottom-start-2)/step))
  local pages=math.max(1,math.ceil(#rows/count)); state.jobsPage=math.min(pages,state.jobsPage or 1)
  if #rows==0 then W.text(r,l.x+2,start,l.w-4,"Henuz uretim emri yok. Depodan tarifli urun secin.",C.muted) end
  for i=1,count do
    local job=rows[(state.jobsPage-1)*count+i]; if not job then break end
    local y=start+(i-1)*step
    local color=job.state=="done" and C.good or (job.state=="failed" or job.state=="unknown") and C.warn or C.accent
    W.text(r,l.x+2,y,l.w-4,F.integer(job.amount).." x "..job.label,C.text)
    local cancelable=job.state=="running" or job.state=="computing"
    local owned=job.automatic or job.owner==((state.context or {}).modem)
    local status=labels[job.state] or "BILINMIYOR"
    if compact and job.state=="failed" and job.error and job.error~="" then status=status.." / "..(job.errorMessage or job.error) end
    W.text(r,l.x+2,y+1,l.w-((cancelable and owned) and 15 or 4),status,color)
    if cancelable and owned then r:button(l.x+l.w-12,y+1,10,"IPTAL ET","cancelcraft:"..job.id,false,1,not (state.canceling or {})[job.id]) end
    if job.state=="unknown" and owned then r:button(l.x+l.w-19,y+1,17,"ME'DE BAKTIM","archivecraft:"..job.id,false,1,not (state.canceling or {})[job.id]) end
    if not compact then
      W.text(r,l.x+2,y+2,l.w-4,(job.automatic and "STOK KURALI | " or "").."CPU: "..(job.cpu~="" and job.cpu or "Otomatik / AE2 secimi"),C.muted)
      W.text(r,l.x+2,y+3,l.w-4,job.error~="" and (job.errorMessage or job.error) or job.id,C.muted)
    end
    if job.error and job.error~="" then r:button(l.x+l.w-12,y+(compact and 2 or 3),10,"HATA DETAY","craftdetail:"..job.id,false,1) end
  end
  local y=tiny and l.bottom or l.bottom-1
  if not tiny and jobs.craftingError and jobs.craftingError~="" then W.text(r,l.x+1,l.bottom,l.w-2,jobs.craftingError,C.warn) end
  if pages>1 then
    r:button(l.x+1,y,8,"ONCE","jobsprev",false,1,state.jobsPage>1)
    W.text(r,l.x+10,y,math.max(1,l.w-21),state.jobsPage.." / "..pages,C.muted)
    r:button(l.x+l.w-9,y,8,"SONRA","jobsnext",false,1,state.jobsPage<pages)
  end
end
local function result(r,c)
  local width=math.min(92,r.w-2); local height=math.min(22,r.h-2)
  local x=math.floor((r.w-width)/2)+1; local y=math.max(2,math.floor((r.h-height)/2))
  r:fill(1,2,r.w,r.h-2,C.bg); W.panel(r,x,y,width,height,"AE2 / KAYNAK KONTROLU VE SONUC")
  W.text(r,x+2,y+1,width-4,c.label,C.text)
  W.text(r,x+2,y+2,width-4,c.amount.." adet | CPU: "..(c.cpu~="" and c.cpu or "OTOMATIK"),C.muted)
  W.text(r,x+2,y+3,width-4,c.submitting and "EMIR GONDERILIYOR" or c.pending and "KAYNAKLAR / URETIM PLANI DENETLENIYOR" or (labels[c.jobState] or "SONUC / HATA"),c.pending and C.accent or C.warn)
  local message=c.error or (c.submitting and "Emir diske kaydediliyor; yanit bekleniyor." or "AE2 kaynaklari ve plani denetliyor. Uretimin basladigi henuz dogrulanmadi. Isleri izleyebilirsiniz.")
  if c.rawError and c.rawError~="" then message=message.." | SURUCU: "..c.rawError end
  local lines={}; local size=width-4
  for word in F.clean(message):gmatch("%S+") do
    if #lines==0 then lines[1]="" end
    while #word>size do
      if lines[#lines]~="" then lines[#lines+1]="" end
      lines[#lines]=word:sub(1,size); lines[#lines+1]=""; word=word:sub(size+1)
    end
    local last=lines[#lines]
    if #last>0 and #last+1+#word>size then lines[#lines+1]=word else lines[#lines]=last..(#last>0 and " " or "")..word end
  end
  local count=math.max(1,height-7); c.detailPages=math.max(1,math.ceil(#lines/count)); c.detailPage=math.min(c.detailPage or 1,c.detailPages)
  for i=1,count do W.text(r,x+2,y+3+i,size,lines[(c.detailPage-1)*count+i] or "",c.error and C.warn or C.muted) end
  local p=y+height-3
  if c.detailPages>1 then
    r:button(x+2,p,7,"ONCE","craft:detailprev",false,1,c.detailPage>1)
    W.text(r,x+10,p,size-18,c.detailPage.." / "..c.detailPages,C.muted)
    r:button(x+width-9,p,7,"SONRA","craft:detailnext",false,1,c.detailPage<c.detailPages)
  end
  local half=math.floor((width-5)/2)
  r:button(x+2,y+height-2,half,"KAPAT","craft:close",false,1,not c.submitting)
  r:button(x+3+half,y+height-2,half,"ISLERI GOR","craft:jobs",true,1,not c.submitting)
end
function M.modal(r,state)
  local c=state.craft; if not c then return end
  r.buttons={}
  if c.submitted then result(r,c); return end
  local tall=r.h>=24; local step=tall and 2 or 1
  local width=math.min(76,r.w-2); local height=tall and 18 or 10
  local x=math.floor((r.w-width)/2)+1; local y=math.max(2,math.floor((r.h-height)/2))
  r:fill(1,2,r.w,r.h-2,C.bg)
  W.panel(r,x,y,width,height,"AE2 / URETIM EMRI")
  W.text(r,x+2,y+1,width-4,c.label..(c.variant or ""),C.text)
  W.text(r,x+2,y+step+1,width-4,"MIKTAR: "..c.amount..(c.submitted and "" or "_"),C.accent)
  local cell=math.floor((width-4)/4)
  for i,n in ipairs({1,8,16,64}) do r:button(x+2+(i-1)*cell,y+step*2+1,cell-1,tostring(n),"craft:preset:"..n,false,1,not c.submitted) end
  local digit=math.floor((width-4)/10)
  for i=1,10 do r:button(x+2+(i-1)*digit,y+step*3+1,digit-1,tostring(i%10),"craft:"..i%10,false,1,not c.submitted) end
  r:button(x+2,y+step*4+1,math.floor((width-5)/2),"SIL","craft:back",false,1,not c.submitted)
  r:button(x+2+math.floor((width-3)/2),y+step*4+1,math.floor((width-5)/2),"TEMIZLE","craft:clear",false,1,not c.submitted)
  r:button(x+2,y+step*5+1,width-4,"CPU: "..(c.cpu~="" and c.cpu or "OTOMATIK").." >","craft:cpu",false,1,not c.submitted and not c.loading)
  W.wrap(r,x+2,y+step*6+1,width-4,tall and 2 or 1,c.error or c.loading and "Tarif ve CPU bilgisi aliniyor..." or c.submitting and "Emir gonderiliyor; yanit bekleniyor..." or "Adet miktari, stok hedefi degildir.",c.error and C.warn or C.muted)
  local actions=y+step*7+1; local half=math.floor((width-5)/2)
  r:button(x+2,actions,half,"VAZGEC","craft:close",false,tall and 2 or 1,not c.submitting)
  r:button(x+3+half,actions,half,c.uncertain and "ISLERI GOR" or (c.amount.." ADET URET"),c.uncertain and "craft:jobs" or "craft:submit",true,tall and 2 or 1,c.uncertain or not c.loading and not c.submitted and c.preview~=nil)
end
return M
