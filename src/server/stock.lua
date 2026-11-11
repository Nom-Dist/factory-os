-- Stock rules share the crafting journal: the rule and its durable order can
-- never be restored independently. No second path calls native request().
local identity=require("core.items")
local M={owner="@factoryos-stock"}
local active={submitting=true,computing=true,running=true,cancel_requested=true,unknown=true}
local function integer(n,lo,hi) return type(n)=="number" and n==n and n%1==0 and n>=lo and n<=hi end
function M.valid(a,product)
  if type(a)~="table" or not integer(a.revision,0,2147483647) or not integer(a.nextId,1,2147483647) or
    type(a.paused)~="boolean" or type(a.rules)~="table" or #a.rules>16 then return false end
  local ids,keys={},{}
  for _,r in ipairs(a.rules) do
    if type(r)~="table" or not integer(r.id,1,a.nextId-1) or ids[r.id] or not product(r.item) or
      type(r.enabled)~="boolean" or not integer(r.minimum,1,1000000) or not integer(r.target,r.minimum,1000000) or
      type(r.address)~="string" or #r.address==0 or #r.address>64 or type(r.label)~="string" or #r.label>160 then return false end
    local key=identity.key(r.item); if keys[key] then return false end
    ids[r.id]=true; keys[key]=true
  end
  return true
end
function M.new(craft,ae,clock)
  craft.journal.automation=craft.journal.automation or {revision=0,nextId=1,paused=false,rules={}}
  local a=craft.journal.automation
  local self={runtime={},nextAttempt=clock()+30,cursor=0}
  local counts,countsRevision,countsRuleRevision={}
  local function runtime(r)
    self.runtime[r.id]=self.runtime[r.id] or {next=clock()+30,failures=0,state="BEKLIYOR"}
    return self.runtime[r.id]
  end
  local function find(id) for i,r in ipairs(a.rules) do if r.id==id then return r,i end end end
  local function persist()
    if a.revision>=2147483647 then craft.blocked="Stok kural surum siniri"; return nil,craft.blocked end
    a.revision=a.revision+1
    return craft.save()
  end
  local function inflight(r)
    local amount=0; local unknown=false; local key=identity.key(r.item)
    for _,job in ipairs(craft.journal.orders) do
      if active[job.state] and identity.key(job.product)==key then
        amount=amount+job.amount; unknown=unknown or job.state=="unknown"
      end
    end
    return amount,unknown
  end
  local function stock(r)
    if not ae.online or ae.address~=r.address or ae.truncated then return nil end
    if countsRevision~=ae.revision or countsRuleRevision~=a.revision then
      counts={}; local wanted,names={},{}
      for _,rule in ipairs(a.rules) do
        counts[rule.id]=0; wanted[identity.key(rule.item)]=rule.id
        names[rule.item.name]=names[rule.item.name] or {}; table.insert(names[rule.item.name],rule)
      end
      -- One pass per snapshot, retaining at most 16 counts. Never copy the
      -- inventory or encode all 2000 identities once for every single rule.
      for i,item in ipairs(ae.items or {}) do
        if names[item.name] then
          local key=identity.key(item); local id=key and wanted[key]
          if id then
            if type(item.size)~="number" or item.size<0 or item.size~=item.size or item.size==math.huge then counts[id]=false
            elseif counts[id]~=false then counts[id]=counts[id]+item.size end
          elseif not key then
            -- An ambiguous stack might be this exact variant; do not infer zero.
            for _,rule in ipairs(names[item.name]) do if item.damage==rule.item.damage then counts[rule.id]=false end end
          end
        end
        if i%200==0 and os.sleep then os.sleep(0) end
      end
      countsRevision=ae.revision; countsRuleRevision=a.revision
    end
    return counts[r.id]~=false and math.floor(counts[r.id] or 0) or nil
  end
  function self:enabled()
    if craft.blocked or a.paused then return false end
    for _,r in ipairs(a.rules) do if r.enabled then return true end end
    return false
  end
  function self:list(args)
    local page=args.page or 1
    if not integer(page,1,4) then return nil,"Gecersiz kural sayfasi" end
    local pages=math.max(1,math.ceil(#a.rules/4)); page=math.min(page,pages)
    local rows={}
    for i=(page-1)*4+1,math.min(page*4,#a.rules) do
      local r=a.rules[i]; local rt=runtime(r); local amount,unknown=inflight(r)
      rows[#rows+1]={id=r.id,item=r.item,label=r.label,minimum=r.minimum,target=r.target,enabled=r.enabled,
        stock=stock(r),inFlight=amount,state=craft.blocked and "KAYIT HATASI" or not r.enabled and "KAPALI" or
          unknown and "ME KONTROLU GEREKLI" or amount>0 and "URETIM BEKLENIYOR" or a.paused and "DURAKLATILDI" or rt.state,
        error=rt.error or "",retryIn=math.max(0,math.ceil(rt.next-clock()))}
    end
    return {rules=rows,page=page,pages=pages,total=#a.rules,revision=a.revision,paused=a.paused,error=craft.blocked or ""}
  end
  function self:change(args)
    if craft.blocked then return nil,craft.blocked end
    if args.page~=nil and not integer(args.page,1,4) then return nil,"Gecersiz kural sayfasi" end
    if args.revision~=a.revision then return nil,"Kurallar degisti; listeyi yenileyin" end
    local r,index=find(args.id)
    if args.action=="pause" then
      if type(args.paused)~="boolean" then return nil,"Gecersiz duraklatma" end
      a.paused=args.paused
    elseif args.action=="save" then
      if not integer(args.minimum,1,1000000) or not integer(args.target,args.minimum,1000000) then return nil,"1 <= minimum <= hedef <= 1000000 olmali" end
      if args.id~=nil and not r then return nil,"Kural bulunamadi" end
      local native,err,p,item,label=craft:resolve(r and r.item or args.item)
      if not native then return nil,err end
      if r and p.address~=r.address then return nil,"AE2 bileseni degisti; kurali yeniden olusturun" end
      for _,other in ipairs(a.rules) do
        if other~=r and identity.key(other.item)==identity.key(item) then return nil,"Bu varyantin zaten stok kurali var" end
      end
      if not r then
        if #a.rules>=16 or a.nextId>=2147483647 then return nil,"En fazla 16 stok kurali" end
        r={id=a.nextId,item=item,label=label,address=p.address}; a.nextId=a.nextId+1; a.rules[#a.rules+1]=r
      end
      -- Editing always disarms the rule; enabling is a separate deliberate action.
      r.minimum=args.minimum; r.target=args.target; r.enabled=false; self.runtime[r.id]=nil
    elseif args.action=="enable" then
      if not r or type(args.enabled)~="boolean" then return nil,"Kural bulunamadi" end
      r.enabled=args.enabled; self.runtime[r.id]=nil
    elseif args.action=="delete" then
      if not r then return nil,"Kural bulunamadi" end
      if inflight(r)>0 then return nil,"Once urunun aktif/belirsiz isini kontrol edin" end
      table.remove(a.rules,index); self.runtime[r.id]=nil
    else return nil,"Gecersiz kural islemi" end
    local ok,err=persist(); if not ok then return nil,err end
    return self:list({page=args.page or 1})
  end
  function self:controlJob(client,args,archive)
    for _,job in ipairs(craft.journal.orders) do
      if job.owner==M.owner and job.ruleId and job.owner..":"..job.sequence==args.id then
        if archive and job.state~="unknown" then return craft:archive(M.owner,args) end
        local r=find(job.ruleId)
        -- Persistently disarm before cancel/archive, including computing errors.
        if r and r.enabled and active[job.state] then r.enabled=false; local ok,err=persist(); if not ok then return nil,err end end
        if archive then return craft:archive(M.owner,args) end
        return craft:cancel(M.owner,args)
      end
    end
    if archive then return craft:archive(client,args) end
    return craft:cancel(client,args)
  end
  local function defer(rt,error)
    rt.failures=math.min(5,rt.failures+1); rt.next=clock()+math.min(900,60*2^(rt.failures-1))
    rt.state="TEKRAR BEKLENIYOR"; rt.error=error
  end
  function self:tick(updating)
    -- Consume terminal results even while globally paused. A completed order
    -- needs a subsequent inventory revision before another stock decision.
    for _,r in ipairs(a.rules) do
      local rt=runtime(r)
      if rt.order then
        for _,job in ipairs(craft.journal.orders) do
          if job.owner==M.owner and job.sequence==rt.order and not active[job.state] then
            rt.order=nil; rt.afterRevision=ae.revision
            if job.state=="failed" then defer(rt,job.error)
            else rt.next=clock()+30; rt.state="STOK YENILEME BEKLENIYOR"; rt.error=""; rt.failures=0 end
            break
          end
        end
      end
    end
    if not self:enabled() then return end
    local guard
    if updating then guard="GUNCELLEME BEKLENIYOR"
    elseif not ae.online then guard="AE2 BAGLANTISI YOK"
    elseif ae.cpuError and ae.cpuError~="" then guard="CPU BILGISI YOK"
    elseif craft:busy() then guard="AKTIF ISLER BEKLENIYOR"
    else for _,cpu in ipairs(ae.cpus or {}) do if cpu.busy then guard="CPU'LAR BEKLENIYOR"; break end end end
    if guard then for _,r in ipairs(a.rules) do if r.enabled then runtime(r).state=guard end end; return end
    if clock()<self.nextAttempt or #a.rules==0 then return end
    for step=1,#a.rules do
      local index=(self.cursor+step-1)%#a.rules+1; local r=a.rules[index]; local rt=runtime(r)
      if r.enabled then
        local count=stock(r)
        if count==nil then rt.state="STOK/AE2 KIMLIGI BELIRSIZ"
        elseif rt.afterRevision and (ae.revision or 0)<=rt.afterRevision then rt.state="TAZE STOK BEKLENIYOR"
        elseif clock()<rt.next then rt.state="TEKRAR BEKLENIYOR"
        elseif count>=r.minimum then rt.state="STOK YETERLI"; rt.error=""; rt.failures=0
        else
          self.cursor=index; self.nextAttempt=clock()+30
          local quote,err=craft:options(M.owner,{item=r.item})
          if quote then
            if craft.quotes[M.owner].address~=r.address then defer(rt,"AE2 bileseni degisti"); return end
            for _,cpu in ipairs(quote.cpus) do if cpu.busy then defer(rt,"CPU'lar mesgul; harici islerin urunu okunamiyor"); return end end
            craft.quotes[M.owner].ruleId=r.id
            local result,why=craft:start(M.owner,{sequence=quote.sequence,token=quote.token,amount=r.target-count,cpu=""})
            if result then rt.order=quote.sequence; rt.state="URETIM BEKLENIYOR"; rt.error=""
            else defer(rt,why) end
          else defer(rt,err) end
          return
        end
      end
    end
  end
  return self
end
return M
