-- by Qige <qigezhao@gmail.com>
-- 2017.08.01 hw_platform|init|HAL_SET_RT|HAL_GET_RT

local ccff = require 'qutil.ccff'
local exec = ccff.execute
local sfmt = string.format
local sfind = string.find

--local DBG = print
local function DBG(msg) end

local function string_has(str, key)
    local p1, p2 = sfind(str, key)
    if (p1 ~= nil) then
        return true
    end
    return false
end

local gws_raw = {}

gws_raw.abb = require 'arn.gws_abb'
gws_raw.Util_GWS3K = require 'arn.gws_3k'
gws_raw.Util_GWS4K = require 'arn.gws_4k'
gws_raw.Util_GWS5Kv1 = require 'arn.gws_5kv1'
gws_raw.Util_GWS5Kv2 = require 'arn.gws_5kv2'

gws_raw.conf = {}
gws_raw.conf.cmd_cpu = 'cat /proc/cpuinfo | grep system'
gws_raw.conf.cmd_device = 'ls /dev/gws* 2>/dev/null'

gws_raw.cache = {}
gws_raw.cache.hw_platform = nil

--[[
Return:
    GWS5Kv2|GWS5Kv1|GWS4K|GWS3K|(Unknown)
CPU Types: 
    1. GWS5Kv2:    AR9531+5001
    2. GWS5Kv1:    AR9344+5001
    3. GWS4K:      AR9330
    4. GWS3K:      AR7130+9220+1100
]]--
function gws_raw.hw_platform()
    DBG(sfmt("hal gws-raw--------> hw_platform()"))
    local hw_arch = nil

    local cpu, dev
    local cpu_raw = exec(gws_raw.conf.cmd_cpu)
    local dev_raw = exec(gws_raw.conf.cmd_device)

    -- GWS5Kv2-9531
    if (string_has(cpu_raw, 'QCA9533')) then
        cpu = 'QCA9533'
        hw_arch = 'GWS5Kv2'    
    elseif (string_has(cpu_raw, 'AR9344')) then
        cpu = 'AR9344'
        -- GWS5Kv1-9344
        if (string_has(dev_raw, 'gws5001Dev')) then
            dev = 'gws5001Dev'
            hw_arch = 'GWS5Kv1'
        end
    -- GWS4K-9330
    elseif (string_has(cpu_raw, 'AR9330')) then
        cpu = 'AR9330'
        hw_arch = 'GWS4K'
    -- GWS3K-7130
    elseif (string_has(cpu_raw, 'AR7130')) then
        cpu = 'AR7130'
        hw_arch = 'GWS3K'
    else
        cpu = '-'
        hw_arch = '(Unknown)'
    end

    --DBG(sfmt("hal gws-raw--------+ cpu_raw=%s,arch_raw=%s", cpu_raw, dev_raw))
    DBG(sfmt("hal gws-raw--------+ cpu=%s,arch=%s", cpu, hw_arch))
    return hw_arch
end

function gws_raw.init()
    DBG(sfmt("hal gws-raw----> init()"))
    if (not gws_raw.cache.hw_platform) then
        DBG(sfmt("hal gws-raw----+ un-initialized"))
        gws_raw.cache.hw_platform = gws_raw.hw_platform()
    end
end

-- TODO:
-- Verify platform
-- Ensure command binary file exists
-- Execute command
function gws_raw.HAL_SET_RT(key, value)
    DBG(sfmt("hal gws-raw> HAL_SET_RT k=[%s],v=[%s] (@%d)", key or '-', value or '-', os.time()))
    
    gws_raw.init()
    local hw_platform = gws_raw.cache.hw_platform
    if (hw_platform == 'GWS5Kv1') then
        result = gws_raw.Util_GWS5Kv1.set_rt(key, value)
    elseif (hw_platform == 'GWS5Kv2') then
        result = gws_raw.Util_GWS5Kv2.set_rt(key, value)
    elseif (hw_platform == 'GWS4K') then
        result = gws_raw.Util_GWS4K.set_rt(key, value)
    else
        result = gws_raw.Util_GWS3K.set_rt(key, value)
    end
end

--[[
Tasks: 
    1. Dismiss hardware platform related query methods;
    2. Do query, & return realtime value;
    3. Default platform is GWS3K (defined since 2011).
]]--
function gws_raw.HAL_GET_RT()
    local result
    DBG(sfmt("hal gws-raw> HAL_GET_RT (@%d)", os.time()))
    
    gws_raw.init()
    local hw_platform = gws_raw.cache.hw_platform
    if (hw_platform == 'GWS5Kv1') then
        result = gws_raw.Util_GWS5Kv1.update_rt(key)
    elseif (hw_platform == 'GWS5Kv2') then
        result = gws_raw.Util_GWS5Kv2.update_rt(key)
    elseif (hw_platform == 'GWS4K') then
        result = gws_raw.Util_GWS4K.update_rt(key)
    else
        result = gws_raw.Util_GWS3K.update_rt(key)
    end
    
    -- add hardware platform to result
    if ((not result) or (type(result) ~= 'table')) then
        result = {}
    end
    result.hw_ver = hw_platform
    
    return result
end

return gws_raw