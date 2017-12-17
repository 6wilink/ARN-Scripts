--[[
Note:
    Although GWS5Kv1 & GWS5Kv2 share the same methods and functions,
    this copy will let maintainer handle 2 types of hardware.

    by Qige <qigezhao@gmail.com>
    2017.08.10 update_rt|set_rt
    2017.08.16 set_rt+return
BugList:
    20170816    #1  'rfinfo' maybe not output right region after 'setregion'
                    must run 'rfinfo; rfinfo' to get the right value
]]--

--local DBG = print
local function DBG(msg) end

local ccff = require 'arn.utils.ccff'
local uhf = require 'arn.device.uhf'

local exec = ccff.execute
local vint = ccff.val.n
local sfmt = string.format
local ssub = string.sub
local slen = string.len

local fread = ccff.file.read
local fwrite = ccff.file.write

local gws_radio = {}

gws_radio.conf = {}
gws_radio.conf.val_length_max = 8

gws_radio.cmd = {}
gws_radio.cmd.rfinfo_clean  = 'echo > /tmp/.GWS5Kv2.tmp'
gws_radio.cmd.rfinfo_lock   = '/tmp/.GWS5Kv2.lock'
gws_radio.cmd.rfinfo_wait   = 'sleep 1'
gws_radio.cmd.rfinfo        = 'echo > /tmp/.GWS5Kv2.tmp; `which gws5001app` rfinfo >/dev/null 2>&1; `which gws5001app` rfinfo 2>/dev/null > /tmp/.GWS5Kv2.tmp'
gws_radio.cmd.rfinfo_all    = 'cat /tmp/.GWS5Kv2.tmp 2>/dev/null'
gws_radio.cmd.region        = 'cat /tmp/.GWS5Kv2.tmp 2> /dev/null | grep Region | grep [01]* -o'
gws_radio.cmd.channel       = "cat /tmp/.GWS5Kv2.tmp 2> /dev/null | grep Chan: | awk '{print $2}'"
gws_radio.cmd.txpower       = 'cat /tmp/.GWS5Kv2.tmp 2> /dev/null | grep Tx | grep Power | grep [0-9\.]* -o'
gws_radio.cmd.chanbw        = 'cat /tmp/.GWS5Kv2.tmp 2> /dev/null | grep Chan | grep BW | grep [0-9]* -o'
gws_radio.cmd.rxgain        = 'cat /tmp/.GWS5Kv2.tmp 2> /dev/null | grep Rx | grep Gain | grep [0-9\.]* -o'

gws_radio.cmd.region_set    = '`which gws5001app` setregion %s 2> /dev/null; setregion %s 2> /dev/null; '
gws_radio.cmd.channel_set   = '`which gws5001app` setchan %s 2> /dev/null; setchan %s 2> /dev/null; '
gws_radio.cmd.txpower_set   = '`which gws5001app` settxpwr %s 2> /dev/null; settxpwr %s 2> /dev/null; '
gws_radio.cmd.chanbw_set    = '`which gws5001app` setchanbw %s 2> /dev/null; setchanbw %s 2> /dev/null; '
gws_radio.cmd.rxgain_set    = '`which gws5001app` setrxgain %s 2> /dev/null; setrxgain %s 2> /dev/null; '
gws_radio.cmd.txchain_set   = '`which gws5001app` rf%s 2> /dev/null; rf%s 2> /dev/null; '

function gws_radio.rfinfo_init()
    DBG(sfmt("GWS5Kv2----> update_init()"))
    -- v2.0 2017.10.19 enable read lock
    rfinfo_lock = fread(gws_radio.cmd.rfinfo_lock)
    if (rfinfo_lock ~= 'lock' and rfinfo_lock ~= 'lock\n') then
        print(sfmt('%80s', '> updating radio <'))
        DBG('note> updating device < lock:', rfinfo_lock)
        fwrite(gws_radio.cmd.rfinfo_lock, 'lock')
        exec(gws_radio.cmd.rfinfo)
        fwrite(gws_radio.cmd.rfinfo_lock, 'unlock')
        DBG('note> updated')
    else
        print(sfmt('%80s', '> device busy <'))
        lock_counts = 3
        while(rfinfo_lock == 'lock' or rfinfo_lock == 'lock\n') do
            exec(gws_radio.cmd.rfinfo_wait)
            rfinfo_lock = fread(gws_radio.cmd.rfinfo_lock)
            lock_counts = lock_counts - 1
            if (lock_counts < 0) then
                print(sfmt('%80s', 'solving dead-lock'))
                break
            end
        end
        fwrite(gws_radio.cmd.rfinfo_lock, 'unlock') -- FIXME
    end
    --print(exec(gws_radio.cmd.rfinfo_all))
end

function gws_radio.rfinfo_clean()
    exec(gws_radio.cmd.rfinfo_clean)
end

--[[
Tasks:
    1. Return each value by key;
    2. If result is too long, return first 8 chars.
]]--
function gws_radio.update_item(key)
    local result
    if (key == 'region') then
        result = exec(gws_radio.cmd.region)
    elseif (key == 'channel' or key == 'channo') then
        result = exec(gws_radio.cmd.channel)
    elseif (key == 'txpower' or key == 'txpwr') then
        result = exec(gws_radio.cmd.txpower)
    elseif (key == 'chanbw') then
        result = exec(gws_radio.cmd.chanbw)
    elseif (key == 'rxgain') then
        result = exec(gws_radio.cmd.rxgain)
    end
    -- limit return length
    local lmax = gws_radio.conf.val_length_max
    if (result and slen(result) > lmax) then
        result = ssub(result, 1, lmax)
    end
    return vint(result)
end

--[[
Tasks:
    1. Do cli call;
    2. Fetch each parameters from tmp file.
]]--
function gws_radio.UPDATE_RT()
    DBG(sfmt("GWS5Kv2> update_rt (@%d)", os.time()))
    local result = {}

    gws_radio.rfinfo_init()

    result.region = gws_radio.update_item('region') or '0'
    DBG(sfmt("GWS5Kv2----> update_item() region=%s", result.region))

    result.channo = gws_radio.update_item('channel') or '0'
    result.freq = uhf.channel_to_freq(result.region, result.channo)
    DBG(sfmt("GWS5Kv2----> update_item() channel=%s,freq=%s", result.channo, result.freq))

    result.txpwr = gws_radio.update_item('txpower') or '0'
    DBG(sfmt("GWS5Kv2----> update_item() txpower=%s", result.txpwr))

    result.chanbw = gws_radio.update_item('chanbw') or '0'
    DBG(sfmt("GWS5Kv2----> update_item() chanbw=%s", result.chanbw))

    result.rxgain = gws_radio.update_item('rxgain') or '0'
    DBG(sfmt("GWS5Kv2----> update_item() rxgain=%s", result.rxgain))

    --result.ts = os.time()
    --gws_radio.rfinfo_clean()
    return result
end

function gws_radio.SET_RT(key, value)
    local result = true
    DBG(sfmt("GWS5Kv2> set_rt k=%s,value=%s (@%d)", key or '-', value or '-', os.time()))
    if (key == 'region') then
        exec(sfmt(gws_radio.cmd.region_set, value, value))
        result = false
    elseif (key == 'channel' or key == 'channo') then
        -- fix "setchan" request channels when chanbw > 8, like "setchan 42 43", "setchan 43 44 45"
        -- but gws5001app not requesting this. by Qige 2017.12.17
        local v1 = tonumber(value) or 0
        local chanbw = tonumber(gws_radio.update_item('chanbw')) or 0
        local channels
        if (chanbw > 8) then
            local v2 = v1 + 1
            channels = sfmt('%s %s', v1 or '', v2 or '')
        elseif (chanbw > 16) then
            local v2 = v1 + 1
            local v3 = v2 + 1
            channels = sfmt('%s %s %s', v1, v2, v3)
        else
            channels = value
        end
        exec(sfmt(gws_radio.cmd.channel_set, value, channels))
        result = false
    elseif (key == 'txpower' or key == 'txpwr') then
        exec(sfmt(gws_radio.cmd.txpower_set, value, value))
        result = false
    elseif (key == 'chanbw') then
        exec(sfmt(gws_radio.cmd.chanbw_set, value, value))
        result = false
    elseif (key == 'rxgain') then
        exec(sfmt(gws_radio.cmd.rxgain_set, value, value))
        result = false
    elseif (key == 'tx' or key == 'rf') then -- 'gws5001app rfon|rfoff'
        exec(sfmt(gws_radio.cmd.txchain_set, value, value))
        result = false
    end
    gws_radio.rfinfo_clean()
    return result
end

return gws_radio
