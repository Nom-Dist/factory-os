local C=require("ui.renderer").colors
local W=require("ui.widgets")
local M={}
local labels={idle="KONTROL BEKLENIYOR",checking="GUNCELLEME KONTROL EDILIYOR",available="YENI SURUM VAR",current="SISTEM GUNCEL",downloading="DOSYALAR HAZIRLANIYOR",ready="YENIDEN BASLATILIYOR",error="ISLEM TAMAMLANAMADI"}
function M.label(info) return labels[(info or {}).phase] or labels.idle end
function M.action(r,x,y,width,info)
  info=info or {}
  local apply=info.available and not info.busy
  local label=info.busy and "GUNCELLEME ISLEMI SURUYOR" or apply and info.canApply==false and "URETIM MESGUL / SONRA DENE" or apply and "GUNCELLE / YENIDEN AC" or "GUNCELLEME KONTROL ET"
  r:button(x,y,width,label,apply and "update:apply" or "update:check",apply,1,not info.busy and (not apply or info.canApply~=false))
end
function M.draw(r,x,y,w,h,info)
  info=info or {phase="idle"}
  W.panel(r,x,y,w,h,"YAZILIM / GUNCELLEMELER")
  local color=info.phase=="error" and C.warn or info.phase=="current" and C.good or info.available and C.accent or C.muted
  if h<16 then
    W.text(r,x+1,y+1,w-2,M.label(info),color)
    if h>=6 then W.text(r,x+1,y+3,w-2,info.message or "",C.muted) end
    M.action(r,x+1,math.min(y+h-1,r.h-2),w-2,info)
    return
  end
  W.text(r,x+2,y+3,w-4,M.label(info),color)
  W.text(r,x+2,y+6,w-4,"KURULU SURUM",C.muted)
  W.text(r,x+2,y+7,w-4,info.currentRelease or "--",C.text)
  W.text(r,x+2,y+10,w-4,"GITHUB / SUNUCUDAKI SURUM",C.muted)
  W.text(r,x+2,y+11,w-4,info.version and info.version~="" and info.version or "Henuz kontrol edilmedi",C.accent)
  if h>=30 then
    W.wrap(r,x+2,y+14,w-4,3,info.message or "",info.phase=="error" and C.warn or C.muted)
    if (info.total or 0)>0 then
      r:bar(x+2,y+18,w-4,(info.progress or 0)/info.total)
      W.text(r,x+2,y+20,w-4,(info.progress or 0).." / "..info.total.."  "..(info.file or ""),C.muted)
    end
    W.wrap(r,x+2,y+23,w-4,2,info.role=="server" and (info.automatic and "GitHub her "..math.floor((info.interval or 900)/60).." dakikada kontrol edilir. Uygulamak icin dugmeye basin." or "Otomatik kontrol kapali. Simdi kontrol et dugmesini kullanabilirsiniz.") or "Guncelleme sunucudan kablosuz alinir. Bu ekranda Internet Card gerekmez.",C.muted)
  end
  local buttonY=y+h-11
  if h<30 then buttonY=y+h-5 end
  local width=math.floor((w-6)/2)
  r:button(x+2,buttonY,width,"SIMDI KONTROL ET","update:check",false,2,not info.busy)
  r:button(x+width+4,buttonY,w-width-6,"GUNCELLE / YENIDEN AC","update:apply",true,2,not info.busy and info.available==true and info.canApply~=false)
  if h>=30 then
    r:button(x+2,y+h-6,math.min(36,w-4),"OTOMATIK ACILIS: "..(info.autoStart and "ACIK" or "KAPALI"),"update:autostart",info.autoStart,2,not info.busy)
    W.text(r,x+2,y+h-2,w-4,info.canApply==false and info.reason or "Ayarlar korunur. Dosyalar dogrulanir, sonra yeniden acilir.",info.canApply==false and C.warn or C.muted)
  end
end
return M
