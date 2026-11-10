local M={}
function M.new(net,clock)
  local self={tab=1,page=1,rowOffset=0,query="",editing=false,lastPoll=-math.huge,error=nil}
  function self:refresh()
    self.lastPoll=clock()
    if not net.online then return end
    if self.tab==2 then
      local page,query=self.page,self.query
      net:request("GET_AE2_STOCKS",{page=page,query=query},function(data,err)
        if self.page~=page or self.query~=query then return end
        self.error=err
        self.stocks=data
      end)
    elseif self.tab==3 then
      net:request("GET_CRAFTING_JOBS",{},function(data,err) self.error=err; self.jobs=data end)
    end
  end
  function self:touch(id)
    local tab=id and id:match("^tab:(%d)$")
    if tab then self.tab=tonumber(tab); self.error=nil
    elseif id=="tabprev" then self.tab=(self.tab+5)%7+1
    elseif id=="tabnext" then self.tab=self.tab%7+1
    elseif id=="prev" then self.page=math.max(1,self.page-1); self.rowOffset=0
    elseif id=="next" then self.page=math.min((self.stocks or {}).pages or 1,self.page+1); self.rowOffset=0
    elseif id=="scroll" then
      local total=#((self.stocks or {}).items or {})
      self.rowOffset=(self.rowOffset+6>=total) and 0 or self.rowOffset+6
    elseif id=="search" then self.editing=not self.editing end
    if id then self:refresh() end
  end
  function self:key(char,code)
    if not self.editing then return end
    if code==28 then self.editing=false; self.page=1; self.rowOffset=0; self:refresh()
    elseif code==14 then self.query=self.query:sub(1,-2)
    elseif type(char)=="number" and char>=32 and char<=126 and #self.query<80 then self.query=self.query..string.char(char) end
  end
  function self:tick() if clock()-self.lastPoll>=10 then self:refresh() end end
  return self
end
return M
