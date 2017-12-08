-- by Qige <qigezhao@gmail.com>
-- 2017.08.22

-- DEBUG USE ONLY
--local DBG = print
local function DBG(msg) end

local Cache = require 'arn.utils.cache'
local Ccff = require 'arn.utils.ccff'
local exec = Ccff.execute
local sfmt = string.format
local slen = string.len
local ssub = string.sub
local sgsub = string.gsub

local rarp = {}
rarp.conf = {}
rarp.conf.fcache_rarp = '/tmp/.arn-cache.dev-'
rarp.conf.rarp_cmd_fmt = "rarp-client %s 211 | awk '{print $2}' | tr -d '\n'"
rarp.conf.rarp_timeout = 3600

--[[
Tasks:
    1. Read IP from cache;
    2. If cache missed, use RARP, & save to cache.
]]--
function rarp.FETCH_IP(mac, flagIPOnly)
    DBG(sfmt('rarp> FETCH_IP(%s)', mac))
    if (mac and slen(mac) >= 17) then
        local ip_raw = rarp.load_ip_from_cache(mac)
        if (ip_raw and ip_raw ~= '') then
            DBG(sfmt('rarp> ----+ cache convert: %s=%s)', mac, ip_raw))
            if (flagIPOnly) then
                return ip_raw
            end
            return ip_raw .. ' ' .. ssub(mac, 10, -1)
        end
        ip_raw = rarp.rarp_request(mac)
        if (ip_raw and ip_raw ~= '') then
            DBG(sfmt('rarp> ----+ rarp convert: %s=%s', mac, ip_raw or '-'))
            rarp.save_ip_to_cache(mac, ip_raw)
            if (flagIPOnly) then
                return ip_raw
            end
            return ip_raw .. '+' .. ssub(mac, 10, -1)
        end
        return mac
    end
    return '(unknown)' .. ' ' .. ssub(mac, 1, 8)
end

-- Convert MAC to IP via cmd
-- +rarp-client +rarp-server
function rarp.rarp_request(mac)
    local rarp_cmd_fmt = rarp.conf.rarp_cmd_fmt
    if (mac) then
        local rarp = sfmt(rarp_cmd_fmt, mac)
        return exec(rarp)
    end
    return nil
end

function rarp.cache_key(mac)
    return sgsub(mac or '', ':', '')
end

function rarp.load_ip_from_cache(mac)
    local key = rarp.cache_key(mac)
    local cache_file = rarp.conf.fcache_rarp .. key
    local cache = Cache.LOAD_VALID(cache_file, rarp.conf.rarp_timeout)
    if (cache and type(cache) == 'table') then
        local ip = cache[key] or ''
        return ip
    end
    return nil
end

function rarp.save_ip_to_cache(mac, ip)
    local key = rarp.cache_key(mac)
    local cache_file = rarp.conf.fcache_rarp .. key
    local cache = Cache.LOAD_VALID(cache_file, rarp.conf.rarp_timeout)
    if (not cache or type(cache) ~= 'table') then
        cache = {}
    end
    cache[key] = ip
    Cache.SAVE(cache_file, cache)
end

return rarp
