local config=require("core.config")
local M={}
local fields={"webUrl","webToken","webEnabled","webControl","webInterval"}
function M.new(cfg,clock,apply,canApply)
  local self={editing=false,tokenConfigured=cfg.webToken~=""}
  function self:open()
    self.webMenu=true; self.editing=true; self.keyboard=false; self.shift=false; self.field="url"
    self.draft={url=cfg.webUrl,token="",control=cfg.webControl}; self.error=nil; self.message=nil
  end
  function self:close()
    self.webMenu=false; self.editing=false; self.keyboard=false; self.draft=nil; self.error=nil
  end
  function self:insert(text)
    if not self.webMenu or type(text)~="string" then return end
    local key=self.field=="token" and "token" or "url"
    if text:find("[^ -~]") or key=="token" and text:find("[^%w_%-]") then self.error="Gecersiz karakter; adres veya tokeni kontrol edin"; return end
    local limit=key=="token" and 128 or 512
    if #self.draft[key]+#text>limit then self.error="Alan uzunluk siniri asildi"; return end
    self.draft[key]=self.draft[key]..text; self.error=nil
  end
  function self:save(disconnect)
    local allowed,why=canApply(); if not allowed then self.error=why; return end
    local candidate={}; for k,v in pairs(cfg) do candidate[k]=v end
    if disconnect then candidate.webEnabled=false; candidate.webControl=false
    else
      local url=self.draft.url:match("^%s*(.-)%s*$"):gsub("/+$","")
      if url:match("^https://[%w%.%-]+:?%d*$") then url=url.."/bridge/ingest"
      elseif url:match("^ws://[%w%.%-]+:?%d*$") then url=url.."/bridge/device" end
      candidate.webUrl=url; candidate.webEnabled=true; candidate.webControl=self.draft.control
      if self.draft.token~="" then candidate.webToken=self.draft.token end
      if #candidate.webToken<32 then self.error="Baglanti tokeni en az 32 karakter olmali"; return end
    end
    local ok,err=config.validate(candidate); if not ok then self.error=err; return end
    local safe,written,reason=pcall(config.save,candidate)
    if not safe or not written then self.error="Ayarlar diske yazilamadi; baglanti degistirilmedi"; return end
    -- Reconfigure only after the atomic disk write succeeded. No crafting call.
    apply(candidate)
    for _,key in ipairs(fields) do cfg[key]=candidate[key] end
    self.tokenConfigured=candidate.webToken~=""
    self.draft.token=""; self.draft.url=candidate.webUrl; self.draft.control=candidate.webControl
    self.keyboard=false; self.error=nil
    self.message=disconnect and "Baglanti kapatildi; mevcut AE2 isleri surer" or "Kaydedildi; baglanti kuruluyor"
  end
  function self:touch(id)
    if id=="web:open" then self:open(); return end
    if not self.webMenu then return end
    if self.keyboard then
      if id=="webkey:done" then self.keyboard=false
      elseif id=="webkey:shift" then self.shift=not self.shift
      elseif id=="webkey:back" then self.draft[self.field]=self.draft[self.field]:sub(1,-2)
      elseif id=="webkey:clear" then self.draft[self.field]=""
      else local letter=id and id:match("^webkey:char:(.)$"); if letter then self:insert(self.shift and letter:upper() or letter) end end
      return
    end
    if id=="web:close" then self:close()
    elseif id=="web:url" or id=="web:token" then self.field=id:sub(5); self.keyboard=true
    elseif id=="web:control" then self.draft.control=not self.draft.control
    elseif id=="web:save" then self:save(false)
    elseif id=="web:disconnect" then self:save(true) end
  end
  function self:key(char,code)
    if not self.webMenu then return end
    if code==1 then if self.keyboard then self.keyboard=false else self:close() end
    elseif code==15 then self.field=self.field=="url" and "token" or "url"
    elseif code==28 or code==156 then if self.keyboard then self.keyboard=false else self:save(false) end
    elseif code==14 then self.draft[self.field]=self.draft[self.field]:sub(1,-2)
    elseif type(char)=="number" and char>=32 and char<=126 then self:insert(string.char(char)) end
  end
  function self:paste(text)
    if type(text)=="string" then self:insert(text:match("^%s*(.-)%s*$")) end
  end
  function self:tick() end
  return self
end
return M
