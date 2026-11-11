local C=require("ui.renderer").colors
local W=require("ui.widgets")
local F=require("ui.format")
local M={}
function M.draw(r,l,state)
  local data=state.rules; local tiny=l.bottom-l.y<9; local step=tiny and 3 or 5
  W.panel(r,l.x,l.y,l.w,l.bottom-l.y+1,"STOK HEDEFLERI")
  local top=l.y+(tiny and 1 or 4)
  local count=math.max(1,math.min(4,math.floor((l.bottom-top)/step)))
  state.ruleVisible=count
  local rows=data and data.rules or {}
  if (state.ruleOffset or 0)>=#rows then state.ruleOffset=0 end
  r:button(l.x+l.w-15,l.y,14,data and data.paused and "DEVAM ET" or "TUMUNU BEKLET","rule:pause",false,1,data~=nil and not state.savingRule)
  if not tiny then
    W.text(r,l.x+1,l.y+2,l.w-2,state.rulesError or (data and data.error~="" and data.error) or
      "Stok < minimum: hedefe tamamla. Yeni kural: depodan urun secin.",state.rulesError and C.warn or C.muted)
  end
  if #rows==0 then W.text(r,l.x+1,top,l.w-2,state.rulesError or "Depodan tarifli urun secip STOK HEDEFI'ne dokunun.",C.muted) end
  for i=1,count do
    local index=(state.ruleOffset or 0)+i; local rule=rows[index]; if not rule then break end
    local y=top+(i-1)*step
    W.text(r,l.x+1,y,l.w-10,rule.label,C.text)
    r:button(l.x+l.w-9,y,8,"DUZENLE","rule:edit:"..index)
    local details="Stok "..(rule.stock and F.integer(rule.stock) or "?").." / Min "..rule.minimum.." / Hedef "..rule.target
    W.text(r,l.x+1,y+1,l.w-2,tiny and (rule.state.." | "..(rule.stock and F.integer(rule.stock) or "?").."/"..rule.target) or details,C.accent)
    if not tiny then
      W.text(r,l.x+1,y+2,l.w-2,rule.state..((rule.inFlight or 0)>0 and " | Emir: "..rule.inFlight or "")..
        ((rule.retryIn or 0)>0 and " | Bekleme: "..rule.retryIn.." sn" or ""),rule.enabled and C.good or C.muted)
      W.text(r,l.x+1,y+3,l.w-23,rule.error or "",C.warn)
    end
    local controls=y+(tiny and 2 or 3)
    if controls<=l.bottom-1 then
      r:button(l.x+l.w-22,controls,12,rule.enabled and "ACIK: KAPAT" or "KAPALI: AC","rule:enable:"..index,rule.enabled,1,not state.savingRule)
      r:button(l.x+l.w-9,controls,8,"SIL","rule:delete:"..index,false,1,not state.savingRule and (rule.inFlight or 0)==0)
    end
  end
  -- Tiny screens reuse the last line for the selected rule's enable control.
  local y=l.bottom
  local rule=rows[(state.ruleOffset or 0)+1]
  if tiny and rule and top+2>l.bottom-1 then r:button(l.x,y,13,rule.enabled and "ACIK: KAPAT" or "KAPALI: AC","rule:enable:"..((state.ruleOffset or 0)+1),rule.enabled,1,not state.savingRule) end
  r:button(l.x+l.w-24,y,7,"< ONCE","rule:prev",false,1,data and (data.page>1 or (state.ruleOffset or 0)>0))
  r:button(l.x+l.w-16,y,8,"SONRA >","rule:next",false,1,data and (data.page<data.pages or (state.ruleOffset or 0)+count<#rows))
  r:button(l.x+l.w-7,y,7,"YENILE","rule:refresh")
end
function M.modal(r,state)
  local c=state.ruleEditor; if not c then return end
  r.buttons={}; r:fill(1,2,r.w,r.h-2,C.bg)
  local tall=r.h>=24; local width=math.min(76,r.w-2); local height=tall and 18 or 10; local step=tall and 2 or 1
  local x=math.floor((r.w-width)/2)+1; local y=math.max(2,math.floor((r.h-height)/2))
  W.panel(r,x,y,width,height,"OTOMATIK STOK / KURAL")
  W.text(r,x+1,y+1,width-2,c.label,C.text)
  local half=math.floor((width-3)/2)
  r:button(x+1,y+step+1,half,"MIN: "..c.minimum,"ruleedit:minimum",c.field=="minimum")
  r:button(x+2+half,y+step+1,half,"HEDEF: "..c.target,"ruleedit:target",c.field=="target")
  local digit=math.floor((width-2)/10)
  for i=1,10 do r:button(x+1+(i-1)*digit,y+step*2+1,digit-1,tostring(i%10),"ruleedit:"..i%10,false,1,not c.submitted) end
  r:button(x+1,y+step*3+1,half,"SIL","ruleedit:back",false,1,not c.submitted)
  r:button(x+2+half,y+step*3+1,half,"TEMIZLE","ruleedit:clear",false,1,not c.submitted)
  W.wrap(r,x+1,y+step*4+1,width-2,tall and 3 or 2,c.error or "Minimumun altinda hedefe tamamlar. Kayit sonrasi listeden ACIK yapin.",c.error and C.warn or C.muted)
  if c.id then r:button(x+1,y+(tall and 13 or 7),width-2,"KURALI SIL","ruleedit:delete",false,1,not c.submitted and not state.savingRule) end
  local actions=y+step*6+2
  r:button(x+1,actions,half,"KAPAT","ruleedit:close",false,tall and 2 or 1,not state.savingRule)
  r:button(x+2+half,actions,half,c.submitted and "YENILE" or "KAYDET",c.submitted and "ruleedit:refresh" or "ruleedit:save",true,tall and 2 or 1,not state.savingRule and state.rules~=nil)
end
return M
