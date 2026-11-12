-- Loaded afresh by /bin/factoryos.lua; active pointer selects an immutable release.
local root,args=...
root=root or "/usr/lib/factoryos"
local f=io.open(root.."/active","r") or io.open(root.."/active.bak","r")
assert(f,"FactoryOS active release missing")
local version=f:read("*l"); f:close()
assert(version and version:match("^[%w%._%-]+$") and not version:find("..",1,true),"Invalid release pointer")
local release=root.."/releases/"..version
-- OpenOS caches modules across commands. Keep running service closures intact.
if not package.loaded["factoryos.service"] or not package.loaded["factoryos.service"].running then
  -- OpenOS itself owns many core.* modules. Clear only FactoryOS's exact names.
  local names={"core.cli","core.codec","core.config","core.crypto","core.hardware","core.installer",
    "core.logger","core.runtime","core.storage","core.updater","core.items","core.autostart","core.updates","network.modem","network.messages",
    "network.protocol","network.websocket","server.web","server.ae2","server.crafting","server.stock","server.energy","server.machines","server.main",
    "client.main_display","client.crafting","client.stock","client.server_console","client.side_display","client.preferences","ui.renderer","ui.screens","ui.server_console","ui.main_screen","ui.crafting","ui.stock","ui.widgets","ui.format","ui.updates"}
  for _,name in ipairs(names) do package.loaded[name]=nil end
end
package.path=release.."/?.lua;"..release.."/?/init.lua;"..package.path
return require("core.cli").main(args or {},root)
