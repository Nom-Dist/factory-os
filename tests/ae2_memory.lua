-- Standalone allocation regression, not a measurement of total OpenOS usage.
-- The host runner enforces a 2 MiB Lua allocation limit for this fixture.
local p={address="me",type="me_interface"}
p.getItemsInNetwork=function()
  local rows={}
  for i=1,2000 do
    rows[i]={name="mod:item_"..i,label="Item "..i,damage=0,size=i,hasTag=false,isCraftable=false,
      tooltip={"extra tooltip "..i},unused="extra "..i}
  end
  return rows
end
package.preload.component=function()
  return {list=function()
    local done=false
    return function() if not done then done=true; return "me","me_interface" end end
  end,proxy=function() return p end}
end
os.sleep=function() end
local ae=require("server.ae2").new({ae2Enabled=true,ae2Address=""})
for i=1,5 do
  ae:poll()
  assert(ae.online,ae.error)
  assert(#ae.items==2000)
end
print("  PASS AE2 2000-item refresh x5 under 2 MiB allocation limit")
