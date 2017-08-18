--[[
VERIFIED @ 2017.08.14
    by Qige <qigezhao@gmail.com>
History:
    2017.06.19 import abb from Proto-EC54S
    2017.08.10 gws_abb|indent
    2017.08.11 update_safe_rt|mesh_id
    2017.08.14 bitrate
TODO:
    1. set()
]]--

-- DEBUG USE ONLY
--local DBG = print
local function DBG(msg) end

local iwinfo = require "iwinfo"

local ccff = require "qutil.ccff"
local fget  = ccff.conf.get
local fset  = ccff.conf.set
local s     = ccff.val.s
local n     = ccff.val.n
local exec  = ccff.execute
local trimr = ccff.trimr

local ts    = os.time
local out   = io.write
local prt   = print
local sfmt  = string.format
local suc   = string.upper
local tbl_push = table.insert


local gws_abb = {}

gws_abb.cmd = {}
gws_abb.cmd.wmac        = 'cat /sys/class/net/wlan0/address 2>/dev/null | tr -d "\n"'
gws_abb.cmd.mesh_id     = 'uci get wireless.@wifi-iface[0].mesh_id 2> /dev/null'

-- FIXME: should be read from config file
gws_abb.conf = {}
gws_abb.conf.dev        = 'wlan0'
gws_abb.conf.api        = 'nl80211'
gws_abb.conf.chanbw     = fget('wireless', 'radio0', 'chanbw') or 8

-- limitations
gws_abb.bar = {}
gws_abb.bar.rf_val_min      = -110
gws_abb.bar.peer_inactive   = 3000

-- .iw, .param, .wmac
gws_abb.cache = {}
gws_abb.cache.iw = nil
gws_abb.cache.wmac = nil

--[[
Tasks:
    1. If iw is initialized, do dothing;
    2. If not, init by 'iwinfo'.
]]--
function gws_abb.init()
    DBG('hal gws_abb--------> init()')
	local iw = gws_abb.cache.iw
	if (not iw) then
		local api = gws_abb.conf.api or 'nl80211'
		gws_abb.cache.iw = iwinfo[api]
	end
    local wmac = gws_abb.cache.wmac
    if (not wmac) then
        gws_abb.wmac()
    end
end

--Read WLAN0 MAC in cli
function gws_abb.wmac()
    DBG('hal gws_abb--------> wmac()')
    local wmac_cmd = gws_abb.cmd.wmac
    local wmac = ccff.execute(wmac_cmd)
    DBG(sfmt('hal gws_abb--------# wmac=[%s]', wmac))
    gws_abb.cache.wmac = wmac
    return wmac
end

function gws_abb.mesh_id(mode)
    local mesh_id = exec(gws_abb.cmd.mesh_id) or '--- '
    return trimr(mesh_id, 1)
end

--[[
TODO:
    1. All settings: chanbw|ssid|mode
]]--
function gws_abb.set(key, value)
    print(sfmt('%80s', '### {ABB} NOT VERIFIED SINCE 2017.08.10 > set()### '))
    DBG(sfmt('hal gws_abb----> (TODO) set(k=%s,v=%s)', key, value))

    local cmd
    if (key == 'siteno') then
        DBG(sfmt('hal gws_abb------+ set siteno=%s', value))
        fset('ec54s','v2','siteno', value)
    elseif (key == 'mode') then
        if (value == 'car' or value == 'CAR') then
            cmd = 'config_car; arn_car\n'
        elseif (value == 'ear' or value == 'EAR') then
            cmd = 'config_ear; arn_ear\n'
        elseif (value == 'mesh' or value == 'MESH') then
            cmd = 'config_mesh; arn_mesh\n'
        end
    elseif (key == 'chanbw') then
        cmd = sfmt('setchanbw %d\n', value)
    elseif (key == 'wifi') then
        if (value == '0') then
            cmd = 'reboot\n'
        elseif (value == '1') then
            cmd = 'wifi\n'
        elseif (value == '2') then
            cmd = 'wifi down\n'
        else
            cmd = 'wifi up\n'
        end
    end

    ccff.execute(cmd)
end

--[[
Return:
    1. Maybe nil, and each item maybe nil;
    2. Maybe only basic data;
    3. Maybe with peers' data.
Tasks:
    1. Init ABB;
    2. Gather data;
    3. Gather peers' data if needed.
]]--
function gws_abb.update_safe_rt()
    --print(sfmt('%80s', '### {ABB} VERIFIED SINCE 2017.08.14 ### '))
    DBG(sfmt('hal gws_abb------> (FIXME) param()'))

    -- init dev/api/iw
    gws_abb.init()
    DBG(sfmt('hal gws_abb------+ (FIXME) abb initialized'))

    DBG(sfmt('hal gws_abb------+ (FIXME) start gather data'))
    local abb = {}
    local dev = gws_abb.conf.dev
    local api = gws_abb.conf.api
    local iw = gws_abb.cache.iw

    local format_rf = gws_abb.format.rf_val
    local format_mode = gws_abb.format.mode

    abb.bssid   = suc(iw.bssid(dev) or '----')
    abb.wmac    = suc(gws_abb.cache.wmac or '----')
    abb.chanbw  = gws_abb.conf.chanbw
    abb.mode    = format_mode(iw.mode(dev) or '----')
    if (abb.mode == 'CAR' or abb.mode == 'EAR') then
        abb.ssid = iw.ssid(dev) or '---'
    elseif (abb.mode == 'Mesh') then
        abb.ssid = gws_abb.mesh_id()
    else
        abb.ssid = '----'
    end
    DBG(sfmt('hal gws_abb--------# mode=%s,bssid=%s,ssid=%s,wmac=%s,chanbw=%s,mode=%s',
        abb.mode,abb.bssid, abb.ssid, abb.wmac, abb.chanbw, abb.mode))

    local noise = format_rf(iw.noise(dev))
    -- GWS4K noise may equals 0
    if (noise == 0) then
        noise = -101
    end
    local signal = format_rf(iw.signal(dev))
    if (signal < noise) then
        signal = noise
    end
    abb.noise = noise
    abb.signal = signal
    DBG(sfmt('hal gws_abb--------# signal=%s,noise=%s',
        abb.signal, abb.noise))

    DBG(sfmt('hal gws_abb------+ (FIXME) start gather peers\' data'))
    local peers = gws_abb.peers(abb.bssid, abb.noise) or {}
    local peer_qty = #peers
    abb.peers = peers
    abb.peer_qty = peer_qty
    DBG(sfmt('hal gws_abb--------# (FIXME) total %s peers', abb.peer_qty))

    abb.ts = os.time()

    return abb
end

function gws_abb.demo_peer(idx)
    local peer = {}
    peer.bssid = 'AA:BB:CC:DD:EE:F' .. idx
    peer.wmac = 'FF:EE:DD:CC:BB:A' .. idx
    peer.ip = '----'
    peer.signal = -85 + idx
    peer.noise = -101
    peer.inactive = 555 * idx
    peer.rx_mcs = 1 + idx
    peer.rx_br = 1.1 + idx
    peer.rx_short_gi = idx
    peer.tx_mcs = 0 + idx
    peer.tx_br = 2.2 + idx
    peer.tx_short_gi = 1 - idx
    return peer
end

-- get all peers in table
function gws_abb.peers(bssid, noise)
    local peers = {}

    local dev = gws_abb.conf.dev
    local api = gws_abb.conf.api
    local iw = gws_abb.cache.iw

    local ai, ae
    local al = iw.assoclist(dev)
    if al and next(al) then
        for ai, ae in pairs(al) do
            local peer = {}
            local signal = gws_abb.format.rf_val(ae.signal)
            local inactive = n(ae.inactive) or 65535
            if (signal ~= 0 and signal > noise and inactive < gws_abb.bar.peer_inactive) then
                peer.bssid = bssid
                peer.wmac = s(ai) or '----'

                peer.signal = signal or noise
                peer.noise = noise

                peer.inactive = inactive

                --print('abb.peers raw> rx_mcs|tx_mcs = ', ae.rx_mcs, ae.tx_mcs)
                peer.rx_mcs = n(ae.rx_mcs) or 0
                peer.rx_br = gws_abb.format.bitrate(ae.rx_rate) or 0
                peer.rx_short_gi = n(ae.rx_short_gi) or 0
                peer.tx_mcs = n(ae.tx_mcs) or 0
                peer.tx_br = gws_abb.format.bitrate(ae.tx_rate) or 0
                peer.tx_short_gi = n(ae.tx_short_gi) or 0

                tbl_push(peers, peer)
            end
        end
    end

    -- DEBUG USE ONLY
    --tbl_push(peers, gws_abb.demo_peer(1))
    --tbl_push(peers, gws_abb.demo_peer(2))

    return peers
end


-- format string/number
gws_abb.format = {}

--[[
Modes:
    1. CAR: 'Master';
    2. EAR: 'Client';
    3. Mesh: 'Mesh Point'.
]]--
function gws_abb.format.mode(m)
	if (m == 'Master') then
		return 'CAR'
	elseif (m == 'Client') then
		return 'EAR'
	elseif (m == 'Mesh Point') then
		return 'Mesh'
	else
		return m
	end
end

function gws_abb.format.bitrate(v)
    result = 0
    if (v) then
        result = sfmt("%.1f", v / 1000 / 20 * gws_abb.conf.chanbw)
    end
    return result
end
--[[
Tasks:
    1. Compare with -110, if lt, set to -110;
    2. Default return -110.
]]--
function gws_abb.format.rf_val(v)
    local r = gws_abb.bar.rf_val_min
    if (v and v > r) then
        r = v
    end
    return r
end

return gws_abb
