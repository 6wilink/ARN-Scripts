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
        local str_item, str_pair_begin, str_pair_end
        local data_type = type(data)
        if (data_type == 'table') then
            str_pair_begin = '{'
            str_pair_end = '}'
            str_item = ''
            local str_item_value = ''
            local idx, val
            for idx,val in pairs(data) do
                -- check idx is nubmer?
                -- check val is table?
                if (idx) then
                    if (type(idx) == 'number') then
                        str_pair_begin = '['
                        str_pair_end = ']'
                        if (str_item == '') then
                            str_item = str_item .. str_pair_begin
                        end
                        str_item_value = string.format('%s', JSON.encode_all(val))
                    else
                        str_pair_begin = '{'
                        str_pair_end = '}'
                        if (str_item == '') then
                            str_item = str_item .. str_pair_begin
                        end
                        str_item_value = string.format('"%s":%s', idx, JSON.encode_all(val))
                    end
                    if (str_item ~= '{' and str_item ~= '[') then
                        str_item = str_item .. ','
                    end
                    str_item = str_item .. str_item_value
                end
            end
            -- FIXME: empty table
            if ((not str_item) or str_item == '') then
                str_item = 'null'
            else
                str_item = str_item .. str_pair_end
            end
        elseif (data_type == 'number') then
            str_item = data
        elseif (data_type == 'string') then
            if (data == 'nil' or data == 'null') then
                str_item = 'null'
            else
                str_item = '"' .. data .. '"'
            end
        else
            str_item = 'null' -- data_type == nil
        end

        json_str = str_item
        str_item = ''
    else
        json_str = 'null'
    end

    return json_str
end

return JSON