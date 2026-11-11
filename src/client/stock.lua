local M={}
function M.attach(self,net,clock)
  self.lastRulePoll=-math.huge; self.rulePage=1; self.ruleOffset=0
  function self:refreshRules()
    if not net.online or self.loadingRules or self.savingRule then return end
    self.loadingRules=true; self.lastRulePoll=clock()
    local token={}; self.ruleToken=token
    local sent,why=net:request("GET_STOCK_RULES",{page=self.rulePage},function(data,err)
      if self.ruleToken~=token then return end
      self.loadingRules=false; self.rules=data; self.rulesError=err
      if data then
        self.rulePage=data.page
        if self.ruleEditor and self.ruleEditor.revision==nil then self.ruleEditor.revision=data.revision end
      end
    end)
    if not sent then self.loadingRules=false; self.rulesError=why end
  end
  function self:changeRule(args,editor)
    if self.savingRule or not self.rules or not net.online then return end
    args.revision=args.revision or self.rules.revision; args.page=self.rulePage
    self.savingRule=true; self.ruleToken={}; self.loadingRules=false
    local sent,why=net:request("SET_STOCK_RULE",args,function(data,err)
      self.savingRule=false
      if data then
        self.rules=data; self.rulePage=data.page; self.ruleOffset=0; self.rulesError=nil
        if editor and self.ruleEditor==editor then self.ruleEditor=nil; self.tab=3 end
        self:notice(args.action=="save" and "Kural kaydedildi; listeden ACIK yapin" or "Stok kurallari guncellendi")
      else
        self.rules=nil; self.rulesError=err
        if editor then editor.error=err or "Yanit yok; listeyi yenileyin"; editor.submitted=true end
        self:notice(err or "Yanit yok; kurallari yenileyin","warn"); self:refreshRules()
      end
    end)
    if not sent then self.savingRule=false; if editor then editor.submitted=false; editor.error=why end; self:notice(why,"warn") end
  end
  function self:beginRule(rule)
    local item=rule and rule.item or self.selected
    if not item or not net.online then return end
    self.ruleEditor={id=rule and rule.id,item=item,label=rule and rule.label or item.label,
      minimum=tostring(rule and rule.minimum or 64),target=tostring(rule and rule.target or 256),field="minimum",
      revision=self.rules and self.rules.revision}
    self:refreshRules()
  end
  function self:ruleEdit(action)
    local c=self.ruleEditor; if not c then return end
    if action=="close" then if not self.savingRule then self.ruleEditor=nil end; return end
    if action=="refresh" then self:refreshRules(); return end
    if c.submitted or self.savingRule then return end
    if action=="delete" and c.id then self:changeRule({action="delete",id=c.id,revision=c.revision},c); return end
    if action=="save" then
      local minimum,target=tonumber(c.minimum),tonumber(c.target)
      if not minimum or not target or minimum%1~=0 or target%1~=0 or minimum<1 or target<minimum or target>1000000 then
        c.error="1 <= minimum <= hedef <= 1000000 olmali"; return
      end
      if not self.rules then c.error="Once kurallari yenileyin"; self:refreshRules(); return end
      c.submitted=true
      self:changeRule({action="save",id=c.id,item=c.item,minimum=minimum,target=target,revision=c.revision},c)
    elseif action=="minimum" or action=="target" then c.field=action
    elseif action=="back" then c[c.field]=c[c.field]:sub(1,-2)
    elseif action=="clear" then c[c.field]=""
    elseif action:match("^%d$") and #c[c.field]<7 then c[c.field]=c[c.field]..action end
  end
  function self:ruleTouch(action)
    if action=="open" then self:beginRule(); return end
    if action=="refresh" then self:refreshRules(); return end
    if action=="pause" and self.rules then self:changeRule({action="pause",paused=not self.rules.paused}); return end
    if action=="prev" or action=="next" then
      if not self.rules or self.loadingRules then return end
      local visible=self.ruleVisible or 4
      if action=="next" then
        if self.ruleOffset+visible<#self.rules.rules then self.ruleOffset=self.ruleOffset+visible
        elseif self.rulePage<self.rules.pages then self.rulePage=self.rulePage+1; self.ruleOffset=0; self:refreshRules() end
      elseif self.ruleOffset>0 then self.ruleOffset=math.max(0,self.ruleOffset-visible)
      elseif self.rulePage>1 then self.rulePage=self.rulePage-1; self.ruleOffset=0; self:refreshRules() end
      return
    end
    local verb,index=action:match("^(%a+):(%d+)$")
    local rule=((self.rules or {}).rules or {})[tonumber(index)]
    if not rule then return end
    if verb=="edit" then self:beginRule(rule)
    elseif verb=="enable" then self:changeRule({action="enable",id=rule.id,enabled=not rule.enabled})
    elseif verb=="delete" then self:changeRule({action="delete",id=rule.id}) end
  end
end
return M
