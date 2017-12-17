-- by Qige <qigezhao@gmail.com>

--[[
Notes:
    1. DO NOT call .SAFE_GET right after .SAFE_SET !!! Wait at least 2 seconds;
    2. DO NOT change any config or default value UNLESS you really sure;
    3. ARN.Mngr provide Cache control|RARP|Save config|Calc thrpt|Filter input/output;
    4. DO NOT USE "next()" !!!: "local pkt = {}; if (pkt and next(pkt)) then print('it is a table') end"
LOG
    2017.07.31  .SAFE_GET|.SAFE_SET|/etc/arn-spec
    2017.08.01  return nil|realtime|cache|freq|filter|/etc/config/arn-spec
    2017.08.09  cache file|serialize|unserialize|vint|
                DBG|default|filter_chanbw|freq_to_channel|channel_to_freq|
                sfmt|ssplit
    2017.08.11  abb_rt|radio_cache|cache_expires_until
    2017.08.16  nw_thrpt|Util.Cache|display timeout|+4K

    2017.08.18  re-write after ARN-TPC
]]--

-- DEBUG USE ONLY
--local DBG = print
local function DBG(msg) end

-- load Utilities
local Uhf           = require 'arn.device.uhf'
local Ccff          = require 'arn.utils.ccff'
local Cache         = require 'arn.utils.cache'

local exec          = Ccff.execute
local conf_get      = Ccff.conf.get
local util_set      = Ccff.conf.set
local vint          = Ccff.val.n
local vlimit        = Ccff.val.limit
local ssplit        = Ccff.split
local trimr         = Ccff.trimr
local is_array      = Ccff.val.is_array
local in_list       = Ccff.val.in_list
local sfmt          = string.format
local sgsub         = string.gsub
local slen          = string.len
local ssub          = string.sub

-- load ARN HAL Module
local DEV_HAL = require 'arn.device.hal.hal_raw'

--[[
    Module:      Device Manager
    Maintainer:  Qige <qigezhao@gmail.com>
    Last Update: 2017.08.10
]]--
local dev_mngr = {}
dev_mngr.conf = {}
dev_mngr.conf.arn_spec          = 'arn-spec'
dev_mngr.conf.config            = 'arn'

dev_mngr.conf.fcache_set_expiry = 3

--dev_mngr.conf.nw_ifname         = 'br-lan'
dev_mngr.conf.nw_eth0_cmd        = "cat /proc/net/dev | grep eth0 | awk '{print $2,$10}'"
dev_mngr.conf.nw_brlan_cmd        = "cat /proc/net/dev | grep br-lan | awk '{print $2,$10}'"
dev_mngr.conf.nw_wlan0_cmd        = "cat /proc/net/dev | grep wlan0 | awk '{print $2,$10}'"
dev_mngr.conf.nw_cache_intl     = 5

dev_mngr.conf.fcache_radio      = '/tmp/.arn-cache.radio'
dev_mngr.conf.fcache_nw         = '/tmp/.arn-cache.nw'

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

dev_mngr.default.cache_timeout  = 10

dev_mngr.default.rarp_timeout   = 300

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
dev_mngr.limit.chanbw_range     = conf_get(dev_mngr.conf.arn_spec,'v1','chanbw')        or dev_mngr.default.chanbw_range
dev_mngr.limit.region_min       = conf_get(dev_mngr.conf.arn_spec,'v1','region_min')    or dev_mngr.default.region_min
dev_mngr.limit.region_max       = conf_get(dev_mngr.conf.arn_spec,'v1','region_max')    or dev_mngr.default.region_max
dev_mngr.limit.freq_min         = conf_get(dev_mngr.conf.arn_spec,'v1','freq_min')      or dev_mngr.default.freq_min
dev_mngr.limit.freq_max         = conf_get(dev_mngr.conf.arn_spec,'v1','freq_max')      or dev_mngr.default.freq_max

dev_mngr.limit.txpower_min      = conf_get(dev_mngr.conf.arn_spec,'v1','txpower_min')   or dev_mngr.default.txpower_min
dev_mngr.limit.txpower_max      = conf_get(dev_mngr.conf.arn_spec,'v1','txpower_max')   or dev_mngr.default.txpower_max
dev_mngr.limit.rxgain_min       = conf_get(dev_mngr.conf.arn_spec,'v1','rxgain_min')    or dev_mngr.default.rxgain_min
dev_mngr.limit.rxgain_max       = conf_get(dev_mngr.conf.arn_spec,'v1','rxgain_max')    or dev_mngr.default.rxgain_max

dev_mngr.limit.cache_timeout    = conf_get(dev_mngr.conf.arn_spec,'v1','cache_timeout') or dev_mngr.default.cache_timeout

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
    local nw_thrpt, abb_safe_rt, radio_hal

    -- ARNAnalogBaseband need realtime result (return instantly)
    abb_safe_rt = dev_mngr.kpi_abb_safe_rt_raw()
    if (not is_array(abb_safe_rt)) then abb_safe_rt = {} end
    abb_safe_rt.ts = nil

    -- Get cache, read cache.ts
    local cache_elapsed = 0
    local cache_file = dev_mngr.conf.fcache_radio
    local cache_timeout = vint(dev_mngr.limit.cache_timeout)

    local cache = Cache.LOAD_VALID(cache_file, cache_timeout)
    if (is_array(cache)) then
        cache_elapsed = os.time() - (cache.ts or 0)
        radio_hal = cache
    else
        DBG("----+ cache ARN Radio timeout, require update right away")
        radio_hal = dev_mngr.kpi_radio_rt_raw()

        DBG(sfmt("--------# region=%s", (radio_hal and radio_hal.region) or '-'))
        Cache.SAVE(cache_file, radio_hal)
    end
    if (not is_array(radio_hal)) then radio_hal = {} end

    -- add Timestamp
    radio_hal.elapsed = cache_elapsed
    radio_hal.timeout = cache_timeout
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
    local cmd = sfmt("%s; %s; %s", dev_mngr.conf.nw_eth0_cmd, dev_mngr.conf.nw_brlan_cmd, dev_mngr.conf.nw_wlan0_cmd)
    local counters = exec(cmd) or '0 0'
    --print(counters)
    rxtx_bytes = ssplit(counters, ' \\\n')

    result.rx = 0
    result.tx = 0
    if (is_array(rxtx_bytes)) then
        if (#rxtx_bytes >= 6) then
            result.rx = rxtx_bytes[1] + rxtx_bytes[3] + rxtx_bytes[5]
            result.tx = rxtx_bytes[2] + rxtx_bytes[4] + rxtx_bytes[6]
        elseif (#rxtx_bytes >= 2) then
            result.rx = rxtx_bytes[1]
            result.tx = rxtx_bytes[2]
        end
    end
    result.ts = os.time()
    return result
end

function dev_mngr.calc_thrpt(bytes1, bytes2, elapsed)
    local thrpt
    -- filter elapsed
    if (elapsed <= 0) then
        elapsed = 0.5 -- fix 'inf'
    end

    local bytes = bytes2 - bytes1
    if (bytes < 0) then bytes = 0 - bytes end

    local thrpt = tonumber(sfmt("%.0f", bytes * 8 / elapsed))

    --[[
    if (bps > 1024 * 1024) then
        thrpt = sfmt("%.2f Mbps", (bps / 1024 / 1024))
    elseif (bps > 1024) then
        thrpt = sfmt("%.2f Kbps", (bps / 1024))
    else
        thrpt = sfmt("%.2f bps", bps)
    end
    ]]--
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

    local cache_file = dev_mngr.conf.fcache_nw
    DBG(sfmt("--------+ cache file: %s", cache_file))
    local cache = Cache.LOAD_VALID(cache_file, dev_mngr.conf.nw_cache_intl + 1)
    if (is_array(cache)) then
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
        result.rx = 0
        result.tx = 0

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
    local abb_raw = DEV_HAL.HAL_GET_ABB_SAFE_RT()
    if (is_array(abb_raw)) then
        DBG("------+ fresh result from HAL.AnalogBaseband (un-filtered) < noise=" .. abb_raw.noise or '-')
    else
        DBG("------+ NO result from HAL.AnalogBaseband")
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
    local radio_hal_raw = DEV_HAL.HAL_GET_RADIO_RT()
    if (is_array(radio_hal_raw)) then
        --table.sort(radio_hal_raw)
        DBG("------+ fresh result from HAL.ARNRadio (un-filtered)")
    else
        DBG("------+ NO result from HAL.ARNRadio")
        -- should keep old cache file content
        --local cache_file = dev_mngr.conf.fcache_radio
        --Cache.CLEAN(cache_file)
    end
    return radio_hal_raw
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

    -- save to filter channo/channel
    local region = vlimit(v, vmin, vmax)
    dev_mngr.cache.region = region
    return region
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

function dev_mngr.filter_freq(value)
    local f_min = dev_mngr.limit.freq_min
    local f_max = dev_mngr.limit.freq_max
    return vlimit(value, f_min, f_max)
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
    local bw = value
    local range = dev_mngr.limit.chanbw_range
    local chanbw = dev_mngr.default.chanbw
    if (bw and in_list(range, ' ', bw)) then
        chanbw = bw
    end
    DBG(sfmt("--------# chanbw range = chanbw/list [%s/%s]", chanbw, range))
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

function dev_mngr.filter_tx(value)
    local result = 'off'
    if (value == 'on' or value == 'ON' or value == '1' or value == 1) then
        result = 'on'
    end
    return result
end

function dev_mngr.filter_item(item, value)
    local result
    if (item == 'region') then
        result = dev_mngr.filter_region(value)
    elseif (item == 'channo' or item == 'channel') then
        result = dev_mngr.filter_channel(value)
    elseif (item == 'txpwr' or item == 'txpower') then
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
        if (region < 1) then
            result = region .. ' (US)'
        else
            result = region .. ' (CN)'
        end
    elseif (item == 'channo' or item == 'channel') then
        result = dev_mngr.filter_channel(value)
    elseif (item == 'txpwr' or item == 'txpower') then
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
    return tostring(result)
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
    2. If current value equals filtered value, do nothing.
FIXME:
    1. add all common commands/answers;
]]--
function dev_mngr.set_with_filter(key, value)
    DBG("--> set_with_filter()")
    local result
    local val

    local dev_hal = dev_mngr.kpi_cached_raw() or {}
    local radio_hal = dev_hal.radio_hal
    if (key == 'channel' or key == 'freq') then
        DBG("--+ set channel")
        local region = dev_mngr.filter_region(radio_hal.region)

        local channel = value
        if (key == 'freq') then
            key = 'channel'
            channel = Uhf.freq_to_channel(region, dev_mngr.filter_freq(value))
        end
        val = dev_mngr.filter_channel(channel)

        if (val == radio_hal.channo or val == radio_hal.channel) then
            return key, val
        end

        print(sfmt("set channel to %s (freq=%s)", val, Uhf.channel_to_freq(region, val)))
    elseif (key == 'region') then
        DBG("--+ set region")
        val = dev_mngr.filter_region(value)

        if (val == radio_hal.region) then return false end

        print(sfmt("set region to %s", val))
    elseif (key == 'txpower' or key == 'txpwr') then
        DBG("--+ set txpower")
        val = dev_mngr.filter_txpower(value)

        if (val == radio_hal.txpwr or val == radio_hal.txpower) then
            return key, val
        end

        print(sfmt("set txpower to %s", val))
    elseif (key == 'chanbw') then
        DBG("--+ set chanbw")
        val = dev_mngr.filter_chanbw(value)

        if (val == radio_hal.chanbw) then
            return key, val
        end

        print(sfmt("set chanbw to %s", val))
    elseif (key == 'tx') then
        DBG("--+ set tx chain")
        val = dev_mngr.filter_tx(value)

        print(sfmt("set tx to %s", val))
    else
        -- transparent through
        print(sfmt("unknown %s=%s", key, value))
    end

    -- set via HAL Layer
    -- when done, save to config file
    DBG("--+ call HAL_SET()")
    result = DEV_HAL.HAL_SET_RT(key, val)
    if (result) then
        DBG(sfmt("err: set %s=%s failed", key, val))
    else
        if (key ~= 'tx') then
            DBG(sfmt("--+ call save_config(k=%s,v=%s)", key, value))
            dev_mngr.save_config(key, val)
            -- timeout & clean cache after set
            local cache_file = dev_mngr.conf.fcache_radio
            Cache.EXPIRES_UNTIL(cache_file, dev_mngr.conf.fcache_set_expiry, dev_mngr.limit.cache_timeout)
        end
    end
    return key, val
end

-- if region/channel/txpower/chanbw, save to config file
function dev_mngr.save_config(key, value)
    DBG(sfmt("--> save_config(): set %s=%s", key or '{k}', value or '{v}'))
    if (key == 'region') then
        DBG("--+ save config.region")
        util_set(dev_mngr.conf.config, 'v1', 'region', value)
    elseif (key == 'channel' or key == 'channo') then
        DBG("--+ save config.channel")
        util_set(dev_mngr.conf.config, 'v1', 'channel', value)
    elseif (key == 'txpower' or key == 'txpwr') then
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
    local gws_raw       = dev_mngr.kpi_cached_raw()     or {}
    local abb_safe_rt   = gws_raw.abb_safe_rt           or {}
    local radio_hal     = gws_raw.radio_hal             or {}
    local nw_thrpt      = gws_raw.nw_thrpt              or {}

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
    --table.sort(gws_raw)
    result.radio_safe = {}
    for i,v in pairs(radio_hal) do
        result.radio_safe[i] = func(i, v)
    end

    -- safe rx/tx thrpt
    result.nw_thrpt = {}
    result.nw_thrpt.rx = nw_thrpt.rx or 0.01
    result.nw_thrpt.tx = nw_thrpt.tx or 0.01

    DBG("+ result is safe to use < noise=" .. result.abb_safe.noise)
    DBG("+ return result < freq=" .. (result.radio_safe.freq or '-'))
    return result
end


return dev_mngr
