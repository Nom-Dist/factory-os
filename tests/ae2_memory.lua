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
local craft={journal={orders={},automation={revision=1,nextId=17,paused=false,rules={}}}}
for i=1,16 do
  craft.journal.automation.rules[i]={id=i,item={name="mod:item_"..i,damage=0,hasTag=false,tag=""},label="Item "..i,
    minimum=1,target=64,enabled=false,address="me"}
end
local stock=require("server.stock").new(craft,ae,function() return 0 end)
for i=1,5 do
  ae:poll()
  assert(ae.online,ae.error)
  assert(#ae.items==2000)
  for page=1,4 do
    for _,r in ipairs(stock:list({page=page}).rules) do assert(r.stock==r.id) end
  end
end
print("  PASS AE2 2000-item refresh x5 and 16 stock-rule counts under 2 MiB allocation limit")
