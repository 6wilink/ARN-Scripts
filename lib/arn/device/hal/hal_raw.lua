-- by Qige <qigezhao@gmail.com>
-- 2017.08.01 hw_platform|init|HAL_SET_RT|HAL_GET_RT
-- 2017.08.16 GWS4K|GWS5K|cmd_interval

local ccff = require 'arn.utils.ccff'
local exec          = ccff.execute
local file_read     = ccff.file.read
local file_write    = ccff.file.write
local vint          = ccff.val.n
local shas          = ccff.has
local sfmt          = string.format
local sfind         = string.find

--local DBG = print
local function DBG(msg) end


local gws_raw = {}

gws_raw.abb = require 'arn.device.hal.gws_abb'
gws_raw.Util_GWS3K      = require 'arn.device.hal.gws_3k'
gws_raw.Util_GWS4K      = require 'arn.device.hal.gws_4k'
gws_raw.Util_GWS5Kv1    = require 'arn.device.hal.gws_5kv1'
gws_raw.Util_GWS5Kv2    = require 'arn.device.hal.gws_5kv2'

gws_raw.conf = {}
gws_raw.conf.cmd_cpu        = 'cat /proc/cpuinfo | grep system'
gws_raw.conf.cmd_device     = 'ls /dev/gws* 2>/dev/null'
gws_raw.conf.cmd_interval   = 5
gws_raw.conf.cmd_ts_file    = '/tmp/.hal-cmd-ts.tmp'

gws_raw.cache = {}
gws_raw.cache.hw_platform   = nil

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
    if (shas(cpu_raw, 'QCA9533')) then
        cpu = 'QCA9533'
        hw_arch = 'GWS5Kv2'    
    elseif (shas(cpu_raw, 'AR9344')) then
        cpu = 'AR9344'
        -- GWS5Kv1-9344
        if (shas(dev_raw, 'gws5001Dev')) then
            dev = 'gws5001Dev'
            hw_arch = 'GWS5Kv1'
        end
    -- GWS4K-9330
    elseif (shas(cpu_raw, 'AR9330')) then
        cpu = 'AR9330'
        hw_arch = 'GWS4K'
    -- GWS3K-7130
    elseif (shas(cpu_raw, 'AR7130')) then
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

function gws_raw.get_last_cmd_ts()
    local f = gws_raw.conf.cmd_ts_file
    return file_read(f)
end

function gws_raw.set_last_cmd_ts(ts)
    local f = gws_raw.conf.cmd_ts_file
    file_write(f, ts)
end

function gws_raw.init()
    DBG(sfmt("hal gws-raw----> init()"))
    if (not gws_raw.cache.hw_platform) then
        DBG(sfmt("hal gws-raw----+ un-initialized"))
        gws_raw.cache.hw_platform = gws_raw.hw_platform()
    end
end

--[[
Tasks:
    1. SET needs interval;
    2. Return error when too frequently.
]]--
function gws_raw.HAL_SET_RT(key, value)
    local result
    DBG(sfmt("hal radio> HAL_SET_RT k=[%s],v=[%s] (@%d)", key or '-', value or '-', os.time()))

    -- 5K/4K/3K all needs SET interval
    gws_raw.init()
    
    -- check Last Command TS first
    local cmd_interval = gws_raw.conf.cmd_interval
    local now_ts = os.time()
    local last_cmd_ts = vint(gws_raw.get_last_cmd_ts()) or 0
    local cmd_gap = now_ts - last_cmd_ts    
    DBG(sfmt('hal> now=%s, last=%s, interval=%s', now_ts, last_cmd_ts, cmd_interval))
    -- ARNRadio related settings
    local hw_platform = gws_raw.cache.hw_platform
    if (hw_platform == 'GWS5Kv1') then
        if (cmd_gap >= cmd_interval) then    
            DBG(sfmt('hal> last command finished'))
            gws_raw.set_last_cmd_ts(os.time())
            result = gws_raw.Util_GWS5Kv1.SET_RT(key, value)
        else
            result = 'hal> wait for last command finish'
            print(result)
        end
    elseif (hw_platform == 'GWS5Kv2') then
        if (cmd_gap >= cmd_interval) then    
            DBG(sfmt('hal> last command finished'))
            gws_raw.set_last_cmd_ts(os.time())
            result = gws_raw.Util_GWS5Kv2.SET_RT(key, value)
        else
            result = 'hal> wait for last command finish'
            print(result)
        end
    elseif (hw_platform == 'GWS4K') then
        if (cmd_gap >= cmd_interval) then    
            DBG(sfmt('hal> last command finished'))
            gws_raw.set_last_cmd_ts(os.time())
            result = gws_raw.Util_GWS4K.SET_RT(key, value)
        else
            result = 'hal> wait for last command finish'
            print(result)
        end
    else
        if (cmd_gap >= cmd_interval) then    
            DBG(sfmt('hal> last command finished'))
            gws_raw.set_last_cmd_ts(os.time())
            result = gws_raw.Util_GWS3K.SET_RT(key, value)
        else
            result = 'hal> wait for last command finish'
            print(result)
        end
    end
    return result
end

function gws_raw.HAL_GET_ABB_SAFE_RT()
    local result = {}
    DBG(sfmt("hal abb> HAL_GET_RT (@%d)", os.time()))
    
    local result = gws_raw.abb.update_safe_rt()
    
    -- add hardware platform to result
    if ((not result) or (type(result) ~= 'table')) then
        result = {}
    end
    result.hw_ver = hw_platform
    return result
end

--[[
Tasks: 
    1. Dismiss hardware platform related query methods;
    2. Do query, & return realtime value;
    3. Default platform is GWS3K (defined since 2011).
]]--
function gws_raw.HAL_GET_RADIO_RT()
    local result = {}
    DBG(sfmt("hal radio> HAL_GET_RT (@%d)", os.time()))
    
    gws_raw.init()
    local hw_platform = gws_raw.cache.hw_platform
    DBG(sfmt("hal gws-raw----> %s update_rt()", hw_platform))
    if (hw_platform == 'GWS5Kv1') then
        result = gws_raw.Util_GWS5Kv1.UPDATE_RT(key)
    elseif (hw_platform == 'GWS5Kv2') then
        result = gws_raw.Util_GWS5Kv2.UPDATE_RT(key)
    elseif (hw_platform == 'GWS4K') then
        result = gws_raw.Util_GWS4K.UPDATE_RT(key)
    else
        result = gws_raw.Util_GWS3K.UPDATE_RT(key)
    end
    
    -- add hardware platform to result
    if ((not result) or (type(result) ~= 'table')) then
        result = {}
    end
    result.hw_ver = hw_platform
    
    return result
end

return gws_raw