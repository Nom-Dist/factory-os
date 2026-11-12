-- SHA-256 for downloaded file integrity. Native 5.3 fallback is local code.
local b=bit32
if not b then
  local chunk=assert(load([=[return {
    band=function(a,b) return (a & b) & 0xffffffff end,
    bor=function(a,b) return (a | b) & 0xffffffff end,
    bxor=function(a,b,c) return ((a ~ b) ~ (c or 0)) & 0xffffffff end,
    bnot=function(a) return (~a) & 0xffffffff end,
    rshift=function(a,n) return (a & 0xffffffff) >> n end,
    rrotate=function(a,n) return (((a & 0xffffffff) >> n) | (a << (32-n))) & 0xffffffff end
  }]=],"=factoryos/local-bitops","t",{}),"Lua 5.2 bit32 or Lua 5.3 required")
  b=chunk()
end
local band, bxor, bnot, rshift, ror = b.band, b.bxor, b.bnot, b.rshift, b.rrotate
local M = {}
local K = {
  0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
  0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
  0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
  0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
  0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
  0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
  0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
  0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2}
local function word(n)
  return string.char(band(rshift(n,24),255), band(rshift(n,16),255), band(rshift(n,8),255), band(n,255))
end
function M.sha256(s, raw)
  local len = #s
  s = s .. "\128" .. string.rep("\0", (55-len)%64) .. word(math.floor(len/536870912)) .. word((len*8)%4294967296)
  local h = {0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19}
  for offset=1,#s,64 do
    local w = {}
    for i=0,15 do
      local a,c,d,e = s:byte(offset+i*4,offset+i*4+3)
      w[i] = a*16777216+c*65536+d*256+e
    end
    for i=16,63 do
      local x,y = w[i-15],w[i-2]
      w[i] = (w[i-16]+bxor(ror(x,7),ror(x,18),rshift(x,3))+w[i-7]+bxor(ror(y,17),ror(y,19),rshift(y,10)))%4294967296
    end
    local a,c,d,e,f,g,j,k = table.unpack(h)
    for i=0,63 do
      local t1 = (k+bxor(ror(f,6),ror(f,11),ror(f,25))+bxor(band(f,g),band(bnot(f),j))+K[i+1]+w[i])%4294967296
      local t2 = (bxor(ror(a,2),ror(a,13),ror(a,22))+bxor(band(a,c),band(a,d),band(c,d)))%4294967296
      k,j,g,f,e,d,c,a = j,g,f,(e+t1)%4294967296,d,c,a,(t1+t2)%4294967296
    end
    local v = {a,c,d,e,f,g,j,k}
    for i=1,8 do h[i]=(h[i]+v[i])%4294967296 end
  end
  local out = {}
  for i=1,8 do out[i] = raw and word(h[i]) or string.format("%08x",h[i]) end
  return table.concat(out)
end
function M.equal(a,c)
  if type(a)~="string" or type(c)~="string" or #a~=#c then return false end
  local diff=0
  for i=1,#a do diff=b.bor(diff,bxor(a:byte(i),c:byte(i))) end
  return diff==0
end
-- RFC 6455 handshake only. SHA-256 remains the release integrity algorithm.
function M.sha1(s)
  local len=#s
  s=s.."\128"..string.rep("\0",(55-len)%64)..word(math.floor(len/536870912))..word((len*8)%4294967296)
  local h={0x67452301,0xefcdab89,0x98badcfe,0x10325476,0xc3d2e1f0}
  for offset=1,#s,64 do
    local w={}
    for i=0,15 do local a,c,d,e=s:byte(offset+i*4,offset+i*4+3); w[i]=((a*256+c)*256+d)*256+e end
    for i=16,79 do w[i]=ror(bxor(bxor(w[i-3],w[i-8]),bxor(w[i-14],w[i-16])),31) end
    local a,c,d,e,f=h[1],h[2],h[3],h[4],h[5]
    for i=0,79 do
      local fn,k
      if i<20 then fn=b.bor(band(c,d),band(bnot(c),e)); k=0x5a827999
      elseif i<40 then fn=bxor(c,d,e); k=0x6ed9eba1
      elseif i<60 then fn=b.bor(b.bor(band(c,d),band(c,e)),band(d,e)); k=0x8f1bbcdc
      else fn=bxor(c,d,e); k=0xca62c1d6 end
      local t=(ror(a,27)+fn+f+k+w[i])%4294967296
      f,e,d,c,a=e,d,ror(c,2),a,t
    end
    for i,v in ipairs({a,c,d,e,f}) do h[i]=(h[i]+v)%4294967296 end
  end
  local out={}; for i=1,5 do out[i]=word(h[i]) end; return table.concat(out)
end
return M
