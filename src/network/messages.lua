local M={}
M.read={HEARTBEAT=true,GET_SERVER_STATUS=true,GET_AE2_STOCKS=true,GET_CRAFTING_JOBS=true,GET_POWER_STATUS=true,GET_MACHINE_STATUS=true,GET_UPDATE_INFO=true,GET_UPDATE_FILE=true}
function M.authorize(role,command)
  if not M.read[command] then return nil,"UNSUPPORTED_COMMAND" end
  if role~="main" and role~="side" then return nil,"FORBIDDEN" end
  if role=="side" and (command=="GET_AE2_STOCKS" or command=="GET_CRAFTING_JOBS") then return nil,"FORBIDDEN" end
  return true
end
return M
