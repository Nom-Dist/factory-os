local component=require("component")
local M={}
function M.select(kind,address,optional)
  if address and address~="" then
    local ok,p=pcall(component.proxy,address)
    if ok and p and p.type==kind then return p end
    return nil,"Configured "..kind.." missing: "..address
  end
  local list={}
  for addr in component.list(kind,true) do list[#list+1]=addr end
  if #list==1 then return component.proxy(list[1]) end
  if #list==0 then return nil,(optional and "Optional " or "Missing ")..kind end
  return nil,"Multiple "..kind.." components; select exact address with factoryos config "..kind.." ADDRESS"
end
function M.check(c)
  local modem,err=M.select("modem",c.modem)
  if not modem then return nil,err end
  if not modem.isWireless() then return nil,"Wireless Network Card required" end
  local gpu,ge=M.select("gpu",c.gpu)
  if not gpu then return nil,ge end
  local screen,se=M.select("screen",c.screen)
  if not screen then return nil,se end
  local ok,reason=gpu.bind(screen.address,false)
  if not ok then return nil,"GPU bind failed: "..tostring(reason) end
  local w,h=gpu.maxResolution()
  if w<40 or h<12 then return nil,"Screen/GPU requires at least 40x12 characters" end
  return {modem=modem,gpu=gpu,screen=screen,maxWidth=w,maxHeight=h,
    internet=component.isAvailable("internet")}
end
function M.describe()
  local lines={}
  for address,kind in component.list() do
    lines[#lines+1]=kind.." "..address
  end
  table.sort(lines)
  return table.concat(lines,"\n")
end
return M
