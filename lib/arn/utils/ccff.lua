-- cmd/conf/file/filter
-- by Qige <qigezhao@gmail.com>
-- 2017.06.30/2017.08.11
-- 2017.09.06 ccff.file.exists

local uci = require 'uci'

local ccff = {}

function ccff.execute(cmd)
	if (cmd) then
		local pipe = io.popen(cmd)
		local prompt = pipe:read("*all")
		io.close(pipe)
		return prompt
	end
	return nil
end

ccff.conf = {}
function ccff.conf.get(conf, sec, opt)
  local result
	if (uci) then
		if (conf and sec and opt) then
			local uc = uci.cursor()
			result = uc:get(conf, sec, opt)
		end
	end
	return result
end

function ccff.conf.set(conf, sec, opt, val)
	if (uci) then
		if (conf and sec and opt and val) then
			local uc = uci.cursor()
			uc:set(conf, sec, opt, val)
			uc:commit(conf)
		end
	end
end

ccff.file = {}
function ccff.file.read(path)
	local content
	if (path) then
        local fd = io.open(path, "r+")
        if (fd) then
            content = fd:read("*all")
            fd:close()
        end
	end
	return content
end

function ccff.file.write(path, data)
	if (path and data) then
		local fd = io.open(path, "w+")
        if (fd) then
            fd:write(data)
            fd:close()
        else
            print('error> write file', path, 'failed')
        end
	end
end

function ccff.file.exists(path)
    local result = ccff.file.read(path)
    if (result) then
        return true
    end
    return false
end

function ccff.file.cp(src, des)
	local content = ccff.read(src)
	ccff.write(des, content)
end

function ccff.triml(str, cnt)
    if (str) then
        return string.sub(str, 1 + cnt, -1)
    end
    return nil
end

function ccff.trimr(str, cnt)
    if (str) then
        return string.sub(str, 1, -1 - (cnt or 0))
    end
    return nil
end

-- string split()
-- @return table/nil
-- @from http://zhaiku.blog.51cto.com/2489043/1163077
function ccff.split(str, delim)
    local rt= {}
    if (delim == nil) then delim = ',' end
    if (str ~= nil) then
        string.gsub(str, '[^'..delim..']+', function(w) table.insert(rt, w) end)
    end
    return rt
end

ccff.val = {}
function ccff.val.is_array(s)
    if (s and type(s) == 'table') then
        return true
    end
    return false
end

function ccff.has(str, key)
    local p1, p2 = string.find(str, key)
    if (p1 ~= nil) then
        return true
    end
    return false
end

function ccff.val.s(str)
    if (str) then
        return tostring(str)
    end
    return '?'
end

function ccff.val.n(str)
    if (str) then
        return tonumber(str)
    end
    return 0
end

function ccff.val.limit(v, vmin, vmax)
    local val = tonumber(v) or 0
    local val_min = tonumber(vmin) or 0
    local val_max = tonumber(vmax) or 0
    if (val < val_min) then
        val = val_min
    end
    if (val > val_max) then
        val = val_max
    end
    return val
end

function ccff.val.in_list(list, delim, s)
    local result = false
    local ranges = ccff.split(list, delim)
    for idx, val in pairs(ranges) do
        if (val == s) then 
            result = true
            break
        end
    end
    return result
end

return ccff
