local C=require("ui.renderer").colors
local M={}
local tabs={"Overview","AE2 stocks","Crafting CPUs","Energy","Machines","Alarms","Settings"}
local function num(n) return type(n)=="number" and string.format("%.0f",n) or "unknown" end
function M.draw(r,role,net,state,clock)
  r:begin()
  local online=role=="server" or net.online
  local status=role=="server" and state.serverStatus or net.status
  status=status or {}
  local ae=status.ae2 or {}
  r:fill(1,1,r.w,3,C.panel)
  r:text(3,2,"FACTORY OS / "..(role=="main" and "CONTROL" or role=="side" and "TELEMETRY" or "SERVER"),C.accent,C.panel)
  r:text(math.max(3,r.w-10),2,online and "ONLINE" or "OFFLINE",online and C.good or C.bad,C.panel)
  r:text(2,r.h,"v0.1.2 | "..(online and "wireless network" or "searching / reconnecting"),C.muted)
  if role=="server" then
    r:panel(2,5,r.w-2,r.h-6,"SYSTEM CONSOLE")
    r:text(3,7,"Clients: "..#(status.clients or {}),nil,C.panel)
    r:text(3,9,"AE2: "..(ae.online and "ONLINE" or "OFFLINE"),ae.online and C.good or C.bad,C.panel)
    r:text(3,11,"factoryos stop / status / logs",C.muted,C.panel)
    r:flush(); return
  end
  local tab=state.tab or 1
  local left=(role=="main" and r.w>=70) and 23 or 2
  if left>2 then
    for i,label in ipairs(tabs) do r:button(2,4+i*2,19,label,"tab:"..i,tab==i) end
  elseif role=="main" then
    r:button(2,4,11,"< page","tabprev"); r:text(15,4,tabs[tab],C.accent)
    r:button(r.w-9,4,9,"page >","tabnext")
  end
  local y=6
  local width=r.w-left-1
  r:panel(left,y,width,r.h-y-1,role=="side" and "ENERGY / FACTORY" or tabs[tab]:upper())
  local function line(offset,s,color) r:text(left+1,y+offset,tostring(s):sub(1,width-2),color,C.panel) end
  if not online then
    line(2,"SERVER OFFLINE",C.bad)
    line(4,"Automatic reconnect is active.",C.muted)
    line(6,"Check modem addresses, range and chunks.",C.muted)
    if net.status then line(8,"Cached telemetry is stale.",C.bad) end
  elseif role=="side" or tab==4 then
    local power=status.power or {}; local e=power.ae2 or {}
    line(2,"AE2 NETWORK ENERGY",C.accent)
    if ae.online and e.supported then
      line(4,num(e.stored).." / "..num(e.capacity).." AE")
      r:bar(left+1,y+6,math.max(1,width-3),(e.capacity or 0)>0 and e.stored/e.capacity or 0)
      line(8,"Input: "..num(e.injection).." AE/t")
      line(10,"Usage: "..num(e.usage).." AE/t")
    else line(4,"AE2 energy unavailable",C.muted) end
    line(12,"RF/FE: unsupported driver",C.muted)
    line(14,"Reactors: read only / unavailable",C.muted)
  elseif tab==1 then
    line(2,"FACTORY NETWORK",C.accent)
    line(4,"AE2: "..(ae.online and "ONLINE" or "OFFLINE"),ae.online and C.good or C.bad)
    line(6,"Stored item variants: "..num(ae.itemTypes)..(ae.truncated and " (limited!)" or ""))
    line(8,"Connected clients: "..#(status.clients or {}))
    line(10,"Server uptime: "..num(status.uptime).." s")
    line(12,"Crafting control: pending validation",C.muted)
    line(14,"Reactor control: unavailable",C.muted)
  elseif tab==2 then
    local stocks=state.stocks or {items={},page=1,pages=1,total=0}
    line(2,state.error or (stocks.truncated and "WARNING: inventory limited to 2000 variants" or "ITEM / VARIANT                             COUNT"),state.error and C.bad or C.muted)
    local visible=math.max(0,math.min(24,r.h-y-10))
    -- Logical network pages are 24 rows. Scroll within a page on smaller GPUs.
    for i=1,visible do
      local item=(stocks.items or {})[i+(state.rowOffset or 0)]
      if item then
        line(3+i,(item.label.." ["..item.damage..(item.hasTag and ",NBT" or "").."]"):sub(1,math.max(1,width-15)))
        r:text(r.w-12,y+3+i,string.format("%10s",num(item.size)),C.accent,C.panel)
      end
    end
    r:button(left+1,r.h-3,8,"< prev","prev"); r:button(left+10,r.h-3,8,"next >","next")
    r:button(left+19,r.h-3,8,"scroll","scroll"); r:button(left+28,r.h-3,9,"refresh","refresh")
    r:text(left+1,r.h-5,("Filter: "..(state.query or "")..(state.editing and "_" or "")):sub(1,math.max(0,width-12)),C.muted,C.panel)
    r:button(r.w-10,r.h-5,9,state.editing and "done" or "search","search",state.editing)
    line(r.h-y-2,"Page "..stocks.page.."/"..stocks.pages.." | "..stocks.total.." variants")
  elseif tab==3 then
    line(2,state.error or "CPU OCCUPANCY (not full job details)",state.error and C.bad or C.muted)
    for i,cpu in ipairs((state.jobs or {}).cpus or {}) do
      if y+3+i>=r.h-3 then break end
      line(3+i,(cpu.busy and "BUSY  " or "IDLE  ")..cpu.name.." / "..num(cpu.storage).." B",cpu.busy and C.accent or C.good)
    end
    line(r.h-y-3,"Remote craft requests disabled in v0.1",C.muted)
  elseif tab==5 then
    line(2,"No verified machine drivers installed.",C.muted)
    line(4,"Monitoring / control: unsupported",C.muted)
  elseif tab==6 then
    line(2,ae.online and "AE2 link healthy" or (ae.error or "AE2 unavailable"),ae.online and C.good or C.bad)
    line(4,"Crafting and reactor control disabled.",C.muted)
    line(6,"Logs: factoryos logs",C.muted)
  elseif tab==7 then
    line(2,"Local configuration: factoryos config",C.muted)
    line(4,"Each display owns one GPU / screen.")
    line(6,"Updates: stop, then factoryos update")
    line(8,"No automatic or wireless updates yet.",C.muted)
  end
  r:flush()
end
return M
