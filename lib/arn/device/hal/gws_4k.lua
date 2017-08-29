--[[
Note: 
    Although GWS4K share the same methods and functions,
    this copy will let maintainer handle 2 types of hardware.

    by Qige <qigezhao@gmail.com>
    2017.08.16 update_rt
]]--

local DBG = print
--local function DBG(msg) end

local ccff = require 'arn.utils.ccff'
local uhf = require 'arn.device.uhf'

local exec = ccff.execute
local vint = ccff.val.n
local sfmt = string.format
local ssub = string.sub
local slen = string.len

local gws_radio = {}

gws_radio.conf = {}
gws_radio.conf.val_length_max = 8

gws_radio.cmd = {}
gws_radio.cmd.rfinfo_clean  = 'echo > /tmp/.GWS4K.tmp'
gws_radio.cmd.rfinfo        = 'rfinfo 2>/dev/null > /tmp/.GWS4K.tmp'
gws_radio.cmd.region        = 'cat /tmp/.GWS4K.tmp 2> /dev/null | grep Region -A1 | grep [01]* -o'
gws_radio.cmd.channel       = 'cat /tmp/.GWS4K.tmp 2> /dev/null | grep Channel -A1 | grep [0-9]* -o'
gws_radio.cmd.txpower       = 'cat /tmp/.GWS4K.tmp 2> /dev/null | grep ^Tx | grep Power | grep [0-9\.]* -o'
gws_radio.cmd.chanbw        = 'uci get wireless.radio0.chanbw'

gws_radio.cmd.region_set    = 'setregion %s 2> /dev/null '
gws_radio.cmd.channel_set   = 'setchan %s 2> /dev/null '
gws_radio.cmd.txpower_set   = 'settxpwr %s 2> /dev/null '
gws_radio.cmd.chanbw_set    = 'setchanbw %s 2> /dev/null '
gws_radio.cmd.rxgain_set    = 'setrxgain %s 2> /dev/null '

function gws_radio.update_init()
    DBG(sfmt("GWS4K----> update_init()"))
    exec(gws_radio.cmd.rfinfo)
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
    DBG(sfmt("GWS4K> update_rt (@%d)", os.time()))
    local result = {}
    
    gws_radio.update_init()
    
    DBG(sfmt("GWS4K----> update_item() region"))
    result.region = gws_radio.update_item('region')
    
    DBG(sfmt("GWS4K----> update_item() channel"))
    result.channo = gws_radio.update_item('channel')
    result.freq = uhf.channel_to_freq(result.region, result.channo)
    
    DBG(sfmt("GWS4K----> update_item() txpower"))
    result.txpwr = gws_radio.update_item('txpower')
    
    DBG(sfmt("GWS4K----> update_item() chanbw"))
    result.chanbw = gws_radio.update_item('chanbw')
    
    --result.ts = os.time()
    return result
end

function gws_radio.SET_RT(key, value)
    local result = true
    DBG(sfmt("GWS4K> set_rt k=%s,value=%s (@%d)", key or '-', value or '-', os.time()))
    if (key == 'region') then
        exec(sfmt(gws_radio.cmd.region_set, value))
        result = false
    elseif (key == 'channel' or key == 'channo') then
        exec(sfmt(gws_radio.cmd.channel_set, value))
        result = false
    elseif (key == 'txpower' or key == 'txpwr') then
        exec(sfmt(gws_radio.cmd.txpower_set, value))
        result = false
    elseif (key == 'rxgain') then
        exec(sfmt(gws_radio.cmd.rxgain_set, value))
        result = false
    end
    gws_radio.rfinfo_clean()
    return result
end

return gws_radio