-- OC 1.8.3 reports submission failures, but exposes no missing-item list.
local M={}
function M.explain(reason)
  local raw=tostring(reason or ""); local lower=raw:lower()
  if lower:find("missing resources",1,true) then
    return "AE2_REJECTED","AE2 isi baslatamadi. Kaynak eksigi veya uygun CPU/bellek sorunu olabilir. ME Terminal'de kontrol edin."
  elseif lower:find("no controller",1,true) or lower:find("no ae grid",1,true) or lower:find("waiting for ae network to load",1,true) then
    return "AE2_UNAVAILABLE","AE2 agi hazir degil veya baglanti yok. Adapter ve ag baglantisini kontrol edin."
  elseif lower:find("not enough memory",1,true) or lower:find("outofmemory",1,true) then
    return "MEMORY","Bellek yetersiz. Asagidaki surucu yanitini ve OC/AE2 bellegini kontrol edin."
  elseif lower:find("request failed",1,true) then
    return "AE2_ERROR","AE2 uretim istegini reddetti. Surucunun hata ayrintisi asagida."
  end
  return raw~="" and "ERROR" or "",raw
end
return M
