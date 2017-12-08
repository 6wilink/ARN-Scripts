-- by Qige <qigezhao@gmail.com>
-- 2017.09.04 v2.1

local sfmt = string.format

local JSON = {}

function JSON.Encode(data)
    local json
	local data_type = type(data)
	if (data_type == 'table') then
		json = JSON.encode_all(data)
	elseif (data_type == 'string') then
		json = sfmt('["%s"]', data)
    elseif (data_type == 'number') then
		json = sfmt('[%d]', data)
	end
    return json
end

function JSON.encode_all(data)
    local json_str = ''
    if (data) then
        local str_pair
        local data_type = type(data)
        if (data_type == 'table') then
            str_pair = '{'
			local str_re = ''
            local idx, val
            for idx,val in pairs(data) do
				-- check idx is nubmer?
				-- check val is table?
				if (idx and type(idx) == 'number') then
					str_re = sfmt('"%s":[%s]', idx, JSON.encode_all(val))
				else
					str_re = sfmt('"%s":%s', idx, JSON.encode_all(val))
				end
				if (str_pair ~= '{') then
					str_pair = str_pair .. ','
				end
                str_pair = str_pair .. str_re
            end
            str_pair = str_pair .. '}'
        elseif (data_type == 'number') then
            str_pair = data
        elseif (data_type == 'string') then
            if (data == 'nil' or data == 'null') then
                str_pair = 'null'
            else
                str_pair = '"' .. data .. '"'
            end
        else
            str_pair = 'null' -- data_type == nil
        end

        json_str = str_pair
        str_pair = ''
    end
    return json_str
end

return JSON