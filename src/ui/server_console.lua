local C=require("ui.renderer").colors
local W=require("ui.widgets")
local M={}
local phases={disabled="KAPALI",waiting="BEKLENIYOR",connecting="BAGLANIYOR",online="BAGLI",sending="VERI GONDERILIYOR",offline="BAGLANTI HATASI",closed="KAPALI"}
function M.draw(r,net,state,clock)
  r:begin(); local w,h=r.w,r.h; local info=state.webStatus or {phase="disabled"}
  if state.keyboard and state.draft then
    W.panel(r,2,2,w-2,h-3,state.field=="token" and "TOKEN / GIZLI GIRIS" or "PANEL ADRESI / GIRIS")
    local value=state.draft[state.field] or ""
    W.text(r,3,3,w-4,state.field=="token" and (string.rep("*",math.min(#value,w-8)).."_") or (value.."_"):sub(-(w-4)),C.accent)
    local step=h>=16 and 2 or 1; local cell=math.floor((w-4)/10)
    for row,letters in ipairs({"1234567890","qwertyuiop","asdfghjkl:","zxcvbnm._/"}) do
      for i=1,#letters do
        local char=letters:sub(i,i)
        r:button(3+(i-1)*cell,4+(row-1)*step,cell-1,state.shift and char:upper() or char,"webkey:char:"..char,false,step)
      end
    end
    local y=4+4*step
    r:button(3,y,5,"-","webkey:char:-")
    r:button(9,y,9,"BUYUK","webkey:shift",state.shift)
    r:button(19,y,6,"SIL","webkey:back")
    r:button(26,y,w-28,"TEMIZLE","webkey:clear")
    r:button(3,h-2,w-4,"ALANA UYGULA / GERI","webkey:done",true)
    W.text(r,2,h,w-2,"Tab: alan | Enter: geri | Esc: geri",C.muted,C.bg)
  elseif state.webMenu and state.draft then
    W.panel(r,2,2,w-2,h-2,"WEB PANELI / BAGLANTI AYARLARI")
    W.text(r,3,3,w-4,"PANEL ADRESI",C.muted)
    local url=state.draft.url~="" and state.draft.url or "https://panel.alanadi.com"
    r:button(3,4,w-4,url:sub(-(w-6)),"web:url",state.field=="url")
    W.text(r,3,5,w-4,"TOKEN (bos: kayitli tokeni kullan)",C.muted)
    local token=state.draft.token~="" and string.rep("*",math.min(#state.draft.token,w-8)) or state.tokenConfigured and "[kayitli token / degistir]" or "[yeni token icin dokun]"
    r:button(3,6,w-4,token,"web:token",state.field=="token")
    r:button(3,7,w-4,"UZAKTAN KONTROL: "..(state.draft.control and "ACIK" or "KAPALI"),"web:control",state.draft.control)
    W.text(r,3,8,w-4,"WEB: "..(phases[info.phase] or "BEKLENIYOR"),info.phase=="online" and C.good or info.phase=="offline" and C.warn or C.muted)
    local connectionError=info.error and info.error~="" and info.error or nil
    W.wrap(r,3,9,w-4,math.max(1,h-11),state.error or connectionError or state.message or "",(state.error or connectionError) and C.warn or C.muted)
    local half=math.floor((w-5)/2)
    r:button(3,h-2,half,"KAYDET / BAGLAN","web:save",true)
    r:button(4+half,h-2,w-half-5,"KAPAT","web:close")
    r:button(3,h-1,w-4,"BAGLANTIYI KES","web:disconnect")
    W.text(r,2,h,w-2,"Tab: alan | Enter: baglan | Esc: kapat",C.muted,C.bg)
  else
    r:fill(1,1,w,3,C.panel); W.text(r,3,2,w-4,"FACTORY OS / SERVER",C.accent)
    W.panel(r,2,5,w-2,h-6,"SYSTEM CONSOLE")
    local status=state.serverStatus or {}; local ae=status.ae2 or {}
    W.text(r,3,6,w-4,"Ekranlar: "..#(status.clients or {}),C.muted)
    W.text(r,3,7,w-4,"AE2: "..(ae.online and "ONLINE" or "OFFLINE"),ae.online and C.good or C.warn)
    if h>=14 then W.text(r,3,9,w-4,"WEB: "..(phases[info.phase] or "KAPALI"),info.phase=="online" and C.good or C.muted) end
    if h>=16 then W.text(r,3,10,w-4,require("ui.updates").label(state.update),C.muted) end
    r:button(3,h-4,w-4,"WEB PANELI / BAGLANTI","web:open",true)
    require("ui.updates").action(r,3,h-2,w-4,state.update)
    W.text(r,2,h,w-2,"v0.6.1 | F4: WEB | F5/F6: Update",C.muted,C.bg)
  end
  r:flush()
end
return M
