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
]]--

-- DEBUG USE ONLY
--local DBG = print
local function DBG(msg) end

-- load Utilities
local serializer    = require 'qutil.serialize'
local ccff          = require 'qutil.ccff'
local uhf           = require 'arn.uhf'
local util_get      = ccff.conf.get
local util_set      = ccff.conf.set
local vint          = ccff.val.n
local vlimit        = ccff.val.limit
local ssplit        = ccff.split
local sfmt          = string.format

-- load ARN HAL Module
local dev_hal = require 'arn.hal_raw'

--[[
    Module:      Device Manager
    Maintainer:  Qige <qigezhao@gmail.com>
    Last Update: 2017.08.10
]]--
local dev_mngr = {}
dev_mngr.conf           = {}
dev_mngr.conf.arn_spec  = 'arn-spec'
dev_mngr.conf.config    = 'arn'
dev_mngr.conf._cache    = '/tmp/.arn.cache'

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

dev_mngr.default.cache_timeout  = 5

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
dev_mngr.cache.region = nil

-- Load & unserialize cache from file
function dev_mngr.cache_load()
    DBG("----> cache_load()")
    local cache_raw
    local cache_file = dev_mngr.conf._cache
    local cache_content = ccff.file.read(cache_file)
    if (cache_content) then
        cache_raw = serializer.unserialize(cache_content)
    end
    return cache_raw
end

-- Save cache with ts to file
-- @condition pass in 'table'
function dev_mngr.cache_save(cache)
    DBG("----> cache_save()")
    local cache_raw
    local cache_file = dev_mngr.conf._cache
    if (cache and type(cache) == 'table') then
        DBG("----+ save cache to file")
        cache.ts = os.time()
        cache_raw = serializer.serialize(cache)
        ccff.file.write(cache_file, cache_raw)
    else
        DBG("----+ NO or bad data, do nothing")
    end
end

function dev_mngr.cache_clean()
    DBG("----> cache_clean()")
    local cache_file = dev_mngr.conf._cache
    ccff.file.write(cache_file, '')
    dev_mngr.cache.region = nil
end

--[[
Tasks:
    1. Cache control
    2. Cache update & read
    3. Without filter, unsafe
]]--
function dev_mngr.kpi_cached_raw()
    DBG("--> kpi_cached_raw()")
    local radio_hal

    -- Get cache, read cache.ts
    local cache = dev_mngr.cache_load()
  
    -- Cache invalid or cache time out
    local cache_timeout = vint(dev_mngr.limit.cache_timeout)
    local now_ts = os.time() -- in seconds
    local cache_ts
    if (cache) then
        cache_ts = vint(cache.ts)
    else
        cache_ts = 0
    end  
    local cache_elapsed = now_ts - cache_ts
    
    if (cache_ts == 0 or cache_elapsed >= cache_timeout) then
        DBG("----+ cache timeout, require update right away")
        radio_hal = dev_mngr.kpi_realtime_raw()
        dev_mngr.cache_save(radio_hal)
    else
        DBG("----+ cache valid")
        radio_hal = cache
    end
    if ((not radio_hal) or type(radio_hal) ~= 'table') then radio_hal = {} end
    radio_hal.ts = nil
    return radio_hal
end

--[[
Tasks:
    1. Read data via HAL
    2. Without filter, unsafe
]]--
function dev_mngr.kpi_realtime_raw()
    DBG("------> kpi_realtime()")
    local radio_hal_raw = dev_hal.HAL_GET_RT()
    if (radio_hal_raw) then
        DBG("------+ fresh result from HAL (un-filtered)")
    else
        DBG("------+ NO result from HAL")
        -- should keep old cache file content
        --dev_mngr.cache_clean()
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
    local ch_min = uhf.freq_to_channel(region, dev_mngr.limit.freq_min)
    local ch_max = uhf.freq_to_channel(region, dev_mngr.limit.freq_max)
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
    DBG("> SAFE_SET()")
    return dev_mngr.set_with_filter(key, value)
end

--[[
Tasks:
    1. Filter user input before sent to HAL Layer
FIXME: 
    1. add all common commands/answers
]]--
function dev_mngr.set_with_filter(key, value)
    DBG("--> set_with_filter()")
    local result
    local val
    if (key == 'channel' or key == 'freq') then
        DBG("--+ set channel")
        local dev_hal = dev_mngr.kpi_cached_raw() or {}
        local region = dev_mngr.filter_region(dev_hal.region, value)
        local channel = value
        if (key == 'freq') then
            key = 'channel'
            local freq = value
            if (freq < dev_mngr.limit.freq_min or freq > dev_mngr.limit.freq_max) then
                DBG("--------+ Bad frequency")
                channel = nil
            else
                channel = uhf.freq_to_channel(region, value)
            end
        end
        val = dev_mngr.filter_channel(channel)
        print(sfmt("set channel to %s (freq=%s)", channel, uhf.channel_to_freq(region, channel)))
    elseif (key == 'region') then
        DBG("--+ set region")
        val = dev_mngr.filter_region(value)
        print(sfmt("set region to %s", val))
    elseif (key == 'txpower') then
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
        -- timeout & clean cache immediately
        dev_mngr.cache_clean()
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

    DBG("+ get raw result (+cache)")
    local gws_raw = dev_mngr.kpi_cached_raw() or {}

    -- filter each item before return
    DBG("+ start filter result")
    local func = dev_mngr.filter_item
    if (with_unit) then func = dev_mngr.filter_item_append_unit end
    
    -- filter region first, to ENSURE filter_channel get right region cache value
    if (gws_raw.region) then func('region', gws_raw.region) end

    --table.sort(gws_raw, function(a, b) return (tonumber(a) > tonumber(b)) end)
    for i,v in pairs(gws_raw) do
        result[i] = func(i, v)
    end
    DBG("+ result is safe to use")

    DBG("+ return result")
    return result
end

return dev_mngr