-- Periodic metadata checks and user-requested, verified updates. Never auto-applies.
local updater=require("core.updater")
local storage=require("core.storage")
local codec=require("core.codec")
local thread=require("thread")
local M={cacheRoot="/var/lib/factoryos/update-cache",chunkSize=1024}
function M.new(cfg,net,clock,service,options)
  options=options or {}
  local root=options.root or updater.root
  local cacheRoot=options.cacheRoot or M.cacheRoot
  local self={phase="idle",message="Henuz kontrol edilmedi",busy=false,closed=false,progress=0,total=0,
    current=(storage.read(root.."/active",100) or "unknown"):gsub("[\r\n]+$",""),nextCheck=clock()+15,epoch=0}
  local function idle()
    if not options.isIdle then return true end
    local ok,allowed,reason=pcall(options.isIdle)
    if not ok then return false,"Uretim durumu okunamadi" end
    return allowed,reason
  end
  local function assertIdle()
    local allowed,reason=idle(); assert(allowed,reason or "Uretim CPU'lari mesgul; sonra tekrar deneyin")
  end
  local function checkAlive() assert(not self.closed,"Update cancelled") end
  function self:public()
    local allowed,reason=idle()
    if cfg.role~="server" then
      local remote=(net.status or {}).update
      if not net.online then allowed=false; reason="Sunucu baglantisi yok"
      elseif remote and remote.canApply==false then allowed=false; reason=remote.reason end
    end
    return {phase=self.phase,message=self.message,busy=self.busy,currentRelease=self.current,
      release=self.manifest and self.manifest.release or self.remoteRelease or "",
      version=self.manifest and (self.manifest.version or self.manifest.release) or self.remoteVersion or "",
      available=(self.manifest and self.manifest.release or self.remoteRelease or self.current)~=self.current,
      progress=self.progress,total=self.total,file=self.file or "",autoStart=cfg.autoStart,
      automatic=cfg.updateAutoCheck,interval=cfg.updateCheckInterval,role=cfg.role,
      canApply=allowed==true,reason=reason or "",lastCheck=self.lastCheck or 0}
  end
  function self:spawn(fn)
    if self.busy or self.closed then return false end
    self.busy=true; self.epoch=self.epoch+1
    local epoch=self.epoch
    self.worker=thread.create(function()
      local ok,err=xpcall(fn,debug.traceback)
      if self.closed or self.epoch~=epoch then return end
      self.busy=false
      if not ok then
        self.phase="error"; self.message=tostring(err):match("[^\r\n]+") or "Guncelleme basarisiz"
        if options.log then options.log("ERROR","Update: "..tostring(err)) end
      end
    end)
    return true
  end
  function self:accept(manifest)
    updater.validate(manifest); self.manifest=manifest; self.lastCheck=clock()
    self.phase=manifest.release==self.current and "current" or "available"
    self.message=self.phase=="current" and "En guncel surum kullaniliyor" or "Yeni surum hazir"
  end
  function self:checkNow()
    checkAlive(); self.phase="checking"; self.message="GitHub kontrol ediliyor"
    local manifest=assert(codec.decode(updater.source(cfg.updateBase)("manifest.dat",65536)),"Invalid update manifest")
    checkAlive(); self:accept(manifest)
  end
  function self:prepareNow()
    if not self.manifest then self:checkNow() end
    local manifest=self.manifest
    if self.cachedManifest and self.cachedManifest.release==manifest.release then return manifest end
    self.phase="downloading"; self.message="Sunucu dosyalari hazirliyor"
    self.cachedManifest=updater.stage(updater.source(cfg.updateBase),cacheRoot,{manifest=manifest,quiet=true,
      progress=function(i,n,path) checkAlive(); self.progress=i; self.total=n; self.file=path end})
    self.cacheFiles={}
    for _,file in ipairs(manifest.files) do self.cacheFiles[file.path]=file end
    self.phase=manifest.release==self.current and "current" or "available"
    self.message="Kablosuz guncelleme paketi hazir"
    return manifest
  end
  function self:rpc(command,args)
    checkAlive(); assert(net.online,"Sunucu baglantisi yok")
    local done,result,reason=false,nil,nil
    local id,err=net:request(command,args,function(data,why) result=data; reason=why; done=true end)
    assert(id,err)
    local deadline=clock()+20
    while not done do checkAlive(); assert(clock()<deadline,"Kablosuz guncelleme zaman asimi"); os.sleep(0.05) end
    assert(result,reason or "Guncelleme yaniti alinamadi")
    return result
  end
  function self:remoteInfo(args,waitReady)
    local result=self:rpc("GET_UPDATE_INFO",args)
    local deadline=clock()+600
    while result.busy or waitReady and not result.ready do
      assert(result.info and result.info.phase~="error",result.info and result.info.message or "Sunucu guncelleme hatasi")
      checkAlive(); assert(clock()<deadline,"Sunucu paketi hazirlayamadi")
      self.message=result.info.message or "Sunucu bekleniyor"
      self.progress=result.info.progress or 0; self.total=result.info.total or 0; self.file=result.info.file
      os.sleep(1)
      result=self:rpc("GET_UPDATE_INFO",{})
      if not result.busy and not result.ready and waitReady then error(result.info.message or "Guncelleme paketi hazir degil") end
    end
    assert(result.info and result.info.phase~="error",result.info and result.info.message or "Sunucu guncelleme hatasi")
    if result.manifest then updater.validate(result.manifest) end
    return result
  end
  function self:check()
    if self.busy then return end
    self.phase="checking"; self.message=cfg.role=="server" and "GitHub kontrol ediliyor" or "Sunucudan kontrol isteniyor"
    self.nextCheck=clock()+cfg.updateCheckInterval
    return self:spawn(function()
      if cfg.role=="server" then self:checkNow()
      else
        local result=self:remoteInfo({check=true})
        assert(result.manifest,"Sunucuda guncelleme bilgisi yok; sunucuyu guncelleyin")
        self:accept(result.manifest)
      end
    end)
  end
  function self:apply()
    if self.busy then return end
    self.phase="downloading"; self.message="Guncelleme hazirlaniyor"
    return self:spawn(function()
      local prepared
      assertIdle()
      if cfg.role=="server" then
        self:checkNow()
        if self.manifest.release==self.current then return end
        local manifest=self:prepareNow()
        local base=cacheRoot.."/releases/"..manifest.release
        prepared=updater.stage(function(path,limit) checkAlive(); return assert(storage.read(base.."/"..path:gsub("^src/",""),limit)) end,
          root,{manifest=manifest,quiet=true,progress=function(i,n,path) self.progress=i; self.total=n; self.file=path end})
      else
        local result=self:remoteInfo({})
        if not result.manifest then result=self:remoteInfo({check=true}) end
        assert(result.manifest,"Sunucuda guncelleme paketi yok")
        self:accept(result.manifest)
        if self.manifest.release==self.current then return end
        assert(result.info.canApply,result.info.reason or "Uretim mesgul")
        local manifest=self.manifest
        result=self:remoteInfo({prepare=true,release=manifest.release},true)
        assert(result.manifest.release==manifest.release,"Guncelleme degisti; tekrar kontrol edin")
        self.phase="downloading"; self.message="Dosyalar kablosuz aliniyor"
        local index={}; for _,file in ipairs(manifest.files) do index["src/"..file.path]=file end
        prepared=updater.stage(function(path,limit)
          local file=assert(index[path],"Unknown update file")
          local chunks,offset={},0
          while offset<file.size do
            checkAlive()
            local chunk=self:rpc("GET_UPDATE_FILE",{release=manifest.release,path=file.path,offset=offset})
            assert(chunk.release==manifest.release and chunk.path==file.path and chunk.offset==offset and chunk.size==file.size,"Invalid update chunk")
            assert(type(chunk.data)=="string" and #chunk.data>0 and #chunk.data<=M.chunkSize and offset+#chunk.data<=limit,"Invalid update chunk size")
            chunks[#chunks+1]=chunk.data; offset=offset+#chunk.data; os.sleep(0)
          end
          return table.concat(chunks)
        end,root,{manifest=manifest,quiet=true,progress=function(i,n,path) self.progress=i; self.total=n; self.file=path end})
        result=self:remoteInfo({}); assert(result.info.canApply,result.info.reason or "Uretim mesgul")
      end
      assertIdle(); checkAlive()
      self.readyManifest=prepared
      self.phase="ready"; self.message="Dogrulandi; yeniden baslatiliyor"
    end)
  end
  function self:serve(command,args)
    assert(cfg.role=="server","Server only")
    if command=="GET_UPDATE_INFO" then
      if args.check then self:check() end
      if args.prepare then
        if not self.manifest or args.release~=self.manifest.release then return nil,"UPDATE_CHANGED" end
        if not self.busy and (not self.cachedManifest or self.cachedManifest.release~=args.release) then
          self.phase="downloading"; self.message="Paket hazirlaniyor"; self:spawn(function() self:prepareNow() end)
        end
      end
      return {info=self:public(),manifest=self.manifest,busy=self.busy,
        ready=self.cachedManifest~=nil and self.manifest~=nil and self.cachedManifest.release==self.manifest.release}
    end
    if command=="GET_UPDATE_FILE" then
      if not self.cachedManifest or args.release~=self.cachedManifest.release then return nil,"UPDATE_NOT_READY" end
      local file=type(args.path)=="string" and self.cacheFiles and self.cacheFiles[args.path]
      local offset=args.offset
      if not file or type(offset)~="number" or offset%1~=0 or offset<0 or offset>=file.size then return nil,"INVALID_UPDATE_FILE" end
      local data,err=storage.read(cacheRoot.."/releases/"..args.release.."/"..file.path,file.size)
      if not data then return nil,err end
      return {data=data:sub(offset+1,offset+M.chunkSize),offset=offset,size=file.size,path=file.path,release=args.release}
    end
    return nil,"UNSUPPORTED_COMMAND"
  end
  function self:touch(id)
    if id=="update:check" then self:check()
    elseif id=="update:apply" then self:apply()
    elseif id=="update:autostart" and not self.busy then
      local previous=cfg.autoStart; cfg.autoStart=not previous
      local ok,err=pcall(function() assert(require("core.config").save(cfg)); require("core.autostart").ensure(cfg.autoStart) end)
      if not ok then cfg.autoStart=previous; self.phase="error"; self.message=tostring(err) end
    end
  end
  function self:tick()
    if cfg.role=="server" then
      if cfg.updateAutoCheck and clock()>=self.nextCheck and not self.busy then self:check() end
    elseif net.online then
      local remote=(net.status or {}).update
      if remote and type(remote.release)=="string" and remote.release~="" and not self.busy then
        self.remoteRelease=remote.release; self.remoteVersion=remote.version
        if self.manifest and self.manifest.release~=remote.release then self.manifest=nil; self.phase="idle" end
        if not self.manifest and self.phase=="idle" then
          self.phase=remote.release==self.current and "current" or "available"
          self.message=self.phase=="current" and "En guncel surum kullaniliyor" or "Sunucuda yeni surum var"
        end
      end
    end
  end
  function self:close()
    self.closed=true; self.epoch=self.epoch+1
    if self.worker and self.worker.kill then pcall(self.worker.kill,self.worker) end
  end
  return self
end
return M
