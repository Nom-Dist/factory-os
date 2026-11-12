local preferences=require("client.preferences")
local items=require("core.items")
local M={}
function M.new(net,clock)
  local prefs,warning=preferences.load()
  local self={tab=1,page=1,rowOffset=0,visibleRows=24,query="",draft="",editing=false,
    filter="all",sort="name",lastStockPoll=-math.huge,lastJobsPoll=-math.huge,
    favorites=prefs.favorites,wasOnline=false}
  function self:notice(text,kind) self.message={text=text,kind=kind or "info",at=clock()} end
  if warning then self:notice(warning,"warn") end
  function self:isFavorite(item) local key=items.key(item); return key and self.favorites[key]~=nil or false end
  function self:clearStocks()
    self.stockToken={}; self.stocks=nil; self.stockReceivedAt=nil; self.selected=nil; self.loadingStocks=false
  end
  function self:refreshStocks(force)
    if not net.online or self.tab~=2 or (self.loadingStocks and not force) then return end
    self.lastStockPoll=clock()
    local token={}; self.stockToken=token; self.loadingStocks=true; self.stockError=nil
    local keys={}; for key in pairs(self.favorites) do keys[#keys+1]=key end; table.sort(keys)
    local args={page=self.page,query=self.query,sort=self.sort,filter=self.filter}
    if self.filter=="favorites" then args.favoriteKeys=keys end
    local id,reason=net:request("GET_AE2_STOCKS",args,function(data,err)
      if token~=self.stockToken then return end
      self.loadingStocks=false
      if data and ((self.filter~="all" and data.filter~=self.filter) or (self.sort~="name" and data.sort~=self.sort)) then
        data=nil; err="Bu gorunum icin sunucuyu guncelleyin"
      end
      self.stockError=err; self.stocks=data
      if data then
        self.page=data.page; self.stockReceivedAt=clock()
        local count=#(data.items or {})
        if self.rowOffset<0 then self.rowOffset=math.floor(math.max(0,count-1)/self.visibleRows)*self.visibleRows end
        if self.rowOffset>=count then self.rowOffset=0 end
        local selected=items.key(self.selected)
        self.selected=nil
        if selected then for _,item in ipairs(data.items or {}) do if items.key(item)==selected then self.selected=item; break end end end
      else self.stockReceivedAt=nil; self.selected=nil end
    end)
    if not id then self.loadingStocks=false; self.stockError=reason end
  end
  function self:refreshJobs()
    if not net.online or self.loadingJobs then return end
    self.lastJobsPoll=clock(); self.loadingJobs=true
    local token={}; self.jobToken=token
    local id,reason=net:request("GET_CRAFTING_JOBS",{},function(data,err)
      if token~=self.jobToken then return end
      self.loadingJobs=false; self.jobs=data; self.jobsError=err
      if data then self.jobsReceivedAt=clock() else self.jobsReceivedAt=nil end
      if self.syncCraft then self:syncCraft() end
    end)
    if not id then self.loadingJobs=false; self.jobsError=reason end
  end
  function self:refresh(force)
    self:refreshJobs(); self:refreshStocks(force)
    if self.tab==3 then self:refreshRules() end
  end
  function self:beginSearch() self.draft=self.query; self.editing=true end
  function self:applySearch()
    self.query=self.draft; self.editing=false; self.page=1; self.rowOffset=0
    self:clearStocks(); self:refreshStocks(true)
  end
  function self:edit(action)
    if action=="apply" then self:applySearch()
    elseif action=="cancel" then self.editing=false; self.draft=self.query
    elseif action=="back" then self.draft=self.draft:sub(1,-2)
    elseif action=="clear" then self.draft=""
    elseif action=="space" then if #self.draft<80 then self.draft=self.draft.." " end
    elseif #action==1 and #self.draft<80 then self.draft=self.draft..action end
  end
  function self:paste(text)
    if self.ruleEditor then
      if type(text)=="string" and not self.ruleEditor.submitted then
        text=text:match("^%s*(.-)%s*$")
        if text:match("^%d+$") then for i=1,#text do self:ruleEdit(text:sub(i,i)) end end
      end
      return
    end
    if self.craft then
      if not self.craft.submitted and type(text)=="string" then
        text=text:match("^%s*(.-)%s*$")
        if text:match("^%d+$") then self.craft.amount=(self.craft.amount..text):sub(1,7)
        else self.craft.error="Miktar alanina yalnizca rakam girin" end
      end
      return
    end
    if not self.editing or type(text)~="string" then return end
    self.draft=(self.draft..text:gsub("[^ -~]","")):sub(1,80)
  end
  function self:key(char,code)
    if self.ruleEditor then
      if code==28 or code==156 then self:ruleEdit("save")
      elseif code==1 then self:ruleEdit("close")
      elseif code==15 then self:ruleEdit(self.ruleEditor.field=="minimum" and "target" or "minimum")
      elseif code==14 then self:ruleEdit("back")
      elseif type(char)=="number" and char>=48 and char<=57 then self:ruleEdit(string.char(char)) end
      return
    end
    if self.craft then
      if code==28 or code==156 then self:craftTouch("submit")
      elseif code==1 then self:craftTouch("close")
      elseif code==14 then self:craftTouch("back")
      elseif type(char)=="number" and char>=48 and char<=57 then self:craftTouch(string.char(char)) end
      return
    end
    if not self.editing then return end
    if code==28 or code==156 then self:edit("apply")
    elseif code==1 then self:edit("cancel")
    elseif code==14 then self:edit("back")
    elseif type(char)=="number" and char>=32 and char<=126 then self:edit(string.char(char)) end
  end
  function self:toggleFavorite(item)
    local key=items.key(item)
    if not key then self:notice("NBT kimligi belirsiz; favori kaydedilemiyor","warn"); return end
    local previous=self.favorites[key]
    if previous then self.favorites[key]=nil
    else
      local count=0; for _ in pairs(self.favorites) do count=count+1 end
      if count>=32 then self:notice("En fazla 32 favori kaydedilebilir","warn"); return end
      self.favorites[key]=tostring(item.label or item.name):sub(1,160)
    end
    local ok,saved=pcall(preferences.save,{schema=1,favorites=self.favorites})
    if not ok or not saved then self.favorites[key]=previous; self:notice("Favoriler diske kaydedilemedi","warn"); return end
    self:notice(previous and "Urun favorilerden kaldirildi" or "Urun favorilere eklendi")
    if self.filter=="favorites" then self:clearStocks(); self:refreshStocks(true) end
  end
  function self:touch(id)
    if not id then return end
    if self.ruleEditor then local action=id:match("^ruleedit:(.+)$"); if action then self:ruleEdit(action) end; return end
    if self.craft then local action=id:match("^craft:(.+)$"); if action then self:craftTouch(action) end; return end
    local ruleAction=id:match("^rule:(.+)$")
    if ruleAction then self:ruleTouch(ruleAction); return end
    if id=="craft:open" then self:beginCraft(); return end
    local detail=id:match("^craftdetail:(.+)$")
    if detail then self:craftDetails(detail); return end
    local cancel=id:match("^cancelcraft:(.+)$")
    if cancel then self:cancelCraft(cancel); return end
    local archive=id:match("^archivecraft:(.+)$")
    if archive then self:cancelCraft(archive,true); return end
    if id=="jobsprev" or id=="jobsnext" then self.jobsPage=math.max(1,(self.jobsPage or 1)+(id=="jobsnext" and 1 or -1)); return end
    local key=id:match("^key:(.+)$")
    if self.editing then if key then self:edit(key) end; return end
    local tab=id:match("^tab:(%d)$")
    if tab or id=="tabprev" or id=="tabnext" then
      local nextTab=tab and tonumber(tab) or id=="tabnext" and self.tab%9+1 or (self.tab+7)%9+1
      if nextTab<1 or nextTab>9 then return end
      local changed=nextTab~=self.tab; self.tab=nextTab
      if changed and nextTab==2 then self:clearStocks(); self:refreshStocks(true) end
      if nextTab==3 then self:refreshRules() end
      self:refreshJobs(); return
    end
    if id=="refresh" then self:refresh(true); self:notice("Veriler yenileniyor"); return end
    if id=="search" then self:beginSearch(); return end
    if id=="clear" then self.draft=""; self:applySearch(); return end
    local filter=id:match("^filter:(.+)$")
    if filter and (filter=="all" or filter=="craftable" or filter=="favorites") then
      self.filter=filter; self.page=1; self.rowOffset=0; self:clearStocks(); self:refreshStocks(true); return
    end
    if id=="sort" then
      self.sort=self.sort=="name" and "amount" or "name"
      self.page=1; self.rowOffset=0; self:clearStocks(); self:refreshStocks(true); return
    end
    local row=tonumber(id:match("^item:(%d+)$"))
    if row then self.selected=(self.stocks or {}).items and self.stocks.items[row]; return end
    local favorite=tonumber(id:match("^favorite:(%d+)$"))
    if favorite then local item=((self.stocks or {}).items or {})[favorite]; if item then self:toggleFavorite(item) end; return end
    if id=="favorite:selected" and self.selected then self:toggleFavorite(self.selected); return end
    if id=="prev" or id=="next" then
      if self.loadingStocks or not self.stocks then return end
      local count=#(self.stocks.items or {})
      if id=="next" then
        if self.rowOffset+self.visibleRows<count then self.rowOffset=self.rowOffset+self.visibleRows
        elseif self.page<self.stocks.pages then self.page=self.page+1; self.rowOffset=0; self:clearStocks(); self:refreshStocks(true) end
      elseif self.rowOffset>0 then self.rowOffset=math.max(0,self.rowOffset-self.visibleRows)
      elseif self.page>1 then self.page=self.page-1; self.rowOffset=-1; self:clearStocks(); self:refreshStocks(true) end
      self.selected=nil
    end
  end
  function self:tick()
    if not net.online then
      self:craftDisconnected()
      if self.wasOnline then
        self:clearStocks(); self.jobToken={}; self.jobs=nil; self.jobsReceivedAt=nil; self.loadingJobs=false
        self.ruleToken={}; self.rules=nil; self.loadingRules=false
      end
      self.wasOnline=false; return
    end
    if not self.wasOnline then self.wasOnline=true; self:refresh(true) end
    if clock()-self.lastJobsPoll>=((self.tab==4 or self.craft and self.craft.pending) and 2 or 10) then self:refreshJobs() end
    if self.tab==2 and clock()-self.lastStockPoll>=10 then self:refreshStocks(false) end
    if self.tab==3 and clock()-self.lastRulePoll>=5 then self:refreshRules() end
  end
  require("client.crafting").attach(self,net)
  require("client.stock").attach(self,net,clock)
  return self
end
return M
