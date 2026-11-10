local M={}
function M.status(ae2)
  return {ae2=ae2.energy,external={supported=false,unit="unknown"},reactors={supported=false,readOnly=true}}
end
return M
