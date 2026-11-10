local component=require("component")
local M={}
local types={me_controller=true,me_interface=true,me_importbus=true,me_exportbus=true}
local function safe(p,method,...)
  if not p or type(p[method])~="function" then return nil,"unsupported: "..method end
  local ok,value=pcall(p[method],...)
  if not ok then return nil,tostring(value) end
  if value==nil then return nil,"no value from "..method end
  return value
end
local function text(s,n) return tostring(s or ""):gsub("[%c]"," "):sub(1,n or 160) end
function M.new(cfg)
  local self={items={},cpus={},online=false,error="AE2 not polled",energy={supported=false,unit="AE"},revision=0}
  function self:discover()
    local found={}
    for address,kind in component.list() do
      if types[kind] and (cfg.ae2Address=="" or cfg.ae2Address==address) then found[#found+1]=address end
    end
    if #found==0 then return nil,"AE2 Adapter component missing/offline" end
    if #found>1 then return nil,"Multiple AE2 components; set ae2Address" end
    return component.proxy(found[1])
  end
  function self:poll()
    if not cfg.ae2Enabled then self.online=false; self.error="AE2 disabled"; return end
    local p,err=self:discover()
    if not p then self.online=false; self.error=err; self.items={}; self.cpus={}; self.energy={supported=false,unit="AE"}; return end
    local items,why=safe(p,"getItemsInNetwork")
    if type(items)~="table" then
      self.online=false; self.error=why or "Invalid AE2 inventory"; self.items={}; self.cpus={}; self.energy={supported=false,unit="AE"}; return
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
    local capacity=safe(p,"getMaxStoredPower")
    self.energy={supported=type(stored)=="number" and type(capacity)=="number",unit="AE",error=se or ""}
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
    local matched={}
    for _,item in ipairs(self.items) do
      if query=="" or item.label:lower():find(query,1,true) or item.name:lower():find(query,1,true) then matched[#matched+1]=item end
    end
    local rows={}
    for i=(page-1)*24+1,math.min(page*24,#matched) do rows[#rows+1]=matched[i] end
    return {items=rows,page=page,total=#matched,pages=math.max(1,math.ceil(#matched/24)),revision=self.revision,truncated=self.truncated}
  end
  function self:jobs()
    -- getCpus exposes occupancy, not existing jobs or item quantities.
    return {cpus=self.cpus,trackedJobs={},existingJobDetails="unsupported",error=self.cpuError or ""}
  end
  function self:summary() return {online=self.online,error=self.error,itemTypes=#self.items,address=self.address or "",revision=self.revision,truncated=self.truncated==true} end
  return self
end
return M
