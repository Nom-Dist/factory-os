local M={}
function M.clean(value) return tostring(value or ""):gsub("[^ -~]","?") end
function M.integer(n)
  if type(n)~="number" or n~=n or math.abs(n)==math.huge then return "--" end
  local s=string.format("%.0f",n)
  local sign=s:sub(1,1)=="-" and "-" or ""
  s=s:gsub("^%-","")
  local out=s:reverse():gsub("(%d%d%d)","%1,"):reverse():gsub("^,","")
  return sign..out
end
function M.compact(n)
  if type(n)~="number" or n~=n or math.abs(n)==math.huge then return "--" end
  for _,u in ipairs({{1e12,"T"},{1e9,"B"},{1e6,"M"},{1e3,"K"}}) do
    if math.abs(n)>=u[1] then return (string.format("%.2f",n/u[1]):gsub("0+$",""):gsub("%.$",""))..u[2] end
  end
  return string.format("%.0f",n)
end
function M.percent(value,capacity)
  if type(value)~="number" or type(capacity)~="number" or capacity<=0 then return "--" end
  return string.format("%.0f%%",math.max(0,math.min(100,value/capacity*100)))
end
function M.duration(n)
  if type(n)~="number" then return "--" end
  n=math.max(0,math.floor(n))
  if n>=86400 then return math.floor(n/86400).."g "..math.floor(n/3600)%24 .."sa" end
  return string.format("%02d:%02d:%02d",math.floor(n/3600),math.floor(n/60)%60,n%60)
end
return M
