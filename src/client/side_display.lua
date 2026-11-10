-- Side display consumes only the status heartbeat; no stock traffic or control.
return {new=function() return {tick=function() end,touch=function() end} end}
