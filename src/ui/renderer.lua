-- Software diff buffer; intentionally no 1.8 VRAM/bitblt APIs.
local M={colors={bg=0x0b1220,panel=0x152337,accent=0x20bfd0,text=0xdce8ed,muted=0x8095aa,good=0x55cc88,bad=0xee6666,
  raised=0x1b3043,line=0x294253,blue=0x629ff5,warn=0xe6ba68,stripe=0x112032,selected=0x20435a}}
function M.new(gpu,screen,role)
  local maxw,maxh=gpu.maxResolution()
  local w=math.min(maxw,role=="main" and 160 or role=="side" and 80 or 50)
  local h=math.min(maxh,role=="main" and 50 or role=="side" and 25 or 16)
  gpu.setResolution(w,h)
  gpu.setDepth(gpu.maxDepth())
  local self={w=w,h=h,screen=screen.address,gpu=gpu,front={},buttons={}}
  local C=M.colors
  function self:begin()
    self.rows={}; self.buttons={}
    for y=1,h do
      local row={chars={},fg={},bg={}}
      for x=1,w do row.chars[x]=" "; row.fg[x]=C.text; row.bg[x]=C.bg end
      self.rows[y]=row
    end
  end
  function self:text(x,y,s,fg,bg)
    if y<1 or y>h then return end
    s=tostring(s):gsub("[^ -~]","?")
    local row=self.rows[y]
    for i=1,#s do
      local at=x+i-1
      if at>=1 and at<=w then row.chars[at]=s:sub(i,i); row.fg[at]=fg or C.text; row.bg[at]=bg or C.bg end
    end
  end
  function self:fill(x,y,width,height,color)
    for line=math.max(y,1),math.min(y+height-1,h) do self:text(x,line,string.rep(" ",math.max(0,width)),C.text,color) end
  end
  function self:panel(x,y,width,height,title)
    self:fill(x,y,width,height,C.panel)
    self:text(x+1,y,title:sub(1,math.max(0,width-2)),C.accent,C.panel)
  end
  function self:button(x,y,width,label,id,selected,height,enabled)
    height=height or 1
    local bg=selected and C.accent or C.panel
    local fg=enabled==false and C.muted or selected and C.bg or C.text
    self:fill(x,y,width,height,bg)
    self:text(x,y+math.floor((height-1)/2),(" "..label..string.rep(" ",width)):sub(1,width),fg,bg)
    if enabled~=false then self:hotspot(x,y,width,height,id) end
  end
  function self:hotspot(x,y,width,height,id)
    local right,bottom=math.min(self.w,x+width-1),math.min(self.h,y+height-1)
    x,y=math.max(1,x),math.max(1,y)
    if right>=x and bottom>=y then self.buttons[#self.buttons+1]={x=x,y=y,w=right-x+1,h=bottom-y+1,id=id} end
  end
  function self:bar(x,y,width,value)
    value=math.max(0,math.min(1,value or 0))
    self:text(x,y,string.rep("-",width),C.muted,C.panel)
    self:text(x,y,string.rep("#",math.floor(width*value)),C.accent,C.panel)
  end
  function self:flush()
    for y,row in ipairs(self.rows) do
      local prev=self.front[y]
      local x=1
      while x<=w do
        if prev and row.chars[x]==prev.chars[x] and row.fg[x]==prev.fg[x] and row.bg[x]==prev.bg[x] then x=x+1
        else
          local start=x; local fg,bg=row.fg[x],row.bg[x]; local chars={}
          repeat
            chars[#chars+1]=row.chars[x]; x=x+1
          until x>w or row.fg[x]~=fg or row.bg[x]~=bg or (prev and row.chars[x]==prev.chars[x] and row.fg[x]==prev.fg[x] and row.bg[x]==prev.bg[x])
          gpu.setForeground(fg); gpu.setBackground(bg); gpu.set(start,y,table.concat(chars))
        end
      end
    end
    self.front=self.rows
  end
  function self:touch(address,x,y)
    if address~=self.screen then return end
    for _,b in ipairs(self.buttons) do if y>=b.y and y<b.y+b.h and x>=b.x and x<b.x+b.w then return b.id end end
  end
  return self
end
return M
