local codec=require("core.codec")
local M={}
-- View preference identity only. Ambiguous NBT variants cannot be favorited.
function M.key(item)
  if type(item)~="table" or type(item.name)~="string" then return end
  if item.identityComplete==false or (item.hasTag and (type(item.tag)~="string" or item.tag=="")) then return end
  return codec.encode({name=item.name,damage=item.damage or 0,hasTag=item.hasTag==true,tag=item.tag or ""})
end
return M
