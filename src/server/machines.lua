-- Registry boundary: never invent a machine capability when no verified driver exists.
local M={}
function M.status() return {supported=false,machines={},reason="No verified 1.12.2 drivers configured"} end
function M.setEnabled() return nil,"unsupported" end
return M
