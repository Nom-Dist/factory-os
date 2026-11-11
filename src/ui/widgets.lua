local C=require("ui.renderer").colors
local F=require("ui.format")
local M={}
function M.text(r,x,y,width,text,color,bg,align)
  width=math.max(0,math.floor(width))
  local s=F.clean(text)
  if #s>width then s=width>2 and s:sub(1,width-2)..".." or s:sub(1,width) end
  if align=="right" then x=x+width-#s end
  r:text(x,y,s,color or C.text,bg or C.panel)
end
function M.panel(r,x,y,w,h,title)
  if w<2 or h<1 then return end
  r:fill(x,y,w,h,C.panel)
  r:fill(x,y,w,1,C.raised)
  M.text(r,x+1,y,w-2,title,C.muted,C.raised)
end
function M.wrap(r,x,y,width,height,text,color,bg)
  local s=F.clean(text)
  local lines={}
  for word in s:gmatch("%S+") do
    if #lines==0 then lines[1]="" end
    while #word>width and width>0 do
      if lines[#lines]~="" then lines[#lines+1]="" end
      lines[#lines]=word:sub(1,width); lines[#lines+1]=""; word=word:sub(width+1)
    end
    local last=lines[#lines]
    if #last>0 and #last+1+#word>width then lines[#lines+1]=word
    else lines[#lines]=last..(#last>0 and " " or "")..word end
  end
  for i=1,math.min(height,#lines) do M.text(r,x,y+i-1,width,lines[i],color,bg) end
end
function M.metric(r,x,y,w,title,value,note,color)
  M.panel(r,x,y,w,8,title)
  r:fill(x,y+1,1,6,color or C.accent)
  M.text(r,x+2,y+3,w-4,value,color or C.accent)
  M.text(r,x+2,y+6,w-4,note,C.muted)
end
return M
