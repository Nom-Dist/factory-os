"""Actual Lua bridge + RFC6455 TCP + Node relay; game hardware/disk are mocked."""
from pathlib import Path
import json
import os
import select
import socket
import sys
import time
import uuid

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / ".tools"))
from lupa import lua52, lua53

engine = lua52 if os.environ.get("TEST_LUA") == "52" else lua53
lua = engine.LuaRuntime(encoding=None, unpack_returned_tuples=True)
preload = lua.globals().package.preload
for p in (ROOT / "src").rglob("*.lua"):
    name = p.relative_to(ROOT / "src").with_suffix("").as_posix().replace("/", ".").encode()
    preload[name] = lua.eval("function(s,n) return assert(load(s,n,'t')) end")(p.read_bytes(), name)
sockets = []

def connect(host, port):
    assert host == b"127.0.0.1"
    s = socket.socket(); s.setblocking(False); s.connect_ex(("127.0.0.1", int(port))); sockets.append(s)
    def ready():
        if not select.select([], [s], [], 0)[1]: return False
        if s.getsockopt(socket.SOL_SOCKET, socket.SO_ERROR): raise RuntimeError("connect_failed")
        return True
    def read(n):
        try:
            data = s.recv(int(n)); return data if data else None
        except BlockingIOError: return b""
    def write(data):
        try: return s.send(data)
        except BlockingIOError: return 0
    return lua.table_from({b"finishConnect": ready, b"read": read, b"write": write, b"close": s.close})

lua.globals().PY_CONNECT = connect
lua.globals().PY_UUID = lambda: uuid.uuid4().hex.encode()
lua.globals().PY_URL = f"ws://127.0.0.1:{os.environ['TEST_PORT']}/bridge/device".encode()
lua.globals().PY_TOKEN = os.environ["TEST_BRIDGE_TOKEN"].encode()
lua.execute(b'''
local disk={}; local codec=require("core.codec")
package.loaded["filesystem"]={exists=function(p) return disk[p]~=nil end}
package.loaded["core.storage"]={load=function(p) return disk[p] and codec.decode(disk[p]) end,
  save=function(p,v) disk[p]=codec.encode(v); return true end}
package.loaded["uuid"]={next=PY_UUID}
testTime=0; nativeRequests=0; startRpcs=0; durable=false; requestedAt=0
local item={name="test:interop_alloy",label="Interop Alloy (mock device)",damage=0,size=8,hasTag=false,tag="",isCraftable=true,identityComplete=true}
local internet={type="internet",address="interop-internet",connect=PY_CONNECT,isTcpEnabled=function() return true end}
local cpus={{name="Test CPU",busy=false,storage=8192}}
local recipe={getItemStack=function() return item end,request=function(amount,power,...)
  assert(amount==3 and power==true and select("#",...)==0)
  local j=assert(codec.decode(disk["/var/lib/factoryos/crafting.dat"]))
  assert(j.orders[1].state=="submitting" and j.orders[1].owner=="@factoryos-web")
  nativeRequests=nativeRequests+1; durable=true
  requestedAt=testTime
  local function status()
    if os.getenv("TEST_PLAN_FAILURE")=="1" and testTime-requestedAt>=0.25 then return false,"request failed (missing resources?)" end
    return nil,"computing"
  end
  return {isDone=status,isCanceled=status}
end}
local me={type="me_interface",address="interop-me",isNetworkPowered=function() return true end,
  getCraftables=function() return {recipe} end,getCpus=function() return cpus end,getItemsInNetwork=function()
    local copy={}; for k,v in pairs(item) do copy[k]=v end; return {copy}
  end}
local components={[internet.address]=internet,[me.address]=me}
package.loaded.component={list=function(kind)
  local list={}; for addr,p in pairs(components) do if not kind or p.type==kind then list[#list+1]={addr,p.type} end end
  local i=0; return function() i=i+1; if list[i] then return table.unpack(list[i]) end end
end,proxy=function(a) return components[a] end}
os.sleep=function() end
local cfg=require("core.config").defaults("server"); cfg.poll=5; cfg.webEnabled=true; cfg.webControl=true; cfg.webUrl=PY_URL; cfg.webToken=PY_TOKEN; cfg.webInterval=2
local server=require("server.main").new(cfg,function() return testTime end,function() end)
local dispatch=server.dispatch
server.dispatch=function(self,command,...)
  if command=="START_CRAFT" then startRpcs=startRpcs+1 end
  return dispatch(self,command,...)
end
bridge=require("server.web").new(cfg,server,function() return testTime end,function() end)
function step(t) testTime=t; server:tick(); bridge:tick() end
''')
start = time.monotonic()
done_at = None
try:
    print("READY", flush=True)
    while time.monotonic() - start < 15:
        lua.globals().step(time.monotonic() - start)
        if lua.globals().startRpcs >= 2 and done_at is None: done_at = time.monotonic()
        if done_at and time.monotonic() - done_at > (3 if os.environ.get("TEST_PLAN_FAILURE") == "1" else .8): break
        time.sleep(.01)
    report = {"nativeRequests": lua.globals().nativeRequests, "startRpcs": lua.globals().startRpcs, "durable": bool(lua.globals().durable), "lua": engine.LUA_VERSION}
    print(json.dumps(report), flush=True)
    assert report["nativeRequests"] == 1 and report["startRpcs"] == 2 and report["durable"]
finally:
    lua.globals().bridge.close(lua.globals().bridge)
    for s in sockets: s.close()
