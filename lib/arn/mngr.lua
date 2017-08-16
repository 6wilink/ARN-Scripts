-- by Qige <qigezhao@gmail.com>

--[[
Notes:
    1. DO NOT call .SAFE_GET right after .SAFE_SET !!! Wait at least 1 second;
    2. DO NOT change any config or default value UNLESS you really know;
    3. 
LOG
    2017.07.31  .SAFE_GET|.SAFE_SET|/etc/arn-spec
    2017.08.01  return nil|realtime|cache|freq|filter|/etc/config/arn-spec
    2017.08.09  cache file|serialize|unserialize|vint|
                DBG|default|filter_chanbw|freq_to_channel|channel_to_freq|
                sfmt|ssplit
    2017.08.11  abb_rt|radio_cache|cache_expires_until
    2017.08.16  nw_thrpt|Util.Cache
]]--

-- DEBUG USE ONLY
--local DBG = print
local function DBG(msg) end

-- load Utilities
local Ccff          = require 'qutil.ccff'
local Cache         = require 'qutil.cache'
local Uhf           = require 'arn.uhf'

local exec          = Ccff.execute
local util_get      = Ccff.conf.get
local util_set      = Ccff.conf.set
local vint          = Ccff.val.n
local vlimit        = Ccff.val.limit
local ssplit        = Ccff.split
local trimr         = Ccff.trimr
local sfmt          = string.format

-- load ARN HAL Module
local dev_hal = require 'arn.hal_raw'

--[[
    Module:      Device Manager
    Maintainer:  Qige <qigezhao@gmail.com>
    Last Update: 2017.08.10
]]--
local dev_mngr = {}
dev_mngr.conf = {}
dev_mngr.conf.arn_spec          = 'arn-spec'
dev_mngr.conf.config            = 'arn'
dev_mngr.conf._cache_radio      = '/tmp/.arn-radio.cache'
dev_mngr.conf.valid_after_set   = 2
dev_mngr.conf.nw_ifname         = 'br-lan'
dev_mngr.conf.nw_cmd_fmt        = "cat /proc/net/dev | grep %s | awk '{print $2,$10}'"
dev_mngr.conf._cache_nw         = '/tmp/.arn-nw.cache'
dev_mngr.conf.nw_cache_intl     = 5

dev_mngr.default = {}
dev_mngr.default.chanbw         = 8
dev_mngr.default.chanbw_range   = '5 8 10 20'

dev_mngr.default.region_min     = 0
dev_mngr.default.region_max     = 1
dev_mngr.default.freq_min       = 470
dev_mngr.default.freq_max       = 700

dev_mngr.default.txpower_min    = 5
dev_mngr.default.txpower_max    = 33
dev_mngr.default.rxgain_min     = -30
dev_mngr.default.rxgain_max     = 30

dev_mngr.default.cache_timeout  = 30

--[[
Tasks:
    Read all common settings
ConfFiles:
    /etc/config/arn-spec
    /etc/config/arn
Parameters (with samples):
    chanbw:         "5 8 10 12 16 20 24"
    region_min:     0
    region_max:     1
    freq_min:       470
    freq_max:       790
    txpower_min:    9
    txpower_max:    33
]]--
dev_mngr.limit = {}
dev_mngr.limit.chanbw_range     = util_get(dev_mngr.conf.arn_spec,'v1','chanbw')        or dev_mngr.default.chanbw_range
dev_mngr.limit.region_min       = util_get(dev_mngr.conf.arn_spec,'v1','region_min')    or dev_mngr.default.region_min
dev_mngr.limit.region_max       = util_get(dev_mngr.conf.arn_spec,'v1','region_max')    or dev_mngr.default.region_max
dev_mngr.limit.freq_min         = util_get(dev_mngr.conf.arn_spec,'v1','freq_min')      or dev_mngr.default.freq_min
dev_mngr.limit.freq_max         = util_get(dev_mngr.conf.arn_spec,'v1','freq_max')      or dev_mngr.default.freq_max
dev_mngr.limit.txpower_min      = util_get(dev_mngr.conf.arn_spec,'v1','txpower_min')   or dev_mngr.default.txpower_min
dev_mngr.limit.txpower_max      = util_get(dev_mngr.conf.arn_spec,'v1','txpower_max')   or dev_mngr.default.txpower_max
dev_mngr.limit.rxgain_min       = util_get(dev_mngr.conf.arn_spec,'v1','rxgain_min')    or dev_mngr.default.rxgain_min
dev_mngr.limit.rxgain_max       = util_get(dev_mngr.conf.arn_spec,'v1','rxgain_max')    or dev_mngr.default.rxgain_max
dev_mngr.limit.cache_timeout    = util_get(dev_mngr.conf.arn_spec,'v1','cache_timeout') or dev_mngr.default.cache_timeout

-- for temporary use
dev_mngr.cache = {}
dev_mngr.cache.region           = nil -- cache region before filter_channel()


--[[
Tasks:
    1. Cache control
    2. Cache update & read
    3. Without filter, unsafe
]]--
function dev_mngr.kpi_cached_raw()
    DBG("--> kpi_cached_raw()")

    local result = {}
    local nw_counters, abb_safe_rt, radio_hal
    
    -- ARNAnalogBaseband need realtime result (return instantly)
    abb_safe_rt = dev_mngr.kpi_abb_safe_rt_raw()
    if ((not abb_safe_rt) or type(abb_safe_rt) ~= 'table') then abb_safe_rt = {} end
    abb_safe_rt.ts = nil

    -- Get cache, read cache.ts
    local cache_file = dev_mngr.conf._cache_radio
    local cache_timeout = vint(dev_mngr.limit.cache_timeout)
    local cache = Cache.LOAD_VALID(cache_file, cache_timeout)

    if (cache and next(cache)) then
        local cache_elapsed = os.time() - cache.ts
        DBG(sfmt("----+ cache ARN Radio valid used for %ds, max %ds", cache_elapsed, cache_timeout))
        radio_hal = cache
    else
        DBG("----+ cache ARN Radio timeout, require update right away")
        radio_hal = dev_mngr.kpi_radio_rt_raw()
        Cache.SAVE(cache_file, radio_hal)
    end
    if ((not radio_hal) or type(radio_hal) ~= 'table') then radio_hal = {} end
    radio_hal.ts = nil
    
    -- Device "br-lan"
    nw_thrpt = dev_mngr.kpi_nw_thrpt_calc()

    result.abb_safe_rt = abb_safe_rt
    result.radio_hal = radio_hal
    result.nw_thrpt = nw_thrpt
    return result
end

function dev_mngr.kpi_nw_counters_rt()
    local result = {}
    local cmd = sfmt(dev_mngr.conf.nw_cmd_fmt, dev_mngr.conf.nw_ifname)
    local counters = trimr(exec(cmd), 1) or '0 0'
    --print(counters)
    rxtx_bytes = ssplit(counters, ' ')
    result.rx = rxtx_bytes[1] or 0
    result.tx = rxtx_bytes[2] or 0
    result.ts = os.time()
    return result
end

function dev_mngr.calc_thrpt(bytes1, bytes2, elapsed)
    local bytes = 0
    if (bytes1 > bytes2) then
        bytes = bytes1 - bytes2
    else
        bytes = bytes2 - bytes1
    end
    if (elapsed < 0) then
        elapsed = 1
    elseif (elapsed == 0) then
        elapsed = 0.5 -- fix 'inf'
    end
    if (bytes < 0) then bytes = 0 - bytes end
    local bps = bytes * 8 / elapsed
    
    local thrpt
    if (bps > 1024 * 1024) then
        thrpt = sfmt("%.2f Mbps", (bps / 1024 / 1024))
    elseif (bps > 1024) then
        thrpt = sfmt("%.2f Kbps", (bps / 1024))
    else
        thrpt = sfmt("%.2f bps", bps)
    end
    return thrpt
end

--[[
Tasks:
    1. Network Counters history;
    2. Throughput calculation for multi-calling.
]]--
function dev_mngr.kpi_nw_thrpt_calc()
    DBG("------> kpi_nw_thrpt_calc()")
    local result = {}
    local nw_rxtx_rt = dev_mngr.kpi_nw_counters_rt()

    local cache_file = dev_mngr.conf._cache_nw
    DBG(sfmt("--------+ cache file: %s", cache_file))
    local cache = Cache.LOAD_VALID(cache_file, dev_mngr.conf.nw_cache_intl + 1)
    if (cache and next(cache)) then
        DBG("--------+ cache NW Thrpt valid")
        local nw_rxtx_last = cache
        local elapsed = (nw_rxtx_rt.ts or 0) - (nw_rxtx_last.ts or 0)
        result.rx = dev_mngr.calc_thrpt(nw_rxtx_rt.rx or 0, nw_rxtx_last.rx or 0, elapsed)
        result.tx = dev_mngr.calc_thrpt(nw_rxtx_rt.tx or 0, nw_rxtx_last.tx or 0, elapsed)
        if (elapsed >= dev_mngr.conf.nw_cache_intl) then        
            DBG(sfmt("--------+ Save NW Thrpt cache (rx=%s,tx=%s)", nw_rxtx_rt.rx, nw_rxtx_rt.tx))
            Cache.SAVE(cache_file, nw_rxtx_rt)
        end
    else
        DBG("--------+ Bad NW Thrpt cache")
        result.rx = '0.00 bps'
        result.tx = '0.00 bps'
        
        DBG(sfmt("--------+ Save NW Thrpt cache (rx=%s,tx=%s)", nw_rxtx_rt.rx, nw_rxtx_rt.tx))
        Cache.SAVE(cache_file, nw_rxtx_rt)
    end
    return result
end

--[[
Tasks:
    1. Read data via HAL
    2. Without filter, unsafe
]]--
function dev_mngr.kpi_abb_safe_rt_raw()
    DBG("------> kpi_abb_safe_rt_raw()")
    local abb_raw = dev_hal.HAL_GET_ABB_SAFE_RT()
    if (abb_raw) then
        DBG("------+ fresh result from HAL.AnalogBaseband (un-filtered) < noise=" .. abb_raw.noise or '-')
    else
        DBG("------+ NO result from HAL.AnalogBaseband")
        -- should keep old cache file content
        --Cache.CLEAN()
    end
    return abb_raw
end

--[[
Tasks:
    1. Read data via HAL
    2. Without filter, unsafe
]]--
function dev_mngr.kpi_radio_rt_raw()
    DBG("------> kpi_radio_rt_raw()")
    local radio_hal_raw = dev_hal.HAL_GET_RADIO_RT()
    if (radio_hal_raw) then
        DBG("------+ fresh result from HAL.ARNRadio (un-filtered)")
    else
        DBG("------+ NO result from HAL.ARNRadio")
        -- should keep old cache file content
        --local cache_file = dev_mngr.conf._cache_radio
        --Cache.CLEAN(cache_file)
    end
    return radio_hal_raw
end

--[[
Requires:
    Make sure you have filter_region() before filter_chnanel()
    to use dev_mngr.cache.region
Tasks:
    1. Limit frequency range;
    2. Convert frequency to channel number based on region
]]--
function dev_mngr.filter_channel(value)
    DBG(sfmt("--------> (FIXME) filter_channel(UHF c=%s)", value or '-'))
    local region = dev_mngr.cache.region
    local ch_min = Uhf.freq_to_channel(region, dev_mngr.limit.freq_min)
    local ch_max = Uhf.freq_to_channel(region, dev_mngr.limit.freq_max)
    return vlimit(value, ch_min, ch_max)
end

--[[
Limits:
    1. Region 0: 6 MHz/channel, center frequency start from 473, channel 14
    2. Region 1: 8 MHz/channel, center frequency start from 474, channel 21
]]--
function dev_mngr.filter_region(value)
    DBG(sfmt("--------> filter_region(r=%s)", value or '-'))
    local v = vint(value)
    local vmin = dev_mngr.limit.region_min
    local vmax = dev_mngr.limit.region_max
    DBG(sfmt("--------# region range = [min %s, max %s]", vmin, vmax))
    
    local region = vlimit(v, vmin, vmax)
    dev_mngr.cache.region = region
    return region
end

--[[
Unit Convert:
    1. 100mW: 9 to 20 dBm
    2. 200mW: 9 to 23 dBm
    3. 500mW: 9 to 24 dBm
    4. 2Watt: 9 to 33 dBm
    5. 8Watt: 9 to 38 dBm
]]--
function dev_mngr.filter_txpower(value)
    DBG(sfmt("--------> filter_txpower(p=%s)", value or '-'))
    local v = vint(value)
    local vmin = dev_mngr.limit.txpower_min
    local vmax = dev_mngr.limit.txpower_max
    DBG(sfmt("--------# txpower range = [min %s, max %s]", vmin, vmax))
    return vlimit(v, vmin, vmax)
end

function dev_mngr.filter_rxgain(value)
    DBG(sfmt("--------> filter_rxgain(p=%s)", value or '-'))
    local v = vint(value)
    local vmin = dev_mngr.limit.rxgain_min
    local vmax = dev_mngr.limit.rxgain_max
    DBG(sfmt("--------# rxgain range = [min %s, max %s]", vmin, vmax))
    return vlimit(v, vmin, vmax)
end

-- fetch chanbw from config file
-- read from list, default '5 8 10 20'
function dev_mngr.filter_chanbw(value)
    DBG(sfmt("--------> filter_chanbw(b=%s) < default is 8", value or '-'))    
    local bw = vint(value)
    local chanbw = dev_mngr.default.chanbw
    local range = dev_mngr.limit.chanbw_range
    DBG(sfmt("--------# chanbw range = list [%s]", range))
    local ranges = ssplit(range, ' ')
    for idx, val in pairs(ranges) do
        local v = vint(val)
        if (v == bw) then 
            DBG(sfmt("--------+ set chanbw to %d", bw))
            chanbw = value
            break
        end
    end
    return chanbw
end

function dev_mngr.filter_mode(value)
    local result = 'ear'
    if (value == 'CAR' or value == 'car') then
        result = 'car'
    elseif (value == 'MESH' or value == 'mesh') then
        result = 'mesh'
    end
    return result
end

function dev_mngr.filter_item(item, value)
    local result
    if (item == 'region') then
        result = dev_mngr.filter_region(value)
    elseif (item == 'channo') then
        result = dev_mngr.filter_channel(value)
    elseif (item == 'txpwr') then
        result = dev_mngr.filter_txpower(value)
    elseif (item == 'chanbw') then
        result = dev_mngr.filter_chanbw(value)
    elseif (item == 'rxgain') then
        result = dev_mngr.filter_rxgain(value)
    else
        result = value
    end
    return result
end

function dev_mngr.filter_item_append_unit(item, value)
    local result
    if (item == 'region') then
        local region = dev_mngr.filter_region(value)
        if (region > 0) then
            result = region .. ' (8M)'
        else
            result = region .. ' (6M)'
        end
    elseif (item == 'channo') then
        result = dev_mngr.filter_channel(value)
    elseif (item == 'txpwr') then
        result = dev_mngr.filter_txpower(value) .. ' dBm'
    elseif (item == 'chanbw') then
        result = dev_mngr.filter_chanbw(value) .. ' MHz'
    elseif (item == 'rxgain') then
        result = dev_mngr.filter_rxgain(value) .. ' db'
    elseif (item == 'freq') then
        result = value .. ' MHz'
    else
        result = value
    end
    return result
end

--[[
Range: 
    Public API
Tasks: 
    1. Wrapper of set_with_filter()
]]--
function dev_mngr.SAFE_SET(key, value)
    DBG(sfmt("> SAFE_SET(key=%s,value=%s)", key, value))
    return dev_mngr.set_with_filter(key, value)
end

--[[
Tasks:
    1. Filter user input before sent to HAL Layer
FIXME: 
    1. add all common commands/answers;
    2. If current value equals filtered value, do nothing.
]]--
function dev_mngr.set_with_filter(key, value)
    DBG("--> set_with_filter()")
    local result
    local val
    if (key == 'channel' or key == 'freq') then
        DBG("--+ set channel")
        local dev_hal = dev_mngr.kpi_cached_raw() or {}
        local radio_hal = dev_hal.radio_hal
        local region = dev_mngr.filter_region(radio_hal.region)
        
        local channel = value
        if (key == 'freq') then
            key = 'channel'
            local freq = value
            if (freq < dev_mngr.limit.freq_min or freq > dev_mngr.limit.freq_max) then
                DBG("--------+ Bad frequency")
                channel = nil
            else
                channel = Uhf.freq_to_channel(region, value)
            end
        end
        val = dev_mngr.filter_channel(channel)
        print(sfmt("set channel to %s (freq=%s)", val, Uhf.channel_to_freq(region, val)))
    elseif (key == 'region') then
        DBG("--+ set region")
        val = dev_mngr.filter_region(value)
        print(sfmt("set region to %s", val))
    elseif (key == 'txpower' or key == 'txpwr') then
        DBG("--+ set txpower")
        val = dev_mngr.filter_txpower(value)
        print(sfmt("set txpower to %s", val))
    elseif (key == 'chanbw') then
        DBG("--+ set chanbw")
        val = dev_mngr.filter_chanbw(value)
        print(sfmt("set chanbw to %s", val))
    else
        print(sfmt("unknown %s=%s", key, value))
    end
    -- set via HAL Layer
    DBG("--+ call HAL_SET()")
    result = dev_hal.HAL_SET_RT(key, val)
    if (result) then
        print(sfmt("err: set %s=%s failed", key, val))
    else
        DBG("--+ call save_config()")
        dev_mngr.save_config(key, val)
        -- timeout & clean cache after set
        local cache_file = dev_mngr.conf._cache_radio
        Cache.EXPIRES_UNTIL(cache_file, dev_mngr.conf.valid_after_set + dev_mngr.limit.cache_timeout)
    end
    return result
end

-- if region/channel/txpower/chanbw, save to config file
function dev_mngr.save_config(key, value)
    DBG(sfmt("--> save_config(): set %s=%s", key or '{k}', value or '{v}'))
    if (key == 'region') then
        DBG("--+ save config.region")
        util_set(dev_mngr.conf.config, 'v1', 'region', value)
    elseif (key == 'channel') then
        DBG("--+ save config.channel")
        util_set(dev_mngr.conf.config, 'v1', 'channel', value)
    elseif (key == 'txpower') then
        DBG("--+ save config.txpower")
        util_set(dev_mngr.conf.config, 'v1', 'txpower', value)
    elseif (key == 'chanbw') then
        DBG("--+ save config.chanbw")
        util_set(dev_mngr.conf.config, 'v1', 'chanbw', value)
    end
end

--[[
TODO:
    Handle return result
Range:
    Public API
Tasks:
    1. Get raw "table" via kpi_cached_raw()
    2. Pass filter before return
    3. Return string by user's request
]]--
function dev_mngr.SAFE_GET(with_unit)
    DBG("> SAFE_GET()")
    local result = {}
    local func = dev_mngr.filter_item

    DBG("+ get raw result (+cache)")
    local gws_raw = dev_mngr.kpi_cached_raw() or {}
    local abb_safe_rt = gws_raw.abb_safe_rt or {}
    local radio_hal = gws_raw.radio_hal or {}
    local nw_thrpt = gws_raw.nw_thrpt or {}

    -- filter each item before return
    DBG("+ start filter HAL.ABB result < noise=" .. abb_safe_rt.noise)
    result.abb_safe = {}
    for i,v in pairs(abb_safe_rt) do
        result.abb_safe[i] = func(i, v)
    end

    DBG("+ start filter HAL.ARNRadio result")
    if (with_unit) then func = dev_mngr.filter_item_append_unit end
    
    -- filter region first, to ENSURE filter_channel get right region cache value
    if (radio_hal.region) then func('region', radio_hal.region) end

    --table.sort(gws_raw, function(a, b) return (tonumber(a) > tonumber(b)) end)
    table.sort(gws_raw)
    result.radio_safe = {}
    for i,v in pairs(radio_hal) do
        result.radio_safe[i] = func(i, v)
    end
    
    -- safe rx/tx thrpt
    result.nw_thrpt = {}
    result.nw_thrpt.rx = nw_thrpt.rx or 0.01
    result.nw_thrpt.tx = nw_thrpt.tx or 0.01
    
    DBG("+ result is safe to use < noise=" .. result.abb_safe.noise)
    DBG("+ return result < freq=" .. result.radio_safe.freq)
    return result
end

return dev_mngr