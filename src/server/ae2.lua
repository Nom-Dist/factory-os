local component=require("component")
local identity=require("core.items")
local M={}
local types={me_controller=true,me_interface=true,me_importbus=true,me_exportbus=true}
local function safe(p,method,...)
  -- OC proxy callbacks are callable tables, not necessarily Lua functions.
  if not p or p[method]==nil then return nil,"unsupported: "..method end
  local ok,value,reason=pcall(p[method],...)
  if not ok then return nil,method..": "..tostring(value) end
  if value==nil then return nil,method..": "..tostring(reason or "no value returned") end
  return value
end
local function text(s,n) return tostring(s or ""):gsub("[%c]"," "):sub(1,n or 160) end
function M.new(cfg)
  local self={items={},cpus={},online=false,error="AE2 not polled",energy={supported=false,unit="AE"},revision=0}
  function self:unavailable(reason)
    self.online=false; self.error=text(reason,400); self.items={}; self.cpus={}
    self.cpuError=self.error; self.truncated=false; self.energy={supported=false,unit="AE"}
  end
  function self:candidates()
    local found={}
    for address,kind in component.list() do
      if types[kind] then found[#found+1]={address=address,kind=kind} end
    end
    table.sort(found,function(a,b) return a.address<b.address end)
    return found
  end
  function self:discover()
    self.address=nil
    local found={}
    for _,candidate in ipairs(self:candidates()) do
      if cfg.ae2Address=="" or cfg.ae2Address==candidate.address then found[#found+1]=candidate.address end
    end
    if #found==0 then return nil,"AE2 Adapter component missing/offline"..(cfg.ae2Address~="" and (": "..cfg.ae2Address) or "") end
    if #found>1 then return nil,"Multiple AE2 components; set ae2Address" end
    self.address=found[1]
    return component.proxy(found[1])
  end
  function self:poll()
    self.powered=nil; self.powerError=nil
    if not cfg.ae2Enabled then self.address=nil; self:unavailable("AE2 disabled"); return end
    local p,err=self:discover()
    if not p then self:unavailable(err); return end
    self.powered,self.powerError=safe(p,"isNetworkPowered")
    if self.powered==false then self:unavailable("AE2 network unpowered (isNetworkPowered=false)"); return end
    local items,why=safe(p,"getItemsInNetwork")
    if type(items)~="table" then
      self:unavailable(why or "getItemsInNetwork: invalid inventory result"); return
    end
    local normalized={}
    self.truncated=false
    for _,v in ipairs(items) do
      if type(v)=="table" and type(v.name)=="string" and type(v.size)=="number" then
        -- Keep variants separate. hasTag without an exposed tag/hash is explicitly ambiguous.
        local tag=type(v.tag)=="string" and v.tag or type(v.nbt_hash)=="string" and v.nbt_hash or nil
        normalized[#normalized+1]={name=text(v.name,160),label=text(v.label or v.name,160),damage=tonumber(v.damage) or 0,
          size=v.size,hasTag=v.hasTag==true,tag=text(tag or "",512),isCraftable=v.isCraftable==true,
          identityComplete=v.hasTag~=true or tag~=nil}
        if #normalized>=2000 then self.truncated=#items>2000; break end
      end
      if #normalized%200==0 and #normalized>0 and os.sleep then os.sleep(0) end
    end
    table.sort(normalized,function(a,b) if a.label==b.label then return a.name..":"..a.damage..a.tag<b.name..":"..b.damage..b.tag end; return a.label<b.label end)
    self.items=normalized; self.address=p.address; self.online=true; self.error=""; self.revision=self.revision+1
    local cpus,ce=safe(p,"getCpus")
    self.cpus={}; self.cpuError=ce
    if type(cpus)=="table" then
      for _,c in ipairs(cpus) do
        if type(c)=="table" then self.cpus[#self.cpus+1]={name=text(c.name),busy=c.busy==true,storage=tonumber(c.storage) or 0,coprocessors=tonumber(c.coprocessors) or 0} end
      end
    end
    local stored,se=safe(p,"getStoredPower")
    local capacity,ce=safe(p,"getMaxStoredPower")
    self.energy={supported=type(stored)=="number" and type(capacity)=="number",unit="AE",error=se or ce or ""}
    if self.energy.supported then
      self.energy.stored=stored; self.energy.capacity=capacity
      self.energy.injection=safe(p,"getAvgPowerInjection")
      self.energy.usage=safe(p,"getAvgPowerUsage")
    end
  end
  function self:stocks(args)
    if not self.online then return nil,"AE2_OFFLINE: "..self.error end
    local page=tonumber(args.page) or 1
    if page%1~=0 or page<1 or page>100000 then return nil,"INVALID_PAGE" end
    local query=type(args.query)=="string" and args.query:lower():sub(1,80) or ""
    local filter=args.filter or "all"
    if filter~="all" and filter~="craftable" and filter~="favorites" then return nil,"INVALID_FILTER" end
    local sort=args.sort or "name"
    if sort~="name" and sort~="amount" then return nil,"INVALID_SORT" end
    local favorites={}
    if filter=="favorites" then
      if type(args.favoriteKeys)~="table" or #args.favoriteKeys>32 then return nil,"INVALID_FAVORITES" end
      for _,key in ipairs(args.favoriteKeys) do
        if type(key)~="string" or #key>1024 then return nil,"INVALID_FAVORITES" end
        favorites[key]=true
      end
    end
    local matched={}
    for _,item in ipairs(self.items) do
      local matches=query=="" or item.label:lower():find(query,1,true) or item.name:lower():find(query,1,true)
      if matches and (filter=="all" or filter=="craftable" and item.isCraftable or filter=="favorites" and favorites[identity.key(item) or false]) then matched[#matched+1]=item end
    end
    if sort=="amount" then
      table.sort(matched,function(a,b)
        if a.size~=b.size then return a.size>b.size end
        return a.label..a.name..a.damage..a.tag<b.label..b.name..b.damage..b.tag
      end)
    end
    local pages=math.max(1,math.ceil(#matched/24)); page=math.min(page,pages)
    local rows={}
    for i=(page-1)*24+1,math.min(page*24,#matched) do rows[#rows+1]=matched[i] end
    return {items=rows,page=page,total=#matched,allTotal=#self.items,pages=pages,revision=self.revision,truncated=self.truncated,sort=sort,filter=filter}
  end
  function self:jobs()
    -- getCpus exposes occupancy, not existing jobs or item quantities.
    return {cpus=self.cpus,trackedJobs={},existingJobDetails="unsupported",error=self.cpuError or ""}
  end
  function self:summary() return {online=self.online,error=self.error,itemTypes=#self.items,address=self.address or "",powered=self.powered,revision=self.revision,truncated=self.truncated==true} end
  return self
end
return M
