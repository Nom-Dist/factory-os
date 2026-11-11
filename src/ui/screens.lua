local C=require("ui.renderer").colors
local M={}
local function num(n) return type(n)=="number" and string.format("%.0f",n) or "unknown" end
function M.draw(r,role,net,state,clock)
  if role=="main" then return require("ui.main_screen").draw(r,net,state,clock) end
  r:begin()
  local online=role=="server" or net.online
  local status=(role=="server" and state.serverStatus or net.status) or {}
  local ae=status.ae2 or {}
  r:fill(1,1,r.w,3,C.panel)
  r:text(3,2,"FACTORY OS / "..(role=="side" and "TELEMETRY" or "SERVER"),C.accent,C.panel)
  r:text(math.max(3,r.w-10),2,online and "ONLINE" or "OFFLINE",online and C.good or C.bad,C.panel)
  r:text(2,r.h,"v0.2.0 | "..(online and "wireless network" or "searching / reconnecting"),C.muted)
  if role=="server" then
    r:panel(2,5,r.w-2,r.h-6,"SYSTEM CONSOLE")
    r:text(3,7,"Clients: "..#(status.clients or {}),nil,C.panel)
    r:text(3,9,"AE2: "..(ae.online and "ONLINE" or "OFFLINE"),ae.online and C.good or C.bad,C.panel)
    r:text(3,11,"factoryos stop / status / logs",C.muted,C.panel)
  else
    local y,width=6,r.w-3
    r:panel(2,y,width,r.h-y-1,"ENERGY / FACTORY")
    local function line(offset,s,color) r:text(3,y+offset,tostring(s):sub(1,width-2),color,C.panel) end
    if not online then
      line(2,"SERVER OFFLINE",C.bad); line(4,"Automatic reconnect is active.",C.muted)
      line(6,"Check modem addresses, range and chunks.",C.muted)
    else
      local e=(status.power or {}).ae2 or {}
      line(2,"AE2 NETWORK ENERGY",C.accent)
      if ae.online and e.supported then
        line(4,num(e.stored).." / "..num(e.capacity).." AE")
        r:bar(3,y+6,math.max(1,width-3),(e.capacity or 0)>0 and e.stored/e.capacity or 0)
        line(8,"Input: "..num(e.injection).." AE/t"); line(10,"Usage: "..num(e.usage).." AE/t")
      else line(4,"AE2 energy unavailable",C.muted) end
      line(12,"RF/FE: unsupported driver",C.muted); line(14,"Reactors: read only / unavailable",C.muted)
    end
  end
  r:flush()
end
return M
