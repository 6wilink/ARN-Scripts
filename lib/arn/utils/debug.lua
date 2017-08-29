-- by Qige <qigezhao@gmail.com>
-- 2017.08.14

local dbg = {}

function dbg.dump_dec(str)
    if (str) then
        local index
        for index = 1, string.len(str) do
            io.write(string.format("B%d-%d ", index, string.byte(str, index)))
        end
        print()
    end
end

function dbg.dump_hex(str)
    if (str) then
        local index
        for index = 1, string.len(str) do
            io.write(string.format("B%d-%02X ", index, string.byte(str, index)))
        end
        print()
    end
end

return dbg