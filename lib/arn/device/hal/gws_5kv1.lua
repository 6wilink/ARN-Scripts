--[[
Note: 
    Although GWS5Kv1 & GWS5Kv2 share the same methods and functions,
    this copy will let maintainer handle 2 types of hardware.

    by Qige <qigezhao@gmail.com>
    almost same as GWS5Kv2, it's a wrapper
]]--

--local DBG = print
local function DBG(msg) end

local gws_radio = require 'arn.device.hal.gws_5kv2'
return gws_radio