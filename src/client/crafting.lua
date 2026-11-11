local identity=require("core.items")
local M={}
function M.attach(self,net)
  function self:beginCraft()
    local item=self.selected
    if not net.online or not ((net.status or {}).ae2 or {}).online or not item or not item.isCraftable or not identity.key(item) then
      self:notice("Tarifli ve kimligi belirli bir urun secin","warn"); return
    end
    local c={label=item.label,variant=" / Meta: "..tostring(item.damage or 0)..(item.hasTag and " / NBT" or ""),amount="1",cpu="",loading=true}; self.craft=c
    local id,why=net:request("GET_CRAFT_OPTIONS",{item={name=item.name,damage=item.damage,hasTag=item.hasTag,tag=item.tag,identityComplete=item.identityComplete}},function(data,err)
      if self.craft~=c then return end
      c.loading=false; c.preview=data; c.error=err
      if data then
        c.label=data.label; c.cpus={""}; local names={}
        for _,cpu in ipairs(data.cpus or {}) do
          if cpu.name~="" then names[cpu.name]=(names[cpu.name] or 0)+1 end
        end
        for _,cpu in ipairs(data.cpus or {}) do if cpu.name~="" and cpu.selectable~=false and not cpu.busy and names[cpu.name]==1 then c.cpus[#c.cpus+1]=cpu.name end end
      end
    end)
    if not id then c.loading=false; c.error=why end
  end
  function self:craftTouch(action)
    local c=self.craft; if not c then return end
    if action=="close" or action=="jobs" then
      if c.submitting then return end
      self.craft=nil
      if action=="jobs" then self.tab=4; self:refreshJobs() end
      return
    end
    if c.submitted then return end
    if action=="submit" then
      local n=tonumber(c.amount)
      if c.loading or not c.preview or not n or n%1~=0 or n<1 or n>1000000 then c.error="Miktar 1..1000000 arasi tam sayi olmali"; return end
      c.submitted=true; c.submitting=true; c.error=nil
      local id,why=net:request("START_CRAFT",{token=c.preview.token,sequence=c.preview.sequence,amount=n,cpu=c.cpu},function(data,err)
        if self.craft~=c then return end
        c.submitting=false
        if data then
          self.craft=nil; self.tab=4; self:notice("Emir kaydedildi: "..c.label.." x"..n); self:refreshJobs()
        else
          c.error=err or "Emir sonucu alinamadi"
          if err=="TIMEOUT" or err=="OFFLINE" or err=="INTERNAL_ERROR" then
            c.uncertain=true; c.error="Yanit yok. Emir tekrar gonderilmedi; isleri kontrol edin."
          else c.submitted=false end
        end
      end)
      if not id then c.submitting=false; c.submitted=false; c.error=why end
      return
    end
    if action=="back" then c.amount=c.amount:sub(1,-2)
    elseif action=="clear" then c.amount=""
    elseif action=="cpu" and c.cpus then
      local index=1; for i,name in ipairs(c.cpus) do if name==c.cpu then index=i; break end end
      c.cpu=c.cpus[index%#c.cpus+1]
    elseif action:match("^preset:%d+$") then c.amount=action:sub(8)
    elseif action:match("^%d$") and #c.amount<7 then c.amount=(c.amount=="0" and "" or c.amount)..action end
  end
  function self:cancelCraft(id,archive)
    self.canceling=self.canceling or {}
    if self.canceling[id] then return end
    self.canceling[id]=true
    local sent,why=net:request(archive and "ARCHIVE_CRAFT" or "CANCEL_CRAFT",{id=id},function(data,err)
      self.canceling[id]=nil
      self:notice(data and (archive and "Izleme arsivlendi; AE2 isi degistirilmedi" or "Iptal durumu yenileniyor") or (err or "Islem tamamlanamadi"),data and "info" or "warn")
      self:refreshJobs()
    end)
    if not sent then self.canceling[id]=nil; self:notice(why,"warn") end
  end
end
return M
