local storage=require("core.storage")
local fs=require("filesystem")
local identity=require("core.items")
local uuid=require("uuid")
local errors=require("core.craft_errors")
local M={path="/var/lib/factoryos/crafting.dat"}
local active={submitting=true,computing=true,running=true,cancel_requested=true,unknown=true}
local terminal={done=true,canceled=true,failed=true,reviewed=true}
local function text(s) return tostring(s or ""):gsub("[%c]"," "):sub(1,240) end
local function integer(n,min,max) return type(n)=="number" and n==n and n%1==0 and n>=min and n<=max end
local function call(p,method,...)
  if not p then return nil,"unsupported: "..method end
  local accessible,fn=pcall(function() return p[method] end)
  if not accessible then return nil,text(fn) end
  if fn==nil then return nil,"unsupported: "..method end
  local ok,a,b=pcall(fn,...)
  if not ok then return nil,text(a) end
  return a,b and text(b) or nil
end
local function product(v)
  if type(v)~="table" or type(v.name)~="string" or #v.name==0 or #v.name>160 or v.identityComplete==false then return end
  if not integer(v.damage or 0,0,2147483647) then return end
  local tag=type(v.tag)=="string" and v.tag or type(v.nbt_hash)=="string" and v.nbt_hash or ""
  if #tag>512 or v.hasTag==true and tag=="" then return end
  return {name=v.name,damage=v.damage or 0,hasTag=v.hasTag==true,tag=tag,identityComplete=true}
end
local function valid(j)
  if type(j)~="table" or j.schema~=1 or type(j.high)~="table" or type(j.orders)~="table" or #j.orders>32 then return false end
  local n=0
  for owner,seq in pairs(j.high) do
    n=n+1
    if type(owner)~="string" or #owner>64 or not integer(seq,1,2147483647) or n>16 then return false end
  end
  for _,r in ipairs(j.orders) do
    if type(r)~="table" or type(r.owner)~="string" or not integer(r.sequence,1,j.high[r.owner] or 0) or
      type(r.token)~="string" or not product(r.product) or not integer(r.amount,1,1000000) or
      type(r.cpu)~="string" or type(r.label)~="string" or not (active[r.state] or terminal[r.state]) then return false end
    if r.ruleId~=nil and not integer(r.ruleId,1,2147483647) then return false end
  end
  if j.automation~=nil and not require("server.stock").valid(j.automation,product) then return false end
  return true
end
function M.new(ae,clock,log,path)
  path=path or M.path; log=log or function() end
  local self={journal={schema=1,high={},orders={}},quotes={},handles={},lastTick=-math.huge}
  if fs.exists(path) then
    local j=storage.load(path)
    if valid(j) then
      self.journal=j
      for _,r in ipairs(j.orders) do
        if active[r.state] then r.state="unknown"; r.error="Sunucu yeniden basladi; ME Terminal'den kontrol edin. Emir tekrar gonderilmedi." end
      end
    else self.blocked="Uretim kaydi bozuk; yeni emirler durduruldu" end
  elseif fs.exists(path..".bak") or fs.exists(path..".tmp") then
    self.blocked="Uretim kaydi eksik; eski kayitla emir tekrari engellendi"
  end
  local function save()
    if self.blocked then return nil,self.blocked end
    local ok,a,b=pcall(storage.save,path,self.journal)
    if not ok or not a then
      self.blocked="Uretim kaydi yazilamadi: "..text(ok and b or a)
      log("ERROR",self.blocked); return nil,self.blocked
    end
    return true
  end
  local function public(r)
    local code,message=errors.explain(r.error)
    return {id=r.owner..":"..r.sequence,label=r.label,amount=r.amount,cpu=r.cpu,state=r.state,error=r.error or "",errorCode=code,errorMessage=message,owner=r.owner,automatic=r.ruleId~=nil,ruleId=r.ruleId}
  end
  local function observe(r,handle)
    local done,de=call(handle,"isDone"); local canceled,ce=call(handle,"isCanceled")
    local state,err
    if done==true then state="done"
    elseif canceled==true then state="canceled"
    elseif de=="computing" or ce=="computing" then state="computing"
    elseif done==false and canceled==false and not de and not ce then state=r.state=="cancel_requested" and "cancel_requested" or "running"
    elseif done==false and de or canceled==false and ce then state="failed"; err=de or ce
    else state="unknown"; err=de or ce or "Is durumu okunamadi" end
    local changed=r.state~=state or r.error~=(err or "")
    r.state=state; r.error=text(err)
    if terminal[state] then self.handles[r]=nil end
    return changed
  end
  self.save=save
  local function find(owner,sequence)
    for _,r in ipairs(self.journal.orders) do if r.owner==owner and r.sequence==sequence then return r end end
  end
  function self:busy()
    for _,r in ipairs(self.journal.orders) do if active[r.state] then return true end end
    return self.blocked~=nil
  end
  function self:resolve(item)
    local wanted=product(item)
    if not wanted then return nil,"Urunun NBT/varyant kimligi belirsiz" end
    if not ae.online then return nil,"AE2 baglantisi yok" end
    local p,why=ae:discover(); if not p then return nil,why end
    local list,err=call(p,"getCraftables",{name=wanted.name,damage=wanted.damage})
    if type(list)~="table" then return nil,err or "Tarif okunamadi" end
    if #list>64 then return nil,"Bu urun icin 64'ten fazla tarif varyanti var; secim dogrulanamadi" end
    local match,label
    for _,craft in ipairs(list) do
      local stack,why=call(craft,"getItemStack")
      if type(stack)~="table" then return nil,"Tarif kimligi okunamadi: "..(why or "gecersiz urun") end
      local exact=product(stack)
      if exact and identity.key(exact)==identity.key(wanted) then
        if match then return nil,"Ayni varyant icin birden fazla tarif var" end
        match=craft; label=text(stack.label or stack.name):sub(1,160)
      end
    end
    if not match then return nil,"Bu urun/varyant icin tarif bulunamadi" end
    return match,nil,p,wanted,label
  end
  function self:cpus(p)
    local cpus,err=call(p,"getCpus")
    if type(cpus)~="table" then return nil,err or "CPU listesi okunamadi" end
    local out={}
    for i=1,math.min(32,#cpus) do
      local c=cpus[i]
      if type(c)=="table" then
        local name=text(c.name):sub(1,160)
        out[#out+1]={name=name,selectable=type(c.name)=="string" and c.name~="" and name==c.name,
          busy=c.busy==true,storage=tonumber(c.storage) or 0}
      end
    end
    return out
  end
  function self:options(owner,args)
    if self.blocked then return nil,self.blocked end
    local craft,err,p,item,label=self:resolve(args.item)
    if not craft then return nil,err end
    local cpus,why=self:cpus(p); if not cpus then return nil,why end
    local q={token=uuid.next(),sequence=(self.journal.high[owner] or 0)+1,item=item,label=label,address=p.address,at=clock()}
    if q.sequence>2147483647 then return nil,"Emir numarasi sinirina ulasildi" end
    self.quotes[owner]=q
    return {token=q.token,sequence=q.sequence,label=label,cpus=cpus,maxAmount=1000000}
  end
  function self:start(owner,args)
    if not integer(args.sequence,1,2147483647) or type(args.token)~="string" or #args.token>64 or
      not integer(args.amount,1,1000000) or type(args.cpu or "")~="string" or #(args.cpu or "")>160 then return nil,"Gecersiz uretim emri" end
    local cpu=args.cpu or ""
    local old=find(owner,args.sequence)
    if old then
      if old.token~=args.token or old.amount~=args.amount or old.cpu~=cpu then return nil,"Emir kimligi baska bir istekte kullanilmis" end
      return public(old)
    end
    if args.sequence<=(self.journal.high[owner] or 0) then return nil,"Bu emir daha once islendi; tekrar gonderilmedi" end
    if self.blocked then return nil,self.blocked end
    local q=self.quotes[owner]
    if not q or q.token~=args.token or q.sequence~=args.sequence or clock()-q.at>60 then return nil,"Uretim secimi eskidi; pencereyi yeniden acin" end
    local live=0; for _,r in ipairs(self.journal.orders) do if active[r.state] then live=live+1 end end
    if live>=8 then return nil,"En fazla 8 aktif/belirsiz emir izlenebilir" end
    local owners=0; for _ in pairs(self.journal.high) do owners=owners+1 end
    if not self.journal.high[owner] and owners>=16 then return nil,"Emir sahibi kaydi siniri dolu" end
    local craft,err,p,item,label=self:resolve(q.item)
    if not craft then return nil,err end
    if p.address~=q.address then return nil,"AE2 bileseni degisti; urunu yeniden secin" end
    local cpus,why=self:cpus(p); if not cpus then return nil,why end
    local available=false; local named=0
    for _,c in ipairs(cpus) do
      if cpu=="" and not c.busy then available=true end
      if cpu~="" and c.name==cpu then named=named+1; available=not c.busy and c.selectable end
    end
    if cpu~="" and named~=1 then return nil,"CPU adi benzersiz degil veya CPU bulunamadi" end
    if not available then return nil,"Uygun bos crafting CPU yok" end
    if #self.journal.orders>=32 then
      local removed=false
      for i=#self.journal.orders,1,-1 do
        if terminal[self.journal.orders[i].state] then table.remove(self.journal.orders,i); removed=true; break end
      end
      if not removed then return nil,"Uretim gecmisi dolu" end
    end
    local r={owner=owner,sequence=args.sequence,token=args.token,product=item,label=label,amount=args.amount,cpu=cpu,state="submitting",error="",ruleId=q.ruleId}
    self.journal.high[owner]=args.sequence; table.insert(self.journal.orders,1,r)
    -- Durable high-water mark BEFORE the only side-effecting AE2 call.
    local written,reason=save()
    if not written then
      r.state="failed"; r.error="Emir diske kaydedilemedi; AE2 uretim cagrisi yapilmadi. "..text(reason)
      self.quotes[owner]=nil
      return nil,reason
    end
    self.quotes[owner]=nil
    local handle,failure
    if cpu=="" then handle,failure=call(craft,"request",r.amount,true)
    else handle,failure=call(craft,"request",r.amount,true,cpu) end
    if (type(handle)=="table" or type(handle)=="userdata") and handle.isDone~=nil and handle.isCanceled~=nil then
      self.handles[r]=handle; r.state="computing"
      observe(r,handle)
    else r.state="unknown"; r.error=text(failure or "Emir sonucu alinamadi; ME Terminal'den kontrol edin") end
    save(); log("INFO","Craft "..r.owner..":"..r.sequence.." "..r.label.." x"..r.amount.." "..r.state)
    return public(r)
  end
  function self:tick()
    if clock()-self.lastTick<2 then return end
    self.lastTick=clock()
    for owner,q in pairs(self.quotes) do if clock()-q.at>60 then self.quotes[owner]=nil end end
    local changed=false
    for r,handle in pairs(self.handles) do
      if observe(r,handle) then
        changed=true
        log((r.state=="failed" or r.state=="unknown") and "WARN" or "INFO","Craft "..r.owner..":"..r.sequence.." "..r.state..(r.error~="" and (": "..r.error) or ""))
      end
    end
    if changed then save() end
  end
  function self:cancel(owner,args)
    local r
    for _,record in ipairs(self.journal.orders) do if record.owner==owner and record.owner..":"..record.sequence==args.id then r=record; break end end
    if not r then return nil,"Emir bulunamadi veya bu ekrana ait degil" end
    if terminal[r.state] or r.state=="cancel_requested" then return public(r) end
    local handle=self.handles[r]; if not handle then return nil,"Is baglantisi kayip; ME Terminal'den iptal edin" end
    local ok,why=call(handle,"cancel")
    if ok~=true then return nil,why=="computing" and "Hesaplama suruyor; biraz sonra iptal edin" or why or "Is henuz iptal edilemiyor" end
    r.state="cancel_requested"; r.error=""; save()
    return public(r)
  end
  function self:archive(owner,args)
    for _,r in ipairs(self.journal.orders) do
      if r.owner==owner and r.owner..":"..r.sequence==args.id then
        if r.state=="reviewed" then return public(r) end
        if r.state~="unknown" then return nil,"Yalnizca durumu bilinmeyen emir elle arsivlenebilir" end
        self.handles[r]=nil; r.state="reviewed"; r.error="Kullanici ME Terminal kontrolunden sonra izlemeyi arsivledi; AE2'ye iptal veya uretim emri verilmedi."
        local ok,err=save(); if not ok then return nil,err end
        return public(r)
      end
    end
    return nil,"Emir bulunamadi veya bu ekrana ait degil"
  end
  function self:jobs()
    local out={}; for _,r in ipairs(self.journal.orders) do out[#out+1]=public(r) end
    return {cpus=ae.cpus,trackedJobs=out,existingJobDetails="factoryos_orders_only",error=ae.cpuError or "",
      craftingEnabled=not self.blocked,craftingError=self.blocked or ""}
  end
  return self
end
return M
