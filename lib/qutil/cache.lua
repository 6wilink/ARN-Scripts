-- by Qige <qigezhao@gmail.com>
-- 2017.08.16 LOAD_VALID_CACHE|LOAD|SAVE|CLEAN

-- DEBUG USE ONLY
--local DBG = print
local function DBG(msg) end

local Serializer    = require 'qutil.serialize'
local Ccff          = require 'qutil.ccff'
local file_read     = Ccff.file.read
local file_write    = Ccff.file.write
local vint          = Ccff.val.n
local sfmt          = string.format


local Cache = {}

function Cache.LOAD_VALID(cache_file, cache_timeout)
    DBG(sfmt("Cache> LOAD_VALID_CACHE(%s, %s)", cache_file or '-', cache_timeout or '-'))
    local result
        
    -- Cache invalid or cache time out
    local now_ts = os.time() -- in seconds
    local cache_ts
    local cache = Cache.LOAD(cache_file)
    if (cache) then
        cache_ts = vint(cache.ts)
    else
        cache_ts = 0
    end  
    local cache_elapsed = now_ts - cache_ts
    DBG(sfmt("----+ cache ts (now=%d, eclapsed=%d, cache=%d)", now_ts, cache_elapsed, cache_ts))
    if (cache_ts > 0 and cache_elapsed < (cache_timeout or 1)) then
        DBG(sfmt("----+ cache valid used for %ds, max %ds", cache_elapsed, cache_timeout))
        result = cache
    end
    return result
end

-- Load & unserialize cache from file
function Cache.LOAD(cache_file)
    DBG(sfmt("Cache> LOAD(%s)", cache_file or '-'))
    local cache_raw
    local cache_content = file_read(cache_file)
    if (cache_content) then
        cache_raw = Serializer.unserialize(cache_content)
    end
    if (cache_raw and not next(cache_raw)) then
        cache_raw = {}
        cache_raw.ts = os.time()
    end
    return cache_raw
end

-- Save cache with ts to file
-- @condition pass in 'table'
function Cache.SAVE(cache_file, cache, ts)
    DBG(sfmt("Cache> SAVE(%s, %s, %s)", cache_file or '-', 'cache{table}', ts or '-'))
    local cache_raw
    if (cache and type(cache) == 'table') then
        DBG("----+ save cache to file")
        cache.ts = ts or os.time()
        cache_raw = Serializer.serialize(cache)
        file_write(cache_file, cache_raw)
    else
        DBG("----+ NO or bad data, do nothing")
    end
end

-- set cache TIMEOUT ts
function Cache.EXPIRES_UNTIL(cache_file, sec)
    DBG(sfmt("Cache> EXPIRES_UNTIL(%s, %s)", cache_file or '-', sec or '-'))
    local now_ts = os.time()
    local until_ts = now_ts - sec
    DBG(sfmt("----+ cache will be expired in %ds (target=%d,now=%d)", sec, until_ts, now_ts))
    
    local cache = Cache.LOAD(cache_file)
    if (cache and next(cache)) then
        Cache.SAVE(cache_file, cache, until_ts)
    end
end

function Cache.CLEAN(cache_file)
    DBG(sfmt("Cache> CLEAN(%s, %s)", cache_file or '-'))
    file_write(cache_file, '')
    dev_mngr.cache.region = nil
    dev_mngr.cache.valid_until = nil
end

return Cache
