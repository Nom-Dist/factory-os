-- Read-only OpenOS probe. Copy to an OC disk and run: ingame_probe.lua
-- Does not request crafting, change machine state, or rebind GPUs.
local component=require("component")
local computer=require("computer")
local serialization=require("serialization")
local report={lua=_VERSION,openos=_OSVERSION or "unknown",uptime=computer.uptime(),components={}}
local infoOk,deviceInfo=pcall(function() return computer.getDeviceInfo() end)
local readMethods={"isWireless","maxPacketSize","getScreen","getAspectRatio","getResolution","maxResolution",
  "getItemsInNetwork","getCpus","getStoredPower","getMaxStoredPower","getAvgPowerInjection","getAvgPowerUsage"}
for address,kind in component.list() do
  local entry={address=address,type=kind,methods={},results={}}
  if infoOk and type(deviceInfo)=="table" then entry.deviceInfo=deviceInfo[address] end
  local p=component.proxy(address)
  local ok,methods=pcall(component.methods,address)
  if ok then for name in pairs(methods) do entry.methods[#entry.methods+1]=name end; table.sort(entry.methods) end
  for _,method in ipairs(readMethods) do
    if p[method]~=nil then
      local success,a,b=pcall(p[method])
      if method=="getItemsInNetwork" and success and type(a)=="table" then
        entry.results[method]={count=#a,sample={}}
        for i=1,math.min(5,#a) do entry.results[method].sample[i]=a[i] end
      else entry.results[method]={ok=success,value=a,second=b} end
    end
  end
  report.components[#report.components+1]=entry
  os.sleep(0)
end
local path="/home/factoryos-probe.log"
local f=assert(io.open(path,"w")); f:write(serialization.serialize(report)); f:close()
print("Read-only probe written to "..path)
print("Compare these components/methods with docs/compatibility.md; production is not verified by this probe.")
